extends Ruleset
class_name Gen1Ruleset
## The built-in, asm-faithful Gen-1 ruleset (gh #31, ADR-018). gh #31 is the delegating
## skeleton: Types is live (the tracer through the seam); Formulas/Battle/Catch/
## Progression stay in the fused code until gh #32–#34 migrate them here module by
## module, `--battledettest` md5s checked between every move.


func id() -> String:
	return "gen1"


func configure() -> void:
	types = Gen1Types.new(ProjectData.legacy("types.json"))
