# The tests (docs/plans/01-PLAN-dexmenu.md 3.11, 02-PLAN-own-menu.md 3.12, 00-PLAN-build-order.md): the unit tests,
# then for each selection the test host builds Windows' menu as Explorer does and shows it with Dexmenu off and on.
# LexPen decides per selection which of its items show and with which title (..\LexPen\src\shell\LexPenShell.cpp
# GetState, GetTitle); this checks LexPen's items are the ones expected and the same either way, and the host checks
# each run (see DexmenuTest.cpp): off, Windows' menu as it is; on, Dexmenu's own menu with every item of Windows' menu
# as a card (the base layout). Each also with --late (Windows' menu changed by id while shown, as Explorer does), and
# on with a click on "View in LexPen" (its id handed back). Then: a Windows submenu filled when opened (Send to), and a
# broken layout file (Windows' own menu).
# Needs register.ps1 run first. LexPen's left side (HKCU\Software\Classes\LexPen.Shell LeftFile) is set per case and
# put back as it was.
param([string]$Work = (Join-Path $env:TEMP 'dexmenu-tests'))

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$host_ = Join-Path $root 'bin\DexmenuTest.exe'
# The base layout unless a case says otherwise; named, not left unset, as the user's own chosen layout
# (%APPDATA%\Dexmenu\settings.json) would be used then.
$baseLayout = Join-Path $root 'tests\layout-base.json'
$env:DEXMENU_LAYOUT_FILE = $baseLayout
$env:DEXMENU_SEEN_FOLDER = Join-Path $Work 'seen'   # the seen items of the tests' right-clicks, not the user's

# Unit tests first (no Windows menu needed).
& (Join-Path $root 'bin\DexmenuUnitTests.exe') | Where-Object { $_ -like 'FAIL*' -or $_ -like '*FAILED' } | ForEach-Object { Write-Output "unit: $_" }
$unitFailures = $LASTEXITCODE
Write-Output $(if ($unitFailures) { "unit tests: $unitFailures failed" } else { 'unit tests: all passed' })

Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Work\folder" | Out-Null
Set-Content "$Work\a.txt" 'a'
Set-Content "$Work\b.txt" 'b'
Set-Content "$Work\b.txt.bak" 'b'
Set-Content "$Work\left.txt" 'left'

# One run of the host, at most a minute (a run that hangs is killed and fails).
function Run($paths, [bool]$on, [string[]]$extra = @()) {
    $env:DEXMENU = if ($on) { '1' } else { '0' }   # 0: off, also when the registry has it on
    $outFile = Join-Path $Work 'host-out.txt'
    $argList = @($extra + $paths | ForEach-Object { '"' + $_ + '"' })
    $p = Start-Process $host_ -ArgumentList $argList -NoNewWindow -PassThru -RedirectStandardOutput $outFile
    if (-not $p.WaitForExit(60000)) {
        Stop-Process $p -Force
        $out = @(Get-Content $outFile) + 'FAIL the host hung (killed after a minute)'
        return [pscustomobject]@{ Code = 99; Out = $out; LexPen = ($out | Where-Object { $_ -like '== Items with verb*' }) }
    }
    $out = @(Get-Content $outFile -Encoding utf8)
    [pscustomobject]@{ Code = $p.ExitCode; Out = $out; LexPen = ($out | Where-Object { $_ -like '== Items with verb*' }) }
}

# The LexPen titles in a host's items line, in order.
function Titles($line) { [regex]::Matches($line, '\["([^"]*)"') | ForEach-Object { $_.Groups[1].Value } }

$lexKey = 'HKCU:\Software\Classes\LexPen.Shell'
# Runs a block with LexPen's left side set ($left, or none), putting LexPen's own value back after.
function WithLeft([string]$left, [scriptblock]$block) {
    $hadKey = Test-Path $lexKey
    $oldLeft = if ($hadKey) { (Get-ItemProperty $lexKey -Name LeftFile -ErrorAction SilentlyContinue).LeftFile } else { $null }
    try {
        Set-Content "$Work\left-side.txt" $left -Encoding utf8
        New-Item -Force $lexKey -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty $lexKey LeftFile "$Work\left-side.txt"
        & $block
    }
    finally {
        if (-not $hadKey) { Remove-Item -Recurse -Force $lexKey }
        elseif ($null -eq $oldLeft) { Remove-ItemProperty $lexKey LeftFile -ErrorAction SilentlyContinue }
        else { Set-ItemProperty $lexKey LeftFile $oldLeft }
    }
}

function Report([string]$name, [object[]]$runs, [string[]]$problems, [string]$detail) {
    foreach ($r in $runs) { if ($r.Code -ne 0) { $problems += "$($r.Name): host checks failed" } }
    if ($problems) {
        Write-Output "FAIL $name"
        $problems | ForEach-Object { Write-Output "     $_" }
        foreach ($r in $runs) { $r.Out | Where-Object { $_ -like 'FAIL *' } | ForEach-Object { Write-Output "     $($r.Name): $_" } }
        $script:failed++
        return
    }
    Write-Output "PASS $name$detail"
}

$cases = @(
    @{ Name = 'one file'; Paths = @("$Work\a.txt"); Expect = @('Select left side to compare', 'Edit in LexPen', 'View in LexPen') },
    @{ Name = 'one file with a .bak'; Paths = @("$Work\b.txt"); Expect = @('Select left side to compare', 'Delete .bak file', 'Edit in LexPen', 'View in LexPen') },
    @{ Name = 'two files'; Paths = @("$Work\a.txt", "$Work\b.txt"); Expect = @('Compare', 'Delete .bak files', 'Edit in LexPen', 'View in LexPen') },
    @{ Name = 'one folder'; Paths = @("$Work\folder"); Expect = @('Select left side to compare', 'Delete all .bak files', 'View in LexPen') },
    @{ Name = 'a file and a folder'; Paths = @("$Work\a.txt", "$Work\folder"); Expect = @('Compare', 'Delete all .bak files', 'View in LexPen') },
    @{ Name = 'one file, a left side chosen'; Paths = @("$Work\a.txt"); Left = "$Work\left.txt"; Expect = @('Select as new left side to compare', 'Compare to left.txt', 'Edit in LexPen', 'View in LexPen') }
)

$script:failed = 0
foreach ($c in $cases) {
    $runs = $null
    WithLeft $(if ($c.Left) { $c.Left } else { '' }) {
        $script:runs = @(
            (Run $c.Paths $false) | Add-Member -NotePropertyName Name -NotePropertyValue 'off' -PassThru
            (Run $c.Paths $true) | Add-Member -NotePropertyName Name -NotePropertyValue 'on' -PassThru
            (Run $c.Paths $false @('--late')) | Add-Member -NotePropertyName Name -NotePropertyValue 'off, changes while shown' -PassThru
            (Run $c.Paths $true @('--late')) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, changes while shown' -PassThru
            (Run $c.Paths $true @('--choose', 'LexPen.View')) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, View in LexPen clicked' -PassThru
        )
    }
    $off = $runs[0]
    $on = $runs[1]
    $got = @(Titles $off.LexPen)
    $problems = @()
    # Ids are Windows' per menu built (another handler's items can shift them), so across runs: titles and verbs only.
    # Within one run the host compares ids exactly.
    $withoutIds = { param($line) $line -replace ' id=\d+', '' }
    if ((& $withoutIds $off.LexPen) -ne (& $withoutIds $on.LexPen)) { $problems += "LexPen gave other items with Dexmenu on: off $($off.LexPen) / on $($on.LexPen)" }
    if (($got -join '|') -ne ($c.Expect -join '|')) { $problems += "LexPen's items: [$($got -join '; ')], expected [$($c.Expect -join '; ')]" }
    Report $c.Name $runs $problems ": LexPen's items [$($got -join '; ')]"
}

# A Windows submenu that its extension fills only when it opens.
WithLeft '' {
    $script:runs = @((Run @("$Work\a.txt") $true @('--open', 'Send to')) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, Send to opened' -PassThru)
}
Report 'Send to opened from its card, filled when opened' $runs @() ''

# A broken layout file: Windows' own menu.
Set-Content "$Work\broken.json" '{ "default": [ ' -Encoding utf8
$env:DEXMENU_LAYOUT_FILE = "$Work\broken.json"
WithLeft '' {
    $script:runs = @((Run @("$Work\a.txt") $true @('--expect-windows')) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, broken layout' -PassThru)
}
$env:DEXMENU_LAYOUT_FILE = $baseLayout
Report 'a broken layout file: Windows'' own menu' $runs @() ''

# The settings app (plan 00 step 4): its preview, drawn by the DLL from the seen items, shows the menu a right-click
# showed; a change to the layout file redraws it.
function DumpCards([string]$path) {
    if (-not (Test-Path $path)) { return @() }
    $levels = 0
    foreach ($line in Get-Content $path -Encoding utf8) {
        if ($line -like 'level *') { $levels++; if ($levels -gt 1) { break }; continue }
        if ($line -match '^card (item|menu) id=\d+ enabled=(\d) .* sub=(\d) .* text=(.*)$') {
            [pscustomobject]@{ Kind = $matches[1]; Text = $matches[4]; Enabled = $matches[2] -eq '1'; Sub = $matches[3] -eq '1' }
        }
    }
}
function MenuCards([string[]]$hostOut) {
    $in = $false
    foreach ($line in $hostOut) {
        if ($line -like "== Dexmenu's menu*") { $in = $true; continue }
        if (-not $in) { continue }
        if ($line -match '^\s+level [1-9]' -or $line -match '^(PASS|FAIL|==)') { break }
        if ($line -match '^\s+(item|menu) "(.*)" id=\d+( disabled)?( submenu)?$') {
            [pscustomobject]@{ Kind = $matches[1]; Text = $matches[2]; Enabled = -not $matches[3]; Sub = [bool]$matches[4] }
        }
    }
}
function Same($a, $b) { ($a | ForEach-Object { "$($_.Kind)|$($_.Text)|$($_.Enabled)|$($_.Sub)" }) -join "`n" -eq (($b | ForEach-Object { "$($_.Kind)|$($_.Text)|$($_.Enabled)|$($_.Sub)" }) -join "`n") }

Remove-Item -Recurse -Force $env:DEXMENU_SEEN_FOLDER -ErrorAction SilentlyContinue   # only this right-click's items
WithLeft '' {
    $script:runs = @((Run @("$Work\a.txt") $true) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, items recorded for the preview' -PassThru)
}
$menu = @(MenuCards $runs[0].Out)
$problems = @()
if ($menu.Count -eq 0) { $problems += 'the menu''s cards not found in the host''s output' }
$layoutFile = "$Work\layout.json"
Copy-Item -Force (Join-Path $root 'tests\layout-base.json') $layoutFile
$env:DEXMENU_LAYOUT_FILE = $layoutFile
$env:DEXMENU_DUMP = "$Work\preview-dump.txt"
Remove-Item $env:DEXMENU_DUMP -ErrorAction SilentlyContinue
$app = Start-Process (Join-Path $root 'bin\DexmenuSettings.exe') -ArgumentList '--kind', 'file' -PassThru
try {
    $preview = @()
    for ($i = 0; $i -lt 150 -and $preview.Count -eq 0; $i++) { Start-Sleep -Milliseconds 100; $preview = @(DumpCards $env:DEXMENU_DUMP) }
    if ($preview.Count -eq 0) { $problems += 'the preview showed nothing' }
    elseif (-not (Same $preview $menu)) { $problems += "the preview differs from the menu: preview [$(($preview | ForEach-Object Text) -join '; ')], menu [$(($menu | ForEach-Object Text) -join '; ')]" }
    # The remaining card moved into a card "More" with a menu: the preview shows only "More".
    Set-Content $layoutFile '{ "default": [ { "line": [ { "card": "More", "menu": [ { "line": [ { "card": "Rest", "rules": [ "remaining" ] } ] } ] } ] } ] }' -Encoding utf8
    $after = @()
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 100
        $after = @(DumpCards $env:DEXMENU_DUMP)
        if ($after.Count -eq 1) { break }
    }
    if (-not ($after.Count -eq 1 -and $after[0].Kind -eq 'menu' -and $after[0].Text -eq 'More')) {
        $problems += "after the layout file changed the preview shows [$(($after | ForEach-Object Text) -join '; ')], expected [More]"
    }
}
finally {
    if (-not $app.HasExited) { [void]$app.CloseMainWindow(); if (-not $app.WaitForExit(5000)) { Stop-Process $app -Force } }
    $env:DEXMENU_DUMP = $null
    $env:DEXMENU_LAYOUT_FILE = $baseLayout
}
Report 'the settings app: the preview is the menu, and follows the layout file' $runs $problems ": $($menu.Count) cards"

# Step 5: the editor's self-test (its operations: dropping, deleting, moving, the remaining card, the priority list).
$selftestOut = Join-Path $Work 'selftest.txt'
$st = Start-Process (Join-Path $root 'bin\DexmenuSettings.exe') -ArgumentList '--selftest', "`"$selftestOut`"" -PassThru
if (-not $st.WaitForExit(60000)) { Stop-Process $st -Force }
$stLines = @(Get-Content $selftestOut -ErrorAction SilentlyContinue)
$stProblems = @($stLines | Where-Object { $_ -like 'FAIL*' })
if ($stLines.Count -eq 0) { $stProblems += 'the self-test wrote nothing' }
$runs = @()
Report 'the editor''s operations (self-test in WebView2)' $runs $stProblems ''

# Step 5: a layout of rules gives the same menu at a right-click as in the editor's preview; a card that found several
# items places each where it stands, and a click on one hands back the item's id.
$rulesLayout = Join-Path $Work 'rules.json'
Copy-Item -Force (Join-Path $root 'tests\layout-rules.json') $rulesLayout
$env:DEXMENU_LAYOUT_FILE = $rulesLayout
# The preview shows the first run's items only: the seen items are merged, and runs differ in what Windows adds late.
Remove-Item -Recurse -Force $env:DEXMENU_SEEN_FOLDER -ErrorAction SilentlyContinue
$seenFolder = $env:DEXMENU_SEEN_FOLDER
WithLeft '' {
    $script:runs = @((Run @("$Work\a.txt") $true @('--any-layout')) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, a layout of rules' -PassThru)
    $env:DEXMENU_SEEN_FOLDER = Join-Path $Work 'seen-other'
    $script:runs += @((Run @("$Work\a.txt") $true @('--any-layout', '--choose', 'LexPen.View')) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, View in LexPen chosen, found by the LexPen card' -PassThru)
}
$env:DEXMENU_SEEN_FOLDER = $seenFolder
$menu = @(MenuCards $runs[0].Out)
$problems = @()
$start = ($menu | Select-Object -First 3 | ForEach-Object { "$($_.Kind):$($_.Text)" }) -join '; '
if ($start -ne 'item:Edit in LexPen; item:View in LexPen; menu:Tools') {
    $problems += "the menu starts [$start], expected [item:Edit in LexPen; item:View in LexPen; menu:Tools]"
}
if (@($menu | Where-Object { $_.Text -like '*in LexPen' }).Count -ne 2 -or ($menu | Where-Object { $_.Text -eq '7-Zip' })) {
    $problems += 'an item a rule took is also elsewhere at the top'
}
$env:DEXMENU_DUMP = Join-Path $Work 'preview-rules-dump.txt'
$app = Start-Process (Join-Path $root 'bin\DexmenuSettings.exe') -ArgumentList '--kind', 'file' -PassThru
try {
    $preview = @()
    for ($i = 0; $i -lt 150 -and $preview.Count -eq 0; $i++) { Start-Sleep -Milliseconds 100; $preview = @(DumpCards $env:DEXMENU_DUMP) }
    if (-not (Same $preview $menu)) { $problems += "the preview differs from the menu: preview [$(($preview | ForEach-Object Text) -join '; ')], menu [$(($menu | ForEach-Object Text) -join '; ')]" }
}
finally {
    if (-not $app.HasExited) { [void]$app.CloseMainWindow(); if (-not $app.WaitForExit(5000)) { Stop-Process $app -Force } }
    $env:DEXMENU_DUMP = $null
    $env:DEXMENU_LAYOUT_FILE = $baseLayout
}
Report 'a layout of rules: the right-click and the preview show the same menu' $runs $problems ": $($menu.Count) cards"

# The seen items merged (Dexmenu.Seen): one file right-clicked without and with a left side chosen in LexPen; the
# preview shows LexPen's items of both, those of only one striped ("sometimes"), the others not.
Remove-Item -Recurse -Force $env:DEXMENU_SEEN_FOLDER -ErrorAction SilentlyContinue
WithLeft '' {
    $script:runs = @((Run @("$Work\a.txt") $true) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, no left side' -PassThru)
}
WithLeft "$Work\left.txt" {
    $script:runs += @((Run @("$Work\a.txt") $true) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, a left side chosen' -PassThru)
}
$problems = @()
$env:DEXMENU_DUMP = Join-Path $Work 'preview-merged-dump.txt'
$app = Start-Process (Join-Path $root 'bin\DexmenuSettings.exe') -ArgumentList '--kind', 'file' -PassThru
try {
    $cards = @()
    for ($i = 0; $i -lt 150 -and $cards.Count -eq 0; $i++) {
        Start-Sleep -Milliseconds 100
        if (Test-Path $env:DEXMENU_DUMP) {
            $cards = @(Get-Content $env:DEXMENU_DUMP -Encoding utf8 | Where-Object { $_ -match '^card item .* sometimes=(\d) .* text=(.*)$' } |
                ForEach-Object { [pscustomobject]@{ Sometimes = $matches[1] -eq '1'; Text = $matches[2] } })
        }
    }
    $want = @{ 'Select left side to compare' = $true; 'Select as new left side to compare' = $true; 'Compare to left.txt' = $true;
        'Edit in LexPen' = $false; 'View in LexPen' = $false }
    foreach ($k in $want.Keys) {
        $c = @($cards | Where-Object Text -eq $k)
        if ($c.Count -ne 1) { $problems += "the preview shows '$k' $($c.Count) time(s), expected once" }
        elseif ($c[0].Sometimes -ne $want[$k]) { $problems += "'$k': sometimes=$($c[0].Sometimes), expected $($want[$k])" }
    }
}
finally {
    if (-not $app.HasExited) { [void]$app.CloseMainWindow(); if (-not $app.WaitForExit(5000)) { Stop-Process $app -Force } }
    $env:DEXMENU_DUMP = $null
}
Report 'the seen items merged: items of only some right-clicks shown striped in the preview' $runs $problems ''

# A rule with a path into a submenu an extension fills only when opened (Send to): Dexmenu opens it before the rules
# run, so its "Desktop" target is found and shown at the top.
$env:DEXMENU_LAYOUT_FILE = Join-Path $root 'tests\layout-sendto.json'
WithLeft '' {
    $script:runs = @((Run @("$Work.txt") $true @('--any-layout')) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, a rule into Send to' -PassThru)
}
$env:DEXMENU_LAYOUT_FILE = $baseLayout
$top = @(MenuCards $runs[0].Out)
$problems = @()
if (-not ($top | Where-Object { $_.Kind -eq 'item' -and $_.Text -like '*Desktop*' })) {
    $problems += "Send to's Desktop target not at the top: [$(($top | Select-Object -First 4 | ForEach-Object Text) -join '; ')]"
}
Report 'a rule into a submenu filled when opened (Send to) finds its items' $runs $problems ''

# The preview's live menu (ShellMenu, DexmenuSettings.exe --live): Windows' real menu of a right-click in a base folder,
# its submenus filled; a file in the work folder has LexPen's items and 7-Zip's filled submenu; the empty part of a
# folder has a menu too.
$problems = @()
$liveOut = Join-Path $Work 'live.json'
function LiveMenu([string[]]$liveArgs) {
    Remove-Item $liveOut -ErrorAction SilentlyContinue
    $p = Start-Process (Join-Path $root 'bin\DexmenuSettings.exe') -ArgumentList (@('--live', "`"$liveOut`"") + ($liveArgs | ForEach-Object { "`"$_`"" })) -PassThru
    if (-not $p.WaitForExit(60000)) { Stop-Process $p -Force; return $null }
    if ($p.ExitCode -ne 0) { return $null }
    Get-Content $liveOut -Raw -Encoding utf8 | ConvertFrom-Json
}
function Names($items) { foreach ($i in $items) { if ($i.name) { $i.name }; if ($i.items) { Names $i.items } } }
WithLeft '' {
    $live = LiveMenu @('file', $Work, "$Work\a.txt")
    if ($null -eq $live) { $script:problems += 'a file: no menu' }
    else {
        $names = @(Names $live.items)
        foreach ($n in 'Select left side to compare', 'Edit in LexPen', 'View in LexPen') { if ($names -notcontains $n) { $script:problems += "a file: '$n' missing" } }
        $zip = $live.items | Where-Object name -eq '7-Zip'
        if ($zip -and -not $zip.items) { $script:problems += 'a file: 7-Zip''s submenu not filled' }
    }
}
$live = LiveMenu @('background', $Work)
if ($null -eq $live -or @(Names $live.items).Count -eq 0) { $problems += 'a folder''s empty part: no menu' }
elseif (@($live.items | Where-Object submenu).Count -lt 2) { $problems += 'a folder''s empty part: no View / Sort by submenus (the folder view''s own items)' }
$runs = @()
Report 'the preview''s live menu: Windows'' real menu of a right-click in a folder' $runs $problems ''

# The last right-click (seen\last.json, written by the DLL after its menu was shown), where the preview starts: a file
# in the work folder right-clicked, its kind, folder and item recorded.
$problems = @()
$lastFile = Join-Path $env:DEXMENU_SEEN_FOLDER 'last.json'
Remove-Item $lastFile -ErrorAction SilentlyContinue
WithLeft '' {
    $script:runs = @((Run @("$Work\a.txt") $true) | Add-Member -NotePropertyName Name -NotePropertyValue 'on, a file right-clicked' -PassThru)
}
if (-not (Test-Path $lastFile)) { $problems += 'no last right-click written' }
else {
    $last = Get-Content $lastFile -Raw -Encoding utf8 | ConvertFrom-Json
    if ($last.kind -ne 'file' -or $last.folder -ne $Work -or @($last.items).Count -ne 1 -or $last.items[0] -ne "$Work\a.txt") {
        $problems += "last right-click: kind '$($last.kind)', folder '$($last.folder)', items [$(@($last.items) -join '; ')]"
    }
}
Report 'the last right-click recorded for the preview' $runs $problems ''

# Registering for the current user from the settings app (Registration.cs), without restarting Explorer: unregistered,
# then registered again (as the tests need it).
function RegState {
    $inproc = 'HKCU:\Software\Classes\CLSID\{CD4EEF01-47D9-4172-A48A-F6E61850D170}\InprocServer32'
    $dll = if (Test-Path $inproc) { (Get-ItemProperty $inproc).'(default)' } else { '' }
    $handlers = @('AllFilesystemObjects', 'Directory\Background', 'Drive' | Where-Object { Test-Path "HKCU:\Software\Classes\$_\shellex\ContextMenuHandlers\Dexmenu" }).Count
    [pscustomobject]@{ Dll = $dll; Handlers = $handlers; Enabled = (Get-ItemProperty HKCU:\Software\Dexmenu -ErrorAction SilentlyContinue).Enabled }
}
$settingsExe = Join-Path $root 'bin\DexmenuSettings.exe'
$problems = @()
Start-Process $settingsExe -ArgumentList '--unregister' -Wait
$s = RegState
if ($s.Dll -or $s.Handlers -or $s.Enabled -ne 0) { $problems += "after --unregister: dll '$($s.Dll)', $($s.Handlers) handler key(s), enabled $($s.Enabled)" }
Start-Process $settingsExe -ArgumentList '--register' -Wait
$s = RegState
if ($s.Dll -ne (Join-Path $root 'bin\DexmenuShell.dll') -or $s.Handlers -ne 3 -or $s.Enabled -ne 1) { $problems += "after --register: dll '$($s.Dll)', $($s.Handlers) handler key(s), enabled $($s.Enabled)" }
$runs = @()
Report 'register and unregister for the current user' $runs $problems ''

Write-Output ($(if ($failed) { "$failed case(s) failed" } else { 'all cases passed' }))
exit ($failed + $unitFailures)
