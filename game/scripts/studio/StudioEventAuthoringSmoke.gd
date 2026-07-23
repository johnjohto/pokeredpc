extends RefCounted
class_name StudioEventAuthoringSmoke
## End-to-end gh #56 gate: schema palette/sweep, real map-object event creation,
## nested command-list authoring with undo, canonical save, and child VM execution.


func run(shell: StudioShell, scratch: String) -> bool:
	var ok := true
	var event_dir := scratch.path_join("data/events")
	var schema_source := FileAccess.get_file_as_string("res://core/schemas/event.schema.json")
	var schema = JSON.parse_string(schema_source)
	var palette := _palette(schema)
	var used := {}
	var swept := 0
	var mismatch := ""
	for file in DirAccess.get_files_at(event_dir):
		if not file.ends_with(".json"): continue
		var path := event_dir.path_join(file)
		var raw := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(raw)
		var reserialized := CanonJSON.serialize(parsed) if parsed is Dictionary else ""
		var reparsed = JSON.parse_string(reserialized)
		if not (parsed is Dictionary) or not (reparsed is Dictionary) or reparsed != parsed:
			mismatch = file
			break
		_collect_commands(parsed.get("commands", []), used)
		swept += 1
	var missing: Array = []
	for kind in used:
		if kind not in palette: missing.append(kind)
	var schema_vm_drift: Array = []
	for kind in EventVM.CMDS:
		if kind not in palette: schema_vm_drift.append("schema misses " + str(kind))
	for kind in palette:
		if kind not in EventVM.CMDS: schema_vm_drift.append("VM misses " + str(kind))
	ok = _check("all %d Kanto events round-trip and every used command is in the schema palette" % swept,
		mismatch == "" and missing.is_empty() and schema_vm_drift.is_empty(),
		"mismatch=%s missing=%s schema/VM=%s" % [mismatch, str(missing), str(schema_vm_drift)]) and ok

	var script_dir := scratch.path_join("data/scripts")
	var script_record := {
		"id": "script:studio_combination_lock",
		"source": """let code = 2 * 100 + 4 * 10 + 1
set_var("studio_dial", code)
give_coins(1)
return get_var("studio_dial") == 241 and map_id() == "StudioLinkTest" """
	}
	var script_dir_error := DirAccess.make_dir_recursive_absolute(script_dir)
	var script_path := script_dir.path_join("studio_combination_lock.json")
	var script_write_error := CanonJSON.write_file(script_path, script_record)
	ok = _check("canonical HatchScript record enters the Studio scratch project",
		script_dir_error == OK and script_write_error == "", script_write_error) and ok

	var map_workspace = shell.edit_map("StudioLinkTest")
	ok = _check("authored map reopens for event linking", map_workspace != null,
		shell.status_text()) and ok
	if map_workspace == null: return false
	map_workspace._selected_object_kind = "npc"
	map_workspace._selected_object_id = "link_guide"
	map_workspace._refresh_object_list()
	var object_ui: Dictionary = map_workspace.object_controls()
	(object_ui["edit_event"] as Button).pressed.emit()
	var workspace = shell.active_event_workspace()
	ok = _check("map NPC Create / Edit Event writes and opens a linked event",
		workspace != null and workspace.document.basename == "studiolinktest_link_guide",
		shell.status_text()) and ok
	if workspace == null: return false

	# The script result drives an ordinary event branch. The true branch is non-blocking
	# and observable in the child; the false branch is a nested ask with both answer
	# branches, proving the recursive conversation editor remains intact.
	workspace.add_command([], "run_script")
	workspace.document.replace_command([0], {"cmd": "run_script",
		"script": "script:studio_combination_lock", "result": "studio_script_ok"})
	workspace.add_command([], "if")
	workspace.document.replace_command([1], {"cmd": "if", "cond": "studio_script_ok",
		"then": [], "else": []})
	workspace._rebuild_content()
	workspace.add_command([1, "then"], "notice")
	workspace.document.replace_command([1, "then", 0],
		{"cmd": "notice", "text": "The Studio branch ran."})
	workspace.add_command([1, "then"], "set_flag")
	workspace.document.replace_command([1, "then", 1],
		{"cmd": "set_flag", "flag": "STUDIO_EVENT_BRANCH_RAN"})
	workspace.add_command([1, "else"], "ask")
	workspace.document.replace_command([1, "else", 0],
		{"cmd": "ask", "text": "Take the other branch?", "then": [], "else": []})
	workspace.add_command([1, "else", 0, "then"], "say")
	workspace.document.replace_command([1, "else", 0, "then", 0],
		{"cmd": "say", "text": "Yes branch."})
	workspace.add_command([1, "else", 0, "else"], "say")
	workspace.document.replace_command([1, "else", 0, "else", 0],
		{"cmd": "say", "text": "No branch."})
	workspace._rebuild_content()
	var before_undo: Dictionary = workspace.document.edit_state()
	workspace.add_command([1, "then"], "clear_flag")
	workspace.undo()
	var undo_exact: bool = workspace.document.edit_state() == before_undo
	workspace.redo()
	workspace.undo()
	ok = _check("nested if/ask blocks author through the schema palette with exact undo/redo",
		undo_exact and workspace.command_palette([1, "else", 0, "then"]) != null
		and workspace.document.validate().is_empty(), workspace.status_text()) and ok
	var valid_state: Dictionary = workspace.document.edit_state()
	var disk_before := FileAccess.get_file_as_string(workspace.document.path)
	workspace.document.data["commands"].append({"cmd": "not_a_vm_command"})
	workspace._rebuild_content()
	workspace._update_state()
	var invalid_error: String = workspace.save()
	var invalid_visible: bool = workspace.status_text().begins_with("REFUSED")
	workspace.document.restore_edit_state(valid_state)
	workspace._rebuild_content()
	workspace._update_state()
	ok = _check("an invalid command is visible inline and Save leaves source untouched",
		invalid_error != "" and invalid_visible
		and FileAccess.get_file_as_string(workspace.document.path) == disk_before,
		invalid_error) and ok

	var save_error: String = workspace.save()
	var reopened := EventDocument.open(scratch, "studiolinktest_link_guide")
	var map_opened := MapDocument.open(scratch, "StudioLinkTest")
	var linked_id := ""
	if bool(map_opened.get("ok", false)):
		for object in (map_opened["document"] as MapDocument).objects:
			if str(object.get("id", "")) == "link_guide": linked_id = str(object.get("event", ""))
	var report := ProjectValidator.validate_project(scratch)
	var reopened_script = JSON.parse_string(FileAccess.get_file_as_string(script_path))
	ok = _check("event, script, and TMX link save/reopen and pass whole-project validation",
		save_error == "" and bool(reopened.get("ok", false))
		and reopened_script == script_record
		and linked_id == "event:studiolinktest_link_guide" and bool(report.get("ok", false)),
		save_error + "; " + "; ".join(PackedStringArray(report.get("errors", [])))) and ok

	var child = shell.launch_playtest(true, true, "StudioLinkTest", [], {},
		"studiolinktest_link_guide")
	if child == null:
		return _check("event play-test child launches", false, shell.status_text()) and ok
	var ack: Dictionary = await child.wait_for_handshake(shell.get_tree(), 25000)
	var exited: bool = await child.wait_for_exit(shell.get_tree(), 5000)
	ok = _check("child Engine executes the authored script and takes its result branch",
		bool(ack.get("ok", false)) and bool(ack.get("event_probe_ok", false))
		and bool(ack.get("event_probe_flag", false)) and exited,
		str(ack.get("event_probe_error", ack.get("error", "")))) and ok
	child.cleanup_handshake()
	print("[studioevent] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _palette(schema: Dictionary) -> Array:
	var out: Array = []
	for candidate in schema.get("$defs", {}).get("block", {}).get("items", {}).get("anyOf", []):
		var command: Dictionary = candidate.get("properties", {}).get("cmd", {})
		if command.has("const"): out.append(str(command["const"]))
	return out


static func _collect_commands(commands, out: Dictionary) -> void:
	if not (commands is Array): return
	for command in commands:
		if not (command is Dictionary): continue
		out[str(command.get("cmd", ""))] = true
		_collect_commands(command.get("then", []), out)
		_collect_commands(command.get("else", []), out)


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[studioevent] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
