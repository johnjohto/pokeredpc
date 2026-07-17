extends Control
## The OPTION menu (engine/menus/main_menu.asm DisplayOptionMenu): three bordered rows —
## TEXT SPEED (FAST/MEDIUM/SLOW), BATTLE ANIMATION (ON/OFF), BATTLE STYLE (SHIFT/SET) — and
## CANCEL. Up/down move between rows, left/right pick the value (applied immediately, as in
## Gen 1), A on CANCEL or B/START leaves. Values live in Main.options.

signal closed

const DARK := Color(0.133, 0.188, 0.224)
const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8
# Cursor tile-x per value on each row (the asm's TextSpeedOptionData etc. cursor columns).
const XS := [[1, 7, 14], [1, 10], [1, 10]]
const SPEEDS := [1, 3, 5]                    # FAST / MEDIUM / SLOW letter delays (frames)

var main
var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var frame_tex: Texture2D
var row := 0                                 # 0 text speed, 1 animation, 2 style, 3 CANCEL


func setup(m, ft: Texture2D, cols: int, cmap: Dictionary) -> void:
	main = m
	font_tex = ft
	font_cols = cols
	charmap = cmap
	frame_tex = load("res://assets/frame.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func open_menu() -> void:
	row = 0
	visible = true
	queue_redraw()


func _value(r: int) -> int:
	match r:
		0: return SPEEDS.find(int(main.options["text_speed"]))
		1: return 0 if main.options["battle_anim"] else 1
		_: return 0 if main.options["battle_shift"] else 1


func _set_value(r: int, v: int) -> void:
	match r:
		0: main.options["text_speed"] = SPEEDS[v]
		1: main.options["battle_anim"] = v == 0
		2: main.options["battle_shift"] = v == 0
	main.apply_options()


func handle_input() -> void:
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("p_start") \
			or (Input.is_action_just_pressed("ui_accept") and row == 3):
		visible = false
		closed.emit()
		return
	var moved := false
	if Input.is_action_just_pressed("ui_down"):
		row = mini(row + 1, 3)
		moved = true
	elif Input.is_action_just_pressed("ui_up"):
		row = maxi(row - 1, 0)
		moved = true
	elif row < 3 and (Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right")):
		var n: int = XS[row].size()
		var d := 1 if Input.is_action_just_pressed("ui_right") else -1
		_set_value(row, clampi(_value(row) + d, 0, n - 1))
		moved = true
	if moved:
		if main.audio:
			main.audio.play_sfx("press_ab")
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	# Three 20x5-tile bordered boxes (TextBoxBorder b=3, c=18 at rows 0/5/10).
	Frame.draw(self, frame_tex, 0, 0, 20, 5, LIGHT)
	Frame.draw(self, frame_tex, 0, 40, 20, 5, LIGHT)
	Frame.draw(self, frame_tex, 0, 80, 20, 5, LIGHT)
	_text("TEXT SPEED", 8, 8)
	_text(" FAST  MEDIUM SLOW", 8, 24)
	_text("BATTLE ANIMATION", 8, 48)
	_text(" ON       OFF", 8, 64)
	_text("BATTLE STYLE", 8, 88)
	_text(" SHIFT    SET", 8, 104)
	_text("CANCEL", 16, 128)
	# Every row keeps a cursor one cell LEFT of its picked value: the active row's is the
	# filled ▶, the others hollow ▷ — CANCEL included (profiled from the reference shot).
	for r in 3:
		_text("▶" if r == row else "▷", XS[r][_value(r)] * GLYPH, 24 + r * 40)
	_text("▶" if row == 3 else "▷", 8, 128)


func _text(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var ti: int = charmap[ch]
			var src := Rect2((ti % font_cols) * GLYPH, (ti / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
