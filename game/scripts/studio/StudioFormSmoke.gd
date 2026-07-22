extends RefCounted
class_name StudioFormSmoke
## The gh #49 leg of --studiotest. Kept outside StudioShell so production panel
## behavior and the form engine's end-to-end fixture driver change independently.


func run(shell, scratch: String) -> bool:
	var ok := true
	# The form is generated from the validator's real schema. Drive its public field
	# seam and actual Control signals, never private layout internals.
	var species_file := scratch.path_join("data/species/bulbasaur.json")
	var species_raw := FileAccess.get_file_as_string(species_file)
	var bulbasaur = JSON.parse_string(species_raw)
	var editor_context := ProjectValidator.editor_context(scratch, "species")
	var form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(form)
	form.bind_record("species", "bulbasaur", bulbasaur, editor_context)
	var name_input: Control = form.field_control("/name")
	ok = _check("schema form generates the species name field",
		name_input is LineEdit and (name_input as LineEdit).text == str(bulbasaur["name"])) and ok
	var type_input: Control = form.field_control("/types/0")
	ok = _check("x-ref field is a picker over the validator's type ids",
		type_input is OptionButton and (type_input as OptionButton).item_count == 15
		and (type_input as OptionButton).get_item_text((type_input as OptionButton).selected)
			== str(bulbasaur["types"][0]), str(editor_context.get("errors", []))) and ok
	(name_input as LineEdit).text = ""
	(name_input as LineEdit).text_changed.emit("")
	var refused: Array = form.save_record(species_file)
	ok = _check("invalid field reports inline and save leaves bytes untouched",
		form.field_error("/name").contains("minLength") and not refused.is_empty()
		and FileAccess.get_file_as_string(species_file) == species_raw,
		"; ".join(PackedStringArray(refused))) and ok
	var edited_name := "BULBASAUR PRIME"
	(name_input as LineEdit).text = edited_name
	(name_input as LineEdit).text_changed.emit(edited_name)
	var save_errors: Array = form.save_record(species_file)
	var edited: Dictionary = (bulbasaur as Dictionary).duplicate(true)
	edited["name"] = edited_name
	var project_report := ProjectValidator.validate_project(scratch)
	ok = _check("valid widget edit saves canonically and the project validates",
		save_errors.is_empty() and not form.is_dirty()
		and FileAccess.get_file_as_string(species_file) == CanonJSON.serialize(edited) + "\n"
		and bool(project_report["ok"]), "; ".join(PackedStringArray(save_errors))) and ok
	(name_input as LineEdit).text = "UNSAVED NAME"
	(name_input as LineEdit).text_changed.emit("UNSAVED NAME")
	var was_dirty: bool = form.is_dirty()
	form.revert_record()
	var reverted_name: Control = form.field_control("/name")
	ok = _check("revert restores the last saved draft and clears dirty state",
		was_dirty and not form.is_dirty() and reverted_name is LineEdit
		and (reverted_name as LineEdit).text == edited_name) and ok
	var hp_input: Control = form.field_control("/stats/hp")
	var growth_input: Control = form.field_control("/growth")
	ok = _check("nested integers and enums use schema-derived controls",
		hp_input is SpinBox and int((hp_input as SpinBox).value) == int(bulbasaur["stats"]["hp"])
		and int((hp_input as SpinBox).min_value) == 1
		and int((hp_input as SpinBox).max_value) == 255
		and growth_input is OptionButton and (growth_input as OptionButton).item_count == 4
		and (growth_input as OptionButton).get_item_text((growth_input as OptionButton).selected)
			== str(bulbasaur["growth"])) and ok
	var valid_species_raw := FileAccess.get_file_as_string(species_file)
	var dangling_species: Dictionary = JSON.parse_string(valid_species_raw)
	(dangling_species["types"] as Array)[0] = "type:no_such_type"
	var dangling_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(dangling_form)
	dangling_form.bind_record("species", "bulbasaur", dangling_species, editor_context)
	var dangling_picker: OptionButton = dangling_form.field_control("/types/0")
	var dangling_errors: Array = dangling_form.save_record(species_file)
	ok = _check("dangling x-ref stays visible and is refused before write",
		dangling_picker.get_item_text(dangling_picker.selected).begins_with("[missing]")
		and dangling_form.field_error("/types/0").contains("dangling reference")
		and not dangling_errors.is_empty()
		and FileAccess.get_file_as_string(species_file) == valid_species_raw,
		"; ".join(PackedStringArray(dangling_errors))) and ok

	# Missing required fields still get a repair control and their root-reported schema
	# error is routed to that field's inline label.
	var missing_name: Dictionary = JSON.parse_string(valid_species_raw)
	missing_name.erase("name")
	var missing_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(missing_form)
	missing_form.bind_record("species", "bulbasaur", missing_name, editor_context)
	ok = _check("missing required field is repairable and reports inline",
		missing_form.field_control("/name") is LineEdit
		and missing_form.field_error("/name").contains("missing required field")) and ok
	var missing_nested: Dictionary = JSON.parse_string(valid_species_raw)
	missing_nested.erase("stats")
	missing_nested.erase("types")
	var missing_nested_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(missing_nested_form)
	missing_nested_form.bind_record("species", "bulbasaur", missing_nested, editor_context)
	var repair_hp: SpinBox = missing_nested_form.field_control("/stats/hp")
	repair_hp.value = 99
	repair_hp.value_changed.emit(99.0)
	var repair_type: OptionButton = missing_nested_form.field_control("/types/0")
	repair_type.item_selected.emit(repair_type.selected)
	ok = _check("missing required containers are created by their first nested edit",
		missing_nested_form.is_dirty()
		and not missing_nested_form.field_error("/stats").contains("missing required field 'stats'")
		and not missing_nested_form.field_error("/types").contains("missing required field 'types'")) and ok
	var bad_context: Dictionary = editor_context.duplicate(true)
	bad_context["ok"] = false
	bad_context["errors"] = ["editor context unavailable"]
	var root_error_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(root_error_form)
	root_error_form.bind_record("species", "bulbasaur", JSON.parse_string(valid_species_raw),
		bad_context)
	ok = _check("unmapped validation failures have a visible form-level error",
		root_error_form.field_error("").contains("editor context unavailable")) and ok

	var registry := preload("res://scripts/studio/FormWidgetRegistry.gd").new()
	registry.register("species", "/name", func(_schema: Dictionary, value, changed: Callable) -> Control:
		var custom_input := LineEdit.new()
		custom_input.text = str(value)
		custom_input.set_meta("studiotest_custom", true)
		custom_input.text_changed.connect(changed)
		return custom_input)
	var custom_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(custom_form)
	custom_form.bind_record("species", "bulbasaur", JSON.parse_string(valid_species_raw),
		editor_context, registry)
	var custom_name: LineEdit = custom_form.field_control("/name")
	custom_name.text = "CUSTOM WIDGET EDIT"
	custom_name.text_changed.emit(custom_name.text)
	ok = _check("custom widget registry overrides the exact content-type and field path",
		custom_name.has_meta("studiotest_custom") and custom_form.is_dirty()
		and not custom_form.field_control("/stats/hp").has_meta("studiotest_custom")) and ok
	var add_move: Button = form.array_add_control("/start_moves")
	add_move.pressed.emit()
	var added_move: Control = form.field_control("/start_moves/2")
	var added_dirty := form.is_dirty()
	form.revert_record()
	ok = _check("default array widget adds a schema-shaped entry and reverts it",
		added_move is OptionButton and (added_move as OptionButton).item_count == 165
		and added_dirty and form.field_control("/start_moves/2") == null) and ok
	var remove_move: Button = form.array_remove_control("/start_moves/1")
	remove_move.pressed.emit()
	var removed_dirty := form.is_dirty()
	var removed: bool = form.field_control("/start_moves/1") == null
	form.revert_record()
	ok = _check("default array widget removes an entry and revert restores it",
		removed_dirty and removed and form.field_control("/start_moves/1") is OptionButton) and ok

	var item_context := ProjectValidator.editor_context(scratch, "items")
	var town_map_file := scratch.path_join("data/items/town_map.json")
	var town_map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(town_map_file))
	var item_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(item_form)
	item_form.bind_record("items", "town_map", town_map, item_context)
	var add_price: Button = item_form.optional_add_control("/price")
	add_price.pressed.emit()
	var price_input: Control = item_form.field_control("/price")
	var optional_dirty := item_form.is_dirty()
	item_form.revert_record()
	ok = _check("absent optional schema field can be added and reverted",
		price_input is SpinBox and int((price_input as SpinBox).value) == 0
		and optional_dirty and item_form.field_control("/price") == null
		and item_form.optional_add_control("/price") is Button) and ok
	var potion: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		scratch.path_join("data/items/potion.json")))
	var potion_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(potion_form)
	potion_form.bind_record("items", "potion", potion, item_context)
	var remove_price: Button = potion_form.optional_remove_control("/price")
	remove_price.pressed.emit()
	var price_removed := potion_form.field_control("/price") == null
	var add_after_remove := potion_form.optional_add_control("/price") is Button
	var remove_dirty := potion_form.is_dirty()
	potion_form.revert_record()
	ok = _check("present optional schema field can be removed and reverted",
		price_removed and add_after_remove and remove_dirty
		and potion_form.optional_add_control("/price") == null
		and potion_form.field_control("/price") is SpinBox) and ok

	# A free-form object is still one schema field: edit its complete JSON value through
	# one generated control rather than silently dropping extension keys.
	var custom_item: Dictionary = town_map.duplicate(true)
	custom_item["custom"] = {"difficulty": "hard", "bonus": 3}
	var freeform := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(freeform)
	freeform.bind_record("items", "town_map", custom_item, item_context)
	var custom_json: Control = freeform.field_control("/custom")
	if custom_json is TextEdit:
		(custom_json as TextEdit).text = "{\"bonus\":7,\"difficulty\":\"easy\"}"
		(custom_json as TextEdit).text_changed.emit()
	ok = _check("free-form custom object gets an editable JSON control",
		custom_json is TextEdit and (custom_json as TextEdit).text.contains("difficulty")
		and freeform.is_dirty() and freeform.field_error("/custom") == "") and ok

	var mounted_form = shell.edit_record("items", "town_map")
	ok = _check("shell mounts a schema form for a selected record",
		mounted_form != null and mounted_form.field_control("/name") is LineEdit
		and mounted_form.get_parent() != null) and ok
	var collection_registry := preload("res://scripts/studio/FormWidgetRegistry.gd").new()
	collection_registry.register("species", "/types",
		func(_schema: Dictionary, _value, changed: Callable) -> Control:
			var custom_types := Button.new()
			custom_types.text = "Custom types"
			custom_types.set_meta("studiotest_collection", true)
			custom_types.pressed.connect(func() -> void: changed.call(["type:fire"]))
			return custom_types)
	var collection_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(collection_form)
	collection_form.bind_record("species", "bulbasaur", JSON.parse_string(valid_species_raw),
		editor_context, collection_registry)
	var custom_types: Button = collection_form.field_control("/types")
	custom_types.pressed.emit()
	ok = _check("registry can override a whole array field",
		custom_types.has_meta("studiotest_collection") and collection_form.is_dirty()
		and collection_form.field_control("/types/0") == null) and ok
	var move_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(move_form)
	move_form.bind_record("moves", "tackle", JSON.parse_string(FileAccess.get_file_as_string(
		scratch.path_join("data/moves/tackle.json"))),
		ProjectValidator.editor_context(scratch, "moves"))
	var trainer_form := preload("res://scripts/studio/SchemaForm.gd").new()
	shell.add_child(trainer_form)
	trainer_form.bind_record("trainers", "opp_brock", JSON.parse_string(
		FileAccess.get_file_as_string(scratch.path_join("data/trainers/opp_brock.json"))),
		ProjectValidator.editor_context(scratch, "trainers"))
	ok = _check("all four Phase-4 schemas generate their nested/reference controls",
		move_form.field_control("/type") is OptionButton
		and move_form.field_control("/power") is SpinBox
		and trainer_form.field_control("/parties/0/0/species") is OptionButton
		and trainer_form.field_control("/parties/0/0/level") is SpinBox) and ok
	return ok


func _check(name: String, good: bool, detail := "") -> bool:
	print("[studiotest] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
