extends "res://scripts/MapScripts.gd"
## scripts/SilphCo1F.asm — the receptionist arrives once Silph is freed.


func object_shown(k: String) -> Variant:
	if k == "SPRITE_LINK_RECEPTIONIST@4,2":
		return has_event("BEAT_SILPH_CO_GIOVANNI")
	return null
