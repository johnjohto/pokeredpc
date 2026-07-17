extends "res://scripts/MapScripts.gd"
## scripts/PalletTown.asm — Oak's intercept when heading north without a starter.


## PalletTown_Script's header: entering town after Oak's ball gift arms his dex-rating
## dialog (SetEvent EVENT_PALLET_AFTER_GETTING_POKEBALLS).
func on_enter() -> void:
	if has_event("GOT_POKEBALLS_FROM_OAK"):
		set_event("PALLET_AFTER_GETTING_POKEBALLS")


func on_step(cell: Vector2i) -> bool:
	# Leaving Pallet to the north without a POKéMON triggers Oak's intercept (checks YCoord == 1).
	# Fires before the player crosses into Route 1.
	if cell.y <= 1 and not has_event("GOT_STARTER"):
		main.cutscene.oak_intercept()
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_OAK@8,5":
		return false            # Oak only appears during the intercept cutscene
	return null
