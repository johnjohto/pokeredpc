extends RefCounted
class_name MapDocumentSmoke
## Interface-level proof for the deep native-map module (gh #52/#54): callers see
## normalized cells/objects, editable snapshots, and source-preserving saves; XML mechanics
## remain private.


func run() -> bool:
	var ok := true
	var fixture := "res://core/fixtures/valid_tmx"
	var opened := MapDocument.open(fixture, "TestTown")
	ok = _check("format-2 TMX + external TSX opens", bool(opened.get("ok", false)),
		str(opened.get("error", ""))) and ok
	if not bool(opened.get("ok", false)):
		return false
	var document: MapDocument = opened["document"]
	ok = _check("16x16 cell grid normalizes dimensions and collision",
		document.width == 4 and document.height == 3
		and document.tile_at(Vector2i(0, 0)) == 0
		and document.is_walkable(Vector2i(0, 0))
		and not document.is_walkable(Vector2i(1, 0))
		and document.feet_tile_at(Vector2i(0, 0)) == 16,
		"size=%dx%d tiles=%s" % [document.width, document.height, str(document.tiles)]) and ok
	ok = _check("typed Tiled objects become runtime warps/NPCs",
		document.warps.size() == 1 and str(document.warps[0].get("dest_map", "")) == "TestTown"
		and document.objects.size() == 1 and str(document.objects[0].get("id", "")) == "guide",
		"warps=%s objects=%s" % [str(document.warps), str(document.objects)]) and ok
	var runtime := document.runtime_map()
	ok = _check("runtime view carries native cells and project-local tileset",
		str(runtime.get("_native", "")) == "tmx" and int(runtime.get("cell_width", 0)) == 4
		and str((runtime.get("_tileset", {}) as Dictionary).get("image_path", "")).contains("valid_tmx"),
		str(runtime)) and ok
	var loaded_image := document.load_image()
	var image: Image = loaded_image.get("image")
	ok = _check("project-local tileset image loads without res:// import data",
		bool(loaded_image.get("ok", false)) and image != null
		and image.get_width() == 128 and image.get_height() == 48,
		str(loaded_image.get("error", ""))) and ok

	var exact_path := OS.get_user_data_dir().path_join("mapdoc_exact.tmx")
	var save_error := document.save(exact_path)
	var original := FileAccess.get_file_as_bytes(document.path)
	var written := FileAccess.get_file_as_bytes(exact_path)
	ok = _check("no-op save is byte-identical and preserves unknown Tiled data",
		save_error == "" and original == written
		and FileAccess.get_file_as_string(exact_path).contains("third-party:weather"),
		save_error) and ok

	var edit_scratch := OS.get_user_data_dir().path_join("mapdoc_edit")
	if DirAccess.dir_exists_absolute(edit_scratch):
		OS.move_to_trash(edit_scratch)
	var edit_copy := _copy_dir(fixture, edit_scratch)
	var edit_opened := MapDocument.open(edit_scratch, "TestTown")
	ok = _check("editable-map scratch opens", edit_copy == "" and bool(edit_opened.get("ok", false)),
		edit_copy + str(edit_opened.get("error", ""))) and ok
	if bool(edit_opened.get("ok", false)):
		var editable: MapDocument = edit_opened["document"]
		var before := editable.edit_state()
		var changed := editable.set_tile(Vector2i(0, 0), 1)
		changed = editable.set_walkable(Vector2i(0, 0), true) or changed
		var edited_state := editable.edit_state()
		editable.restore_edit_state(before)
		var undo_exact := not editable.is_dirty() and editable.tile_at(Vector2i(0, 0)) == 0 \
			and editable.is_walkable(Vector2i(0, 0))
		editable.restore_edit_state(edited_state)
		var tsx_before := FileAccess.get_file_as_bytes(edit_scratch.path_join("tilesets/tracer.tsx"))
		var targeted_error := editable.save()
		var reopened := MapDocument.open(edit_scratch, "TestTown")
		var edited_source := FileAccess.get_file_as_string(editable.path)
		var tsx_after := FileAccess.get_file_as_bytes(edit_scratch.path_join("tilesets/tracer.tsx"))
		ok = _check("tile/collision state snapshots undo and redo exactly",
			changed and undo_exact and editable.tile_at(Vector2i(0, 0)) == 1
			and editable.is_walkable(Vector2i(0, 0))) and ok
		ok = _check("targeted TMX save reopens with per-cell collision",
			targeted_error == "" and bool(reopened.get("ok", false))
			and (reopened.get("document") as MapDocument).tile_at(Vector2i(0, 0)) == 1
			and (reopened.get("document") as MapDocument).is_walkable(Vector2i(0, 0))
			and edited_source.contains("name=\"Collision\"")
			and edited_source.contains("third-party:weather")
			and edited_source.contains("third-party:intensity")
			and tsx_before == tsx_after, targeted_error) and ok

	var scratch := OS.get_user_data_dir().path_join("mapdoc_malformed")
	if DirAccess.dir_exists_absolute(scratch):
		OS.move_to_trash(scratch)
	var copy_error := _copy_dir(fixture, scratch)
	ok = _check("malformed-map scratch project copies", copy_error == "", copy_error) and ok
	if copy_error == "":
		var map_path := scratch.path_join("maps/TestTown.tmx")
		var source := FileAccess.get_file_as_string(map_path)
		_write_text(map_path, source.replace(
			"name=\"pokeredpc:format\" type=\"int\" value=\"1\"",
			"name=\"pokeredpc:format\" type=\"int\" value=\"99\""))
		var newer := MapDocument.open(scratch, "TestTown")
		ok = _check("newer map bridge refuses naming both versions",
			not bool(newer.get("ok", false))
			and "map bridge format 99; this build supports 1" in str(newer.get("error", "")),
			str(newer.get("error", ""))) and ok
		_write_text(map_path, source.replace("tilewidth=\"16\"", "tilewidth=\"8\""))
		var malformed := MapDocument.open(scratch, "TestTown")
		ok = _check("malformed map refuses before callers see partial state",
			not bool(malformed.get("ok", false))
			and "TMX tile size must be 16x16" in str(malformed.get("error", "")),
			str(malformed.get("error", ""))) and ok
		_write_text(map_path, source.replace("../tilesets/tracer.tsx", "../../../escape.tsx"))
		var escaped := MapDocument.open(scratch, "TestTown")
		ok = _check("project-relative Tiled paths cannot escape the project",
			not bool(escaped.get("ok", false))
			and "tileset source escapes project" in str(escaped.get("error", "")),
			str(escaped.get("error", ""))) and ok
	print("[mapdoc] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[mapdoc] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


static func _write_text(path: String, value: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write " + path
	file.store_string(value)
	return ""


static func _copy_dir(from: String, to: String) -> String:
	var directory := DirAccess.open(from)
	if directory == null:
		return "cannot open " + from
	DirAccess.make_dir_recursive_absolute(to)
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		var source := from.path_join(entry)
		var target := to.path_join(entry)
		if directory.current_is_dir():
			var child_error := _copy_dir(source, target)
			if child_error != "":
				return child_error
		else:
			var out := FileAccess.open(target, FileAccess.WRITE)
			if out == null:
				return "cannot write " + target
			out.store_buffer(FileAccess.get_file_as_bytes(source))
		entry = directory.get_next()
	directory.list_dir_end()
	return ""
