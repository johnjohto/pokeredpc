extends VBoxContainer
class_name StudioMapWorkspace
## Phase-5 native map authoring workspace. MapDocument owns edits/serialization; this class
## composes tools, palette, undo/redo, dirty state, save/revert, and play-test intent.

signal document_saved(path: String)
signal playtest_requested(map_label: String)
signal event_requested(kind: String, object_id: String, event_id: String)

var document: MapDocument
var world_document = null
var canvas: StudioMapCanvas
var palette
var _status: Label
var _save: Button
var _revert: Button
var _undo_button: Button
var _redo_button: Button
var _play: Button
var _tool := "brush"
var _selected_tile := 0
var _tool_buttons := {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _stroke_before: Dictionary = {}
var _map_labels: Array = []
var _object_list: OptionButton
var _object_id: LineEdit
var _object_x: SpinBox
var _object_y: SpinBox
var _object_event: LineEdit
var _object_detail_a: LineEdit
var _object_detail_b: LineEdit
var _object_detail_c: LineEdit
var _object_number_a: SpinBox
var _object_number_b: SpinBox
var _object_apply: Button
var _object_delete: Button
var _object_event_edit: Button
var _selected_object_kind := ""
var _selected_object_id := ""
var _connection_list: OptionButton
var _connection_direction: OptionButton
var _connection_map: OptionButton
var _connection_offset: SpinBox
var _connection_apply: Button
var _connection_delete: Button


func _ready() -> void:
	name = "MapWorkspace"
	custom_minimum_size = Vector2(590, 500)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func bind_document(value: MapDocument, world = null, map_labels: Array = []) -> String:
	document = value
	world_document = world
	_map_labels = map_labels.duplicate()
	_undo.clear()
	_redo.clear()
	_stroke_before = {}
	_selected_tile = clampi(_selected_tile, 0, int(document.tileset.get("tile_count", 1)) - 1)
	_build_ui()
	var error := canvas.bind_document(document)
	if error != "":
		_status.text = "REFUSED — " + error
		_save.disabled = true
		return error
	palette.bind_document(document, canvas.atlas)
	palette.select_tile(_selected_tile, false)
	select_tool("brush")
	_update_state()
	return ""


func canvas_control() -> StudioMapCanvas:
	return canvas


func palette_control():
	return palette


func select_tile(tile_id: int) -> void:
	_selected_tile = tile_id
	if palette != null and palette.selected_tile != tile_id:
		palette.select_tile(tile_id, false)
	_update_state()


func select_tool(tool: String) -> void:
	if not _tool_buttons.has(tool):
		return
	_tool = tool
	for key in _tool_buttons:
		(_tool_buttons[key] as Button).button_pressed = str(key) == tool
	canvas.set_input_mode("pan" if tool == "pan" else "paint")
	_update_state()


func begin_stroke() -> void:
	if _stroke_before.is_empty():
		_stroke_before = _capture_state()


func apply_cell(cell: Vector2i) -> bool:
	var changed := false
	match _tool:
		"brush": changed = document.set_tile(cell, _selected_tile)
		"block":
			var block_id := document.block_for_tile(_selected_tile)
			changed = document.paint_block(cell, block_id) if block_id >= 0 else false
		"erase": changed = document.set_tile(cell, document.border_tile)
		"fill": changed = document.fill_tile(cell, _selected_tile)
		"walkable": changed = document.set_walkable(cell, true)
		"solid": changed = document.set_walkable(cell, false)
		"warp", "npc", "sign", "trigger": changed = _place_object(_tool, cell)
	if changed:
		canvas.queue_redraw()
		_refresh_object_list()
		_update_state()
	return changed


func end_stroke() -> void:
	if _stroke_before.is_empty():
		return
	var after := _capture_state()
	if not _states_equal(_stroke_before, after):
		_undo.append(_stroke_before)
		_redo.clear()
	_stroke_before = {}
	_update_state()


func paint_once(cell: Vector2i) -> bool:
	begin_stroke()
	var changed := apply_cell(cell)
	end_stroke()
	return changed


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_capture_state())
	_restore_state(_undo.pop_back())
	canvas.queue_redraw()
	_refresh_object_list()
	_refresh_connections()
	_update_state()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_capture_state())
	_restore_state(_redo.pop_back())
	canvas.queue_redraw()
	_refresh_object_list()
	_refresh_connections()
	_update_state()


func save_to(target_path := "") -> String:
	if document == null:
		return "no map document"
	var error := document.save(target_path)
	if error == "" and world_document != null and target_path == "":
		error = world_document.save()
	if error == "":
		_status.text = "Saved · %s" % document.path
		document_saved.emit(document.path if target_path == "" else target_path)
	else:
		_status.text = "REFUSED — " + error
	_update_state()
	return error


func revert_document() -> String:
	var opened := MapDocument.open(document.project_dir, document.label)
	if not bool(opened.get("ok", false)):
		var error := str(opened.get("error", "cannot reopen map"))
		_status.text = "REFUSED — " + error
		return error
	var reopened_world = null
	if world_document != null:
		var world_opened := preload("res://core/WorldDocument.gd").open(document.project_dir)
		if not bool(world_opened.get("ok", false)):
			var world_error := str(world_opened.get("error", "cannot reopen world graph"))
			_status.text = "REFUSED — " + world_error
			return world_error
		reopened_world = world_opened["document"]
	return bind_document(opened["document"], reopened_world, _map_labels)


func is_dirty() -> bool:
	return document != null and (document.is_dirty() \
		or (world_document != null and world_document.is_dirty()))


func undo_control() -> Button:
	return _undo_button


func redo_control() -> Button:
	return _redo_button


func save_control() -> Button:
	return _save


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	_tool_buttons.clear()

	var toolbar_panel := PanelContainer.new()
	toolbar_panel.name = "ActionBar"
	add_child(toolbar_panel)
	var toolbar := HBoxContainer.new()
	toolbar_panel.add_child(toolbar)
	_undo_button = _button("Undo", false)
	_undo_button.pressed.connect(undo)
	toolbar.add_child(_undo_button)
	_redo_button = _button("Redo", false)
	_redo_button.pressed.connect(redo)
	toolbar.add_child(_redo_button)
	_save = _button("Save", false)
	_save.pressed.connect(func() -> void: save_to())
	toolbar.add_child(_save)
	_revert = _button("Revert", false)
	_revert.pressed.connect(revert_document)
	toolbar.add_child(_revert)
	_play = _button("Play-test map", false)
	_play.pressed.connect(_request_playtest)
	toolbar.add_child(_play)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	var out := _button("−", false)
	out.tooltip_text = "Zoom out"
	out.pressed.connect(func() -> void: canvas.zoom_by(-0.5))
	toolbar.add_child(out)
	var inside := _button("+", false)
	inside.tooltip_text = "Zoom in"
	inside.pressed.connect(func() -> void: canvas.zoom_by(0.5))
	toolbar.add_child(inside)
	var tileset := OptionButton.new()
	tileset.add_item(str(document.tileset.get("name", "Tileset")))
	tileset.disabled = true
	tileset.custom_minimum_size.x = 145
	toolbar.add_child(tileset)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var tools := PanelContainer.new()
	tools.name = "ToolRail"
	tools.custom_minimum_size.x = 170
	body.add_child(tools)
	var tool_column := VBoxContainer.new()
	tools.add_child(tool_column)
	tool_column.add_child(_section("TOOLS"))
	_add_tool(tool_column, "brush", "Tile brush")
	_add_tool(tool_column, "block", "Block brush")
	_add_tool(tool_column, "erase", "Eraser")
	_add_tool(tool_column, "fill", "Fill")
	_add_tool(tool_column, "walkable", "Walkable")
	_add_tool(tool_column, "solid", "Solid")
	_add_tool(tool_column, "pan", "Pan")
	tool_column.add_child(HSeparator.new())
	tool_column.add_child(_section("OBJECTS"))
	_add_tool(tool_column, "warp", "Place warp")
	_add_tool(tool_column, "npc", "Place NPC")
	_add_tool(tool_column, "sign", "Place sign")
	_add_tool(tool_column, "trigger", "Place trigger")
	tool_column.add_child(HSeparator.new())
	tool_column.add_child(_section("TILESET"))
	var palette_scroll := ScrollContainer.new()
	palette_scroll.name = "PaletteScroll"
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tool_column.add_child(palette_scroll)
	palette = preload("res://scripts/studio/StudioTilePalette.gd").new()
	palette.tile_selected.connect(select_tile)
	palette_scroll.add_child(palette)
	var collision := CheckButton.new()
	collision.text = "Collision overlay"
	collision.button_pressed = true
	collision.toggled.connect(func(on: bool) -> void:
		canvas.show_collision = on
		canvas.queue_redraw())
	tool_column.add_child(collision)

	var canvas_panel := PanelContainer.new()
	canvas_panel.name = "CanvasPanel"
	canvas_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(canvas_panel)
	canvas = StudioMapCanvas.new()
	canvas.stroke_started.connect(begin_stroke)
	canvas.cell_requested.connect(apply_cell)
	canvas.stroke_finished.connect(end_stroke)
	canvas_panel.add_child(canvas)

	var inspector := VBoxContainer.new()
	inspector.name = "InspectorDock"
	inspector.custom_minimum_size.x = 275
	body.add_child(inspector)
	var facts_panel := PanelContainer.new()
	inspector.add_child(facts_panel)
	var facts := VBoxContainer.new()
	facts_panel.add_child(facts)
	facts.add_child(_section("INSPECTOR"))
	facts.add_child(_fact("Map", document.label))
	facts.add_child(_fact("Size", "%d × %d cells" % [document.width, document.height]))
	facts.add_child(_fact("Spawn", str(document.default_spawn)))
	facts.add_child(_fact("Objects", str(document.objects.size() + document.warps.size()
		+ document.signs.size() + document.triggers.size())))
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(inspector_scroll)
	var layers := VBoxContainer.new()
	layers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(layers)
	layers.add_child(_section("LAYERS"))
	layers.add_child(_layer("▰  Ground", true))
	layers.add_child(_layer("◇  Collision", false))
	layers.add_child(_layer("●  Objects", false))
	layers.add_child(_layer("◆  Triggers", false))
	layers.add_child(HSeparator.new())
	_build_object_inspector(layers)
	if world_document != null:
		layers.add_child(HSeparator.new())
		_build_connection_inspector(layers)
	_refresh_object_list()
	_refresh_connections()

	_status = Label.new()
	_status.add_theme_color_override("font_color", StudioTheme.MUTED)
	add_child(_status)


func _add_tool(parent: Control, key: String, label: String) -> void:
	var button := _button(label, false)
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func() -> void: select_tool(key))
	parent.add_child(button)
	_tool_buttons[key] = button


func _place_object(kind: String, cell: Vector2i) -> bool:
	var suffix := 1
	var object_id := "%s_%03d" % [kind, suffix]
	var used := {}
	for candidate_kind in ["warp", "npc", "sign", "trigger"]:
		for record in document.records_for_kind(candidate_kind):
			used[str(record.get("id", ""))] = true
	while used.has(object_id):
		suffix += 1
		object_id = "%s_%03d" % [kind, suffix]
	var fields := {}
	match kind:
		"warp": fields = {"dest_map": document.label, "dest_const": "", "dest_warp": 1}
		"npc": fields = {"sprite": "SPRITE_RED", "args": ["STAY", "DOWN"], "event": ""}
		"sign": fields = {"text": "", "event": ""}
		"trigger": fields = {"width": 1, "height": 1, "event": ""}
	var error := document.add_typed_object(kind, object_id, cell, fields)
	if error != "":
		_status.text = "REFUSED — " + error
		return false
	_selected_object_kind = kind
	_selected_object_id = object_id
	return true


func _build_object_inspector(parent: VBoxContainer) -> void:
	parent.add_child(_section("OBJECT INSPECTOR"))
	_object_list = OptionButton.new()
	_object_list.item_selected.connect(_on_object_selected)
	parent.add_child(_object_list)
	_object_id = _inspector_line(parent, "Stable id")
	_object_x = _inspector_spin(parent, "Cell X", 0, maxi(0, document.width - 1))
	_object_y = _inspector_spin(parent, "Cell Y", 0, maxi(0, document.height - 1))
	_object_event = _inspector_line(parent, "Event id")
	_object_event.placeholder_text = "event:my_event (optional)"
	_object_detail_a = _inspector_line(parent, "Detail A")
	_object_detail_b = _inspector_line(parent, "Detail B")
	_object_detail_c = _inspector_line(parent, "Detail C")
	_object_number_a = _inspector_spin(parent, "Number A", 1, 256)
	_object_number_b = _inspector_spin(parent, "Number B", 1, 256)
	var actions := HBoxContainer.new()
	parent.add_child(actions)
	_object_apply = _button("Apply", true)
	_object_apply.pressed.connect(_apply_object_inspector)
	actions.add_child(_object_apply)
	_object_delete = _button("Delete", true)
	_object_delete.pressed.connect(_delete_selected_object)
	actions.add_child(_object_delete)
	_object_event_edit = _button("Create / Edit Event", true)
	_object_event_edit.pressed.connect(func() -> void:
		event_requested.emit(_selected_object_kind, _selected_object_id,
			_object_event.text.strip_edges()))
	parent.add_child(_object_event_edit)


func _refresh_object_list() -> void:
	if _object_list == null:
		return
	_object_list.clear()
	var wanted := -1
	for kind in ["warp", "npc", "sign", "trigger"]:
		for record in document.records_for_kind(kind):
			var object_id := str(record.get("id", ""))
			_object_list.add_item("%s · %s" % [kind.capitalize(), object_id])
			var index := _object_list.item_count - 1
			_object_list.set_item_metadata(index, {"kind": kind, "id": object_id})
			if kind == _selected_object_kind and object_id == _selected_object_id:
				wanted = index
	if _object_list.item_count == 0:
		_selected_object_kind = ""
		_selected_object_id = ""
		_set_object_fields_enabled(false)
		return
	if wanted < 0:
		wanted = 0
	_object_list.select(wanted)
	_on_object_selected(wanted)


func _on_object_selected(index: int) -> void:
	if index < 0 or index >= _object_list.item_count:
		return
	var metadata: Dictionary = _object_list.get_item_metadata(index)
	_selected_object_kind = str(metadata.get("kind", ""))
	_selected_object_id = str(metadata.get("id", ""))
	var selected: Dictionary = {}
	for record in document.records_for_kind(_selected_object_kind):
		if str(record.get("id", "")) == _selected_object_id:
			selected = record
			break
	if selected.is_empty():
		return
	_object_id.text = _selected_object_id
	_object_x.value = int(selected.get("x", 0))
	_object_y.value = int(selected.get("y", 0))
	_object_event.text = str(selected.get("event", ""))
	_object_detail_a.text = ""
	_object_detail_b.text = ""
	_object_detail_c.text = ""
	_object_number_a.value = 1
	_object_number_b.value = 1
	_configure_object_field(_object_event, "Event id", _selected_object_kind != "warp")
	_configure_object_field(_object_detail_a, "Detail A", false)
	_configure_object_field(_object_detail_b, "Detail B", false)
	_configure_object_field(_object_detail_c, "Detail C", false)
	_configure_object_field(_object_number_a, "Number A", false)
	_configure_object_field(_object_number_b, "Number B", false)
	match _selected_object_kind:
		"warp":
			_configure_object_field(_object_detail_a, "Destination map", true)
			_configure_object_field(_object_detail_b, "Ruleset destination", true)
			_configure_object_field(_object_number_a, "Destination warp", true)
			_object_detail_b.placeholder_text = "optional constant"
			_object_detail_a.text = str(selected.get("dest_map", ""))
			_object_detail_b.text = str(selected.get("dest_const", ""))
			_object_number_a.value = int(selected.get("dest_warp", 1))
		"npc":
			_configure_object_field(_object_detail_a, "Sprite", true)
			_configure_object_field(_object_detail_b, "Movement", true)
			_configure_object_field(_object_detail_c, "Facing", true)
			var args: Array = selected.get("args", ["STAY", "NONE"])
			_object_detail_a.text = str(selected.get("sprite", ""))
			_object_detail_b.text = str(args[0])
			_object_detail_c.text = str(args[1])
		"sign":
			_configure_object_field(_object_detail_a, "Inline text", true)
			_object_detail_a.placeholder_text = "optional when an event is set"
			_object_detail_a.text = str(selected.get("text", ""))
		"trigger":
			_configure_object_field(_object_number_a, "Region width (cells)", true)
			_configure_object_field(_object_number_b, "Region height (cells)", true)
			_object_number_a.value = int(selected.get("width", 1))
			_object_number_b.value = int(selected.get("height", 1))
	var locked := bool(selected.get("_legacy_locked", false))
	_set_object_fields_enabled(not locked)
	if locked and _status != null:
		_status.text = "Imported legacy object · read-only compatibility payload"


func _set_object_fields_enabled(enabled: bool) -> void:
	for control in [_object_id, _object_x, _object_y, _object_event, _object_detail_a,
			_object_detail_b, _object_detail_c, _object_number_a, _object_number_b]:
		if control != null:
			control.editable = enabled
	if _object_apply != null:
		_object_apply.disabled = not enabled
	if _object_delete != null:
		_object_delete.disabled = not enabled
	if _object_event_edit != null:
		_object_event_edit.disabled = not enabled or _selected_object_kind not in ["npc", "trigger"]


func _apply_object_inspector() -> void:
	if _selected_object_kind == "" or _selected_object_id == "":
		return
	var before := _capture_state()
	var values := {"id": _object_id.text.strip_edges(), "x": int(_object_x.value),
		"y": int(_object_y.value), "event": _object_event.text.strip_edges()}
	match _selected_object_kind:
		"warp":
			values.merge({"dest_map": _object_detail_a.text.strip_edges(),
				"dest_const": _object_detail_b.text.strip_edges(),
				"dest_warp": int(_object_number_a.value)})
		"npc": values.merge({"sprite": _object_detail_a.text.strip_edges(),
			"args": [_object_detail_b.text.strip_edges(), _object_detail_c.text.strip_edges()]})
		"sign": values["text"] = _object_detail_a.text
		"trigger": values.merge({"width": int(_object_number_a.value),
			"height": int(_object_number_b.value)})
	var new_id := str(values["id"])
	var error := document.update_typed_object(_selected_object_kind, _selected_object_id, values)
	if error != "":
		_status.text = "REFUSED — " + error
		return
	_selected_object_id = new_id
	_commit_discrete_edit(before)
	canvas.queue_redraw()
	_refresh_object_list()


func _delete_selected_object() -> void:
	if _selected_object_kind == "" or _selected_object_id == "":
		return
	var before := _capture_state()
	var error := document.remove_typed_object(_selected_object_kind, _selected_object_id)
	if error != "":
		_status.text = "REFUSED — " + error
		return
	_selected_object_kind = ""
	_selected_object_id = ""
	_commit_discrete_edit(before)
	canvas.queue_redraw()
	_refresh_object_list()


func _build_connection_inspector(parent: VBoxContainer) -> void:
	parent.add_child(_section("WORLD CONNECTIONS"))
	_connection_list = OptionButton.new()
	_connection_list.item_selected.connect(_on_connection_selected)
	parent.add_child(_connection_list)
	_connection_direction = OptionButton.new()
	for direction in ["north", "south", "west", "east"]:
		_connection_direction.add_item(direction.capitalize())
		_connection_direction.set_item_metadata(_connection_direction.item_count - 1, direction)
	parent.add_child(_connection_direction)
	_connection_map = OptionButton.new()
	for map_label in _map_labels:
		if str(map_label) != document.label:
			_connection_map.add_item(str(map_label))
	parent.add_child(_connection_map)
	_connection_offset = _inspector_spin(parent, "Block offset", -256, 256)
	_connection_offset.value = 0
	var actions := HBoxContainer.new()
	parent.add_child(actions)
	_connection_apply = _button("Link / Update", _connection_map.item_count == 0)
	_connection_apply.pressed.connect(_apply_connection)
	actions.add_child(_connection_apply)
	_connection_delete = _button("Unlink", true)
	_connection_delete.pressed.connect(_delete_connection)
	actions.add_child(_connection_delete)


func _refresh_connections() -> void:
	if _connection_list == null or world_document == null:
		return
	_connection_list.clear()
	for connection in world_document.connections(document.label):
		_connection_list.add_item("%s · %s · offset %d" % [
			str(connection.get("direction", "")).capitalize(),
			str(connection.get("map", "")).trim_prefix("map:"), int(connection.get("offset", 0))])
		_connection_list.set_item_metadata(_connection_list.item_count - 1, connection)
	_connection_delete.disabled = _connection_list.item_count == 0
	if _connection_list.item_count > 0:
		_connection_list.select(0)
		_on_connection_selected(0)


func _on_connection_selected(index: int) -> void:
	if index < 0 or index >= _connection_list.item_count:
		return
	var connection: Dictionary = _connection_list.get_item_metadata(index)
	_select_option_metadata(_connection_direction, str(connection.get("direction", "")))
	_select_option_text(_connection_map, str(connection.get("map", "")).trim_prefix("map:"))
	_connection_offset.value = int(connection.get("offset", 0))


func _apply_connection() -> void:
	if world_document == null or _connection_map.item_count == 0:
		return
	var before := _capture_state()
	var direction := str(_connection_direction.get_item_metadata(_connection_direction.selected))
	var destination := _connection_map.get_item_text(_connection_map.selected)
	var error: String = world_document.set_connection(document.label, direction, destination,
		int(_connection_offset.value))
	if error != "":
		_status.text = "REFUSED — " + error
		return
	_commit_discrete_edit(before)
	_refresh_connections()


func _delete_connection() -> void:
	if world_document == null or _connection_list.selected < 0:
		return
	var connection: Dictionary = _connection_list.get_item_metadata(_connection_list.selected)
	var before := _capture_state()
	if world_document.remove_connection(document.label, str(connection.get("direction", ""))):
		_commit_discrete_edit(before)
		_refresh_connections()


func object_controls() -> Dictionary:
	return {"list": _object_list, "id": _object_id, "x": _object_x, "y": _object_y,
		"event": _object_event, "detail_a": _object_detail_a, "detail_b": _object_detail_b,
		"detail_c": _object_detail_c, "number_a": _object_number_a,
		"number_b": _object_number_b, "apply": _object_apply, "delete": _object_delete,
		"edit_event": _object_event_edit}


## Shell transaction seam: an event file is written first, then its map object is linked.
## If the TMX save fails the project has only an unreferenced event, never a dangling map link.
func link_selected_event(event_id: String) -> String:
	if _selected_object_kind not in ["npc", "trigger"] or _selected_object_id == "":
		return "select an authored NPC or trigger first"
	_object_event.text = event_id
	_apply_object_inspector()
	if str(_object_event.text) != event_id:
		return "could not link selected object"
	return save_to()


func connection_controls() -> Dictionary:
	return {"list": _connection_list, "direction": _connection_direction,
		"map": _connection_map, "offset": _connection_offset, "apply": _connection_apply,
		"delete": _connection_delete}


func _request_playtest() -> void:
	if is_dirty():
		_status.text = "Save or Revert before play-testing this map"
		return
	playtest_requested.emit(document.label)


func _update_state() -> void:
	if document == null or _status == null:
		return
	var dirty := is_dirty()
	_undo_button.disabled = _undo.is_empty()
	_redo_button.disabled = _redo.is_empty()
	_save.disabled = not dirty
	_revert.disabled = not dirty
	_play.disabled = dirty
	_status.text = "%dx%d cells · %s · tile %d · %s" % [document.width, document.height,
		_tool.capitalize(), _selected_tile, "DIRTY" if dirty else "SAVED"]


func _capture_state() -> Dictionary:
	return {"map": document.edit_state() if document != null else {},
		"world": world_document.edit_state() if world_document != null else {}}


func _restore_state(state: Dictionary) -> void:
	if document != null:
		document.restore_edit_state(state.get("map", {}))
	if world_document != null:
		world_document.restore_edit_state(state.get("world", {}))


func _commit_discrete_edit(before: Dictionary) -> void:
	var after := _capture_state()
	if not _states_equal(before, after):
		_undo.append(before)
		_redo.clear()
	_update_state()


static func _states_equal(a: Dictionary, b: Dictionary) -> bool:
	return a == b


static func _inspector_line(parent: VBoxContainer, label_text: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", StudioTheme.MUTED)
	parent.add_child(label)
	var line := LineEdit.new()
	line.set_meta("field_label", label)
	parent.add_child(line)
	return line


static func _inspector_spin(parent: VBoxContainer, label_text: String,
		minimum: float, maximum: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", StudioTheme.MUTED)
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.set_meta("field_label", label)
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	parent.add_child(spin)
	return spin


static func _configure_object_field(control: Control, label_text: String, shown: bool) -> void:
	control.visible = shown
	var label = control.get_meta("field_label", null)
	if label is Label:
		label.text = label_text
		label.visible = shown


static func _select_option_text(option: OptionButton, wanted: String) -> void:
	for index in option.item_count:
		if option.get_item_text(index) == wanted:
			option.select(index)
			return


static func _select_option_metadata(option: OptionButton, wanted: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == wanted:
			option.select(index)
			return


static func _button(text: String, disabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.custom_minimum_size.y = 34
	return button


static func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", StudioTheme.MUTED)
	label.add_theme_font_size_override("font_size", 12)
	return label


static func _fact(key: String, value: String) -> Label:
	var label := Label.new()
	label.text = "%s\n%s" % [key, value]
	label.tooltip_text = value
	return label


static func _layer(text: String, selected: bool) -> Button:
	var layer := Button.new()
	layer.text = text
	layer.alignment = HORIZONTAL_ALIGNMENT_LEFT
	layer.disabled = not selected
	return layer
