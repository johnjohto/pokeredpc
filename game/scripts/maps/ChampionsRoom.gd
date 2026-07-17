extends "res://scripts/MapScripts.gd"
## scripts/ChampionsRoom.asm - the final rival battle -> Hall of Fame; Oak only walks in after
## you take the title.
##
## Walking in is the trigger, not talking: beating AGATHA arms this room's entry script
## (`AgathasRoomAgathaEndBattleScript` writes SCRIPT_CHAMPIONSROOM_PLAYER_ENTERS), and the next load
## marches the player up to the rival. Without it he can be walked around — the Hall of Fame stairs at
## (3,0)/(4,0) are reachable from the door. Talking still works, for a save resumed inside the room.


func on_enter() -> void:
	if has_event("CHAMPION_ROOM_ENTRY") and not has_event("BEAT_CHAMPION"):
		clear_event("CHAMPION_ROOM_ENTRY")        # the armed script pointer is consumed by the walk-in
		main.cutscene.champion_entrance()


func on_interact(_front: Vector2i, npc) -> bool:
	if npc != null and npc.key == "SPRITE_BLUE@4,2" and not has_event("BEAT_CHAMPION"):
		face_player(npc)
		main.cutscene.champion_battle()
		return true
	return false


func object_shown(k: String) -> Variant:
	if k == "SPRITE_OAK@3,7":
		# TOGGLE_CHAMPIONS_ROOM_OAK ships hidden; the ceremony ShowObjects him mid-scene and
		# HideObjects him on his exit (gh #179) — at load he is never standing at the door.
		return false
	return null
