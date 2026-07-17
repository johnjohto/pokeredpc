extends Control
## Screen transitions, faithful to pokered:
##  - the 8 battle wipes + the triple screen flash (engine/battle/battle_transitions.asm) —
##    each paints 8x8 tiles black on the 20x18 grid in the original order and pace, ending on
##    a fully black screen that holds until clear();
##  - the warp fade (GBFadeOutToBlack, home/fade.asm): 4 palette steps x 8 frames.
## Sits topmost in the UI layer and draws over the live (frozen) overworld.

const W := 20
const H := 18

var _cells: Array = []             # painted-black tiles, row-major W*H
var _flash := 0.0                  # palette-flash level: -1..0 darken to black, 0..1 lighten to white
var _fade := 0.0                   # warp-fade blackness 0..1
var _white := 0.0                  # battle-exit whiteness 0..1 (GBFadeInFromWhite)
var _hold := false                 # effect done: hold a solid black screen until clear()
var _snap: Texture2D               # frozen screen for shrink/split
var _snap_mode := ""               # "", "shrink", "split"
var _snap_t := 0.0                 # shrink/split progress 0..1

# The circle wipe's arc shapes (BattleTransition_CircleData1-5): alternating paint-run and
# skip-back counts, -1 ends. Each run paints c tiles stepping x, then the cursor returns to the
# run's start, steps one row, and shifts opposite the paint direction by the skip count.
const _CIRCLE := {
	1: [2, 3, 5, 4, 9, -1],
	2: [1, 1, 2, 2, 4, 2, 4, 2, 3, -1],
	3: [2, 1, 3, 1, 4, 1, 4, 1, 4, 1, 3, 1, 2, 1, 1, 1, 1, -1],
	4: [4, 1, 4, 0, 3, 1, 3, 0, 2, 1, 2, 0, 1, -1],
	5: [4, 0, 3, 0, 3, 0, 2, 0, 2, 0, 1, 0, 1, -1],
}
# The two half circles' steps (BattleTransition_HalfCircle1/2): [paint-right?, data id, x, y].
# Half 1 sweeps the top of the screen (rows step down), half 2 the bottom (rows step up).
const _HALF1 := [[true, 1, 18, 6], [true, 2, 19, 3], [true, 3, 18, 0], [true, 4, 14, 0],
	[true, 5, 10, 0], [false, 5, 9, 0], [false, 4, 5, 0], [false, 3, 1, 0],
	[false, 2, 0, 3], [false, 1, 1, 6]]
const _HALF2 := [[false, 1, 1, 11], [false, 2, 0, 14], [false, 3, 1, 17], [false, 4, 5, 17],
	[false, 5, 9, 17], [true, 5, 10, 17], [true, 4, 14, 17], [true, 3, 18, 17],
	[true, 2, 19, 14], [true, 1, 18, 11]]


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	_reset()


func _reset() -> void:
	_cells = []
	_cells.resize(W * H)
	_cells.fill(false)
	_flash = 0.0
	_fade = 0.0
	_white = 0.0
	_hold = false
	_snap = null
	_snap_mode = ""
	_snap_t = 0.0


## End the transition: drop the black screen (the next scene has been made visible).
func clear() -> void:
	visible = false
	_reset()
	queue_redraw()


## Play a battle wipe to a fully black screen (held until clear()).
func battle_wipe(kind: String) -> void:
	visible = true
	_reset()
	queue_redraw()
	match kind:
		"double_circle":
			await _flash3()
			await _circle(true)
		"circle":
			await _flash3()
			await _circle(false)
		"spiral_in":
			await _spiral(false)
		"spiral_out":
			await _spiral(true)
		"h_stripes":
			await _stripes(true)
		"v_stripes":
			await _stripes(false)
		"shrink":
			await _snap_effect("shrink")
		"split":
			await _snap_effect("split")
	_hold = true
	queue_redraw()


## GBFadeOutToBlack: 4 palette steps, 8 frames each, then hold black until clear().
func fade_black() -> void:
	visible = true
	_reset()
	await _run_steps(4, 32.0 / 60.0, func(i: int) -> void: _fade = (i + 1) / 4.0)
	_hold = true
	queue_redraw()


## GBFadeInFromBlack: the held black lifts in 4 palette steps (fade_black in reverse).
func fade_in_black() -> void:
	_hold = false
	_fade = 1.0
	queue_redraw()
	await _run_steps(4, 32.0 / 60.0, func(i: int) -> void: _fade = (3 - i) / 4.0)
	clear()


## Battle exit: the screen cuts to white over the reappearing overworld, holds a beat, then
## fades in over 3 palette steps of 8 frames (.battleOccurred's DelayFrames 10 ->
## MapEntryAfterBattle -> GBFadeInFromWhite). Ends by clearing itself.
func battle_exit() -> void:
	visible = true
	_reset()
	_white = 1.0
	queue_redraw()
	await _wait(10.0 / 60.0)
	await _run_steps(3, 24.0 / 60.0, func(i: int) -> void: _white = [0.66, 0.33, 0.0][i])
	clear()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Run `count` effect steps evenly over `dur` seconds (a tween keeps the wall-clock duration
## exact; per-step timers would accumulate a frame of slack each).
func _run_steps(count: int, dur: float, apply: Callable) -> void:
	var done := [-1]
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var i := mini(int(t), count - 1)
		while done[0] < i:
			done[0] += 1
			apply.call(done[0])
		queue_redraw(), 0.0, float(count), dur)
	await tw.finished


func _paint(x: int, y: int) -> void:
	if x >= 0 and x < W and y >= 0 and y < H:
		_cells[y * W + x] = true


const _FLASH_STEPS := [-0.33, -0.66, -1.0, -0.66, -0.33, 0.0, 0.33, 0.66, 1.0, 0.66, 0.33, 0.0]


## The triple flash (BattleTransition_FlashScreen): the whole palette cycles normal -> black ->
## normal -> white -> normal, 2 frames per step, 3 times (72 frames).
func _flash3() -> void:
	await _run_steps(36, 72.0 / 60.0, func(i: int) -> void: _flash = _FLASH_STEPS[i % 12])
	_flash = 0.0


## The trainer spirals. Outward (stronger enemy): a square spiral from the center tile (10,10),
## 3 tiles per frame for 120 frames. Inward: the perimeter inward (down the left edge first),
## with the screen updated every 7 tiles at 3-frame steps.
func _spiral(outward: bool) -> void:
	var order: Array = []
	if outward:
		var x := 10
		var y := 10
		var dirs := [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1)]
		var arm := 1
		var d := 0
		order.append(Vector2i(x, y))
		while order.size() < 440:                     # walk far enough to cover the 20x18 screen
			for leg in 2:
				for i in arm:
					x += dirs[d].x
					y += dirs[d].y
					order.append(Vector2i(x, y))
				d = (d + 1) % 4
			arm += 1
	else:
		var left := 0
		var right := W - 1
		var top := 0
		var bottom := H - 1
		while left <= right and top <= bottom:
			for y in range(top, bottom + 1):          # down the left edge
				order.append(Vector2i(left, y))
			for x in range(left + 1, right + 1):      # right along the bottom
				order.append(Vector2i(x, bottom))
			for y in range(bottom - 1, top - 1, -1):  # up the right edge
				order.append(Vector2i(right, y))
			for x in range(right - 1, left, -1):      # left along the top
				order.append(Vector2i(x, top))
			left += 1
			right -= 1
			top += 1
			bottom -= 1
	# outward: 3 walk steps per frame for 120 frames; inward: 7 tiles per 3 frames (~154 frames)
	var frames := 120.0 if outward else order.size() * 3.0 / 7.0
	await _run_steps(order.size(), frames / 60.0,
		func(i: int) -> void: _paint(order[i].x, order[i].y))


## One arc step of the circle wipe (BattleTransition_Circle_Sub3).
func _paint_arc(right: bool, down: bool, data: Array, x: int, y: int) -> void:
	var k := 0
	while true:
		var c: int = data[k]
		k += 1
		var px := x
		for i in c:
			_paint(px, y)
			px += 1 if right else -1
		y += 1 if down else -1
		var skip: int = data[k]
		k += 1
		if skip == -1:
			return
		x += -skip if right else skip


## The wild-battle circle sweep. Double (weaker enemy): both half circles at once, 10 steps.
## Single (stronger): half 1 then half 2, 20 steps. 3 frames per step.
func _circle(double: bool) -> void:
	if double:
		await _run_steps(10, 30.0 / 60.0, func(i: int) -> void:
			_circle_step(_HALF1[i], true)
			_circle_step(_HALF2[i], false))
		return
	await _run_steps(20, 60.0 / 60.0, func(i: int) -> void:
		_circle_step(_HALF1[i] if i < 10 else _HALF2[i - 10], i < 10))


func _circle_step(s: Array, down: bool) -> void:
	_paint_arc(s[0], down, _CIRCLE[s[1]], s[2], s[3])
	# The CircleData5 arms (the near-vertical steps beside the pivot) stop one row short of it,
	# leaving 4 tiles at the screen center that the GB only blacks with the final whole-palette
	# blackout. Extend them one row so the sweep consumes the pivot too (a deliberate 4-tile
	# deviation — it reads as a hole at modern clarity).
	if s[1] == 5:
		_paint(s[2], 7 if down else 10)


## The dungeon wild-battle combs: interlaced stripes closing from both ends, 3 frames per step.
## "Horizontal" fills the even rows left-to-right and the odd rows right-to-left, one column per
## step; "vertical" the even columns top-down and odd columns bottom-up, one row per step.
func _stripes(horizontal: bool) -> void:
	if horizontal:
		await _run_steps(W, W * 3.0 / 60.0, func(i: int) -> void:
			for r in range(0, H, 2):
				_paint(i, r)
			for r in range(1, H, 2):
				_paint(W - 1 - i, r))
		return
	await _run_steps(H, H * 3.0 / 60.0, func(i: int) -> void:
		for c in range(0, W, 2):
			_paint(c, i)
		for c in range(1, W, 2):
			_paint(c, H - 1 - i))


## The dungeon trainer-battle collapses, drawn from a frozen screen grab: "shrink" squeezes the
## image into the center over 9 steps; "split" slides the four quadrants apart. Both end on
## black held an extra 10 frames.
func _snap_effect(mode: String) -> void:
	var img := get_viewport().get_texture().get_image()
	_snap = ImageTexture.create_from_image(img)
	_snap_mode = mode
	await _run_steps(9, 54.0 / 60.0, func(i: int) -> void: _snap_t = (i + 1) / 9.0)
	_snap_mode = ""
	_hold = true
	queue_redraw()
	await _wait(10.0 / 60.0)


func _draw() -> void:
	if _hold:
		draw_rect(Rect2(0, 0, 160, 144), Color.BLACK)
		return
	if _snap_mode != "" and _snap:
		draw_rect(Rect2(0, 0, 160, 144), Color.BLACK)
		if _snap_mode == "shrink":
			var w := 160.0 * (1.0 - _snap_t)
			var h := 144.0 * (1.0 - _snap_t)
			draw_texture_rect(_snap, Rect2((160.0 - w) / 2.0, (144.0 - h) / 2.0, w, h), false)
		else:                                          # split: quadrants slide diagonally apart
			var d := 80.0 * _snap_t
			var sw := _snap.get_width() / 2.0
			var sh := _snap.get_height() / 2.0
			draw_texture_rect_region(_snap, Rect2(-d, -d, 80, 72), Rect2(0, 0, sw, sh))
			draw_texture_rect_region(_snap, Rect2(80 + d, -d, 80, 72), Rect2(sw, 0, sw, sh))
			draw_texture_rect_region(_snap, Rect2(-d, 72 + d, 80, 72), Rect2(0, sh, sw, sh))
			draw_texture_rect_region(_snap, Rect2(80 + d, 72 + d, 80, 72), Rect2(sw, sh, sw, sh))
		return
	for y in H:
		for x in W:
			if _cells[y * W + x]:
				draw_rect(Rect2(x * 8, y * 8, 8, 8), Color.BLACK)
	if _flash < 0.0:
		draw_rect(Rect2(0, 0, 160, 144), Color(0, 0, 0, -_flash))
	elif _flash > 0.0:
		draw_rect(Rect2(0, 0, 160, 144), Color(1, 1, 1, _flash))
	if _fade > 0.0:
		draw_rect(Rect2(0, 0, 160, 144), Color(0, 0, 0, _fade))
	if _white > 0.0:
		draw_rect(Rect2(0, 0, 160, 144), Color(1, 1, 1, _white))
