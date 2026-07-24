extends RefCounted
class_name StudioCreatorTypesSmoke
## The gh #68 extensibility legs of --studiotest (ADR-031): custom-field declarations
## give real form controls and validation teeth to the reserved custom bag, and a
## creator-defined content type becomes a browsable, creatable, x-ref-able record
## family — all through real Studio controls, no hand-edited files.

const ARTIFACT_SCHEMA := """{"type": "object", "required": ["id", "name"],
 "properties": {"id": {"type": "string"}, "name": {"type": "string"},
 "power": {"type": "integer", "minimum": 1}, "custom": {"type": "object"}},
 "additionalProperties": false}"""


func run(shell, _scratch: String) -> bool:
	var ok := true
	if not shell.has_method("new_record_fields"):
		return _check("shell exposes the creator-type seams", false)
	# --- custom-field declarations: create the table, declare three item fields ---
	shell.select_workspace("custom_fields")
	var create_button: Button = shell.new_map_control()
	ok = _check("custom_fields workspace offers creation while the file is missing",
		create_button.text == "Create custom_fields.json"
		and not create_button.disabled) and ok
	create_button.pressed.emit()
	var form = shell.edit_table("data/custom_fields.json", "custom_fields")
	if form == null:
		return _check("custom_fields opens in the schema form", false) and ok
	(form.map_key_control("") as LineEdit).text = "items"
	(form.map_add_control("") as Button).pressed.emit()
	for declared in [["rarity", '{"type": "integer", "minimum": 0}'],
			["companion", '{"type": "string", "x-ref": "species"}'],
			["relic", '{"type": "string", "x-ref": "artifact"}']]:
		(form.map_key_control("/items") as LineEdit).text = str(declared[0])
		(form.map_add_control("/items") as Button).pressed.emit()
		var fragment: TextEdit = form.field_control("/items/%s" % declared[0])
		fragment.text = str(declared[1])
		fragment.text_changed.emit()
	var path: String = shell.project_dir.path_join("data/custom_fields.json")
	var errors: Array = form.save_record(path)
	ok = _check("three declared item fields save clean", errors.is_empty(),
		"; ".join(PackedStringArray(errors))) and ok
	# a keyword typo in a declaration refuses at draft time, never at first-record time
	(form.map_key_control("/items") as LineEdit).text = "broken"
	(form.map_add_control("/items") as Button).pressed.emit()
	var broken: TextEdit = form.field_control("/items/broken")
	broken.text = '{"tyep": "integer"}'
	broken.text_changed.emit()
	ok = _check("a typo'd declaration keyword refuses inline",
		form.field_error("/items/broken").contains("tyep")
		and not form.save_record(path).is_empty()) and ok
	form.revert_record()
	# --- the declared shape reaches the record editor with validation teeth ---
	var item_form = shell.edit_record("items", "potion")
	(item_form.optional_add_control("/custom") as Button).pressed.emit()
	(item_form.optional_add_control("/custom/rarity") as Button).pressed.emit()
	var rarity: SpinBox = item_form.field_control("/custom/rarity")
	ok = _check("a declared custom field renders a REAL control", rarity is SpinBox) and ok
	rarity.value = -1
	rarity.value_changed.emit(rarity.value)
	var item_path: String = shell.project_dir.path_join("data/items/potion.json")
	ok = _check("a declaration violation refuses inline and cannot save",
		item_form.field_error("/custom/rarity") != ""
		and not item_form.save_record(item_path).is_empty()) and ok
	rarity.value = 3
	rarity.value_changed.emit(rarity.value)
	(item_form.optional_add_control("/custom/companion") as Button).pressed.emit()
	var companion: OptionButton = item_form.field_control("/custom/companion")
	ok = _check("a declared x-ref field renders the id picker",
		companion is OptionButton and companion.item_count > 100) and ok
	_pick(companion, "species:pikachu")
	errors = item_form.save_record(item_path)
	ok = _check("declared custom values save clean", errors.is_empty(),
		"; ".join(PackedStringArray(errors))) and ok
	# --- creator content types: declare, refuse collisions, create records ---
	shell.select_workspace("content_types")
	shell.new_map_control().pressed.emit()
	var types_form = shell.edit_table("data/content_types.json", "content_types")
	if types_form == null:
		return _check("content_types opens in the schema form", false) and ok
	(types_form.map_key_control("") as LineEdit).text = "species"
	(types_form.map_add_control("") as Button).pressed.emit()
	var types_path: String = shell.project_dir.path_join("data/content_types.json")
	ok = _check("a kind colliding with the built-in layout refuses inline",
		types_form.field_error("/species").contains("collides")
		and not types_form.save_record(types_path).is_empty()) and ok
	types_form.map_remove_control("/species").pressed.emit()
	(types_form.map_key_control("") as LineEdit).text = "artifact"
	(types_form.map_add_control("") as Button).pressed.emit()
	var prefix_input: LineEdit = types_form.field_control("/artifact/id_prefix")
	prefix_input.text = "artifact"
	prefix_input.text_changed.emit(prefix_input.text)
	var schema_input: TextEdit = types_form.field_control("/artifact/schema")
	schema_input.text = ARTIFACT_SCHEMA
	schema_input.text_changed.emit()
	errors = types_form.save_record(types_path)
	ok = _check("the artifact declaration saves clean", errors.is_empty(),
		"; ".join(PackedStringArray(errors))) and ok
	# --- the declared kind is a first-class record family after reopen ---
	var reopen_error: String = shell.open_project(shell.project_dir)
	shell.select_workspace("artifact")
	var new_button: Button = shell.new_map_control()
	ok = _check("the creator kind joins the sidebar with its creation dialog",
		reopen_error == "" and new_button.text == "New artifact…"
		and not new_button.disabled) and ok
	var fields: Dictionary = shell.new_record_fields()
	(fields["name"] as LineEdit).text = "sun_stone"
	(fields["dialog"] as ConfirmationDialog).confirmed.emit()
	var record_path: String = shell.project_dir.path_join("data/artifact/sun_stone.json")
	ok = _check("creation writes the schema-shaped record",
		FileAccess.file_exists(record_path)) and ok
	var artifact_form = shell.edit_record("artifact", "sun_stone")
	var artifact_name: LineEdit = artifact_form.field_control("/name")
	artifact_name.text = "Sun Stone"
	artifact_name.text_changed.emit(artifact_name.text)
	errors = artifact_form.save_record(record_path)
	var report: Dictionary = ProjectValidator.validate_project(shell.project_dir)
	ok = _check("the creator record saves and the whole project validates",
		errors.is_empty() and bool(report.get("ok", false))
		and int((report.get("ids", {}) as Dictionary).get("artifact", 0)) == 1,
		"; ".join(PackedStringArray(report.get("errors", [])))) and ok
	# --- the features compose: a custom field x-refs the creator kind ---
	item_form = shell.edit_record("items", "potion")
	(item_form.optional_add_control("/custom/relic") as Button).pressed.emit()
	var relic: OptionButton = item_form.field_control("/custom/relic")
	_pick(relic, "artifact:sun_stone")
	errors = item_form.save_record(item_path)
	report = ProjectValidator.validate_project(shell.project_dir)
	ok = _check("a custom field references the creator kind and it all validates",
		errors.is_empty() and bool(report.get("ok", false)),
		"; ".join(PackedStringArray(report.get("errors", [])))) and ok
	return ok


static func _pick(picker: OptionButton, id: String) -> void:
	for i in picker.item_count:
		if str(picker.get_item_metadata(i)) == id:
			picker.select(i)
			picker.item_selected.emit(i)
			return


func _check(name: String, good: bool, detail := "") -> bool:
	print("[studiocreator] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
