extends "res://scripts/MapScripts.gd"
## scripts/SeafoamIslandsB3F.asm - the boulder holes down to B4F (SEAFOAM4 events).

const HOLES := [{"cell": Vector2i(3, 16), "ev": "SEAFOAM4_BOULDER1_DOWN_HOLE"},
	{"cell": Vector2i(6, 16), "ev": "SEAFOAM4_BOULDER2_DOWN_HOLE"}]


func boulder_hole(cell: Vector2i) -> bool:
	return hole_at(cell, HOLES)


func on_boulder(cell: Vector2i, npc) -> void:
	boulder_falls(cell, npc, HOLES)