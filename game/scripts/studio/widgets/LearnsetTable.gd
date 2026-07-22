extends VBoxContainer
class_name StudioLearnsetTable
## Ordered species level-up learnset editor. Order remains creator-controlled because it
## is project data; rows can be edited, inserted, removed, and moved without a side model.

const Support := preload("res://scripts/studio/widgets/WidgetSupport.gd")

var _schema: Dictionary = {}
var _move_ids: Array = []
var _value: Array = []
var _changed := Callable()
var _level_controls := []
var _move_controls := []
var _remove_controls := []
var _up_controls := []
var _down_controls := []
var _add_button: Button


func setup(schema: Dictionary, value, move_ids: Array, changed: Callable) -> void:
	_schema = schema
	_value = value.duplicate(true) if value is Array else []
	_move_ids = move_ids.duplicate()
	_changed = changed
	_build()


func row_count() -> int:
	return _value.size()


func level_control(index: int) -> SpinBox:
	return _at(_level_controls, index)


func move_control(index: int) -> OptionButton:
	return _at(_move_controls, index)


func remove_control(index: int) -> Button:
	return _at(_remove_controls, index)


func move_up_control(index: int) -> Button:
	return _at(_up_controls, index)


func move_down_control(index: int) -> Button:
	return _at(_down_controls, index)


func add_control() -> Button:
	return _add_button


func current_value() -> Array:
	return _value.duplicate(true)


func _build() -> void:
	_level_controls.clear()
	_move_controls.clear()
	_remove_controls.clear()
	_up_controls.clear()
	_down_controls.clear()
	for child in get_children():
		child.queue_free()
	var table := GridContainer.new()
	table.columns = 5
	add_child(table)
	for heading in ["Level", "Move", "", "", ""]:
		var label := Label.new()
		label.text = heading
		table.add_child(label)
	var member_schema: Dictionary = _schema.get("items", {})
	var properties: Dictionary = member_schema.get("properties", {})
	var level_schema: Dictionary = properties.get("level", {})
	for i in _value.size():
		var index := i
		var row: Dictionary = _value[index] if _value[index] is Dictionary else {}
		var level := SpinBox.new()
		level.min_value = float(level_schema.get("minimum", 1))
		level.max_value = float(level_schema.get("maximum", 100))
		level.step = 1
		level.value = float(row.get("level", level.min_value))
		level.value_changed.connect(func(next: float) -> void:
			(_value[index] as Dictionary)["level"] = int(next)
			_emit_changed())
		table.add_child(level)
		_level_controls.append(level)
		var move := OptionButton.new()
		move.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Support.fill_id_picker(move, _move_ids, str(row.get("move", "move:")))
		move.item_selected.connect(func(selected: int) -> void:
			(_value[index] as Dictionary)["move"] = str(move.get_item_metadata(selected))
			_emit_changed())
		table.add_child(move)
		_move_controls.append(move)
		var up := Button.new()
		up.text = "↑"
		up.disabled = index == 0
		up.pressed.connect(func() -> void: _move_row(index, index - 1))
		table.add_child(up)
		_up_controls.append(up)
		var down := Button.new()
		down.text = "↓"
		down.disabled = index == _value.size() - 1
		down.pressed.connect(func() -> void: _move_row(index, index + 1))
		table.add_child(down)
		_down_controls.append(down)
		var remove := Button.new()
		remove.text = "Remove"
		remove.disabled = _value.size() <= int(_schema.get("minItems", 0))
		remove.pressed.connect(func() -> void:
			_value.remove_at(index)
			_emit_and_rebuild())
		table.add_child(remove)
		_remove_controls.append(remove)
	_add_button = Button.new()
	_add_button.text = "Add learned move"
	_add_button.disabled = _schema.has("maxItems") \
		and _value.size() >= int(_schema["maxItems"])
	_add_button.pressed.connect(func() -> void:
		_value.append({
			"level": int(level_schema.get("minimum", 1)),
			"move": str(_move_ids[0]) if not _move_ids.is_empty() else "move:"
		})
		_emit_and_rebuild())
	add_child(_add_button)


func _move_row(from: int, to: int) -> void:
	var row = _value.pop_at(from)
	_value.insert(to, row)
	_emit_and_rebuild()


func _emit_changed() -> void:
	if _changed.is_valid():
		_changed.call(_value.duplicate(true))


func _emit_and_rebuild() -> void:
	_emit_changed()
	_build()


func _at(controls: Array, index: int):
	return controls[index] if index >= 0 and index < controls.size() else null
