extends "res://scripts/MapScripts.gd"
## scripts/ViridianMart.asm — the parcel errand: the clerk calls you over on the first visit
## after getting a starter, and won't sell until the parcel reaches Oak.


func on_enter() -> void:
	# The clerk hands over OAK's PARCEL on the first visit after getting a starter.
	if has_event("GOT_STARTER") and not has_event("GOT_OAKS_PARCEL") and not has_event("OAK_GOT_PARCEL"):
		main.cutscene.viridian_mart_parcel()


func on_interact(_front: Vector2i, npc) -> bool:
	# Holding the parcel: the clerk reminds you instead of opening the shop (the asm gates the
	# shop on EVENT_OAK_GOT_PARCEL via a second text table).
	if npc != null and npc.key.begins_with("SPRITE_CLERK@") \
			and has_event("GOT_OAKS_PARCEL") and not has_event("OAK_GOT_PARCEL"):
		face_player(npc)
		say("Okay! Say hi to\nPROF.OAK for me!")
		return true
	return false
