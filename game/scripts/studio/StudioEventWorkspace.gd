extends VBoxContainer
class_name StudioEventWorkspace
## Schema-derived event command-list editor (gh #56). EventDocument owns every edit;
## this view supplies nested branch controls, exact undo/redo, and inline save refusal.

signal document_saved(path: String)
signal playtest_requested(map_label: String)

var document: EventDocument
var _title: Label
var _status: Label
var _content: VBoxContainer
var _save: Button
var _revert: Button
var _undo_button: Button
var _redo_button: Button
var _play: Button
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _palette_controls := {}


func bind_document(value: EventDocument) -> String:
	document = value
	_undo.clear()
	_redo.clear()
	_build_shell()
	_rebuild_content()
	_update_state()
	return ""


func is_dirty() -> bool:
	return document != null and document.is_dirty()


func save() -> String:
	var error := document.save()
	_update_state()
	if error == "":
		_status.text = "Saved · " + document.path
		document_saved.emit(document.path)
	else:
		_status.text = "REFUSED — " + error
	return error


func revert_document() -> String:
	var opened := EventDocument.open(document.project_dir, document.basename)
	if not bool(opened.get("ok", false)):
		var error := str(opened.get("error", "cannot reopen event"))
		_status.text = "REFUSED — " + error
		return error
	return bind_document(opened["document"])


func undo() -> void:
	if _undo.is_empty(): return
	_redo.append(document.edit_state())
	document.restore_edit_state(_undo.pop_back())
	_rebuild_content()
	_update_state()


func redo() -> void:
	if _redo.is_empty(): return
	_undo.append(document.edit_state())
	document.restore_edit_state(_redo.pop_back())
	_rebuild_content()
	_update_state()


func add_command(block_path: Array, kind: String) -> String:
	var before := document.edit_state()
	var error := document.add_command(block_path, kind)
	if error == "":
		_commit(before, true)
	return error


func command_palette(block_path: Array) -> OptionButton:
	return _palette_controls.get(JSON.stringify(block_path))


func save_control() -> Button:
	return _save


func undo_control() -> Button:
	return _undo_button


func redo_control() -> Button:
	return _redo_button


func status_text() -> String:
	return _status.text


func _build_shell() -> void:
	for child in get_children(): child.queue_free()
	var bar_panel := PanelContainer.new()
	add_child(bar_panel)
	var bar := HBoxContainer.new()
	bar_panel.add_child(bar)
	_undo_button = _button("Undo")
	_undo_button.pressed.connect(undo)
	bar.add_child(_undo_button)
	_redo_button = _button("Redo")
	_redo_button.pressed.connect(redo)
	bar.add_child(_redo_button)
	_save = _button("Save")
	_save.pressed.connect(save)
	bar.add_child(_save)
	_revert = _button("Revert")
	_revert.pressed.connect(revert_document)
	bar.add_child(_revert)
	_play = _button("Play-test event")
	_play.pressed.connect(func() -> void:
		if is_dirty():
			_status.text = "Save or Revert before play-testing this event"
		else:
			playtest_requested.emit(str(document.data.get("trigger", {}).get("map", "")).trim_prefix("map:")))
	bar.add_child(_play)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	add_child(_title)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
	_status = Label.new()
	_status.add_theme_color_override("font_color", StudioTheme.MUTED)
	add_child(_status)


func _rebuild_content() -> void:
	_palette_controls.clear()
	for child in _content.get_children(): child.queue_free()
	var trigger_panel := PanelContainer.new()
	_content.add_child(trigger_panel)
	var trigger_box := VBoxContainer.new()
	trigger_panel.add_child(trigger_box)
	trigger_box.add_child(_section("TRIGGER"))
	var trigger_editor := preload("res://scripts/studio/StudioSchemaValueEditor.gd").new()
	trigger_editor.bind_value(document.data.get("trigger", {}), document.trigger_schema(),
		document.schema, document.context.get("ids", {}))
	trigger_editor.value_changed.connect(func(value) -> void:
		if not (value is Dictionary): return
		var before := document.edit_state()
		document.set_trigger(value)
		_commit(before, false))
	trigger_box.add_child(trigger_editor)
	_content.add_child(HSeparator.new())
	_content.add_child(_section("COMMAND LIST"))
	_build_block(_content, [])


func _build_block(parent: VBoxContainer, block_path: Array) -> void:
	var block = document.block_at(block_path)
	if not (block is Array): return
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 7)
	parent.add_child(list)
	for index in block.size():
		var command: Dictionary = block[index]
		_build_command(list, block_path + [index], command)
	var add_row := HBoxContainer.new()
	parent.add_child(add_row)
	var palette := OptionButton.new()
	for kind in document.command_kinds(): palette.add_item(str(kind))
	palette.custom_minimum_size.x = 220
	add_row.add_child(palette)
	_palette_controls[JSON.stringify(block_path)] = palette
	var add := Button.new()
	add.text = "+ Add command"
	add.pressed.connect(func() -> void:
		if palette.item_count > 0: add_command(block_path, palette.get_item_text(palette.selected)))
	add_row.add_child(add)


func _build_command(parent: VBoxContainer, command_path: Array, command: Dictionary) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var name_label := Label.new()
	name_label.text = "%d  %s" % [int(command_path[-1]) + 1,
		str(command.get("cmd", "invalid command")).replace("_", " ").capitalize()]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	for action in [["↑", -1], ["↓", 1]]:
		var move := Button.new()
		move.text = action[0]
		move.tooltip_text = "Move command"
		move.pressed.connect(func() -> void:
			var before := document.edit_state()
			if document.move_command(command_path, action[1]): _commit(before, true))
		header.add_child(move)
	var duplicate := Button.new()
	duplicate.text = "Duplicate"
	duplicate.pressed.connect(func() -> void:
		var before := document.edit_state()
		if document.duplicate_command(command_path): _commit(before, true))
	header.add_child(duplicate)
	var remove := Button.new()
	remove.text = "Delete"
	remove.pressed.connect(func() -> void:
		var before := document.edit_state()
		if document.remove_command(command_path): _commit(before, true))
	header.add_child(remove)
	var kind := str(command.get("cmd", ""))
	var command_schema := document.command_schema(kind)
	if command_schema.is_empty():
		var invalid := Label.new()
		invalid.text = "Unknown command '%s'" % kind
		invalid.add_theme_color_override("font_color", Color("ff657a"))
		box.add_child(invalid)
		return
	var fields := preload("res://scripts/studio/StudioSchemaValueEditor.gd").new()
	fields.bind_value(command, command_schema, document.schema,
		document.context.get("ids", {}), ["cmd", "then", "else"])
	fields.value_changed.connect(func(value) -> void:
		if not (value is Dictionary): return
		# Branch fields are owned by the nested command-list controls and must survive
		# a scalar-field edit made by the schema value editor.
		for branch in ["then", "else"]:
			if command.has(branch): value[branch] = command[branch].duplicate(true)
		var before := document.edit_state()
		if document.replace_command(command_path, value):
			command = value
			_commit(before, false))
	box.add_child(fields)
	var properties: Dictionary = command_schema.get("properties", {})
	for branch in ["then", "else"]:
		if not properties.has(branch): continue
		var required: bool = branch in command_schema.get("required", [])
		if not command.has(branch) and not required:
			var add_branch := Button.new()
			add_branch.text = "+ Add %s branch" % branch
			add_branch.alignment = HORIZONTAL_ALIGNMENT_LEFT
			add_branch.pressed.connect(func() -> void:
				var before := document.edit_state()
				var next := command.duplicate(true)
				next[branch] = []
				if document.replace_command(command_path, next): _commit(before, true))
			box.add_child(add_branch)
			continue
		if command.has(branch):
			var branch_header := HBoxContainer.new()
			box.add_child(branch_header)
			var branch_label := _section(branch.to_upper() + " BRANCH")
			branch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			branch_header.add_child(branch_label)
			if not required:
				var remove_branch := Button.new()
				remove_branch.text = "Remove branch"
				remove_branch.pressed.connect(func() -> void:
					var before := document.edit_state()
					var next := command.duplicate(true)
					next.erase(branch)
					if document.replace_command(command_path, next): _commit(before, true))
				branch_header.add_child(remove_branch)
			_build_block(box, command_path + [branch])


func _commit(before: Dictionary, rebuild: bool) -> void:
	if before == document.edit_state(): return
	_undo.append(before)
	_redo.clear()
	if rebuild: _rebuild_content()
	_update_state()


func _update_state() -> void:
	var dirty := is_dirty()
	_title.text = "events / %s%s" % [document.basename, " *" if dirty else ""]
	_undo_button.disabled = _undo.is_empty()
	_redo_button.disabled = _redo.is_empty()
	_save.disabled = not dirty
	_revert.disabled = not dirty
	_play.disabled = dirty
	var errors := document.validate()
	_status.text = ("Valid · %s" % ("DIRTY" if dirty else "SAVED")) if errors.is_empty() \
		else "INVALID — " + "; ".join(PackedStringArray(errors.slice(0, 3)))


static func _button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 34
	return button


static func _section(label: String) -> Label:
	var out := Label.new()
	out.text = label
	out.add_theme_color_override("font_color", StudioTheme.MUTED)
	return out
