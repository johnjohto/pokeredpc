extends Control
## The in-game trade movie (engine/movie/trade.asm + trade2.asm, the InternalClockTradeAnim
## sequence — the player's Game Boy on the left). Beats, in order: the outgoing mon's info
## card + flipped pic slide in from the right; poof -> the ball drops, the cry plays; the
## open cable end appears (SFX_HEAL_HP); the ball shakes then rolls into the cable
## (SFX_TINK per 4px, the cable bulging); the circled party icon crawls the cable from the
## left Game Boy to the right one (the screen scrolling under it, the BG flashing
## BGP^$3c every 8 frames); the farewell texts; the received mon crawls back; the cable
## end again, the ball tilts out, and the incoming mon's card + pic + poof + cry close it.
## Time is tracked in scaled frames (delta*60), so battle turbo/time_scale speed it up.

const LIGHT := Color(0.918, 0.984, 0.808)
const DARK := Color(0.133, 0.188, 0.224)
const GLYPH := 8
const CRAWL_H := 128.0             # 16 units x 8 frames: the 256 px horizontal scroll
const CRAWL_V := 64.0              # 8 vertical/edge steps x 8 frames

var main
var battle                         # the anim-data player (_build_move_anim / _manim_tex)
var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var fbe_tex: Texture2D             # condensed glyphs: ID=17, No=18
var frame_tex: Texture2D
var tiles_tex: Texture2D           # trade_tiles.png (game_boy + link_cable strip, 16/row)
var tiles_flash_tex: Texture2D     # the same strip under BGP^$3c (shades 1<->2 swapped)
var gfx_maps: Dictionary = {}      # trade_gfx.json: game_boy / link_cable tilemaps
var ball_texs: Array = []          # 16x16 ball quads: [tile $7e, tile $7f (bulge)]
var bubble_tex: Texture2D          # trade_bubble.png (16x32: circle, oval)
var icons_tex: Texture2D
var icons_map: Dictionary = {}

var _phase := ""
var _t := 0.0                      # scaled frames since the phase began
var _state: Dictionary = {}
var _anim_sprites: Array = []      # a ball anim's current frame (battle sprite-list format)
var _tink_step := -1


func setup(m, ft: Texture2D, cols: int, cmap: Dictionary, b) -> void:
	main = m
	battle = b
	font_tex = ft
	font_cols = cols
	charmap = cmap
	fbe_tex = load("res://assets/font_battle_extra.png")
	frame_tex = load("res://assets/frame.png")
	tiles_tex = load("res://assets/trade_tiles.png")
	tiles_flash_tex = _flash_variant(tiles_tex)
	gfx_maps = ProjectData.legacy("trade_gfx.json")     # gh #25: data rides the project
	ball_texs = [_quad_of(load("res://assets/trade_ball.png"), 2), _quad_of(load("res://assets/trade_ball.png"), 3)]
	bubble_tex = load("res://assets/trade_bubble.png")
	icons_tex = load("res://assets/mon_icons.png")
	icons_map = ProjectData.legacy("mon_icons.json")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## BGP xor $3c swaps shades 1 and 2 (%11100100 -> %11011000) — the cable-flash palette.
func _flash_variant(tex: Texture2D) -> Texture2D:
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.is_equal_approx(main.GB_SHADES[1]):
				img.set_pixel(x, y, main.GB_SHADES[2])
			elif c.is_equal_approx(main.GB_SHADES[2]):
				img.set_pixel(x, y, main.GB_SHADES[1])
	return ImageTexture.create_from_image(img)


## A 16x16 quad of one 8x8 tile from trade_ball.png mirrored 4 ways (the OAM block).
func _quad_of(tex: Texture2D, tile: int) -> Texture2D:
	var src: Image = tex.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var t := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	t.blit_rect(src, Rect2i((tile % 2) * 8, (tile / 2) * 8, 8, 8), Vector2i.ZERO)
	var q := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	q.blit_rect(t, Rect2i(0, 0, 8, 8), Vector2i.ZERO)
	var fx := t.duplicate(); fx.flip_x()
	q.blit_rect(fx, Rect2i(0, 0, 8, 8), Vector2i(8, 0))
	var fy := t.duplicate(); fy.flip_y()
	q.blit_rect(fy, Rect2i(0, 0, 8, 8), Vector2i(0, 8))
	var fxy := t.duplicate(); fxy.flip_x(); fxy.flip_y()
	q.blit_rect(fxy, Rect2i(0, 0, 8, 8), Vector2i(8, 8))
	return ImageTexture.create_from_image(q)


func _process(delta: float) -> void:
	if _phase == "":
		return
	_t += delta * 60.0
	if _phase == "ball_roll":                     # SFX_TINK per 4px step (Delay3 apart)
		var step := int(_t / 3.0)
		if step != _tink_step and 88 + step * 4 < 152:
			_tink_step = step
			if main.audio:
				main.audio.play_sfx("tink")
	queue_redraw()


func _wait(frames: float) -> void:
	while _t < frames:
		await get_tree().process_frame


func _begin(phase: String) -> void:
	_phase = phase
	_t = 0.0
	queue_redraw()


## The full internal-clock movie. give/get: species slugs; the info cards read OT/ID.
## `partner` is the person across the cable (the farewell texts); `get_ot` is the incoming
## mon's card OT. NPC trades keep the cartridge's "TRAINER" defaults; link trades pass the
## partner's real name and the record's OT (gh #6 playtest).
var partner_label := "TRAINER"     # the right Game Boy's name box (link: the partner)


func play(give_sp: String, give_ot: String, give_otid: int, get_sp: String, get_otid: int,
		partner := "TRAINER", get_ot := "TRAINER") -> void:
	visible = true
	partner_label = partner
	var give_name: String = main.mon_display_name(give_sp)
	var get_name: String = main.mon_display_name(get_sp)
	# 1) Trade_ShowPlayerMon: the card + flipped pic slide in from the right, poof, ball
	#    drop, cry.
	_state = {"species": give_sp, "ot": give_ot, "otid": give_otid,
		"pic": load("res://assets/pokemon/front/%s.png" % give_sp), "hide_pic": false,
		"box_y": 80.0}
	_begin("show_mon")
	await _wait(63)                               # WX/SCX $7e -> 0 at 2 px/frame
	await _wait(63 + 80)                          # Trade_Delay80
	await _ball_anim("TRADE_BALL_POOF_ANIM")
	_state["hide_pic"] = true                     # TRADE_BALL_DROP_ANIM "clears mon pic"
	await _ball_anim("TRADE_BALL_DROP_ANIM")
	if main.audio:
		main.audio.play_cry(give_sp)
	# 2) Trade_DrawOpenEndOfLinkCable.
	_begin("cable_end")
	if main.audio:
		main.audio.play_sfx("heal_hp")
	await _wait(10)
	# 3) Trade_AnimateBallEnteringLinkCable: shake, then roll right into the cable.
	await _ball_anim("TRADE_BALL_SHAKE_ANIM")
	await _wait(_t + 10)
	_tink_step = -1
	_begin("ball_roll")
	await _wait(48)                               # x $60 -> $a0 in 4px steps, Delay3 each
	# 4) the crawl, left GB -> right GB.
	_state = {"dir": 1, "species": give_sp}
	_begin("crawl")
	await _wait(CRAWL_H + CRAWL_V)
	# 5) the farewell texts on a cleared window.
	_begin("text")
	await _movie_text("%s went\nto %s." % [give_name, partner], 200)
	await _movie_text("For %s's\n%s," % [main.player_name, give_name], 80)
	await _movie_text("%s sends\n%s." % [partner, get_name], 80)
	await _movie_text("%s waves\nfarewell as" % partner, 80)
	await _movie_text("%s is\ntransferred." % get_name, 80)
	# 6) the crawl back, right GB -> left GB, with the received mon's icon.
	_state = {"dir": -1, "species": get_sp}
	_begin("crawl")
	await _wait(CRAWL_V + CRAWL_H)
	# 7) the cable end again; the ball tilts out; the incoming mon's card + poof + cry.
	_begin("cable_end")
	if main.audio:
		main.audio.play_sfx("heal_hp")
	await _wait(10)
	await _ball_anim("TRADE_BALL_TILT_ANIM")
	_state = {"species": get_sp, "ot": get_ot, "otid": get_otid,
		"pic": load("res://assets/pokemon/front/%s.png" % get_sp), "hide_pic": false,
		"box_y": 80.0}
	_begin("show_mon")
	_t = 63.0                                     # no slide: the card is drawn in place
	await _ball_anim("TRADE_BALL_POOF_ANIM")
	if main.audio:
		main.audio.play_cry(get_sp)
	await _wait(63 + 100)                         # Trade_Delay100
	# ClearScreenArea (4,10) 8x12 wipes the CARD before the farewell prints — the pic stays.
	# Leaving it drew the text box over the card's body, a floating-border mess (playtest).
	_state["hide_box"] = true
	queue_redraw()
	await _movie_text("Take good care of\n%s." % get_name, 80)
	_phase = ""
	visible = false


func _ball_anim(nm: String) -> void:
	for st in battle._build_move_anim(nm, true):
		if st.has("se"):                          # trade anims carry no special effects
			continue
		_anim_sprites = st["sprites"]
		queue_redraw()
		await get_tree().create_timer(maxf(1.0 / 60.0, float(st.get("wait", 0.05)))).timeout
	_anim_sprites = []
	queue_redraw()


## A movie text: instant print (BIT_NO_TEXT_DELAY), no button — it holds `frames`, then
## clears (Trade_SlideTextBoxOffScreen's outcome, without the WX slide).
func _movie_text(s: String, frames: float) -> void:
	main.textbox.show_text(s)
	main.textbox.revealed = 999.0
	main.textbox.held = true                      # suppress the ▼ (no input is waited on)
	_t = 0.0
	await _wait(frames)
	main.textbox.visible = false
	main.textbox.held = false


# ---- drawing ---------------------------------------------------------------

func _tile(idx: int, x: float, y: float, flash := false) -> void:
	var tex := tiles_flash_tex if flash else tiles_tex
	draw_texture_rect_region(tex, Rect2(x, y, 8, 8), Rect2((idx % 16) * 8, (idx / 16) * 8, 8, 8))


func _tilemap(name: String, tx: float, ty: float, flash := false) -> void:
	var m: Dictionary = gfx_maps[name]
	var w := int(m["w"])
	var ids: Array = m["ids"]
	for i in ids.size():
		_tile(int(ids[i]), tx + (i % w) * 8, ty + (i / w) * 8, flash)


func _str(s: String, x: float, y: float) -> void:
	var cx := x
	for ch in s:
		if ch != " " and charmap.has(ch):
			var t: int = charmap[ch]
			draw_texture_rect_region(font_tex, Rect2(cx, y, GLYPH, GLYPH),
				Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH))
		cx += GLYPH


func _fbe(t: int, x: float, y: float) -> void:
	draw_texture_rect_region(fbe_tex, Rect2(x, y, 8, 8), Rect2((t % 15) * 8, (t / 15) * 8, 8, 8))


## The mon info card (Trade_PrintPlayerMonInfoText): the "──№.<dex>" run ON the top
## border, the species name, OT and 5-digit ID (LEADING_ZEROES).
func _info_box(x: float, y: float, sp: String, ot: String, otid: int) -> void:
	Frame.draw(self, frame_tex, x, y, 12, 8, LIGHT)
	draw_rect(Rect2(x + 24, y, 40, 8), LIGHT)     # "№.NNN" replaces part of the border run
	_fbe(18, x + 24, y)                           # №
	draw_rect(Rect2(x + 34, y + 5, 2, 2), DARK)   # its tiny dot
	_str("%03d" % (int(main.dex_order.find(sp)) + 1), x + 40, y)
	_str(main.mon_display_name(sp), x + 8, y + 16)
	_str("OT/", x + 8, y + 32)
	_str(ot, x + 32, y + 32)
	_fbe(17, x + 8, y + 48)                       # ID
	_fbe(18, x + 16, y + 48)                      # №
	draw_rect(Rect2(x + 26, y + 53, 2, 2), DARK)
	_str("%05d" % (otid % 65536), x + 32, y + 48)


func _draw_flipped_pic(pic: Texture2D, dx: float) -> void:
	if pic == null:
		return
	var w := pic.get_width()
	var px := 56.0 + dx + 8.0 * floorf((7.0 - w / 8.0) / 2.0)
	draw_set_transform(Vector2(px + w, 16.0 + 56.0 - pic.get_height()), 0, Vector2(-1, 1))
	draw_texture(pic, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_anim_sprites() -> void:
	for s in _anim_sprites:
		var tile := int(s[1])
		var src := Rect2((tile & 15) * 8, (tile >> 4) * 8, 8, 8)
		draw_set_transform(Vector2(int(s[2]) + (8 if s[4] else 0), int(s[3]) + (8 if s[5] else 0)),
			0.0, Vector2(-1.0 if s[4] else 1.0, -1.0 if s[5] else 1.0))
		draw_texture_rect_region(battle._manim_tex[s[0]], Rect2(0, 0, 8, 8), src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	match _phase:
		"show_mon":
			var dx: float = maxf(0.0, 126.0 - 2.0 * _t)
			if not bool(_state["hide_pic"]):
				_draw_flipped_pic(_state["pic"], dx)
			if not bool(_state.get("hide_box", false)):
				_info_box(32.0 + dx, float(_state["box_y"]), str(_state["species"]),
					str(_state["ot"]), int(_state["otid"]))
		"cable_end":
			_tilemap("link_cable", 48, 16)
		"ball_roll":
			_tilemap("link_cable", 48, 16)
			var step := int(_t / 3.0)
			var bx := 88.0 + step * 4.0
			if bx < 152.0:
				draw_texture(ball_texs[step % 2], Vector2(bx, 16))
		"crawl":
			_draw_crawl()
	_draw_anim_sprites()


## The Game Boy screens joined by a 256 px cable strip; the circled icon holds still while
## the strip scrolls, then walks the cable stub at the edge (Trade_AnimMonMoveVertical).
func _draw_crawl() -> void:
	var dir := int(_state["dir"])
	var k := int(_t / 8.0)
	var alt := k % 2 == 1                         # icon frame + bubble frame + BGP flash
	var o: float                                  # strip x at the screen's left edge
	var icon := Vector2(92, 28)                   # base ($54,$1c): circle TL (84,20)
	if dir == 1:
		o = minf(256.0, 2.0 * _t)
		if _t > CRAWL_H:                          # the edge walk: right 16, then down 40
			var s := minf(8.0, (_t - CRAWL_H) / 8.0)
			icon += Vector2(minf(s, 4.0) * 4.0, maxf(0.0, s - 4.0) * 10.0)
	else:
		# base ($64,$44), same OAM->screen mapping as the send's ($54,$1c)->(92,28):
		# TL (108,68), so the icon sits centered on the right GB's cable mouth (y 72-80)
		# and the up-40 walk lands it exactly on the tube row like the send side.
		# (It rode 8 px below the pipe the whole receive leg — playtest report.)
		icon = Vector2(108, 68)
		if _t <= CRAWL_V:                         # up 40, then left 16, before the scroll
			var s := minf(8.0, _t / 8.0)
			icon += Vector2(-maxf(0.0, s - 4.0) * 4.0, -minf(s, 4.0) * 10.0)
			o = 256.0
		else:
			icon += Vector2(-16, -40)
			o = maxf(0.0, 256.0 - 2.0 * (_t - CRAWL_V))
	# the left GB screen (strip 0..160)
	_draw_left_gb(-o, alt)
	# the connecting cable row (strip 160..256, row 4)
	for cx in range(160, 256, 8):
		_tile(45, cx - o, 32, alt)                # $5e horizontal cable
	# the right GB screen (strip 256..416)
	_draw_right_gb(256.0 - o, alt)
	# the 32x32 bubble (mirrored quads) first, the icon over it — the icon's lower OAM
	# slots win on the DMG (WriteMonPartySpriteOAMBySpecies before Trade_WriteCircleOAMBlock)
	var bf := 16.0 if alt else 0.0
	var btl := icon + Vector2(-8, -8)
	draw_texture_rect_region(bubble_tex, Rect2(btl.x, btl.y, 16, 16), Rect2(0, bf, 16, 16))
	draw_set_transform(Vector2(btl.x + 32, btl.y), 0, Vector2(-1, 1))
	draw_texture_rect_region(bubble_tex, Rect2(0, 0, 16, 16), Rect2(0, bf, 16, 16))
	draw_set_transform(Vector2(btl.x, btl.y + 32), 0, Vector2(1, -1))
	draw_texture_rect_region(bubble_tex, Rect2(0, 0, 16, 16), Rect2(0, bf, 16, 16))
	draw_set_transform(Vector2(btl.x + 32, btl.y + 32), 0, Vector2(-1, -1))
	draw_texture_rect_region(bubble_tex, Rect2(0, 0, 16, 16), Rect2(0, bf, 16, 16))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var sp := str(_state["species"])
	if icons_map.has(sp):
		draw_texture_rect_region(icons_tex, Rect2(icon.x, icon.y, 16, 16),
			Rect2(int(icons_map[sp]) * 16, (16.0 if alt else 0.0), 16, 16))


func _draw_left_gb(o: float, flash: bool) -> void:
	_tilemap("game_boy", o + 40, 24, flash)       # the GAME BOY pic at (5,3)
	_tile(44, o + 88, 32, flash)                  # $5d open cable end at (11,4)
	for i in 8:
		_tile(45, o + 96 + i * 8, 32, flash)      # $5e x8
	Frame.draw(self, frame_tex, o + 32, 96, 9, 4, LIGHT)   # the name box at (4,12)
	_str(main.player_name, o + 40, 112)


func _draw_right_gb(o: float, flash: bool) -> void:
	for i in 14:
		_tile(45, o + i * 8, 32, flash)           # cable row 4, cols 0-13
	_tile(46, o + 112, 32, flash)                 # $5f corner at (14,4)
	for r in 4:
		_tile(48, o + 112, 40 + r * 8, flash)     # $61 vertical, rows 5-8
	_tile(47, o + 112, 72, flash)                 # $60 bend at (14,9)
	_tile(44, o + 104, 72, flash)                 # $5d open end at (13,9)
	_tilemap("game_boy", o + 56, 64, flash)       # the GAME BOY pic at (7,8)
	Frame.draw(self, frame_tex, o + 48, 0, 9, 4, LIGHT)    # the name box at (6,0)
	_str(partner_label, o + 56, 16)              # the partner's GB (link: their real name)
