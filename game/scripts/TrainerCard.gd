extends Control
## The trainer card (start menu → the player's name): DrawTrainerInfo + draw_badges.asm.
## The player's pic sits upper-right with NAME/MONEY/TIME beside it, and the lower box holds
## the 8 gym slots — each shows the leader's face until that badge is earned, then the badge.

signal closed

const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8
const BADGE_ORDER := ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
	"SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE"]

var main
var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var pic_tex: Texture2D
var badges_tex: Texture2D
var info_tex: Texture2D            # border tiles $77-$7E + the checkered bg (trainer_info.png 3x3)
var numbers_tex: Texture2D         # the fancy "1"-"8" tiles (badge_numbers.png 2x4)
var circle_tex: Texture2D          # the $76 circle tile framing ●BADGES● (circle_tile.png)


func setup(m, ft: Texture2D, cols: int, cmap: Dictionary) -> void:
	main = m
	font_tex = ft
	font_cols = cols
	charmap = cmap
	pic_tex = load("res://assets/trainer_front.png")
	badges_tex = load("res://assets/badges.png")
	info_tex = load("res://assets/trainer_info.png")
	numbers_tex = load("res://assets/badge_numbers.png")
	circle_tex = load("res://assets/circle_tile.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func open_card() -> void:
	visible = true
	queue_redraw()


func handle_input() -> void:
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
		visible = false
		closed.emit()


# trainer_info.png tile positions (row-major 3x3): $77 bottom edge, $78 right, $79 upper-left,
# $7a top, $7b upper-right, $7c left, $7d lower-left, $7e lower-right, then the checkered bg.
const _T := {"bot": Vector2(0, 0), "right": Vector2(8, 0), "ul": Vector2(16, 0),
	"top": Vector2(0, 8), "ur": Vector2(8, 8), "left": Vector2(16, 8),
	"ll": Vector2(0, 16), "lr": Vector2(8, 16), "bg": Vector2(16, 16)}


func _tile(which: String, tx: int, ty: int) -> void:
	draw_texture_rect_region(info_tex, Rect2(tx * 8, ty * 8, 8, 8), Rect2(_T[which], Vector2(8, 8)))


## The card box style (TrainerInfo_DrawTextBox): corner/edge tiles around a 6-row interior.
func _card_box(tx: int, ty: int, w: int) -> void:
	draw_rect(Rect2((tx + 1) * 8, (ty + 1) * 8, w * 8, 48), LIGHT)
	_tile("ul", tx, ty)
	_tile("ur", tx + w + 1, ty)
	_tile("ll", tx, ty + 7)
	_tile("lr", tx + w + 1, ty + 7)
	for c in w:
		_tile("top", tx + 1 + c, ty)
		_tile("bot", tx + 1 + c, ty + 7)
	for r in 6:
		_tile("left", tx, ty + 1 + r)
		_tile("right", tx + w + 1, ty + 1 + r)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)            # the ClearScreen base
	_card_box(0, 0, 18)                                # info box: (0,0), interior 18 wide
	# RedPicFront: only the region inside the box frame survives — the wrapped columns are
	# erased and the box edges overdraw the pic's fringe. Profiled against the reference:
	# the visible crop is 5x6 tiles at column 14 (Red spans x 122-147 there).
	draw_texture_rect_region(pic_tex, Rect2(112, 8, 40, 48), Rect2(0, 0, 40, 48))
	_text("NAME/", 16, 16)
	_text(main.player_name, 56, 16)
	_text("MONEY/", 16, 32)
	_text("¥" + str(main.player_money), 64, 32)        # zero-suppressed BCD: the ¥ hugs the
	_text("TIME/", 16, 48)                             # first digit right after the label
	_text("%d:%02d" % [int(main.play_seconds / 3600.0), int(main.play_seconds / 60.0) % 60], 72, 48)
	_text("BADGES", 56, 72)                            # ●BADGES● at hlcoord 6,9
	draw_texture(circle_tex, Vector2(48, 72))          # the $76 circle tiles framing the label
	draw_texture(circle_tex, Vector2(104, 72))
	_card_box(1, 10, 16)                               # badges box: (1,10), interior 16 wide
	for r in 8:                                        # the checkered strips flanking it
		_tile("bg", 0, 10 + r)                         # ($d7 = vChars1 $57, the bg pattern tile)
		_tile("bg", 19, 10 + r)
	for i in 8:
		var c := i % 4
		var r := i / 4
		# the number tile at (2+4c, 11+3r); the 16x16 face — or the badge once earned
		# (DrawBadges: +4 tiles = the next strip entry) — at (3+4c, 12+3r)
		draw_texture_rect_region(numbers_tex, Rect2((2 + 4 * c) * 8, (11 + 3 * r) * 8, 8, 8),
			Rect2((i % 2) * 8, (i / 2) * 8, 8, 8))
		var strip := i * 2 + (1 if BADGE_ORDER[i] in main.badges else 0)
		draw_texture_rect_region(badges_tex, Rect2((3 + 4 * c) * 8, (12 + 3 * r) * 8, 16, 16),
			Rect2(0, strip * 16, 16, 16))


func _text(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var ti: int = charmap[ch]
			var src := Rect2((ti % font_cols) * GLYPH, (ti / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
