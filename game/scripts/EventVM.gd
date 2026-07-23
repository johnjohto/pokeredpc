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
var _last_given := {}    # the mon added by the most recent give_mon (offer_nickname's target)
var _by_interact := {}   # "<label>|<object key>" -> [records] (id order)
var _by_front := {}      # "<label>|<x>,<y>"      -> [records] (faced-cell interactions)
var _by_visible := {}    # "<label>|<object key>" -> event record
var _by_step := {}       # "<label>|<x>,<y>"      -> [records]
var _by_enter := {}      # "<label>"              -> [records]
var _by_battle_end := {} # "<label>"              -> [records]
var _by_bhole := {}      # "<label>|<x>,<y>"      -> true (a boulder may be shoved in)
var _by_boulder := {}    # "<label>|<x>,<y>"      -> [records] (a boulder landed here)
var _by_at := {}         # "<label>|<x>,<y>"      -> [records] (player-cell interactions: slot seats)
var _by_warp := {}       # "<label>"              -> [records] (warp gates/replacements)
var _scripts := {}       # script basename -> parsed HatchScript (compiled at project load)

const KINDS := ["interact", "visible", "enter", "step", "battle_end", "boulder_hole", "boulder", "warp"]
const CMDS := ["say", "notice", "if", "give_item", "take_item", "set_flag", "clear_flag", "sfx",
	"beat", "set_last_map", "set_block", "set_force_bike", "mount_bike",
	"bounce_back", "step_back_down", "walk_player", "vending", "fall_hole",
	"elevator_retarget", "elevator_panel", "block_cell", "unblock_cell",
	"trainer_battle", "reset_elite4", "boulder_fall", "walk_forward",
	"set_var", "set_npc_text", "hide_object", "show_object", "lucky_slot", "play_slots",
	"club_enter", "club_leave", "trash_reset", "trash_can", "face_object",
	"face_player", "play_song", "wait", "walk_object_to", "class_battle", "heal_party",
	"ask", "show_dex_entry", "pic", "clear_pic", "set_starter", "set_rival_starter", "give_mon",
	"show_text", "close_text", "emote", "walk_object", "walk_player_to", "walk_together_to", "warp_to",
	"place_object", "play_map_music", "give_badge", "defeat_gym_trainers",
	"fade_out", "fade_in", "refresh_objects",
	"offer_nickname", "show_money", "hide_money", "take_money",
	"wild_battle", "give_coins", "walk_both_to", "run_script"]

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
func load_all(records: Dictionary, scripts: Dictionary = {}) -> String:
	if _beat_names.is_empty():
		var cs: Script = _CUTSCENE_SCRIPT
		for m in cs.get_script_method_list():
			_beat_names[str(m["name"])] = true
	for script_key in scripts:
		var script_record_v = scripts[script_key]
		var record_error := _validate_script_record(str(script_key), script_record_v)
		if record_error != "":
			return record_error
		var script_record: Dictionary = script_record_v
		var parsed := HatchScript.parse(str(script_record.get("source", "")))
		if parsed.error != "":
			return "script '%s': %s" % [script_key, parsed.error]
		_scripts[str(script_key)] = parsed
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
				elif t.has("at"):
					# `at` cells match the PLAYER's own cell (a slot-machine seat: you stand
					# on it and press A, whatever you face).
					for c in t["at"]:
						_push(_by_at, "%s|%d,%d" % [label, int(c[0]), int(c[1])], r)
				else:
					return "event '%s': interact trigger needs an object, front, or at cells" % key
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
			"warp":
				err = _compile_block(r.get("commands", []), key)
				if err != "":
					return err
				if not t.has("dest"):
					return "event '%s': warp trigger needs a dest map" % key
				_push(_by_warp, label, r)
		maps[label] = true
	return ""


## Main boots ProjectData directly rather than running the full Studio/CI validator.
## Keep the small script-record contract at this execution boundary too, so malformed
## source records cannot bypass their schema on a direct Engine launch.
func _validate_script_record(key: String, record_v) -> String:
	if not (record_v is Dictionary):
		return "script '%s': record must be an object" % key
	var key_pattern := RegEx.create_from_string("^[a-z0-9_]+$")
	if key_pattern.search(key) == null:
		return "script '%s': filename key must match [a-z0-9_]+" % key
	var record: Dictionary = record_v
	var allowed := ["id", "source", "$comment", "custom"]
	for field in record:
		if str(field) not in allowed:
			return "script '%s': unknown field '%s'" % [key, str(field)]
	var expected_id := "script:" + key
	if str(record.get("id", "")) != expected_id:
		return "script '%s': id must be '%s'" % [key, expected_id]
	if not (record.get("source") is String) or str(record.get("source", "")).is_empty():
		return "script '%s': source must be a non-empty string" % key
	if record.has("$comment") and not (record["$comment"] is String):
		return "script '%s': $comment must be a string" % key
	if record.has("custom") and not (record["custom"] is Dictionary):
		return "script '%s': custom must be an object" % key
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
	var pc: Vector2i = main.player.cell
	for r in _by_at.get("%s|%d,%d" % [label, pc.x, pc.y], []):
		if _gate(r):
			run(r, {"npc": npc, "cell": pc})
			return true
	return false


## A warp the player stepped on, before the fade + load: the first record whose dest map
## and gate match consumes the warp (blocked, or replaced by a beat — SafariZoneGate).
func warp_fire(label: String, w: Dictionary, dest_label: String) -> bool:
	for r in _by_warp.get(label, []):
		if _bare(str(r["trigger"]["dest"])) != dest_label:
			continue
		if _gate(r):
			run(r, {"warp": w, "dest_label": dest_label})
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
		_last_given = {}     # offer_nickname reaches only a give_mon from THIS event
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
			"ask":
				# The Gen-1 yes/no box: `then` on YES, `else` on NO (choose_starter's confirm).
				var abr: Array = c.get("then", []) if await main.cutscene.ask(_interp(str(c["text"]))) \
					else c.get("else", [])
				if not await _run_block(abr, ctx):
					return false
			"show_dex_entry":
				# The Pokédex data screen as a ceremony native (StarterDex).
				await main.show_dex_entry(_bare(str(c["species"])))
			"pic":
				# The full-size front pic overlay the ask floats over (choose_starter's pose).
				var ptex: Texture2D = load("res://assets/pokemon/front/%s.png" % _bare(str(c["species"])))
				if ptex:
					main.cutscene.pic(ptex)
			"clear_pic":
				main.cutscene.clear_pic()
			"set_starter":
				main.player_starter = _bare(str(c["species"]))
			"set_rival_starter":
				main.rival_starter = _bare(str(c["species"]))
			"give_mon":
				# A story-gifted mon joins the party (the starter, Eevee, the Hitmons…) —
				# the box takes the overflow, and a full party AND box refuses + aborts the
				# event (GivePokemon's failure, Cutscene._receive_mon verbatim — gh #41
				# questline 6; the flag stays unset so the gift re-offers).
				var gm: Dictionary = main.make_mon(_bare(str(c["species"])), int(c["level"]), [])
				var gm_to_party: bool = main.player_party.size() < 6
				if gm_to_party:
					main.player_party.append(gm)
				elif main.pc_box.size() < 20:
					main.pc_box.append(gm)
				else:
					await main.cutscene.say("Your party and\nbox are full!")
					return false
				_last_given = gm
				if gm_to_party and bool(c.get("nickname_offer", false)):
					await main.cutscene.offer_nickname(gm)
			"give_item":
				var display := _item_display(str(c["item"]))
				if not main.add_item(display, int(c.get("count", 1))):
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
					elif str(a) == "@warp_dest_label":
						argv.append(ctx.get("dest_label"))
					elif str(a) == "@warp_index0":
						argv.append(int(ctx.get("warp", {}).get("dest_warp", 1)) - 1)
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
				if c.has("count"):
					# A multi-step forced walk (lab_intro's aisle follow); stops at walls.
					await main.cutscene.walk_forward(main.player, DIRS[str(c["dir"])], int(c["count"]))
				else:
					await main.player.step(DIRS[str(c["dir"])])
			"show_text":
				# A held textbox: types out and STAYS (DoNotWaitForButtonPress) until close_text
				# — the intercept's "Hey! Wait!" hanging over the emote choreography.
				main.textbox.show_text(_interp(str(c["text"])))
			"close_text":
				main.textbox.advance()
			"emote":
				# The EmotionBubble: pops over the player (or a named object), holds its
				# faithful 60 frames, and hides — one atomic beat, as pokered plays it.
				var etgt = main.player if str(c.get("object", "")) == "" else main._npc_by_key(str(c["object"]))
				if etgt != null:
					etgt.show_emote(str(c["kind"]))
					await main.cutscene.wait(1.0)
					etgt.hide_emote()
			"walk_object":
				# A dir+count forced walk for an object (walk_forward); stops at walls.
				var wfo = main._npc_by_key(str(c["object"]))
				if wfo != null:
					await main.cutscene.walk_forward(wfo, DIRS[str(c["dir"])], int(c["count"]))
			"walk_player_to":
				var wta: Array = c["to"]
				await main.cutscene.walk(main.player,
					main.find_path(main.player.cell, Vector2i(int(wta[0]), int(wta[1]))))
			"walk_together_to":
				# The lead walks its found path with the player in tow (Oak leading you in).
				var lead = main._npc_by_key(str(c["object"]))
				if lead != null:
					var lta: Array = c["to"]
					await main.cutscene.walk_together(lead, main.player,
						main.find_path(lead.cell, Vector2i(int(lta[0]), int(lta[1]))))
			"warp_to":
				# A scripted map change mid-event (the intercept walking you into the lab).
				main.load_world(_bare(str(c["map"])), int(c.get("warp", -1)))
				ctx["_map"] = main.center_label
			"place_object":
				# Teleport a map object somewhere and show it (the rival re-entering at the
				# lab door for the Pokédex handout).
				var po = main._npc_by_key(str(c["object"]))
				if po != null:
					var pa: Array = c["at"]
					po.cell = Vector2i(int(pa[0]), int(pa[1]))
					po.position = Vector2(po.cell * 16)
					po.set_shown(true)
			"vending":
				main._vending_enter()
			"fall_hole":
				# The Gen-1 dungeon warp (IsPlayerOnDungeonWarp): drop to the named floor,
				# landing on the DungeonWarpData cell. The fall ceremony stays native and is
				# awaited so run()'s cutscene_active restore cannot trample its flag.
				var to: Array = c["to"]
				await main.cutscene.fall_down_hole(_bare(str(c["map"])), Vector2i(int(to[0]), int(to[1])))
				main.cutscene_active = true
			"block_cell":
				# Make a walkable cell impassable outside the block grid (an E4 exit seal's
				# warp squares) — cleared per load; the enter record re-lays it.
				main._blocked_cells[Vector2i(int(c["x"]), int(c["y"]))] = true
			"unblock_cell":
				main._blocked_cells.erase(Vector2i(int(c["x"]), int(c["y"])))
			"trainer_battle":
				# Engage a map trainer outside the sight system (a coordinate trigger:
				# LANCE, the Mt. Moon fossil nerd). Awaited — an unawaited call would let
				# run()'s cutscene_active restore trample the beat's own flag on the same
				# frame. No-op if the object is absent or hidden.
				var tnpc = main._npc_by_key(str(c["object"]))
				if tnpc != null and tnpc.shown:
					tnpc.face_to(main.player.cell)
					await main.cutscene.trainer_battle(tnpc, false)
					main.cutscene_active = true    # re-arm for the rest of the event (as beat does)
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
			"set_var":
				# The saved vars store (ADR-019 §5): the first non-boolean durable state.
				main.event_vars[str(c["name"])] = int(c["value"])
			"run_script":
				# Phase-6 hatch (ADR-028, gh #65): scripts are precompiled project
				# records and can reach only the curated Callables below. Command calls
				# queue ordinary VM commands, preserving their await/abort semantics.
				var script_key := _bare(str(c["script"]))
				var script := _scripts[script_key] as HatchScript
				var flags_before: Dictionary = main.story_events.duplicate(true)
				var vars_before: Dictionary = main.event_vars.duplicate(true)
				var queued_commands: Array = []
				var result = script.run({}, _event_script_functions(ctx, queued_commands))
				if script.error != "":
					main.story_events = flags_before
					main.event_vars = vars_before
					push_error("[events] script '%s': %s" % [script_key, script.error])
					return false
				var queue_error := _compile_block(queued_commands, "script:%s" % script_key)
				if queue_error != "":
					main.story_events = flags_before
					main.event_vars = vars_before
					push_error("[events] " + queue_error)
					return false
				if c.has("result"):
					if result == null:
						main.story_events = flags_before
						main.event_vars = vars_before
						push_error("[events] script '%s' returned no result for '%s'" % [
							script_key, str(c["result"])])
						return false
				if not await _run_block(queued_commands, ctx):
					return false
				if c.has("result"):
					main.event_vars[str(c["result"])] = result
			"set_npc_text":
				# Lines that live in a map script, not a trainer header (the Mt. Moon fossil
				# nerd) — wire them onto the object so the forced fight reads right.
				var tnpc2 = main._npc_by_key(str(c["object"]))
				if tnpc2 != null:
					if c.has("battle_text"):
						tnpc2.battle_text = str(c["battle_text"])
					if c.has("end_text"):
						tnpc2.end_text = str(c["end_text"])
			"face_object":
				# Turn a map object in place (wave C: the first choreography primitive —
				# oak_dont_go_away's Oak turning to call after the player). dir "player"
				# resolves toward the player's cell (face_to), for triggers whose player
				# cell varies (the S.S. Anne deck's two trigger cells).
				var fo = main._npc_by_key(str(c["object"]))
				if fo != null:
					if str(c["dir"]) == "player":
						fo.face_to(main.player.cell)
					else:
						fo.face(DIRS[str(c["dir"])])
			"face_player":
				main.player.facing = DIRS[str(c["dir"])]
				main.player._update_sprite()
			"play_song":
				if main.audio:
					main.audio.play_song(str(c["key"]))
			"play_map_music":
				# PlayDefaultMusic: the center map's own theme resumes (a jingle scene ended).
				if main.audio:
					main.audio.play_map_music(main.center_label)
			"wait":
				# A timed beat in frames (battle/text DelayFrames domain: 1/60 s each).
				await main.cutscene.wait(int(c["frames"]) / 60.0)
			"walk_object_to":
				# Pathfound walk to a fixed cell or to the player (+ offset) — the beats'
				# `walk(npc, find_path(...))` as a declarative command (wave C).
				var wo = main._npc_by_key(str(c["object"]))
				if wo != null:
					var tgt: Vector2i
					if str(c["to"]) == "player":
						tgt = main.player.cell
					else:
						var ta: Array = c["to"]
						tgt = Vector2i(int(ta[0]), int(ta[1]))
					if c.has("offset"):
						var off: Array = c["offset"]
						tgt += Vector2i(int(off[0]), int(off[1]))
					await main.cutscene.walk(wo, main.find_path(wo.cell, tgt))
			"class_battle":
				# A scripted trainer-class battle (the rival, not a map trainer): faithful
				# to the beats' start_trainer_battle(class, party, npc_id) + await finished.
				# Awaited so run()'s cutscene_active restore cannot trample it.
				main.start_trainer_battle(str(c["class"]), int(c["party"]), str(c.get("npc", "")))
				if bool(c.get("no_blackout", false)):
					main.battle.no_blackout = true
				await main.battle.finished
				main.cutscene_active = true    # re-arm for the rest of the event (as beat does)
			"heal_party":
				main.heal_party()
			"fade_out":
				# color "black" (default) = home/fade.asm GBFadeOutToBlack (Team Rocket leaving
				# Silph under the dark, gh #158); "white" = GBFadeOutToWhite (Silph 9F's nurse
				# heal flash, scripts/SilphCo9F.asm). The screen holds until the matching fade_in.
				if str(c.get("color", "black")) == "white":
					await main.cutscene.fade_out()
				else:
					await main.transition.fade_black()
			"fade_in":
				if str(c.get("color", "black")) == "white":
					await main.cutscene.fade_in()
				else:
					await main.transition.fade_in_black()
			"refresh_objects":
				# Re-evaluate every map object's visibility gate right now — pokered's
				# ShowObject/HideObject sweep mid-scene (this floor's rockets vanish while
				# the screen is dark; other floors flip at load from the same flags).
				main.refresh_objects()
			"offer_nickname":
				# DisplayNamingScreen for the LAST give_mon'd mon, as a separate command —
				# the gift beats offer the nickname AFTER the "received" line, unlike the
				# starter's inline nickname_offer (gh #41 questline 6).
				if not _last_given.is_empty():
					await main.cutscene.offer_nickname(_last_given)
			"show_money":
				# The MONEY_BOX overlay shown before a priced offer (MtMoonPokecenter.asm /
				# Museum1F.asm); stays up until hide_money, refreshed by take_money.
				main.moneybox.show_box()
			"hide_money":
				main.moneybox.hide_box()
			"take_money":
				main.player_money -= int(c["amount"])
				main.moneybox.refresh()          # redrawn right after SubBCDPredef
			"wild_battle":
				# A scripted wild encounter (the MAROWAK ghost): the retired beat's
				# start_battle + await. `unveil: true` = the ghost intro — appears as GHOST
				# until the SILPH SCOPE reveal mid-intro. Awaited, and re-armed after, as
				# class_battle does.
				if bool(c.get("unveil", false)):
					main.battle.unveil = true
				main.start_battle(_bare(str(c["species"])), int(c["level"]))
				await main.battle.finished
				main.battle.unveil = false
				main.cutscene_active = true
			"give_coins":
				# Game Corner coins, capped at the COIN CASE's 9999 (MaxCoinsText's cap).
				main.player_coins = mini(9999, main.player_coins + int(c["count"]))
			"walk_both_to":
				# The Pewter escort drag (gh #70): the NPC and the player walk their own
				# pathfound routes SIMULTANEOUSLY (PewterMovementScript_WalkToGym / the
				# museum guy's RLE pair) — Cutscene.walk_both is the primitive.
				var escort = main._npc_by_key(str(c["object"]))
				if escort != null:
					var escort_to: Array = c["to"]
					var player_to: Array = c["player_to"]
					await main.cutscene.walk_both(escort,
						Vector2i(int(escort_to[0]), int(escort_to[1])),
						Vector2i(int(player_to[0]), int(player_to[1])))
			"give_badge":
				# The badge case (the gym dissolution, gh #41): append once, idempotent — the
				# pokered quirk of the badge playing sound_level_up stays an explicit `sfx`
				# command in the record.
				if not str(c["badge"]) in main.badges:
					main.badges.append(str(c["badge"]))
			"defeat_gym_trainers":
				# pokered: beating a gym leader runs SetEvents on that gym's
				# EVENT_BEAT_<GYM>_TRAINER_* flags so its trainers no longer engage (gh #109).
				# Mark every trainer object_event on the center map defeated, exactly as the
				# retired gym_leader_battle beat did (the leader included — it is harmless).
				for o in main.map.get("object_events", []):
					var oa: Array = o.get("args", [])
					if oa.size() >= 4 and str(oa[3]).begins_with("OPP_"):
						main.defeated_trainers["%s:%d,%d" % [main.center_label, int(o["x"]), int(o["y"])]] = true
			"hide_object":
				# pokered's HideObject predef: flip a toggleable object's visibility right now.
				var h = main._npc_by_key(str(c["object"]))
				if h != null:
					h.set_shown(false)
			"show_object":
				# pokered's ShowObject predef. A collected item ball never comes back: a save
				# made before the show-event existed can reach here holding the item.
				var s = main._npc_by_key(str(c["object"]))
				if s != null and not (s.item != "" and main.picked_items.has(
						"%s:%d,%d" % [main.center_label, s.cell.x, s.cell.y])):
					s.set_shown(true)
			"lucky_slot":
				# GameCornerSelectLuckySlotMachine: transient RAM-like state, re-rolled each
				# visit (the overworld RNG — never the battle stream).
				var seats: Array = c["seats"]
				var pick: Array = seats[randi() % seats.size()]
				main._lucky_slot = Vector2i(int(pick[0]), int(pick[1]))
			"play_slots":
				# StartSlotMachine (AbleToPlaySlotsCheck first); the machine itself stays a
				# native modal.
				if not main.player_bag.has("COIN CASE"):
					main._say("A COIN CASE is\nrequired!")
				elif main.player_coins <= 0:
					main._say("You don't have\nany coins!")
				else:
					main.modal = main.slots
					main.slots.start(main.player.cell == main._lucky_slot)
			"club_enter":
				main.club_room_enter()
			"club_leave":
				main.club_room_leave()
			"trash_reset":
				main._trash_first = randi() % 15
			"trash_can":
				# A faced Vermilion Gym trash can (GymTrashScript): the two-switch hunt.
				var ci: int = main._trash_can_index(Vector2i(ctx["cell"]))
				if ci >= 0:
					main._trash_check(ci)
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
			"ask":
				# The yes/no prompt branches like `if`, on the player's answer (wave C).
				for b in ["then", "else"]:
					var aerr := _compile_block(c.get(b, []), key)
					if aerr != "":
						return aerr
			"beat":
				if not _beat_names.has(str(c.get("name", ""))):
					return "event '%s': unknown beat '%s' (not a Cutscene method)" % [key, str(c.get("name", ""))]
			"walk_player", "walk_forward", "walk_object", "face_player":
				if not DIRS.has(str(c.get("dir", ""))):
					return "event '%s': unknown %s dir '%s'" % [
						key, cmd, str(c.get("dir", ""))]
			"face_object":
				if str(c.get("dir", "")) != "player" and not DIRS.has(str(c.get("dir", ""))):
					return "event '%s': unknown face_object dir '%s'" % [
						key, str(c.get("dir", ""))]
			"run_script":
				var script_key := _bare(str(c.get("script", "")))
				if not _scripts.has(script_key):
					return "event '%s': unknown script '%s'" % [key, script_key]
				if c.has("result") and not str(c["result"]).is_valid_identifier():
					return "event '%s': script result '%s' is not a variable name" % [
						key, str(c["result"])]
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
	if ident == "in_safari":
		return 1 if main.in_safari else 0
	if ident == "player_x":
		return main.player.cell.x
	if ident == "player_y":
		return main.player.cell.y
	if ident == "party_count":
		# GivePokemon's full-party test (a gift branches its text BEFORE the give).
		return main.player_party.size()
	if ident == "box_count":
		# The 20-slot BILL's PC box (constants/pokemon_data_constants.asm MONS_PER_BOX;
		# with party_count: a gift's both-full pre-check).
		return main.pc_box.size()
	if ident == "money":
		return main.player_money
	if ident == "coins":
		return main.player_coins
	if ident == "battle_doll_escape":
		# wBattleResult stays 0 on a POKé DOLL escape — the documented ghost-laying
		# trick (the MAROWAK script keys on it alongside the win).
		return 1 if main.battle.doll_escape else 0
	if ident == "dex_owned":
		main._sync_owned()
		return main.pokedex_owned.size()
	if ident.begins_with("player_starter_"):
		# Starter identity (OaksLab's untaken-ball rule): which species the player picked.
		return 1 if str(main.player_starter) == ident.substr(15) else 0
	if ident.begins_with("rival_starter_"):
		return 1 if str(main.rival_starter) == ident.substr(14) else 0
	if ident == "battle_won":
		# The last battle's outcome, for post-class_battle branches (wave C).
		return 1 if main.battle.won else 0
	if ident.begins_with("defeated_"):
		var parts := ident.substr(9).split("_")
		if parts.size() == 2:
			return 1 if main.defeated_trainers.has("%s:%d,%d" % [label, int(parts[0]), int(parts[1])]) else 0
	return 1 if main.has_event(ident) else 0


# ---- HatchScript event API ----------------------------------------------------------

## The event hatch's complete external surface for gh #65. Durable flag/var mutations
## happen immediately so script control flow can observe them. Curated command-library
## equivalents enqueue ordinary EventVM commands; run_script awaits that queue after a
## successful script run, reusing the VM's established coroutine and abort semantics.
func _event_script_functions(ctx: Dictionary, commands: Array) -> Dictionary:
	return {
		"has_flag": func(name): return main.has_event(str(name)),
		"set_flag": func(name): main.set_event(str(name)); return null,
		"clear_flag": func(name): main.story_events.erase(str(name)); return null,
		"get_var": func(name): return main.event_vars.get(str(name), 0),
		"set_var": func(name, value): main.event_vars[str(name)] = value; return null,
		"clear_var": func(name): main.event_vars.erase(str(name)); return null,
		"item_count": func(item): return int(main.player_bag.get(_item_display(str(item)), 0)),
		"party_count": func(): return main.player_party.size(),
		"box_count": func(): return main.pc_box.size(),
		"party_has": func(species):
			var wanted := _bare(str(species)).to_lower()
			for mon in main.player_party:
				if str(mon.get("species", "")).to_lower() == wanted:
					return true
			return false,
		"map_id": func(): return str(ctx.get("_map", main.center_label)),
		"player_x": func(): return main.player.cell.x,
		"player_y": func(): return main.player.cell.y,
		"facing": func(): return main.player.facing,
		"money": func(): return main.player_money,
		"coins": func(): return main.player_coins,
		"badge_count": func(): return main.badges.size(),
		"has_badge": func(badge): return main.badges.has(str(badge).to_upper()),
		"say": func(text): return _queue_script_command(commands, "say",
			{"text": str(text)}),
		"notice": func(text): return _queue_script_command(commands, "notice",
			{"text": str(text)}),
		"show_text": func(text): return _queue_script_command(commands, "show_text",
			{"text": str(text)}),
		"close_text": func(): return _queue_script_command(commands, "close_text", {}),
		"sfx": func(key): return _queue_script_command(commands, "sfx",
			{"key": str(key)}),
		"play_song": func(key): return _queue_script_command(commands, "play_song",
			{"key": str(key)}),
		"play_map_music": func(): return _queue_script_command(
			commands, "play_map_music", {}),
		"wait_frames": func(frames): return _queue_script_command(commands, "wait",
			{"frames": int(frames)}),
		"give_item": func(item, count): return _queue_script_command(commands, "give_item",
			{"item": str(item), "count": int(count)}),
		"take_item": func(item): return _queue_script_command(commands, "take_item",
			{"item": str(item)}),
		"give_coins": func(count): return _queue_script_command(commands, "give_coins",
			{"count": int(count)}),
		"take_money": func(amount): return _queue_script_command(commands, "take_money",
			{"amount": int(amount)}),
		"give_badge": func(badge): return _queue_script_command(commands, "give_badge",
			{"badge": str(badge)}),
		"heal_party": func(): return _queue_script_command(commands, "heal_party", {}),
		"set_last_map": func(map_id): return _queue_script_command(commands, "set_last_map",
			{"map": str(map_id)}),
		"set_force_bike": func(value): return _queue_script_command(commands, "set_force_bike",
			{"value": bool(value)}),
		"mount_bike": func(): return _queue_script_command(commands, "mount_bike", {}),
		"block_cell": func(x, y): return _queue_script_command(commands, "block_cell",
			{"x": int(x), "y": int(y)}),
		"unblock_cell": func(x, y): return _queue_script_command(commands, "unblock_cell",
			{"x": int(x), "y": int(y)}),
		"walk_player": func(dir, count): return _queue_script_command(commands, "walk_player",
			{"dir": str(dir), "count": int(count)}),
		"walk_forward": func(dir, count): return _queue_script_command(commands, "walk_forward",
			{"dir": str(dir), "count": int(count)}),
		"walk_object": func(object, dir, count): return _queue_script_command(commands,
			"walk_object", {"object": str(object), "dir": str(dir), "count": int(count)}),
		"walk_player_to": func(x, y): return _queue_script_command(commands, "walk_player_to",
			{"to": [int(x), int(y)]}),
		"place_object": func(object, x, y): return _queue_script_command(commands, "place_object",
			{"object": str(object), "at": [int(x), int(y)]}),
		"face_object": func(object, dir): return _queue_script_command(commands, "face_object",
			{"object": str(object), "dir": str(dir)}),
		"face_player": func(dir): return _queue_script_command(commands, "face_player",
			{"dir": str(dir)}),
		"hide_object": func(object): return _queue_script_command(commands, "hide_object",
			{"object": str(object)}),
		"show_object": func(object): return _queue_script_command(commands, "show_object",
			{"object": str(object)}),
		"refresh_objects": func(): return _queue_script_command(
			commands, "refresh_objects", {}),
		"warp_to": func(map_id, warp): return _queue_script_command(commands, "warp_to",
			{"map": str(map_id), "warp": int(warp)})
	}


func _queue_script_command(commands: Array, cmd: String, fields: Dictionary):
	var command := fields.duplicate(true)
	command["cmd"] = cmd
	commands.append(command)
	return null


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
