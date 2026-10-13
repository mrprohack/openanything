# Builds open.exe and black-box tests it. Never launches an app: resolution is checked with --which.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File test.ps1
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\build.cmd"
if ($LASTEXITCODE) { throw "build failed" }
$exe = "$PSScriptRoot\open.exe"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("open-test-" + [guid]::NewGuid())
New-Item -ItemType Directory "$tmp\some dir" | Out-Null
foreach ($f in 'doc.PDF', 'a.png', 'b.png', 'www.site.com', 'x.tar.gz', '-dash.txt') { Set-Content -LiteralPath "$tmp\$f" 'x' }
$env:APPDATA = "$tmp\appdata"
$cfgFile = "$tmp\appdata\open\config.json"

# Runs open.exe with a raw command line (exact quoting, empty args work), cwd = $tmp.
function Invoke-Open([string]$cmdline) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe, $cmdline
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $tmp
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
    @{ rc = $p.ExitCode; out = $out.Trim(); err = $err.Trim() }
}

# -like patterns for stdout and stderr; '' means must be empty.
function T([string]$cmdline, [int]$rc, [string]$out = '*', [string]$err = '*') {
    $r = Invoke-Open $cmdline
    if ($r.rc -ne $rc -or $r.out -notlike $out -or $r.err -notlike $err) {
        throw "FAIL: open $cmdline`n  rc=$($r.rc) (want $rc)`n  out=[$($r.out)] (want $out)`n  err=[$($r.err)] (want $err)"
    }
}
function Assert($cond, $msg) { if (-not $cond) { throw "FAIL: $msg" } }

try {
    # usage and parsing
    T '' 0 'usage: open*' ''
    T '--help' 0 '*--which*config:*' ''
    T '/?' 0 'usage: open*' ''
    T '--version' 0 'open 2.0.0' ''
    T '--bogus' 2 '' '*unknown option --bogus*try open --help*'
    T '--set pdf' 2 '' '*--set needs <ext> and <app>*'
    T '--set pdf --list' 2 '' '*--set needs*'
    T '--set pdf --bogus' 2 '' '*--set needs*'
    T '--with -x a.png' 2 '' '*--with needs <app>*'
    T '--unset' 2 '' '*--unset needs <ext>*'
    T '--with notepad' 2 '' '*--with needs a target*'
    T '--which' 2 '' '*--which needs a target*'
    T '--set ..pdf x' 2 '' "*invalid extension '..pdf'*"
    T '--set " pdf" x' 2 '' "*invalid extension ' pdf'*"
    T '--set C:\x x' 2 '' "*invalid extension 'C:\x'*"
    T '--unset ""' 2 '' "*invalid extension ''*"
    Assert (-not (Test-Path $cfgFile)) 'bad usage must not create a config'

    # set / list / unset round trip, key normalization
    T '--list' 0 'no overrides*' ''
    T '--set PDF C:\Windows\notepad.exe' 0 '.pdf -> C:\Windows\notepad.exe' ''
    T '--set Url nosuchapp_xyz' 0 'url -> nosuchapp_xyz' "*warning: can't find 'nosuchapp_xyz'*"
    T '--set dir explorer' 0 'dir -> explorer' ''          # on PATH via PATHEXT
    T '--set tar.gz notepad' 0 '.tar.gz -> notepad' ''
    $appPath = (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths' | Select-Object -First 1).PSChildName
    T "--set .apx `"$appPath`"" 0 "*.apx -> $appPath" ''      # App Paths name: no warning
    T '--list' 0 '*.pdf*C:\Windows\notepad.exe*url*nosuchapp_xyz*' ''
    $json = Get-Content -Raw $cfgFile | ConvertFrom-Json
    Assert ($json.'.pdf' -eq 'C:\Windows\notepad.exe' -and $json.url -eq 'nosuchapp_xyz') 'config file format'
    T '--unset .apx' 0 '.apx -> (Windows default)' ''
    T '--unset apx' 1 '' '*no override for .apx*'

    # --which: overrides, --with, defaults, URLs, folders, path-first, wildcards, trimming, --
    T "--which `"$tmp\doc.PDF`"" 0 "$tmp\doc.PDF -> C:\Windows\notepad.exe (override .pdf)" ''
    T 'doc.PDF --which --with myapp' 0 "$tmp\doc.PDF -> myapp (--with)" ''
    T '--which x.tar.gz' 0 "$tmp\x.tar.gz -> notepad (override .tar.gz)" ''
    T '--which a.png' 0 "$tmp\a.png -> Windows default*" ''
    T '--which https://x.com' 0 'https://x.com -> nosuchapp_xyz (override url)' ''
    T '--which www.example.org' 0 'https://www.example.org -> nosuchapp_xyz (override url)' ''
    T '--which www.site.com' 0 "$tmp\www.site.com -> Windows default*" ''
    T '--which "some dir"' 0 "$tmp\some dir -> explorer (override dir)" ''
    T "--which `"$tmp\some dir\`"" 0 "$tmp\some dir -> explorer (override dir)" ''   # arrives as ...some dir"
    T '--which *.png' 0 "$tmp\a.png -> Windows default*`n*$tmp\b.png -> Windows default*" ''
    T '--which *.nomatch' 1 '' "*not found: '*.nomatch'*"
    T '--which missing.txt a.png' 1 "$tmp\a.png -> *" "*not found: 'missing.txt'*"
    T '--which ""' 1 '' "*not found: ''*"
    T '--which -- -dash.txt' 0 "$tmp\-dash.txt -> Windows default*" ''
    T '--which -dash.txt' 2 '' '*unknown option -dash.txt*'
    $r = & $exe --which 'https://x.com/?a=1&b=2'
    Assert ($r -eq 'https://x.com/?a=1&b=2 -> nosuchapp_xyz (override url)') "& in URL from PowerShell: $r"
    T '--unset url' 0 'url -> (Windows default)' ''
    T '--unset dir' 0 'dir -> (Windows default)' ''
    T '--which https://x.com' 0 'https://x.com -> Windows default*' ''
    T '--which .' 0 "$tmp -> Windows default: Explorer" ''

    # launch failure is reported (missing exe: ShellExecute fails without UI)
    T '--with C:\nonexistent\nope.exe a.png' 1 '' "*can't open $tmp\a.png with C:\nonexistent\nope.exe:*"

    # config safety: invalid configs are reported and never overwritten
    foreach ($bad in '{bad', '[]', '{".pdf": 1}') {
        Set-Content -LiteralPath $cfgFile $bad -NoNewline
        T '--set pdf x' 1 '' "*invalid config $cfgFile*"
        T '--list' 1 '' '*invalid config*'
        Assert ((Get-Content -Raw $cfgFile) -eq $bad) "invalid config was overwritten: $bad"
    }
    T '--with myapp --which a.png' 0 "$tmp\a.png -> myapp (--with)" ''   # --with alone never reads config
    [IO.File]::WriteAllText($cfgFile, '{"PDF": "a", ".Png": "b", "URL": "c"}')
    T '--list' 0 '.pdf*a*.png*b*url*c' ''

    # save failure: "open" is a file, so the config folder can't be created
    $env:APPDATA = "$tmp\blocked"; New-Item -ItemType Directory $env:APPDATA | Out-Null; Set-Content "$env:APPDATA\open" 'x'
    T '--set pdf x' 1 '' "*can't save config*"

    # argument quoting for --with / overrides (CommandLineToArgvW rules)
    Add-Type -TypeDefinition (Get-Content -Raw "$PSScriptRoot\open.cs") -ReferencedAssemblies System.Web.Extensions
    $cases = @{ 'C:\' = '"C:\\"'; 'a b' = '"a b"'; 'a\b' = '"a\b"'; 'a"b' = '"a\"b"'; 'a\"b' = '"a\\\"b"'; 'x\\' = '"x\\\\"' }
    foreach ($k in $cases.Keys) { Assert ([OpenAnything]::Quote($k) -eq $cases[$k]) "Quote($k) = $([OpenAnything]::Quote($k))" }
}
finally { Remove-Item -Recurse -Force $tmp }
'ok'
