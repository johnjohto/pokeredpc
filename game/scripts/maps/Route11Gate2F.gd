extends "res://scripts/MapScripts.gd"
## scripts/Route11Gate2F.asm - Oak''s aide: the ITEMFINDER at 30 owned species.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_SCIENTIST@2,6":
		face_player(npc)
		main.cutscene.oaks_aide("ITEMFINDER", 30, "GOT_ITEMFINDER",
			"There are items on\nthe ground that\ncan''t be seen.\fITEMFINDER will\ndetect an item\nclose to you.\fIt can''t pinpoint\nit, so you have\nto look yourself!")
		return true
	return false