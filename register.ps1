# Registers bin\DexmenuShell.dll for the current user (HKCU\Software\Classes) as a context menu handler for files,
# folders, a folder's empty part and drives (docs/plans/01-PLAN-dexmenu.md 3.1, 3.9). -Remove takes it away again.
# Registered is not on: the DLL does nothing until HKCU\Software\Dexmenu Enabled is 1 (-Enable) or DEXMENU=1 is set
# in the process (the tests). Explorer keeps a loaded DLL until it restarts.
param([switch]$Remove, [switch]$Enable, [switch]$Disable)

$clsid = '{CD4EEF01-47D9-4172-A48A-F6E61850D170}'
$classes = 'HKCU:\Software\Classes'
$kinds = 'AllFilesystemObjects', 'Directory\Background', 'Drive'
$dll = Join-Path $PSScriptRoot 'bin\DexmenuShell.dll'

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
