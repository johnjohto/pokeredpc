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

const TWO_TURN := ["CHARGE_EFFECT", "FLY_EFFECT", "SOLARBEAM"]   # turn 1 charges
# (Battle.gd holds an identical copy until its _do_move users migrate here — wave B)

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
