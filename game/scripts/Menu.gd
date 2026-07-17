extends Control
## Reusable cursor list menu (start menu, yes/no, etc.). Draws a bordered box of
## items with a ▶ cursor; up/down to move, A to choose, B to cancel.
##
## Input is driven by Player via handle_input() (one action per frame) so opening
## and closing a menu can't double-fire on the same keypress.
##
## Like pokered's shared tilemap, boxes can stack: push_under() freezes the current
## box (its cursor turned to the hollow ▷, PlaceUnfilledArrowMenuCursor) and a
## submenu opened with keep_under draws over it — the bag over the start menu,
## USE/TOSS over the bag (gh #66).

signal chosen(index: int)   # selected item index, or -1 on cancel
signal selected(index: int) # SELECT pressed on a row (for reordering, e.g. the bag)

const DARK := Color(0.133, 0.188, 0.224)
const LIGHT := Color(0.918, 0.984, 0.808)
# The HP-bar fill is GB shade 2, a step LIGHTER than the black outline: font_battle_extra.png's
# full-segment tile ($6b) fills rows 3-4 with 2bpp colour 2 under the identity BGP $e4 (gh #155).
const HPFILL := Color(0.396, 0.541, 0.447)
const ROW := 16
const PAD := 8
const GLYPH := 8
const MAX_VISIBLE := 7      # taller lists scroll a window of this many rows
const LIST_VISIBLE := 4     # the ITEMLISTMENU window (home/list_menu.asm prints 4 names)

var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var frame_tex: Texture2D
var items: Array = []
var cursor := 0
var scroll := 0            # index of the top visible row (for lists > MAX_VISIBLE)
var swap_mark := -1        # a row "held" by SELECT for reordering (-1 = none)
var origin := Vector2.ZERO
# Quantity-picker mode (Poké Mart): up/down change a count, A emits it, B emits -1.
var qty_mode := false
var qty := 1
var qty_max := 1
var qty_unit := 0          # unit price (or sell value) for the running total
# Party mode (POKéMON menu): each row shows the mon's name/level/status + an HP bar and HP number.
var party_mode := false
# TMHM_PARTY_MENU (teaching a TM/HM): one ABLE/NOT-ABLE bool per mon replaces the HP bar + status,
# so you can see who can learn the move (party_menu.asm .teachMoveMenu). Empty = the normal menu.
var teach_flags: Array = []
var party: Array = []
var full_bg := false       # clear the whole screen to LIGHT first (title CONTINUE/NEW GAME menu)
var box_w := 0             # force a box width in tiles (0 = auto-fit to the items)
var box_h := 0             # force a box height in tiles (0 = auto: visible rows * 2 + 1)
var row0 := 1              # first text row inside the box, in tiles (start/item menus use 2)
var single_spaced := false # place list rows 1 tile apart (PlaceString + BIT_SINGLE_SPACED_LINES)
var under: Array = []      # frozen parent boxes drawn beneath (the Gen-1 shared-tilemap look)
var hollow := false        # draw the cursor as the hollow ▷ (PlaceUnfilledArrowMenuCursor)
var list_mode := false     # ITEMLISTMENU: fixed 16x11 box at (4,2), 4 rows, ×NN quantities
var qtys: Array = []       # list_mode: per-row quantity (-1 = none printed, e.g. key items)
var save_info := {}        # {player,badges,dex,time} -> draw the save-screen info box + prompt
var version := ""          # shown bottom-left on the title main menu (gh #50)
var mon_icons_tex: Texture2D  # 10 party-menu icons (16x16 each)
var mon_icons_map := {}    # species -> icon index in mon_icons_tex
var fbe_tex: Texture2D     # condensed glyphs (font_battle_extra: HP/:L/ID/No + bar pieces)
var hud_tex: Texture2D     # the battle-HUD tile strip (the party "HP:" pair)
var keep_party := false    # draw the party screen behind this menu (the STATS/SWITCH submenu)
var party_sel := 0         # the mon the submenu is open for (hollow cursor on its row)


func setup(tex: Texture2D, cols: int, cmap: Dictionary) -> void:
	font_tex = tex
	font_cols = cols
	charmap = cmap
	frame_tex = load("res://assets/frame.png")
	fbe_tex = load("res://assets/font_battle_extra.png")
	hud_tex = load("res://assets/battle_hud.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func open(opts: Array, at: Vector2, keep_under := false) -> void:
	if not keep_under:
		under.clear()
	items = opts
	cursor = 0
	scroll = 0
	swap_mark = -1
	origin = at
	qty_mode = false
	party_mode = false
	keep_party = false
	hollow = false
	list_mode = false
	qtys = []
	full_bg = false
	box_w = 0
	box_h = 0
	row0 = 1
	single_spaced = false
	save_info = {}
	version = ""
	visible = true
	queue_redraw()


## The Gen-1 field item list (ITEMLISTMENU, home/list_menu.asm): the fixed 16x11
## LIST_MENU_BOX at (4,2)-(19,12) — names at col 6 on rows 4/6/8/10 (4 per window),
## each quantity as ×NN on the row below at col 14 (skipped for key items, IsKeyItem),
## and ▼ at (18,11) while the last row sits below the window. `quantities` pairs with
## `names` (-1 = print no quantity). Cursor/scroll restore wBagSavedMenuItem + the
## surviving wListScrollOffset.
func open_itemlist(names: Array, quantities: Array, at_cursor := 0, at_scroll := 0,
		keep_under := false) -> void:
	open(names, Vector2(32, 16), keep_under)
	list_mode = true
	qtys = quantities
	box_w = 16
	box_h = 11
	row0 = 2
	cursor = clampi(at_cursor, 0, names.size() - 1)
	scroll = clampi(at_scroll, maxi(0, cursor - 2), mini(cursor, maxi(0, names.size() - 3)))
	queue_redraw()


## Freeze the live box into the background stack; a submenu opened with keep_under draws
## over it. The parent's cursor turns hollow (▷) exactly as PlaceUnfilledArrowMenuCursor
## leaves it when a Gen-1 submenu opens on top.
func push_under() -> void:
	hollow = true
	under.append(_capture())


## Restore the top background layer as the live box — a closing submenu that put back the
## tiles it covered (TwoOptionMenu). The restored cursor stays hollow.
func pop_under() -> void:
	if under.is_empty():
		visible = false
		return
	var st: Dictionary = under.pop_back()
	items = st["items"]
	cursor = st["cursor"]
	scroll = st["scroll"]
	swap_mark = st["swap_mark"]
	origin = st["origin"]
	hollow = st["hollow"]
	list_mode = st["list_mode"]
	qtys = st["qtys"]
	row0 = st["row0"]
	box_w = st["box_w"]
	box_h = st["box_h"]
	single_spaced = st["single_spaced"]
	qty_mode = st["qty_mode"]
	qty = st["qty"]
	qty_unit = st["qty_unit"]
	queue_redraw()


func _capture() -> Dictionary:
	return {
		"items": items.duplicate(), "cursor": cursor, "scroll": scroll,
		"swap_mark": swap_mark, "origin": origin, "hollow": hollow,
		"list_mode": list_mode, "qtys": qtys.duplicate(), "row0": row0,
		"box_w": box_w, "box_h": box_h, "single_spaced": single_spaced,
		"qty_mode": qty_mode, "qty": qty, "qty_unit": qty_unit,
	}


## POKéMON menu (engine/menus/party_menu.asm): the party as HP-bar rows. `mons` are the party dicts;
## the cursor/`chosen` index selects a mon, so callers use it exactly like a plain list.
func open_party(mons: Array, at: Vector2, teach := []) -> void:
	under.clear()                      # the party menu clears the whole screen
	party = mons
	items = mons                       # cursor count = party size
	teach_flags = teach                # non-empty -> TMHM menu (ABLE/NOT ABLE per mon)
	cursor = 0
	scroll = 0
	origin = at
	qty_mode = false
	party_mode = true
	hollow = false
	list_mode = false
	visible = true
	queue_redraw()


## Keep the cursor inside the visible window after it moves.
func _fix_scroll() -> void:
	var vis := mini(items.size(), MAX_VISIBLE)
	if cursor < scroll:
		scroll = cursor
	elif cursor >= scroll + vis:
		scroll = cursor - vis + 1
	scroll = clampi(scroll, 0, maxi(0, items.size() - vis))


## Quantity picker: choose 1..maxq (each worth `unit`); `chosen` emits the count, or -1 on cancel.
func open_qty(maxq: int, unit: int, at: Vector2, keep_under := false) -> void:
	if not keep_under:
		under.clear()
	qty_mode = true
	party_mode = false
	hollow = false
	list_mode = false
	qty = 1
	qty_max = max(1, maxq)
	qty_unit = unit
	origin = at
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func handle_input() -> void:
	if qty_mode:
		if Input.is_action_just_pressed("ui_up"):
			qty = qty % qty_max + 1 if qty < qty_max else 1     # wrap 1..qty_max
			queue_redraw()
		elif Input.is_action_just_pressed("ui_down"):
			qty = qty - 1 if qty > 1 else qty_max
			queue_redraw()
		elif Input.is_action_just_pressed("ui_accept"):
			chosen.emit(qty)
		elif Input.is_action_just_pressed("ui_cancel"):
			chosen.emit(-1)
		return
	if list_mode:
		# ITEMLISTMENU (home/list_menu.asm): the cursor rides the top 3 window rows only
		# (wMaxMenuItem = 2, the 4th row is a preview); DOWN on the 3rd scrolls while
		# scroll+3 <= item count (the pre-CANCEL wListCount); no wraparound.
		if Input.is_action_just_pressed("ui_up"):
			if cursor > 0:
				if cursor == scroll:
					scroll -= 1
				cursor -= 1
				queue_redraw()
		elif Input.is_action_just_pressed("ui_down"):
			if cursor - scroll < 2:
				if cursor + 1 < items.size():
					cursor += 1
					queue_redraw()
			elif scroll + 3 <= items.size() - 1:
				scroll += 1
				cursor += 1
				queue_redraw()
		elif Input.is_action_just_pressed("ui_accept"):
			chosen.emit(cursor)
		elif Input.is_action_just_pressed("ui_cancel"):
			chosen.emit(-1)
		elif Input.is_action_just_pressed("p_select"):
			selected.emit(cursor)
		return
	var n := items.size()
	if Input.is_action_just_pressed("ui_up"):
		cursor = (cursor - 1 + n) % n
		_fix_scroll()
		queue_redraw()
	elif Input.is_action_just_pressed("ui_down"):
		cursor = (cursor + 1) % n
		_fix_scroll()
		queue_redraw()
	elif Input.is_action_just_pressed("ui_accept"):
		chosen.emit(cursor)
	elif Input.is_action_just_pressed("ui_cancel"):
		chosen.emit(-1)
	elif Input.is_action_just_pressed("p_select"):
		selected.emit(cursor)


func _draw() -> void:
	if full_bg:                                           # blank screen behind the title menu
		draw_rect(Rect2(0, 0, 160, 144), LIGHT)
		if version != "":
			_draw_str("v" + version, 8, 136)
	if party_mode:
		_draw_party()
		return
	if keep_party:                                        # STATS/SWITCH submenu over the party
		_draw_party(party_sel, true)
	for st in under:                                      # frozen parent boxes, bottom-up
		_draw_box(st)
	if not save_info.is_empty():                          # save screen: info box + prompt (main_menu.asm)
		Frame.draw(self, frame_tex, 32, 0, 16, 10, LIGHT) # 14x8 interior at (4,0); labels at rows 2/4/6/8
		_draw_str("PLAYER", 40, 16); _draw_str(str(save_info["player"]), 96, 16)
		_draw_str("BADGES", 40, 32); _draw_str("%2d" % int(save_info["badges"]), 136, 32)
		_draw_str("POKéDEX", 40, 48); _draw_str("%3d" % int(save_info["dex"]), 128, 48)
		_draw_str("TIME", 40, 64); _draw_str(str(save_info["time"]), 104, 64)
		# The prompt is a normal PrintText textbox: the full-size bottom box (rows 12-17) with
		# double-spaced lines at (1,14) and (1,16) — not a squeezed 4-row one (gh #156).
		Frame.draw(self, frame_tex, 0, 96, 20, 6, LIGHT)
		_draw_str("Would you like to", 8, 112)
		_draw_str("SAVE the game?", 8, 128)
	_draw_box(_capture())      # (the MONEY_BOX overlay lives in MoneyBox.gd now)


## Draw one boxed menu from a state dict — the live box or a frozen `under` layer.
func _draw_box(st: Dictionary) -> void:
	var org: Vector2 = st["origin"]
	if st["qty_mode"]:
		if int(st["qty_unit"]) > 0:                       # priced picker: ×NN + the running total
			Frame.draw(self, frame_tex, org.x, org.y, 9, 3, LIGHT)
			_draw_str("x%2d" % int(st["qty"]), org.x + GLYPH, org.y + GLYPH)
			_draw_str("¥%5d" % (int(st["qty"]) * int(st["qty_unit"])),
				org.x + 4 * GLYPH, org.y + GLYPH)
		else:                                             # just-quantity: the 5x3 "×01" box
			Frame.draw(self, frame_tex, org.x, org.y, 5, 3, LIGHT)   # DisplayChooseQuantityMenu
			_draw_str("×%02d" % int(st["qty"]), org.x + GLYPH, org.y + GLYPH)
		return
	var its: Array = st["items"]
	var lm: bool = st["list_mode"]
	var scr: int = st["scroll"]
	var maxlen := 0
	for it in its:
		maxlen = max(maxlen, str(it).length())
	var vis: int = mini(its.size() - scr, LIST_VISIBLE) if lm else mini(its.size(), MAX_VISIBLE)
	var wt: int = st["box_w"] if int(st["box_w"]) > 0 else maxlen + 3   # border+cursor+text+border
	var ht: int = st["box_h"] if int(st["box_h"]) > 0 else vis * 2 + 1
	Frame.draw(self, frame_tex, org.x, org.y, wt, ht, LIGHT)
	for r in vis:
		var i: int = scr + r
		var spacing: int = GLYPH if bool(st["single_spaced"]) else ROW
		var y: float = org.y + int(st["row0"]) * GLYPH + r * spacing
		if i == int(st["cursor"]):
			# The font's own ▶ tile ($ed), not a hand-drawn triangle (gh #154).
			_draw_str("▷" if st["hollow"] else "▶", org.x + GLYPH, y)
		elif i == int(st["swap_mark"]):                   # a SELECT-held row: hollow ▷ (list_menu.asm)
			_draw_str("▷", org.x + GLYPH, y)
		_draw_str(str(its[i]), org.x + 2 * GLYPH, y)
		if lm and i < (st["qtys"] as Array).size() and int(st["qtys"][i]) >= 0:
			_draw_str("×", org.x + 10 * GLYPH, y + GLYPH) # quantity on the row below, col 14
			_draw_str("%2d" % int(st["qtys"][i]), org.x + 11 * GLYPH, y + GLYPH)
	if lm:
		if its.size() > scr + LIST_VISIBLE:               # more rows below: ▼ at (18,11)
			_draw_str("▼", org.x + 14 * GLYPH, org.y + 9 * GLYPH)
	else:
		# scroll arrows when the list overflows the window
		if scr > 0:
			_draw_str("^", org.x + GLYPH, org.y + 1)
		if scr + vis < its.size():
			_draw_str("v", org.x + GLYPH, org.y + GLYPH + vis * ROW)


## A condensed glyph tile from font_battle_extra (HP=15, :L=12, ID=17, No=18, ...).
func _glyph(t: int, x: float, y: float) -> void:
	draw_texture_rect_region(fbe_tex, Rect2(x, y, 8, 8), Rect2((t % 15) * 8, (t / 15) * 8, 8, 8))


## A battle-HUD strip tile (battle_hud.png, 30x1): the party "HP:" pair is tiles 15+0.
func _hud(t: int, x: float, y: float) -> void:
	draw_texture_rect_region(hud_tex, Rect2(x, y, 8, 8), Rect2(t * 8, 0, 8, 8))


## The POKéMON menu (engine/menus/party_menu.asm): each mon on two rows — the mini icon, name
## at col 3, the :L glyph + level at col 13, status at col 17; then HP: + the 6-tile bar and
## the right-aligned cur/max — over a "Choose a POKéMON." textbox. No outer box.
func _draw_party(sel := -1, hollow := false) -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)                  # blank screen behind the party
	if sel < 0:
		sel = cursor
	for i in party.size():
		var m: Dictionary = party[i]
		var y: float = i * 16.0
		var y2: float = y + GLYPH
		var sp := str(m["species"])                          # mini party icon (data/icon_pointers.asm)
		if mon_icons_tex and mon_icons_map.has(sp):
			var ii: int = int(mon_icons_map[sp])
			var fr := 0
			var by := y
			if i == sel and _icon_anim:                      # the selected icon animates
				if ii == 1 or ii == 2:                       # BALL/HELIX shake 1px instead
					by += 1.0
				else:
					fr = 1                                   # the walk frame
			draw_texture_rect_region(mon_icons_tex, Rect2(8, by, 16, 16),
				Rect2(ii * 16, fr * 16, 16, 16))
		if i == sel:
			_draw_str("▷" if hollow else "▶", 0, y2)         # the cursor rides the HP row
		_draw_str(str(m["name"]), 24, y)
		_glyph(12, 104, y)                                   # the ":L" tile at col 13
		_draw_str(str(int(m["level"])), 112, y)
		if not teach_flags.is_empty():                       # TMHM menu: ABLE/NOT ABLE, no HP bar/status
			var able: bool = i < teach_flags.size() and bool(teach_flags[i])
			_draw_str("ABLE" if able else "NOT ABLE", 72, y2)   # party_menu.asm: row+1, col 9
			continue
		var st := str(m.get("status", "")).to_upper()
		if st != "":
			_draw_str(st, 136, y)                            # status at name+14 (col 17)
		_hud(15, 32, y2)                                     # the exact "HP:" pair (battle_hud
		_hud(0, 40, y2)                                      # tiles 15+0, bit-matched to the ref)
		_hp_pill(m, y2)
		_draw_str("%3d/" % int(m["hp"]), 104, y2)            # cur ends col 15, / at 16
		_draw_str("%4d" % int(m["maxhp"]), 128, y2)          # max ends col 19
	Frame.draw(self, frame_tex, 0, 96, 20, 6, LIGHT)         # "Choose a POKéMON." message box
	_draw_str("Choose a POKéMON.", 8, 112)


## The Gen-1 HP pill, profiled from the reference: 1px edges x48-95, rounded 2px caps at
## x47/x96, a 2px fill band from x48.
func _hp_pill(m: Dictionary, y2: float) -> void:
	var frac: float = clampf(float(m["hp"]) / maxf(1.0, float(m["maxhp"])), 0.0, 1.0)
	draw_rect(Rect2(48, y2 + 2, 48, 1), DARK)
	draw_rect(Rect2(48, y2 + 5, 48, 1), DARK)
	draw_rect(Rect2(47, y2 + 3, 1, 2), DARK)
	draw_rect(Rect2(96, y2 + 3, 1, 2), DARK)
	var fw := maxf(1.0 if int(m["hp"]) > 0 else 0.0, floorf(48.0 * frac))
	draw_rect(Rect2(48, y2 + 3, fw, 2), HPFILL)


var _icon_anim := false            # party icon animation phase (the selected mon bounces)
var _icon_t := 0.0


func _process(delta: float) -> void:
	if not (visible and (party_mode or keep_party)) or party.is_empty():
		return
	# The selected mon's icon animates at its HP-color speed — PartyMonSpeeds: a frame lasts
	# 5 (green) / 16 (yellow) / 32 (red) V-blanks, +1 off SGB (`wOnSGB xor 1`, so 6/17/33 on
	# the DMG this port mirrors; engine/gfx/mon_icons.asm GetAnimationSpeed).
	var sel := cursor if party_mode else party_sel
	var m: Dictionary = party[clampi(sel, 0, party.size() - 1)]
	var frac := float(m["hp"]) / maxf(1.0, float(m["maxhp"]))
	var vbl := 6.0 if frac > 0.5 else (17.0 if frac > 0.2 else 33.0)
	_icon_t += delta
	if _icon_t >= vbl / 60.0:
		_icon_t = 0.0
		_icon_anim = not _icon_anim
		queue_redraw()


func _draw_str(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var t: int = charmap[ch]
			var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
