extends Control
## Pokémon stats/summary screen (engine/pokemon/status_screen.asm). Two pages:
##   1: pic, No., name/:L/HP bar/status, ATTACK..SPECIAL box, TYPE1(/2), IDNo, OT
##   2: pic, No., name, EXP POINTS, LEVEL UP (to next), and the four moves with PP
## A advances page 1 -> 2 -> closes; B closes (back to the party screen).

signal closed

const DARK := Color(0.133, 0.188, 0.224)
const LIGHT := Color(0.918, 0.984, 0.808)
# The HP-bar fill is GB shade 2, a step LIGHTER than the black outline (gh #155; see Menu.HPFILL).
const HPFILL := Color(0.396, 0.541, 0.447)
const GLYPH := 8

var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var frame_tex: Texture2D
var fbe_tex: Texture2D            # condensed glyphs: :L=12, to=14, HP=15, ID=17, No=18, wedge=22
var hud_tex: Texture2D            # the battle-HUD strip (the "HP:" pair = tiles 15+0)
var _boldp_tex: Texture2D         # the bold P (the "PP" label)
var main

var mon: Dictionary
var page := 0
var _pic: Texture2D
var _num := 0


func setup(tex: Texture2D, cols: int, cmap: Dictionary, game) -> void:
	font_tex = tex
	font_cols = cols
	charmap = cmap
	frame_tex = load("res://assets/frame.png")
	fbe_tex = load("res://assets/font_battle_extra.png")
	hud_tex = load("res://assets/battle_hud.png")
	_boldp_tex = load("res://assets/bold_p.png")
	main = game
	visible = false


func open(m: Dictionary) -> void:
	mon = m
	page = 0
	_pic = load("res://assets/pokemon/front/%s.png" % str(m["species"]))
	_num = main.dex_order.find(str(m["species"])) + 1
	visible = true
	queue_redraw()


func handle_input() -> void:
	if Input.is_action_just_pressed("ui_accept"):
		if page == 0:                     # A: next page, then out (StatusScreen -> StatusScreen2)
			page = 1
			queue_redraw()
		else:
			visible = false
			closed.emit()
	elif Input.is_action_just_pressed("ui_cancel"):
		visible = false
		closed.emit()


func _glyph(t: int, x: float, y: float) -> void:
	draw_texture_rect_region(fbe_tex, Rect2(x, y, 8, 8), Rect2((t % 15) * 8, (t / 15) * 8, 8, 8))


func _hud(t: int, x: float, y: float) -> void:
	draw_texture_rect_region(hud_tex, Rect2(x, y, 8, 8), Rect2(t * 8, 0, 8, 8))


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	if _pic:                                              # flipped front sprite, tile-centred
		var w := _pic.get_width()                         # in the 7x7 box, bottom-anchored
		var px := 8.0 + 8.0 * floorf((7.0 - w / 8.0) / 2.0)
		draw_set_transform(Vector2(px + w, 56.0 - _pic.get_height()), 0, Vector2(-1, 1))
		draw_texture(_pic, Vector2.ZERO)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_glyph(18, 8, 56)                                     # the "No" glyph + its tiny dot
	draw_rect(Rect2(18, 61, 2, 2), DARK)
	_str("%03d" % _num, 24, 56)
	_str(str(mon["name"]), 72, 8)
	# the top-right bracket (profiled from the reference): the 2px divider at y=59-60 with
	# its stepped wedge climbing into the left end
	draw_rect(Rect2(66, 59, 91, 1), DARK)
	draw_rect(Rect2(64, 60, 92, 1), DARK)
	draw_rect(Rect2(70, 57, 2, 1), DARK)
	draw_rect(Rect2(68, 58, 4, 1), DARK)
	draw_rect(Rect2(155, 8, 2, 51), DARK)                 # the top bracket's right edge
	if page == 0:
		# page 1 adds a second bracket: TYPE1 down the right edge into a mirrored bottom rail
		draw_rect(Rect2(155, 72, 2, 68), DARK)
		draw_rect(Rect2(98, 139, 59, 1), DARK)
		draw_rect(Rect2(96, 140, 60, 1), DARK)
		draw_rect(Rect2(102, 137, 2, 1), DARK)
		draw_rect(Rect2(100, 138, 4, 1), DARK)
		_page1()
	else:
		_page2()


func _page1() -> void:
	_glyph(12, 112, 16)                                   # the ":L" tile
	_str(str(int(mon["level"])), 120, 16)
	_hud(15, 88, 24)                                      # the exact "HP:" pair
	_hud(0, 96, 24)
	var frac: float = clampf(float(mon["hp"]) / maxf(1.0, float(mon["maxhp"])), 0.0, 1.0)
	draw_rect(Rect2(104, 26, 48, 1), DARK)                # the Gen-1 pill bar
	draw_rect(Rect2(104, 29, 48, 1), DARK)
	draw_rect(Rect2(103, 27, 1, 2), DARK)
	draw_rect(Rect2(152, 27, 1, 2), DARK)
	draw_rect(Rect2(104, 27, maxf(1.0 if int(mon["hp"]) > 0 else 0.0, floorf(48.0 * frac)), 2), HPFILL)
	_str("%3d/" % int(mon["hp"]), 96, 32)
	_str("%3d" % int(mon["maxhp"]), 128, 32)
	var st := str(mon.get("status", ""))
	_str("STATUS/", 72, 48)
	_str(st.to_upper() if st != "" else "OK", 128, 48)
	# stats box (bottom-left, 10 tiles wide), values right-aligned inside it
	Frame.draw(self, frame_tex, 0, 64, 10, 10, LIGHT)
	var labels := ["ATTACK", "DEFENSE", "SPEED", "SPECIAL"]
	var vals := [int(mon["atk"]), int(mon["def"]), int(mon["spd"]), int(mon["spc"])]
	for i in 4:
		_str(labels[i], 8, 72 + i * 16)
		_str("%3d" % vals[i], 48, 80 + i * 16)
	# types / ID / OT down the right side (no box)
	var types: Array = mon["types"]
	_str("TYPE1/", 80, 72)
	_str(str(types[0]), 88, 80)
	if types.size() > 1 and str(types[1]) != str(types[0]):
		_str("TYPE2/", 80, 88)
		_str(str(types[1]), 88, 96)
	_glyph(17, 80, 104)                                   # "ID"
	_glyph(18, 88, 104)                                   # "No"
	_str("/", 96, 104)
	_str("%5d" % main.player_id, 96, 112)
	_str("OT/", 80, 120)
	_str(str(mon.get("ot", main.player_name)), 96, 128)


func _page2() -> void:
	_str("EXP POINTS", 72, 24)
	_str("%9d" % int(mon["exp"]), 80, 32)
	_str("LEVEL UP", 72, 40)
	var to_next: int = maxi(0, main.exp_for_level(int(mon["level"]) + 1,
		str(mon.get("growth", "medium_fast"))) - int(mon["exp"]))
	var ns := str(to_next)
	_str(ns, 112 - ns.length() * 8, 48)                   # right-aligned before the "to" glyph
	_glyph(14, 112, 48)                                   # the small "to"
	_glyph(12, 128, 48)                                   # ":L"
	_str(str(int(mon["level"]) + 1), 136, 48)
	# the moves box: full width, name rows + PP rows
	Frame.draw(self, frame_tex, 0, 64, 20, 10, LIGHT)
	var mvs: Array = mon["moves"]
	for i in 4:
		var y := 72 + i * 16
		if i < mvs.size():
			var mv: String = str(mvs[i]["move"])
			_str(str(main.mon_moves[mv]["name"]) if main.mon_moves.has(mv) else mv, 16, y)
			if _boldp_tex:                                # the bold-P pair (char $72, P.1bpp)
				draw_texture(_boldp_tex, Vector2(88, y + 8))
				draw_texture(_boldp_tex, Vector2(96, y + 8))
			else:
				_str("PP", 88, y + 8)
			_str("%2d/%2d" % [int(mvs[i]["pp"]), int(mvs[i]["maxpp"])], 112, y + 8)
		else:
			_str("-", 16, y)
			draw_rect(Rect2(89, y + 12, 6, 1), DARK)      # the bold "--" under the PP column
			draw_rect(Rect2(96, y + 12, 6, 1), DARK)


func _str(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var t: int = charmap[ch]
			var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
