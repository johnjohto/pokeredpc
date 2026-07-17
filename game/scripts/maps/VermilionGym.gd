extends "res://scripts/MapScripts.gd"
## scripts/VermilionGym.asm — the trash-can switch puzzle gating Lt. Surge's motorized door
## (engine/events/hidden_events/vermilion_gym_trash.asm). The switch indices live on Main
## (_trash_first/_trash_second): transient RAM-like state, deliberately unsaved.

# Which cans may hold the 2nd switch given the 1st (GymTrashCans table). Cans index col*3+row
# over a 5x3 grid.
const _TRASH_NEIGHBORS := [
	[1, 3], [0, 2, 4], [1, 5], [0, 4, 6], [1, 3, 5, 7], [2, 4, 8], [3, 7, 9],
	[4, 6, 8, 10], [5, 7, 11], [6, 10, 12], [7, 9, 11, 13], [8, 10, 14], [9, 13],
	[10, 12, 14], [11, 13]]


func on_enter() -> void:
	# Close the motorized door (block 2,2; the .blk ships it open) and reset the trash-can
	# puzzle until it's solved (VermilionGymSetDoorTile).
	if not has_event("VERMILION_2ND_LOCK"):
		clear_event("VERMILION_1ST_LOCK")
		main._trash_first = randi() % 15
		set_block(2, 2, 0x24)


func on_interact(front: Vector2i, _npc) -> bool:
	# A faced trash can, until the door is open.
	if not has_event("VERMILION_2ND_LOCK"):
		var ci := _trash_can_index(front)
		if ci >= 0:
			_trash_check(ci)
			return true
	return false


## Trash-can index for a faced gym tile (x in {1,3,5,7,9}, y in {7,9,11}), or -1 if not a can.
func _trash_can_index(cell: Vector2i) -> int:
	if cell.x in [1, 3, 5, 7, 9] and cell.y in [7, 9, 11]:
		return int((cell.x - 1) / 2) * 3 + int((cell.y - 7) / 2)
	return -1


## Check a trash can (GymTrashScript): find the two hidden switches in sequence to open the
## motorized door to Lt. Surge; a wrong 2nd guess resets them.
func _trash_check(ci: int) -> void:
	if not has_event("VERMILION_1ST_LOCK"):
		if ci == main._trash_first:
			set_event("VERMILION_1ST_LOCK")
			main._trash_second = _TRASH_NEIGHBORS[ci][randi() % _TRASH_NEIGHBORS[ci].size()]
			sfx("switch")
			say("Hey! There's a\nswitch under the\ntrash!\nTurn it on!\fThe 1st electric\nlock opened!")
		else:
			say("Nope, there's\nonly trash here.")
	elif ci == main._trash_second:
		set_event("VERMILION_2ND_LOCK")
		set_block(2, 2, 0x05)                  # the motorized door opens
		sfx("go_inside")
		say("The 2nd electric\nlock opened!\fThe motorized door\nopened!")
	else:
		clear_event("VERMILION_1ST_LOCK")
		main._trash_first = randi() % 15
		sfx("denied")
		say("Nope! There's\nonly trash here.\nHey! The electric\nlocks were reset!")
