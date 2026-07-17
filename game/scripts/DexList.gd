extends Control
## Pokédex contents screen (engine/menus/pokedex.asm): a scrolling list of dex numbers + names on
## the left (a poké-ball dot beside owned mons), a vertical divider, and SEEN/OWN counts over a
## DATA / CRY / AREA / QUIT side menu. Up/Down scroll the list; A opens the side menu on a seen mon;
## B backs out / closes.

signal closed

const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8
const VISIBLE := 7            # list rows shown at once
const SIDE_ITEMS := ["DATA", "CRY", "AREA", "QUIT"]

var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var main

var scroll := 0              # dex index at the top of the window
var cursor := 0              # highlighted row within the window (0..VISIBLE-1)
var focus := "list"          # "list" or "menu"
var menu_cur := 0            # DATA/CRY/AREA/QUIT


var dex_tiles: Texture2D          # the dex screens' own tile row ($60-$7a; gh #152)
var _repeat_t := 0.0              # held up/down auto-repeat (the hJoy7 low-sensitivity joypad)


func setup(tex: Texture2D, cols: int, cmap: Dictionary, game) -> void:
	font_tex = tex
	font_cols = cols
	charmap = cmap
	main = game
	dex_tiles = load("res://assets/dex_tiles.png")
	visible = false


func open() -> void:
	scroll = 0
	cursor = 0
	focus = "list"
	menu_cur = 0
	visible = true
	queue_redraw()


func _sel_species() -> String:
	var i := scroll + cursor
	return str(main.dex_order[i]) if i < main.dex_order.size() else ""


## The highest dex index the player has SEEN (wDexMaxSeenMon): the list neither draws nor
## scrolls past it — everything below the last seen mon simply doesn't exist yet (gh #152).
func _max_index() -> int:
	var hi := 0
	for i in main.dex_order.size():
		if main.pokedex_seen.has(str(main.dex_order[i])):
			hi = i
	return hi


func handle_input() -> void:
	if focus == "list":
		# Held up/down auto-repeats: the dex list polls the low-sensitivity joypad (hJoy7 = 1),
		# which re-fires a held direction every 6 frames (gh #152).
		var held := 0
		if Input.is_action_pressed("ui_down"):
			held = 1
		elif Input.is_action_pressed("ui_up"):
			held = -1
		if held != 0:
			if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("ui_up"):
				_repeat_t = -0.35              # the fresh press acts now; repeats follow the delay
				_move(held)
			else:
				_repeat_t += get_process_delta_time()
				if _repeat_t >= 6.0 / 60.0:
					_repeat_t = 0.0
					_move(held)
			return
		if Input.is_action_just_pressed("ui_right"):
			_page(7)                           # .checkIfRightPressed: a page of 7 down
		elif Input.is_action_just_pressed("ui_left"):
			_page(-7)                          # .checkIfLeftPressed: a page of 7 up
		elif Input.is_action_just_pressed("ui_accept"):
			if main.pokedex_seen.has(_sel_species()):     # side menu only opens on a seen mon
				focus = "menu"
				menu_cur = 0
				queue_redraw()
		elif Input.is_action_just_pressed("ui_cancel"):
			visible = false
			closed.emit()
	else:
		if Input.is_action_just_pressed("ui_down"):
			menu_cur = (menu_cur + 1) % SIDE_ITEMS.size(); queue_redraw()
		elif Input.is_action_just_pressed("ui_up"):
			menu_cur = (menu_cur - 1 + SIDE_ITEMS.size()) % SIDE_ITEMS.size(); queue_redraw()
		elif Input.is_action_just_pressed("ui_cancel"):
			focus = "list"; queue_redraw()
		elif Input.is_action_just_pressed("ui_accept"):
			await _side_select()


func _move(d: int) -> void:
	var n: int = _max_index() + 1
	var idx := clampi(scroll + cursor + d, 0, n - 1)
	# keep the cursor in [0, VISIBLE-1], scrolling the window otherwise
	if idx < scroll:
		scroll = idx
		cursor = 0
	elif idx >= scroll + VISIBLE:
		scroll = idx - VISIBLE + 1
		cursor = VISIBLE - 1
	else:
		cursor = idx - scroll
	queue_redraw()


## Left/right page the WINDOW by 7 while the cursor row stays put, clamped so the last window
## ends exactly at the highest seen mon; a shorter-than-a-window list doesn't page at all.
func _page(d: int) -> void:
	var n: int = _max_index() + 1
	if n < VISIBLE:
		return
	scroll = clampi(scroll + d, 0, n - VISIBLE)
	cursor = mini(cursor, n - 1 - scroll)
	queue_redraw()


func _side_select() -> void:
	var sp := _sel_species()
	match menu_cur:
		0:                                                 # DATA
			visible = false                                # the list sits ABOVE the entry in the
			await main.show_dex_entry(sp, main.pokedex_owned.has(sp))   # tree - hide it (gh #30)
			main.modal = self                              # restore the list as the modal (entry cleared it)
			visible = true; queue_redraw()
		1:                                                 # CRY
			if main.audio:
				main.audio.play_cry(sp)
		2:                                                 # AREA: the nest map (TownMapNestIcons)
			main.show_nest(sp)
			await main.townmap.closed
			main.modal = self
			visible = true; queue_redraw()
		3:                                                 # QUIT -> back to the START menu
			visible = false
			closed.emit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	_str("CONTENTS", 8, 8)
	var n: int = _max_index() + 1                          # rows past the last seen mon don't draw
	for r in VISIBLE:
		var i := scroll + r
		if i >= n:
			break
		var sp: String = str(main.dex_order[i])
		var ynum := 16.0 + r * 16.0                        # number row
		var yname := ynum + 8.0                            # name row (indented)
		_str("%03d" % (i + 1), 8, ynum)
		if main.pokedex_owned.has(sp):                     # the $72 poké-ball tile marks owned mons
			_dtile(0x72, 24, yname)
		if main.pokedex_seen.has(sp):
			_str(main.mon_display_name(sp), 32, yname)
		else:
			_str("----------", 32, yname)                  # .dashedLine, ten font dashes
		if focus == "list" and r == cursor:
			_cursor(0, yname)                              # cursor sits on the name row, not the number
	# The rail at column 14: the $71 vertical-line tile, with the $70 box tile on every even row
	# below the top (DrawPokedexVerticalLine alternates them down both halves; gh #152).
	for row in 18:
		_dtile(0x70 if row % 2 == 0 and row > 0 else 0x71, 112, row * 8)
	# SEEN / OWN counts, the '─' separator row (five $7a font tiles at 15,8), and the side menu
	_str("SEEN", 128, 16)
	_str("%3d" % main.pokedex_seen.size(), 128, 24)
	_str("OWN", 128, 40)
	_str("%3d" % main.pokedex_owned.size(), 128, 48)
	for c in 5:
		_dtile(0x7a, 120 + c * 8, 64)
	for m in SIDE_ITEMS.size():
		_str(SIDE_ITEMS[m], 128, 80 + m * 16)
		if focus == "menu" and m == menu_cur:
			_cursor(120, 80 + m * 16)


func _dtile(vram: int, x: float, y: float) -> void:       # a dex_tiles.png tile by VRAM id
	draw_texture_rect_region(dex_tiles, Rect2(x, y, 8, 8), Rect2((vram - 0x60) * 8, 0, 8, 8))


func _cursor(x: float, y: float) -> void:                    # ▶ selection glyph (matches pokered)
	_str("▶", x, y)


func _str(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var t: int = charmap[ch]
			var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
