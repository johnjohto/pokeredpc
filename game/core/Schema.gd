extends RefCounted
class_name CoreSchema
## v2 Core (gh #22, ADR-017): a JSON-Schema-subset validator. The schema documents in
## core/schemas/ are standard draft-2020-12 files (external tools can consume them);
## this validator implements exactly the subset those schemas use, and ERRORS on any
## keyword it does not know — a typo'd keyword must not become phantom validation.
##
## Supported: type, enum, const, required, properties, additionalProperties (bool|schema),
## patternProperties, items, prefixItems, minItems, maxItems, minimum, maximum, minLength,
## maxLength, pattern, anyOf, $ref (#/$defs/... within the same document) — plus the
## project format's own annotations: `x-ref: "<prefix>"` (a string holding a record id of
## that prefix, existence checked by ProjectValidator) and `x-ref-keys: "<prefix>"` (every
## key of an object is such an id). Ignored annotations: $schema, $id, $comment, $defs,
## title, description, default.
##
## Godot JSON parses every number as float; "integer" accepts a float with no fractional
## part (and never a bool).

const _KNOWN := ["$schema", "$id", "$comment", "$defs", "title", "description", "default",
	"type", "enum", "const", "required", "properties", "additionalProperties",
	"patternProperties", "items", "prefixItems", "minItems", "maxItems",
	"minimum", "maximum", "minLength", "maxLength", "pattern", "anyOf", "$ref",
	"x-ref", "x-ref-keys"]


## Validate `inst` against `schema` (with `root` for $defs lookups). Appends
## "path — message" strings to `errors` and {prefix, value, path} dicts to `refs`.
static func validate(inst, schema: Dictionary, root: Dictionary, path: String,
		errors: Array, refs: Array) -> void:
	for k in schema:
		if not _KNOWN.has(str(k)):
			errors.append("%s — unsupported schema keyword '%s'" % [path, k])
			return

	if schema.has("$ref"):
		var target := str(schema["$ref"])
		if not target.begins_with("#/$defs/"):
			errors.append("%s — $ref '%s' is not #/$defs/-local" % [path, target])
			return
		var name := target.substr(8)
		var defs: Dictionary = root.get("$defs", {})
		if not defs.has(name):
			errors.append("%s — $ref target '%s' not found" % [path, target])
			return
		validate(inst, defs[name], root, path, errors, refs)
		return

	if schema.has("anyOf"):
		var branches: Array = schema["anyOf"]
		for branch in branches:
			var be: Array = []
			var br: Array = []
			validate(inst, branch, root, path, be, br)
			if be.is_empty():
				refs.append_array(br)
				return
		errors.append("%s — matches no anyOf branch" % path)
		return

	if schema.has("type") and not _type_ok(inst, str(schema["type"])):
		errors.append("%s — expected %s, got %s" % [path, schema["type"], _name_of(inst)])
		return

	if schema.has("enum"):
		var allowed: Array = schema["enum"]
		if not allowed.has(inst):
			errors.append("%s — value %s not one of %s" % [path, _short(inst), _short(allowed)])
			return
	if schema.has("const") and not _same(inst, schema["const"]):
		errors.append("%s — value %s is not the constant %s" % [path, _short(inst), _short(schema["const"])])
		return

	match typeof(inst):
		TYPE_STRING:
			_validate_string(inst, schema, path, errors, refs)
		TYPE_DICTIONARY:
			_validate_object(inst, schema, root, path, errors, refs)
		TYPE_ARRAY:
			_validate_array(inst, schema, root, path, errors, refs)
		TYPE_FLOAT, TYPE_INT:
			if schema.has("minimum") and float(inst) < float(schema["minimum"]):
				errors.append("%s — %s is below the minimum %s" % [path, _short(inst), schema["minimum"]])
			if schema.has("maximum") and float(inst) > float(schema["maximum"]):
				errors.append("%s — %s is above the maximum %s" % [path, _short(inst), schema["maximum"]])


static func _validate_string(s: String, schema: Dictionary, path: String,
		errors: Array, refs: Array) -> void:
	if schema.has("minLength") and s.length() < int(schema["minLength"]):
		errors.append("%s — string shorter than minLength %d" % [path, int(schema["minLength"])])
	if schema.has("maxLength") and s.length() > int(schema["maxLength"]):
		errors.append("%s — string longer than maxLength %d" % [path, int(schema["maxLength"])])
	if schema.has("pattern") and not _regex_match(str(schema["pattern"]), s):
		errors.append("%s — '%s' does not match pattern %s" % [path, s, schema["pattern"]])
	if schema.has("x-ref"):
		var prefix := str(schema["x-ref"])
		if not s.begins_with(prefix + ":"):
			errors.append("%s — reference '%s' must start with '%s:'" % [path, s, prefix])
		else:
			refs.append({"prefix": prefix, "value": s, "path": path})


static func _validate_object(d: Dictionary, schema: Dictionary, root: Dictionary,
		path: String, errors: Array, refs: Array) -> void:
	for req in schema.get("required", []):
		if not d.has(req):
			errors.append("%s — missing required field '%s'" % [path, req])
	if schema.has("x-ref-keys"):
		var kprefix := str(schema["x-ref-keys"])
		for k in d:
			if not str(k).begins_with(kprefix + ":"):
				errors.append("%s/%s — key must be a '%s:' reference" % [path, k, kprefix])
			else:
				refs.append({"prefix": kprefix, "value": str(k), "path": path + "/" + str(k)})
	var props: Dictionary = schema.get("properties", {})
	var patterns: Dictionary = schema.get("patternProperties", {})
	for k in d:
		var kpath := path + "/" + str(k)
		if props.has(k):
			validate(d[k], props[k], root, kpath, errors, refs)
			continue
		var matched := false
		for pat in patterns:
			if _regex_match(str(pat), str(k)):
				matched = true
				validate(d[k], patterns[pat], root, kpath, errors, refs)
		if matched:
			continue
		var ap = schema.get("additionalProperties", true)
		if ap is bool:
			if not ap:
				errors.append("%s — unknown field '%s'" % [path, k])
		elif ap is Dictionary:
			validate(d[k], ap, root, kpath, errors, refs)


static func _validate_array(a: Array, schema: Dictionary, root: Dictionary,
		path: String, errors: Array, refs: Array) -> void:
	if schema.has("minItems") and a.size() < int(schema["minItems"]):
		errors.append("%s — fewer than minItems %d entries" % [path, int(schema["minItems"])])
	if schema.has("maxItems") and a.size() > int(schema["maxItems"]):
		errors.append("%s — more than maxItems %d entries" % [path, int(schema["maxItems"])])
	var prefix_items: Array = schema.get("prefixItems", [])
	for i in a.size():
		var ipath := "%s/%d" % [path, i]
		if i < prefix_items.size():
			validate(a[i], prefix_items[i], root, ipath, errors, refs)
		elif schema.has("items"):
			validate(a[i], schema["items"], root, ipath, errors, refs)


static func _type_ok(inst, t: String) -> bool:
	match t:
		"object": return inst is Dictionary
		"array": return inst is Array
		"string": return inst is String
		"boolean": return inst is bool
		"null": return inst == null
		"number": return (inst is float or inst is int) and not (inst is bool)
		"integer":
			if inst is bool:
				return false
			if inst is int:
				return true
			return inst is float and inst == floorf(inst)
	return false


static func _name_of(inst) -> String:
	if inst == null:
		return "null"
	if inst is bool:
		return "boolean"
	if inst is float or inst is int:
		return "number"
	if inst is String:
		return "string"
	if inst is Array:
		return "array"
	if inst is Dictionary:
		return "object"
	return type_string(typeof(inst))


static func _short(v) -> String:
	var s := JSON.stringify(v)
	return s if s.length() <= 60 else s.substr(0, 57) + "..."


static func _same(a, b) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)


static func _regex_match(pattern: String, s: String) -> bool:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return false
	return re.search(s) != null
