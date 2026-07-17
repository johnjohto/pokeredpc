extends Control
## Pokédex data screen (engine/menus/pokedex.asm ShowPokedexData): the mon's pic, №, name,
## species category, height/weight, and the flavor description. Used by the starter examination
## (StarterDex) and the Pokédex. Advance description pages / close with A or B.

signal closed

const DARK := Color(0.133, 0.188, 0.224)     # GB_PALETTE[3]
const LIGHT := Color(0.918, 0.984, 0.808)    # GB_PALETTE[0]
const GLYPH := 8

var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var frame_tex: Texture2D

var _entry: Dictionary
var _name := ""
var _num := 0
var _sprite: Texture2D
var _pages: PackedStringArray
var _page := 0
var _owned := true   # seen-but-not-owned mons show only the pic/No/name (no HT/WT/description)


var fbe_tex: Texture2D


func setup(tex: Texture2D, cols: int, cmap: Dictionary) -> void:
	font_tex = tex
	font_cols = cols
	charmap = cmap
	frame_tex = load("res://assets/frame.png")
	fbe_tex = load("res://assets/font_battle_extra.png")
	dex_tiles = load("res://assets/dex_tiles.png")
	visible = false


func open(mon_name: String, entry: Dictionary, sprite_tex: Texture2D, num: int, owned := true) -> void:
	_name = mon_name
	_entry = entry
	_sprite = sprite_tex
	_num = num
	_owned = owned
	_pages = str(entry.get("desc", "")).split("\f")
	_page = 0
	visible = true
	queue_redraw()


func handle_input() -> void:
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
		_page += 1
		if _page >= _pages.size():
			visible = false
			closed.emit()
		else:
			queue_redraw()


var dex_tiles: Texture2D                     # the dex screens' own tile row ($60-$7a; gh #152)
var _arrow_on := true                        # the page cursor blinks (HandleDownArrowBlinkTiming)
var _blink_t := 0.0

# The row-9 divider, tile by tile (PokedexDataDividerLine): ends $68/$6A, dashes $69, boxes $6B.
const _DIVIDER := [0x68, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x6B,
	0x6B, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6A]


func _process(delta: float) -> void:
	if not visible or _page >= _pages.size() - 1:
		return
	_blink_t += delta
	if _blink_t >= 32.0 / 60.0:              # the textbox down-arrow cadence
		_blink_t = 0.0
		_arrow_on = not _arrow_on
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	# The border is the dex's own tiles: $64 top / $6f bottom / $66 left / $67 right runs with
	# the $63/$65/$6c/$6e corners (ShowPokedexDataInternal's DrawTileLine calls; gh #152).
	for c in range(1, 19):
		_dtile(0x64, c * 8, 0)
		_dtile(0x6f, c * 8, 136)
	for r in range(1, 17):
		_dtile(0x66, 0, r * 8)
		_dtile(0x67, 152, r * 8)
	_dtile(0x63, 0, 0)
	_dtile(0x65, 152, 0)
	_dtile(0x6c, 0, 136)
	_dtile(0x6e, 152, 136)
	if _sprite:
		draw_texture(_sprite, Vector2(8, 8))             # mon pic, upper-left
	_glyph(18, 8, 64)                                    # the "No" glyph + zero-padded number
	_str(".%03d" % _num, 16, 64)
	_str(_name, 72, 16)
	for c in _DIVIDER.size():                            # the row-9 divider, the real tiles
		_dtile(_DIVIDER[c], c * 8, 72)
	if not _owned:                                       # seen only: no data yet
		return
	_str(str(_entry.get("cat", "")), 72, 32)             # species category, e.g. "SEED"
	_str("HT", 72, 48)                                   # HeightWeightText: HT ?′??″ / WT ???lb
	_str("%2d" % int(_entry.get("ft", 0)), 96, 48)
	_tile(129, 112, 48)                                  # ′ feet
	_str("%02d" % int(_entry.get("in", 0)), 120, 48)
	_tile(130, 136, 48)                                  # ″ inches
	_str("WT", 72, 56)
	_str("%5.1f" % (int(_entry.get("wt", 0)) / 10.0), 88, 56)
	_str("lb", 128, 56)
	var lines := str(_pages[_page]).split("\n") if _pages.size() > 0 else PackedStringArray()
	for i in lines.size():                               # description double-spaced from row 11
		_str(str(lines[i]), 8, 88 + i * 16)
	if _page < _pages.size() - 1 and _arrow_on:          # more pages: the blinking ▼ (gh #152)
		_str("▼", 144, 128)


func _dtile(vram: int, x: float, y: float) -> void:      # a dex_tiles.png tile by VRAM id
	draw_texture_rect_region(dex_tiles, Rect2(x, y, 8, 8), Rect2((vram - 0x60) * 8, 0, 8, 8))


func _glyph(t: int, x: float, y: float) -> void:         # a font_battle_extra tile (No=18)
	draw_texture_rect_region(fbe_tex, Rect2(x, y, 8, 8), Rect2((t % 15) * 8, (t / 15) * 8, 8, 8))


func _tile(idx: int, x: float, y: float) -> void:
	var src := Rect2((idx % font_cols) * GLYPH, (idx / font_cols) * GLYPH, GLYPH, GLYPH)
	draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)


func _str(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var t: int = charmap[ch]
			var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
