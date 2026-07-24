extends RefCounted
class_name StudioScriptSmoke
## The gh #67 leg of --studiotest: the syntax-checked HatchScript editor — script
## browsing and creation through the real dialog, a monospace multiline /source field,
## live positioned parse diagnostics in the gh #61 error styling, save refusal that
## never disturbs the last good bytes, and Save/Revert dirty-state participation.


func run(shell, _scratch: String) -> bool:
	var ok := true
	if not shell.has_method("new_script_fields"):
		return _check("shell exposes the script-creation seam", false)
	# --- browsing: the scripts kind joins the sidebar (Kanto ships zero scripts) ---
	shell.select_workspace("scripts")
	var new_button: Button = shell.new_map_control()
	ok = _check("scripts workspace arms the creation button",
		not new_button.disabled and new_button.text == "New script…",
		"text='%s' disabled=%s" % [new_button.text, str(new_button.disabled)]) and ok
	# --- creation refusal: an id-pattern-breaking name never touches disk ---
	var fields: Dictionary = shell.new_script_fields()
	(fields["name"] as LineEdit).text = "Bad Name"
	(fields["dialog"] as ConfirmationDialog).confirmed.emit()
	ok = _check("an invalid script name refuses before disk",
		not FileAccess.file_exists(
			shell.project_dir.path_join("data/scripts/Bad Name.json"))) and ok
	# --- creation: the record lands and its editor opens ---
	(fields["name"] as LineEdit).text = "door_puzzle"
	(fields["dialog"] as ConfirmationDialog).confirmed.emit()
	var path: String = shell.project_dir.path_join("data/scripts/door_puzzle.json")
	ok = _check("creation writes the record and lists it",
		FileAccess.file_exists(path)
		and _records_contain(shell.records_control(), "door_puzzle")) and ok
	var form = shell.edit_record("scripts", "door_puzzle")
	if form == null:
		return _check("script record opens in the schema form", false) and ok
	var source: TextEdit = form.field_control("/source")
	ok = _check("the /source field is a monospace multiline editor",
		source is TextEdit and source.has_theme_font_override("font")) and ok
	# --- live positioned diagnostics (the gh #61 label + danger border flow) ---
	var before := FileAccess.get_file_as_string(path)
	source.text = "let broken =\nreturn 1"
	source.text_changed.emit()
	ok = _check("a broken draft names its position inline with the danger border",
		form.field_error("/source").contains("line 2, column 1") and form.is_dirty()
		and source.has_theme_stylebox_override("normal"),
		form.field_error("/source")) and ok
	var errors: Array = form.save_record(path)
	ok = _check("a broken draft cannot be saved and the bytes are untouched",
		not errors.is_empty() and FileAccess.get_file_as_string(path) == before,
		"; ".join(PackedStringArray(errors))) and ok
	# --- the fix clears the diagnostic, saves, and validates whole-project ---
	source.text = "let code = 2 * 100 + 41\nreturn code == 241"
	source.text_changed.emit()
	ok = _check("the fixed draft clears the diagnostic",
		form.field_error("/source") == "", form.field_error("/source")) and ok
	errors = form.save_record(path)
	var report: Dictionary = ProjectValidator.validate_project(shell.project_dir)
	ok = _check("the fixed script saves clean and the project validates",
		errors.is_empty() and not form.is_dirty() and bool(report.get("ok", false)),
		"; ".join(PackedStringArray(report.get("errors", [])))) and ok
	# --- Revert restores the last save (the rebuild replaces the control) ---
	source = form.field_control("/source")
	source.text = "let x ="
	source.text_changed.emit()
	var was_dirty: bool = form.is_dirty()
	form.revert_record()
	var reverted: TextEdit = form.field_control("/source")
	ok = _check("Revert restores the last good source and clears dirty",
		was_dirty and not form.is_dirty()
		and reverted.text.begins_with("let code"), reverted.text) and ok
	return ok


static func _records_contain(records: ItemList, wanted: String) -> bool:
	for i in records.item_count:
		if records.get_item_text(i) == wanted:
			return true
	return false


func _check(name: String, good: bool, detail := "") -> bool:
	print("[studioscript] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
