extends "res://scripts/MapScripts.gd"
## scripts/SaffronCity.asm - Rockets occupy Saffron until Silph is freed, then leave and the
## residents come back out (toggleable objects).
##
## The two guards outside Silph Co are toggled earlier, and elsewhere: rescuing MR.FUJI on
## Pokémon Tower 7F hides ROCKET8 and shows ROCKET9 (PokemonTower7F.asm, PokemonTower7FMrFujiText).
## That is what opens the building — ROCKET8 stands on (18,22), the only cell from which the door
## at (18,21) can be entered, so until he leaves Silph Co is sealed (gh #79). ROCKET9 takes his
## place one cell east, asleep, and blocks nothing.
const SILPH_GUARD := "SPRITE_ROCKET@18,22"      # ROCKET8: awake, in the doorway
const SILPH_SLEEPER := "SPRITE_ROCKET@19,22"    # ROCKET9: ships OFF, appears once Fuji is safe


func object_shown(k: String) -> Variant:
	if k.begins_with("SPRITE_ROCKET@"):
		# Beating Giovanni clears every grunt out of the city (SilphCo11F.asm .HideToggleableObjectIDs).
		if has_event("BEAT_SILPH_CO_GIOVANNI"):
			return false
		if k == SILPH_GUARD:
			return not has_event("RESCUED_MR_FUJI")
		if k == SILPH_SLEEPER:
			return has_event("RESCUED_MR_FUJI")
		return true
	if k.begins_with("SPRITE_SCIENTIST@") or k.begins_with("SPRITE_SILPH_WORKER_") \
			or k.begins_with("SPRITE_GENTLEMAN@") or k.begins_with("SPRITE_BIRD@") \
			or k.begins_with("SPRITE_ROCKER@"):
		return has_event("BEAT_SILPH_CO_GIOVANNI")
	return null
