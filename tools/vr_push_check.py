#!/usr/bin/env python
# gh #105 regression check: confirm every boulder shove in the Victory Road route is legal under pokered's
# faithful push-collision rule. CheckForCollisionWhenPushingBoulder (engine/overworld/player_state.asm) calls
# CheckForTilePairCollisions2 against TilePairCollisionsLand, comparing the PLAYER's feet tile (screen 8,9)
# to the tile TWO steps ahead (the boulder's destination). A push is refused on a tile-pair (elevation)
# mismatch between those two tiles, or onto a stairs tile ($15). This mirrors try_push_boulder in Main.gd.
#
# If this prints "0 of N pushes would be BLOCKED", the hard-coded route in _pt_climb_victory_road is
# faithful-compatible and needs no change. Re-run if the route (_PT_VR*_PUSHES) is ever retuned.
import json
R = "game/assets"
NAME = {"1F": "VictoryRoad1F", "2F": "VictoryRoad2F", "3F": "VictoryRoad3F"}
PAIRS = [(0x20, 0x05), (0x41, 0x05), (0x2a, 0x05), (0x05, 0x21)]  # cavern TilePairCollisionsLand
SUB = [[4, 6], [12, 14]]
DV = {0: (0, 1), 1: (0, -1), 2: (-1, 0), 3: (1, 0)}              # DOWN UP LEFT RIGHT
DN = {0: "DOWN", 1: "UP", 2: "LEFT", 3: "RIGHT"}


def feetfn(f):
    m = json.load(open(f'{R}/maps/{NAME[f]}.json'))
    ts = json.load(open(f"{R}/tilesets/{m['tileset']}.json"))
    bd = ts.get('blockset', ts.get('blocks'))
    return lambda c: bd[m['blocks'][c[1] // 2][c[0] // 2]][SUB[c[1] % 2][c[0] % 2]]


def pair(a, b):
    return any((a == x and b == y) or (a == y and b == x) for x, y in PAIRS)


# The route driven by _pt_climb_victory_road (Main.gd), per floor: [start(x,y), dir, times].
ROUTE = {
    "1F": [[(5, 15), 0, 1], [(5, 16), 3, 3], [(8, 16), 1, 1], [(8, 15), 3, 1], [(9, 15), 1, 1],
           [(9, 14), 3, 7], [(16, 14), 1, 2], [(16, 12), 3, 1], [(17, 12), 0, 1]],
    "2F": [[(4, 14), 0, 1], [(4, 15), 2, 1], [(3, 15), 0, 1], [(3, 16), 2, 2],   # switch1
           [(23, 16), 2, 14]],                                                   # switch2 (post hole-drop)
    "3F": [[(22, 3), 1, 2], [(22, 1), 2, 16], [(6, 1), 0, 1], [(6, 2), 2, 4], [(2, 2), 0, 3], [(2, 5), 3, 1],
           [(22, 15), 3, 1]],                                                    # last: into the hole (exempt)
}
HOLE = {"3F": (23, 15)}

bad = total = 0
for f, pushes in ROUTE.items():
    feet = feetfn(f)
    for start, d, times in pushes:
        dv = DV[d]
        b = list(start)
        for _ in range(times):
            player = (b[0] - dv[0], b[1] - dv[1])
            dest = (b[0] + dv[0], b[1] + dv[1])
            total += 1
            fp, fd = feet(player), feet(dest)
            is_hole = f in HOLE and dest == HOLE[f]
            blk = (pair(fp, fd) or fd == 0x15) and not is_hole   # elevation pair, or stairs dest
            tag = "  HOLE(exempt)" if is_hole else ("  <<< BLOCKED by pokered!" if blk else "")
            bad += 1 if blk else 0
            print(f"[{f}] push {DN[d]:5} boulder{tuple(b)} player{player} feet=${fp:02x} -> "
                  f"dest{dest} feet=${fd:02x}{tag}")
            b = [b[0] + dv[0], b[1] + dv[1]]
print(f"\n=== {bad} of {total} pushes would be BLOCKED under pokered's faithful rule ===")
raise SystemExit(1 if bad else 0)
