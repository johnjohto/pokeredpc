# The gh #66 formula-hatch determinism gate (ADR-030): battle streams must be
# byte-identical whether the gen1 kernels run native or as HatchScript re-expressions.
# Runs --exprtest first (which rebuilds the gen1-scripted scratch project and proves
# the equivalence sweep), then --battledettest against the vanilla project and against
# the scratch, and diffs the four stream md5s itself. md5s are machine-relative
# (gh #44), so the comparison is same-machine run-vs-run, never pinned constants.
#
#   pwsh tools/hatchdet.ps1
#
# Exit 0 = GATE GREEN (all suites green and the four md5s identical).

$root = Split-Path $PSScriptRoot -Parent
$godot = $env:POKEREDPC_GODOT
if (-not $godot) {
    $name = if ($IsLinux) { "Godot_v4.7-stable_linux.x86_64" }
            elseif ($IsMacOS) { "Godot.app/Contents/MacOS/Godot" }
            else { "Godot_v4.7-stable_win64.exe" }
    $godot = Join-Path $PSScriptRoot (Join-Path "godot" $name)
}
$game = Join-Path $root "game"

function Invoke-Suite([string]$label, [string[]]$suiteArgs) {
    Write-Host "==> $label" -ForegroundColor Cyan
    $output = & $godot --headless --path $game -- @suiteArgs 2>&1 | ForEach-Object { "$_" }
    $global:LASTEXITCODE = $LASTEXITCODE
    return $output
}

$expr = Invoke-Suite "exprtest (equivalence sweep + scratch build)" @("--exprtest")
if ($LASTEXITCODE -ne 0 -or -not ($expr -match "\[expr\] ALL GREEN")) {
    $expr | Where-Object { $_ -match "FAIL|FATAL" } | Write-Host
    Write-Host "[hatchdet] FAIL — exprtest not green" -ForegroundColor Red
    exit 1
}
$scratch = ($expr | Select-String "\[expr\] hatch determinism scratch: (.+)$").Matches.Groups[1].Value.Trim()
if (-not $scratch -or -not (Test-Path (Join-Path $scratch "manifest.json"))) {
    Write-Host "[hatchdet] FAIL — exprtest did not leave the gen1-scripted scratch" -ForegroundColor Red
    exit 1
}

function Get-StreamHashes([string]$label, [string[]]$suiteArgs) {
    $output = Invoke-Suite $label $suiteArgs
    if ($LASTEXITCODE -ne 0 -or -not ($output -match "\[battledet\] ALL GREEN")) {
        $output | Where-Object { $_ -match "FAIL|FATAL" } | Write-Host
        Write-Host "[hatchdet] FAIL — $label not green" -ForegroundColor Red
        exit 1
    }
    $hashes = [ordered]@{}
    foreach ($match in ($output | Select-String "\[battledet\] (\w+):.*stream_md5=([0-9a-f]+)")) {
        $hashes[$match.Matches.Groups[1].Value] = $match.Matches.Groups[2].Value
    }
    return $hashes
}

$vanilla = Get-StreamHashes "battledettest (vanilla project)" @("--battledettest")
$scripted = Get-StreamHashes "battledettest (gen1-scripted scratch)" @("--battledettest", "--project=$scratch")

$ok = $vanilla.Count -eq 4 -and $scripted.Count -eq 4
foreach ($scenario in $vanilla.Keys) {
    $same = $vanilla[$scenario] -eq $scripted[$scenario]
    $verdict = if ($same) { "IDENTICAL" } else { "DIFFERS" }
    Write-Host ("[hatchdet] {0}: native {1} vs scripted {2} — {3}" -f $scenario,
        $vanilla[$scenario], $scripted[$scenario], $verdict)
    $ok = $ok -and $same
}
if ($ok) {
    Write-Host "[hatchdet] GATE GREEN — scripted kernels reproduce the native streams byte-for-byte" -ForegroundColor Green
    exit 0
}
Write-Host "[hatchdet] FAIL — stream md5s diverged under scripted kernels" -ForegroundColor Red
exit 1
