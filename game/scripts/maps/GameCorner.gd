extends "res://scripts/MapScripts.gd"
## scripts/GameCorner.asm — the ROCKET guarding the poster, the poster switch hiding the Rocket
## Hideout staircase, the slot machines (engine/slots/game_corner_slots.asm), and the coin clerk /
## coin-gift guru. The lucky machine (main._lucky_slot) is transient RAM-like state, re-rolled
## each visit.

## `object_event 9, 5, SPRITE_ROCKET, STAY, UP, ..., OPP_ROCKET, 7`, shipped ON by
## toggleable_objects.asm. He stands on (9,5) — the *only* walkable cell adjacent to the poster
## at (9,4), which is a wall tile — and STAYs facing UP into it, so he never engages on sight.
## Reading the poster therefore means talking to him and beating him first.
const ROCKET := "SPRITE_ROCKET@9,5"

# Slot-machine seats (data/events/hidden_events.asm, GAME_CORNER). The player stands on a
# seat and presses A to play. Three seats are unplayable (out of order, etc.).
const SLOT_SEATS := [
	Vector2i(1, 10), Vector2i(1, 11), Vector2i(1, 12), Vector2i(1, 13), Vector2i(1, 14), Vector2i(1, 15),
	Vector2i(6, 10), Vector2i(6, 11), Vector2i(6, 13), Vector2i(6, 14), Vector2i(6, 15),
	Vector2i(7, 10), Vector2i(7, 11), Vector2i(7, 12), Vector2i(7, 13), Vector2i(7, 14), Vector2i(7, 15),
	Vector2i(12, 10), Vector2i(12, 11), Vector2i(12, 12), Vector2i(12, 13), Vector2i(12, 14), Vector2i(12, 15),
	Vector2i(13, 10), Vector2i(13, 11), Vector2i(13, 13), Vector2i(13, 14), Vector2i(13, 15),
	Vector2i(18, 11), Vector2i(18, 12), Vector2i(18, 13), Vector2i(18, 14), Vector2i(18, 15),
]
const SLOT_SEATS_BROKEN := {
	Vector2i(6, 12): "OUT OF ORDER\nThis is broken.",
	Vector2i(13, 12): "OUT TO LUNCH\nThis is reserved.",
	Vector2i(18, 10): "Someone's keys!\nThey'll be back.",
}


func on_enter() -> void:
	# The staircase to the Rocket Hideout stays hidden (a wall) until the poster switch is
	# found (GameCornerSetRocketHideoutDoorTile).
	if not has_event("FOUND_ROCKET_HIDEOUT"):
		set_block(8, 2, 0x2A)
		main._blocked_cells[Vector2i(17, 4)] = true   # can't reach the warp until the switch is found
	main._lucky_slot = SLOT_SEATS[randi() % SLOT_SEATS.size()]   # GameCornerSelectLuckySlotMachine


func on_battle_end() -> void:
	# GameCornerRocketBattleScript: losing sends him walking off (MoveSprite), and
	# GameCornerRocketExitScript then hides him for good (HideObject TOGGLE_GAME_CORNER_ROCKET).
	# The walk is animation; what matters is that (9,5) is freed, because it is the one cell the
	# poster can be read from. Without this he stands there forever and the Rocket Hideout — and so
	# the SILPH SCOPE, and so the rest of the game — is unreachable on foot (gh #89).
	if defeated(9, 5):
		hide_object(ROCKET)


func object_shown(k: String) -> Variant:
	if k == ROCKET:
		return not defeated(9, 5)                     # he leaves after his battle and never returns
	return null


func on_interact(front: Vector2i, npc) -> bool:
	# The poster: a hidden switch opens the staircase to the Rocket Hideout.
	if front == Vector2i(9, 4) and not has_event("FOUND_ROCKET_HIDEOUT"):
		sfx("go_inside")
		set_event("FOUND_ROCKET_HIDEOUT")
		set_block(8, 2, 0x43)
		main._blocked_cells.erase(Vector2i(17, 4))
		say("Hey!\fA switch behind\nthe poster!?\nLet's push it!")
		return true
	# Slot machines (hidden_event StartSlotMachine): stand at a seat, press A.
	if main.player.cell in SLOT_SEATS:
		_play_slots(main.player.cell)
		return true
	if SLOT_SEATS_BROKEN.has(main.player.cell):
		say(SLOT_SEATS_BROKEN[main.player.cell])
		return true
	if npc == null:
		return false
	# Coin clerk -> buy 50 coins for ¥1000; the fishing guru -> 10 free coins (once).
	if npc.key == "SPRITE_CLERK@5,6":
		face_player(npc)
		main.cutscene.coin_clerk()
		return true
	if npc.key == "SPRITE_FISHING_GURU@5,11":
		face_player(npc)
		main.cutscene.coin_gift()
		return true
	return false


## Sit at a slot machine (StartSlotMachine).
func _play_slots(cell: Vector2i) -> void:
	if not main.player_bag.has("COIN CASE"):       # AbleToPlaySlotsCheck
		say("A COIN CASE is\nrequired!")
		return
	if main.player_coins <= 0:
		say("You don't have\nany coins!")
		return
	main.modal = main.slots
	main.slots.start(cell == main._lucky_slot)
