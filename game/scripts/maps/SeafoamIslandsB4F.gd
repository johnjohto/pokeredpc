extends "res://scripts/MapScripts.gd"
## scripts/SeafoamIslandsB4F.asm - the strong currents: once the boulders block the flow,
## these tiles sweep a surfing player along a forced route (dir 1=UP, 3=RIGHT). The landing
## current (needs the B2F boulders -> SEAFOAM3) pushes you up out of the fall spot; the
## crossing current (needs the B3F boulders -> SEAFOAM4) carries you toward Articuno.

const CURRENTS := {
	Vector2i(20, 17): {"g": "SEAFOAM3", "seq": [[1, 2]]},
	Vector2i(21, 17): {"g": "SEAFOAM3", "seq": [[1, 2]]},
	Vector2i(20, 16): {"g": "SEAFOAM3", "seq": [[1, 2]]},
	Vector2i(21, 16): {"g": "SEAFOAM3", "seq": [[1, 1]]},
	Vector2i(4, 14): {"g": "SEAFOAM4", "seq": [[1, 3], [3, 2], [1, 1]]},
	Vector2i(5, 14): {"g": "SEAFOAM4", "seq": [[1, 3], [3, 3], [1, 1]]},
}


func on_step(cell: Vector2i) -> bool:
	if main.surfing and CURRENTS.has(cell):
		var cur: Dictionary = CURRENTS[cell]
		if has_event(str(cur["g"]) + "_BOULDER1_DOWN_HOLE") and has_event(str(cur["g"]) + "_BOULDER2_DOWN_HOLE"):
			_current(cur["seq"])
			return true
	return false


## Sweep the surfing player along: forced runs of [dir, count] (walk_forward stops at walls).
func _current(seq: Array) -> void:
	main.cutscene_active = true
	main.modal = null
	for st in seq:
		await main.cutscene.walk_forward(main.player, int(st[0]), int(st[1]))
	main.cutscene_active = false