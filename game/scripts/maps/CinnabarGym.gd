extends "res://scripts/MapScripts.gd"
## scripts/CinnabarGym.asm - the six quiz gates (cinnabar_gym_quiz.asm CinnabarGymGateCoords):
## close unanswered gates on load, open the answered ones. The quiz machines themselves are
## HIDDEN_EVENTS (generic) firing Cutscene.cinnabar_quiz.

const GATES := [[9, 3, 0x54], [6, 3, 0x54], [6, 6, 0x54], [3, 8, 0x5F],
	[2, 6, 0x54], [2, 3, 0x54]]


func on_enter() -> void:
	for i in 6:
		var gt: Array = GATES[i]
		set_block(int(gt[0]), int(gt[1]),
			0xE if has_event("CINNABAR_GATE_%d" % (i + 1)) else int(gt[2]))