extends RefCounted
class_name RulesetFormulas
## The formula-layer interface (ADR-018 §1, §3): the pure kernels the engine calls —
## stat-calc, exp-curve, crit, damage, accuracy, catch-rate. Stat SELECTION (which stat,
## screens, unmodified-on-crit) is battle-module logic and stays with the battle state;
## these are the arithmetic contracts. Kernels that draw randomness take the battle's
## draw helpers as Callables so implementations control formula math, never draw order.
## The integer-exact expression evaluator (gh #35) is an ALTERNATE provider, proven by
## an equivalence sweep against gen1 — never on gen1's hot path.


## A mon's stat from base / level / DV / stat-exp (HP variant included).
func stat_calc(_base: int, _level: int, _dv: int, _is_hp: bool, _sexp := 0) -> int:
	push_error("[ruleset] RulesetFormulas.stat_calc not implemented")
	return 1


## Total EXP required to be level n under a growth curve.
func exp_for_level(_n: int, _growth: String) -> int:
	push_error("[ruleset] RulesetFormulas.exp_for_level not implemented")
	return 0


## Highest level whose EXP threshold xp has reached (the curve's inverse).
func level_for_exp(_xp: int, _growth: String) -> int:
	push_error("[ruleset] RulesetFormulas.level_for_exp not implemented")
	return 1


## Whether this hit is a critical, from the attacker's base speed + volatile state.
func crit_roll(_base_spd: int, _focus: bool, _move_name: String, _rf: Callable) -> bool:
	push_error("[ruleset] RulesetFormulas.crit_roll not implemented")
	return false


## The damage pipeline's arithmetic core: level/crit + power + the two chosen stats.
func damage_core(_level: int, _crit: bool, _power: int, _a_stat: int, _d_stat: int) -> int:
	push_error("[ruleset] RulesetFormulas.damage_core not implemented")
	return 0


## The final damage randomization.
func randomize_damage(dmg: int, _rr: Callable) -> int:
	push_error("[ruleset] RulesetFormulas.randomize_damage not implemented")
	return dmg


## Whether a move hits, from its accuracy and the accuracy/evasion stages.
func accuracy_roll(_accuracy: int, _acc_stage: int, _eva_stage: int, _ri: Callable) -> bool:
	push_error("[ruleset] RulesetFormulas.accuracy_roll not implemented")
	return true


## A stat under a stage modifier.
func stage_apply(base: int, _stage: int) -> int:
	push_error("[ruleset] RulesetFormulas.stage_apply not implemented")
	return base


## Fixed-damage moves' damage.
func special_damage(_move: String, level: int, _rr: Callable) -> int:
	push_error("[ruleset] RulesetFormulas.special_damage not implemented")
	return level


## One catch attempt: ball + target status/rate/hp → {caught: bool, shakes: int}.
func catch_attempt(_ball: String, _status: String, _rate: int, _hp: int, _maxhp: int,
		_ri: Callable) -> Dictionary:
	push_error("[ruleset] RulesetFormulas.catch_attempt not implemented")
	return {"caught": false, "shakes": 0}
