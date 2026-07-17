extends "res://scripts/MapScripts.gd"
## scripts/VermilionCity.asm — the sailor gates the S.S. Anne dock on the S.S.TICKET.
##
## VermilionCityDefaultScript fires when the player stands on `SSAnneTicketCheckCoords` = (18,30) **facing
## down** — the tile just north of the dock warp, beside the sailor at (19,30). With the ticket he waves you
## aboard; without it (or once the ship has sailed) he turns you back with a simulated PAD_UP. The port used
## to run this off the dock warp tile itself (18,31), so the text popped a tile too far south (gh #115).


func on_step(cell: Vector2i) -> bool:
	if cell != Vector2i(18, 30) or main.player.facing != 0:   # only walking DOWN onto the sailor's tile
		return false
	if has_event("SS_ANNE_LEFT"):
		_sailor("The S.S.ANNE has\nalready departed.", true)
		return true
	if not has_event("GOT_SS_TICKET"):
		_sailor("I'm sorry. You\nneed a TICKET to\nboard the ship.", true)
		return true
	_sailor("", false)                                        # has the ticket: board_ss_anne says its own line
	return true


## The sailor speaks; `turn_away` pushes the player back up a tile (no ticket / ship gone), otherwise the
## ticket checks out and board_ss_anne waves us onto the dock (and sets last_outside_map for the exit warp).
func _sailor(text: String, turn_away: bool) -> void:
	main.cutscene_active = true
	if turn_away:
		await main.cutscene.say(text)
		await main.player.step(1)                             # UP — pokered's simulated PAD_UP
		main.cutscene_active = false
		return
	main.cutscene_active = false
	main.cutscene.board_ss_anne("VermilionDock", 0)           # VERMILION_DOCK, warp 1 (0-based 0 = the dock top)
