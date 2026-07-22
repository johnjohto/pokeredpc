extends RefCounted
class_name EventDocument
## Editable event record (gh #56). The schema is the source of truth for both the
## command palette and command defaults; nested block paths let Studio edit if/ask
## branches without knowing the VM's command vocabulary.

var project_dir := ""
var basename := ""
var path := ""
var data: Dictionary = {}
var schema: Dictionary = {}
var context: Dictionary = {}
var _saved: Dictionary = {}
var _source := ""


static func open(project_root: String, event_basename: String) -> Dictionary:
	var document = new()
	var error := document._load(project_root, event_basename)
	return {"ok": error == "", "document": document if error == "" else null,
		"error": error}


static func create(project_root: String, event_basename: String, trigger: Dictionary) -> Dictionary:
	var document = new()
	var error := document._initialize(project_root, event_basename,
		{"id": "event:" + event_basename, "trigger": trigger.duplicate(true), "commands": []})
	if error == "" and FileAccess.file_exists(document.path):
		error = "event '%s' already exists" % event_basename
	return {"ok": error == "", "document": document if error == "" else null,
		"error": error}


func edit_state() -> Dictionary:
	return data.duplicate(true)


func restore_edit_state(state: Dictionary) -> void:
	data = state.duplicate(true)


func is_dirty() -> bool:
	return data != _saved


func command_kinds() -> Array:
	var out: Array = []
	for command_schema in command_schemas():
		var properties: Dictionary = command_schema.get("properties", {})
		var cmd_schema: Dictionary = properties.get("cmd", {})
		if cmd_schema.has("const"):
			out.append(str(cmd_schema["const"]))
	return out


func command_schemas() -> Array:
	var block: Dictionary = resolve_schema({"$ref": "#/$defs/block"})
	var item: Dictionary = resolve_schema(block.get("items", {}))
	return item.get("anyOf", [])


func command_schema(kind: String) -> Dictionary:
	for candidate in command_schemas():
		var resolved := resolve_schema(candidate)
		var cmd: Dictionary = (resolved.get("properties", {}) as Dictionary).get("cmd", {})
		if str(cmd.get("const", "")) == kind:
			return resolved
	return {}


func trigger_schema() -> Dictionary:
	return resolve_schema((schema.get("properties", {}) as Dictionary).get("trigger", {}))


func resolve_schema(candidate) -> Dictionary:
	if not (candidate is Dictionary):
		return {}
	var resolved: Dictionary = candidate
	var seen := {}
	while resolved.has("$ref"):
		var ref := str(resolved["$ref"])
		if seen.has(ref) or not ref.begins_with("#/$defs/"):
			return {}
		seen[ref] = true
		var name := ref.substr(8)
		var defs: Dictionary = schema.get("$defs", {})
		if not defs.has(name):
			return {}
		resolved = defs[name]
	return resolved


func default_for(candidate):
	var source: Dictionary = resolve_schema(candidate)
	if source.has("default"):
		return source["default"]
	if source.has("const"):
		return source["const"]
	if source.has("enum"):
		var values: Array = source["enum"]
		return values[0] if not values.is_empty() else ""
	if source.has("anyOf"):
		var branches: Array = source["anyOf"]
		return default_for(branches[0]) if not branches.is_empty() else null
	match str(source.get("type", "")):
		"object":
			var out := {}
			var properties: Dictionary = source.get("properties", {})
			for key in source.get("required", []):
				if properties.has(key):
					out[key] = default_for(properties[key])
			return out
		"array":
			var out: Array = []
			var prefix: Array = source.get("prefixItems", [])
			for item_schema in prefix:
				out.append(default_for(item_schema))
			var minimum := int(source.get("minItems", 0))
			while out.size() < minimum:
				out.append(default_for(source.get("items", {})))
			return out
		"integer", "number": return int(source.get("minimum", 0))
		"boolean": return false
		"string": return ""
	return null


## A block path is [] for /commands, or alternating command-index/branch-name tokens,
## e.g. [2, "then", 0, "else"]. A command path ends with its command index.
func block_at(block_path: Array):
	var current = data.get("commands", [])
	for token in block_path:
		if token is int:
			if not (current is Array) or token < 0 or token >= current.size():
				return null
			current = current[token]
		else:
			if not (current is Dictionary) or not current.has(str(token)):
				return null
			current = current[str(token)]
	return current if current is Array else null


func command_at(command_path: Array):
	if command_path.is_empty() or not (command_path[-1] is int):
		return null
	var block = block_at(command_path.slice(0, command_path.size() - 1))
	var index: int = command_path[-1]
	if not (block is Array) or index < 0 or index >= block.size():
		return null
	return block[index]


func add_command(block_path: Array, kind: String, index := -1) -> String:
	var block = block_at(block_path)
	var command_schema_value := command_schema(kind)
	if not (block is Array):
		return "command block does not exist"
	if command_schema_value.is_empty():
		return "unknown event command '%s'" % kind
	var command = default_for(command_schema_value)
	if not (command is Dictionary):
		return "command schema for '%s' is not an object" % kind
	var at: int = block.size() if index < 0 else clampi(index, 0, block.size())
	block.insert(at, command)
	return ""


func remove_command(command_path: Array) -> bool:
	if command_path.is_empty() or not (command_path[-1] is int):
		return false
	var block = block_at(command_path.slice(0, command_path.size() - 1))
	var index: int = command_path[-1]
	if not (block is Array) or index < 0 or index >= block.size():
		return false
	block.remove_at(index)
	return true


func duplicate_command(command_path: Array) -> bool:
	var command = command_at(command_path)
	if not (command is Dictionary):
		return false
	var block = block_at(command_path.slice(0, command_path.size() - 1))
	var index: int = command_path[-1]
	block.insert(index + 1, command.duplicate(true))
	return true


func move_command(command_path: Array, delta: int) -> bool:
	if command_path.is_empty() or not (command_path[-1] is int):
		return false
	var block = block_at(command_path.slice(0, command_path.size() - 1))
	var from: int = command_path[-1]
	var to := from + delta
	if not (block is Array) or from < 0 or from >= block.size() or to < 0 or to >= block.size():
		return false
	var command = block[from]
	block.remove_at(from)
	block.insert(to, command)
	return true


func replace_command(command_path: Array, value: Dictionary) -> bool:
	if command_path.is_empty() or not (command_path[-1] is int):
		return false
	var block = block_at(command_path.slice(0, command_path.size() - 1))
	var index: int = command_path[-1]
	if not (block is Array) or index < 0 or index >= block.size():
		return false
	block[index] = value.duplicate(true)
	return true


func set_trigger(value: Dictionary) -> void:
	data["trigger"] = value.duplicate(true)


func validate() -> Array:
	return ProjectValidator.validate_event_editor_record(project_dir, basename, data, context)


func save() -> String:
	if not is_dirty() and FileAccess.file_exists(path):
		return ""
	var errors := validate()
	if not errors.is_empty():
		return str(errors[0])
	var error := CanonJSON.write_file(path, data)
	if error == "":
		_saved = data.duplicate(true)
		_source = CanonJSON.serialize(data) + "\n"
	return error


func _load(project_root: String, event_basename: String) -> String:
	var file_path := ProjectSettings.globalize_path(project_root).simplify_path() \
		.path_join("data/events/%s.json" % event_basename)
	var source := FileAccess.get_file_as_string(file_path)
	if source == "":
		return "cannot open '%s'" % file_path
	var parsed = JSON.parse_string(source)
	if not (parsed is Dictionary):
		return "cannot parse '%s' as an event record" % file_path
	var error := _initialize(project_root, event_basename, parsed)
	if error == "":
		_source = source
		_saved = data.duplicate(true)
	return error


func _initialize(project_root: String, event_basename: String, initial: Dictionary) -> String:
	if not _valid_basename(event_basename):
		return "event name must use lowercase letters, numbers, and underscores"
	project_dir = ProjectSettings.globalize_path(project_root).simplify_path()
	basename = event_basename
	path = project_dir.path_join("data/events/%s.json" % basename)
	context = ProjectValidator.editor_context(project_dir, "events")
	if not bool(context.get("ok", false)):
		return "; ".join(PackedStringArray(context.get("errors", [])))
	schema = context.get("schema", {})
	data = initial.duplicate(true)
	_saved = {} if not FileAccess.file_exists(path) else data.duplicate(true)
	return ""


static func _valid_basename(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[a-z0-9_]+$")
	return regex.search(value) != null
