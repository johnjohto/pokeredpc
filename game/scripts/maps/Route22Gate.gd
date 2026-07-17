extends "res://scripts/MapScripts.gd"
## scripts/Route22Gate.asm — the way north to Route 23 / the League needs the BOULDERBADGE, and this is
## the one gate house in Kanto entered from two *different* maps (Route 22 to the south, Route 23 to the
## north). All four of its doors are `LAST_MAP` warps, so pokered's script re-picks `wLastMap` from the
## half of the building the player stands in — `ld a, [wYCoord] / cp 4 / jr c` → ROUTE_23 above the
## counter, ROUTE_22 below it. Without that the north door leads back the way you came and Route 23 —
## with it Victory Road, the Elite Four and the Hall of Fame — is unreachable on foot (gh #87).


func on_step(cell: Vector2i) -> bool:
	main.last_outside_map = "Route23" if cell.y < 4 else "Route22"
	if (cell == Vector2i(4, 2) or cell == Vector2i(5, 2)) and "BOULDERBADGE" not in main.badges:
		bounce_back(cell)
		sfx("denied")
		say("Only truly skilled\ntrainers are\nallowed through.\fThe rules are the\nrules. I can't\nlet you pass!")
		return true
	return false
