extends RefCounted
class_name StudioEditorSmoke
## The gh #50 leg of --studiotest: the four content editors and the four deliberately
## scoped custom widgets from ADR-020 d3.


func run(shell, scratch: String) -> bool:
	var ok := true
	var species_form = shell.edit_record("species", "bulbasaur")
	var sprites: Control = species_form.field_control("/sprites") if species_form != null else null
	var types: Control = species_form.field_control("/types") if species_form != null else null
	var learnset: Control = species_form.field_control("/level_moves") if species_form != null else null
	ok = _check("species editor mounts sprite, type, and learnset widgets",
		species_form != null
		and sprites != null and sprites.has_method("picker")
		and types != null and types.has_method("slot_picker")
		and learnset != null and learnset.has_method("level_control")) and ok
	var front: OptionButton = sprites.call("picker", "front") if sprites != null else null
	var back: OptionButton = sprites.call("picker", "back") if sprites != null else null
	var front_preview: TextureRect = sprites.call("preview", "front") if sprites != null else null
	var charmander_front := _metadata_index(front, "assets/pokemon/front/charmander.png")
	if charmander_front >= 0:
		front.item_selected.emit(charmander_front)
	var second_type_remove: Button = types.call("remove_control", 1) if types != null else null
	if second_type_remove != null:
		second_type_remove.pressed.emit()
	var removed_type := (types.call("current_value") as Array).size() == 1
	var add_type: Button = types.call("add_control") if types != null else null
	if add_type != null:
		add_type.pressed.emit()
	var first_type: OptionButton = types.call("slot_picker", 0) if types != null else null
	var fire_type := _metadata_index(first_type, "type:fire")
	if fire_type >= 0:
		first_type.item_selected.emit(fire_type)
	var original_learnset_size: int = learnset.call("row_count") if learnset != null else -1
	var add_move: Button = learnset.call("add_control") if learnset != null else null
	if add_move != null:
		add_move.pressed.emit()
	var added_learnset_row: bool = learnset.call("row_count") == original_learnset_size + 1
	var remove_added_move: Button = learnset.call("remove_control", original_learnset_size) \
		if learnset != null else null
	if remove_added_move != null:
		remove_added_move.pressed.emit()
	var first_level: SpinBox = learnset.call("level_control", 0) if learnset != null else null
	if first_level != null:
		first_level.value = 8
		first_level.value_changed.emit(8.0)
	ok = _check("species widgets preview assets and edit bounded structured values",
		front != null and back != null and front.item_count == 151 and back.item_count == 151
		and front_preview != null and front_preview.texture != null
		and charmander_front >= 0 and removed_type
		and (types.call("current_value") as Array).size() == 2
		and added_learnset_row and learnset.call("row_count") == original_learnset_size
		and species_form.is_dirty()) and ok
	var species_path := scratch.path_join("data/species/bulbasaur.json")
	var species_save_errors: Array = species_form.save_record(species_path)
	var saved_species: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(species_path))
	ok = _check("species custom-widget edits save canonically and validate",
		species_save_errors.is_empty() and not species_form.is_dirty()
		and saved_species["sprites"]["front"] == "assets/pokemon/front/charmander.png"
		and saved_species["types"][0] == "type:fire"
		and int(saved_species["level_moves"][0]["level"]) == 8,
		"; ".join(PackedStringArray(species_save_errors))) and ok
	var saved_types: Array = saved_species["types"]
	var unsaved_types: Control = species_form.field_control("/types")
	var unsaved_first_type: OptionButton = unsaved_types.call("slot_picker", 0)
	var water_type := _metadata_index(unsaved_first_type, "type:water")
	if water_type >= 0:
		unsaved_first_type.item_selected.emit(water_type)
	var custom_was_dirty: bool = species_form.is_dirty()
	species_form.revert_record()
	var reverted_types: Control = species_form.field_control("/types")
	ok = _check("Revert restores saved custom-widget values",
		custom_was_dirty and not species_form.is_dirty()
		and reverted_types.call("current_value") == saved_types) and ok

	var move_form = shell.edit_record("moves", "tackle")
	ok = _check("move editor remains schema-driven",
		move_form != null and move_form.field_control("/type") is OptionButton
		and move_form.field_control("/power") is SpinBox) and ok
	var item_form = shell.edit_record("items", "potion")
	ok = _check("item editor remains schema-driven",
		item_form != null and item_form.field_control("/price") is SpinBox) and ok

	var trainer_form = shell.edit_record("trainers", "opp_brock")
	var parties: Control = trainer_form.field_control("/parties") if trainer_form != null else null
	ok = _check("trainer editor mounts the party builder",
		trainer_form != null and parties != null
		and parties.has_method("species_control") and parties.has_method("level_control")) and ok
	var initial_parties: int = parties.call("party_count") if parties != null else -1
	var add_party: Button = parties.call("add_party_control") if parties != null else null
	if add_party != null:
		add_party.pressed.emit()
	var added_party: bool = parties.call("party_count") == initial_parties + 1
	var remove_party: Button = parties.call("remove_party_control", initial_parties) \
		if parties != null else null
	if remove_party != null:
		remove_party.pressed.emit()
	var initial_members: int = parties.call("member_count", 0) if parties != null else -1
	var add_member: Button = parties.call("add_member_control", 0) if parties != null else null
	if add_member != null:
		add_member.pressed.emit()
	var added_member: bool = parties.call("member_count", 0) == initial_members + 1
	var remove_member: Button = parties.call("remove_member_control", 0, initial_members) \
		if parties != null else null
	if remove_member != null:
		remove_member.pressed.emit()
	var first_species: OptionButton = parties.call("species_control", 0, 0) \
		if parties != null else null
	var abra := _metadata_index(first_species, "species:abra")
	if abra >= 0:
		first_species.item_selected.emit(abra)
	var first_member_level: SpinBox = parties.call("level_control", 0, 0) \
		if parties != null else null
	if first_member_level != null:
		first_member_level.value = 15
		first_member_level.value_changed.emit(15.0)
	ok = _check("party builder adds/removes variants and members, then edits a member",
		added_party and parties.call("party_count") == initial_parties
		and added_member and parties.call("member_count", 0) == initial_members
		and abra >= 0 and trainer_form.is_dirty()) and ok
	var trainer_path := scratch.path_join("data/trainers/opp_brock.json")
	var trainer_save_errors: Array = trainer_form.save_record(trainer_path)
	var saved_trainer: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(trainer_path))
	var final_report := ProjectValidator.validate_project(scratch)
	ok = _check("trainer party edit saves and the complete Studio project validates",
		trainer_save_errors.is_empty() and not trainer_form.is_dirty()
		and saved_trainer["parties"][0][0]["species"] == "species:abra"
		and int(saved_trainer["parties"][0][0]["level"]) == 15
		and bool(final_report["ok"]), "; ".join(PackedStringArray(
			trainer_save_errors if not trainer_save_errors.is_empty() else final_report["errors"]))) and ok
	return ok


func _metadata_index(picker: OptionButton, wanted: String) -> int:
	if picker == null:
		return -1
	for i in picker.item_count:
		if str(picker.get_item_metadata(i)) == wanted:
			return i
	return -1


func _check(name: String, good: bool, detail := "") -> bool:
	print("[studiotest] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
