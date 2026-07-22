extends RefCounted
class_name ProjectValidator
## v2 Core (gh #22, ADR-017): validates a project directory against the format contract
## (core/schemas/format.json + the per-type schemas). This is the seed of the Phase-5
## lint engine and the same walk the gh #25 runtime loader will trust.
##
## Rules enforced:
##  - manifest.json exists, parses, and its integer `format` is not newer than this
##    build supports (refuse-newer NAMES both versions — the link-refusal pattern,
##    ADR-017 d7).
##  - every file is claimed by exactly one layout entry (first match wins); an
##    unclaimed file is an error, so a typo'd path can't silently ship dead data.
##  - every JSON file parses and validates against its schema (CoreSchema).
##  - kind=record: the file's id field equals id_prefix:basename (bare_id: the field
##    holds the bare basename, as v1's interim map JSON does); ids register for refs.
##  - kind=table with `declares`: the pointed-at array registers ids (the type chart
##    declares `type:` ids this way).
##  - after the walk, every `x-ref`/`x-ref-keys` reference must resolve to a
##    registered id ("dangling reference" errors name the ref and its file).
##  - event records (gh #42, ADR-019): every object a trigger or command names must
##    exist on the record's map, and every declared cell/region must lie inside it —
##    a dangling trigger seals a path as silently as dead code would.

const SUPPORTED_FORMAT := 1
const SCHEMA_DIR := "res://core/schemas/"


## Validate the project at `dir` (res:// or an OS path).
## Returns {ok: bool, errors: [String], files: int, ids: {prefix: count}}.
static func validate_project(dir: String) -> Dictionary:
	var errors: Array = []
	var format: Dictionary = _load_json_file(SCHEMA_DIR + "format.json", errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "files": 0, "ids": {}, "id_registry": {}}
	var layout: Array = format.get("layout", [])
	var schemas := {}
	for entry in layout:
		var sname := str(entry.get("schema", ""))
		if sname != "" and not schemas.has(sname):
			schemas[sname] = _load_json_file(SCHEMA_DIR + sname + ".schema.json", errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "files": 0, "ids": {}, "id_registry": {}}

	var files := _walk(dir, "")
	var ids := {}                       # prefix -> {full_id: true}
	var refs: Array = []                # {prefix, value, path(file-qualified)}
	var events: Array = []              # event records, for the semantic pass (gh #42)

	# The manifest gates everything: read it first so a format refusal leads the report.
	if files.has("manifest.json"):
		var m_errors: Array = []
		var manifest = _load_json_file(dir.path_join("manifest.json"), m_errors)
		if m_errors.is_empty() and manifest is Dictionary and manifest.has("format"):
			var fmt = manifest["format"]
			if (fmt is float or fmt is int) and int(fmt) > SUPPORTED_FORMAT:
				errors.append("manifest.json — project format %d; this build supports format %d — update the engine"
					% [int(fmt), SUPPORTED_FORMAT])
				return {"ok": false, "errors": errors, "files": files.size(), "ids": {},
					"id_registry": {}}
	else:
		errors.append("manifest.json — missing (a project requires a manifest)")

	for rel in files:
		var entry := _match_layout(layout, rel)
		if entry.is_empty():
			errors.append("%s — unclaimed file (no place in the project format)" % rel)
			continue
		var kind := str(entry.get("kind", ""))
		if kind == "asset":
			continue
		var file_errors: Array = []
		var inst = _load_json_file(dir.path_join(rel), file_errors)
		if not file_errors.is_empty():
			for e in file_errors:
				errors.append("%s — %s" % [rel, str(e).trim_prefix(dir.path_join(rel) + " — ")])
			continue
		var schema: Dictionary = schemas.get(str(entry.get("schema", "")), {})
		var file_refs: Array = []
		var verrors: Array = []
		CoreSchema.validate(inst, schema, schema, "", verrors, file_refs)
		for e in verrors:
			errors.append("%s: %s" % [rel, e])
		for r in file_refs:
			refs.append({"prefix": r["prefix"], "value": r["value"],
				"path": "%s: %s" % [rel, r["path"]]})
		if kind == "record" and inst is Dictionary:
			_register_record(entry, rel, inst, ids, errors)
			if str(entry.get("id_prefix", "")) == "event":
				events.append({"rel": rel, "inst": inst})
		if kind == "table" and entry.has("declares") and inst is Dictionary:
			_register_declared(entry["declares"], inst, ids)

	_check_events(dir, events, errors)

	for r in refs:
		var prefix := str(r["prefix"])
		var have: Dictionary = ids.get(prefix, {})
		if not have.has(str(r["value"])):
			errors.append("%s — dangling reference '%s' — no %s with that id"
				% [r["path"], r["value"], prefix])

	var counts := {}
	for prefix in ids:
		counts[prefix] = (ids[prefix] as Dictionary).size()
	return {"ok": errors.is_empty(), "errors": errors, "files": files.size(), "ids": counts,
		"id_registry": ids}


## Studio's form context comes from the same format walk and schema files as project
## validation: no parallel type list or reference index can drift from the boot gate.
## `ids` is prefix -> {full_id: true}; pickers sort those keys for display.
static func editor_context(dir: String, content_type: String) -> Dictionary:
	var report := validate_project(dir)
	var errors: Array = (report.get("errors", []) as Array).duplicate()
	var format = _load_json_file(SCHEMA_DIR + "format.json", errors)
	var entry: Dictionary = {}
	if format is Dictionary:
		var wanted := "data/%s/*.json" % content_type
		for candidate in format.get("layout", []):
			if str(candidate.get("path", "")) == wanted:
				entry = candidate
				break
	if entry.is_empty():
		errors.append("no record schema for content type '%s'" % content_type)
		return {"ok": false, "errors": errors, "schema": {}, "ids": {}, "entry": {}}
	var schema = _load_json_file(
		SCHEMA_DIR + str(entry.get("schema", "")) + ".schema.json", errors)
	return {"ok": errors.is_empty(), "errors": errors, "schema": schema,
		"ids": report.get("id_registry", {}), "entry": entry}


## Validate one in-memory editor draft without touching disk. This is the save
## preflight: the record gets the full CoreSchema pass, filename identity rule, and
## resolution against the exact id registry built by validate_project().
static func validate_editor_record(basename: String, record: Dictionary,
		context: Dictionary) -> Array:
	var errors: Array = []
	if not bool(context.get("ok", false)):
		errors.append_array(context.get("errors", []))
		return errors
	var schema: Dictionary = context.get("schema", {})
	var refs: Array = []
	CoreSchema.validate(record, schema, schema, "", errors, refs)
	var entry: Dictionary = context.get("entry", {})
	var prefix := str(entry.get("id_prefix", ""))
	var id_field := str(entry.get("id_field", "id"))
	var expected := basename if bool(entry.get("bare_id", false)) else prefix + ":" + basename
	var got := str(record.get(id_field, ""))
	if got != expected:
		errors.append("/%s — record id '%s' does not match filename (expected '%s')"
			% [id_field, got, expected])
	var registry: Dictionary = context.get("ids", {})
	for ref in refs:
		var ref_prefix := str(ref["prefix"])
		var have: Dictionary = registry.get(ref_prefix, {})
		if not have.has(str(ref["value"])):
			errors.append("%s — dangling reference '%s' — no %s with that id"
				% [ref["path"], ref["value"], ref_prefix])
	return errors


# ---- event semantics (gh #42, ADR-019 consequences) ---------------------------------

## Commands that name a map object.
const _OBJECT_CMDS := ["trainer_battle", "set_npc_text", "hide_object", "show_object",
	"face_object", "walk_object", "walk_object_to", "walk_together_to", "place_object",
	"walk_both_to"]


## Every object an event names must exist on its map; every cell must lie inside it.
static func _check_events(dir: String, events: Array, errors: Array) -> void:
	var maps := {}                      # label -> {objects, w, h} or null (missing)
	for ev in events:
		var rel: String = ev["rel"]
		var inst: Dictionary = ev["inst"]
		var t: Dictionary = inst.get("trigger", {})
		var label := _bare_id(str(t.get("map", "")))
		var m = _map_info(dir, label, maps)
		if m == null:
			continue                    # the x-ref pass reports the dangling map itself
		if t.has("object") and not (m["objects"] as Dictionary).has(str(t["object"])):
			errors.append("%s — names object '%s', which is not on map '%s'" % [rel, str(t["object"]), label])
		_check_cmd_objects(inst.get("commands", []), label, dir, maps, errors, rel)
		var cw: int = int(m["w"]) * 2
		var ch: int = int(m["h"]) * 2
		for c in t.get("cells", []) + t.get("front", []) + t.get("at", []):
			if int(c[0]) < 0 or int(c[1]) < 0 or int(c[0]) >= cw or int(c[1]) >= ch:
				errors.append("%s — cell (%d,%d) is outside map '%s' (%dx%d cells)"
					% [rel, int(c[0]), int(c[1]), label, cw, ch])
		if t.has("region"):
			var rg: Array = t["region"]
			if rg.size() == 4 and (int(rg[0]) < 0 or int(rg[1]) < 0
					or int(rg[2]) >= cw or int(rg[3]) >= ch):
				errors.append("%s — region %s exceeds map '%s' (%dx%d cells)"
					% [rel, str(rg), label, cw, ch])


## Walk a block with a CURRENT-map context: `warp_to` re-points object resolution at its
## target — an event's command stream crosses maps exactly where pokered's script does
## (the Oak intercept walks Pallet into the lab). Branches inherit the context at entry;
## the parent keeps its own afterwards — a static approximation that holds because Kanto's
## cross-map records are linear tails (a warp_to inside a branch whose parent then names
## objects would need per-path analysis; the lint would flag it loudly, not miss it).
static func _check_cmd_objects(cmds, label: String, dir: String, maps: Dictionary, errors: Array, rel: String) -> void:
	if not (cmds is Array):
		return
	for c in cmds:
		if not (c is Dictionary):
			continue
		var cmd := str(c.get("cmd", ""))
		if cmd == "warp_to":
			label = _bare_id(str(c.get("map", "")))
		elif _OBJECT_CMDS.has(cmd) and c.has("object"):
			var m = _map_info(dir, label, maps)
			if m != null and not (m["objects"] as Dictionary).has(str(c["object"])):
				errors.append("%s — names object '%s', which is not on map '%s'" % [rel, str(c["object"]), label])
		elif cmd == "if" or cmd == "ask":
			_check_cmd_objects(c.get("then", []), label, dir, maps, errors, rel)
			_check_cmd_objects(c.get("else", []), label, dir, maps, errors, rel)


## The map's object keys + cell dimensions, cached; null when the map file is absent.
static func _map_info(dir: String, label: String, cache: Dictionary):
	if cache.has(label):
		return cache[label]
	var path := dir.path_join("maps/%s.json" % label)
	if not FileAccess.file_exists(path):
		cache[label] = null
		return null
	var errs: Array = []
	var m = _load_json_file(path, errs)
	if not errs.is_empty() or not (m is Dictionary):
		cache[label] = null
		return null
	var objects := {}
	for o in m.get("object_events", []):
		if o is Dictionary:
			objects["%s@%d,%d" % [str(o.get("sprite", "")), int(o.get("x", -1)), int(o.get("y", -1))]] = true
	var info := {"objects": objects, "w": int(m.get("width", 0)), "h": int(m.get("height", 0))}
	cache[label] = info
	return info


static func _bare_id(id: String) -> String:
	return id.substr(id.find(":") + 1)


static func _register_record(entry: Dictionary, rel: String, inst: Dictionary,
		ids: Dictionary, errors: Array) -> void:
	var prefix := str(entry.get("id_prefix", ""))
	var id_field := str(entry.get("id_field", "id"))
	var base := rel.get_file().get_basename()
	var expected := base if bool(entry.get("bare_id", false)) else prefix + ":" + base
	var got := str(inst.get(id_field, ""))
	if got != expected:
		errors.append("%s — record %s '%s' does not match its filename (expected '%s')"
			% [rel, id_field, got, expected])
	if not ids.has(prefix):
		ids[prefix] = {}
	ids[prefix][prefix + ":" + base] = true


static func _register_declared(declares: Dictionary, inst: Dictionary, ids: Dictionary) -> void:
	var prefix := str(declares.get("prefix", ""))
	var node = inst
	for seg in str(declares.get("pointer", "")).split("/", false):
		if node is Dictionary and node.has(seg):
			node = node[seg]
		else:
			return                      # schema validation already reported the shape
	if node is Array:
		if not ids.has(prefix):
			ids[prefix] = {}
		for v in node:
			ids[prefix][str(v)] = true


## First layout entry whose path pattern claims `rel`; {} when unclaimed. Patterns are
## segment-wise globs ('*' within one segment); a trailing '**' claims a whole subtree.
static func _match_layout(layout: Array, rel: String) -> Dictionary:
	for entry in layout:
		var pattern := str(entry.get("path", ""))
		if pattern.ends_with("/**"):
			if rel.begins_with(pattern.substr(0, pattern.length() - 2)):
				return entry
			continue
		var psegs := pattern.split("/")
		var rsegs := rel.split("/")
		if psegs.size() != rsegs.size():
			continue
		var all := true
		for i in psegs.size():
			if not rsegs[i].match(psegs[i]):
				all = false
				break
		if all:
			return entry
	return {}


## Recursive listing of relative file paths ('/'-joined), .import noise skipped.
static func _walk(root: String, rel: String) -> Dictionary:
	var out := {}
	var da := DirAccess.open(root.path_join(rel) if rel != "" else root)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if not name.begins_with("."):
			var child := name if rel == "" else rel + "/" + name
			if da.current_is_dir():
				out.merge(_walk(root, child))
			elif not name.ends_with(".import"):
				out[child] = true
		name = da.get_next()
	da.list_dir_end()
	return out


static func _load_json_file(path: String, errors: Array):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s — cannot open (%s)" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		errors.append("%s — JSON parse error at line %d: %s" % [path, j.get_error_line(), j.get_error_message()])
		return {}
	return j.data
