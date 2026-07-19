# Engine: battles

A 1v1 wild battle with Gen-1 rules. Data is extracted by `extract.py: build_battle`; the
engine is `game/scripts/Battle.gd` (a self-contained modal).

## Extracted data

- `assets/pokemon/base_stats.json` — `species -> {hp,atk,def,spd,spc, types[2], catch,
  base_exp, learnset, tmhm, growth}` (from `data/pokemon/base_stats/*.asm`, keyed by species name).
  `tmhm` is the TM/HM move list used for teach-compatibility (see [npcs.md](npcs.md) HM field moves).
- `assets/moves.json` — `MOVE_CONST -> {name, power, type, accuracy, pp, effect}` (the
  `move` macro rows carry the constant directly).
- `assets/types.json` — `{attacker: {defender: multiplier}}` from `TypeEffects`
  (`SUPER_EFFECTIVE`=2, `NOT_VERY`=0.5, `NO_EFFECT`=0; default 1).
- `assets/pokemon/front/<species>.png`, `back/<species>.png` — the pic PNGs (40×40 / 32×32),
  transparent + full tonal range like overworld sprites.
- `assets/trainers.json` — `OPP_CLASS -> {name, money, parties:[[{species,level},...], ...]}`
  (from `data/trainers/parties.asm` + class consts + names + `pic_pointers_money.asm`).

## Formulas (Gen-1, with DV=0 / EV=0)

```
HP    = floor((base + DV) * 2 * level / 100) + level + 10
stat  = floor((base + DV) * 2 * level / 100) + 5

# damage (per hit)
A, D  = (Special, Special) if move.type is special else (Attack, Defense)
lvl   = level*2 on a critical hit
dmg   = floor((2*lvl/5 + 2) * power * A / D / 50) + 2
dmg  *= 1.5 if move.type in attacker.types        # STAB
dmg  *= type_mult(type, def_type1) * type_mult(type, def_type2)
dmg   = max(1, floor(dmg * random(217..255) / 255))   # unless immune (0)
```

**DVs (IVs):** each mon rolls random DVs 0–15 for Atk/Def/Spd/Spc (the HP DV is the LSBs of
the four), stored in `mon.dvs` and added to base in `stat()`. EVs are 0.

**Critical hits** (`_calc_hit`, faithful to `CriticalHitTest`): chance is derived from base
Speed — normal `(baseSpeed/2 *2 /2)/256` ≈ `baseSpeed/512`; high-crit moves ×8; **Focus Energy
*quarters* it** (the Gen-1 `srl`-instead-of-`sla` bug). A crit doubles the level term **and
ignores** stat stages, burn, and Reflect/Light Screen (uses raw stats).

Special types (Gen-1, category by **type**): FIRE, WATER, GRASS, ELECTRIC, PSYCHIC_TYPE,
ICE, DRAGON. Accuracy: miss if `random(0..99) >= accuracy`.

**Badge stat boosts** (`_battle_stat`, faithful to `BadgeStatBoosts`): each gym badge raises one
of the **player's** in-battle stats by ×9/8 (`+ v>>3`) — BOULDER→Attack, CASCADE→Defense,
THUNDER→Speed, SOUL→Special. Applied wherever the player's active mon's stat is read in the damage
formula (offense and defense, crit and non-crit); the foe never gets it. Keyed off `Main.badges`.
Verified by `--badgetest`.

## Flow (`Battle.gd`)

State machine driven by `handle_input()` (it's `game.modal` during battle). Action menu is
**FIGHT / PKMN / ITEM / RUN**. A turn orders the player+enemy actions by Speed (ties random),
applies each (skipping the second if the first faints the target), and narrates via a message
queue (typewriter, A to advance). On a win the lead mon **gains EXP, may level up** (stats
recomputed, HP grows) **and learn level-up moves**. Faint → forced switch, or heal + blackout
if no usable mons. Battle ends → `finished` → `Main` clears `modal`.

- **Party + switching**: `PKMN` opens the party screen; switching in costs the turn (resets
  the switched mon's stat stages). Switches are animated (gh #72): the withdrawn mon's pic
  vanishes with "Come back, X!" (a queued `recall` marker), and the replacement pops out
  through the same ball-throw/poof/grow stage as the battle start (`send_player` marker →
  the `throw` intro stage, with the new mon's cry); the SHIFT free switch and faint-forced
  switch share the markers, and the enemy side already grows in via `next_enemy`.
- **Items**: `ITEM` uses the bag. **Poké Ball** → Gen-1 catch (see below); a catch adds the
  mon to the party and ends the battle, a miss costs the turn. **Potion** heals 20 HP (costs
  the turn). The battle bag is an ITEMLISTMENU like the overworld one, so **SELECT reorders
  it** the same way (gh #57).
- **Move reordering**: in the FIGHT menu, SELECT holds a move (hollow `▷` on its row) and a
  second SELECT swaps the two rows — move and PP together, persisting to the party mon
  (core.asm `SwapMovesInMenu`; gh #58). A/B deselects a held move; a second SELECT on the
  same row deselects too. Swapping while transformed/mimicked reorders the real moves as
  well — pokered's party write is unconditional. Verified by `--movefxtest`.
- **Transform / Mimic are battle-only** (gh #62; pokered writes `wBattleMon*`, never the
  party struct): the player's mon gets a copy-on-write overlay — Transform backs up
  moves/types and copies the target's stats/moves (PP 5); Mimic copies the moves array and
  puts the target's move **in MIMIC's own slot, keeping that slot's PP** (MimicEffect).
  The player **picks which technique to copy** when the move executes mid-turn — the
  target's move list in a box at (0,7), UP/DOWN/A only, no cancel (`.letPlayerChooseMove`,
  gh #65); the enemy copies a random non-empty move (no PP check, `.getRandomMove`).
  The overlay reverts on switch-out, forced/shift switches, and battle end
  (`_revert_battle_copy`): after Transform the real moves return untouched (transformed PP
  is separate — `DecrementPP` returns when TRANSFORMED) and stats recompute from party
  truth; after Mimic the PP spent copies back into the party slots (pokered's dual
  PP write — the mimicked move drains the original move's PP, the Gen-1 quirk).
- **Stat-change moves**: power-0 moves apply stat **stages** (−6..+6) via the move `effect`
  (`ATTACK_DOWN1_EFFECT`, `SPECIAL_UP1_EFFECT`, …); `UP` affects the user, `DOWN` the target.
  Stage multipliers scale Atk/Def/Spc in the damage formula and accuracy/evasion in the hit
  check. **PP** is tracked per move (can't pick a 0-PP move).
- **Secondary (side) effects** use the asm's exact byte thresholds (gh #75): poison
  52/103 out of 256 (PoisonEffect "20/40 percent + 1"), burn/freeze/paralysis 26/77
  (FreezeBurnParalyzeEffect) — and the latter are blocked when the target **shares the
  move's type** (BODY SLAM can't paralyze a NORMAL-type); stat-down sides 85, flinch 26/77,
  confusion 25. A faint-forced switch resets the incoming mon's stat stages and volatiles
  and adds it to the EXP split, like every other switch (gh #74).
- **Evolution runs the full movie** (gh #67; engine/movie/evolution.asm `EvolveMon` via
  `Cutscene.evolution` + `Main.run_evolution`): "What? X is evolving!", the old pic and cry,
  the Safari-Zone theme (pokered's evolution music), the accelerating black-silhouette
  flicker, and the result's cry + "X evolved into Y!" with the fanfare. **B cancels**
  (unless forced — trade evolutions), leaving the mon unevolved; a stone is consumed even on
  a cancel (the Gen-1 waste). Level-up evolutions are **deferred to battle end**
  (`Battle.can_evolve` = `wCanEvolveFlags`; only mons that leveled this battle are checked,
  so an over-leveled catch waits for its next level-up). Rare candy, stones, and trades
  share the same sequence. Verified by `--movefxtest` / `--stonetest` / `--tradetest`.
- **Status conditions** (`mon.status`, one at a time; shown as a HUD badge — audited vs
  `CheckPlayerStatusConditions` and friends, gh #176 phase 2):
  - inflicted from the move `effect` — primary (`SLEEP_EFFECT`, `PARALYZE_EFFECT`,
    `POISON_EFFECT`) always; `*_SIDE_EFFECT1/2` on damaging moves at the asm's exact bytes.
    Type-immune (can't poison Poison, burn Fire, freeze Ice; a side effect never lands on a
    target sharing the move's type).
  - The turn-start gate runs in the asm's order: **sleep** (counter 1–7 ticks; the waking turn
    is lost too) → **freeze** (no self-thaw; a Fire hit thaws) → held by the enemy's trapping
    move → flinch → **confusion** (counter ticks, then 127/256 to hurt itself — the integer
    power-40 chain against its own stage-modified Defense) → **paralysis** (64/256 fully
    paralyzed). Full paralysis and a confusion self-hit break charge/Bide/thrash/trapping
    locks (`_break_locks`): an interrupted FLY/DIG reappears and a Wrap victim goes free.
  - **PAR** quarters Speed and **BRN** halves physical Attack — destructively, on the STORED
    battle stat (see §Stat pipeline). A stage recalc of that stat rebuilds it without the
    penalty (AGILITY cures a paralyzed mon's slowness), the stat-move trailer re-applies (and
    **compounds**) the non-acting side's penalties, and **curing the status does not restore
    the stat** — it stays quartered/halved until a recalc or switch.
  - **PSN/BRN residual** is 1⁄16 max HP (min 1), ticking **after that side's own action** (per
    `HandlePoisonBurnLeechSeed`, not at end of turn), skipped on the turn its action ended in a
    faint. Toxic escalates ×counter — and the counter multiplies (and advances) on the **LEECH
    SEED drain too** (the documented Leech Seed glitch).
  - Verified by `--statustest`, `--faithtest` (toxic ×2), and `--movefxtest` (penalty-wipe
    quirk, integer self-hit, leech+toxic glitch, sleep-before-flinch order, lock breaking).
    Status persists on party mons after battle; overworld poison ticks + Pokécenter healing in
    [save.md](save.md).

## Stat pipeline (`p_mod`/`e_mod`, audited gh #176 phase 2)

The port keeps pokered's model: each side's four battle stats live in a **stored** dict
(`wBattleMon*`/`wEnemyMon*`), mutated exactly as the asm mutates RAM; the mon dicts' own stats
stay **unmodified** (`wPlayerMonUnmodified*`), used for crits (badge-free!) and recalcs.

- **Rebuild** (`_rebuild_mod_stats`) at battle start, switch-in, and mid-battle level-ups:
  unmodified × current stage ratio → burn/paralysis penalties → the player's badge boosts.
- **Badge boosts** (`BadgeStatBoosts`) go by the badge byte's even BITS, not gym order:
  **Boulder→Attack, Thunder→Defense, Soul→Speed, Volcano→Special** (Cascade boosts nothing).
  Each application is `v += v/8` capped 999.
- **Stage changes** (`_change_stage` = `StatModifier*Effect`): the changed stat rebuilds from
  its unmodified value (dropping its penalty and boost), a stat-up on a stored 999 (or a
  stat-down on a stored 1) fails with the stage rolled back — then the **trailer** runs:
  badge boosts **re-apply to all four player stats** ("will be boosted further" — the stacking
  glitch), and the **non-acting side's** par/burn penalties re-apply, compounding
  ("these shouldn't be here"). AI X items run the same pipeline.
- **Stat-down front gates**, in asm order: the ENEMY's pure stat-down moves carry a hidden
  **65/256 miss** in non-link battles; substitute blocks; MIST protects; a mid-FLY/DIG target
  can't be hit.
- Verified by `--badgetest` (mapping, Cascade-nothing, enemy unboosted), `--movefxtest`
  (quarter → AGILITY cure → foe's-Growl re-compound, burn halve through the self-hit, the
  THUNDER→def boost and its restack), and the full `--elite4stage --gauntlet`.

## Trainer battles

`Battle.start_trainer(party, enemy_data, name, money_base)` fights the trainer's **whole team**
in sequence: when an enemy mon faints (after the player gets EXP), the trainer sends out the
next one and play returns to the menu; the battle is won only when the **last** mon faints.
RUN (`"No! There's no running…"`) is disabled. A thrown Poké Ball is **not** refunded: the
ball is spent, `"The trainer\nblocked the BALL!"` / `"Don't be a thief!"` print, and the enemy
takes its turn (`ThrowBallAtTrainerMon` exits via `RemoveUsedItem`, not `ItemUseFailed`).
On a win the player gets prize money = `money_base × last mon's level`.

Trainer NPCs are tagged from their `object_event` trainer args (`OPP_CLASS, party_num`,
stored on the `NPC`). Interacting with an **undefeated** trainer starts the battle
(`Main.start_trainer_battle`); `defeated_trainers` (keyed by map+cell) stops re-fights, after
which the NPC shows its normal text. Verified by `--trainertest` (2-mon Bug Catcher, RUN
blocked, win → prize). Player money lives in `Main.player_money`.

### Trainer AI (`trainer_ai.asm`, audited gh #176 phase 2)

- **Move choice** (`AIEnemyTrainerChooseMoves`): every move starts at priority 10, the class's
  modification layers (`trainers.json` `ai_mods`, from `move_choices.asm`) adjust it, and the
  pick is uniform among the minimum-priority moves. Mod 1: +5 on pure status-ailment moves when
  the player is already statused. Mod 2 (second turn only, `wAILayer2Encouragement`): −1 on
  set-up effects (the asm's two constant ranges). Mod 3: −1 super-effective / +1 not-very when
  a better move exists — using **`AIGetTypeEffectiveness`'s first-matching-entry read**, never
  the composed multiplier (ELECTRIC into WATER/FLYING reads 2×, not 4×).
- **Item/switch handler** (`_ai_item_turn`): rolled unconditionally before the enemy's move
  (no lock gate — a wrapping or mid-FLY mon can still potion), replacing the move on success.
  Per-class thresholds are the asm's byte compares (`25 percent + 1` = r < 65, `50 percent +
  1` = r < 129, etc.), incl. CooltrainerF's missing-`ret` fall-through and Blaine potioning at
  full HP (heals 0, still spends). The **`wAICount` budget** (`ai_count`, per mon — reset at
  every send-out) is consumed by items only; **switches are free** (`SwitchEnemyMon` never
  decrements). A maxed X item still costs its use and the turn ("Nothing happened!"), and a
  successful X SPEED/X ATTACK wipes the par/brn stat penalty like any stage recalc.
- All 47 classes' `ai`/`ai_count`/`ai_mods` extractions verified byte-identical to
  `ai_pointers.asm` + `move_choices.asm`. Verified by `--movefxtest` (first-match read, free
  switch, maxed-X spend) and the full `--elite4stage --gauntlet` (Lorelei/Bruno/Agatha/Lance).

## Catch (`ItemUseBall`, audited gh #176 phase 2)

`Battle._attempt_catch(ball, rate_override)` is the full Gen-1 algorithm
(`engine/items/item_effects.asm` `ItemUseBall`), all divisions floored:

- **Rand1 span** by ball: POKé `[0,255]`, GREAT `[0,200]`, ULTRA/SAFARI `[0,150]`
  (inclusive — the asm rejection-samples; the port draws uniformly). MASTER always catches.
- **Status shave**: sleep/freeze subtract 25, any other ailment 12; underflow (`Rand1 < shave`)
  is a certain catch.
- `W = (maxHP·255 / BallFactor) / max(1, HP/4)` with BallFactor 8 (GREAT) else 12, and
  `X = min(W, 255)` — computed **before** the catch-rate compare, so X feeds the wobble calc
  whichever stage fails. Catch when `Rand1−shave ≤ catch_rate` AND (`W > 255` or
  `rand(0..255) ≤ X`).
- **Wobbles on a failure**: `Y = rate·100 / BallFactor2` (255/200/150 by ball; `Y > 255` → 3
  shakes), `Z = X·Y/255 + status2` (10 slp/frz, 5 other ailment), shakes 0/1/2/3 at
  `Z <10 / <30 / <70 / ≥70` → "You missed…" / "Darn!…" / "Aww!…" / "Shoot!…".

Around the throw, mirroring the asm: a full party **and** full box (20) refuses the throw
(no ball, no turn — `BoxFullCannotThrowBall`); the unidentified GHOST and the unveiled
MAROWAK dodge (`"It dodged the\nthrown BALL!"`, ball spent, capture calc skipped); catching a
**transformed** wild mon assumes DITTO (fresh data, DVs/HP/status carried — pokered's noted
bug); a party-full catch transfers to the PC with `"transferred to\nBILL's PC!"` (or
`"someone's PC!"` before `MET_BILL`). The safari BALL runs the same algorithm with the
bait/rock-modified rate. The POKé DOLL escapes any **wild** battle — ghost battles included;
a doll escape leaves `wBattleResult` at 0, so Tower 6F counts the MAROWAK as laid to rest
(the documented trick). Verified by `--movefxtest` (deterministic wobble spread),
`--catchtest`/`--newcatchtest`, and `--towerghosttest`.

## Triggering (`TryDoWildEncounter`, audited gh #176 phase 2)

- The player has a real **party** and a **bag**, held in `Main`.
- **Wild encounters** roll on each completed step (`Main._on_player_moved`), per the asm's tile
  rule: the encounter **rate** keys off the standing half-block's bottom-RIGHT tile (grass tile →
  `grass_rate`; water `$14` → `water_rate`; any tile indoors outside the FOREST tileset →
  `grass_rate`, gh #106) and the **table** off the bottom-LEFT tile (`$14` → water, else grass) —
  so Route 21's left-shore column really serves grass-table mons (TANGELA) at the water rate
  while surfing. The rate rolls `rand(0..255) < rate`; the slot rolls another byte against
  `wild.json`'s cumulative `slots` thresholds (51/51/39/25/25/25/13/13/11/3 per 256). No roll on
  warp cells (`IsPlayerStandingOnDoorTileOrWarpTile`).
- **REPEL** (100/200/250 steps) is a level filter, not an off-switch: the roll runs and only a
  wild mon **below the first party slot's level** is hidden; the expiry step prints "REPEL's
  effect wore off." and cannot encounter.
- **3 battle-free steps** follow every battle (`wNumberOfNoRandomBattleStepsLeft`, re-armed to 3
  by a warp mid-cooldown; the REPEL counter doesn't tick during them).
- Verified by `--wildtest` (rate %, species, tile rule, repel filter, cooldown), `--battletest`,
  `--catchtest`, `--statmovetest`.

## Move effects

All ~68 Gen-1 move effect categories are handled (dispatched on the move `effect` in
`_do_move` → `_do_damage_move` / `_do_status_move`), with per-side **volatile state**
(`_new_vol`: confusion, flinch, recharge, two-turn charge, trapping, thrash, leech, screens,
focus, mist, disable, substitute, bide):

- **Damage variants**: multi-hit (2–5 / twice / Twineedle), fixed/special damage (Seismic
  Toss, Night Shade, Dragon Rage, Sonic Boom, Psywave), Super Fang, OHKO, recoil, drain /
  Dream Eater, Jump Kick crash, Swift (never miss), Explosion, high-crit moves, Pay Day.
- **Secondary effects** (chance): status, stat-downs, flinch, confusion.
- **Volatile/field**: confusion (50% self-hit), flinch, Hyper Beam recharge, two-turn charge
  (Fly/Solar Beam/…), trapping (Wrap), Thrash, Leech Seed, Light Screen/Reflect (×2 def),
  Haze, Mist, Focus Energy, Substitute (HP buffer), Bide, Disable, Teleport/Whirlwind (flee).
- **Scripted**: Metronome, Mirror Move, Mimic, Transform, Conversion (functional).
- **Structural**: level-up **evolution**, **Struggle** (when out of PP), **move replacement**
  on learning a 5th move, EXP/leveling, status, stat stages, prize money.

Verified by `--movefxtest` (fixed/super-fang/drain/recoil/leech/heal/confuse + evolution).

## Faithful details

- **Toxic** sets a badly-poisoned counter; residual damage is `maxHP/16 × counter` and the
  counter climbs each turn (resets to normal poison on switch, since volatiles reset).
- **Substitute** costs ¼ max HP, **absorbs damage** until it breaks, and **blocks** secondary
  effects, status moves, stat-drops, confusion, and Leech Seed while up.
- **Trapping** (Wrap/Bind/Fire Spin/Clamp) locks the user into the move and **prevents the
  target from acting** for the duration (`bind`/`bound`).
- **Secondary-effect odds** are 10% (`_SIDE_EFFECT1`) / 30% (`_SIDE_EFFECT2`) — exactly
  pokered's `10 percent + 1` / `30 percent + 1`. **Screens** persist until the user switches
  (Gen-1 behavior), which falls out of the volatile reset. **Metronome** excludes itself /
  Mirror Move / Transform / Struggle.

## Presentation (Gen-1 sequences)

- **Battle transitions** (`Transition.gd`, faithful to `engine/battle/battle_transitions.asm`):
  the overworld is consumed into black by one of the **8 wipes**, picked by three bits —
  trainer battle? / enemy ≥ 3 levels above the first usable party mon? / dungeon map
  (`dungeon_maps.json` from `data/maps/dungeon_maps.asm`)? Outdoor wild battles play the
  **triple screen flash** first, then the circle sweep (double half-circles when you outlevel,
  a single slower one otherwise); outdoor trainers get the square **spiral** (inward/outward);
  dungeon wilds the interlaced **stripe combs** (horizontal/vertical); dungeon trainers the
  **shrink**/**split** collapse of a frozen screen grab. All tile orders, step pacing (3
  tiles/frame spiral, 3-frame arc steps, ...) and the exact `CircleData` arc shapes are
  transcribed from the asm. The wipe runs before `Battle` opens (as `BattleTransition` runs
  before `_InitBattleCommon`); tests skip it (`fast_hp`). Verified by `--wipetest`.
- **Battle exit**: the screen cuts to white over the reappearing overworld, holds 10 frames,
  and fades in over 3 palette steps of 8 frames (`.battleOccurred` → `MapEntryAfterBattle` →
  `GBFadeInFromWhite`); dark maps skip it, as do tests.
- **Warp fade**: doors/stairs/warps play the map-change sound and fade to black in 4 palette
  steps of 8 frames (`PlayMapChangeSound` + `GBFadeOutToBlack`), the new map appearing in a
  cut. Dark caves skip the fade (the `wMapPalOffset` check), as do tests.
- One deliberate deviation: the circle sweep's `CircleData5` arms are extended one row so the
  sweep consumes the 4 pivot tiles at the screen center — the GB left them unpainted until its
  final whole-palette blackout, which reads as a hole at modern clarity.

- **Battle-start intro**, faithful to `_InitBattleCommon`/`PrintBeginningBattleText`/
  `StartBattle`/`SendOutMon` and driven by `{"intro": …}` + auto-advancing `{"auto": …}` text
  markers (no A presses until the menu): after the battle wipe, the player's back pic and the
  enemy mon — or the **enemy trainer's pic** — slide in from opposite edges as dark
  silhouettes (144 px at 2 px/frame ≈ 1.2 s), palettes reveal (Delay3), then
  — *wild:* the mon's cry, the player's pokeball bracket, "Wild X appeared!" types, the enemy
  HUD joins it, a 40-frame beat;
  — *trainer:* the `SFX_TRAINER_APPEARED` sting + a beat, **both** parties' brackets (the
  enemy's mirrored top-left, balls filling right-to-left), "wants to fight!", the trainer
  slides off right (8 tile-steps × 2 frames), "sent out X!", the mon **grows in**
  (`AnimateSendingOutMon` 3×3 → 5×5 → full) + cry + HUD, the 40-frame beat.
  Then both: the player pic slides off left (9 × 2 frames), "Go! X!" types, the player HUD
  appears, the real `POOF_ANIM` smoke burst, the mon pops out, and its cry plays. Safari
  battles run the wild intro with no send-out — the player's own pic stays up all battle.
  A trainer's **mid-battle send-out** reuses the grow+cry via the `{"next_enemy"}` marker.
- **HP-bar drain** (`UpdateHPBar2`): every in-battle HP change (damage, recoil/drain, poison/
  burn/leech, healing) animates the bar sliding to the new value (~2 frames/pixel) with the HP
  number counting down. A per-side `_shown_hp` drives the HUD; `_set_hp(mon, hp, msgs)` sets the
  value and queues an `{"hp"}` drain marker.
- **Faint** (`SlideDownFaintedMonPic`): the fainting pic sinks straight down out of view (the
  player's mon cries, the enemy uses the fall SFX) before the "fainted!" message.
- **Level-up stats box** (`PrintStatsBox`): the new ATTACK/DEFENSE/SPEED/SPECIAL show in a box
  on the right while "X grew to level N!" stays in the text box.
- The bottom text box blinks a ▼ "more" arrow when a message is fully revealed.
- **HUD** is built from the real HUD tiles at pokered's exact coords (name/level, `HP:`/bar/
  caps, the corner/line/triangle bracket), mirrored between player and enemy.
- Tests set `battle.fast_hp` to skip these animations (instant) so logic tests stay fast; the
  `--statustest` render poses the intro stages / drain / faint / level-up box for verification.

## Evolution & learning

- **Level-up** evolution happens after a level-up; **stone** evolution is triggered from the
  overworld ITEM menu (use a stone on a party mon → `Main._try_stone`/`_evolve_mon`).
- **Trade** evolution triggers on **in-game NPC trades** (see below).
- **EXP** (`GainExperience`, audited gh #176 phase 2) is split among the living party mons that
  participated against the enemy (`participants`, reset per enemy on switch-in). Each gets
  `floor((base_exp / N) × level / 7)`, then **×1.5 for a traded mon** (foreign OT) and **×1.5 for
  a trainer battle** — both boosts stack (`BoostExp` = `q + floor(q/2)`), capped at the level-100
  exp. **Stat exp** accumulates the defeated mon's raw base stats / N (capped 65535), folded into
  the stats at the next recalc via `CalcStat`'s sqrt term. **EXP.ALL** halves the base exp and
  base stats up front, then splits that halved pool a second time across the whole party (fighters
  or not) divided by the party count. Verified by `--battletest` and `--movefxtest` (boost + split
  assertions).
- Learning a **5th move** opens an interactive "delete a move?" panel (`learn` state).
- **Transform** copies the target's stats, types, moves, stat stages, and on-screen sprite.

## Determinism — the lockstep oracle (gh #2, ADR-014)

v1.1 link battles run **deterministic lockstep**: both peers simulate the identical battle
from a shared seed and exchange only the players' chosen actions, so the battle engine is
under a hard determinism requirement — same seed + same action sequence ⇒ the identical
battle, always, across processes.

- **Battle-local RNG.** Every battle-*logic* random draw goes through `Battle._ri(n)` /
  `_rr(lo,hi)` / `_rf()` — a battle-local `RandomNumberGenerator` seeded in `_begin`
  (`battle_seed`; set `next_seed` before `start*()` to force it — a link session will fix it
  at establishment, tests pin it). The **global** RNG (which the overworld advances at frame
  rate: NPC wander, encounter rolls) is never consulted after battle start, so frame timing
  cannot shift battle outcomes. Each draw advances `rng_cursor` — the lockstep "RNG cursor".
  Presentation (animations, tweens) draws nothing from the battle RNG, so animations
  on/off/skipped cannot desync peers.
- **The event stream.** Every battle appends canonical lines to `det_stream` (echoed as
  `[battledet]` stdout lines when `det_log` is set — the v1.1 soak reads logs):
  - `S|<kind> seed=N|c=0|<digest>` at battle start;
  - `T<n>|p[<action>]e[<action>]|c=<cursor>|<digest>` per turn (from `_end_of_turn`, the
    funnel every turn kind passes through — fight/switch/item/run alike). Actions are
    canonical: `m:MOVE`, `w:idx` (switch), `i:ITEM`, `r` (run), `f:MOVE` (forced locks);
  - `X|…` for mid-flow player decisions (faint replacement, SHIFT free switch, MIMIC's
    pick, the learn-move pick) — every choice that must cross the wire under lockstep;
  - `END|won=… caught=… blackout=…` at battle end.
  The digest is an md5 over a fixed-field-order dump of everything battle rules touch: both
  parties' full mon state (species/level/exp/HP/status/stats/types/moves+PP), stat stages,
  the stored battle stats (`p_mod`/`e_mod`), volatiles, and the AI/run counters. **Equality
  of two peers' streams is the definition of "in sync"** (ADR-014); a divergence names the
  turn it happened on.
- **The replay check** (`--battledettest [--verbose]`): scenario battles driven through the
  real input state machine — trainer AI classes with items/switches, status moves, player
  switching, bag items, multi-turn locks (WRAP/THRASH/HYPER BEAM), confusion, multi-hit,
  Transform/Mimic/Metronome/Disable/Substitute, and the wild catch/run rolls — each run
  **twice from the same seed** (streams must be byte-identical) and **once from another**
  (streams must differ, so the oracle can't pass vacuously — the gh #84 lesson). Each
  scenario prints its `stream_md5`, so separate *invocations* are comparable too: lockstep
  peers are separate processes, and the md5s are stable across processes.
- Float ops in the damage/crit path (`_rf() < b/256.0`, the ×217..255/255 roll) are IEEE-754
  double arithmetic — bit-stable across runs and across x86-64 builds of the same version;
  the v1.1 link-identity handshake (exact version + content hash) is what guarantees both
  peers run the same code and data. The two-machine guarantee is re-proven by the gh #8
  desync soak.

## In-game trades (`Main`)

The 10 `TradeMons` (give→get→nickname) are extracted to `assets/trades.json`, along with a
`text_trades` map (NPC `TEXT_*` id → trade index, parsed from each trade-house script's
`ld a, TRADE_FOR_x`). Talking to a trade NPC (`interact`) offers the trade: if a party mon
matches the requested species it's swapped for the received one at the same level
(`_do_trade`, one-shot via `traded_npcs`). A received species that evolves by trade
(`EVOLVE_TRADE`: Haunter→Gengar, Kadabra→Alakazam, Machoke→Machamp, Graveler→Golem) **evolves
immediately** — this is the `InGameTrade_CheckForTradeEvo` mechanic, generalized from the
Graveler/Haunter name-check (a Japanese-Blue leftover) to all trade-evo species. Verified by
`--tradetest` (Poliwhirl→Jynx, and Haunter→Gengar on receipt).

> The 8 reachable English trades don't *give* a trade-evo species, so you won't see a trade
> evolution from them in normal play (correct to English R/B); the path is in place for any
> trade that does. Player↔player trading isn't possible single-player.

## Remaining approximations

- Overworld poison ticks + Pokécenter healing are implemented (see [save.md](save.md)).
  Trade NPCs swap at the given mon's level (the received mon keeps the OT nickname). Gen-1
  **stat exp** IS modelled now (see the EXP note above) — accumulated per battle and folded into
  the stats at each recalc.
- A PC/box when the party is full; the bag is a flat dict (no item screen outside battle).
- (Formerly listed here, all long since implemented: per-map wild tables + rates — see
  §Triggering — trainer line-of-sight, the rival's starter-dependent party, and gym-leader
  scripting.)
- **Per-move attack animations are in** (the `DrawFrameBlock` subanimation system, issue
  **#19**): `_do_move` queues a `{"moveanim": MOVE, "attacker": side}` marker (in place of the
  old placeholder flash) which plays the move's real tile animation — `_build_move_anim`
  compiles the extracted script into timed shadow-OAM steps drawn over everything, and
  `_do_special_effect` runs the SE commands natively (screen flash + dark/light palettes,
  BG-only shake, pic hide/show/blink, the Tackle lunge, the Seismic-Toss/Withdraw/Whirlwind
  slides, delays). After the animation comes the **hit reaction**
  (`PlayApplyingAttackAnimation`), *then* the HP-bar drain: the effectiveness sting together
  with — per `AnimationTypePointerTable` — the target blinking (player damaging move, no side
  effect), a light shake (player, side effect), a hard vertical/horizontal shake (enemy
  damaging moves), or the slow silent shake after non-damaging moves (`PlayBattleAnimation2`).
  The enemy's AMNESIA/REST reuse the confusion/sleep anims (`ShareMoveAnimations`). A missed
  move plays neither animation nor sound; `fast_hp` tests fall back to the plain
  MoveSoundTable cue. See
  [../data-formats/battle-anims.md](../data-formats/battle-anims.md); verified by
  `--moveanimtest`. *Deferred:* ~15 rare special effects are stubs (spiral balls, wavy screen,
  water droplets, pic warps, falling leaves/petals…), the per-anim frame-block hooks
  (`AnimationIdSpecialEffects`) aren't wired, and slides don't clip to the pic box. The intro
  slide-in, HP-bar drain, faint slide, level-up stats box, and the pixel-faithful HUD are done
  (see **Presentation** above).
