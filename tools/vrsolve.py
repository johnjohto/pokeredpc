#!/usr/bin/env python
# Generalized Victory Road / cavern boulder-push solver (gh #105). Finds the push sequence to shove one
# boulder onto a target cell (a switch or a hole), tile-pair-aware for the player's movement but
# tile-pair-EXEMPT for the push itself (pokered CollisionCheckOnLand checks the sprite in front first).
# Entrance warps are standable (they only fire facing the map edge, gh #80); ladder warp-tiles are not.
#
# Usage:  python tools/vrsolve.py <Map> <startX,Y> <boulderX,Y> <targetX,Y>
#              [--others x,y;x,y] [--open bx,by;bx,by] [--wt 0x18,0x1a,0x22]
import json, sys
from collections import deque

def parse_cells(s):
    return set(tuple(int(v) for v in p.split(',')) for p in s.split(';') if p)

def main():
    a = sys.argv
    mp = a[1]; START = tuple(int(v) for v in a[2].split(','))
    BOULDER = tuple(int(v) for v in a[3].split(',')); TARGET = tuple(int(v) for v in a[4].split(','))
    others = set(); open_blocks = set(); WT = {0x18, 0x1a, 0x22}
    i = 5
    while i < len(a):
        if a[i] == '--others': others = parse_cells(a[i+1]); i += 2
        elif a[i] == '--open': open_blocks = parse_cells(a[i+1]); i += 2
        elif a[i] == '--wt': WT = set(int(x, 16) for x in a[i+1].split(',')); i += 2
        else: i += 1
    R = "game/assets"
    m = json.load(open(f'{R}/maps/{mp}.json')); ts = json.load(open(f"{R}/tilesets/{m['tileset']}.json"))
    bd = ts['blocks']; walk = set(ts['walkable_tiles']); W, H = m['width'], m['height']; CW, CH = W*2, H*2
    SUB = [[4, 6], [12, 14]]
    def feet(c): return bd[m['blocks'][c[1]//2][c[0]//2]][SUB[c[1] % 2][c[0] % 2]]
    warps = {(w['x'], w['y']) for w in m['warps']}
    oc = set()
    for (bx, by) in open_blocks:
        for sx in (0, 1):
            for sy in (0, 1): oc.add((bx*2+sx, by*2+sy))
    PAIRS = [(0x20, 0x05), (0x41, 0x05), (0x2A, 0x05), (0x05, 0x21)]
    def tpblk(p, q):
        s, f = feet(p), feet(q); return any((s == x and f == y) or (s == y and f == x) for x, y in PAIRS)
    def walkable(c):
        x, y = c
        if c in oc: return True
        if not (0 <= x < CW and 0 <= y < CH and feet(c) in walk): return False
        if c in warps and feet(c) in WT: return False        # ladder warp-tiles: can't stand (warp on step)
        return True
    def reachable(player, obst):
        seen = {player}; q = deque([player])
        while q:
            c = q.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (c[0]+dx, c[1]+dy)
                if n in seen or n in obst or not walkable(n): continue
                if not (n in oc or c in oc) and tpblk(c, n): continue
                seen.add(n); q.append(n)
        return seen
    DIRS = {0: (0, 1), 1: (0, -1), 2: (-1, 0), 3: (1, 0)}; DN = {0: 'DOWN', 1: 'UP', 2: 'LEFT', 3: 'RIGHT'}
    # BFS over boulder position; player region derived. The target need not be "walkable" (a hole isn't),
    # so allow the boulder to be pushed onto it regardless of walkable().
    startb = (BOULDER, frozenset(reachable(START, others | {BOULDER})))
    seen = {BOULDER}; q = deque([(BOULDER, startb[1], [])])
    while q:
        b, region, path = q.popleft()
        if b == TARGET:
            legs = []
            for frm, d in path:
                if legs and legs[-1][1] == d and (legs[-1][0][0]+DIRS[d][0]*legs[-1][2], legs[-1][0][1]+DIRS[d][1]*legs[-1][2]) == frm:
                    legs[-1][2] += 1
                else: legs.append([frm, d, 1])
            print(f'{mp}: boulder {BOULDER} -> {TARGET} in {len(path)} pushes:')
            for frm, d, t in legs:
                print('\t[Vector2i(%d, %d), %d, %d],   # %s x%d' % (frm[0], frm[1], d, t, DN[d], t))
            return
        for d, (dx, dy) in DIRS.items():
            behind = (b[0]-dx, b[1]-dy); ahead = (b[0]+dx, b[1]+dy)
            if ahead != TARGET and (not walkable(ahead) or ahead in others): continue
            if behind not in region: continue
            if ahead in seen: continue
            seen.add(ahead)
            q.append((ahead, frozenset(reachable(b, others | {ahead})), path+[(b, d)]))
    print(f'{mp}: boulder {BOULDER} -> {TARGET}: NO SOLUTION')

main()
