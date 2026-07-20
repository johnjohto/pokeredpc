extends Control
## Wild battle (Gen-1 rules). Self-contained modal: draws the scene, runs the
## action/move/party menus, computes damage (Gen-1 formula), and handles a party
## with switching, EXP/leveling, and move-learning.
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
const SPECIAL_TYPES := ["FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE", "DRAGON"]
const STAGE_MULT := {-6: 0.25, -5: 0.28, -4: 0.33, -3: 0.4, -2: 0.5, -1: 0.66,
	0: 1.0, 1: 1.5, 2: 2.0, 3: 2.5, 4: 3.0, 5: 3.5, 6: 4.0}
const STAT_KEY := {"ATTACK": "atk", "DEFENSE": "def", "SPECIAL": "spc",
	"SPEED": "spd", "ACCURACY": "acc", "EVASION": "eva"}
const HIGH_CRIT := ["SLASH", "KARATE_CHOP", "RAZOR_LEAF", "CRABHAMMER"]
const TWO_TURN := ["CHARGE_EFFECT", "FLY_EFFECT", "SOLARBEAM"]   # turn 1 charges
const _VANISH_CHARGE := ["DIG", "FLY"]          # ...and these two go out of sight while they do (gh #122)
# stat-down side effects -> the stat they lower
const SIDE_STAT := {"SPEED_DOWN_SIDE_EFFECT": "SPEED", "DEFENSE_DOWN_SIDE_EFFECT": "DEFENSE",
	"ATTACK_DOWN_SIDE_EFFECT": "ATTACK", "SPECIAL_DOWN_SIDE_EFFECT": "SPECIAL"}

var p_stages: Dictionary
var e_stages: Dictionary
var p_vol: Dictionary
var e_vol: Dictionary
var _eff_re := RegEx.new()

var main                    # Main: make_mon / exp_for_level / recompute_stats / heal_party
var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var base_stats: Dictionary
var moves_db: Dictionary
var type_chart: Dictionary

var party: Array = []
var active := 0
var participants: Array = []   # party indices that fought the current enemy (for EXP split)
var learn_move := ""           # move pending the "delete a move?" prompt
var player_mon: Dictionary
var enemy_mon: Dictionary
var enemy_party: Array = []   # trainer battles: enemy's whole team
var enemy_active := 0
var is_trainer := false
var is_safari := false         # Safari Zone battle: BALL/BAIT/ROCK/RUN, no fighting, the mon may flee
var demo := false              # BATTLE_TYPE_OLD_MAN: the catching tutorial plays itself (no player mon)
var _demo_ran := false         # the scripted menu keystrokes have fired
var run_attempts := 0          # wNumRunAttempts: each failed try adds 30 to the next escape roll
var _item_scroll := 0          # the battle bag list's scroll window (4 visible)
var newly_caught := false      # this catch is a first-time species (dex entry shows after)
var doll_escape := false       # fled via POKé DOLL: wBattleResult stays 0 (the MAROWAK trick)
# Gen-1 trainer AI (engine/battle/trainer_ai.asm): the class's move-choice modification
# layers, its item/switch handler, and how many uses it gets per mon (wAICount).
var ai_mods: Array = []
var ai_kind := "Generic"
var ai_count_max := 3
var _ai_uses := 0
var _ai_turn := 0              # enemy moves taken (wAILayer2Encouragement)
# AIMoveChoiceModification2's effect ranges: [ATTACK_UP1, BIDE) + [ATTACK_UP2, POISON).
const MOD2_EFFECTS := ["ATTACK_UP1_EFFECT", "DEFENSE_UP1_EFFECT", "SPEED_UP1_EFFECT",
	"SPECIAL_UP1_EFFECT", "ACCURACY_UP1_EFFECT", "EVASION_UP1_EFFECT", "PAY_DAY_EFFECT",
	"SWIFT_EFFECT", "ATTACK_DOWN1_EFFECT", "DEFENSE_DOWN1_EFFECT", "SPEED_DOWN1_EFFECT",
	"SPECIAL_DOWN1_EFFECT", "ACCURACY_DOWN1_EFFECT", "EVASION_DOWN1_EFFECT",
	"CONVERSION_EFFECT", "HAZE_EFFECT", "ATTACK_UP2_EFFECT", "DEFENSE_UP2_EFFECT",
	"SPEED_UP2_EFFECT", "SPECIAL_UP2_EFFECT", "ACCURACY_UP2_EFFECT", "EVASION_UP2_EFFECT",
	"HEAL_EFFECT", "TRANSFORM_EFFECT", "ATTACK_DOWN2_EFFECT", "DEFENSE_DOWN2_EFFECT",
	"SPEED_DOWN2_EFFECT", "SPECIAL_DOWN2_EFFECT", "ACCURACY_DOWN2_EFFECT",
	"EVASION_DOWN2_EFFECT", "LIGHT_SCREEN_EFFECT", "REFLECT_EFFECT"]
var ghost := false             # unidentified GHOST (Pokémon Tower, no SILPH SCOPE): can't be fought
var unveil := false            # the scripted MAROWAK: appears as GHOST until the SILPH SCOPE reveal
var _ghost_tex: Texture2D      # the GHOST battle pic (gfx/battle/ghost.png)
var _oldman_tex: Texture2D     # the OLD MAN's back pic (the catching tutorial)
var _fbe_tex: Texture2D        # condensed glyphs (font_battle_extra)
var _icons_tex: Texture2D      # party mini icons
var _icons_map := {}
var safari_bait := 0           # "eating" counter (less likely to flee)
var safari_escape := 0         # "angry" counter (more likely to flee)
var safari_catch := 0          # current (bait/rock-modified) catch rate
var trainer_name := ""
var prize := 0
var won := false              # true once the battle is won (vs blackout)
var caught := false           # true once the enemy mon is caught (a ball succeeded)
var blacked_out := false      # true if the player ran out of usable mons
var no_blackout := false      # story battles (first rival) that heal + continue instead of whiting out
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
var _flee_pending := false    # Teleport/Whirlwind used in a wild battle
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
var can_evolve: Array = []   # party indices that leveled this battle (wCanEvolveFlags, gh #67)
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
# Link battles run deterministic lockstep: both peers simulate the identical battle from a
# shared seed and exchange only chosen actions, so every battle-LOGIC random draw must come
# from this battle-local generator — never the global RNG, which the overworld (NPC wander,
# encounter rolls) advances at frame rate. Each turn appends a canonical event line (turn,
# both actions, the RNG cursor, a state digest) to `det_stream`; byte-equality of two peers'
# streams is the DEFINITION of "in sync" (ADR-014). Verified by --battledettest.
var rng := RandomNumberGenerator.new()
var rng_cursor := 0            # logic draws since battle start (the lockstep "RNG cursor")
var battle_seed := 0           # this battle's seed (a link session fixes it at establishment)
var next_seed := -1            # set before start*() to force the seed (tests/link); -1 = derive
var det_stream: Array = []     # canonical event lines (docs/engine/battle.md "Determinism")
var det_log := false           # echo events to stdout as [battledet] lines (the link soak reads logs)
var turn_no := 0
var _det_paction := "-"        # the player action driving the current turn, canonical form
var _det_eaction := "-"        # the enemy action (in a link battle: the peer's choice)

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
var link_battle := false
var link_host := false
var peer_name := ""            # the partner's player name (their trainer label)
var link_actions: Array = []   # the peer's col_act actions, in turn order (fed by Cutscene)
var link_swaps: Array = []     # the peer's col_swap faint replacements, in order
var _link_wait := ""           # "" | "act" (their turn action) | "swap" (their replacement)
var _link_pact := {}           # our pending action while waiting for theirs
var _link_elapsed := 0.0
var link_over := false         # set when the link died mid-battle (stakeless end)


## Battle-logic random draws (the ONLY randomness battle rules may use): each advances the
## cursor, so two lockstep peers can compare how much randomness every turn consumed.
func _ri(n: int) -> int:
	rng_cursor += 1
	return rng.randi() % n


func _rr(lo: int, hi: int) -> int:
	rng_cursor += 1
	return rng.randi_range(lo, hi)


func _rf() -> float:
	rng_cursor += 1
	return rng.randf()


## One canonical event line: kind ("S" start / "T<n>" turn / "X" mid-turn decision / "END"),
## the action info, the RNG cursor, and the state digest.
func _det_event(kind: String, info: String) -> void:
	var line := "%s|%s|c=%d|%s" % [kind, info, rng_cursor, _det_digest()]
	det_stream.append(line)
	if det_log:
		print("[battledet] " + line)


## Canonical digest of everything the battle rules can read or write. Field order is fixed
## throughout — the digest must not depend on dictionary construction history.
func _det_digest() -> String:
	# Link battles (gh #7): the two peers simulate MIRRORED (each is its own "player"), so
	# the canonical digest orders the HOST's side first on both, and drops the asymmetric
	# bookkeeping that has no rule effect under link (exp participants, AI counters, run
	# attempts, the end flags — the winner is canonicalized on the END line instead).
	if link_battle:
		var sides: Array = [[active, party, p_stages, p_mod, p_vol],
			[enemy_active, enemy_party, e_stages, e_mod, e_vol]]
		if not link_host:
			sides.reverse()
		var s2 := "a%d/b%d;" % [sides[0][0], sides[1][0]]
		for m in sides[0][1]:
			s2 += _det_mon(m)
		s2 += "~"
		for m in sides[1][1]:
			s2 += _det_mon(m)
		s2 += "~" + _det_kv(sides[0][2]) + _det_kv(sides[1][2]) \
			+ _det_kv(sides[0][3]) + _det_kv(sides[1][3])
		s2 += "~" + _det_kv(sides[0][4]) + _det_kv(sides[1][4])
		return s2.md5_text()
	var s := "a%d/e%d;" % [active, enemy_active]
	for m in party:
		s += _det_mon(m)
	s += "~"
	for m in enemy_party:
		s += _det_mon(m)
	s += "~" + _det_kv(p_stages) + _det_kv(e_stages) + _det_kv(p_mod) + _det_kv(e_mod)
	s += "~" + _det_kv(p_vol) + _det_kv(e_vol)
	s += "~r%d;u%d;t%d;p%s;%s%s%s" % [run_attempts, _ai_uses, _ai_turn,
		str(participants), str(won), str(caught), str(blacked_out)]
	return s.md5_text()


func _det_mon(mon: Dictionary) -> String:
	var s := "%s,L%d,x%d,%d/%d,%s%d," % [str(mon["species"]), int(mon["level"]),
		int(mon["exp"]), int(mon["hp"]), int(mon["maxhp"]), str(mon["status"]), int(mon["sleep"])]
	s += "%d.%d.%d.%d," % [int(mon["atk"]), int(mon["def"]), int(mon["spd"]), int(mon["spc"])]
	s += str(mon["types"][0]) + "." + str(mon["types"][1]) + ","
	for mv in mon["moves"]:
		s += "%s/%d." % [str(mv["move"]), int(mv["pp"])]
	return s + ";"


## Sorted key=value dump of a stages/mod/vol dict. The Transform/Mimic backups are NOT
## digested: they are restore bookkeeping derivative of state already digested (moves/types/
## stats), and they exist only on the owning side — in mirrored link sims the same mon is
## "player" on one peer and "enemy" on the other, so their presence would falsely diverge.
func _det_kv(d: Dictionary) -> String:
	var ks := d.keys()
	ks.sort()
	var s := ""
	for k in ks:
		if str(k) in ["transform_backup", "mimic_backup"]:
			continue
		var v = d[k]
		s += "%s=%s," % [str(k), "#" if (v is Dictionary or v is Array) else str(v)]
	return s + ";"


## The canonical form of a player action for the event stream.
func _det_action(action: Dictionary) -> String:
	var kind := str(action["kind"])
	if kind == "switch":
		return "w:%d" % int(action["idx"])
	if kind == "forced":
		return "f:" + str(action["move"])
	return "m:" + str(player_mon["moves"][int(action["idx"])]["move"])


func setup(ftex: Texture2D, cols: int, cmap: Dictionary, base: Dictionary, mdb: Dictionary, tchart: Dictionary) -> void:
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
	var icf := FileAccess.open("res://assets/mon_icons.json", FileAccess.READ)
	if icf:
		_icons_map = JSON.parse_string(icf.get_as_text())
	_invert = ColorRect.new()                  # the AnimationFlashScreen palette inversion
	_invert.size = Vector2(160, 144)
	var iv := ShaderMaterial.new()
	iv.shader = load("res://shaders/invert.gdshader")
	_invert.material = iv
	_invert.visible = false
	add_child(_invert)
	_balls_tex = load("res://assets/balls.png")
	_manim = JSON.parse_string(FileAccess.get_file_as_string("res://assets/move_anims.json"))
	for ts in _manim["tilesets"]:
		if not _manim_tex.has(str(ts["img"])):
			_manim_tex[str(ts["img"])] = load("res://assets/%s.png" % str(ts["img"]))
	base_stats = base
	moves_db = mdb
	type_chart = tchart
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_eff_re.compile("^([A-Z]+)_(UP|DOWN)([12])_EFFECT$")
	visible = false


func _new_stages() -> Dictionary:
	return {"atk": 0, "def": 0, "spc": 0, "spd": 0, "acc": 0, "eva": 0}


# The STORED battle stats (wBattleMon* / wEnemyMon*), maintained exactly as pokered mutates
# them: rebuilt at send-out and level-up, one stat recalculated per stage change, penalties
# and badge boosts applied ON TOP destructively — which is what makes the Gen-1 stacking
# glitches real (see _stat_move_trailer). The mon dicts' own stats stay UNMODIFIED
# (wPlayerMonUnmodified*), used for crits and stage recalcs.
var p_mod := {"atk": 1, "def": 1, "spd": 1, "spc": 1}
var e_mod := {"atk": 1, "def": 1, "spd": 1, "spc": 1}


# Gen-1 badge stat boosts, by the EVEN BIT POSITIONS of wObtainedBadges (BadgeStatBoosts):
# Boulder (bit 0) -> ATTACK, Thunder (bit 2) -> DEFENSE, Soul (bit 4) -> SPEED,
# Volcano (bit 6) -> SPECIAL. (Not the intuitive gym order - Cascade boosts nothing.)
const _BADGE_STAT := {"atk": "BOULDERBADGE", "def": "THUNDERBADGE", "spd": "SOULBADGE", "spc": "VOLCANOBADGE"}


## One ×1.125 badge application: v += v/8, capped at MAX_STAT_VALUE (999).
## Link battles take none (ApplyBadgeStatBoosts rets on LINK_STATE_BATTLING) — and the two
## mirrored lockstep sims would disagree on the numbers if either side's badges applied.
func _badge_boost(v: int, key: String) -> int:
	if link_battle:
		return v
	if main and str(_BADGE_STAT.get(key, "")) in main.badges:
		return mini(999, v + (v >> 3))
	return v


## LoadBattleMonFromParty / GainExperience's stat rebuild: every stat from the party mon's
## unmodified value × the current stage ratio, then the burn/paralysis penalties, then the
## player's badge boosts — in that order, all destructive on the stored copy.
func _rebuild_mod_stats(is_player: bool) -> void:
	var mon: Dictionary = player_mon if is_player else enemy_mon
	var st: Dictionary = p_stages if is_player else e_stages
	var mod: Dictionary = p_mod if is_player else e_mod
	for k in ["atk", "def", "spd", "spc"]:
		mod[k] = _stage_apply(int(mon[k]), int(st[k]))
	if str(mon["status"]) == "par":
		mod["spd"] = maxi(1, int(mod["spd"] / 4))      # QuarterSpeedDueToParalysis
	if str(mon["status"]) == "brn":
		mod["atk"] = maxi(1, int(mod["atk"] / 2))      # HalveAttackDueToBurn
	if is_player:
		for k in ["atk", "def", "spd", "spc"]:
			mod[k] = _badge_boost(int(mod[k]), k)      # ApplyBadgeStatBoosts


## Per-side volatile battle state (reset each battle and on switch-in). The burn/paralysis
## stat penalties live in the STORED battle stats (p_mod/e_mod), not here.
func _new_vol() -> Dictionary:
	return {"confuse": 0, "flinch": false, "recharge": false, "charging": "",
		"leech": false, "toxic": 0, "thrash": 0, "thrash_move": "", "raging": false,
		"bind": 0, "bind_move": "", "bound": 0,
		"light_screen": false, "reflect": false, "focus": false, "mist": false,
		"disabled": "", "bide": 0, "bide_turns": 0, "sub": 0, "sub_up": false,
		"sub_broke": false, "last_move": ""}


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
	for i in party.size():
		if int(party[i]["hp"]) > 0:
			return i
	return 0


func _has_other_usable() -> bool:
	for i in party.size():
		if i != active and int(party[i]["hp"]) > 0:
			return true
	return false


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
		elif main == null or main.link.state != "linked":
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


## TryRunningFromBattle: ghosts and safari mons never hold you; otherwise escape is free when
## you're at least as fast, else odds are playerSpeed*32 / ((enemySpeed/4) % 256) + 30 per
## prior attempt against a byte roll — and failing costs the turn (the wild mon attacks).
func _try_run() -> void:
	_det_paction = "r"
	run_attempts += 1
	if not (ghost or is_safari or demo):
		var ps := _eff_speed(true)
		var es := _eff_speed(false)
		if ps < es:
			var b := (es >> 2) % 256
			if b > 0:
				var q := (ps * 32) / b + 30 * (run_attempts - 1)
				if q <= 255 and _ri(256) >= q:
					_enemy_turn_after_item(["Can't escape!"])
					return
	_say([{"sfx": "run"}, "Got away\nsafely!"], "run")


func _choose_action() -> void:
	match menu_items[cursor]:
		"FIGHT":
			state = "moves"; cursor = 0; _move_swap = -1; queue_redraw()
		"PKMN":
			state = "party"; cursor = active; queue_redraw()
		"ITEM":
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


## Undo the Transform/Mimic battle-only overlay before `mon` leaves the field (gh #62).
## pokered keeps these in wBattleMon* and never writes the party struct; switching out or
## ending the battle reloads the real data.
func _revert_battle_copy(mon: Dictionary, vol: Dictionary) -> void:
	if vol.has("transform_backup"):
		var bk: Dictionary = vol["transform_backup"]
		# transformed PP is fully separate (DecrementPP returns when TRANSFORMED): no copy-back
		mon["moves"] = vol["mimic_backup"] if vol.has("mimic_backup") else bk["moves"]
		mon["types"] = bk["types"]
		main.recompute_stats(mon)          # party-truth stats (also right after a level-up)
		vol.erase("transform_backup")
		vol.erase("mimic_backup")
	elif vol.has("mimic_backup"):
		var real: Array = vol["mimic_backup"]
		var cur: Array = mon["moves"]
		for i in mini(real.size(), cur.size()):
			real[i]["pp"] = cur[i]["pp"]   # PP drains hit the party slot too (DecrementPP quirk)
		mon["moves"] = real
		vol.erase("mimic_backup")


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
		# v1.1 divergence, documented: the cartridge allows items in link battles; the
		# lockstep port refuses them for now (the enemy-side application of every bag item
		# is a later faithfulness pass). Both sims refuse identically — no desync surface.
		_say(["Items can't be\nused in a link\nbattle!"], "menu")
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


## The wild mon's turn: show eating/angry (decrementing the factor), then roll to flee.
func _safari_turn(msgs: Array) -> void:
	if safari_bait > 0:
		safari_bait -= 1
		msgs.append("%s is eating!" % enemy_mon["name"])
	elif safari_escape > 0:
		safari_escape -= 1
		if safari_escape == 0:                       # anger faded -> catch rate back to normal
			safari_catch = int(base_stats[enemy_mon["species"]]["catch"])
		msgs.append("%s is angry!" % enemy_mon["name"])
	var spd := int(enemy_mon["spd"]) % 256
	var b := spd * 2                                  # flee chance /256 (safari_zone.asm)
	var ran: bool = spd > 127
	if not ran:
		if safari_bait > 0:
			b = b >> 2                                # eating -> a quarter as likely to flee
		elif safari_escape > 0:
			b = min(255, b << 1)                      # angry -> twice as likely to flee
		ran = _ri(256) < b
	if ran:
		msgs.append("%s fled!" % enemy_mon["name"])
		_say(msgs, "run")
	else:
		_say(msgs, "menu")
	turn_no += 1
	_det_event("T%d" % turn_no, "p[%s]e[safari]" % _det_paction)
	_det_paction = "-"


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


## ItemUseBall's capture + wobble algorithm, Gen-1 exact: the ball kind sets rand1's span
## and the HP factor's divisor; sleep/freeze shave 25 off the roll and other ailments 12
## (underflow = certain catch); a failure wobbles 0-3 times by Z = X*Y/255 + status2.
## X = min(W, 255) is computed BEFORE the catch-rate comparison, so hQuotient+3 still holds
## it at .failedToCapture whichever stage failed — a rand1-stage failure uses the same
## HP-derived X as a rand2-stage one, never the catch rate (gh #176).
func _attempt_catch(ball := "POKé BALL", rate_override := -1) -> Dictionary:
	if ball == "MASTER BALL":
		return {"caught": true, "shakes": 3}
	var span := 256
	var bf := 12
	var bf2 := 255
	if ball == "GREAT BALL":
		span = 201; bf = 8; bf2 = 200
	elif ball in ["ULTRA BALL", "SAFARI BALL"]:
		span = 151; bf2 = 150
	var st := str(enemy_mon["status"])
	var r1 := _ri(span)
	r1 -= 25 if st in ["slp", "frz"] else (12 if st != "" else 0)
	if r1 < 0:
		return {"caught": true, "shakes": 3}
	var rate := rate_override if rate_override >= 0 \
		else int(base_stats[enemy_mon["species"]]["catch"])
	var x := int(int(enemy_mon["maxhp"]) * 255 / bf) / maxi(1, int(int(enemy_mon["hp"]) / 4))
	if r1 <= rate:
		if x > 255 or _ri(256) <= x:
			return {"caught": true, "shakes": 3}
	var y := rate * 100 / bf2
	if y > 255:
		return {"caught": false, "shakes": 3}
	var z := mini(x, 255) * y / 255 + (10 if st in ["slp", "frz"] else (5 if st != "" else 0))
	return {"caught": false, "shakes": 0 if z < 10 else (1 if z < 30 else (2 if z < 70 else 3))}


func _enemy_turn_after_item(msgs: Array) -> void:
	# The item was the player's action; the enemy still moves — and speed order still decides
	# whether the player's own residual ticks before or after the enemy's move (the item turn
	# runs the same MainInBattleLoop with ExecutePlayerMove a no-op).
	var emove := _enemy_choose()
	_det_eaction = "m:" + emove
	var pf: bool = _eff_speed(true) > _eff_speed(false) \
		or (_eff_speed(true) == _eff_speed(false) and _rf() < 0.5)
	if pf:
		if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
			_residual(player_mon, p_vol, enemy_mon, msgs)
		if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
			_enemy_act(emove, msgs)
			if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
				_residual(enemy_mon, e_vol, player_mon, msgs)
	else:
		if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
			_enemy_act(emove, msgs)
			if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
				_residual(enemy_mon, e_vol, player_mon, msgs)
		if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
			_residual(player_mon, p_vol, enemy_mon, msgs)
	_end_of_turn(msgs)


# ---- link lockstep (gh #7) -------------------------------------------------

## Where a chosen action enters the engine. Non-link: resolve immediately (the AI supplies
## the enemy's move). Link: send ours, hold in "linkwait" until the peer's arrives, then
## both sims resolve the same pair.
func _submit_action(action: Dictionary) -> void:
	if not link_battle:
		_resolve(action)
		return
	_link_pact = action
	main.link.send_message({"t": "col_act", "action": _det_action(action)})
	main._maybe_kill("act%d" % (turn_no + 1))    # gh #9: cable pull after our turn-N action
	_link_wait = "act"
	_link_elapsed = 0.0
	msg = "Waiting..."
	revealed = 999
	state = "linkwait"                 # ignores input; _process watches the queues
	queue_redraw()


## The peer's canonical action string back into an enemy action. The forced tag matters:
## a forced continuation (bind/thrash/charge/RAGE/Bide) spends no PP on the sender's sim,
## so it must spend none here either — and the stream label must match byte for byte.
func _parse_peer_action(s: String) -> Dictionary:
	if s.begins_with("w:"):
		return {"kind": "eswitch", "idx": int(s.substr(2))}
	if s.begins_with("f:"):
		return {"kind": "emove", "move": s.substr(2), "forced": true}
	if s.begins_with("m:"):
		return {"kind": "emove", "move": s.substr(2), "forced": false}
	return {"kind": "emove", "move": "STRUGGLE", "forced": false}


## Both actions in hand: switches first (independent), then the moves in canonical speed
## order — a tie draws the shared coin as "heads = the HOST acts first", so the mirrored
## sims order it identically (pokered's link battles resolve ties off the shared random
## list the same way).
func _resolve_link(pact: Dictionary, eact: Dictionary) -> void:
	_det_paction = _det_action(pact) if str(pact.get("kind", "")) != "" else "-"
	_det_eaction = ("w:%d" % int(eact["idx"])) if str(eact["kind"]) == "eswitch" \
		else ("f:" if bool(eact.get("forced", false)) else "m:") + str(eact["move"])
	var msgs: Array = []
	if str(pact["kind"]) == "switch":
		_player_act(pact, msgs)
	if str(eact["kind"]) == "eswitch":
		_link_enemy_switch(int(eact["idx"]), msgs)
	var p_moves: bool = str(pact["kind"]) in ["move", "forced"]
	var e_moves: bool = str(eact["kind"]) == "emove"
	if p_moves or e_moves:
		var pf := true
		if p_moves and e_moves:
			var ps := _eff_speed(true)
			var es := _eff_speed(false)
			if ps == es:
				var host_first := _rf() < 0.5
				pf = host_first if link_host else not host_first
			else:
				pf = ps > es
		elif e_moves:
			pf = false
		var emove := str(eact.get("move", ""))
		var eforced := bool(eact.get("forced", false))
		if pf:
			if p_moves:
				_player_act(pact, msgs)
				if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
					_residual(player_mon, p_vol, enemy_mon, msgs)
			if e_moves and enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
				_link_enemy_act(emove, msgs, eforced)
				if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
					_residual(enemy_mon, e_vol, player_mon, msgs)
		else:
			if e_moves:
				_link_enemy_act(emove, msgs, eforced)
				if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
					_residual(enemy_mon, e_vol, player_mon, msgs)
			if p_moves and enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
				_player_act(pact, msgs)
				if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
					_residual(player_mon, p_vol, enemy_mon, msgs)
	p_vol["flinch"] = false
	e_vol["flinch"] = false
	_end_of_turn(msgs)


## The peer's move, no AI anywhere near it (the item/switch handler is theirs to choose).
## A forced continuation spends no PP, exactly like the local forced branch.
func _link_enemy_act(move: String, msgs: Array, forced := false) -> void:
	if not forced and str(e_vol["charging"]) == "" and not _is_two_turn(move):
		for mv in enemy_mon["moves"]:
			if str(mv["move"]) == move:
				mv["pp"] = max(0, int(mv["pp"]) - 1)
				break
	_do_move(enemy_mon, player_mon, move, msgs, e_stages, p_stages, false)


## The peer switched: their pick lands on our enemy side, applied SYNCHRONOUSLY (their sim
## applied their own switch synchronously, and the turn digest compares end states) with
## the revert their sim ran on switch-out; the markers replay it for presentation.
func _link_enemy_switch(idx: int, msgs: Array) -> void:
	if idx < 0 or idx >= enemy_party.size() or int(enemy_party[idx]["hp"]) <= 0:
		return
	msgs.append("%s withdrew\n%s!" % [peer_name, enemy_mon["name"]])
	msgs.append({"hide_pic": "enemy"})
	_revert_battle_copy(enemy_mon, e_vol)
	_set_enemy(idx)
	msgs.append({"auto": "%s sent\nout %s!" % [peer_name, enemy_party[idx]["name"]]})
	msgs.append({"next_enemy": idx})


func _link_enemy_has_usable() -> bool:
	for i in enemy_party.size():
		if i != enemy_active and int(enemy_party[i]["hp"]) > 0:
			return true
	return false


## The peer's faint replacement arrived: send it out. The swap applies SYNCHRONOUSLY (the
## presentation's next_enemy marker re-applies it, idempotently) so this side's X event
## digests the same post-swap state the replacing side digested — byte-identical streams.
func _link_enemy_swap_in(idx: int) -> void:
	if idx < 0 or idx >= enemy_party.size():
		idx = 0
	_revert_battle_copy(enemy_mon, e_vol)   # the outgoing mon sheds Transform/Mimic, as the
	_set_enemy(idx)                         # peer's own sim reverts it on switch-out
	_det_event("X", "%s:w:%d" % ["j" if link_host else "h", idx])   # mirror of the peer's X
	_say([{"auto": "%s sent\nout %s!" % [peer_name, enemy_party[idx]["name"]]},
		{"next_enemy": idx}], "menu")


## The link died mid-battle: the session simply ends, stakeless (spec story 17).
func _link_dead() -> void:
	link_over = true
	won = false
	blacked_out = false
	_say(["The link has been\nclosed."], "end")


# ---- turn resolution -------------------------------------------------------

func _resolve(action: Dictionary) -> void:
	if ghost and action["kind"] == "move":
		# Unidentified GHOST (PrintGhostText): the player's mon is too scared to attack, and
		# the ghost only wails — nobody deals damage; running is the only way out.
		_say(["%s is too\nscared to move!" % player_mon["name"],
			"GHOST: Get out...\nGet out..."], "menu")
		return
	_det_paction = _det_action(action)
	var msgs: Array = []
	var emove := _enemy_choose()
	_det_eaction = "m:" + emove
	# Each side's own psn/brn/LEECH SEED tick lands right after ITS action, in act order —
	# MainInBattleLoop calls HandlePoisonBurnLeechSeed per side, not at end of turn — and is
	# skipped when that action ended in a faint (a KO'd opponent, or your own recoil/EXPLODE):
	# the asm faint-checks before each residual. A first mover fainted by its own poison also
	# costs the second mover its move (the loop jumps to the faint handler).
	var pf := true                                     # a switch resolves player-first
	if action["kind"] != "switch":
		var ps := _eff_speed(true)
		var es := _eff_speed(false)
		pf = ps > es or (ps == es and _rf() < 0.5)
	if pf:
		_player_act(action, msgs)
		if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
			_residual(player_mon, p_vol, enemy_mon, msgs)
		if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
			_enemy_act(emove, msgs)
			if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
				_residual(enemy_mon, e_vol, player_mon, msgs)
	else:
		_enemy_act(emove, msgs)
		if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
			_residual(enemy_mon, e_vol, player_mon, msgs)
		if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
			_player_act(action, msgs)
			if enemy_mon["hp"] > 0 and player_mon["hp"] > 0:
				_residual(player_mon, p_vol, enemy_mon, msgs)
	p_vol["flinch"] = false
	e_vol["flinch"] = false
	_end_of_turn(msgs)


func _player_act(action: Dictionary, msgs: Array) -> void:
	if action["kind"] == "switch":
		player_mon["label"] = player_mon["name"]
		msgs.append("Come back,\n%s!" % player_mon["name"])
		msgs.append({"recall": true})  # the withdrawn mon's pic vanishes with the text (gh #72)
		_revert_battle_copy(player_mon, p_vol)
		active = action["idx"]
		player_mon = party[active]
		player_mon["label"] = player_mon["name"]
		p_stages = _new_stages()       # stat changes + volatiles reset on switch
		p_vol = _new_vol()
		_rebuild_mod_stats(true)
		_sub_shown["player"] = false
		if not active in participants:
			participants.append(active)
		msgs.append({"auto": "Go! %s!" % player_mon["name"]})
		msgs.append({"send_player": true})   # ball throw + poof + pop-out (same as battle start)
	elif action["kind"] == "forced":
		_do_move(player_mon, enemy_mon, str(action["move"]), msgs, p_stages, e_stages, true)
	else:
		var mv: Dictionary = player_mon["moves"][action["idx"]]
		# gh #168: a two-turn charge move spends no PP on its charge turn — DecrementPP happens when it
		# fires next turn (in _do_move). Turn-2 firing comes through the "forced" branch above (which also
		# spends no PP). Charging turn-2 never reaches here. Every other move spends its PP now.
		if str(p_vol["charging"]) == "" and not _is_two_turn(str(mv["move"])):
			mv["pp"] = max(0, int(mv["pp"]) - 1)
		_do_move(player_mon, enemy_mon, str(mv["move"]), msgs, p_stages, e_stages, true)


func _enemy_choose() -> String:
	var forced := _forced_move(e_vol)
	if forced != "":
		return forced
	var usable: Array = []
	for mv in enemy_mon["moves"]:
		if int(mv["pp"]) > 0 and str(mv["move"]) != str(e_vol["disabled"]):
			usable.append(str(mv["move"]))
	if usable.is_empty():
		return "STRUGGLE"
	# AIEnemyTrainerChooseMoves: every move starts at priority 10, the class's modification
	# layers adjust, and the pick is uniform among the minimum-priority moves.
	if is_trainer and not ai_mods.is_empty():
		var pri := {}
		for m in usable:
			pri[m] = 10
		if 1 in ai_mods and str(player_mon["status"]) != "":
			for m in usable:               # Mod1: don't re-status an already-statused player
				var md: Dictionary = moves_db.get(m, {})
				if int(md.get("power", 0)) == 0 and str(md.get("effect", "")) in \
						["SLEEP_EFFECT", "POISON_EFFECT", "PARALYZE_EFFECT"]:
					pri[m] += 5
		if 2 in ai_mods and _ai_turn == 1:
			for m in usable:               # Mod2: favour set-up moves on the second turn
				if str(moves_db.get(m, {}).get("effect", "")) in MOD2_EFFECTS:
					pri[m] -= 1
		if 3 in ai_mods:
			for m in usable:               # Mod3: play the type matchup vs the player's mon
				var eff := _ai_eff(m)
				if eff > 1.0:
					pri[m] -= 1
				elif eff < 1.0 and _ai_better_move(usable, m):
					pri[m] += 1
		var best := 999
		for m in usable:
			best = mini(best, int(pri[m]))
		var picks: Array = []
		for m in usable:
			if int(pri[m]) == best:
				picks.append(m)
		usable = picks
	return str(usable[_ri(usable.size())])


## AIGetTypeEffectiveness: the FIRST TypeEffects entry matching the move's type against either
## of the player's types wins — the AI never composes the table like the damage engine does.
## A dual-type pairing reads as whichever entry comes first in table order (ELECTRIC into
## WATER/FLYING reads 2x, not the real 4x), and no match reads neutral.
func _ai_eff(move: String) -> float:
	var row: Dictionary = type_chart.get(str(moves_db.get(move, {}).get("type", "")), {})
	for dt in row:
		if str(player_mon["types"][0]) == dt or str(player_mon["types"][1]) == dt:
			return float(row[dt])
	return 1.0


## Mod3's "better move" scan: Super Fang / fixed damage / Fly, or any damaging move of a
## different type, makes a not-very-effective move worth discouraging.
func _ai_better_move(usable: Array, than: String) -> bool:
	var tt := str(moves_db.get(than, {}).get("type", ""))
	for m in usable:
		if m == than:
			continue
		var md: Dictionary = moves_db.get(m, {})
		var eff := str(md.get("effect", ""))
		if eff in ["SUPER_FANG_EFFECT", "SPECIAL_DAMAGE_EFFECT", "FLY_EFFECT"]:
			return true
		if str(md.get("type", "")) != tt and int(md.get("power", 0)) > 0:
			return true
	return false


# ---- Gen-1 trainer item/switch AI (engine/battle/trainer_ai.asm, handler for handler) ----

## The class handler rolls its chance and may spend the enemy's turn on an item or switch.
## Thresholds are the asm's raw random-byte compares: "25 percent + 1" = r < 65,
## "50 percent + 1" = r < 129, "13 percent - 1" = r < 32, Agatha's "8 percent" = r < 20.
func _ai_item_turn(msgs: Array) -> bool:
	if _ai_uses <= 0:
		return false
	var r := _ri(256)
	match ai_kind:
		"Juggler":
			if r < 65: return _ai_switch(msgs)
		"Blackbelt":
			if r < 32: return _ai_x_item("atk", "X ATTACK", msgs)
		"Giovanni":
			if r < 65: return _ai_guard_spec(msgs)
		"CooltrainerM":
			if r < 65: return _ai_x_item("atk", "X ATTACK", msgs)
		"CooltrainerF":
			# the asm's 25% gate falls through (its ret nc is missing) — kept verbatim
			if _hp_below(10): return _ai_heal(200, "HYPER POTION", msgs)
			if _hp_below(5): return _ai_switch(msgs)
		"Brock":
			if str(enemy_mon["status"]) != "": return _ai_full_heal(msgs)
		"Misty":
			if r < 65: return _ai_x_item("def", "X DEFEND", msgs)
		"LtSurge":
			if r < 65: return _ai_x_item("spd", "X SPEED", msgs)
		"Erika":
			if r < 129 and _hp_below(10): return _ai_heal(50, "SUPER POTION", msgs)
		"Koga":
			if r < 65: return _ai_x_item("atk", "X ATTACK", msgs)
		"Blaine":
			# no HP check, faithfully: Blaine potions at ANY hp — full included (heals 0,
			# still spends the use and his move; AIRecoverHP has no full-HP guard)
			if r < 65: return _ai_heal(50, "SUPER POTION", msgs)
		"Sabrina":
			if r < 65 and _hp_below(10): return _ai_heal(200, "HYPER POTION", msgs)
		"Rival2":
			if r < 32 and _hp_below(5): return _ai_heal(20, "POTION", msgs)
		"Rival3":
			if r < 32 and _hp_below(5): return _ai_heal(-1, "FULL RESTORE", msgs)
		"Lorelei":
			if r < 129 and _hp_below(5): return _ai_heal(50, "SUPER POTION", msgs)
		"Bruno":
			if r < 65: return _ai_x_item("def", "X DEFEND", msgs)
		"Agatha":
			if r < 20: return _ai_switch(msgs)
			if r < 129 and _hp_below(4): return _ai_heal(50, "SUPER POTION", msgs)
		"Lance":
			if r < 129 and _hp_below(5): return _ai_heal(200, "HYPER POTION", msgs)
	return false


func _hp_below(frac: int) -> bool:                 # AICheckIfHPBelowFraction: hp < maxhp/frac
	return int(enemy_mon["hp"]) < int(enemy_mon["maxhp"]) / frac


## AIRecoverHP / AIUseFullRestore: no full-HP guard — the use (and the enemy's move) is spent
## even when the heal lands 0 (Blaine really does waste SUPER POTIONs at full HP).
func _ai_heal(amount: int, item: String, msgs: Array) -> bool:
	_ai_uses -= 1
	if amount < 0:                                 # FULL RESTORE: full HP + status cure
		enemy_mon["hp"] = int(enemy_mon["maxhp"])
		enemy_mon["status"] = ""
		enemy_mon["sleep"] = 0
	else:
		enemy_mon["hp"] = mini(int(enemy_mon["maxhp"]), int(enemy_mon["hp"]) + amount)
	msgs.append("%s used\n%s!" % [trainer_name, item])
	if amount < 0:
		_show_status(enemy_mon, msgs)
	msgs.append({"hp": "enemy", "to": int(enemy_mon["hp"])})
	return true


func _ai_full_heal(msgs: Array) -> bool:
	if str(enemy_mon["status"]) == "":
		return false
	_ai_uses -= 1
	enemy_mon["status"] = ""
	enemy_mon["sleep"] = 0
	msgs.append("%s used\nFULL HEAL!" % trainer_name)
	msgs.append("%s became\nhealthy!" % enemy_mon["name"])
	_show_status(enemy_mon, msgs)
	return true


## AIIncreaseStat: the use (and the turn) is spent even at +6, where StatModifierUpEffect
## just reports failure. A successful boost runs the full recalc + trailer — including the
## trailer's re-penalizing of the PLAYER's par/brn stats (the compounding glitch).
func _ai_x_item(stat: String, item: String, msgs: Array) -> bool:
	_ai_uses -= 1
	msgs.append("%s used\n%s!" % [trainer_name, item])
	if int(e_stages[stat]) >= 6:
		msgs.append("Nothing happened!")
		return true
	var label: String = {"atk": "ATTACK", "def": "DEFENSE", "spd": "SPEED", "spc": "SPECIAL"}[stat]
	_change_stage(enemy_mon, e_stages, label, 1, msgs)
	return true


func _ai_guard_spec(msgs: Array) -> bool:
	# AIUseGuardSpec sets the bit unconditionally — an already-misted mon still costs the use.
	_ai_uses -= 1
	e_vol["mist"] = true
	msgs.append("%s used\nGUARD SPEC.!" % trainer_name)
	msgs.append("%s's shrouded\nin mist!" % enemy_mon["name"])
	return true


func _ai_switch(msgs: Array) -> bool:              # AISwitchIfEnoughMons
	var next := -1
	for i in enemy_party.size():
		if i != enemy_active and int(enemy_party[i]["hp"]) > 0:
			next = i
			break
	if next < 0:
		return false
	# No _ai_uses spend: SwitchEnemyMon never calls DecrementAICount — switching is free,
	# only the item routines consume the class's wAICount budget.
	msgs.append("%s withdrew\n%s!" % [trainer_name, enemy_mon["name"]])
	msgs.append({"hide_pic": "enemy"})
	msgs.append({"auto": "%s sent\nout %s!" % [trainer_name, enemy_party[next]["name"]]})
	msgs.append({"next_enemy": next})
	return true


## A move the side is locked into this turn (charging/recharge/bind/thrash/bide), or "".
func _forced_move(vol: Dictionary) -> String:
	if bool(vol["recharge"]):
		return "RECHARGE"
	if str(vol["charging"]) != "":
		return str(vol["charging"])
	if int(vol["bind"]) > 0:
		return str(vol["bind_move"])
	if int(vol["thrash"]) > 0:
		return str(vol["thrash_move"])
	if bool(vol["raging"]):
		return "RAGE"                              # Gen-1 Rage never lets go (USING_RAGE)
	if int(vol["bide_turns"]) > 0:
		return "BIDE"
	return ""


## A two-turn charge move (FLY/DIG/SOLARBEAM/Sky Attack/…) — matches _do_move's charge gate (gh #168).
func _is_two_turn(move: String) -> bool:
	return move in TWO_TURN or str(moves_db.get(move, {}).get("effect", "")) in TWO_TURN


## DecrementPP: spend one PP of `move` in `mon`'s moveset. No-op if the mon doesn't own the move
## (e.g. a charge move summoned by METRONOME), as pokered's DecrementPP keys off the selected slot.
func _spend_pp(mon: Dictionary, move: String) -> void:
	for mv in mon["moves"]:
		if str(mv["move"]) == move:
			mv["pp"] = max(0, int(mv["pp"]) - 1)
			return


func _enemy_act(move: String, msgs: Array) -> void:
	# TrainerAI: the class handler may spend this turn on an item or a switch instead. It is
	# rolled unconditionally before the move — the asm call site has no lock gate, so even a
	# wrapping, thrashing, or mid-FLY trainer mon can potion, its multi-turn state left to
	# resume on the next turn (the skipped move doesn't tick any of its counters).
	if is_trainer and _ai_item_turn(msgs):
		_ai_turn += 1
		return
	_ai_turn += 1                                  # wAILayer2Encouragement
	if str(e_vol["charging"]) == "" and not _is_two_turn(move):   # gh #168: charge PP is spent on turn 2 (in _do_move)
		for mv in enemy_mon["moves"]:
			if str(mv["move"]) == move:
				mv["pp"] = max(0, int(mv["pp"]) - 1)
				break
	_do_move(enemy_mon, player_mon, move, msgs, e_stages, p_stages, false)


func _end_of_turn(msgs: Array) -> void:
	var nxt := "menu"
	if _flee_pending:
		_flee_pending = false
		_say(msgs, "run")
		return
	# gh #112: BOTH faints must be handled on a double KO (recoil / EXPLODE / end-of-turn poison can drop
	# both mons the same turn). The old `if enemy… elif player…` fainted only the enemy and left the
	# player's 0-HP mon active — it could still pick a move the next turn. pokered's HandleEnemyMonFainted
	# also removes a co-fainted player mon (RemoveFaintedPlayerMon) and, if that empties the party, blacks
	# the player out even though the enemy was KO'd (AnyPartyAlive → HandlePlayerBlackOut).
	var player_dead: bool = int(player_mon["hp"]) <= 0
	if int(enemy_mon["hp"]) <= 0:
		msgs.append({"faint": "enemy"})
		msgs.append("%s\nfainted!" % enemy_mon["label"])
		_award_exp(msgs)
		if link_battle and _link_enemy_has_usable():
			# The next enemy is the PEER's pick, arriving as col_swap — _resolve_after's
			# "menu" gate holds in linkwait until it does. No SHIFT prompt in link (asm).
			nxt = "menu"
		elif is_trainer and not link_battle and enemy_active < enemy_party.size() - 1:
			# SHIFT battle style (the default): the trainer announces the next mon and offers a
			# free switch first (EnemySendOutFirstMon's TrainerAboutToUseText + party menu).
			# Tests (fast_hp) run as SET — the prompt needs interactive input.
			if main and main.options["battle_shift"] and not fast_hp and not player_dead and _has_other_usable():
				msgs.append("%s is about to use\n%s!" % [trainer_name, enemy_party[enemy_active + 1]["name"]])
				msgs.append({"shift": true})
			# The swap is deferred to a queue marker: calling _set_enemy here (at queue-build
			# time) would put the next mon's pic/HUD on screen and play its cry while the
			# fainted mon's slide and messages are still presenting. As in EnemySendOut, the
			# "sent out" text flows straight into the new mon growing in + its cry.
			msgs.append({"auto": "%s sent\nout %s!" % [trainer_name, enemy_party[enemy_active + 1]["name"]]})
			msgs.append({"next_enemy": enemy_active + 1})
			nxt = "menu"
		else:
			# The enemy's last mon fell. But a mutual KO that also empties the player's party is a
			# blackout, not a win (pokered checks AnyPartyAlive before TrainerBattleVictory) — so withhold
			# the victory text/prize/`won` when the player is about to black out below.
			var player_blackout: bool = player_dead and not _has_other_usable()
			if is_trainer and not player_blackout:
				if trainer_pic_tex:
					msgs.append({"trainer_slide": "in"})
				msgs.append("%s was\ndefeated!" % trainer_name)
				if prize > 0:
					main.player_money += prize
					msgs.append("%s got ¥%d\nfor winning!" % [main.player_name, prize])
			if not player_blackout:
				won = true
			nxt = "end"
	if player_dead:
		msgs.append({"faint": "player"})
		msgs.append("%s\nfainted!" % player_mon["label"])
		if _has_other_usable():
			# A fainted mon must send out a replacement — unless the enemy's last mon fainted this same
			# turn (won == true), where the win stands and the battle ends with a fainted lead.
			if not won:
				nxt = "party_forced"
		else:
			msgs.append("%s is out of\nuseable POKéMON!" % main.player_name)
			msgs.append("%s whited out!" % main.player_name)
			blacked_out = true            # Main warps to the last Center on battle finish
			won = false                   # a mutual KO that empties your party is a blackout, not a win
			nxt = "end"
	_say(msgs, nxt)
	# Determinism oracle (gh #2): every turn kind funnels through here — emit its event.
	# Link (gh #7): host/join labels, host first, so both peers' lines are byte-identical.
	turn_no += 1
	if link_battle:
		_det_event("T%d" % turn_no, "h[%s]j[%s]" % [
			_det_paction if link_host else _det_eaction,
			_det_eaction if link_host else _det_paction])
	else:
		_det_event("T%d" % turn_no, "p[%s]e[%s]" % [_det_paction, _det_eaction])
	_det_paction = "-"
	_det_eaction = "-"


## GainExperience (engine/battle/experience.asm), driven by HandleExpGain (core.asm). Each
## LIVING participant gains exp = ((base_exp / N) * level / 7), floored at every step, then the
## ×1.5 BoostExp for a traded mon (foreign OT) and again for a trainer battle — both can stack.
## Stat exp accumulates the enemy's raw base stats / N (capped 65535). With EXP.ALL held, the
## base exp AND base stats are halved up front (core.asm .halveExpDataLoop), then a second pass
## splits that halved pool across the WHOLE party — fighters or not — divided by the party count.
## (A fainted participant loses its gain-exp flag in RemoveFaintedPlayerMon, so N is the living
## count both here and in DivideExpDataByNumMonsGainingExp.)
func _award_exp(msgs: Array) -> void:
	if link_battle:
		return                       # link battles award nothing — stakeless (gh #7)
	var alive: Array = []
	for idx in participants:
		if idx < party.size() and int(party[idx]["hp"]) > 0:
			alive.append(idx)
	if alive.is_empty():
		return
	var exp_all: bool = main.player_bag.has("EXP.ALL")
	var be := int(enemy_mon["base_exp"])
	if exp_all:
		be = be >> 1                          # EXP.ALL halves base exp (and base stats) first
	_award_exp_pass(alive, alive.size(), be, exp_all, msgs)
	if exp_all:
		var whole: Array = []
		for idx in party.size():
			if int(party[idx]["hp"]) > 0:
				whole.append(idx)
		msgs.append("with EXP.ALL,")
		_award_exp_pass(whole, party.size(), be, exp_all, msgs)


## One GainExperience pass: the (already-halved for EXP.ALL) base exp / base stats are divided
## among `n` mons (DivideExpDataByNumMonsGainingExp) and handed to each recipient with its boosts.
func _award_exp_pass(recipients: Array, n: int, base_exp: int, halve_stats: bool, msgs: Array) -> void:
	var per := int(base_exp / n) * int(enemy_mon["level"]) / 7      # floor((be/N) * L / 7)
	for idx in recipients:
		var mon: Dictionary = party[idx]
		var e := per
		if str(mon.get("ot", main.player_name)) != main.player_name:
			e = _boost_exp(e)                 # traded mon: ×1.5 (BoostExp)
		if is_trainer:
			e = _boost_exp(e)                 # trainer battle: ×1.5 (BoostExp)
		var cap: int = main.exp_for_level(100, str(mon["growth"]))
		mon["exp"] = mini(cap, int(mon["exp"]) + e)   # capped at the level-100 exp (GainExperience)
		_gain_stat_exp(mon, n, halve_stats)
		msgs.append("%s gained\n%d EXP. Points!" % [mon["name"], e])
		_level_up_loop(mon, msgs, idx == active)


## BoostExp: exp × 1.5 = q + floor(q/2) (the asm's 16-bit srl/rr then add).
func _boost_exp(q: int) -> int:
	return q + int(q / 2)


## GainExperience's stat-exp loop: the defeated mon's raw base stats (halved for EXP.ALL, then
## divided by the N mons gaining exp) accumulate into each mon's pool, capped 65535; the stats
## pick the pool up at the next recalc (level-up) via CalcStat's sqrt term.
func _gain_stat_exp(mon: Dictionary, n := 1, halve := false) -> void:
	var eb: Dictionary = enemy_mon["base"]
	var se: Dictionary = mon.get("sexp", {"hp": 0, "atk": 0, "def": 0, "spd": 0, "spc": 0})
	for k in ["hp", "atk", "def", "spd", "spc"]:
		var gain := int(eb[k]) >> 1 if halve else int(eb[k])   # EXP.ALL halves the base stats too
		gain = int(gain / n)                                   # then / the mons gaining exp
		se[k] = mini(65535, int(se.get(k, 0)) + gain)
	mon["sexp"] = se


func _level_up_loop(mon: Dictionary, msgs: Array, allow_prompt: bool) -> void:
	var species: String = mon["species"]
	while int(mon["level"]) < 100 \
			and int(mon["exp"]) >= main.exp_for_level(int(mon["level"]) + 1, str(mon["growth"])):
		var oldmax := int(mon["maxhp"])
		mon["level"] = int(mon["level"]) + 1
		main.recompute_stats(mon)
		mon["hp"] = int(mon["hp"]) + (int(mon["maxhp"]) - oldmax)
		msgs.append({"sfx": "level_up"})
		msgs.append("%s grew to\nlevel %d!" % [mon["name"], mon["level"]])
		if allow_prompt:                              # the active mon shows its new stats box (PrintStatsBox)
			# A mid-battle level-up rebuilds the battle stats from the new party stats with
			# penalties and badges fresh (GainExperience: CalculateModifiedStats ->
			# ApplyBurnAndParalysisPenaltiesToPlayer -> ApplyBadgeStatBoosts).
			_rebuild_mod_stats(true)
			msgs.append({"levelstats": {"atk": int(mon["atk"]), "def": int(mon["def"]),
				"spd": int(mon["spd"]), "spc": int(mon["spc"])}})
		for lm in base_stats[species]["level_moves"]:
			if int(lm[0]) == int(mon["level"]):
				_learn(mon, str(lm[1]), msgs, allow_prompt)
		# Evolution waits for the battle to end (wCanEvolveFlags -> Evolution_PartyMonLoop);
		# Main runs the full sequence for each flagged mon after `finished` (gh #67).
		var pi := party.find(mon)
		if pi >= 0 and not can_evolve.has(pi):
			can_evolve.append(pi)


func _learn(mon: Dictionary, move: String, msgs: Array, allow_prompt: bool) -> void:
	for mv in mon["moves"]:
		if str(mv["move"]) == move:
			return
	var pp := int(moves_db[move]["pp"])
	if mon["moves"].size() < 4:
		mon["moves"].append({"move": move, "pp": pp, "maxpp": pp})
		msgs.append("%s learned\n%s!" % [mon["name"], str(moves_db[move]["name"])])
	elif allow_prompt:
		# Interactive prompt (active mon only): a {"learn": ...} marker pauses the queue for the
		# move-forget screen (learn_move.asm TryingToLearnText -> WhichMoveToForgetText).
		msgs.append("%s is trying to\nlearn %s!" % [mon["name"], str(moves_db[move]["name"])])
		msgs.append("But, %s can't learn\nmore than 4 moves!" % mon["name"])
		msgs.append({"learn": move})
	else:
		# A benched participant levels up: no prompt, but LearnMove still never deletes an HM (gh #93),
		# so give up the first slot that isn't one. Four HMs means there is nothing to give up.
		var slot := -1
		for i in (mon["moves"] as Array).size():
			if not str(mon["moves"][i]["move"]) in main.HM_MOVES.values():
				slot = i
				break
		if slot < 0:
			return
		var forgot: String = str(moves_db[str(mon["moves"][slot]["move"])]["name"])
		mon["moves"][slot] = {"move": move, "pp": pp, "maxpp": pp}
		msgs.append("%s forgot %s\nand learned %s!" % [mon["name"], forgot, str(moves_db[move]["name"])])


# ---- damage ----------------------------------------------------------------

func _do_move(att: Dictionary, defn: Dictionary, move: String, msgs: Array,
		att_st: Dictionary, def_st: Dictionary, att_is_player: bool) -> void:
	var att_vol: Dictionary = p_vol if att_is_player else e_vol
	var def_vol: Dictionary = e_vol if att_is_player else p_vol
	def_vol["sub_broke"] = false       # per-move: set when this hit pops the SUBSTITUTE

	# Forced / special pseudo-moves.
	if move == "RECHARGE":
		att_vol["recharge"] = false
		msgs.append("%s must\nrecharge!" % att["label"])
		return
	if move == "BIDE":
		_do_bide(att, defn, msgs, att_vol)
		return

	if not _can_act(att, att_vol, def_vol, msgs):
		return

	var md: Dictionary = moves_db[move] if move != "STRUGGLE" else \
		{"name": "STRUGGLE", "effect": "RECOIL_EFFECT", "power": 50, "type": "NORMAL", "accuracy": 100, "pp": 1}
	att_vol["last_move"] = move
	var eff_name := str(md["effect"])

	# Two-turn charge moves: first turn charges, second fires (no PP/charge again).
	if (eff_name in TWO_TURN or move in TWO_TURN) and str(att_vol["charging"]) == "":
		att_vol["charging"] = move
		msgs.append("%s used\n%s!" % [att["label"], str(md["name"])])
		msgs.append(_charge_line(move))
		if move in _VANISH_CHARGE:                      # DIG burrows under / FLY rises out of sight (gh #122)
			msgs.append({"hide_pic": "player" if att_is_player else "enemy"})
		return
	if str(att_vol["charging"]) != "":                  # turn 2: the charge fires (we're past _can_act)
		if str(att_vol["charging"]) in _VANISH_CHARGE:  # DIG/FLY reappear as they strike
			msgs.append({"show_pic": "player" if att_is_player else "enemy"})
		# gh #168: PP is decremented on the EXECUTION turn, not the charge turn — pokered's DecrementPP runs
		# only after CheckStatusConditions passes (PlayerCanExecuteChargingMove → …Move). A charge disrupted
		# mid-air by full paralysis / confusion self-hit returns from _can_act above and wastes no PP.
		_spend_pp(att, move)
	att_vol["charging"] = ""

	# "Use another move" scripts.
	if eff_name == "METRONOME_EFFECT":
		msgs.append("%s used\nMETRONOME!" % att["label"])
		_do_move(att, defn, _metronome_pick(), msgs, att_st, def_st, att_is_player)
		return
	if eff_name == "MIRROR_MOVE_EFFECT":
		msgs.append("%s used\nMIRROR MOVE!" % att["label"])
		var last := str(def_vol["last_move"])
		if last == "" or last == "MIRROR_MOVE":
			msgs.append("But it failed!")
		else:
			_do_move(att, defn, last, msgs, att_st, def_st, att_is_player)
		return

	msgs.append("%s used\n%s!" % [att["label"], str(md["name"])])
	# The move's animation (with its sounds) is queued by the damage/status paths below,
	# after accuracy — a missed move plays neither animation nor sound, as in Gen 1.
	# Semi-invulnerable target: a damaging move can only hit a mon mid-FLY/DIG via SWIFT
	# (gh #160, pokered MoveHitTest INVULNERABLE bit). Bide's release bypasses this path.
	if int(md["power"]) > 0 and str(def_vol["charging"]) in _VANISH_CHARGE \
			and eff_name != "SWIFT_EFFECT":
		msgs.append("%s's\nattack missed!" % att["label"])
		_on_miss(att, md, msgs)
		return

	# Accuracy (MoveHitTest, Swift never misses): byte math — 100% accuracy is 255, rolled
	# against rand(256), so even a sure move misses 1/256 of the time (the famous Gen-1
	# quirk). Accuracy and evasion stages scale the byte sequentially, capped at 255.
	if eff_name != "SWIFT_EFFECT" and int(md["accuracy"]) > 0:
		var acc := int(int(md["accuracy"]) * 255 / 100.0)
		acc = int(acc * float(STAGE_MULT[clampi(int(att_st["acc"]), -6, 6)]))
		acc = int(acc * float(STAGE_MULT[clampi(-int(def_st["eva"]), -6, 6)]))
		acc = mini(acc, 255)
		if _ri(256) >= acc:
			msgs.append("%s's\nattack missed!" % att["label"])
			_on_miss(att, md, msgs)
			return

	# NIGHT SHADE is pokered's one zero-power move that damages: core.asm branches on
	# SPECIAL_DAMAGE_EFFECT before its zero-power skip (.specialDamage), so the effect —
	# not the power byte — decides the path (gh #181).
	if int(md["power"]) == 0 and str(md["effect"]) != "SPECIAL_DAMAGE_EFFECT":
		_do_status_move(att, defn, move, md, msgs, att_st, def_st, att_vol, def_vol, att_is_player)
	else:
		_do_damage_move(att, defn, move, md, msgs, att_st, def_st, att_vol, def_vol, att_is_player)


# ---- damaging moves --------------------------------------------------------

func _do_damage_move(att: Dictionary, defn: Dictionary, move: String, md: Dictionary, msgs: Array,
		att_st: Dictionary, def_st: Dictionary, att_vol: Dictionary, def_vol: Dictionary, att_is_player: bool) -> void:
	var eff_name := str(md["effect"])
	var eff := _type_eff(str(md["type"]), defn["types"])
	if eff == 0.0:
		msgs.append("It doesn't affect\n%s..." % defn["name"])
		return
	if eff_name == "DREAM_EATER_EFFECT" and str(defn["status"]) != "slp":
		msgs.append("But it failed!")
		return

	var am := _move_anim_marker(move, att_is_player)   # the real per-move animation (gh #19)
	if not am.is_empty():
		msgs.append(am)
	# The hit reaction plays after the move's animation and before the HP drain
	# (PlayApplyingAttackAnimation): the effectiveness sting (SFX_Damage / Super_Effective /
	# Not_Very_Effective) together with a blink or shake by AnimationTypePointerTable — the
	# target blinks for a player move without a side effect; otherwise the screen shakes
	# (enemy attacks hard: vertical/heavy 8 cycles, side-effect player moves light: 2).
	msgs.append({"sfx": "super_effective" if eff > 1.0 else ("not_very_effective" if eff < 1.0 else "damage")})
	if att_is_player and eff_name == "NO_ADDITIONAL_EFFECT":
		msgs.append({"anim": "hit", "who": "enemy"})           # ANIMATIONTYPE_BLINK_ENEMY_MON_SPRITE
	elif att_is_player:
		msgs.append({"anim": "shake", "axis": "x", "px": 2})   # ..._HORIZONTALLY_LIGHT
	elif eff_name == "NO_ADDITIONAL_EFFECT":
		msgs.append({"anim": "shake", "axis": "y", "px": 8})   # ..._VERTICALLY
	else:
		msgs.append({"anim": "shake", "axis": "x", "px": 8})   # ..._HORIZONTALLY_HEAVY

	var total := 0
	var crit_any := false
	if eff_name == "OHKO_EFFECT":
		if int(defn["level"]) > int(att["level"]):
			msgs.append("It failed!")
			return
		total = int(defn["hp"])
		msgs.append("It's a one-hit\nKO!")
	elif eff_name == "SPECIAL_DAMAGE_EFFECT":
		total = _special_damage(att, move)
	elif eff_name == "SUPER_FANG_EFFECT":
		total = max(1, int(int(defn["hp"]) / 2))
	else:
		var hits := 1
		if eff_name == "TWO_TO_FIVE_ATTACKS_EFFECT":
			hits = int([2, 2, 3, 3, 4, 5][_ri(6)])
		elif eff_name in ["ATTACK_TWICE_EFFECT", "TWINEEDLE_EFFECT"]:
			hits = 2
		var n := 0
		for i in hits:
			if int(defn["hp"]) <= 0:
				break
			var r := _calc_hit(att, defn, md, att_st, def_st, att_vol, def_vol)
			if bool(r.get("floored_miss", false)):
				# a type pair floored the damage to 0: pokered turns the move into a MISS
				# (AdjustDamageForMoveType's wMoveMissed; the 2-3 dmg x0.25 quirk)
				msgs.append("%s's\nattack missed!" % att["label"])
				break
			total += int(r["dmg"])
			crit_any = crit_any or bool(r["crit"])
			_deal(defn, def_vol, int(r["dmg"]), msgs)
			n += 1
		if hits > 1:
			msgs.append("Hit %d time(s)!" % n)

	if eff_name in ["OHKO_EFFECT", "SPECIAL_DAMAGE_EFFECT", "SUPER_FANG_EFFECT"]:
		_deal(defn, def_vol, total, msgs)
	# Bide stores damage taken by the defender.
	if int(def_vol["bide_turns"]) > 0:
		def_vol["bide"] = int(def_vol["bide"]) + total

	if crit_any:
		msgs.append("A critical hit!")
	if eff != 1.0 and not eff_name in ["OHKO_EFFECT", "SPECIAL_DAMAGE_EFFECT", "SUPER_FANG_EFFECT"]:
		msgs.append("It's super\neffective!" if eff > 1.0 else "It's not very\neffective...")

	# Freeze thaw, recoil/drain/explode, then secondary effects.
	if str(defn["status"]) == "frz" and str(md["type"]) == "FIRE" and int(defn["hp"]) > 0:
		defn["status"] = ""
		msgs.append("%s thawed out!" % defn["name"])
		_show_status(defn, msgs)
	if eff_name == "RECOIL_EFFECT":
		var rc := maxi(1, int(total / 4))
		msgs.append("%s is hit\nwith recoil!" % att["name"])
		_set_hp(att, int(att["hp"]) - rc, msgs)
	elif eff_name in ["DRAIN_HP_EFFECT", "DREAM_EATER_EFFECT"]:
		var gain := maxi(1, int(total / 2))
		msgs.append("%s sucked\nhealth!" % defn["name"])
		_set_hp(att, int(att["hp"]) + gain, msgs)
	elif eff_name == "EXPLODE_EFFECT":
		_set_hp(att, 0, msgs)
	elif eff_name == "PAY_DAY_EFFECT":
		main.player_money += 2 * int(att["level"])
		msgs.append("Coins scattered\neverywhere!")
	elif eff_name == "HYPER_BEAM_EFFECT" and int(defn["hp"]) > 0:
		att_vol["recharge"] = true
	elif eff_name == "TRAPPING_EFFECT" and int(defn["hp"]) > 0:
		if int(att_vol["bind"]) <= 0:                 # first hit: lock both sides
			var n := _rr(1, 3)
			att_vol["bind"] = n
			att_vol["bind_move"] = move
			def_vol["bound"] = n
		else:                                         # a forced repeat
			att_vol["bind"] = int(att_vol["bind"]) - 1
	elif eff_name == "THRASH_PETAL_DANCE_EFFECT" and int(att_vol["thrash"]) <= 0:
		att_vol["thrash"] = _rr(1, 2)                # 2-3 turns total (this one + 1-2 more)
		att_vol["thrash_move"] = move
	elif eff_name == "RAGE_EFFECT":
		att_vol["raging"] = true                     # locked into RAGE until the battle ends
	if int(att_vol["thrash"]) > 0 and eff_name == "THRASH_PETAL_DANCE_EFFECT":
		att_vol["thrash"] = int(att_vol["thrash"]) - 1
		if int(att_vol["thrash"]) <= 0:
			att_vol["confuse"] = _rr(2, 5)            # thrash ends confused 2-5 turns ((rand&3)+2)

	if int(defn["hp"]) > 0:
		_side_effect(md, defn, def_st, def_vol, msgs)
		# HandleBuildingRage: a raging defender's ATTACK climbs with every hit it takes
		if bool(def_vol["raging"]) and int(def_st["atk"]) < 6:
			def_st["atk"] = int(def_st["atk"]) + 1
			msgs.append("%s's\nRAGE is building!" % defn["name"])


## A single hit's damage (Gen-1 formula, with crit / stages / screens / burn).
func _calc_hit(att: Dictionary, defn: Dictionary, md: Dictionary, att_st: Dictionary, def_st: Dictionary,
		att_vol: Dictionary, def_vol: Dictionary) -> Dictionary:
	# Gen-1 critical-hit probability (faithful, including the Focus Energy bug).
	var b := int(int(att["base_spd"]) / 2)
	if bool(att_vol["focus"]):
		b = int(b / 2)                            # BUG: Focus Energy quarters crit chance
	else:
		b = mini(255, b * 2)
	if str(md["name"]).replace(" ", "_") in HIGH_CRIT:
		b = mini(255, mini(255, b * 2) * 2)
	else:
		b = int(b / 2)
	var crit := _rf() < (b / 256.0)
	var lvl: int = int(att["level"]) * 2 if crit else int(att["level"])
	var special: bool = str(md["type"]) in SPECIAL_TYPES
	var akey := "spc" if special else "atk"
	var dkey := "spc" if special else "def"
	var att_is_player := is_same(att_vol, p_vol)
	var a_stat: int
	var d_stat: int
	if crit:
		# Crits read the UNMODIFIED stats (wPlayerMonUnmodified*): no stages, no burn/par
		# penalty, no screens — and no badge boosts (the unmodified copy is snapshotted
		# before ApplyBadgeStatBoosts runs).
		a_stat = int(att[akey])
		d_stat = int(defn[dkey])
	else:
		# The STORED battle stats: stages, penalties, and badge boosts (with their stacking
		# histories) are already baked in — GetDamageVars* just reads them.
		a_stat = int((p_mod if att_is_player else e_mod)[akey])
		d_stat = int((e_mod if att_is_player else p_mod)[dkey])
		if (special and bool(def_vol["light_screen"])) or (not special and bool(def_vol["reflect"])):
			d_stat *= 2                            # uncapped in pokered too (512+ wraps on GB)
	if str(md["effect"]) == "EXPLODE_EFFECT":
		d_stat = maxi(1, int(d_stat / 2))          # CalculateDamage: EXPLODE_EFFECT halves defense
	# GetDamageVars*: if either stat overflows a byte, BOTH scale by /4 at byte precision.
	# (pokered can reach a 0 divisor here and freeze; the port clamps to 1 instead of hanging.)
	if a_stat > 255 or d_stat > 255:
		a_stat = maxi(1, int(a_stat / 4))
		d_stat = maxi(1, int(d_stat / 4))
	# CalculateDamage, integer-exact: every step floors like the GB divides, the quotient caps
	# at 997 and MIN_NEUTRAL_DAMAGE (+2) lands on top — max 999 (gh #176 phase 2).
	var dmg := int((2 * lvl) / 5) + 2
	dmg = int(dmg * int(md["power"]) * a_stat / maxi(1, d_stat))
	dmg = mini(int(dmg / 50), 997) + 2
	# AdjustDamageForMoveType: STAB adds a floored half, then each matching TypeEffects TABLE
	# ENTRY applies ×n/10 with its own floor, in table order. A pure-type defender (stored
	# TYPE,TYPE) matches an entry ONCE — the old product over both slots squared it. A pair
	# that floors the damage to 0 turns the move into a MISS (the 2-3 dmg x0.25 quirk).
	if str(md["type"]) in att["types"]:
		dmg += int(dmg / 2)
	var eff := 1.0
	var row: Dictionary = type_chart.get(str(md["type"]), {})
	for dt in row:
		if str(defn["types"][0]) == dt or str(defn["types"][1]) == dt:
			var mult := float(row[dt])
			eff *= mult
			dmg = int(dmg * mult)                  # ×20/10 / ×5/10 / ×0, floored per entry
			if dmg == 0:
				return {"dmg": 0, "crit": crit, "eff": eff, "floored_miss": true}
	# RandomizeDamage: damage below 2 is not randomized
	if dmg > 1:
		dmg = maxi(1, int(dmg * _rr(217, 255) / 255.0))
	return {"dmg": dmg, "crit": crit, "eff": eff}


# pokered's stat-stage ratios (StatModifier n/100); the modified stat floors and lives in [1, 999].
const _STAGE_NUM := {-6: 25, -5: 28, -4: 33, -3: 40, -2: 50, -1: 66,
	0: 100, 1: 150, 2: 200, 3: 250, 4: 300, 5: 350, 6: 400}


func _stage_apply(base: int, stage: int) -> int:
	return clampi(int(base * _STAGE_NUM[clampi(stage, -6, 6)] / 100), 1, 999)


## The type multiplier exactly as AdjustDamageForMoveType composes it: each TypeEffects table
## entry for the move's type fires ONCE if it matches either defender type — a pure-type mon
## (stored TYPE,TYPE) is not double-counted (gh #176 phase 2).
func _type_eff(move_type: String, def_types: Array) -> float:
	var e := 1.0
	var row: Dictionary = type_chart.get(move_type, {})
	for dt in row:
		if str(def_types[0]) == dt or str(def_types[1]) == dt:
			e *= float(row[dt])
	return e


## Apply damage to a mon, routed to its SUBSTITUTE first if one is up.
## Set a battling mon's HP and queue an animated HP-bar drain to the new value (like UpdateHPBar2).
func _set_hp(mon: Dictionary, new_hp: int, msgs: Array) -> void:
	new_hp = clampi(new_hp, 0, int(mon["maxhp"]))
	mon["hp"] = new_hp
	msgs.append({"hp": "player" if is_same(mon, player_mon) else "enemy", "to": new_hp})


func _show_status(mon: Dictionary, msgs: Array) -> void:
	msgs.append({"status": "player" if is_same(mon, player_mon) else "enemy",
		"to": str(mon["status"])})


## Apply damage — a SUBSTITUTE soaks it (AttackSubstitute): damage over 255 always breaks it,
## damage GREATER than its HP breaks it, and exactly-equal damage leaves a 0-HP sub standing
## (the Gen-1 quirk). Breaking nullifies the move's secondary effect for this hit.
func _deal(defn: Dictionary, def_vol: Dictionary, dmg: int, msgs: Array) -> void:
	if bool(def_vol["sub_up"]):
		msgs.append("The SUBSTITUTE took damage for %s!" % defn["name"])
		if dmg > 255 or dmg > int(def_vol["sub"]):
			def_vol["sub"] = 0
			def_vol["sub_up"] = false
			def_vol["sub_broke"] = true
			msgs.append("%s's SUBSTITUTE\nbroke!" % defn["name"])
			msgs.append({"sub_hide": "player" if defn == player_mon else "enemy"})
		else:
			def_vol["sub"] = int(def_vol["sub"]) - dmg
	else:
		_set_hp(defn, int(defn["hp"]) - dmg, msgs)


func _special_damage(att: Dictionary, move: String) -> int:
	match move:
		"SEISMIC_TOSS", "NIGHT_SHADE": return int(att["level"])
		"DRAGON_RAGE": return 40
		"SONICBOOM": return 20
		"PSYWAVE": return max(1, _rr(1, int(1.5 * int(att["level"]))))
	return int(att["level"])


func _on_miss(att: Dictionary, md: Dictionary, msgs: Array) -> void:
	if str(md["effect"]) == "JUMP_KICK_EFFECT":      # crash damage on miss
		msgs.append("%s kept going\nand crashed!" % att["name"])
		_set_hp(att, int(att["hp"]) - max(1, int(int(att["maxhp"]) / 8)), msgs)


func _charge_line(move: String) -> String:
	match move:
		"DIG": return "It burrowed its\nway under!"
		"FLY": return "It flew up high!"
		"SOLARBEAM": return "It took in\nsunlight!"
		"SKULL_BASH": return "It lowered\nits head!"
		"RAZOR_WIND": return "It made a\nwhirlwind!"
		"SKY_ATTACK": return "It glows!"
	return "It is charging!"


## Secondary effects of a damaging move that hit (status / stat-down / flinch / confusion).
## Chances are the asm's exact byte thresholds (a byte roll under N/256): PoisonEffect
## 52/103 (20/40 "percent + 1"), FreezeBurnParalyzeEffect 26/77 (10/30) — and the latter is
## blocked when the target shares the MOVE's type (BODY SLAM can't paralyze a NORMAL-type,
## gh #75); stat-down sides 85 (33), flinch 26/77, confusion 25.
func _side_effect(md: Dictionary, defn: Dictionary, def_st: Dictionary, def_vol: Dictionary, msgs: Array) -> void:
	if bool(def_vol["sub_up"]) or bool(def_vol["sub_broke"]):
		def_vol["sub_broke"] = false
		return              # a SUBSTITUTE blocks secondary effects — including the breaking hit's
		                    # (AttackSubstitute zeroes the move effect when the sub pops)
	var eff_name := str(md["effect"])
	var st := _status_from_effect(eff_name)
	var roll := _ri(256)
	if st[0] != "" and "SIDE_EFFECT" in eff_name:
		if str(st[0]) != "psn" and str(md["type"]) in defn["types"]:
			return          # FreezeBurnParalyzeEffect: immune when sharing the move's type
		if roll < int(st[1]):
			_apply_status(defn, str(st[0]), msgs)
	elif eff_name == "TWINEEDLE_EFFECT" and roll < 52:
		_apply_status(defn, "psn", msgs)
	elif SIDE_STAT.has(eff_name) and roll < 85:
		_change_stage(defn, def_st, str(SIDE_STAT[eff_name]), -1, msgs)
	elif eff_name in ["FLINCH_SIDE_EFFECT1", "FLINCH_SIDE_EFFECT2"] and roll < (77 if eff_name.ends_with("2") else 26):
		def_vol["flinch"] = true
	elif eff_name == "CONFUSION_SIDE_EFFECT" and roll < 25:
		_confuse(defn, def_vol, msgs)


# ---- status (power-0) moves ------------------------------------------------

func _do_status_move(att: Dictionary, defn: Dictionary, move: String, md: Dictionary, msgs: Array,
		att_st: Dictionary, def_st: Dictionary, att_vol: Dictionary, def_vol: Dictionary, att_is_player: bool) -> void:
	# TODO(gh #160): opponent-targeting status moves should also miss a mid-FLY/DIG target.
	# The move data has no target metadata, so guard them once self/field moves can be distinguished safely.
	var am := _move_anim_marker(move, att_is_player)   # the animation plays even if the effect
	if not am.is_empty():                              # then fails ("nothing happened"), as in Gen 1
		msgs.append(am)
	# Non-damaging moves get the slow, silent screen sway after their animation
	# (PlayBattleAnimation2: ANIMATIONTYPE_SHAKE_SCREEN_HORIZONTALLY_SLOW_2 / _SLOW).
	msgs.append({"anim": "sway", "px": 3 if att_is_player else 6})
	var e := str(md["effect"])
	var st := _status_from_effect(e)
	if st[0] != "" and not "SIDE_EFFECT" in e:
		if bool(def_vol["sub_up"]):
			msgs.append("But it failed!")
			return
		_apply_status(defn, str(st[0]), msgs)
		if move == "TOXIC" and str(defn["status"]) == "psn":
			def_vol["toxic"] = 1                      # badly poisoned
		return
	if _eff_re.search(e) != null:                     # stat up/down move
		_apply_stat_move(att, defn, md, msgs, att_st, def_st, def_vol)
		return
	match e:
		"HEAL_EFFECT":
			if str(md["name"]) == "REST":
				att["status"] = "slp"; att["sleep"] = 2
				msgs.append("%s started\nsleeping!" % att["name"])
				_show_status(att, msgs)
				_set_hp(att, int(att["maxhp"]), msgs)
			else:
				msgs.append("%s regained\nhealth!" % att["name"])
				_set_hp(att, int(att["hp"]) + int(int(att["maxhp"]) / 2), msgs)
		"CONFUSION_EFFECT":
			if bool(def_vol["sub_up"]):
				msgs.append("But it failed!")
			else:
				_confuse(defn, def_vol, msgs)
		"LEECH_SEED_EFFECT":
			if "GRASS" in defn["types"] or bool(def_vol["sub_up"]):
				msgs.append("It doesn't affect\n%s..." % defn["name"])
			else:
				def_vol["leech"] = true
				msgs.append("%s was\nseeded!" % defn["name"])
		"FOCUS_ENERGY_EFFECT":
			att_vol["focus"] = true
			msgs.append("%s is getting\npumped!" % att["name"])
		"LIGHT_SCREEN_EFFECT":
			att_vol["light_screen"] = true
			msgs.append("%s's\nSPECIAL rose!" % att["name"])
		"REFLECT_EFFECT":
			att_vol["reflect"] = true
			msgs.append("%s's\nDEFENSE rose!" % att["name"])
		"MIST_EFFECT":
			att_vol["mist"] = true
			msgs.append("%s's shrouded\nin MIST!" % att["name"])
		"HAZE_EFFECT":
			p_stages = _new_stages(); e_stages = _new_stages()
			_rebuild_mod_stats(true); _rebuild_mod_stats(false)   # HazeEffect: unmodified stats back
			msgs.append("All STATS were\neliminated!")
		"SPLASH_EFFECT":
			msgs.append("But nothing\nhappened!")
		"SWITCH_AND_TELEPORT_EFFECT":
			if is_trainer:
				msgs.append("But it failed!")
			else:
				_flee_pending = true
				msgs.append("Got away\nsafely!")
		"DISABLE_EFFECT":
			var d := _random_move_with_pp(defn)
			if d == "" or bool(def_vol["sub_up"]):
				msgs.append("But it failed!")
			else:
				def_vol["disabled"] = d
				msgs.append("%s's %s\nwas disabled!" % [defn["name"], str(moves_db[d]["name"])])
		"CONVERSION_EFFECT":
			# ConversionEffect_ copies the DEFENDER's types onto the user — Gen 1's
			# CONVERSION, not Gen 2's own-first-move version — and fails against a
			# mon mid-DIG/FLY (bit INVULNERABLE).
			if str(def_vol["charging"]) in _VANISH_CHARGE:
				msgs.append("But it failed!")
			else:
				att["types"] = (defn["types"] as Array).duplicate()
				msgs.append("Converted type to\n%s's!" % defn["label"])
		"SUBSTITUTE_EFFECT":
			# SubstituteEffect_: sub HP = maxhp/4; the cost check branches only on underflow,
			# so exactly a quarter of max HP succeeds and leaves the user at 0 (the self-KO bug).
			var cost := int(int(att["maxhp"]) / 4)
			if bool(att_vol["sub_up"]):
				msgs.append("%s\nhas a SUBSTITUTE!" % att["name"])
			elif int(att["hp"]) < cost:
				msgs.append("Too weak to make\na SUBSTITUTE!")
			else:
				att_vol["sub"] = cost
				att_vol["sub_up"] = true
				msgs.append("It created a\nSUBSTITUTE!")
				msgs.append({"sub_show": "player" if att_is_player else "enemy"})
				_set_hp(att, int(att["hp"]) - cost, msgs)
		"MIMIC_EFFECT":
			# MimicEffect writes wBattleMonMoves only — give the player's mon a battle-only
			# copy so the party keeps its real moves (gh #62). PP drains still reach the
			# party slot at the revert (DecrementPP skips the party only when TRANSFORMED).
			# The battle-only copy is kept for the player's mon — and for BOTH sides in a
			# link battle, where the same mon is "enemy" on the peer's sim and must revert
			# identically on switch-out (gh #8: the soak caught the one-sided revert).
			if (att_is_player or link_battle) and not att_vol.has("mimic_backup") \
					and not att_vol.has("transform_backup"):
				att_vol["mimic_backup"] = att["moves"]
				var mcopy: Array = []
				for mv2 in att["moves"]:
					mcopy.append((mv2 as Dictionary).duplicate())
				att["moves"] = mcopy
			# the copied move lands in MIMIC's own slot and keeps that slot's PP
			var slot := 0
			for i in (att["moves"] as Array).size():
				if str(att["moves"][i]["move"]) == "MIMIC":
					slot = i
					break
			if att_is_player and not link_battle:
				# the player picks the technique to copy (.letPlayerChooseMove, gh #65):
				# the menu pops when the move executes, mid-turn. In a LINK battle both
				# sims take the deterministic random pick below instead — a mid-turn menu
				# choice can't cross the wire mid-resolution (documented v1.1 divergence).
				var names: Array = []
				for mv2 in defn["moves"]:
					names.append(str(mv2["move"]))
				msgs.append({"mimic_pick": names, "slot": slot})
			else:
				# the enemy copies a random non-empty move (.getRandomMove — no PP check)
				var m := str(defn["moves"][_ri((defn["moves"] as Array).size())]["move"])
				var mslot: Dictionary = att["moves"][slot]
				mslot["move"] = m
				mslot["maxpp"] = int(moves_db[m]["pp"])
				msgs.append("%s learned\n%s!" % [att["name"], str(moves_db[m]["name"])])
		"TRANSFORM_EFFECT":
			# TransformEffect_ writes the wBattleMon struct only; keep the party mon's real
			# moves/types so they revert when it leaves the field (gh #62).
			if (att_is_player or link_battle) and not att_vol.has("transform_backup"):
				att_vol["transform_backup"] = {"moves": att["moves"], "types": att["types"]}
			att_vol["transformed"] = true     # a transformed catch becomes a DITTO (ItemUseBall)
			att["types"] = (defn["types"] as Array).duplicate()
			var att_mod: Dictionary = p_mod if att_is_player else e_mod
			var def_mod: Dictionary = e_mod if att_is_player else p_mod
			for k in ["atk", "def", "spc", "spd"]:
				att[k] = defn[k]              # the unmodified copies (for crits/recalcs)
				att_mod[k] = def_mod[k]       # and the STORED stats (TransformEffect copies wBattleMon)
			att["moves"] = []
			for mv in defn["moves"]:
				att["moves"].append({"move": mv["move"], "pp": 5, "maxpp": 5})
			for k in att_st:                          # copy the target's stat stages
				att_st[k] = def_st[k]
			if att_is_player:                         # become the target's sprite
				back_tex = load("res://assets/pokemon/back/%s.png" % defn["species"])
			else:
				front_tex = load("res://assets/pokemon/front/%s.png" % defn["species"])
			msgs.append("%s TRANSFORMED\ninto %s!" % [att["name"], defn["name"]])
		"BIDE_EFFECT":
			att_vol["bide"] = 0; att_vol["bide_turns"] = 2
			msgs.append("%s is storing\nenergy!" % att["name"])
		_:
			pass


func _do_bide(att: Dictionary, defn: Dictionary, msgs: Array, att_vol: Dictionary) -> void:
	att_vol["bide_turns"] = int(att_vol["bide_turns"]) - 1
	if int(att_vol["bide_turns"]) > 0:
		msgs.append("%s is storing\nenergy!" % att["name"])
		return
	var out := maxi(1, int(att_vol["bide"]) * 2)
	att_vol["bide"] = 0
	msgs.append("%s unleashed\nenergy!" % att["name"])
	_set_hp(defn, int(defn["hp"]) - out, msgs)


func _confuse(mon: Dictionary, vol: Dictionary, msgs: Array) -> void:
	if int(vol["confuse"]) > 0:
		return
	vol["confuse"] = _rr(2, 5)
	msgs.append("%s became\nconfused!" % mon["name"])


func _random_move_with_pp(mon: Dictionary) -> String:
	var opts: Array = []
	for mv in mon["moves"]:
		if int(mv["pp"]) > 0:
			opts.append(str(mv["move"]))
	return "" if opts.is_empty() else str(opts[_ri(opts.size())])


func _metronome_pick() -> String:
	var keys: Array = moves_db.keys()
	for i in range(20):
		var m := str(keys[_ri(keys.size())])
		if m != "METRONOME" and m != "MIRROR_MOVE" and m != "STRUGGLE" and m != "TRANSFORM":
			return m
	return "POUND"


func _has_usable_move(mon: Dictionary, vol: Dictionary) -> bool:
	for mv in mon["moves"]:
		if int(mv["pp"]) > 0 and str(mv["move"]) != str(vol["disabled"]):
			return true
	return false


func _type_mult(atk_type: String, def_type: String) -> float:
	return float(type_chart.get(atk_type, {}).get(def_type, 1.0))


# ---- status conditions -----------------------------------------------------

## Can `att` act this turn? CheckPlayerStatusConditions' order, exactly: sleep -> freeze ->
## held by the enemy's trapping move -> flinch -> confusion (the counter ticks, then 127/256
## to hurt itself) -> paralysis (64/256 fully paralyzed). A sleeping mon never reaches the
## flinch/confusion ticks, and the waking turn is lost too.
func _can_act(att: Dictionary, vol: Dictionary, other_vol: Dictionary, msgs: Array) -> bool:
	match str(att["status"]):
		"slp":
			att["sleep"] = int(att["sleep"]) - 1
			if int(att["sleep"]) <= 0:
				att["status"] = ""
				msgs.append("%s woke up!" % att["label"])
				_show_status(att, msgs)
			else:
				msgs.append("%s is fast\nasleep!" % att["label"])
			return false
		"frz":
			msgs.append("%s is frozen\nsolid!" % att["label"])
			return false
	if int(vol["bound"]) > 0:                          # held by the enemy's Wrap/Bind/Clamp
		vol["bound"] = int(vol["bound"]) - 1
		msgs.append("%s can't\nmove!" % att["label"])
		return false
	if bool(vol["flinch"]):
		msgs.append("%s flinched!" % att["label"])
		return false
	if int(vol["confuse"]) > 0:
		vol["confuse"] = int(vol["confuse"]) - 1
		if int(vol["confuse"]) <= 0:
			msgs.append("%s snapped out\nof confusion!" % att["label"])
		else:
			msgs.append("%s is\nconfused!" % att["label"])
			if _ri(256) >= 129:                        # cp 50 percent + 1: 127/256 to hurt itself
				msgs.append("It hurt itself in\nits confusion!")
				_set_hp(att, int(att["hp"]) - _confusion_self_damage(att, vol), msgs)
				_break_locks(vol, other_vol, msgs)
				return false
	if str(att["status"]) == "par" and _ri(256) < 64:   # 25 percent
		msgs.append("%s is fully\nparalyzed!" % att["label"])
		_break_locks(vol, other_vol, msgs)
		return false
	return true


## HandleSelfConfusionDamage: the integer damage chain at power 40 with the mon's own STORED
## attack against its own STORED defense (the asm swaps the enemy's defense bytes for the
## user's — stages/penalties/boosts all baked) — typeless, critless, never misses, no random.
func _confusion_self_damage(att: Dictionary, vol: Dictionary) -> int:
	var mod: Dictionary = p_mod if is_same(vol, p_vol) else e_mod
	var a_stat := int(mod["atk"])
	var d_stat := int(mod["def"])
	if a_stat > 255 or d_stat > 255:                   # the GetDamageVars* /4 byte scaling
		a_stat = maxi(1, int(a_stat / 4))
		d_stat = maxi(1, int(d_stat / 4))
	var dmg := int((2 * int(att["level"])) / 5) + 2
	dmg = int(dmg * 40 * a_stat / maxi(1, d_stat))
	return mini(int(dmg / 50), 997) + 2


## .MonHurtItselfOrFullyParalysed: bide, thrash, charge and trapping locks all break (the
## confusion counter and major status stay). A vanished FLY/DIG mon reappears, and a foe held
## by this mon's Wrap is freed — the hold lives on the ATTACKER's USING_TRAPPING_MOVE bit.
func _break_locks(vol: Dictionary, other_vol: Dictionary, msgs: Array) -> void:
	if str(vol["charging"]) in _VANISH_CHARGE:
		msgs.append({"show_pic": "player" if is_same(vol, p_vol) else "enemy"})
	vol["charging"] = ""
	vol["bide"] = 0
	vol["bide_turns"] = 0
	vol["thrash"] = 0
	vol["thrash_move"] = ""
	if int(vol["bind"]) > 0:
		vol["bind"] = 0
		other_vol["bound"] = 0
	vol["bind_move"] = ""


## effect name -> [status code, side-effect byte threshold /256]. Primary status effects
## are certain (256); the sides use the asm's exact bytes — PoisonEffect 52/103, everything
## else (FreezeBurnParalyzeEffect) 26/77 (gh #75: poison sides ran at half rate).
func _status_from_effect(effect: String) -> Array:
	var chance := 256
	if "SIDE_EFFECT" in effect:
		if "POISON" in effect:
			chance = 103 if effect.ends_with("2") else 52
		else:
			chance = 77 if effect.ends_with("2") else 26
	if "SLEEP" in effect:
		return ["slp", chance]
	if "POISON" in effect or "TOXIC" in effect:
		return ["psn", chance]
	if "PARALYZE" in effect:
		return ["par", chance]
	if "BURN" in effect:
		return ["brn", chance]
	if "FREEZE" in effect:
		return ["frz", chance]
	return ["", 0.0]


func _apply_status(mon: Dictionary, st: String, msgs: Array) -> void:
	if st == "" or str(mon["status"]) != "":
		return                                  # one status at a time
	if (st == "psn" and "POISON" in mon["types"]) \
			or (st == "brn" and "FIRE" in mon["types"]) \
			or (st == "frz" and "ICE" in mon["types"]):
		return                                  # type immunity
	mon["status"] = st
	var mod: Dictionary = p_mod if is_same(mon, player_mon) else e_mod
	if st == "slp":
		mon["sleep"] = _rr(1, 7)                # SleepEffect: (rand & 7) rerolled while 0
	elif st == "par":
		mod["spd"] = maxi(1, int(mod["spd"] / 4))   # QuarterSpeedDueToParalysis, destructive —
	elif st == "brn":                               # a later cure does NOT restore the stat
		mod["atk"] = maxi(1, int(mod["atk"] / 2))   # HalveAttackDueToBurn likewise
	var verb := {"psn": "was poisoned!", "par": "was paralyzed!", "slp": "fell asleep!",
		"brn": "was burned!", "frz": "was frozen solid!"}
	msgs.append("%s %s" % [mon["name"], verb[st]])
	_show_status(mon, msgs)


## HandlePoisonBurnLeechSeed — the mover's own after-action damage: poison/burn 1/16 max (min
## 1, Toxic escalates), then Leech Seed drains to `other`. The toxic counter multiplies (and
## advances) on the LEECH drain too — "the toxic ticks are considered even if the damage is
## not poison (hence the Leech Seed glitch)", asm comment verbatim.
func _residual(mon: Dictionary, vol: Dictionary, other: Dictionary, msgs: Array) -> void:
	if int(mon["hp"]) <= 0:
		return
	var s := str(mon["status"])
	var base := maxi(1, int(int(mon["maxhp"]) / 16))
	if s == "psn":
		var ticks := int(vol["toxic"])               # 0 = normal poison, >=1 = badly poisoned
		var dmg := base
		if ticks > 0:
			dmg = base * ticks
			vol["toxic"] = ticks + 1
		msgs.append("%s is hurt\nby poison!" % mon["name"])
		_set_hp(mon, int(mon["hp"]) - dmg, msgs)
	elif s == "brn":
		msgs.append("%s is hurt\nby its burn!" % mon["name"])
		_set_hp(mon, int(mon["hp"]) - base, msgs)
	if bool(vol["leech"]) and int(mon["hp"]) > 0:
		var drain := base
		if int(vol["toxic"]) > 0:                    # the Leech Seed glitch
			drain = base * int(vol["toxic"])
			vol["toxic"] = int(vol["toxic"]) + 1
		msgs.append("LEECH SEED saps\n%s!" % mon["name"])
		_set_hp(mon, int(mon["hp"]) - drain, msgs)
		_set_hp(other, int(other["hp"]) + drain, msgs)


## The side's STORED speed (wBattleMonSpeed / wEnemyMonSpeed): stages, the paralysis quarter
## (with its compounding history), and badge boosts are already baked in.
func _eff_speed(is_player: bool) -> int:
	return int((p_mod if is_player else e_mod)["spd"])


## Apply a stat-change move (GROWL/LEER/GROWTH/...). UP affects the user, DOWN the target.
func _apply_stat_move(att: Dictionary, defn: Dictionary, md: Dictionary, msgs: Array,
		att_st: Dictionary, def_st: Dictionary, def_vol: Dictionary) -> void:
	var m := _eff_re.search(str(md["effect"]))
	if m == null or not STAT_KEY.has(m.get_string(1)):
		return
	var up := m.get_string(2) == "UP"
	if not up:
		# StatModifierDownEffect's front gates, in the asm's order: the ENEMY's pure
		# stat-down moves carry a hidden 65/256 miss in a non-link battle (the player's
		# don't); a substitute blocks; MIST protects; a mid-FLY/DIG target can't be hit
		# (the INVULNERABLE check).
		if not link_battle and is_same(defn, player_mon) and _ri(256) < 65:
			# ...and in a LINK battle no side rolls it (the asm checks wLinkState) — the
			# mirrored sims would otherwise draw on one peer and not the other.
			msgs.append("%s's\nattack missed!" % att["label"])
			return
		if bool(def_vol["sub_up"]):
			msgs.append("But it failed!")
			return
		if bool(def_vol["mist"]):
			msgs.append("%s is protected\nby MIST!" % defn["name"])
			return
		if str(def_vol["charging"]) in _VANISH_CHARGE:
			msgs.append("%s's\nattack missed!" % att["label"])
			return
	var amt := int(m.get_string(3))
	_change_stage(att if up else defn, att_st if up else def_st, m.get_string(1), amt if up else -amt, msgs)


## StatModifier(Up|Down)Effect: bump the stage, rebuild the changed stat from its UNMODIFIED
## value × the stage ratio ("paralysis and burn penalties, as well as badge boosts are
## ignored"), then run the trailer that makes the Gen-1 stacking glitches real. A stat-up on a
## stored 999 (or a stat-down on a stored 1) fails outright, stage rolled back.
func _change_stage(mon: Dictionary, stages: Dictionary, stat_name: String, delta: int, msgs: Array) -> void:
	if not STAT_KEY.has(stat_name):
		return
	var key: String = STAT_KEY[stat_name]
	var nw: int = clampi(int(stages[key]) + delta, -6, 6)
	if nw == int(stages[key]):
		msgs.append("%s's\n%s won't go %s!" % [mon["name"], stat_name, "higher" if delta > 0 else "lower"])
		return
	var target_is_player := is_same(stages, p_stages)
	var mod: Dictionary = p_mod if target_is_player else e_mod
	if mod.has(key):                                    # acc/eva have no stored stat
		if delta > 0 and int(mod[key]) >= 999:
			msgs.append("Nothing happened!")            # .checkIf999 -> RestoreOriginalStatModifier
			return
		if delta < 0 and int(mod[key]) <= 1:
			msgs.append("Nothing happened!")            # "can't lower stat below 1" -> CantLowerAnymore
			return
	stages[key] = nw
	if mod.has(key):
		# The recalc: unmodified × ratio, floored, min 1, cap 999 — penalties and badge
		# boosts on THIS stat are silently dropped (the wipe half of the quirk).
		mod[key] = _stage_apply(int(mon[key]), nw)
	var sharp := "sharply " if absi(delta) >= 2 else ""
	# authored break after the possessive, as the asm texts do ("BULBASAUR's / DEFENSE fell!")
	msgs.append("%s's\n%s %s%s!" % [mon["name"], stat_name, sharp, "rose" if delta > 0 else "fell"])
	_stat_move_trailer(target_is_player, delta > 0)


## The tail every successful stage change runs (acc/eva included): badge boosts REAPPLY to all
## four of the player's stored stats whenever the player's mon was the target — "even to those
## not affected by the stat-up move (will be boosted further)", the stacking glitch — and then
## QuarterSpeedDueToParalysis + HalveAttackDueToBurn re-penalize the NON-ACTING side's mon,
## compounding on its stored stats ("these shouldn't be here", effects.asm 504).
func _stat_move_trailer(target_is_player: bool, up: bool) -> void:
	if target_is_player:
		for k in ["atk", "def", "spd", "spc"]:
			p_mod[k] = _badge_boost(int(p_mod[k]), k)
	# Gen 1 has no self-lowering or foe-raising moves: the actor is the target's side on an
	# UP, its opponent on a DOWN — so the non-acting side is the target's opposite on an UP,
	# the target itself on a DOWN.
	var pen_is_player: bool = (not target_is_player) if up else target_is_player
	var pmon: Dictionary = player_mon if pen_is_player else enemy_mon
	var pmod: Dictionary = p_mod if pen_is_player else e_mod
	if str(pmon["status"]) == "par":
		pmod["spd"] = maxi(1, int(pmod["spd"] / 4))
	if str(pmon["status"]) == "brn":
		pmod["atk"] = maxi(1, int(pmod["atk"] / 2))


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
