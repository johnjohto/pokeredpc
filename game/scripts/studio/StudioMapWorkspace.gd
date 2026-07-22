extends VBoxContainer
class_name StudioMapWorkspace
## Reference-shaped Phase-5 workspace: compact actions, tool rail, dominant map,
## inspector, and layers. Editing controls are deliberately disabled until gh #54;
## this tracer can preview and byte-stably save the shared MapDocument.

signal document_saved(path: String)

var document: MapDocument
var canvas: StudioMapCanvas
var _status: Label
var _save: Button


func _ready() -> void:
	name = "MapWorkspace"
	custom_minimum_size = Vector2(590, 500)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func bind_document(value: MapDocument) -> String:
	document = value
	_build_ui()
	var error := canvas.bind_document(document)
	if error != "":
		_status.text = "REFUSED — " + error
		_save.disabled = true
		return error
	_status.text = "%dx%d movement cells · %s · READ ONLY" % [
		document.width, document.height, str(document.tileset.get("name", "tileset"))]
	return ""


func canvas_control() -> StudioMapCanvas:
	return canvas


func save_to(target_path := "") -> String:
	if document == null:
		return "no map document"
	var error := document.save(target_path)
	_status.text = "Saved byte-identically" if error == "" else "REFUSED — " + error
	if error == "":
		document_saved.emit(document.path if target_path == "" else target_path)
	return error


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var toolbar_panel := PanelContainer.new()
	toolbar_panel.name = "ActionBar"
	add_child(toolbar_panel)
	var toolbar := HBoxContainer.new()
	toolbar_panel.add_child(toolbar)
	var back := _button("Undo", true)
	toolbar.add_child(back)
	var forward := _button("Redo", true)
	toolbar.add_child(forward)
	_save = _button("Save", false)
	_save.pressed.connect(func() -> void: save_to())
	toolbar.add_child(_save)
	var play := _button("Play-test", true)
	toolbar.add_child(play)
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
	tileset.custom_minimum_size.x = 150
	toolbar.add_child(tileset)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var tools := PanelContainer.new()
	tools.name = "ToolRail"
	tools.custom_minimum_size.x = 92
	body.add_child(tools)
	var tool_column := VBoxContainer.new()
	tools.add_child(tool_column)
	tool_column.add_child(_section("TOOLS"))
	tool_column.add_child(_button("Select", false))
	tool_column.add_child(_button("Brush", true))
	tool_column.add_child(_button("Eraser", true))
	tool_column.add_child(HSeparator.new())
	tool_column.add_child(_section("OVERLAYS"))
	var grid := CheckButton.new()
	grid.text = "Grid"
	grid.button_pressed = true
	grid.toggled.connect(func(on: bool) -> void:
		canvas.show_grid = on
		canvas.queue_redraw())
	tool_column.add_child(grid)
	var collision := CheckButton.new()
	collision.text = "Collision"
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
