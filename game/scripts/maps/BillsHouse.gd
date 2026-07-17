extends "res://scripts/MapScripts.gd"
## scripts/BillsHouse.asm — Bill-as-a-POKéMON, the cell-separator PC, and the real Bill's
## S.S.TICKET, with the story-driven visibility swaps between his three forms.


func on_interact(front: Vector2i, npc) -> bool:
	# The cell-separator PC (hidden_event at 1,4 facing UP).
	if front == Vector2i(1, 4) and main.player.facing == 1:
		if has_event("BILL_SAID_USE_CELL_SEPARATOR") and not has_event("USED_CELL_SEPARATOR_ON_BILL"):
			main.cutscene.bill_separator()
		else:
			say("TELEPORTER is\ndisplayed on the\nPC monitor.")
		return true
	if npc == null:
		return false
	# Bill-as-a-POKéMON starts the cell-separator event; the real Bill gives the ticket.
	if npc.key == "SPRITE_MONSTER@6,5":
		face_player(npc)
		main.cutscene.bill_intro()
		return true
	if npc.key == "SPRITE_SUPER_NERD@4,4":
		face_player(npc)
		main.cutscene.bill_ticket()
		return true
	return false


func object_shown(k: String) -> Variant:
	match k:
		"SPRITE_MONSTER@6,5":    return not has_event("BILL_SAID_USE_CELL_SEPARATOR")  # Bill-as-mon
		"SPRITE_SUPER_NERD@4,4": return has_event("USED_CELL_SEPARATOR_ON_BILL")        # real Bill
		"SPRITE_SUPER_NERD@6,5": return false                                           # post-game Bill
	return null
