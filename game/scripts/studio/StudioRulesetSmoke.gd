extends RefCounted
class_name StudioRulesetSmoke
## The gh #68 knob leg of --studiotest (ADR-031): the ruleset config workspace — the
## singleton table editor, the schema'd map control with the faithful values visible,
## canonical save through the shared preflight, and a child Engine proving the turned
## knob live in play.

const Playtest := preload("res://scripts/studio/StudioPlaytest.gd")


func run(shell, scratch: String) -> bool:
	var ok := true
	if not shell.has_method("edit_table"):
		return _check("shell exposes the singleton table seam", false)
	shell.select_workspace("ruleset")
	ok = _check("the ruleset workspace lists the config record",
		_records_contain(shell.records_control(), "ruleset")) and ok
	# The type chart is a singleton table too: a creator adds an elemental type as
	# data through the same seam (the gh #20 epic's "new type, no engine code").
	var types_form = shell.edit_table("data/types.json", "types")
	ok = _check("the type chart opens with map controls per attacking type",
		types_form != null and types_form.map_add_control("/chart") is Button
		and types_form.field_control("/chart/type:water/type:fire") is SpinBox) and ok
	var form = shell.edit_table("data/ruleset.json", "ruleset")
	if form == null:
		return _check("ruleset config opens in the schema form", false) and ok
	# The faithful defaults are VISIBLE data — the extractor emits the full gen1 tables.
	var stage2: SpinBox = form.field_control("/config/stat_stage_multipliers/2")
	ok = _check("the stage-multiplier map renders per-key controls with faithful values",
		stage2 is SpinBox and int(stage2.value) == 200,
		str(stage2.value) if stage2 != null else "<null>") and ok
	# Turn the knob through the real control and save through the shared preflight.
	stage2.value = 300
	stage2.value_changed.emit(stage2.value)
	var path: String = shell.project_dir.path_join("data/ruleset.json")
	var errors: Array = form.save_record(path)
	var report: Dictionary = ProjectValidator.validate_project(shell.project_dir)
	ok = _check("the turned knob saves clean and the project validates",
		errors.is_empty() and not form.is_dirty() and bool(report.get("ok", false)),
		"; ".join(PackedStringArray(errors))) and ok
	# The map control round-trips: remove the key, re-add it, restore the value.
	(form.map_remove_control("/config/stat_stage_multipliers/2") as Button).pressed.emit()
	ok = _check("removing a map key drops its control and dirties the draft",
		form.field_control("/config/stat_stage_multipliers/2") == null
		and form.is_dirty()) and ok
	var key_input: LineEdit = form.map_key_control("/config/stat_stage_multipliers")
	key_input.text = "2"
	(form.map_add_control("/config/stat_stage_multipliers") as Button).pressed.emit()
	var re_added: SpinBox = form.field_control("/config/stat_stage_multipliers/2")
	ok = _check("re-adding the key rebuilds its control",
		re_added is SpinBox) and ok
	re_added.value = 300
	re_added.value_changed.emit(re_added.value)
	errors = form.save_record(path)
	ok = _check("the map round-trip saves clean", errors.is_empty(),
		"; ".join(PackedStringArray(errors))) and ok
	# A separate child Engine proves the knob is LIVE in play, not just on disk.
	var pt := Playtest.new()
	var launch_error: String = pt.launch(scratch, true, true, "", [], {}, "", true)
	ok = _check("knob play-test child launches", launch_error == "", launch_error) and ok
	if launch_error == "":
		var ack: Dictionary = await pt.wait_for_handshake(shell.get_tree(), 30000)
		var exited: bool = await pt.wait_for_exit(shell.get_tree(), 5000)
		pt.cleanup_handshake()
		ok = _check("child engine answers stage_apply(100, 2) == 300 through the seam",
			bool(ack.get("ok", false)) and int(ack.get("formula_stage2", -1)) == 300
			and exited, str(ack.get("formula_stage2", "<absent>"))) and ok
	return ok


static func _records_contain(records: ItemList, wanted: String) -> bool:
	for i in records.item_count:
		if records.get_item_text(i) == wanted:
			return true
	return false


func _check(name: String, good: bool, detail := "") -> bool:
	print("[studioruleset] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
