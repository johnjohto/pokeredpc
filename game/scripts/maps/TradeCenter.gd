extends "res://scripts/MapScripts.gd"
## The Cable Club Trade Center (gh #6, ADR-014; scripts/TradeCenter.asm +
## engine/link/cable_club.asm). The partner's avatar sits in the opposite chair
## (TradeCenter_Script repositions TRADECENTER_OPPONENT); pressing A into the table —
## its two center cells, between the seats at (3,4)/(6,4) — or at the partner opens the
## trade flow (`Cutscene.trade_center_table`). Walking onto the doormat row leaves the
## club: the link closes and the player is back beside the attendant.

const TABLE := [Vector2i(4, 4), Vector2i(5, 4)]


func on_enter() -> void:
	main.club_room_enter()


func on_step(cell: Vector2i) -> bool:
	return main.club_room_step(cell)


func on_interact(front: Vector2i, npc) -> bool:
	if npc != null or front in TABLE:
		main.cutscene.trade_center_table()
		return true
	return false
