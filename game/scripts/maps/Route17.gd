extends "res://scripts/MapScripts.gd"
## engine/overworld/player_state.asm CheckForceBikeOrSurf — BIT_ALWAYS_ON_BIKE persists while
## Cycling Road rebases onto Route 17.


func on_enter() -> void:
	if main.force_bike:
		main._mount_forced_bike()
