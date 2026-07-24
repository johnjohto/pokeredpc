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
	var edit_copy := ProjectData.copy_dir(fixture, edit_scratch)
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
		if bool(reopened.get("ok", false)):
			var authored: MapDocument = reopened["document"]
			var object_before := authored.edit_state()
			var object_error := authored.add_typed_object("warp", "studio_door",
				Vector2i(0, 1), {"dest_map": "TestTown", "dest_const": "", "dest_warp": 1})
			if object_error == "":
				object_error = authored.add_typed_object("npc", "studio_guide",
					Vector2i(1, 1), {"sprite": "SPRITE_TESTER", "args": ["STAY", "DOWN"],
						"event": "event:test_event"})
			if object_error == "":
				object_error = authored.add_typed_object("sign", "studio_sign",
					Vector2i(2, 2), {"text": "Hello", "event": ""})
			if object_error == "":
				object_error = authored.add_typed_object("trigger", "studio_trigger",
					Vector2i(0, 2), {"width": 2, "height": 1, "event": "event:test_event"})
			if object_error == "":
				object_error = authored.update_typed_object("sign", "studio_sign",
					{"id": "studio_notice", "x": 3, "text": "Welcome"})
			var object_after := authored.edit_state()
			authored.restore_edit_state(object_before)
			var object_undo := authored.edit_state() == object_before
			authored.restore_edit_state(object_after)
			var object_save := authored.save()
			var object_reopened := MapDocument.open(edit_scratch, "TestTown")
			var object_source := FileAccess.get_file_as_string(authored.path)
			var persisted: MapDocument = object_reopened.get("document")
			ok = _check("typed objects add/edit as one exact undoable document state",
				object_error == "" and object_undo and object_save == ""
				and bool(object_reopened.get("ok", false)) and persisted.warps.size() == 2
				and persisted.objects.size() == 2 and persisted.signs.size() == 1
				and persisted.triggers.size() == 1
				and str(persisted.signs[0].get("id", "")) == "studio_notice"
				and int(persisted.signs[0].get("x", -1)) == 3,
				object_error + object_save + str(object_reopened.get("error", ""))) and ok
			var runtime_objects: Array = persisted.runtime_map().get("object_events", []) \
				if bool(object_reopened.get("ok", false)) else []
			ok = _check("targeted object writer preserves unrelated TMX and hides editor metadata",
				object_source.contains("third-party:weather")
				and object_source.contains("third-party:intensity")
				and object_source.contains("name=\"studio_trigger\"")
				and not runtime_objects.is_empty()
				and not (runtime_objects[-1] as Dictionary).has("_tiled_id")) and ok
			if bool(object_reopened.get("ok", false)):
				var remove_error := persisted.remove_typed_object("npc", "studio_guide")
				if remove_error == "":
					remove_error = persisted.update_typed_object("warp", "studio_door",
						{"dest_warp": 2})
				var remove_save := persisted.save()
				var final_open := MapDocument.open(edit_scratch, "TestTown")
				var final_doc: MapDocument = final_open.get("document")
				ok = _check("existing typed objects update/remove and reopen without drift",
					remove_error == "" and remove_save == "" and bool(final_open.get("ok", false))
					and final_doc.objects.size() == 1 and final_doc.warps.size() == 2
					and int(final_doc.warps[-1].get("dest_warp", 0)) == 2,
					remove_error + remove_save + str(final_open.get("error", ""))) and ok

	var scratch := OS.get_user_data_dir().path_join("mapdoc_malformed")
	if DirAccess.dir_exists_absolute(scratch):
		OS.move_to_trash(scratch)
	var copy_error := ProjectData.copy_dir(fixture, scratch)
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
	# gh #58: explicit Tiled-origin fixture — a TMX carrying real Tiled editor artifacts
	# (editorsettings, a map class, an extra decorated layer, a locked objectgroup,
	# template/gid objects) opens and survives Studio-side saves where unedited.
	var tiled_fixture := "res://core/fixtures/tiled_origin"
	var tiled_opened := MapDocument.open(tiled_fixture, "TiledOrigin")
	ok = _check("Tiled-origin TMX opens through the same MapDocument seam",
		bool(tiled_opened.get("ok", false)), str(tiled_opened.get("error", ""))) and ok
	if bool(tiled_opened.get("ok", false)):
		var tiled: MapDocument = tiled_opened["document"]
		var tiled_path := OS.get_user_data_dir().path_join("tiled_origin_roundtrip.tmx")
		var tsx_before := FileAccess.get_file_as_bytes(
			tiled_fixture.path_join("tilesets/tracer.tsx"))
		var tiled_noop := tiled.save(tiled_path)
		var tiled_identical: bool = FileAccess.get_file_as_bytes(tiled.path) == \
			FileAccess.get_file_as_bytes(tiled_path)
		tiled.set_tile(Vector2i(0, 0), 1)
		var tiled_edit := tiled.save(tiled_path)
		var tiled_source := FileAccess.get_file_as_string(tiled_path)
		ok = _check("Tiled-origin artifacts survive no-op and targeted saves",
			tiled_noop == "" and tiled_identical and tiled_edit == ""
			and tsx_before == FileAccess.get_file_as_bytes(
				tiled_fixture.path_join("tilesets/tracer.tsx"))
			and tiled_source.contains("<editorsettings>")
			and tiled_source.contains("class=\"town\"")
			and tiled_source.contains("name=\"Fringe\"")
			and tiled_source.contains("opacity=\"0.75\"")
			and tiled_source.contains("locked=\"1\"")
			and tiled_source.contains("template=\"templates/stamp.tx\"")
			and tiled_source.contains("third-party:intensity"),
			tiled_noop + tiled_edit) and ok
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
