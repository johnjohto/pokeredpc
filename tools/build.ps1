# Extract assets from pokered/ and (re)import them into the Godot project.
# Runs on any OS with pwsh: the Godot binary is picked per-platform (gh #12),
# overridable via the POKEREDPC_GODOT env var. (Windows uses the _console
# variant so the editor's import log reaches the terminal.)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$godot = $env:POKEREDPC_GODOT
if (-not $godot) {
    $name = if ($IsLinux) { "Godot_v4.7-stable_linux.x86_64" }
            elseif ($IsMacOS) { "Godot.app/Contents/MacOS/Godot" }
            else { "Godot_v4.7-stable_win64_console.exe" }
    $godot = Join-Path $PSScriptRoot (Join-Path "godot" $name)
}

Write-Host "==> Extracting assets..." -ForegroundColor Cyan
python (Join-Path $PSScriptRoot "extract.py") @args

Write-Host "==> Importing into Godot..." -ForegroundColor Cyan
# Editor pass generates .import files; it may exit non-zero on headless shutdown.
& $godot --headless --editor --quit --path (Join-Path $root "game") | Out-Null
Write-Host "==> Done." -ForegroundColor Green
