extends VBoxContainer
class_name StudioTypeSelector
## Compact species type editor: one or two validator-owned type IDs, with the schema's
## min/max bounds applied to add/remove actions.

const Support := preload("res://scripts/studio/widgets/WidgetSupport.gd")

var _schema: Dictionary = {}
var _type_ids: Array = []
var _value: Array = []
var _changed := Callable()
var _pickers := []
var _remove_buttons := []
var _add_button: Button


func setup(schema: Dictionary, value, type_ids: Array, changed: Callable) -> void:
	_schema = schema
	_value = value.duplicate(true) if value is Array else []
	_type_ids = type_ids.duplicate()
	_changed = changed
	_build()


func slot_picker(index: int) -> OptionButton:
	return _pickers[index] if index >= 0 and index < _pickers.size() else null


func add_control() -> Button:
	return _add_button


func remove_control(index: int) -> Button:
	return _remove_buttons[index] if index >= 0 and index < _remove_buttons.size() else null


func current_value() -> Array:
	return _value.duplicate(true)


func _build() -> void:
	_pickers.clear()
	_remove_buttons.clear()
	for child in get_children():
		child.queue_free()
	for i in _value.size():
		var index := i
		var row := HBoxContainer.new()
		add_child(row)
		var choose := OptionButton.new()
		choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Support.fill_id_picker(choose, _type_ids, str(_value[index]))
		choose.item_selected.connect(func(selected: int) -> void:
			_value[index] = str(choose.get_item_metadata(selected))
			_emit_changed())
		row.add_child(choose)
		_pickers.append(choose)
		var remove := Button.new()
		remove.text = "Remove"
		remove.disabled = _value.size() <= int(_schema.get("minItems", 0))
		remove.pressed.connect(func() -> void:
			_value.remove_at(index)
			_emit_changed()
			_build())
		row.add_child(remove)
		_remove_buttons.append(remove)
	_add_button = Button.new()
	_add_button.text = "Add type"
	_add_button.disabled = _schema.has("maxItems") \
		and _value.size() >= int(_schema["maxItems"])
	_add_button.pressed.connect(func() -> void:
		_value.append(str(_type_ids[0]) if not _type_ids.is_empty() else "type:")
		_emit_changed()
		_build())
	add_child(_add_button)


func _emit_changed() -> void:
	if _changed.is_valid():
		_changed.call(_value.duplicate(true))
