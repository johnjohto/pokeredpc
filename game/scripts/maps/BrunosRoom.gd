extends "res://scripts/MapScripts.gd"
## scripts/BrunosRoom.asm - the exit seal: walled until Bruno falls.


func on_enter() -> void:
	e4_exit(Vector2i(5, 2), [[2, 0, 0x24, 0x05]], [Vector2i(4, 0), Vector2i(5, 0)])


func on_battle_end() -> void:
	on_enter()                                # beating Bruno unseals the exit on the spot