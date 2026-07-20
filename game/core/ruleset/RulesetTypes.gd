extends RefCounted
class_name RulesetTypes
## The type/effectiveness module interface (ADR-018 §1): a data-defined type chart plus
## the resolver the battle core asks. Implementations own their chart; the engine never
## reads it directly.


## The composed multiplier of `move_type` against a defender's two stored types
## (Gen-1 stores a mono-type mon as TYPE,TYPE — implementations must not double-count).
func eff(_move_type: String, _def_types: Array) -> float:
	push_error("[ruleset] RulesetTypes.eff not implemented")
	return 1.0


## The single-entry chart multiplier of one attacking type against one defending type.
func mult(_atk_type: String, _def_type: String) -> float:
	push_error("[ruleset] RulesetTypes.mult not implemented")
	return 1.0


## The chart row for an attacking type, in TABLE ORDER — Gen-1's damage loop applies each
## matching entry with its own floor, in order, so iteration order is behavior. Scaffolding
## for gh #31/#32: once the damage formula lives inside the ruleset (gh #32) the raw row
## need not cross the seam and this accessor can retire.
func row(_move_type: String) -> Dictionary:
	push_error("[ruleset] RulesetTypes.row not implemented")
	return {}
