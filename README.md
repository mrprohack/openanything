# openanything

Open any file, folder or URL from the Windows command line with the right app, and choose which app opens what.

```
open photo.png        → image viewer
open page.html        → browser
open report.pdf       → PDF reader
open .                → Explorer
open https://x.com    → browser
```

Without your own settings, `open` uses the Windows default app for each file type. You can override that for any extension with `--set`.

## Install

Requirements: Windows 10/11, with nothing else to install. It runs on Windows PowerShell 5.1, which comes with Windows.

```powershell
git clone https://github.com/mrprohack/openanything.git
cd openanything
# add this folder to your user PATH, then open a new terminal
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path","User") + ";$PWD", "User")
```

Check that it works:

```
open --help
```

## Usage

```
open <target> [<target> ...]       open one or more files, folders or URLs
open --with <app> <target>         open with <app> this one time
open --set <ext> <app>             always open <ext> with <app>
open --unset <ext>                 remove an override (back to the Windows default)
open --list                        show your overrides
```

### Examples

```powershell
open notes.txt                          # default text editor
open a.png b.png c.pdf                  # several files at once
open --with notepad config.json         # one-off: use Notepad

open --set pdf "C:\Tools\SumatraPDF.exe"   # full path to an app
open --set html firefox                    # short names work: firefox, chrome, msedge, notepad, ...
open --set .md code                        # leading dot is optional
open --list
open --unset pdf
```

### Special keys

Besides file extensions, `--set` accepts two special keys:

| Key   | Applies to                                       | Example                    |
|-------|--------------------------------------------------|----------------------------|
| `url` | anything with `://`, plus `mailto:` and `www.`   | `open --set url chrome`    |
| `dir` | folders                                          | `open --set dir totalcmd`  |

## How it picks the app

For each target, the first rule that matches wins:

1. `--with <app>` on the command line
2. Your override for that extension (or `url` / `dir`) in the config file
3. The Windows default app for the file type, as set in *Settings → Apps → Default apps*

The app is started through Windows `ShellExecute`. That means `<app>` can be a full path, a program on your `PATH`, or a name registered under Windows *App Paths* (which is why `firefox` and `chrome` work without a full path). `open` returns right away and does not wait for the app to close.

## Configuration

Overrides are stored as JSON in `%APPDATA%\open\config.json`:

```json
{
  ".pdf": "C:\\Tools\\SumatraPDF.exe",
  ".html": "firefox",
  "url": "chrome"
}
```

You can edit this file by hand or with `--set` / `--unset`.

## Exit codes

| Code | Meaning                                                    |
|------|------------------------------------------------------------|
| `0`  | every target opened                                        |
| `1`  | at least one target was not found or could not be opened  |

Error messages go to stderr, for example `open: not found: missing.png`.

## Limitations

- The app is chosen by extension only, not by file content. Files with no extension use the Windows default.
- An override is a single app with no extra arguments (`code -n` is not supported).
- In PowerShell, `open` runs `open.cmd`. If you have defined an `open` alias or function yourself, that one wins.
- Each run starts PowerShell, which adds roughly a quarter of a second of startup time.

## How it runs

`open.cmd` calls `powershell -NoProfile -ExecutionPolicy Bypass -File openanything.ps1`. `-ExecutionPolicy Bypass` applies only to that one call, so you do **not** need to change your system's execution policy. The script is deliberately not named `open.ps1`, so that PowerShell always runs `open.cmd` and never tries to run the script directly (which the default execution policy would block).

## Development

```
powershell -ExecutionPolicy Bypass -File test_open.ps1    # prints "ok" if the app-selection logic is correct
```

Files:

- `openanything.ps1` — the whole tool
- `open.cmd` — shim so `open` works in cmd and PowerShell
- `test_open.ps1` — self-check for the app-selection logic

## License

[MIT](LICENSE)
