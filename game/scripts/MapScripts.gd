extends RefCounted
## Per-map story scripts (docs/engine/map-scripts.md; gh #53). One adapter per scripted map at
## scripts/maps/<MapLabel>.gd, mirroring pokered's scripts/<Map>.asm state machines. Main consults
## the hooks below at fixed touchpoints; unscripted maps get this no-op base. Adapters are
## stateless — durable state lives in main.story_events (saved) — and hold `main` the way pokered
## scripts hold all of WRAM.

var main


# ---- hooks (called by Main; docs/engine/map-scripts.md has the exact call points) ---------------

## After a map finishes loading (warp arrival, connection rebase). Lay script-placed blocks here.
func on_enter() -> void:
	pass


## Each completed player step, before rebase / warps / trainer sight (pokered runs the map script
## first each overworld frame). Return true if a trigger fired (consumes the step).
func on_step(_cell: Vector2i) -> bool:
	return false


## A pressed on the faced cell/NPC, before generic handling (hidden items, Cut, item balls,
## counters, NPC text). Return true if handled. Talking to an NPC? face_player(npc) first.
func on_interact(_front: Vector2i, _npc) -> bool:
	return false


## A warp the player stepped on, before the generic fade + load. Return true if consumed
## (blocked, or replaced by a cutscene beat).
func on_warp(_w: Dictionary, _dest_const: String, _dest_label: String) -> bool:
	return false


## A trainer battle on this map was just won. pokered's EndTrainerBattle (home/trainers.asm) sets
## BIT_CUR_MAP_LOADED_1, which re-runs the map's load callback — so a door the callback places
## opens the instant its last guard falls, without leaving and re-entering. Adapters whose
## on_enter callback is gated on a trainer they own override this to re-run it.
func on_battle_end() -> void:
	pass


## Story-driven object visibility (pokered's toggleable objects): true/false decides,
## null falls through to Main's remaining cases / the default (shown).
func object_shown(_k: String) -> Variant:
	return null


## May a STRENGTH boulder be shoved into this (unwalkable) cell — a Seafoam hole?
## Queried by try_push_boulder before the shove.
func boulder_hole(_cell: Vector2i) -> bool:
	return false


## A STRENGTH boulder just slid onto this cell: floor switches, hole falls.
func on_boulder(_cell: Vector2i, _npc) -> void:
	pass


# ---- the script vocabulary (thin wrappers over Main, so adapters read as script) ----------------

func has_event(ev: String) -> bool:
	return main.has_event(ev)


func set_event(ev: String) -> void:
	main.set_event(ev)


func clear_event(ev: String) -> void:
	main.story_events.erase(ev)


func say(text: String) -> void:
	main._say(text)


func set_block(bx: int, by: int, block_id: int) -> void:
	main.set_block(bx, by, block_id)


func sfx(key: String) -> void:
	if main.audio:
		main.audio.play_sfx(key)


## Turn the player back the way they came (a guard pushing you off a gate cell).
func bounce_back(cell: Vector2i) -> void:
	var fd: Vector2i = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)][main.player.facing]
	main.player.place(cell - fd)


## pokered's `*MovePlayerDownScript` idiom (Viridian City's gym door, Route 23's badge checkpoints):
## face DOWN, then simulate one PAD_DOWN. It is a **step**, not a teleport — collision still applies, so
## the press hops a down-ledge two cells, walks onto open ground, or bumps a wall and leaves the player
## exactly where they stood. Turning it into a `place()` is how you end up inside scenery (gh #86).
func step_back_down(cell: Vector2i) -> void:
	main.player.facing = 0                       # ld [wSpritePlayerStateData1FacingDirection], 0
	var d := Vector2i(0, 1)
	if main.ledge_match(cell, "down", d):
		main.player.place(cell + d * 2)
	elif main.player_can_enter(cell + d):
		main.player.place(cell + d)


func face_player(npc) -> void:
	npc.face_to(main.player.cell)


## pokered's ShowObject / HideObject predefs: flip a toggleable object's visibility right now
## (object_shown decides it at load time; this is the mid-map beat that changes it).
func show_object(k: String) -> void:
	var n = main._npc_by_key(k)
	if n == null:
		return
	# A collected item ball never comes back. pokered gets this from ordering (the ball only exists
	# once its event is set), but a save made before that event existed can reach here holding the item.
	if n.item != "" and main.picked_items.has("%s:%d,%d" % [main.center_label, n.cell.x, n.cell.y]):
		return
	n.set_shown(true)


func hide_object(k: String) -> void:
	var n = main._npc_by_key(k)
	if n != null:
		n.set_shown(false)


## Has the trainer whose home cell is (x, y) on this map been beaten?
func defeated(x: int, y: int) -> bool:
	return main.defeated_trainers.has("%s:%d,%d" % [main.center_label, x, y])


# ---- shared gimmick mechanisms -------------------------------------------------------------------

## Elite Four exit seals (scripts/*Room.asm ShowOrHideExitBlock): the forward exit stays a wall
## (and its warp cells impassable) until the room's member — keyed by home cell — is beaten.
## blocks = [[bx, by, locked, open], ...]; warps = the exit warp cells.
func e4_exit(member: Vector2i, blocks: Array, warps: Array) -> void:
	var beaten := defeated(int(member.x), int(member.y))
	for b in blocks:
		set_block(int(b[0]), int(b[1]), int(b[3] if beaten else b[2]))
	for wc in warps:
		if beaten:
			main._blocked_cells.erase(wc)
		else:
			main._blocked_cells[wc] = true


## Pokémon Mansion switch-door blocks (scripts/PokemonMansion*.asm): swap each row between its
## OFF and ON layout per the shared MANSION_SWITCH_ON flag. rows = [[bx, by, off, on], ...].
func mansion_blocks(rows: Array) -> void:
	var on := has_event("MANSION_SWITCH_ON")
	for e in rows:
		set_block(int(e[0]), int(e[1]), int(e[3]) if on else int(e[2]))


## Press a Mansion switch: toggle the shared flag + re-lay this floor's blocks.
func mansion_switch(rows: Array) -> void:
	if has_event("MANSION_SWITCH_ON"):
		clear_event("MANSION_SWITCH_ON")
	else:
		set_event("MANSION_SWITCH_ON")
	mansion_blocks(rows)
	sfx("go_inside")
	say("A big switch!\fYou flipped the\nswitch!")


## Victory Road floor switches: re-open already-switched doors on load. rows = [{sw, ev, blk}].
func switch_doors_enter(rows: Array) -> void:
	for s in rows:
		if has_event(str(s["ev"])):
			set_block(int(s["blk"][0]), int(s["blk"][1]), int(s["blk"][2]))


## A boulder landed on a floor switch: set its event + open its door for good.
func boulder_switch(cell: Vector2i, rows: Array) -> void:
	for s in rows:
		if cell == s["sw"] and not has_event(str(s["ev"])):
			set_event(str(s["ev"]))
			set_block(int(s["blk"][0]), int(s["blk"][1]), int(s["blk"][2]))
			sfx("go_inside")


## Seafoam boulder holes: is this cell one? holes = [{cell, ev}].
func hole_at(cell: Vector2i, holes: Array) -> bool:
	for h in holes:
		if cell == h["cell"]:
			return true
	return false


## A boulder shoved onto a hole falls to the floor below and is gone for good.
func boulder_falls(cell: Vector2i, npc, holes: Array) -> void:
	for h in holes:
		if cell == h["cell"]:
			set_event(str(h["ev"]))
			set_event("FELL_" + str(npc.key))
			npc.set_shown(false)
			sfx("collision")
			break


## Rocket Hideout guard doors (scripts/RocketHideout*.asm DoorCallbackScript): a door block stays
## a wall until the guarding grunt(s) are beaten. blk = [bx, by, locked, open]; need = the grunts'
## home cells (all must fall). Call from on_enter — the static .blk leaves these open.
## `unlock_ev` gates the open clunk to the first unlock (B4F's EVENT_..._DOOR_UNLOCKED).
func guard_door(blk: Array, need: Array, unlock_ev := "") -> void:
	var open_it := true
	for pos in need:
		if not defeated(int(pos.x), int(pos.y)):
			open_it = false
	if open_it and unlock_ev != "" and not has_event(unlock_ev):
		set_event(unlock_ev)
		sfx("go_inside")
	set_block(int(blk[0]), int(blk[1]), int(blk[3] if open_it else blk[2]))


## The elevator system (engine/events/elevator.asm + overworld/elevator.asm ShakeElevator).
## On entry the two door warps lead back to the boarding floor (StoreWarpEntries); call from
## on_enter.
func elevator_enter() -> void:
	var from: Dictionary = main.warped_from
	if from.is_empty() or int(from.get("warp", 0)) <= 0:
		return
	for w in main.map["warps"]:
		w["dest_map"] = str(from["map"])
		w["dest_warp"] = int(from["warp"])


## The elevator panel (DisplayElevatorFloorMenu): pick a floor from the list, retarget the
## door warps, and shake the car. floors = [[label, dest_map, dest_warp(1-based)], ...];
## B keeps the current destination.
func elevator_panel(floors: Array) -> void:
	main._say_keep("Which floor do\nyou want? ")
	main.menu_mode = "cutscene"
	main.modal = main.menu
	var labels: Array = []
	for f in floors:
		labels.append(str(f[0]))
	main.menu.open(labels, Vector2(32, 16))
	var idx: int = await main.menu.chosen
	main.modal = null
	main.textbox.visible = false
	if idx < 0 or idx >= floors.size():
		return
	for w in main.map["warps"]:
		w["dest_map"] = str(floors[idx][1])
		w["dest_warp"] = int(floors[idx][2])
	await main.shake_elevator()


# Saffron gate guards (scripts/Route5Gate.asm): thirsty, they block the way until handed a drink.
const SAFFRON_DRINKS := ["FRESH WATER", "SODA POP", "LEMONADE"]
const _PUSH_DIR := {Vector2i(0, 1): 0, Vector2i(0, -1): 1, Vector2i(-1, 0): 2, Vector2i(1, 0): 3}


## One drink opens all four gates (GAVE_SAFFRON_GUARDS_DRINK); otherwise pushed back off the
## checkpoint cell, away from Saffron.
func thirsty_guard(cell: Vector2i, push: Vector2i) -> void:
	var drink := ""
	for d in SAFFRON_DRINKS:
		if main.player_bag.has(d):
			drink = d
			break
	if drink != "":
		main.player_bag[drink] = int(main.player_bag[drink]) - 1
		if int(main.player_bag[drink]) <= 0:
			main.player_bag.erase(drink)
		set_event("GAVE_SAFFRON_GUARDS_DRINK")
		say("Yech! That hit\nthe spot!\fThanks! Now I feel\nrefreshed.\fGo right ahead!")
	else:
		# pokered Route5GateDefaultScript: show the thirsty line, THEN a simulated PAD walks the player
		# back one tile — a real walk step, not a teleport, and text-first (gh #113).
		main.cutscene_active = true
		main.modal = null
		await main.cutscene.say("I'm on guard duty.\fGee, I'm thirsty,\nthough!\fSorry, the road's\nclosed.")
		await main.player.step(_PUSH_DIR[push])
		main.cutscene_active = false


## Gen-1 **dungeon warp**: stepping on a hole drops you to the floor below. The holes are *not* tiles —
## each map's script carries an explicit coord list and picks the destination floor from the matched
## index (`IsPlayerOnDungeonWarp` + `wWhichDungeonWarp`; e.g. `PokemonMansion3FDefaultScript`), and the
## landing cell comes from `DungeonWarpData` (data/maps/special_warps.asm). Walking over the *other*
## burnt-floor tiles does nothing, which is why only these exact cells drop you.
## `holes` = [[hole_cell, dest_map, landing_cell], ...]. Returns true if this step fell. Call from
## `on_step`, which runs before warps (gh #85).
func dungeon_hole(cell: Vector2i, holes: Array) -> bool:
	for h in holes:
		if cell == h[0]:
			main.cutscene.fall_down_hole(str(h[1]), h[2])
			return true
	return false


## Silph Co card-key doors (scripts/SilphCo*.asm GateCallbackScript): lay the floor's locked door
## blocks on load unless already unlocked. rows = [[block_x, block_y, locked_block], ...].
func place_silph_doors(rows: Array) -> void:
	for d in rows:
		if not has_event("SILPH_DOOR_%s_%d_%d" % [main.center_label, d[0], d[1]]):
			set_block(int(d[0]), int(d[1]), int(d[2]))


## Facing a Silph door block: the CARD KEY opens it for good (the event is saved), else refused.
## Returns true if the faced block was a still-locked door.
func silph_door_interact(front: Vector2i, rows: Array, open_block: int) -> bool:
	var bx := front.x / 2
	var by := front.y / 2
	var is_door := false
	for d in rows:
		if int(d[0]) == bx and int(d[1]) == by:
			is_door = true
			break
	var dev := "SILPH_DOOR_%s_%d_%d" % [main.center_label, bx, by]
	if not is_door or has_event(dev):
		return false
	if main.player_bag.has("CARD KEY"):
		set_event(dev)
		set_block(bx, by, open_block)
		sfx("go_inside")
		say("Bingo!\fThe CARD KEY\nopened the door!")
	else:
		say("Darn! It needs a\nCARD KEY!")
	return true
