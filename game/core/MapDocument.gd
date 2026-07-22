extends RefCounted
class_name MapDocument
## Phase-5 native map module (gh #52/#54, ADR-021/024). Core, Engine, Studio, and the
## validator all cross this one seam: open a Tiled TMX map into a normalized
## 16x16-cell document, or target owned TMX fields without reserializing XML. XML/Tiled
## details, path containment, TSX properties, CSV GIDs, and object conventions
## stay behind this interface instead of leaking into four callers.

const BRIDGE_FORMAT := 1
const CELL_SIZE := 16
const GID_FLIP_MASK := 0xE0000000
static var _tsx_cache := {}             # absolute path + exact source hash -> normalized TSX

var project_dir := ""
var label := ""
var path := ""
var source_bytes := PackedByteArray()
var width := 0
var height := 0
var tiles := PackedInt32Array()       # row-major local TSX tile ids
var walkable := PackedByteArray()     # row-major, 1 = player may stand
var feet_tiles := PackedInt32Array()  # ruleset semantic id; local id by default
var border_tile := 0
var border_block := -1
var block_width := 0
var block_height := 0
var blocks: Array = []                # optional reversible 32px authoring groups
var default_spawn := Vector2i.ZERO
var tileset: Dictionary = {}
var warps: Array = []
var signs: Array = []
var objects: Array = []
var triggers: Array = []
var properties: Dictionary = {}
var _first_gid := 1
var _next_layer_id := 1
var _has_collision_layer := false
var _collision_authored := false
var _saved_tiles := PackedInt32Array()
var _saved_walkable := PackedByteArray()


## Open maps/<label>.tmx and its external TSX. Returns
## {ok:true, document:MapDocument} or {ok:false, error:String}; callers never
## need to understand XMLParser or partial parse state.
static func open(project_root: String, map_label: String) -> Dictionary:
	var document := MapDocument.new()
	var error := document._load(project_root, map_label)
	return {"ok": error == "", "document": document if error == "" else null,
		"error": error}


## Create a minimal format-2 TMX map against an existing project TSX, then open it through
## the normal refusal boundary. Studio owns the UX; Core owns safe paths and valid source.
static func create(project_root: String, map_label: String, map_width: int, map_height: int,
		tileset_file: String) -> Dictionary:
	var label_regex := RegEx.new()
	label_regex.compile("^[A-Za-z][A-Za-z0-9_]*$")
	if label_regex.search(map_label) == null:
		return {"ok": false, "document": null,
			"error": "map name must start with a letter and use only letters, numbers, or _"}
	if map_width < 1 or map_height < 1 or map_width > 256 or map_height > 256:
		return {"ok": false, "document": null, "error": "map size must be between 1 and 256 cells"}
	if tileset_file.get_file() != tileset_file or not tileset_file.to_lower().ends_with(".tsx"):
		return {"ok": false, "document": null, "error": "choose a project tileset"}
	var root := _absolute(project_root)
	var map_path := root.path_join("maps/%s.tmx" % map_label).simplify_path()
	var tsx_path := root.path_join("tilesets").path_join(tileset_file).simplify_path()
	if not _is_inside(root, map_path) or not _is_inside(root, tsx_path):
		return {"ok": false, "document": null, "error": "new map path escapes the project"}
	if FileAccess.file_exists(map_path):
		return {"ok": false, "document": null, "error": "map '%s' already exists" % map_label}
	var probe := MapDocument.new()
	probe.project_dir = root
	var loaded_tsx := probe._load_tsx(tsx_path)
	if not bool(loaded_tsx.get("ok", false)):
		return {"ok": false, "document": null, "error": str(loaded_tsx.get("error", "invalid tileset"))}
	var normalized: Dictionary = loaded_tsx["tileset"]
	var tile_id := 0
	for candidate in int(normalized.get("tile_count", 0)):
		var props: Dictionary = (normalized.get("tile_properties", {}) as Dictionary).get(candidate, {})
		if bool(props.get("pokeredpc:walkable", false)):
			tile_id = candidate
			break
	var gids := PackedInt32Array()
	gids.resize(map_width * map_height)
	gids.fill(tile_id + 1)
	var rows := PackedStringArray()
	for y in map_height:
		var row := PackedStringArray()
		for x in map_width:
			row.append(str(gids[y * map_width + x]))
		rows.append(",".join(row))
	var csv := ",\n".join(rows)
	var source := """<?xml version="1.0" encoding="UTF-8"?>
<map version="1.11" tiledversion="1.11.2" orientation="orthogonal" renderorder="right-down" width="%d" height="%d" tilewidth="16" tileheight="16" infinite="0" nextlayerid="2" nextobjectid="1">
 <properties>
  <property name="pokeredpc:format" type="int" value="1"/>
  <property name="pokeredpc:border_tile" type="int" value="%d"/>
  <property name="pokeredpc:default_spawn" value="0,0"/>
 </properties>
 <tileset firstgid="1" source="../tilesets/%s"/>
 <layer id="1" name="Ground" width="%d" height="%d">
  <data encoding="csv">
%s
  </data>
 </layer>
</map>
""" % [map_width, map_height, tile_id, _xml_escape(tileset_file), map_width, map_height, csv]
	DirAccess.make_dir_recursive_absolute(map_path.get_base_dir())
	var file := FileAccess.open(map_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "document": null, "error": "cannot create '%s' (%s)" % [
			map_path, error_string(FileAccess.get_open_error())]}
	file.store_string(source)
	file.close()
	return open(root, map_label)


## Persist the document. A no-op writes the original bytes exactly. An edit patches only
## Ground CSV and the owned optional Collision layer; every unrelated byte survives.
func save(target_path := "") -> String:
	var out := path if target_path == "" else _absolute(target_path)
	var emitted := _edited_source()
	if not bool(emitted.get("ok", false)):
		return str(emitted.get("error", "cannot serialize map"))
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		return "cannot write '%s' (%s)" % [out, error_string(FileAccess.get_open_error())]
	file.store_buffer(emitted["bytes"])
	file.close()
	if out == path:
		source_bytes = emitted["bytes"]
		_saved_tiles = tiles.duplicate()
		_saved_walkable = walkable.duplicate()
		_has_collision_layer = bool(emitted.get("has_collision", _has_collision_layer))
		_collision_authored = _has_collision_layer
		_next_layer_id = int(emitted.get("next_layer_id", _next_layer_id))
	return ""


func is_dirty() -> bool:
	return tiles != _saved_tiles or walkable != _saved_walkable


func edit_state() -> Dictionary:
	return {"tiles": tiles.duplicate(), "walkable": walkable.duplicate(),
		"collision_authored": _collision_authored}


func restore_edit_state(state: Dictionary) -> void:
	var restored_tiles: PackedInt32Array = state.get("tiles", PackedInt32Array())
	var restored_walkable: PackedByteArray = state.get("walkable", PackedByteArray())
	if restored_tiles.size() != width * height or restored_walkable.size() != width * height:
		return
	tiles = restored_tiles.duplicate()
	walkable = restored_walkable.duplicate()
	_collision_authored = bool(state.get("collision_authored", _has_collision_layer))
	_refresh_tile_metadata()
	_rebuild_blocks()


func set_tile(cell: Vector2i, tile_id: int) -> bool:
	if not _contains(cell) or tile_id < 0 or tile_id >= int(tileset.get("tile_count", 0)):
		return false
	var index := cell.y * width + cell.x
	if int(tiles[index]) == tile_id:
		return false
	tiles[index] = tile_id
	var props: Dictionary = (tileset.get("tile_properties", {}) as Dictionary).get(tile_id, {})
	feet_tiles[index] = int(props.get("pokeredpc:feet_tile", tile_id))
	if not _collision_authored:
		walkable[index] = 1 if bool(props.get("pokeredpc:walkable", false)) else 0
	_rebuild_block_at(Vector2i(cell.x / 2, cell.y / 2))
	return true


func set_walkable(cell: Vector2i, value: bool) -> bool:
	if not _contains(cell):
		return false
	var index := cell.y * width + cell.x
	var byte := 1 if value else 0
	if int(walkable[index]) == byte:
		return false
	walkable[index] = byte
	_collision_authored = true
	return true


func fill_tile(start: Vector2i, tile_id: int) -> bool:
	if not _contains(start) or tile_id < 0 or tile_id >= int(tileset.get("tile_count", 0)):
		return false
	var from := tile_at(start)
	if from == tile_id:
		return false
	var pending: Array[Vector2i] = [start]
	var seen := {}
	var changed := false
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		if seen.has(cell) or not _contains(cell) or tile_at(cell) != from:
			continue
		seen[cell] = true
		changed = set_tile(cell, tile_id) or changed
		pending.append(cell + Vector2i.LEFT)
		pending.append(cell + Vector2i.RIGHT)
		pending.append(cell + Vector2i.UP)
		pending.append(cell + Vector2i.DOWN)
	return changed


func paint_block(cell: Vector2i, block_id: int) -> bool:
	var groups: Dictionary = tileset.get("block_tiles", {})
	if not groups.has(block_id):
		return false
	var origin := Vector2i(cell.x / 2 * 2, cell.y / 2 * 2)
	if not _contains(origin) or not _contains(origin + Vector2i.ONE):
		return false
	var changed := false
	var group: Array = groups[block_id]
	for quadrant in 4:
		changed = set_tile(origin + Vector2i(quadrant % 2, quadrant / 2),
			int(group[quadrant])) or changed
	return changed


func block_for_tile(tile_id: int) -> int:
	var member: Array = (tileset.get("tile_blocks", {}) as Dictionary).get(tile_id, [])
	return int(member[0]) if member.size() == 2 else -1


## Engine adapter: the native document expressed as the map dictionary Main
## already receives. `_native=tmx` selects the cell renderer; the familiar
## warp/sign/object arrays keep story/runtime code independent of serialization.
func runtime_map() -> Dictionary:
	var tile_rows: Array = []
	var collision_rows: Array = []
	var feet_rows: Array = []
	for y in height:
		var tr: Array = []
		var cr: Array = []
		var fr: Array = []
		for x in width:
			var i := y * width + x
			tr.append(tiles[i])
			cr.append(walkable[i])
			fr.append(feet_tiles[i])
		tile_rows.append(tr)
		collision_rows.append(cr)
		feet_rows.append(fr)
	var out := {
		"_native": "tmx", "name": label, "tileset": str(tileset.get("name", "")),
		"cell_width": width, "cell_height": height, "tiles": tile_rows,
		"cell_walkable": collision_rows, "cell_feet": feet_rows,
		"border_tile": border_tile, "default_spawn": [default_spawn.x, default_spawn.y],
		"warps": _runtime_records(warps), "connections": [],
		"bg_events": _runtime_records(signs), "object_events": _runtime_records(objects),
		"triggers": triggers.duplicate(true), "_tileset": tileset.duplicate(true)}
	if not blocks.is_empty():
		out["width"] = block_width
		out["height"] = block_height
		out["blocks"] = blocks.duplicate(true)
		out["border_block"] = border_block
	return out


## Exact format-1-shaped semantic view used only by the Kanto migration oracle.
## Native runtime-only cell/atlas fields stay out, so parity cannot accidentally
## pass by comparing two serialization-specific structures.
func legacy_map(connections: Array = []) -> Dictionary:
	return {"name": label, "tileset": str(tileset.get("name", "")),
		"width": block_width, "height": block_height, "blocks": blocks.duplicate(true),
		"border_block": border_block, "warps": _runtime_records(warps),
		"connections": connections.duplicate(true), "bg_events": _runtime_records(signs),
		"object_events": _runtime_records(objects)}


static func _runtime_records(records: Array) -> Array:
	var out: Array = []
	for record in records:
		var normalized: Dictionary = record
		out.append((normalized.get("_runtime", normalized) as Dictionary).duplicate(true))
	return out


func tile_at(cell: Vector2i) -> int:
	return tiles[cell.y * width + cell.x] if _contains(cell) else -1


func is_walkable(cell: Vector2i) -> bool:
	return _contains(cell) and walkable[cell.y * width + cell.x] == 1


func feet_tile_at(cell: Vector2i) -> int:
	return feet_tiles[cell.y * width + cell.x] if _contains(cell) else -1


## Raw project-local imagery; no res:// import side channel. Both Engine and
## Studio turn this Image into their own ImageTexture at the presentation seam.
func load_image() -> Dictionary:
	var image := Image.load_from_file(str(tileset.get("image_path", "")))
	if image == null or image.is_empty():
		return {"ok": false, "error": "cannot load tileset image '%s'" %
			str(tileset.get("image_path", "")), "image": null}
	return {"ok": true, "error": "", "image": image}


func _contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func _load(project_root: String, map_label: String) -> String:
	project_dir = _absolute(project_root)
	label = map_label
	path = project_dir.path_join("maps/%s.tmx" % label).simplify_path()
	if not _is_inside(project_dir, path):
		return "map path escapes project: %s" % path
	var bytes := _read_bytes(path)
	if not bool(bytes.get("ok", false)):
		return str(bytes["error"])
	source_bytes = bytes["bytes"]
	var parsed := _xml_tree(source_bytes, path)
	if not bool(parsed.get("ok", false)):
		return str(parsed["error"])
	var root: Dictionary = parsed["root"]
	if str(root.get("name", "")) != "map":
		return "%s — expected <map>, got <%s>" % [path, str(root.get("name", ""))]
	var attrs: Dictionary = root["attrs"]
	_next_layer_id = maxi(1, _attr_int(attrs, "nextlayerid", 1))
	if str(attrs.get("orientation", "")) != "orthogonal":
		return "%s — only orthogonal TMX maps are supported" % path
	if _attr_int(attrs, "tilewidth", -1) != CELL_SIZE or _attr_int(attrs, "tileheight", -1) != CELL_SIZE:
		return "%s — TMX tile size must be %dx%d movement cells" % [path, CELL_SIZE, CELL_SIZE]
	if _attr_int(attrs, "infinite", 0) != 0:
		return "%s — infinite TMX maps are not supported" % path
	width = _attr_int(attrs, "width", 0)
	height = _attr_int(attrs, "height", 0)
	if width < 1 or height < 1:
		return "%s — map width/height must be positive" % path
	properties = _properties(root)
	var bridge := int(properties.get("pokeredpc:format", 0))
	if bridge > BRIDGE_FORMAT:
		return "%s — map bridge format %d; this build supports %d — update the engine" % [
			path, bridge, BRIDGE_FORMAT]
	if bridge < 1:
		return "%s — missing valid integer property 'pokeredpc:format'" % path
	border_tile = int(properties.get("pokeredpc:border_tile", 0))
	border_block = int(properties.get("pokeredpc:border_block", -1))
	var spawn: Variant = _cell_property(str(properties.get("pokeredpc:default_spawn", "0,0")))
	if spawn == null:
		return "%s — property 'pokeredpc:default_spawn' must be 'x,y'" % path
	default_spawn = spawn

	var refs := _children(root, "tileset")
	if refs.size() != 1:
		return "%s — exactly one external TSX tileset is required (found %d)" % [path, refs.size()]
	var ref: Dictionary = refs[0]
	var rattrs: Dictionary = ref["attrs"]
	if not rattrs.has("source") or str(rattrs.get("source", "")) == "":
		return "%s — embedded tilesets are not supported; use external TSX" % path
	var first_gid := _attr_int(rattrs, "firstgid", 0)
	if first_gid < 1:
		return "%s — tileset firstgid must be positive" % path
	_first_gid = first_gid
	var tsx_path := path.get_base_dir().path_join(str(rattrs["source"])).simplify_path()
	if not _is_inside(project_dir, tsx_path):
		return "%s — tileset source escapes project: %s" % [path, str(rattrs["source"])]
	var ts_result := _load_tsx(tsx_path)
	if not bool(ts_result.get("ok", false)):
		return str(ts_result["error"])
	tileset = ts_result["tileset"]
	tileset["first_gid"] = first_gid
	if border_tile < 0 or border_tile >= int(tileset["tile_count"]):
		return "%s — border tile %d is outside tileset 0..%d" % [
			path, border_tile, int(tileset["tile_count"]) - 1]
	if not _contains(default_spawn):
		return "%s — default spawn %s is outside %dx%d map" % [
			path, str(default_spawn), width, height]

	var ground: Dictionary = {}
	var collision_layer: Dictionary = {}
	for layer in _children(root, "layer"):
		var layer_name := str((layer as Dictionary)["attrs"].get("name", ""))
		if layer_name == "Ground":
			if not ground.is_empty():
				return "%s — duplicate tile layer named 'Ground'" % path
			ground = layer
		elif layer_name == "Collision":
			if not collision_layer.is_empty():
				return "%s — duplicate tile layer named 'Collision'" % path
			collision_layer = layer
	if ground.is_empty():
		return "%s — required tile layer 'Ground' is missing" % path
	var layer_error := _parse_ground(ground, first_gid)
	if layer_error != "":
		return layer_error
	if not collision_layer.is_empty():
		layer_error = _parse_collision(collision_layer, first_gid)
		if layer_error != "":
			return layer_error
		_has_collision_layer = true
		_collision_authored = true
	var block_error := _parse_blocks()
	if block_error != "":
		return block_error
	var objects_error := _parse_objects(root)
	if objects_error != "":
		return objects_error
	_saved_tiles = tiles.duplicate()
	_saved_walkable = walkable.duplicate()
	return ""


func _load_tsx(tsx_path: String) -> Dictionary:
	var bytes := _read_bytes(tsx_path)
	if not bool(bytes.get("ok", false)):
		return {"ok": false, "error": bytes["error"]}
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_MD5)
	hasher.update(bytes["bytes"])
	var cache_key := tsx_path + ":" + hasher.finish().hex_encode()
	if _tsx_cache.has(cache_key):
		return {"ok": true, "tileset": (_tsx_cache[cache_key] as Dictionary).duplicate(true)}
	var parsed := _xml_tree(bytes["bytes"], tsx_path)
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "error": parsed["error"]}
	var root: Dictionary = parsed["root"]
	if str(root.get("name", "")) != "tileset":
		return {"ok": false, "error": "%s — expected <tileset>" % tsx_path}
	var attrs: Dictionary = root["attrs"]
	if _attr_int(attrs, "tilewidth", -1) != CELL_SIZE or _attr_int(attrs, "tileheight", -1) != CELL_SIZE:
		return {"ok": false, "error": "%s — TSX tile size must be %dx%d" % [
			tsx_path, CELL_SIZE, CELL_SIZE]}
	var count := _attr_int(attrs, "tilecount", 0)
	var columns := _attr_int(attrs, "columns", 0)
	if count < 1 or columns < 1:
		return {"ok": false, "error": "%s — TSX tilecount/columns must be positive" % tsx_path}
	var images := _children(root, "image")
	if images.size() != 1:
		return {"ok": false, "error": "%s — atlas TSX needs exactly one <image>" % tsx_path}
	var image_attrs: Dictionary = (images[0] as Dictionary)["attrs"]
	var image_path := tsx_path.get_base_dir().path_join(str(image_attrs.get("source", ""))).simplify_path()
	if not _is_inside(project_dir, image_path):
		return {"ok": false, "error": "%s — image source escapes project" % tsx_path}
	if not FileAccess.file_exists(image_path):
		return {"ok": false, "error": "%s — image source is missing: %s" % [tsx_path, image_path]}
	var tile_meta := {}
	var block_tiles := {}
	var tile_blocks := {}
	for tile_node in _children(root, "tile"):
		var node: Dictionary = tile_node
		var id := _attr_int(node["attrs"], "id", -1)
		if id < 0 or id >= count:
			return {"ok": false, "error": "%s — tile id %d is outside 0..%d" % [
				tsx_path, id, count - 1]}
		var props := _properties(node)
		tile_meta[id] = props
		var block = _block_property(str(props.get("pokeredpc:block", "")))
		if block != null:
			var block_id: int = block[0]
			var quadrant: int = block[1]
			if not block_tiles.has(block_id):
				block_tiles[block_id] = [-1, -1, -1, -1]
			var group: Array = block_tiles[block_id]
			if int(group[quadrant]) >= 0:
				return {"ok": false, "error": "%s — duplicate pokeredpc:block %d,%d" % [
					tsx_path, block_id, quadrant]}
			group[quadrant] = id
			block_tiles[block_id] = group
			tile_blocks[id] = [block_id, quadrant]
	for block_id in block_tiles:
		if (block_tiles[block_id] as Array).has(-1):
			return {"ok": false, "error": "%s — pokeredpc:block %d needs all four quadrants" % [
				tsx_path, int(block_id)]}
	var normalized := {
		"name": str(attrs.get("name", tsx_path.get_file().get_basename())),
		"path": tsx_path, "source_bytes": bytes["bytes"], "tile_size": CELL_SIZE,
		"tile_count": count, "columns": columns, "image_path": image_path,
		"image_width": _attr_int(image_attrs, "width", 0),
		"image_height": _attr_int(image_attrs, "height", 0),
		"properties": _properties(root), "tile_properties": tile_meta,
		"block_tiles": block_tiles, "tile_blocks": tile_blocks}
	_tsx_cache[cache_key] = normalized.duplicate(true)
	return {"ok": true, "tileset": normalized}


func _parse_ground(layer: Dictionary, first_gid: int) -> String:
	var attrs: Dictionary = layer["attrs"]
	if _attr_int(attrs, "width", width) != width or _attr_int(attrs, "height", height) != height:
		return "%s — Ground layer dimensions must match map %dx%d" % [path, width, height]
	var data_nodes := _children(layer, "data")
	if data_nodes.size() != 1:
		return "%s — Ground layer needs exactly one <data>" % path
	var data: Dictionary = data_nodes[0]
	if str(data["attrs"].get("encoding", "")) != "csv":
		return "%s — Ground layer data must use CSV encoding" % path
	var tokens := str(data.get("text", "")).strip_edges().split(",", false)
	if tokens.size() != width * height:
		return "%s — Ground layer has %d GIDs; expected %d" % [path, tokens.size(), width * height]
	tiles.resize(width * height)
	walkable.resize(width * height)
	feet_tiles.resize(width * height)
	var meta: Dictionary = tileset["tile_properties"]
	for i in tokens.size():
		var token := str(tokens[i]).strip_edges()
		if not token.is_valid_int():
			return "%s — Ground GID #%d is not an integer: '%s'" % [path, i, token]
		var gid := int(token)
		if gid == 0:
			return "%s — Ground GID #%d is empty; paint every movement cell" % [path, i]
		if (gid & GID_FLIP_MASK) != 0:
			return "%s — flipped/rotated GIDs are not supported yet (cell %d)" % [path, i]
		var local := gid - first_gid
		if local < 0 or local >= int(tileset["tile_count"]):
			return "%s — Ground GID %d is outside the external tileset" % [path, gid]
		var props: Dictionary = meta.get(local, {})
		tiles[i] = local
		walkable[i] = 1 if bool(props.get("pokeredpc:walkable", false)) else 0
		feet_tiles[i] = int(props.get("pokeredpc:feet_tile", local))
	return ""


func _parse_collision(layer: Dictionary, first_gid: int) -> String:
	var attrs: Dictionary = layer["attrs"]
	if _attr_int(attrs, "width", width) != width or _attr_int(attrs, "height", height) != height:
		return "%s — Collision layer dimensions must match map %dx%d" % [path, width, height]
	var data_nodes := _children(layer, "data")
	if data_nodes.size() != 1:
		return "%s — Collision layer needs exactly one <data>" % path
	var data: Dictionary = data_nodes[0]
	if str(data["attrs"].get("encoding", "")) != "csv":
		return "%s — Collision layer data must use CSV encoding" % path
	var tokens := str(data.get("text", "")).strip_edges().split(",", false)
	if tokens.size() != width * height:
		return "%s — Collision layer has %d GIDs; expected %d" % [
			path, tokens.size(), width * height]
	for i in tokens.size():
		var token := str(tokens[i]).strip_edges()
		if not token.is_valid_int():
			return "%s — Collision GID #%d is not an integer: '%s'" % [path, i, token]
		var gid := int(token)
		if (gid & GID_FLIP_MASK) != 0:
			return "%s — flipped/rotated Collision GIDs are not supported (cell %d)" % [path, i]
		if gid != 0 and (gid < first_gid or gid - first_gid >= int(tileset["tile_count"])):
			return "%s — Collision GID %d is outside the external tileset" % [path, gid]
		walkable[i] = 1 if gid == 0 else 0
	return ""


func _parse_blocks() -> String:
	var groups: Dictionary = tileset.get("block_tiles", {})
	if groups.is_empty() or border_block < 0:
		return ""                              # block groups are optional for generic maps
	if not groups.has(border_block):
		return "%s — pokeredpc:border_block %d is absent from the tileset" % [path, border_block]
	if width % 2 != 0 or height % 2 != 0:
		return ""                              # odd maps remain valid but cannot expose a full block grid
	block_width = width / 2
	block_height = height / 2
	_rebuild_blocks()
	return ""


func _rebuild_blocks() -> void:
	if block_width <= 0 or block_height <= 0:
		blocks = []
		return
	blocks = []
	for by in block_height:
		var row: Array = []
		for bx in block_width:
			row.append(_coherent_block(Vector2i(bx, by)))
		blocks.append(row)


func _rebuild_block_at(block_cell: Vector2i) -> void:
	if blocks.is_empty() or block_cell.x < 0 or block_cell.y < 0 \
			or block_cell.x >= block_width or block_cell.y >= block_height:
		return
	blocks[block_cell.y][block_cell.x] = _coherent_block(block_cell)


func _coherent_block(block_cell: Vector2i) -> int:
	var tile_blocks: Dictionary = tileset.get("tile_blocks", {})
	var block_id := -1
	for quadrant in 4:
		var cx := block_cell.x * 2 + quadrant % 2
		var cy := block_cell.y * 2 + quadrant / 2
		var local := int(tiles[cy * width + cx])
		if not tile_blocks.has(local):
			return -1
		var member: Array = tile_blocks[local]
		if int(member[1]) != quadrant:
			return -1
		if block_id < 0:
			block_id = int(member[0])
		elif block_id != int(member[0]):
			return -1
	return block_id


func _refresh_tile_metadata() -> void:
	feet_tiles.resize(width * height)
	var meta: Dictionary = tileset.get("tile_properties", {})
	for i in tiles.size():
		var local := int(tiles[i])
		var props: Dictionary = meta.get(local, {})
		feet_tiles[i] = int(props.get("pokeredpc:feet_tile", local))


func _parse_objects(root: Dictionary) -> String:
	for group_node in _children(root, "objectgroup"):
		for object_node in _children(group_node, "object"):
			var node: Dictionary = object_node
			var attrs: Dictionary = node["attrs"]
			var object_class := str(attrs.get("class", attrs.get("type", "")))
			if not object_class.begins_with("pokeredpc:"):
				continue                         # third-party/Tiled objects round-trip untouched
			var object_name := str(attrs.get("name", ""))
			if object_name == "":
				return "%s — %s object needs a stable Tiled name" % [path, object_class]
			var px := float(attrs.get("x", "0"))
			var py := float(attrs.get("y", "0"))
			var cx := roundi(px / CELL_SIZE)
			var cy := roundi(py / CELL_SIZE)
			if not is_equal_approx(px, float(cx * CELL_SIZE)) or not is_equal_approx(py, float(cy * CELL_SIZE)):
				return "%s — object '%s' must align to the %dpx cell grid" % [
					path, object_name, CELL_SIZE]
			var cell := Vector2i(cx, cy)
			if not _contains(cell):
				return "%s — object '%s' at %s is outside the map" % [path, object_name, str(cell)]
			var props := _properties(node)
			var legacy: Variant = null
			if props.has("pokeredpc:legacy"):
				legacy = JSON.parse_string(str(props["pokeredpc:legacy"]))
				if not (legacy is Dictionary):
					return "%s — object '%s' has invalid pokeredpc:legacy JSON" % [path, object_name]
				if int(legacy.get("x", -1)) != cx or int(legacy.get("y", -1)) != cy:
					return "%s — object '%s' legacy position disagrees with Tiled point" % [path, object_name]
			match object_class:
				"pokeredpc:warp":
					var dest := str(props.get("pokeredpc:dest_map", ""))
					var dest_const := str(props.get("pokeredpc:dest_const", ""))
					if dest != "" and not dest.begins_with("map:"):
						return "%s — warp '%s' property pokeredpc:dest_map must be prefixed" % [path, object_name]
					if dest == "" and dest_const == "":
						return "%s — warp '%s' needs pokeredpc:dest_map or an explicit ruleset destination" % [path, object_name]
					var warp := {"id": object_name, "x": cx, "y": cy,
						"dest_map": dest.substr(4) if dest != "" else "",
						"dest_const": dest_const,
						"dest_warp": int(props.get("pokeredpc:dest_warp", 1))}
					if legacy != null:
						warp["_runtime"] = legacy
					warps.append(warp)
				"pokeredpc:sign":
					var sign := {"id": object_name, "x": cx, "y": cy,
						"text": str(props.get("pokeredpc:text", "")),
						"event": str(props.get("pokeredpc:event", ""))}
					if legacy != null:
						sign["_runtime"] = legacy
					signs.append(sign)
				"pokeredpc:npc":
					var sprite := str(props.get("pokeredpc:sprite", ""))
					if sprite == "":
						return "%s — NPC '%s' needs property pokeredpc:sprite" % [path, object_name]
					var object := {"id": object_name, "x": cx, "y": cy, "sprite": sprite,
						"args": [str(props.get("pokeredpc:movement", "STAY")),
							str(props.get("pokeredpc:facing", "NONE"))],
						"event": str(props.get("pokeredpc:event", ""))}
					if legacy != null:
						object["_runtime"] = legacy
					objects.append(object)
				"pokeredpc:trigger":
					triggers.append({"id": object_name, "x": cx, "y": cy,
						"event": str(props.get("pokeredpc:event", ""))})
				_:
					return "%s — unknown pokeredpc object class '%s'" % [path, object_class]
	return ""


func _edited_source() -> Dictionary:
	if not is_dirty():
		return {"ok": true, "bytes": source_bytes, "has_collision": _has_collision_layer,
			"next_layer_id": _next_layer_id}
	var source := source_bytes.get_string_from_utf8()
	if tiles != _saved_tiles:
		var ground_patch := _replace_layer_csv(source, "Ground", _tile_csv())
		if not bool(ground_patch.get("ok", false)):
			return ground_patch
		source = str(ground_patch["source"])
	var has_collision := _has_collision_layer
	var next_id := _next_layer_id
	if _has_collision_layer and walkable != _saved_walkable:
		var collision_csv := _collision_csv()
		var collision_patch := _replace_layer_csv(source, "Collision", collision_csv)
		if not bool(collision_patch.get("ok", false)):
			return collision_patch
		source = str(collision_patch["source"])
	elif not _has_collision_layer and not _walkable_matches_tiles():
		var inserted := _insert_collision_layer(source, _collision_csv(), next_id)
		if not bool(inserted.get("ok", false)):
			return inserted
		source = str(inserted["source"])
		has_collision = true
		next_id += 1
	return {"ok": true, "bytes": source.to_utf8_buffer(), "has_collision": has_collision,
		"next_layer_id": next_id}


func _tile_csv() -> String:
	var gids := PackedInt32Array()
	gids.resize(tiles.size())
	for i in tiles.size():
		gids[i] = int(tiles[i]) + _first_gid
	return _csv_rows(gids)


func _collision_csv() -> String:
	var gids := PackedInt32Array()
	gids.resize(walkable.size())
	for i in walkable.size():
		gids[i] = 0 if int(walkable[i]) == 1 else _first_gid
	return _csv_rows(gids)


func _csv_rows(values: PackedInt32Array) -> String:
	var rows := PackedStringArray()
	for y in height:
		var row := PackedStringArray()
		for x in width:
			row.append(str(values[y * width + x]))
		rows.append(",".join(row))
	return ",\n".join(rows)


func _walkable_matches_tiles() -> bool:
	var meta: Dictionary = tileset.get("tile_properties", {})
	for i in tiles.size():
		var props: Dictionary = meta.get(int(tiles[i]), {})
		var expected := 1 if bool(props.get("pokeredpc:walkable", false)) else 0
		if int(walkable[i]) != expected:
			return false
	return true


static func _replace_layer_csv(source: String, layer_name: String, csv: String) -> Dictionary:
	var regex := RegEx.new()
	var pattern := "(?s)<layer\\b[^>]*\\bname=\"%s\"[^>]*>.*?<data\\b[^>]*\\bencoding=\"csv\"[^>]*>(.*?)</data>" % layer_name
	var compile_error := regex.compile(pattern)
	if compile_error != OK:
		return {"ok": false, "error": "cannot compile targeted %s layer writer" % layer_name}
	var matched := regex.search(source)
	if matched == null:
		return {"ok": false, "error": "cannot find editable CSV layer '%s' in source" % layer_name}
	var body_start := matched.get_start(1)
	var body_end := matched.get_end(1)
	return {"ok": true, "source": source.substr(0, body_start) + "\n" + csv + "\n" +
		source.substr(body_end)}


func _insert_collision_layer(source: String, csv: String, layer_id: int) -> Dictionary:
	var map_start := source.find("<map")
	var map_end := source.find(">", map_start)
	if map_start < 0 or map_end < 0:
		return {"ok": false, "error": "cannot find TMX map root"}
	var next_key := "nextlayerid=\""
	var next_at := source.find(next_key, map_start)
	if next_at >= 0 and next_at < map_end:
		var value_start := next_at + next_key.length()
		var value_end := source.find("\"", value_start)
		if value_end < 0 or value_end > map_end:
			return {"ok": false, "error": "malformed nextlayerid attribute"}
		source = source.substr(0, value_start) + str(layer_id + 1) + source.substr(value_end)
	else:
		source = source.substr(0, map_end) + " nextlayerid=\"%d\"" % (layer_id + 1) + \
			source.substr(map_end)
	var marker := source.find("<objectgroup")
	if marker < 0:
		marker = source.find("</map>")
	if marker < 0:
		return {"ok": false, "error": "cannot find Collision layer insertion point"}
	var newline := "\r\n" if "\r\n" in source else "\n"
	var layer := "<layer id=\"%d\" name=\"Collision\" width=\"%d\" height=\"%d\" visible=\"0\">%s  <data encoding=\"csv\">%s%s%s  </data>%s </layer>%s " % [
		layer_id, width, height, newline, newline, csv, newline, newline, newline]
	return {"ok": true, "source": source.substr(0, marker) + layer + source.substr(marker)}


static func _read_bytes(file_path: String) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open '%s' (%s)" % [
			file_path, error_string(FileAccess.get_open_error())]}
	return {"ok": true, "bytes": file.get_buffer(file.get_length())}


## XMLParser is pull-only, so build a private generic tree once. Unknown nodes are
## retained in source_bytes for byte-stable writes but deliberately absent from the
## normalized interface until a caller has a reason to understand them.
static func _xml_tree(bytes: PackedByteArray, file_path: String) -> Dictionary:
	var parser := XMLParser.new()
	var open_error := parser.open_buffer(bytes)
	if open_error != OK:
		return {"ok": false, "error": "%s — XML open error: %s" % [
			file_path, error_string(open_error)]}
	var root: Dictionary = {}
	var stack: Array = []
	while true:
		var read_error := parser.read()
		if read_error == ERR_FILE_EOF:
			break
		if read_error != OK:
			return {"ok": false, "error": "%s — XML parse error: %s" % [
				file_path, error_string(read_error)]}
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var attrs := {}
				for i in parser.get_attribute_count():
					attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
				var node := {"name": parser.get_node_name(), "attrs": attrs,
					"children": [], "text": ""}
				if stack.is_empty():
					if not root.is_empty():
						return {"ok": false, "error": "%s — multiple XML roots" % file_path}
					root = node
				else:
					(stack[-1]["children"] as Array).append(node)
				if not parser.is_empty():
					stack.append(node)
			XMLParser.NODE_ELEMENT_END:
				if not stack.is_empty():
					stack.pop_back()
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if not stack.is_empty():
					stack[-1]["text"] = str(stack[-1]["text"]) + parser.get_node_data()
	if root.is_empty():
		return {"ok": false, "error": "%s — empty XML document" % file_path}
	return {"ok": true, "root": root}


static func _children(node: Dictionary, wanted: String) -> Array:
	var out: Array = []
	for child in node.get("children", []):
		if str((child as Dictionary).get("name", "")) == wanted:
			out.append(child)
	return out


static func _properties(node: Dictionary) -> Dictionary:
	var out := {}
	for container in _children(node, "properties"):
		for property_node in _children(container, "property"):
			var p: Dictionary = property_node
			var attrs: Dictionary = p["attrs"]
			var key := str(attrs.get("name", ""))
			if key == "":
				continue
			var raw := str(attrs.get("value", p.get("text", "")))
			match str(attrs.get("type", "string")):
				"bool": out[key] = raw.to_lower() == "true" or raw == "1"
				"int": out[key] = int(raw)
				"float": out[key] = float(raw)
				_: out[key] = raw
	return out


static func _attr_int(attrs: Dictionary, key: String, fallback: int) -> int:
	var raw := str(attrs.get(key, ""))
	return int(raw) if raw.is_valid_int() else fallback


static func _cell_property(raw: String):
	var pieces := raw.split(",", false)
	if pieces.size() != 2 or not str(pieces[0]).strip_edges().is_valid_int() \
			or not str(pieces[1]).strip_edges().is_valid_int():
		return null
	return Vector2i(int(str(pieces[0]).strip_edges()), int(str(pieces[1]).strip_edges()))


static func _block_property(raw: String):
	var pieces := raw.split(",", false)
	if pieces.size() != 2 or not str(pieces[0]).strip_edges().is_valid_int() \
			or not str(pieces[1]).strip_edges().is_valid_int():
		return null
	var block_id := int(str(pieces[0]).strip_edges())
	var quadrant := int(str(pieces[1]).strip_edges())
	if block_id < 0 or quadrant < 0 or quadrant > 3:
		return null
	return [block_id, quadrant]


static func _xml_escape(value: String) -> String:
	return value.replace("&", "&amp;").replace("\"", "&quot;").replace("<", "&lt;").replace(">", "&gt;")


static func _absolute(file_path: String) -> String:
	return ProjectSettings.globalize_path(file_path).simplify_path()


static func _is_inside(root: String, candidate: String) -> bool:
	var r := root.simplify_path().replace("\\", "/").trim_suffix("/")
	var c := candidate.simplify_path().replace("\\", "/")
	if OS.get_name() == "Windows":
		r = r.to_lower()
		c = c.to_lower()
	return c == r or c.begins_with(r + "/")
