# Launch the game. Project args can be passed directly (e.g. --selftest, --shot).
# Godot requires a standalone `--` before user args; insert it here so callers do not
# need to know that engine detail. Preserve an explicitly supplied separator for
# compatibility and for advanced callers mixing Godot and project arguments.
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
$forwardedArgs = @($args)
if ($forwardedArgs.Count -gt 0 -and $forwardedArgs -notcontains "--") {
    $forwardedArgs = @("--") + $forwardedArgs
}
& $godot --path (Join-Path $root "game") @forwardedArgs
