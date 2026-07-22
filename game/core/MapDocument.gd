extends RefCounted
class_name MapDocument
## Phase-5 native map module (gh #52, ADR-021). Core, Engine, Studio, and the
## validator all cross this one seam: open a Tiled TMX map into a normalized
## 16x16-cell document, or save its untouched source bytes exactly. XML/Tiled
## details, path containment, TSX properties, CSV GIDs, and object conventions
## stay behind this interface instead of leaking into four callers.

const BRIDGE_FORMAT := 1
const CELL_SIZE := 16
const GID_FLIP_MASK := 0xE0000000

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
var default_spawn := Vector2i.ZERO
var tileset: Dictionary = {}
var warps: Array = []
var signs: Array = []
var objects: Array = []
var triggers: Array = []
var properties: Dictionary = {}


## Open maps/<label>.tmx and its external TSX. Returns
## {ok:true, document:MapDocument} or {ok:false, error:String}; callers never
## need to understand XMLParser or partial parse state.
static func open(project_root: String, map_label: String) -> Dictionary:
	var document := MapDocument.new()
	var error := document._load(project_root, map_label)
	return {"ok": error == "", "document": document if error == "" else null,
		"error": error}


## Persist an UNEDITED document. Phase 5.3 grows targeted edit operations; this
## tracer deliberately writes the original buffer so a Studio no-op save is
## byte-identical and every unknown Tiled layer/property/comment survives.
func save(target_path := "") -> String:
	var out := path if target_path == "" else _absolute(target_path)
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		return "cannot write '%s' (%s)" % [out, error_string(FileAccess.get_open_error())]
	file.store_buffer(source_bytes)
	return ""


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
	return {
		"_native": "tmx", "name": label, "tileset": str(tileset.get("name", "")),
		"cell_width": width, "cell_height": height, "tiles": tile_rows,
		"cell_walkable": collision_rows, "cell_feet": feet_rows,
		"border_tile": border_tile, "default_spawn": [default_spawn.x, default_spawn.y],
		"warps": warps.duplicate(true), "connections": [],
		"bg_events": signs.duplicate(true), "object_events": objects.duplicate(true),
		"triggers": triggers.duplicate(true), "_tileset": tileset.duplicate(true)}


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
	for layer in _children(root, "layer"):
		if str((layer as Dictionary)["attrs"].get("name", "")) == "Ground":
			if not ground.is_empty():
				return "%s — duplicate tile layer named 'Ground'" % path
			ground = layer
	if ground.is_empty():
		return "%s — required tile layer 'Ground' is missing" % path
	var layer_error := _parse_ground(ground, first_gid)
	if layer_error != "":
		return layer_error
	var objects_error := _parse_objects(root)
	if objects_error != "":
		return objects_error
	return ""


func _load_tsx(tsx_path: String) -> Dictionary:
	var bytes := _read_bytes(tsx_path)
	if not bool(bytes.get("ok", false)):
		return {"ok": false, "error": bytes["error"]}
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
	for tile_node in _children(root, "tile"):
		var node: Dictionary = tile_node
		var id := _attr_int(node["attrs"], "id", -1)
		if id < 0 or id >= count:
			return {"ok": false, "error": "%s — tile id %d is outside 0..%d" % [
				tsx_path, id, count - 1]}
		tile_meta[id] = _properties(node)
	return {"ok": true, "tileset": {
		"name": str(attrs.get("name", tsx_path.get_file().get_basename())),
		"path": tsx_path, "source_bytes": bytes["bytes"], "tile_size": CELL_SIZE,
		"tile_count": count, "columns": columns, "image_path": image_path,
		"image_width": _attr_int(image_attrs, "width", 0),
		"image_height": _attr_int(image_attrs, "height", 0),
		"properties": _properties(root), "tile_properties": tile_meta}}


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
			match object_class:
				"pokeredpc:warp":
					var dest := str(props.get("pokeredpc:dest_map", ""))
					if not dest.begins_with("map:"):
						return "%s — warp '%s' needs prefixed property pokeredpc:dest_map" % [path, object_name]
					warps.append({"id": object_name, "x": cx, "y": cy,
						"dest_map": dest.substr(4),
						"dest_warp": int(props.get("pokeredpc:dest_warp", 1))})
				"pokeredpc:sign":
					signs.append({"id": object_name, "x": cx, "y": cy,
						"text": str(props.get("pokeredpc:text", "")),
						"event": str(props.get("pokeredpc:event", ""))})
				"pokeredpc:npc":
					var sprite := str(props.get("pokeredpc:sprite", ""))
					if sprite == "":
						return "%s — NPC '%s' needs property pokeredpc:sprite" % [path, object_name]
					objects.append({"id": object_name, "x": cx, "y": cy, "sprite": sprite,
						"args": [str(props.get("pokeredpc:movement", "STAY")),
							str(props.get("pokeredpc:facing", "NONE"))],
						"event": str(props.get("pokeredpc:event", ""))})
				"pokeredpc:trigger":
					triggers.append({"id": object_name, "x": cx, "y": cy,
						"event": str(props.get("pokeredpc:event", ""))})
				_:
					return "%s — unknown pokeredpc object class '%s'" % [path, object_class]
	return ""


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


static func _absolute(file_path: String) -> String:
	return ProjectSettings.globalize_path(file_path).simplify_path()


static func _is_inside(root: String, candidate: String) -> bool:
	var r := root.simplify_path().replace("\\", "/").trim_suffix("/")
	var c := candidate.simplify_path().replace("\\", "/")
	if OS.get_name() == "Windows":
		r = r.to_lower()
		c = c.to_lower()
	return c == r or c.begins_with(r + "/")
