extends RefCounted
class_name EventVM
## The Event VM (ADR-019, gh #39/#40): interprets a project's authored event records —
## a declarative trigger + a nested-block command list (core/schemas/event.schema.json,
## the Core "Event-VM defs") — over the same await primitives Cutscene beats use, so one
## event runs at a time behind `cutscene_active` and events stay atomic w.r.t. saves.
## Durable state is story flags (+ the vars store when a beat demands one); event names
## stay byte-exact with v1's — they are the save format.
##
## `load_all` indexes triggers per map at boot and REFUSES any trigger kind, command, or
## condition it cannot execute — the schema's enums and this interpreter move together
## (ADR-019 §6: each command lands with the Kanto beat that demands it, never ahead).
## `visible` triggers are load-time queries (`visible_for`), never command runs
## (plan §6 risk 7: no VM in per-frame surfaces); `step` dispatch is indexed by
## `(map, cell)` at load, so the overworld loop only ever hashes the stepped cell.

var main

var maps := {}           # map label -> true (any event targets this map)
var _by_interact := {}   # "<label>|<object key>" -> [records] (id order)
var _by_front := {}      # "<label>|<x>,<y>"      -> [records] (faced-cell interactions)
var _by_visible := {}    # "<label>|<object key>" -> event record
var _by_step := {}       # "<label>|<x>,<y>"      -> [records]
var _by_enter := {}      # "<label>"              -> [records]
var _by_battle_end := {} # "<label>"              -> [records]
var _by_bhole := {}      # "<label>|<x>,<y>"      -> true (a boulder may be shoved in)
var _by_boulder := {}    # "<label>|<x>,<y>"      -> [records] (a boulder landed here)

const KINDS := ["interact", "visible", "enter", "step", "battle_end", "boulder_hole", "boulder"]
const CMDS := ["say", "notice", "if", "give_item", "take_item", "set_flag", "clear_flag", "sfx",
	"beat", "set_last_map", "set_block", "set_force_bike", "mount_bike",
	"bounce_back", "step_back_down", "walk_player", "vending", "fall_hole",
	"elevator_retarget", "elevator_panel", "block_cell", "unblock_cell",
	"trainer_battle", "reset_elite4", "boulder_fall", "walk_forward"]

## Player facing indices (Player.facing) by direction word.
const DIRS := {"down": 0, "up": 1, "left": 2, "right": 3}
const _FACING_VEC := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]

## `beat` invokes a native Cutscene beat by name (the strangler-fig seam: wave C dissolves
## story beats into commands; ceremonies stay native forever). Validated against the
## script, not the instance — load_all may run before Main builds its Cutscene.
const _CUTSCENE_SCRIPT := preload("res://scripts/Cutscene.gd")
static var _beat_names := {}


## Index every record (basename -> record, from ProjectData.events()). Returns "" or the
## boot-fatal error naming the record — a project asking for semantics this build lacks
## must refuse loudly at load, the ADR-017 refuse-newer pattern applied to events.
func load_all(records: Dictionary) -> String:
	if _beat_names.is_empty():
		var cs: Script = _CUTSCENE_SCRIPT
		for m in cs.get_script_method_list():
			_beat_names[str(m["name"])] = true
	var keys := records.keys()
	keys.sort()                              # record-id order is the dispatch order
	for key in keys:
		var r: Dictionary = records[key]
		var t: Dictionary = r.get("trigger", {})
		var kind := str(t.get("kind", ""))
		if not KINDS.has(kind):
			return "event '%s': unknown trigger kind '%s' (this build knows %s)" % [key, kind, str(KINDS)]
		var label := _bare(str(t.get("map", "")))
		var err := ""
		if t.has("when"):
			var w = _compile_cond(str(t["when"]))
			if w == null:
				return "event '%s': when '%s' does not parse" % [key, str(t["when"])]
			r["_when"] = w
		if t.has("facing") and not DIRS.has(str(t["facing"])):
			return "event '%s': unknown facing '%s'" % [key, str(t["facing"])]
		match kind:
			"interact":
				err = _compile_block(r.get("commands", []), key)
				if err != "":
					return err
				if t.has("object"):
					_push(_by_interact, "%s|%s" % [label, str(t["object"])], r)
				elif t.has("front"):
					var fc = _trigger_cells(t, key)
					if fc is String:
						return fc
					for c in fc:
						_push(_by_front, "%s|%d,%d" % [label, c.x, c.y], r)
				else:
					return "event '%s': interact trigger needs an object or front cells" % key
			"visible":
				var src := str(t.get("visible_when", ""))
				var e = _compile_cond(src)
				if e == null:
					return "event '%s': visible_when '%s' does not parse" % [key, src]
				r["_vis"] = e
				_by_visible["%s|%s" % [label, str(t.get("object", ""))]] = r
			"step":
				err = _compile_block(r.get("commands", []), key)
				if err != "":
					return err
				var cells = _trigger_cells(t, key)
				if cells is String:
					return cells
				if (cells as Array).is_empty():
					return "event '%s': step trigger needs cells or a region" % key
				for c in cells:
					_push(_by_step, "%s|%d,%d" % [label, c.x, c.y], r)
			"enter":
				err = _compile_block(r.get("commands", []), key)
				if err != "":
					return err
				var ec = _trigger_cells(t, key)
				if ec is String:
					return ec
				_push(_by_enter, label, r)
			"battle_end":
				err = _compile_block(r.get("commands", []), key)
				if err != "":
					return err
				_push(_by_battle_end, label, r)
			"boulder_hole":
				var hc = _trigger_cells(t, key)
				if hc is String:
					return hc
				if (hc as Array).is_empty():
					return "event '%s': boulder_hole trigger needs cells" % key
				for c in hc:
					_by_bhole["%s|%d,%d" % [label, c.x, c.y]] = true
			"boulder":
				err = _compile_block(r.get("commands", []), key)
				if err != "":
					return err
				var bc = _trigger_cells(t, key)
				if bc is String:
					return bc
				if (bc as Array).is_empty():
					return "event '%s': boulder trigger needs cells" % key
				for c in bc:
					_push(_by_boulder, "%s|%d,%d" % [label, c.x, c.y], r)
		maps[label] = true
	return ""


func _push(index: Dictionary, key: String, r: Dictionary) -> void:
	if not index.has(key):
		index[key] = []
	index[key].append(r)


## The trigger's cell set: explicit `cells`/`front` cells plus an inclusive `region`
## [x0,y0,x1,y1]. Returns an Array of Vector2i, or a String error. Cached on the record.
func _trigger_cells(t: Dictionary, key: String):
	if t.has("_cells"):
		return t["_cells"]
	var out: Array = []
	for c in t.get("cells", []) + t.get("front", []):
		out.append(Vector2i(int(c[0]), int(c[1])))
	if t.has("region"):
		var rg: Array = t["region"]
		if rg.size() != 4 or int(rg[2]) < int(rg[0]) or int(rg[3]) < int(rg[1]):
			return "event '%s': region must be [x0, y0, x1, y1]" % key
		for y in range(int(rg[1]), int(rg[3]) + 1):
			for x in range(int(rg[0]), int(rg[2]) + 1):
				out.append(Vector2i(x, y))
	t["_cells"] = out
	return out


# ---- hook-side dispatch (called by EventMapScript) ----------------------------------

## The `visible` query for object_shown: true/false, or null to fall through (no event).
func visible_for(label: String, object_key: String):
	var r = _by_visible.get("%s|%s" % [label, object_key])
	if r == null:
		return null
	return _truthy(r["_vis"], label)


## A pressed on this map: object-keyed records for the faced NPC first, then faced-cell
## records. The first record whose gate (`when`/`facing`) passes runs and consumes the
## press; none passing falls through to the generic flow (hidden items, Cut, NPC text).
func interact_fire(label: String, front: Vector2i, npc) -> bool:
	if npc != null:
		for r in _by_interact.get("%s|%s" % [label, str(npc.key)], []):
			if _gate(r):
				npc.face_to(main.player.cell)
				run(r, {"npc": npc, "cell": front})
				return true
	for r in _by_front.get("%s|%d,%d" % [label, front.x, front.y], []):
		if _gate(r):
			run(r, {"npc": npc, "cell": front})
			return true
	return false


## A completed player step: non-consuming records all run (state pokes); the first
## consuming record whose gate passes runs and consumes the step (no warp/sight/
## poison/encounter), mirroring pokered running the map script before trainer sight.
func step_fire(label: String, cell: Vector2i) -> bool:
	for r in _by_step.get("%s|%d,%d" % [label, cell.x, cell.y], []):
		if not _gate(r):
			continue
		if bool(r["trigger"].get("consume", true)):
			run(r, {"cell": cell})
			return true
		run(r, {"cell": cell})
	return false


## Map load: the map's `enter` records in id order, one coroutine (a record with `cells`
## only fires when the player arrived on one of them — the arrival-warp idiom).
func run_enter(label: String) -> void:
	var recs: Array = _by_enter.get(label, [])
	for r in recs:
		var cells: Array = r["trigger"].get("_cells", [])
		if not cells.is_empty() and not (main.player.cell in cells):
			continue
		if _gate(r):
			await run(r, {"cell": main.player.cell})


## A won trainer battle on the map. `rerun_enter: true` re-runs the map's `enter` records
## first — pokered's EndTrainerBattle sets BIT_CUR_MAP_LOADED_1, so the load callback runs
## again the moment a trainer battle ends and a door it lays opens ON THE SPOT (the
## map-scripts.md post-battle rule as a declarative trigger field).
func run_battle_end(label: String) -> void:
	for r in _by_battle_end.get(label, []):
		if bool(r["trigger"].get("rerun_enter", false)):
			await run_enter(label)
		if _gate(r):
			await run(r, {})


## May a STRENGTH boulder be shoved into this (unwalkable) cell — a Seafoam/Victory Road
## hole? Queried by try_push_boulder before the shove (a load-time index, no VM run).
func boulder_hole_at(label: String, cell: Vector2i) -> bool:
	return _by_bhole.has("%s|%d,%d" % [label, cell.x, cell.y])


## A STRENGTH boulder just slid onto this cell: floor switches, hole falls. The landing
## boulder NPC rides the ctx (the `boulder_fall` command hides it and marks FELL_<key>).
func run_boulder(label: String, cell: Vector2i, npc) -> void:
	for r in _by_boulder.get("%s|%d,%d" % [label, cell.x, cell.y], []):
		if _gate(r):
			await run(r, {"cell": cell, "npc": npc})


func _gate(r: Dictionary) -> bool:
	var t: Dictionary = r["trigger"]
	if t.has("facing") and main.player.facing != DIRS[str(t["facing"])]:
		return false
	if r.has("_when") and not _truthy(r["_when"], _bare(str(t.get("map", "")))):
		return false
	return true


## Run an event's command list as the active cutscene. Fire-and-forget from a hook (the
## hook returns `handled` immediately, exactly as adapters call Cutscene beats today).
## `cutscene_active` is saved/restored, not cleared — battle_end records fire inside the
## trainer-battle beat, which still owns the flag.
func run(rec: Dictionary, ctx: Dictionary = {}) -> void:
	var prev: bool = main.cutscene_active
	main.cutscene_active = true
	if not prev:
		main.modal = null
	ctx["_map"] = _bare(str(rec.get("trigger", {}).get("map", "")))
	await _run_block(rec.get("commands", []), ctx)
	main.cutscene_active = prev


## Execute one block; false = the event aborted (a refused give_item stops the list,
## faithful to Cutscene._gift's early return).
func _run_block(cmds: Array, ctx: Dictionary) -> bool:
	for c_v in cmds:
		var c: Dictionary = c_v
		match str(c["cmd"]):
			"say":
				await main.cutscene.say(_interp(str(c["text"])))
			"notice":
				# The one-shot, non-blocking textbox (Main._say) — a guard's one-liner after a
				# push-back. The event does not wait for the dismissal, exactly as the retired
				# adapters' say() helper behaved; `say` is the blocking dialogue page.
				main._say(_interp(str(c["text"])))
			"if":
				var branch: Array = c.get("then", []) if _truthy(c["_cond"], str(ctx.get("_map", ""))) \
					else c.get("else", [])
				if not await _run_block(branch, ctx):
					return false
			"give_item":
				var display := _item_display(str(c["item"]))
				if not main.add_item(display):
					await main.cutscene.say("You don't have\nroom for this!")
					return false
			"take_item":
				var tdisp := _item_display(str(c["item"]))
				if main.player_bag.has(tdisp):
					main.player_bag[tdisp] = int(main.player_bag[tdisp]) - 1
					if int(main.player_bag[tdisp]) <= 0:
						main.player_bag.erase(tdisp)
			"set_flag":
				main.set_event(str(c["flag"]))
			"clear_flag":
				main.story_events.erase(str(c["flag"]))
			"sfx":
				if main.audio:
					main.audio.play_sfx(str(c["key"]))
			"beat":
				var argv: Array = []
				for a in c.get("args", []):
					if str(a) == "@npc":
						argv.append(ctx.get("npc"))       # the triggering NPC
					elif str(a).begins_with("@object:"):
						argv.append(main._npc_by_key(str(a).substr(8)))   # a named map object
					else:
						argv.append(a)
				await main.cutscene.callv(str(c["name"]), argv)
				main.cutscene_active = true    # a beat drops the flag at its end; re-arm for the rest
			"set_last_map":
				main.last_outside_map = _bare(str(c["map"]))
			"set_block":
				main.set_block(int(c["x"]), int(c["y"]), int(c["block"]))
			"set_force_bike":
				main.force_bike = bool(c["value"])
			"mount_bike":
				main._mount_forced_bike()
			"bounce_back":
				# The guard pushes you back the way you came (one cell against your facing).
				var fd: Vector2i = _FACING_VEC[main.player.facing]
				main.player.place(Vector2i(ctx["cell"]) - fd)
			"step_back_down":
				# pokered's *MovePlayerDownScript: face DOWN + one simulated PAD_DOWN — a step,
				# not a teleport, so a down-ledge hops two cells and a wall leaves you put (gh #86).
				main.player.facing = 0
				var cell: Vector2i = ctx["cell"]
				var d := Vector2i(0, 1)
				if main.ledge_match(cell, "down", d):
					main.player.place(cell + d * 2)
				elif main.player_can_enter(cell + d):
					main.player.place(cell + d)
			"walk_player":
				await main.player.step(DIRS[str(c["dir"])])
			"vending":
				main._vending_enter()
			"fall_hole":
				# The Gen-1 dungeon warp (IsPlayerOnDungeonWarp): drop to the named floor,
				# landing on the DungeonWarpData cell. The fall ceremony stays native.
				var to: Array = c["to"]
				main.cutscene.fall_down_hole(_bare(str(c["map"])), Vector2i(int(to[0]), int(to[1])))
			"block_cell":
				# Make a walkable cell impassable outside the block grid (an E4 exit seal's
				# warp squares) — cleared per load; the enter record re-lays it.
				main._blocked_cells[Vector2i(int(c["x"]), int(c["y"]))] = true
			"unblock_cell":
				main._blocked_cells.erase(Vector2i(int(c["x"]), int(c["y"])))
			"trainer_battle":
				# Engage a map trainer outside the sight system (a coordinate trigger:
				# LANCE, the Mt. Moon fossil nerd). Fire-and-forget, exactly as the retired
				# adapters called it; no-op if the object is absent or hidden.
				var tnpc = main._npc_by_key(str(c["object"]))
				if tnpc != null and tnpc.shown:
					tnpc.face_to(main.player.cell)
					main.cutscene.trainer_battle(tnpc, false)
			"boulder_fall":
				# The shoved boulder drops through the hole for good: the floor event + the
				# generic FELL_<object> visibility rule (base boulder_falls, verbatim).
				var bnpc = ctx.get("npc")
				if bnpc != null:
					main.set_event(str(c["flag"]))
					main.set_event("FELL_" + str(bnpc.key))
					bnpc.set_shown(false)
					if main.audio:
						main.audio.play_sfx("collision")
			"walk_forward":
				# A forced run of steps (Seafoam B4F's strong currents): stops at walls,
				# exactly as Cutscene.walk_forward does.
				await main.cutscene.walk_forward(main.player, DIRS[str(c["dir"])], int(c["count"]))
			"reset_elite4":
				# IndigoPlateauLobby's gauntlet reset (ResetEventRange INDIGO_PLATEAU_EVENTS);
				# the ceremony stays native.
				main.reset_elite4_gauntlet()
			"elevator_retarget":
				# engine/events/elevator.asm StoreWarpEntries: on entry the door warps lead
				# back to the boarding floor. Call from an `enter` record.
				var from: Dictionary = main.warped_from
				if not from.is_empty() and int(from.get("warp", 0)) > 0:
					for w in main.map["warps"]:
						w["dest_map"] = str(from["map"])
						w["dest_warp"] = int(from["warp"])
			"elevator_panel":
				await _elevator_panel(c["floors"])
	return true


## The elevator panel (DisplayElevatorFloorMenu): pick a floor from the list, retarget the
## door warps, and shake the car. floors = [[label, map ref, dest_warp(1-based)], ...];
## B keeps the current destination. (overworld/elevator.asm ShakeElevator; the asm floor
## tables' warp numbers are 0-based, +1 in the records.)
func _elevator_panel(floors: Array) -> void:
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
		w["dest_map"] = _bare(str(floors[idx][1]))
		w["dest_warp"] = int(floors[idx][2])
	await main.shake_elevator()


# ---- compilation (load-time, so a bad record refuses at boot, not mid-story) --------

## Walk a block, refuse unknown commands, and pre-parse every `if` condition in place.
func _compile_block(cmds, key: String) -> String:
	if not (cmds is Array):
		return "event '%s': commands is not a list" % key
	for c_v in cmds:
		var c: Dictionary = c_v
		var cmd := str(c.get("cmd", ""))
		if not CMDS.has(cmd):
			return "event '%s': unknown command '%s' (this build knows %s)" % [key, cmd, str(CMDS)]
		match cmd:
			"if":
				var e = _compile_cond(str(c.get("cond", "")))
				if e == null:
					return "event '%s': condition '%s' does not parse" % [key, str(c.get("cond", ""))]
				c["_cond"] = e
				for b in ["then", "else"]:
					var err := _compile_block(c.get(b, []), key)
					if err != "":
						return err
			"beat":
				if not _beat_names.has(str(c.get("name", ""))):
					return "event '%s': unknown beat '%s' (not a Cutscene method)" % [key, str(c.get("name", ""))]
			"walk_player":
				if not DIRS.has(str(c.get("dir", ""))):
					return "event '%s': unknown walk_player dir '%s'" % [key, str(c.get("dir", ""))]
	return ""


## Parse a FormulaExpr condition and remember its identifiers (they resolve to story
## flags / event vars at eval; extras beyond the AST's variables are harmless — eval
## only reads the ones it needs). Returns null on a parse error.
func _compile_cond(src: String):
	var e := FormulaExpr.parse(src)
	if e.error != "":
		return null
	var idents := {}
	for t in e._tokenize(src):        # the evaluator's own lexer: idents minus functions
		if t[0] == "ident" and not FormulaExpr._FUNCS.has(t[1]):
			idents[t[1]] = true
	return {"expr": e, "idents": idents.keys()}


func _truthy(cond: Dictionary, label := "") -> bool:
	var vars := {}
	for ident in cond["idents"]:
		vars[ident] = _ident_value(str(ident), label)
	return bool(cond["expr"].eval(vars))


## Condition vocabulary: event vars win, then the engine-state prefixes, else a story
## flag (1/0). `item_<id>` is the bag count, `badge_<name>`/`badge_count` the badge
## case, `force_bike` Cycling Road's BIT_ALWAYS_ON_BIKE, `surfing` the surf state, and
## `defeated_<x>_<y>` whether the trainer whose home cell is (x, y) ON THE RECORD'S MAP
## has been beaten (the trigger's map, not the center map — visible queries can run for
## a neighbor's objects).
func _ident_value(ident: String, label: String):
	if main.event_vars.has(ident):
		return main.event_vars[ident]
	if ident.begins_with("item_"):
		return int(main.player_bag.get(_item_display(ident.substr(5)), 0))
	if ident == "badge_count":
		return main.badges.size()
	if ident.begins_with("badge_"):
		return 1 if main.badges.has(ident.substr(6).to_upper()) else 0
	if ident == "force_bike":
		return 1 if main.force_bike else 0
	if ident == "surfing":
		return 1 if main.surfing else 0
	if ident == "player_x":
		return main.player.cell.x
	if ident == "player_y":
		return main.player.cell.y
	if ident == "dex_owned":
		main._sync_owned()
		return main.pokedex_owned.size()
	if ident.begins_with("defeated_"):
		var parts := ident.substr(9).split("_")
		if parts.size() == 2:
			return 1 if main.defeated_trainers.has("%s:%d,%d" % [label, int(parts[0]), int(parts[1])]) else 0
	return 1 if main.has_event(ident) else 0


# ---- helpers ------------------------------------------------------------------------

## "{player}"/"{rival}" placeholders -> the saved names (the format never bakes them in).
func _interp(text: String) -> String:
	return text.replace("{player}", str(main.player_name)).replace("{rival}", str(main.rival_name))


## The format speaks item IDs; the bag speaks display names — the loader resolves
## (ADR-017 d4): "item:town_map" -> item_names["TOWN_MAP"] -> "TOWN MAP".
func _item_display(item_id: String) -> String:
	return str(main.item_names.get(_bare(item_id).to_upper(), _bare(item_id)))


func _bare(id: String) -> String:
	return id.substr(id.find(":") + 1)
