extends Ruleset
class_name Gen1Ruleset
## The built-in, asm-faithful Gen-1 ruleset (gh #31, ADR-018). Types (gh #31) and the
## formula kernels (gh #32) are live behind the seam; Battle/Catch/Progression stay in
## the fused code until gh #33–#34 migrate them here module by module, `--battledettest`
## md5s checked between every move.


func id() -> String:
	return "gen1"


func configure() -> void:
	types = Gen1Types.new(ProjectData.legacy("types.json"))
	formulas = Gen1Formulas.new()
	battle = Gen1Battle.new()
