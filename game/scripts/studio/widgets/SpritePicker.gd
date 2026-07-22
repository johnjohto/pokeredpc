extends VBoxContainer
class_name StudioSpritePicker
## Species front/back sprite selector. Assets stay in the opened project; Texture2D
## previews are created from external PNG files instead of assuming res:// ownership.

const Support := preload("res://scripts/studio/widgets/WidgetSupport.gd")

var _project_dir := ""
var _value: Dictionary = {}
var _changed := Callable()
var _pickers := {}
var _previews := {}


func setup(project_dir: String, value, changed: Callable) -> void:
	_project_dir = project_dir
	_value = value.duplicate(true) if value is Dictionary else {}
	_changed = changed
	_build()


func picker(side: String) -> OptionButton:
	return _pickers.get(side, null)


func preview(side: String) -> TextureRect:
	return _previews.get(side, null)


func current_value() -> Dictionary:
	return _value.duplicate(true)


func _build() -> void:
	_pickers.clear()
	_previews.clear()
	for child in get_children():
		child.queue_free()
	for side in ["front", "back"]:
		var row := HBoxContainer.new()
		add_child(row)
		var side_label := Label.new()
		side_label.text = str(side).capitalize()
		side_label.custom_minimum_size.x = 48
		row.add_child(side_label)
		var image := TextureRect.new()
		image.custom_minimum_size = Vector2(64, 64)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(image)
		_previews[side] = image
		var choose := OptionButton.new()
		choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var relative_dir := "assets/pokemon/%s" % side
		var paths := Support.png_paths(_project_dir, relative_dir)
		var current := str(_value.get(side, ""))
		if current != "" and not paths.has(current):
			paths.append(current)
			paths.sort()
		for path in paths:
			choose.add_item(str(path).get_file())
			choose.set_item_metadata(choose.item_count - 1, str(path))
			if str(path) == current:
				choose.select(choose.item_count - 1)
		choose.item_selected.connect(_on_selected.bind(side, choose))
		row.add_child(choose)
		_pickers[side] = choose
		_update_preview(side)


func _on_selected(index: int, side: String, choose: OptionButton) -> void:
	_value[side] = str(choose.get_item_metadata(index))
	_update_preview(side)
	if _changed.is_valid():
		_changed.call(_value.duplicate(true))


func _update_preview(side: String) -> void:
	var image: TextureRect = _previews.get(side, null)
	if image != null:
		image.texture = Support.external_texture(_project_dir, str(_value.get(side, "")))
