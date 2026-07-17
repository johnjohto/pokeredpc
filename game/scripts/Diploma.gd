extends Control
## The DIPLOMA (engine/events/diploma.asm DisplayDiploma): a full-screen card in the
## trainer-info border — ●Diploma●, "Player <NAME>", the congrats text, GAME FREAK — with
## the title-screen Red pic printed behind the card (the asm shifts his title OAM 33 px
## right and sets the behind-BG priority bit; OBP0=$90 renders every shade one step
## lighter). Any button closes it (WaitForTextScrollButtonPress).

signal closed

const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8
# GB shades 0-3; OBP0 $90 maps sprite colour 3->shade 2, 2->1, 1->0 (0 stays transparent).
const _SHADES := [Color(0.918, 0.984, 0.808), Color(0.710, 0.824, 0.584),
	Color(0.396, 0.541, 0.447), Color(0.133, 0.188, 0.224)]

var main
var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var info_tex: Texture2D            # the trainer-info border tiles (same 3x3 sheet as the card)
var circle_tex: Texture2D          # the $70 CircleTile framing ●Diploma●
var player_tex: Texture2D          # title Red (assets/title/player.png), OBP0-$90-shifted


func setup(m, ft: Texture2D, cols: int, cmap: Dictionary) -> void:
	main = m
	font_tex = ft
	font_cols = cols
	charmap = cmap
	info_tex = load("res://assets/trainer_info.png")
	circle_tex = load("res://assets/circle_tile.png")
	player_tex = _obp0_90(load("res://assets/title/player.png"))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Bake the OBP0=$90 palette: every opaque pixel's shade steps one lighter.
func _obp0_90(tex: Texture2D) -> Texture2D:
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var best := 0
			var bd := 99.0
			for i in _SHADES.size():
				var d: float = _SHADES[i].r - c.r
				var dg: float = _SHADES[i].g - c.g
				var db: float = _SHADES[i].b - c.b
				var dist := d * d + dg * dg + db * db
				if dist < bd:
					bd = dist
					best = i
			img.set_pixel(x, y, _SHADES[maxi(best - 1, 0)])
	return ImageTexture.create_from_image(img)


func open_card() -> void:
	visible = true
	queue_redraw()


func handle_input() -> void:
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
		visible = false
		closed.emit()


# trainer_info.png tile positions (row-major 3x3) — same sheet as TrainerCard.
const _T := {"bot": Vector2(0, 0), "right": Vector2(8, 0), "ul": Vector2(16, 0),
	"top": Vector2(0, 8), "ur": Vector2(8, 8), "left": Vector2(16, 8),
	"ll": Vector2(0, 16), "lr": Vector2(8, 16)}


func _tile(which: String, tx: int, ty: int) -> void:
	draw_texture_rect_region(info_tex, Rect2(tx * 8, ty * 8, 8, 8), Rect2(_T[which], Vector2(8, 8)))


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)          # ClearScreen
	# Red first: the behind-BG priority bit means the card's glyphs and border overdraw him.
	# Title OAM base (82,80) + the 33 px shift -> (115,80).
	draw_texture(player_tex, Vector2(115, 80))
	# Diploma_TextBoxBorder at (0,0), interior 18x16 = the whole 20x18 screen.
	_tile("ul", 0, 0)
	_tile("ur", 19, 0)
	_tile("ll", 0, 17)
	_tile("lr", 19, 17)
	for c in 18:
		_tile("top", 1 + c, 0)
		_tile("bot", 1 + c, 17)
	for r in 16:
		_tile("left", 0, 1 + r)
		_tile("right", 19, 1 + r)
	# DiplomaTextPointersAndCoords (tile x, y).
	draw_texture(circle_tex, Vector2(5 * 8, 2 * 8))  # ●Diploma●
	_text("Diploma", 6 * 8, 2 * 8)
	draw_texture(circle_tex, Vector2(13 * 8, 2 * 8))
	_text("Player", 3 * 8, 4 * 8)
	_text(main.player_name, 10 * 8, 4 * 8)
	# PlaceString <NEXT> without BIT_SINGLE_SPACED_LINES = two rows per line.
	var congrats := ["Congrats! This", "diploma certifies", "that you have",
		"completed your", "POKéDEX."]
	for i in congrats.size():
		_text(congrats[i], 2 * 8, (6 + 2 * i) * 8)
	_text("GAME FREAK", 9 * 8, 16 * 8)


func _text(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var ti: int = charmap[ch]
			var src := Rect2((ti % font_cols) * GLYPH, (ti / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
