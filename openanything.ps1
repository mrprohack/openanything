# openanything - open files, folders and URLs with the right app. Your overrides first, Windows default otherwise.
$Config = Join-Path $(if ($env:APPDATA) { $env:APPDATA } else { $HOME }) 'open\config.json'

$Usage = @"
usage: open <target> [<target> ...]     open files, folders or URLs
       open --with <app> <target> ...   use <app> this one time
       open --set <ext> <app>           always open <ext> (.pdf, url, dir) with <app>
       open --unset <ext>               remove an override
       open --list                      show overrides
config: $Config
"@

function Out-Line($s) { [Console]::Out.WriteLine($s) }
function Out-Err($s) { [Console]::Error.WriteLine("open: $s") }

function Read-Config {
    $cfg = @{}
    if (Test-Path -LiteralPath $Config) {
        $obj = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($obj) { foreach ($p in $obj.PSObject.Properties) { $cfg[$p.Name] = $p.Value } }
    }
    $cfg
}

function Save-Config($cfg) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Config) | Out-Null
    [IO.File]::WriteAllText($Config, ($cfg | ConvertTo-Json))   # UTF-8, no BOM
}

function Test-Url($t) { $t -match '://' -or $t -match '^(mailto:|www\.)' }

# Config key: 'url', 'dir', or the lowercase extension ('.pdf').
function Get-Key($t) {
    if (Test-Url $t) { 'url' }
    elseif (Test-Path -LiteralPath $t -PathType Container) { 'dir' }
    else { [IO.Path]::GetExtension($t).ToLower() }
}

function ConvertTo-Key($k) {
    $k = $k.ToLower()
    if ($k -eq 'url' -or $k -eq 'dir' -or $k.StartsWith('.')) { $k } else { ".$k" }
}

# App to use for target, or $null for the Windows default.
function Resolve-App($t, $cfg, $with) {
    if ($with) { $with } else { $cfg[(Get-Key $t)] }
}

function Start-Target($t, $app) {
    if ($t -match '^www\.') { $t = "https://$t" }
    # ShellExecute finds apps by full path, PATH, or App Paths (firefox, chrome, notepad...)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.UseShellExecute = $true
    if ($app) { $psi.FileName = $app; $psi.Arguments = "`"$t`"" } else { $psi.FileName = $t }
    [void][Diagnostics.Process]::Start($psi)
}

function Invoke-Open([string[]]$argv) {
    $targets = @(); $with = $null; $set = $null; $unset = $null; $list = $false
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $a = $argv[$i]
        $need = @{ '--with' = 1; '--set' = 2; '--unset' = 1 }[$a]
        if ($need -and $i + $need -ge $argv.Count) { Out-Err "$a needs $need value(s)"; Out-Line $Usage; return 2 }
        if ($a -eq '--with') { $with = $argv[++$i] }
        elseif ($a -eq '--set') { $set = $argv[$i + 1], $argv[$i + 2]; $i += 2 }
        elseif ($a -eq '--unset') { $unset = $argv[++$i] }
        elseif ($a -eq '--list') { $list = $true }
        elseif ($a -eq '--help' -or $a -eq '-h' -or $a -eq '/?') { Out-Line $Usage; return 0 }
        else { $targets += $a }
    }

    $cfg = Read-Config
    if ($set) {
        $k = ConvertTo-Key $set[0]; $cfg[$k] = $set[1]; Save-Config $cfg
        Out-Line "$k -> $($set[1])"
    }
    if ($unset) {
        $k = ConvertTo-Key $unset
        if ($cfg.ContainsKey($k)) { $cfg.Remove($k); Save-Config $cfg } else { Out-Line "no override for $k" }
    }
    if ($list) {
        if ($cfg.Count -eq 0) { Out-Line "no overrides ($Config)" }
        foreach ($k in $cfg.Keys | Sort-Object) { Out-Line ("{0,-8} {1}" -f $k, $cfg[$k]) }
    }
    if (-not ($targets -or $set -or $unset -or $list)) { Out-Line $Usage; return 0 }

    $rc = 0
    foreach ($t in $targets) {
        if (-not (Test-Url $t)) {
            if (-not (Test-Path -LiteralPath $t)) { Out-Err "not found: $t"; $rc = 1; continue }
            $t = (Resolve-Path -LiteralPath $t).ProviderPath
        }
        $app = Resolve-App $t $cfg $with
        try { Start-Target $t $app }
        catch {
            $e = $_.Exception; if ($e.InnerException) { $e = $e.InnerException }
            Out-Err "can't open $t with $(if ($app) { $app } else { 'default app' }): $($e.Message)"; $rc = 1
        }
    }
    $rc
}

# Run unless dot-sourced (the tests dot-source this file).
if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Open $args) }
