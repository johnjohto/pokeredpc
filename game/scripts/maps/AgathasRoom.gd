extends "res://scripts/MapScripts.gd"
## scripts/AgathasRoom.asm - the exit seal: walled until Agatha falls. Beating her also arms the
## Champion's room entry script (`AgathasRoomAgathaEndBattleScript`: `ld a,
## SCRIPT_CHAMPIONSROOM_PLAYER_ENTERS`), so the last battle starts as you walk in.


func on_enter() -> void:
	e4_exit(Vector2i(5, 2), [[2, 0, 0x3B, 0x0E]], [Vector2i(4, 0), Vector2i(5, 0)])


func on_battle_end() -> void:
	on_enter()                                # beating Agatha unseals the exit on the spot
	if defeated(5, 2):
		set_event("CHAMPION_ROOM_ENTRY")
