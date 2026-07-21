extends "res://scripts/MapScripts.gd"
## The generic adapter for maps whose story is AUTHORED EVENTS (ADR-019, gh #39):
## Main.map_script() returns this — instead of a hand-written scripts/maps/<Label>.gd —
## when the project carries events for the label. The eight hooks stay Main's contract,
## so the dispatch order (and map-scripts.md's two faithfulness rules) hold by
## construction; events plug in behind them. A hand-written .gd, if one still exists,
## wins over events during a migration wave (map_script warns about the overlap).

var label := ""


func on_interact(_front: Vector2i, npc) -> bool:
	if npc == null:
		return false
	var rec = main.event_vm.interact_event(label, str(npc.key))
	if rec == null:
		return false
	face_player(npc)
	main.event_vm.run(rec)
	return true


func object_shown(k: String) -> Variant:
	return main.event_vm.visible_for(label, k)
