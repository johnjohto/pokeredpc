extends RefCounted
class_name StudioMapSmoke
## The Studio half of gh #52: the real workspace consumes MapDocument, exposes
## the concept-pinned three-part layout, renders the atlas, and saves exact bytes.


func sweep_all(shell: StudioShell) -> bool:
	var labels: Array = ProjectData.map_labels()
	var refusals: Array[String] = []
	for label in labels:
		var workspace = shell.edit_map(str(label))
		if workspace == null:
			refusals.append("%s — %s" % [str(label), shell.status_text()])
	var detail := "; ".join(PackedStringArray(refusals))
	return _check("all %d Kanto maps mount in Studio" % labels.size(),
		labels.size() == 223 and refusals.is_empty(), detail)


func run(shell: StudioShell) -> bool:
	var ok := true
	var workspace = shell.preview_map("res://core/fixtures/valid_tmx", "TestTown")
	ok = _check("native map mounts in the Studio workspace", workspace != null) and ok
	if workspace == null:
		return false
	ok = _check("map workspace has tools, dominant canvas, inspector and action bar",
		workspace.find_child("ToolRail", true, false) != null
		and workspace.find_child("MapCanvas", true, false) != null
		and workspace.find_child("InspectorDock", true, false) != null
		and workspace.find_child("ActionBar", true, false) != null) and ok
	var canvas: StudioMapCanvas = workspace.canvas_control()
	var rendered := canvas.render_image()
	var source := canvas.atlas
	ok = _check("Studio canvas renders the project-local TSX cells",
		not rendered.is_empty() and rendered.get_size() == Vector2i(64, 48)
		and rendered.get_pixel(8, 8).is_equal_approx(source.get_pixel(8, 8))
		and rendered.get_pixel(24, 8).is_equal_approx(source.get_pixel(24, 8)),
		"size=%s" % str(rendered.get_size())) and ok
	var shot_error := rendered.save_png("res://studio_tmx.png")
	ok = _check("Studio tracer screenshot writes", shot_error == OK,
		error_string(shot_error)) and ok
	var exact := OS.get_user_data_dir().path_join("studio_map_exact.tmx")
	var save_error: String = workspace.save_to(exact)
	ok = _check("Studio no-op Save preserves every TMX byte",
		save_error == "" and FileAccess.get_file_as_bytes(exact)
		== FileAccess.get_file_as_bytes(workspace.document.path), save_error) and ok
	print("[studiomap] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[studiomap] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
