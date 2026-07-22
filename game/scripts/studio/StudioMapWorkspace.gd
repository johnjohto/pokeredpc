extends VBoxContainer
class_name StudioMapWorkspace
## Phase-5 native map authoring workspace. MapDocument owns edits/serialization; this class
## composes tools, palette, undo/redo, dirty state, save/revert, and play-test intent.

signal document_saved(path: String)
signal playtest_requested(map_label: String)

var document: MapDocument
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
var _saved_state: Dictionary = {}


func _ready() -> void:
	name = "MapWorkspace"
	custom_minimum_size = Vector2(590, 500)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func bind_document(value: MapDocument) -> String:
	document = value
	_undo.clear()
	_redo.clear()
	_stroke_before = {}
	_saved_state = document.edit_state()
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
		_stroke_before = document.edit_state()


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
	if changed:
		canvas.queue_redraw()
		_update_state()
	return changed


func end_stroke() -> void:
	if _stroke_before.is_empty():
		return
	var after := document.edit_state()
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
	_redo.append(document.edit_state())
	document.restore_edit_state(_undo.pop_back())
	canvas.queue_redraw()
	_update_state()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(document.edit_state())
	document.restore_edit_state(_redo.pop_back())
	canvas.queue_redraw()
	_update_state()


func save_to(target_path := "") -> String:
	if document == null:
		return "no map document"
	var error := document.save(target_path)
	if error == "":
		_saved_state = document.edit_state()
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
	return bind_document(opened["document"])


func is_dirty() -> bool:
	return document != null and not _states_equal(document.edit_state(), _saved_state)


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
	inspector.custom_minimum_size.x = 190
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
	var layers_panel := PanelContainer.new()
	layers_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.add_child(layers_panel)
	var layers := VBoxContainer.new()
	layers_panel.add_child(layers)
	layers.add_child(_section("LAYERS"))
	layers.add_child(_layer("▰  Ground", true))
	layers.add_child(_layer("◇  Collision", false))
	layers.add_child(_layer("●  Objects", false))
	layers.add_child(_layer("◆  Triggers", false))

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


static func _states_equal(a: Dictionary, b: Dictionary) -> bool:
	return a.get("tiles", PackedInt32Array()) == b.get("tiles", PackedInt32Array()) \
		and a.get("walkable", PackedByteArray()) == b.get("walkable", PackedByteArray()) \
		and bool(a.get("collision_authored", false)) == bool(b.get("collision_authored", false))


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
