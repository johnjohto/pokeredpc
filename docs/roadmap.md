# Roadmap & status

**Living document** — update the table when a milestone lands; add sub-tasks as discovered.

**After 1.0 (direction):** **v1.1 = multiplayer** — the extended design conversation happens *immediately
after 1.0*; it ships on v1 and also sets requirements for v2. **v2** is the fan-game creation toolkit
(standalone Studio editor + generic engine + shareable projects) — see [v2/plan.md](v2/plan.md) and
ADR-013. Sequence: **1.0 → v1.1 multiplayer → v2**. No v2 work begins until multiplayer's shape is known.

**Versioning:** SemVer where **`0.9.x` = full audited parity** (every system verified against the
disassembly) and **`1.0.0` additionally requires a complete playthrough sign-off** — audits prove
systems in isolation; only a full run proves the game — a **two-stage hybrid gate** (an automated
seeded legit-play run → the human playthrough; see [decisions.md](decisions.md) ADR-011). (MINOR = content/feature milestones,
PATCH = fixes/polish). The version lives in `VERSION` + `project.godot`
(`application/config/version`, shown on the title screen) and is git-tagged `vX.Y.Z`; see
`CHANGELOG.md`. **Current: `1.0.0` — SHIPPED 2026-07-17.** The ADR-011 two-stage gate is closed:
Stage 1 (the seeded legit-play bot, NEW GAME → HALL OF FAME, seeds 1+2 GREEN) and Stage 2 (the
complete human playthrough, signed off after ~60 fixed playtest issues and the full audit
campaigns gh #19–#22/#176/#185). Every engine system maps to a completed audit; the tracker is
at zero open bugs. **The next milestone is the v1.1 multiplayer design conversation** (to be
held with the user — no multiplayer work before its shape is agreed), then v2 (ADR-013).
Earlier: the playthrough bug waves (gh #23–#52, 27 issues) are fully fixed across 0.9.1–0.9.12:
and the playthrough bug waves (gh #23–#52, 27 issues) are fully fixed across 0.9.1–0.9.12:
options/start/yes-no boxes, party + summary + battle-item screens, Pokédex (with working
DATA/CRY/AREA/QUIT), the mart rebuilt as its own modal, nurse heal ceremony, catch-flow
presentation, the GB's off-centre camera, test-save isolation, and white emote bubbles — each
verified against the user's reference screenshots (`build/preview/bugs/`).
Engine sweeps (July 3): the move-effect table is at 100% coverage (RAGE was the last gap), the
full Gen-1 trainer AI is in (move-choice layers + all 19 item/switch handlers), and stat
experience (Gen-1 EVs) landed — GainExperience + CalcStat's sqrt term. The crit formula was
audited asm-exact (all four focus/high-crit paths).
Remaining: the low-traffic map beat passes (gh #22), then the playthrough continues → 1.0. The
**Stage-1 legit-play bot** (gh #76, ADR-011) now plays **the whole game from NEW GAME to the HALL OF
FAME**, and as of 2026-07-10 **all 21 stages are green** on seed 1 (`opening → parcel → brock → misty →
bill → ssanne → surge → rocktunnel → erika → silphscope → pokeflute → snorlax → koga → safari → saffron →
silph → sabrina → blaine → giovanni → victoryroad → elite4`) — `tools/validate_gate.py` on the assembled
run reports **GATE GREEN** (21 checkpoints in order, HALL OF FAME entered, no `FAIL(`/`stayed put`/
`SCRIPT ERROR`/teleport tells). The Champion fell at L65. This was first proven as a chain of
`--from=<stage>` segments; the **single unbroken process** was blocked on **gh #98** — the
`Engine.time_scale = 25` clobber that had never taken effect, so a full run at real time was 90+ minutes,
past the background-job ceiling. **gh #98 is now fixed** (2026-07-11): a driver owns the clock, 25× is
live everywhere, and the runs stay faithful (nav budgets already scaled by the live time scale, and the
battle RNG never depended on it). Verified — `--surgenavtest --route9` (nav+whiteout+warps) 3 s,
`--erikastage` (catch + gym leader) 41 s, `--elite4stage --gauntlet` (the tightest battle loop, ~40 min
before) **21 s**, and `--from=misty` chained through **14 stages** at speed. A full seeded run now reaches
Mt. Moon in ~82 s, so the single-process sign-off run became feasible — and, after gh #131, **green**.
That first full continuous run surfaced a systemic robustness gap the chained `--from` segments had hidden:
the early stages (unlike Misty onward) challenged their gyms/gauntlets with **no potions and no whiteout
retry**, so an RNG-unlucky faint whited out to Pallet's default respawn and ended the run — and at 25× the
frame-timing-shifted RNG makes those winnable fights lose often enough to matter (Brock, then Nugget Bridge,
then Mt. Moon each surfaced in turn). The `brock`, `misty` (Mt. Moon), and `bill` legs now heal at the town
Center (registering it as the respawn), carry potions so the mid-battle heal can fire, and retry a lost leg —
exactly what the later stages and a real player do (gh #131). **`--playthrough --seed 1` now runs green
NEW GAME → HALL OF FAME in one unbroken process** — all 21 checkpoints in order, `validate_gate.py` → GATE
GREEN, Champion beaten on Elite Four attempt 4 at L73, ~21 min wall-clock. The textbook single-process
Stage-1 sign-off is done; the human playthrough (ADR-011 Stage 2) is what remains to gate 1.0.

## Milestones

| # | Milestone | State | Notes |
|---|---|---|---|
| 0 | Asset extraction pipeline | ✅ done | overworld tileset + Pallet Town |
| 1 | Map rendering (block→tile) | ✅ done | custom 2D draw in `Main.gd` |
| 2 | Collision | ✅ done | bottom-left-tile (feet) passability rule |
| 3 | Grid-walking player + camera | ✅ done | placeholder sprite → real sprite in M4 |
| 4 | Real player sprite + walk animation | ✅ done | `gfx/sprites/red.png`, 6 frames |
| 5 | All maps + tilesets extracted | ✅ done | 223 maps, 24 tilesets |
| 6 | Warps / doors (enter buildings) | ✅ done | round-trip verified |
| 7 | Map connections (seamless routes) | ✅ done | offsets verified (incl. non-zero) |
| — | Ledge hops + tall-grass overlap | ✅ done | overworld polish (pre-M8) |
| 8 | NPCs (sprites + movement + collision) | ✅ done | wander, solid, interaction hook |
| 9 | Text boxes + font | ✅ done | typewriter, pages, signs+NPCs; 653/1209 ids |
| 10 | Menus (start menu, yes/no, lists) | ✅ done | reusable cursor menu; modal input model |
| 11 | Battle engine (complete) | ✅ done | all move effects, status, evolution, trainers, items |
| 12 | Save system + Pokécenter heal + overworld poison | ✅ done | JSON slot, continue on launch; see [engine/save.md](engine/save.md) |
| 13 | Audio — music | ✅ done | GB 4-channel synth of pokered song data; see [engine/audio.md](engine/audio.md) |
| 14 | Audio — SFX / cries | ✅ done | 151 SFX (both banks) + 151 cries; menu blip, cry, and per-action battle SFX wired |

## Current focus

The **main quest is completable end-to-end** (0.6.0) and most **side content** is now in too.
Landed since 0.6.0 (all `--<flag>` tested): Saffron drink-gate; the **Game Corner** (faithful slot
machines + coins + prize room); **Good/Super rods**; **static legendaries** (Articuno/Zapdos/Moltres/
Mewtwo + Power Plant Voltorbs); **gift Pokémon** (Eevee, Hitmon choice, Magikarp salesman);
**fossils** (Mt. Moon pick → museum amber → Cinnabar revival); the **Pokémon Mansion switches** +
**Cinnabar Gym** SECRET KEY lock; and the **Victory Road** boulder-switch door puzzle. In-game
trades, the Safari Zone, fishing, Day Care, the PC, and remappable controls were already in.

**Remaining toward 1.0:** a broader faithfulness audit. The two previously-deferred items — the
**Seafoam B4F strong current** and the **Silph Co card-key door lock** — are now both implemented
(see below).

**Map-script faithfulness campaign (gh #22):** the story-critical sweep is done — Pallet, Oak's
Lab, Viridian (+ the old-man catching demo), Pewter (+ the two escort drags & east gate),
Cerulean, Routes 22/24/25 + Bill, Vermilion + S.S. Anne, Lavender/Pokémon Tower (+ the
unidentified-GHOST battle system), Celadon (+ spin tiles, also Viridian Gym's), Saffron/Silph
(+ the 7F corridor ambush), Cinnabar (+ the quiz doors). Each map was beat-audited against its
asm (emotes, music cues, no-wait text, walk choreography, object toggles). Remaining: the
lower-traffic maps and small deferred deltas — see the #22 checklist.

**Menus/options audit:** the **OPTION menu is in** (`OptionsScreen.gd`, faithful to
`DisplayOptionMenu`): text speed drives both text boxes, BATTLE ANIMATION OFF plays the 30-frame
beat, and **BATTLE STYLE SHIFT** adds the missing "Will ⟨PLAYER⟩ change POKéMON?" free-switch
prompt before a trainer's next mon; saved with the game, reachable from the start + main menus.
The start menu gained its conditional POKéDEX / player-name / EXIT entries. Audited-and-OK:
the Pokédex list (owned dots, SEEN/OWN, DATA/CRY/AREA side menu + entry pages), party menu
(icons/HP rows + STATS/SWITCH submenu), the PC family (Bill's/player's/Oak's-rating/item PC with
TOSS), marts + quantity picker, save screen, the trainer badge card, bag capacity/TOSS, the
League PC. Verified by `--optiontest` / `--menutest`.

**Music-engine audit (gh #73, v0.9.27):** songs **loop at their real `sound_loop` points** —
each channel walks its intro then one loop body, and the wav loops over
`[max intro end, + lcm(bodies)]`, so intros never replay, unequal channels keep cycling (the
title screen's drums roll on under the ended melody), and jingles play once. The audit also
landed: **vibrato** / **toggle_perfect_pitch** / **duty_cycle_pattern** / **pitch_slide**
(previously parsed-and-dropped), the real **channel-3 wavetables** (incl. the per-bank glitch
wave 5 — Lavender Town's lead) at the correct **half-rate frequency** (basslines were an
octave high), **drums as the real noise instruments** through a Gen-1 **LFSR** (the poly
register was ignored — every drum and noise SFX was the same white hiss),
finalbattle's cross-channel `sound_call`s (silently skipped bars), and `PlayBattleMusic`'s
picks (gym leaders + Lance → gym-leader theme, the Champion → finalbattle). See
[engine/audio.md](engine/audio.md); verified by `--audiotest` / `--presynthtest`; listen
artifacts in `build/preview/audio/`.

**Menu-stack + item-list audit (gh #66, v0.9.26):** menus now stack like pokered's shared
tilemap — the START menu stays under the bag (hollow ▷ parked on ITEM), the bag under
USE/TOSS, and the toss ×NN picker + YES/NO confirm pile on top (`Menu.push_under`/`under`);
the item list is the faithful ITEMLISTMENU (16×11 box at (4,2), names col 6 rows 4-10, ×NN
quantities below-right — none for key items — the ▼ at (18,11), the 3-row cursor window +
scroll rule), the USE/TOSS box sits at its real (13,10), and bag messages overdraw the stack's
bottom rows (textbox z-bump). See [engine/menus.md](engine/menus.md); verified by `--bagtest`
/ `--keybindtest` / `--uishot` (usetoss/tossqty/tossconfirm shots).

**Item-menu behavior audit (gh #56/#57/#58, v0.9.19):** using or tossing an item returns to the
bag with the cursor kept (`ItemMenuLoop` + `wBagSavedMenuItem`); only a successful escape rope /
itemfinder / flute / rod / bicycle closes the menu (`UsableItems_CloseMenu`), and the bicycle
skips USE/TOSS. SELECT-swap now matches `HandleItemListSwapping` on every ITEMLISTMENU (bag,
PC item lists, battle bag, mart SELL) with the hollow-▷ held marker, and SELECT reorders moves
in the battle FIGHT menu (`SwapMovesInMenu`). Verified by `--bagtest` / `--keybindtest` /
`--movefxtest`.

**Audit fallout batch (gh #59–#64, v0.9.20):** B backs out of every start-menu screen to the
START menu (`RedisplayStartMenu`); TM/HM use plays the "Booted up" confirm and runs the
LearnMove forget flow (abandon loop, HM moves can't be deleted, TM consumed only on learn);
ESCAPE ROPE is gated to the EscapeRopeTilesets; bag stacks cap at 99 (AddItemToInventory_)
and an emptied slot resets the bag cursor; Transform/Mimic act on a battle-only copy that
reverts on switch-out/battle end with pokered's PP quirks (`DecrementPP`); `--stonetest`
repaired (it drove the start menu by stale index and relied on the debug default bag).

**Boot-intro audit is done** (splash.asm/intro.asm/title.asm): the third audio bank (the intro SFX)
is now extracted, and the whole boot plays faithfully — copyright 3 s, the silent letterboxed beat,
the shooting star + logo flash + falling stars with their sounds, the Gengar/Nidorino fight with
its hip/hop/raise/crash/lunge cues and full 80-frame entrance, and the title's logo-bounce crash →
beat → version whoosh → only then the music, with the shown mon's cry on START. Posed by
`--introshot`; regression `--titletest`.

**Battle transitions + warp fade are in** (see [engine/battle.md](engine/battle.md)
"Presentation"): pokered's full 8-wipe system (flash + circle sweeps / spirals / stripe combs /
shrink & split, picked by the trainer/level/dungeon bits with `dungeon_maps.json`) replaces the
placeholder blinds, and warps fade to black with the map-change sound (`GBFadeOutToBlack`).
Verified by `--wipetest`.

**Battle-screen faithfulness pass** (the audit's first area, see [engine/battle.md](engine/battle.md)
"Presentation"): the HUD is rebuilt from the real HUD tiles at pokered's exact coords; the full
Gen-1 **start intro** is in and audited line-by-line against the asm — auto-advancing intro texts,
the faithful wild order (cry → balls → "appeared!" → HUD → 40-frame beat), the complete **trainer
intro** (trainer silhouette slide-in, sting, both ball brackets, slide-off, the sent-out mon
growing in + cry, reused for mid-battle send-outs), and the safari variant (no send-out, the
player's pic stays); the **HP bar drains** (`UpdateHPBar2`) on every HP change;
the **faint** slides the pic down (`SlideDownFaintedMonPic`); and level-up shows the real **stats
box** (`PrintStatsBox`). Move-effect message ordering was verified faithful. **Per-move attack
animations are in (issue #19,** all four phases**):** `build_move_anims` extracts the full
`DrawFrameBlock` system (203 anim scripts, 86 subanimations, 122 frame blocks, 177 base coords + the
`move_anim_0/1` tile sheets) into `move_anims.json` — see
[data-formats/battle-anims.md](data-formats/battle-anims.md); `Battle._build_move_anim` compiles any
anim into timed shadow-OAM steps (faithful write-pointer/mode semantics, enemy-turn transforms,
per-subanim SFX) played by a `{"moveanim"}` queue marker; the common **special effects** are native
(screen flash/palettes, BG-only shake, pic hide/show/blink, lunges, slides); and `_do_move` queues
the real animation followed by the faithful **hit reaction** then the HP drain
(`PlayApplyingAttackAnimation`: sting + target blink / light/heavy/vertical shake by
`AnimationTypePointerTable`; slow silent shake for status moves; a miss plays neither animation nor
sound). Verified
by `tools/preview_move_anims.py` (data-only composite) + `--moveanimtest` (in-engine: counts,
transforms, timed markers, a real fight turn, posed shots). **The special-effect routines are in
(gh #20, DONE):** every `SpecialEffectPointers` entry is handled in `Battle._do_special_effect`
(commit `bb96418`) — spiral balls, water droplets, wavy screen, squish/minimize/transform pic warps,
falling leaves/petals, the ball fountains, slides/blinks/shakes — and the per-anim frame-block hooks
(`AnimationIdSpecialEffects`: Mega Punch's per-block flash, the Blizzard/Thunderbolt/Hyper Beam flash
cadences, Explosion's vanish, Growl's note trail, Rock Slide's shakes) are wired in `Battle._anim_hook`
(commit `3377c8f`). Verified by `--moveanimtest` (all 203 anims build; every SE smoke-plays and cleans
up its render state; the hooks fire). **`wavy_screen` is now the faithful per-scanline raster** (Psychic/
Confusion/Psywave/Night Shade): `_do_wavy_screen` freezes the 160×144 frame to a texture and `_draw`
redraws it row-by-row shifted by pokered's `WavyScreenLineOffsets` table (±2px, the wave advancing one
row per frame for 255 frames), replacing the earlier whole-screen sine shake. The capture's
`frame_post_draw` is headless-guarded (gh #103; headless keeps the faithful duration with no visual).
Posed by `--moveanimtest` (`moveanim_wavy.png`). **The last stylised particle effects are now
per-OAM exact** (the gh #22 closeout): spiral balls trail the real `SpiralBallAnimationCoordinates`
pairs (3 balls, 5-frame steps, the ending screen flash), the water droplets replay
`AnimationWaterDropletsEverywhere`'s byte-wraparound rain (64 one-frame screens), and Razor Leaf /
Petal Dance run `AnimationFallingObjects`' movement bytes verbatim (2px falls, the delta-X pendulum,
the 104-termination). The one divergence is documented in code: the two `$09/$89`-seeded petals
overread the delta table into code bytes on cartridge; the port clamps to the max delta instead of
emulating raw memory.

**Frame-timing audit** is done (see [engine/timing.md](engine/timing.md)): pokered's overworld loop
ticks at **30 Hz** (two V-blanks per iteration) while battle/text `DelayFrames` are 1/60 s — the port
keeps its high render framerate but paces everything by the faithful domain. Fixed: NPC walk speed
(0.536 s/tile + the 4-phase step cycle and original wander delays), the ledge hop (0.536 s), boulder
slides, the sight `!` bubble (1.0 s), text speed (Gen-1 MEDIUM, 3 V-blanks/letter), and the battle
hit blink / decaying shakes / sway / lunge / slide frame counts. Player walk & bike were already
faithful.

**Fly / Surf / ship transitions** are in: **Fly** now fades through with the fly SFX
(`Cutscene.fly_transition`) instead of snapping; **Surf** glides onto the water (`Player.surf_hop`)
rather than teleporting; and the **S.S. Anne departure** fades out with the horn as it pulls away
(`ss_anne_departs`). Verified by `--flytest` / `--surftest` / `--ssannetest`.

**End credits** are the real roll now (gh #22, v0.9.29, faithful to engine/movie/credits.asm):
`build_credits` parses `data/credits` into `credits.json` — 35 pages of staff text, each line
keeping its **column-offset byte** (base col 9, `#`→`POKé`), plus per-page `fade`/`mon`/`copyright`
flags and the 15-entry `CreditsMons` order. `Cutscene.run_credits` draws the Gen-1 layout: black
**letterbox bars** over a white text band, left-aligned staff lines at their real columns, and at
each `*_MON` page a **Pokémon front sprite scrolls left across the band as a black silhouette**
(DisplayCreditsMon) — the transition between sections. The **© page** reuses the boot copyright
tiles and **THE END** is the real spaced letter graphic (`credits_the_end.png`). Tests run a fast
path (audio off). Verified by `--creditstest` (35 pages / 15 mon slides / 1 © page); posed by
`--creditshot` (text/mon/copyright/end in `build/preview/credits/`).

**Dark-cave palette swap** is in: dark maps (`DARK_MAPS`) render the Gen-1 dark palette — a uniform
full-screen darkening, **not** a spotlight (gh #127). Entering Rock Tunnel pokered sets
`wMapPalOffset = $06`, so `LoadGBPal` loads `FadePal2` (`BGP/OBP0 = 3,3,3,2`): the lightest of the
four DMG shades maps to shade 2, every darker shade to shade 3 (black). `shaders/cave_dark.gdshader`
on the `darkness` overlay remaps the rendered screen's shades to that palette; FLASH hides it entirely
(`_update_darkness`). Rendered by `--caveshot`.

**Town Map** is in: the extractor (`build_town_map`) composites the RLE tilemap + tile sheet into a
160×144 `town_map.png`, extracts the cursor, and emits `town_map.json` (the TownMapOrder cycle of
`{x, y, name}` + a map-label→index start table). `TownMap.gd` is the viewer (`Audio` tink + a
blinking cursor; UP/DOWN cycle locations, A/B close), opened from the bag's **TOWN MAP** — given by
Daisy in Blue's house once you hold the Pokédex (`Cutscene.daisy_town_map`). Verified by
`--townmaptest`; rendered by `--townmapshot`.

**Per-move attack SFX** are in: the extractor emits `move_sfx.json` (`build_move_sfx` from
`data/moves/sfx.asm`'s MoveSoundTable — `MOVE_CONST -> [sfx_key, pitch]`), and `Battle._do_move`
plays each move's sound (with its pitch modifier via `Audio.play_sfx(key, pitch)`) when the move is
used, before the effectiveness hit cue. Verified by `--sfxtest`.

**Wild encounters now key by map label** (`build_wild`): the extractor resolves `WildDataPointers`
positionally against the map-constant order, so shared tables map to every map that uses them — e.g.
the surf-only **SeaRoutes** Tentacool table now covers Route 19 + Route 20 (previously dropped). In
Red only Route 19/20/21 have water (surf) encounters; every other table is `def_water_wildmons 0`.

**Story scripting** (in progress): a cutscene runner (`Cutscene.gd`) with event flags, player/
rival identity, and starter tracking (saved/loaded); a GB-style **naming screen** (preset list +
keyboard, ornate frame); and **Oak's speech** on NEW GAME (Oak → flipped Nidorino → name yourself
→ name your rival → "your legend is about to unfold"). All boxes now use the shared `Frame.gd`
helper for the Gen-1 double-line border.

The **Pallet Town → Oak's Lab opening quest** is in (faithful to scripts/PalletTown.asm +
scripts/OaksLab.asm): the player wakes in their room at pokered's NewGameWarp; trying to leave
Pallet north without a POKéMON triggers **Oak's intercept** (he appears, walks up, "It's unsafe!",
leads you to the lab); the **lab entrance + choose-a-mon speech**; **picking a level-5 starter**
from the three balls; the **rival taking the counterpart** and the **first rival battle**
(OPP_RIVAL1, party by your pick), with party-heal + the rival walking out afterward. Built on
scripted movement: `Player`/`NPC.step()/face()`, a BFS `find_path()`, cutscene `walk()` helpers,
and event-driven object visibility (`NPC.set_shown` / `Main._object_shown`). Verified by
`--oaktest`.

The **Oak's Parcel errand** is in (faithful to scripts/ViridianMart.asm + scripts/OaksLab.asm +
scripts/ViridianCity.asm): entering **Viridian Mart** after getting a starter, the clerk calls you
to the counter and hands over **OAK's PARCEL** (`Main._on_map_loaded` → `Cutscene.viridian_mart_
parcel`); the road north out of **Viridian City** is blocked by the sleepy old man until you have
the POKéDEX (`viridian_oldman_block` at X==19,Y==9); **delivering** the parcel to Oak triggers the
**POKéDEX receipt** — the rival rushes back in, Oak gives you both the POKéDEX (the two desk-shelf
POKéDEX sprites disappear), and the rival leaves (`Cutscene.deliver_parcel` → `pokedex_receipt`,
fired from the Oak interaction). Events: `GOT_OAKS_PARCEL`, `OAK_GOT_PARCEL`, `GOT_POKEDEX`,
`RIVAL_GOT_POKEDEX`. Verified by `--parceltest`.

**Trainer line-of-sight** is in (faithful to `home/trainers.asm` + `engine/overworld/trainer_
sight.asm`): an undefeated trainer facing the player, lined up within its view range, engages on a
step — the `!` bubble pops, the trainer marches up, and battles with before/after dialogue. View
range + before/end/after-battle text are extracted from the script trainer headers into the map
JSON; the `!` bubble is the extracted `shock` emote. Defeat is keyed by the trainer's home cell.
See [engine/npcs.md](engine/npcs.md); verified by `--sighttest`.

**All eight gyms** are in (one `_GYM_LEADERS` data entry each): **Brock** (Boulder+TM34),
**Misty** (Cascade+TM11), **Lt. Surge** (Thunder+TM24), **Erika** (Rainbow+TM21), **Koga**
(Soul+TM06), **Sabrina** (Marsh+TM46), **Blaine** (Volcano+TM38), and **Giovanni** (Earth+TM27,
Viridian Gym party 3 — distinct from the Rocket Hideout Giovanni, which is special-cased). All
verified by `--gymtest`. The earlier per-gym mechanics: the gym's ordinary trainers engage via the
sight system; talking to the leader runs the pre-battle speech → battle → badge + TM on a win, with
a re-challenge line once beaten. Adding a leader is one `Cutscene._GYM_LEADERS` entry. Vermilion's
**trash-can switch puzzle** gates Surge (a runtime door via `Main.set_block`). Badges are tracked in
`Main.badges` (saved). See [engine/npcs.md](engine/npcs.md); verified by `--gymtest` / `--surgetest`.

**Battle SFX** are wired (engine-2 SFX bank now extracted too): per-action cues fire in sync with
their message via queue markers — the hit sting by type effectiveness, faint, level-up, ball
toss + caught, and run. See [engine/audio.md](engine/audio.md); verified by `--sfxtest`.

**Badge stat boosts** are in (`Battle._battle_stat`, faithful to `BadgeStatBoosts`): each badge
raises one of the player's in-battle stats by ×9/8 (BOULDER→Atk, CASCADE→Def, THUNDER→Spd,
SOUL→Spc). See [engine/battle.md](engine/battle.md); verified by `--badgetest`.

**Overworld item balls** are in: a `SPRITE_POKE_BALL` with an item-const arg is a pickup —
`build_items` extracts `items.json` (const → display name, TMs as `TMnn`), and facing + A adds it to
the bag, then the ball is gone for good (`Main.picked_items`, saved). See [engine/npcs.md](engine/npcs.md);
verified by `--itemtest`.

**Poké Marts** are in: a mart clerk opens BUY / SELL — `build_marts` extracts each mart's stock and
`build_items` the BCD prices (`item_prices.json`); a **quantity picker** (`Menu.open_qty`) handles
buying/selling N at once (capped by money / stock). See [engine/npcs.md](engine/npcs.md); verified
by `--marttest`.

**Pokémon storage PC** is in: the Pokémon Center PC opens WITHDRAW / DEPOSIT (`Main.pc_box`, saved)
with last-mon / full-party guards, so a full party no longer blocks catching. Verified by `--pctest`.

**HM field moves** are started with **Cut**: HMs teach a field move from the bag (compatibility from
the extracted `tmhm` list, HM not consumed), and facing a cuttable tree with a CUT-knowing mon + the
Cascade Badge swaps the tree block away (`Main.set_block`, faithful to `cut_tree_blocks.asm`). The
data tables cover Fly/Surf/Strength/Flash too; those (and obtaining HM01 on the S.S. Anne) are next.
See [engine/npcs.md](engine/npcs.md); verified by `--cuttest`.

**Hidden items** are in: facing their tile and pressing A yields the item (`Main.found_hidden`,
saved), no Itemfinder needed. Verified by `--hiddentest`.

**Usable bag items** are filled out: potions (incl. Super/Hyper/Max/Full Restore), status heals,
Revive, Rare Candy, plus field items **Repel** (suppresses wild encounters, `Main.repel_steps`,
saved) and **Escape Rope** (warp to the respawn map). Verified by `--itemusetest`.

**Cerulean rival battle** (the 2nd story rival fight) is in: crossing the north bridge
((20,6)/(21,6)) triggers the rival to appear, battle (OPP_RIVAL1, a tougher party by starter), and
leave with the hint to thank BILL (`Cutscene.cerulean_rival`). Verified by `--crivaltest`.

**S.S. Anne chain (in progress, full faithful):** **Bill's house** is done — talk to Bill-as-a-
POKéMON, agree to help, he enters the teleporter; run the **cell-separator PC** (separation jingle);
the real Bill steps out and gives the **S.S.TICKET** with the nudge to board the S.S. Anne
(`Cutscene.bill_intro`/`bill_separator`/`bill_ticket`, `_object_shown` toggles). Verified by
`--billtest`. **Boarding + captain done**: the Vermilion dock warp is gated on the S.S.TICKET
(sailor flashes you aboard, else "you need a TICKET"; `_do_warp` gate + `Cutscene.board_ss_anne`),
and the seasick **captain** in his cabin gives **HM01 (CUT)** after you rub his back
(`Cutscene.ss_anne_captain`). So Cut is now obtainable → teachable → cuts trees. The ship's maps,
trainers (sight), and item balls already work via the generic systems. The **2F deck rival battle**
(OPP_RIVAL2, party by starter, `Cutscene.ss_anne_rival`) and the **ship departing** when you step
off the ship after HM01 (`Cutscene.ss_anne_departs` → `SS_ANNE_LEFT`, a one-time area) are also in.
**The whole S.S. Anne chain is complete** — Bill → ticket → board → deck rival → captain's HM01 →
leave → ship sails. Verified by `--ssannetest`. The departure is the **real animation** (gh #22,
v0.9.28, faithful to VermilionDock.asm): MUSIC_SURFING + the horn, the ship band (the LY 80-127
raster window) sliding west 128 px at 1 px per 8 frames with white smoke puffs popping above the
smokestack every 16 px and drifting east, the erase to open water, the second horn, and the
scripted walk north off the dock — no dialogue, as on the cartridge. Posed by `--anneshot`.

**Legit-play bot (gh #76) — Rock Tunnel leg to Lavender:** the `rocktunnel` stage (Vermilion →
Cerulean → Route 9/10 → Rock Tunnel → Lavender) is in `_PT_STAGES_WIP`. The **Rock Tunnel 1F/B1F
ladder maze** is derived (`--rtprobe` connectivity probe) and **verified** end-to-end
(`--rocktunneltest --tunnel` → Lavender; no FLASH needed — cave darkness is a render-only overlay).
Entering Route 9 from Cerulean drops you in a small grassy pocket gated eastward by a **CUT tree**
(block 0x35 at (5,8) — the same Cut gate as the Vermilion Gym); the bot cuts it with the HM01 mon
earned in the `ssanne` stage (`_pt_cut_route9_tree`). The **`erika` stage** crosses Lavender → Route 8 →
the Route 7-8 Underground Path → Route 7 → Celadon (bypassing the drink-gated Saffron gates), catches a
**Growlithe** on Route 7 (Fire — resists Erika's grass, hits it 2×, the coverage answer like Diglett
vs Surge), cuts the tree gating the gym plaza (block 0x32 at (35,32)) **and** the tree gating Erika's
platform *inside* the gym, and beats **Erika** for the RAINBOWBADGE (`--erikastage` PASS end-to-end,
with the persistent-player whiteout-retry). This surfaced + fixed a real **engine bug**: the cut
mechanic dropped the GYM-tileset cut tree (tile 0x50) + half of pokered's `CutTreeBlockSwaps` — the
Celadon Gym was unbeatable on foot for the human playthrough too. Now `_try_cut` handles OVERWORLD
(0x3D) + GYM (0x50) with the full block-swap table. The **`silphscope` stage** (Celadon Game Corner
poster → Rocket Hideout → Giovanni → SILPH SCOPE) is **complete** (`--silphscopetest` PASS from Celadon,
now including the poster leg it used to skip — see gh #89 below): the bot beats the ROCKET standing on
the poster's stand cell, then the full **B1F→B4F descent** works on foot via **spin-aware pathfinding**
(`_pt_plan`/`_pt_walk_dungeon` model a step onto an arrow as landing on its stop tile; verified
`--spinnavtest`/`--silphdescent` across the B2F/B3F arrow mazes). This surfaced + fixed a second bug:
the **spinner tile coords were transposed** in `build_spinners` (`map_coord_movement` is (x,y), read
as (y,x)) — the spin mazes (Rocket Hideout, Viridian Gym) were never walkable on foot. **B4F is two
disconnected regions**: the B3F stairs land in the west wing (Rocket 3 + the LIFT KEY); Giovanni, the
SILPH SCOPE, his two door grunts and the elevator are all in the east one. The only crossing is the
**LIFT-KEY elevator**, boarded from **B2F** (B1F's elevator door sits behind its own guard door), so
the leg is: take the key, climb out, ride back down (`_pt_hideout_lift_key`/`_pt_hideout_ride_to_b4f`).
The door grunts have **view range 0** — walking past never engages them — so the bot talks them into
their fights (`_pt_talk_npc`/`_pt_fight_trainer`).

The **`pokeflute` stage** follows it (`--pokeflutetest [--tower]` PASS from Celadon): back east through
the Route 7-8 Underground Path to Lavender (`_pt_celadon_to_lavender`, the mirror of the `erika`
crossing), then up the **Pokémon Tower** — the 2F rival ambush and 6F's MAROWAK are *coordinate*
triggers rather than doors, and both sit on cells you cannot walk around ((15,5) is the only link
between 2F's halves; (10,16) is the only cell leading to the 7F stairs) — past the three Rockets holding
**MR.FUJI** on 7F, who sends you home for the **POKé FLUTE**. This taught the navigator one new trick:
**an item ball is a solid sprite, so a ball left in a corridor is a door whose key is the item**. Tower
6F's **RARE CANDY (6,8)** sits on the single-tile passage into the entire southern half of the floor
(verified: our blocks match pokered's `.blk` byte-for-byte, and `object_event 6, 8, SPRITE_POKE_BALL`),
so a real player *must* take it to reach 7F. `_pt_walk_dungeon` now clears a blocking ball the same way
it clears a blocking guard (`_pt_take_blocking_item`), and when it truly gives up it names the objects in
the way (`_pt_report_blocked`) instead of just printing a cell — see [decisions.md](decisions.md) ADR-012
for why the bot clears obstacles *by kind* rather than proving which one is the articulation point. The
climb runs under the persistent-player whiteout-retry, like Erika's.

The **`snorlax` stage** spends that flute (`--snorlaxstage` PASS): Lavender → Route 12 → wake and beat
the **SNORLAX** asleep across the road (10,62) → Routes 13/14/15 → **Fuchsia**, the next gym town. Two
new navigation facts came out of it, both of which bite a human the same way:
- **A gate house can be the road.** Route 12's north wall and Route 15's midpoint are sealed; the only
  way past is *through* the building, in one door and out the other. Both doors are `LAST_MAP`, so
  `_pt_warp_out`'s "first matching warp" walks straight back out the way it came — `_pt_warp_via` steps
  onto one **specific** warp cell instead.
- **Not every row of a map connection leads anywhere.** Route 13's west edge lines up with Route 14's
  **row-6 pocket**: a one-tile corridor with a BIRD KEEPER standing in it who faces *down*, so his sight
  line never touches you and he never steps aside. Walk straight across and you can only back out.
  `_pt_cross(dir, budget, prefer)` now names the row to leave by. `--rtprobe` gained a matching report —
  for each edge it lists the cells that are actually **crossable** (the cell beyond, on the neighbour,
  is walkable) and which of those the flood reached, which is what distinguishes "I reached the edge"
  from "I can leave by it".

The **`koga` stage** takes the fifth badge (`--kogastage` PASS): Fuchsia Gym's *invisible walls* turn out
to be ordinary collision, so the guard-aware walk threads the maze, clears its six sight-trainers, and
beats **KOGA** at (4,10) for the **SOULBADGE** (+ TM06) — the badge that lets SURF be used outside battle.
Walking to a named door now sets `avoid_warps`, since Fuchsia's doors share a row and a plain walk to the
gym trips the Pokémon Center's first. (`--gymtest` teleports to each leader, so it never exercised gym
navigation on foot; this is the first time Koga's maze has been walked.)

The **`safari` stage** buys both remaining field HMs (`--safaristage` PASS): pay the ¥500, wind through
the park to the **SECRET HOUSE** for **HM03 (SURF)**, take the **GOLD TEETH** (West, 19,7), and trade them
to the **WARDEN** for **HM04 (STRENGTH)**; both are then taught. Three things it settled:
- **The park's areas are a loop, not a hub** (`--rtprobe`). From the Center's entrance only the **East**
  door is reachable; East reaches North, North reaches West. The Center's *own* west door opens into a
  126-cell pocket that leads nowhere but back into West — so the way out is to retrace, not to take the
  nearest door.
- **Encounters inside the park are BALL/BAIT/ROCK/RUN**, so the battle policy runs rather than fighting
  (a safari mon never holds you — `TryRunningFromBattle`). Running out of the park's 500 steps only costs
  another ¥500, and every leg is guarded on what's already held, so a cut-short trip resumes.
- **Only the Squirtle line can carry SURF here.** Charizard learns CUT and STRENGTH but not SURF or FLY
  in Gen 1, and the run's starter is SQUIRTLE (`_pt_stage_opening`) — so Blastoise takes both HMs.
  `_pt_teach_cut` generalised into `_pt_teach_hm(hm, move)`.

The **`saffron` stage** walks back north and through the drink gate (`--saffronstage` PASS; `--drink` runs
just the Celadon half): Fuchsia → Route 15's gate → Routes 14/13 climbed north (leaving Route 14 by row 8)
→ Route 12's gate → Lavender → the Underground Path → **Celadon**, five flights up the Mart to the
**rooftop vending machines** for a drink, then east to **Route 7's gate**, whose thirsty guard takes it —
one drink opens all four — and out into **Saffron**. Route 7's east edge is walled but for that gate house,
and both its doors are `LAST_MAP`, so the east one drops you back onto Route 7 *past* the wall. The vending
machine reopens itself for another can (`_vending_buy`), so the bot has to cancel out of it; otherwise the
modal never clears and every later walk stalls waiting on it.

The **`silph` stage** liberates Silph Co and opens Saffron Gym (`--silphstage` PASS; `--card` runs just the
key leg). Silph Co is a **teleport-pad maze**, not an elevator ride: the lift serves every floor without a
key (`SilphCoElevatorFloors`) and reaches **neither** place that matters. The route was derived on the real
collision + object data with every trainer treated as a permanent wall — a beaten one stays where it
stopped, so it never frees the cell it was blocking — which means the leg needs no luck:
- The **CARD KEY** (5F, ball at 21,16) sits in a row-16 corridor whose west door is held by a **range-1**
  ROCKET (8,16) — sight 1 means he never marches, so he is a wall forever — and whose east end is the
  one-wide column 28, with another ROCKET at (28,4) plugging it. You cannot walk in from either side. The
  way in is to **arrive**: ride to **9F**, take its pad at (17,15), and it drops you on **5F (9,15)**,
  *inside* the corridor. A warp you land on is inert until you leave it, so you step south off it, walk
  east to (20,16), and face the ball. Stepping back north onto (9,15) — armed again — returns you to 9F.
- **11F's elevator landing (13,0) does not reach GIOVANNI.** It reaches 52 cells: the top corridor and
  the 10F stairs (9,0). Giovanni (6,9) is behind the floor's one card-key door, block **(3,6)** (locked
  `0x20`, open `0x3`), whose wall cells are (6,13)/(7,13) — face it from (6,14).
- The only way into that half is the pad **`7F (5,7) → 11F (3,2)`**, and **7F's pad room is sealed off
  from the rest of 7F** (its walls hold no door). You land in it from **3F's pad (11,11)**, which is
  itself behind 3F's card-key door, block (8,4). Crossing the room trips the **rival ambush** at (3,3),
  exactly as `SilphCo7F.asm` intends.

So the route is: 1F → lift **9F** → pad → 5F **CARD KEY** → pad back → lift **3F** → open (8,4) → pad →
**7F** → pad → **11F** → open (3,6) → **GIOVANNI**. Each floor's door table lives in its adapter, and
`_pt_walk_dungeon` opens the doors itself once the key is in the bag — the **third obstacle kind**
alongside guards and item balls (ADR-012). A door is a *block*, not a sprite, and **which of its four
cells is the wall differs per floor** (`facility` `0x54` walls its top pair, `0x5F` its right pair;
`interior` `0x20` its bottom pair), so the bot looks it up rather than assuming.

That leg surfaced **two more engine bugs**, both of which a human would have hit — and one of them was a
hard softlock on the critical path:
- **Silph Co could not be entered on foot** (gh #79, fixed). Its Saffron door (18,21) has exactly one
  approach cell, (18,22), and `SAFFRONCITY_ROCKET8` stands on it. pokered clears him on the **Pokémon
  Tower rescue** — `PokemonTower7FMrFujiText` hides ROCKET8 and shows the sleeping ROCKET9 one cell east
  — not on Giovanni. The port ran neither toggle and kept every Rocket until `BEAT_SILPH_CO_GIOVANNI`,
  who is *inside*. Saffron Gym is gated the same way (ROCKET3 stands on (34,4), its doorway), so
  everything from Sabrina onward was walled off. `--silphtest` warps straight in, so it never surfaced.
- **The Rocket Hideout could not be reached on foot** (gh #89, fixed). `bg_event 9, 4` is the Game Corner
  poster — a **wall tile** whose only walkable neighbour is (9,5) — and `object_event 9, 5, SPRITE_ROCKET,
  STAY, UP, …, OPP_ROCKET, 7` stands on it, facing the poster, so he never engages on sight and must be
  talked to. `toggleable_objects.asm` ships him ON; `GameCornerRocketBattleScript` walks him off and
  `GameCornerRocketExitScript` hides him, both only after his battle. The port's `GameCorner.gd` modelled
  the poster switch, the hidden staircase, the slots and the coin clerks — and nothing about him — so
  `EVENT_FOUND_ROCKET_HIDEOUT` was unsettable and the SILPH SCOPE, the Pokémon Tower and everything past
  them were sealed. Fixed through the existing `object_shown` / `on_battle_end` hooks. `--silphscopetest`
  never saw it because it **pre-set `FOUND_ROCKET_HIDEOUT`**: the gh #84 pattern one level up — a setup
  line that hands a stage its own goal state makes every assertion after it vacuous. Found by the first
  continuous seeded run to ever walk this leg.
- **Cerulean Cave was sealed forever** (gh #90, fixed). `CERULEANCITY_SUPER_NERD3` STAYs on (4,12), the
  only land cell touching the cave door at (4,11) (you SURF up to him). `HallOfFame.asm` hides him
  (`HideObject TOGGLE_CERULEAN_CAVE_GUY`) once you are recorded as CHAMPION; the port never did, so MEWTWO
  was unreachable. One clause in `CeruleanCity.gd`, keyed on the `HALL_OF_FAME` event the ceremony already
  sets. **`tools/audit_chokepoints.py`** makes that whole family a permanent check, the way
  `tools/audit_places.py` did for `place()`: for every warp, sign and item ball on every map it reports
  when *all* the walkable cells adjacent to it are occupied by a solid sprite, and separately when a
  sprite is a cut vertex sealing off a whole region. It re-derives gh #79 and gh #89 from scratch and
  found gh #90; reviewed hits (Mt. Moon's fossils, both SNORLAX, the Victory Road boulders, the Warden's
  boulder, Silph 5F's CARD KEY corridor) are silenced by name with a reason, so it exits 0 and can gate.
- **Warps fire on any step** (gh #80, **FIXED** — landed with #105 on `feature/gh105-tile-pair-collisions`).
  `_warp_should_fire` mirrors `CheckWarpsNoCollision`: warp immediately only on a tileset door/warp tile
  (`IsPlayerStandingOnDoorTileOrWarpTile`, ported from `{warp,door}_tile_ids.asm`), else require
  `ExtraWarpCheck` (fn1 facing the map edge / fn2 warp-tile-in-front per map/tileset). So Silph 11F's plain
  `(5,5)` mat no longer ejects you (the president + MASTER BALL are reachable on foot), and a Center mat you
  arrive on doesn't bounce you. fn2 at a map edge reads the **border block** (`_feet_tile_or_border`), which
  is how the S.S. Anne / cabin / Vermilion Dock edge-exits fire; horizontal gate houses and the Silph
  elevator fire from the door-facing cell, and the bot turns to that facing on arrival. Full chained gate
  re-verify (NEW GAME → HALL OF FAME, seed 1) stayed green.
- **Tile-pair (elevation) collisions** (gh #105, #128, **FIXED**). `_tile_pair_blocked`
  (`CheckForTilePairCollisions`, `data/tilesets/pair_collision_tile_ids.asm`) blocks a step between two
  walkable cells at different elevations (cavern floor↔ledge, water↔shore surfing); boulder pushes get
  pokered's own push check (`CheckForCollisionWhenPushingBoulder`, player-tile↔destination + stairs). Caves
  fracture into ladder-linked pockets; the bot's dungeon routes were re-derived (Victory Road became a real
  multi-floor boulder/switch/hole puzzle solved by `tools/vrdyn.py`). See
  [engine/collision.md](engine/collision.md) and `docs/notes/gh105-victory-road.md`.

The **`sabrina` stage** takes the sixth badge (`--sabrinastage` PASS; `--pads` runs just the pad chain).
Saffron Gym is nine sealed rooms in a 3×3 grid, and its **entire warp table is 30 self-warps**
(`data/maps/objects/SaffronGym.asm`) — the only way between rooms is a teleport pad. Its door is clear
only once GIOVANNI has fallen (`SAFFRONCITY_ROCKET3` stands on (34,4)), so `silph` gates it. SABRINA has
**view range 0**, so she is talked to, not walked into. Derived on the real pad graph with every trainer
a permanent wall: from the door at (8,17), the pads `(11,15) → (15,15) → (15,5) → (1,5)` land on
**(11,11)**, the one pad inside her room. `_pt_take_pad` reads each landing off the map's own warp table
rather than a second copy, and steps onto the pad from a neighbouring cell — a pad warps *within* the
map, so no map change fires to signal arrival.

**Next up — the sea, and `blaine`.** The bot can now **SURF**: `_pt_use_field_move` drives the real party
field-move submenu (so the badge gate and the "It can't be used here." refusal run for real),
`_pt_surf_on` mounts from a shore cell, and `--surfnavtest` PASSes Fuchsia → Route 19 → **across the
connection into Route 20, still afloat**. Two facts fell out while deriving it:
- **Route 20's sea is split in two.** Walls at column 43 (rows 2–13) and column 62 (rows 10–16) fence the
  Seafoam Islands landmass across the middle, and the halves share no water (our `.blk` is byte-identical
  to pokered's). The only crossing is the islands' two Route-20 doors — and on **Seafoam 1F those doors
  sit in disconnected regions**, so it descends into B1F. Seafoam is on the road to Cinnabar, not beside it.
- **The open-water approach is Pallet Town → Route 21**, a single water component end to end. That is the
  `blaine` route, and it is **walked**: `_pt_fly_to` drives the two menus FLY needs (party submenu → the
  `visited_fly` town list), and `_pt_reach_cinnabar` flies home, mounts Pallet's beach at (4,13), and
  swims Route 21's 90 cells to Cinnabar's north shore (`--cinnabarnavtest` PASS).

**The SECRET KEY is walked (gh #85, fixed).** `--secretkeytest` PASSes: from Cinnabar's street, in the
front door, 1F → 2F → 3F, flip 3F's panel, **fall through the western balcony** into 1F's sealed south,
down to B1F, flip its south panel then its north one, take the key, and out by the back door. The route
was derived on the real collision + warp + **hole** graph with the switch state carried through, and the
panels turn out **not to be interchangeable** — B1F's north one seals B1F's own staircase, so the walk out
is not the walk in (`_pt_mansion_flip_for` presses a panel, looks, and presses it back if it did not
help).

The **`blaine` stage** then takes the seventh badge (`--blainestage` PASS; `--gym` skips the mansion).
Cinnabar Gym is six rooms that snake back on themselves, each sealed by a **quiz gate** — the machines are
`hidden_events.asm` wall panels, pressed from below facing UP. A right answer opens that room's gate for
good; a wrong one and the room's trainer jumps you. Because the rooms snake, the order is forced: the only
machine you can reach is the next one. The bot answers off the same `HIDDEN_EVENTS` row the engine reads,
as a player with a guide would, and `_pt_answer_quiz` wins the fight anyway if an answer ever misses.

Two bugs sat between the bot and the VOLCANOBADGE:
- The Pokémon Mansion's switches were **unpressable** (gh #83, fixed). Each is a **wall panel**, keyed off
  the *faced* tile per `hidden_events.asm`'s `SPRITE_FACING_UP`, but all four adapters tested the player's
  own cell — and every switch cell is solid. `--mansiontest` teleported the player *inside the wall* to
  press them, so it passed.
- **Hole tiles were not implemented at all** (gh #85, fixed). Gen 1 drops you a floor when you step on a
  hole — a **dungeon warp**. They are *not* found by scanning tiles: each map's script carries an explicit
  coord list and picks the destination floor from the matched index (`PokemonMansion3FDefaultScript`'s
  `.holeCoords` + `IsPlayerOnDungeonWarp`), with the landing cell in `DungeonWarpData`
  (`data/maps/special_warps.asm`). 3F's **western balcony drops to 1F (16,14)**, and that is the *only*
  entrance to 1F's southern half, which holds the Scientist, the CARBOS and the **stairs down to B1F**.
  Verified in-engine before the fix: with the switch OFF *and* with it ON, the flood from the front door
  never reached (21,23). So the SECRET KEY was unobtainable, the Cinnabar Gym door never unlocked, and
  BLAINE's badge could not be won. Now: `Cutscene.fall_down_hole` + a `dungeon_hole` adapter helper, wired
  on `PokemonMansion3F.on_step`; verified by `--holetest` (both drops, plus "a non-hole burnt tile does
  nothing"). **Still to wire:** `DungeonWarpList` also covers Seafoam Islands B1F–B4F — the port has
  those only as the boulder-drop special case, never as something the *player* falls through. (Victory
  Road 3F's hole is wired now — see the `victoryroad` stage below.)

`--rtprobe` gained **`--event NAME`**, which sets a story event before the map loads, so a floor whose
`on_enter` lays blocks from an event (a mansion switch, a Silph card-key door) can be probed in both
states. That is what settled the question above.

And it surfaced the worst engine bug so far:
- **Surfing across a map connection was impossible** (gh #82, fixed). `_is_water` only consulted the
  **center** map — `_tile_at` returns `-1` off it — while `_cell_walkable` resolves a neighbour's
  collision, where water is solid. So the sea ended at every map edge. `load_world` also cleared
  `surfing` unconditionally, though it runs on a connection rebase too. **Cinnabar Island has no dry
  connection**, so BLAINE's badge, the Pokémon Mansion, the SECRET KEY and the fossil lab were all
  unreachable — a critical-path softlock. `--surftest` mounts and dismounts inside one map and
  `--seafoamtest` moves by warp, so nothing had ever surfed across a connection.

The **`giovanni` stage** takes the eighth badge (`--giovannistage` PASS). Viridian Gym is badge-locked:
`ViridianCityCheckGymOpenScript` keeps the door shut until you hold every *other* badge, then
`VIRIDIAN_GYM_OPEN` latches for good — the port had no check at all, so the EARTHBADGE could be taken
before Brock (gh #86, fixed). The turn-away is a **simulated PAD_DOWN**, and the tile below the door
step is a **down-ledge**, so the refusal hops you back onto the street — `MapScripts.step_back_down`
now reproduces that idiom (Route 23's checkpoints use it too). Inside, the gym is a spin-tile maze
(`spin_aware`), and GIOVANNI has view range 0 — talked to, not walked into.

The **`victoryroad` stage** climbs to the League (`--victoryroadtest [--r23|--cave]` PASS end-to-end).
Route 23 is a river with a footpath at each end — walk, SURF the middle 32 rows, walk — and its only
door is **Route22Gate**, which surfaced its own softlock (gh #87, fixed): it is the one gate house in
Kanto entered from two *different* maps, and all four of its doors are `LAST_MAP` warps, so pokered
re-picks `wLastMap` by which half of the building you stand in (`wYCoord < 4` → ROUTE_23). The port
had no such rule — both doors led back where you came from, and Route 23, Victory Road, and the whole
League were unreachable on foot. Victory Road itself is a figure-of-eight: 2F's ladder lands you in a
sealed 71-cell west pocket whose only exit is the door its switch1 opens (the lone boulder in the
pocket is the answer — `_pt_push_boulder`, the **fourth obstacle kind** after guards, item balls and
card-key doors, but *aimed* rather than merely cleared); 2F's exit pair sits in a 13-cell pocket
reachable only from **3F's east pocket**, itself reachable only from 2F's (25,14) ladder
(`_pt_take_ladder` pins each leg to its intended landing — four ladders per floor means "the map
changed" is not "arrived"). Faithfulness that landed with it: **Route 23 re-arms the boulder puzzle**
on entry (`Route23SetVictoryRoadBoulders` — switches cleared, 3F's boulder restored, 2F's hidden
again), 2F clears 1F's switch on load, **3F's hole** now drops the *player* to 2F (22,16) — the
`cavern $22` dungeon warp, previously boulder-only — and a boulder shoved into it vanishes and
reappears on 2F one row below (the toggleable-boulder pair).

The **`elite4` stage** ends the run (`--elite4stage [--gauntlet]` PASS): lobby → LORELEI → BRUNO →
AGATHA → LANCE → the CHAMPION → the **HALL OF FAME**. The gauntlet rule is real, not a mood:
`IndigoPlateauLobby_Script` wipes the whole Indigo Plateau event range the moment you walk back down
mid-challenge (`BIT_STARTED_ELITE_4`, armed when Lorelei's room loads), so all four stand back up —
the bot heals and shops *once* on the way in, runs the five fights without leaving, and on a whiteout
restarts from LORELEI as a player would. It also surfaced the port's last walled-off softlock
(gh #88, fixed): **Lance's room ships its entrance doorway closed** in the static `.blk` —
`LanceShowOrHideEntranceBlocks` opens it on every load until `EVENT_LANCES_ROOM_LOCK_DOOR` latches
(stepping into the hall slams it behind you) — so LANCE, the CHAMPION and the HALL OF FAME were
unreachable on foot; `--elitetest` never saw it because it `place()`s beside each opponent (the
gh #84 pattern again). Two more walk-arounds closed with it: LANCE engages by **coordinate** (view
range 0 — (5,1)/(6,2) start the fight), and beating AGATHA arms `SCRIPT_CHAMPIONSROOM_PLAYER_ENTERS`,
so the Champion's room now marches you into the final battle as you enter — without those, both could
simply be walked past to the stairs.

**Stage seams are their own bug class (gh #76).** A stage verified in isolation proves nothing about the
seam from the *previous* stage's checkpoint end-state: the isolated tests start the bot outdoors, but a
real stage ends wherever its last milestone happened — usually inside a gym, behind a CUT tree the next
map load regrows. Five seams broke this way and are fixed. `surge` and `erika` end inside their gyms, so
the plaza trees now cut from either side; the `erika` checkpoint puts the bot on Erika's platform behind
the gym's *interior* tree at (5,7), a 16-cell pocket holding no door at all; `sabrina` ends in her
pad-sealed room, so `blaine` rides the derived exit chain out (pads are **directed** — the way out is not
the way in reversed); and `giovanni` ends on Viridian Gym's arrow floor, so `_pt_warp_out` now always
plans spin-aware. **Cerulean City is cut in two by a one-way ledge:** the gym side — Pokécenter, mart,
gym door, the Route 4 and Route 24 edges — is *entered* over the down-ledges at (32..34,18) and can never
be left that way, and it reaches neither Route 5 nor Route 9. A Rock Tunnel whiteout respawns in that
Pokécenter, so the retry has to cross back through the Rocket-trashed house (27,11 → the back-wall hole →
27,9) exactly as a player would. `--surgenavtest --route9` drives that recovery off a real `whiteout()`,
with no `place()` past the geometry.

**Everything the isolated tests were quietly handing the stages (gh #91, #92, #94, #95).** The continuous
run is the only thing that has ever held the real state, and it found six softlocks in a row that way — a
`place()` past the geometry (gh #84), a pre-set event (gh #89), a hand-made bag (gh #91), a Blastoise with
a spare move slot (gh #92), a hand-made team and wallet (gh #94), and a party that already knew FLY
(gh #95). Concretely: pokered's bag holds **20 distinct items** and a 21st ball is refused on the floor, so
the hoarding bot never got the GOLD TEETH; the only mon in its party that can carry SURF or STRENGTH is a
Blastoise whose four slots are full by L40, so `_pt_teach_hm` has to drive the real LearnMove forget prompt;
**nothing ever went for HM02**, whose Route 16 house is walled off behind a single **CUT tree at (34,9)**
(the fence is solid, the gate house's two passages are disconnected inside, and the SNORLAX and BICYCLE are
both red herrings); and the bot routes *around* trainers, so it arrives at Silph Co at L41 and at Route 22's
**second rival ambush** — six mons, a L53 Venusaur, armed by the eighth badge — at L53, and loses both. It
now grinds on Route 7 and on **Route 18** (418 exp a fight; most route grass turns out to be fenced off from
its own entrance, Route 15's included), never switches a L19 bench mon into a L40 leader, and buys HYPER
POTIONs rather than 50-HP SUPER POTIONs for a lead with 205 HP.

**The headless gate could never have passed (gh #99 #103).** `Cutscene.ss_anne_departs` sets
`cutscene_active = true`, then awaits `RenderingServer.frame_post_draw` so it can screen-grab the strip of
water it sails the ship across. Under `--headless` nothing draws, that signal is never emitted, and the
coroutine **suspends forever** — the ship never leaves, the gangway steps and the warp into Vermilion never
run, and the player stands on the dock at (14,2). Nothing is printed: a suspended coroutine is not a crash,
so there is no `SCRIPT ERROR` to grep for. This is the long-standing "S.S. Anne dock strand", blamed twice
on other things (gh #96, then RNG) because every `--from=ssanne` replay that *passed* was run windowed
through `tools/run.ps1`. **The ADR-011 Stage-1 gate is headless by definition**, so no continuous run has
ever got past `ssanne`. `tools/audit_headless.py` now forbids the pattern outside the `*test`/`*shot`
debug drivers, and is verified red on the offending commit. The general lesson, and it is not confined to
this project: *an `await` on a signal the main loop never emits is an invisible softlock*, and the
absence of an error message is not evidence of health.

**Two bugs in the bot's own walking verbs (gh #99), both hidden by a retry loop.** `_pt_step` budgets its
waits in *frames*, at counts written for a 60 fps game — but `_playthrough` runs at `Engine.max_fps = 500`,
where the 0.08 s turn-in-place tween takes exactly the 40 frames the turn budget allowed, so the key was
released mid-turn and the step never happened. And `_pt_walk_to` returned `true` on `player.cell == goal`
*above* its `if modal == battle` branch, so a step that lands on the goal returns with a wild battle still
on screen. Neither is visible through `_pt_walk_to`, which has a stuck-counter and simply retries.
`_pt_cross` takes exactly **one** step to cross a map edge — no retry, no diagnostic — so whether a
crossing worked came down to which way the walk's last step happened to face, and whether the edge cell's
grass rolled an encounter. Route 1's south edge is grass, and the first two NEW GAME runs died on it two
stages in. The budgets scale with the frame rate now, `_pt_settle()` clears the screen before a crossing,
and `_pt_cross` retries and *reports*. The lesson generalises past the bot: **a `--from=<stage>` replay
that passes where the continuous run failed has exonerated nothing** — it rolled the encounter elsewhere.

The `sabrina` leg surfaced a third bug, this one cosmetic but glaring:
- **Mr. Mime had no sprite** (gh #81, fixed). He is SABRINA's second Pokémon (`SabrinaData`), so the
  sixth gym leader has always sent out an invisible mon. pokered stores his artwork as `mr.mime.png` /
  `mr.mimeb.png` — the only files under `gfx/pokemon/` that aren't a bare species key — and
  `build_battle()`'s `if f.exists()` guard turned the mismatch into a **silent skip**, shipping 150 of
  151 sprites. The extractor now maps the name and **raises** if any species lacks a front or back
  sprite. `--gymtest` fights Sabrina and still passed, because a null texture is only a *draw* error:
  Godot logs it every frame and runs on.

An earlier leg surfaced **two more engine bugs**, both of which a human would have hit:
- **Script-placed doors didn't reopen until you left and came back.** pokered's `EndTrainerBattle`
  (`home/trainers.asm`) sets `BIT_CUR_MAP_LOADED_1`, re-running the map's load callback the instant a
  trainer battle ends. The port only ran `on_enter` on map load, so the Rocket Hideout B1F/B4F guard
  doors and the **Lorelei/Bruno/Agatha exit seals** stayed shut after their guard fell — and those E4
  rooms have no other exit, so it read as a softlock. Fixed with an eighth map-script hook,
  `on_battle_end()` (see [engine/map-scripts.md](engine/map-scripts.md)); verified by `--rockettest`
  / `--e4test`.
- **The B4F LIFT KEY and SILPH SCOPE balls were visible from the start.** `toggleable_objects.asm`
  ships both **OFF**: the LIFT KEY appears only when the beaten Rocket 3 admits he dropped it
  (`ROCKET_DROPPED_LIFT_KEY` → `ShowObject`), the SILPH SCOPE only when Giovanni steps aside. The port
  showed both on load, so either could be pocketed without the fight that gates it. Fixed in
  `RocketHideoutB4F.gd` + `Cutscene.giovanni_hideout`, with `show_object`/`hide_object` added to the
  adapter vocabulary; verified by `--rockettest`.

**Pokédex tracking** is in: enemies are marked *seen* when they appear in battle, and the party +
PC box fold into *owned* (`Main.pokedex_seen`/`pokedex_owned`, saved); the POKéDEX start-menu entry
shows a **scrolling list** of all 151 in dex order (name once seen, `*` once owned, `----` unseen;
`build_dex` → `dex_order.json`). Verified by `--dextest`.

The reusable cursor **menu now scrolls** (`Menu.MAX_VISIBLE` window with ^/v arrows), so long lists
— bag, mart, PC box, party, the dex — no longer overflow the screen. Verified by `--scrolltest`.

The start-menu name entry now shows a **trainer card** (`Main._trainer_card`: name, money, badge
count, Pokédex tally) — the one place gym badges surface to the player.

**The Day Care** is in: the Route 5 Day-Care man takes a party mon (`Cutscene.daycare_man` →
`Main._daycare_deposit`); it earns 1 EXP per overworld step, and withdrawal recomputes its level/stats
from EXP and charges `(levels_grown + 1) × ¥100` (`level_for_exp`). Saved. (The Gen-1 daycare
move-learning quirk is intentionally omitted.) Verified by `--daycaretest`.

**TM teaching** is in: selecting a TM in the bag teaches its move (`Main.tm_moves`, the
ordered `add_tm` map from `extract.py`) to a compatible party mon — `tmhm`-checked like HMs, but
**single-use** (the TM is consumed). The gym TMs (TM34/TM11/TM24/TM21) are now usable.
Verified by `--tmtest`.

**Game Corner slots** are in: the Celadon Game Corner slot machines (`Main.SLOT_SEATS`; three seats
are out of order / out to lunch / someone's keys) run a faithful minigame (`SlotMachine.gd`) — bet
1-3 coins for 1/3/5 paylines, stop three reels with A, win on a line of matching symbols
(7=300, BAR=100, cherry=8, Pokémon=15). Each spin is rigged before it runs (SlotMachine_SetFlags:
mostly no-win, sometimes a normal match, rarely a 7/BAR jackpot), and the third reel rolls to the
rigged outcome. Coins (`player_coins`, capped 9999, saved) come from the coin clerk (50 for ¥1000),
the fishing guru (10 once), and wins; the COIN CASE is from the Celadon Diner gambler. Verified by
`--slottest`; rendered by `--slotshot`.

**Game Corner prize room** is in: the three prize counters (`GameCornerPrizeRoom`, bg_events at
(2,2)/(4,2)/(6,2)) exchange coins for the RED prizes (`Cutscene._PRIZES` from data/events/prizes.asm
+ prize_mon_levels.asm) — two Pokémon counters (ABRA/CLEFAIRY/NIDORINA, DRATINI/SCYTHER/PORYGON at
their fixed levels) and a TM counter (DRAGON RAGE/HYPER BEAM/SUBSTITUTE). Prizes overflow to the box
when the party is full; broke buyers are refused (`Cutscene.prize_vendor`/`give_prize`). Verified by
`--prizetest`.

**Saffron drink-gate** is in: the four Saffron gate buildings (Route5/6/7/8 Gate, which the routes'
walled edges force you through) have a thirsty guard at fixed coords (`Main.SAFFRON_GATES`) who
blocks + pushes you back until handed a Celadon drink (FRESH WATER / SODA POP / LEMONADE); one drink
sets `GAVE_SAFFRON_GUARDS_DRINK` and opens all four (`_saffron_guard`). Verified by `--saffrontest`.

**Safari Zone** is in: the gate (`Cutscene.safari_gate`, gating the `SAFARI_ZONE_CENTER` warp) charges
¥500 for **30 SAFARI BALLs + a 500-step game** (`in_safari`/`safari_balls`/`safari_steps`, saved);
encounters become a dedicated **BALL/BAIT/ROCK/RUN** battle (`Battle.start_safari` — bait halves the
catch rate & reduces flee, rock doubles it & raises flee, the mon may run, no fighting). The menu is
the faithful `SAFARI_BATTLE_MENU_TEMPLATE` (gh #169): **one full-width box** (0,12..19,17) reading
`BALL×nn     BAIT` / `THROW ROCK  RUN` with the ball count printed *inside the menu* at tile (7,14)
(core.asm `.safariLeftColumn`), cursor columns x=1/x=13 — no separate on-screen counter; the step
counter ticks down (`_on_player_moved`) and time-out ends the game (`Cutscene.safari_game_over`).
Time-out is a *sequence*, not a teleport (gh #171): `SafariZoneGameOver` rings the PA jingle and reads
the announcement out, and only then sets `wSafariZoneGameOver` — the flag that makes `OverworldLoop`
take `WarpFound2` — so the eject is the closing beat. "Time's up!" is skipped when no BALLs remain.
Running out of BALLs ends the game too (gh #180): the last BALL ends the encounter on the spot
(`.outOfSafariBallsText`), and the same ceremony fires the moment you're back on the overworld
(`SafariZoneCheck`, farcalled every `OverworldLoop` iteration).
At the gate, `SafariZoneGateLeavingSafariScript` lands you at the park-side door facing down, the
worker signs you out, your BALLs go back, and you're walked 3 south.
Verified by `--safaritest` + `--safaribattletest`.

**Silph Co** is in: the **Card Key** (5F item ball); the **Saffron rival** on 7F (`Cutscene.silph_rival`,
OPP_RIVAL2 party 7/8/9); a grateful worker's **Lapras** gift (7F); **Giovanni #2** on 11F
(`giovanni_silph`, OPP_GIOVANNI party 2, flees when beaten); and the **president's MASTER BALL**
(`silph_president`, after Giovanni). Verified by `--silphtest`. Also fixed: **rival battle parties are
now keyed by the rival's starter** (the counterpart of the player's), matching `wRivalStarter`
(`_rival_st()`) — the SS Anne/Cerulean/Tower/Champion fights previously used the player's starter.
**Card-key doors are now in** (the earlier "dead-end" was wrong): the doors aren't in the static
`.blk` at all — each floor's `GateCallbackScript` *places* them on load with `ReplaceTileBlock`
(blocks `0x54`/`0x5F`, whose feet tiles are the `0x18`/`0x24` walls), keyed by **block** coords.
`Main.SILPH_DOORS` reproduces every floor's door placements; the load hook lays the locked blocks
(unless the door's `SILPH_DOOR_<floor>_<bx>_<by>` event is set), and facing one with the CARD KEY
swaps it for open floor (`0xE`, or `0x3` on 11F) and sets the event so it stays open
(`_is_silph_door` + the interact handler). Verified by `--cardkeytest`.

**Fly** is in (completing all five HMs): **HM02** from the Route 16 house girl
(`Cutscene.fly_house_girl`); using FLY (party menu, Thunder-gated, outdoors) opens a menu of the
towns you've **visited** (`visited_fly`, tracked on map load; `FLY_DESTS` spawn coords from
`FlyWarpDataPtr`) and warps you there (`Main._open_fly_menu`/`_fly_to`), with the full BIRD
animation (gh #144, `Cutscene.fly_transition` — `player_animations.asm`'s flap-in-place, the
top-right swoop, the high right-to-left pass, and the arrival dive, on pokered's own screen-coord
lists at Delay3 cadence; the map music waits for the landing). Verified by `--flytest`.

**The Elite Four + Champion** are in: the four members (Lorelei/Bruno/Agatha/Lance) battle through
the generic trainer system as you walk up to them in their rooms; the **Champion** is the rival
(`Cutscene.champion_battle`, OPP_RIVAL3 party by starter). Beating him runs the full ceremony
(gh #179, `ChampionsRoom.asm` + `HallOfFame.asm`): the rival's two defeat texts, **OAK arrives**
(voice first, then ShowObject at the south door + the UP×5 walk to the pair), congratulates the
player naming the **starter**, scolds the rival, "Come with me!", exits north and the player
follows up the left column around the rival (the sim-joypad RLE plays in reverse, gh #182) onto the (3,0) door —
into the **HALL_OF_FAME map**, up beside Oak at the machine for the Er-hem speech (the Cerulean
cave guard stands down here, gh #90), then the team registration (`Cutscene.hall_of_fame` — each
mon's sprite/name/level + the HoF theme) and the staff-credits roll. Post-credits, faithfully:
the League **resets for a rematch** (`Main.reset_elite4_gauntlet(true)` — champion included),
`respawn_map` becomes Pallet, the game **saves itself**, THE END holds for a button, and the boot
replays to the **title screen** — CONTINUE resumes on the Hall of Fame floor. **The game is
completable end-to-end.** Verified by `--elitetest` / `--elite4stage`.

**Strength** is in: the Fuchsia **Warden** trades the **GOLD TEETH** (a Safari Zone item ball) for
**HM04** (`Cutscene.warden_strength`); using STRENGTH (party menu, Rainbow-gated) sets
`strength_active`, and then walking into a **boulder** shoves it one tile if the space beyond is
clear (`Main.try_push_boulder`, hooked into `Player`). Verified by `--strengthtest`. Surf + Strength
make Victory Road navigable.

**Surf** is in: **HM03** comes from the Safari Zone secret-house guru (`Cutscene.safari_surf_guru`);
teaching SURF and using it (party field-move menu) while facing water hops the player onto the water
(`surfing`, Soul-Badge-gated) — `is_walkable` makes water passable only while surfing, stepping onto
land dismounts, and wild encounters use the per-map **water** table while surfing. While afloat the
player wears the **SEEL sheet** (gh #170) — `LoadSurfingPlayerSpriteGraphics` loads `SeelSprite`, Gen
1's actual surfing player — via the same `Player._sheet` swap as the BICYCLE (gh #161); dismounting
reloads the walking sheet on the spot (`.stopSurfing` calls `LoadPlayerSpriteGraphics`). Verified by
`--surftest`. (Water tables verified complete against pokered by the gh #176 parity audit — the sea routes share
the TENTACOOL table, everything else genuinely has none.)

**Snorlax** is in: using the **POKé FLUTE** while facing a road-blocking SNORLAX wakes it into a
catchable L30 battle (`Cutscene.wake_snorlax`); beating/catching it clears the route
(`BEAT_SNORLAX_<map>`, generic `_object_shown`). Used elsewhere the flute cures party sleep.
Verified by `--snorlaxtest`. This opens the routes south to Fuchsia.

**Pokémon Tower → Poké Flute** is in: the restless **MAROWAK ghost** on 6F (coord 10,16) is gated by
the SILPH SCOPE — with it you fight MAROWAK L30 (`Cutscene.marowak_ghost`), without it the ghost
blocks you; **Mr. Fuji** on 7F is rescued and warps you to his house (`mr_fuji_tower`), where he
hands over the **POKé FLUTE** (`mr_fuji_flute`; he's hidden at home until rescued). Verified by
`--towerghosttest`.

**Rocket Hideout → Silph Scope** is in: the Celadon Game Corner **poster switch** (`interact` at
(9,4)) reveals the hidden staircase (`set_block` + a `_blocked_cells` guard so the warp can't be
reached while walled); the B1F-B4F floors are navigable (spin-tile arrows are walkable) with Rocket
grunts via the trainer system; **Giovanni** (`Cutscene.giovanni_hideout`) guards the **SILPH SCOPE**
and steps aside when beaten; the Silph Scope + Lift Key are picked up as ordinary item balls. Verified
by `--hideouttest`. The once-deferred refinements have all landed since: the spin-tile arrow floors
(`--spintest`), the guard doors (B1F single-grunt with its every-entry-clunk asm bug, B4F two-grunt
with the one-shot unlock event), and the **elevators** (v0.9.22) — all three (Rocket Hideout with
the LIFT-KEY gate, Celadon Mart, Silph Co) run pokered's real system: the door warps lead back to
the boarding floor until the panel's floor list retargets them, with the ShakeElevator ride (camera
judder + collision clacks + the Safari-PA ding). The Silph elevator's static map data ships broken
(UNUSED_MAP_ED) doors, so the runtime retarget is what makes it usable at all.

**Playtest fixes (faithfulness pass):** the lab rival now shows his line on contact (the battle is
positional); the **item PC** (`<PLAYER>'s PC`) is in via a faithful two-level PC menu; Oak now leads
the player to his lab in **lockstep** (`Cutscene.walk_together`); the **starter's sprite** shows
during selection (`pic()`); mart/Center clerks are **talk-across-counter** (extracted `counter_tiles`
per tileset) and the parcel script stands the player in front of the counter, not on it. In-battle
ANTIDOTE/POTION confirmed (antidote cures, potion = flat 20). Hidden items + item balls verified
complete in extraction (53 + 104; gift-mon balls like Eevee/Hitmons remain bespoke future events).

**In-battle item use** is in: the battle ITEM menu now handles the full set faithfully —
healing potions (all tiers; FULL RESTORE also cures status), status heals (per-status + FULL HEAL),
and X-stat boosters (+1 stage) — each consuming the turn, with ineffective uses refused without
consuming (`Battle._use_item`). Verified by `--battleitemtest`.

**The Bicycle** is in: the Vermilion Pokémon Fan Club chairman gives the **BIKE VOUCHER**
(`Cutscene.fan_club_chairman`), the Cerulean **Bike Shop** trades it for the **BICYCLE**
(`bike_shop_clerk`), and using it outdoors toggles 2x movement (`Main._toggle_bike`,
`Player.step_scale`; cleared indoors). Verified by `--biketest`.

**Celadon vending machines** are in: facing a roof vending machine opens a drink-buy menu
(FRESH WATER / SODA POP / LEMONADE, `Main._open_vending`) — the drinks the Saffron gate guards want.
Verified by `--vendingtest`.

**Fishing** is in (all three rods): the Vermilion guru gives the **OLD ROD**
(`Cutscene.old_rod_guru`), the Fuchsia guru's older brother the **GOOD ROD** (`good_rod_guru`), and
the Route 12 brother the **SUPER ROD** (`super_rod_guru`). Using a rod from the bag while facing a
water/shore tile (`Main._use_rod` / `_rod_encounter`, mirroring `item_effects.asm`) hooks a wild mon:
OLD ROD always MAGIKARP L5; GOOD ROD ~⅓ bite, GOLDEEN/POLIWAG L10; SUPER ROD per-map fishing groups
(`Main.SUPER_ROD_GROUPS`/`SUPER_ROD_MAPS` from data/wild/super_rod.asm). Verified by `--fishtest` +
`--rodtest`.

**Seafoam Islands** are fully in: a STRENGTH boulder shoved onto a hole cell (`Main.SEAFOAM_HOLES`,
per floor) falls to the floor below — removed for good (`FELL_<key>` flag) and setting the floor's
`*_DOWN_HOLE` event (`try_push_boulder`). Once those events are set, the **B4F strong currents**
(`SEAFOAM_CURRENTS`) sweep a surfing player along the original forced routes (`_seafoam_current` →
`Cutscene.walk_forward`, dir/count sequences from the RLE lists): the B2F-boulder landing current
pushes you up out of the fall spot, the B3F-boulder crossing current carries you up-and-right toward
Articuno. `walk_forward` respects walls so a current can never strand you. Verified by `--seafoamtest`
+ `--seafoamcurrenttest`.

**Route 22 rival** is in (bug fix — he was appearing prematurely): the rival objects at (25,5) are
hidden (`_object_shown`) until his battle is armed and the player reaches the trigger (29,4/29,5) —
battle 1 while `GOT_POKEDEX && !BEAT_BROCK`, battle 2 at 8 badges (`_on_player_moved` →
`Cutscene.route22_rival`). He walks in from the west, battles (OPP_RIVAL1/2, party by rival starter),
and leaves. Verified by `--route22test`. Also: the **ledge hop** now cycles the walk frames across the
whole arc (`Player._ledge_jump`) instead of holding one frame.

**UI audit** (rendered every menu vs Gen 1): start menu / PC menu / battle are faithful. Fixed: the
**POKéMON menu** now draws HP-bar rows (name/level + HP bar + cur/max HP + status) via a party mode
on `Menu` (`open_party`/`_draw_party`), used by all four party flows; the **bag** gained its `CANCEL`
entry. Verified by `--partytest`; rendered by `--uishot`. Still stylised vs Gen 1 (noted for later):
the Pokédex is a flat list (no ● caught markers / entry pages), the trainer card is a textbox rather
than a badge card, party menu icons aren't drawn, and the mon submenu lacks SWITCH.

**Rocket Hideout guard doors** are in (audit fix): the B1F door (`Main.ROCKET_DOORS`) stays a wall
until Rocket 5 falls, and the B4F door guarding Giovanni until *both* its guards do
(`DoorCallbackScript`, gated on `defeated_trainers`). The static `.blk` left both open, so the grunt
gates were skippable. Verified by `--rockettest`.

**Elite Four exit seals** are in (a faithfulness-audit fix): each of Lorelei/Bruno/Agatha's rooms
seals its forward exit (`Main.E4_EXITS` — a locked door block + the exit-warp cells added to
`_blocked_cells`) until that member is beaten (`defeated_trainers`), then opens it — mirroring each
room's `ShowOrHideExitBlock`. This was **missing** because the doors are script-placed, not in the
`.blk`: the static defaults left **Lorelei softlocked** (exit walled even after winning) and **Bruno
skippable** (exit open without fighting). Lance's forward path is guarded by Lance himself. Verified
by `--e4test`.

**Route 23 badge gate** is in: the seven `Main.ROUTE23_GATES` checkpoints (cell-row Y → badge) block
you northward toward the Indigo Plateau unless you hold the matching badge (Cascade at the south end
through Earth at the north), turning you back south with the original text (`_on_player_moved`); Y=35
only gates the west side (X<14), per `scripts/Route23.asm`. Verified by `--route23test`.

**Victory Road boulder switches** are in: each floor has a floor switch (`Main.VICTORY_SWITCHES`)
that, when a STRENGTH boulder is shoved onto it (`try_push_boulder`), sets an event and opens that
floor's door block (`set_block`) — re-applied on load so it stays open. This is the puzzle that
gates the path to the Indigo Plateau. Verified by `--victorytest`. (The cross-floor switch reset and
the secondary boulder-holes are simplified to per-floor permanent opens.)

**Pokémon Mansion + Cinnabar Gym** are in: the mansion's switches (`Main.MANSION_SWITCHES`, faced
UP) toggle a shared `MANSION_SWITCH_ON` flag that swaps each floor's gate/floor blocks on load and on
press (`MANSION_BLOCKS` / `_apply_mansion_blocks` / `_mansion_switch`, mirroring
PokemonMansion*.asm). The **SECRET KEY** is the B1F item ball; the Cinnabar Gym door warp is gated on
it (`_do_warp`, "The door is locked..."). Verified by `--mansiontest`.

**Fossils** are in: take one of the Mt. Moon B2F fossils (DOME or HELIX — `Cutscene.mtmoon_fossil`,
the other becomes unreachable) and the Pewter Museum **OLD AMBER** (`give_old_amber`); the Cinnabar
Lab fossil scientist (`revive_fossil`) takes a fossil, then — after you leave to Cinnabar Island and
return (which clears `LAB_STILL_REVIVING_FOSSIL`) — revives it into KABUTO/OMANYTE/AERODACTYL L30
(`Main.fossil_mon`, saved). Verified by `--fossiltest`.

**Gift Pokémon** are in: the **Eevee** ball on the Celadon Mansion roof (`gift_mon_ball`, L25), the
Fighting Dojo's **Hitmonlee/Hitmonchan** prize (`hitmon_gift` — pick one, the other vanishes, no
seconds), and the Mt. Moon Pokécenter **Magikarp salesman** (`magikarp_salesman`, L5 for ¥500). All
add to the party or overflow to the box (`Cutscene._receive_mon`). Verified by `--gifttest`.

**Static legendaries** are in: Articuno (Seafoam B4F), Zapdos (Power Plant), Moltres (Victory Road
2F) and Mewtwo (Cerulean Cave B1F) spawn from their map's `object_event` species+level args — the
generic stationary-mon path (`NPC.wild_species`/`wild_level`, set in `Main._spawn_npcs` when an
object's "opp" arg is a species rather than `OPP_*`). Interacting starts a catchable wild battle
(`Cutscene.static_encounter`); defeating or catching it sets `CAUGHT_STATIC_<map>_<x>_<y>` (keyed by
position, so per-sprite) and it never respawns (`Battle.caught` now also flags a successful ball). The
same path enables the Power Plant's disguised **Voltorbs/Electrodes** (6×VOLTORB L40, 2×ELECTRODE
L43). Verified by `--legendtest`.

**Pokémon Tower rival battle** (4th story rival fight) is in: the rival stands on Tower 2F and
stepping beside him ((15,5)/(14,6)) starts the battle (OPP_RIVAL2, party 4/5/6 by starter), then he
leaves (`Cutscene.tower_rival`). Verified by `--towertest`.

**Flash** is in: dark caves (Rock Tunnel etc., `Main.DARK_MAPS`) render under a dim overlay
(`darkness` ColorRect); a party **field-move menu** (`_open_mon_menu`) lets a mon use **FLASH**
(badge-gated) to light the area (`flash_lit`, reset on leaving), or **CUT** a tree in front — the tree
plays the Gen-1 collapse animation (`_cut_tree_anim`, `AnimCut`) before it's gone. **HM05**
comes from the Route 2 Oak's Aide at ≥10 species (`Cutscene.oaks_aide_flash`). Verified by
`--flashtest`.

Remaining: the later gym leaders (Fuchsia/Koga onward — gated by Cycling Road/Snorlax/Surf and the
Saffron/Silph web), the Silph Scope → Pokémon Tower ghosts / Mr. Fuji → Poké Flute → Snorlax chain,
Surf/Strength traversal, per-move attack SFX, low-HP alarm, the spotlight-vs-dim nicety.

**Map-script seam (gh #53) — complete:** all ~80 scripted maps live behind `MapScripts.gd`'s
seven-hook interface — one adapter per scripted map in `game/scripts/maps/`, 1:1 with pokered's
`scripts/<Map>.asm` (see [engine/map-scripts.md](engine/map-scripts.md), ADR-010). Main's
per-map dispatch chains and all ~24 gimmick tables are gone (one adapter call per touchpoint);
every family migration was guarded by its `--flag` selftests. The sweep also surfaced and fixed
two pre-existing harness stalls (oaktest's StarterDex screen, _drive_bill's naming screen) —
gifttest/fossiltest now pass for the first time since the nickname-offer wave. New #22 beats
land directly as adapters.

## Backlog / discovered sub-tasks

- **Faithful battle-screen polish** (current battle UI is a functional approximation, not a
  pixel-accurate match of pokered): bordered HUD boxes, the ground platforms under each mon,
  "HP:" label + colored/length-accurate HP bar, name/level placement at pokered's tile coords,
  the FIGHT/PKMN/ITEM/RUN box split + move/PP/type sub-window, and battle animations
  (sprite slide-in, attack FX, HP-bar drain tween, the encounter intro transition).


- ~~Extractor: 2 maps skipped~~ ✅ fixed — all **223** maps extract now. `UndergroundPathNorthSouth`'s
  header fudges the height (declares 4×24, blk is 4×23), so the extractor trusts the blk when it's a
  clean multiple of the width; `UndergroundPathRoute7Copy` shares the base map's `.blk` (Copy-suffix
  fallback). This restores the Cerulean↔Vermilion underground link. Verified by `--maptest`.
- Engine: door open/close animation + auto step-out on warp arrival.
- Engine: tile-pair collisions (water/land edges) and ledges (one-way jumps).
- Engine: clamp/letterbox camera on maps smaller than the screen (border fills for now).
- Battle (M11): extract moves/types/learnsets and capture Gen-1 formulas in pokemon.md.
