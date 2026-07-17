# Data format: battle move animations

Extraction of pokered's per-move attack animations — the `DrawFrameBlock` subanimation
system (`engine/battle/animations.asm`) — into `assets/move_anims.json` plus the two tile
sheets `assets/move_anim_0.png` / `move_anim_1.png` (RGBA, white → transparent like all OAM
sprites). Built by `build_move_anims` in `tools/extract.py`; scope/phases in issue **#19**.
The engine player is `Battle._build_move_anim` + the `{"moveanim"}` queue marker (queued by
`_do_move` after accuracy); the common special effects run natively in
`Battle._do_special_effect`, the rare ones are stubs (see the follow-up issue).

## The pokered model (four layers)

1. **Animation script** (`data/moves/animations.asm`, `AttackAnimationPointers`) — one per
   move id, plus the post-`NUM_ATTACKS` "anim ids" (ball toss/shake/poof, status flashes,
   slide-down, safari rock/bait…). A script is a list of `battle_anim` commands; each either
   plays a **subanimation** (with a tileset id + per-frame-block delay) or runs a **special
   effect** (a code routine), and can start a move's **SFX**.
2. **Subanimation** (`data/battle_anims/subanimations.asm`, 86) — a transform **type** + N
   frames of `(frame block, base coord, mode)`.
3. **Frame block** (`data/battle_anims/frame_blocks.asm`, 122) — the OAM sprites making up
   one drawn frame: per sprite an (x, y) pixel offset, tile, and X/Y flip flags.
4. **Base coords** (`data/battle_anims/base_coords.asm`, 177) — the screen anchors the frame
   blocks are drawn relative to.

Ids everywhere are table indexes; the names come from `constants/move_animation_constants.asm`.

## `move_anims.json`

```jsonc
{
  "tilesets":     [{"img": "move_anim_0", "tiles": 79}, ...],   // battle_anim tileset id 0-2
  "base_coords":  [[x, y], ...],                                 // OAM-space px
  "frame_blocks": [[[x, y, tile, xflip, yflip], ...], ...],      // px offsets from base coord
  "subanims":     [{"type": 0-5, "frames": [[frame_block, base_coord, mode], ...]}, ...],
  "anims": {                                                     // move/anim const -> script
    "POUND":  [{"sfx": "POUND", "sub": 1, "tileset": 0, "delay": 8}],
    "MIST":   [{"sfx": null, "se": "water_droplets_everywhere"}, ...]
  },
  "anim_special_effects": {"MEGA_PUNCH": "AnimationFlashScreen", ...}
}
```

- **`anims`** — keyed by move constant (matches `move_sfx.json` / battle code), then the anim
  ids (`TOSS_ANIM`, `POOF_ANIM`, `BURN_PSN_ANIM`, …, plus the const-less `ZIGZAG_SCREEN_ANIM`).
  `sfx` is the move whose `move_sfx.json` sound starts with the command (`null` = silent).
  A subanim command carries `tileset` (0-2) and `delay` (frames waited after each frame block).
  A special-effect command carries `se` — the `SE_*` name lowercased (`"wavy_screen"`); the
  ~25 SE routines are *code* (screen shake/flashes, pic slides, spiral balls…), run natively
  by `Battle._do_special_effect` (rare ones stubbed).
- **`base_coords`** — `[x, y]` in **OAM space**: screen px = `(x-8, y-16)` (GB OAM offsets).
  Stored `[x, y]` for consistency even though the asm writes `db Y, X`.
- **`frame_blocks`** — sprites as `[x, y, tile, xflip, yflip]`; offsets are
  `dbsprite col*8+xpix, row*8+ypix`. `tile` is the **raw sheet index** (the GB adds `$31`,
  its vSprites load slot — already removed here). Sheets are 16 tiles/row.
  Quirk: `FrameBlock62` declares 15 sprites but lists 16 — the engine draws the declared
  count, so the dead 16th is dropped.
- **`tilesets`** — `MoveAnimationTilesPointers`: tileset **2 shares move_anim_0's sheet**
  capped at 64 tiles (used by the trade-ball subanims), so only two PNGs exist.

## Playback semantics (for the Phase-2 player)

- **Subanim type** (`SUBANIMTYPE_*`: 0 normal · 1 hvflip · 2 hflip · 3 coordflip · 4 reverse
  · 5 enemy) applies **only on the enemy's turn** — the player's turn plays untransformed.
  Type 5 (`ENEMY`) is the inverse: hflip on the *player's* turn, normal on the enemy's
  (`GetSubanimationTransform1/2`).
  - *hvflip*: mirror final OAM coords (`x'=168-x`, `y'=136-y`) and toggle both sprite flips.
  - *hflip*: `x'=168-x`, translate y **+40 px**, toggle X flip.
  - *coordflip*: mirror the **base coord** only (no sprite flag change).
  - *reverse*: play the frame list last → first.
- **Frame block mode** (per frame): each block writes its sprites at the shadow-OAM
  pointer; a block with a delay (modes `0`/`3`/`4`) shows a visible frame. Then `2`/`3`
  advance the pointer past the block (blocks accumulate — beams grow), `4` leaves it (the
  *next* block overwrites this one in place), and `0` erases the buffer and restarts.
  The buffer persists across a move's subanims with only the pointer reset
  (`PlaySubanimation`), so kept blocks linger (Rock Slide's lifted rocks). Quirk: `GROWL`
  skips the mode-0 erase.
- **`anim_special_effects`** (`data/battle_anims/special_effects.asm`) — anims listed here
  run their routine after **every frame block** (`DoSpecialEffectByAnimationId`), e.g.
  `MEGA_PUNCH`'s per-block screen flash, `THUNDERBOLT`'s flash every 8 blocks, the ball-toss
  arc SFX. Routine names kept verbatim for Phase 3.
- **Hit reaction** — not part of the animation data: after the move's animation,
  `PlayApplyingAttackAnimation` plays the effectiveness sting + a blink/shake chosen by
  `wAnimationType` (`AnimationTypePointerTable`: target blink for a player damaging move with
  no side effect; light shake with one; hard vertical/heavy shake for enemy damaging moves;
  slow silent shake for non-damaging moves), and only then does the HP bar drain. Mirrored by
  the `{"anim"}` queue markers `Battle._do_damage_move`/`_do_status_move` append after the
  `{"moveanim"}` marker. The enemy's AMNESIA/REST swap to `CONF_ANIM`/`SLP_ANIM`
  (`ShareMoveAnimations`, in `_build_move_anim`).

## Verifying

`python tools/preview_move_anims.py [MOVE ...]` composites the frames of a few moves from
the extracted data alone → `build/preview/move_anims_preview.png` (Thunder's bolt, Ember's
flame column, Razor Leaf's toss-then-slice, etc. should be recognizably Gen-1). The json is
also self-checked at extraction: table lengths vs the asm asserts, every referenced
subanim/frame-block/base-coord id in range, and every drawn tile within its commanded
tileset's tile count. In-engine: `pwsh tools/run.ps1 -- --moveanimtest` (frame counts, the
enemy-turn transform, a timed `{"moveanim"}` marker, posed screenshots).
