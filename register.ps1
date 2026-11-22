# Registers bin\DexmenuShell.dll for the current user (HKCU\Software\Classes) as a context menu handler for files,
# folders, a folder's empty part, the desktop's empty part and drives (docs/plans/01-PLAN-dexmenu.md 3.1, 3.9). -Remove takes it away again.
# Registered is not on: the DLL does nothing until HKCU\Software\Dexmenu Enabled is 1 (-Enable) or DEXMENU=1 is set
# in the process (the tests). Explorer keeps a loaded DLL until it restarts.
# -FullMenu: Windows 11 shows the full menu at once, not its short menu with "Show more options" (plan 3.10: Windows'
# own switch, an empty InprocServer32 for its short menu's class, per user); -ShortMenu undoes it. Explorer restarted.
param([switch]$Remove, [switch]$Enable, [switch]$Disable, [switch]$FullMenu, [switch]$ShortMenu)

$clsid = '{CD4EEF01-47D9-4172-A48A-F6E61850D170}'
$classes = 'HKCU:\Software\Classes'
$kinds = 'AllFilesystemObjects', 'Directory\Background', 'DesktopBackground', 'Drive'
$dll = Join-Path $PSScriptRoot 'bin\DexmenuShell.dll'

if ($FullMenu -or $ShortMenu) {
    $modernMenu = "$classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    if ($FullMenu) { New-Item -Force -Path "$modernMenu\InprocServer32" -Value '' | Out-Null }
    else { Remove-Item -Recurse -Force -LiteralPath $modernMenu -ErrorAction SilentlyContinue }
    Stop-Process -Name explorer -Force
    Start-Sleep 3
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    return
}

if ($Enable -or $Disable) {
    New-Item -Force 'HKCU:\Software\Dexmenu' | Out-Null
    Set-ItemProperty 'HKCU:\Software\Dexmenu' Enabled ([int][bool]$Enable) -Type DWord
    return
}

foreach ($kind in $kinds) {
    $key = "$classes\$kind\shellex\ContextMenuHandlers\Dexmenu"
    if ($Remove) { Remove-Item -Recurse -Force -LiteralPath $key -ErrorAction SilentlyContinue }
    else { New-Item -Force -Path $key -Value $clsid | Out-Null }
}
if ($Remove) {
    Remove-Item -Recurse -Force -LiteralPath "$classes\CLSID\$clsid" -ErrorAction SilentlyContinue
    return
}
if (-not (Test-Path $dll)) { throw "not built: $dll" }
New-Item -Force -Path "$classes\CLSID\$clsid" -Value 'Dexmenu' | Out-Null
New-Item -Force -Path "$classes\CLSID\$clsid\InprocServer32" -Value $dll | Out-Null
Set-ItemProperty -LiteralPath "$classes\CLSID\$clsid\InprocServer32" ThreadingModel Apartment
