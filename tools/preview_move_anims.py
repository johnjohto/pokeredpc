#!/usr/bin/env python3
"""Composite battle move-animation frames from the extracted data (gh #19 phase 1).

Renders each move's subanimation frames purely from assets/move_anims.json + the
move_anim_* sheets — no engine involved — to verify the extraction visually:

    python tools/preview_move_anims.py [MOVE_CONST ...]
    -> build/preview/move_anims_preview.png

Mimics the engine's shadow-OAM writes (docs/data-formats/battle-anims.md): each frame
block writes its sprites at the OAM pointer, a frame is snapshotted at every block with
a delay (modes 0/3/4), then the mode moves the pointer — 2/3 advance past the block,
4 leaves it (the next block overwrites), 0 erases the buffer and restarts. The buffer
carries across a move's subanims (PlaySubanimation resets only the pointer).
Untransformed (player's-turn) view; panels are GB-screen sized on the lightest green.
"""
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "preview" / "move_anims_preview.png"
BG = (0xE0, 0xF8, 0xD0, 255)
MOVES = sys.argv[1:] or ["THUNDER", "EMBER", "RAZOR_LEAF", "GUST", "BUBBLEBEAM", "SING"]
COLS = 6

data = json.load(open(ROOT / "game" / "assets" / "move_anims.json"))
sheets = {n: Image.open(ROOT / "game" / "assets" / f"{n}.png")
          for n in {ts["img"] for ts in data["tilesets"]}}


def render(oam):
    im = Image.new("RGBA", (160, 144), BG)
    for sheet, t, x, y, xf, yf in oam:
        g = sheet.crop((t % 16 * 8, t // 16 * 8, t % 16 * 8 + 8, t // 16 * 8 + 8))
        if xf:
            g = g.transpose(Image.FLIP_LEFT_RIGHT)
        if yf:
            g = g.transpose(Image.FLIP_TOP_BOTTOM)
        im.alpha_composite(g, (max(x, 0), max(y, 0)))
    return im


def frames_for(move, max_frames):
    snaps = []
    oam = []                               # flat shadow-OAM sprite list
    for cmd in data["anims"][move]:
        if "sub" not in cmd:
            continue                       # special effects are code (phase 3), skip
        sheet = sheets[data["tilesets"][cmd["tileset"]]["img"]]
        ptr = 0                            # wFBDestAddr, in sprites
        for fb, bc, mode in data["subanims"][cmd["sub"]]["frames"]:
            bx, by = data["base_coords"][bc]
            block = [(sheet, t, bx - 8 + x, by - 16 + y, xf, yf)
                     for x, y, t, xf, yf in data["frame_blocks"][fb]]
            oam[ptr:ptr + len(block)] = block      # write at the pointer
            if mode != 2:                  # modes with a delay show a frame
                snaps.append(render(oam))
            if mode in (2, 3):
                ptr += len(block)
            elif mode != 4:                # 0: erase + restart (GROWL keeps its sprites)
                if move != "GROWL":
                    oam = []
                ptr = 0
    if len(snaps) > max_frames:            # sample the sequence evenly
        step = (len(snaps) - 1) / (max_frames - 1)
        snaps = [snaps[round(i * step)] for i in range(max_frames)]
    return snaps


grid = Image.new("RGBA", (COLS * 164 + 4, len(MOVES) * 148 + 4), (40, 40, 40, 255))
for row, mv in enumerate(MOVES):
    for col, im in enumerate(frames_for(mv, COLS)):
        grid.alpha_composite(im, (4 + col * 164, 4 + row * 148))
OUT.parent.mkdir(parents=True, exist_ok=True)
grid.save(OUT)
print(f"preview {OUT.relative_to(ROOT)}: {', '.join(MOVES)}")
