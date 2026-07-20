extends RefCounted
class_name RulesetRegistry
## The built-in ruleset registry (gh #31, ADR-018 §1): resolves a project manifest's
## `ruleset` string to a Ruleset. Unknown names return null — the CALLER refuses,
## naming both the asked-for ruleset and the ones this build knows (the link-identity /
## refuse-newer pattern applied to mechanics).

const _BUILTIN := {
	"gen1": "res://rulesets/gen1/Gen1Ruleset.gd",
}


static func resolve(rid: String) -> Ruleset:
	if not _BUILTIN.has(rid):
		return null
	var rs: Ruleset = load(_BUILTIN[rid]).new()
	return rs


static func known() -> String:
	var names := _BUILTIN.keys()
	names.sort()
	return ", ".join(names)
