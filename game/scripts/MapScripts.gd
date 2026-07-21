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


# (The shared gimmick mechanisms — thirsty_guard, mansion_blocks/mansion_switch,
# elevator_enter/elevator_panel, the Silph card-key door pair, e4_exit, guard_door,
# switch_doors_enter/boulder_switch, hole_at/boulder_falls, and dungeon_hole — migrated
# into authored events + the Event VM's command vocabulary with their maps, gh #40.)
