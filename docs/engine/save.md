# Engine: save / load + healing

## Save file

A normal game uses `user://pokeredpc_save.json` (Godot's per-user dir). `Main.save_game()`
writes the full game state; `Main.load_game()` restores it. Studio play-tests pass a stable
`--saveslot=studio_<path-hash>` derived from the opened project's normalized absolute path,
so each project instead uses its own `pokeredpc_save_studio_<hash>.json`; testing one creator
project can never overwrite the normal game or another project's progress (ADR-020 d5, gh #51).
The serialized fields:

| Field | Source |
|---|---|
| `map` | `center_label` — the active map to reload. **Never a Cable Club room** (gh #6/#9: the trade commit saves at the table, but a reload has no link session — a club-room save writes the attendant-side return point instead, and `load_game` rescues legacy club-room saves via the escape warp) |
| `cell` | `[player.cell.x, player.cell.y]` |
| `facing` | `player.facing` (enum int) |
| `last_outside_map` | for `LAST_MAP` warps |
| `money` | `player_money` |
| `bag` | `player_bag` (item → count) |
| `party` | `player_party` — full mon dicts (species, level, dvs, base, moves, hp, status, …) |
| `defeated_trainers` / `traded_npcs` / `picked_items` / `found_hidden` | one-shot flags (keyed by map+cell / text id / map+cell) |
| `events` | `story_events` (story EVENT flags) + `player_name`/`rival_name`/`*_starter` |
| `badges` | gym badges earned, in order (e.g. `["BOULDERBADGE"]`) |
| `pc_box` | Pokémon stored in the PC (full mon dicts) |
| `link_addr` | v1.1 (additive): the last successfully joined Cable Club address — the joiner's ED default |
| `pokedex_seen` / `pokedex_owned` | Pokédex species sets (seen in battle / caught-obtained) |

The party mons are already plain dictionaries of primitives + arrays, so they serialize
directly. JSON turns ints into floats on read, so bag counts are re-cast to `int` on load and
mon fields are always read through `int(...)`/`str(...)` at the use site.

## Title screen + continue

A normal launch runs `TitleScreen`'s boot sequence (`DUR`/`NEXT` drive the phases; each emits
`phase_changed`, which sets the music in `Main._on_title_phase`):

1. **Copyright** (~3 s, silent) — the exact 3-row tilemap from `title.asm` rendered with the
   condensed copyright tiles (`copyright_strip` = `gfx/splash/copyright.png`, `$60-$72`) plus the
   GAME FREAK wordmark (`$73-$7B`): "©'95'96'98 Nintendo / Creatures inc. / GAME FREAK inc."
2. **Game Freak logo** (~3.2 s, silent) — **letterboxed**; the **figure** (`gamefreak_logo`,
   native size) sits centered above the **GAMEFREAK wordmark** (left 56 px of
   `gamefreak_presents` = `Version_GFX`'s sibling, the real intro lettering). A **big 16×16 star**
   shoots diagonally top-right → bottom-left across the logo, then **four waves of four small
   stars** (the real `SmallStarsWaveNCoords`) fall from beneath it.
3. **Gengar vs Nidorino** — **letterboxed**, following `intro.asm`'s `FightIntroBackMon` (Gengar,
   background mon, **left**, from behind, 3 poses cropped from `gengar.png`; frame-1's stray
   top-right tile is blanked) vs `FrontMon` (Nidorino, **right**, native orientation, facing
   Gengar). The choreography is **frame-accurate**: `build_title` extracts the seven
   `IntroNidorinoAnimation` tables to `title_intro.json`; `_build_timeline` expands
   `PlayIntroScene`'s `SEQ`. Positions match pokered: Gengar at x24, Nidorino's OAM at x72 (just
   overlapping, dipping a little under the bottom bar). The whole timeline is **time-scaled to the
   `introbattle` track length** (`Main` passes `audio.song_length("introbattle")` ≈ 11.6 s into
   `title._battle_dur`) so the fight ends exactly with the music; ends in a **fade to white**.
4. **Title** — source-positioned (from `title.asm`: mon 56×56 at (40,80), trainer at (82,80),
   copyright at (16,136), all sprite bottoms at y136). The Pokémon **logo drops/bounces in**
   (SCY pattern), **"Red Version"** (composed from `red_version.png`'s own letters — the asset
   packs "RedGreenVersion") **slides in from the right**. The **Red trainer** holds a **Poké Ball**
   (extracted from his hand as its own sprite so it can **hop** — `TitleBallYTable` — when a
   **starter** slides out). The cycling mon **slides in from the right (fast, ~0.3 s eased), holds,
   then slides out left** behind the trainer, its bottom-right overlapping the trainer's bottom-left.
   Bottom copyright is `©'95.'96.'98 GAME FREAK inc.` butted tight. Plays **`titlescreen`**.

A keypress skips ahead; on the title it opens **CONTINUE** (if a save exists) → `load_game()` or
**NEW GAME** → clears the old slot. Graphics + the title-mon list are extracted by `build_title`.
`--test` runs skip the sequence. Verified by `--titletest`.

> Renderer gotcha: a **dark `draw_rect`/`ColorRect`/texture won't reliably rasterize inside the
> title Control's `_draw` in the headless `--titletest` capture** (bright colors do; the menu/
> battle dark rects do too) — but the **letterbox bars render fine on a live boot**, so they are
> drawn **after** the sprites (over them, clipping anything that dips into the bars). The
> `--titletest` PNGs therefore don't show the bars even though they appear in-game.

## Triggering

- **SAVE** in the start menu → `YES` calls `save_game()` (shows "RED saved the game!" or
  "Save failed!"). See [menus.md](menus.md). The save also stores `respawn_map` (below).

Verified by `--savetest` (round-trip of money/bag/party/flags).

## Whiteout

When the player runs out of usable mons — losing a battle (`Battle.blacked_out`) or being wiped
by overworld poison — `whiteout()` heals the party and `load_world`s to `respawn_map`: the most
recent **Pokémon Center** healed at (set when talking to a nurse), or Pallet Town at game start.
`respawn_map` is saved. Verified by `--whiteouttest`.

## Pokémon Center healing

Talking to a **nurse** (`object_event` with `SPRITE_NURSE`, i.e. `npc.file == "nurse"`, at
cell (3,1) in every Pokécenter) calls `heal_party()` — full HP, cleared status, restored PP —
and shows the welcome/heal dialogue. Verified by `--healtest`.

## Overworld poison

`Main._overworld_poison()` runs on each walking step (`_on_player_moved`): once any party mon
is poisoned, every **4 steps** each poisoned mon loses 1 HP. A mon that hits 0 faints (message);
if the whole party faints the player **whites out** (party healed — there is no
return-to-last-Center warp yet). Verified by `--savetest` (4 steps → −1 HP).
