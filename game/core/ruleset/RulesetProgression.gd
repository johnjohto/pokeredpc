extends RefCounted
class_name RulesetProgression
## The progression-module interface (ADR-018 §1): progression FLAGS + GATE CONDITIONS —
## the generalization of v1's badges and HM-use gates (gh #34).


## The progression flag that boosts this battle stat key ("" = none).
func badge_for_stat(_stat: String) -> String:
	push_error("[ruleset] RulesetProgression.badge_for_stat not implemented")
	return ""


## The progression flag gating this field move outside battle ("" = none).
func badge_for_field_move(_move: String) -> String:
	push_error("[ruleset] RulesetProgression.badge_for_field_move not implemented")
	return ""
