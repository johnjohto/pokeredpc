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
