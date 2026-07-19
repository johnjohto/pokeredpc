#!/usr/bin/env python3
"""
pokered -> pokeredpc asset extractor.

Reads source data directly from the pret/pokered disassembly and emits
engine-ready assets (PNG tilesets/sprites + JSON map/tileset data) for the Godot
port. Generalized to every tileset and map.

Run:  python tools/extract.py
Docs: docs/data-formats/ and docs/guides/extending-the-extractor.md
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "pokered"
OUT = ROOT / "game" / "assets"
PREVIEW = ROOT / "build" / "preview"

# pokered's sprite filenames are the species key, with one exception: Mr. Mime's are `mr.mime.png` /
# `mr.mimeb.png`. Keyed by base_stats species key -> the stem to read from gfx/pokemon/. (gh #81)
SPRITE_STEM = {"mrmime": "mr.mime"}

TILE = 8           # px per source tile
BLOCK_TILES = 4    # tiles per block side
BLOCK = TILE * BLOCK_TILES

# BGB's default grey-green palette, sampled from the user's reference shots (gh #51).
GB_PALETTE = [(0xEA, 0xFB, 0xCE), (0xB5, 0xD2, 0x95), (0x65, 0x8A, 0x72), (0x22, 0x30, 0x39)]


def read(rel):
    return (SRC / rel).read_text(encoding="utf-8")


def slug(camel):
    return camel.lower()


def strip_comment(s):
    return s.split(";", 1)[0]


# --------------------------------------------------------------------------- #
# Graphics
# --------------------------------------------------------------------------- #

def load_tileset_png(png_path):
    """Load a tileset PNG -> (RGBA image, tiles_per_row, tile_count)."""
    from PIL import Image
    im = Image.open(png_path).convert("L")
    w, h = im.size
    cols, rows = w // TILE, h // TILE
    shades = sorted(set(im.getdata()))
    ramp = list(reversed(GB_PALETTE))[: len(shades)] if len(shades) <= 4 else None
    rgba = Image.new("RGBA", (w, h))
    src, dst = im.load(), rgba.load()
    if ramp:
        lut = {s: ramp[i] for i, s in enumerate(shades)}
        for y in range(h):
            for x in range(w):
                r, g, b = lut[src[x, y]]
                dst[x, y] = (r, g, b, 255)
    else:
        for y in range(h):
            for x in range(w):
                v = src[x, y]
                dst[x, y] = (v, v, v, 255)
    return rgba, cols, cols * rows


def extract_emote(name, dst):
    """gfx/emotes/<name>.png (16x16) -> RGBA on the GB palette. The lightest shade is the bubble's
    white interior (kept opaque) except where it's connected to the border (the exterior, made
    transparent via a flood fill from the corners)."""
    from PIL import Image
    im = Image.open(SRC / "gfx" / "emotes" / f"{name}.png").convert("L")
    w, h = im.size
    shades = sorted(set(im.getdata()))
    light = shades[-1]
    # These are OBJ tiles: the sprite palette (OBP) renders color 1 as WHITE on hardware —
    # the bubble interior — not the BG's light green (gh #41). Colors 2/3 stay mid/dark.
    obp = {0: 0, 1: 0, 2: 2, 3: 3}
    lut = {s: (*GB_PALETTE[obp[round((255 - s) / 85)]], 255) for s in shades}
    src = im.load()
    exterior = set()                       # flood the connected light region from the border
    stack = [(x, y) for x in range(w) for y in (0, h - 1) if src[x, y] == light]
    stack += [(x, y) for y in range(h) for x in (0, w - 1) if src[x, y] == light]
    while stack:
        x, y = stack.pop()
        if (x, y) in exterior or not (0 <= x < w and 0 <= y < h) or src[x, y] != light:
            continue
        exterior.add((x, y))
        stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    out = Image.new("RGBA", (w, h))
    dpx = out.load()
    for y in range(h):
        for x in range(w):
            dpx[x, y] = (0, 0, 0, 0) if (x, y) in exterior else lut[src[x, y]]
    out.save(dst)


def extract_smoke(dst):
    """gfx/overworld/smoke.png (one 8x8 tile) -> a white puff on transparency. The S.S. Anne
    departure zeroes rOBP1 so every non-zero color renders white (color 0 stays OBJ-transparent);
    the scene stacks the tile 2x2 for each 16x16 puff (LoadSmokeTileFourTimes)."""
    from PIL import Image
    im = Image.open(SRC / "gfx" / "overworld" / "smoke.png").convert("L")
    light = max(set(im.getdata()))
    out = Image.new("RGBA", im.size)
    s, d = im.load(), out.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            d[x, y] = (0, 0, 0, 0) if s[x, y] == light else (*GB_PALETTE[0], 255)
    out.save(dst)


def _ow_rgba(im_l):
    """Overworld sprite palette: GB color 0 (white) -> transparent; colors 1/2 -> the two lightest
    shades (idx 0,1) for a light body, but color 3 -> idx 3 (black) so the outline stays crisp.
    Between too-dark (idx 1,2,3) and too-bright/no-outline (idx 0,1,2)."""
    from PIL import Image
    w, h = im_l.size
    out = Image.new("RGBA", (w, h))
    sp, dp = im_l.load(), out.load()
    for y in range(h):
        for x in range(w):
            c = round((255 - sp[x, y]) / 255.0 * 3)
            if c == 0:
                dp[x, y] = (0, 0, 0, 0)
            elif c == 3:
                dp[x, y] = GB_PALETTE[3] + (255,)      # outline stays black
            else:
                dp[x, y] = GB_PALETTE[c - 1] + (255,)  # body a shade lighter
    return out


def extract_overworld_sprite(name, dst):
    """Overworld sprite strip (16xN, 16x16 frames) -> RGBA, lightest shade = transparent.

    Each shade maps to its *absolute* GB palette index (255->white, 170->light, 85->dark, 0->black),
    with the lightest shade keyed transparent (GB sprite color 0). A brightness-rank stretch would
    push a sprite's dark gray to black and render it too dark (#14)."""
    from PIL import Image
    im = Image.open(SRC / "gfx" / "sprites" / f"{name}.png").convert("L")
    w, h = im.size
    _ow_rgba(im).save(dst)
    return w, h, h // 16


# --------------------------------------------------------------------------- #
# Tilesets: name -> gfx png + blockset + collision
# --------------------------------------------------------------------------- #

def parse_tileset_constants():
    """Ordered list of tileset CONST names (index = tileset id)."""
    out = []
    for line in read("constants/tileset_constants.asm").splitlines():
        m = re.match(r"\s*const\s+(\w+)", line)
        if m:
            out.append(m.group(1))
    return out


def parse_tileset_counters():
    """CamelCase tileset name -> counter tile ids (the up-to-3 'counter' args; talk-across tiles)."""
    out = {}
    for line in read("data/tilesets/tileset_headers.asm").splitlines():
        m = re.match(r"\s*tileset\s+(\w+)\s*,(.+)", line)
        if m:
            args = [a.strip() for a in strip_comment(m.group(2)).split(",")]
            out[m.group(1)] = [int(a[1:], 16) for a in args[:3] if a.startswith("$")]
    return out


def parse_tileset_table():
    """Ordered list of tileset CamelCase names from the `Tilesets:` table."""
    out = []
    for line in read("data/tilesets/tileset_headers.asm").splitlines():
        m = re.match(r"\s*tileset\s+(\w+),", line)
        if m:
            out.append(m.group(1))
    return out


def parse_gfx_wiring():
    """name(Camel) -> {gfx: pokered-relative png, bst: pokered-relative bst}.

    Handles stacked labels sharing one INCBIN (e.g. RedsHouse1/RedsHouse2).
    """
    gfx, bst = {}, {}
    pend_g, pend_b = [], []
    for line in read("gfx/tilesets.asm").splitlines():
        s = line.strip()
        mg = re.match(r"(\w+)_GFX::", s)
        mb = re.match(r"(\w+)_Block::", s)
        if mg:
            pend_g.append(mg.group(1))
        if mb:
            pend_b.append(mb.group(1))
        m_inc = re.search(r'INCBIN "gfx/tilesets/(\w+)\.2bpp"', s)
        if m_inc:
            png = f"gfx/tilesets/{m_inc.group(1)}.png"
            for n in pend_g:
                gfx[n] = png
            pend_g = []
        m_blk = re.search(r'INCBIN "gfx/blocksets/(\w+)\.bst"', s)
        if m_blk:
            path = f"gfx/blocksets/{m_blk.group(1)}.bst"
            for n in pend_b:
                bst[n] = path
            pend_b = []
    return gfx, bst


def parse_collision_table():
    """label -> sorted list of passable tile ids (handles stacked labels)."""
    out, pending = {}, []
    for line in read("data/tilesets/collision_tile_ids.asm").splitlines():
        s = line.strip()
        m = re.match(r"(\w+)_Coll::", s)
        if m:
            pending.append(m.group(1))
            continue
        if s.startswith("coll_tiles"):
            args = strip_comment(s[len("coll_tiles"):])
            ids = sorted(int(x.strip().lstrip("$"), 16) for x in args.split(",") if x.strip())
            for n in pending:
                out[n] = ids
            pending = []
    return out


def _gb_rgba(im_l):
    """Grayscale image -> RGBA via the *absolute* GB shade index (white -> transparent,
    170/85/0 -> GB_PALETTE[1..3]). A brightness-rank stretch would wash a 4-shade pic out."""
    from PIL import Image
    w, h = im_l.size
    out = Image.new("RGBA", (w, h))
    sp, dp = im_l.load(), out.load()
    for y in range(h):
        for x in range(w):
            idx = round((255 - sp[x, y]) / 255 * 3)
            dp[x, y] = (0, 0, 0, 0) if idx == 0 else GB_PALETTE[idx] + (255,)
    return out


def _mon_sprite(src_png, dst):
    """Convert a Pokémon pic PNG (2-bit grayscale) to RGBA with the GB palette."""
    from PIL import Image
    _gb_rgba(Image.open(src_png).convert("L")).save(dst)


def parse_base_stats():
    """species (lowercase) -> {hp,atk,def,spd,spc,types,catch,base_exp,learnset,growth}."""
    out = {}
    for p in sorted((SRC / "data" / "pokemon" / "base_stats").glob("*.asm")):
        t = p.read_text()
        ms = re.search(r"db\s+(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\s*\n", t)
        mt = re.search(r"db\s+(\w+),\s*(\w+)\s*;\s*type", t)
        mc = re.search(r"db\s+(\d+)\s*;\s*catch rate", t)
        mx = re.search(r"db\s+(\d+)\s*;\s*base exp", t)
        ml = re.search(r"db\s+(\w+),\s*(\w+),\s*(\w+),\s*(\w+)\s*;\s*level\s*1 learnset", t)
        mg = re.search(r"db\s+(GROWTH_\w+)", t)
        if not (ms and mt and ml):
            continue
        learn = [m for m in ml.groups() if m != "NO_MOVE"]
        tmhm = []                                   # TM/HM compatibility (multi-line `tmhm` macro)
        mh = re.search(r"tmhm\s+(.*?)\n\s*;\s*end", t, re.S)
        if mh:
            tmhm = [w.strip() for w in mh.group(1).replace("\\", " ").split(",") if w.strip()]
        out[p.stem] = {
            "hp": int(ms[1]), "atk": int(ms[2]), "def": int(ms[3]),
            "spd": int(ms[4]), "spc": int(ms[5]),
            "types": [mt[1], mt[2]], "catch": int(mc[1]) if mc else 0,
            "base_exp": int(mx[1]) if mx else 0, "learnset": learn, "tmhm": tmhm,
            "growth": mg[1] if mg else "GROWTH_MEDIUM_FAST"}
    return out


def parse_evos_moves():
    """species -> {evolutions, level_moves:[[level, MOVE], ...]} from evos_moves.asm."""
    out = {}
    cur = None
    section = None
    for line in read("data/pokemon/evos_moves.asm").splitlines():
        s = line.split(";", 1)[0].strip()
        m = re.match(r"(\w+)EvosMoves:", s)
        if m:
            cur = m.group(1).lower()
            out[cur] = {"evolutions": [], "level_moves": []}
            section = "evo"
            continue
        if cur is None:
            continue
        if s == "db 0":
            section = "learn" if section == "evo" else None
            continue
        if section == "evo":
            me = re.match(r"db\s+(EVOLVE_\w+),\s*(.+)", s)
            if me:
                out[cur]["evolutions"].append([me.group(1)] + [x.strip() for x in me.group(2).split(",")])
        elif section == "learn":
            ml = re.match(r"db\s+(\d+),\s*(\w+)", s)
            if ml:
                out[cur]["level_moves"].append([int(ml.group(1)), ml.group(2)])
    return out


def parse_moves():
    """MOVE_CONST -> {name, power, type, accuracy, pp, effect}."""
    out = {}
    for line in read("data/moves/moves.asm").splitlines():
        m = re.match(r"\s*move\s+(\w+),\s*(\w+),\s*(\d+),\s*(\w+),\s*(\d+),\s*(\d+)", line)
        if m:
            out[m[1]] = {"name": m[1].replace("_", " "), "effect": m[2],
                         "power": int(m[3]), "type": m[4],
                         "accuracy": int(m[5]), "pp": int(m[6])}
    return out


def parse_type_chart():
    """nested {attacker: {defender: multiplier}} from TypeEffects (default 1.0)."""
    mult = {"SUPER_EFFECTIVE": 2.0, "NOT_VERY_EFFECTIVE": 0.5, "NO_EFFECT": 0.0}
    chart = {}
    for line in read("data/types/type_matchups.asm").splitlines():
        m = re.match(r"\s*db\s+(\w+),\s*(\w+),\s*(\w+)", line)
        if m and m[3] in mult:
            chart.setdefault(m[1], {})[m[2]] = mult[m[3]]
    return chart


def _mon_species(const):
    return const.lower().replace("_", "")     # NIDORAN_M -> nidoranm


def _parse_party(toks):
    toks = [t for t in toks if t]
    if toks and toks[-1] == "0":
        toks = toks[:-1]
    if not toks:
        return None
    mons = []
    if toks[0] in ("$FF", "-1"):              # explicit per-mon levels
        rest = toks[1:]
        for i in range(0, len(rest) - 1, 2):
            mons.append({"species": _mon_species(rest[i + 1]), "level": int(rest[i])})
    else:                                     # one level for the whole party
        lvl = int(toks[0])
        for t in toks[1:]:
            mons.append({"species": _mon_species(t), "level": lvl})
    return mons


def build_trainers(base):
    """OPP_CLASS -> {name, money, parties:[[{species,level},...], ...]}."""
    consts = []  # [NOBODY, YOUNGSTER, ...]
    for line in read("constants/trainer_constants.asm").splitlines():
        m = re.match(r"\s*trainer_const\s+(\w+)", line)
        if m:
            consts.append(m.group(1))
    text = read("data/trainers/parties.asm")
    labels = re.findall(r"\s*dw\s+(\w+Data)\b", text)
    parties_by_label = {}
    cur = None
    for line in text.splitlines():
        s = line.split(";", 1)[0].rstrip()
        ml = re.match(r"(\w+Data):", s)
        if ml:
            cur = ml.group(1)
            parties_by_label[cur] = []
            continue
        md = re.match(r"\s*db\s+(.+)", s)
        if cur and md:
            party = _parse_party([t.strip() for t in md.group(1).split(",")])
            if party:
                parties_by_label[cur].append(party)
    names = re.findall(r'\s*li\s+"(.+)"', text) or []
    names = re.findall(r'\s*li\s+"(.+)"', read("data/trainers/names.asm"))
    # pic_money stores 6 BCD digits (e.g. 1500), but GetAmountMoneyWon multiplies only the
    # middle byte by the last mon's level - the effective base is value/100 (gh #43).
    money = [int(x) // 100 for x in re.findall(r"pic_money\s+\w+,\s*(\d+)", read("data/trainers/pic_pointers_money.asm"))]
    # AI move-choice modification layers per class (data/trainers/move_choices.asm), and the
    # per-class item/switch AI with its use count (data/trainers/ai_pointers.asm).
    mods = [[int(n) for n in re.findall(r"\d", args)]
            for args in re.findall(r"^\tmove_choices([^;\n]*)",
                                    read("data/trainers/move_choices.asm"), re.M)]
    ai = re.findall(r"dbw (\d+), (\w+)AI", read("data/trainers/ai_pointers.asm"))
    out = {}
    for i, label in enumerate(labels):
        if i + 1 >= len(consts):
            break
        clean = []
        for p in parties_by_label.get(label, []):
            clean.append([m for m in p if m["species"] in base])
        out["OPP_" + consts[i + 1]] = {
            "name": names[i] if i < len(names) else consts[i + 1],
            "money": money[i] if i < len(money) else 0,
            "ai_mods": mods[i] if i < len(mods) else [],
            "ai": ai[i][1] if i < len(ai) else "Generic",
            "ai_count": int(ai[i][0]) if i < len(ai) else 3,
            "parties": clean}
    json.dump(out, open(OUT / "trainers.json", "w"), indent=1)
    print(f"trainers: {len(out)} classes")


def build_trades():
    """In-game NPC trades: TradeMons (give->get->nick) + a TEXT_id -> trade-index map.

    Each trade-house NPC's text_asm handler sets `ld a, TRADE_FOR_x`; that handler label
    is also the dw_const target for a TEXT_ constant, so we can map the NPC's text id to
    the trade it performs.
    """
    def slug(const):
        return const.lower().replace("_", "")

    # TRADE_DIALOGSET_* -> InGameTradeTextPointers index (constants/script_constants.asm)
    dialogsets = {"TRADE_DIALOGSET_CASUAL": 0, "TRADE_DIALOGSET_EVOLUTION": 1, "TRADE_DIALOGSET_HAPPY": 2}
    trades = []
    for m in re.finditer(r'npctrade\s+(\w+),\s*(\w+),\s*(\w+),\s*"([^"]*)"', read("data/events/trades.asm")):
        trades.append({"give": slug(m.group(1)), "get": slug(m.group(2)), "nick": m.group(4),
                       "dialogset": dialogsets[m.group(3)]})

    order = re.findall(r"\s*const\s+(TRADE_FOR_\w+)", read("constants/script_constants.asm"))

    label_trade, label_text = {}, {}
    for p in (SRC / "scripts").glob("*.asm"):
        s = p.read_text(encoding="utf-8")
        for mm in re.finditer(r"dw_const\s+(\w+),\s*(TEXT_\w+)", s):
            label_text[mm.group(1)] = mm.group(2)
        cur = None
        for line in s.splitlines():
            ml = re.match(r"(\w+):", line)
            if ml:
                cur = ml.group(1)
            mt = re.search(r"ld a,\s*(TRADE_FOR_\w+)", line)
            if cur and mt and mt.group(1) in order:
                label_trade[cur] = mt.group(1)

    text_trades = {}
    for label, tconst in label_trade.items():
        if label in label_text:
            text_trades[label_text[label]] = order.index(tconst)

    json.dump({"trades": trades, "text_trades": text_trades},
              open(OUT / "trades.json", "w"), indent=1)
    print(f"trades: {len(trades)} trades, {len(text_trades)} NPC trade texts")


def _parse_audio_cmd(line):
    """One asm audio line -> a compact [op, args...] command, or None to skip."""
    s = line.split(";", 1)[0].strip()
    if not s:
        return None
    if s.endswith(":") and not s.endswith("::"):     # local label (loop target)
        return ["label", s[:-1]]
    parts = s.split(None, 1)
    op = parts[0]
    args = [a.strip() for a in parts[1].split(",")] if len(parts) > 1 else []
    def ints(n):
        return [int(a, 0) for a in args[:n]]
    if op == "note":
        return ["note", args[0].rstrip("_"), int(args[1])]
    if op == "rest":
        return ["rest", int(args[0])]
    if op == "octave":
        return ["octave", int(args[0])]
    if op == "note_type":
        return ["note_type"] + ints(3)
    if op == "duty_cycle":
        return ["duty", int(args[0])]
    if op == "duty_cycle_pattern":
        return ["dutypat"] + ints(4)      # rotates one step per frame (Audio1_ApplyDutyCyclePattern)
    if op == "tempo":
        return ["tempo", int(args[0])]
    if op == "volume":
        return ["volume"] + ints(2)
    if op == "drum_note":
        return ["drum", int(args[0]), int(args[1])]
    if op == "drum_speed":
        return ["drumspeed", int(args[0])]
    if op == "pitch_sweep":
        # time [0-7] (0 = off), shift signed [-7, 7] or 8 = "negative zero" = off. Hardware
        # sweep on square channel 1: every time/128 s, period +=/-= period >> |shift|.
        return ["sweep", int(args[0]), int(args[1])]
    if op == "square_note":
        return ["snote", int(args[0]), int(args[1]), int(args[2]), int(args[3], 0)]
    if op == "noise_note":
        return ["nnote", int(args[0]), int(args[1]), int(args[2]), int(args[3], 0)]
    if op == "sound_loop":
        return ["loop", int(args[0]), args[1]]
    if op == "sound_call":
        return ["call", args[0]]
    if op == "sound_ret":
        return ["ret"]
    if op == "vibrato":
        return ["vibrato"] + ints(3)                  # delay, depth, rate (macros/scripts/audio.asm)
    if op == "toggle_perfect_pitch":
        return ["ppitch"]                             # +1 on every note's frequency while on
    if op == "pitch_slide":
        return ["slide", int(args[0]), int(args[1]), args[2].rstrip("_")]  # length, octave, note
    return None                                        # execute_music/panning/etc: ignored


def build_audio():
    """Per-song channel command lists + a map->song lookup (GB music synthesized in-engine)."""
    # MUSIC_X -> song key (e.g. MUSIC_PALLET_TOWN -> "pallettown").
    song_key = {}
    for m in re.finditer(r"music_const\s+(MUSIC_\w+),\s*Music_(\w+)", read("constants/music_constants.asm")):
        song_key[m.group(1)] = m.group(2).lower()
    # song label -> [(hw_channel, channel_label)], from the music headers; remember each
    # song's audio bank (1-3) — the glitch wave-5 instrument differs per bank.
    headers = {}
    song_bank = {}
    for bank, hf in enumerate(["musicheaders1.asm", "musicheaders2.asm", "musicheaders3.asm"], 1):
        cur = None
        for line in read("audio/headers/" + hf).splitlines():
            ml = re.match(r"Music_(\w+)::", line)
            if ml:
                cur = ml.group(1).lower(); headers[cur] = []; song_bank[cur] = bank
                continue
            mc = re.match(r"\s*channel\s+(\d+),\s*(\w+)", line)
            if cur and mc:
                headers[cur].append((int(mc.group(1)), mc.group(2)))
    # channel label -> command list, from every music file.
    chan_cmds = {}
    for p in (SRC / "audio" / "music").glob("*.asm"):
        cur = None
        for line in p.read_text(encoding="utf-8").splitlines():
            ml = re.match(r"(Music_\w+)::", line)
            if ml:
                cur = ml.group(1); chan_cmds[cur] = []
                continue
            if cur is not None:
                c = _parse_audio_cmd(line)
                if c is not None:
                    chan_cmds[cur].append(c)
    # Inline sound_call targets that live in another channel's block (Music_FinalBattle_Ch1
    # borrows Music_FinalBattle_Ch2.sub2): splice the sub's commands in place of the call —
    # per-channel label scopes can't see across blocks, so the call would silently drop bars.
    def _sub_cmds(target):
        blk, _, loc = target.partition(".")
        cmds = chan_cmds.get(blk, [])
        try:
            i = cmds.index(["label", "." + loc])
        except ValueError:
            return None
        out = []
        for c in cmds[i + 1:]:
            if c[0] == "ret":
                break
            out.append(c)
        return out
    for lbl in chan_cmds:
        local = {c[1] for c in chan_cmds[lbl] if c[0] == "label"}
        out = []
        for c in chan_cmds[lbl]:
            if c[0] == "call" and "." in c[1] and c[1] not in local:
                sub = _sub_cmds(c[1])
                if sub is not None:
                    out.extend(sub)
                    continue
            out.append(c)
        chan_cmds[lbl] = out
    # The rival jingle's alternate entry (audio/alternate_tempo.asm Music_RivalAlternateStart,
    # used for his walk-offs/arrivals): each channel plays its short _AlternateStart intro then
    # jumps into the main channel's .mainloop — spliced here into a "meetrival_alt" song.
    if "meetrival" in headers:
        for hw, lbl in headers["meetrival"]:
            alt = chan_cmds[lbl + "_AlternateStart"]
            jump = next(c for c in alt if c[0] == "loop")        # ["loop", 0, "Music_..mainloop"]
            target = "." + str(jump[2]).split(".")[-1]
            main = chan_cmds[lbl]
            idx = next(i for i, c in enumerate(main) if c == ["label", target])
            chan_cmds[lbl + "_AltSpliced"] = [c for c in alt if c[0] != "loop"] + main[idx:]
        headers["meetrival_alt"] = [(hw, lbl + "_AltSpliced") for hw, lbl in headers["meetrival"]]
    songs = {}
    for key, chans in headers.items():
        out_ch = []
        for hw, label in chans:
            if label in chan_cmds:
                out_ch.append({"hw": hw, "cmds": chan_cmds[label]})
        if out_ch:
            songs[key] = {"channels": out_ch, "bank": song_bank.get(key, 1)}
    songs["meetrival_alt"]["bank"] = song_bank.get("meetrival", 1)
    # Channel-3 wave instruments (audio/wave_samples.asm): waves 0-4 are real 32-nibble
    # tables; ids 5-8 hit the glitch .wave5, which reads the ROM bytes that happen to follow
    # — different per audio bank (Lavender Town's eerie lead is bank 1's garbage). The asm
    # documents each bank's effective bytes in comments; extract those as _wave5[bank].
    wtxt = read("audio/wave_samples.asm")
    songs["_waves"] = [[int(v) for v in m.group(1).replace(",", " ").split()]
                       for m in re.finditer(r"\n\s*dn\s+([0-9,\s]+)", wtxt)]
    songs["_wave5"] = {m.group(1): [int(v) for v in m.group(2).replace(",", " ").split()]
                       for m in re.finditer(r"; in audio (\d):[^\n]*\n;\s*dn\s+([0-9,\s]+)", wtxt)}
    json.dump(songs, open(OUT / "audio.json", "w"), indent=1)
    print(f"audio: {len(songs) - 2} songs, {len(songs['_waves'])} waves + "
          f"{len(songs['_wave5'])} wave5 banks")
    build_sfx()
    build_cries()


def song_by_map_const():
    """MAP_CONST -> song key (e.g. PALLET_TOWN -> pallettown), from songs.asm + music_constants."""
    song_key = {}
    for m in re.finditer(r"music_const\s+(MUSIC_\w+),\s*Music_(\w+)", read("constants/music_constants.asm")):
        song_key[m.group(1)] = m.group(2).lower()
    out = {}
    for m in re.finditer(r"db\s+(MUSIC_\w+),\s*BANK\([^)]*\)\s*;\s*(\w+)", read("data/maps/songs.asm")):
        if m.group(1) in song_key:
            out[m.group(2)] = song_key[m.group(1)]
    return out


def _norm_species(name):
    return (name.lower().replace("♂", "m").replace("♀", "f")
            .replace(".", "").replace("'", "").replace("-", "").replace(" ", ""))


def build_credits():
    """The end credits (engine/movie/credits.asm). Each page is
    {lines: [[col_offset, text], ...], fade, mon, copyright} — the four terminator commands
    ($FC-$FF CRED_TEXT[_FADE][_MON]) end a page, `FADE` = the text fades in, `_MON` scrolls the
    next CreditsMons silhouette as the transition; CRED_COPYRIGHT ($FB) marks the © page;
    CRED_THE_END ($FA) is the final THE END screen (handled by the runner). Each credit string
    carries a leading signed byte = its column offset from base column 9 (hlcoord 9, 6)."""
    txt = read("data/credits/credits_text.asm")
    txt = re.sub(r"IF DEF\(_BLUE\).*?ENDC", "", txt, flags=re.S)          # Red version strings
    txt = txt.replace("IF DEF(_RED)", "").replace("ENDC", "")
    label_text, cur = {}, None
    for line in txt.splitlines():
        m = re.match(r"(Cred\w+):", line)
        if m:
            cur = m.group(1)
            continue
        dm = re.search(r'db\s+(-?\d+),\s*"([^"@]*)@"', line)              # offset byte + text
        if cur and dm:
            label_text[cur] = [int(dm.group(1)), dm.group(2).replace("#", "POKé")]  # # = POKé
            cur = None
    pointers = re.findall(r"dw\s+(Cred\w+)", read("data/credits/credits_text.asm"))
    consts = re.findall(r"const\s+(CRED_\w+)", read("constants/credits_constants.asm"))
    cred_text = {consts[i]: label_text.get(pointers[i])                   # text index -> [off, str]
                 for i in range(min(len(consts), len(pointers)))}
    mons = [_norm_species(m) for m in re.findall(r"db\s+(\w+)", read("data/credits/credits_mons.asm"))]
    terms = {"CRED_TEXT", "CRED_TEXT_FADE", "CRED_TEXT_MON", "CRED_TEXT_FADE_MON"}
    pages, lines, copyright, mi = [], [], False, 0
    order = re.sub(r";[^\n]*", "", read("data/credits/credits_order.asm"))   # drop the header comment
    for tok in re.findall(r"CRED_\w+", order):
        if tok in terms:
            mon = None
            if tok.endswith("_MON"):
                mon = mons[mi] if mi < len(mons) else None
                mi += 1
            pages.append({"lines": lines, "fade": "FADE" in tok, "mon": mon, "copyright": copyright})
            lines, copyright = [], False
        elif tok == "CRED_COPYRIGHT":
            copyright = True
        elif tok == "CRED_THE_END":
            pass                                                          # the runner draws THE END
        elif cred_text.get(tok):
            lines.append(cred_text[tok])
    json.dump(pages, open(OUT / "credits.json", "w", encoding="utf-8"), indent=1)
    # THE END graphic (gfx/credits/the_end.png): dark ink on transparency, drawn on the white band.
    from PIL import Image
    te = Image.open(SRC / "gfx" / "credits" / "the_end.png").convert("L")
    light = max(te.getdata())
    out = Image.new("RGBA", te.size)
    s, d = te.load(), out.load()
    for y in range(te.size[1]):
        for x in range(te.size[0]):
            d[x, y] = (0, 0, 0, 0) if s[x, y] == light else (*GB_PALETTE[3], 255)
    out.save(OUT / "credits_the_end.png")
    print(f"credits: {len(pages)} pages, {mi} mon slides")


def build_town_map():
    """The Kanto town map: composite the RLE tilemap + tile sheet into one PNG, the cursor sprite,
    and the cycle entries (x, y, name) in TownMapOrder with a label->index start table."""
    from PIL import Image
    sheet = Image.open(SRC / "gfx" / "town_map" / "town_map.png").convert("L")   # 4x4 grid of 8x8 tiles
    rle = (SRC / "gfx" / "town_map" / "town_map.rle").read_bytes()
    tiles = []
    for byte in rle:                                    # each byte: (tile << 4) | run length
        if byte == 0:
            break
        tiles.extend([byte >> 4] * (byte & 0xF))
    W, H = 20, 18
    grid = Image.new("L", (W * 8, H * 8))
    for i, t in enumerate(tiles[:W * H]):
        sx, sy = (t % 4) * 8, (t // 4) * 8
        grid.paste(sheet.crop((sx, sy, sx + 8, sy + 8)), ((i % W) * 8, (i // W) * 8))
    rgba = Image.new("RGBA", grid.size)                 # opaque GB shades (white = lightest, not clear)
    s, d = grid.load(), rgba.load()
    for y in range(H * 8):
        for x in range(W * 8):
            d[x, y] = GB_PALETTE[round((255 - s[x, y]) / 255 * 3)] + (255,)
    rgba.save(OUT / "town_map.png")
    _gb_rgba(Image.open(SRC / "gfx" / "town_map" / "town_map_cursor.png").convert("L")).save(
        OUT / "town_map_cursor.png")

    names = dict(re.findall(r'(\w+):\s*db\s*"([^"@]*)@?"', read("data/maps/names.asm")))
    entries_txt = read("data/maps/town_map_entries.asm")
    order_consts = list(parse_map_constants().keys())   # ExternalMapEntries is indexed by map const
    ext_rows = re.findall(r"outdoor_map\s+(\d+),\s*(\d+),\s*(\w+)", entries_txt)
    loc = {}
    for i, (x, y, nm) in enumerate(ext_rows):
        if i < len(order_consts):
            loc[order_consts[i]] = (int(x), int(y), names.get(nm, nm))
    for mc, x, y, nm in re.findall(r"indoor_map\s+(\w+),\s*(\d+),\s*(\d+),\s*(\w+)", entries_txt):
        loc.setdefault(mc, (int(x), int(y), names.get(nm, nm)))   # external wins where both exist

    const_to_label = {}
    for p in (SRC / "data" / "maps" / "headers").glob("*.asm"):
        h = parse_map_header(p)
        if h["label"] and h["map_const"]:
            const_to_label[h["map_const"]] = h["label"]

    entries, start = [], {}
    for mc in re.findall(r"db\s+(\w+)", read("data/maps/town_map_order.asm")):
        if mc not in loc:
            continue
        x, y, nm = loc[mc]
        if const_to_label.get(mc):
            start[const_to_label[mc]] = len(entries)
        entries.append({"x": x, "y": y, "name": nm})
    json.dump({"entries": entries, "start": start},
              open(OUT / "town_map.json", "w", encoding="utf-8"), indent=1)
    print(f"town_map: {len(entries)} cycle entries, {len(start)} start labels")


def build_move_sfx():
    """MOVE_CONST -> [sfx_key, pitch] from MoveSoundTable (data/moves/sfx.asm). The sound plays when
    the move is used; the pitch byte (frequency modifier) distinguishes moves that share a base SFX."""
    out = {}
    for sfx, pitch, _tempo, mv in re.findall(
            r"db\s+(SFX_\w+),\s*\$([0-9a-fA-F]+),\s*\$([0-9a-fA-F]+)\s*;\s*(\w+)",
            read("data/moves/sfx.asm")):
        out[mv] = [sfx[4:].lower(), int(pitch, 16)]
    json.dump(out, open(OUT / "move_sfx.json", "w"), indent=1)
    print(f"move_sfx: {len(out)} moves")


def build_move_anims():
    """Per-move battle animation data (gh #19 phase 1): pokered's DrawFrameBlock system
    (engine/battle/animations.asm) -> move_anims.json + the move_anim_0/1 tile sheets as RGBA.

    Data model (all ids are list indexes; see docs/data-formats/battle-anims.md):
      - anims: move/anim const -> command list. Each command starts a move's SFX (the move_sfx.json
        key, null = silent) and either plays a subanimation {sub, tileset, delay} or runs a special
        effect {se} (code, kept by SE_* name; the ~25 routines are engine work, phases 2-3).
      - subanims: transform type (SUBANIMTYPE_*: 0 normal / 1 hvflip / 2 hflip+40px-down /
        3 coordflip / 4 reverse / 5 enemy) + [frame block, base coord, mode] frames. The type
        applies on the *enemy's* turn; the player's turn plays untransformed (type 5: hflip on the
        player's turn, normal on the enemy's) — GetSubanimationTransform1/2.
      - frame_blocks: one frame's sprites as [x, y, tile, xflip, yflip], px offsets from the base
        coord (dbsprite col/row*8 + xpix/ypix). Tiles are raw sheet indexes (GB adds $31, the
        vSprites load slot). Modes (FRAMEBLOCKMODE_*): 00 delay+erase (each frame replaces the
        last), 02 no delay+keep, 03 delay+keep, 04 delay+keep+next overwrites in place.
      - base_coords: [x, y] anchors in OAM space (screen px = x-8, y-16); COORDFLIP mirrors
        them as x'=168-x, y'=136-y (HVFLIP mirrors final coords the same way).
      - tilesets: battle_anim tileset id -> {img, tiles}; tileset 2 is move_anim_0's sheet capped
        at 64 tiles (MoveAnimationTilesPointers).
      - anim_special_effects: anim const -> routine run after *every* frame block of that anim
        (DoSpecialEffectByAnimationId, data/battle_anims/special_effects.asm), e.g. the per-block
        screen flash of MEGA_PUNCH."""
    from PIL import Image
    for n in (0, 1):
        _gb_rgba(Image.open(SRC / "gfx" / "battle" / f"move_anim_{n}.png").convert("L")).save(
            OUT / f"move_anim_{n}.png")

    ba_text = read("constants/move_animation_constants.asm")
    def const_indices(prefix):
        return {n: i for i, n in enumerate(re.findall(r"^\s*const\s+(%s\w+)" % prefix, ba_text, re.M))}
    subanim_ids = const_indices("SUBANIM_")
    subanim_types = const_indices("SUBANIMTYPE_")
    fb_ids = const_indices("FRAMEBLOCK_")
    bc_ids = const_indices("BASECOORD_")
    mode_ids = const_indices("FRAMEBLOCKMODE_")

    # base coords: `db $Y, $X` in index order -> [x, y]
    base_coords = [[int(x, 16), int(y, 16)] for y, x in re.findall(
        r"db\s+\$([0-9A-Fa-f]+),\s*\$([0-9A-Fa-f]+)", read("data/battle_anims/base_coords.asm"))]

    # frame blocks: `db count` + count * `dbsprite col, row, xpix, ypix, tile, flags`
    fb_text = read("data/battle_anims/frame_blocks.asm")
    fb_order = re.findall(r"^\s*dw\s+(\w+)", fb_text, re.M)
    by_label, counts, cur = {}, {}, None
    for line in fb_text.splitlines():
        line = strip_comment(line)
        m = re.match(r"(\w+):", line)
        if m:
            cur = m.group(1); by_label[cur] = []
            continue
        m = re.match(r"\s*db\s+(\d+)", line)
        if m and cur:
            counts[cur] = int(m.group(1))
            continue
        m = re.match(r"\s*dbsprite\s+(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*\$([0-9A-Fa-f]+),\s*(.+)", line)
        if m and cur:
            col, row, xp, yp = (int(v) for v in m.groups()[:4])
            by_label[cur].append([col * 8 + xp, row * 8 + yp, int(m.group(5), 16),
                                  1 if "OAM_XFLIP" in m.group(6) else 0,
                                  1 if "OAM_YFLIP" in m.group(6) else 0])
    # The engine draws exactly the declared count, so trust it: FrameBlock62 lists 16 sprites but
    # declares `db 15` — its last sprite is dead data in pokered.
    for label, n in counts.items():
        assert len(by_label[label]) >= n, f"frame block {label}: {len(by_label[label])} sprites < count {n}"
        by_label[label] = by_label[label][:n]
    frame_blocks = [by_label[l] for l in fb_order]

    # subanimations: `subanim SUBANIMTYPE_x, count` + count * `db FRAMEBLOCK, BASECOORD, MODE`
    sa_text = read("data/battle_anims/subanimations.asm")
    sa_order = re.findall(r"^\s*dw\s+(\w+)", sa_text, re.M)
    sa_by_label, cur = {}, None
    for line in sa_text.splitlines():
        line = strip_comment(line)
        m = re.match(r"(Subanim_\w+):", line)
        if m:
            cur = m.group(1); sa_by_label[cur] = {"type": 0, "frames": []}
            continue
        m = re.match(r"\s*subanim\s+(\w+),\s*(\d+)", line)
        if m and cur:
            sa_by_label[cur]["type"] = subanim_types[m.group(1)]
            continue
        m = re.match(r"\s*db\s+(FRAMEBLOCK_\w+),\s*(BASECOORD_\w+),\s*(FRAMEBLOCKMODE_\w+)", line)
        if m and cur:
            sa_by_label[cur]["frames"].append([fb_ids[m.group(1)], bc_ids[m.group(2)], mode_ids[m.group(3)]])
    subanims = [sa_by_label[l] for l in sa_order]

    # animation scripts: `battle_anim sound, SE_x` or `battle_anim sound, SUBANIM_x, tileset, delay`,
    # each ended by `db -1`; stacked labels (PoundAnim/StruggleAnim) share one script.
    an_text = read("data/moves/animations.asm")
    an_order = re.findall(r"^\s*dw\s+(\w+)", an_text, re.M)
    scripts, pending, cur = {}, [], None
    for line in an_text.splitlines():
        line = strip_comment(line)
        m = re.match(r"(\w+):", line)
        if m:
            pending.append(m.group(1))
            continue
        m = re.match(r"\s*battle_anim\s+(.+)", line)
        if m:
            if pending:
                cur = []
                for l in pending:
                    scripts[l] = cur
                pending = []
            args = [a.strip() for a in m.group(1).split(",")]
            sfx = None if args[0] == "NO_MOVE" else args[0]
            if len(args) == 2:                                     # special effect
                cur.append({"sfx": sfx, "se": args[1][3:].lower()})  # SE_WAVY_SCREEN -> wavy_screen
            else:                                                  # subanimation
                cur.append({"sfx": sfx, "sub": subanim_ids[args[1]],
                            "tileset": int(args[2]), "delay": int(args[3])})
            continue
        if re.match(r"\s*db\s+-1", line):
            cur, pending = None, []

    # AttackAnimationPointers order == move-id order (constants/move_constants.asm), then the
    # post-NUM_ATTACKS anim ids (SHOWPIC_ANIM..BAIT_ANIM), then the const-less ZigZagScreenAnim.
    consts = [c for c in re.findall(r"^\s*const\s+(\w+)", read("constants/move_constants.asm"), re.M)
              if c != "NO_MOVE"] + ["ZIGZAG_SCREEN_ANIM"]
    assert len(consts) == len(an_order), f"anim pointers ({len(an_order)}) != move consts ({len(consts)})"
    anims = {c: scripts[l] for c, l in zip(consts, an_order)}

    per_anim_se = dict(re.findall(r"anim_special_effect\s+(\w+),\s*(\w+)",
                                  read("data/battle_anims/special_effects.asm")))

    tilesets = [{"img": f"move_anim_{i}", "tiles": t} for i, t in [(0, 79), (1, 79), (0, 64)]]
    for cmds in anims.values():                                    # referential sanity
        for c in cmds:
            if "sub" in c:
                assert c["sub"] < len(subanims) and c["tileset"] <= 2 and c["delay"] < 64
    for sa in subanims:
        for fb, bc, mode in sa["frames"]:
            assert fb < len(frame_blocks) and bc < len(base_coords) and mode <= 4
    json.dump({"tilesets": tilesets, "base_coords": base_coords, "frame_blocks": frame_blocks,
               "subanims": subanims, "anims": anims, "anim_special_effects": per_anim_se},
              open(OUT / "move_anims.json", "w"), indent=1)
    print(f"move_anims: {len(anims)} anims, {len(subanims)} subanims, {len(frame_blocks)} frame "
          f"blocks, {len(base_coords)} base coords, {len(per_anim_se)} per-anim SEs + 2 tile sheets")


def build_sfx():
    """Sound effects + cries, keyed by name. Reads the engine-1 bank and the engine-2 bank (which
    holds the battle SFX: damage / effectiveness / faint / ball / run); engine 1 wins shared names."""
    def read_headers(fname):
        hd, cur = {}, None
        for line in read(fname).splitlines():
            ml = re.match(r"(SFX_\w+)::", line)
            if ml:
                cur = ml.group(1); hd[cur] = []
                continue
            mc = re.match(r"\s*channel\s+(\d+),\s*(\w+)", line)
            if cur and mc:
                hd[cur].append((int(mc.group(1)), mc.group(2)))
        return hd
    chan_cmds = {}
    for p in (SRC / "audio" / "sfx").glob("*.asm"):
        cur = None
        for line in p.read_text(encoding="utf-8").splitlines():
            ml = re.match(r"(SFX_[A-Za-z0-9_]+):", line)
            if ml and not line.startswith(" ") and not line.startswith("\t"):
                cur = ml.group(1).rstrip(":"); chan_cmds[cur] = []
                continue
            if cur is not None:
                c = _parse_audio_cmd(line)
                if c is not None:
                    chan_cmds[cur].append(c)
    sfx = {}
    for fname, suffix in [("audio/headers/sfxheaders1.asm", "_1"),
                          ("audio/headers/sfxheaders2.asm", "_2"),
                          ("audio/headers/sfxheaders3.asm", "_3")]:   # engine 3: the boot-intro SFX
        for label, chans in read_headers(fname).items():
            key = re.sub(suffix + r"$", "", label[4:]).lower()   # SFX_Press_AB_1 -> press_ab
            if key in sfx:                                        # engine 1 wins on shared names
                continue
            out_ch = []
            for hw, clabel in chans:
                if clabel in chan_cmds:
                    out_ch.append({"hw": ((hw - 1) % 4) + 1, "cmds": chan_cmds[clabel]})  # 5-8 -> 1-4
            if out_ch:
                sfx[key] = {"channels": out_ch}
    json.dump(sfx, open(OUT / "sfx.json", "w"), indent=1)
    print(f"sfx: {len(sfx)} effects")


def build_items():
    """Item constant -> display name (assets/items.json). Regular/key items zip ItemNames with the
    `const` list (shared item-id order); TMs/HMs become TMnn/HMnn from the add_tm/add_hm order."""
    names = []
    for line in read("data/items/names.asm").splitlines():
        m = re.match(r'\s*li\s+"(.*)"', line)
        if m:
            names.append(m.group(1))               # literal (already has é etc.)
    prices_by_id = []                              # ItemPrices, item-id order (id 1 = index 0)
    for line in read("data/items/prices.asm").splitlines():
        m = re.match(r"\s*bcd3\s+(\d+)", strip_comment(line))
        if m:
            prices_by_id.append(int(m.group(1)))
    items = {}
    prices = {}                                    # display name -> buy price
    tm_moves = {}                                   # TMnn -> move const it teaches
    idx = 0                                         # item id counter (NO_ITEM = 0, unnamed)
    tm = hm = 0
    for line in read("constants/item_constants.asm").splitlines():
        s = strip_comment(line).strip()
        m = re.match(r"const\s+(\w+)\s*$", s)
        if m:
            if 1 <= idx <= len(names):
                items[m.group(1)] = names[idx - 1]
                # Glitch slots (const ITEM_xx) can share a display name with a real item —
                # ITEM_32 is a second "PP UP" priced 9800, while the real PP_UP is 0
                # (unsellable, like the Ethers/Elixers). Never let a glitch slot price the
                # real item (gh #176).
                if not m.group(1).startswith("ITEM_") \
                        and idx - 1 < len(prices_by_id) and prices_by_id[idx - 1] > 0:
                    prices[names[idx - 1]] = prices_by_id[idx - 1]
            idx += 1
            continue
        m = re.match(r"add_tm\s+(\w+)", s)
        if m:
            tm += 1
            items["TM_" + m.group(1)] = "TM%02d" % tm
            tm_moves["TM%02d" % tm] = m.group(1)   # e.g. TM11 -> BUBBLEBEAM
            continue
        m = re.match(r"add_hm\s+(\w+)", s)
        if m:
            hm += 1
            items["HM_" + m.group(1)] = "HM%02d" % hm
    # TMs are 0 in the generic ItemPrices table — they're priced by a separate nybble table
    # (data/items/tm_prices.asm; each nybble is the price in thousands; GetMachinePrice reads it).
    # Without this the Celadon TM mart shows every price as 0 (gh #132). HMs stay priceless.
    tm_nybbles = []
    for line in read("data/items/tm_prices.asm").splitlines():
        m = re.match(r"\s*nybble\s+(\d+)", strip_comment(line))
        if m:
            tm_nybbles.append(int(m.group(1)))
    for i, n in enumerate(tm_nybbles, start=1):
        prices["TM%02d" % i] = n * 1000
    json.dump(items, open(OUT / "items.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    json.dump(prices, open(OUT / "item_prices.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    json.dump(tm_moves, open(OUT / "tm_moves.json", "w"), indent=1)
    print(f"items: {len(items)} names ({tm} TMs, {hm} HMs), {len(prices)} priced")


def build_hidden_items(const_to_label):
    """Map label -> [{x, y, item const}] for hidden (invisible) items, from the `HiddenItems`
    entries grouped under `hidden_events_for <MAP>` in data/events/hidden_events.asm."""
    out = {}
    cur = None
    for line in read("data/events/hidden_events.asm").splitlines():
        s = strip_comment(line).strip()
        m = re.match(r"hidden_events_for\s+(\w+)", s)
        if m:
            cur = const_to_label.get(m.group(1))
            continue
        m = re.match(r"hidden_event\s+(\d+)\s*,\s*(\d+)\s*,\s*HiddenItems\s*,\s*(\w+)", s)
        if m and cur:
            out.setdefault(cur, []).append({"x": int(m.group(1)), "y": int(m.group(2)), "item": m.group(3)})
    json.dump(out, open(OUT / "hidden_items.json", "w"), indent=1)
    print(f"hidden items: {sum(len(v) for v in out.values())} across {len(out)} maps")


def build_dex():
    """National-dex-ordered species list (assets/dex_order.json) from constants/pokedex_constants.asm
    (`const DEX_<NAME>`), lowercased to match base_stats keys."""
    order = []
    for line in read("constants/pokedex_constants.asm").splitlines():
        m = re.match(r"\s*const\s+DEX_(\w+)", line)
        if m:
            # DEX_NIDORAN_M etc keep the underscore; every other asset (base_stats, wild,
            # pics) uses the squashed slug - normalize so species keys match everywhere.
            order.append(m.group(1).lower().replace("_", ""))
    json.dump(order, open(OUT / "dex_order.json", "w"), indent=1)
    print(f"dex: {len(order)} species in order")


def build_marts():
    """Map label -> list of item consts a mart sells (data/items/marts.asm `script_mart …`,
    keyed by the `<Map>Clerk…Text` label)."""
    marts = {}
    label = None
    for line in read("data/items/marts.asm").splitlines():
        s = strip_comment(line).strip()
        m = re.match(r"(\w+?)Clerk\w*Text::", s)
        if m:
            label = m.group(1)
            continue
        m = re.match(r"script_mart\s+(.+)", s)
        if m and label:
            marts[label] = [t.strip() for t in m.group(1).split(",")]
            label = None
    json.dump(marts, open(OUT / "marts.json", "w"), indent=1)
    print(f"marts: {len(marts)} inventories")


def build_cries():
    """species -> {cry sfx key, pitch, length} from CryData (added to freq / sfx tempo)."""
    cries = {}
    for m in re.finditer(r"mon_cry\s+SFX_CRY_(\w+),\s*(\$[0-9A-Fa-f]+),\s*(\$[0-9A-Fa-f]+)\s*;\s*(.+)",
                         read("data/pokemon/cries.asm")):
        cries[_norm_species(m.group(4).strip())] = {
            "cry": "cry" + m.group(1).lower(),
            "pitch": int(m.group(2)[1:], 16),
            "length": int(m.group(3)[1:], 16)}
    json.dump(cries, open(OUT / "cries.json", "w"), indent=1)
    print(f"cries: {len(cries)} species")


def build_title():
    """Title + intro graphics (logo, Game Freak, shooting star, 3 Nidorino + 3 Gengar intro
    frames) and the cycling title-mon list."""
    from PIL import Image
    (OUT / "title").mkdir(parents=True, exist_ok=True)
    for f in ["pokemon_logo", "gamefreak_inc"]:
        _mon_sprite(SRC / "gfx" / "title" / f"{f}.png", OUT / "title" / f"{f}.png")
    # Oak's-speech intro pics (56x56): Prof. Oak, the rival, and Red's front pic.
    _mon_sprite(SRC / "gfx" / "trainers" / "prof.oak.png", OUT / "title" / "oak.png")
    _mon_sprite(SRC / "gfx" / "trainers" / "rival1.png", OUT / "title" / "rival.png")
    _mon_sprite(SRC / "gfx" / "player" / "red.png", OUT / "title" / "redfront.png")
    # Shrink frames for the end-of-speech "trainer shrinks into the overworld sprite" animation.
    _mon_sprite(SRC / "gfx" / "player" / "shrink1.png", OUT / "title" / "shrink1.png")
    _mon_sprite(SRC / "gfx" / "player" / "shrink2.png", OUT / "title" / "shrink2.png")
    # Red trainer + the Poké Ball in his hand. The ball (tile at local (0,16)) is a separate sprite
    # so it can hop, so extract it and blank it from the trainer body.
    from PIL import ImageDraw
    ptrain = Image.open(SRC / "gfx" / "title" / "player.png").convert("L")
    _gb_rgba(ptrain.crop((0, 16, 8, 24))).save(OUT / "title" / "ball.png")
    ptrain = ptrain.copy()
    ImageDraw.Draw(ptrain).rectangle((0, 16, 7, 23), fill=255)
    _gb_rgba(ptrain).save(OUT / "title" / "player.png")
    # Version_GFX (red_version.png) packs "RedGreenVersion"; the retail Red title reads
    # "Red Version", so compose it from the graphic's own letters (Red=[0:21], Version=[46:77]).
    rv = Image.open(SRC / "gfx" / "title" / "red_version.png").convert("L")
    red, vsn = rv.crop((0, 0, 16, 8)), rv.crop((40, 0, 80, 8))   # "Version" starts at the V (col 40)
    ver = Image.new("L", (16 + 4 + 40, 8), 255)
    ver.paste(red, (0, 0))
    ver.paste(vsn, (20, 0))
    _gb_rgba(ver).save(OUT / "title" / "red_version.png")
    _mon_sprite(SRC / "gfx" / "splash" / "gamefreak_logo.png", OUT / "title" / "gamefreak_logo.png")
    # "GAME FREAK" wordmark. This pokered clone's gamefreak_presents.png is a *condensed* variant
    # (it packs "EAK" into one glyph), so reconstruct from its clean letter tiles placed one-per-
    # 8px-tile, reusing the GAME "E"/"A" for FREAK and hand-drawing the missing "K" in the same font.
    gfp = Image.open(SRC / "gfx" / "splash" / "gamefreak_presents.png").convert("L")
    def _tile(i):
        return gfp.crop((i * 8, 0, i * 8 + 8, 8))
    G, A, M, E, F, R = (_tile(i) for i in range(6))                 # tiles 0-5 are clean
    K_ROWS = ["##...##.", ".##.##..", ".####...", ".###....", ".####...", ".##.##..", "##...##.", "........"]
    K = Image.new("L", (8, 8), 255)
    for y, row in enumerate(K_ROWS):
        for x, c in enumerate(row):
            if c == "#":
                K.putpixel((x, y), 0)
    def _word(tiles):
        out = Image.new("L", (len(tiles) * 8, 8), 255)
        for i, tl in enumerate(tiles):
            out.paste(tl, (i * 8, 0))
        return out
    _gb_rgba(_word([G, A, M, E])).save(OUT / "title" / "gamefreak_game.png")
    _gb_rgba(_word([F, R, E, A, K])).save(OUT / "title" / "gamefreak_freak.png")
    _mon_sprite(SRC / "gfx" / "splash" / "falling_star.png", OUT / "title" / "star.png")
    # The tile holds two mini stars; the darker lower-left one blinks via the rOBP1 toggle
    # (MoveDownSmallStars), so also emit the tile with it removed for the "off" phase.
    fstar = Image.open(SRC / "gfx" / "splash" / "falling_star.png").convert("L")
    _gb_rgba(fstar.point(lambda v: 255 if v == 0 else v)).save(OUT / "title" / "star_upper.png")
    # Big shooting star (16x16) = move_anim_1 tile 3 (top-left quadrant) + tile 19 (bottom-left),
    # mirrored horizontally for the right half (GameFreakShootingStarOAMData).
    ma = Image.open(SRC / "gfx" / "battle" / "move_anim_1.png").convert("L")   # 16 tiles/row
    tl, bl = ma.crop((24, 0, 32, 8)), ma.crop((24, 8, 32, 16))                 # tiles 3 and 19
    big = Image.new("L", (16, 16), 255)
    big.paste(tl, (0, 0)); big.paste(tl.transpose(Image.FLIP_LEFT_RIGHT), (8, 0))
    big.paste(bl, (0, 8)); big.paste(bl.transpose(Image.FLIP_LEFT_RIGHT), (8, 8))
    _gb_rgba(big).save(OUT / "title" / "bigstar.png")
    # the condensed copyright tile strip ($60-$72: ©'95'96'98 + Nintendo + Creatures inc.)
    _mon_sprite(SRC / "gfx" / "splash" / "copyright.png", OUT / "title" / "copyright_strip.png")
    # Nidorino (front mon, right side) faces left toward Gengar in its native orientation.
    for i in (1, 2, 3):
        _mon_sprite(SRC / "gfx" / "intro" / f"red_nidorino_{i}.png", OUT / "title" / f"nidorino_{i}.png")
    # Gengar (back mon, from behind): three 56x56 poses. The *silhouette* must be opaque (so it
    # hides Nidorino sliding behind it) including its dithered interior highlights, while only the
    # surrounding background is transparent — so flood-fill the white that is connected to the
    # border and treat every other pixel (dark or enclosed-white) as opaque.
    import collections
    gsheet = Image.open(SRC / "gfx" / "intro" / "gengar.png").convert("L")   # 168x56 = 3x 56x56
    for f in range(3):
        pose = gsheet.crop((f * 56, 0, f * 56 + 56, 56)).copy()
        if f == 0:                                # blank a stray dark tile at the top-left
            from PIL import ImageDraw
            ImageDraw.Draw(pose).rectangle((0, 8, 7, 15), fill=255)
        px = pose.load()
        outside = [[False] * 56 for _ in range(56)]
        q = collections.deque()
        for x in range(56):
            for y in (0, 55):
                if px[x, y] > 200:
                    outside[y][x] = True; q.append((x, y))
        for y in range(56):
            for x in (0, 55):
                if px[x, y] > 200 and not outside[y][x]:
                    outside[y][x] = True; q.append((x, y))
        while q:
            x, y = q.popleft()
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < 56 and 0 <= ny < 56 and not outside[ny][nx] and px[nx, ny] > 200:
                    outside[ny][nx] = True; q.append((nx, ny))
        out = Image.new("RGBA", (56, 56))
        dp = out.load()
        for y in range(56):
            for x in range(56):
                dp[x, y] = (0, 0, 0, 0) if outside[y][x] else GB_PALETTE[round((255 - px[x, y]) / 255 * 3)] + (255,)
        out.save(OUT / "title" / f"gengar_{f}.png")
    # cycling title mons (Red set), starters resolved to species
    starters = {"STARTER1": "charmander", "STARTER2": "squirtle", "STARTER3": "bulbasaur"}
    text = read("data/pokemon/title_mons.asm")
    text = re.sub(r"IF DEF\(_BLUE\).*?ENDC", "", text, flags=re.S)
    mons = []
    for m in re.finditer(r"db\s+(\w+)", text):
        c = m.group(1)
        mons.append(starters.get(c, c.lower().replace("_", "")))
    json.dump(mons, open(OUT / "title_mons.json", "w"), indent=1)
    # The 7 Nidorino intro animations (per-frame [dy, dx] deltas; each frame holds 5 game-frames).
    itext = read("engine/movie/intro.asm")
    anims = []
    for n in range(1, 8):
        m = re.search(r"IntroNidorinoAnimation%d:(.*?)ANIMATION_END" % n, itext, re.S)
        rows = re.findall(r"db\s+(-?\d+),\s*(-?\d+)", m.group(1))
        anims.append([[int(a), int(b)] for a, b in rows])
    json.dump(anims, open(OUT / "title_intro.json", "w"), indent=1)
    print(f"title: logo/figure/star/copyright-© + 3 nidorino + 3 gengar + {len(anims)} intro anims, {len(mons)} mons")


def build_wild():
    """Per-map wild encounter tables (grass/water rate + 10 level/species slots) + the
    fixed slot-probability cumulative thresholds. Keyed by map *label*: several maps share a
    wild-data table (e.g. the sea routes), resolved via WildDataPointers."""
    cum, total = [], 0
    for m in re.finditer(r"wild_chance\s+(\d+)", read("data/wild/probabilities.asm")):
        total += int(m.group(1))
        cum.append(total - 1)

    # Parse each wild-data file once, keyed by its stem (== the <Stem>WildMons label).
    by_stem = {}
    for p in (SRC / "data" / "wild" / "maps").glob("*.asm"):
        text = p.read_text()
        text = re.sub(r"IF DEF\(_BLUE\).*?ENDC", "", text, flags=re.S)   # Red version
        text = re.sub(r"IF DEF\(_RED\)", "", text).replace("ENDC", "")

        def section(kind):
            mr = re.search(r"def_%s_wildmons\s+(\d+)(.*?)end_%s_wildmons" % (kind, kind), text, re.S)
            if not mr:
                return 0, []
            mons = [[int(lv), sp.lower().replace("_", "")]
                    for lv, sp in re.findall(r"db\s+(\d+),\s*(\w+)", mr.group(2))][:10]
            return int(mr.group(1)), mons

        grate, grass = section("grass")
        wrate, water = section("water")
        if grass or water:
            by_stem[p.stem] = {"grass_rate": grate, "grass": grass, "water_rate": wrate, "water": water}

    # map_const -> map label (e.g. ROUTE_19 -> "Route19").
    const_to_label = {}
    for p in (SRC / "data" / "maps" / "headers").glob("*.asm"):
        h = parse_map_header(p)
        if h["label"] and h["map_const"]:
            const_to_label[h["map_const"]] = h["label"]

    # WildDataPointers is indexed by map-constant order (most entries have no comment), so zip the
    # `dw <Stem>WildMons` list against the ordered map constants. Shared tables (e.g. SeaRoutes for
    # ROUTE_19/20) then resolve to every map that points at them.
    order = re.findall(r"map_const\s+(\w+)\s*,\s*\d+\s*,\s*\d+", read("constants/map_constants.asm"))
    dws = re.findall(r"dw\s+(\w+?)WildMons", read("data/wild/grass_water.asm"))
    assert len(order) == len(dws), "WildDataPointers (%d) misaligned with map_const order (%d)" % (len(dws), len(order))
    maps = {}
    for mc, stem in zip(order, dws):
        if stem == "Nothing" or stem not in by_stem:
            continue
        label = const_to_label.get(mc)
        if label:
            maps[label] = by_stem[stem]
    json.dump({"slots": cum, "maps": maps}, open(OUT / "wild.json", "w"), indent=1)
    print(f"wild: {len(maps)} maps with encounters (from {len(by_stem)} tables)")


def build_spinners():
    """Spin-tile slide paths (RocketHideoutB2F/B3F + ViridianGym scripts): each map's
    <X>ArrowTilePlayerMovement table maps a standing coord (y, x) to an RLE list of simulated
    joypad presses (PAD_DIR, count) that slides the player to the matching stop tile.
    Output: spinners.json = {map_label: {"x,y": [[dir, count], ...]}} with the port's dir enum
    (0 down / 1 up / 2 left / 3 right)."""
    dirs = {"PAD_DOWN": 0, "PAD_UP": 1, "PAD_LEFT": 2, "PAD_RIGHT": 3}
    out = {}
    for label in ("RocketHideoutB2F", "RocketHideoutB3F", "ViridianGym"):
        text = read(f"scripts/{label}.asm")
        # Each movement list: Label:  db PAD_X, n  ...  db -1
        lists = {}
        for m in re.finditer(r"(\w+ArrowMovement\d+):((?:\s+db\s+PAD_\w+,\s*\d+)*)", text):
            lists[m.group(1)] = [[dirs[d], int(n)]
                                 for d, n in re.findall(r"db\s+(PAD_\w+),\s*(\d+)", m.group(2))]
        table = {}
        # `map_coord_movement X, Y, lbl` -> `dbmapcoord X, Y` (macros/coords.asm: args are x, y).
        # Read them as (x, y); reading them swapped transposed every spin-tile coord (3 B2F paths
        # then slid the player off the map — the spin mazes were never actually walkable).
        for x, y, lbl in re.findall(r"map_coord_movement\s+(\d+),\s*(\d+),\s*(\w+)", text):
            table["%d,%d" % (int(x), int(y))] = lists[lbl]
        out[label] = table
        assert table, f"no spinner table parsed for {label}"
    json.dump(out, open(OUT / "spinners.json", "w"), indent=1)
    print(f"spinners: " + ", ".join(f"{k}={len(v)}" for k, v in out.items()))


def build_dungeon_maps():
    """Dungeon-map labels for the battle-transition pick (data/maps/dungeon_maps.asm, read by
    GetBattleTransitionID_IsDungeonMap): DungeonMaps1 lists single maps, DungeonMaps2 inclusive
    ranges in map-id order."""
    text = read("data/maps/dungeon_maps.asm")
    order = re.findall(r"map_const\s+(\w+)", read("constants/map_constants.asm"))
    idx = {c: i for i, c in enumerate(order)}
    const_to_label = {}
    for p in (SRC / "data" / "maps" / "headers").glob("*.asm"):
        h = parse_map_header(p)
        if h["label"] and h["map_const"]:
            const_to_label[h["map_const"]] = h["label"]
    part1, part2 = text.split("DungeonMaps2")
    labels = set()
    for c in re.findall(r"db\s+([A-Z]\w+)", part1):
        labels.add(const_to_label[c])
    for a, b in re.findall(r"db\s+([A-Z]\w+),\s*([A-Z]\w+)", part2):
        for i in range(idx[a], idx[b] + 1):
            if order[i] in const_to_label:
                labels.add(const_to_label[order[i]])
    json.dump(sorted(labels), open(OUT / "dungeon_maps.json", "w"), indent=1)
    print(f"dungeon maps: {len(labels)} labels")


def build_warp_rules():
    """The faithful warp-firing rules (gh #80, home/overworld.asm CheckWarpsNoCollision /
    CheckWarpsCollision + engine/overworld/player_state.asm):

    - warp_tiles[tileset slug]: standing on one of these fires the warp on the landing step
      (data/tilesets/warp_tile_ids.asm — a positional NUM_TILESETS table whose label sections
      stack and FALL THROUGH: a bare `db ...` run continues into the next label's list until a
      `warp_tiles` macro line terminates it, so Facility = its own 3 + Cemetery's + Underground's).
    - door_tiles[tileset slug]: ditto (data/tilesets/door_tile_ids.asm, keyed `dbw TILESET, ptr`;
      IsPlayerStandingOnDoorTileOrWarpTile checks doors first).
    - carpet_tiles[dir]: ExtraWarpCheck "function 2" (IsWarpTileInFrontOfPlayer) — the tile in
      FRONT of the player, per facing direction (data/tilesets/warp_carpet_tile_ids.asm).
      Function 1 (IsPlayerFacingEdgeOfMap) needs no data. Which function applies is per
      map/tileset, hardcoded in the engine like pokered's ExtraWarpCheck."""
    consts = parse_tileset_constants()
    names = parse_tileset_table()
    slugs = [slug(n) for n in names]
    const_slug = dict(zip(consts, slugs))

    def tile_list(lines, start, terminator):
        """Walk label sections from `start`, collecting db/terminator args across fallthroughs."""
        out = []
        for l in lines[start:]:
            if re.match(r"\.\w+:", l) or not l:
                continue
            m = re.match(terminator + r"\b(.*)", l)
            if m:  # the macro line ends the list (its own args included)
                return out + [int(a.strip()[1:], 16) for a in m.group(1).split(",")
                              if a.strip().startswith("$")]
            m = re.match(r"db\s+(.+)", l)
            if m:  # a bare db run falls through into the next label's list
                out += [int(a.strip()[1:], 16) for a in m.group(1).split(",")
                        if a.strip().startswith("$")]
        return out

    def label_index(lines):
        return {m.group(1): i for i, l in enumerate(lines)
                if (m := re.match(r"(\.\w+):", l))}

    wlines = [strip_comment(l).strip() for l in read("data/tilesets/warp_tile_ids.asm").splitlines()]
    worder = [m.group(1) for l in wlines if (m := re.match(r"dw\s+(\.\w+)", l))]
    assert len(worder) == len(slugs), f"{len(worder)} warp-tile rows vs {len(slugs)} tilesets"
    wlabels = label_index(wlines)
    warp_tiles = {slugs[i]: tile_list(wlines, wlabels[worder[i]], "warp_tiles")
                  for i in range(len(worder))}

    dtext = read("data/tilesets/door_tile_ids.asm")
    dlines = [strip_comment(l).strip() for l in dtext.splitlines()]
    dlabels = label_index(dlines)
    door_tiles = {s: [] for s in slugs}
    for c, lbl in re.findall(r"dbw\s+(\w+),\s*(\.\w+)", dtext):
        door_tiles[const_slug[c]] = tile_list(dlines, dlabels[lbl], "door_tiles")

    ctext = read("data/tilesets/warp_carpet_tile_ids.asm")
    carpet = {}
    for m in re.finditer(r"\.Facing(\w+)WarpTiles:\s*\n\s*warp_carpet_tiles\s+(.+)", ctext):
        carpet[m.group(1).lower()] = [int(a.strip()[1:], 16)
                                      for a in strip_comment(m.group(2)).split(",")]

    # Spot-check the fallthrough parse against the asm by hand.
    assert warp_tiles["overworld"] == [0x1B, 0x58], warp_tiles["overworld"]
    assert warp_tiles["facility"] == [0x43, 0x58, 0x20, 0x1B, 0x13], warp_tiles["facility"]
    assert warp_tiles["plateau"] == [0x1B, 0x3B], warp_tiles["plateau"]
    assert warp_tiles["shipport"] == [] and warp_tiles["club"] == []
    assert door_tiles["overworld"] == [0x1B, 0x58] and door_tiles["gym"] == []
    assert set(carpet) == {"down", "up", "left", "right"} and carpet["up"] == [0x01, 0x5C]

    json.dump({"warp_tiles": warp_tiles, "door_tiles": door_tiles, "carpet_tiles": carpet},
              open(OUT / "warp_rules.json", "w"), indent=1)
    print(f"warp rules: {sum(1 for v in warp_tiles.values() if v)} tilesets with warp tiles, "
          f"{sum(1 for v in door_tiles.values() if v)} with door tiles")


def build_battle_intro():
    """Assets for the battle-start sequence: the player's back trainer pic (redb, 32x32) shown while
    the mons slide in, and the party status pokeballs (balls, 4 tiles) drawn along the HUD bracket."""
    from PIL import Image
    _gb_rgba(Image.open(SRC / "gfx" / "player" / "redb.png").convert("L")).save(OUT / "trainer_back.png")
    _gb_rgba(Image.open(SRC / "gfx" / "battle" / "balls.png").convert("L")).save(OUT / "balls.png")
    # The unidentified-GHOST battle pic (Pokémon Tower without the SILPH SCOPE), drawn like a
    # mon front sprite (lightest shade transparent).
    _mon_sprite(SRC / "gfx" / "battle" / "ghost.png", OUT / "ghost.png")
    # The museum fossil-skeleton pics (hidden_events/museum_fossils.asm popups).
    _mon_sprite(SRC / "gfx" / "pokemon" / "front" / "fossilaerodactyl.png", OUT / "fossil_aerodactyl.png")
    _mon_sprite(SRC / "gfx" / "pokemon" / "front" / "fossilkabutops.png", OUT / "fossil_kabutops.png")
    # The OLD MAN's back pic for the catching tutorial (BATTLE_TYPE_OLD_MAN).
    _gb_rgba(Image.open(SRC / "gfx" / "battle" / "oldmanb.png").convert("L")).save(OUT / "oldman_back.png")
    # The condensed battle/menu glyphs (gfx/font/font_battle_extra.png, 15x2 tiles):
    # [0]=P: [1-10]=HP-bar pieces [12]=:L [15]=HP [17]=ID [18]=No ...
    _gb_rgba(Image.open(SRC / "gfx" / "font" / "font_battle_extra.png").convert("L")).save(OUT / "font_battle_extra.png")
    # The Pokémon Center healing machine OBJ tiles (monitor + heal ball, AnimateHealingMachine).
    _ow_rgba(Image.open(SRC / "gfx" / "overworld" / "heal_machine.png").convert("L")).save(
        OUT / "sprites" / "heal_machine.png")
    # The bold P tile (gfx/font/P.png, char $72 at runtime): the summary screen's "PP" label.
    _gb_rgba(Image.open(SRC / "gfx" / "font" / "P.png").convert("L")).save(OUT / "bold_p.png")
    # Trainer card (draw_badges.asm): the player's front pic and the leader-face/badge strip
    # (16x256: face,badge alternating for the 8 gyms — the face shows until the badge is won).
    _gb_rgba(Image.open(SRC / "gfx" / "player" / "red.png").convert("L")).save(OUT / "trainer_front.png")
    _gb_rgba(Image.open(SRC / "gfx" / "trainer_card" / "badges.png").convert("L")).save(OUT / "badges.png")
    # The card's border/background tiles ($77-$7E + the checkered bg, 3x3) and the fancy
    # badge-number tiles ("1"-"8", 2x4).
    _gb_rgba(Image.open(SRC / "gfx" / "trainer_card" / "trainer_info.png").convert("L")).save(OUT / "trainer_info.png")
    _gb_rgba(Image.open(SRC / "gfx" / "trainer_card" / "badge_numbers.png").convert("L")).save(OUT / "badge_numbers.png")
    # The $76 circle tile framing the BADGES label (gfx/trainer_card.asm CircleTile).
    _mon_sprite(SRC / "gfx" / "trainer_card" / "circle_tile.png", OUT / "circle_tile.png")
    # (The ball-poof smoke draws straight from POOF_ANIM's frame blocks in move_anims.json —
    # no separate strip needed since the gh #20 unification.)
    print("battle intro: trainer back pic + party pokeballs + card gfx")


def build_battle():
    (OUT / "pokemon" / "front").mkdir(parents=True, exist_ok=True)
    (OUT / "pokemon" / "back").mkdir(parents=True, exist_ok=True)
    base = parse_base_stats()
    evos = parse_evos_moves()
    for sp, info in base.items():
        info["level_moves"] = evos.get(sp, {}).get("level_moves", [])
        info["evolutions"] = evos.get(sp, {}).get("evolutions", [])
    json.dump(base, open(OUT / "pokemon" / "base_stats.json", "w"), indent=1)
    json.dump(parse_moves(), open(OUT / "moves.json", "w"), indent=1)
    json.dump(parse_type_chart(), open(OUT / "types.json", "w"), indent=1)
    nf = nb = 0
    missing = []
    for species in base:
        stem = SPRITE_STEM.get(species, species)
        f = SRC / "gfx" / "pokemon" / "front" / f"{stem}.png"
        b = SRC / "gfx" / "pokemon" / "back" / f"{stem}b.png"
        # Every species must have both, or a battle draws a null texture (gh #81). Never skip quietly.
        for src, kind in ((f, "front"), (b, "back")):
            if not src.exists():
                missing.append(f"{species} ({kind}: {src.name})")
        if f.exists():
            _mon_sprite(f, OUT / "pokemon" / "front" / f"{species}.png"); nf += 1
        if b.exists():
            _mon_sprite(b, OUT / "pokemon" / "back" / f"{species}.png"); nb += 1
    if missing:
        raise SystemExit("missing pokemon sprites: " + ", ".join(missing))
    print(f"battle: {len(base)} species, {len(parse_moves())} moves, "
          f"{nf} front + {nb} back sprites")
    build_trainers(base)


def extract_font():
    """Font tiles -> RGBA (ink = dark GB shade, paper = transparent). Returns cols."""
    from PIL import Image
    im = Image.open(SRC / "gfx" / "font" / "font.png").convert("1")
    w, h = im.size
    ed = Image.open(SRC / "gfx" / "font" / "ED.png").convert("1")  # naming-screen "ED" ligature
    pdx = Image.open(SRC / "gfx" / "pokedex" / "pokedex.png").convert("L").point(
        lambda v: 255 if v >= 128 else 0, "1")                    # pokedex tiles (feet/inches, divider)
    big = Image.new("1", (w, h + 8), 1)                            # extra row -> extra tiles from index 128
    big.paste(im, (0, 0))
    big.paste(ed, (0, h))                                          # 128 = ED
    big.paste(pdx.crop((0, 0, 8, 8)), (8, h))                     # 129 = feet prime (pokedex tile $60)
    big.paste(pdx.crop((8, 0, 16, 8)), (16, h))                   # 130 = inches double-prime ($61)
    big.paste(pdx.crop((16, 16, 24, 24)), (24, h))               # 131 = divider left cap ($68)
    big.paste(pdx.crop((0, 24, 8, 32)), (32, h))                 # 132 = divider box ($69)
    big.paste(pdx.crop((8, 24, 16, 32)), (40, h))                # 133 = divider right cap ($6A)
    big.paste(pdx.crop((16, 24, 24, 32)), (48, h))               # 134 = divider line ($6B)
    im, w, h = big, big.size[0], big.size[1]
    out = Image.new("RGBA", (w, h))
    ink = GB_PALETTE[3]
    src, dst = im.load(), out.load()
    for y in range(h):
        for x in range(w):
            dst[x, y] = (ink[0], ink[1], ink[2], 255) if src[x, y] == 0 else (0, 0, 0, 0)
    out.save(OUT / "font.png")
    # Text-box frame tiles (font_extra ┌─┐│└┘ = chars $79-$7E = tiles 25-30, loaded at vChars2 $60).
    fx = Image.open(SRC / "gfx" / "font" / "font_extra.png").convert("L")
    strip = Image.new("L", (48, 8), 255)
    for i in range(6):                                    # cols 9-14 of row 1
        strip.paste(fx.crop(((9 + i) * 8, 8, (9 + i) * 8 + 8, 16)), (i * 8, 0))
    _gb_rgba(strip).save(OUT / "frame.png")
    return w // TILE


def parse_charmap():
    """Single printable char -> font tile index (byte - 0x80). Space (0x7f) renders blank."""
    out = {}
    for line in read("constants/charmap.asm").splitlines():
        m = re.match(r'\s*charmap\s+"(.+?)",\s*\$([0-9a-fA-F]+)', line)
        if m and len(m.group(1)) == 1:
            val = int(m.group(2), 16)
            if val >= 0x80:
                out[m.group(1)] = val - 0x80
    return out


def _decode_text(s):
    """Expand text macro tokens to displayable characters. <PLAYER>/<RIVAL> are kept as
    placeholders — the engine substitutes the chosen names at display time (Main.resolve_text)."""
    s = s.replace("#", "POKé")
    s = s.replace("<PKMN>", "PKMN").replace("<USER>", "USER").replace("<TARGET>", "TARGET")
    # strip remaining tokens, keeping the inner text — except the name placeholders
    return re.sub(r"<(?!PLAYER>|RIVAL>)(\w+)>", r"\1", s)


def parse_text_strings():
    """text/*.asm + data/text/*.asm: string label (_Foo) -> decoded string with \\n / \\f."""
    out = {}
    files = list((SRC / "text").glob("*.asm")) + list((SRC / "data" / "text").glob("*.asm"))
    for p in files:
        cur, buf = None, ""
        for line in p.read_text(encoding="utf-8").splitlines():
            s = line.split(";", 1)[0].rstrip()
            ml = re.match(r"\s*(_\w+):", s)
            if ml:
                if cur:
                    out[cur] = buf.split("@", 1)[0]
                cur, buf = ml.group(1), ""
                continue
            m = re.match(r"\s*(text|line|cont|next|para|page|done|prompt|text_end)\b(.*)", s)
            if not m or cur is None:
                continue
            kind = m.group(1)
            sm = re.search(r'"(.*)"', m.group(2))
            txt = _decode_text(sm.group(1)) if sm else ""
            if kind == "text":
                buf += txt
            elif kind in ("line", "cont", "next"):
                buf += "\n" + txt
            elif kind in ("para", "page"):
                buf += "\f" + txt
            elif kind in ("done", "prompt", "text_end"):
                out[cur] = buf.split("@", 1)[0]
                cur, buf = None, ""
        if cur:
            out[cur] = buf.split("@", 1)[0]
    return out


def parse_script_text():
    """scripts/*.asm: resolve each TEXT_id to a decoded-string label (`_Foo`).

    A script label's dialogue may not be a plain `text_far` on the label itself:
    text_asm handlers `PrintText` another label via `ld hl, X`, and trainer NPCs
    (`ld hl, <Header>` + `call TalkToTrainer`) keep their before/after text in the
    trainer header. We follow those so script/trainer NPCs aren't left blank.

    Returns (text_ptrs, resolved) where resolved[TEXT_id] = string label or None."""
    text_ptrs = {}          # TEXT_id -> script label
    direct = {}             # label -> first `text_far` string label in its block
    hlrefs = {}             # label -> [labels referenced via `ld hl, X`]
    theader = {}            # trainer-header label -> (before_label, after_label)
    # scripts/ holds the TEXT_id -> label table; shared labels (signs, etc.) are defined in home/
    # and engine/, so scan those too for their text_far definitions.
    files = (list((SRC / "scripts").glob("*.asm")) + list((SRC / "home").glob("*.asm"))
             + list((SRC / "engine").rglob("*.asm")))
    for p in files:
        cur = None
        for line in p.read_text(encoding="utf-8").splitlines():
            s = line.split(";", 1)[0].strip()
            md = re.match(r"dw_const\s+(\w+)\s*,\s*(TEXT_\w+)", s)
            if md:
                text_ptrs[md.group(2)] = md.group(1)
                continue
            ml = re.match(r"(\w+)::?\s*$", s)   # top-level label (`Foo:` or exported `Foo::`)
            if ml:
                cur = ml.group(1)
                continue
            if cur is None:
                continue
            mf = re.match(r"text_far\s+(_\w+)", s)
            if mf:
                direct.setdefault(cur, mf.group(1))
                continue
            mh = re.match(r"ld hl,\s*(\w+)\s*$", s)
            if mh:
                hlrefs.setdefault(cur, []).append(mh.group(1))
                continue
            mt = re.match(r"trainer\s+\w+\s*,\s*\d+\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)", s)
            if mt:
                theader[cur] = (mt.group(1), mt.group(3))

    def resolve(label, depth=0):
        if label is None or depth > 8:
            return None
        if label in direct:
            return direct[label]
        if label in theader:                       # a trainer header -> its before-battle text
            return resolve(theader[label][0], depth + 1)
        for ref in hlrefs.get(label, []):          # follow ld-hl PrintText references
            r = resolve(ref, depth + 1)
            if r:
                return r
        return None

    resolved = {tid: resolve(lbl) for tid, lbl in text_ptrs.items()}
    return text_ptrs, resolved, direct


def build_link_manifest():
    """gh #3 (ADR-014 link identity): hash the link-relevant extracted data at extraction
    time, so two peers can compare identities in one handshake instead of re-deriving (or
    silently drifting into an undebuggable mid-battle desync). Parts are the tables both
    engines must agree on to simulate the identical battle / speak the same mon record:
    species (base stats + growth + evolutions + learnsets), moves, and the type chart.
    The per-part hashes let a refusal name WHICH part differs; content_hash is the md5 of
    the part hashes joined in sorted part order."""
    import hashlib
    part_files = {
        "base_stats": OUT / "pokemon" / "base_stats.json",
        "moves": OUT / "moves.json",
        "types": OUT / "types.json",
    }
    parts = {}
    for name, path in sorted(part_files.items()):
        parts[name] = hashlib.md5(path.read_bytes()).hexdigest()
    content = hashlib.md5("".join(parts[k] for k in sorted(parts)).encode()).hexdigest()
    json.dump({"schema": 1, "parts": parts, "content_hash": content},
              open(OUT / "link_manifest.json", "w"), indent=1)
    print(f"link manifest: {len(parts)} parts, content_hash={content}")


def build_text():
    cols = extract_font()
    charmap = parse_charmap()
    json.dump(charmap, open(OUT / "charmap.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    strings = parse_text_strings()
    _, resolved, _ = parse_script_text()
    text_map = {}
    for tid, far in resolved.items():
        if far and far in strings:
            text_map[tid] = strings[far]
    json.dump(text_map, open(OUT / "text.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"text: font {cols} cols, {len(charmap)} chars, {len(strings)} strings, "
          f"{len(text_map)}/{len(resolved)} text ids resolved")


def parse_sprite_labels():
    """gfx/sprites.asm: sprite label -> png file basename."""
    out = {}
    for line in read("gfx/sprites.asm").splitlines():
        m = re.match(r'(\w+):: *INCBIN "gfx/sprites/(\w+)\.2bpp"', line.strip())
        if m:
            out[m.group(1)] = m.group(2)
    return out


def parse_sprite_table():
    """SpriteSheetPointerTable: ordered sprite labels (index i -> sprite id i+1)."""
    out = []
    for line in read("data/sprites/sprites.asm").splitlines():
        m = re.match(r"\s*overworld_sprite\s+(\w+),", line)
        if m:
            out.append(m.group(1))
    return out


def parse_sprite_constants():
    """Ordered SPRITE_* constant names (index = sprite id; SPRITE_NONE = 0)."""
    out = []
    for line in read("constants/sprite_constants.asm").splitlines():
        m = re.match(r"\s*const\s+(SPRITE_\w+)", line)
        if m:
            out.append(m.group(1))
    return out


def build_sprites():
    """Extract every overworld sprite sheet + emit SPRITE_* -> {file, frames} index."""
    labels = parse_sprite_table()
    label_file = parse_sprite_labels()
    consts = parse_sprite_constants()
    index = {}
    frames_by_file = {}
    for i, label in enumerate(labels):
        file = label_file.get(label)
        if not file:
            continue
        if file not in frames_by_file:
            _, _, frames_by_file[file] = extract_overworld_sprite(file, OUT / "sprites" / f"{file}.png")
        const = consts[i + 1] if i + 1 < len(consts) else None   # label i -> sprite id i+1
        if const:
            index[const] = {"file": file, "frames": frames_by_file[file]}
    json.dump(index, open(OUT / "sprites" / "index.json", "w"), indent=1)
    print(f"sprites: {len(frames_by_file)} sheets, {len(index)} SPRITE_* mapped")
    for emote in ("shock", "question", "happy"):    # trainer-sight "!" bubble etc.
        extract_emote(emote, OUT / "sprites" / f"emote_{emote}.png")
    extract_smoke(OUT / "sprites" / "smoke.png")    # the S.S. Anne departure puffs
    extract_smoke_dust(OUT / "sprites" / "smoke_dust.png")   # the boulder dust puff (gh #185)
    extract_overworld_sprite("red_bike", OUT / "sprites" / "red_bike.png")   # the player on the BICYCLE (gh #161)


def extract_trade_gfx():
    """The trade movie's gfx (engine/movie/trade.asm): trade_tiles.png = the BG strip
    (game_boy.2bpp + link_cable.2bpp, VRAM $31..; 16 tiles/row), trade_gfx.json = the
    GAME BOY (6x8) and open-cable-end (12x3) tilemaps as zero-based strip indices,
    trade_ball.png = the cable_ball sprite tiles ($7c-$7f), and trade_bubble.png = the
    TRADEBUBBLE circle icon (two 16x16 frames: circle, oval)."""
    from PIL import Image

    def tiles_of(path):
        im = Image.open(path).convert("L")
        out = []
        for ty in range(im.size[1] // 8):
            for tx in range(im.size[0] // 8):
                out.append(im.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8)))
        return out

    def gb_rgba(im, transparent_white):
        o = Image.new("RGBA", im.size)
        s, d = im.load(), o.load()
        for y in range(im.size[1]):
            for x in range(im.size[0]):
                idx = (255 - s[x, y]) // 85
                if idx == 0 and transparent_white:
                    d[x, y] = (0, 0, 0, 0)
                else:
                    d[x, y] = (*GB_PALETTE[idx], 255)
        return o

    # game_boy.2bpp is rgbgfx-deduplicated (34 unique tiles, scan order — its .tilemap
    # reconstructs the picture); link_cable.2bpp is raw (15 tiles). VRAM: $31..$61.
    gb_unique = []
    for t in tiles_of(SRC / "gfx" / "trade" / "game_boy.png"):
        if not any(t.tobytes() == u.tobytes() for u in gb_unique):
            gb_unique.append(t)
    tiles = gb_unique + tiles_of(SRC / "gfx" / "trade" / "link_cable.png")
    cols = 16
    rows = (len(tiles) + cols - 1) // cols
    strip = Image.new("L", (cols * 8, rows * 8), 255)
    for i, t in enumerate(tiles):
        strip.paste(t, ((i % cols) * 8, (i // cols) * 8))
    gb_rgba(strip, False).save(OUT / "trade_tiles.png")
    gb_rgba(Image.open(SRC / "gfx" / "trade" / "cable_ball.png").convert("L"), True).save(OUT / "trade_ball.png")
    # The bubble renders under OBP1 %11010000 (Trade_LoadMonPartySpriteGfx): colour 1 ->
    # shade 0, colour 2 -> shade 1, colour 3 -> shade 3, colour 0 transparent.
    bub = Image.open(SRC / "gfx" / "trade" / "bubble.png").convert("L")
    ob = Image.new("RGBA", bub.size)
    sb, db = bub.load(), ob.load()
    obp1 = {0: None, 1: GB_PALETTE[0], 2: GB_PALETTE[1], 3: GB_PALETTE[3]}
    for y in range(bub.size[1]):
        for x in range(bub.size[0]):
            c = obp1[(255 - sb[x, y]) // 85]
            db[x, y] = (0, 0, 0, 0) if c is None else (*c, 255)
    ob.save(OUT / "trade_bubble.png")
    maps = {}
    for name, w in (("game_boy", 6), ("link_cable", 12)):
        raw = (SRC / "gfx" / "trade" / f"{name}.tilemap").read_bytes()
        maps[name] = {"w": w, "ids": [b - 0x31 for b in raw]}
    json.dump(maps, open(OUT / "trade_gfx.json", "w"), indent=0)


def extract_smoke_dust(dst):
    """The same smoke tile under the boulder dust's OBP1 %11100100 (identity mapping):
    colors 1-3 render as GB shades 1-3, color 0 stays OBJ-transparent
    (engine/overworld/dust_smoke.asm AnimateBoulderDust)."""
    from PIL import Image
    im = Image.open(SRC / "gfx" / "overworld" / "smoke.png").convert("L")
    out = Image.new("RGBA", im.size)
    s, d = im.load(), out.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            idx = (255 - s[x, y]) // 85          # 255/170/85/0 -> color 0/1/2/3
            d[x, y] = (0, 0, 0, 0) if idx == 0 else (*GB_PALETTE[idx], 255)
    out.save(dst)


def parse_tileset_grass():
    """CamelCase tileset name -> grass tile id (5th `tileset` arg), or -1 if none."""
    out = {}
    for line in read("data/tilesets/tileset_headers.asm").splitlines():
        m = re.match(r"\s*tileset\s+(\w+)\s*,(.+)", line)
        if m:
            args = [a.strip() for a in strip_comment(m.group(2)).split(",")]
            grass = args[3] if len(args) > 3 else "-1"  # name, c1,c2,c3, grass, anim
            out[m.group(1)] = int(grass[1:], 16) if grass.startswith("$") else -1
    return out


def parse_ledges():
    """LedgeTiles -> [{dir, stand, ledge}] (OVERWORLD tileset only in pokered)."""
    dirs = {"SPRITE_FACING_DOWN": "down", "SPRITE_FACING_UP": "up",
            "SPRITE_FACING_LEFT": "left", "SPRITE_FACING_RIGHT": "right"}
    out = []
    for line in read("data/tilesets/ledge_tiles.asm").splitlines():
        s = strip_comment(line).strip()
        m = re.match(r"db\s+(SPRITE_FACING_\w+)\s*,\s*\$([0-9a-fA-F]+)\s*,\s*\$([0-9a-fA-F]+)", s)
        if m:
            out.append({"dir": dirs[m.group(1)], "stand": int(m.group(2), 16),
                        "ledge": int(m.group(3), 16)})
    return out


def load_blockset(rel):
    data = (SRC / rel).read_bytes()
    assert len(data) % 16 == 0, f"{rel} not a multiple of 16"
    return [list(data[i : i + 16]) for i in range(0, len(data), 16)]


def build_flower():
    """The overworld flower (tile $03) cycles through 3 frames (home/vcopy.asm). Emit them side by
    side as flower.png (24x8), converted with the same GB ramp as the tilesets so frame 1 matches."""
    from PIL import Image
    combined = Image.new("L", (24, 8))
    for i, n in enumerate((1, 2, 3)):
        f = Image.open(SRC / "gfx" / "tilesets" / "flower" / f"flower{n}.png").convert("L")
        combined.paste(f, (i * 8, 0))
    # Fixed GB grayscale ramp (255->white .. 0->black), matching the tilesets. A per-image ramp is
    # wrong here: the flower gfx only uses 3 of the 4 grays, which would shift every color one darker.
    rgba = Image.new("RGBA", (24, 8))
    src, dst = combined.load(), rgba.load()
    for y in range(8):
        for x in range(24):
            r, g, b = GB_PALETTE[(255 - src[x, y]) // 85]
            dst[x, y] = (r, g, b, 255)
    rgba.save(OUT / "tilesets" / "flower.png")
    print("flower: 3 frames")


def build_dex_entries():
    """Pokédex entry data per species: category ("SEED"), height (ft,in), weight (tenths lb), and the
    flavor description. Source: data/pokemon/dex_entries.asm + data/pokemon/dex_text.asm."""
    # Flavor text: text/next/page -> a string with \n (line) and \f (page) breaks.
    desc = {}
    dt = read("data/pokemon/dex_text.asm")
    # capture through the `dex` terminator: the blank line before a `page` used to cut every
    # multi-page description short (gh #24)
    for m in re.finditer(r"^_(\w+)DexEntry::\n(.*?)^\tdex", dt, re.M | re.S):
        name, body = m.group(1).lower(), m.group(2)
        s = ""
        for cmd, txt in re.findall(r'\t(text|next|line|cont|page|para)\s+"([^"]*)"', body):
            if s == "":
                s = txt
            elif cmd in ("page", "para"):
                s += "\f" + txt
            else:
                s += "\n" + txt
        desc[name] = s
    # Structured data: category / height / weight.
    entries = {}
    de = read("data/pokemon/dex_entries.asm")
    for m in re.finditer(r'^(\w+)DexEntry:\n\tdb "([^"]*)@"\n\tdb (\d+),\s*(\d+)\n\tdw (\d+)', de, re.M):
        name = m.group(1).lower()
        entries[name] = {"cat": m.group(2), "ft": int(m.group(3)), "in": int(m.group(4)),
                         "wt": int(m.group(5)), "desc": desc.get(name, "")}
    # (The asm labels' squashed form — nidoranm/nidoranf/mrmime — IS the canonical species
    # slug used by base_stats/wild/pics; dex_order normalizes to it too.)
    json.dump(entries, open(OUT / "dex_entries.json", "w"), indent=1)
    print(f"dex entries: {len(entries)} ({sum(1 for e in entries.values() if e['desc'])} with text)")


def build_battle_hud():
    """Battle HUD tile row (VRAM $62-$7f): font_battle_extra with battle_hud_1/2/3 layered over the
    slots they overwrite. Used for the special 'HP:' ($71), ':L' level ($6e), and HP-bar cap/segment
    tiles that DrawHPBar/PrintLevel place — not the regular font. -> battle_hud.png (30 tiles)."""
    from PIL import Image

    def tiles(path, n):
        im = Image.open(SRC / path).convert("L")
        w = im.width // 8
        return [im.crop(((i % w) * 8, (i // w) * 8, (i % w) * 8 + 8, (i // w) * 8 + 8)) for i in range(n)]

    vram = tiles("gfx/font/font_battle_extra.png", 30)   # index 0 = VRAM $62
    for i, t in enumerate(tiles("gfx/battle/battle_hud_1.png", 3)):
        vram[0x6d - 0x62 + i] = t
    for i, t in enumerate(tiles("gfx/battle/battle_hud_2.png", 3)):
        vram[0x73 - 0x62 + i] = t
    for i, t in enumerate(tiles("gfx/battle/battle_hud_3.png", 3)):
        vram[0x76 - 0x62 + i] = t
    strip = Image.new("L", (30 * 8, 8), 255)
    for i, t in enumerate(vram):
        strip.paste(t, (i * 8, 0))
    out = Image.new("RGBA", strip.size)
    sp, dp = strip.load(), out.load()
    ink = GB_PALETTE[3]
    for y in range(8):
        for x in range(strip.width):
            dp[x, y] = (ink[0], ink[1], ink[2], 255) if sp[x, y] < 128 else (0, 0, 0, 0)
    out.save(OUT / "battle_hud.png")
    print("battle_hud: 30 tiles ($62-$7f)")


def build_mon_icons():
    """Party-menu mon icons (data/icon_pointers.asm): 10 types x 16x16 -> mon_icons.png, plus a
    species->icon-index map from data/pokemon/menu_icons.asm (dex order). MON/BALL/FAIRY/BIRD/WATER
    reuse an overworld sprite sheet at frame 0; BUG/GRASS/SNAKE/QUADRUPED use their 8x16 strip frame
    centered; HELIX falls back to the ball."""
    from PIL import Image
    order = ["ICON_MON", "ICON_BALL", "ICON_HELIX", "ICON_FAIRY", "ICON_BIRD",
             "ICON_WATER", "ICON_BUG", "ICON_GRASS", "ICON_SNAKE", "ICON_QUADRUPED"]
    idx = {name: i for i, name in enumerate(order)}
    mapping = {}
    for m in re.finditer(r"nybble (ICON_\w+)\s*;\s*(.+)", read("data/pokemon/menu_icons.asm")):
        mapping[re.sub(r"[^a-z0-9]", "", m.group(2).lower())] = idx[m.group(1)]

    def frame0(path):                                    # top 16x16 of an overworld sprite sheet
        return _ow_rgba(Image.open(SRC / path).convert("L").crop((0, 0, 16, 16)))

    def framew(path):                                    # the down-walk frame (sheet frame 3)
        im = Image.open(SRC / path).convert("L")
        if im.height >= 64:
            return _ow_rgba(im.crop((0, 48, 16, 64)))
        return _ow_rgba(im.crop((0, 0, 16, 16)))

    def dedicated(path, fr):                             # an 8x16 half, mirrored (frame 0 or 1)
        im = Image.open(SRC / path).convert("L")         # (the icons are symmetric OAM pairs)
        left = im.crop((0, fr * 16, 8, fr * 16 + 16))
        f = Image.new("L", (16, 16), 255)                # white background -> transparent
        f.paste(left, (0, 0))
        f.paste(left.transpose(Image.FLIP_LEFT_RIGHT), (8, 0))
        return _ow_rgba(f)

    # Two frames per icon (the party menu cycles them). Row 0 = the BASE frame every icon rests
    # on, row 1 = the frame the selected icon swaps to. data/icon_pointers.asm is authoritative
    # and NOT uniform (gh #153): MON/FAIRY/BIRD rest on the WALK frame (gfx tile offset 12) and
    # swap to stand; WATER (the SEEL) is the other way round; BUG/GRASS rest on their pngs'
    # BOTTOM half (INC_FRAME_2) and swap to the top; SNAKE/QUADRUPED rest on the top (FRAME_1).
    rows = [
        [framew("gfx/sprites/monster.png"), frame0("gfx/sprites/poke_ball.png"),
         frame0("gfx/sprites/poke_ball.png"), framew("gfx/sprites/fairy.png"),
         framew("gfx/sprites/bird.png"), frame0("gfx/sprites/seel.png"),
         dedicated("gfx/icons/bug.png", 1), dedicated("gfx/icons/plant.png", 1),
         dedicated("gfx/icons/snake.png", 0), dedicated("gfx/icons/quadruped.png", 0)],
        [frame0("gfx/sprites/monster.png"), frame0("gfx/sprites/poke_ball.png"),
         frame0("gfx/sprites/poke_ball.png"), frame0("gfx/sprites/fairy.png"),
         frame0("gfx/sprites/bird.png"), framew("gfx/sprites/seel.png"),
         dedicated("gfx/icons/bug.png", 0), dedicated("gfx/icons/plant.png", 0),
         dedicated("gfx/icons/snake.png", 1), dedicated("gfx/icons/quadruped.png", 1)],
    ]
    sheet = Image.new("RGBA", (160, 32))
    for r, icons in enumerate(rows):
        for i, ic in enumerate(icons):
            sheet.paste(ic, (i * 16, r * 16))
    sheet.save(OUT / "mon_icons.png")
    json.dump(mapping, open(OUT / "mon_icons.json", "w"), indent=1)
    print(f"mon icons: {len(mapping)} species mapped, 10 icons")


def build_dex_tiles():
    """The Pokédex screens' own tile row (gh #152): LoadPokedexTilePatterns overwrites VRAM
    $60-$71 with gfx/pokedex/pokedex.png (18 tiles: borders, the data screen's divider, the
    contents rail's box $70 + line $71) and puts the owned-marker poké ball at $72; the '─'
    char ($7a) stays font_extra's tile. -> dex_tiles.png, one row indexed by (vram - $60)."""
    from PIL import Image

    def tiles(path, n, w=None):
        im = Image.open(SRC / path).convert("L")
        tw = w if w else im.width // 8
        return [im.crop(((i % tw) * 8, (i // tw) * 8, (i % tw) * 8 + 8, (i // tw) * 8 + 8))
                for i in range(n)]

    strip = Image.new("L", (27 * 8, 8), 255)
    for i, t in enumerate(tiles("gfx/pokedex/pokedex.png", 18)):
        strip.paste(t, (i * 8, 0))
    strip.paste(tiles("gfx/battle/balls.png", 1)[0], (18 * 8, 0))      # $72 the poké ball
    strip.paste(tiles("gfx/font/font_extra.png", 27)[26], (26 * 8, 0)) # $7a the '─' char
    out = Image.new("RGBA", strip.size)
    sp, dp = strip.load(), out.load()
    ink, mid = GB_PALETTE[3], GB_PALETTE[1]
    for y in range(8):
        for x in range(strip.width):
            v = sp[x, y]
            if v < 64:
                dp[x, y] = (ink[0], ink[1], ink[2], 255)
            elif v < 192:                                              # the mid shades survive
                dp[x, y] = (mid[0], mid[1], mid[2], 255)
            else:
                dp[x, y] = (0, 0, 0, 0)
    out.save(OUT / "dex_tiles.png")
    print("dex tiles: 27 ($60-$7a)")


def build_trainer_pics():
    """Extract the battle pics for each trainer class -> assets/trainers/pics/<slug>.png and a
    trainer_pics.json mapping OPP_<CLASS> -> slug. Class order (trainer_constants, minus NOBODY)
    is parallel to pic_pointers_money, and gfx/pics maps each pic label to its file."""
    classes = [c for c in re.findall(r"trainer_const (\w+)", read("constants/trainer_constants.asm"))
               if c != "NOBODY"]
    labels = re.findall(r"pic_money (\w+),", read("data/trainers/pic_pointers_money.asm"))
    lab2file = dict(re.findall(r'(\w+)::\s*INCBIN "gfx/trainers/([\w.]+)\.pic"', read("gfx/pics.asm")))
    assert len(classes) == len(labels), f"{len(classes)} classes vs {len(labels)} pics"
    (OUT / "trainers" / "pics").mkdir(parents=True, exist_ok=True)
    mapping = {}
    for cls, lab in zip(classes, labels):
        f = lab2file.get(lab)                   # e.g. youngster, jr.trainerm, prof.oak
        png = SRC / "gfx" / "trainers" / f"{f}.png" if f else None
        if not png or not png.exists():         # unused classes (CHIEF) have no real pic
            continue
        slug = f.replace(".", "")               # -> jrtrainerm (safe filename)
        _mon_sprite(png, OUT / "trainers" / "pics" / f"{slug}.png")
        mapping["OPP_" + cls] = slug
    json.dump(mapping, open(OUT / "trainer_pics.json", "w"), indent=1)
    print(f"trainer pics: {len(mapping)}")


def build_tilesets():
    """Emit one tileset JSON+PNG per CamelCase tileset name; return const -> slug."""
    consts = parse_tileset_constants()
    names = parse_tileset_table()
    gfx, bst = parse_gfx_wiring()
    coll = parse_collision_table()
    grass = parse_tileset_grass()
    counters = parse_tileset_counters()
    ledges = parse_ledges()
    assert len(consts) == len(names), f"{len(consts)} consts vs {len(names)} table rows"

    const_to_slug = {}
    for const, name in zip(consts, names):
        img, cols, ntiles = load_tileset_png(SRC / gfx[name])
        s = slug(name)
        img.save(OUT / "tilesets" / f"{s}.png")
        walkable = coll.get(name, [])
        if not walkable:
            print(f"  ! tileset {name}: no *_Coll entry (all blocked)")
        out = {"name": s, "tile_cols": cols, "tile_count": ntiles,
               "blocks": load_blockset(bst[name]), "walkable_tiles": walkable,
               "grass_tile": grass.get(name, -1), "counter_tiles": counters.get(name, [])}
        if name == "Overworld":      # ledge mechanic is overworld-only in pokered
            out["ledges"] = ledges
        json.dump(out, open(OUT / "tilesets" / f"{s}.json", "w"), indent=1)
        const_to_slug[const] = s
    print(f"tilesets: {len(const_to_slug)} written")
    return const_to_slug


# --------------------------------------------------------------------------- #
# Maps
# --------------------------------------------------------------------------- #

def parse_map_constants():
    """MAP_CONST -> (width, height) in blocks."""
    out = {}
    for line in read("constants/map_constants.asm").splitlines():
        m = re.match(r"\s*map_const\s+(\w+)\s*,\s*(\d+)\s*,\s*(\d+)", line)
        if m:
            out[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return out


def parse_map_header(path):
    """Parse a map header .asm -> {label, map_const, tileset_const, connections}."""
    label = map_const = tileset_const = None
    connections = []
    for line in path.read_text().splitlines():
        s = strip_comment(line).strip()
        m = re.match(r"map_header\s+(\w+)\s*,\s*(\w+)\s*,\s*(\w+)", s)
        if m:
            label, map_const, tileset_const = m.groups()
        mc = re.match(r"connection\s+(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(-?\d+)", s)
        if mc:
            connections.append({"dir": mc.group(1), "map": mc.group(2),
                                "offset": int(mc.group(4))})
    return {"label": label, "map_const": map_const,
            "tileset_const": tileset_const, "connections": connections}


def parse_map_objects(label):
    """Parse data/maps/objects/<label>.asm -> border_block, warps, bg/object events."""
    path = SRC / "data" / "maps" / "objects" / f"{label}.asm"
    res = {"border_block": 0, "warps": [], "bg_events": [], "object_events": []}
    if not path.exists():
        return res
    for line in path.read_text().splitlines():
        s = strip_comment(line).strip()
        m = re.match(r"db\s+\$?([0-9a-fA-F]+)\s*$", s)  # border block (first db)
        if m and not res["warps"]:
            try:
                res["border_block"] = int(m.group(1), 16)
            except ValueError:
                pass
        m = re.match(r"warp_event\s+(\d+)\s*,\s*(\d+)\s*,\s*(\w+)\s*,\s*(\d+)", s)
        if m:
            res["warps"].append({"x": int(m.group(1)), "y": int(m.group(2)),
                                 "dest_const": m.group(3), "dest_warp": int(m.group(4))})
            continue
        m = re.match(r"bg_event\s+(\d+)\s*,\s*(\d+)\s*,\s*(\w+)", s)
        if m:
            res["bg_events"].append({"x": int(m.group(1)), "y": int(m.group(2)),
                                     "text": m.group(3)})
            continue
        m = re.match(r"object_event\s+(\d+)\s*,\s*(\d+)\s*,\s*(\w+)\s*,(.+)", s)
        if m:
            rest = [t.strip() for t in m.group(4).split(",")]
            res["object_events"].append({"x": int(m.group(1)), "y": int(m.group(2)),
                                         "sprite": m.group(3), "args": rest})
    return res


def parse_trainer_headers(label):
    """scripts/<label>.asm: `def_trainers [N]` start index + ordered `trainer` headers.

    The `trainer` macro is `trainer flag, view_range, TextBefore, TextEnd, TextAfter`. Headers
    bind to consecutive ABSOLUTE sprite indices starting at N (`def_trainers 2` = the first
    header belongs to object_event #2, 1-based) — NOT to the trainer objects in filtered order.
    Gym leaders are sprite 1 with no header (their battle is talk-only), so gyms use
    `def_trainers 2`; zipping by filtered order gave the leader the first trainer's sight range
    and battle text (gh #55).
    """
    path = SRC / "scripts" / f"{label}.asm"
    start, res = 1, []
    if not path.exists():
        return start, res
    for line in path.read_text(encoding="utf-8").splitlines():
        s = strip_comment(line).strip()
        m0 = re.match(r"def_trainers(?:\s+(\d+))?\s*$", s)
        if m0:
            start = int(m0.group(1) or 1)
            continue
        m = re.match(r"trainer\s+\w+\s*,\s*(\d+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)", s)
        if m:  # trainer flag, range, TextBefore, TextEnd, TextAfter
            res.append({"sight": int(m.group(1)), "before": m.group(2),
                        "end": m.group(3), "after": m.group(4)})
    return start, res


def build_maps(const_to_slug):
    dims = parse_map_constants()
    headers = []
    for p in sorted((SRC / "data" / "maps" / "headers").glob("*.asm")):
        h = parse_map_header(p)
        if h["label"]:
            headers.append(h)
    const_to_label = {h["map_const"]: h["label"] for h in headers}
    # For resolving trainer before/after-battle text: header references a script label, which
    # `text_far`s the real string label (first_far), whose decoded text is in `strings`.
    strings = parse_text_strings()
    _, _, first_far = parse_script_text()

    def resolve_text(script_label):
        return strings.get(first_far.get(script_label, ""), "")

    written = skipped = 0
    for h in headers:
        label, mc = h["label"], h["map_const"]
        if mc not in dims:
            skipped += 1
            continue
        w, hh = dims[mc]
        blk = SRC / "maps" / f"{label}.blk"
        if not blk.exists() and label.endswith("Copy"):
            blk = SRC / "maps" / f"{label[:-4]}.blk"   # "...Copy" maps share the base map's blocks
        if not blk.exists():
            skipped += 1
            continue
        data = blk.read_bytes()
        if len(data) != w * hh:
            # Some headers fudge a dimension (e.g. UNDERGROUND_PATH_NORTH_SOUTH is declared 4x24 but
            # the .blk is really 4x23). Trust the actual blk when it's a clean multiple of the width.
            if len(data) % w == 0:
                print(f"  ~ {label}: blk {len(data)} != {w*hh}; using actual height {len(data)//w}")
                hh = len(data) // w
            else:
                print(f"  ! {label}: blk {len(data)} not divisible by width {w}, skipping")
                skipped += 1
                continue
        grid = [list(data[r * w : (r + 1) * w]) for r in range(hh)]
        obj = parse_map_objects(label)
        for wp in obj["warps"]:
            wp["dest_map"] = const_to_label.get(wp["dest_const"], None)
        # Attach trainer sight range + before/after-battle text: header j binds to the
        # object_event at absolute sprite index (def_trainers start + j), 1-based (gh #55).
        tstart, theaders = parse_trainer_headers(label)
        for j, hdr in enumerate(theaders):
            idx = tstart - 1 + j
            if idx >= len(obj["object_events"]):
                print(f"  ! {label}: trainer header {j} -> sprite {tstart + j} out of range")
                break
            oe = obj["object_events"][idx]
            if not any(str(a).startswith("OPP_") for a in oe["args"]):
                print(f"  ! {label}: trainer header {j} -> sprite {tstart + j} is not a trainer")
                continue
            oe["sight"] = hdr["sight"]
            bt = resolve_text(hdr["before"])
            et = resolve_text(hdr["end"])
            at = resolve_text(hdr["after"])
            if bt:
                oe["battle_text"] = bt
            if et:
                oe["end_text"] = et
            if at:
                oe["after_text"] = at
        json.dump(
            {"name": label, "tileset": const_to_slug.get(h["tileset_const"], "overworld"),
             "width": w, "height": hh, "blocks": grid,
             "border_block": obj["border_block"], "warps": obj["warps"],
             "connections": h["connections"], "bg_events": obj["bg_events"],
             "object_events": obj["object_events"]},
            open(OUT / "maps" / f"{label}.json", "w"), indent=1)
        written += 1
    # map label -> song key (keyed by the real map labels, so building music resolves).
    sbc = song_by_map_const()
    map_music = {const_to_label[c]: sk for c, sk in sbc.items() if c in const_to_label}
    json.dump(map_music, open(OUT / "map_music.json", "w"), indent=1)
    print(f"maps: {written} written, {skipped} skipped, {len(map_music)} map->music")
    return const_to_label


# --------------------------------------------------------------------------- #
# Preview (verification)
# --------------------------------------------------------------------------- #

def render_map_preview(slug_name, label, path):
    from PIL import Image
    ts = json.load(open(OUT / "tilesets" / f"{slug_name}.json"))
    mp = json.load(open(OUT / "maps" / f"{label}.json"))
    img = Image.open(OUT / "tilesets" / f"{slug_name}.png")
    cols, blockset, grid = ts["tile_cols"], ts["blocks"], mp["blocks"]
    w, h = mp["width"], mp["height"]
    out = Image.new("RGBA", (w * BLOCK, h * BLOCK))
    cache = {}

    def tile(idx):
        if idx not in cache:
            tx, ty = (idx % cols) * TILE, (idx // cols) * TILE
            cache[idx] = img.crop((tx, ty, tx + TILE, ty + TILE))
        return cache[idx]

    for by in range(h):
        for bx in range(w):
            tdef = blockset[grid[by][bx]]
            for ty in range(BLOCK_TILES):
                for tx in range(BLOCK_TILES):
                    out.paste(tile(tdef[ty * BLOCK_TILES + tx]),
                              (bx * BLOCK + tx * TILE, by * BLOCK + ty * TILE))
    out.save(path)
    return out.size


# --------------------------------------------------------------------------- #

def main():
    for d in ["tilesets", "maps", "sprites"]:
        (OUT / d).mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)

    const_to_slug = build_tilesets()
    build_flower()
    build_battle_hud()
    build_battle_intro()
    build_mon_icons()
    build_dex_tiles()
    build_trainer_pics()
    build_dex_entries()
    build_sprites()
    build_text()
    build_items()
    build_dex()
    build_marts()
    build_battle()
    build_link_manifest()
    build_trades()
    extract_trade_gfx()
    build_title()
    build_wild()
    build_move_sfx()
    build_move_anims()
    build_dungeon_maps()
    build_warp_rules()
    build_spinners()
    build_town_map()
    build_credits()
    build_audio()
    const_to_label = build_maps(const_to_slug)
    build_hidden_items(const_to_label)
    size = render_map_preview("overworld", "PalletTown", PREVIEW / "PalletTown.png")
    print(f"preview PalletTown: {size[0]}x{size[1]}px")


if __name__ == "__main__":
    main()
