extends Control
## The MONEY_BOX (data/text_boxes.asm MONEY_BOX_TEMPLATE): tiles (11,0)-(19,2), the
## "MONEY" label's text tiles replacing the top border at (13,0), the amount right-
## anchored ending at tile 18 with the ¥ hugging the leading digit (PrintBCDNumber
## MONEY_SIGN + suppressed leading zeroes). pokered's paid dialogs — vending machines,
## the Daycare withdrawal, the Museum ticket, the Safari gate, the MtMoon Magikarp
## salesman — draw it before the cost prompt and redraw it right after paying
## (subtract_paid_money.asm), and it stays up for the rest of the dialog. Marts draw
## their own inside MartScreen. Geometry moved here from Menu.money (gh #159/#185).

const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8

var main
var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var frame_tex: Texture2D


func setup(m, ft: Texture2D, cols: int, cmap: Dictionary) -> void:
	main = m
	font_tex = ft
	font_cols = cols
	charmap = cmap
	frame_tex = load("res://assets/frame.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func show_box() -> void:
	visible = true
	queue_redraw()


## After SubtractAmountPaidFromMoney: the box redraws with the new balance.
func refresh() -> void:
	queue_redraw()


func hide_box() -> void:
	visible = false


func _draw() -> void:
	Frame.draw(self, frame_tex, 88, 0, 9, 3, LIGHT)
	draw_rect(Rect2(104, 0, 40, 8), LIGHT)      # the label REPLACES the top border run
	_draw_str("MONEY", 104, 0)
	var ms := "¥" + str(main.player_money)
	_draw_str(ms, 152 - ms.length() * GLYPH, GLYPH)


func _draw_str(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var t: int = charmap[ch]
			var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
