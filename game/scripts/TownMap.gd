extends Control
## The TOWN MAP viewer (engine/items/town_map.asm DisplayTownMap). Shows the Kanto map with a
## blinking cursor over a location; UP/DOWN cycle through the locations (TownMapOrder), each showing
## its name; A/B closes. Opened from the bag's TOWN MAP item.

signal closed
signal fly_chosen(label)

const DARK := Color(0.133, 0.188, 0.224)
const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8

var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var main
var map_tex: Texture2D
var cursor_tex: Texture2D
var entries: Array = []          # [{x, y, name}, ...] in cycle order
var idx := 0
var _blink := 0.0
var _show_cursor := true
var nest_title := ""             # AREA mode: "<MON>'s NEST" with blinking nest markers
var nest_spots: Array = []       # [{x, y}] locations to mark (empty = AREA UNKNOWN)
var fly_dests: Array = []        # [{label, x, y, name}] visited towns in FLY cycle order
var _fly_mode := false
var frame_tex: Texture2D


func setup(ftex: Texture2D, cols: int, cmap: Dictionary, main_ref, data: Dictionary) -> void:
	font_tex = ftex
	font_cols = cols
	charmap = cmap
	main = main_ref
	entries = data.get("entries", [])
	map_tex = load("res://assets/town_map.png")
	cursor_tex = load("res://assets/town_map_cursor.png")
	frame_tex = load("res://assets/frame.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)


func open(start_idx: int) -> void:
	_fly_mode = false
	fly_dests = []
	nest_title = ""
	nest_spots = []
	idx = clampi(start_idx, 0, maxi(0, entries.size() - 1))
	_show_cursor = true
	_blink = 0.0
	visible = true
	set_process(true)
	queue_redraw()


## The Pokédex AREA view (TownMapSpriteBlinkingAnimation): "<MON>'s NEST" with the nest
## locations blinking; no spots shows the AREA UNKNOWN box instead.
func open_nest(title: String, spots: Array) -> void:
	_fly_mode = false
	fly_dests = []
	nest_title = title
	nest_spots = spots
	_show_cursor = true
	_blink = 0.0
	visible = true
	set_process(true)
	queue_redraw()


## FLY's picker cycles only through visited towns (pokered/engine/items/town_map.asm
## LoadTownMap_Fly and BuildFlyLocationsList). The bird/player sprites are deferred (gh #144).
func open_fly(dests: Array) -> void:
	_fly_mode = true
	fly_dests = dests
	nest_title = ""
	nest_spots = []
	idx = 0
	_show_cursor = true
	_blink = 0.0
	visible = true
	set_process(true)
	queue_redraw()


func is_fly_mode() -> bool:
	return _fly_mode


func current_fly_label() -> String:
	if not _fly_mode or idx < 0 or idx >= fly_dests.size():
		return ""
	return str(fly_dests[idx]["label"])


func handle_input() -> void:
	if _fly_mode:
		var fly_n := fly_dests.size()
		if fly_n == 0:
			_close()
			return
		if Input.is_action_just_pressed("ui_up"):
			idx = (idx + 1) % fly_n
			_tink()
		elif Input.is_action_just_pressed("ui_down"):
			idx = (idx - 1 + fly_n) % fly_n
			_tink()
		elif Input.is_action_just_pressed("ui_accept"):
			fly_chosen.emit(current_fly_label())
			visible = false
			set_process(false)
		elif Input.is_action_just_pressed("ui_cancel"):
			_close()
		return
	if nest_title != "":                     # AREA mode: any button closes
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
			_close()
		return
	var n := entries.size()
	if n == 0:
		_close()
		return
	if Input.is_action_just_pressed("ui_up"):
		idx = (idx + 1) % n
		_tink()
	elif Input.is_action_just_pressed("ui_down"):
		idx = (idx - 1 + n) % n
		_tink()
	elif Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
		_close()


func _tink() -> void:
	_show_cursor = true
	_blink = 0.0
	if main and main.audio:
		main.audio.play_sfx("tink")
	queue_redraw()


func _close() -> void:
	visible = false
	set_process(false)
	closed.emit()


func _process(delta: float) -> void:
	_blink += delta
	if _blink >= 0.4:
		_blink = 0.0
		_show_cursor = not _show_cursor
		queue_redraw()


func _draw() -> void:
	if map_tex:
		draw_texture(map_tex, Vector2.ZERO)
	if nest_title != "":                                  # the Pokédex AREA view
		draw_rect(Rect2(0, 0, 160, GLYPH + 2), LIGHT)
		_str(nest_title, 8, 1)
		if nest_spots.is_empty():
			Frame.draw(self, frame_tex, 8, 56, 18, 4, LIGHT)
			_str("AREA UNKNOWN", 32, 68)
		elif _show_cursor and cursor_tex:
			for s in nest_spots:                          # the nests blink together
				draw_texture(cursor_tex, Vector2(int(s["x"]) * 8 + 12, int(s["y"]) * 8 + 4))
		return
	if _fly_mode:
		if idx < fly_dests.size():
			var dest: Dictionary = fly_dests[idx]
			draw_rect(Rect2(0, 0, 160, GLYPH + 2), LIGHT)
			draw_rect(Rect2(0, 0, 160, GLYPH + 2), DARK, false, 1.0)
			_str("To " + str(dest["name"]), GLYPH, 1)
			if _show_cursor and cursor_tex:
				draw_texture(cursor_tex, Vector2(int(dest["x"]) * 8 + 12, int(dest["y"]) * 8 + 4))
		return
	if idx < entries.size():
		var e: Dictionary = entries[idx]
		# Location name along the top row (DisplayTownMap places it at row 0).
		draw_rect(Rect2(0, 0, 160, GLYPH + 2), LIGHT)
		draw_rect(Rect2(0, 0, 160, GLYPH + 2), DARK, false, 1.0)
		_str(str(e["name"]), GLYPH, 1)
		if _show_cursor and cursor_tex:
			# Location tile sits at screen (x*8+16, y*8+8); centre the 16px cursor on it.
			draw_texture(cursor_tex, Vector2(int(e["x"]) * 8 + 12, int(e["y"]) * 8 + 4))


func _str(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var t: int = charmap[ch]
			var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
