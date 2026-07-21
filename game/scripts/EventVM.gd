extends RefCounted
class_name EventVM
## The Event VM (ADR-019, gh #39): interprets a project's authored event records —
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
## (plan §6 risk 7: no VM in per-frame surfaces).

var main

var maps := {}           # map label -> true (any event targets this map)
var _by_interact := {}   # "<label>|<object key>" -> event record
var _by_visible := {}    # "<label>|<object key>" -> event record

const KINDS := ["interact", "visible"]
const CMDS := ["say", "if", "give_item", "set_flag", "clear_flag", "sfx"]


## Index every record (basename -> record, from ProjectData.events()). Returns "" or the
## boot-fatal error naming the record — a project asking for semantics this build lacks
## must refuse loudly at load, the ADR-017 refuse-newer pattern applied to events.
func load_all(records: Dictionary) -> String:
	for key in records.keys():
		var r: Dictionary = records[key]
		var t: Dictionary = r.get("trigger", {})
		var kind := str(t.get("kind", ""))
		if not KINDS.has(kind):
			return "event '%s': unknown trigger kind '%s' (this build knows %s)" % [key, kind, str(KINDS)]
		var label := _bare(str(t.get("map", "")))
		var obj := str(t.get("object", ""))
		match kind:
			"interact":
				var err := _compile_block(r.get("commands", []), key)
				if err != "":
					return err
				_by_interact["%s|%s" % [label, obj]] = r
			"visible":
				var src := str(t.get("visible_when", ""))
				var e = _compile_cond(src)
				if e == null:
					return "event '%s': visible_when '%s' does not parse" % [key, src]
				r["_when"] = e
				_by_visible["%s|%s" % [label, obj]] = r
		maps[label] = true
	return ""


## The interact event for this object on this map, or null.
func interact_event(label: String, object_key: String):
	return _by_interact.get("%s|%s" % [label, object_key])


## The `visible` query for object_shown: true/false, or null to fall through (no event).
func visible_for(label: String, object_key: String):
	var r = _by_visible.get("%s|%s" % [label, object_key])
	if r == null:
		return null
	return _truthy(r["_when"])


## Run an event's command list as the active cutscene. Fire-and-forget from a hook (the
## hook returns `handled` immediately, exactly as adapters call Cutscene beats today).
func run(rec: Dictionary) -> void:
	main.cutscene_active = true
	main.modal = null
	await _run_block(rec.get("commands", []))
	main.cutscene_active = false


## Execute one block; false = the event aborted (a refused give_item stops the list,
## faithful to Cutscene._gift's early return).
func _run_block(cmds: Array) -> bool:
	for c_v in cmds:
		var c: Dictionary = c_v
		match str(c["cmd"]):
			"say":
				await main.cutscene.say(_interp(str(c["text"])))
			"if":
				var branch: Array = c.get("then", []) if _truthy(c["_cond"]) else c.get("else", [])
				if not await _run_block(branch):
					return false
			"give_item":
				var display := _item_display(str(c["item"]))
				if not main.add_item(display):
					await main.cutscene.say("You don't have\nroom for this!")
					return false
			"set_flag":
				main.set_event(str(c["flag"]))
			"clear_flag":
				main.story_events.erase(str(c["flag"]))
			"sfx":
				if main.audio:
					main.audio.play_sfx(str(c["key"]))
	return true


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
		if cmd == "if":
			var e = _compile_cond(str(c.get("cond", "")))
			if e == null:
				return "event '%s': condition '%s' does not parse" % [key, str(c.get("cond", ""))]
			c["_cond"] = e
			for b in ["then", "else"]:
				var err := _compile_block(c.get(b, []), key)
				if err != "":
					return err
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


func _truthy(cond: Dictionary) -> bool:
	var vars := {}
	for ident in cond["idents"]:
		if main.event_vars.has(ident):
			vars[ident] = main.event_vars[ident]
		else:
			vars[ident] = 1 if main.has_event(str(ident)) else 0
	return bool(cond["expr"].eval(vars))


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
