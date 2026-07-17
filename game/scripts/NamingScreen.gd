extends Control
## GB-style naming screen: a preset-name list (NEW NAME + presets) then, on NEW NAME, the 5x9
## keyboard from data/text/alphabets.asm with a case toggle. Driven by Player.handle_input (one
## action/frame). Emits done(name). Used for the player and the rival in Oak's speech.

signal done(name: String)

const DARK := Color(0.133, 0.188, 0.224)
const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8
const NAME_MAX := 7
const COLW := 16.0   # 2 tiles per column (naming_screen.asm PrintAlphabet)
const ROWH := 16.0
const GX := 16.0
const GY := 40.0
# data/text/alphabets.asm UpperCaseAlphabet (last cell = ED confirm; "Pk"/"Mn" are 1 GB tile each).
const KB := [
	["A", "B", "C", "D", "E", "F", "G", "H", "I"],
	["J", "K", "L", "M", "N", "O", "P", "Q", "R"],
	["S", "T", "U", "V", "W", "X", "Y", "Z", " "],
	["×", "(", ")", ":", ";", "[", "]", "Pk", "Mn"],
	["-", "?", "!", "♂", "♀", "/", ".", ",", "ED"],
]

var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var frame_tex: Texture2D
var title := "YOUR"
var prompt := ""
var presets: Array = []
var mode := "presets"        # "presets" or "keyboard"
var name_buf := ""
var lower := false
var cur := Vector2i(0, 0)     # keyboard cursor (col, row); row 5 = the case toggle
var sel := 0                  # preset-list cursor


func setup(tex: Texture2D, cols: int, cmap: Dictionary) -> void:
	font_tex = tex
	font_cols = cols
	charmap = cmap
	frame_tex = load("res://assets/frame.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## title = "YOUR" / "RIVAL's"; presets = preset names (first is default if blank); prompt = the
## bottom-textbox question shown next to the preset list.
func open(t: String, p: Array, q := "", skip_presets := false) -> void:
	title = t
	presets = p
	prompt = q
	mode = "keyboard" if skip_presets else "presets"   # nicknames go straight to the keyboard
	sel = 0
	name_buf = ""
	lower = false
	cur = Vector2i(0, 0)
	visible = true
	queue_redraw()


func _finish(n: String) -> void:
	visible = false
	done.emit(n)


func handle_input() -> void:
	if mode == "presets":
		_presets_input()
	else:
		_keyboard_input()


func _presets_input() -> void:
	var n := presets.size() + 1                      # NEW NAME + presets
	if Input.is_action_just_pressed("ui_up"):
		sel = (sel - 1 + n) % n
		queue_redraw()
	elif Input.is_action_just_pressed("ui_down"):
		sel = (sel + 1) % n
		queue_redraw()
	elif Input.is_action_just_pressed("ui_accept"):
		if sel == 0:
			mode = "keyboard"
			queue_redraw()
		else:
			_finish(str(presets[sel - 1]))


func _keyboard_input() -> void:
	if Input.is_action_just_pressed("ui_up"):
		cur.y = (cur.y - 1 + 6) % 6
		queue_redraw()
	elif Input.is_action_just_pressed("ui_down"):
		cur.y = (cur.y + 1) % 6
		queue_redraw()
	elif Input.is_action_just_pressed("ui_left") and cur.y < 5:
		cur.x = (cur.x - 1 + 9) % 9
		queue_redraw()
	elif Input.is_action_just_pressed("ui_right") and cur.y < 5:
		cur.x = (cur.x + 1) % 9
		queue_redraw()
	elif Input.is_action_just_pressed("ui_cancel"):
		name_buf = name_buf.substr(0, max(0, name_buf.length() - 1))
		queue_redraw()
	elif Input.is_action_just_pressed("ui_accept"):
		if cur.y == 5:                               # the lower/UPPER case toggle
			lower = not lower
			queue_redraw()
			return
		var cell := _cell(cur.y, cur.x)
		if cell == "ED":
			_finish(name_buf if name_buf != "" else str(presets[0]))
		elif name_buf.length() < NAME_MAX:
			name_buf += cell
			queue_redraw()


func _cell(r: int, c: int) -> String:
	var s: String = KB[r][c]
	return s.to_lower() if (lower and s.length() == 1 and s >= "A" and s <= "Z") else s


func _draw() -> void:
	if mode == "presets":
		# Source: TextBoxBorder at (0,0), 9x10 interior => 11x12 tiles; single-spaced list from
		# row 2 (data/maps + engine/movie/oak_speech). No full-screen clear, so an intro pic
		# beside the list (slid right) stays visible.
		var items := ["NEW NAME"] + presets
		Frame.draw(self, frame_tex, 0, 0, 11, 12, LIGHT)
		draw_rect(Rect2(24, 0, 4 * GLYPH, GLYPH), LIGHT)    # opaque title backing (not see-through)
		_str("NAME", 24, 0)                                  # title sits on the top border
		for i in items.size():
			var y := 16.0 + i * 16.0                         # double-spaced list (issue #4 reference)
			if i == sel:
				_cursor(8, y)
			_str(str(items[i]), 16, y)
		if prompt != "":                                     # the question, in the bottom textbox
			Frame.draw(self, frame_tex, 0, 96, 20, 6, LIGHT)
			var ln := prompt.split("\n")
			for i in ln.size():
				_str(str(ln[i]), 8, 112 + i * 16)
		return
	# keyboard mode (full screen)
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	_str("%s NAME?" % title, 0, 8)                           # title flush-left (naming_screen.asm 0,1)
	# Name preview at rows 2/3 (naming_screen.asm 10,2 / 10,3): typed letters on the upper row over a
	# row of underscores, with the current slot's underscore raised to mark the cursor.
	for i in NAME_MAX:
		var px := 80.0 + i * GLYPH
		if i == name_buf.length():                           # current slot: ONLY the raised underscore
			draw_rect(Rect2(px, 22, 7, 2), DARK)
		else:                                                # bold baseline underscore elsewhere
			draw_rect(Rect2(px, 30, 7, 2), DARK)
		if i < name_buf.length():
			_str(name_buf[i], px, 16)                        # typed letter (row 2)
	Frame.draw(self, frame_tex, 0, 32, 20, 11, LIGHT)
	for r in 5:
		for c in 9:
			var s := _cell(r, c)
			var px := GX + c * COLW
			var py := GY + r * ROWH
			if s == "Pk":                                    # <PK>/<MN>/ED are single ligature tiles
				_tile(97, px, py)
			elif s == "Mn":
				_tile(98, px, py)
			elif s == "ED":
				_tile(128, px, py)
			else:
				_str(s, px, py)
	_str("UPPER CASE" if lower else "lower case", GX, 122)
	if cur.y < 5:
		_cursor(GX + cur.x * COLW - 8, GY + cur.y * ROWH)
	else:
		_cursor(GX - 8, 122)


func _cursor(x: float, y: float) -> void:                    # the ▶ selection glyph (matches pokered)
	_str("▶", x, y)


func _tile(idx: int, x: float, y: float) -> void:              # draw a font tile by raw index
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
