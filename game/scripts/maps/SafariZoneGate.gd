extends "res://scripts/MapScripts.gd"
## scripts/SafariZoneGate.asm - pay the 500 fee before entering the park.


func on_warp(w: Dictionary, dest_const: String, dest_label: String) -> bool:
	if dest_const == "SAFARI_ZONE_CENTER" and not main.in_safari:
		main.cutscene.safari_gate(dest_label, int(w["dest_warp"]) - 1)
		return true
	return false