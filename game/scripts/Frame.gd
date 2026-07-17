class_name Frame
## Draws a Gen-1 ornate text-box/menu frame (font_extra tiles ┌─┐│└┘) on a CanvasItem.
## Atlas (frame.png) order: 0=┌ 1=─ 2=┐ 3=│ 4=└ 5=┘. Interior filled LIGHT; the tile glyphs
## (transparent paper, dark ink) draw the double-line border over it.

const GLYPH := 8


## Draw a wt×ht (tiles) framed box with its top-left at (x, y).
static func draw(ci: CanvasItem, tex: Texture2D, x: float, y: float, wt: int, ht: int, light: Color) -> void:
	ci.draw_rect(Rect2(x, y, wt * GLYPH, ht * GLYPH), light)
	var rx := x + (wt - 1) * GLYPH
	var by := y + (ht - 1) * GLYPH
	for c in range(1, wt - 1):
		_tile(ci, tex, 1, x + c * GLYPH, y)               # top ─
		_tile(ci, tex, 1, x + c * GLYPH, by)              # bottom ─
	for r in range(1, ht - 1):
		_tile(ci, tex, 3, x, y + r * GLYPH)               # left │
		_tile(ci, tex, 3, rx, y + r * GLYPH)              # right │
	_tile(ci, tex, 0, x, y)                               # ┌
	_tile(ci, tex, 2, rx, y)                              # ┐
	_tile(ci, tex, 4, x, by)                              # └
	_tile(ci, tex, 5, rx, by)                             # ┘


static func _tile(ci: CanvasItem, tex: Texture2D, idx: int, px: float, py: float) -> void:
	ci.draw_texture_rect_region(tex, Rect2(px, py, GLYPH, GLYPH), Rect2(idx * GLYPH, 0, GLYPH, GLYPH))
