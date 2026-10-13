// openanything: open files, folders and URLs with the right app. Your overrides first, Windows default otherwise.
// Build with build.cmd (in-box .NET Framework csc, C# 5).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using Microsoft.Win32;

public static class OpenAnything {
    class Fail : Exception {
        public readonly int Code;
        public Fail(int code, string message) : base(message) { Code = code; }
    }

    const string Version = "open 2.0.0";
    static readonly string AppData = Environment.GetEnvironmentVariable("APPDATA");
    static readonly string ConfigPath = Path.Combine(string.IsNullOrEmpty(AppData)
        ? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData) : AppData, "open", "config.json");

    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
    static extern int AssocQueryString(int flags, int str, string assoc, string extra, StringBuilder outBuf, ref uint size);

    static string Usage() {
        return @"usage: open <target>...              open files, folders or URLs with their app
       open --with <app> <target>... use <app> this one time
       open --which <target>...      show which app would open each target
       open --set <ext> <app>        always open <ext> with <app>
       open --unset <ext>            go back to the Windows default for <ext>
       open --list                   show your overrides
       open --version
<ext>: an extension like pdf or .pdf, or the special key url (links) or dir (folders)
<app>: a full path, a program on PATH, or an App Paths name like firefox
Wildcards like *.png are expanded. Put -- before targets that start with -.
config: " + ConfigPath + @"
exit codes: 0 ok, 1 not found / can't open / config problem, 2 bad usage";
    }

    [STAThread]
    public static int Main(string[] args) {
        try {
            return Run(args);
        } catch (Fail f) {
            Console.Error.WriteLine("open: " + f.Message);
            if (f.Code == 2) Console.Error.WriteLine("try open --help");
            return f.Code;
        } catch (Exception e) { Console.Error.WriteLine("open: " + e.Message); return 1; }
    }

    static int Run(string[] args) {
        string with = null;
        bool list = false, which = false, options = true;
        var ops = new List<string[]>();   // {key, app}; app == null means unset
        var targets = new List<string>();
        for (int i = 0; i < args.Length; i++) {
            string a = args[i];
            if (!options || !(a.StartsWith("-") || a == "/?")) { targets.Add(a); continue; }
            switch (a) {
                case "--": options = false; break;
                case "--help": case "-h": case "-?": case "/?": Console.WriteLine(Usage()); return 0;
                case "--version": Console.WriteLine(Version); return 0;
                case "--list": list = true; break;
                case "--which": which = true; break;
                case "--with": with = Value(args, ref i, "--with needs <app>", true); break;
                case "--set":
                    string key = Key(Value(args, ref i, "--set needs <ext> and <app>", false));
                    ops.Add(new[] { key, Value(args, ref i, "--set needs <ext> and <app>", true) });
                    break;
                case "--unset": ops.Add(new[] { Key(Value(args, ref i, "--unset needs <ext>", false)), null }); break;
                default: throw new Fail(2, "unknown option " + a);
            }
        }
        if (targets.Count == 0 && (which || with != null)) throw new Fail(2, (which ? "--which" : "--with") + " needs a target");
        if (targets.Count == 0 && ops.Count == 0 && !list) { Console.WriteLine(Usage()); return 0; }

        var cfg = (with == null || ops.Count > 0 || list) ? Load() : new Dictionary<string, string>();
        int rc = 0;
        foreach (string[] op in ops) {
            if (op[1] != null) {
                cfg[op[0]] = op[1];
                Save(cfg);
                Console.WriteLine(op[0] + " -> " + op[1]);
                if (!AppExists(op[1])) Console.Error.WriteLine("open: warning: can't find '" + op[1] + "' - check the name or use a full path");
            } else if (cfg.Remove(op[0])) { Save(cfg); Console.WriteLine(op[0] + " -> (Windows default)"); }
            else { Console.Error.WriteLine("open: no override for " + op[0]); rc = 1; }
        }
        if (list) {
            if (cfg.Count == 0) Console.WriteLine("no overrides (" + ConfigPath + ")");
            var keys = new List<string>(cfg.Keys);
            keys.Sort(StringComparer.Ordinal);
            foreach (string k in keys) Console.WriteLine(string.Format("{0,-8} {1}", k, cfg[k]));
        }

        foreach (string arg in targets) {
            string t = arg.TrimEnd('"');   // cmd/PowerShell turn "C:\some dir\" into C:\some dir"
            List<string> found = Expand(t);
            if (found.Count == 0) { Console.Error.WriteLine("open: not found: '" + t + "'"); rc = 1; }
            foreach (string r in found) {
                string why;
                string app = Pick(r, cfg, with, out why);
                if (which) Console.WriteLine(r + " -> " + (app != null ? app + " (" + why + ")" : "Windows default" + Friendly(r)));
                else if (!Launch(r, app)) rc = 1;
            }
        }
        return rc;
    }

    // The value after args[i]; must exist and not look like an option.
    static string Value(string[] args, ref int i, string message, bool isApp) {
        if (i + 1 >= args.Length || args[i + 1].StartsWith("-") || args[i + 1] == "/?" || (isApp && args[i + 1].Trim() == ""))
            throw new Fail(2, message);
        return args[++i];
    }

    static string Norm(string k) {
        k = k.ToLowerInvariant();
        return k == "url" || k == "dir" || k.StartsWith(".") ? k : "." + k;
    }

    static string Key(string k) {
        string n = Norm(k);
        if (!Regex.IsMatch(n, @"^(url|dir|(\.[a-z0-9_+-]+)+)$")) throw new Fail(2, "invalid extension '" + k + "'");
        return n;
    }

    // Existing path first (even www.site.com), then URL, then wildcard. Empty list = not found.
    static List<string> Expand(string t) {
        var found = new List<string>();
        if (t.Length == 0) return found;
        if (File.Exists(t) || Directory.Exists(t)) found.Add(Path.GetFullPath(t));
        else if (Regex.IsMatch(t, "^[A-Za-z][A-Za-z0-9+.-]+:")) found.Add(t);   // 2+ chars, so C: is not a scheme
        else if (t.StartsWith("www.", StringComparison.OrdinalIgnoreCase)) found.Add("https://" + t);
        else if (t.IndexOfAny(new[] { '*', '?' }) >= 0) {
            try {
                string dir = Path.GetDirectoryName(t);
                string[] hits = Directory.GetFileSystemEntries(string.IsNullOrEmpty(dir) ? "." : dir, Path.GetFileName(t));
                Array.Sort(hits, StringComparer.OrdinalIgnoreCase);
                foreach (string h in hits) found.Add(Path.GetFullPath(h));
            } catch (Exception) { }   // bad pattern or missing folder: not found
        }
        return found;
    }

    // App for a resolved target, or null for the Windows default. Longest extension wins (.tar.gz before .gz).
    static string Pick(string r, Dictionary<string, string> cfg, string with, out string why) {
        why = "--with";
        if (with != null) return with;
        string app, key = Directory.Exists(r) ? "dir" : File.Exists(r) ? null : "url";
        if (key == null) {
            string name = Path.GetFileName(r).ToLowerInvariant();
            for (int i = name.IndexOf('.'); i >= 0; i = name.IndexOf('.', i + 1))
                if (cfg.TryGetValue(name.Substring(i), out app)) { why = "override " + name.Substring(i); return app; }
            return null;
        }
        why = "override " + key;
        return cfg.TryGetValue(key, out app) ? app : null;
    }

    static string Friendly(string r) {
        if (Directory.Exists(r)) return ": Explorer";
        string assoc = File.Exists(r) ? Path.GetExtension(r) : r.Substring(0, r.IndexOf(':'));
        if (assoc == "") return "";
        var sb = new StringBuilder(512);
        uint size = 512;
        // ASSOCF_INIT_IGNOREUNKNOWN = 0x400, ASSOCSTR_FRIENDLYAPPNAME = 4
        return AssocQueryString(0x400, 4, assoc, null, sb, ref size) == 0 ? ": " + sb : "";
    }

    static bool Launch(string r, string app) {
        // ErrorDialog on the default path matches double-click: unassociated files get the "How do you want to open" picker.
        var psi = new ProcessStartInfo(app ?? r) { UseShellExecute = true, ErrorDialog = app == null };
        if (app != null) psi.Arguments = Quote(r);
        try { Process.Start(psi); return true; }
        catch (Exception e) {
            Console.Error.WriteLine("open: can't open " + r + " with " + (app ?? "default app") + ": " + e.Message);
            return false;
        }
    }

    // Quote one argument so CommandLineToArgvW gives it back unchanged (C:\ stays C:\, " can't add args).
    public static string Quote(string s) {
        var sb = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in s) {
            if (c == '\\') { slashes++; continue; }
            sb.Append('\\', c == '"' ? slashes * 2 + 1 : slashes).Append(c);
            slashes = 0;
        }
        return sb.Append('\\', slashes * 2).Append('"').ToString();
    }

    // Same places ShellExecute looks: full path, PATH + PATHEXT, App Paths.
    static bool AppExists(string app) {
        if (app.IndexOfAny(new[] { '\\', '/', ':' }) >= 0) return File.Exists(app);
        var names = new List<string> { app };
        foreach (string ext in (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE").Split(';')) names.Add(app + ext);
        foreach (string dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
            foreach (string n in names)
                if (dir.Trim('"') != "" && File.Exists(dir.Trim('"').TrimEnd('\\') + "\\" + n)) return true;
        try {
            foreach (RegistryKey root in new[] { Registry.CurrentUser, Registry.LocalMachine })
                foreach (string n in new[] { app, app + ".exe" })
                    using (RegistryKey k = root.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\" + n))
                        if (k != null) return true;
        } catch (Exception) { }
        return false;
    }

    static Fail Invalid(string reason) { return new Fail(1, "invalid config " + ConfigPath + ": " + reason); }

    // Never writes: a broken config is reported, not replaced.
    static Dictionary<string, string> Load() {
        var cfg = new Dictionary<string, string>();
        if (!File.Exists(ConfigPath)) return cfg;
        string text;
        try { text = File.ReadAllText(ConfigPath); }
        catch (Exception e) { throw new Fail(1, "can't read config " + ConfigPath + ": " + e.Message); }
        if (text.Trim() == "") return cfg;
        object root;
        try { root = new JavaScriptSerializer().DeserializeObject(text); }
        catch (Exception e) { throw Invalid(e.Message); }
        var obj = root as Dictionary<string, object>;
        if (obj == null) throw Invalid("not a JSON object");
        foreach (var kv in obj) {
            var app = kv.Value as string;
            if (app == null) throw Invalid("value of '" + kv.Key + "' is not a string");
            cfg[Norm(kv.Key)] = app;
        }
        return cfg;
    }

    // Write a temp file next to the config, then swap it in, so a failed save never leaves a half-written config.
    static void Save(Dictionary<string, string> cfg) {
        var js = new JavaScriptSerializer();
        var keys = new List<string>(cfg.Keys);
        keys.Sort(StringComparer.Ordinal);
        var lines = keys.ConvertAll(k => "  " + js.Serialize(k) + ": " + js.Serialize(cfg[k]));
        string json = lines.Count == 0 ? "{}\r\n" : "{\r\n" + string.Join(",\r\n", lines) + "\r\n}\r\n";
        string tmp = ConfigPath + ".tmp";
        try {
            Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath));
            File.WriteAllText(tmp, json);   // UTF-8, no BOM
            if (File.Exists(ConfigPath)) File.Replace(tmp, ConfigPath, null);
            else File.Move(tmp, ConfigPath);
        } catch (Exception e) {
            try { File.Delete(tmp); } catch (Exception) { }
            throw new Fail(1, "can't save config " + ConfigPath + ": " + e.Message);
        }
    }
}
