extends "res://scripts/MapScripts.gd"
## scripts/PokemonTower6F.asm — the restless MAROWAK ghost blocks the stairs at (10,16).


func on_step(cell: Vector2i) -> bool:
	if cell == Vector2i(10, 16) and not has_event("BEAT_GHOST_MAROWAK"):
		main.cutscene.marowak_ghost()
		return true
	return false
