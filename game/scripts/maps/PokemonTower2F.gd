extends "res://scripts/MapScripts.gd"
## scripts/PokemonTower2F.asm — the rival battle on the second floor.


func on_step(cell: Vector2i) -> bool:
	if (cell == Vector2i(15, 5) or cell == Vector2i(14, 6)) and not has_event("BEAT_POKEMON_TOWER_RIVAL"):
		main.cutscene.tower_rival()
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_BLUE@14,5":
		return not has_event("BEAT_POKEMON_TOWER_RIVAL")   # the rival leaves after the fight
	return null
