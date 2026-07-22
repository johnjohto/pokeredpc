extends RefCounted
class_name WorldDocument
## Editable format-2 world graph (gh #55). Maps own local TMX geometry; this document owns
## only reciprocal cardinal placement. Offsets remain in 32px block units for compatibility
## with ADR-023/Kanto. Studio and ProjectValidator share the same semantic checks.

const DIRECTIONS := ["north", "south", "west", "east"]
const OPPOSITE := {"north": "south", "south": "north", "west": "east", "east": "west"}

var project_dir := ""
var path := ""
var data: Dictionary = {}
var _saved: Dictionary = {}


static func open(project_root: String) -> Dictionary:
	# Use the implicit script constructor here. ProjectValidator preloads this script before
	# Godot's global class cache necessarily knows about a newly-added class_name.
	var document = new()
	var error := document._load(project_root)
	return {"ok": error == "", "document": document if error == "" else null,
		"error": error}


func connections(map_label: String) -> Array:
	return ((data.get("maps", {}) as Dictionary).get("map:" + map_label, []) as Array).duplicate(true)


func edit_state() -> Dictionary:
	return data.duplicate(true)


func restore_edit_state(state: Dictionary) -> void:
	data = state.duplicate(true)


func is_dirty() -> bool:
	return data != _saved


func set_connection(source_label: String, direction: String, destination_label: String,
		offset: int) -> String:
	if direction not in DIRECTIONS:
		return "connection direction must be north, south, west, or east"
	if source_label == destination_label:
		return "a map cannot connect to itself"
	if not _map_exists(source_label) or not _map_exists(destination_label):
		return "both connection maps must exist"
	var before := data.duplicate(true)
	var maps: Dictionary = data.get("maps", {})
	var source_key := "map:" + source_label
	var destination_key := "map:" + destination_label
	if not maps.has(source_key):
		maps[source_key] = []
	if not maps.has(destination_key):
		maps[destination_key] = []
	var existing := _connection_in(maps[source_key], direction)
	if not existing.is_empty() and str(existing.get("map", "")) != destination_key:
		data = before
		return "%s is already connected %s to %s" % [source_label, direction,
			_bare(str(existing.get("map", "")))]
	var reverse_direction := str(OPPOSITE[direction])
	var reverse := _connection_in(maps[destination_key], reverse_direction)
	if not reverse.is_empty() and str(reverse.get("map", "")) != source_key:
		data = before
		return "%s is already connected %s to %s" % [destination_label, reverse_direction,
			_bare(str(reverse.get("map", "")))]
	_upsert(maps[source_key], {"direction": direction, "map": destination_key,
		"offset": offset})
	_upsert(maps[destination_key], {"direction": reverse_direction, "map": source_key,
		"offset": -offset})
	data["maps"] = maps
	var errors := validate()
	if not errors.is_empty():
		data = before
		return str(errors[0])
	return ""


func remove_connection(source_label: String, direction: String) -> bool:
	var maps: Dictionary = data.get("maps", {})
	var source_key := "map:" + source_label
	if not maps.has(source_key):
		return false
	var records: Array = maps[source_key]
	var found := _connection_in(records, direction)
	if found.is_empty():
		return false
	var destination_key := str(found.get("map", ""))
	_remove_direction(records, direction)
	if maps.has(destination_key):
		var reverse_records: Array = maps[destination_key]
		var reverse_direction := str(OPPOSITE.get(direction, ""))
		for index in range(reverse_records.size() - 1, -1, -1):
			var candidate: Dictionary = reverse_records[index]
			if str(candidate.get("direction", "")) == reverse_direction \
					and str(candidate.get("map", "")) == source_key:
				reverse_records.remove_at(index)
	return true


func validate() -> Array:
	return validate_data(project_dir, data)


func save() -> String:
	if not is_dirty():
		return ""
	var errors := validate()
	if not errors.is_empty():
		return str(errors[0])
	var error := CanonJSON.write_file(path, data)
	if error == "":
		_saved = data.duplicate(true)
	return error


static func validate_data(project_root: String, world: Dictionary) -> Array:
	var errors: Array = []
	var maps: Dictionary = world.get("maps", {})
	var size_cache := {}
	for source_key in maps:
		var source_label := _bare(str(source_key))
		if not FileAccess.file_exists(project_root.path_join("maps/%s.tmx" % source_label)):
			errors.append("data/world.json: key '%s' names a missing map" % source_key)
			continue
		var directions := {}
		for raw in maps[source_key]:
			if not (raw is Dictionary):
				continue # schema validation owns the structural error
			var connection: Dictionary = raw
			var direction := str(connection.get("direction", ""))
			var destination_key := str(connection.get("map", ""))
			var destination_label := _bare(destination_key)
			var offset := int(connection.get("offset", 0))
			if directions.has(direction):
				errors.append("data/world.json: %s has duplicate %s connections" % [
					source_key, direction])
				continue
			directions[direction] = true
			if direction not in DIRECTIONS or not maps.has(destination_key):
				continue # schema/reference validation reports this more precisely
			var reverse_direction := str(OPPOSITE[direction])
			var reverse_count := 0
			for reverse_raw in maps[destination_key]:
				if reverse_raw is Dictionary:
					var reverse: Dictionary = reverse_raw
					if str(reverse.get("direction", "")) == reverse_direction \
							and str(reverse.get("map", "")) == str(source_key) \
							and int(reverse.get("offset", 0)) == -offset:
						reverse_count += 1
			if reverse_count != 1:
				errors.append("data/world.json: %s %s -> %s offset %d needs exactly one %s reciprocal offset %d" % [
					source_key, direction, destination_key, offset, reverse_direction, -offset])
				continue
			var source_size := _map_block_size(project_root, source_label, size_cache)
			var destination_size := _map_block_size(project_root, destination_label, size_cache)
			if source_size == Vector2i.ZERO or destination_size == Vector2i.ZERO:
				continue
			var overlap := 0
			if direction in ["north", "south"]:
				overlap = mini(source_size.x, offset + destination_size.x) - maxi(0, offset)
			else:
				overlap = mini(source_size.y, offset + destination_size.y) - maxi(0, offset)
			if overlap <= 0:
				errors.append("data/world.json: %s %s -> %s offset %d has no shared edge" % [
					source_key, direction, destination_key, offset])
	return errors


func _load(project_root: String) -> String:
	project_dir = ProjectSettings.globalize_path(project_root).simplify_path()
	path = project_dir.path_join("data/world.json")
	var source := FileAccess.get_file_as_string(path)
	if source == "":
		return "cannot open '%s'" % path
	var parsed = JSON.parse_string(source)
	if not (parsed is Dictionary) or not parsed.has("maps"):
		return "%s — expected a world object with maps" % path
	data = parsed
	_saved = data.duplicate(true)
	return ""


func _map_exists(label: String) -> bool:
	return FileAccess.file_exists(project_dir.path_join("maps/%s.tmx" % label))


static func _connection_in(records: Array, direction: String) -> Dictionary:
	for record in records:
		if record is Dictionary and str(record.get("direction", "")) == direction:
			return record
	return {}


static func _upsert(records: Array, connection: Dictionary) -> void:
	for index in records.size():
		if str((records[index] as Dictionary).get("direction", "")) == str(connection["direction"]):
			records[index] = connection
			return
	records.append(connection)


static func _remove_direction(records: Array, direction: String) -> void:
	for index in range(records.size() - 1, -1, -1):
		if str((records[index] as Dictionary).get("direction", "")) == direction:
			records.remove_at(index)


static func _map_block_size(project_root: String, label: String, cache: Dictionary) -> Vector2i:
	if cache.has(label):
		return cache[label]
	var opened := MapDocument.open(project_root, label)
	if not bool(opened.get("ok", false)):
		cache[label] = Vector2i.ZERO
		return Vector2i.ZERO
	var document: MapDocument = opened["document"]
	var size := Vector2i(ceili(float(document.width) / 2.0),
		ceili(float(document.height) / 2.0))
	cache[label] = size
	return size


static func _bare(map_id: String) -> String:
	return map_id.substr(4) if map_id.begins_with("map:") else map_id
