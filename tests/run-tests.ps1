# The spike's test (docs/plans/01-PLAN-dexmenu.md 3.11): for each selection, the test host builds Windows' menu with
# Dexmenu off and on. LexPen decides per selection which of its items show and with which title
# (..\LexPen\src\shell\LexPenShell.cpp GetState, GetTitle); this checks that, with Dexmenu on, exactly the items LexPen
# gave for that selection are in "from LexPen", as LexPen gave them, and that LexPen gives the same items either way.
# Needs register.ps1 run first. The left side case writes HKCU\Software\Classes\LexPen.Shell LeftFile for the run and
# puts the key back as it was.
param([string]$Work = (Join-Path $env:TEMP 'dexmenu-tests'))

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$host_ = Join-Path $root 'bin\DexmenuTest.exe'
$env:DEXMENU_LAYOUT = Join-Path $PSScriptRoot 'layout-lexpen.txt'

Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Work\folder" | Out-Null
Set-Content "$Work\a.txt" 'a'
Set-Content "$Work\b.txt" 'b'
Set-Content "$Work\b.txt.bak" 'b'
Set-Content "$Work\left.txt" 'left'

function Run($paths, [bool]$on) {
    $env:DEXMENU = if ($on) { '1' } else { $null }
    $out = & $host_ @paths
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out; LexPen = ($out | Where-Object { $_ -like '== Items with verb*' }) }
}

# The LexPen titles in a host's items line, in order.
function Titles($line) { [regex]::Matches($line, '\["([^"]*)"') | ForEach-Object { $_.Groups[1].Value } }

$cases = @(
    @{ Name = 'one file'; Paths = @("$Work\a.txt"); Expect = @('Select left side to compare', 'Edit in LexPen', 'View in LexPen') },
    @{ Name = 'one file with a .bak'; Paths = @("$Work\b.txt"); Expect = @('Select left side to compare', 'Delete .bak file', 'Edit in LexPen', 'View in LexPen') },
    @{ Name = 'two files'; Paths = @("$Work\a.txt", "$Work\b.txt"); Expect = @('Compare', 'Delete .bak files', 'Edit in LexPen', 'View in LexPen') },
    @{ Name = 'one folder'; Paths = @("$Work\folder"); Expect = @('Select left side to compare', 'Delete all .bak files', 'View in LexPen') },
    @{ Name = 'a file and a folder'; Paths = @("$Work\a.txt", "$Work\folder"); Expect = @('Compare', 'Delete all .bak files', 'View in LexPen') },
    @{ Name = 'one file, a left side chosen'; Paths = @("$Work\a.txt"); Left = "$Work\left.txt"; Expect = @('Select as new left side to compare', 'Compare to left.txt', 'Edit in LexPen', 'View in LexPen') }
)

$lexKey = 'HKCU:\Software\Classes\LexPen.Shell'
$failed = 0
foreach ($c in $cases) {
    $hadKey = Test-Path $lexKey
    $oldLeft = if ($hadKey) { (Get-ItemProperty $lexKey -Name LeftFile -ErrorAction SilentlyContinue).LeftFile } else { $null }
    try {
        if ($c.Left) {
            Set-Content "$Work\left-side.txt" $c.Left -Encoding utf8
            New-Item -Force $lexKey -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty $lexKey LeftFile "$Work\left-side.txt"
        }
        $off = Run $c.Paths $false
        $on = Run $c.Paths $true
    }
    finally {
        if ($c.Left) {
            if (-not $hadKey) { Remove-Item -Recurse -Force $lexKey }
            elseif ($null -eq $oldLeft) { Remove-ItemProperty $lexKey LeftFile -ErrorAction SilentlyContinue }
            else { Set-ItemProperty $lexKey LeftFile $oldLeft }
        }
    }
    $got = @(Titles $off.LexPen)
    $problems = @()
    if ($off.Code -ne 0) { $problems += 'Dexmenu off: host checks failed' }
    if ($on.Code -ne 0) { $problems += 'Dexmenu on: host checks failed' }
    # Ids are Windows' per menu built (another handler's items can shift them), so across runs: titles and verbs only.
    # Within one run the host compares ids exactly.
    $withoutIds = { param($line) $line -replace ' id=\d+', '' }
    if ((& $withoutIds $off.LexPen) -ne (& $withoutIds $on.LexPen)) { $problems += "LexPen gave other items with Dexmenu on: off $($off.LexPen) / on $($on.LexPen)" }
    if (($got -join '|') -ne ($c.Expect -join '|')) { $problems += "LexPen's items: [$($got -join '; ')], expected [$($c.Expect -join '; ')]" }
    if ($problems) {
        $failed++
        Write-Output "FAIL $($c.Name)"
        $problems | ForEach-Object { Write-Output "     $_" }
        $off.Out + $on.Out | Where-Object { $_ -like 'FAIL *' } | ForEach-Object { Write-Output "     $_" }
    }
    else { Write-Output "PASS $($c.Name): from LexPen = [$($got -join '; ')]" }
}
Write-Output ($(if ($failed) { "$failed case(s) failed" } else { 'all cases passed' }))
exit $failed
