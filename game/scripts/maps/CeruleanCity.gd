extends "res://scripts/MapScripts.gd"
## scripts/CeruleanCity.asm — the north-bridge rival ambush, the beaten Rocket who returns the stolen
## TM28 (DIG), and the two police guards on the trashed house: GUARD2 (27,12) blocks the door until you
## get the S.S.TICKET from Bill, then it's swapped for GUARD1 (28,12) — the only on-foot route from the
## gym side to Route 5 runs through that house (BillsHouse.asm toggles the guards on GOT_SS_TICKET).


func on_step(cell: Vector2i) -> bool:
	# The rival ambushes the player by the north bridge (CeruleanCityCoords2 = (20,6)/(21,6)).
	if (cell == Vector2i(20, 6) or cell == Vector2i(21, 6)) and not has_event("BEAT_CERULEAN_RIVAL"):
		main.cutscene.cerulean_rival()
		return true
	return false


func on_interact(_front: Vector2i, npc) -> bool:
	# The Rocket returns TM_DIG once, after you beat him (#12). Undefeated, he battles through
	# the generic trainer path (fall through).
	if npc != null and npc.key == "SPRITE_ROCKET@30,8" and defeated(30, 8) and not has_event("GOT_TM28"):
		face_player(npc)
		var tm: String = str(main.item_names.get("TM_DIG", "TM28"))
		main.player_bag[tm] = int(main.player_bag.get(tm, 0)) + 1
		set_event("GOT_TM28")
		sfx("get_item1")
		say("I'll return the\nTM I stole!\f%s received\n%s!" % [main.player_name, tm])
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_BLUE@20,2":
		return false                                 # rival appears only for the bridge battle cutscene
	if k == "SPRITE_GUARD@27,12":
		return not has_event("GOT_SS_TICKET")        # GUARD2 blocks the trashed-house door until the ticket
	if k == "SPRITE_GUARD@28,12":
		return has_event("GOT_SS_TICKET")            # GUARD1 hidden until then (pokered toggle swap)
	if k == "SPRITE_SUPER_NERD@4,12":
		# CERULEANCITY_SUPER_NERD3 ships ON and STAYs on (4,12), the one land cell touching the
		# CERULEAN_CAVE_1F door at (4,11) — you SURF up to him, and he tells you how strong the
		# POKéMON inside are. HallOfFame.asm hides him (TOGGLE_CERULEAN_CAVE_GUY) the moment you are
		# recorded as CHAMPION; until then the cave, and MEWTWO, are closed. (gh #90.)
		return not has_event("HALL_OF_FAME")
	return null
