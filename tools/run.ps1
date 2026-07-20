# Launch the game. Pass extra args through (e.g. -- --selftest, -- --shot).
# Runs on any OS with pwsh: the Godot binary is picked per-platform (gh #12),
# overridable via the POKEREDPC_GODOT env var.
$root = Split-Path $PSScriptRoot -Parent
$godot = $env:POKEREDPC_GODOT
if (-not $godot) {
    $name = if ($IsLinux) { "Godot_v4.7-stable_linux.x86_64" }
            elseif ($IsMacOS) { "Godot.app/Contents/MacOS/Godot" }
            else { "Godot_v4.7-stable_win64.exe" }
    $godot = Join-Path $PSScriptRoot (Join-Path "godot" $name)
}
& $godot --path (Join-Path $root "game") @args
