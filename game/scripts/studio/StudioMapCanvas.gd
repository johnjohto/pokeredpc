extends Control
class_name StudioMapCanvas
## Read-only Phase-5 map canvas. It consumes MapDocument directly, draws the same
## project-local atlas cells as Engine, and establishes the canvas/overlay language
## that gh #54 will make interactive.

const CELL := MapDocument.CELL_SIZE

var document: MapDocument
var atlas: Image
var texture: ImageTexture
var zoom := 6.0
var show_grid := true
var show_collision := true


func _ready() -> void:
	name = "MapCanvas"
	custom_minimum_size = Vector2(300, 360)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)


func bind_document(value: MapDocument) -> String:
	document = value
	var loaded := document.load_image()
	if not bool(loaded.get("ok", false)):
		return str(loaded.get("error", "cannot load map atlas"))
	atlas = loaded["image"]
	texture = ImageTexture.create_from_image(atlas)
	queue_redraw()
	return ""


func zoom_by(delta: float) -> void:
	zoom = clampf(zoom + delta, 0.5, 8.0)
	queue_redraw()


func source_rect_for_tile(tile_id: int) -> Rect2i:
	if document == null:
		return Rect2i()
	var columns := int(document.tileset.get("columns", 1))
	return Rect2i((tile_id % columns) * CELL, (tile_id / columns) * CELL, CELL, CELL)


## Unscaled, grid-free pixels used by the Studio smoke and comparison artifacts.
## The live _draw path uses the same source_rect_for_tile mapping.
func render_image() -> Image:
	if document == null or atlas == null:
		return Image.new()
	var image := Image.create(document.width * CELL, document.height * CELL,
		false, Image.FORMAT_RGBA8)
	for y in document.height:
		for x in document.width:
			image.blit_rect(atlas, source_rect_for_tile(document.tile_at(Vector2i(x, y))),
				Vector2i(x * CELL, y * CELL))
	return image


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), StudioTheme.WINDOW)
	if document == null or texture == null:
		return
	var display_zoom := _display_zoom()
	var map_size := Vector2(document.width * CELL, document.height * CELL) * display_zoom
	var origin := ((size - map_size) * 0.5).floor()
	draw_rect(Rect2(origin - Vector2(8, 8), map_size + Vector2(16, 16)),
		Color(0, 0, 0, 0.28), true)
	for y in document.height:
		for x in document.width:
			var cell := Vector2i(x, y)
			var dst := Rect2(origin + Vector2(cell * CELL) * display_zoom,
				Vector2(CELL, CELL) * display_zoom)
			draw_texture_rect_region(texture, dst, source_rect_for_tile(document.tile_at(cell)))
			if show_collision and not document.is_walkable(cell):
				draw_rect(dst, Color(0.95, 0.21, 0.29, 0.23), true)
	if show_grid:
		for x in range(document.width + 1):
			var px := origin.x + x * CELL * display_zoom
			draw_line(Vector2(px, origin.y), Vector2(px, origin.y + map_size.y),
				Color(0.76, 0.85, 0.91, 0.22), 1.0)
		for y in range(document.height + 1):
			var py := origin.y + y * CELL * display_zoom
			draw_line(Vector2(origin.x, py), Vector2(origin.x + map_size.x, py),
				Color(0.76, 0.85, 0.91, 0.22), 1.0)
	_draw_markers(document.warps, origin, display_zoom, StudioTheme.CYAN, "W")
	_draw_markers(document.objects, origin, display_zoom, StudioTheme.MINT, "N")
	_draw_markers(document.signs, origin, display_zoom, Color(0.98, 0.72, 0.27, 1), "S")
	_draw_markers(document.triggers, origin, display_zoom, StudioTheme.MAGENTA, "T")


func _display_zoom() -> float:
	var unscaled := Vector2(document.width * CELL, document.height * CELL)
	var available := (size - Vector2(32, 32)).max(Vector2(CELL, CELL))
	return maxf(0.5, minf(zoom, minf(available.x / unscaled.x, available.y / unscaled.y)))


func _draw_markers(records: Array, origin: Vector2, display_zoom: float,
		color: Color, letter: String) -> void:
	for record in records:
		var center := origin + (Vector2(float(record.get("x", 0)),
			float(record.get("y", 0))) + Vector2(0.5, 0.5)) * CELL * display_zoom
		draw_circle(center, maxf(6.0, 4.0 * display_zoom), Color(color, 0.28))
		draw_arc(center, maxf(6.0, 4.0 * display_zoom), 0, TAU, 24, color, 2.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(-4, 5), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
