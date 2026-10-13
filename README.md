# openanything

Open any file, folder or URL from the Windows command line with the right app, and choose which app opens what.

```
open photo.png        → image viewer
open page.html        → browser
open report.pdf       → PDF reader
open .                → Explorer
open https://x.com    → browser
```

Without your own settings, `open` uses the Windows default app, exactly like double-clicking the file. You can override that for any extension with `--set`.

`open` is a single small `open.exe`. It works the same in cmd, PowerShell and Windows Terminal, starts instantly, and needs nothing else installed. Like most command line tools it prints nothing when it succeeds.

## Install

Requirements: Windows 10 or 11.

Run this in PowerShell:

```powershell
irm https://raw.githubusercontent.com/mrprohack/openanything/main/install.ps1 | iex
```

It downloads `open.exe` from the [latest release](https://github.com/mrprohack/openanything/releases/latest) into `%LOCALAPPDATA%\Programs\open` and adds that folder to your user PATH. No admin rights needed, and you can run it again to update. Then open a **new** terminal window and check:

```
open --version
```

If `open` is still not found, sign out of Windows and back in.

**Build it yourself instead.** You need nothing installed: the C# compiler that ships with Windows (.NET Framework 4) is enough. `install.ps1` installs the `open.exe` next to it when there is one.

```
git clone https://github.com/mrprohack/openanything.git
cd openanything
build.cmd
powershell -ExecutionPolicy Bypass -File install.ps1
```

The exe is not code-signed. If you download it by hand and Windows blocks it, run `Unblock-File open.exe`.

### Uninstall

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/mrprohack/openanything/main/install.ps1))) -Uninstall
```

This removes the folder and its PATH entry. Your settings stay in `%APPDATA%\open`; delete them with `Remove-Item -Recurse "$env:APPDATA\open"`.

## Usage

```
open <target>...              open files, folders or URLs with their app
open --with <app> <target>... use <app> this one time
open --which <target>...      show which app would open each target, without opening it
open --set <ext> <app>        always open <ext> with <app>
open --unset <ext>            go back to the Windows default for <ext>
open --list                   show your overrides
open --version
open --help
```

`<ext>` is a file extension like `pdf` or `.pdf` (the dot is optional, case does not matter), or one of the special keys `url` and `dir`. Multi-part extensions like `tar.gz` work too; the longest match wins.

### Examples

```powershell
open notes.txt                             # default text editor
open a.png b.png c.pdf                     # several targets at once
open *.png                                 # wildcards are expanded by open itself
open www.github.com                        # www. is opened as https://www.github.com
open mailto:me@example.com                 # any URL scheme: mailto:, ms-settings:, magnet:, ...
open --with notepad config.json            # one-off: use Notepad this time

open --set pdf "C:\Tools\SumatraPDF.exe"   # full path to an app
open --set html firefox                    # or a short name (see "Finding app names")
open --set .md code
open --list
open --unset pdf

open --which report.pdf https://x.com      # what would open these? Opens nothing.
open -- -notes.txt                         # -- ends options, for names starting with -
```

`--which` prints one line per target:

```
C:\docs\report.pdf -> C:\Tools\SumatraPDF.exe (override .pdf)
https://x.com -> Windows default: Firefox
```

### Special keys

Besides file extensions, `--set` and `--unset` accept two special keys:

| Key   | Applies to                                                                 | Example                   |
|-------|----------------------------------------------------------------------------|---------------------------|
| `url` | every URL: `https://`, `mailto:`, `ms-settings:` and so on, plus `www.`    | `open --set url chrome`   |
| `dir` | folders                                                                    | `open --set dir totalcmd` |

## Finding app names

`<app>` in `--set` and `--with` can be:

- **A full path.** This always works: `"C:\Program Files\Mozilla Firefox\firefox.exe"`.
- **A program on your PATH**, like `notepad` or `code`. Check with `where.exe code`.
- **A name registered under Windows *App Paths***, like `firefox`, `chrome`, `msedge`, `winword` or `excel`. These work even though they are not on your PATH. List them with:

  ```powershell
  Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths' | Select-Object PSChildName
  ```

If `--set` can't find the app in any of these places it still saves the setting, but warns you, so you can catch typos.

## How it picks the app

For each target (file, folder or URL), the first rule that matches wins:

1. `--with <app>` on the command line
2. Your override for that extension, or for `url` / `dir`
3. The Windows default app, as set in *Settings → Apps → Default apps*

If a file type has no default app, Windows asks *"How do you want to open this file?"*, just like a double-click.

A target that exists on disk is always treated as a file or folder, even if it looks like a web address (a file named `www.example.com`). Otherwise it is a URL if it starts with a scheme like `https:` or `mailto:`, or with `www.`. Anything else that isn't found prints `open: not found: '<target>'`.

`open` starts the app and returns right away. It does not wait for the app to close.

## Configuration

Overrides are stored as JSON in `%APPDATA%\open\config.json`:

```json
{
  ".html": "firefox",
  ".pdf": "C:\\Tools\\SumatraPDF.exe",
  "url": "chrome"
}
```

You can edit this file by hand or with `--set` / `--unset`. If the file is not valid JSON, `open` reports `open: invalid config ...` and leaves the file untouched until you fix it.

## Exit codes

| Code | Meaning                                                                       |
|------|-------------------------------------------------------------------------------|
| `0`  | everything worked                                                             |
| `1`  | a target was not found or could not be opened, or the config file has a problem |
| `2`  | bad usage: unknown option, missing value or invalid extension                 |

Errors and warnings go to stderr, for example `open: not found: 'missing.png'`.

## Security

`open` does what a double-click does. Opening an `.exe`, `.bat`, `.cmd`, `.lnk` or similar file **runs** it. Don't pass untrusted input (file names or URLs from someone else) to `open` in scripts.

## Limitations

- The app is chosen by extension only, not by file content.
- An override is a single app with no extra arguments (`code -n` is not supported). The target is passed as one quoted argument.
- A PowerShell 5.1 quirk: a quoted argument ending in a backslash, like `open '.\My Folder\' next`, swallows the argument that follows it. Leave off the trailing backslash: `open '.\My Folder' next`.
- If you have defined your own `open` alias or function in PowerShell, that one wins over `open.exe`.

## Development

```
build.cmd                                                     # compile open.cs into open.exe
powershell -NoProfile -ExecutionPolicy Bypass -File test.ps1  # build, then test; prints "ok"
```

Files:

- `open.cs` — the whole tool (C# 5, compiled by the in-box .NET Framework compiler)
- `build.cmd` — builds `open.exe`
- `test.ps1` — black-box tests. They use a temporary config and never launch an app.
- `install.ps1` — installer: puts `open.exe` in `%LOCALAPPDATA%\Programs\open` and on your PATH (`-Uninstall` reverses it)

## License

[MIT](LICENSE)
