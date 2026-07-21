extends "res://scripts/MapScripts.gd"
## The generic adapter for maps whose story is AUTHORED EVENTS (ADR-019, gh #39/#40):
## Main.map_script() returns this — instead of a hand-written scripts/maps/<Label>.gd —
## when the project carries events for the label. The eight hooks stay Main's contract,
## so the dispatch order (and map-scripts.md's two faithfulness rules) hold by
## construction; events plug in behind them. A hand-written .gd, if one still exists,
## wins over events during a migration wave (map_script warns about the overlap).

var label := ""


func on_enter() -> void:
	main.event_vm.run_enter(label)


func on_step(cell: Vector2i) -> bool:
	return main.event_vm.step_fire(label, cell)


func on_interact(front: Vector2i, npc) -> bool:
	return main.event_vm.interact_fire(label, front, npc)


func on_battle_end() -> void:
	main.event_vm.run_battle_end(label)


func on_warp(w: Dictionary, _dest_const: String, dest_label: String) -> bool:
	return main.event_vm.warp_fire(label, w, dest_label)


func boulder_hole(cell: Vector2i) -> bool:
	return main.event_vm.boulder_hole_at(label, cell)


func on_boulder(cell: Vector2i, npc) -> void:
	main.event_vm.run_boulder(label, cell, npc)


func object_shown(k: String) -> Variant:
	return main.event_vm.visible_for(label, k)
