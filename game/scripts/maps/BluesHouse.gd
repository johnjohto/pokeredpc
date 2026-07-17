extends "res://scripts/MapScripts.gd"
## scripts/BluesHouse.asm - Daisy hands over the TOWN MAP; only one Daisy at a time
## (toggleable_objects).


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_DAISY@2,3":
		face_player(npc)
		main.cutscene.daisy_town_map()
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_DAISY@2,3":
		return not has_event("GOT_TOWN_MAP")   # sitting Daisy hands over the TOWN MAP...
	if k == "SPRITE_DAISY@6,4":
		return has_event("GOT_TOWN_MAP")       # ...then she's up and walking around
	return null