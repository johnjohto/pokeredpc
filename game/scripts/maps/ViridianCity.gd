extends "res://scripts/MapScripts.gd"
## scripts/ViridianCity.asm — the sleepy road-blocker north of town (wakes once you have the
## POKéDEX), the awake old man's catching demo, and the gym's badge lock.

## `ViridianCityCheckGymOpenScript`: the gym stays shut until you hold every *other* badge
## (`cp ~(1 << BIT_EARTHBADGE)`), then `EVENT_VIRIDIAN_GYM_OPEN` latches on for good. The
## Gambler at (30,8) is only flavour — nothing physically blocks the door (gh #86).
const OTHER_BADGES := ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
	"SOULBADGE", "MARSHBADGE", "VOLCANOBADGE"]
## The cell below the gym door at (32,7). `ViridianCityMovePlayerDownScript` simulates one PAD_DOWN from
## it, and (32,9) is a **down-ledge** (overworld stand tile 0x2C over ledge tile 0x37), so that press hops
## the player clean over it and back onto the street at (32,10) — it does not walk them into a wall.
const GYM_DOOR_STEP := Vector2i(32, 8)


func on_step(cell: Vector2i) -> bool:
	# The sleepy old man blocks the road north until the player has the Pokédex
	# (ViridianCityCheckGotPokedexScript checks X==19, Y==9).
	if cell == Vector2i(19, 9) and not has_event("GOT_POKEDEX"):
		main.cutscene.viridian_oldman_block()
		return true
	if not has_event("VIRIDIAN_GYM_OPEN"):
		if _has_other_badges():
			set_event("VIRIDIAN_GYM_OPEN")      # latches the moment the seventh badge is in hand
		elif cell == GYM_DOOR_STEP:
			step_back_down(cell)                # one simulated PAD_DOWN -> hopped back down the ledge
			say("The GYM's doors are\nlocked...")
			return true
	return false


func _has_other_badges() -> bool:
	for b in OTHER_BADGES:
		if not main.badges.has(b):
			return false
	return true


func on_interact(_front: Vector2i, npc) -> bool:
	# The awake old man -> the catching demo (BATTLE_TYPE_OLD_MAN).
	if npc != null and npc.key == "SPRITE_GAMBLER@17,5":
		face_player(npc)
		main.cutscene.oldman_demo(npc)
		return true
	return false


func object_shown(k: String) -> Variant:
	# The sleepy road-blocker wakes after his coffee (toggleable_objects.asm: SLEEPY starts ON,
	# the awake old man OFF).
	if k == "SPRITE_GAMBLER_ASLEEP@18,9":
		return not has_event("GOT_POKEDEX")
	if k == "SPRITE_GAMBLER@17,5":
		return has_event("GOT_POKEDEX")
	return null
