extends VBoxContainer
class_name StudioSchemaValueEditor
## Recursive JSON-Schema value control used by the event trigger and command cards.
## It deliberately consumes the Core schema subset instead of mirroring event fields.

signal value_changed(value)

var _value
var _schema: Dictionary = {}
var _root: Dictionary = {}
var _ids: Dictionary = {}
var _omit: Array = []


func bind_value(value, value_schema: Dictionary, root_schema: Dictionary,
		ids: Dictionary = {}, omit_keys: Array = []) -> void:
	_value = value.duplicate(true) if value is Dictionary or value is Array else value
	_schema = value_schema
	_root = root_schema
	_ids = ids
	_omit = omit_keys.duplicate()
	_rebuild()


func value():
	return _value.duplicate(true) if _value is Dictionary or _value is Array else _value


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_build_for(self, _value, _schema, func(next) -> void:
		_value = next
		value_changed.emit(value()))


func _build_for(parent: Control, current, raw_schema: Dictionary, changed: Callable) -> void:
	var spec := _resolve(raw_schema)
	if spec.has("anyOf"):
		_build_any_of(parent, current, spec, changed)
		return
	if spec.has("enum") or spec.has("const") or spec.has("x-ref"):
		_build_choice(parent, current, spec, changed)
		return
	match str(spec.get("type", "")):
		"object": _build_object(parent, current if current is Dictionary else {}, spec, changed)
		"array": _build_array(parent, current if current is Array else [], spec, changed)
		"boolean":
			var check := CheckButton.new()
			check.text = "Enabled"
			check.button_pressed = bool(current)
			check.toggled.connect(func(on: bool) -> void: changed.call(on))
			parent.add_child(check)
		"integer", "number":
			var spin := SpinBox.new()
			spin.min_value = float(spec.get("minimum", -1000000))
			spin.max_value = float(spec.get("maximum", 1000000))
			spin.step = 1 if str(spec.get("type", "")) == "integer" else 0.01
			spin.value = float(current if current is float or current is int else 0)
			spin.value_changed.connect(func(next: float) -> void:
				changed.call(int(next) if str(spec.get("type", "")) == "integer" else next))
			parent.add_child(spin)
		_:
			var line := LineEdit.new()
			line.text = str(current)
			line.placeholder_text = str(spec.get("description", ""))
			line.text_changed.connect(func(next: String) -> void: changed.call(next))
			parent.add_child(line)


func _build_object(parent: Control, current: Dictionary, spec: Dictionary,
		changed: Callable) -> void:
	var properties: Dictionary = spec.get("properties", {})
	var required: Array = spec.get("required", [])
	var keys: Array = []
	for key in required:
		if properties.has(key) and key not in _omit:
			keys.append(key)
	var optional := properties.keys()
	optional.sort()
	for key in optional:
		if key not in required and key not in _omit:
			keys.append(key)
	for key in keys:
		var present := current.has(key)
		var row := VBoxContainer.new()
		parent.add_child(row)
		var heading := HBoxContainer.new()
		row.add_child(heading)
		var label := Label.new()
		label.text = str(key).capitalize()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", StudioTheme.MUTED)
		heading.add_child(label)
		if key not in required:
			var enabled := CheckButton.new()
			enabled.text = "Use"
			enabled.button_pressed = present
			enabled.toggled.connect(func(on: bool) -> void:
				var next := current.duplicate(true)
				if on:
					next[key] = _default_for(properties[key])
				else:
					next.erase(key)
				changed.call(next)
				current = next
				_value = next if parent == self else _value
				_rebuild())
			heading.add_child(enabled)
		if present:
			_build_for(row, current[key], properties[key], func(next) -> void:
				var object := current.duplicate(true)
				object[key] = next
				current = object
				changed.call(object))


func _build_array(parent: Control, current: Array, spec: Dictionary,
		changed: Callable) -> void:
	var prefix: Array = spec.get("prefixItems", [])
	for index in current.size():
		var row := HBoxContainer.new()
		parent.add_child(row)
		var ordinal := Label.new()
		ordinal.text = "[%d]" % index
		ordinal.custom_minimum_size.x = 38
		row.add_child(ordinal)
		var value_host := VBoxContainer.new()
		value_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value_host)
		var item_schema: Dictionary = prefix[index] if index < prefix.size() else spec.get("items", {})
		_build_for(value_host, current[index], item_schema, func(next) -> void:
			var array := current.duplicate(true)
			array[index] = next
			current = array
			changed.call(array))
		if current.size() > int(spec.get("minItems", 0)):
			var remove := Button.new()
			remove.text = "×"
			remove.tooltip_text = "Remove entry"
			remove.pressed.connect(func() -> void:
				var array := current.duplicate(true)
				array.remove_at(index)
				changed.call(array)
				current = array
				_value = array if parent == self else _value
				_rebuild())
			row.add_child(remove)
	var maximum := int(spec.get("maxItems", 1000000))
	if current.size() < maximum and (spec.has("items") or current.size() < prefix.size()):
		var add := Button.new()
		add.text = "+ Add entry"
		add.alignment = HORIZONTAL_ALIGNMENT_LEFT
		add.pressed.connect(func() -> void:
			var array := current.duplicate(true)
			var next_schema: Dictionary = prefix[array.size()] if array.size() < prefix.size() \
				else spec.get("items", {})
			array.append(_default_for(next_schema))
			changed.call(array)
			current = array
			_value = array if parent == self else _value
			_rebuild())
		parent.add_child(add)


func _build_choice(parent: Control, current, spec: Dictionary, changed: Callable) -> void:
	var values: Array = []
	if spec.has("const"):
		values = [spec["const"]]
	elif spec.has("enum"):
		values = spec["enum"]
	else:
		var registry: Dictionary = _ids.get(str(spec.get("x-ref", "")), {})
		values = registry.keys()
		values.sort()
	var option := OptionButton.new()
	if not values.has(current):
		option.add_item("Choose…" if str(current) == "" else "Invalid · " + str(current))
		option.set_item_metadata(0, current)
		option.select(0)
	for candidate in values:
		option.add_item(str(candidate))
		option.set_item_metadata(option.item_count - 1, candidate)
		if candidate == current:
			option.select(option.item_count - 1)
	if option.item_count == 0:
		var line := LineEdit.new()
		line.text = str(current)
		line.text_changed.connect(func(next: String) -> void: changed.call(next))
		parent.add_child(line)
		return
	option.disabled = spec.has("const")
	option.item_selected.connect(func(index: int) -> void:
		changed.call(option.get_item_metadata(index)))
	parent.add_child(option)


func _build_any_of(parent: Control, current, spec: Dictionary, changed: Callable) -> void:
	var branches: Array = spec.get("anyOf", [])
	var selected := 0
	for index in branches.size():
		var errors: Array = []
		CoreSchema.validate(current, branches[index], _root, "", errors, [])
		if errors.is_empty():
			selected = index
			break
	var option := OptionButton.new()
	for index in branches.size():
		var branch := _resolve(branches[index])
		option.add_item(str(branch.get("title", branch.get("type", "Choice %d" % (index + 1)))).capitalize())
	option.select(selected)
	option.item_selected.connect(func(index: int) -> void:
		changed.call(_default_for(branches[index]))
		_rebuild())
	parent.add_child(option)
	_build_for(parent, current, branches[selected], changed)


func _resolve(raw: Dictionary) -> Dictionary:
	var current := raw
	var seen := {}
	while current.has("$ref"):
		var ref := str(current["$ref"])
		if seen.has(ref) or not ref.begins_with("#/$defs/"):
			return {}
		seen[ref] = true
		var name := ref.substr(8)
		var defs: Dictionary = _root.get("$defs", {})
		if not defs.has(name):
			return {}
		current = defs[name]
	return current


func _default_for(raw: Dictionary):
	var spec := _resolve(raw)
	if spec.has("default"): return spec["default"]
	if spec.has("const"): return spec["const"]
	if spec.has("enum"):
		return spec["enum"][0] if not (spec["enum"] as Array).is_empty() else ""
	if spec.has("anyOf"):
		return _default_for(spec["anyOf"][0]) if not (spec["anyOf"] as Array).is_empty() else null
	match str(spec.get("type", "")):
		"object":
			var out := {}
			var props: Dictionary = spec.get("properties", {})
			for key in spec.get("required", []):
				out[key] = _default_for(props.get(key, {}))
			return out
		"array":
			var out: Array = []
			for item in spec.get("prefixItems", []): out.append(_default_for(item))
			while out.size() < int(spec.get("minItems", 0)):
				out.append(_default_for(spec.get("items", {})))
			return out
		"integer", "number": return int(spec.get("minimum", 0))
		"boolean": return false
		_: return ""
