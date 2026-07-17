extends "res://scripts/MapScripts.gd"
## scripts/PokemonTower5F.asm PokemonTower5FDefaultScript — the four-tile purified zone.

const PURIFIED_ZONE := [Vector2i(10, 8), Vector2i(11, 8), Vector2i(10, 9), Vector2i(11, 9)]

var _in_zone := false   # floor-local equivalent of EVENT_IN_PURIFIED_ZONE; leaving re-arms it


func on_step(cell: Vector2i) -> bool:
	if cell in PURIFIED_ZONE:
		if not _in_zone:
			_in_zone = true
			main.cutscene.tower_purified_zone()
		# Main returns before its dungeon-floor encounter roll when on_step consumes the step,
		# mirroring PokemonTower5FDefaultScript's BIT_NO_BATTLES while the player is in the zone.
		return true
	_in_zone = false
	return false
