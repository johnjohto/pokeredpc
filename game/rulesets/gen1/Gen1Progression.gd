extends RulesetProgression
class_name Gen1Progression
## The Gen-1 progression module (gh #34, ADR-018 §1): progression FLAGS are the badges,
## and the two gate mappings that were already data are config-driven — which badge
## boosts which battle stat (BadgeStatBoosts' even bit positions), and which badge
## unlocks each field move outside battle. Defaults are the faithful gen1 values;
## data/ruleset.json's config overrides them (ADR-018 §4).

var _badge_stat := {"atk": "BOULDERBADGE", "def": "THUNDERBADGE",
	"spd": "SOULBADGE", "spc": "VOLCANOBADGE"}
var _field_move_badge := {"CUT": "CASCADEBADGE", "FLASH": "BOULDERBADGE",
	"STRENGTH": "RAINBOWBADGE", "SURF": "SOULBADGE", "FLY": "THUNDERBADGE"}


func _init(cfg: Dictionary = {}) -> void:
	if cfg.get("badge_stat_boosts") is Dictionary and not (cfg["badge_stat_boosts"] as Dictionary).is_empty():
		_badge_stat = cfg["badge_stat_boosts"]
	if cfg.get("field_move_badges") is Dictionary and not (cfg["field_move_badges"] as Dictionary).is_empty():
		_field_move_badge = cfg["field_move_badges"]


## The progression flag (badge) that boosts this battle stat key, "" for none.
func badge_for_stat(stat: String) -> String:
	return str(_badge_stat.get(stat, ""))


## The progression flag (badge) gating this field move outside battle, "" for none.
func badge_for_field_move(move: String) -> String:
	return str(_field_move_badge.get(move, ""))