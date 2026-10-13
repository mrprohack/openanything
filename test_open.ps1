# Self-check for the app-selection logic. Run: powershell -ExecutionPolicy Bypass -File test_open.ps1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\openanything.ps1"

function Assert($cond, $msg) { if (-not $cond) { throw "FAIL: $msg" } }

$cfg = @{ '.pdf' = 'SumatraPDF.exe'; 'url' = 'firefox'; 'dir' = 'totalcmd' }

Assert ((Get-Key 'a\b\Doc.PDF') -eq '.pdf') 'extension key is lowercase'
Assert ((Get-Key 'https://x.com') -eq 'url') 'https is url'
Assert ((Get-Key 'www.x.com') -eq 'url') 'www is url'
Assert ((Get-Key $env:TEMP) -eq 'dir') 'folder is dir'
Assert ((Get-Key 'noext') -eq '') 'no extension'

Assert ((Resolve-App 'x.pdf' $cfg) -eq 'SumatraPDF.exe') 'config override'
Assert ((Resolve-App 'x.pdf' $cfg 'notepad') -eq 'notepad') '--with beats config'
Assert ($null -eq (Resolve-App 'x.png' $cfg)) 'Windows default'
Assert ((Resolve-App 'https://x.com' $cfg) -eq 'firefox') 'url override'
Assert ((Resolve-App $PSScriptRoot $cfg) -eq 'totalcmd') 'dir override'

Assert ((ConvertTo-Key 'PDF') -eq '.pdf') 'adds dot'
Assert ((ConvertTo-Key '.pdf') -eq '.pdf') 'keeps dot'
Assert ((ConvertTo-Key 'URL') -eq 'url') 'url key'

'ok'
