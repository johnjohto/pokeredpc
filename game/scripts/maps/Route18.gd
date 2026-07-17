extends "res://scripts/MapScripts.gd"
## engine/overworld/player_state.asm CheckForceBikeOrSurf + data/maps/force_bike_surf.asm
## ForcedBikeOrSurfMaps — these Route 18 coordinates silently set BIT_ALWAYS_ON_BIKE and mount.

const FORCE_BIKE_COORDS := [Vector2i(33, 8), Vector2i(33, 9)]


func on_step(cell: Vector2i) -> bool:
	if cell in FORCE_BIKE_COORDS and not main.force_bike:
		main._mount_forced_bike()
	return false
