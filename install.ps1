# Installs open.exe to %LOCALAPPDATA%\Programs\open and adds it to your user PATH.
#   irm https://raw.githubusercontent.com/mrprohack/openanything/main/install.ps1 | iex
# Uninstall:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/mrprohack/openanything/main/install.ps1))) -Uninstall
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'

$dir = "$env:LOCALAPPDATA\Programs\open"
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$path = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$parts = @($path -split ';' | Where-Object { $_ -and $_ -ne $dir })

if ($Uninstall) {
    $key.SetValue('Path', ($parts -join ';'), 'ExpandString')
    $key.Close()
    Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
    Write-Host "Removed $dir and its PATH entry. Your settings in $env:APPDATA\open were kept."
} else {
    New-Item -ItemType Directory -Force $dir | Out-Null
    $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'open.exe' }
    if ($local -and (Test-Path $local)) {
        Copy-Item $local "$dir\open.exe" -Force
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest 'https://github.com/mrprohack/openanything/releases/latest/download/open.exe' -OutFile "$dir\open.exe" -UseBasicParsing
    }
    Unblock-File "$dir\open.exe"
    $key.SetValue('Path', ((@($parts) + $dir) -join ';'), 'ExpandString')
    $key.Close()
    if (($env:Path -split ';') -notcontains $dir) { $env:Path += ";$dir" }
    Write-Host "Installed $dir\open.exe. Run: open --version"
}
# tell Windows the environment changed, so new terminals see it
[Environment]::SetEnvironmentVariable('OPEN_SETUP', '1', 'User'); [Environment]::SetEnvironmentVariable('OPEN_SETUP', $null, 'User')
