extends RefCounted
class_name WorldDocumentSmoke
## Interface proof for gh #55's reciprocal world graph: one edit owns both directed
## records, validates shared geometry, snapshots exactly, and writes canonical JSON.


func run() -> bool:
	var ok := true
	var fixture := "res://core/fixtures/valid_tmx"
	var scratch := OS.get_user_data_dir().path_join("worlddoc_edit")
	if DirAccess.dir_exists_absolute(scratch):
		OS.move_to_trash(scratch)
	var copy_error := ProjectData.copy_dir(fixture, scratch)
	var second := MapDocument.create(scratch, "LinkTown", 4, 3, "tracer.tsx")
	var world_path := scratch.path_join("data/world.json")
	var write_error := CanonJSON.write_file(world_path, {"maps": {
		"map:TestTown": [], "map:LinkTown": []}, "custom": {"weather": "kept"}})
	var opened := preload("res://core/WorldDocument.gd").open(scratch)
	ok = _check("world scratch with two native maps opens",
		copy_error == "" and bool(second.get("ok", false)) and write_error == ""
		and bool(opened.get("ok", false)), copy_error + write_error + str(opened.get("error", ""))) and ok
	if not bool(opened.get("ok", false)):
		return false
	var document = opened["document"]
	var before: Dictionary = document.edit_state()
	var connection_error: String = document.set_connection("TestTown", "east", "LinkTown", 1)
	var after: Dictionary = document.edit_state()
	var forward: Array = document.connections("TestTown")
	var reverse: Array = document.connections("LinkTown")
	document.restore_edit_state(before)
	var undo_exact: bool = not document.is_dirty() and document.connections("TestTown").is_empty()
	document.restore_edit_state(after)
	ok = _check("one connection edit creates an exact reciprocal and snapshots undo/redo",
		connection_error == "" and forward.size() == 1 and reverse.size() == 1
		and str(forward[0].get("direction", "")) == "east"
		and int(forward[0].get("offset", 0)) == 1
		and str(reverse[0].get("direction", "")) == "west"
		and int(reverse[0].get("offset", 0)) == -1 and undo_exact,
		connection_error) and ok
	var save_error: String = document.save()
	var reopened := preload("res://core/WorldDocument.gd").open(scratch)
	var persisted = reopened.get("document")
	var persisted_forward: Array = persisted.connections("TestTown")
	ok = _check("world graph saves canonically and reopens without drift",
		save_error == "" and bool(reopened.get("ok", false)) and not persisted.is_dirty()
		and persisted_forward.size() == 1
		and str(persisted_forward[0].get("direction", "")) == "east"
		and str(persisted_forward[0].get("map", "")) == "map:LinkTown"
		and int(persisted_forward[0].get("offset", 0)) == 1
		and str(persisted.data.get("custom", {}).get("weather", "")) == "kept",
		"save=%s open=%s dirty=%s want=%s got=%s custom=%s" % [save_error,
			str(reopened.get("error", "")), str(persisted.is_dirty()), str(forward),
			str(persisted_forward), str(persisted.data.get("custom", {}))]) and ok
	var malformed := {"maps": {"map:TestTown": [{"direction": "east",
		"map": "map:LinkTown", "offset": 0}], "map:LinkTown": []}}
	var malformed_errors: Array = preload("res://core/WorldDocument.gd").validate_data(scratch, malformed)
	ok = _check("semantic validation names a missing reciprocal",
		malformed_errors.size() == 1 and "needs exactly one west reciprocal" in str(malformed_errors[0]),
		"; ".join(PackedStringArray(malformed_errors))) and ok
	var saved_state: Dictionary = persisted.edit_state()
	var geometry_error: String = persisted.set_connection("TestTown", "east", "LinkTown", 20)
	ok = _check("an impossible shared edge refuses without partial graph mutation",
		geometry_error.contains("has no shared edge") and persisted.edit_state() == saved_state,
		geometry_error) and ok
	var removed: bool = persisted.remove_connection("TestTown", "east")
	ok = _check("removing either side removes the reciprocal too",
		removed and persisted.connections("TestTown").is_empty()
		and persisted.connections("LinkTown").is_empty()) and ok
	print("[worlddoc] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[worlddoc] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
