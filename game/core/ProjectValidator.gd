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

const SUPPORTED_FORMAT := 1
const SCHEMA_DIR := "res://core/schemas/"


## Validate the project at `dir` (res:// or an OS path).
## Returns {ok: bool, errors: [String], files: int, ids: {prefix: count}}.
static func validate_project(dir: String) -> Dictionary:
	var errors: Array = []
	var format: Dictionary = _load_json_file(SCHEMA_DIR + "format.json", errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "files": 0, "ids": {}}
	var layout: Array = format.get("layout", [])
	var schemas := {}
	for entry in layout:
		var sname := str(entry.get("schema", ""))
		if sname != "" and not schemas.has(sname):
			schemas[sname] = _load_json_file(SCHEMA_DIR + sname + ".schema.json", errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "files": 0, "ids": {}}

	var files := _walk(dir, "")
	var ids := {}                       # prefix -> {full_id: true}
	var refs: Array = []                # {prefix, value, path(file-qualified)}

	# The manifest gates everything: read it first so a format refusal leads the report.
	if files.has("manifest.json"):
		var m_errors: Array = []
		var manifest = _load_json_file(dir.path_join("manifest.json"), m_errors)
		if m_errors.is_empty() and manifest is Dictionary and manifest.has("format"):
			var fmt = manifest["format"]
			if (fmt is float or fmt is int) and int(fmt) > SUPPORTED_FORMAT:
				errors.append("manifest.json — project format %d; this build supports format %d — update the engine"
					% [int(fmt), SUPPORTED_FORMAT])
				return {"ok": false, "errors": errors, "files": files.size(), "ids": {}}
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
		if kind == "table" and entry.has("declares") and inst is Dictionary:
			_register_declared(entry["declares"], inst, ids)

	for r in refs:
		var prefix := str(r["prefix"])
		var have: Dictionary = ids.get(prefix, {})
		if not have.has(str(r["value"])):
			errors.append("%s — dangling reference '%s' — no %s with that id"
				% [r["path"], r["value"], prefix])

	var counts := {}
	for prefix in ids:
		counts[prefix] = (ids[prefix] as Dictionary).size()
	return {"ok": errors.is_empty(), "errors": errors, "files": files.size(), "ids": counts}


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
