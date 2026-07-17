extends "res://scripts/MapScripts.gd"
## scripts/RocketHideoutB1F.asm — the guard door: shut until the grunt at (28,18) falls.


func on_enter() -> void:
	guard_door([12, 8, 0x54, 0x0E], [Vector2i(28, 18)])
	# The clunk replays on EVERY entry once the guard falls: the asm meant to SetEvent
	# EVENT_ENTERED_ROCKET_HIDEOUT but only CheckEventHLs it, so the gate never closes
	# (RocketHideoutB1FDoorCallbackScript's documented bug — kept faithfully).
	if defeated(28, 18):
		sfx("go_inside")


func on_battle_end() -> void:
	on_enter()                                # the guard falls -> the door swings open
