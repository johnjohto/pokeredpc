extends RefCounted
class_name Ruleset
## v2 Core (gh #31, ADR-018): the ruleset seam. A Ruleset bundles the five mechanic
## modules the engine core calls through — it knows these INTERFACES, never Gen-1 rules.
## A project's manifest names its ruleset ("gen1"); RulesetRegistry resolves the name to
## a Ruleset whose modules the engine then drives. gh #31 plants the seam with Types
## routed through it as the tracer; Formulas/Battle/Catch/Progression migrate behind
## their interfaces in gh #32–#34 (strangler-fig, `--battledettest` between every move).

var types: RulesetTypes = null
var formulas: RulesetFormulas = null
var battle: RulesetBattle = null
var catching: RulesetCatch = null
var progression: RulesetProgression = null


func id() -> String:
	return ""


## Called once at boot, after ProjectData.open(): build the modules from project data.
func configure() -> void:
	pass


## The Phase-6 formula hatch (gh #66, ADR-028/ADR-030), generic across rulesets: wrap
## the configured formulas provider with the project's script-backed kernels. Bindings
## live in data/ruleset.json's formula_scripts, sources in data/scripts/. Called once
## at boot after configure(); returns "" or the boot-fatal error naming the kernel and
## script (the refuse-newer pattern — a project asking for a kernel this build cannot
## run must never limp into play with the wrong math).
func attach_formula_scripts() -> String:
	var rc := ProjectData.ruleset_config()
	var bindings = rc.get("formula_scripts", {})
	if not (bindings is Dictionary) or (bindings as Dictionary).is_empty():
		return ""
	var wrapped := HatchFormulas.new(formulas, bindings, ProjectData.scripts())
	if wrapped.boot_error != "":
		return wrapped.boot_error
	formulas = wrapped
	return ""
