extends Node2D
## A non-player overworld character. Renders a facing sprite (6-frame walking
## sheet) or a static object (1-frame sheets like poké balls / boulders), and
## optionally wanders within a small radius of its spawn.

const CELL := 16
# NPCs walk 1 px per overworld tick, 16 ticks per tile; the overworld loop runs two DelayFrames
# per tick, so a step is 32 V-blanks ≈ 0.536 s (movement.asm UpdateSpriteInWalkingAnimation).
const STEP_TIME := 0.536

enum { DOWN, UP, LEFT, RIGHT }
const STAND := { DOWN: 0, UP: 1, LEFT: 2, RIGHT: 2 }
const WALK := { DOWN: 3, UP: 4, LEFT: 5, RIGHT: 5 }
const DIRV := { DOWN: Vector2i(0, 1), UP: Vector2i(0, -1), LEFT: Vector2i(-1, 0), RIGHT: Vector2i(1, 0) }
const TETHER := 4          # max tiles a wanderer strays from home

var game
var home: Vector2i
var cell: Vector2i
var facing := DOWN
var frames := 6
var wander := false
var allowed: Array = []    # dir enums a wanderer may pick
var text_id := ""
var file := ""
var trainer_class := ""      # OPP_* if this NPC is a trainer, else ""
var trainer_num := 0
var sight := 0               # trainer line-of-sight range in tiles (0 = never spots on sight)
var battle_text := ""        # shown before the battle (when spotted or talked to undefeated)
var end_text := ""           # shown right after the player wins the battle
var after_text := ""         # shown when talked to after being defeated
var key := ""                # object id (e.g. "OAKSLAB_OAK1") for cutscene show/hide lookups
var item := ""               # display name of the item this ball holds (overworld item ball)
var wild_species := ""       # a stationary catchable mon (legendary), else ""
var wild_level := 0
var shown := true            # hidden objects don't render, block, wander, or interact
var moving := false
var _phase := 0              # intra-step animation phase 0-3 (frame advances every 4 of 16 ticks)
var spr: Sprite2D
var _t := 0.0
var _next := 0.0


func setup(game_ref, sprite_file: String, data: Dictionary) -> void:
	game = game_ref
	file = sprite_file
	frames = int(data["frames"])
	cell = data["cell"]
	home = cell
	facing = int(data["facing"])
	wander = bool(data["wander"])
	allowed = data["allowed"]
	text_id = str(data["text"])
	position = Vector2(cell * CELL)
	spr = Sprite2D.new()
	spr.texture = load("res://assets/sprites/%s.png" % sprite_file)
	spr.centered = false
	spr.region_enabled = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.offset.y = -4     # overworld sprites sit 4px above the tile grid (movement.asm YPixels-4)
	add_child(spr)
	_reset_timer()
	_update_sprite()


## Show or hide this object (cutscene-controlled visibility, mirrors Show/HideObject).
func set_shown(v: bool) -> void:
	shown = v
	visible = v


func _process(delta: float) -> void:
	if not wander or moving or not shown or game.modal != null or game.cutscene_active:
		return
	_t += delta
	if _t < _next:
		return
	_reset_timer()
	if allowed.is_empty():
		return
	var dir: int = allowed[randi() % allowed.size()]
	facing = dir
	var target: Vector2i = cell + DIRV[dir]
	if abs(target.x - home.x) > TETHER or abs(target.y - home.y) > TETHER \
			or not game.npc_can_enter(target, self):
		_update_sprite()        # turn in place, don't move
		return
	cell = target
	var tw := _start_step()
	tw.finished.connect(func() -> void:
		moving = false
		_update_sprite())


## Begin the one-tile walk tween: the position glides while the animation phase steps through
## the Gen-1 cycle (stand → walk → stand → walk-mirrored, one frame per 4 overworld ticks).
func _start_step(dur := STEP_TIME) -> Tween:
	moving = true
	_phase = 0
	_update_sprite()
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(cell * CELL), dur)
	tw.parallel().tween_method(_set_step_phase, 0.0, 3.99, dur)
	return tw


func _set_step_phase(t: float) -> void:
	var ph := mini(int(t), 3)
	if ph != _phase:
		_phase = ph
		_update_sprite()


func _reset_timer() -> void:
	_t = 0.0
	# Random delay of [1,$7F] overworld ticks before the next wander step; a roll of 0 wraps to
	# $100 ticks — the occasional long pause is an original off-by-one (movement.asm).
	var ticks := randi() % 128
	if ticks == 0:
		ticks = 256
	_next = ticks * 2.0 / 60.0


## Show/hide an emotion bubble one tile above the NPC (trainer-sight "!" = "shock").
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


# Scripted (MoveSprite-style) walks run at the player's pace — 2 px per overworld tick, 8 ticks
# a tile — unlike the slow 1 px/tick ambient wander: Oak's approach and the rival's walks are
# visibly player-speed on GB.
const SCRIPT_STEP := 0.268


## Forced single-step for cutscenes: face `dir` and walk one cell. `await`-able.
func step(dir: int) -> void:
	facing = dir
	cell += DIRV[dir]
	var tw := _start_step(SCRIPT_STEP)
	await tw.finished
	moving = false
	_update_sprite()


## Turn to face a target cell (used on interaction).
func face_to(target: Vector2i) -> void:
	var d := target - cell
	if abs(d.x) > abs(d.y):
		facing = RIGHT if d.x > 0 else LEFT
	else:
		facing = DOWN if d.y > 0 else UP
	_update_sprite()


func _update_sprite() -> void:
	if frames == 1:
		spr.region_rect = Rect2(0, 0, 16, 16)   # static object (poké ball, boulder, …)
		spr.flip_h = false
		return
	# 3-frame sprites (still NPCs) have facing frames [down, up, side] but no walk frames; only
	# 6-frame sprites also animate a step. Both face via STAND[facing] (side is flipped for RIGHT).
	var f: int
	var flip := false
	if moving and frames >= 6:
		# Gen-1 walk cycle within one 16-tick step: stand, walk, stand, walk — with the second
		# walk frame mirrored for down/up so the legs alternate (movement.asm anim counter).
		var walk_frame := _phase % 2 == 1
		match facing:
			DOWN, UP:
				f = WALK[facing] if walk_frame else STAND[facing]
				flip = _phase == 3
			LEFT:
				f = WALK[LEFT] if walk_frame else STAND[LEFT]
			RIGHT:
				f = WALK[RIGHT] if walk_frame else STAND[RIGHT]
				flip = true
	else:
		f = STAND[facing]
		flip = facing == RIGHT
	spr.region_rect = Rect2(0, f * 16, 16, 16)
	spr.flip_h = flip
