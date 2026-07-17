"""Audit every `player.place(Vector2i(x, y))` in the selftest drivers against the map it lands on.

`place()` bypasses collision, so a test that drops the player on a *solid* cell and then interacts
asserts nothing about whether a player could ever stand there. That is exactly how two critical bugs
survived:

  * gh #80 -- `--silphtest` talked to the Silph Co president from `player.place(Vector2i(7, 6))`,
    a wall tile, while he was in fact unreachable on foot.
  * gh #83 -- `--mansiontest` pressed the Pokemon Mansion switches from *inside* the wall they are
    mounted on, while no player could ever flip them.

Run from the repo root:  python tools/audit_places.py
Exit code is 1 if any placement lands on a non-walkable cell.

Not every hit is a bug -- a test may place the player somewhere solid on purpose, and the map
attribution here is a simple "most recent `load_world` wins" scan, which a warp can invalidate. Treat
the output as a list to check, not a verdict. The ones that matter are flagged `then faces/interacts`.

A place() line can carry an inline annotation for the two known blind spots (each was verified by
hand before being annotated -- see gh #84):

    # audit: map=<Label>   the player is really on <Label> by now (a warp/stairs changed the map
                           after the last load_world); check the cell against that map instead
    # audit: surf          the cell is water and the test surfs onto it (walkable only afloat)
"""
import io
import json
import os
import re
import sys

SUB = [[4, 6], [12, 14]]                       # bottom-left tile of each 16px cell
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.join(ROOT, "game", "scripts", "Main.gd")
MAPS = os.path.join(ROOT, "game", "assets", "maps")
TILESETS = os.path.join(ROOT, "game", "assets", "tilesets")

LOAD = re.compile(r'load_world\(\s*"([A-Za-z0-9_]+)"')
PLACE = re.compile(r'player\.place\(\s*Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)')
NOTE = re.compile(r'#\s*audit:\s*(surf|map=([A-Za-z0-9_]+))')

_cache = {}


def walkable(label, x, y):
    """True/False, or None when the map or cell is out of range."""
    if label not in _cache:
        p = os.path.join(MAPS, "%s.json" % label)
        if not os.path.exists(p):
            _cache[label] = None
        else:
            m = json.load(open(p))
            ts = json.load(open(os.path.join(TILESETS, "%s.json" % m["tileset"])))
            _cache[label] = (m, ts, set(ts["walkable_tiles"]))
    entry = _cache[label]
    if entry is None:
        return None
    m, ts, wk = entry
    if not (0 <= x < m["width"] * 2 and 0 <= y < m["height"] * 2):
        return None
    return ts["blocks"][m["blocks"][y // 2][x // 2]][SUB[y % 2][x % 2]] in wk


def main():
    src = io.open(MAIN, encoding="utf-8").read().splitlines()
    cur, bad = None, []
    for i, line in enumerate(src, 1):
        m = LOAD.search(line)
        if m:
            cur = m.group(1)
        p = PLACE.search(line)
        if p and cur:
            x, y = int(p.group(1)), int(p.group(2))
            note = NOTE.search(line)
            against = cur
            if note:
                if note.group(1) == "surf":
                    continue
                against = note.group(2)
            if walkable(against, x, y) is False:
                ctx = "\n".join(src[i - 1:i + 3])
                bad.append((i, against, (x, y), "interact(player)" in ctx or "facing" in ctx))

    print("player.place() onto a non-walkable cell: %d" % len(bad))
    for ln, mp, c, interacts in bad:
        print("  Main.gd:%-6d %-24s %-10s %s" % (
            ln, mp, "(%d,%d)" % c, "<-- then faces/interacts" if interacts else ""))
    if not bad:
        print("  (none - every placement lands on a standable cell)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
