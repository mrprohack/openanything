// open-setup.exe: double-click installer for open.exe (embedded). Installs per user, no admin rights.
// Installs to %LOCALAPPDATA%\Programs\open, adds it to the user PATH and to Settings > Installed apps.
// open-setup.exe [/uninstall] [/S]   (/S = silent, no dialogs)
// Build with build.cmd (in-box .NET Framework csc, C# 5).
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

public static class Setup {
    const string Title = "open setup";
    const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\openanything";
    static readonly string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "open");
    static bool silent;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);

    [STAThread]
    static int Main(string[] args) {
        silent = args.Any(a => a.Equals("/S", StringComparison.OrdinalIgnoreCase));
        bool uninstall = args.Any(a => a.Equals("/uninstall", StringComparison.OrdinalIgnoreCase));
        try {
            if (uninstall) {
                if (!Ask("Uninstall open from " + Dir + "?\n\nYour settings in %APPDATA%\\open are kept.")) return 1;
                Uninstall();
                Say("open was uninstalled.");
            } else {
                if (!Ask("Install open to " + Dir + " and add it to your PATH?")) return 1;
                string version = Install();
                Say(version + " is installed.\n\nOpen a new terminal window and try:\n    open --version\n    open .");
            }
            return 0;
        } catch (Exception e) {
            if (!silent) MessageBox.Show(e.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            else Console.Error.WriteLine(e.Message);
            return 1;
        }
    }

    static string Install() {
        Directory.CreateDirectory(Dir);
        string exe = Path.Combine(Dir, "open.exe");
        try {
            using (Stream src = Assembly.GetExecutingAssembly().GetManifestResourceStream("open.exe"))
            using (FileStream dst = File.Create(exe)) src.CopyTo(dst);
        } catch (IOException) {
            throw new Exception("Could not write " + exe + ". Is open.exe running? Close it and try again.");
        }
        string self = Assembly.GetExecutingAssembly().Location;
        string uninstaller = Path.Combine(Dir, "uninstall.exe");
        if (!string.Equals(Path.GetFullPath(self), uninstaller, StringComparison.OrdinalIgnoreCase))
            File.Copy(self, uninstaller, true);

        SetPath(true);

        string version = RunVersion(exe);
        using (RegistryKey k = Registry.CurrentUser.CreateSubKey(UninstallKey)) {
            k.SetValue("DisplayName", "open (openanything)");
            k.SetValue("DisplayVersion", version.Replace("open ", ""));
            k.SetValue("Publisher", "mrprohack");
            k.SetValue("URLInfoAbout", "https://github.com/mrprohack/openanything");
            k.SetValue("InstallLocation", Dir);
            k.SetValue("DisplayIcon", uninstaller);
            k.SetValue("UninstallString", "\"" + uninstaller + "\" /uninstall");
            k.SetValue("QuietUninstallString", "\"" + uninstaller + "\" /uninstall /S");
            k.SetValue("NoModify", 1, RegistryValueKind.DWord);
            k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        }
        return version;
    }

    static void Uninstall() {
        SetPath(false);
        Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false);
        string exe = Path.Combine(Dir, "open.exe");
        if (File.Exists(exe)) File.Delete(exe);
        // uninstall.exe can't delete itself while running; a hidden cmd removes the folder once we've exited
        Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 3 127.0.0.1 >nul & rd /s /q \"" + Dir + "\"") {
            CreateNoWindow = true, UseShellExecute = false
        });
    }

    // Adds or removes Dir in the user PATH, keeping %VARIABLES% unexpanded, then tells Windows it changed.
    static void SetPath(bool add) {
        using (RegistryKey k = Registry.CurrentUser.CreateSubKey("Environment")) {
            string path = (string)k.GetValue("Path", "", RegistryValueOptions.DoNotExpandEnvironmentNames);
            var parts = path.Split(';').Where(p => p != "" && !string.Equals(p.TrimEnd('\\'), Dir, StringComparison.OrdinalIgnoreCase)).ToList();
            if (add) parts.Add(Dir);
            k.SetValue("Path", string.Join(";", parts), RegistryValueKind.ExpandString);
        }
        UIntPtr r;
        SendMessageTimeout((IntPtr)0xffff, 0x001A, UIntPtr.Zero, "Environment", 2, 5000, out r); // HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG
    }

    // Runs the installed exe once: checks it works and gets its version.
    static string RunVersion(string exe) {
        var psi = new ProcessStartInfo(exe, "--version") { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true };
        using (Process p = Process.Start(psi)) {
            string v = p.StandardOutput.ReadToEnd().Trim();
            p.WaitForExit();
            if (p.ExitCode != 0 || !v.StartsWith("open ")) throw new Exception("The installed open.exe did not run correctly.");
            return v;
        }
    }

    static bool Ask(string q) {
        return silent || MessageBox.Show(q, Title, MessageBoxButtons.OKCancel, MessageBoxIcon.Question) == DialogResult.OK;
    }

    static void Say(string s) {
        if (!silent) MessageBox.Show(s, Title, MessageBoxButtons.OK, MessageBoxIcon.Information);
    }
}
