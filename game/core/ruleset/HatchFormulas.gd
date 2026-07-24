extends RulesetFormulas
class_name HatchFormulas
## The Phase-6 formula hatch (gh #66, ADR-028/ADR-030): a script-backed provider behind
## the RulesetFormulas interface. data/ruleset.json's formula_scripts binds kernel names
## to script: records; a bound kernel runs its HatchScript, an unbound kernel delegates
## to the base provider (the ruleset's native formulas). RNG-drawing kernels register
## the battle's draw Callables as the script hosts rand_float()/rand_range(lo,hi)/
## rand_int(n) — scripts control formula math, never draw order. catch_attempt is the
## one dictionary-shaped kernel: its script reports through the out(name, value) host.
## A runtime failure is LOUD (push_error naming script, kernel, and position) and falls
## back to the base kernel — deterministic for identical inputs and draws, and battle
## math never crashes mid-run. Binding errors refuse at BOOT via boot_error.

const KERNELS := ["stat_calc", "exp_for_level", "level_for_exp", "crit_roll",
	"damage_core", "randomize_damage", "accuracy_roll", "stage_apply",
	"special_damage", "catch_attempt"]

var base_formulas: RulesetFormulas
var boot_error := ""     # "" = bindings resolved and parsed; else the boot-fatal refusal
var last_error := ""     # the most recent runtime fallback ("" = clean); tests read this
var _bound := {}         # kernel -> compiled HatchScript
var _names := {}         # kernel -> "script:<id>" (for error messages)


func _init(base: RulesetFormulas, bindings: Dictionary, script_records: Dictionary) -> void:
	base_formulas = base
	var kernels := bindings.keys()
	kernels.sort()
	for kernel_v in kernels:
		var kernel := str(kernel_v)
		if not KERNELS.has(kernel):
			boot_error = "formula_scripts binds unknown kernel '%s' (this build knows %s)" % [
				kernel, ", ".join(KERNELS)]
			return
		var sid := str(bindings[kernel])
		if not sid.begins_with("script:"):
			# The validator's x-ref pass also rejects this; boot must refuse on its
			# own — a project is loadable without ever passing --validate.
			boot_error = "formula_scripts kernel '%s' names '%s' — script references use the script: prefix" % [
				kernel, sid]
			return
		var key := sid.substr("script:".length())
		if not script_records.has(key) or not (script_records[key] is Dictionary):
			boot_error = "formula_scripts kernel '%s' names missing script '%s'" % [kernel, sid]
			return
		var source := str((script_records[key] as Dictionary).get("source", ""))
		var parsed := HatchScript.parse(source)
		if parsed.error != "":
			boot_error = "formula script '%s' (kernel %s): %s" % [sid, kernel, parsed.error]
			return
		_bound[kernel] = parsed
		_names[kernel] = sid


## The bound kernel names, sorted (the play-test probe and the suites report these).
func bound_kernels() -> Array:
	var names := _bound.keys()
	names.sort()
	return names


func stat_calc(base: int, level: int, dv: int, is_hp: bool, sexp := 0) -> int:
	if _bound.has("stat_calc"):
		var v = _run("stat_calc", {"base": base, "level": level, "dv": dv,
			"is_hp": is_hp, "sexp": sexp}, {})
		if v != null:
			return int(v)
	return base_formulas.stat_calc(base, level, dv, is_hp, sexp)


func exp_for_level(n: int, growth: String) -> int:
	if _bound.has("exp_for_level"):
		var v = _run("exp_for_level", {"n": n, "growth": growth}, {})
		if v != null:
			return int(v)
	return base_formulas.exp_for_level(n, growth)


func level_for_exp(xp: int, growth: String) -> int:
	if _bound.has("level_for_exp"):
		var v = _run("level_for_exp", {"xp": xp, "growth": growth}, {})
		if v != null:
			return int(v)
	if _bound.has("exp_for_level"):
		# The inverse must invert the SCRIPTED curve, not the base one (ADR-030): a
		# creator who binds exp_for_level alone gets a consistent level-up threshold.
		var lvl := 1
		while lvl < 100 and exp_for_level(lvl + 1, growth) <= xp:
			lvl += 1
		return lvl
	return base_formulas.level_for_exp(xp, growth)


func crit_roll(base_spd: int, focus: bool, move_name: String, rf: Callable) -> bool:
	if _bound.has("crit_roll"):
		var v = _run("crit_roll", {"base_spd": base_spd, "focus": focus,
			"move_name": move_name}, {"rand_float": func(): return float(rf.call())})
		if v != null:
			return _as_bool(v)
	return base_formulas.crit_roll(base_spd, focus, move_name, rf)


func damage_core(level: int, crit: bool, power: int, a_stat: int, d_stat: int) -> int:
	if _bound.has("damage_core"):
		var v = _run("damage_core", {"level": level, "crit": crit, "power": power,
			"a_stat": a_stat, "d_stat": d_stat}, {})
		if v != null:
			return int(v)
	return base_formulas.damage_core(level, crit, power, a_stat, d_stat)


func randomize_damage(dmg: int, rr: Callable) -> int:
	if _bound.has("randomize_damage"):
		var v = _run("randomize_damage", {"dmg": dmg},
			{"rand_range": func(lo, hi): return int(rr.call(int(lo), int(hi)))})
		if v != null:
			return int(v)
	return base_formulas.randomize_damage(dmg, rr)


func accuracy_roll(accuracy: int, acc_stage: int, eva_stage: int, ri: Callable) -> bool:
	if _bound.has("accuracy_roll"):
		var v = _run("accuracy_roll", {"accuracy": accuracy, "acc_stage": acc_stage,
			"eva_stage": eva_stage}, {"rand_int": func(n): return int(ri.call(int(n)))})
		if v != null:
			return _as_bool(v)
	return base_formulas.accuracy_roll(accuracy, acc_stage, eva_stage, ri)


func stage_apply(base: int, stage: int) -> int:
	if _bound.has("stage_apply"):
		var v = _run("stage_apply", {"base": base, "stage": stage}, {})
		if v != null:
			return int(v)
	return base_formulas.stage_apply(base, stage)


func special_damage(move: String, level: int, rr: Callable) -> int:
	if _bound.has("special_damage"):
		var v = _run("special_damage", {"move": move, "level": level},
			{"rand_range": func(lo, hi): return int(rr.call(int(lo), int(hi)))})
		if v != null:
			return int(v)
	return base_formulas.special_damage(move, level, rr)


func catch_attempt(ball: String, status: String, rate: int, hp: int, maxhp: int,
		ri: Callable) -> Dictionary:
	if _bound.has("catch_attempt"):
		var outs := {}
		_run("catch_attempt", {"ball": ball, "status": status, "rate": rate,
			"hp": hp, "maxhp": maxhp}, {
			"rand_int": func(n): return int(ri.call(int(n))),
			"out": func(name, value): outs[str(name)] = value; return null,
		}, true)
		if last_error == "" and outs.get("caught") is bool and _is_int_like(outs.get("shakes")):
			return {"caught": bool(outs["caught"]), "shakes": int(outs["shakes"])}
		if last_error == "":
			_fallback("catch_attempt",
				"script must out(\"caught\", <bool>) and out(\"shakes\", <int>)")
	return base_formulas.catch_attempt(ball, status, rate, hp, maxhp, ri)


## Run a bound kernel script. A scalar kernel must return a value: null (a runtime
## error, or a script that never returned) means "fall back to the base kernel", with
## last_error set and the failure pushed loudly. Dictionary-shaped kernels pass
## returnless = true and read their out() values instead.
func _run(kernel: String, vars: Dictionary, hosts: Dictionary, returnless := false):
	last_error = ""
	var script: HatchScript = _bound[kernel]
	var v = script.run(vars, hosts)
	if script.error != "":
		_fallback(kernel, script.error)
		return null
	if v == null and not returnless:
		_fallback(kernel, "script returned no value")
		return null
	if not returnless and not (v is bool or v is int or v is float):
		_fallback(kernel, "script returned a %s, not a number or boolean"
			% type_string(typeof(v)))
		return null
	return v


func _fallback(kernel: String, why: String) -> void:
	last_error = "formula script '%s' (kernel %s): %s" % [
		str(_names.get(kernel, "?")), kernel, why]
	push_error("[hatch] %s — falling back to the base kernel" % last_error)


static func _is_int_like(v) -> bool:
	return v is int or (v is float and v == floorf(v))


## _run guarantees v is bool/int/float; a numeric result reads as its truthiness.
static func _as_bool(v) -> bool:
	return v if v is bool else float(v) != 0.0
