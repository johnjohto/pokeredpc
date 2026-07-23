extends VBoxContainer
class_name SchemaForm
## Schema-driven record form (ADR-020 d3/d4, gh #49). Public callers bind a record
## and address generated controls by JSON-pointer path; the schema remains the single
## source of field shape and constraints.

var _draft: Dictionary = {}
var _saved: Dictionary = {}
var _schema: Dictionary = {}
var _id_registry: Dictionary = {}
var _basename := ""
var _content_type := ""
var _context: Dictionary = {}
var _widget_registry: RefCounted = null
var _field_controls := {}
var _array_add_controls := {}
var _array_remove_controls := {}
var _optional_add_controls := {}
var _optional_remove_controls := {}
var _error_labels := {}
var _field_labels := {}
var _section_of_field := {}
var _section_titles: Array[String] = []
var _invalid_controls: Array[Control] = []
var _current_errors: Array = []
var _dirty := false

signal dirty_changed(dirty: bool)


func bind_record(content_type: String, basename: String, record: Dictionary,
		context: Dictionary, widget_registry: RefCounted = null) -> void:
	_draft = record.duplicate(true)
	_saved = record.duplicate(true)
	_schema = context.get("schema", {})
	_id_registry = context.get("ids", {})
	_content_type = content_type
	_basename = basename
	_context = context
	_widget_registry = widget_registry
	_set_dirty(false)
	_rebuild()


## The public test/editor seam: return the input control generated for a JSON pointer.
func field_control(path: String) -> Control:
	return _field_controls.get(path, null)


func field_error(path: String) -> String:
	var label: Label = _error_labels.get(path, null)
	return label.text if label != null else ""


func array_add_control(path: String) -> Button:
	return _array_add_controls.get(path, null)


func array_remove_control(item_path: String) -> Button:
	return _array_remove_controls.get(item_path, null)


func optional_add_control(path: String) -> Button:
	return _optional_add_controls.get(path, null)


func optional_remove_control(path: String) -> Button:
	return _optional_remove_controls.get(path, null)


func is_dirty() -> bool:
	return _dirty


## gh #61 presentation seams: the curated section a root field renders under, and the
## section titles in display order ("" / [] when the content type has no layout).
func section_titles() -> Array[String]:
	return _section_titles.duplicate()


func section_for_field(path: String) -> String:
	var segments := path.split("/", false)
	if segments.is_empty():
		return ""
	return str(_section_of_field.get("/" + str(segments[0]), ""))


func field_label(path: String) -> Label:
	return _field_labels.get(path, null)


## The required-field marker beside the label (gh #61); null for nested/ungenerated paths.
func field_marker(path: String) -> Label:
	var label: Label = _field_labels.get(path, null)
	if label == null:
		return null
	var box := label.get_parent()
	if box == null or not (box is HBoxContainer) or box.get_child_count() < 2 \
			or not (box.get_child(1) is Label):
		return null
	return box.get_child(1)


## Validate before opening the file. Invalid drafts never reach CanonJSON, so refusal
## cannot truncate or otherwise disturb the last good bytes.
func save_record(path: String) -> Array:
	var errors := _validate_draft()
	if not errors.is_empty():
		return errors
	var write_error := CanonJSON.write_file(path, _draft)
	if write_error != "":
		return [write_error]
	_saved = _draft.duplicate(true)
	_set_dirty(false)
	return []


func revert_record() -> void:
	_draft = _saved.duplicate(true)
	_set_dirty(false)
	_rebuild()


func _rebuild() -> void:
	_field_controls.clear()
	_array_add_controls.clear()
	_array_remove_controls.clear()
	_optional_add_controls.clear()
	_optional_remove_controls.clear()
	_error_labels.clear()
	_field_labels.clear()
	_section_of_field.clear()
	_section_titles.clear()
	_invalid_controls.clear()
	for child in get_children():
		child.queue_free()
	# Keep an explicit form-level target for schema/context failures that cannot be
	# attached to a particular generated field.
	_add_error_label(self, "")
	var sections := StudioFormLayout.sections_for(_content_type, _schema.get("properties", {}))
	if sections.is_empty():
		_build_object(self, _schema, _draft, "")
	else:
		_build_root_sections(sections)
	_validate_draft()


## Root fields render as titled cards (gh #61). Only the grouping is curated; each
## field still builds from its schema inside its card.
func _build_root_sections(sections: Array) -> void:
	var properties: Dictionary = _schema.get("properties", {})
	for entry in sections:
		var title := str(entry[0])
		var fields: Array = entry[1]
		_section_titles.append(title)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", StudioTheme.card())
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(card)
		var body := VBoxContainer.new()
		card.add_child(body)
		var header := Label.new()
		header.text = title.to_upper()
		header.add_theme_font_size_override("font_size", StudioTheme.FONT_SECTION)
		header.add_theme_color_override("font_color", StudioTheme.MUTED)
		body.add_child(header)
		var subset := {}
		for field in fields:
			subset[field] = properties[field]
		_build_object(body, {"properties": subset, "required": _schema.get("required", [])},
			_draft, "")
		for field in fields:
			_section_of_field["/" + str(field)] = title


func _build_object(parent: Control, schema: Dictionary, value: Dictionary, path: String) -> void:
	var properties: Dictionary = schema.get("properties", {})
	var required: Array = schema.get("required", [])
	for field in properties:
		var field_schema: Dictionary = properties[field]
		var field_path := path + "/" + str(field)
		var is_required := required.has(field)
		var comment := str(field_schema.get("$comment", ""))
		if not value.has(field):
			if is_required:
				# A malformed record must remain repairable in Studio. Render the
				# schema-shaped control without silently inserting data into the draft;
				# its first edit creates the missing value.
				_build_field(parent, str(field), field_schema,
					_default_value(field_schema), field_path, is_required)
			else:
				_build_missing_optional(parent, str(field), field_schema, field_path)
			continue
		_build_field(parent, str(field), field_schema, value[field], field_path, is_required)
		if not is_required:
			var remove := Button.new()
			remove.text = "Remove %s" % field
			remove.pressed.connect(func() -> void: _remove_optional(field_path))
			parent.add_child(remove)
			_optional_remove_controls[field_path] = remove
		if comment != "" and _field_labels.has(field_path):
			(_field_labels[field_path] as Label).tooltip_text = comment


func _build_missing_optional(parent: Control, field: String, schema: Dictionary,
		path: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = field + " (optional)"
	label.custom_minimum_size.x = 160
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", StudioTheme.MUTED)
	row.add_child(label)
	var add := Button.new()
	add.text = "Add"
	add.pressed.connect(func() -> void: _add_optional(path, schema))
	row.add_child(add)
	_optional_add_controls[path] = add


func _build_field(parent: Control, field: String, schema: Dictionary, value, path: String,
		required := false) -> void:
	if _widget_registry != null:
		var custom: Control = _widget_registry.build(_content_type, path, schema, value,
			func(next) -> void: _set_draft_value(path, next))
		if custom != null:
			_mount_input(parent, field, custom, path, required)
			return
	var kind := str(schema.get("type", ""))
	if kind == "object":
		if _is_freeform_object(schema):
			var json_input := TextEdit.new()
			json_input.custom_minimum_size.y = 96
			json_input.text = CanonJSON.serialize(value)
			json_input.text_changed.connect(func() -> void:
				var parsed = JSON.parse_string(json_input.text)
				_set_draft_value(path, parsed if parsed is Dictionary else json_input.text))
			_mount_input(parent, field, json_input, path, required)
			return
		var section := VBoxContainer.new()
		parent.add_child(section)
		var heading := Label.new()
		heading.text = field
		heading.add_theme_color_override("font_color",
			StudioTheme.TEXT if required else StudioTheme.MUTED)
		section.add_child(heading)
		_field_labels[path] = heading
		_add_error_label(section, path)
		if value is Dictionary:
			_build_object(section, schema, value, path)
		return
	if kind == "array":
		_build_array(parent, field, schema, value if value is Array else [], path)
		return
	var input := _make_input(schema, value, path)
	if input == null:
		return
	_mount_input(parent, field, input, path, required)


func _is_freeform_object(schema: Dictionary) -> bool:
	return (schema.get("properties", {}) as Dictionary).is_empty() \
		and schema.get("additionalProperties", true) != false


func _mount_input(parent: Control, field: String, input: Control, path: String,
		required := false) -> void:
	var block := VBoxContainer.new()
	parent.add_child(block)
	var row := HBoxContainer.new()
	block.add_child(row)
	var label_box := HBoxContainer.new()
	label_box.custom_minimum_size.x = 160
	row.add_child(label_box)
	var label := Label.new()
	label.text = str(field)
	label.add_theme_color_override("font_color",
		StudioTheme.TEXT if required else StudioTheme.MUTED)
	label_box.add_child(label)
	# Required marker: text explains, the mint tick locates (selection-glow rule from
	# the visual-direction doc — a colour cue always pairs with a shape/text cue).
	var marker := Label.new()
	marker.text = "*"
	marker.visible = required
	marker.add_theme_color_override("font_color", StudioTheme.MINT)
	label_box.add_child(marker)
	_field_labels[path] = label
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	_field_controls[path] = input
	_add_error_label(block, path)


func _build_array(parent: Control, field: String, schema: Dictionary, value: Array,
		path: String) -> void:
	var section := VBoxContainer.new()
	parent.add_child(section)
	var header := HBoxContainer.new()
	section.add_child(header)
	var label := Label.new()
	label.text = field
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var add := Button.new()
	add.text = "Add"
	add.disabled = schema.has("maxItems") and value.size() >= int(schema["maxItems"])
	add.pressed.connect(func() -> void: _append_array(path, schema.get("items", {})))
	header.add_child(add)
	_array_add_controls[path] = add
	_add_error_label(section, path)
	var item_schema: Dictionary = schema.get("items", {})
	for i in value.size():
		var item_path := "%s/%d" % [path, i]
		var item_row := HBoxContainer.new()
		section.add_child(item_row)
		var item_content := VBoxContainer.new()
		item_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_row.add_child(item_content)
		_build_field(item_content, "[%d]" % i, item_schema, value[i], item_path)
		var remove := Button.new()
		remove.text = "Remove"
		var item_index := i
		remove.pressed.connect(func() -> void: _remove_array_item(path, item_index))
		item_row.add_child(remove)
		_array_remove_controls[item_path] = remove


func _make_input(schema: Dictionary, value, path: String) -> Control:
	if schema.has("x-ref"):
		var picker := OptionButton.new()
		var prefix := str(schema["x-ref"])
		var ids := (_id_registry.get(prefix, {}) as Dictionary).keys()
		ids.sort()
		var found := false
		for id in ids:
			picker.add_item(str(id))
			picker.set_item_metadata(picker.item_count - 1, str(id))
			if str(id) == str(value):
				found = true
				picker.select(picker.item_count - 1)
		if not found:
			picker.add_item("[missing] " + str(value))
			picker.set_item_metadata(picker.item_count - 1, str(value))
			picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(index: int) -> void:
			_set_draft_value(path, picker.get_item_metadata(index)))
		return picker
	if schema.has("enum"):
		var picker := OptionButton.new()
		var allowed: Array = schema["enum"]
		for option in allowed:
			picker.add_item(str(option))
			if option == value:
				picker.select(picker.item_count - 1)
		picker.item_selected.connect(func(index: int) -> void:
			_set_draft_value(path, allowed[index]))
		return picker
	match str(schema.get("type", "")):
		"string":
			var input := LineEdit.new()
			input.text = str(value)
			input.text_changed.connect(func(text: String) -> void: _set_draft_value(path, text))
			return input
		"integer", "number":
			var number := SpinBox.new()
			number.min_value = float(schema.get("minimum", -1.0e12))
			number.max_value = float(schema.get("maximum", 1.0e12))
			number.allow_lesser = true
			number.allow_greater = true
			number.step = 1.0 if str(schema.get("type", "")) == "integer" else 0.01
			number.value = float(value)
			number.value_changed.connect(func(next: float) -> void:
				_set_draft_value(path, int(next) if str(schema.get("type", "")) == "integer" else next))
			return number
		"boolean":
			var check := CheckBox.new()
			check.button_pressed = bool(value)
			check.toggled.connect(func(pressed: bool) -> void: _set_draft_value(path, pressed))
			return check
	return null


func _append_array(path: String, item_schema: Dictionary) -> void:
	var value = _draft_value(path)
	if not (value is Array):
		_set_draft_value(path, [])
		value = _draft_value(path)
	(value as Array).append(_default_value(item_schema))
	_set_dirty(CanonJSON.serialize(_draft) != CanonJSON.serialize(_saved))
	_rebuild()


func _remove_array_item(path: String, index: int) -> void:
	var value = _draft_value(path)
	if not (value is Array) or index < 0 or index >= (value as Array).size():
		return
	(value as Array).remove_at(index)
	_set_dirty(CanonJSON.serialize(_draft) != CanonJSON.serialize(_saved))
	_rebuild()


func _add_optional(path: String, schema: Dictionary) -> void:
	_set_draft_value(path, _default_value(schema))
	_rebuild()


func _remove_optional(path: String) -> void:
	var segments := path.split("/", false)
	if segments.is_empty():
		return
	var node = _draft
	for i in segments.size() - 1:
		var segment := str(segments[i])
		node = node[int(segment)] if node is Array else node[segment]
	if node is Dictionary:
		(node as Dictionary).erase(str(segments[-1]))
	_set_dirty(CanonJSON.serialize(_draft) != CanonJSON.serialize(_saved))
	_rebuild()


func _draft_value(path: String):
	var node = _draft
	for segment in path.split("/", false):
		if node is Array:
			var index := int(segment)
			if index < 0 or index >= (node as Array).size():
				return null
			node = node[index]
		elif node is Dictionary:
			if not (node as Dictionary).has(str(segment)):
				return null
			node = node[str(segment)]
		else:
			return null
	return node


func _default_value(schema: Dictionary):
	if schema.has("default"):
		var default_value = schema["default"]
		return default_value.duplicate(true) if default_value is Array or default_value is Dictionary else default_value
	if schema.has("x-ref"):
		var ids := (_id_registry.get(str(schema["x-ref"]), {}) as Dictionary).keys()
		ids.sort()
		return str(ids[0]) if not ids.is_empty() else str(schema["x-ref"]) + ":"
	if schema.has("enum") and not (schema["enum"] as Array).is_empty():
		return schema["enum"][0]
	match str(schema.get("type", "")):
		"object":
			var object := {}
			var properties: Dictionary = schema.get("properties", {})
			for field in schema.get("required", []):
				if properties.has(field):
					object[field] = _default_value(properties[field])
			return object
		"array":
			var array := []
			for _i in int(schema.get("minItems", 0)):
				array.append(_default_value(schema.get("items", {})))
			return array
		"string":
			return ""
		"integer":
			return int(schema.get("minimum", 0))
		"number":
			return float(schema.get("minimum", 0.0))
		"boolean":
			return false
	return null


func _add_error_label(parent: Control, path: String) -> void:
	var error := Label.new()
	error.modulate = StudioTheme.DANGER
	error.visible = false
	parent.add_child(error)
	_error_labels[path] = error


func _set_draft_value(path: String, value) -> void:
	var segments := path.split("/", false)
	if segments.is_empty():
		return
	var node = _draft
	for i in segments.size() - 1:
		var segment := str(segments[i])
		var make_array := str(segments[i + 1]).is_valid_int()
		if node is Array:
			var index := int(segment)
			while (node as Array).size() <= index:
				(node as Array).append(null)
			var child = node[index]
			if not (child is Array or child is Dictionary):
				child = [] if make_array else {}
				node[index] = child
			node = child
		elif node is Dictionary:
			if not (node as Dictionary).has(segment) \
					or not (node[segment] is Array or node[segment] is Dictionary):
				node[segment] = [] if make_array else {}
			node = node[segment]
		else:
			return
	var leaf := str(segments[-1])
	if node is Array:
		var leaf_index := int(leaf)
		while (node as Array).size() <= leaf_index:
			(node as Array).append(null)
		node[leaf_index] = value
	else:
		node[leaf] = value
	_set_dirty(CanonJSON.serialize(_draft) != CanonJSON.serialize(_saved))
	_validate_draft()


func _set_dirty(value: bool) -> void:
	if _dirty == value:
		return
	_dirty = value
	dirty_changed.emit(_dirty)


func _validate_draft() -> Array:
	_current_errors = ProjectValidator.validate_editor_record(_basename, _draft, _context)
	for label in _error_labels.values():
		(label as Label).text = ""
		(label as Label).visible = false
	for control in _invalid_controls:
		_clear_invalid(control)
	_invalid_controls.clear()
	for error in _current_errors:
		var message := str(error)
		var split_at := message.find(" — ")
		var path := message.substr(0, split_at) if split_at >= 0 else ""
		var target := path
		# CoreSchema correctly reports a missing property against its containing
		# object. Route that diagnostic to the repair control generated above.
		var missing_marker := "missing required field '"
		var missing_at := message.find(missing_marker)
		if missing_at >= 0:
			var field_start := missing_at + missing_marker.length()
			var field_end := message.find("'", field_start)
			if field_end > field_start:
				target = path + "/" + message.substr(field_start, field_end - field_start)
		while target != "" and not _error_labels.has(target):
			target = target.substr(0, target.rfind("/"))
		if _error_labels.has(target):
			var label: Label = _error_labels[target]
			label.text += ("\n" if label.text != "" else "") + (
				message.substr(split_at + 3) if split_at >= 0 else message)
			label.visible = true
			if _field_controls.has(target):
				_mark_invalid(_field_controls[target])
	return _current_errors.duplicate()


## The error label explains; the danger border on the offending input locates (gh #61).
func _mark_invalid(control: Control) -> void:
	var target: Control = control
	if control is SpinBox:
		target = (control as SpinBox).get_line_edit()
	if target.has_method("add_theme_stylebox_override"):
		target.add_theme_stylebox_override("normal", StudioTheme.error_box())
		_invalid_controls.append(target)


func _clear_invalid(control: Control) -> void:
	control.remove_theme_stylebox_override("normal")
