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

# Gen-1 badge stat boosts, by the EVEN BIT POSITIONS of wObtainedBadges (BadgeStatBoosts):
# Boulder (bit 0) -> ATTACK, Thunder (bit 2) -> DEFENSE, Soul (bit 4) -> SPEED,
# Volcano (bit 6) -> SPECIAL. (Not the intuitive gym order - Cascade boosts nothing.)
const _BADGE_STAT := {"atk": "BOULDERBADGE", "def": "THUNDERBADGE", "spd": "SOULBADGE", "spc": "VOLCANOBADGE"}

const SPECIAL_TYPES := ["FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE", "DRAGON"]
const STAT_KEY := {"ATTACK": "atk", "DEFENSE": "def", "SPECIAL": "spc",
	"SPEED": "spd", "ACCURACY": "acc", "EVASION": "eva"}
const TWO_TURN := ["CHARGE_EFFECT", "FLY_EFFECT", "SOLARBEAM"]   # turn 1 charges
const _VANISH_CHARGE := ["DIG", "FLY"]          # ...and these two go out of sight while they do (gh #122)
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
	if b.main and str(_BADGE_STAT.get(key, "")) in b.main.badges:
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
	# The byte-exact ItemUseBall algorithm is the ruleset's catch_attempt kernel (gh #32).
	var rate := rate_override if rate_override >= 0 \
		else int(base_stats[enemy_mon["species"]]["catch"])
	return rset.formulas.catch_attempt(ball, str(enemy_mon["status"]), rate,
		int(enemy_mon["hp"]), int(enemy_mon["maxhp"]), _ri)
