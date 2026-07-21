extends RefCounted
class_name RulesetCatch
## The catch-module interface (ADR-018 §1): ball + target state → caught / shake count,
## plus the safari catch-rate transitions (gh #34).


## One ball attempt: {caught: bool, shakes: int}. `ri` is the battle's draw helper —
## implementations own the math, never the draw order.
func attempt(_ball: String, _status: String, _rate: int, _hp: int, _maxhp: int,
		_ri: Callable) -> Dictionary:
	push_error("[ruleset] RulesetCatch.attempt not implemented")
	return {"caught": false, "shakes": 0}


## The working catch rate after throwing bait / a rock.
func bait_rate(catch_rate: int) -> int:
	push_error("[ruleset] RulesetCatch.bait_rate not implemented")
	return catch_rate


func rock_rate(catch_rate: int) -> int:
	push_error("[ruleset] RulesetCatch.rock_rate not implemented")
	return catch_rate
