extends "res://scripts/MapScripts.gd"
## scripts/RocketHideoutB4F.asm — the two-grunt door guarding Giovanni, and Giovanni himself:
## he guards the SILPH SCOPE, then steps aside once beaten. Both key balls ship hidden
## (toggleable_objects.asm: ROCKETHIDEOUTB4F_LIFT_KEY / _SILPH_SCOPE are OFF) — the beats below
## are what put them on the floor.

const GIOVANNI := "SPRITE_GIOVANNI@25,3"
const ROCKET_3 := "SPRITE_ROCKET@11,2"             # the grunt who lost the LIFT KEY
const LIFT_KEY_BALL := "SPRITE_POKE_BALL@10,2"     # ITEM_5 — dropped by Rocket 3 at (11,2)
const SILPH_SCOPE_BALL := "SPRITE_POKE_BALL@25,2"  # ITEM_4 — left behind by Giovanni at (25,3)


func on_enter() -> void:
	guard_door([12, 5, 0x2D, 0x0E], [Vector2i(23, 12), Vector2i(26, 12)],
		"ROCKET_HIDEOUT_B4F_DOOR_UNLOCKED")   # the clunk plays once (EVENT_..._4_DOOR_UNLOCKED)


func on_battle_end() -> void:
	on_enter()                                # the second guard falls -> the door swings open


func on_interact(_front: Vector2i, npc) -> bool:
	if npc == null:
		return false
	if npc.key == GIOVANNI and not has_event("BEAT_ROCKET_HIDEOUT_GIOVANNI"):
		face_player(npc)
		main.cutscene.giovanni_hideout()
		return true
	# Beaten, Rocket 3 lets slip that he dropped the LIFT KEY — which is what puts the ball on the
	# floor beside him (RocketHideoutB4FRocket3AfterBattleText: PrintText, then CheckAndSetEvent
	# EVENT_ROCKET_DROPPED_LIFT_KEY -> ShowObject ITEM_5). The reveal waits on the text, so it's a beat.
	if npc.key == ROCKET_3 and defeated(11, 2) and not has_event("ROCKET_DROPPED_LIFT_KEY"):
		face_player(npc)
		main.cutscene.rocket_drops_lift_key(npc)
		return true
	return false


func object_shown(k: String) -> Variant:
	match k:
		GIOVANNI:
			return not has_event("BEAT_ROCKET_HIDEOUT_GIOVANNI")   # Giovanni steps aside
		LIFT_KEY_BALL:
			return has_event("ROCKET_DROPPED_LIFT_KEY")
		SILPH_SCOPE_BALL:
			return has_event("BEAT_ROCKET_HIDEOUT_GIOVANNI")
	return null
