extends "res://scripts/MapScripts.gd"
## scripts/Route23.asm — the badge checkpoints: each latitude needs a specific badge to pass
## north toward the Indigo Plateau. Stepping back onto the road also re-arms Victory Road's boulder
## puzzle (`Route23SetVictoryRoadBoulders`).

# Cell-row Y -> the badge needed to pass north.
const GATES := {
	136: "CASCADEBADGE", 119: "THUNDERBADGE", 105: "RAINBOWBADGE", 96: "SOULBADGE",
	85: "MARSHBADGE", 56: "VOLCANOBADGE", 35: "EARTHBADGE",
}


## Route23SetVictoryRoadBoulders: both of 2F's switches and both of 3F's reset, 3F's boulder goes back to
## (22,15) and 2F's is hidden again — so a second trip through Victory Road is a second solve.
func on_enter() -> void:
	for ev in ["VR2_SWITCH1", "VR2_SWITCH2", "VR3_SWITCH1", "VR3_SWITCH2"]:
		clear_event(ev)
	clear_event("FELL_SPRITE_BOULDER@22,15")      # ShowObject(TOGGLE_VICTORY_ROAD_3F_BOULDER)


func on_step(cell: Vector2i) -> bool:
	# Y=35 only gates the west side (X<14).
	if GATES.has(cell.y) and not (cell.y == 35 and cell.x >= 14):
		var need: String = GATES[cell.y]
		# Route23DefaultScript: each guard checks its badge once (EVENT_PASSED_<badge>_CHECK). Once you've
		# cleared a checkpoint you walk straight through it thereafter (gh #178).
		var passed := "PASSED_%s_CHECK" % need
		if has_event(passed):
			return false
		if need not in main.badges:
			# _Route23YouDontHaveTheBadgeYetText, then a MovePlayerDownScript push-back.
			step_back_down(cell)
			say("You can pass here\nonly if you have\nthe %s!\fYou don't have\nthe %s yet!\fYou have to have\nit to get to\nPOKéMON LEAGUE!" % [need, need])
			return true
		# You have it: the guard inspects the badge and waves you on (Oh-That-Is + GoRightAhead), and marks
		# this checkpoint cleared so he won't stop you again.
		set_event(passed)
		say("You can pass here\nonly if you have\nthe %s!\fOh! That is the\n%s!\fOK then! Please,\ngo right ahead!" % [need, need])
		return true
	return false
