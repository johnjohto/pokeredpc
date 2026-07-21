"""Audit every map for a *solid sprite standing where nothing else can pass*.

NPCs, item balls and boulders are all solid, and pokered removes them only from a script (a battle
won, an event set). When the port fails to mirror that script the sprite becomes a permanent wall.
Three bugs of this exact shape have shipped, so this checks the two ways it happens:

  approach -- every walkable cell adjacent to a warp, sign or item ball is occupied.
      gh #79: SAFFRONCITY_ROCKET8 on (18,22), the one approach to Silph Co's door.
      gh #89: GAMECORNER_ROCKET on (9,5), the one cell the Rocket Hideout poster is read from --
              so the hideout, the SILPH SCOPE and the rest of the game were unreachable.
      gh #90: CERULEANCITY_SUPER_NERD3 on (4,12), the one land cell at Cerulean Cave's door.

  gate     -- the sprite is a cut vertex: remove it and two otherwise separate walkable regions
              join. Pokemon Tower 6F's RARE CANDY sits in the one-tile passage into the floor's
              southern half, so a real player must take it to pass.

Run from the repo root:  python tools/audit_chokepoints.py [--all]
Exit code is 1 if any *unreviewed* hit is found.

This is a list to check, not a verdict. A hit is fine when the sprite is meant to be a door and the
port models the script that opens it -- so each reviewed hit is silenced by naming it in EXPECTED
below, with the reason. `--all` prints the silenced ones too.

Blind spots, both of which over-report rather than under-report: "walkable" means land, so a target
you SURF up to reads as having only its land approaches; and a sprite hidden at map load (an item
ball whose event has not fired) is still counted as solid.
"""
import json
import os
import sys

SUB = [[4, 6], [12, 14]]                       # bottom-left tile of each 16px cell
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPS = os.path.join(ROOT, "game", "assets", "maps")
TILESETS = os.path.join(ROOT, "game", "assets", "tilesets")

# Reviewed hits: "<Map>:<sprite_x>,<sprite_y>" -> why it is not a bug.
EXPECTED = {
    "GameCorner:9,5":
        "gh #89: the ROCKET is the poster's door; the game_corner event records hide him once beaten",
    "SaffronCity:18,22":
        "gh #79: ROCKET8 is Silph Co's door; the saffron visible records clear him on the Tower rescue",
    "SaffronCity:34,4":
        "gh #79: ROCKET3 is Saffron Gym's door; the saffron records clear every grunt on Giovanni",
    "PokemonTower6F:6,8":
        "the RARE CANDY ball is the passage's door -- taking it is the key (faithful to pokered)",
    "CeruleanCity:27,12":
        "GUARD2 blocks the trashed house until GOT_SS_TICKET (the cerulean guard-swap records)",
    "CeruleanCity:4,12":
        "gh #90: SUPER_NERD3 is Cerulean Cave's door; hidden once CHAMPION (cerulean_cave_guy_shown)",
    "SaffronCity:7,6":
        "a takeover ROCKET on Copycat's door; the saffron records clear every grunt on Giovanni",
    "SaffronCity:13,12":
        "a takeover ROCKET on the Pidgey house door; cleared with the rest on Giovanni",
    "WardensHouse:8,4":
        "the BOULDER is the RARE CANDY's door -- STRENGTH shoves it aside (faithful to pokered)",

    # -- gates, all reviewed and faithful ---------------------------------------------------------
    "MtMoonB2F:12,6": "a FOSSIL is the exit ladder's door: take either and MtMoonB2F.asm hides both",
    "MtMoonB2F:13,6": "the other FOSSIL of the same pair",
    "Route12:10,62": "the SNORLAX *is* the road; the POKe FLUTE wakes it",
    "Route16:26,10": "the other SNORLAX, on the Cycling Road",
    "Route13:12,4":
        "a BIRD KEEPER (sight 2) faces RIGHT into the road, so he marches off his tile when spotted; "
        "the 12-cell pocket behind him is Route 13's west-edge seam with Route 14",
    "Route14:15,6":
        "a BIRD KEEPER (sight 2) faces DOWN into the road. The 4 cells behind him are a dead-end "
        "corridor that Route 13's west edge lines up with -- enter it and you can only back out, "
        "because from there you are not in his sight line. Cross Route 13 at y=8 instead",
    "Route25:24,4": "a JR.TRAINER (sight 3) faces the road and marches when spotted; his pocket holds a ball",
    "SilphCo5F:28,4":
        "the ROCKET is the CARD KEY corridor's east neck. You do not walk in -- the 9F teleport pad "
        "lands you inside it, beside the ball at (21,16)",
    "VictoryRoad2F:5,5": "a STRENGTH boulder; shoving it onto the floor switch is the puzzle",
    "VictoryRoad3F:24,10": "the other STRENGTH boulder",
}

# gh #42 (ADR-019): reviewed blockers whose "door opens" claim rests on AUTHORED EVENTS,
# not engine code -- a deleted or mistyped record would seal the game as silently as dead
# code once did (gh #79/#89/#90 were exactly this shape). For each, some record in
# game/events/ must reference BOTH the map and the object; the audit gates on it.
EVENT_BACKED = {
    "GameCorner:9,5": "SPRITE_ROCKET@9,5",
    "SaffronCity:18,22": "SPRITE_ROCKET@18,22",
    "SaffronCity:34,4": "SPRITE_ROCKET@34,4",
    "SaffronCity:7,6": "SPRITE_ROCKET@7,6",
    "SaffronCity:13,12": "SPRITE_ROCKET@13,12",
    "CeruleanCity:27,12": "SPRITE_GUARD@27,12",
    "CeruleanCity:4,12": "SPRITE_SUPER_NERD@4,12",
    "MtMoonB2F:12,6": "SPRITE_FOSSIL@12,6",
    "MtMoonB2F:13,6": "SPRITE_FOSSIL@13,6",
}

EVENTS_DIR = os.path.join(ROOT, "game", "events")


def verify_event_doors():
    """Each EVENT_BACKED blocker must be named (map + object) by some authored record."""
    texts = {}
    if os.path.isdir(EVENTS_DIR):
        for fn in sorted(os.listdir(EVENTS_DIR)):
            if fn.endswith(".json"):
                with open(os.path.join(EVENTS_DIR, fn), encoding="utf-8") as f:
                    texts[fn] = f.read()
    missing = []
    for key, obj in EVENT_BACKED.items():
        label = key.split(":")[0]
        if not any('"map:%s"' % label in t and obj in t for t in texts.values()):
            missing.append((key, obj))
    print("event-backed doors verified: %d/%d" % (len(EVENT_BACKED) - len(missing), len(EVENT_BACKED)))
    for key, obj in missing:
        print("  %-22s no authored record names %s -- the door may never open" % (key, obj))
    return missing


_cache = {}


def load(label):
    if label not in _cache:
        m = json.load(open(os.path.join(MAPS, "%s.json" % label), encoding="utf-8"))
        ts = json.load(open(os.path.join(TILESETS, "%s.json" % m["tileset"]), encoding="utf-8"))
        walk = set(ts["walkable_tiles"])
        walk.add(ts["grass_tile"])
        _cache[label] = (m, ts, walk)
    return _cache[label]


def walkable(label, x, y):
    m, ts, walk = load(label)
    if not (0 <= x < m["width"] * 2 and 0 <= y < m["height"] * 2):
        return False
    return ts["blocks"][m["blocks"][y // 2][x // 2]][SUB[y % 2][x % 2]] in walk


def targets(m):
    """(kind, cell) for everything a player has to walk up to."""
    for w in m["warps"]:
        yield "warp -> %s" % (w.get("dest_map") or "LAST_MAP"), (w["x"], w["y"])
    for b in m.get("bg_events", []):
        yield "sign", (b["x"], b["y"])
    for o in m.get("object_events", []):
        if str(o.get("sprite", "")).startswith("SPRITE_POKE_BALL"):
            yield "item ball", (o["x"], o["y"])


def components(label, sprites):
    """Connected components of the walkable cells, with every sprite cell removed."""
    m, _, _ = load(label)
    gw, gh = m["width"] * 2, m["height"] * 2
    seen, comp, cid = {}, 0, 0
    for y in range(gh):
        for x in range(gw):
            if (x, y) in seen or (x, y) in sprites or not walkable(label, x, y):
                continue
            cid += 1
            stack = [(x, y)]
            seen[(x, y)] = cid
            while stack:
                cx, cy = stack.pop()
                for n in ((cx, cy - 1), (cx, cy + 1), (cx - 1, cy), (cx + 1, cy)):
                    if (0 <= n[0] < gw and 0 <= n[1] < gh and n not in seen
                            and n not in sprites and walkable(label, *n)):
                        seen[n] = cid
                        stack.append(n)
    return seen


def gates(label, sprites):
    """Sprites whose removal would join two otherwise separate walkable regions.

    Only regions worth reaching count. Every shop counter and staff alcove is technically a
    separate region behind an NPC, so a side is "worth reaching" only if it holds a warp, a sign,
    an item ball, or a cell on a connected map edge -- something the player has a reason to walk
    to. SPRITE_LINK_RECEPTIONIST is skipped outright: the Cable Club behind her is not implemented.
    """
    m, _, _ = load(label)
    gw, gh = m["width"] * 2, m["height"] * 2
    comp = components(label, sprites)
    edge_dirs = {str(c["dir"]) for c in m.get("connections", [])}

    def worth(cid, blocker):
        # `blocker` is excluded: an item ball is not a reason to reach the alcove it sits in.
        cells = {c for c, i in comp.items() if i == cid}
        for _, t in targets(m):
            if t == blocker:
                continue
            if t in cells or any(n in cells for n in ((t[0], t[1] - 1), (t[0], t[1] + 1),
                                                      (t[0] - 1, t[1]), (t[0] + 1, t[1]))):
                return True
        for x, y in cells:
            if ((y == 0 and "north" in edge_dirs) or (y == gh - 1 and "south" in edge_dirs)
                    or (x == 0 and "west" in edge_dirs) or (x == gw - 1 and "east" in edge_dirs)):
                return True
        return False

    out = []
    for (sx, sy), sprite in sprites.items():
        if sprite == "SPRITE_LINK_RECEPTIONIST" or not walkable(label, sx, sy):
            continue                           # cable club / standing in a wall recess
        ids = {comp[n] for n in ((sx, sy - 1), (sx, sy + 1), (sx - 1, sy), (sx + 1, sy))
               if n in comp}
        if len(ids) < 2 or not all(worth(i, (sx, sy)) for i in ids):
            continue                           # not a gate, or one side is a dead-end alcove
        sizes = sorted((sum(1 for v in comp.values() if v == i) for i in ids), reverse=True)
        out.append(((sx, sy), sprite, sizes))
    return out


def main():
    show_all = "--all" in sys.argv
    hits, silenced = [], []
    for fn in sorted(os.listdir(MAPS)):
        if not fn.endswith(".json"):
            continue
        label = fn[:-5]
        m, _, _ = load(label)
        sprites = {(o["x"], o["y"]): str(o.get("sprite", "?")) for o in m.get("object_events", [])}

        for kind, (tx, ty) in targets(m):
            # A warp/ball occupies its own cell; a sign is a wall you face. Either way, the player
            # has to stand on a walkable neighbour of it (or, for a warp, step onto the warp itself).
            approaches = [c for c in ((tx, ty - 1), (tx, ty + 1), (tx - 1, ty), (tx + 1, ty))
                          if walkable(label, *c)]
            if not approaches:
                continue                       # sealed by geometry alone -- not this audit's business
            blockers = [c for c in approaches if c in sprites]
            if len(blockers) != len(approaches):
                continue                       # at least one approach is clear
            for bc in blockers:
                key = "%s:%d,%d" % (label, bc[0], bc[1])
                row = (label, sprites[bc], bc, "approach", "%s %s" % (kind, (tx, ty)))
                (silenced if key in EXPECTED else hits).append((key, row))

        for bc, sprite, sizes in gates(label, sprites):
            key = "%s:%d,%d" % (label, bc[0], bc[1])
            if any(k == key for k, _ in hits + silenced):
                continue                       # already reported as an approach blocker
            row = (label, sprite, bc, "gate", "joins regions of %s cells" % "+".join(map(str, sizes)))
            (silenced if key in EXPECTED else hits).append((key, row))

    def show(rows):
        for key, (label, sprite, bc, kind, what) in rows:
            print("  %-22s %-24s on %-9s [%s] %s" % (label, sprite, "(%d,%d)" % bc, kind, what))
            if key in EXPECTED:
                print("      %s" % EXPECTED[key])

    print("solid sprites that seal a warp/sign/ball or a whole region: %d" % len(hits))
    show(hits)
    if not hits:
        print("  (none unreviewed)")
    if show_all and silenced:
        print("\nreviewed / expected (%d):" % len(silenced))
        show(silenced)
    unbacked = verify_event_doors()
    return 1 if hits or unbacked else 0


if __name__ == "__main__":
    sys.exit(main())
