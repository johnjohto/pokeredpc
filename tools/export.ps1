# Export a playable Windows build: build/windows/pokeredpc.exe with the project data as a
# loose `project/` folder beside it (res://project is .gdignore'd raw data — invisible to
# Godot's exporter by design, keeping the files md5-stable with no import artifacts; the
# runtime falls back to <exe dir>/project in exported builds).
#
# Personal-use project (AGENTS.md): do NOT distribute the exported build or the extracted
# assets — the export is for playing your own copy without the toolchain.
#
# Run:  pwsh tools/export.ps1     (after tools/build.ps1 has extracted + imported)
$root = Split-Path $PSScriptRoot -Parent
$godot = $env:POKEREDPC_GODOT
if (-not $godot) {
    $godot = Join-Path $PSScriptRoot (Join-Path "godot" "Godot_v4.7-stable_win64.exe")
}
if (-not (Test-Path (Join-Path $root "game/project/manifest.json"))) {
    Write-Error "no project at game/project — run tools/build.ps1 first"
    exit 1
}
$out = Join-Path $root "build/windows"
New-Item -ItemType Directory -Force $out | Out-Null
$exe = Join-Path $out "pokeredpc.exe"
$before = if (Test-Path $exe) { (Get-Item $exe).LastWriteTime } else { [datetime]::MinValue }
# The pipe is load-bearing: the Godot exe is GUI-subsystem, and an unpiped call DETACHES —
# the script would race past a still-running export. Piping forces a synchronous drain.
& $godot --headless --path (Join-Path $root "game") --export-release "Windows Desktop" 2>&1 | Out-Host
# Judge by the artifact, not the exit code: headless Godot may exit 0xC0000005 on shutdown
# after a completed export (the known-harmless import quirk, see AGENTS.md).
if (-not (Test-Path $exe) -or (Get-Item $exe).LastWriteTime -le $before) {
    Write-Error "godot export produced no new $exe"
    exit 1
}
Remove-Item -Recurse -Force (Join-Path $out "project") -ErrorAction SilentlyContinue
Copy-Item -Recurse (Join-Path $root "game/project") (Join-Path $out "project")
$exe = Join-Path $out "pokeredpc.exe"
$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host "exported: $exe ($size MB) + project/ ($([math]::Round((Get-ChildItem -Recurse (Join-Path $out 'project') | Measure-Object Length -Sum).Sum / 1MB, 1)) MB)"
