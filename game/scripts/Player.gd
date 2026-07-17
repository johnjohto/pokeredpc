extends Node2D
## Grid-based overworld player: Gen-1 walking sprite, ledge hops, and the
## tall-grass leg-overlap effect.
##
## red.png is a 16x96 strip of six 16x16 frames:
##   0 down(stand) 1 up(stand) 2 side(stand) 3 down(walk) 4 up(walk) 5 side(walk)
## Side frames face LEFT in the source; RIGHT is the same frame flipped.

signal moved(cell: Vector2i)

const CELL := 16
# A walk step is 8 overworld ticks of 2 px; the overworld loop runs two DelayFrames per tick
# (home/overworld.asm), so one tile = 16 V-blanks ≈ 0.268 s. The bicycle is 2x (step_scale 0.5).
const STEP_TIME := 0.268
const TURN_TIME := 0.08    # brief turn-in-place before walking a new direction
# The ledge hop steps through its 16 PlayerJumpingYScreenCoords entries one per overworld tick:
# 32 V-blanks ≈ 0.536 s for the 2-tile jump (engine/overworld/player_animations.asm).
const JUMP_TIME := 0.536
const ARC := 12.0          # ledge hop peak height (px)
const SPRITE_Y_OFFSET := -4.0   # overworld sprites draw 4px above the tile grid (movement.asm)

enum { DOWN, UP, LEFT, RIGHT }
const STAND := { DOWN: 0, UP: 1, LEFT: 2, RIGHT: 2 }
const WALK := { DOWN: 3, UP: 4, LEFT: 5, RIGHT: 5 }
const DIR_NAME := { DOWN: "down", UP: "up", LEFT: "left", RIGHT: "right" }

var game                   # Main: is_walkable / ledge_match / try_push_boulder / audio
var cell: Vector2i
var placed := false
var moving := false
var jumping := false
var facing := DOWN
var _step_t := 0.0          # elapsed time within the current step (drives the walk cycle)
var _step_dur := 0.18       # duration of the current step (so the 4-phase cycle fits one step)
var step_scale := 1.0       # < 1 speeds up walking (the bicycle is 0.5 = 2x)
var turn_cooldown := 0.0
var spr: Sprite2D
var _sheet := "red"          # which sprite sheet is loaded: red / red_bike / seel (gh #161, #170)
var cam: Camera2D           # the follow camera (Main.shake_elevator judders its offset)


func setup(game_ref) -> void:
	game = game_ref
	spr = Sprite2D.new()
	spr.texture = load("res://assets/sprites/red.png")
	spr.centered = false
	spr.region_enabled = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.offset.y = SPRITE_Y_OFFSET     # sprites sit 4px above the tile grid (movement.asm YPixels-4)
	add_child(spr)
	# (The tall-grass leg overlap is Main.grass_overlay: the map tiles under the sprite's
	# lower half redraw over it, per the GB's OAM grass priority — sprite_oam.asm.)
	cam = Camera2D.new()
	# The GB view puts the player sprite at screen (64, 60) — 8 px LEFT of centre — so the
	# camera sits half a tile right of the player's cell centre (gh #38).
	cam.position = Vector2(CELL / 2.0 + 8.0, CELL / 2.0)
	add_child(cam)
	cam.make_current()


func place(c: Vector2i, keep_facing := false) -> void:
	cell = c
	position = Vector2(cell * CELL)
	if not keep_facing:
		facing = DOWN
	moving = false
	jumping = false
	turn_cooldown = 0.0
	placed = true
	spr.position.y = 0
	# Standing where you were put never warps until you step off and back on (pokered arms warps
	# the same way on arrival). Callers used to sync game.warp_armed themselves; a direct place()
	# onto a warp cell left it stale-armed, and the first directional press fired the warp via the
	# gh #80 standing-warp branch — how the --b4f harness teleported itself up the hideout stairs.
	if game:
		game.warp_armed = game._warp_at(cell) == null
	_update_sprite()
	queue_redraw()


## Glide onto a cell (SURF mount) keeping facing, instead of teleporting.
func surf_hop(c: Vector2i) -> void:
	var from := position
	cell = c
	placed = true
	moving = true
	_step_t = 0.0
	_step_dur = STEP_TIME
	position = from
	_update_sprite()
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(cell * CELL), STEP_TIME)
	tw.finished.connect(func() -> void:
		moving = false
		_update_sprite())


func _input_dir() -> int:
	if Input.is_action_pressed("ui_up"):
		return UP
	if Input.is_action_pressed("ui_down"):
		return DOWN
	if Input.is_action_pressed("ui_left"):
		return LEFT
	if Input.is_action_pressed("ui_right"):
		return RIGHT
	return -1


func front_cell() -> Vector2i:
	return cell + _delta(facing)


const SPIN_NEXT := {DOWN: LEFT, LEFT: UP, UP: RIGHT, RIGHT: DOWN}   # SpinnerPlayerFacingDirections
var spinning := false              # sliding across spin tiles: the facing whirls, no walk anim
var _spin_t := 0.0


func _process(delta: float) -> void:
	if spinning:
		_spin_t += delta               # the facing advances every overworld tick (2 V-blanks)
		if _spin_t >= 2.0 / 60.0:
			_spin_t = 0.0
			facing = SPIN_NEXT[facing]
			_update_sprite()
	if moving:
		_step_t += delta                 # advance the walk cycle through the 4 phases mid-step
		_update_sprite()
	if moving or not placed:
		return
	# All modal/overworld input is read here, once per frame, so opening and
	# closing a modal can't double-fire on the same keypress.
	if game.modal != null:
		# START toggles the start menu closed (B/cancel still backs out via the menu itself).
		if game.modal == game.menu and game.menu_mode == "start" and Input.is_action_just_pressed("p_start"):
			game.menu.chosen.emit(-1)
		else:
			game.modal.handle_input()
		return
	if game.cutscene_active:
		return                          # a cutscene is driving; no free movement/interact
	if Input.is_action_just_pressed("p_start"):   # START opens the menu (B does nothing in the field)
		game.open_start_menu()
		return
	if Input.is_action_just_pressed("ui_accept"):
		game.interact(self)
		return
	var want := _input_dir()
	if want == -1:
		turn_cooldown = 0.0
		return
	if want != facing:
		facing = want
		turn_cooldown = TURN_TIME
		game._boulder_reset_tried()   # turning away restarts the STRENGTH two-push count (gh #129)
		_update_sprite()
		return
	if turn_cooldown > 0.0:
		turn_cooldown -= delta
		return

	# gh #80: standing on a warp and pressing a qualifying direction fires it — pokered's
	# CheckWarpsNoCollision warps on the held direction (ExtraWarpCheck: facing the map edge / a warp
	# tile in front), even when the step itself is blocked (walking into the map edge to leave a
	# building). warp_armed guards against re-warping the instant you arrive standing on one.
	if game.warp_armed and game._warp_at(cell) != null and game._warp_should_fire(cell):
		game._do_warp(game._warp_at(cell))
		return

	var d := _delta(facing)
	if game.ledge_match(cell, DIR_NAME[facing], d):
		_ledge_jump(d)
		return
	var target := cell + d
	# pokered CollisionCheckOnLand order: a sprite (NPC/boulder) in front is checked BEFORE the tile-pair
	# rule, so a shove is routed to try_push_boulder — which applies pokered's OWN push collision check
	# (CheckForCollisionWhenPushingBoulder, including its tile-pair test on the boulder's destination),
	# not the player-step tile-pair rule below.
	if game._npc_at(target) != null:
		if not game.try_push_boulder(target, d):     # STRENGTH: shove a boulder out of the way
			_bump_step()                              # a solid sprite — full walk-in-place step (#16)
			return
	elif game._tile_pair_blocked(cell, target):       # no sprite: CheckForTilePairCollisions (gh #105)
		_bump_step()                                  # elevation edge (cavern/forest): can't cross here
		return
	elif not game.is_walkable(target):
		_bump_step()
		return
	elif game._warp_at(target) != null and not game._cell_walkable(target) and not game._warp_should_fire(target, facing):
		# gh #149: a warp set into a SOLID tile (a gate door in a wall, e.g. Route 7's (11,9)) is only
		# enterable from the side that fires it (pokered's ExtraWarpCheck) — you enter the gate via the
		# adjacent walkable mat. is_walkable() treats every warp tile as open, so without this you could
		# walk straight onto the solid door from any other direction and just stand on it. The tile is
		# impassable in pokered whether or not it carries a warp, so bump unless this step would warp.
		_bump_step()
		return
	cell = target
	moving = true
	_step_t = 0.0
	_step_dur = STEP_TIME * step_scale
	_update_sprite()
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(cell * CELL), STEP_TIME * step_scale)
	tw.finished.connect(func() -> void:
		moving = false
		_update_sprite()
		moved.emit(cell))


## Gen 1 wall bump: a full walk-in-place step (with the collision SFX), then back to stand, so the
## animation finishes instead of freezing mid-step (#16). `moving` locks input for the step's duration.
func _bump_step() -> void:
	moving = true
	_step_t = 0.0
	_step_dur = STEP_TIME
	_update_sprite()
	if game.audio:                                    # home/overworld.asm .collision plays SFX_COLLISION
		game.audio.play_sfx("collision")
	var tw := create_tween()
	tw.tween_interval(STEP_TIME)
	tw.finished.connect(func() -> void:
		moving = false
		_update_sprite())


## Emotion bubble one tile above the player (the "!" of Oak's intercept — EmotionBubble
## over sprite index 0). Same visuals as NPC.show_emote.
var _emote: Sprite2D

func show_emote(emote_name: String) -> void:
	if _emote == null:
		_emote = Sprite2D.new()
		_emote.centered = false
		_emote.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_emote.position = Vector2(0, -CELL)
		_emote.z_index = 1
		add_child(_emote)
	_emote.texture = load("res://assets/sprites/emote_%s.png" % emote_name)
	_emote.visible = true


func hide_emote() -> void:
	if _emote:
		_emote.visible = false


## Turn to face a direction without moving (cutscene helper).
func face(dir: int) -> void:
	facing = dir
	_update_sprite()


## Turn to face a target cell (cutscene helper).
func face_to(target: Vector2i) -> void:
	var d := target - cell
	if abs(d.x) > abs(d.y):
		face(RIGHT if d.x > 0 else LEFT)
	else:
		face(DOWN if d.y > 0 else UP)


## Forced single-step for cutscenes: face `dir` and walk one cell, ignoring collision and
## without firing `moved` (no warp/encounter side-effects). `await`-able. `dur` overrides the
## step duration (walk_together paces the player to the slower NPC lead).
func step(dir: int, dur := 0.0) -> void:
	if dur <= 0.0:
		dur = STEP_TIME
	if not spinning:                   # a sliding player keeps whirling instead of facing the way
		facing = dir
	cell += _delta(dir)
	moving = true
	_step_t = 0.0
	_step_dur = dur
	_update_sprite()
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(cell * CELL), dur)
	await tw.finished
	moving = false
	_update_sprite()


func _ledge_jump(d: Vector2i) -> void:
	cell += d * 2
	moving = true
	jumping = true
	_step_t = 0.0
	_step_dur = JUMP_TIME
	_update_sprite()
	queue_redraw()              # draw the shadow
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(cell * CELL), JUMP_TIME)
	var arc := create_tween()   # body arcs up then down over the ground-level shadow
	arc.tween_property(spr, "position:y", -ARC, JUMP_TIME * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc.tween_property(spr, "position:y", 0.0, JUMP_TIME * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.finished.connect(func() -> void:
		moving = false
		jumping = false
		spr.position.y = 0
		_update_sprite()
		queue_redraw()          # clear the shadow
		moved.emit(cell))


func _delta(f: int) -> Vector2i:
	match f:
		UP: return Vector2i(0, -1)
		DOWN: return Vector2i(0, 1)
		LEFT: return Vector2i(-1, 0)
		_: return Vector2i(1, 0)


func _update_sprite() -> void:
	# wWalkBikeSurfState picks the loaded sheet (home/overworld.asm LoadPlayerSpriteGraphics):
	# walking = RedSprite, biking = RedBikeSprite (gh #161), surfing = SeelSprite — Gen 1's
	# surfing player literally rides the SEEL overworld sprite (gh #170).
	if game:
		var sheet: String = "seel" if game.surfing else ("red_bike" if game.riding else "red")
		if sheet != _sheet:
			_sheet = sheet
			spr.texture = load("res://assets/sprites/%s.png" % sheet)
	var frame: int
	var flip := false
	if moving and not spinning:
		# Gen-1 walk cycle (UpdateSpriteInWalkingAnimation): within each step the leg swings out
		# (walk) then plants (stand), and the forward foot alternates every tile — so the legs open
		# and close and both feet show, instead of one held frame.
		var walking := _step_t < _step_dur * 0.5
		var foot := ((cell.x + cell.y) & 1) == 1
		match facing:
			DOWN, UP:
				frame = WALK[facing] if walking else STAND[facing]
				flip = walking and foot
			LEFT:
				frame = WALK[LEFT] if walking else STAND[LEFT]
			RIGHT:
				frame = WALK[RIGHT] if walking else STAND[RIGHT]
				flip = true
	else:
		frame = STAND[facing]
		flip = facing == RIGHT
	spr.region_rect = Rect2(0, frame * 16, 16, 16)
	spr.flip_h = flip


func _draw() -> void:
	if jumping:
		# Gen-1 ledge shadow: a full flat oval (gfx/overworld/shadow.png is one quarter, mirrored both
		# ways — the tile is the top half; the widest row is the vertical centre) at the feet (#13).
		var c := Color(0.133, 0.188, 0.224)
		var rows := [[5, 6], [3, 10], [2, 12], [1, 14], [2, 12], [3, 10], [5, 6]]   # [x, width] per row
		for i in rows.size():
			draw_rect(Rect2(rows[i][0], 9 + i, rows[i][1], 1), c)
