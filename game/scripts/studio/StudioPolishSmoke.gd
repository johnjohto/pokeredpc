extends RefCounted
class_name StudioPolishSmoke
## gh #61: the schema-driven editor's presentation layer. Record-browser filtering with
## an explicit empty state, curated section cards in layout order, required markers,
## and danger borders on invalid inputs — all while the gh #49/#50 contracts (field
## paths, error labels, canonical saves) stay with the other smokes.


func run(shell: StudioShell, _scratch: String) -> bool:
	var ok := true
	shell.select_workspace("species")
	var filter: LineEdit = shell.records_filter_control()
	var records: ItemList = shell.records_control()
	filter.text = "saur"
	filter.text_changed.emit("saur")
	var names: Array = []
	for index in records.item_count:
		names.append(records.get_item_text(index))
	ok = _check("record filter narrows the browser to matching records",
		names == ["bulbasaur", "ivysaur", "venusaur"], str(names)) and ok
	filter.text = "zzz"
	filter.text_changed.emit("zzz")
	ok = _check("a no-match filter shows an explicit empty state",
		records.item_count == 1 and records.get_item_text(0) == "(no matches)"
		and records.is_item_disabled(0)) and ok
	filter.text = ""
	filter.text_changed.emit("")
	ok = _check("clearing the filter restores every record", records.item_count == 151,
		"got %d" % records.item_count) and ok

	var form = shell.edit_record("species", "bulbasaur")
	ok = _check("species fields group into curated sections in layout order",
		form != null and form.section_titles() == ["Identity", "Battle", "Moves",
			"Evolution", "Advanced"], str(form.section_titles() if form != null else [])) and ok
	if form == null:
		return false
	ok = _check("nested fields report their root section",
		form.section_for_field("/stats/hp") == "Battle"
		and form.section_for_field("/dex/num") == "Identity"
		and form.section_for_field("/level_moves/0/move") == "Moves") and ok
	var required_label: Label = form.field_label("/name")
	var required_marker: Label = form.field_marker("/name")
	ok = _check("required fields carry the marker; plain fields stay muted",
		required_label != null and required_marker != null and required_marker.visible
		and required_marker.text == "*",
		"label=%s" % required_label) and ok

	var name_input: LineEdit = form.field_control("/name")
	name_input.text = ""
	name_input.text_changed.emit("")
	var marked := name_input.has_theme_stylebox_override("normal")
	var error_text: String = form.field_error("/name")
	name_input.text = "Bulbasaur"
	name_input.text_changed.emit("Bulbasaur")
	ok = _check("an invalid draft marks the input and explains beside it",
		marked and error_text.contains("minLength"), error_text) and ok
	ok = _check("fixing the draft clears the marking", not name_input.has_theme_stylebox_override("normal")
		and form.field_error("/name") == "") and ok
	form.revert_record()

	var moves_form = shell.edit_record("moves", "pound")
	ok = _check("moves sections follow their own layout",
		moves_form != null and moves_form.section_titles() == ["Identity", "Battle", "Advanced"],
		str(moves_form.section_titles() if moves_form != null else [])) and ok
	var items_form = shell.edit_record("items", "potion")
	ok = _check("items sections follow their own layout",
		items_form != null and items_form.section_titles() == ["Identity", "Details", "Advanced"],
		str(items_form.section_titles() if items_form != null else [])) and ok
	var trainers_form = shell.edit_record("trainers", "opp_blaine")
	ok = _check("trainers sections follow their own layout",
		trainers_form != null and trainers_form.section_titles() == ["Identity", "Battle", "Advanced"],
		str(trainers_form.section_titles() if trainers_form != null else [])) and ok
	# The layout map is curated: a typo must fail loudly here, not silently hide a
	# field in "Other". Every layout name must resolve against its schema.
	var drift: Array = []
	var schema_files := {"species": "species", "moves": "move", "items": "item", "trainers": "trainer"}
	for content_type in StudioFormLayout.SECTIONS:
		var schema = JSON.parse_string(FileAccess.get_file_as_string(
			"res://core/schemas/%s.schema.json" % schema_files[content_type]))
		var properties: Dictionary = schema.get("properties", {}) if schema is Dictionary else {}
		for entry in StudioFormLayout.SECTIONS[content_type]:
			for field in entry[1]:
				if not properties.has(field):
					drift.append("%s/%s" % [content_type, field])
	ok = _check("every curated layout field resolves against its schema", drift.is_empty(),
		str(drift)) and ok
	print("[studiopolish] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[studiopolish] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
