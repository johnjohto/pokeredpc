extends "res://scripts/MapScripts.gd"
## scripts/Route15Gate2F.asm - Oak''s aide: the EXP.ALL at 50 owned species.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_SCIENTIST@4,2":
		face_player(npc)
		main.cutscene.oaks_aide("EXP.ALL", 50, "GOT_EXP_ALL",
			"EXP.ALL gives\nEXP points to all\nthe POKéMON with\nyou, even if they\ndon''t fight.\fIt does, however,\nreduce the amount\nof EXP for each\nPOKéMON.\fIf you don''t need\nit, you should\nstore it via PC.")
		return true
	return false