extends Control
## The battle HOST (presentation + flow): draws the scene, runs the action/move/
## party menus and the message pump, and plays the ordered event stream. The
## MECHANICS — state, turn resolution, move execution, AI, catch, EXP — live in
## the ruleset's battle module (Gen1Battle, gh #33/ADR-018); this node forwards
## the battle state via properties and delegates the mechanics calls, so the
## test harness and link plumbing keep their surface.
##
## Persistent party mons are built by Main (make_mon); the battle mutates their
## hp/exp/level in place, so progress carries back to the overworld.

signal finished

const DARK := Color(0.133, 0.188, 0.224)
const LIGHT := Color(0.918, 0.984, 0.808)
const HPFILL := Color(0.396, 0.541, 0.447)
const GLYPH := 8
var speed := 20.0            # glyphs/s: 60 / letter-delay frames (the OPTION text-speed setting)
const MAXCHARS := 18         # glyphs that fit on one line of the message box
# (move/stage/crit data tables live in the gen1 ruleset now — gh #32/#33)

# gh #33 (ADR-018): the battle STATE lives in the ruleset's battle module (Gen1Battle);
# these properties forward reads/writes so presentation, the test harness, and the link
# plumbing keep their surface. Mechanics functions migrate there cluster by cluster.
var mech                    # the ruleset battle module session (rset.battle, bound in setup)
var p_stages: Dictionary:
	get: return mech.p_stages
	set(v): mech.p_stages = v
var e_stages: Dictionary:
	get: return mech.e_stages
	set(v): mech.e_stages = v
var p_vol: Dictionary:
	get: return mech.p_vol
	set(v): mech.p_vol = v
var e_vol: Dictionary:
	get: return mech.e_vol
	set(v): mech.e_vol = v
var _eff_re: RegEx:
	get: return mech._eff_re
	set(v): mech._eff_re = v

var main                    # Main: make_mon / exp_for_level / recompute_stats / heal_party
var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var base_stats: Dictionary:
	get: return mech.base_stats
	set(v): mech.base_stats = v
var moves_db: Dictionary:
	get: return mech.moves_db
	set(v): mech.moves_db = v
var rset: Ruleset               # the seam (gh #31, ADR-018): types resolve through it

var party: Array:
	get: return mech.party
	set(v): mech.party = v
var active: int:
	get: return mech.active
	set(v): mech.active = v
var participants: Array:   # party indices that fought the current enemy (for EXP split)
	get: return mech.participants
	set(v): mech.participants = v
var learn_move: String:    # move pending the "delete a move?" prompt
	get: return mech.learn_move
	set(v): mech.learn_move = v
var player_mon: Dictionary:
	get: return mech.player_mon
	set(v): mech.player_mon = v
var enemy_mon: Dictionary:
	get: return mech.enemy_mon
	set(v): mech.enemy_mon = v
var enemy_party: Array:    # trainer battles: enemy's whole team
	get: return mech.enemy_party
	set(v): mech.enemy_party = v
var enemy_active: int:
	get: return mech.enemy_active
	set(v): mech.enemy_active = v
var is_trainer: bool:
	get: return mech.is_trainer
	set(v): mech.is_trainer = v
var is_safari: bool:       # Safari Zone battle: BALL/BAIT/ROCK/RUN, no fighting, the mon may flee
	get: return mech.is_safari
	set(v): mech.is_safari = v
var demo := false              # BATTLE_TYPE_OLD_MAN: the catching tutorial plays itself (no player mon)
var _demo_ran := false         # the scripted menu keystrokes have fired
var run_attempts: int:     # wNumRunAttempts: each failed try adds 30 to the next escape roll
	get: return mech.run_attempts
	set(v): mech.run_attempts = v
var _item_scroll := 0          # the battle bag list's scroll window (4 visible)
var newly_caught: bool:    # this catch is a first-time species (dex entry shows after)
	get: return mech.newly_caught
	set(v): mech.newly_caught = v
var doll_escape: bool:     # fled via POKé DOLL: wBattleResult stays 0 (the MAROWAK trick)
	get: return mech.doll_escape
	set(v): mech.doll_escape = v
# Gen-1 trainer AI (engine/battle/trainer_ai.asm) state lives on the module too.
var ai_mods: Array:
	get: return mech.ai_mods
	set(v): mech.ai_mods = v
var ai_kind: String:
	get: return mech.ai_kind
	set(v): mech.ai_kind = v
var ai_count_max: int:
	get: return mech.ai_count_max
	set(v): mech.ai_count_max = v
var _ai_uses: int:
	get: return mech._ai_uses
	set(v): mech._ai_uses = v
var _ai_turn: int:         # enemy moves taken (wAILayer2Encouragement)
	get: return mech._ai_turn
	set(v): mech._ai_turn = v
var ghost: bool:           # unidentified GHOST (Pokémon Tower, no SILPH SCOPE): can't be fought
	get: return mech.ghost
	set(v): mech.ghost = v
var unveil: bool:          # the scripted MAROWAK: appears as GHOST until the SILPH SCOPE reveal
	get: return mech.unveil
	set(v): mech.unveil = v
var _ghost_tex: Texture2D      # the GHOST battle pic (gfx/battle/ghost.png)
var _oldman_tex: Texture2D     # the OLD MAN's back pic (the catching tutorial)
var _fbe_tex: Texture2D        # condensed glyphs (font_battle_extra)
var _icons_tex: Texture2D      # party mini icons
var _icons_map := {}
var safari_bait: int:      # "eating" counter (less likely to flee)
	get: return mech.safari_bait
	set(v): mech.safari_bait = v
var safari_escape: int:    # "angry" counter (more likely to flee)
	get: return mech.safari_escape
	set(v): mech.safari_escape = v
var safari_catch: int:     # current (bait/rock-modified) catch rate
	get: return mech.safari_catch
	set(v): mech.safari_catch = v
var trainer_name: String:
	get: return mech.trainer_name
	set(v): mech.trainer_name = v
var prize: int:
	get: return mech.prize
	set(v): mech.prize = v
var won: bool:             # true once the battle is won (vs blackout)
	get: return mech.won
	set(v): mech.won = v
var caught: bool:          # true once the enemy mon is caught (a ball succeeded)
	get: return mech.caught
	set(v): mech.caught = v
var blacked_out: bool:     # true if the player ran out of usable mons
	get: return mech.blacked_out
	set(v): mech.blacked_out = v
var no_blackout: bool:     # story battles (first rival) that heal + continue instead of whiting out
	get: return mech.no_blackout
	set(v): mech.no_blackout = v
var _flash_who := ""          # "enemy"/"player" sprite currently blinking from a hit
var _flash_on := true         # false during the blink's off-phase
var trainer_pic_tex: Texture2D # the opponent's battle pic (trainer battles), shown at intro + defeat
var trainer_pic_x := 999.0     # x of the trainer pic; >=160 = off-screen (drawn where the mon goes)
var _trainer_intro := false    # during "wants to fight": only the trainer is on screen (no mons/HUD)
# Battle-start sequence (SlidePlayerAndEnemySilhouettesOnScreen + SendOutMon):
var _trainer_back_tex: Texture2D   # Red's back pic, shown until the mon is sent out
var _balls_tex: Texture2D          # party status pokeballs
var _poof_steps: Array = []        # the send-out poof, straight from POOF_ANIM's frame blocks
# The fixed pic windows (7x7 tiles enemy / the 2x back box): slides clip at their edges, as
# the GB's tilemap does — pixels outside the box never change.
const ENEMY_BOX := Rect2(96, -2, 56, 56)
const PLAYER_BOX := Rect2(8, 40, 64, 64)
# AnimationWavyScreen (Psychic/Confusion/Psywave/Night Shade): the frozen screen is scrolled per
# scanline by these horizontal pixel offsets (WavyScreenLineOffsets, "vaguely a sine wave"), the wave
# advancing one row per frame for 255 frames (ld c, $ff). rSCX is the BG X shown at screen x=0, so a
# row with offset o draws shifted left by o. See engine/battle/animations.asm:1929.
const WAVY_OFFSETS := [0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1,
	0, 0, 0, 0, 0, -1, -1, -1, -2, -2, -2, -2, -2, -1, -1, -1]
const WAVY_FRAMES := 255
# Per-move attack animations (gh #19 phases 2-3): pokered's DrawFrameBlock subanimation system,
# data-driven from move_anims.json (docs/data-formats/battle-anims.md). _anim_sprites is the
# shadow-OAM of the current visual frame — [sheet, tile, x, y, xflip, yflip] per sprite — drawn
# over everything (text box included) like Gen-1 OAM sprites. The special-effect commands set
# the _anim_* render state below (screen palette/flash, hidden pics, pic offsets, BG shake).
var _manim := {}                   # move_anims.json
var _manim_tex := {}               # tile-sheet name -> Texture2D
var _anim_sprites: Array = []
var _anim_pal := ""                # "", "dark", "light": SE_*_SCREEN_PALETTE overlay
var _anim_flash := false           # screen-flash overlay on (SE_DARK_SCREEN_FLASH)
var _anim_hidden := {"player": false, "enemy": false}   # pics hidden by SEs (hide/slide-off)
var _anim_off := {"player": Vector2.ZERO, "enemy": Vector2.ZERO}   # pic offsets (lunges/slides)
var _anim_scale := {"player": Vector2.ONE, "enemy": Vector2.ONE}   # pic squish/minimize scaling
var _sub_shown := {"player": false, "enemy": false}   # the SUBSTITUTE doll replaces the pic
var _monster_tex: Texture2D        # the MonsterSprite doll (AnimationSubstitute)
var _invert: ColorRect             # true palette-invert overlay (AnimationFlashScreen)
var _anim_mon_dark := {"player": false, "enemy": false}   # darken_mon_palette (pic-only dim)
var _growl_trail: Array = []       # Growl's doubled note (OAM 0-3 copied to 4-7)
var _anim_hud_off := Vector2.ZERO   # enemy HUD offset (SE_SHAKE_ENEMY_HUD)
var _fx: Array = []                 # transient SE particles: {"pos": Vector2, "kind": String}
var _anim_shake := Vector2.ZERO    # BG offset while a screen shake runs (GB rSCX/rSCY: OAM unaffected)
var _wavy_tex: Texture2D = null    # AnimationWavyScreen: the frozen frame, redrawn per-scanline-shifted
var _wavy_phase := 0               # the wave's row phase (advances one per frame)
var _auto_msg := false             # the current msg auto-advances once revealed (Gen-1 intro texts)
var _intro_stage := ""             # "" outside the intro; else the current intro stage name
var _intro_egrow := 0.0            # sent-out enemy mon grow fraction (AnimateSendingOutMon); 0 = hidden
var _intro_pback_x := 8.0          # player back/trainer pic x during the slide
var _intro_efront_x := 96.0        # enemy front pic x during the slide
var _intro_ball_t := 0.0           # ball-throw + mon-grow progress (0..1)
var _intro_pokeballs := false      # the player party-pokeball bracket is up
var _intro_enemy_hud := false      # the enemy HUD has appeared
var _intro_player_hud := false     # the player HUD has appeared
var _flee_pending: bool:   # Teleport/Whirlwind used in a wild battle
	get: return mech._flee_pending
	set(v): mech._flee_pending = v
var front_tex: Texture2D
var back_tex: Texture2D
var frame_tex: Texture2D        # fancy Gen-1 textbox border for the message / menu boxes
var hud_tex: Texture2D          # battle HUD tile row $62-$7f (HP:, :L, bar caps)

var state := ""             # "msg" | "menu" | "moves" | "party" | "party_forced" | "item" | "mimic"
var bag_keys: Array = []     # item names currently shown in the ITEM menu
var _move_swap := -1         # move row "held" by SELECT for reordering (SwapMovesInMenu)
var _item_swap := -1         # battle-bag row "held" by SELECT (the bag is ITEMLISTMENU in battle too)
var _mimic_moves: Array = [] # the target's moves offered by MIMIC's pick menu (gh #65)
var _mimic_slot := 0         # the battle-move slot the picked move lands in (MIMIC's own)
var can_evolve: Array:     # party indices that leveled this battle (wCanEvolveFlags, gh #67)
	get: return mech.can_evolve
	set(v): mech.can_evolve = v
var menu_items := ["FIGHT", "PKMN", "ITEM", "RUN"]
const SAFARI_MENU := ["BALL", "BAIT", "ROCK", "RUN"]
var cursor := 0
var msg := ""
var revealed := 0.0
var _blink := false            # "more text" cursor blink state
var _blink_t := 0.0
var _shown_hp := {"player": 0.0, "enemy": 0.0}   # HP the bars display; drains toward the real value (UpdateHPBar2)
var _shown_status := {"player": "", "enemy": ""}   # status the HUD badge shows; flips only when its message plays (mirror of _shown_hp)
var _last_mon := {"player": null, "enemy": null}  # detect a (re)sent-out mon to snap its bar
var fast_hp := false           # tests set this to skip the HP-drain animation (instant)
var _faint_who := ""           # "player"/"enemy" while that mon's pic is sliding down (SlideDownFaintedMonPic)
var _faint_t := 0.0            # faint slide progress (0 = up, 1 = fully sunk)
# The pics are presentation state: a mon's pic stays on screen (whatever its data HP, which drops
# at resolve time) until its faint slide removes it, and returns on the next send-out.
var _pic_gone := {"player": false, "enemy": false}
var _level_stats := {}         # new stats shown in the level-up box (PrintStatsBox)
var queue: Array = []
var after := ""

# ---- determinism oracle (gh #2, ADR-014) -----------------------------------
# The battle-local RNG + canonical event stream live on the module (gh #33); the full
# rationale rides with the state in Gen1Battle.gd. Verified by --battledettest.
var rng: RandomNumberGenerator:
	get: return mech.rng
	set(v): mech.rng = v
var rng_cursor: int:       # logic draws since battle start (the lockstep "RNG cursor")
	get: return mech.rng_cursor
	set(v): mech.rng_cursor = v
var battle_seed: int:      # this battle's seed (a link session fixes it at establishment)
	get: return mech.battle_seed
	set(v): mech.battle_seed = v
var next_seed: int:        # set before start*() to force the seed (tests/link); -1 = derive
	get: return mech.next_seed
	set(v): mech.next_seed = v
var det_stream: Array:     # canonical event lines (docs/engine/battle.md "Determinism")
	get: return mech.det_stream
	set(v): mech.det_stream = v
var det_log: bool:         # echo events to stdout as [battledet] lines (the link soak reads logs)
	get: return mech.det_log
	set(v): mech.det_log = v
var turn_no: int:
	get: return mech.turn_no
	set(v): mech.turn_no = v
var _det_paction: String:  # the player action driving the current turn, canonical form
	get: return mech._det_paction
	set(v): mech._det_paction = v
var _det_eaction: String:  # the enemy action (in a link battle: the peer's choice)
	get: return mech._det_eaction
	set(v): mech._det_eaction = v

# ---- link battle (gh #7, ADR-014): deterministic lockstep ------------------
# Both peers run the FULL simulation, each with itself as the "player" side (mirrored, as
# pokered's link battles do), from a shared seed fixed at the table; only chosen actions
# cross the wire. Everything player/enemy-asymmetric that draws RNG or shifts stats is
# neutralized exactly as the asm neutralizes it for LINK_STATE_BATTLING: badge boosts off
# (ApplyBadgeStatBoosts rets), the enemy stat-down hidden 65/256 miss off, no EXP — and the
# speed-tie coin is interpreted canonically ("heads = the HOST acts first"), so the two
# mirrored sims order the same tie the same way. For the lockstep oracle, event lines are
# emitted in host/join labels (h[]/j[]) and the digest orders the host's side first on both
# peers, so byte-equality of the two streams remains the definition of "in sync".
var link_battle: bool:
	get: return mech.link_battle
	set(v): mech.link_battle = v
var link_host: bool:
	get: return mech.link_host
	set(v): mech.link_host = v
var peer_name: String:     # the partner's player name (their trainer label)
	get: return mech.peer_name
	set(v): mech.peer_name = v
var link_actions: Array:   # the peer's col_act actions, in turn order (fed by Cutscene)
	get: return mech.link_actions
	set(v): mech.link_actions = v
var link_swaps: Array:     # the peer's col_swap faint replacements, in order
	get: return mech.link_swaps
	set(v): mech.link_swaps = v
var _link_wait: String:    # "" | "act" (their turn action) | "swap" (their replacement)
	get: return mech._link_wait
	set(v): mech._link_wait = v
var _link_pact: Dictionary:    # our pending action while waiting for theirs
	get: return mech._link_pact
	set(v): mech._link_pact = v
var _link_pact_turn: int:  # the turn it was submitted for (gh #13: resume retransmit)
	get: return mech._link_pact_turn
	set(v): mech._link_pact_turn = v
var _link_lswap: int:      # our last faint replacement sent as col_swap, and its turn
	get: return mech._link_lswap
	set(v): mech._link_lswap = v
var _link_lswap_turn: int:
	get: return mech._link_lswap_turn
	set(v): mech._link_lswap_turn = v
var _link_elapsed: float:
	get: return mech._link_elapsed
	set(v): mech._link_elapsed = v
var link_over: bool:       # set when the link died mid-battle (stakeless end)
	get: return mech.link_over
	set(v): mech.link_over = v


func _ri(n: int) -> int:
	return mech._ri(n)


func _rr(lo: int, hi: int) -> int:
	return mech._rr(lo, hi)


func _rf() -> float:
	return mech._rf()


func _det_event(kind: String, info: String) -> void:
	mech._det_event(kind, info)


func _det_digest() -> String:
	return mech._det_digest()


func _det_mon(mon: Dictionary) -> String:
	return mech._det_mon(mon)


func _det_kv(d: Dictionary) -> String:
	return mech._det_kv(d)


func _det_action(action: Dictionary) -> String:
	return mech._det_action(action)


func setup(ftex: Texture2D, cols: int, cmap: Dictionary, base: Dictionary, mdb: Dictionary, rs: Ruleset) -> void:
	rset = rs
	mech = rset.battle          # gh #33: the battle module owns the state; bind it first
	mech.bind(self)
	font_tex = ftex
	font_cols = cols
	charmap = cmap
	frame_tex = load("res://assets/frame.png")
	hud_tex = load("res://assets/battle_hud.png")
	_trainer_back_tex = load("res://assets/trainer_back.png")
	_ghost_tex = load("res://assets/ghost.png")
	_oldman_tex = load("res://assets/oldman_back.png")
	_monster_tex = load("res://assets/sprites/monster.png")
	_fbe_tex = load("res://assets/font_battle_extra.png")
	_icons_tex = load("res://assets/mon_icons.png")
	_icons_map = ProjectData.legacy("mon_icons.json")   # gh #25: data rides the project
	_invert = ColorRect.new()                  # the AnimationFlashScreen palette inversion
	_invert.size = Vector2(160, 144)
	var iv := ShaderMaterial.new()
	iv.shader = load("res://shaders/invert.gdshader")
	_invert.material = iv
	_invert.visible = false
	add_child(_invert)
	_balls_tex = load("res://assets/balls.png")
	_manim = ProjectData.legacy("move_anims.json")
	for ts in _manim["tilesets"]:
		if not _manim_tex.has(str(ts["img"])):
			_manim_tex[str(ts["img"])] = load("res://assets/%s.png" % str(ts["img"]))
	base_stats = base
	moves_db = mdb
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_eff_re.compile("^([A-Z]+)_(UP|DOWN)([12])_EFFECT$")
	visible = false


func _new_stages() -> Dictionary:
	return mech._new_stages()


# The STORED battle stats (wBattleMon* / wEnemyMon*) live on the module (gh #33);
# the maintenance rationale rides with them in Gen1Battle.gd.
var p_mod: Dictionary:
	get: return mech.p_mod
	set(v): mech.p_mod = v
var e_mod: Dictionary:
	get: return mech.e_mod
	set(v): mech.e_mod = v


func _badge_boost(v: int, key: String) -> int:
	return mech._badge_boost(v, key)


func _rebuild_mod_stats(is_player: bool) -> void:
	mech._rebuild_mod_stats(is_player)


func _new_vol() -> Dictionary:
	return mech._new_vol()


func start(p_party: Array, e_species: String, e_level: int) -> void:
	_begin(p_party)
	is_trainer = false
	enemy_party = [main.make_mon(e_species, e_level, [])]
	_set_enemy(0)
	# Faithful to _InitBattleCommon/StartBattle/SendOutMon: silhouettes slide in, palettes reveal,
	# the wild mon cries as the party pokeballs appear, "Wild X appeared!" types (no A press), the
	# enemy HUD joins it, a 40-frame beat, the player pic slides off, then "Go!" + poof + pop-out.
	if ghost or unveil:
		# Pokémon Tower: the enemy presents as the unidentified GHOST (common_text.asm
		# .pokemonTower — the GhostPic and the name "GHOST" over the real mon data).
		front_tex = _ghost_tex
		enemy_mon["real_name"] = enemy_mon["name"]
		enemy_mon["name"] = "GHOST"
		enemy_mon["label"] = "GHOST"
	var q: Array = [{"intro": "silhouette"}, {"intro": "reveal"}, {"intro": "pokeballs"},
		{"auto": "Wild %s\nappeared!" % enemy_mon["name"]}]
	if ghost:
		q.append("Darn! The GHOST\ncan't be ID'd!")
	elif unveil:
		q.append("SILPH SCOPE\nunveiled the\nGHOST's identity!")
		q.append({"unveil": true})
	q.append_array([{"intro": "enemy_hud"}, {"intro": "pause"}])
	if not demo:                # BATTLE_TYPE_OLD_MAN sends no mon out: the back pic stays put
		q.append_array([{"intro": "slide_off"},
			{"auto": "Go! %s!" % player_mon["name"]}, {"intro": "throw"}])
	_det_event("S", "wild seed=%d" % battle_seed)
	_say(q, "menu")


## Trainer battle: enemy_data is a list of {species, level}; fight the whole team.
func start_trainer(p_party: Array, enemy_data: Array, tname: String, money_base: int, pic_tex: Texture2D = null) -> void:
	_begin(p_party)
	is_trainer = true
	trainer_name = tname
	enemy_party = []
	for m in enemy_data:
		enemy_party.append(main.make_mon(str(m["species"]), int(m["level"]), []))
	prize = money_base * int(enemy_party[-1]["level"])
	_set_enemy(0)
	trainer_pic_tex = pic_tex
	_trainer_intro = trainer_pic_tex != null
	# Faithful to _InitBattleCommon/EnemySendOutFirstMon: the trainer's pic slides in as the
	# silhouette, the encounter sting + a beat, both parties' pokeball brackets, "wants to
	# fight!" (no A press), the trainer slides off right, "sent out X!", the mon grows in and
	# cries, its HUD appears, a 40-frame beat, then the player's own send-out.
	var q: Array = [{"intro": "silhouette"}, {"intro": "reveal"}, {"intro": "t_appeared"},
		{"intro": "pokeballs"}, {"auto": "%s\nwants to fight!" % tname}]
	if trainer_pic_tex:
		q.append({"intro": "t_slide_off"})
	q.append_array([{"auto": "%s sent\nout %s!" % [tname, enemy_mon["name"]]},
		{"intro": "enemy_grow"}, {"intro": "enemy_hud"}, {"intro": "pause"},
		{"intro": "slide_off"}, {"auto": "Go! %s!" % player_mon["name"]}, {"intro": "throw"}])
	_det_event("S", "trainer seed=%d" % battle_seed)
	_say(q, "menu")


## Link battle (gh #7): the peer's decoded party is the enemy team, the seed is the shared
## one fixed at the Colosseum table, and no AI runs — the enemy's actions arrive over the
## wire. Trainer semantics (RUN blocked, thrown balls blocked); no prize, no EXP, stakeless.
func start_link(p_party: Array, e_party: Array, host: bool, seed_v: int, pname: String) -> void:
	next_seed = seed_v
	_begin(p_party)
	link_battle = true
	link_host = host
	peer_name = pname
	is_trainer = true
	no_blackout = true                 # a lost link battle is stakeless — never a whiteout
	trainer_name = pname
	enemy_party = e_party
	prize = 0
	link_actions = []
	link_swaps = []
	_link_wait = ""
	_link_pact = {}
	_link_pact_turn = -1
	_link_lswap = -1
	_link_lswap_turn = -1
	link_over = false
	_set_enemy(0)
	# cable_club.asm sets wCurOpponent = OPP_RIVAL1 for a link battle: the partner appears
	# as the rival, pic and all, through the ordinary trainer intro. (A pic-less trainer
	# intro is a combination that never exists on cartridge — running one meshed the enemy
	# mon's slide-in with its HUD; playtest report.)
	var pic_slug := str(main.trainer_pics.get("OPP_RIVAL1", "")) if main else ""
	trainer_pic_tex = load("res://assets/trainers/pics/%s.png" % pic_slug) if pic_slug != "" else null
	_trainer_intro = trainer_pic_tex != null
	var q: Array = [{"intro": "silhouette"}, {"intro": "reveal"}, {"intro": "t_appeared"},
		{"intro": "pokeballs"}, {"auto": "%s\nwants to fight!" % pname}]
	if trainer_pic_tex:
		q.append({"intro": "t_slide_off"})
	q.append_array([{"auto": "%s sent\nout %s!" % [pname, enemy_mon["name"]]},
		{"intro": "enemy_grow"}, {"intro": "enemy_hud"}, {"intro": "pause"},
		{"intro": "slide_off"}, {"auto": "Go! %s!" % player_mon["name"]}, {"intro": "throw"}])
	_det_event("S", "link seed=%d" % battle_seed)
	_say(q, "menu")


## Safari Zone encounter: throw BALL/BAIT/ROCK or RUN; the mon can flee, you can't fight.
func start_safari(p_party: Array, e_species: String, e_level: int) -> void:
	_begin(p_party)
	is_safari = true
	menu_items = SAFARI_MENU
	safari_bait = 0; safari_escape = 0
	enemy_party = [main.make_mon(e_species, e_level, [])]
	_set_enemy(0)
	safari_catch = int(base_stats[enemy_mon["species"]]["catch"])
	# The same wild intro, but no send-out — the player's own pic stays on screen (StartBattle
	# jumps straight to the safari menu).
	_det_event("S", "safari seed=%d" % battle_seed)
	_say([{"intro": "silhouette"}, {"intro": "reveal"}, {"intro": "pokeballs"},
		{"auto": "Wild %s\nappeared!" % enemy_mon["name"]}, {"intro": "enemy_hud"},
		{"intro": "pause"}, {"intro": "end"}], "menu")


func _begin(p_party: Array) -> void:
	link_battle = false
	link_host = false
	peer_name = ""
	# Determinism oracle (gh #2): seed the battle-local RNG. Outside a link/test, the seed
	# itself comes off the global RNG — the battle stays as unpredictable as before, but
	# every draw AFTER this line is battle-local and replayable from the seed alone.
	battle_seed = next_seed if next_seed >= 0 else (randi() & 0x7fffffff)
	next_seed = -1
	rng.seed = battle_seed
	rng_cursor = 0
	turn_no = 0
	det_stream = []
	_det_paction = "-"
	_det_eaction = "-"
	party = p_party
	is_trainer = false
	is_safari = false
	_demo_ran = false
	run_attempts = 0
	newly_caught = false
	doll_escape = false
	ai_mods = []
	ai_kind = "Generic"
	ai_count_max = 3
	_ai_turn = 0
	trainer_pic_tex = null
	trainer_pic_x = 999.0
	_trainer_intro = false
	menu_items = ["FIGHT", "PKMN", "ITEM", "RUN"]
	active = _first_usable()
	player_mon = party[active]
	player_mon["label"] = player_mon["name"]
	_shown_status["player"] = str(player_mon["status"])
	can_evolve = []                    # party indices that leveled this battle (wCanEvolveFlags)
	won = false
	caught = false
	blacked_out = false
	no_blackout = false
	p_stages = _new_stages()
	e_stages = _new_stages()
	p_vol = _new_vol()
	e_vol = _new_vol()
	_rebuild_mod_stats(true)
	_sub_shown = {"player": false, "enemy": false}
	visible = true
	_pic_gone = {"player": false, "enemy": false}
	_load_back()
	# The battle wipe (Main.transition) has already consumed the overworld into black; the
	# screen cuts to the battle layout as the silhouette slide begins (_InitBattleCommon).
	msg = ""
	_auto_msg = false
	_intro_stage = ""
	_intro_pokeballs = false
	_intro_enemy_hud = false
	_intro_player_hud = false
	_intro_ball_t = 0.0
	_intro_egrow = 0.0


func _set_enemy(idx: int) -> void:
	enemy_active = idx
	enemy_mon = enemy_party[idx]
	_shown_hp["enemy"] = float(enemy_mon["hp"])   # the bar shows THIS mon's HP, not the last one's — an AI
	                                              # switch to an already-damaged mon must read right (gh #167)
	_shown_status["enemy"] = str(enemy_mon["status"])
	_ai_uses = ai_count_max            # wAICount: item/switch uses reset per mon
	enemy_mon["label"] = "Enemy " + enemy_mon["name"]
	front_tex = load("res://assets/pokemon/front/%s.png" % enemy_mon["species"])
	_pic_gone["enemy"] = false         # the new mon's pic is back on screen
	_sub_shown["enemy"] = false
	e_stages = _new_stages()
	e_vol = _new_vol()
	_rebuild_mod_stats(false)
	participants = [active]            # EXP split resets per enemy
	if main:
		main.mark_seen(str(enemy_mon["species"]))
		# (no cry here: the intro/send-out stages play it at the faithful moment — the wild cry
		# with the pokeballs, the trainer's mon after its grow-in)


func _load_back() -> void:
	back_tex = load("res://assets/pokemon/back/%s.png" % player_mon["species"])


func _first_usable() -> int:
	return mech._first_usable()


func _has_other_usable() -> bool:
	return mech._has_other_usable()


# ---- message queue ---------------------------------------------------------

func _sfx(key: String, pitch := 0) -> void:
	if main and main.audio:
		main.audio.play_sfx(key, pitch)


## A queue cue that plays a move's attack sound (MoveSoundTable), or nothing if unmapped.
func _move_sfx_cue(move: String) -> Dictionary:
	if main and move in main.move_sfx:
		var e: Array = main.move_sfx[move]
		return {"sfx": str(e[0]), "pitch": int(e[1])}
	return {}


## The queue entry that plays a move's attack animation (gh #19 phase 4) — the animation's own
## commands carry the move sounds. When animations are skipped (fast_hp tests), fall back to
## just the MoveSoundTable cue so SFX behavior is still exercised.
func _move_anim_marker(move: String, att_is_player: bool) -> Dictionary:
	if fast_hp:
		return _move_sfx_cue(move)
	return {"moveanim": move, "attacker": "player" if att_is_player else "enemy"}


func _say(msgs: Array, next: String) -> void:
	# Word-wrap each message to the box width and paginate to <=2 lines, so text
	# never runs off the right edge.
	queue = []
	for m in msgs:
		if m is String:
			queue.append_array(_wrap(m))
		else:
			queue.append(m)        # marker (e.g. {"learn": move}) passes through
	after = next
	_next_msg()


func _wrap(text: String) -> Array:
	var lines: Array = []
	for part in text.split("\n"):
		var cur := ""
		for word in part.split(" "):
			if cur == "":
				cur = word
			elif cur.length() + 1 + word.length() <= MAXCHARS:
				cur += " " + word
			else:
				lines.append(cur)
				cur = word
		lines.append(cur)
	var pages: Array = []
	var i := 0
	while i < lines.size():
		pages.append("\n".join(lines.slice(i, i + 2)))
		i += 2
	return pages


func _next_msg() -> void:
	if queue.is_empty():
		_resolve_after()
		return
	var item = queue.pop_front()
	if item is Dictionary and item.has("learn"):
		learn_move = str(item["learn"])
		cursor = 0
		state = "learn"
		queue_redraw()
		return
	if item is Dictionary and item.has("mimic_pick"):   # the player picks MIMIC's copy (gh #65)
		_mimic_moves = item["mimic_pick"]
		_mimic_slot = int(item["slot"])
		cursor = 0
		state = "mimic"
		queue_redraw()
		return
	if item is Dictionary and item.has("recall"):       # switch-out: the pic vanishes (gh #72)
		_pic_gone["player"] = true
		queue_redraw()
		_next_msg()
		return
	if item is Dictionary and item.has("send_player"):  # switch-in: load the new back pic and
		_shown_status["player"] = str(player_mon["status"])
		_load_back()                                    # run the ball throw + poof + pop-out
		_pic_gone["player"] = false
		_do_intro_stage("throw")
		return
	if item is Dictionary and item.has("sfx"):   # play a cue, then fall through to the next message
		_sfx(str(item["sfx"]), int(item.get("pitch", 0)))
		_next_msg()
		return
	if item is Dictionary and item.has("intro"):  # a battle-start sequence stage
		_do_intro_stage(str(item["intro"]))
		return
	if item is Dictionary and item.has("trainer_slide"):  # slide the trainer pic in/out (#11)
		state = "anim"                            # ignore input during the slide
		var to_x := 168.0 if str(item["trainer_slide"]) == "out" else 112.0
		if str(item["trainer_slide"]) == "in":
			trainer_pic_x = 168.0
		var tw := create_tween()
		tw.tween_method(func(x: float) -> void: trainer_pic_x = x; queue_redraw(), trainer_pic_x, to_x, 0.35)
		tw.tween_callback(func() -> void: _trainer_intro = false; _next_msg())  # mons appear after slide-out
		return
	if item is Dictionary and item.has("hp"):    # drain the HP bar toward a new value (UpdateHPBar2)
		var who := str(item["hp"])
		var to := float(item["to"])
		var mon: Dictionary = player_mon if who == "player" else enemy_mon
		var mx := maxf(1.0, float(mon["maxhp"]))
		if fast_hp:                               # tests: skip the animation
			_shown_hp[who] = to
			_next_msg()
			return
		var px := absf((to - float(_shown_hp[who])) / mx) * 48.0   # bar is 48 px wide
		if px < 0.75:                             # <1 px change: no visible drain, just continue
			_shown_hp[who] = to
			_next_msg()
			return
		state = "anim"                            # 2 frames per pixel, like AnimateHPBar
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: _shown_hp[who] = v; queue_redraw(), float(_shown_hp[who]), to, px * 2.0 / 60.0)
		tw.tween_callback(_next_msg)
		return
	if item is Dictionary and item.has("status"):   # the status badge flips now, with its message
		_shown_status[str(item["status"])] = str(item["to"])
		queue_redraw()
		_next_msg()
		return
	if item is Dictionary and item.has("faint"):  # slide the fainting mon's pic down (SlideDownFaintedMonPic)
		var fwho := str(item["faint"])
		if fast_hp:
			_pic_gone[fwho] = true                # the pic is removed even when the slide is skipped
			_next_msg()
			return
		_faint_who = fwho
		_faint_t = 0.0
		state = "anim"
		if main.audio:
			if fwho == "player":
				main.audio.play_cry(str(player_mon["species"]))   # the player's mon cries as it faints
			else:
				main.audio.play_sfx("faint_fall")
		var ftw := create_tween()
		ftw.tween_method(func(v: float) -> void: _faint_t = v; queue_redraw(), 0.0, 1.0, 0.25)
		ftw.tween_callback(func() -> void:
			_faint_who = ""
			_pic_gone[fwho] = true                # gone until the next send-out
			queue_redraw()
			_next_msg())
		return
	if item is Dictionary and item.has("next_enemy"):  # the trainer's next mon steps in only now —
		_set_enemy(int(item["next_enemy"]))       # deferred from _end_of_turn so its pic/HUD/cry
		_do_intro_stage("enemy_grow")             # don't replace the fainted mon mid-sequence;
		return                                    # it grows in + cries, then the stage advances
	if item is Dictionary and item.has("levelstats"):  # the level-up stats box (PrintStatsBox)
		if fast_hp:                               # tests: skip the box (no input to dismiss it)
			_next_msg()
			return
		_level_stats = item["levelstats"]
		state = "levelstats"
		queue_redraw()
		return
	if item is Dictionary and item.has("moveanim"):  # a move's real attack animation (gh #19)
		if fast_hp:                               # tests skip animations
			_next_msg()
			return
		# BATTLE ANIMATION OFF plays a 30-frame beat instead — EXCEPT the Poké Ball capture animations, which
		# pokered plays regardless: TOSS_ANIM jumps straight to TossBallAnimation, skipping the option check
		# (animations.asm), so the throw/poof/wobbles show even with move animations off (gh #119).
		if main and not main.options["battle_anim"] and not item.get("always", false):
			state = "anim"
			var otw := create_tween()
			otw.tween_interval(30.0 / 60.0)
			otw.tween_callback(_next_msg)
			return
		state = "anim"                            # no input while the animation plays
		_play_move_anim(str(item["moveanim"]), str(item.get("attacker", "player")) == "player")
		return
	if item is Dictionary and item.has("hide_pic"):  # the mon vanishes into the ball
		_pic_gone[str(item["hide_pic"])] = true
		queue_redraw()
		_next_msg()
		return
	if item is Dictionary and item.has("show_pic"):  # ...and bursts back out
		_pic_gone[str(item["show_pic"])] = false
		queue_redraw()
		_next_msg()
		return
	if item is Dictionary and item.has("sub_show"):  # the SUBSTITUTE doll takes the pic's place
		_sub_shown[str(item["sub_show"])] = true
		queue_redraw()
		_next_msg()
		return
	if item is Dictionary and item.has("sub_hide"):  # the doll pops and the mon returns
		_sub_shown[str(item["sub_hide"])] = false
		queue_redraw()
		_next_msg()
		return
	if item is Dictionary and item.has("unveil"):    # MarowakAnim: the GHOST becomes MAROWAK
		front_tex = load("res://assets/pokemon/front/%s.png" % enemy_mon["species"])
		enemy_mon["name"] = enemy_mon["real_name"]
		enemy_mon["label"] = enemy_mon["name"]
		if main and main.audio:
			main.audio.play_cry(str(enemy_mon["species"]))
		queue_redraw()
		state = "anim"                               # a beat while the reveal lands
		var utw := create_tween()
		utw.tween_interval(0.8)
		utw.tween_callback(_next_msg)
		return
	if item is Dictionary and item.has("shift"):  # SHIFT style: offer a free switch before the
		msg = "Will %s change\nPOKéMON?" % main.player_name   # trainer's next mon
		revealed = 999
		cursor = 0
		state = "shift"
		queue_redraw()
		return
	if item is Dictionary and item.has("anim"):  # the hit reaction (PlayApplyingAttackAnimation)
		if fast_hp:                               # tests skip it, like the other presentation markers
			_next_msg()
			return
		state = "anim"                            # ignore input while the hit animation plays
		var tw := create_tween()
		match str(item["anim"]):
			"shake":                              # PredefShakeScreenHorizontally/Vertically: the
				# window bounces right/down and back with decaying magnitude px..1; the BG moves,
				# OAM sprites don't. rWX halves are 4+5 frames, rWY halves 3+3.
				var ax := Vector2(1, 0) if str(item.get("axis", "x")) == "x" else Vector2(0, 1)
				var out_t := (4.0 if ax.x > 0.0 else 3.0) / 60.0
				var back_t := (5.0 if ax.x > 0.0 else 3.0) / 60.0
				for i in range(int(item.get("px", 8)), 0, -1):
					var off := ax * float(i)
					tw.tween_callback(func() -> void: _anim_shake = off; queue_redraw())
					tw.tween_interval(out_t)
					tw.tween_callback(func() -> void: _anim_shake = Vector2.ZERO; queue_redraw())
					tw.tween_interval(back_t)
				tw.tween_callback(func() -> void: _next_msg())
			"sway":                               # ShakeScreenHorizontallySlow: glide px right at
				var px := float(item.get("px", 6))   # 1 px per 2 frames and back, twice; silent
				for r in 2:
					tw.tween_method(func(v: float) -> void: _anim_shake = Vector2(v, 0); queue_redraw(),
						0.0, px, px * 2.0 / 60.0)
					tw.tween_method(func(v: float) -> void: _anim_shake = Vector2(v, 0); queue_redraw(),
						px, 0.0, px * 2.0 / 60.0)
				tw.tween_callback(func() -> void: _anim_shake = Vector2.ZERO; queue_redraw(); _next_msg())
			_:                                    # blink the hit mon: 6 cycles of 5+5 frames
				_flash_who = str(item["who"])     # (BlinkEnemyMonSprite -> AnimationBlinkMon)
				for i in 6:
					tw.tween_callback(func() -> void: _flash_on = false; queue_redraw())
					tw.tween_interval(5.0 / 60.0)
					tw.tween_callback(func() -> void: _flash_on = true; queue_redraw())
					tw.tween_interval(5.0 / 60.0)
				tw.tween_callback(func() -> void: _flash_who = ""; _next_msg())
		return
	if item is Dictionary and item.has("auto"):  # intro text that flows on without an A press
		msg = str(item["auto"])
		revealed = 0.0
		_auto_msg = true
		state = "msg"
		queue_redraw()
		return
	msg = str(item)
	revealed = 0.0
	_auto_msg = false
	state = "msg"
	queue_redraw()


func _resolve_after() -> void:
	match after:
		"menu":
			# Link: a fainted enemy waits for the peer's replacement before anything else.
			if link_battle and int(enemy_mon["hp"]) <= 0 and _link_enemy_has_usable():
				_link_wait = "swap"
				_link_elapsed = 0.0
				msg = "Waiting..."
				revealed = 999
				state = "linkwait"
				queue_redraw()
				return
			var fm := _forced_move(p_vol)
			if fm != "":
				_submit_action({"kind": "forced", "move": fm})
			elif not _has_usable_move(player_mon, p_vol):
				_submit_action({"kind": "forced", "move": "STRUGGLE"})
			else:
				state = "menu"; cursor = 0; queue_redraw()
		"moves":
			state = "moves"; cursor = 0; _move_swap = -1; queue_redraw()
		"party_forced":
			state = "party_forced"; cursor = _first_usable(); queue_redraw()
		_:
			if link_battle:
				var winner := "draw"
				if link_over:
					winner = "void"          # the link died mid-battle
				elif won:
					winner = "host" if link_host else "join"
				elif blacked_out:
					winner = "join" if link_host else "host"
				_det_event("END", "winner=" + winner)
			else:
				_det_event("END", "won=%s caught=%s blackout=%s" % [won, caught, blacked_out])
			if not caught:
				visible = false        # a catch keeps the scene up for the dex/nickname beats
			_revert_battle_copy(player_mon, p_vol)
			finished.emit()


func _msg_glyphs() -> int:
	var n := 0
	for ch in msg:
		if ch != "\n":
			n += 1
	return n


func _process(delta: float) -> void:
	if demo and state == "menu" and not _demo_ran:
		_demo_ran = true
		_run_demo()
	# Link lockstep (gh #7): "linkwait" holds until the peer's action/replacement arrives.
	# No artificial clock on a live link — a friend may think — but a dead link ends it
	# (ENet detects a vanished peer; spec stories 16/21).
	if link_battle and state == "linkwait" and _link_wait != "":
		if _link_wait == "act" and not link_actions.is_empty():
			var ea := _parse_peer_action(str(link_actions.pop_front()))
			_link_wait = ""
			_resolve_link(_link_pact, ea)
		elif _link_wait == "swap" and not link_swaps.is_empty():
			var si2 := int(link_swaps.pop_front())
			_link_wait = ""
			_link_enemy_swap_in(si2)
		elif main == null or (main.link.state != "linked" and not main.link.holding()):
			# gh #13: an outage (lost, or the resume handshake's transient states) is not a
			# death — the linkwait holds with it; only a truly closed link voids the battle.
			_link_wait = ""
			_link_dead()
	if state == "msg" and revealed < _msg_glyphs():
		revealed += speed * delta
		queue_redraw()
	elif state == "msg" and _auto_msg:            # intro texts continue on their own (PrintText)
		_auto_msg = false
		_next_msg()
	elif state == "msg":                          # fully revealed: blink the "more text" arrow
		_blink_t += delta
		if _blink_t >= 0.4:
			_blink_t = 0.0
			_blink = not _blink
			queue_redraw()
	# Keep each bar's displayed HP in sync with the real value. A drain during a turn is animated by
	# the {"hp"} marker (state "anim"); here we snap when a mon is (re)sent out (reference changed),
	# during the intro, or between actions -- never mid-drain or mid-message.
	for who in ["player", "enemy"]:
		var mon: Dictionary = player_mon if who == "player" else enemy_mon
		if mon.is_empty():
			continue
		var changed := not is_same(mon, _last_mon[who])
		_last_mon[who] = mon
		if changed:
			_pic_gone[who] = false        # a (re)sent-out mon's pic is back
			queue_redraw()
		if changed or _intro_stage != "" or (state != "anim" and state != "msg"):
			if _shown_hp[who] != float(mon["hp"]):
				_shown_hp[who] = float(mon["hp"])
				queue_redraw()
			if str(_shown_status[who]) != str(mon["status"]):
				_shown_status[who] = str(mon["status"])
				queue_redraw()


# ---- input -----------------------------------------------------------------

## The old-man tutorial's simulated keystrokes (core.asm DisplayBattleMenu): the cursor rests
## on FIGHT for 80 frames, hops to ITEM, then the POKé BALL is thrown from his own pocket.
func _run_demo() -> void:
	cursor = 0
	queue_redraw()
	await get_tree().create_timer(80.0 / 60.0).timeout
	cursor = 2                    # ITEM
	queue_redraw()
	await get_tree().create_timer(30.0 / 60.0).timeout
	if state == "menu":           # still ours to drive
		_use_item("POKé BALL")


func handle_input() -> void:
	if demo and state == "menu":
		return                    # the tutorial drives the menu itself
	match state:
		"msg":
			if Input.is_action_just_pressed("ui_accept"):
				if revealed < _msg_glyphs():
					revealed = _msg_glyphs()
				else:
					_next_msg()
				queue_redraw()
		"levelstats":                                # dismiss the level-up stats box
			if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
				_next_msg()
		"menu":
			_nav_grid()                              # 2x2: up/down flip row, left/right flip column
			if Input.is_action_just_pressed("ui_accept"):
				_choose_action()
		"moves":
			_nav(player_mon["moves"].size())
			if Input.is_action_just_pressed("ui_accept"):
				_move_swap = -1                          # A/B deselect the held move (SelectMenuItem)
				if int(player_mon["moves"][cursor]["pp"]) > 0:
					_submit_action({"kind": "move", "idx": cursor})
				else:
					queue_redraw()
			elif Input.is_action_just_pressed("ui_cancel"):
				_move_swap = -1
				state = "menu"; cursor = 0; queue_redraw()
			elif Input.is_action_just_pressed("p_select"):
				_swap_moves()
		"party", "party_forced", "party_shift":
			_nav(party.size())
			if Input.is_action_just_pressed("ui_accept"):
				_choose_party()
			elif Input.is_action_just_pressed("ui_cancel") and state == "party":
				state = "menu"; cursor = 0; queue_redraw()
			elif Input.is_action_just_pressed("ui_cancel") and state == "party_shift":
				_next_msg()                              # declined after all: play on
		"shift":                                         # "Will <PLAYER> change POKéMON?" (SHIFT style)
			if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
				cursor = 1 - cursor
				queue_redraw()
			elif Input.is_action_just_pressed("ui_accept"):
				if cursor == 0:                          # YES: pick the free switch
					state = "party_shift"
					cursor = 0
					queue_redraw()
				else:
					_next_msg()
			elif Input.is_action_just_pressed("ui_cancel"):
				_next_msg()
		"item":
			_nav(bag_keys.size() + 1)                    # bag entries + CANCEL
			_item_scroll = clampi(_item_scroll, cursor - 3, cursor)
			if Input.is_action_just_pressed("ui_accept"):
				_item_swap = -1                          # choosing clears the hold (StartMenu_Item)
				if cursor >= bag_keys.size():            # CANCEL
					state = "menu"; cursor = 0; queue_redraw()
				else:
					main._bag_saved_idx = cursor         # remember the cursor across the use (wBagSavedMenuItem)
					main._bag_saved_scroll = _item_scroll
					_use_item(str(bag_keys[cursor]))
			elif Input.is_action_just_pressed("ui_cancel"):
				_item_swap = -1
				state = "menu"; cursor = 0; queue_redraw()
			elif Input.is_action_just_pressed("p_select"):
				_swap_bag_items()
		"learn":
			_nav(player_mon["moves"].size())         # pick a move; B (.cancel) gives up learning
			if Input.is_action_just_pressed("ui_accept"):
				_learn_choose(cursor)
			elif Input.is_action_just_pressed("ui_cancel"):
				_learn_choose(player_mon["moves"].size())   # give up (out-of-range idx = "did not learn")
		"mimic":                                     # MIMIC's pick: UP/DOWN/A only, no B (gh #65)
			_nav(_mimic_moves.size())
			if Input.is_action_just_pressed("ui_accept"):
				_mimic_choose()


func _nav(n: int) -> void:
	if Input.is_action_just_pressed("ui_up"):
		cursor = (cursor - 1 + n) % n; queue_redraw()
	elif Input.is_action_just_pressed("ui_down"):
		cursor = (cursor + 1) % n; queue_redraw()


## SELECT in the FIGHT menu holds a move; a second SELECT swaps the two rows — move and PP
## together (core.asm SwapMovesInMenu writes wBattleMonMoves/PP and the party mon's copies;
## player_mon IS the shared party dict here, so one array swap covers both). A second SELECT
## on the same row deselects (the no-op swap). Disable tracks the move by name, so it follows
## the swap like pokered's index fix-up.
func _swap_moves() -> void:
	var mv: Array = player_mon["moves"]
	if _move_swap < 0:
		_move_swap = cursor                          # hold this move
	else:
		var held = mv[_move_swap]
		mv[_move_swap] = mv[cursor]
		mv[cursor] = held
		# SwapMovesInMenu writes the party struct unconditionally — swapping while
		# transformed/mimicked reorders the real moves too (the Gen-1 behavior), so the
		# battle-only copies' backups (gh #62) swap along.
		for bk in [p_vol.get("transform_backup", {}).get("moves"), p_vol.get("mimic_backup")]:
			if bk is Array and _move_swap < (bk as Array).size() and cursor < (bk as Array).size():
				var held2 = bk[_move_swap]
				bk[_move_swap] = bk[cursor]
				bk[cursor] = held2
		_move_swap = -1
	queue_redraw()


## SELECT in the battle bag: the in-battle item list is an ITEMLISTMENU too (core.asm), so it
## reorders with SELECT exactly like the overworld bag (HandleItemListSwapping): CANCEL can't
## be swapped, re-SELECTing the held item keeps it held.
func _swap_bag_items() -> void:
	if cursor >= bag_keys.size():
		return
	if _item_swap < 0:
		_item_swap = cursor                          # hold this item
	elif cursor != _item_swap:
		var held = bag_keys[_item_swap]              # swap the two items' positions
		bag_keys[_item_swap] = bag_keys[cursor]
		bag_keys[cursor] = held
		var reordered := {}
		for k in bag_keys:
			reordered[k] = main.player_bag[k]
		main.player_bag.clear()                      # reorder the shared bag dict in place
		main.player_bag.merge(reordered)
		_item_swap = -1
	queue_redraw()


## The 2x2 action menu (index 0=FIGHT 1=PKMN 2=ITEM 3=RUN): up/down flip the row, left/right the column.
func _nav_grid() -> void:
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down"):
		cursor = cursor ^ 2; queue_redraw()
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
		cursor = cursor ^ 1; queue_redraw()


func _try_run() -> void:
	mech._try_run()


func _choose_action() -> void:
	match menu_items[cursor]:
		"FIGHT":
			state = "moves"; cursor = 0; _move_swap = -1; queue_redraw()
		"PKMN":
			state = "party"; cursor = active; queue_redraw()
		"ITEM":
			if link_battle:
				# Faithful: the cartridge refuses items in link battles at menu selection —
				# the bag never opens (core.asm BagWasSelected's LINK_STATE_BATTLING guard,
				# ItemsCantBeUsedHereText) — and so does every Gen-1 link battle ever fought.
				_say(["Items can't be\nused here."], "menu")
				return
			bag_keys = main.player_bag.keys()
			if bag_keys.is_empty():
				_say(["You have no\nitems!"], "menu")
			else:
				# The battle bag shares wBagSavedMenuItem with the overworld bag, so it reopens on the
				# item you last touched (unless it was used up) rather than snapping to the top (gh #120).
				_item_swap = -1
				cursor = clampi(main._bag_saved_idx, 0, bag_keys.size())
				_item_scroll = clampi(main._bag_saved_scroll, 0, maxi(0, bag_keys.size() - 3))
				state = "item"; queue_redraw()
		"RUN":
			if is_trainer:
				_say(["No! There's no running from a TRAINER battle!"], "menu")
			else:
				_try_run()
		"BALL":
			_safari_ball()
		"BAIT":
			_det_paction = "bait"
			safari_catch = safari_catch >> 1                 # bait halves the catch rate
			safari_escape = 0
			safari_bait = min(255, safari_bait + (_ri(5) + 1))
			_safari_turn(["%s threw\nsome BAIT." % main.player_name])
		"ROCK":
			_det_paction = "rock"
			safari_catch = min(255, safari_catch * 2)         # a rock doubles the catch rate
			safari_bait = 0
			safari_escape = min(255, safari_escape + (_ri(5) + 1))
			_safari_turn(["%s threw\na ROCK." % main.player_name])


## Apply the MIMIC pick: the chosen move replaces MIMIC's own slot, keeping that slot's PP
## (MimicEffect), then the queued messages resume with "learned!".
func _mimic_choose() -> void:
	var m := str(_mimic_moves[cursor])
	var mslot: Dictionary = player_mon["moves"][_mimic_slot]
	mslot["move"] = m
	mslot["maxpp"] = int(moves_db[m]["pp"])
	_det_event("X", "mimic:" + m)          # MIMIC's mid-turn pick: a player decision (gh #2)
	queue.push_front("%s learned\n%s!" % [player_mon["name"], str(moves_db[m]["name"])])
	_next_msg()


## Resolve the "delete a move?" prompt (always the active mon).
func _learn_choose(idx: int) -> void:
	var mon: Dictionary = player_mon
	var out: Array = []
	if idx < mon["moves"].size():
		# learn_move.asm checks the chosen slot with IsMoveHM and sends you straight back to the list
		# (HMCantDeleteText -> `jr .loop`). Without it a level-up quietly deletes SURF or STRENGTH and
		# strands the save — Cinnabar, Route 23 and Seafoam all need SURF (gh #93).
		if str(mon["moves"][idx]["move"]) in main.HM_MOVES.values():
			queue = _wrap("HM techniques\ncan't be deleted!") + [{"learn": learn_move}] + queue
			_next_msg()
			return
		var old: String = str(moves_db[str(mon["moves"][idx]["move"])]["name"])
		var pp := int(moves_db[learn_move]["pp"])
		mon["moves"][idx] = {"move": learn_move, "pp": pp, "maxpp": pp}
		out = ["1, 2 and... Poof!", "%s forgot\n%s!" % [mon["name"], old],
			"And %s learned\n%s!" % [mon["name"], str(moves_db[learn_move]["name"])]]
	else:
		out = ["%s did not learn\n%s." % [mon["name"], str(moves_db[learn_move]["name"])]]
	var pre: Array = []
	for m in out:
		pre.append_array(_wrap(m))
	_det_event("X", "learn:%d" % idx)         # the "delete a move?" pick: a player decision (gh #2)
	queue = pre + queue                       # show result, then resume the queued messages
	_next_msg()


func _revert_battle_copy(mon: Dictionary, vol: Dictionary) -> void:
	mech._revert_battle_copy(mon, vol)


func _choose_party() -> void:
	if cursor == active or int(party[cursor]["hp"]) <= 0:
		return                        # can't switch to the active or a fainted mon
	if state == "party_forced":
		_revert_battle_copy(player_mon, p_vol)
		active = cursor
		player_mon = party[active]
		player_mon["label"] = player_mon["name"]
		p_stages = _new_stages()      # the replacement starts with fresh mods and volatiles
		p_vol = _new_vol()            # (gh #74: stat drops used to survive a faint-switch)
		_rebuild_mod_stats(true)      # LoadBattleMonFromParty: fresh stats + penalties + badges
		_sub_shown["player"] = false
		if not participants.has(active):
			participants.append(active)
		# Faint replacement: a player decision mid-flow (gh #2). In link, role-labeled so the
		# peer's matching event (emitted at swap arrival) is byte-identical.
		if link_battle:
			_det_event("X", "%s:w:%d" % ["h" if link_host else "j", active])
			_link_lswap = active
			_link_lswap_turn = turn_no
			main.link.send_message({"t": "col_swap", "idx": active})
		else:
			_det_event("X", "w:%d" % active)
		_say([{"auto": "Go! %s!" % player_mon["name"]}, {"send_player": true}], "menu")
	elif state == "party_shift":
		# SHIFT style: a free switch before the trainer's next mon comes out; the queued
		# send-out continues after it (EnemySendOutFirstMon's party-menu path).
		_revert_battle_copy(player_mon, p_vol)
		active = cursor
		player_mon = party[active]
		player_mon["label"] = player_mon["name"]
		p_stages = _new_stages()      # switching resets stat stages and volatile state
		p_vol = _new_vol()
		_rebuild_mod_stats(true)
		_sub_shown["player"] = false
		if not participants.has(active):
			participants.append(active)
		_det_event("X", "w:%d" % active)   # SHIFT free switch: a player decision mid-flow (gh #2)
		queue.push_front({"send_player": true})
		queue.push_front({"auto": "Go! %s!" % player_mon["name"]})
		queue.push_front({"recall": true})
		_next_msg()
	else:
		_submit_action({"kind": "switch", "idx": cursor})


# ---- items & catching ------------------------------------------------------

const _X_ITEMS := {"X ATTACK": "atk", "X DEFEND": "def", "X SPEED": "spd", "X SPECIAL": "spc", "X ACCURACY": "acc"}
const _STAT_LABEL := {"atk": "ATTACK", "def": "DEFENSE", "spd": "SPEED", "spc": "SPECIAL", "acc": "ACCURACY"}


func _consume(item: String) -> void:
	main.player_bag[item] = int(main.player_bag[item]) - 1
	if int(main.player_bag[item]) <= 0:
		main.player_bag.erase(item)
		main._bag_saved_idx = 0        # a depleted slot resets the bag cursor (RemoveItemFromInventory_, gh #120)
		main._bag_saved_scroll = 0


func _use_item(item: String) -> void:
	if link_battle:
		# Unreachable via the UI (the ITEM menu entry refuses first, as the asm does);
		# kept so a scripted driver calling _use_item directly can't open a desync surface.
		_say(["Items can't be\nused here."], "menu")
		return
	if not demo and int(main.player_bag.get(item, 0)) <= 0:
		return                                    # (the old man throws his own ball)
	_det_paction = "i:" + item
	# --- Poké Balls (all four kinds roll ItemUseBall's algorithm) ---
	if item in ["POKé BALL", "GREAT BALL", "ULTRA BALL", "MASTER BALL"]:
		if is_trainer:
			# ThrowBallAtTrainerMon: the ball IS thrown and wasted, and the enemy takes its
			# turn (it exits via RemoveUsedItem, not ItemUseFailed).
			_consume(item)
			_enemy_turn_after_item([{"sfx": "ball_toss"},
				{"moveanim": "TOSS_ANIM", "attacker": "player", "always": true},
				"The trainer\nblocked the BALL!", "Don't be a thief!"])
			return
		if not demo and _box_and_party_full():
			# The old man demo skips the party/box check (BATTLE_TYPE_OLD_MAN).
			_say(["The POKéMON BOX\nis full! Can't\nuse that item!"], "menu")
			return
		if ghost or unveil:
			# Neither the unidentified GHOST nor the unveiled MAROWAK can be caught: the
			# capture calc is skipped with the can't-be-caught anim data (IsGhostBattle /
			# the RESTLESS_SOUL check in ItemUseBall), the ball is spent, and the wild
			# turn proceeds — for the GHOST, that turn is only its wail.
			_consume(item)
			var msgs: Array = [{"sfx": "ball_toss"}, "%s used\n%s!" % [main.player_name, item],
				{"moveanim": "TOSS_ANIM", "attacker": "player", "always": true},
				"It dodged the\nthrown BALL!", "This POKéMON\ncan't be caught!"]
			if ghost:
				msgs.append("GHOST: Get out...\nGet out...")
				_say(msgs, "menu")
			else:
				_enemy_turn_after_item(msgs)
			return
		if not demo:
			_consume(item)
		# The ball presentation plays through the generic anim player (TOSS_ANIM: the arc to
		# the target; POOF_ANIM: the mon vanishing into the ball; SHAKE_ANIM per wobble).
		var msgs: Array = [{"sfx": "ball_toss"},
			"%s used\n%s!" % ["OLD MAN" if demo else main.player_name, item],
			{"moveanim": "TOSS_ANIM", "attacker": "player", "always": true},
			{"moveanim": "POOF_ANIM", "attacker": "player", "always": true}, {"hide_pic": "enemy"}]
		# The old man's throw always captures (ItemUseBall jumps straight to .captured
		# for BATTLE_TYPE_OLD_MAN); everyone else rolls the real algorithm per ball kind.
		var res: Dictionary = {"caught": true, "shakes": 3} if demo else _attempt_catch(item)
		if bool(res["caught"]):
			if demo:
				# BATTLE_TYPE_OLD_MAN: the tutorial WEEDLE is shown caught, then discarded (no
				# party add, no nickname — `caught` stays false so the post-battle flow skips it).
				for i in 3:
					msgs.append({"moveanim": "SHAKE_ANIM", "attacker": "player", "always": true})
				msgs.append({"sfx": "caught_mon"})
				msgs.append("All right!\n%s was\ncaught!" % enemy_mon["name"])
				_say(msgs, "end")
				return
			if bool(e_vol.get("transformed", false)):
				# A transformed catch is assumed to be a DITTO (the TRANSFORMED check in
				# ItemUseBall, a noted pokered bug): LoadEnemyMonData rebuilds it fresh at
				# its level with the original DVs; current HP and status carry over.
				var fresh: Dictionary = main.make_mon("ditto", int(enemy_mon["level"]), [],
					enemy_mon.get("dvs", {}))
				fresh["hp"] = mini(int(enemy_mon["hp"]), int(fresh["maxhp"]))
				fresh["status"] = str(enemy_mon["status"])
				fresh["sleep"] = int(enemy_mon.get("sleep", 0))
				enemy_mon = fresh
			_catch_succeeds(msgs)
		else:
			var shakes := int(res["shakes"])    # 0-3 wobbles by how close it came
			for i in shakes:
				msgs.append({"moveanim": "SHAKE_ANIM", "attacker": "player", "always": true})
			msgs.append({"moveanim": "POOF_ANIM", "attacker": "player", "always": true})   # it bursts back out
			msgs.append({"show_pic": "enemy"})
			msgs.append(["You missed the\nPOKéMON!", "Darn! The POKéMON\nbroke free!",
				"Aww! It appeared\nto be caught!",
				"Shoot! It was so\nclose too!"][shakes])
			if demo:
				_say(msgs, "end")               # the demo ends after its one throw either way
			else:
				_enemy_turn_after_item(msgs)
		return
	# --- Healing potions (POTION..MAX POTION / FULL RESTORE; -1 = full heal) ---
	if main.POTIONS.has(item):
		var cures_status: bool = item == "FULL RESTORE" and str(player_mon["status"]) != ""
		if int(player_mon["hp"]) >= int(player_mon["maxhp"]) and not cures_status:
			_say(["It won't have any\neffect."], "menu")
			return
		_consume(item)
		var amt := int(main.POTIONS[item])
		var gap := int(player_mon["maxhp"]) - int(player_mon["hp"])
		var heal: int = gap if amt < 0 else min(amt, gap)
		if cures_status:
			player_mon["status"] = ""; player_mon["sleep"] = 0
		var im: Array = ["%s\nrecovered %d HP!" % [player_mon["name"], heal]]
		if cures_status:
			_show_status(player_mon, im)
		_set_hp(player_mon, int(player_mon["hp"]) + heal, im)   # animate the bar filling up
		_enemy_turn_after_item(im)
		return
	# --- Status heals (FULL HEAL cures any; the rest only their one status) ---
	if item == "FULL HEAL" or main.STATUS_HEALS.has(item):
		var tgt := "" if item == "FULL HEAL" else str(main.STATUS_HEALS[item])
		var cur := str(player_mon["status"])
		if cur == "" or (tgt != "" and cur != tgt):
			_say(["It won't have any\neffect."], "menu")
			return
		_consume(item)
		player_mon["status"] = ""; player_mon["sleep"] = 0
		var im: Array = ["%s was\ncured!" % player_mon["name"]]
		_show_status(player_mon, im)
		_enemy_turn_after_item(im)
		return
	# --- X stat boosters: the full StatModifierUpEffect pipeline (recalc + trailer) ---
	if _X_ITEMS.has(item):
		var key := str(_X_ITEMS[item])
		if int(p_stages[key]) >= 6:
			_say(["It won't have any\neffect."], "menu")
			return
		_consume(item)
		var im: Array = []
		_change_stage(player_mon, p_stages, str(_STAT_LABEL[key]), 1, im)
		_enemy_turn_after_item(im)
		return
	# --- DIRE HIT: "getting pumped" — the Focus Energy crit bit (ItemUseXStat, gh #175) ---
	if item == "DIRE HIT":
		if bool(p_vol["focus"]):
			_say(["It won't have any\neffect."], "menu")
			return
		_consume(item)
		p_vol["focus"] = true
		_enemy_turn_after_item(["%s used\nDIRE HIT!" % main.player_name, "%s is getting\npumped!" % player_mon["name"]])
		return
	# --- GUARD SPEC.: shroud the mon in MIST, blocking stat reduction (mirrors _ai_guard_spec, gh #175) ---
	if item == "GUARD SPEC.":
		if bool(p_vol["mist"]):
			_say(["It won't have any\neffect."], "menu")
			return
		_consume(item)
		p_vol["mist"] = true
		_enemy_turn_after_item(["%s used\nGUARD SPEC.!" % main.player_name, "%s's shrouded\nin mist!" % player_mon["name"]])
		return
	# --- POKé DOLL: distract a WILD mon and flee for sure (ItemUsePokedoll); useless vs a trainer (gh #175) ---
	if item == "POKé DOLL":
		if is_trainer or is_safari:
			_say(["It won't have any\neffect."], "menu")
			return
		_consume(item)
		# It works in ANY wild battle — the ghost ones included (ItemUsePokedoll only checks
		# wIsInBattle == 1), and the escape leaves wBattleResult at 0: the Tower 6F script
		# reads that as the MAROWAK laid to rest — the documented POKé DOLL trick.
		doll_escape = true
		_say([{"sfx": "run"}, "Got away\nsafely!"], "run")
		return
	# --- not usable in battle ---
	_say(["It won't have any\neffect."], "menu")


## Gen-1 Poké Ball catch check (BallFactor 12, no status in our wild demo).
## Throw a SAFARI BALL: caught -> ends; broke free -> the mon takes its turn (may flee).
func _safari_ball() -> void:
	if _box_and_party_full():
		# The refusal fires before the ball is spent, and no wild turn happens (ItemUseFailed
		# leaves wActionResultOrTookBattleTurn at 0, so core.asm loops back to the safari menu).
		_say(["The POKéMON BOX\nis full! Can't\nuse that item!"], "menu")
		return
	# No 0-ball guard, faithfully: ItemUseBall just decrements wNumSafariBalls — the menu can
	# never reappear at 0, because the battle ends the moment the count hits it (gh #180).
	_det_paction = "i:SAFARI BALL"
	main.safari_balls -= 1
	# The same ItemUseBall roll with the bait/rock-modified rate, and the same toss/wobble
	# presentation as any other ball.
	var msgs: Array = [{"sfx": "ball_toss"}, "%s used\nSAFARI BALL!" % main.player_name,
		{"moveanim": "TOSS_ANIM", "attacker": "player", "always": true},
		{"moveanim": "POOF_ANIM", "attacker": "player", "always": true}, {"hide_pic": "enemy"}]
	var res: Dictionary = _attempt_catch("SAFARI BALL", safari_catch)
	if bool(res["caught"]):
		_catch_succeeds(msgs)                # safari catches get the dex/nickname flow too
	else:
		var shakes := int(res["shakes"])
		for i in shakes:
			msgs.append({"moveanim": "SHAKE_ANIM", "attacker": "player", "always": true})
		msgs.append({"moveanim": "POOF_ANIM", "attacker": "player", "always": true})
		msgs.append({"show_pic": "enemy"})
		msgs.append(["You missed the\nPOKéMON!", "Darn! The POKéMON\nbroke free!",
			"Aww! It appeared\nto be caught!",
			"Shoot! It was so\nclose too!"][shakes])
		if main.safari_balls == 0:
			# That was the last BALL: the encounter ends on the spot with the PA line — no
			# wild-mon turn (core.asm .displaySafariZoneBattleMenu -> .outOfSafariBallsText).
			msgs.append("PA: Ding-dong!\fYou are out of\nSAFARI BALLs!")
			_say(msgs, "end")
		else:
			_safari_turn(msgs)


func _safari_turn(msgs: Array) -> void:
	mech._safari_turn(msgs)


## Party AND box full refuses a ball throw before it is spent (BoxFullCannotThrowBall ->
## ItemUseFailed: no ball, no turn). The port models one 20-slot box, as elsewhere.
func _box_and_party_full() -> bool:
	return party.size() >= 6 and main.pc_box.size() >= 20


## The catch-success tail shared by ItemUseBall and the safari throw (.captured onward): three
## wobbles settle, the capture jingle, the "All right!" line, then the mon joins the party — or,
## party full, the PC box with the transfer line keyed on MET_BILL (ItemUseBallText07/08).
func _catch_succeeds(msgs: Array) -> void:
	newly_caught = not main.pokedex_owned.has(str(enemy_mon["species"]))
	for i in 3:
		msgs.append({"moveanim": "SHAKE_ANIM", "attacker": "player", "always": true})
	msgs.append({"sfx": "caught_mon"})
	msgs.append("All right!\n%s was\ncaught!" % enemy_mon["name"])
	caught = true
	enemy_mon["label"] = enemy_mon["name"]
	if party.size() < 6:
		party.append(enemy_mon)
	else:
		main.pc_box.append(enemy_mon)   # party full -> the PC box (not lost)
		msgs.append("%s was\ntransferred to\n%s!" % [enemy_mon["name"],
			"BILL's PC" if main.has_event("MET_BILL") else "someone's PC"])
	_say(msgs, "end")


func _attempt_catch(ball := "POKé BALL", rate_override := -1) -> Dictionary:
	return mech._attempt_catch(ball, rate_override)


func _enemy_turn_after_item(msgs: Array) -> void:
	mech._enemy_turn_after_item(msgs)


# ---- link lockstep (gh #7) -------------------------------------------------

func _submit_action(action: Dictionary) -> void:
	mech._submit_action(action)


func link_send_resume() -> void:
	mech.link_send_resume()


func link_reconcile(peer: Dictionary) -> void:
	mech.link_reconcile(peer)


func _parse_peer_action(s: String) -> Dictionary:
	return mech._parse_peer_action(s)


func _resolve_link(pact: Dictionary, eact: Dictionary) -> void:
	mech._resolve_link(pact, eact)


func _link_enemy_act(move: String, msgs: Array, forced := false) -> void:
	mech._link_enemy_act(move, msgs, forced)


func _link_enemy_switch(idx: int, msgs: Array) -> void:
	mech._link_enemy_switch(idx, msgs)


func _link_enemy_has_usable() -> bool:
	return mech._link_enemy_has_usable()


func _link_enemy_swap_in(idx: int) -> void:
	mech._link_enemy_swap_in(idx)


## The link died mid-battle: the session simply ends, stakeless (spec story 17).
func _link_dead() -> void:
	link_over = true
	won = false
	blacked_out = false
	_say(["The link has been\nclosed."], "end")


# ---- turn resolution -------------------------------------------------------

func _resolve(action: Dictionary) -> void:
	mech._resolve(action)


func _player_act(action: Dictionary, msgs: Array) -> void:
	mech._player_act(action, msgs)


func _enemy_choose() -> String:
	return mech._enemy_choose()


func _ai_eff(move: String) -> float:
	return mech._ai_eff(move)


func _ai_better_move(usable: Array, than: String) -> bool:
	return mech._ai_better_move(usable, than)


# ---- Gen-1 trainer item/switch AI (engine/battle/trainer_ai.asm, handler for handler) ----

func _ai_item_turn(msgs: Array) -> bool:
	return mech._ai_item_turn(msgs)


func _hp_below(frac: int) -> bool:
	return mech._hp_below(frac)


func _ai_heal(amount: int, item: String, msgs: Array) -> bool:
	return mech._ai_heal(amount, item, msgs)


func _ai_full_heal(msgs: Array) -> bool:
	return mech._ai_full_heal(msgs)


func _ai_x_item(stat: String, item: String, msgs: Array) -> bool:
	return mech._ai_x_item(stat, item, msgs)


func _ai_guard_spec(msgs: Array) -> bool:
	return mech._ai_guard_spec(msgs)


func _ai_switch(msgs: Array) -> bool:              # AISwitchIfEnoughMons
	return mech._ai_switch(msgs)


func _forced_move(vol: Dictionary) -> String:
	return mech._forced_move(vol)


func _is_two_turn(move: String) -> bool:
	return mech._is_two_turn(move)


func _spend_pp(mon: Dictionary, move: String) -> void:
	mech._spend_pp(mon, move)


func _enemy_act(move: String, msgs: Array) -> void:
	mech._enemy_act(move, msgs)


func _end_of_turn(msgs: Array) -> void:
	mech._end_of_turn(msgs)


func _award_exp(msgs: Array) -> void:
	mech._award_exp(msgs)


func _award_exp_pass(recipients: Array, n: int, base_exp: int, halve_stats: bool, msgs: Array) -> void:
	mech._award_exp_pass(recipients, n, base_exp, halve_stats, msgs)


func _boost_exp(q: int) -> int:
	return mech._boost_exp(q)


func _gain_stat_exp(mon: Dictionary, n := 1, halve := false) -> void:
	mech._gain_stat_exp(mon, n, halve)


func _level_up_loop(mon: Dictionary, msgs: Array, allow_prompt: bool) -> void:
	mech._level_up_loop(mon, msgs, allow_prompt)


func _learn(mon: Dictionary, move: String, msgs: Array, allow_prompt: bool) -> void:
	mech._learn(mon, move, msgs, allow_prompt)


# ---- damage ----------------------------------------------------------------

func _do_move(att: Dictionary, defn: Dictionary, move: String, msgs: Array,
		att_st: Dictionary, def_st: Dictionary, att_is_player: bool) -> void:
	mech._do_move(att, defn, move, msgs, att_st, def_st, att_is_player)


# ---- damaging moves --------------------------------------------------------

func _do_damage_move(att: Dictionary, defn: Dictionary, move: String, md: Dictionary, msgs: Array,
		att_st: Dictionary, def_st: Dictionary, att_vol: Dictionary, def_vol: Dictionary, att_is_player: bool) -> void:
	mech._do_damage_move(att, defn, move, md, msgs, att_st, def_st, att_vol, def_vol, att_is_player)


func _calc_hit(att: Dictionary, defn: Dictionary, md: Dictionary, att_st: Dictionary, def_st: Dictionary,
		att_vol: Dictionary, def_vol: Dictionary) -> Dictionary:
	return mech._calc_hit(att, defn, md, att_st, def_st, att_vol, def_vol)


func _stage_apply(base: int, stage: int) -> int:
	return mech._stage_apply(base, stage)


func _type_eff(move_type: String, def_types: Array) -> float:
	return mech._type_eff(move_type, def_types)


func _set_hp(mon: Dictionary, new_hp: int, msgs: Array) -> void:
	mech._set_hp(mon, new_hp, msgs)


func _show_status(mon: Dictionary, msgs: Array) -> void:
	mech._show_status(mon, msgs)


func _deal(defn: Dictionary, def_vol: Dictionary, dmg: int, msgs: Array) -> void:
	mech._deal(defn, def_vol, dmg, msgs)


func _special_damage(att: Dictionary, move: String) -> int:
	return mech._special_damage(att, move)


func _on_miss(att: Dictionary, md: Dictionary, msgs: Array) -> void:
	mech._on_miss(att, md, msgs)


func _charge_line(move: String) -> String:
	return mech._charge_line(move)


func _side_effect(md: Dictionary, defn: Dictionary, def_st: Dictionary, def_vol: Dictionary, msgs: Array) -> void:
	mech._side_effect(md, defn, def_st, def_vol, msgs)


# ---- status (power-0) moves ------------------------------------------------

func _do_status_move(att: Dictionary, defn: Dictionary, move: String, md: Dictionary, msgs: Array,
		att_st: Dictionary, def_st: Dictionary, att_vol: Dictionary, def_vol: Dictionary, att_is_player: bool) -> void:
	mech._do_status_move(att, defn, move, md, msgs, att_st, def_st, att_vol, def_vol, att_is_player)


func _do_bide(att: Dictionary, defn: Dictionary, msgs: Array, att_vol: Dictionary) -> void:
	mech._do_bide(att, defn, msgs, att_vol)


func _confuse(mon: Dictionary, vol: Dictionary, msgs: Array) -> void:
	mech._confuse(mon, vol, msgs)


func _random_move_with_pp(mon: Dictionary) -> String:
	return mech._random_move_with_pp(mon)


func _metronome_pick() -> String:
	return mech._metronome_pick()


func _has_usable_move(mon: Dictionary, vol: Dictionary) -> bool:
	return mech._has_usable_move(mon, vol)


func _type_mult(atk_type: String, def_type: String) -> float:
	return mech._type_mult(atk_type, def_type)


# ---- status conditions -----------------------------------------------------

func _can_act(att: Dictionary, vol: Dictionary, other_vol: Dictionary, msgs: Array) -> bool:
	return mech._can_act(att, vol, other_vol, msgs)


func _confusion_self_damage(att: Dictionary, vol: Dictionary) -> int:
	return mech._confusion_self_damage(att, vol)


func _break_locks(vol: Dictionary, other_vol: Dictionary, msgs: Array) -> void:
	mech._break_locks(vol, other_vol, msgs)


func _status_from_effect(effect: String) -> Array:
	return mech._status_from_effect(effect)


func _apply_status(mon: Dictionary, st: String, msgs: Array) -> void:
	mech._apply_status(mon, st, msgs)


func _residual(mon: Dictionary, vol: Dictionary, other: Dictionary, msgs: Array) -> void:
	mech._residual(mon, vol, other, msgs)


func _eff_speed(is_player: bool) -> int:
	return mech._eff_speed(is_player)


func _apply_stat_move(att: Dictionary, defn: Dictionary, md: Dictionary, msgs: Array,
		att_st: Dictionary, def_st: Dictionary, def_vol: Dictionary) -> void:
	mech._apply_stat_move(att, defn, md, msgs, att_st, def_st, def_vol)


func _change_stage(mon: Dictionary, stages: Dictionary, stat_name: String, delta: int, msgs: Array) -> void:
	mech._change_stage(mon, stages, stat_name, delta, msgs)


func _stat_move_trailer(target_is_player: bool, up: bool) -> void:
	mech._stat_move_trailer(target_is_player, up)


# ---- drawing ---------------------------------------------------------------

func _draw() -> void:
	if _wavy_tex != null:                                # AnimationWavyScreen owns the whole frame
		_draw_wavy()
		return
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	if state in ["party", "party_forced", "party_shift"]:
		_draw_party()
		return
	if _anim_shake != Vector2.ZERO:                      # screen shake: BG scroll wobble (gh #19)
		draw_set_transform(_anim_shake, 0.0, Vector2.ONE)
	if _intro_stage != "":                               # battle-start slide/send-out sequence
		_draw_intro()
	else:
		if trainer_pic_tex and trainer_pic_x < 160.0:    # trainer pic covers the enemy-mon slot
			# (#11), based at y=54 like the intro (gh #47: it sat 10px low at the defeat re-show)
			draw_texture(trainer_pic_tex, Vector2(trainer_pic_x, 54.0 - trainer_pic_tex.get_height()))
		elif front_tex and not _pic_gone["enemy"] and _faint_who != "enemy" \
				and not (_flash_who == "enemy" and not _flash_on) and not _anim_hidden["enemy"]:
			# centered in the 7x7 enemy box (hlcoord 12,0) with its base at the player-name row;
			# hidden while its faint slide draws the sinking copy (_draw_faint_sprite)
			var esc: Vector2 = _anim_scale["enemy"]
			if _sub_shown["enemy"]:                      # the doll stands in (AnimationSubstitute:
				draw_texture_rect_region(_monster_tex,   # MonsterSprite facing down, low center)
					Rect2(Vector2(116, 38) + _anim_off["enemy"], Vector2(16, 16)),
					Rect2(0, 0, 16, 16))
			elif esc == Vector2.ONE:
				_draw_pic_clipped(front_tex,
					Rect2(Vector2(96.0 + (56.0 - front_tex.get_width()) / 2.0,
						54.0 - front_tex.get_height()) + _anim_off["enemy"],
						Vector2(front_tex.get_width(), front_tex.get_height())), ENEMY_BOX,
					Color(0.4, 0.4, 0.4) if _anim_mon_dark["enemy"] else Color.WHITE)
			else:                                        # squish/minimize: anchored bottom-centre
				var ew := front_tex.get_width() * esc.x
				var eh := front_tex.get_height() * esc.y
				_draw_pic_clipped(front_tex,
					Rect2(Vector2(124.0 - ew / 2.0, 54.0 - eh) + _anim_off["enemy"],
						Vector2(ew, eh)), ENEMY_BOX)
		if back_tex and not _pic_gone["player"] and _faint_who != "player" and not is_safari \
				and not demo and not _trainer_intro \
				and not (_flash_who == "player" and not _flash_on) and not _anim_hidden["player"]:
			# back sprite is drawn at 2x; squish/minimize scale it anchored bottom-centre
			var psc: Vector2 = _anim_scale["player"]
			if _sub_shown["player"]:                     # the doll stands in (facing up, 2x)
				draw_texture_rect_region(_monster_tex,
					Rect2(Vector2(24, 72) + _anim_off["player"], Vector2(32, 32)),
					Rect2(0, 16, 16, 16))
			else:
				_draw_pic_clipped(back_tex, Rect2(
					Vector2(40.0 - 32.0 * psc.x, 104.0 - 64.0 * psc.y) + _anim_off["player"],
					Vector2(64.0 * psc.x, 64.0 * psc.y)), PLAYER_BOX,
					Color(0.4, 0.4, 0.4) if _anim_mon_dark["player"] else Color.WHITE)
		elif is_safari or demo:              # safari: the player's own pic; the demo: OLD MAN's
			draw_texture_rect(_oldman_tex if demo else _trainer_back_tex,
				Rect2(8, 40, 64, 64), false)
		if _faint_who != "":                             # the fainting pic sinking down
			_draw_faint_sprite()
		if not (trainer_pic_tex and trainer_pic_x < 160.0):  # enemy HUD hidden while the pic is shown
			if _anim_hud_off != Vector2.ZERO:
				draw_set_transform(_anim_hud_off)            # SE_SHAKE_ENEMY_HUD rattles just the HUD
			_info(enemy_mon, false)
			if _anim_hud_off != Vector2.ZERO:
				draw_set_transform(Vector2.ZERO)
		if not is_safari and not _trainer_intro and not demo:   # player mon/HUD appears after the
			_info(player_mon, true)                      # slide-out (safari sends no mon out, and
			                                             # the old-man demo never does)
	Frame.draw(self, frame_tex, 0, 96, 20, 6, LIGHT)     # bottom text box (rows 12-17)
	match state:
		"msg":
			_draw_msg()
		"learn":                                         # the move-forget screen (learn_move.asm)
			_draw_learn()
		"shift":                                         # the change-POKéMON prompt (SHIFT style)
			_draw_msg()
			Frame.draw(self, frame_tex, 0, 56, 6, 5, LIGHT)   # yes/no box (DisplayYesNoTextBox 0,7)
			for i in 2:
				if i == cursor:
					_cursor(8, 64 + i * 16)
				_text(["YES", "NO"][i], 16, 64 + i * 16)
		"levelstats":                                    # PrintStatsBox: the new stats in a box on the right
			_draw_msg()                                  # "X grew to level N!" stays in the bottom box
			Frame.draw(self, frame_tex, 72, 16, 11, 10, LIGHT)   # box at hlcoord 9,2
			var lbl := ["ATTACK", "DEFENSE", "SPEED", "SPECIAL"]
			var key := ["atk", "def", "spd", "spc"]
			for i in 4:
				_text(lbl[i], 80, 24 + i * 16)
				_text("%3d" % int(_level_stats[key[i]]), 120, 32 + i * 16)
		"menu":
			if is_safari:
				# SAFARI_BATTLE_MENU_TEMPLATE (data/text_boxes.asm) is ONE full-width box, 0,12..19,17
				# — the bottom frame drawn above IS it — with the text at 2,14 (gh #169):
				#     BALL×nn     BAIT      the count PrintNumber'd inside the menu at 7,14
				#     THROW ROCK  RUN       (core.asm .safariLeftColumn / .safariRightColumn)
				# and the cursor at column x=1 (left items) / x=13 (right items).
				_text("BALL×", 16, 112)
				_text("%2d" % main.safari_balls, 56, 112)
				_text("BAIT", 112, 112)
				_text("THROW ROCK", 16, 128)
				_text("RUN", 112, 128)
				_cursor(8 if cursor % 2 == 0 else 104, 112 if cursor < 2 else 128)
			else:
				# The menu is its own box on the right (BATTLE_MENU_TEMPLATE = 8,12..19,17), overlaid on
				# the text box so its left border divides the bottom into an (empty) message box + menu.
				Frame.draw(self, frame_tex, 64, 96, 12, 6, LIGHT)
				var pos := [Vector2(80, 112), Vector2(128, 112), Vector2(80, 128), Vector2(128, 128)]
				for i in menu_items.size():
					if i == cursor:
						_cursor(int(pos[i].x) - 8, int(pos[i].y))
					if str(menu_items[i]) == "PKMN":     # <PK><MN> ligature tiles
						_glyph(97, int(pos[i].x), int(pos[i].y))
						_glyph(98, int(pos[i].x) + 8, int(pos[i].y))
					else:
						_text(str(menu_items[i]), int(pos[i].x), int(pos[i].y))
		"moves":
			# FIGHT menu (MoveSelectionMenu): the move list in a box on the right (4,12) + a TYPE/PP
			# box for the hovered move on the left (0,8), over the back-sprite area.
			Frame.draw(self, frame_tex, 32, 96, 16, 6, LIGHT)   # moves box
			var mv: Array = player_mon["moves"]
			for i in 4:                                         # all 4 slots; FormatMovesString prints "-" for empty
				var y := 104 + i * 8                            # moves at (6,13), single-spaced
				if i == cursor:
					_cursor(40, y)
				elif i == _move_swap:                           # the SELECT-held move (SelectMenuItem '▷')
					_text("▷", 40, y)
				_text(str(moves_db[mv[i]["move"]]["name"]) if i < mv.size() else "-", 48, y)
			Frame.draw(self, frame_tex, 0, 64, 11, 5, LIGHT)    # TYPE / PP box for the hovered move
			var m: Dictionary = mv[cursor]
			var mdef: Dictionary = moves_db[str(m["move"])]
			_text("TYPE/", 8, 72)                                # (1,9)
			_text(str(mdef.get("type", "")).to_upper(), 16, 80)  # type name (2,10)
			_text("%2d/%2d" % [m["pp"], m["maxpp"]], 40, 88)     # cur/max PP (5,11)
		"mimic":
			# MIMIC's pick menu (MoveSelectionMenu .mimicmenu): the TARGET's moves in a box
			# at (0,7), names at (2,8) single-spaced, cursor in column 1 (gh #65).
			Frame.draw(self, frame_tex, 0, 56, 16, 6, LIGHT)
			for i in _mimic_moves.size():
				var y := 64 + i * 8
				if i == cursor:
					_cursor(8, y)
				_text(str(moves_db[str(_mimic_moves[i])]["name"]), 16, y)
		"item":
			# The bag overlay (DisplayPlayerBag): a framed list at (4,2)-(19,12), four items
			# visible with 2-row spacing, each quantity on its second row, CANCEL last.
			Frame.draw(self, frame_tex, 32, 16, 16, 11, LIGHT)
			var entries: Array = bag_keys + ["CANCEL"]
			var ivis := mini(4, entries.size() - _item_scroll)
			for r in ivis:
				var i := _item_scroll + r
				var y := 32.0 + r * 16.0                 # names at (6,4), 2 rows apart
				if i == cursor:
					_text("▶", 40, y)
				elif i == _item_swap:                    # the SELECT-held item (list_menu.asm '▷')
					_text("▷", 40, y)
				_text(str(entries[i]), 48, y)
				if i < bag_keys.size():
					_text("×", 112, y + 8)               # quantity on the row below, col 14
					_text("%2d" % int(main.player_bag[bag_keys[i]]), 120, y + 8)
			if _item_scroll + 4 < entries.size():
				_text("▼", 144, 88)                      # (18,11), level with the last quantity
	if state == "anim" and _intro_stage in ["enemy_hud", "pause", "slide_off", "t_slide_off",
			"enemy_grow", "throw"]:
		_draw_msg()                                       # the intro text stays up through the stages
	if _intro_stage == "throw":
		if _intro_ball_t < 6.0 * 4.0 / 60.0:              # poof is an OAM sprite -> drawn over the text box
			_draw_poof_frame(mini(5, int(_intro_ball_t / (4.0 / 60.0))), 40, 90)
	if not _anim_sprites.is_empty():                      # move-anim OAM sprites, over everything (gh #19)
		_draw_anim_sprites()
	for f in _fx:                                         # SE particles (spiral balls, droplets, leaves)
		var fp: Vector2 = f["pos"]
		match str(f["kind"]):
			"ball":
				draw_circle(fp, 3.0, DARK)
			"drop":
				draw_rect(Rect2(fp.x, fp.y, 2, 4), DARK)
			"leaf":
				draw_rect(Rect2(fp.x, fp.y, 4, 3), DARK)
	_invert.visible = _anim_flash                         # true palette inversion (flash SEs)
	if _anim_pal != "":                                   # SE screen palettes (dark/light overlay)
		var oc := LIGHT if _anim_pal == "light" else DARK
		draw_rect(Rect2(0, 0, 160, 144), Color(oc, 0.5))


## The move-forget screen (learn_move.asm TryingToLearn): "Which move should be forgotten?" in the
## bottom text box, the mon's four moves in a bordered box above (hlcoord 4,7), a cursor on one, and
## B to cancel (.cancel -> give up learning). Drawn as an overlay over the battle, as in the reference.
func _draw_learn() -> void:
	_text("Which move should", 8, 112)                   # WhichMoveToForgetText, in the bottom box
	_text("be forgotten?", 8, 128)
	Frame.draw(self, frame_tex, 32, 48, 16, 6, LIGHT)     # the move box (hlcoord 4,7, 14x4 inner)
	var mv: Array = player_mon["moves"]
	for i in mv.size():
		var y := 56 + i * 8                              # moves at (6,8), single-spaced
		if i == cursor:
			_cursor(40, y)
		_text(str(moves_db[mv[i]["move"]]["name"]), 48, y)


## A condensed glyph tile from font_battle_extra (HP=15, :L=12, ...).
func _fbe(t: int, x: float, y: float) -> void:
	draw_texture_rect_region(_fbe_tex, Rect2(x, y, 8, 8), Rect2((t % 15) * 8, (t / 15) * 8, 8, 8))


## The in-battle POKéMON screen is the same party layout as the overworld menu
## (party_menu.asm), with the battle prompt in the bottom box.
func _draw_party() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	for i in party.size():
		var m: Dictionary = party[i]
		var y := i * 16.0
		var y2 := y + 8.0
		var sp := str(m["species"])
		if _icons_tex and _icons_map.has(sp):
			draw_texture_rect_region(_icons_tex, Rect2(8, y, 16, 16),
				Rect2(int(_icons_map[sp]) * 16, 0, 16, 16))
		if i == cursor:
			_text("▶", 0, y2)                                # the cursor rides the HP row
		_text(str(m["name"]), 24, y)
		_fbe(12, 104, y)                                     # the ":L" tile at col 13
		_text(str(int(m["level"])), 112, y)
		var st := str(m.get("status", "")).to_upper()
		if int(m["hp"]) <= 0:
			st = "FNT"
		if st != "":
			_text(st, 136, y)                                # status at col 17
		draw_texture_rect_region(hud_tex, Rect2(32, y2, 8, 8), Rect2(15 * 8, 0, 8, 8))
		draw_texture_rect_region(hud_tex, Rect2(40, y2, 8, 8), Rect2(0, 0, 8, 8))
		var frac := clampf(float(m["hp"]) / maxf(1.0, float(m["maxhp"])), 0.0, 1.0)
		draw_rect(Rect2(48, y2 + 2, 48, 1), DARK)            # the Gen-1 pill bar
		draw_rect(Rect2(48, y2 + 5, 48, 1), DARK)
		draw_rect(Rect2(47, y2 + 3, 1, 2), DARK)
		draw_rect(Rect2(96, y2 + 3, 1, 2), DARK)
		draw_rect(Rect2(48, y2 + 3, maxf(1.0 if int(m["hp"]) > 0 else 0.0, floorf(48.0 * frac)), 2), DARK)
		_text("%3d/" % int(m["hp"]), 104, y2)
		_text("%4d" % int(m["maxhp"]), 128, y2)
	Frame.draw(self, frame_tex, 0, 96, 20, 6, LIGHT)
	_text("Bring out which\nPOKéMON?", 8, 112)


## One stage of the battle-start sequence (see start/start_trainer for the faithful order).
## A stage's visual state lingers (via _intro_stage) through any {"auto"} text queued after it,
## until the next stage replaces it; "throw"/"enemy_grow"/"end" clear it when the intro is over
## (a lingering value would make the _process HP-sync snap bars mid-turn).
func _do_intro_stage(stage: String) -> void:
	_intro_stage = stage
	state = "anim"                                       # no input while the sequence plays
	var tw := create_tween()
	match stage:
		"silhouette":                                    # dark pics slide in: 144 px at 2 px/frame
			_intro_pback_x = 152.0                       # (hSCX $90 -> 0), 72 frames ~= 1.2 s
			_intro_efront_x = -48.0
			tw.tween_interval(3.0 / 60.0)                # the screen-prep beat after the wipe
			tw.tween_method(func(t: float) -> void:
				_intro_pback_x = lerpf(152.0, 8.0, t)
				_intro_efront_x = lerpf(-48.0, 96.0, t)
				queue_redraw(), 0.0, 1.0, 1.2)
		"reveal":                                        # palettes restored to normal (Delay3)
			queue_redraw()
			tw.tween_interval(3.0 / 60.0)
		"t_appeared":                                    # trainer battle: the encounter sting, then
			if main.audio:                               # a beat (WaitForSoundToFinish + 20 frames)
				main.audio.play_sfx("trainer_appeared")
			tw.tween_interval(1.0)
		"pokeballs":                                     # DrawAllPokeballs — with the wild mon's cry
			if not is_trainer and main.audio:            # (PrintBeginningBattleText)
				main.audio.play_cry(str(enemy_mon["species"]))
			_intro_pokeballs = true
			queue_redraw()
			tw.tween_interval(3.0 / 60.0)
		"enemy_hud":                                     # the enemy HUD appears (after the text)
			_intro_enemy_hud = true
			queue_redraw()
			tw.tween_interval(3.0 / 60.0)
		"pause":                                         # StartBattle's DelayFrames 40
			tw.tween_interval(40.0 / 60.0)
		"t_slide_off":                                   # the enemy trainer slides off to the right
			_intro_pokeballs = false                     # (8 tile-steps x 2 frames); the brackets
			tw.tween_method(func(t: float) -> void:      # go with the send-out (ClearSprites)
				_intro_efront_x = lerpf(96.0, 160.0, t); queue_redraw(), 0.0, 1.0, 16.0 / 60.0)
			tw.tween_callback(func() -> void: _trainer_intro = false)
		"enemy_grow":                                    # the sent-out mon pops in through 3 sizes,
			_intro_egrow = 3.0 / 7.0                     # then cries (AnimateSendingOutMon at 15,6;
			queue_redraw()                               # also the mid-battle EnemySendOut)
			tw.tween_interval(4.0 / 60.0)
			tw.tween_callback(func() -> void: _intro_egrow = 5.0 / 7.0; queue_redraw())
			tw.tween_interval(5.0 / 60.0)
			tw.tween_callback(func() -> void:
				_intro_egrow = 0.0                       # full pic takes over from the grow draw
				_intro_stage = ""                        # (the next intro stage re-enters same-frame)
				queue_redraw()
				if main.audio:
					main.audio.play_cry(str(enemy_mon["species"])))
		"slide_off":                                     # the player pic slides off to the left
			_intro_pokeballs = false                     # (9 tile-steps x 2 frames)
			tw.tween_method(func(t: float) -> void:
				_intro_pback_x = lerpf(8.0, -72.0, t); queue_redraw(), 0.0, 1.0, 18.0 / 60.0)
		"throw":                                         # player HUD + poof + first mon pops out
			_intro_player_hud = true
			_intro_ball_t = 0.0
			revealed = 999                               # "Go! X!" (typed by the auto text) stays up
			tw.tween_interval(0.2)
			# _intro_ball_t tracks elapsed seconds: 0.4 s poof (6x4/60) then 0.15 s grow (4/60 + 5/60)
			tw.tween_method(func(t: float) -> void: _intro_ball_t = t; queue_redraw(), 0.0, 0.55, 0.55)
			tw.tween_callback(func() -> void:
				_intro_stage = ""
				_intro_pokeballs = false                 # brackets are intro-only
				if main.audio:
					main.audio.play_cry(str(player_mon["species"])))
		"end":                                           # safari: the intro ends with no send-out
			_intro_stage = ""
			_intro_pokeballs = false
			queue_redraw()
	tw.tween_callback(_next_msg)


func _draw_intro() -> void:
	# Right side: the wild mon — or the enemy trainer's pic until it slides off (t_slide_off),
	# after which the sent-out mon grows in (enemy_grow).
	var etex: Texture2D = trainer_pic_tex if _trainer_intro and trainer_pic_tex else front_tex
	var ew := etex.get_width()
	var ey := 54.0 - etex.get_height()
	if _intro_stage == "silhouette":                     # both pics slide in as dark shapes
		draw_texture(etex, Vector2(_intro_efront_x + (56.0 - ew) / 2.0, ey), DARK)
		draw_texture_rect(_trainer_back_tex, Rect2(_intro_pback_x, 40, 64, 64), false, DARK)
		return
	if _intro_stage == "t_slide_off":                    # the enemy trainer sliding off right
		draw_texture(etex, Vector2(_intro_efront_x + (56.0 - ew) / 2.0, ey))
	elif _intro_stage == "enemy_grow":                   # the sent-out mon growing in (3 sizes)
		if _intro_egrow > 0.0:
			var gw := 56.0 * _intro_egrow
			draw_texture_rect(front_tex, Rect2(96.0 + (56.0 - gw) / 2.0, 54.0 - gw, gw, gw), false)
	else:                                                # in place (full)
		draw_texture(etex, Vector2(96.0 + (56.0 - ew) / 2.0, ey))
	if _intro_stage != "throw":
		if _intro_player_hud:                            # mid-battle send-out: the player's mon is out
			if back_tex and not _pic_gone["player"]:
				draw_texture_rect(back_tex, Rect2(8, 40, 64, 64), false)
			_info(player_mon, true)
		else:                                            # intro: the player's trainer pic
			draw_texture_rect(_trainer_back_tex, Rect2(_intro_pback_x, 40, 64, 64), false)
	if _intro_pokeballs:
		_draw_party_pokeballs()
	if _intro_enemy_hud:
		_info(enemy_mon, false)
	if _intro_stage == "throw":
		if _intro_player_hud:
			_info(player_mon, true)
		if _intro_ball_t >= 6.0 * 4.0 / 60.0:            # the grown mon sits behind the text box
			_draw_grow()


func _draw_party_pokeballs() -> void:
	# the player HUD bracket + one status ball per party mon (SetupOwnPartyPokeballs)
	_hud_tile(0x73, 144, 80); _hud_tile(0x77, 144, 88)
	for i in 8:
		_hud_tile(0x76, 136 - i * 8, 88)
	_hud_tile(0x6f, 72, 88)
	for i in 6:                                           # all six slots; empty ball for unused ones
		var st := 3                                       # 3 = empty slot
		if i < party.size():
			st = 1 if int(party[i]["hp"]) <= 0 else 0     # 0 = healthy, 1 = fainted
		draw_texture_rect_region(_balls_tex, Rect2(88 + i * 8, 80, 8, 8), Rect2(st * 8, 0, 8, 8))
	if not is_trainer:
		return
	# trainer battle: the enemy party's mirrored bracket, top-left (SetupEnemyPartyPokeballs)
	_hud_tile(0x73, 8, 16); _hud_tile(0x74, 8, 24)
	for i in 8:
		_hud_tile(0x76, 16 + i * 8, 24)
	_hud_tile(0x78, 80, 24)
	for i in 6:
		var st := 3
		if i < enemy_party.size():
			st = 1 if int(enemy_party[i]["hp"]) <= 0 else 0
		draw_texture_rect_region(_balls_tex, Rect2(64 - i * 8, 16, 8, 8), Rect2(st * 8, 0, 8, 8))


func _draw_grow() -> void:
	# AnimateSendingOutMon: after the poof the mon grows through 3 discrete sizes (3x3 -> 5x5 -> full).
	# Drawn behind the text box, like the mon proper; the poof (an OAM sprite in Gen 1) is drawn over
	# the box instead. Timing is DelayFrames 4 then 5 for the two downscaled sizes.
	var gt := _intro_ball_t - 6.0 * 4.0 / 60.0
	var frac := 3.0 / 7.0
	if gt >= 9.0 / 60.0:
		frac = 1.0
	elif gt >= 4.0 / 60.0:
		frac = 5.0 / 7.0
	var w := 64.0 * frac
	var h := 64.0 * frac
	draw_texture_rect(back_tex, Rect2(8 + (64 - w) / 2.0, 104 - h, w, h), false)


## The send-out poof, drawn from POOF_ANIM's own frame blocks (the generic anim data) —
## the same source every move animation uses, built lazily on first draw. The anim's default
## orientation is the enemy box (the catch poof); the send-out plays it flipped to our side.
func _draw_poof_frame(i: int, _bx: int, _by: int) -> void:
	if _poof_steps.is_empty():
		_poof_steps = _build_move_anim("POOF_ANIM", false)
	if _poof_steps.is_empty():
		return
	_draw_sprite_list(_poof_steps[mini(i, _poof_steps.size() - 1)]["sprites"])


# ---- move animations (gh #19): pokered's DrawFrameBlock system ---------------

## Build a move's animation as a list of steps. A visual frame is the full shadow-OAM to show:
## {"sprites": [[sheet, tile, x, y, xflip, yflip], ...], "wait": s, "sfx": move-const-or-""};
## a special-effect command becomes {"se": name, "sfx", "sprites": the OAM at that point} (kept
## blocks stay on screen through an SE, as on GB).
## Mirrors PlayAnimation/PlaySubanimation/DrawFrameBlock (engine/battle/animations.asm) over
## move_anims.json: each frame block writes its sprites at the OAM pointer; a block with a delay
## (modes 0/3/4) shows a frame; then mode 2/3 advance the pointer past the block, 4 leaves it
## (the next block overwrites this one), 0 erases the buffer and restarts — except GROWL, whose
## erase is skipped (asm quirk). The buffer persists across the anim's subanims with only the
## pointer reset (so ROCK SLIDE's lifted rocks linger into the toss). The subanim transform
## applies on the enemy's turn only; type 5 (ENEMY) means hflip on the *player's* turn instead
## (GetSubanimationTransform1/2).
func _build_move_anim(move: String, att_is_player: bool) -> Array:
	if not att_is_player:                             # ShareMoveAnimations: the enemy's AMNESIA and
		if move == "AMNESIA":                         # REST reuse the status-condition animations
			move = "CONF_ANIM"
		elif move == "REST":
			move = "SLP_ANIM"
	var frames: Array = []
	var anims: Dictionary = _manim.get("anims", {})
	if not anims.has(move):
		return frames
	var oam: Array = []                               # flat shadow-OAM sprite list
	for cmd in anims[move]:
		if not cmd.has("sub"):                        # special effect, run natively (phase 3)
			frames.append({"se": str(cmd["se"]), "sfx": "" if cmd["sfx"] == null else str(cmd["sfx"]),
				"sprites": oam.duplicate()})
			continue
		var sa: Dictionary = _manim["subanims"][int(cmd["sub"])]
		var t := int(sa["type"])
		if t == 5:                                    # SUBANIMTYPE_ENEMY
			t = 2 if att_is_player else 0
		elif att_is_player:
			t = 0                                     # player's turn: untransformed
		var sheet := str(_manim["tilesets"][int(cmd["tileset"])]["img"])
		var wait := int(cmd["delay"]) / 60.0
		var sfx := "" if cmd["sfx"] == null else str(cmd["sfx"])
		var fr: Array = sa["frames"]
		if t == 4:                                    # SUBANIMTYPE_REVERSE plays last -> first
			fr = fr.duplicate()
			fr.reverse()
		var ptr := 0                                  # wFBDestAddr, in sprites
		var fb_i := 0
		for f in fr:
			var block := _frame_block(sheet, int(f[0]), int(f[1]), t)
			for i in block.size():                    # write at the pointer, extending the buffer
				if ptr + i < oam.size():
					oam[ptr + i] = block[i]
				else:
					oam.append(block[i])
			var mode := int(f[2])
			fb_i += 1
			if mode != 2:                             # modes with a delay show a frame
				# wSubAnimCounter: total..1 — the per-anim hooks key off it after each block
				frames.append({"sprites": oam.duplicate(), "wait": wait, "sfx": sfx,
					"counter": fr.size() - fb_i + 1})
				sfx = ""                              # the subanim's sound plays once
			match mode:
				2, 3:
					ptr += block.size()
				4:
					pass                              # pointer stays: next block overwrites
				_:                                    # 0: erase + restart
					if move != "GROWL":
						oam = []
					ptr = 0
	return frames


## One frame block's sprites at a base coord with the subanim transform applied (DrawFrameBlock).
## Base coords are OAM-space (screen px = x-8, y-16); mirrors are around 168/136 in OAM space.
func _frame_block(sheet: String, fb: int, bc: int, t: int) -> Array:
	var base: Array = _manim["base_coords"][bc]
	var bx := int(base[0])
	var by := int(base[1])
	if t == 3:                                        # COORDFLIP mirrors the base coord only
		bx = 168 - bx
		by = 136 - by
	var out: Array = []
	for s in _manim["frame_blocks"][fb]:
		var x := bx + int(s[0])
		var y := by + int(s[1])
		var xf := int(s[3]) == 1
		var yf := int(s[4]) == 1
		if t == 1:                                    # HVFLIP: mirror final coords, toggle both flips
			x = 168 - x
			y = 136 - y
			xf = not xf
			yf = not yf
		elif t == 2:                                  # HFLIP: mirror X, translate 40 px down
			x = 168 - x
			y += 40
			xf = not xf
		out.append([sheet, int(s[2]), x - 8, y - 16, xf, yf])
	return out


func _draw_anim_sprites() -> void:
	_draw_sprite_list(_anim_sprites + _growl_trail)


func _draw_sprite_list(sprites: Array) -> void:
	for s in sprites:
		var tile := int(s[1])
		var src := Rect2((tile & 15) * 8, (tile >> 4) * 8, 8, 8)   # sheets are 16 tiles/row
		var sx := -1.0 if s[4] else 1.0
		var sy := -1.0 if s[5] else 1.0
		draw_set_transform(Vector2(int(s[2]) + (8 if s[4] else 0), int(s[3]) + (8 if s[5] else 0)),
			0.0, Vector2(sx, sy))
		draw_texture_rect_region(_manim_tex[s[0]], Rect2(0, 0, 8, 8), src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Play a move's animation: step through the compiled frames/effects, then hand the queue back.
## Each step's sound is the referenced move's MoveSoundTable entry, started with the step.
func _play_move_anim(move: String, att_is_player: bool) -> void:
	# The per-anim frame-block hook (AnimationIdSpecialEffects): runs after every frame block,
	# keyed on the counting-down block counter (flash cadences, Explosion's vanish, ...).
	var hook: String = str(_manim.get("anim_special_effects", {}).get(move, ""))
	for st in _build_move_anim(move, att_is_player):
		if str(st.get("sfx", "")) != "":
			var cue := _move_sfx_cue(str(st["sfx"]))
			if not cue.is_empty():
				_sfx(str(cue["sfx"]), int(cue["pitch"]))
		_anim_sprites = st["sprites"]
		queue_redraw()
		if st.has("se"):
			await _do_special_effect(str(st["se"]), att_is_player)
		else:
			await _anim_wait(float(st["wait"]))
			if hook != "" and st.has("counter"):
				await _anim_hook(hook, int(st["counter"]), att_is_player)
	_anim_sprites = []                                # callers clean OAM after PlayAnimation
	_anim_pal = ""                                    # safety: no SE state may leak into the turn
	_anim_flash = false
	_anim_shake = Vector2.ZERO
	_anim_hud_off = Vector2.ZERO
	_anim_hidden = {"player": false, "enemy": false}
	_anim_off = {"player": Vector2.ZERO, "enemy": Vector2.ZERO}
	_anim_scale = {"player": Vector2.ONE, "enemy": Vector2.ONE}
	_anim_mon_dark = {"player": false, "enemy": false}
	_growl_trail = []
	_fx = []
	_wavy_tex = null                                  # never leave the frozen wavy frame up
	queue_redraw()
	_next_msg()


func _anim_wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


## The per-anim frame-block hooks (animations.asm AnimationIdSpecialEffects): cnt is
## wSubAnimCounter, counting down from the subanimation's block total to 1.
func _anim_hook(hook: String, cnt: int, att_is_player: bool) -> void:
	match hook:
		"AnimationFlashScreen":                        # Mega Punch/Kick, Guillotine, Headbutt,
			await _hook_flash()                        # Disable, Bubblebeam, Reflect, Spore
		"FlashScreenEveryEightFrameBlocks":            # Thunderbolt
			if cnt & 7 == 0:
				await _hook_flash()
		"FlashScreenEveryFourFrameBlocks":             # Hyper Beam
			if cnt & 3 == 0:
				await _hook_flash()
		"DoBlizzardSpecialEffects":                    # flashes at blocks 13/9/5/1
			if cnt in [13, 9, 5, 1]:
				await _hook_flash()
		"DoExplodeSpecialEffects":                     # Explosion/Selfdestruct: the user vanishes
			if cnt == 1:                               # at the end, flash-every-4 before that
				_anim_hidden["player" if att_is_player else "enemy"] = true
				queue_redraw()
			elif cnt & 3 == 0:
				await _hook_flash()
		"DoGrowlSpecialEffects":                       # the note doubles: OAM 0-3 copied aside,
			_growl_trail = _anim_sprites.slice(0, 4)   # so the previous note trails the new one
			if cnt == 1:
				_growl_trail = []                      # AnimationCleanOAM at the subanim's end
			queue_redraw()
		"DoRockSlideSpecialEffects":                   # rocks landing: shakes at 8-11, flash at 1
			if cnt < 12 and cnt >= 8:
				_anim_shake = Vector2(1, 1)
				queue_redraw()
				await _anim_wait(2.0 / 60.0)
				_anim_shake = Vector2.ZERO
				queue_redraw()
			elif cnt == 1:
				await _hook_flash()
		_:
			pass                                       # Growl's OAM note copy / trade & ball
			                                           # hooks live in their bespoke players


## AnimationFlashScreen: the BG palette inverts for 2 frames, then restores for 2.
func _hook_flash() -> void:
	_anim_flash = true
	queue_redraw()
	await _anim_wait(2.0 / 60.0)
	_anim_flash = false
	queue_redraw()
	await _anim_wait(2.0 / 60.0)


## Draw a pic clipped to its box: the visible part is the dst∩box intersection, with the
## matching source sub-rect (so slides cut off at the box edge instead of crossing the HUD).
func _draw_pic_clipped(tex: Texture2D, dst: Rect2, box: Rect2, mod := Color.WHITE) -> void:
	var vis := dst.intersection(box)
	if vis.size.x <= 0.0 or vis.size.y <= 0.0:
		return
	var sc := Vector2(tex.get_width() / dst.size.x, tex.get_height() / dst.size.y)
	var src := Rect2((vis.position - dst.position) * sc, vis.size * sc)
	draw_texture_rect_region(tex, vis, src, mod)


## The on-screen centre of a side's pic (for particle effects).
func _pic_center(who: String) -> Vector2:
	if who == "player":
		return Vector2(40, 72)
	var h := float(front_tex.get_height()) if front_tex else 56.0
	return Vector2(124.0, 54.0 - h / 2.0)


## Phase 3 (gh #19/#20): the special-effect routines (SpecialEffectPointers), reimplemented on the
## _anim_* render state. "mon" = the attacker's pic, "enemy mon" = the target's — the SE_*ENEMY*
## routines are the plain ones with the turn flipped (CallWithTurnFlipped). Every used SE is handled
## (gh #20); a few particle/raster effects are rendered as approximations of pokered's exact per-OAM /
## per-scanline math (notably wavy_screen — see the roadmap). The two SEs pokered marks unused
# SpiralBallAnimationCoordinates: the 21 (y,x) OAM pairs the three spiralling balls trail
# along, stored here as (x, y). Screen pos = coord − the OAM offset (8, 16), plus the
# per-turn base (0,0 player / +80,−40 enemy).
const _SPIRAL_COORDS := [
	Vector2(0x28, 0x38), Vector2(0x18, 0x40), Vector2(0x10, 0x50), Vector2(0x18, 0x60),
	Vector2(0x28, 0x68), Vector2(0x38, 0x60), Vector2(0x40, 0x50), Vector2(0x38, 0x40),
	Vector2(0x28, 0x40), Vector2(0x1E, 0x46), Vector2(0x18, 0x50), Vector2(0x1E, 0x5B),
	Vector2(0x28, 0x60), Vector2(0x32, 0x5B), Vector2(0x38, 0x50), Vector2(0x32, 0x46),
	Vector2(0x28, 0x48), Vector2(0x20, 0x50), Vector2(0x28, 0x58), Vector2(0x30, 0x50),
	Vector2(0x28, 0x50)]

# FallingObjects_InitialXCoords / InitialMovementData / DeltaXs — the per-object OAM state
# tables for AnimationFallingObjects (leaves use the first 3, petals all 20). A movement
# byte's low 7 bits index the delta list (wrapping at 9), bit 7 flips the drift direction.
const _FALL_INIT_X := [0x38, 0x40, 0x50, 0x60, 0x70, 0x88, 0x90, 0x56, 0x67, 0x4A,
	0x77, 0x84, 0x98, 0x32, 0x22, 0x5C, 0x6C, 0x7D, 0x8E, 0x99]
const _FALL_INIT_MOVE := [0x00, 0x84, 0x06, 0x81, 0x02, 0x88, 0x01, 0x83, 0x05, 0x89,
	0x09, 0x80, 0x07, 0x87, 0x03, 0x82, 0x04, 0x85, 0x08, 0x86]
const _FALL_DELTA_X := [0, 1, 3, 5, 7, 9, 11, 13, 15]


## (SE_SHAKE_ENEMY_HUD_2, SE_FLASH_ENEMY_MON_PIC) fall through to the default.
func _do_special_effect(se: String, att_is_player: bool) -> void:
	var att := "player" if att_is_player else "enemy"
	var def := "enemy" if att_is_player else "player"
	match se:
		"delay_animation_10":                    # AnimationDelay10
			await _anim_wait(10.0 / 60.0)
		"dark_screen_flash":                     # AnimationFlashScreen: BGP inverted ~2 frames
			_anim_flash = true
			queue_redraw()
			await _anim_wait(2.0 / 60.0)
			_anim_flash = false
			queue_redraw()
			await _anim_wait(2.0 / 60.0)
		"flash_screen_long":                     # AnimationFlashScreenLong: 3 palette cycles
			for i in 3:
				_anim_flash = true
				queue_redraw()
				await _anim_wait(4.0 / 60.0)
				_anim_flash = false
				queue_redraw()
				await _anim_wait(4.0 / 60.0)
		"dark_screen_palette":
			_anim_pal = "dark"
			queue_redraw()
		"darken_mon_palette":                    # dims just the attacker's pic (OBP write)
			_anim_mon_dark[att] = true
			queue_redraw()
		"light_screen_palette":
			_anim_pal = "light"
			queue_redraw()
		"reset_screen_palette":
			_anim_pal = ""
			_anim_mon_dark = {"player": false, "enemy": false}
			queue_redraw()
		"shake_screen", "shake_enemy_hud":       # AnimationShakeScreen: a decaying window bounce
			for i in range(8, 0, -1):            # from 8 px (PredefShakeScreenHorizontally b=8);
				_anim_shake = Vector2(float(i), 0.0)   # the BG moves, OAM sprites don't
				queue_redraw()
				await _anim_wait(4.0 / 60.0)
				_anim_shake = Vector2.ZERO
				queue_redraw()
				await _anim_wait(5.0 / 60.0)
		"hide_mon_pic":
			_anim_hidden[att] = true
			queue_redraw()
		"hide_enemy_mon_pic":
			_anim_hidden[def] = true
			queue_redraw()
		"show_mon_pic", "show_enemy_mon_pic":
			var swho := att if se == "show_mon_pic" else def
			_anim_hidden[swho] = false
			_anim_off[swho] = Vector2.ZERO
			queue_redraw()
			await _anim_wait(3.0 / 60.0)         # Delay3
		"blink_mon", "flash_mon_pic", "blink_enemy_mon":   # 6 cycles of 5+5 frames (AnimationBlinkMon)
			var bwho := def if se == "blink_enemy_mon" else att
			for i in 6:
				_anim_hidden[bwho] = true
				queue_redraw()
				await _anim_wait(5.0 / 60.0)
				_anim_hidden[bwho] = false
				queue_redraw()
				await _anim_wait(5.0 / 60.0)
		"move_mon_horizontally":                 # the attacker lunges a tile toward the target,
			_anim_off[att] = Vector2(8.0 if att == "player" else -8.0, 0.0)
			queue_redraw()                        # shown for 3 frames (the routine's DelayFrames 3)
			await _anim_wait(3.0 / 60.0)
		"reset_mon_position":
			_anim_off[att] = Vector2.ZERO
			_anim_off[def] = Vector2.ZERO
			queue_redraw()
		"slide_mon_up":                          # the attacker's pic rises out of its box
			await _anim_slide(att, Vector2(0, -64), 0.35)   # 7 row-shifts x Delay3 = 21 frames
		"slide_mon_down", "slide_mon_down_and_hide":   # sink out of view (Withdraw/Acid Armor)
			await _anim_slide(att, Vector2(0, 64), 0.35)
		"slide_mon_off":                         # leap off toward the target (Seismic Toss/Low Kick)
			await _anim_slide(att, Vector2(88.0 if att == "player" else -88.0, 0), 0.4)
		"slide_enemy_mon_off":                   # the target is blown away (Whirlwind)
			await _anim_slide(def, Vector2(88.0 if def == "player" else -88.0, 0), 0.4)
		"slide_mon_half_off", "slide_mon_half_left":   # Softboiled: the attacker leans half out
			await _anim_slide(att, Vector2(-32.0 if att == "player" else 32.0, 0), 0.2)
			_anim_hidden[att] = false            # still visible, just displaced
			queue_redraw()
		"spiral_balls_inward":                   # AnimationSpiralBallsInward, per-OAM exact:
			# THREE balls trail one another along SpiralBallAnimationCoordinates, advancing
			# one pair per 5-frame step; base (0,0) over the player, (+80,−40) over the enemy.
			# It ends the moment the lead ball reads the terminator, then the screen flashes
			# (the routine tails into AnimationFlashScreen).
			var sbase := Vector2(80, -40) if att == "enemy" else Vector2(0, 0)
			for step in _SPIRAL_COORDS.size() - 2:
				_fx = []
				for b in 3:
					var p: Vector2 = _SPIRAL_COORDS[step + b]
					_fx.append({"pos": sbase + p + Vector2(-8, -16), "kind": "ball"})
				queue_redraw()
				await _anim_wait(5.0 / 60.0)
			_fx = []
			_anim_flash = true                   # AnimationFlashScreen (2 frames inverted)
			queue_redraw()
			await _anim_wait(2.0 / 60.0)
			_anim_flash = false
			queue_redraw()
			await _anim_wait(2.0 / 60.0)
		"shoot_balls_upward", "shoot_many_balls_upward":   # Teleport/Sky Attack ball fountain
			var base := _pic_center(att) + Vector2(0, 24)
			var n := 4 if se == "shoot_balls_upward" else 8
			for step in 16:
				_fx = []
				for b in n:
					var t := step / 16.0 - float(b % 4) * 0.1
					if t > 0.0:
						_fx.append({"pos": base + Vector2((b - n / 2.0) * 6.0 + 3.0, -56.0 * t),
							"kind": "ball"})
				queue_redraw()
				await _anim_wait(2.0 / 60.0)
			_fx = []
			queue_redraw()
		"water_droplets_everywhere":             # AnimationWaterDropletsEverywhere, per-OAM exact
			# (Surf/Mist/Toxic): 64 one-frame screens (d=32 outer loops × BaseY 16-then-24).
			# X starts at −16 and steps +27 in BYTE arithmetic, −168 at each row end, rows
			# +16 while Y < 112 — the wraparound IS the drifting diagonal rain.
			var wdx := 240                       # ld a, -16
			for i in 64:
				var wdy := 16 if i % 2 == 0 else 24
				_fx = []
				while wdy < 112:
					wdx = (wdx + 27) & 0xFF
					if wdx < 168:                # OAM hides X >= 168
						_fx.append({"pos": Vector2(wdx - 8.0, wdy - 16.0), "kind": "drop"})
					if wdx >= 144:
						wdx = (wdx - 168) & 0xFF
						wdy += 16
				queue_redraw()
				await _anim_wait(1.0 / 60.0)
			_fx = []
			queue_redraw()
		"wavy_screen":                           # Psychic/Night Shade: the real per-scanline raster wave
			await _do_wavy_screen()
		"bounce_up_and_down":                    # Splash: 4 hops of 8 px
			for hop in 4:
				_anim_off[att] = Vector2(0, -8)
				queue_redraw()
				await _anim_wait(6.0 / 60.0)
				_anim_off[att] = Vector2.ZERO
				queue_redraw()
				await _anim_wait(6.0 / 60.0)
		"shake_back_and_forth":                  # Double Team: rapid 8-px wobble, 8 cycles
			for i in 8:
				_anim_off[att] = Vector2(-8, 0)
				queue_redraw()
				await _anim_wait(2.0 / 60.0)
				_anim_off[att] = Vector2(8, 0)
				queue_redraw()
				await _anim_wait(2.0 / 60.0)
			_anim_off[att] = Vector2.ZERO
			queue_redraw()
		"squish_mon_pic":                        # Teleport: the pic squeezes to a sliver
			for step in 8:
				_anim_scale[att] = Vector2(1.0 - step / 8.0, 1.0)
				queue_redraw()
				await _anim_wait(2.0 / 60.0)
			_anim_scale[att] = Vector2(0.0, 1.0)
			_anim_hidden[att] = true
			_anim_scale[att] = Vector2.ONE
			queue_redraw()
		"minimize_mon":                          # Minimize: shrink to a blob at the feet
			for step in 12:
				var f := 1.0 - 0.75 * step / 12.0
				_anim_scale[att] = Vector2(f, f)
				queue_redraw()
				await _anim_wait(3.0 / 60.0)
		"substitute_mon":                        # AnimationSubstitute: the doll pops in low
			_sub_shown[att] = true
			for step in 8:
				_anim_off[att] = Vector2(0, 32.0 - step * 4.0)
				queue_redraw()
				await _anim_wait(2.0 / 60.0)
			_anim_off[att] = Vector2.ZERO
			queue_redraw()
		"transform_mon":                         # Transform: the pic becomes the target's
			if att == "player":
				back_tex = load("res://assets/pokemon/back/%s.png" % str(enemy_mon["species"]))
			else:
				front_tex = load("res://assets/pokemon/front/%s.png" % str(player_mon["species"]))
			queue_redraw()
		"leaves_falling", "petals_falling":      # AnimationFallingObjects, per-OAM exact:
			# 3 leaves (Razor Leaf) / 20 petals (Petal Dance) start at Y = 0,8,16,... with the
			# table Xs; every 3-frame tick each falls 2px while its movement byte walks the
			# delta-X list (wrapping at 9 flips the drift) — the pendulum flutter. Objects
			# reaching Y 112 park off-screen; it ends when the lead object's Y hits 104.
			# (Petals share the droplet tile $71 on cartridge; leaves are tile $37.)
			var fn := 3 if se == "leaves_falling" else 20
			var fkind := "leaf" if se == "leaves_falling" else "drop"
			var fys: Array = []
			var fxs: Array = []
			var fmv: Array = []
			for i in fn:
				fys.append(0 if i == 0 else i * 8)   # ld [wShadowOAM], 0 re-zeroes the lead
				fxs.append(_FALL_INIT_X[i])
				fmv.append(_FALL_INIT_MOVE[i])
			while int(fys[0]) != 104:
				_fx = []
				for i in fn:
					var mb: int = int(fmv[i]) + 1    # the movement byte advances FIRST
					if (mb & 0x7F) == 9:
						mb = (mb & 0x80) ^ 0x80      # wrap the deltas, flip the direction
					fmv[i] = mb
					fys[i] = int(fys[i]) + 2
					if int(fys[i]) >= 112:
						fys[i] = 160                 # parked off-screen
					# The $09/$89-seeded petals wrap-check at exactly 9 but enter at 10 and
					# climb PAST the table: on cartridge they read FallingObjects_
					# UpdateMovementByte's own code bytes as deltas and smear chaotically.
					# The port doesn't emulate raw memory; they drift at the max delta instead.
					var fdx: int = _FALL_DELTA_X[mini(mb & 0x7F, 8)]
					fxs[i] = (int(fxs[i]) + (fdx if (mb & 0x80) == 0 else -fdx)) & 0xFF
					if int(fys[i]) < 160 and int(fxs[i]) < 168:
						_fx.append({"pos": Vector2(int(fxs[i]) - 8.0, int(fys[i]) - 16.0), "kind": fkind})
				queue_redraw()
				await _anim_wait(3.0 / 60.0)
			_fx = []
			queue_redraw()
		"shake_enemy_hud":                       # the target's HUD rattles (not the whole BG)
			for i in range(6, 0, -1):
				_anim_hud_off = Vector2(float(i), 0.0)
				queue_redraw()
				await _anim_wait(3.0 / 60.0)
				_anim_hud_off = Vector2.ZERO
				queue_redraw()
				await _anim_wait(3.0 / 60.0)
		_:
			pass                                 # the two unused SEs ($E3/$E0) + any unknown id


## AnimationWavyScreen (engine/battle/animations.asm): the whole screen ripples as a per-scanline
## horizontal raster shift. pokered freezes the tilemap (BattleAnimCopyTileMapToVRAM), disables the
## auto BG transfer, then for 255 frames sets rSCX per line from WavyScreenLineOffsets — the wave
## advancing one row per frame. We capture the current 160x144 frame to a texture and, in _draw,
## redraw it row-by-row with the same offsets (OAM is unaffected on the GB, but at ±2 px on the tiny
## particle set that difference is imperceptible). The capture needs frame_post_draw, which never fires
## headless (gh #103) — guarded here: headless keeps the faithful duration with no visual.
func _do_wavy_screen() -> void:
	var can_draw := DisplayServer.get_name() != "headless"   # frame_post_draw never fires headless (gh #103)
	if not can_draw:
		await _anim_wait(WAVY_FRAMES / 60.0)         # keep the faithful duration, no visual
		return
	await RenderingServer.frame_post_draw            # let the normal frame render, then snapshot it
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.get_width() != 160:        # only the 160x144 base render is row-addressable
		await _anim_wait(WAVY_FRAMES / 60.0)
		return
	_wavy_tex = ImageTexture.create_from_image(img)
	for f in WAVY_FRAMES:
		_wavy_phase = f
		queue_redraw()
		await _anim_wait(1.0 / 60.0)
	_wavy_tex = null
	_wavy_phase = 0
	queue_redraw()


## Draw the frozen frame with each screen row shifted by its WavyScreenLineOffsets entry (the wave
## phase scrolling one row per frame). The uncovered ±2 px edge shows the LIGHT battle background,
## which is exactly the frame's own edge colour, so the shift is seamless.
func _draw_wavy() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	for y in 144:
		var o: int = WAVY_OFFSETS[(_wavy_phase + y) % WAVY_OFFSETS.size()]
		draw_texture_rect_region(_wavy_tex, Rect2(-o, y, 160, 1), Rect2(0, y, 160, 1))


## Slide a pic from its place to an offset, then keep it hidden (SE_SHOW_/RESET_ restore it).
## Durations from the asm: 8 column-slides x 3 V-blanks (off, 24 frames) or 7 row-shifts x
## Delay3 (up/down, 21 frames).
func _anim_slide(who: String, to: Vector2, dur: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: Vector2) -> void: _anim_off[who] = v; queue_redraw(),
		Vector2.ZERO, to, dur)
	await tw.finished
	_anim_hidden[who] = true
	_anim_off[who] = Vector2.ZERO
	queue_redraw()


func _draw_faint_sprite() -> void:
	# The fainting pic sinks straight down within its own area (SlideDownFaintedMonPic): show its top
	# (1 - t) fraction, shifted down by t of its height, so it slides off the bottom.
	var t: float = _faint_t
	if 1.0 - t <= 0.001:
		return
	if _faint_who == "enemy" and front_tex:
		var w := front_tex.get_width()
		var h := front_tex.get_height()
		var fx := 96.0 + (56.0 - w) / 2.0
		draw_texture_rect_region(front_tex, Rect2(fx, (54.0 - h) + h * t, w, h * (1.0 - t)), Rect2(0, 0, w, h * (1.0 - t)))
	elif _faint_who == "player" and back_tex:
		var th := back_tex.get_height()
		draw_texture_rect_region(back_tex, Rect2(8, 40.0 + 64.0 * t, 64, 64.0 * (1.0 - t)), Rect2(0, 0, back_tex.get_width(), th * (1.0 - t)))


func _info(mon: Dictionary, is_player: bool) -> void:
	# Battle HUD at pokered's exact tile coords (Draw{Player,Enemy}HUDAndHPBar + PlaceHUDTiles). The
	# level is the single ":L" tile ($6e) + digits, or the status badge in its place; "HP:"/bar/caps
	# are the real HUD tiles; the L-bracket is the real corner/line/triangle tiles.
	var st: String = str(_shown_status["player" if is_player else "enemy"])
	var shown: float = float(_shown_hp["player" if is_player else "enemy"])   # animated (draining) HP
	var frac: float = shown / maxf(1.0, float(mon["maxhp"]))
	if is_player:
		_text(str(mon["name"]), 80, 56)                  # name (10,7)
		if st != "":
			_text(st.to_upper(), 120, 64)                # status replaces the level (15,8)
		else:
			_hud_tile(0x6e, 112, 64)                     # ":L" (14,8) + level
			_text("%d" % mon["level"], 120, 64)
		_hp_bar(80, 72, frac)                            # HP bar (10,9)
		_text("%3d/%3d" % [int(round(shown)), mon["maxhp"]], 88, 80)   # HP fraction below the bar (counts down with the drain)
		_hud_tile(0x73, 144, 80); _hud_tile(0x77, 144, 88)     # bracket: vert + corner (18,10/11)
		draw_rect(Rect2(147, 71, 2, 9), DARK)            # extend the vertical up just past the HP bar
		for i in 8:
			_hud_tile(0x76, 136 - i * 8, 88)             # underline back to (10,11)
		_hud_tile(0x6f, 72, 88)                          # left triangle (9,11)
	else:
		_text(str(mon["name"]), 8, 0)                    # name (1,0), flush to the top
		if st != "":
			_text(st.to_upper(), 40, 8)                  # status replaces the level (5,1)
		else:
			_hud_tile(0x6e, 32, 8)                       # ":L" (4,1) + level
			_text("%d" % mon["level"], 40, 8)
		_hp_bar(16, 16, frac)                            # HP bar (2,2)
		_hud_tile(0x73, 8, 16); _hud_tile(0x74, 8, 24)   # bracket: vert + corner (1,2/3)
		for i in 8:
			_hud_tile(0x76, 16 + i * 8, 24)              # underline to (9,3)
		_hud_tile(0x78, 80, 24)                          # right triangle (10,3)


func _hp_bar(x: int, y: int, frac: float) -> void:
	# DrawHPBar: "HP" ($71) + ":"/left-end ($62) + 6 empty segments ($63) + right end ($6d), green fill.
	_hud_tile(0x71, x, y)
	_hud_tile(0x62, x + 8, y)
	var bx := x + 16
	for i in 6:
		_hud_tile(0x63, bx + i * 8, y)
	if frac > 0.0:
		draw_rect(Rect2(bx, y + 3, int(48 * frac), 2), HPFILL)
	_hud_tile(0x6c, bx + 48, y)                          # rounded right cap (not the $6d "|" tile)


func _draw_msg() -> void:
	var shown := int(revealed)
	var count := 0
	var x := 8
	var line := 0
	for ch in msg:
		if ch == "\n":
			line += 1; x = 8; continue
		if count >= shown:
			break
		count += 1
		if ch != " " and charmap.has(ch):
			_glyph(charmap[ch], x, 112 + line * 16)
		x += GLYPH
	if shown >= _msg_glyphs() and _blink:            # blinking ▼ "more text" prompt, bottom-right
		draw_colored_polygon([Vector2(138, 128), Vector2(147, 128), Vector2(142, 134)], DARK)


func _cursor(x: int, y: int) -> void:
	_text("▶", x, y)                                     # the real menu-cursor glyph ($ed)


func _text(s: String, x0: int, y: int) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			_glyph(charmap[ch], x, y)
		x += GLYPH


func _hud_tile(vram: int, x: int, y: int) -> void:       # battle HUD tile by VRAM index ($62-$7f)
	draw_texture_rect_region(hud_tex, Rect2(x, y, GLYPH, GLYPH), Rect2((vram - 0x62) * GLYPH, 0, GLYPH, GLYPH))


func _glyph(t: int, x: int, y: int) -> void:
	var src := Rect2((t % font_cols) * GLYPH, (t / font_cols) * GLYPH, GLYPH, GLYPH)
	draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
