extends Ruleset
class_name Gen1Ruleset
## The built-in, asm-faithful Gen-1 ruleset (gh #31, ADR-018). Types (gh #31) and the
## formula kernels (gh #32) are live behind the seam; Battle/Catch/Progression stay in
## the fused code until gh #33–#34 migrate them here module by module, `--battledettest`
## md5s checked between every move.


func id() -> String:
	return "gen1"


func configure() -> void:
	# data/ruleset.json (ADR-018 §4, gh #34): base must match the manifest's selector;
	# config overrides the built-in faithful defaults, absent keys keep them.
	var rc := ProjectData.ruleset_config()
	if not rc.is_empty() and str(rc.get("base", "gen1")) != "gen1":
		push_error("[ruleset] data/ruleset.json base '%s' does not match the manifest ruleset 'gen1'"
			% str(rc.get("base")))
	var cfg: Dictionary = rc.get("config", {}) if rc.get("config") is Dictionary else {}
	types = Gen1Types.new(ProjectData.legacy("types.json"))
	formulas = Gen1Formulas.new()
	formulas.apply_config(cfg)
	battle = Gen1Battle.new()
	battle.rset = self
	catching = Gen1Catch.new()
	catching.rset = self
	progression = Gen1Progression.new(cfg)
