extends Control
## Game Corner slot machine — engine/slots/slot_machine.asm + data/events/slot_machine_wheels.asm.
##
## A self-contained interactive minigame: bet 1-3 coins, stop three reels with A,
## win by lining up matching symbols on an active payline. Bet 1 = the middle row,
## bet 2 adds the top/bottom rows, bet 3 adds the two diagonals.
##
## Like the original, the house rigs each spin BEFORE it starts (SlotMachine_SetFlags):
## most spins are not allowed to win, some allow a normal (Pokémon/cherry) match, and
## rarely a 7/BAR jackpot. When a win is allowed the third reel is rolled down until a
## winning line appears (SlotMachine_CheckForMatches' rollWheel3DownByOneSymbol); when
## a win lands that isn't allowed, the reel is rolled past it.

signal finished

const DARK := Color(0.133, 0.188, 0.224)
const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8

# Reel strips (data/events/slot_machine_wheels.asm), 18 symbols each, bottom-to-top order.
const WHEEL1 := ["SEVEN", "MOUSE", "FISH", "BAR", "CHERRY", "SEVEN", "FISH", "BIRD", "BAR",
	"CHERRY", "SEVEN", "MOUSE", "BIRD", "BAR", "CHERRY", "SEVEN", "MOUSE", "FISH"]
const WHEEL2 := ["SEVEN", "FISH", "CHERRY", "BIRD", "MOUSE", "BAR", "CHERRY", "FISH", "BIRD",
	"CHERRY", "BAR", "FISH", "BIRD", "CHERRY", "MOUSE", "SEVEN", "FISH", "CHERRY"]
const WHEEL3 := ["SEVEN", "BIRD", "FISH", "CHERRY", "MOUSE", "BIRD", "FISH", "CHERRY", "MOUSE",
	"BIRD", "FISH", "CHERRY", "MOUSE", "BIRD", "BAR", "SEVEN", "BIRD", "FISH"]

# SlotRewardPointers: 7=300, BAR=100, cherry=8, any Pokémon symbol=15.
const PAYOUT := {"SEVEN": 300, "BAR": 100, "CHERRY": 8, "FISH": 15, "BIRD": 15, "MOUSE": 15}
const SYM2 := {"SEVEN": "7", "BAR": "BR", "CHERRY": "CH", "FISH": "FS", "BIRD": "BD", "MOUSE": "MS"}

var font_tex: Texture2D
var slot_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var main                              # back-ref to Main (coins, audio)
var lucky := false

var phase := ""                       # intro / bet / spin / result / again / outof / done
var bet := 0
var bet_cursor := 0                   # 0 = ×3, 1 = ×2, 2 = ×1
var pos := [0, 0, 0]                  # bottom-row symbol index of each reel
var spinning := [false, false, false]
var stop_idx := 0                     # which reel the next A press stops
var spin_t := 0.0
var win_sym := ""
var payout := 0
var msg := ""
var yn := 0                           # yes/no cursor (0 = yes, 1 = no)
var rig := "none"                     # this spin's allowance: none / normal / sevenbar

# Rig state persisted across spins in one sitting (wSlotMachineAllowMatchesCounter / Flags).
var allow_counter := 0
var seven_bar_mode := false


func setup(ftex: Texture2D, cols: int, cmap: Dictionary, main_ref) -> void:
	font_tex = ftex
	font_cols = cols
	charmap = cmap
	main = main_ref
	slot_tex = _asset_texture("slots/slots_1.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)


func start(is_lucky: bool) -> void:
	lucky = is_lucky
	allow_counter = 0
	seven_bar_mode = false
	bet = 0
	win_sym = ""
	phase = "intro"
	msg = "A slot machine!\nWant to play?"
	yn = 0
	visible = true
	set_process(true)
	queue_redraw()


# ---- input (one action per frame, driven by Player) ------------------------

func handle_input() -> void:
	match phase:
		"intro", "again":
			_yn_input(true)
		"bet":
			_bet_input()
		"spin":
			if Input.is_action_just_pressed("ui_accept"):
				_stop_reel()
		"result":
			if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
				_after_result()
		"outof":
			if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
				_finish()


func _yn_input(_enter: bool) -> void:
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
		yn = 1 - yn
		queue_redraw()
	elif Input.is_action_just_pressed("ui_accept"):
		if yn == 0:
			_to_bet()
		else:
			_finish()
	elif Input.is_action_just_pressed("ui_cancel"):
		_finish()


func _bet_input() -> void:
	if Input.is_action_just_pressed("ui_up"):
		bet_cursor = (bet_cursor - 1 + 3) % 3
		queue_redraw()
	elif Input.is_action_just_pressed("ui_down"):
		bet_cursor = (bet_cursor + 1) % 3
		queue_redraw()
	elif Input.is_action_just_pressed("ui_cancel"):
		_finish()
	elif Input.is_action_just_pressed("ui_accept"):
		var b := 3 - bet_cursor
		if main.player_coins < b:
			msg = "Not enough\ncoins!"
			queue_redraw()
			return
		bet = b
		main.player_coins -= b
		_begin_spin()


# ---- flow ------------------------------------------------------------------

func _to_bet() -> void:
	phase = "bet"
	bet_cursor = 0
	msg = "Bet how many\ncoins?"
	queue_redraw()


func _begin_spin() -> void:
	rig = _decide()
	for i in 3:
		pos[i] = randi() % 18
	spinning = [true, true, true]
	stop_idx = 0
	win_sym = ""
	phase = "spin"
	msg = "Start!"
	if main and main.audio:
		main.audio.play_sfx("press_ab")
	queue_redraw()


func _stop_reel() -> void:
	spinning[stop_idx] = false
	if main and main.audio:
		main.audio.play_sfx("press_ab")
	stop_idx += 1
	if stop_idx >= 3:
		_resolve()


func _resolve() -> void:
	var res := resolve_rig(pos, bet, rig)
	pos = res["pos"]
	win_sym = str(res["symbol"])
	if win_sym != "":
		payout = int(res["payout"])
		main.player_coins = mini(9999, main.player_coins + payout)
		apply_reward(win_sym)
		msg = "%s lined up!\nScored %d coins!" % [win_sym, payout]
		if main and main.audio:
			main.audio.play_sfx("get_key_item" if payout >= 100 else "get_item1")
	else:
		payout = 0
		msg = "Not this time!"
	phase = "result"
	queue_redraw()


func _after_result() -> void:
	if main.player_coins <= 0:
		phase = "outof"
		msg = "Darn!\nRan out of coins!"
	else:
		phase = "again"
		msg = "One more go?"
		yn = 0
	queue_redraw()


func _finish() -> void:
	phase = "done"
	visible = false
	set_process(false)
	finished.emit()


# ---- rig logic (pure; unit-tested by --slottest) ---------------------------

## Decide this spin's allowance, mirroring SlotMachine_SetFlags.
func _decide() -> String:
	if seven_bar_mode:
		return "sevenbar"
	if allow_counter > 0:
		return "normal"
	var b := randi() % 256
	if b == 0:                                   # 1/256: prime 60 future winning spins
		allow_counter = 60
		return "none"
	var chance := 250 if lucky else 253          # lucky machine: slightly better 7/BAR odds
	if b > chance:
		seven_bar_mode = true
		return "sevenbar"
	if b > 210:
		return "normal"
	return "none"


## Roll the third reel until the outcome matches the allowance (rollWheel3DownByOneSymbol).
func resolve_rig(p0: Array, b: int, allow: String) -> Dictionary:
	var p := p0.duplicate()
	var tries := 0
	while tries <= 18:
		var sym := find_match(p, b)
		if sym != "":
			var is7 := sym == "SEVEN" or sym == "BAR"
			if allow == "sevenbar" or (allow == "normal" and not is7):
				return {"pos": p, "symbol": sym, "payout": PAYOUT[sym]}
		elif allow == "none":
			return {"pos": p, "symbol": "", "payout": 0}
		p[2] = (p[2] + 1) % 18
		tries += 1
	return {"pos": p, "symbol": "", "payout": 0}


## The winning symbol on the highest-priority active payline, or "" (SlotMachine_CheckForMatches).
func find_match(p: Array, b: int) -> String:
	var reels := [WHEEL1, WHEEL2, WHEEL3]
	var lines: Array = []
	if b >= 3:                                   # diagonals checked first on a 3-coin bet
		lines.append([0, 1, 2])
		lines.append([2, 1, 0])
	if b >= 2:                                   # then the top and bottom rows
		lines.append([2, 2, 2])
		lines.append([0, 0, 0])
	lines.append([1, 1, 1])                       # the middle row (always active)
	for ln in lines:
		var a: String = reels[0][(int(p[0]) + int(ln[0])) % 18]
		var b2: String = reels[1][(int(p[1]) + int(ln[1])) % 18]
		var c: String = reels[2][(int(p[2]) + int(ln[2])) % 18]
		if a == b2 and a == c:
			return a
	return ""


## Update the rig state after a win (SlotReward*Func).
func apply_reward(sym: String) -> void:
	match sym:
		"SEVEN":                                 # always clears the counter, 50% drops 7/BAR mode
			allow_counter = 0
			if randi() % 256 >= 0x80:
				seven_bar_mode = false
		"BAR":
			seven_bar_mode = false
		_:                                       # cherry / Pokémon: spend a primed winning spin
			if allow_counter > 0:
				allow_counter -= 1


# ---- animation + drawing ---------------------------------------------------

func _process(delta: float) -> void:
	if phase != "spin":
		return
	spin_t += delta
	if spin_t < 0.045:
		return
	spin_t = 0.0
	for i in 3:
		if spinning[i]:
			pos[i] = (pos[i] + 1) % 18
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	if slot_tex:
		draw_texture_rect_region(slot_tex, Rect2(8, 24, 128, 24), Rect2(0, 0, 128, 24))
	_str("COIN%4d" % main.player_coins, 8, 8)
	if phase == "result" and win_sym != "":
		_str("WIN%5d" % payout, 96, 8)
	elif bet > 0:
		_str("BET%2d" % bet, 112, 8)
	# Reel window: a 3x3 grid (row 0 = top). Active rows are bracketed by the bet.
	var gx := 48
	var gy := 38
	var col_w := 28
	var row_h := 16
	var reels := [WHEEL1, WHEEL2, WHEEL3]
	draw_rect(Rect2(gx - 6, gy - 4, 3 * col_w - 4, 3 * row_h + 4), DARK, false, 1.0)
	for r in 3:
		if _row_active(r):
			draw_rect(Rect2(gx - 14, gy + r * row_h + 2, 5, 5), DARK)
			draw_rect(Rect2(gx + 3 * col_w - 11, gy + r * row_h + 2, 5, 5), DARK)
	for col in 3:
		for r in 3:
			var sidx: int = int(pos[col]) + (2 - r)        # row 0 = top = bottom index + 2
			var sym: String = reels[col][sidx % 18]
			_str(str(SYM2[sym]), gx + col * col_w, gy + r * row_h)
	# Message / prompt box.
	draw_rect(Rect2(4, 96, 152, 44), LIGHT)
	draw_rect(Rect2(4, 96, 152, 44), DARK, false, 1.0)
	_multiline(msg, 12, 104)
	if phase == "bet":
		var opts := ["x3", "x2", "x1"]
		for i in 3:
			if i == bet_cursor:
				_cursor(112, 104 + i * 12)
			_str(opts[i], 120, 104 + i * 12)
	elif phase == "intro" or phase == "again":
		_str("YES", 120, 104)
		_str("NO", 120, 116)
		_cursor(112, 104 + yn * 12)


## The font's ▶ cursor tile ($ed), matching Menu.gd (gh #154).
func _cursor(x: float, y: float) -> void:
	_str("▶", x, y)


func _row_active(r: int) -> bool:
	if r == 1:
		return true                               # middle row: any bet
	return bet >= 2                               # top/bottom: 2+ coins


func _multiline(s: String, x0: float, y0: float) -> void:
	var y := y0
	for line in s.split("\n"):
		_str(line, x0, y)
		y += 12.0


func _str(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var t: int = charmap[ch]
			var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH


func _asset_texture(rel: String) -> Texture2D:
	var img := Image.new()
	var path := ProjectSettings.globalize_path("res://assets/" + rel)
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)
