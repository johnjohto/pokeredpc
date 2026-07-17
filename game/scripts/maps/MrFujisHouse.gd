extends "res://scripts/MapScripts.gd"
## scripts/MrFujisHouse.asm — Mr. Fuji hands over the POKé FLUTE; he's only home after the
## Pokémon Tower rescue.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_MR_FUJI@3,1":
		face_player(npc)
		main.cutscene.mr_fuji_flute()
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_MR_FUJI@3,1":
		return has_event("RESCUED_MR_FUJI")   # he's home only after the tower rescue
	return null
