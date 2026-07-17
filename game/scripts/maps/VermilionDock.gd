extends "res://scripts/MapScripts.gd"
## scripts/VermilionDock.asm — stepping off the ship onto the dock with HM01, the S.S. Anne
## sets sail (a purely visual scene that ends by walking the player off the dock). The
## sailor gate makes it a one-time area.


func on_enter() -> void:
	# wDestinationWarpID == 1: the player arrived at the gangway warp (from the ship).
	if has_event("GOT_HM01") and not has_event("SS_ANNE_LEFT") \
			and main.player.cell == Vector2i(14, 2):
		main.cutscene.ss_anne_departs()
