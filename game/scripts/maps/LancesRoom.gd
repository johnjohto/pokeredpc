extends "res://scripts/MapScripts.gd"
## scripts/LancesRoom.asm — the doorway into LANCE's hall, and the door that shuts behind you.
##
## The static `.blk` ships that doorway **closed** (blocks `0x72`/`0x73` at block (2,6)/(3,6) — cells
## (4..7, 12..13)), and `LanceShowOrHideEntranceBlocks` opens it (`0x31`/`0x32`) on every map load until
## `EVENT_LANCES_ROOM_LOCK_DOOR` is set. Without that load hook the whole hall — LANCE, the CHAMPION and
## the HALL OF FAME — is walled off from the entrance staircase at (24,16) (gh #88).
##
## Stepping into the hall at (5,11)/(6,11) latches the event and slams the door, so the challenge cannot
## be abandoned mid-way. The lock is undone by `IndigoPlateauLobby`, which resets the whole Elite Four
## event range whenever you come back down — that is what makes a whiteout recoverable.

const OPEN := [[2, 6, 0x31], [3, 6, 0x32]]        # LanceShowOrHideEntranceBlocks: ld a, $31 / ld b, $32
const SHUT := [[2, 6, 0x72], [3, 6, 0x73]]        #                       .closeEntrance: $72 / $73


func on_enter() -> void:
	for b in (SHUT if has_event("LANCES_ROOM_LOCK_DOOR") else OPEN):
		set_block(int(b[0]), int(b[1]), int(b[2]))


func on_step(cell: Vector2i) -> bool:
	# LancesRoomDefaultScript rets early once LANCE is beaten, so nothing below re-fires on a champion.
	if defeated(6, 1):
		return false
	# Coords 1 and 2: standing beside LANCE starts the fight. He has view range 0 and the hall runs
	# straight past him to the Champion's stairs, so without this he is simply skippable.
	if cell == Vector2i(5, 1) or cell == Vector2i(6, 2):
		var lance = main._npc_by_key("SPRITE_LANCE@6,1")
		if lance != null and lance.shown:
			face_player(lance)
			main.cutscene.trainer_battle(lance, false)
			return true
	# Coords 3 and 4: the two cells just inside the hall — the doorway slams behind you.
	if (cell == Vector2i(5, 11) or cell == Vector2i(6, 11)) and not has_event("LANCES_ROOM_LOCK_DOOR"):
		set_event("LANCES_ROOM_LOCK_DOOR")
		sfx("go_inside")
		on_enter()
	return false
