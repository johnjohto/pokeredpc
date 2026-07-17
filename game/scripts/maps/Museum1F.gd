extends "res://scripts/MapScripts.gd"
## scripts/Museum1F.asm — the ticket receptionist gating the exhibit (Museum1FDefaultScript +
## Museum1FScientist1Text) and the side-room scientist who hands over the OLD AMBER.


func on_step(cell: Vector2i) -> bool:
	# Walking up the entrance aisle to the counter fires the receptionist
	# (Museum1FDefaultScript checks Y==4, X==9/10) — the ¥50 gate, or her
	# "take plenty of time" wave-through once the ticket is bought.
	if cell == Vector2i(9, 4) or cell == Vector2i(10, 4):
		main.cutscene.museum_ticket()
		return true
	return false


func on_interact(_front: Vector2i, npc) -> bool:
	if npc == null:
		return false
	# The receptionist (Museum1FScientist1Text): what she says depends on which side of the
	# counter you stand on.
	if npc.key == "SPRITE_SCIENTIST@12,4":
		face_player(npc)
		var pc: Vector2i = main.player.cell
		if pc == Vector2i(13, 4) or pc == Vector2i(12, 3):
			main.cutscene.museum_amber_chat()      # snuck in the back way
		elif pc.y == 4:
			main.cutscene.museum_ticket()          # at the counter front: the ticket flow
		elif has_event("BOUGHT_MUSEUM_TICKET"):
			say("Take plenty of\ntime to look!")
		else:
			say("Please go to the\nother side!")
		return true
	# The side-room scientist: the OLD AMBER.
	if npc.key == "SPRITE_SCIENTIST@15,2":
		face_player(npc)
		main.cutscene.give_old_amber()
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_OLD_AMBER@16,2":
		return not has_event("GOT_OLD_AMBER")
	return null
