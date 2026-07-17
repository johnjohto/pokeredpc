extends "res://scripts/MapScripts.gd"
## scripts/SeafoamIslandsB2F.asm - the boulder holes down to B3F (SEAFOAM3 events).

const HOLES := [{"cell": Vector2i(19, 6), "ev": "SEAFOAM3_BOULDER1_DOWN_HOLE"},
	{"cell": Vector2i(22, 6), "ev": "SEAFOAM3_BOULDER2_DOWN_HOLE"}]


func boulder_hole(cell: Vector2i) -> bool:
	return hole_at(cell, HOLES)


func on_boulder(cell: Vector2i, npc) -> void:
	boulder_falls(cell, npc, HOLES)