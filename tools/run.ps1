# Launch the game. Pass extra args through (e.g. -- --selftest, -- --shot).
$root = Split-Path $PSScriptRoot -Parent
$godot = Join-Path $PSScriptRoot "godot\Godot_v4.7-stable_win64.exe"
& $godot --path (Join-Path $root "game") @args
