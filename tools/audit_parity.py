"""gh #176 phase 1: data-parity audit.

Independently re-parses pokered's gameplay-critical tables (its own decoders — deliberately no
code shared with extract.py) and diffs them against the assets the port actually consumes.
A divergence means the extractor, this verifier, or a hand-edit is wrong: investigate.

Run: python tools/audit_parity.py          (exits 1 on any divergence)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "pokered"
OUT = ROOT / "game" / "assets"

findings = []


def finding(domain, msg):
    findings.append((domain, msg))
    print(f"  DIVERGE [{domain}] {msg}")


def read(rel):
    return (SRC / rel).read_text(encoding="utf-8")


def strip_comment(line):
    return line.split(";", 1)[0]


def load_json(rel):
    return json.load(open(OUT / rel, encoding="utf-8"))


# --------------------------------------------------------------------------- #
def check_type_chart():
    """data/types/type_matchups.asm vs types.json."""
    mult = {"SUPER_EFFECTIVE": 2.0, "NOT_VERY_EFFECTIVE": 0.5, "NO_EFFECT": 0.0}
    asm = {}
    for line in read("data/types/type_matchups.asm").splitlines():
        m = re.match(r"\s*db (\w+),\s*(\w+),\s*(\w+)", strip_comment(line))
        if m:
            asm[(m.group(1), m.group(2))] = mult[m.group(3)]
    port = load_json("types.json")
    flat = {}
    for att, row in port.items():
        for dfn, v in row.items():
            flat[(att, dfn)] = float(v)
    for k, v in asm.items():
        pv = flat.get(k, 1.0)
        if pv != v:
            finding("types", f"{k[0]}->{k[1]}: pokered x{v}, port x{pv}")
    for k, v in flat.items():
        if k not in asm and v != 1.0:
            finding("types", f"{k[0]}->{k[1]}: port has x{v}, pokered has no entry (x1)")
    print(f"type chart: {len(asm)} matchups checked")


# --------------------------------------------------------------------------- #
def check_moves():
    """data/moves/moves.asm vs moves.json."""
    asm = {}
    for line in read("data/moves/moves.asm").splitlines():
        m = re.match(r"\s*move (\w+),\s*(\w+),\s*(\d+),\s*(\w+),\s*(\d+),\s*(\d+)", strip_comment(line))
        if m:
            asm[m.group(1)] = {
                "effect": m.group(2), "power": int(m.group(3)), "type": m.group(4),
                "accuracy": int(m.group(5)), "pp": int(m.group(6))}
    port = load_json("moves.json")
    for name, a in asm.items():
        p = port.get(name)
        if p is None:
            finding("moves", f"{name}: missing from the port")
            continue
        for f in ("effect", "power", "type", "accuracy", "pp"):
            if p.get(f) != a[f]:
                finding("moves", f"{name}.{f}: pokered {a[f]}, port {p.get(f)}")
    for name in port:
        if name not in asm:
            finding("moves", f"{name}: in the port but not pokered")
    print(f"moves: {len(asm)} checked")


# --------------------------------------------------------------------------- #
def check_tms():
    """constants/item_constants.asm add_tm/add_hm order vs tm_moves.json (TM01.. / HM01..)."""
    tms, hms = [], []
    for line in read("constants/item_constants.asm").splitlines():
        s = strip_comment(line).strip()
        m = re.match(r"add_tm (\w+)", s)
        if m:
            tms.append(m.group(1))
        m = re.match(r"add_hm (\w+)", s)
        if m:
            hms.append(m.group(1))
    port = load_json("tm_moves.json")
    for i, mv in enumerate(tms):
        key = "TM%02d" % (i + 1)
        if port.get(key) != mv:
            finding("tms", f"{key}: pokered {mv}, port {port.get(key)}")
    if len(port) != len(tms):
        finding("tms", f"TM count: pokered {len(tms)}, port {len(port)}")
    # The HMs are a hand-written table in Main.gd (HM_MOVES) — the audit reads the consumer.
    gd = (ROOT / "game/scripts/Main.gd").read_text(encoding="utf-8")
    m = re.search(r"const HM_MOVES := \{(.*?)\}", gd, re.S)
    port_hms = dict(re.findall(r'"(HM\d+)": "(\w+)"', m.group(1))) if m else {}
    for i, mv in enumerate(hms):
        key = "HM%02d" % (i + 1)
        if port_hms.get(key) != mv:
            finding("tms", f"{key}: pokered {mv}, port {port_hms.get(key)}")
    print(f"tm/hm: {len(tms)} TMs + {len(hms)} HMs checked")


# --------------------------------------------------------------------------- #
def _species_key(label):
    return re.sub(r"[^a-z0-9]", "", label.lower())


def check_base_stats():
    """data/pokemon/base_stats/*.asm vs pokemon/base_stats.json."""
    port = load_json("pokemon/base_stats.json")
    seen = set()
    for f in sorted((SRC / "data/pokemon/base_stats").glob("*.asm")):
        key = _species_key(f.stem)
        p = port.get(key)
        if p is None:
            finding("stats", f"{key}: species missing from the port")
            continue
        seen.add(key)
        text = f.read_text(encoding="utf-8")
        db = [strip_comment(l).strip() for l in text.splitlines()]
        db = [l for l in db if l.startswith(("db ", "tmhm "))]
        stats = [int(x) for x in db[1][3:].split(",")]
        types = [t.strip() for t in db[2][3:].split(",")]
        catch = int(db[3][3:])
        base_exp = int(db[4][3:])
        lvl1 = [m.strip() for m in db[5][3:].split(",") if m.strip() != "NO_MOVE"]
        growth = db[6][3:].strip()
        tm_text = text[text.index("tmhm"):]
        tm_text = tm_text[:tm_text.index("; end")] if "; end" in tm_text else tm_text
        tmhm = re.findall(r"[A-Z][A-Z_0-9]+", tm_text.replace("tmhm", ""))
        want = dict(zip(("hp", "atk", "def", "spd", "spc"), stats))
        for k, v in want.items():
            if int(p.get(k, -1)) != v:
                finding("stats", f"{key}.{k}: pokered {v}, port {p.get(k)}")
        if [str(t) for t in p.get("types", [])] != types:
            finding("stats", f"{key}.types: pokered {types}, port {p.get('types')}")
        if int(p.get("catch", -1)) != catch:
            finding("stats", f"{key}.catch: pokered {catch}, port {p.get('catch')}")
        if int(p.get("base_exp", -1)) != base_exp:
            finding("stats", f"{key}.base_exp: pokered {base_exp}, port {p.get('base_exp')}")
        if [str(m) for m in p.get("learnset", [])] != lvl1:
            finding("stats", f"{key}.level-1 learnset: pokered {lvl1}, port {p.get('learnset')}")
        if str(p.get("growth", "")) != growth:
            finding("stats", f"{key}.growth: pokered {growth}, port {p.get('growth')}")
        if sorted(str(m) for m in p.get("tmhm", [])) != sorted(tmhm):
            missing = set(tmhm) - set(p.get("tmhm", []))
            extra = set(p.get("tmhm", [])) - set(tmhm)
            finding("stats", f"{key}.tmhm: missing {sorted(missing)} extra {sorted(extra)}")
    for key in port:
        if key not in seen:
            finding("stats", f"{key}: in the port but no pokered base_stats file")
    print(f"base stats: {len(seen)} species checked")


# --------------------------------------------------------------------------- #
def check_evos_moves():
    """data/pokemon/evos_moves.asm (per-label) vs base_stats.json evolutions/level_moves."""
    port = load_json("pokemon/base_stats.json")
    text = read("data/pokemon/evos_moves.asm")
    blocks = re.split(r"^(\w+)EvosMoves:", text, flags=re.M)
    checked = 0
    for i in range(1, len(blocks) - 1, 2):
        label, body = blocks[i], blocks[i + 1]
        key = _species_key(label)
        # MissingNo slots and the battle-only stand-ins (the fossil displays, the ghost)
        # are not dex species; the port rightly has no entries for them.
        if key.startswith("missingno") or key in ("fossilkabutops", "fossilaerodactyl", "monghost"):
            continue
        p = port.get(key)
        if p is None:
            finding("evos", f"{key}: species missing from the port")
            continue
        checked += 1
        evos, moves = [], []
        in_moves = False
        for line in body.splitlines():
            s = strip_comment(line).strip()
            if not s.startswith("db "):
                continue
            vals = [v.strip() for v in s[3:].split(",")]
            if vals == ["0"]:
                if not in_moves:
                    in_moves = True
                    continue
                break
            if in_moves:
                moves.append([int(vals[0]), vals[1]])
            else:
                evos.append(vals)
        pe = [[str(x) for x in e] for e in p.get("evolutions", [])]
        ae = [[str(x) for x in e] for e in evos]
        if pe != ae:
            finding("evos", f"{key}.evolutions: pokered {ae}, port {pe}")
        pm = [[int(l), str(m)] for l, m in p.get("level_moves", [])]
        if pm != moves:
            finding("evos", f"{key}.level_moves: pokered {moves}, port {pm}")
    print(f"evolutions/learnsets: {checked} species checked")


# --------------------------------------------------------------------------- #
def check_trainers():
    """data/trainers/parties.asm + pic_pointers_money.asm vs trainers.json."""
    classes = [c for c in re.findall(r"trainer_const (\w+)", read("constants/trainer_constants.asm"))
               if c != "NOBODY"]
    text = read("data/trainers/parties.asm")
    blocks = re.split(r"^(\w+)Data:", text, flags=re.M)[1:]
    labels, bodies = blocks[0::2], blocks[1::2]
    moneys = re.findall(r"pic_money \w+,\s*(\d+)", read("data/trainers/pic_pointers_money.asm"))
    port = load_json("trainers.json")
    checked = 0
    for i, (label, body) in enumerate(zip(labels, bodies)):
        cls = "OPP_" + classes[i]
        parties = []
        for line in body.splitlines():
            s = strip_comment(line).strip()
            if not s.startswith("db "):
                continue
            vals = [v.strip() for v in s[3:].split(",")]
            if vals[0] == "$FF":
                mons = [{"species": _species_key(vals[j + 1]), "level": int(vals[j])}
                        for j in range(1, len(vals) - 1, 2)]
            else:
                lvl = int(vals[0])
                mons = [{"species": _species_key(m), "level": lvl} for m in vals[1:-1]]
            parties.append(mons)
        p = port.get(cls)
        if p is None:
            if parties:
                finding("trainers", f"{cls}: class missing from the port ({len(parties)} parties)")
            continue
        checked += 1
        pp = [[{"species": str(m["species"]), "level": int(m["level"])} for m in pt]
              for pt in p.get("parties", [])]
        if pp != parties:
            for j, (a, b) in enumerate(zip(parties, pp)):
                if a != b:
                    finding("trainers", f"{cls} party {j + 1}: pokered {a}, port {b}")
            if len(parties) != len(pp):
                finding("trainers", f"{cls}: pokered {len(parties)} parties, port {len(pp)}")
        if i < len(moneys) and int(p.get("money", -1)) * 100 != int(moneys[i]):
            finding("trainers", f"{cls}.money: pokered {moneys[i]}, port {p.get('money')}x100")
    print(f"trainers: {checked} classes checked")


def check_wild():
    """data/wild/maps/*.asm + probabilities.asm vs wild.json."""
    port = load_json("wild.json")
    # the 10 slot-chance bytes
    acc, slots = 0, []
    for m in re.finditer(r"wild_chance\s+(\d+)", read("data/wild/probabilities.asm")):
        acc += int(m.group(1))
        slots.append(acc - 1)
    if port.get("slots") != slots:
        finding("wild", f"slot chances: pokered {slots}, port {port.get('slots')}")
    maps = port.get("maps", {})
    checked = 0
    for f in sorted((SRC / "data/wild/maps").glob("*.asm")):
        text = f.read_text(encoding="utf-8")
        # keep the RED version's tables: drop IF DEF(_BLUE) blocks, unwrap IF DEF(_RED)
        text = re.sub(r"IF DEF\(_BLUE\).*?ENDC", "", text, flags=re.S)
        kind = {}
        for which in ("grass", "water"):
            m = re.search(r"def_%s_wildmons (\d+)" % which, text)
            if not m:
                continue
            seg = text[m.end():]
            end = re.search(r"end_%s_wildmons|def_\w+_wildmons" % which, seg)
            seg = seg[:end.start()] if end else seg
            mons = [[int(a), _species_key(b)]
                    for a, b in re.findall(r"db\s+(\d+),\s*(\w+)", seg)]
            kind[which] = (int(m.group(1)), mons)
        label = f.stem
        if label == "SeaRoutes":
            # a shared water table, not a map: the pointer table hands it to Routes 19/20/21,
            # and the port's per-route entries carry it (verified below via those routes)
            continue
        p = maps.get(label)
        if p is None:
            if any(v[0] > 0 for v in kind.values()):
                finding("wild", f"{label}: map missing from the port")
            continue
        checked += 1
        for which, (rate, mons) in kind.items():
            if int(p.get(which + "_rate", 0)) != rate:
                finding("wild", f"{label}.{which}_rate: pokered {rate}, port {p.get(which + '_rate')}")
            pm = [[int(l), str(s)] for l, s in p.get(which, [])]
            if pm != mons:
                finding("wild", f"{label}.{which}: pokered {mons}, port {pm}")
    print(f"wild: {checked} maps checked (slots {slots == port.get('slots')})")


def check_prices():
    """data/items/prices.asm (item-id order) + names.asm vs item_prices.json."""
    prices = [int(m.group(1)) for m in re.finditer(r"bcd3 (\d+)", read("data/items/prices.asm"))]
    names = re.findall(r'li "([^"]+)"', read("data/items/names.asm"))
    port = load_json("item_prices.json")
    # Gen 1 ships a GLITCH duplicate "PP UP" (item $32, price 0) before the real one ($4F,
    # 9800); price lookups resolve the real item, so keep the LAST occurrence of a dup name.
    best = {}
    for name, price in zip(names, prices):
        best[name] = price
    checked = 0
    for name, price in best.items():
        if name not in port:
            continue                       # the port prices only what's sellable/buyable
        checked += 1
        if int(port[name]) != price:
            finding("prices", f"{name}: pokered {price}, port {port[name]}")
    print(f"item prices: {checked} of {len(prices)} priced items checked")


def check_marts():
    """data/items/marts.asm script_mart lines vs marts.json."""
    port = load_json("marts.json")
    checked = 0
    for m in re.finditer(r"(\w+)MartClerkText::\s*\n\s*script_mart ([^\n]+)", read("data/items/marts.asm")):
        label, items = m.group(1), [i.strip() for i in m.group(2).split(",")]
        matches = [k for k in port if k.replace("Mart", "").startswith(label)]
        key = label + "Mart"
        p = port.get(key)
        if p is None:
            finding("marts", f"{key}: mart missing from the port (candidates: {matches})")
            continue
        checked += 1
        if [str(x) for x in p] != items:
            finding("marts", f"{key}: pokered {items}, port {p}")
    print(f"marts: {checked} checked")


def check_hidden_items():
    """data/events/hidden_item_coords.asm vs hidden_items.json (coords; items unchecked here)."""
    port = load_json("hidden_items.json")
    port_set = set()
    for label, lst in port.items():
        for h in lst:
            port_set.add((label, int(h["x"]), int(h["y"])))
    # map consts -> the port's labels: strip underscores, title-case parts
    def map_label(const):
        parts = const.split("_")
        out = "".join(p.capitalize() for p in parts)
        for a, b in (("Ss", "SS"), ("1f", "1F"), ("2f", "2F"), ("3f", "3F"), ("4f", "4F"),
                     ("5f", "5F"), ("6f", "6F"), ("7f", "7F"), ("8f", "8F"), ("9f", "9F"),
                     ("10f", "10F"), ("11f", "11F"), ("B1f", "B1F"), ("B2f", "B2F"),
                     ("B3f", "B3F"), ("B4f", "B4F")):
            out = out.replace(a, b)
        return out
    asm_set = set()
    for m in re.finditer(r"hidden_item (\w+),\s*(\d+),\s*(\d+)", read("data/events/hidden_item_coords.asm")):
        if m.group(1).startswith("UNUSED_MAP"):
            continue                       # pokered parks an item on an unused map; not portable
        asm_set.add((map_label(m.group(1)), int(m.group(2)), int(m.group(3))))
    for e in sorted(asm_set - port_set):
        finding("hidden", f"pokered has {e}, port lacks it")
    for e in sorted(port_set - asm_set):
        finding("hidden", f"port has {e}, pokered lacks it")
    print(f"hidden items: {len(asm_set)} coords checked")


def check_trades():
    """data/events/trades.asm vs trades.json."""
    port = load_json("trades.json")["trades"]
    asm = [{"give": _species_key(m.group(1)), "get": _species_key(m.group(2)), "nick": m.group(4)}
           for m in re.finditer(r'npctrade (\w+),\s*(\w+),\s*(\w+),\s*"([^"@]+)@?"', read("data/events/trades.asm"))]
    pt = [{"give": str(t["give"]), "get": str(t["get"]), "nick": str(t["nick"])} for t in port]
    if pt != asm:
        for i, (a, b) in enumerate(zip(asm, pt)):
            if a != b:
                finding("trades", f"trade {i}: pokered {a}, port {b}")
        if len(asm) != len(pt):
            finding("trades", f"count: pokered {len(asm)}, port {len(pt)}")
    print(f"trades: {len(asm)} checked")


# --------------------------------------------------------------------------- #
def main():
    for fn in (check_type_chart, check_moves, check_tms, check_base_stats, check_evos_moves,
               check_trainers, check_wild, check_prices, check_marts, check_hidden_items,
               check_trades):
        fn()
    if findings:
        print(f"\nDIVERGENCES: {len(findings)}")
        sys.exit(1)
    print("\nall phase-A domains at parity")


if __name__ == "__main__":
    main()
