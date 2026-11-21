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
$env:DEXMENU_LAYOUT_FILE = $null   # the built-in base layout unless a case says otherwise
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
$env:DEXMENU_LAYOUT_FILE = $null
Report 'a broken layout file: Windows'' own menu' $runs @() ''

# The settings app (plan 00 step 4): its preview, drawn by the DLL from the seen items, shows the menu a right-click
# showed; a change to the layout file redraws it.
function DumpCards([string]$path) {
    if (-not (Test-Path $path)) { return @() }
    $levels = 0
    foreach ($line in Get-Content $path -Encoding utf8) {
        if ($line -like 'level *') { $levels++; if ($levels -gt 1) { break }; continue }
        if ($line -match '^card (item|menu) id=\d+ enabled=(\d) checked=\d default=\d sub=(\d) selected=\d x=-?\d+ y=-?\d+ text=(.*)$') {
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
    $env:DEXMENU_LAYOUT_FILE = $null
}
Report 'the settings app: the preview is the menu, and follows the layout file' $runs $problems ": $($menu.Count) cards"

Write-Output ($(if ($failed) { "$failed case(s) failed" } else { 'all cases passed' }))
exit ($failed + $unitFailures)
