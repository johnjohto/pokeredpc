extends RefCounted
class_name StudioPlaytest
## One separate Engine child launched by Studio (ADR-020 d5, gh #51). A unique handshake
## file proves that the child loaded the requested project and reports its isolated save
## path; no pipe, window embedding, or engine-side Studio dependency is introduced.

var pid := -1
var project_dir := ""
var save_slot := ""
var handshake_path := ""
var token := ""


func launch(open_project_dir: String, probe := false, headless := false, start_map := "",
		inspect_cells: Array = [], traverse: Dictionary = {}, event_probe := "") -> String:
	project_dir = _normalized_project_dir(open_project_dir)
	if not FileAccess.file_exists(project_dir.path_join("manifest.json")):
		return "no project at '%s'" % project_dir
	save_slot = save_slot_for(project_dir)
	token = ("%s:%d:%d" % [project_dir, OS.get_process_id(), Time.get_ticks_usec()]).md5_text()
	handshake_path = OS.get_user_data_dir().path_join(
		"studio_playtest_%s.json" % token.substr(0, 16))
	if FileAccess.file_exists(handshake_path):
		DirAccess.remove_absolute(handshake_path)
	var executable := OS.get_executable_path()
	var args := PackedStringArray()
	if headless:
		args.append("--headless")
	# Development runs re-invoke Godot with this project's project.godot. Exported
	# builds re-invoke themselves and already carry their PCK.
	if executable.get_file().to_lower().begins_with("godot"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append("--")
	args.append_array([
		"--project=" + project_dir,
		"--saveslot=" + save_slot,
		"--playtest-handshake=" + handshake_path,
		"--playtest-token=" + token,
	])
	if start_map != "":
		args.append("--start-map=" + start_map)
	if not inspect_cells.is_empty():
		var encoded := PackedStringArray()
		for cell in inspect_cells:
			var map_cell: Vector2i = cell
			encoded.append("%d,%d" % [map_cell.x, map_cell.y])
		args.append("--playtest-inspect=" + ";".join(encoded))
	if not traverse.is_empty():
		var warp_cell: Vector2i = traverse.get("warp_cell", Vector2i.ZERO)
		var edge_cell: Vector2i = traverse.get("edge_cell", Vector2i.ZERO)
		args.append("--playtest-traverse=%d,%d;%d,%d;%s" % [warp_cell.x, warp_cell.y,
			edge_cell.x, edge_cell.y, str(traverse.get("edge_direction", "left"))])
	if event_probe != "":
		args.append("--playtest-event=" + event_probe)
	if probe:
		args.append("--playtest-probe")
	pid = OS.create_process(executable, args, false)
	if pid <= 0:
		return "could not launch play-test process"
	return ""


func wait_for_handshake(tree: SceneTree, timeout_ms := 15000) -> Dictionary:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		var ack := _read_handshake()
		if not ack.is_empty():
			return ack
		if pid > 0 and not OS.is_process_running(pid):
			return {"ok": false, "error": "play-test exited before its ready handshake"}
		await tree.create_timer(0.05).timeout
	return {"ok": false, "error": "play-test did not become ready within %.1f s" % (timeout_ms / 1000.0)}


func wait_for_exit(tree: SceneTree, timeout_ms := 5000) -> bool:
	var started := Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started < timeout_ms:
		await tree.create_timer(0.05).timeout
	return pid <= 0 or not OS.is_process_running(pid)


func cleanup_handshake() -> void:
	if FileAccess.file_exists(handshake_path):
		DirAccess.remove_absolute(handshake_path)


func _read_handshake() -> Dictionary:
	if not FileAccess.file_exists(handshake_path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(handshake_path))
	if not (parsed is Dictionary):
		return {} # The parent may observe the file between create and the completed write.
	var ack: Dictionary = parsed
	if str(ack.get("token", "")) != token:
		return {"ok": false, "error": "play-test handshake token mismatch"}
	return ack


static func save_slot_for(open_project_dir: String) -> String:
	return "studio_" + _normalized_project_dir(open_project_dir).md5_text().substr(0, 16)


static func save_path_for(open_project_dir: String) -> String:
	return ProjectSettings.globalize_path(
		"user://pokeredpc_save_%s.json" % save_slot_for(open_project_dir))


static func _normalized_project_dir(open_project_dir: String) -> String:
	var normalized := ProjectSettings.globalize_path(open_project_dir).simplify_path().replace("\\", "/")
	return normalized.to_lower() if OS.get_name() == "Windows" else normalized
