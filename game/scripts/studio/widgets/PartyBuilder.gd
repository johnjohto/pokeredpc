extends VBoxContainer
class_name StudioPartyBuilder
## Trainer party builder. A trainer record may carry several ordered party variants;
## each variant owns an ordered, non-empty list of species/level members.

const Support := preload("res://scripts/studio/widgets/WidgetSupport.gd")

var _schema: Dictionary = {}
var _species_ids: Array = []
var _value: Array = []
var _changed := Callable()
var _species_controls := {}
var _level_controls := {}
var _add_member_controls := {}
var _remove_member_controls := {}
var _remove_party_controls := {}
var _add_party_button: Button


func setup(schema: Dictionary, value, species_ids: Array, changed: Callable) -> void:
	_schema = schema
	_value = value.duplicate(true) if value is Array else []
	_species_ids = species_ids.duplicate()
	_changed = changed
	_build()


func party_count() -> int:
	return _value.size()


func member_count(party_index: int) -> int:
	if party_index < 0 or party_index >= _value.size() or not (_value[party_index] is Array):
		return 0
	return (_value[party_index] as Array).size()


func species_control(party_index: int, member_index: int) -> OptionButton:
	return _species_controls.get(_key(party_index, member_index), null)


func level_control(party_index: int, member_index: int) -> SpinBox:
	return _level_controls.get(_key(party_index, member_index), null)


func add_party_control() -> Button:
	return _add_party_button


func add_member_control(party_index: int) -> Button:
	return _add_member_controls.get(party_index, null)


func remove_member_control(party_index: int, member_index: int) -> Button:
	return _remove_member_controls.get(_key(party_index, member_index), null)


func remove_party_control(party_index: int) -> Button:
	return _remove_party_controls.get(party_index, null)


func current_value() -> Array:
	return _value.duplicate(true)


func _build() -> void:
	_species_controls.clear()
	_level_controls.clear()
	_add_member_controls.clear()
	_remove_member_controls.clear()
	_remove_party_controls.clear()
	for child in get_children():
		child.queue_free()
	var party_schema: Dictionary = _schema.get("items", {})
	var member_schema: Dictionary = party_schema.get("items", {})
	var properties: Dictionary = member_schema.get("properties", {})
	var level_schema: Dictionary = properties.get("level", {})
	for p in _value.size():
		var party_index := p
		var party: Array = _value[party_index] if _value[party_index] is Array else []
		var section := VBoxContainer.new()
		add_child(section)
		var header := HBoxContainer.new()
		section.add_child(header)
		var title := Label.new()
		title.text = "Party %d" % (party_index + 1)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var party_up := Button.new()
		party_up.text = "↑"
		party_up.disabled = party_index == 0
		party_up.pressed.connect(func() -> void: _move_party(party_index, party_index - 1))
		header.add_child(party_up)
		var party_down := Button.new()
		party_down.text = "↓"
		party_down.disabled = party_index == _value.size() - 1
		party_down.pressed.connect(func() -> void: _move_party(party_index, party_index + 1))
		header.add_child(party_down)
		var remove_party := Button.new()
		remove_party.text = "Remove party"
		remove_party.disabled = _value.size() <= int(_schema.get("minItems", 0))
		remove_party.pressed.connect(func() -> void:
			_value.remove_at(party_index)
			_emit_and_rebuild())
		header.add_child(remove_party)
		_remove_party_controls[party_index] = remove_party
		var table := GridContainer.new()
		table.columns = 5
		section.add_child(table)
		for heading in ["Species", "Level", "", "", ""]:
			var label := Label.new()
			label.text = heading
			table.add_child(label)
		for m in party.size():
			var member_index := m
			var member: Dictionary = party[member_index] if party[member_index] is Dictionary else {}
			var species := OptionButton.new()
			species.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			Support.fill_id_picker(species, _species_ids,
				str(member.get("species", "species:")))
			species.item_selected.connect(func(selected: int) -> void:
				((_value[party_index] as Array)[member_index] as Dictionary)["species"] = \
					str(species.get_item_metadata(selected))
				_emit_changed())
			table.add_child(species)
			_species_controls[_key(party_index, member_index)] = species
			var level := SpinBox.new()
			level.min_value = float(level_schema.get("minimum", 1))
			level.max_value = float(level_schema.get("maximum", 100))
			level.step = 1
			level.value = float(member.get("level", level.min_value))
			level.value_changed.connect(func(next: float) -> void:
				((_value[party_index] as Array)[member_index] as Dictionary)["level"] = int(next)
				_emit_changed())
			table.add_child(level)
			_level_controls[_key(party_index, member_index)] = level
			var up := Button.new()
			up.text = "↑"
			up.disabled = member_index == 0
			up.pressed.connect(func() -> void:
				_move_member(party_index, member_index, member_index - 1))
			table.add_child(up)
			var down := Button.new()
			down.text = "↓"
			down.disabled = member_index == party.size() - 1
			down.pressed.connect(func() -> void:
				_move_member(party_index, member_index, member_index + 1))
			table.add_child(down)
			var remove := Button.new()
			remove.text = "Remove"
			remove.disabled = party.size() <= int(party_schema.get("minItems", 0))
			remove.pressed.connect(func() -> void:
				(_value[party_index] as Array).remove_at(member_index)
				_emit_and_rebuild())
			table.add_child(remove)
			_remove_member_controls[_key(party_index, member_index)] = remove
		var add_member := Button.new()
		add_member.text = "Add monster"
		add_member.disabled = party_schema.has("maxItems") \
			and party.size() >= int(party_schema["maxItems"])
		add_member.pressed.connect(func() -> void:
			(_value[party_index] as Array).append(_new_member(level_schema))
			_emit_and_rebuild())
		section.add_child(add_member)
		_add_member_controls[party_index] = add_member
	_add_party_button = Button.new()
	_add_party_button.text = "Add party"
	_add_party_button.disabled = _schema.has("maxItems") \
		and _value.size() >= int(_schema["maxItems"])
	_add_party_button.pressed.connect(func() -> void:
		_value.append([_new_member(level_schema)])
		_emit_and_rebuild())
	add_child(_add_party_button)


func _new_member(level_schema: Dictionary) -> Dictionary:
	return {
		"species": str(_species_ids[0]) if not _species_ids.is_empty() else "species:",
		"level": int(level_schema.get("minimum", 1))
	}


func _move_party(from: int, to: int) -> void:
	var party = _value.pop_at(from)
	_value.insert(to, party)
	_emit_and_rebuild()


func _move_member(party_index: int, from: int, to: int) -> void:
	var party: Array = _value[party_index]
	var member = party.pop_at(from)
	party.insert(to, member)
	_emit_and_rebuild()


func _emit_changed() -> void:
	if _changed.is_valid():
		_changed.call(_value.duplicate(true))


func _emit_and_rebuild() -> void:
	_emit_changed()
	_build()


static func _key(party_index: int, member_index: int) -> String:
	return "%d/%d" % [party_index, member_index]
