extends "res://scripts/MapScripts.gd"
## scripts/MtMoonB2F.asm — the SUPER NERD who guards the two fossils, and picking one (the other is lost).
##
## The Super Nerd (12,8, facing RIGHT) has **no line of sight** — pokered engages him from a coordinate
## trigger, not a sight cone. `MtMoonB2FDefaultScript` force-runs `TEXT_MTMOONB2F_SUPER_NERD` the moment you
## stand on (13,8), and (13,8) is the *sole* gateway up into the fossil alcove: (12,8) is the nerd himself
## and (12,9)/(13,9) are the only openings from the south, so every route to the fossils crosses it. Without
## that trigger the nerd just stands there and you walk straight past him and take a fossil for free (gh #107).

const NERD_KEY := "SPRITE_SUPER_NERD@12,8"
# MtMoonB2FSuperNerdText: the "both mine!" taunt (before-battle) and "OK! I'll share!" concession (end).
const NERD_BATTLE := "Hey, stop!\fI found these\nfossils! They're\nboth mine!"
const NERD_END := "OK!\nI'll share!"


func on_enter() -> void:
	# The nerd's lines live in the map script, not a trainer header, so the extractor gave him no
	# before/after text — wire it here so the forced fight (and a plain talk-to) both read right.
	var nerd = main._npc_by_key(NERD_KEY)
	if nerd != null:
		nerd.battle_text = NERD_BATTLE
		nerd.end_text = NERD_END


func on_step(cell: Vector2i) -> bool:
	# MtMoonB2FDefaultScript rets early once the nerd is beaten; nothing below re-fires afterward.
	if defeated(12, 8):
		return false
	# (13,8) is the one tile the fossil alcove can be entered from — stepping onto it makes the nerd engage.
	if cell == Vector2i(13, 8):
		var nerd = main._npc_by_key(NERD_KEY)
		if nerd != null and nerd.shown:
			face_player(nerd)
			main.cutscene.trainer_battle(nerd, false)
			return true
	return false


func on_interact(_front: Vector2i, npc) -> bool:
	if npc == null:
		return false
	# The beaten nerd's parting line depends on whether a fossil has been taken (MtMoonB2FSuperNerdText).
	if npc.key == NERD_KEY and defeated(12, 8):
		face_player(npc)
		if has_event("GOT_DOME_FOSSIL") or has_event("GOT_HELIX_FOSSIL"):
			say("Far away, on\nCINNABAR ISLAND,\nthere's a POKéMON\nLAB.\fThey do research\non regenerating\nfossils.")
		else:
			say("We'll each take\none!\nNo being greedy!")
		return true
	if npc.key == "SPRITE_FOSSIL@12,6":
		face_player(npc)
		main.cutscene.mtmoon_fossil("DOME FOSSIL", "GOT_DOME_FOSSIL", npc, "SPRITE_FOSSIL@13,6")
		return true
	if npc.key == "SPRITE_FOSSIL@13,6":
		face_player(npc)
		main.cutscene.mtmoon_fossil("HELIX FOSSIL", "GOT_HELIX_FOSSIL", npc, "SPRITE_FOSSIL@12,6")
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_FOSSIL@12,6" or k == "SPRITE_FOSSIL@13,6":
		return not (has_event("GOT_DOME_FOSSIL") or has_event("GOT_HELIX_FOSSIL"))
	return null
