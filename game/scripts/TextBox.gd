extends Control
## Gen-1 style dialogue box: a bordered panel at the bottom of the screen that
## types text out a character at a time and paginates on Enter/Space.
##
## Lives under a CanvasLayer (screen space). Text strings come from text.json with
## "\n" = line break and "\f" = page break (para). Glyphs are drawn from font.png
## via the charmap (char -> tile index).

signal closed
signal typed               # ask mode: the final page finished typing (the box holds open)

const DARK := Color(0.133, 0.188, 0.224)     # GB_PALETTE[3]
const LIGHT := Color(0.918, 0.984, 0.808)    # GB_PALETTE[0]
const MARGIN_X := 8                            # col 1 (inside the left border)
const LINE_Y := [112, 128]                     # rows 14 & 16 (box is rows 12-17)
const LINE_H := 16
const GLYPH := 8
const MAXCHARS := 18                          # cols 1-18 inside the border
var speed := 20.0                             # glyphs/s: 60 / letter-delay frames; the OPTION
                                              # text-speed setting (PrintLetterDelay, MEDIUM = 3)

var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var frame_tex: Texture2D
var pages: Array = []        # each page: String of up to 2 lines ("\n")
var page_idx := 0
var revealed := 0.0
var active := false
var hold_last := false       # ask mode: the final page emits `typed` and stays up (no close)
var held := false            # the ask page is holding for a menu (suppresses the ▼ arrow)
var on_typed := Callable()   # one-shot: runs when the final page finishes typing — pokered's
                             # print-then-act sites (e.g. the dex-rating jingle). Set AFTER
                             # show_text (which clears any stale callback).


func setup(tex: Texture2D, cols: int, cmap: Dictionary) -> void:
	font_tex = tex
	font_cols = cols
	charmap = cmap
	frame_tex = load("res://assets/frame.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func show_text(s: String) -> void:
	z_index = 0            # default layering: menus opened after the text draw over it; a
	                       # bag-flow message bumps this to 1 to overdraw the menu stack (gh #66)
	# Split on page breaks (\f), word-wrap to the box width, chunk into <=2 lines.
	pages = []
	for para in s.split("\f"):
		var lines: Array = []
		for raw in para.split("\n"):
			var cur := ""
			for word in raw.split(" "):
				if cur == "":
					cur = word
				elif cur.length() + 1 + word.length() <= MAXCHARS:
					cur += " " + word
				else:
					lines.append(cur)
					cur = word
			lines.append(cur)
		var i := 0
		while i < lines.size():
			pages.append("\n".join(lines.slice(i, i + 2)))
			i += 2
	if pages.is_empty():
		pages = [""]
	page_idx = 0
	revealed = 0.0
	active = true
	hold_last = false
	held = false
	on_typed = Callable()
	visible = true
	queue_redraw()


## Ask mode (yes/no prompts): earlier pages advance normally, but when the FINAL page finishes
## typing, `typed` fires and the box stays open for the menu — as pokered pops the YES/NO the
## moment the question is fully printed, without an A-press.
func show_ask(s: String) -> void:
	show_text(s)
	hold_last = true


func _page_glyphs() -> int:
	if page_idx < 0 or page_idx >= pages.size():
		return 0
	var n := 0
	for ch in str(pages[page_idx]):
		if ch != "\n":
			n += 1
	return n


func _process(delta: float) -> void:
	# Typewriter only. Input (advance/close) is driven by Player so a single
	# keypress can't both close this box and re-open it on the same frame.
	if active and revealed < _page_glyphs():
		revealed += speed * delta
		queue_redraw()
	if active and page_idx == pages.size() - 1 and revealed >= _page_glyphs() \
			and on_typed.is_valid():
		var cb := on_typed
		on_typed = Callable()
		cb.call()
	if active and hold_last and page_idx == pages.size() - 1 and revealed >= _page_glyphs():
		active = false
		hold_last = false
		held = true                        # the box stays visible under the menu
		queue_redraw()
		typed.emit()


## Modal input (called by Player while this box is the active modal). A or B advance/close, as in Gen 1.
func handle_input() -> void:
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
		advance()


## Finish typing, or go to the next page, or close. Returns false when it closed.
func advance() -> bool:
	if revealed < _page_glyphs():
		revealed = _page_glyphs()          # finish typing this page
	elif page_idx < pages.size() - 1:
		page_idx += 1                      # next page
		revealed = 0.0
	elif hold_last or held:
		pass                               # an ask page holds; the menu takes over from here
	else:
		_close()
		return false
	queue_redraw()
	return true


func _close() -> void:
	active = false
	visible = false
	closed.emit()


func _draw() -> void:
	Frame.draw(self, frame_tex, 0, 96, 20, 6, LIGHT)   # rows 12-17, full width
	var shown := int(revealed)
	var count := 0
	var x := MARGIN_X
	var line := 0
	for ch in str(pages[page_idx]):
		if ch == "\n":
			line += 1
			x = MARGIN_X
			continue
		if count >= shown:
			break
		count += 1
		if ch != " " and charmap.has(ch) and line < LINE_Y.size():
			var t: int = charmap[ch]
			var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, LINE_Y[line], GLYPH, GLYPH), src)
		x += GLYPH
	# advance arrow (▼) at the bottom-right once the page is fully typed (asks hold arrowless)
	if shown >= _page_glyphs() and not (hold_last or held) \
			and page_idx <= pages.size() - 1:
		var ax := 145.0
		var ay := 134.0
		draw_colored_polygon([Vector2(ax, ay), Vector2(ax + 6, ay), Vector2(ax + 3, ay + 3)], DARK)
