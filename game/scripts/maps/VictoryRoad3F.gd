extends "res://scripts/MapScripts.gd"
## scripts/VictoryRoad3F.asm - the boulder-onto-switch door puzzle, and the floor's hole.
##
## `.SwitchOrHoleCoords` names two cells. (3,5) is a floor switch: a boulder on it opens a door. (23,15)
## is a **hole** (cavern tile 0x22) and does double duty — a boulder shoved in vanishes and reappears on
## 2F at (23,16) (`HideObject`/`ShowObject` over the two toggleable boulders), while the *player* stepping
## on it takes the dungeon warp down to **2F (22,16)** (`IsPlayerOnDungeonWarp`, landing cell from
## `DungeonWarpData`). Neither is on the road to the Indigo Plateau — they gate items and a shortcut.

const SWITCHES := [{"sw": Vector2i(3, 5), "ev": "VR3_SWITCH1", "blk": [3, 5, 0x1D]}]
## The boulder's fall: hides this floor's BOULDER4 and shows 2F's BOULDER3, one row below the hole.
const BOULDER_HOLES := [{"cell": Vector2i(23, 15), "ev": "VR3_SWITCH2"}]
## The player's fall (DungeonWarpList / DungeonWarpData: VICTORY_ROAD_2F, 22, 16).
const PLAYER_HOLES := [[Vector2i(23, 15), "VictoryRoad2F", Vector2i(22, 16)]]


func on_enter() -> void:
	switch_doors_enter(SWITCHES)


func on_step(cell: Vector2i) -> bool:
	return dungeon_hole(cell, PLAYER_HOLES)


func boulder_hole(cell: Vector2i) -> bool:
	return hole_at(cell, BOULDER_HOLES)


func on_boulder(cell: Vector2i, npc) -> void:
	boulder_switch(cell, SWITCHES)
	boulder_falls(cell, npc, BOULDER_HOLES)


func object_shown(k: String) -> Variant:
	if k == "SPRITE_BOULDER@22,15":               # TOGGLE_VICTORY_ROAD_3F_BOULDER
		return not has_event("VR3_SWITCH2")
	return null
