extends Control
## The Poké Mart (engine/items/marts.asm + data/text_boxes.asm), per the reference shots:
## the BUY/SELL/QUIT box at (0,0)-(10,6), the MONEY box at (11,0)-(19,2) with its label over
## the top border and the BCD-style floating-¥ amount, the item list overlay at (4,2)-(19,12)
## with prices (BUY) or ×N counts (SELL), the ×NN quantity strip, and the YES/NO confirm at
## (14,7) over the priced textbox. Every box stays visible beneath the ones stacked above it.

signal closed

const DARK := Color(0.133, 0.188, 0.224)
const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8

var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var frame_tex: Texture2D
var main

var state := "top"           # top / buy / sell / qty / confirm
var top_cur := 0
var cursor := 0              # absolute index into the open list (stock/bag + CANCEL)
var scroll := 0
var stock: Array = []        # BUY: the mart's item display names
var bag_keys: Array = []     # SELL: the player's bag items
var item := ""               # the item a qty/confirm is for
var qty := 1
var maxq := 1
var selling := false         # the qty/confirm belongs to a SELL
var confirm_yes := true
var swap_mark := -1          # SELL row "held" by SELECT (the sell list is an ITEMLISTMENU;
                             # the BUY list is a PRICEDITEMLISTMENU and doesn't reorder)


func setup(tex: Texture2D, cols: int, cmap: Dictionary, game) -> void:
	font_tex = tex
	font_cols = cols
	charmap = cmap
	frame_tex = load("res://assets/frame.png")
	main = game
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func open(items: Array) -> void:
	stock = items
	state = "top"
	top_cur = 0
	visible = true
	main._say_keep("Hi there!\nMay I help you?")
	queue_redraw()


func handle_input() -> void:
	match state:
		"top":
			if Input.is_action_just_pressed("ui_down"):
				top_cur = (top_cur + 1) % 3; queue_redraw()
			elif Input.is_action_just_pressed("ui_up"):
				top_cur = (top_cur + 2) % 3; queue_redraw()
			elif Input.is_action_just_pressed("ui_accept"):
				_top_select(top_cur)
			elif Input.is_action_just_pressed("ui_cancel"):
				_close_shop()
		"buy", "sell":
			var n := _entries().size()
			if Input.is_action_just_pressed("ui_down"):
				cursor = mini(cursor + 1, n - 1); _fix_scroll(); queue_redraw()
			elif Input.is_action_just_pressed("ui_up"):
				cursor = maxi(cursor - 1, 0); _fix_scroll(); queue_redraw()
			elif Input.is_action_just_pressed("ui_accept"):
				swap_mark = -1                       # choosing clears the hold
				_list_select(cursor)
			elif Input.is_action_just_pressed("ui_cancel"):
				_back_to_top()
			elif state == "sell" and Input.is_action_just_pressed("p_select"):
				_swap_sell_items()
		"qty":
			if Input.is_action_just_pressed("ui_up"):
				qty = qty + 1 if qty < maxq else 1; queue_redraw()
			elif Input.is_action_just_pressed("ui_down"):
				qty = qty - 1 if qty > 1 else maxq; queue_redraw()
			elif Input.is_action_just_pressed("ui_accept"):
				_to_confirm()
			elif Input.is_action_just_pressed("ui_cancel"):
				_back_to_list()
		"confirm":
			if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
				confirm_yes = not confirm_yes; queue_redraw()
			elif Input.is_action_just_pressed("ui_accept"):
				_confirm(confirm_yes)
			elif Input.is_action_just_pressed("ui_cancel"):
				_confirm(false)


func _entries() -> Array:
	return (bag_keys if selling else stock) + ["CANCEL"]


func _fix_scroll() -> void:
	scroll = clampi(scroll, cursor - 3, cursor)


func _unit_price() -> int:
	var p := int(main.item_prices.get(item, 0))
	return p / 2 if selling else p               # selling pays half the shelf price


func _top_select(i: int) -> void:
	top_cur = i
	match i:
		0:                                       # BUY
			selling = false
			cursor = 0; scroll = 0
			state = "buy"
			main._say_keep("Take your time.")
		1:                                       # SELL
			if main.player_bag.is_empty():
				main._say_keep("You don't have\nanything to sell.")
			else:
				selling = true
				bag_keys = main.player_bag.keys()
				cursor = 0; scroll = 0; swap_mark = -1
				state = "sell"
				main._say_keep("What would you\nlike to sell?")
		2:                                       # QUIT
			_close_shop()
	queue_redraw()


func _list_select(i: int) -> void:
	cursor = i
	_fix_scroll()
	var names: Array = bag_keys if selling else stock
	if i >= names.size():                        # CANCEL
		_back_to_top()
		return
	item = str(names[i])
	if selling:
		if _unit_price() <= 0:
			# priceless items — key items, PP UP, the Ethers/Elixers (ItemPrices 0) — refuse
			# with the clerk's line (PokemartUnsellableItemText), not a silent buzz (gh #176)
			main._say_keep("I can't put a\nprice on that.")
			return
		maxq = int(main.player_bag.get(item, 1))
	else:
		var p := _unit_price()
		maxq = mini(99, int(main.player_money / p)) if p > 0 else 0
		if maxq < 1:
			if main.audio: main.audio.play_sfx("denied")
			main._say_keep("You don't have\nenough money.")
			return
	qty = 1
	state = "qty"
	queue_redraw()


## SELECT in the SELL list reorders the bag like the overworld item menu — pokemart.asm
## displays it as an ITEMLISTMENU, so HandleItemListSwapping applies: CANCEL can't be
## swapped, re-SELECTing the held item keeps it held.
func _swap_sell_items() -> void:
	if cursor >= bag_keys.size():
		return
	if swap_mark < 0:
		swap_mark = cursor                           # hold this item
	elif cursor != swap_mark:
		var held = bag_keys[swap_mark]               # swap the two items' positions
		bag_keys[swap_mark] = bag_keys[cursor]
		bag_keys[cursor] = held
		var reordered := {}
		for k in bag_keys:
			reordered[k] = main.player_bag[k]
		main.player_bag.clear()                      # reorder the shared bag dict in place
		main.player_bag.merge(reordered)
		swap_mark = -1
	queue_redraw()


func _to_confirm() -> void:
	state = "confirm"
	confirm_yes = true
	var total := _unit_price() * qty
	if selling:
		main._say_keep("I can pay you\n¥%d. OK?" % total)
	else:
		main._say_keep("That will be\n¥%d. OK?" % total)
	queue_redraw()


func _confirm(yes: bool) -> void:
	if not yes:
		_back_to_list()
		return
	var total := _unit_price() * qty
	if selling:
		main.player_money += total
		main.player_bag[item] = int(main.player_bag.get(item, 0)) - qty
		if int(main.player_bag.get(item, 0)) <= 0:
			main.player_bag.erase(item)
		bag_keys = main.player_bag.keys()
		if main.audio: main.audio.play_sfx("purchase")
		if bag_keys.is_empty():                  # nothing left to sell
			_back_to_top()
			return
		cursor = mini(cursor, bag_keys.size())
		state = "sell"
		main._say_keep("What would you\nlike to sell?")
	else:
		if not main.add_item(item, qty):         # 20-slot bag: a new slot may not fit
			state = "buy"
			main._say_keep("You have no more\nroom for items!")
			queue_redraw()
			return
		main.player_money -= total
		if main.audio: main.audio.play_sfx("purchase")
		state = "buy"
		main._say_keep("Here you are!\nThank you!")
	queue_redraw()


func _back_to_list() -> void:
	state = "sell" if selling else "buy"
	main._say_keep("What would you\nlike to sell?" if selling else "Take your time.")
	queue_redraw()


func _back_to_top() -> void:
	state = "top"
	main._say_keep("Is there anything\nelse I can do?")
	queue_redraw()


func _close_shop() -> void:
	visible = false
	main.textbox.visible = false
	closed.emit()


# ---- drawing ---------------------------------------------------------------

func _draw() -> void:
	# The BUY/SELL/QUIT box and the MONEY box are up in every state.
	Frame.draw(self, frame_tex, 0, 0, 11, 7, LIGHT)
	var tops := ["BUY", "SELL", "QUIT"]
	for i in 3:
		_str(tops[i], 16, 8 + i * 16)
	_str("▶" if state == "top" else "▷", 8, 8 + top_cur * 16)
	Frame.draw(self, frame_tex, 88, 0, 9, 3, LIGHT)
	# The label's text tiles REPLACE the border run on the GB tilemap (MONEY_BOX_TEMPLATE
	# prints at tile 13,0) — blank those cells first or the ─ line strikes through the word.
	draw_rect(Rect2(104, 0, 40, 8), LIGHT)
	_str("MONEY", 104, 0)
	_money(main.player_money, 152, 8)
	if state in ["buy", "sell", "qty", "confirm"]:
		_list_box()
	if state in ["qty", "confirm"]:
		_qty_box()
	if state == "confirm":
		Frame.draw(self, frame_tex, 112, 56, 6, 5, LIGHT)
		_str("YES", 128, 64)
		_str("NO", 128, 80)
		_str("▶", 120, 64 if confirm_yes else 80)


func _list_box() -> void:
	Frame.draw(self, frame_tex, 32, 16, 16, 11, LIGHT)
	var entries := _entries()
	var names: Array = bag_keys if selling else stock
	var vis := mini(4, entries.size() - scroll)
	for r in vis:
		var i := scroll + r
		var y := 32.0 + r * 16.0
		if i == cursor:
			_str("▶" if state in ["buy", "sell"] else "▷", 40, y)
		elif selling and i == swap_mark:             # the SELECT-held item (list_menu.asm '▷')
			_str("▷", 40, y)
		_str(str(entries[i]), 48, y)
		if i < names.size():
			if selling:
				_str("×", 112, y + 8)
				_str("%2d" % int(main.player_bag.get(str(names[i]), 0)), 120, y + 8)
			else:
				_money(int(main.item_prices.get(str(names[i]), 0)), 144, y + 8)
	if scroll + 4 < entries.size():
		_str("▼", 144, 88)                           # (18,11), level with the last quantity


func _qty_box() -> void:
	if state == "confirm":                       # the strip shrinks beside the YES/NO box
		Frame.draw(self, frame_tex, 40, 72, 8, 3, LIGHT)
		_str("×%02d" % qty, 48, 80)
	else:
		Frame.draw(self, frame_tex, 40, 72, 15, 3, LIGHT)
		_str("×%02d" % qty, 48, 80)
		_money(_unit_price() * qty, 144, 80)


## A BCD-style money print: the ¥ hugs the leading digit and the number ends at `x_end`
## (PrintBCDNumber with LEADING_ZEROES suppressed + MONEY_SIGN).
func _money(v: int, x_end: float, y: float) -> void:
	var s := "¥" + str(v)
	_str(s, x_end - s.length() * 8, y)


func _str(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var t: int = charmap[ch]
			var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
