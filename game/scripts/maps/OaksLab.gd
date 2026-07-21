extends "res://scripts/MapScripts.gd"
## scripts/OaksLab.asm — the opening quest: the don't-leave guard, the starter balls, the first
## rival battle trigger, parcel delivery, and the lab cast's story-driven lines + visibility.

const _STARTER_BALL_SPECIES := {
	"SPRITE_POKE_BALL@6,3": "charmander",
	"SPRITE_POKE_BALL@7,3": "squirtle",
	"SPRITE_POKE_BALL@8,3": "bulbasaur",
}


func on_step(cell: Vector2i) -> bool:
	# Trying to leave before choosing a starter: Oak stops you and walks you back up
	# (OaksLabPlayerDontGoAwayScript checks YCoord == 6).
	if cell.y == 6 and has_event("OAK_ASKED_TO_CHOOSE_MON") and not has_event("GOT_STARTER"):
		main.cutscene.oak_dont_go_away()
		return true
	# Heading for the exit after getting a starter triggers the rival's challenge
	# (OaksLabRivalChallengesPlayerScript checks YCoord == 6).
	if cell.y == 6 and has_event("GOT_STARTER") and not has_event("BEAT_RIVAL1"):
		main.cutscene.rival_challenge()
		return true
	return false


func on_interact(_front: Vector2i, npc) -> bool:
	if npc == null:
		return false
	face_player(npc)
	# A starter ball: "those are POKé BALLs" before the choose-mon speech
	# (OaksLabThoseArePokeBallsText), the pick menu after it, the untaken leftover once picked
	# (OaksLabLastMonScript).
	if npc.key.begins_with("SPRITE_POKE_BALL@"):
		if not has_event("OAK_ASKED_TO_CHOOSE_MON"):
			say("Those are POKé\nBALLs. They\ncontain POKéMON!")
		elif not has_event("GOT_STARTER"):
			main.cutscene.choose_starter(npc)
		else:
			say("That's PROF.OAK's\nlast POKéMON!")
		return true
	# Oak: deliver the parcel (-> Pokédex), else his full OaksLabOak1Text branch tree.
	if npc.key == "SPRITE_OAK@5,2":
		if has_event("GOT_OAKS_PARCEL") and not has_event("OAK_GOT_PARCEL"):
			main.cutscene.deliver_parcel()
		else:
			_oak_talk()
		return true
	# The rival: talking always shows a line; his battle is positional (rival_challenge).
	if npc.key == "SPRITE_BLUE@4,3":
		say(_rival_text())
		return true
	return false


func object_shown(k: String) -> Variant:
	match k:
		"SPRITE_OAK@5,2":  return has_event("FOLLOWED_OAK_INTO_LAB")   # front Oak (choose-mon)
		"SPRITE_OAK@5,10": return false                                # entry Oak (cutscene only)
		"SPRITE_BLUE@4,3": return not has_event("RIVAL_LEFT_LAB")      # rival
		"SPRITE_POKE_BALL@6,3", "SPRITE_POKE_BALL@7,3", "SPRITE_POKE_BALL@8,3":
			if not has_event("GOT_STARTER"):
				return true                      # all three until someone picks
			var sp: String = _STARTER_BALL_SPECIES.get(k, "")   # the untaken one stays on the table
			return sp != main.player_starter and sp != main.rival_starter
		"SPRITE_POKEDEX@2,1", "SPRITE_POKEDEX@3,1":
			return not has_event("GOT_POKEDEX")   # on the shelf until Oak hands them out
	return null


## Oak's dialog (OaksLabOak1Text), the asm's exact branch order: the dex rating once the
## collection is going (PALLET_AFTER_GETTING_POKEBALLS, or >=2 owned with the dex), then —
## only with NO POKé BALLs in the bag — the one-time 5-ball gift after the Route 22 rival,
## else the story-progress lines (parcel delivery is handled before this in on_interact).
func _oak_talk() -> void:
	main._sync_owned()
	if has_event("PALLET_AFTER_GETTING_POKEBALLS") \
			or (main.pokedex_owned.size() >= 2 and has_event("GOT_POKEDEX")):
		# .HowIsYourPokedexComingText ends in `prompt` and the rating prints straight
		# after it (wDoNotWaitForButtonPressAfterDisplayingText) — one flowing text.
		main.oaks_dex_rating("OAK: Good to see\nyou! How is your\nPOKéDEX coming?\nHere, let me take\na look!\f")
	elif int(main.player_bag.get("POKé BALL", 0)) > 0:
		_oak_come_see_me()
	elif has_event("BEAT_ROUTE22_RIVAL_1"):
		if has_event("GOT_POKEBALLS_FROM_OAK"):
			_oak_come_see_me()
		else:
			set_event("GOT_POKEBALLS_FROM_OAK")
			_oak_give_balls()
	elif has_event("GOT_POKEDEX"):
		say("POKéMON around the\nworld wait for\nyou, %s!" % main.player_name)
	elif has_event("BEAT_RIVAL1"):
		say("OAK: %s,\nraise your young\nPOKéMON by making\nit fight!" % main.player_name)
	elif has_event("GOT_STARTER"):
		say("OAK: If a wild\nPOKéMON appears,\nyour POKéMON can\nfight against it!")
	else:
		say("OAK: Now, %s,\nwhich POKéMON do\nyou want?" % main.player_name)


func _oak_come_see_me() -> void:
	say("OAK: Come see me\nsometimes.\fI want to know how\nyour POKéDEX is\ncoming along.")


## The line _oak_talk would open with — a pure preview for the test harness (gh #45:
## --oaktest/--parceltest log it; keep the branch order in sync with _oak_talk).
func _oak_text() -> String:
	main._sync_owned()
	if has_event("PALLET_AFTER_GETTING_POKEBALLS") \
			or (main.pokedex_owned.size() >= 2 and has_event("GOT_POKEDEX")):
		return "OAK: Good to see\nyou! How is your\nPOKéDEX coming?\nHere, let me take\na look!"
	if int(main.player_bag.get("POKé BALL", 0)) > 0:
		return "OAK: Come see me\nsometimes.\fI want to know how\nyour POKéDEX is\ncoming along."
	if has_event("BEAT_ROUTE22_RIVAL_1"):
		if has_event("GOT_POKEBALLS_FROM_OAK"):
			return "OAK: Come see me\nsometimes.\fI want to know how\nyour POKéDEX is\ncoming along."
		return "OAK: You can't get\ndetailed data on\nPOKéMON by just\nseeing them."
	if has_event("GOT_POKEDEX"):
		return "POKéMON around the\nworld wait for\nyou, %s!" % main.player_name
	if has_event("BEAT_RIVAL1"):
		return "OAK: %s,\nraise your young\nPOKéMON by making\nit fight!" % main.player_name
	if has_event("GOT_STARTER"):
		return "OAK: If a wild\nPOKéMON appears,\nyour POKéMON can\nfight against it!"
	return "OAK: Now, %s,\nwhich POKéMON do\nyou want?" % main.player_name


## .give_poke_balls — 5 POKé BALLs once (EVENT_GOT_POKEBALLS_FROM_OAK), the get-key-item
## fanfare on the "got" line, then the catching explanation.
func _oak_give_balls() -> void:
	main.cutscene_active = true
	await main.cutscene.say("OAK: You can't get\ndetailed data on\nPOKéMON by just\nseeing them.\fYou must catch\nthem! Use these\nto capture wild\nPOKéMON.")
	main.add_item("POKé BALL", 5)
	if main.audio:
		main.audio.play_sfx("get_key_item")
	await main.cutscene.say("%s got 5\nPOKé BALLs!" % main.player_name)
	await main.cutscene.say("When a wild\nPOKéMON appears,\nit's fair game.\fJust throw a POKé\nBALL at it and try\nto catch it!\fThis won't always\nwork, though.\fA healthy POKéMON\ncould escape. You\nhave to be lucky!")
	main.cutscene_active = false


## The rival's line (OaksLabRivalText): before Oak's speech / before & after picking a starter.
func _rival_text() -> String:
	if not has_event("FOLLOWED_OAK_INTO_LAB_2"):
		return "%s: Yo\n%s! Gramps\nisn't around!" % [main.rival_name, main.player_name]
	if not has_event("GOT_STARTER"):
		return "%s: Heh, I\ndon't need to be\ngreedy like you!\fGo ahead and\nchoose, %s!" % [main.rival_name, main.player_name]
	return "%s: My\nPOKéMON looks a\nlot stronger." % main.rival_name
