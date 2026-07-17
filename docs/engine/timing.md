# Timing: pokered's frame domains → real seconds

The port renders at Godot's full framerate but must *pace* everything like pokered. pokered
has **two timing domains**, and converting a frame count to seconds requires knowing which
one a routine lives in:

1. **V-blank waits (~60 Hz).** `DelayFrame` waits one LCD V-blank (59.7 Hz; we use the
   nominal 1/60 s). Anything that calls `DelayFrame`/`DelayFrames` directly runs here:
   the whole **battle engine** (move animations' per-frame-block `delay`, blinks, shakes,
   slides, HP-bar drain), **text** (`PrintLetterDelay`), sound timing, screen fades, the
   emotion bubble's `DelayFrames 60`.
2. **Overworld ticks (~30 Hz).** The overworld loop runs **two** `DelayFrame`s per
   iteration (`home/overworld.asm` `OverworldLoop` → `OverworldLoopLessDelay`), so
   everything counted in overworld iterations runs at half rate: player/NPC movement,
   the ledge jump, sprite walk-animation counters, NPC movement delays, spin tiles.

**Convention:** `seconds = vblanks / 60`, and `1 overworld tick = 2 V-blanks`. When porting
a timing, cite the asm and state the arithmetic in a comment.

## Reference values (all verified against the asm)

| What | pokered | Port |
|---|---|---|
| Player walk step | 8 ticks × 2 px = 16 VB | `Player.STEP_TIME 0.268` s/tile |
| Bicycle | extra `AdvancePlayerSprite`/tick = 8 VB | `step_scale 0.5` (0.134 s/tile) |
| Ledge hop | 16 `PlayerJumpingYScreenCoords` entries, 1/tick = 32 VB; peak −12 px | `JUMP_TIME 0.536`, `ARC 12` |
| NPC walk step | 16 ticks × 1 px = 32 VB; anim frame every 4 ticks (stand/walk/stand/walk-mirrored) | `NPC.STEP_TIME 0.536` + 4-phase `_phase` cycle |
| NPC wander delay | random [1,$7F] ticks; a 0 roll wraps to $100 (quirk kept) | `NPC._reset_timer` |
| Boulder push | one NPC-speed tile slide | tween at `NPC.STEP_TIME` |
| Text letter delay | `wOptions & $f` VB/char; default MEDIUM = 3 (FAST 1, SLOW 5) | `SPEED 20.0` glyphs/s (TextBox + Battle) |
| Emotion bubble (`!`) | `DelayFrames 60` = 1.0 s | `Cutscene.trainer_battle wait(1.0)` |
| Battle subanim frame delay | `delay` VB per frame block | `delay / 60.0` (`_build_move_anim`) |
| Hit blink | 6 × (5+5) VB (`AnimationBlinkMon`) | `{"anim":"hit"}` handler |
| Hit shakes | decaying window bounce b..1 px; rWX halves ≈4+5 VB, rWY 3+3 (`PredefShakeScreen*`) | `{"anim":"shake"}` handler |
| Status-move sway | ±b px at 1 px / 2 VB, twice (b: player 3 / enemy 6) | `{"anim":"sway"}` handler |
| Tackle lunge | pic shifts 8 px for `DelayFrames 3` | `move_mon_horizontally` |
| Pic slides | off: 8 × 3 VB (0.4 s); up/down: 7 × Delay3 (0.35 s) | `_anim_slide` |
| HP-bar drain | ~2 VB per pixel (`AnimateHPBar`) | `{"hp"}` handler |

Every `DelayFrames N` seen in battle code is `N / 60` seconds — no halving. Every count of
overworld loop iterations is `N / 30`.
