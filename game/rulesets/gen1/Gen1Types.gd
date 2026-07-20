extends RulesetTypes
class_name Gen1Types
## Gen-1's type resolver, moved verbatim from Battle.gd behind the seam (gh #31).
## The chart is the project's data/types.json rebuilt to v1 shape by ProjectData
## (TYPE-const keys, PSYCHIC stored as PSYCHIC_TYPE).

var _chart: Dictionary = {}


func _init(chart: Dictionary) -> void:
	_chart = chart


## The type multiplier exactly as AdjustDamageForMoveType composes it: each TypeEffects table
## entry for the move's type fires ONCE if it matches either defender type — a pure-type mon
## (stored TYPE,TYPE) is not double-counted (gh #176 phase 2).
func eff(move_type: String, def_types: Array) -> float:
	var e := 1.0
	var row: Dictionary = _chart.get(move_type, {})
	for dt in row:
		if str(def_types[0]) == dt or str(def_types[1]) == dt:
			e *= float(row[dt])
	return e


func mult(atk_type: String, def_type: String) -> float:
	return float(_chart.get(atk_type, {}).get(def_type, 1.0))


func row(move_type: String) -> Dictionary:
	return _chart.get(move_type, {})
