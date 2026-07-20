extends RefCounted
class_name RulesetFormulas
## The formula-layer interface (ADR-018 §1, §3): damage, accuracy, crit, catch-rate,
## stat-calc, and exp-curve as a provider the engine calls. gh #32 migrates the fused
## formulas (Battle.gd's _do_damage_move/_calc_hit/_attempt_catch, Main.gd's stat/exp
## code) into gen1's native implementation and pins the method signatures here as each
## lands. The integer-exact expression evaluator (gh #35) is an ALTERNATE provider,
## proven by an equivalence sweep against gen1 — never on gen1's hot path.
