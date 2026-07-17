# Extract assets from pokered/ and (re)import them into the Godot project.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$godot = Join-Path $PSScriptRoot "godot\Godot_v4.7-stable_win64_console.exe"

Write-Host "==> Extracting assets..." -ForegroundColor Cyan
python (Join-Path $PSScriptRoot "extract.py")

Write-Host "==> Importing into Godot..." -ForegroundColor Cyan
# Editor pass generates .import files; it may exit non-zero on headless shutdown.
& $godot --headless --editor --quit --path (Join-Path $root "game") | Out-Null
Write-Host "==> Done." -ForegroundColor Green
