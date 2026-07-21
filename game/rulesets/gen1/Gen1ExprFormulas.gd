extends Gen1Formulas
class_name Gen1ExprFormulas
## The ALTERNATE formula provider (gh #35, ADR-018 §3): the Gen-1 kernels that pure
## arithmetic can express, authored as FormulaExpr expressions — stat_calc, the four
## growth curves, and damage_core (its /4 byte-overflow branch via if()). Never on
## gen1's hot path: gen1 ships native; this class exists to PROVE the expression
## system reproduces the native outputs exactly (the --exprtest equivalence sweep).
## Kernels that draw RNG or walk tables (crit, accuracy, catch, stages) inherit the
## native implementations.

const SRC_STAT_CALC := "int(((base + dv) * 2 + int(min(255, ceil(sqrt(sexp)))) / 4) * level / 100.0) + if(is_hp, level + 10, 5)"
const SRC_EXP := {
	"GROWTH_FAST": "int(4 * n * n * n / 5.0)",
	"GROWTH_SLOW": "int(5 * n * n * n / 4.0)",
	"GROWTH_MEDIUM_SLOW": "int(6.0 * n * n * n / 5.0 - 15 * n * n + 100 * n - 140)",
	"GROWTH_MEDIUM_FAST": "n * n * n",
}
const SRC_DAMAGE_CORE := "min((int((2 * (level * if(crit, 2, 1))) / 5) + 2) * power" \
	+ " * if(a_stat > 255 or d_stat > 255, max(1, a_stat / 4), a_stat)" \
	+ " / max(1, if(a_stat > 255 or d_stat > 255, max(1, d_stat / 4), d_stat)) / 50, 997) + 2"

var _e_stat: FormulaExpr
var _e_exp: Dictionary = {}
var _e_dmg: FormulaExpr


func _init() -> void:
	_e_stat = FormulaExpr.parse(SRC_STAT_CALC)
	for g in SRC_EXP:
		_e_exp[g] = FormulaExpr.parse(SRC_EXP[g])
	_e_dmg = FormulaExpr.parse(SRC_DAMAGE_CORE)
	for e in [_e_stat, _e_dmg, _e_exp["GROWTH_FAST"], _e_exp["GROWTH_SLOW"],
			_e_exp["GROWTH_MEDIUM_SLOW"], _e_exp["GROWTH_MEDIUM_FAST"]]:
		if (e as FormulaExpr).error != "":
			push_error("[expr] gen1 expression failed to parse: " + (e as FormulaExpr).error)


func stat_calc(base: int, level: int, dv: int, is_hp: bool, sexp := 0) -> int:
	return int(_e_stat.eval({"base": base, "level": level, "dv": dv,
		"is_hp": is_hp, "sexp": sexp}))


func exp_for_level(n: int, growth: String) -> int:
	var e: FormulaExpr = _e_exp.get(growth, _e_exp["GROWTH_MEDIUM_FAST"])
	return int(e.eval({"n": n}))


func damage_core(level: int, crit: bool, power: int, a_stat: int, d_stat: int) -> int:
	return int(_e_dmg.eval({"level": level, "crit": crit, "power": power,
		"a_stat": a_stat, "d_stat": d_stat}))
