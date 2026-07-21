extends RulesetBattle
class_name Gen1Battle
## The Gen-1 battle module (gh #33, ADR-018 §1, §2). Owns the BATTLE STATE and (as the
## migration proceeds) the mechanics: turn structure, action order, move execution,
## status + residuals, the trainer AI — everything that computes; the Battle host keeps
## presentation (drawing, HUD, animations, the message pump) and consumes the ordered
## event stream the mechanics append (v1's ADR-009 queue is the contract). Battle.gd
## forwards these fields via properties, so presentation, the test harness, and the link
## plumbing read/write the same state they always did. One session at a time (the host
## node is a singleton); a session object can split out when a second sample demands it.

var b        # the Battle host (presentation + the message pump) — set by bind()
var rset: Ruleset   # the owning ruleset (types/formulas), set by Gen1Ruleset.configure


func bind(battle) -> void:
	b = battle


# ---- battle state (moved verbatim from Battle.gd, comments riding along) ----

var p_stages: Dictionary
var e_stages: Dictionary
var p_vol: Dictionary
var e_vol: Dictionary
var _eff_re := RegEx.new()

# The STORED battle stats (wBattleMon* / wEnemyMon*), maintained exactly as pokered mutates
# them: rebuilt at send-out and level-up, one stat recalculated per stage change, penalties
# and badge boosts applied ON TOP destructively — which is what makes the Gen-1 stacking
# glitches real (see _stat_move_trailer). The mon dicts' own stats stay UNMODIFIED
# (wPlayerMonUnmodified*), used for crits and stage recalcs.
var p_mod := {"atk": 1, "def": 1, "spd": 1, "spc": 1}
var e_mod := {"atk": 1, "def": 1, "spd": 1, "spc": 1}

# (The badge->stat mapping — BadgeStatBoosts' even bit positions — is the progression
# module's config-driven table now: rset.progression.badge_for_stat, gh #34.)

const SPECIAL_TYPES := ["FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE", "DRAGON"]
const STAT_KEY := {"ATTACK": "atk", "DEFENSE": "def", "SPECIAL": "spc",
	"SPEED": "spd", "ACCURACY": "acc", "EVASION": "eva"}
const TWO_TURN := ["CHARGE_EFFECT", "FLY_EFFECT", "SOLARBEAM"]   # turn 1 charges
const _VANISH_CHARGE := ["DIG", "FLY"]          # ...and these two go out of sight while they do (gh #122)
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
# stat-down side effects -> the stat they lower
const SIDE_STAT := {"SPEED_DOWN_SIDE_EFFECT": "SPEED", "DEFENSE_DOWN_SIDE_EFFECT": "DEFENSE",
	"ATTACK_DOWN_SIDE_EFFECT": "ATTACK", "SPECIAL_DOWN_SIDE_EFFECT": "SPECIAL"}

var base_stats: Dictionary
var moves_db: Dictionary

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
var run_attempts := 0          # wNumRunAttempts: each failed try adds 30 to the next escape roll
var newly_caught := false      # this catch is a first-time species (dex entry shows after)
var doll_escape := false       # fled via POKé DOLL: wBattleResult stays 0 (the MAROWAK trick)
# Gen-1 trainer AI (engine/battle/trainer_ai.asm): the class's move-choice modification
# layers, its item/switch handler, and how many uses it gets per mon (wAICount).
var ai_mods: Array = []
var ai_kind := "Generic"
var ai_count_max := 3
var _ai_uses := 0
var _ai_turn := 0              # enemy moves taken (wAILayer2Encouragement)
var ghost := false             # unidentified GHOST (Pokémon Tower, no SILPH SCOPE): can't be fought
var unveil := false            # the scripted MAROWAK: appears as GHOST until the SILPH SCOPE reveal
var safari_bait := 0           # "eating" counter (less likely to flee)
var safari_escape := 0         # "angry" counter (more likely to flee)
var safari_catch := 0          # current (bait/rock-modified) catch rate
var trainer_name := ""
var prize := 0
var won := false              # true once the battle is won (vs blackout)
var caught := false           # true once the enemy mon is caught (a ball succeeded)
var blacked_out := false      # true if the player ran out of usable mons
var no_blackout := false      # story battles (first rival) that heal + continue instead of whiting out
var _flee_pending := false    # Teleport/Whirlwind used in a wild battle
var can_evolve: Array = []   # party indices that leveled this battle (wCanEvolveFlags, gh #67)

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
# cross the wire. See Battle.gd's link section for the neutralization notes.
var link_battle := false
var link_host := false
var peer_name := ""            # the partner's player name (their trainer label)
var link_actions: Array = []   # the peer's col_act actions, in turn order (fed by Cutscene)
var link_swaps: Array = []     # the peer's col_swap faint replacements, in order
var _link_wait := ""           # "" | "act" (their turn action) | "swap" (their replacement)
var _link_pact := {}           # our pending action while waiting for theirs
var _link_pact_turn := -1      # the turn it was submitted for (gh #13: resume retransmit)
var _link_lswap := -1          # our last faint replacement sent as col_swap, and its turn
var _link_lswap_turn := -1
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


func _new_stages() -> Dictionary:
	return {"atk": 0, "def": 0, "spc": 0, "spd": 0, "acc": 0, "eva": 0}


## One ×1.125 badge application: v += v/8, capped at MAX_STAT_VALUE (999).
## Link battles take none (ApplyBadgeStatBoosts rets on LINK_STATE_BATTLING) — and the two
## mirrored lockstep sims would disagree on the numbers if either side's badges applied.
func _badge_boost(v: int, key: String) -> int:
	if link_battle:
		return v
	var badge := rset.progression.badge_for_stat(key)   # config-driven mapping (gh #34)
	if b.main and badge != "" and badge in b.main.badges:
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


## The side's STORED speed (wBattleMonSpeed / wEnemyMonSpeed): stages, the paralysis quarter
## (with its compounding history), and badge boosts are already baked in.
func _eff_speed(is_player: bool) -> int:
	return int((p_mod if is_player else e_mod)["spd"])


## The StatModifier n/100 stage table is the ruleset's stage_apply kernel now (gh #32).
func _stage_apply(base: int, stage: int) -> int:
	return rset.formulas.stage_apply(base, stage)


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


## DecrementPP: spend one PP of `move` in `mon`'s moveset. No-op if the mon doesn't own the move
## (e.g. a charge move summoned by METRONOME), as pokered's DecrementPP keys off the selected slot.
func _spend_pp(mon: Dictionary, move: String) -> void:
	for mv in mon["moves"]:
		if str(mv["move"]) == move:
			mv["pp"] = max(0, int(mv["pp"]) - 1)
			return


## A two-turn charge move (FLY/DIG/SOLARBEAM/Sky Attack/…) — matches _do_move's charge gate (gh #168).
func _is_two_turn(move: String) -> bool:
	return move in TWO_TURN or str(moves_db.get(move, {}).get("effect", "")) in TWO_TURN


func _has_usable_move(mon: Dictionary, vol: Dictionary) -> bool:
	for mv in mon["moves"]:
		if int(mv["pp"]) > 0 and str(mv["move"]) != str(vol["disabled"]):
			return true
	return false


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


## The composed type multiplier, through the ruleset seam (gh #31) — the Gen-1 algorithm
## (AdjustDamageForMoveType's single-fire per table entry) lives in Gen1Types now.
func _type_eff(move_type: String, def_types: Array) -> float:
	return rset.types.eff(move_type, def_types)


func _type_mult(atk_type: String, def_type: String) -> float:
	return rset.types.mult(atk_type, def_type)


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

	# Accuracy (MoveHitTest, Swift never misses) — the byte math (100% = 255 vs rand(256),
	# the 1/256 sure-miss quirk, sequential stage scaling) is the ruleset's accuracy_roll
	# kernel now (gh #32).
	if eff_name != "SWIFT_EFFECT" and int(md["accuracy"]) > 0:
		if not rset.formulas.accuracy_roll(int(md["accuracy"]), int(att_st["acc"]),
				int(def_st["eva"]), _ri):
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

	var am: Dictionary = b._move_anim_marker(move, att_is_player)   # the real per-move animation (gh #19)
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
		b.main.player_money += 2 * int(att["level"])
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
	# Crit probability + damage arithmetic are the ruleset's formula kernels now (gh #32);
	# the stat SELECTION below (unmodified-on-crit, screens, EXPLODE) stays battle state.
	var crit: bool = rset.formulas.crit_roll(int(att["base_spd"]), bool(att_vol["focus"]),
		str(md["name"]), _rf)
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
	var dmg: int = rset.formulas.damage_core(int(att["level"]), crit, int(md["power"]),
		a_stat, d_stat)
	# AdjustDamageForMoveType: STAB adds a floored half, then each matching TypeEffects TABLE
	# ENTRY applies ×n/10 with its own floor, in table order. A pure-type defender (stored
	# TYPE,TYPE) matches an entry ONCE — the old product over both slots squared it. A pair
	# that floors the damage to 0 turns the move into a MISS (the 2-3 dmg x0.25 quirk).
	if str(md["type"]) in att["types"]:
		dmg += int(dmg / 2)
	var eff := 1.0
	var row: Dictionary = rset.types.row(str(md["type"]))
	for dt in row:
		if str(defn["types"][0]) == dt or str(defn["types"][1]) == dt:
			var mult := float(row[dt])
			eff *= mult
			dmg = int(dmg * mult)                  # ×20/10 / ×5/10 / ×0, floored per entry
			if dmg == 0:
				return {"dmg": 0, "crit": crit, "eff": eff, "floored_miss": true}
	dmg = rset.formulas.randomize_damage(dmg, _rr)
	return {"dmg": dmg, "crit": crit, "eff": eff}


func _do_status_move(att: Dictionary, defn: Dictionary, move: String, md: Dictionary, msgs: Array,
		att_st: Dictionary, def_st: Dictionary, att_vol: Dictionary, def_vol: Dictionary, att_is_player: bool) -> void:
	# TODO(gh #160): opponent-targeting status moves should also miss a mid-FLY/DIG target.
	# The move data has no target metadata, so guard them once self/field moves can be distinguished safely.
	var am: Dictionary = b._move_anim_marker(move, att_is_player)   # the animation plays even if the effect
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
				b.back_tex = load("res://assets/pokemon/back/%s.png" % defn["species"])
			else:
				b.front_tex = load("res://assets/pokemon/front/%s.png" % defn["species"])
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


func _confuse(mon: Dictionary, vol: Dictionary, msgs: Array) -> void:
	if int(vol["confuse"]) > 0:
		return
	vol["confuse"] = _rr(2, 5)
	msgs.append("%s became\nconfused!" % mon["name"])


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
	# A typeless 40-power hit through the same damage kernel (incl. the /4 byte scaling).
	var mod: Dictionary = p_mod if is_same(vol, p_vol) else e_mod
	return rset.formulas.damage_core(int(att["level"]), false, 40,
		int(mod["atk"]), int(mod["def"]))


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


func _special_damage(att: Dictionary, move: String) -> int:
	return rset.formulas.special_damage(move, int(att["level"]), _rr)


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


## Undo the Transform/Mimic battle-only overlay before `mon` leaves the field (gh #62).
## pokered keeps these in wBattleMon* and never writes the party struct; switching out or
## ending the battle reloads the real data.
func _revert_battle_copy(mon: Dictionary, vol: Dictionary) -> void:
	if vol.has("transform_backup"):
		var bk: Dictionary = vol["transform_backup"]
		# transformed PP is fully separate (DecrementPP returns when TRANSFORMED): no copy-back
		mon["moves"] = vol["mimic_backup"] if vol.has("mimic_backup") else bk["moves"]
		mon["types"] = bk["types"]
		b.main.recompute_stats(mon)          # party-truth stats (also right after a level-up)
		vol.erase("transform_backup")
		vol.erase("mimic_backup")
	elif vol.has("mimic_backup"):
		var real: Array = vol["mimic_backup"]
		var cur: Array = mon["moves"]
		for i in mini(real.size(), cur.size()):
			real[i]["pp"] = cur[i]["pp"]   # PP drains hit the party slot too (DecrementPP quirk)
		mon["moves"] = real
		vol.erase("mimic_backup")


## ItemUseBall's capture + wobble algorithm, Gen-1 exact: the ball kind sets rand1's span
## and the HP factor's divisor; sleep/freeze shave 25 off the roll and other ailments 12
## (underflow = certain catch); a failure wobbles 0-3 times by Z = X*Y/255 + status2.
## X = min(W, 255) is computed BEFORE the catch-rate comparison, so hQuotient+3 still holds
## it at .failedToCapture whichever stage failed — a rand1-stage failure uses the same
## HP-derived X as a rand2-stage one, never the catch rate (gh #176).
func _attempt_catch(ball := "POKé BALL", rate_override := -1) -> Dictionary:
	# Routed through the Catch module (gh #34); the byte-exact ItemUseBall arithmetic
	# stays the formula layer's catch_attempt kernel (gh #32).
	var rate := rate_override if rate_override >= 0 \
		else int(base_stats[enemy_mon["species"]]["catch"])
	return rset.catching.attempt(ball, str(enemy_mon["status"]), rate,
		int(enemy_mon["hp"]), int(enemy_mon["maxhp"]), _ri)


## Safari BAIT/ROCK (safari_zone.asm): the rate transitions live on the Catch module;
## the eating/angry counters gain 1-5 turns and zero each other out.
func _safari_bait() -> void:
	_det_paction = "bait"
	safari_catch = rset.catching.bait_rate(safari_catch)
	safari_escape = 0
	safari_bait = min(255, safari_bait + (_ri(5) + 1))


func _safari_rock() -> void:
	_det_paction = "rock"
	safari_catch = rset.catching.rock_rate(safari_catch)
	safari_bait = 0
	safari_escape = min(255, safari_escape + (_ri(5) + 1))


func _resolve(action: Dictionary) -> void:
	if ghost and action["kind"] == "move":
		# Unidentified GHOST (PrintGhostText): the player's mon is too scared to attack, and
		# the ghost only wails — nobody deals damage; running is the only way out.
		b._say(["%s is too\nscared to move!" % player_mon["name"],
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
		b._sub_shown["player"] = false
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
	var row: Dictionary = rset.types.row(str(moves_db.get(move, {}).get("type", "")))
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


func _end_of_turn(msgs: Array) -> void:
	var nxt := "menu"
	if _flee_pending:
		_flee_pending = false
		b._say(msgs, "run")
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
			if b.main and b.main.options["battle_shift"] and not b.fast_hp and not player_dead and _has_other_usable():
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
				if b.trainer_pic_tex:
					msgs.append({"trainer_slide": "in"})
				msgs.append("%s was\ndefeated!" % trainer_name)
				if prize > 0:
					b.main.player_money += prize
					msgs.append("%s got ¥%d\nfor winning!" % [b.main.player_name, prize])
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
			msgs.append("%s is out of\nuseable POKéMON!" % b.main.player_name)
			msgs.append("%s whited out!" % b.main.player_name)
			blacked_out = true            # Main warps to the last Center on battle finish
			won = false                   # a mutual KO that empties your party is a blackout, not a win
			nxt = "end"
	b._say(msgs, nxt)
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
	b._set_enemy(idx)
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
	b._set_enemy(idx)                         # peer's own sim reverts it on switch-out
	_det_event("X", "%s:w:%d" % ["j" if link_host else "h", idx])   # mirror of the peer's X
	b._say([{"auto": "%s sent\nout %s!" % [peer_name, enemy_party[idx]["name"]]},
		{"next_enemy": idx}], "menu")


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
	var flee_b := spd * 2                             # flee chance /256 (safari_zone.asm)
	var ran: bool = spd > 127
	if not ran:
		if safari_bait > 0:
			flee_b = flee_b >> 2                      # eating -> a quarter as likely to flee
		elif safari_escape > 0:
			flee_b = min(255, flee_b << 1)            # angry -> twice as likely to flee
		ran = _ri(256) < flee_b
	if ran:
		msgs.append("%s fled!" % enemy_mon["name"])
		b._say(msgs, "run")
	else:
		b._say(msgs, "menu")
	turn_no += 1
	_det_event("T%d" % turn_no, "p[%s]e[safari]" % _det_paction)
	_det_paction = "-"


## Where a chosen action enters the engine. Non-link: resolve immediately (the AI supplies
## the enemy's move). Link: send ours, hold in "linkwait" until the peer's arrives, then
## both sims resolve the same pair.
func _submit_action(action: Dictionary) -> void:
	if not link_battle:
		_resolve(action)
		return
	_link_pact = action
	_link_pact_turn = turn_no
	b.main.link.send_message({"t": "col_act", "action": _det_action(action)})
	b.main._maybe_kill("act%d" % (turn_no + 1))    # gh #9: cable pull after our turn-N action
	_link_wait = "act"
	_link_elapsed = 0.0
	b.msg = "Waiting..."
	b.revealed = 999
	b.state = "linkwait"                 # ignores input; _process watches the queues
	b.queue_redraw()


## TryRunningFromBattle: ghosts and safari mons never hold you; otherwise escape is free when
## you're at least as fast, else odds are playerSpeed*32 / ((enemySpeed/4) % 256) + 30 per
## prior attempt against a byte roll — and failing costs the turn (the wild mon attacks).
func _try_run() -> void:
	_det_paction = "r"
	run_attempts += 1
	if not (ghost or is_safari or b.demo):
		var ps := _eff_speed(true)
		var es := _eff_speed(false)
		if ps < es:
			var b := (es >> 2) % 256
			if b > 0:
				var q := (ps * 32) / b + 30 * (run_attempts - 1)
				if q <= 255 and _ri(256) >= q:
					_enemy_turn_after_item(["Can't escape!"])
					return
	b._say([{"sfx": "run"}, "Got away\nsafely!"], "run")


## gh #13 (ADR-016): after a transport resume both peers exchange where their sims stand —
## turn, RNG cursor, state digest, what they wait on, and their last-sent action/replacement
## (with its turn) so anything that died in flight rides along. Equal points continue; a
## missing in-flight action is fed from the peer's report (each side feeds ITSELF from the
## other's col_resume — both always send one); equal turn+cursor with differing digests is a
## determinism bug by definition — void, stakeless, loud. Mid-resolution skew (same turn,
## different cursor) is NOT comparable and not a desync: the retransmit rules cover it.
func link_send_resume() -> void:
	b.main.link.send_message({"t": "col_resume", "turn": turn_no, "cursor": rng_cursor,
		"digest": _det_digest(), "wait": _link_wait,
		"act": _det_action(_link_pact) if _link_pact_turn >= 0 else "", "act_turn": _link_pact_turn,
		"swap": _link_lswap, "swap_turn": _link_lswap_turn})


func link_reconcile(peer: Dictionary) -> void:
	if not link_battle or link_over:
		return
	var pturn := int(peer.get("turn", -1))
	print("[col] resume reconcile: ours t=%d c=%d wait='%s' | peer t=%d c=%d wait='%s'" % [
		turn_no, rng_cursor, _link_wait, pturn, int(peer.get("cursor", -1)), str(peer.get("wait", ""))])
	if absi(pturn - turn_no) > 1:
		print("[col] reconcile: impossible turn gap under lockstep — determinism bug; voiding stakeless")
		b._link_dead()
		return
	if pturn == turn_no and int(peer.get("cursor", -1)) == rng_cursor \
			and str(peer.get("digest", "")) != _det_digest():
		print("[col] reconcile: DIGEST MISMATCH at t=%d c=%d — determinism bug; voiding stakeless" % [
			turn_no, rng_cursor])
		b._link_dead()
		return
	if _link_wait == "act" and link_actions.is_empty() \
			and int(peer.get("act_turn", -2)) == turn_no and str(peer.get("act", "")) != "":
		link_actions.append(str(peer["act"]))
		print("[col] reconcile: recovered the peer's turn-%d action from the resume report" % turn_no)
	if _link_wait == "swap" and link_swaps.is_empty() \
			and int(peer.get("swap_turn", -2)) == turn_no and int(peer.get("swap", -1)) >= 0:
		link_swaps.append(int(peer["swap"]))
		print("[col] reconcile: recovered the peer's turn-%d replacement from the resume report" % turn_no)


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
	var exp_all: bool = b.main.player_bag.has("EXP.ALL")
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
		if str(mon.get("ot", b.main.player_name)) != b.main.player_name:
			e = _boost_exp(e)                 # traded mon: ×1.5 (BoostExp)
		if is_trainer:
			e = _boost_exp(e)                 # trainer battle: ×1.5 (BoostExp)
		var cap: int = b.main.exp_for_level(100, str(mon["growth"]))
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
			and int(mon["exp"]) >= b.main.exp_for_level(int(mon["level"]) + 1, str(mon["growth"])):
		var oldmax := int(mon["maxhp"])
		mon["level"] = int(mon["level"]) + 1
		b.main.recompute_stats(mon)
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
			if not str(mon["moves"][i]["move"]) in b.main.HM_MOVES.values():
				slot = i
				break
		if slot < 0:
			return
		var forgot: String = str(moves_db[str(mon["moves"][slot]["move"])]["name"])
		mon["moves"][slot] = {"move": move, "pp": pp, "maxpp": pp}
		msgs.append("%s forgot %s\nand learned %s!" % [mon["name"], forgot, str(moves_db[move]["name"])])
