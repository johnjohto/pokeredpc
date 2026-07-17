extends "res://scripts/MapScripts.gd"
## scripts/SeafoamIslandsB1F.asm - the boulder holes down to B2F (SEAFOAM2 events).

const HOLES := [{"cell": Vector2i(18, 6), "ev": "SEAFOAM2_BOULDER1_DOWN_HOLE"},
	{"cell": Vector2i(23, 6), "ev": "SEAFOAM2_BOULDER2_DOWN_HOLE"}]


func boulder_hole(cell: Vector2i) -> bool:
	return hole_at(cell, HOLES)


func on_boulder(cell: Vector2i, npc) -> void:
	boulder_falls(cell, npc, HOLES)