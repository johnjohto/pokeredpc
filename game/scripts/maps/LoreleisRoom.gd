extends "res://scripts/MapScripts.gd"
## scripts/LoreleisRoom.asm - the exit seal: walled until Lorelei falls. Loading this room also arms
## `BIT_STARTED_ELITE_4` (LoreleiShowOrHideExitBlock), which is what makes a later trip back down to
## the lobby reset the whole gauntlet — see IndigoPlateauLobby.gd.


func on_enter() -> void:
	set_event("STARTED_ELITE_4")
	e4_exit(Vector2i(5, 2), [[2, 0, 0x24, 0x05]], [Vector2i(4, 0), Vector2i(5, 0)])


func on_battle_end() -> void:
	on_enter()                                # beating Lorelei unseals the exit on the spot
