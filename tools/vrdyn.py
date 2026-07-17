#!/usr/bin/env python
# Dynamic cross-floor Victory Road solver (gh #105). Finds the boulder-push + ladder route from the 1F
# entrance to the Route 23 exit, modelling the whole dungeon at once:
#   - boulders RESET to start positions each time you (re)enter a floor; only switch/hole EVENT flags
#     persist (and open their blocks permanently),
#   - a boulder pushed onto a switch sets that switch's flag (opens a block); a boulder pushed into the
#     3F hole (23,15) sets VR3b (2F boulder (23,16) appears, 3F boulder (22,15) is gone),
#   - the 3F hole also warps the PLAYER down to 2F(22,16),
#   - tile-pair collisions block the player's steps but NOT pushes; ladder warp-tiles aren't standable,
#     edge/entrance warps are (they only fire facing the map edge, gh #80),
#   - ladders land at the dest map's warps[dest_warp-1].
# Prints the sequence of (floor, action) to wire into _pt_climb_victory_road.
import json
from collections import deque

R = "game/assets"
NAME = {"1F": "VictoryRoad1F", "2F": "VictoryRoad2F", "3F": "VictoryRoad3F"}
PAIRS = [(0x20, 0x05), (0x41, 0x05), (0x2A, 0x05), (0x05, 0x21)]
WT = {0x18, 0x1a, 0x22}                       # ladder warp-tiles (immediate warp; not standable)
SUB = [[4, 6], [12, 14]]

# switch cell -> (flag, opened block bx,by); per floor
SWITCH = {"1F": {(17, 13): ("VR1", (4, 6))},
          "2F": {(1, 16): ("VR2a", (3, 4)), (9, 16): ("VR2b", (11, 7))},
          "3F": {(3, 5): ("VR3a", (3, 5))}}
HOLE = {"3F": (23, 15)}                        # boulder->VR3b ; player-> 2F(22,16)
HOLE_PLAYER_DEST = ("2F", (22, 16))
EXITS = {"2F": {(29, 7), (29, 8)}}             # -> Route 23 (the goal)

def load(f):
    m = json.load(open(f'{R}/maps/{NAME[f]}.json')); ts = json.load(open(f"{R}/tilesets/{m['tileset']}.json"))
    bd = ts['blocks']; walk = set(ts['walkable_tiles']); W, H = m['width'], m['height']
    feet = lambda c: bd[m['blocks'][c[1] // 2][c[0] // 2]][SUB[c[1] % 2][c[0] % 2]]
    warps = m['warps']
    return {'feet': feet, 'walk': walk, 'CW': W * 2, 'CH': H * 2, 'warps': warps,
            'warpset': {(w['x'], w['y']) for w in warps}}
M = {f: load(f) for f in NAME}
# resolve each floor's VR-internal ladders: cell -> (dest_floor, landing cell)  [dest_warp is 1-based]
DESTF = {"VictoryRoad1F": "1F", "VictoryRoad2F": "2F", "VictoryRoad3F": "3F"}
LADDERS = {}
for f in NAME:
    d = {}
    for w in M[f]['warps']:
        dm = w.get('dest_map')
        if dm in DESTF:
            df = DESTF[dm]; land = M[df]['warps'][w['dest_warp'] - 1]
            d[(w['x'], w['y'])] = (df, (land['x'], land['y']))
    LADDERS[f] = d
ALLB = {f: [(o['x'], o['y']) for o in json.load(open(f'{R}/maps/{NAME[f]}.json'))['object_events']
            if o['sprite'] == 'SPRITE_BOULDER'] for f in NAME}

def boulders_of(f, flags):
    bs = set(ALLB[f])
    if f == "2F" and "VR3b" not in flags: bs.discard((23, 16))
    if f == "3F" and "VR3b" in flags: bs.discard((22, 15))
    return frozenset(bs)

def opened(f, flags):
    oc = set()
    for cell, (flag, (bx, by)) in SWITCH[f].items():
        if flag in flags:
            for sx in (0, 1):
                for sy in (0, 1): oc.add((bx * 2 + sx, by * 2 + sy))
    return oc

def tpblk(f, a, b):
    feet = M[f]['feet']; s, t = feet(a), feet(b)
    return any((s == x and t == y) or (s == y and t == x) for x, y in PAIRS)

def standable(f, c, boulders, oc):
    x, y = c; d = M[f]
    if c in oc: return c not in boulders
    if not (0 <= x < d['CW'] and 0 <= y < d['CH'] and d['feet'](c) in d['walk']): return False
    if c in boulders: return False
    if c in d['warpset'] and d['feet'](c) in WT: return False       # ladder warp-tile: warps on step
    return True

def region(f, player, boulders, oc):
    seen = {player}; q = deque([player])
    while q:
        c = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + dx, c[1] + dy)
            if n in seen or not standable(f, n, boulders, oc): continue
            if not (n in oc or c in oc) and tpblk(f, c, n): continue
            seen.add(n); q.append(n)
    return seen

def norm(reg): return min(reg)

def solve():
    start_flags = frozenset()
    start = ("1F", start_flags, boulders_of("1F", start_flags), (8, 16))
    def state_of(f, flags, boulders, player):
        oc = opened(f, flags); reg = region(f, player, boulders, oc)
        return (f, flags, boulders, norm(reg)), reg, oc
    s0, reg0, oc0 = state_of(*start)
    seen = {s0}; q = deque([(s0, reg0, oc0, [])])
    import sys
    n = 0
    while q:
        n += 1
        if n % 200000 == 0:
            print("  ...%d states, |seen|=%d, qlen=%d" % (n, len(seen), len(q)), file=sys.stderr)
        if n > 8000000:
            print("  (state cap hit)", file=sys.stderr); return None
        (f, flags, boulders, pnorm), reg, oc, path = q.popleft()
        # GOAL: an exit warp adjacent to the player region
        for ex in EXITS.get(f, ()):
            if any((ex[0] + dx, ex[1] + dy) in reg for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                return path + [(f, "EXIT %s->Route23" % (ex,))]
        # PUSH each boulder
        for b in boulders:
            for d, (dx, dy) in {0: (0, 1), 1: (0, -1), 2: (-1, 0), 3: (1, 0)}.items():
                behind = (b[0] - dx, b[1] - dy); ahead = (b[0] + dx, b[1] + dy)
                if behind not in reg: continue
                ax, ay = ahead
                is_hole = (f in HOLE and ahead == HOLE[f])
                if not is_hole:
                    # ahead must be a place a boulder can rest: walkable floor or a switch cell (not a wall/ladder/other boulder)
                    if ahead in boulders: continue
                    d2 = M[f]
                    okrest = (ahead in oc) or (0 <= ax < d2['CW'] and 0 <= ay < d2['CH'] and d2['feet'](ahead) in d2['walk']
                                               and not (ahead in d2['warpset'] and d2['feet'](ahead) in WT))
                    if not okrest: continue
                    # pokered CheckForCollisionWhenPushingBoulder: the push is refused if there is a tile-pair
                    # (elevation) difference between the PLAYER's tile (behind) and the boulder DESTINATION
                    # (ahead, two steps in front), or the destination is stairs ($15). NOT fully exempt.
                    if tpblk(f, behind, ahead): continue
                    if d2['feet'](ahead) == 0x15: continue
                nflags = set(flags); nb = set(boulders); nb.discard(b); note = ""
                if is_hole:
                    nflags.add("VR3b"); note = "into hole %s" % (HOLE[f],)   # boulder falls, disappears
                else:
                    nb.add(ahead)
                    if ahead in SWITCH[f]:
                        nflags.add(SWITCH[f][ahead][0]); note = "onto switch %s" % (ahead,)
                nflags = frozenset(nflags); nb = frozenset(nb)
                noc = opened(f, nflags); nreg = region(f, b, nb, noc)  # player now at old boulder cell b
                key = (f, nflags, nb, norm(nreg))
                if key in seen: continue
                seen.add(key)
                q.append((key, nreg, noc, path + [(f, "push %s dir%d -> %s %s" % (b, d, ahead, note))]))
        # LADDERS reachable from region
        for L, (df, land) in LADDERS[f].items():
            if not any((L[0] + dx, L[1] + dy) in reg for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))): continue
            nflags = frozenset(x for x in flags if x != "VR1") if df == "2F" else flags  # VR2F clears VR1
            nb = boulders_of(df, nflags); noc = opened(df, nflags); nreg = region(df, land, nb, noc)
            key = (df, nflags, nb, norm(nreg))
            if key in seen: continue
            seen.add(key)
            q.append((key, nreg, noc, path + [(f, "ladder %s -> %s%s" % (L, df, land))]))
        # PLAYER HOLE (3F): step on hole -> 2F(22,16)
        if f in HOLE:
            hc = HOLE[f]
            if hc not in boulders and any((hc[0] + dx, hc[1] + dy) in reg for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                df, land = HOLE_PLAYER_DEST
                nflags = frozenset(x for x in flags if x != "VR1")
                nb = boulders_of(df, nflags); noc = opened(df, nflags); nreg = region(df, land, nb, noc)
                key = (df, nflags, nb, norm(nreg))
                if key not in seen:
                    seen.add(key)
                    q.append((key, nreg, noc, path + [(f, "fall in hole %s -> %s%s" % (hc, df, land))]))
    return None

ans = solve()
if ans is None:
    print("NO SOLUTION")
else:
    print("SOLUTION (%d steps):" % len(ans))
    for f, a in ans: print("  [%s] %s" % (f, a))
