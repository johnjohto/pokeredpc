extends "res://scripts/MapScripts.gd"
## scripts/BikeShop.asm — the clerk trades the BIKE VOUCHER for the BICYCLE.


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_BIKE_SHOP_CLERK@6,2":
		face_player(npc)
		main.cutscene.bike_shop_clerk()
		return true
	return false
