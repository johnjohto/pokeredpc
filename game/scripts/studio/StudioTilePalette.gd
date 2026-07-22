extends Control
class_name StudioTilePalette
## Compact project-atlas palette for the Phase-5 map editor. It draws directly from the
## same raw Image as the canvas, so palette and authored pixels cannot drift.

signal tile_selected(tile_id: int)

const SWATCH := 34

var document: MapDocument
var texture: ImageTexture
var selected_tile := 0
var columns := 4
var hover_tile := -1


func _ready() -> void:
	name = "TilePalette"
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_exited.connect(func() -> void:
		hover_tile = -1
		queue_redraw())


func bind_document(value: MapDocument, atlas: Image) -> void:
	document = value
	texture = ImageTexture.create_from_image(atlas)
	selected_tile = clampi(selected_tile, 0, int(document.tileset.get("tile_count", 1)) - 1)
	var rows := ceili(float(int(document.tileset.get("tile_count", 1))) / columns)
	custom_minimum_size = Vector2(columns * SWATCH, rows * SWATCH)
	queue_redraw()


func select_tile(tile_id: int, emit := true) -> void:
	if document == null or tile_id < 0 or tile_id >= int(document.tileset.get("tile_count", 0)):
		return
	selected_tile = tile_id
	queue_redraw()
	if emit:
		tile_selected.emit(tile_id)


func _gui_input(event: InputEvent) -> void:
	if document == null:
		return
	if event is InputEventMouseMotion:
		hover_tile = _tile_at_position(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		var tile_id := _tile_at_position(event.position)
		if tile_id >= 0:
			select_tile(tile_id)
			accept_event()


func _tile_at_position(position: Vector2) -> int:
	var x := floori(position.x / SWATCH)
	var y := floori(position.y / SWATCH)
	var tile_id := y * columns + x
	return tile_id if x >= 0 and x < columns and tile_id >= 0 \
		and tile_id < int(document.tileset.get("tile_count", 0)) else -1


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), StudioTheme.WINDOW)
	if document == null or texture == null:
		return
	var atlas_columns := int(document.tileset.get("columns", 1))
	for tile_id in int(document.tileset.get("tile_count", 0)):
		var grid := Vector2i(tile_id % columns, tile_id / columns)
		var rect := Rect2(Vector2(grid * SWATCH) + Vector2(2, 2), Vector2(SWATCH - 4, SWATCH - 4))
		var source := Rect2(Vector2((tile_id % atlas_columns) * MapDocument.CELL_SIZE,
			(tile_id / atlas_columns) * MapDocument.CELL_SIZE),
			Vector2(MapDocument.CELL_SIZE, MapDocument.CELL_SIZE))
		draw_texture_rect_region(texture, rect, source)
		if tile_id == selected_tile:
			draw_rect(rect.grow(1), StudioTheme.MINT, false, 3.0)
		elif tile_id == hover_tile:
			draw_rect(rect.grow(1), StudioTheme.CYAN, false, 1.0)
