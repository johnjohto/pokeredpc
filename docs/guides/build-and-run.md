# Guide: build & run

## Prerequisites (one-time)

```sh
# from the project root
git clone --depth 1 https://github.com/pret/pokered.git pokered
python -m pip install --user Pillow
# download portable Godot 4.7 for your OS into tools/godot/ :
#   Windows: Godot_v4.7-stable_win64.exe          (GUI)
#            Godot_v4.7-stable_win64_console.exe  (CLI / headless, prints to stdout)
#   Linux:   Godot_v4.7-stable_linux.x86_64
#   macOS:   Godot.app  (the scripts call Godot.app/Contents/MacOS/Godot)
```

## Exporting a playable build (Windows)

```powershell
pwsh tools/export.ps1      # after tools/build.ps1 — writes build/windows/
```

Produces `build/windows/pokeredpc.exe` (release template, embedded PCK) with the project
data as a loose **`project/` folder beside the exe** — `res://project` is `.gdignore`'d raw
data, invisible to Godot's exporter *by design* (md5-stable files, no import artifacts), so
the runtime falls back to `<exe dir>/project` in exported builds (`--project=<dir>` still
overrides). The link identity is **derived from the project manifest** in an export (the
same per-part hashes the extractor writes to `link_manifest.json`), so an exported build
links cleanly with a source-run peer — verified: identity match + ping round-trip across
the pair, and the packaged build passes `--selftest` / `--victorytest`. Keep the exe and
the `project/` folder together when moving the build. **Personal use only — do not
distribute the export or the extracted assets.**

## Other platforms (Linux / macOS — gh #12)

The project runs from source on any OS Godot 4.7 ships for; exports are personal-use only
(each player builds their own copy). The whole toolchain is cross-platform:

- `tools/build.ps1` / `tools/run.ps1` run under [pwsh](https://github.com/PowerShell/PowerShell)
  on Linux/macOS and pick the per-OS Godot binary above; set the **`POKEREDPC_GODOT`** env var
  to use a binary elsewhere (e.g. a distro-packaged `godot`). Without pwsh, the direct
  invocations are just `python tools/extract.py`, then
  `tools/godot/<binary> --headless --editor --quit --path game` (import), then
  `tools/godot/<binary> --path game` (play).
- `tools/linktest.py` / `linksoak.py` / `linkdrop.py` resolve the same per-OS binary (and
  honor `POKEREDPC_GODOT`), and read saves from Godot's per-OS user-data dir.
- Saves, trade journals, and keybinds live under Godot's `user://` — per-OS that is
  `%APPDATA%\Godot\app_userdata\pokeredpc` (Windows),
  `~/.local/share/godot/app_userdata/pokeredpc` (Linux),
  `~/Library/Application Support/Godot/app_userdata/pokeredpc` (macOS). Nothing in the
  save/journal code touches OS paths or newlines directly (audited for gh #12): files are
  `JSON.stringify` round-trips through `user://`, and the wire protocol is single-line JSON.
- **Cross-OS link sessions** (the point of gh #12): the link identity handshake requires the
  exact same game version, the exact same **Godot build** (`Engine.get_version_info().string`
  travels in the `hello` — cross-OS builds of one release share it, so 4.7-stable on Windows
  links 4.7-stable on Linux, but 4.7 ≠ 4.7.1), and identical content hashes — both copies
  extracted from the same pret/pokered (the manifest hashes newline-normalized bytes, so the
  OSes' CRLF/LF difference doesn't refuse).

## Build (extract assets + import)

```powershell
pwsh tools/build.ps1
```

This runs `tools/extract.py` (pokered → `game/assets/`) then a headless Godot editor pass to
(re)generate `.import` files. **Note:** the headless import may exit with a Windows access
violation on shutdown (`0xC0000005`) — this is harmless, the import still completes.

## Run

```powershell
pwsh tools/run.ps1            # play (arrow keys to move)
```

## Controls / key bindings

The bindings mirror the Game Boy's eight inputs. Defaults: **arrows** = D-pad, **Z** = A
(confirm / interact / advance text), **X** = B (cancel / back), **Enter** or **Esc** = START
(open/close the menu), **Backspace** = SELECT (reorder items in the bag).

**Space** = turbo (playtest helper, not a GB input): hold it to fast-forward 4x via
`Engine.time_scale` — overworld walking **and battles** (attack animations, HP-bar drains,
auto-advancing battle text; input-gated battle menus simply wait for you). It stays at normal
speed during a cutscene and during non-battle modals — overworld/sign text boxes, the start/bag
menus, and notably the catch ceremony's dex-entry / nickname / naming-keyboard screens, where
accelerating per-frame input used to strand you on the naming keyboard (gh #111). Music keeps
its own pace and the play-time counter stays wall-clock. Remappable like the rest (`turbo=` in
the config).

Controls are remappable via a config file, `keybinds.cfg`, in Godot's user-data dir
(`%APPDATA%\Godot\app_userdata\pokeredpc\keybinds.cfg` on Windows — the exact path is printed to the
console on launch, `[keybinds] applied controls from ...`). It's auto-created with the defaults on
first run. Each value is a comma-separated list of key names:

```ini
[controls]
up="Up"
down="Down"
left="Left"
right="Right"
a="Z"             ; A - confirm / interact
b="X"             ; B - cancel / back
start="Enter,Escape"  ; START - open/close the menu
select="Backspace"    ; SELECT - reorder bag items
```

Valid key names are Godot's (letters, digits, `Up`/`Down`/`Left`/`Right`, `Enter`, `Escape`, `Space`,
`Shift`, `Ctrl`, `Backspace`, ...). Edit the file and relaunch; delete it to restore defaults.
(`Keybinds.gd` applies it to the InputMap at startup; a pre-START/SELECT config is auto-migrated.)

## Auditing the tests

```sh
python tools/audit_places.py
```

Lists every `player.place(Vector2i(x, y))` in `Main.gd` that lands on a **solid** cell. `place()`
bypasses collision, so a driver that drops the player on a wall and then presses A proves nothing about
whether a player could ever stand there — that is how gh #80 (the Silph Co president, faced from a wall
tile) and gh #83 (the Pokémon Mansion switches, pressed from inside the wall) both survived a green
suite. Exits 1 when it finds any; see gh #84 for the current list.

```sh
python tools/audit_headless.py
```

Finds `await RenderingServer.frame_post_draw` on a **gameplay** code path. `--headless` never draws, so
that signal is never emitted and the `await` suspends the coroutine forever — silently, because a
suspended coroutine is not a crash. That is gh #103: `Cutscene.ss_anne_departs` awaited it to screen-grab
the water it sails the ship across, so every headless run stranded on the S.S. Anne gangway, and the
ADR-011 gate (headless by definition) could never pass. The signal may only be awaited from a debug
driver — a `*test`/`*shot` function, run windowed via `tools/run.ps1` — or behind a
`DisplayServer.get_name() != "headless"` guard. Exits 1 on any violation.

```sh
python tools/validate_gate.py <ptrun.log>
```

Validates an ADR-011 Stage-1 run log. **A `PASS:` line is necessary, not sufficient.** It asserts every
stage checkpointed in order and that the run entered the HALL OF FAME, and it fails on six things a
`PASS` would happily coexist with: `FAIL(`, `stayed put` (gh #99's silent crossing bug), `SCRIPT ERROR`
(Godot logs a missing texture and runs on — gh #81), `on_enter SKIPPED` (gh #96), `grind: no reachable
grass` (a grind that did nothing — gh #94), and `attempt N ended on <map>`, which means a stage retried
and so *may* have teleported out of a dungeon via a rebound `LAST_MAP` warp (gh #100).

## Debug / verification flags

Pass these directly to `tools/run.ps1`; the wrapper inserts Godot's required argument
separator automatically. They are handled in `Main.gd` via `OS.get_cmdline_args()` +
`OS.get_cmdline_user_args()`. Each drives a scripted scenario, saves a PNG to `game/`
where noted (git-ignored), prints results, and quits — used to verify features headlessly.

| Flag | What it does |
|---|---|
| `--studio` | **Boot the Studio editor shell instead of the game** (ADR-020/021/023/024, gh #47–#54/#59): one binary, two faces — Studio disables the game's 160×144 pixel-art stretch and opens a themed native resizable 1280×800 desktop window (900×600 minimum), with a persistent top-bar UI-scale slider (80–200%, default 125%), project browser, content/map navigation, schema-generated forms, and isolated child-process Play-test. All 223 Kanto maps open through the format-2 Tiled bridge; the map workspace creates maps and provides tile/block/erase/fill brushes, per-cell collision, pan/zoom, map-level undo/redo, source-preserving Save/Revert, and direct active-map play-test. Forms provide inline validation and canonical Save/Revert. Open any project folder; never edit extractor-owned `game/project` in place (copy it first). `--studio-project=<dir>` opens a folder directly. |
| `--studio-map-fixture` | Open Studio directly on the focused format-2 `TestTown` TMX fixture, showing the Phase-5 themed map workspace without needing a complete creator project. GUI; stays open. |
| `--studiotest` | The Studio gate: scratch-copy/open Kanto, check content counts + refusal, re-save all 515 editable records byte-identically, drive generated/custom editors and restore them, mount the format-2 map workspace, render `studio_tmx.png`, and no-op-save TMX byte-identically. It then creates and edits a map through the real dialog/palette/tools, proves grouped exact undo/redo and targeted source preservation, reopens it, and verifies authored walkable/solid cells in a separate headless Engine child before checking the normal project/save handshake and clean exit. Headless. |
| `--studiomapsweeptest` | The fast Studio map gate (gh #63): reproduce an in-place format-1 → format-2 project rebuild while Studio stays open, verify manifest-aware refresh, then mount all 223 Kanto maps through the real workspace and atlas loader. Headless. |
| `--tmxtest` | Drive the format-2 fixture through Main's real native placement, per-cell collision/semantic IDs, authored spawn, and project-local TSX atlas-quad renderer; writes the unscaled 64×48 `tmxtest.png`. It must hash identically to Studio's `studio_tmx.png`. Headless. |
| `--selftest` | Print map/collision sanity (walkable counts, door/grass/water spot checks). Headless. |
| `--eventtest` | The Event VM tracer (gh #39, ADR-019): loader boot-refusals (unknown command / trigger kind / unparseable condition), the generic `EventMapScript` serving BluesHouse (its hand-written adapter is gone), the `visible` query behind `object_shown`, and the authored Daisy TOWN MAP beat end-to-end (pre-dex line, gift + flag, re-talk, full-bag refusal aborting the event). Headless. |
| `--playthrough` | **Legit-play run — Stage 1 of the 1.0 sign-off (gh #76, ADR-011):** a seeded bot that plays the critical path **on foot, on merit** (real input, so gates/sight/encounters fire natively). Runs ordered **stages** (currently `opening`, `parcel`, `brock`, `misty` — through the CASCADEBADGE), writing a resumable checkpoint save after each. It builds a real team (catches a bench), grinds on merit, and clears dungeons — including Mt. Moon's Rocket-guard maze (triggering each sight-trainer to march off its blocking tile) and its fossil gate. Headless. Pair with `--seed`. |
| `--from=<stage>` | **Modifier** for `--playthrough`: load the previous stage's checkpoint and resume there (debug a leg in ~1 min instead of replaying from NEW GAME). Run the full run once first to create the checkpoints. The sign-off gate run uses no `--from`. |
| `--ptwatchdog=<secs>` | **Modifier** for `--playthrough` (gh #38): the wedge watchdog's window — if the run's progress signature (map, cell, battle events, story events, money, party) freezes for this many wall-clock seconds, it dumps the wedge state (modal / battle state / cutscene / textbox flags), prints a `FAIL(watchdog...)` the gate validator counts, and quits. Default 120; `0` disables (for holding a live wedge open to debug by hand). |
| `--ptwedge=<stage>` | **Modifier** for `--playthrough` (gh #38): simulate the silent-wedge shape — spin quietly forever on entering `<stage>` — to prove the watchdog barks. Test: `--playthrough --seed=1 --ptwatchdog=10 --ptwedge=opening` fails loudly in ~12 s. |
| `--mtmoontest` | Fast regression for the Mt. Moon crossing: set up a post-Brock team on Route 4 and drive the bot through Mt. Moon to Cerulean (no NEW GAME / grind). Prints each ladder leg + a final PASS/FAIL. |
| `--mistytest` | Fast iteration on the Misty fight: set up a post-Mt.-Moon team + potions in the Cerulean Gym and drive the real leader fight with per-turn battle logging (no NEW GAME / grind / nav). Tune with `--lvl N` / `--pots N`. |
| `--surgecombat` | Fast iteration on the Lt. Surge fight: door pre-opened, drive the leader battle with per-turn logging. `--bench diglett:20` puts a Ground mon (immune to Surge's electric) on the bench to exercise the proactive type-disadvantage switch. **Tuning harness, not a green gate** — the default bench-less run pits a lone Wartortle against Surge and is expected to print `FAIL`. The gate is `--surgetest`. (Same for `--erikacombat`: the gate is `--erikastage`, which catches a Growlithe first.) |
| `--surgenavtest` | Fast iteration on the Cerulean→Vermilion navigation: from a post-Misty state (with the S.S.TICKET, so the trashed-house guard is gone) drives gym → trashed-house shortcut → Route 5 → Underground Path → Route 6 → Vermilion. No catch / grind / fight. |
| `--billstage` | Drive the Bill / S.S.TICKET questline from a post-Misty state in Cerulean: north-bridge rival ambush → Nugget Bridge → Route 25 → Bill's cottage → cell-separator → S.S.TICKET. `--lvl N` sets the lead level; `--house` skips the gauntlet and tests only the cottage interaction. |
| `--annestage` | Fast iteration on the S.S. Anne stage (HM01 CUT + the Vermilion Gym tree). Default: from Vermilion with the ticket + an Oddish Cut slave, drive board → rival ambush → captain → HM01 → teach CUT → cut the gym tree. `--catch` starts on Route 6 and tests only the Oddish Cut-slave catch; `--full` runs the whole stage from Cerulean (nav + catch + ship + tree). Pair with `--seed` (the ship rival is a real fight). |
| `--silphstage` | Drive the Silph Co stage from Saffron's street: in the front door (which only opens once MR.FUJI is rescued, gh #79), lift → 9F → the pad into 5F's sealed corridor for the CARD KEY, lift → 3F → the pad chain 3F → 7F → 11F, opening card-key doors on the way, and beat GIOVANNI — which clears Team Rocket off Saffron Gym's door. `--card` stops once the key is in the bag; `--verbose` traces each step. Pair with `--seed` (the 7F rival and GIOVANNI are real fights). |
| `--sabrinastage` | Drive the Saffron Gym stage from the street: in the gym door (clear only once GIOVANNI has fallen), ride the pad chain `(11,15) → (15,15) → (15,5) → (1,5)` into SABRINA's room at (11,11), and beat her for the MARSHBADGE. The gym's whole warp table is 30 self-warps, so every room is reached by teleport. `--pads` stops once the chain lands; `--verbose` traces each step. Pair with `--seed` (SABRINA is a real fight). |
| `--surfnavtest` | The bot's first water crossing: from Fuchsia, walk south onto Route 19's beach, SURF at (5,9), swim down the route fighting the swimmers, and cross the map connection **into Route 20 while still afloat** (impossible before gh #82). Pair with `--seed` (the swimmers are real fights). |
| `--cinnabarnavtest` | Reach Cinnabar Island: FLY home to Pallet, SURF off its beach at (4,13), and swim the 90 cells of Route 21 — fishers and swimmers engage on sight — to the island's north shore. Cinnabar has no dry connection, and the Fuchsia approach runs *through* Seafoam Islands, so this is the way in. Pair with `--seed`. |
| `--event NAME` | **Modifier** for `--rtprobe`: set a story event before the map loads, so a floor whose `on_enter` lays blocks from an event (a Pokémon Mansion switch, a Silph card-key door) can be probed in both states. e.g. `--rtprobe --map PokemonMansion1F --sx 2 --sy 6 --event MANSION_SWITCH_ON --grid`. |
| `--holetest` | Pokémon Mansion balcony holes (gh #85): 3F's western drops fall to 1F (16,14) — the only entrance to 1F's sealed south, and so to the B1F stairs — while the eastern one falls to 2F. Also asserts that the floor's *other* burnt tiles do nothing. |
| `--secretkeytest` | Walk the Pokémon Mansion's switch puzzle from Cinnabar's street: up to 3F, flip its panel, fall through the western balcony into 1F's sealed south, down to B1F, flip both of its panels, take the SECRET KEY, and leave by the back door. The panels are not interchangeable — B1F's north one seals its own staircase. |
| `--blainestage` | Drive the seventh badge from Cinnabar's street: walk the Pokémon Mansion for the SECRET KEY (the gym door is locked without it), then Cinnabar Gym's six quiz gates — a snake of rooms whose order is forced, each machine a wall panel pressed from below — and beat BLAINE. `--gym` starts with the key, skipping the mansion. Pair with `--seed` (BLAINE is a real fight). |
| `--viridiangatetest` | Viridian Gym's badge lock (gh #86): with no badges, stepping onto the door cell (32,8) says "The GYM's doors are locked..." and hops you back down the ledge at (32,9); six badges is still not enough; the seventh latches `VIRIDIAN_GYM_OPEN` and the door admits you. |
| `--giovannistage` | Drive the eighth badge from Viridian's street: in the gym door (shut until the other seven badges are in hand), through the spin-tile maze and its eight sight-trainers, and beat GIOVANNI for the EARTHBADGE. Pair with `--seed`. |
| `--seed N` | **Modifier** for any run: seed the global RNG (`seed(N)`) for a reproducible session instead of `randomize()`. Shipped play passes no flag. |
| `--shot` | Render one frame → `game/shot.png`. |
| `--walkshot` | Walk the player down ~0.5s, capture → `game/walkshot.png` (movement + camera). |
| `--warptest` | Enter Red's house via the door, then exit via the mat (LAST_MAP round-trip). |
| `--conntest` | Walk north out of Pallet Town; verify the active map rebases to Route1. → `conn_*.png`. |
| `--ledgetest` | Find a down-ledge in Route1 and hop it; capture mid-hop arc → `ledgetest.png`. |
| `--grasstest` | Stand on a Route1 grass tile; verify the leg overlay → `grasstest.png`. |
| `--npctest` | Pallet Town NPCs: spawn count, Oak solid + interact, Girl wanders → `npctest.png`. |
| `--texttest` | Talk to Oak (typed box → `texttest.png`); Girl's 2-page text paginates + closes. |
| `--signtest` | Read the Pallet Town sign via real keypresses; closes in finite presses (no loop) → `signtest.png`. |
| `--menutest` | Open start menu (Esc), navigate, select → text; SAVE → yes/no → "saved" → `menu*.png`. |
| `--battletest` | Wild battle: party/menus, fight to a win, EXP + level-up → `battle*.png`. |
| `--catchtest` | Weaken the wild mon, throw a Poké Ball, confirm it joins the party → `catch1.png`. |
| `--statmovetest` | Use GROWL; confirm the enemy's ATTACK stage drops. |
| `--trainertest` | Trainer battle (Bug Catcher, 2 mons): RUN blocked, fight the team, win → prize money. |
| `--statustest` | Status conditions: poison tick, sleep skip+countdown, paralysis Speed ÷4 → `status1.png`. |
| `--movefxtest` | Move effects: fixed/super-fang/drain/recoil/leech/heal/confuse + level-up evolution. |
| `--battledettest` | The battle determinism oracle (gh #2, ADR-014): scenario battles replayed twice per seed — canonical per-turn event streams must be byte-identical, a different seed must diverge; prints per-scenario `stream_md5` (stable across invocations). `--verbose` echoes every event line. |
| `--monrecordtest` | The mon record codec (gh #4): round-trips varied mons through the `mon/1` wire schema, refuses an unknown version, rejects ~24 malformed fixtures cleanly. Single-process. |
| `--schematest` | v2 Core (gh #22, ADR-017): the project-format schema suite — the valid fixture project validates clean (ids registered per prefix), seven broken fixtures each rejected with exactly one error naming file + path. Headless. |
| `--validate=<dir>` | v2 Core (gh #22): validate any project directory (res:// or OS path) against the format — schema violations, unclaimed files, record-id mismatches, dangling references. Exit 0 only when clean. Headless. |
| `--projparitytest` | v2 Core (gh #25/#53/#54): the reconstruction oracle — `ProjectData.legacy()` must deep-equal the legacy `res://assets` file for every data table; all 223 native TMX maps must reconstruct their legacy semantics exactly; and all 24 TSX atlases must preserve their block mappings and source pixels. Headless. |
| `--project=<dir>` | **Modifier** for any run (gh #25): load a different project directory instead of the default `res://project` (the extractor's emission). |
| `--rulesettest` | v2 Phase 2 (gh #31/#32/#34, ADR-018): the ruleset seam — boot must resolve the manifest's ruleset through the registry, an unknown name must refuse, the seam's type resolver must match the raw project chart over the full type cross-product (the Types tracer bullet), the formula kernels answer Gen-1's book values (exp curves, Mew's 298/403, stage table, damage core, the crit byte, the 1/256 sure-miss, MASTER BALL), the Catch/Progression modules answer their mappings, `data/ruleset.json` loads with base gen1, and an overridden config knob actually turns. Headless. |
| `--exprtest` | v2 Phase 2 (gh #35, ADR-018 §3): the formula-expression evaluator — unit semantics (integer exactness, precedence, if/and/or branching, named parse errors) plus the equivalence sweep: the expression-authored Gen-1 kernels (stat_calc, the four growth curves, damage_core incl. the /4 overflow branch) must equal the native outputs over ~1.3k vectors. Headless. |
| `--host [--port=N]` | v1.1 link (gh #3): host a link session and wait; on link, a ping/pong round-trip, then close. See [engine/link.md](../engine/link.md). |
| `--join <ip>` | v1.1 link (gh #3): connect to a host. Modifiers for both: `--tamper=version\|engine\|<part>` (drive the identity refusal), `--linktimeout=N`, `--dupe`. Pairs are driven by `python tools/linktest.py`. |
| `--clubtest` | The Cable Club attendant (gh #5). Alone: every single-instance refusal/timeout path lands back cleanly. With `--clubhost` / `--clubjoin [--port=N] [--tamper=X]`: one side of the full in-game link flow — `--trade` continues into the Trade Center round-trip (gh #6), `--battle` into the Colosseum lockstep battle (gh #7). Driven in pairs by `tools/linktest.py`. |
| `--colsoak` | One desync-soak battle (gh #8): link up, exchange parties + the pinned `--colseed`, fight with a varied deterministic move policy (`--colparty=N` picks the roster set). Driven in batteries by `python tools/linksoak.py [--battles N]`. |
| `--killat=X` / `--recovertest` | gh #9 drop injection: pull the cable at a scripted point (`pick`/`confirm`/`commit`/`ack`/`actN`); relaunch the slot to run the trade-journal recovery. Driven by `python tools/linkdrop.py` (battle drops, the trade rollback/roll-forward matrix, the mutual-opt-in dupe egg). |
| `--moveanimtest` | Move animations (gh #19): step building + enemy-turn transform + timed `{"moveanim"}` markers + a real fight turn → `moveanim_thunder.png`, `moveanim_gust_enemy.png`. |
| `--wipetest` | Battle transitions: the 8-wipe pick (level/trainer/dungeon bits) + each wipe over the overworld + the warp fade → `wipe_*.png`. |
| `--introshot` | Poses the boot intro at key beats (splash star, fight, logo bounce, version) → `intro_*.png`, `title_*.png`. |
| `--optiontest` | The OPTION menu + its effects: text speed applies, BATTLE ANIMATION OFF = 30-frame beat, BATTLE STYLE SHIFT prompt (declined + accepted free switch). |
| `--oldmantest` | Viridian's old man: sleepy/awake object swap + the catching demo (auto-played OLD MAN vs WEEDLE; nothing kept or consumed). |
| `--pewtertest` | Pewter's escorts: museum-guy and gym-kid drags land on the exact cells; the pre-BROCK east-exit gate fires the drag. |
| `--spintest` | Spin tiles: the hideout arrow slides the player along the extracted path, sprite whirling, input locked. |
| `--spinwalltest` | Audits every arrow tile on all three spinner maps: the tile is walkable and its baked slide comes to rest on walkable, non-warp floor (the slide crossing walls mid-path is faithful — pokered skips collision while spinning). |
| `--quiztest` | Cinnabar Gym quiz machines: a right answer opens the gate block; a wrong one starts the room's trainer fight. |
| `--cinnabardoortest` | Cinnabar Gym door lock (gh #172): without the SECRET KEY, walking up bounces the player off the tile below the door (never onto it); with the key the door works. Real movement. |
| `--gatedoortest` | Solid-warp step (gh #149): you can't walk onto a warp set into a solid tile (Route 7's gate door at (11,9)) from a side that doesn't fire it — it bumps — while the gate stays enterable via its walkable mat. |
| `--playmap <Map>` | Drop straight into interactive play on a map (skips the title), for checking a spot by hand. E.g. `--playmap Route7` (defaults to Route 7). Arrow keys; save is routed to the isolated test file. |
| `--bagtest` | Bag rules: USE/TOSS submenu + quantity + confirm, key items refuse tossing, the 20-slot capacity. |
| `--faintordertest` | KO order: a mon KO'd this turn does not still act — both directions (player KOs enemy; enemy KOs player). |
| `--dblkotest` | Double KO (gh #112): a recoil move that KOs the enemy and recoils the user to 0 the same turn faints BOTH mons — the player is forced to switch, not left able to act with a 0-HP lead. |
| `--chargepptest` | Charge-move PP (gh #168): a normal FLY spends its PP on the fire turn (not the charge turn); a FLY frozen mid-charge keeps its PP. |
| `--hoftest` | League PC: hidden pre-HoF, listed after; the records viewer replays the teams and returns to the PC. |
| `--aidetest` | The Route 11/15 gate aides: refused under the dex count, ITEMFINDER at 30 / EXP.ALL at 50 granted. |
| `--faithtest` | Faithful Toxic escalation, Substitute block+absorb, trapping lock, Transform, EXP split. |
| `--learntest` | Learning a 5th move opens the "delete a move?" prompt → `learn1.png`. |
| `--stonetest` | Use a Moon Stone from the overworld bag on Clefairy → Clefable → `stone_*.png`. |
| `--tradetest` | In-game NPC trade: the full dialog (offer/party pick/wrong mon), the trade MOVIE (gh #185 — cards, ball-into-cable, the circled-icon cable crawl), the after-trade line, + trade evolution → `trade_card.png`, `trade_crawl.png`, `trade_evo.png`. |
| `--edgetest` | DV stat variation, crit ignoring ATK stage, and the Focus Energy crit bug. |
| `--savetest` | Save/load round-trip (money/bag/party/flags) + overworld poison tick. Headless. |
| `--healtest` | Pokécenter nurse heals the party (HP/status/PP) in CeruleanPokecenter. Headless. |
| `--audiotest` | Synthesize music + SFX + a cry (Hz/timing/peak); writes `pallettown.wav` / `cry_charmander.wav`. |
| `--presynthtest` | Background pre-synthesis: time for the current song + all 45 to cache. Headless. |
| `--wildtest` | Per-map grass encounters: Route 1 rate + species distribution. Headless. |
| `--whiteouttest` | Battle blackout heals the party and warps to the last Center. Headless. |
| `--titletest` | Title → CONTINUE / NEW GAME flow (with and without a save) → `title.png`. |
| `--oaktest` | Opening quest: Oak's intercept → lab intro → pick a starter → first rival battle → `oak_*.png`. GUI (screenshots). |
| `--parceltest` | Oak's Parcel errand: Viridian gate (blocked/open) + Mart pickup + delivery & POKéDEX receipt. Headless. |
| `--sighttest` | Trainer line-of-sight on Route 3: negatives, `!` bubble + walk-up, before/end/after text, defeat. → `sight_bubble.png` (GUI). |
| `--gymtest` | Gym leaders Brock + Misty: leader battle → badge + TM, re-talk line. Headless. |
| `--sfxtest` | Battle SFX cues: hit (by effectiveness), faint, level-up, ball toss + caught, run. Headless. |
| `--badgetest` | Badge stat boosts: BOULDERBADGE raises the player's Attack ×9/8; foe + un-badged stats unchanged. Headless. |
| `--maptest` | The previously-skipped underground maps load with consistent collision dims + warps. Headless. |
| `--surgetest` | Vermilion Gym: trash-can puzzle (1st/2nd switch, reset) opens the door → Surge → Thunder Badge + TM24. Headless. |
| `--itemtest` | Overworld item ball: pick up POTION in Viridian Forest → bag + sprite gone, persists across reload. Headless. |
| `--marttest` | Poké Mart: clerk opens shop, buy (incl. broke-rejection), cancel, sell at half price. Headless. |
| `--pctest` | PC: top menu → Someone's PC (mon deposit/withdraw + guards) and the <PLAYER>'s PC item box (withdraw/deposit). Headless. |
| `--dexratingtest` | PROF.OAK's dex rating (gh #185): tier texts + band jingles at his PC, the lab rating/5-ball-gift/come-see-me branches, Pallet's ball-gift event. Headless. |
| `--diplomatest` | The DIPLOMA (gh #185): the game designer's 150-owned gate, the card screen renders + closes → `diploma_shot.png`. |
| `--moneyboxtest` | The MONEY_BOX outside marts (gh #185): vending, Daycare fee, Museum ticket, Safari gate, Magikarp salesman — up for the prompt, refreshed after paying, cleared at script end. Headless. |
| `--clearsavetest` | Up+Select+B at the title (gh #185): the clear-save NO/YES (NO first), YES deletes the save, both reboot the title; no combo = normal start. Headless. |
| `--cuttest` | HM Cut: teach via HM01 (compat-checked), badge-gated tree cut in Cerulean, incompatible-species reject. Headless. |
| `--hiddentest` | Hidden item: find the Viridian Forest POTION by facing its tile; one-shot, empty tile yields nothing. Headless. |
| `--itemusetest` | Bag items: potions/status-heal/revive/rare-candy on a mon + Repel counter + Escape Rope warp. Headless. |
| `--crivaltest` | Cerulean bridge rival battle: rival appears → OPP_RIVAL1 (party by starter) → beat flag + leaves. Headless. |
| `--billtest` | Bill's house: talk to Bill-mon → cell-separator PC → Bill emerges → S.S.TICKET. Headless. |
| `--ssannetest` | S.S. Anne: ticket gate, captain's HM01 (CUT), the 2F deck rival (OPP_RIVAL2), and the ship departing. Headless. |
| `--fishtest` | Fishing: the Vermilion guru gives the OLD ROD; using it facing water hooks MAGIKARP L5, land rejects. Headless. |
| `--vendingtest` | Celadon roof vending machine: buy a FRESH WATER, broke-rejection. Headless. |
| `--biketest` | Bike: Fan Club voucher → Cerulean Bike Shop → BICYCLE → ride toggle (2x, outdoor-only). Headless. |
| `--battleitemtest` | In-battle items: X-stat boost, FULL HEAL cure, potion heal/tiers, and no-effect (no consume). Headless. |
| `--tmtest` | TM teaching: TM06 → TOXIC on a compatible mon (consumes the TM); an incompatible TM is refused. Headless. |
| `--daycaretest` | Day Care: deposit a party mon, EXP accrues per step, withdraw at the grown level for a per-level fee. Headless. |
| `--hideouttest` | Rocket Hideout: Game Corner poster opens the staircase; B4F Giovanni guards the SILPH SCOPE → beat → he leaves. Headless. |
| `--towerghosttest` | Pokémon Tower: MAROWAK ghost gated by the SILPH SCOPE → Mr. Fuji rescue + warp home → POKé FLUTE. Headless. |
| `--snorlaxtest` | POKé FLUTE wakes a road SNORLAX → catchable L30 battle → it clears; also cures party sleep elsewhere. Headless. |
| `--surftest` | Surf: HM03 from the Safari secret house → teach SURF → hop onto water (badge-gated) wearing the SEEL sheet (gh #170), land dismounts back to the walking sheet. Headless. |
| `--strengthtest` | Strength: Warden trades GOLD TEETH for HM04 → teach → activate → push a boulder one tile (no-strength blocked). Headless. |
| `--elitetest` | Elite Four: an E4 member (Lorelei) via the trainer system + the Champion (rival OPP_RIVAL3) → Hall of Fame. Headless. |
| `--flytest` | Fly: HM02 from the Route 16 house → teach FLY → visited-town menu → warp to a town, shooting the bird mid-swoop → `fly_bird.png`. **GUI (windowed)** — it awaits `frame_post_draw` for that screenshot, so under `--headless` it suspends forever (gh #103's rule: a `*test` driver may await it, but only run windowed). |
| `--silphtest` | Silph Co: 7F Lapras gift + Saffron rival, 11F Giovanni #2, and the president's MASTER BALL. Headless. |
| `--dockscene` | PLAYABLE: spawn on the Vermilion Dock with HM01 — the S.S. ANNE departure fires on arrival (gh #118) — then keep playing. Isolated test save. |
| `--safaribattletest` | Safari battle: BALL/BAIT/ROCK/RUN menu, rock doubles & bait halves the catch rate, ball use, encounter ends. Shoots the faithful full-width menu (gh #169) to `game/safari_menu.png`. Windowed (screenshot). |
| `--safaritest` | Safari Zone: gate pays ¥500 → 30 balls + 500 steps, the step counter ticks down, and time-out runs the PA announcement *before* the eject (gh #171), then the gate worker signs you out and walks you south. Headless. |
| `--keybindtest` | Key bindings: defaults written + applied (Z=A, arrows, START, SELECT), an action remaps, and SELECT reorders the bag. Headless. |
| `--saffrontest` | Saffron gate: the thirsty guard blocks + pushes back without a drink; a drink opens all gates. Headless. |
| `--slottest` | Game Corner slots: paylines, payouts (7=300/BAR=100/cherry=8/Pokémon=15), the win rig (none/normal/7-BAR), coin cap, and a full play cycle. Headless. |
| `--slotshot` | Render the slot machine at the bet prompt + a 7-7-7 jackpot → `slot_bet.png` / `slot_win.png`. GUI. |
| `--prizetest` | Prize room: buy a Pokémon prize (joins party / overflows to box), a TM prize, broke-rejection, and coin deduction. Headless. |
| `--rodtest` | Fishing rods: Old Rod (Magikarp L5), Good Rod (Goldeen/Poliwag L10), Super Rod (per-map group, e.g. Cerulean's Psyduck/Goldeen/Krabby), and no-bite where there's no group. Headless. |
| `--legendtest` | Static legendaries: Articuno/Zapdos/Moltres/Mewtwo spawn at the right species+level; interacting starts a catchable battle; defeat/catch removes it and it doesn't respawn. Headless. |
| `--gifttest` | Gift Pokémon: Eevee ball (Celadon), Hitmonlee/chan choice (Fighting Dojo, the other vanishes + greedy guard), and the Mt. Moon Magikarp salesman (¥500). Headless. |
| `--fossiltest` | Fossils: take the Mt. Moon DOME (Helix unreachable), the museum OLD AMBER, then the Cinnabar lab revives it (give → leave to the island → return → Kabuto L30). Headless. |
| `--mansiontest` | Pokémon Mansion switches toggle the gate/floor blocks on every floor (shared flag, persists); the Cinnabar Gym door is locked until you carry the SECRET KEY. Headless. |
| `--victorytest` | Victory Road: a STRENGTH boulder pushed onto a floor switch opens that floor's door block (1F + 2F), and the opened door persists across a reload. Headless. |
| `--townmaptest` | Town Map: the cycle entries load, opening from a town starts the cursor there, and the cursor stays on-screen. Headless. |
| `--route23test` | Route 23 badge checkpoints: each latitude blocks you north without its badge (Cascade→Earth), the east side of Y=35 is free, and the right badge lets you through. Headless. |
| `--seafoamtest` | Seafoam Islands: a STRENGTH boulder pushed onto a hole falls (sets the down-hole event), stays gone on reload, and Articuno remains reachable. Headless. |
| `--cardkeytest` | Silph Co card-key doors: script-placed locked door blocks are impassable, the CARD KEY opens the faced one (persists on reload), and the others stay locked. Headless. |
| `--seafoamcurrenttest` | Seafoam B4F strong current: with no boulders placed a current tile is inert; with the B3F boulders down it sweeps the surfing player north along the forced route. Headless. |
| `--e4test` | Elite Four exit seals: each room's forward exit is walled until its member falls, then opens — fixing the Lorelei softlock and the Bruno skip that the static .blk caused. Headless. |
| `--rockettest` | Rocket Hideout guard doors: the B1F door stays shut until Rocket 5 falls, and the B4F Giovanni door until both guards fall (one isn't enough). Headless. |
| `--partytest` | POKéMON menu opens in party mode (HP-bar rows, cursor count = party size); the mon submenu opens on select; the bag's CANCEL entry is present + inert. Headless. |
| `--route22test` | Route 22 rival: hidden by default, no trigger unarmed; armed (Pokédex, pre-Brock) he walks in + battles (OPP_RIVAL1); winning sets the flag + he leaves. Headless. |
| `--rivallosstest` | Losing the first rival battle heals + continues (no whiteout, `BEAT_RIVAL1` set). Headless. |
| `--cyclinggatetest` | Cycling Road gate turns you back without a BICYCLE; Route 22 Gate blocks the way to the League without the BOULDERBADGE. Headless. |
| `--pcaccesstest` / `--pcentershot` | Red's-room item PC + Pokécenter mon storage reachable; each Pokécenter NPC interacts. |
| `--starterballtest` / `--hiddencuttest` / `--blueshousetest` | Untaken starter ball + "last POKéMON" text; hidden item beats a cut tree; one Daisy at a time. Headless. |
| `--uishot` | Render the menu screens (start / bag / party / mon submenu / dex / trainer card / PC) → `ui_*.png`. GUI. |
| `--creditstest` | End credits: the staff pages load (34) and the credits roll runs to completion. Headless. |
| `--creditshot` | Render a credits page (Programmers) → `credits.png`. GUI. |
| `--townmapshot` | Render the Town Map at Pallet Town + Celadon City (cursor moves) → `townmap_pallet.png` / `townmap_celadon.png`. GUI. |
| `--caveshot` | Render Rock Tunnel with the dark-cave palette swap (no FLASH) and fully lit (FLASH) → `cave_dark.png` / `cave_flash.png`. GUI. |
| `--flashtest` | Flash: Rock Tunnel dark overlay, the party field-move menu, badge-gated FLASH lighting it, + HM05 from the Route 2 aide. Headless. |
| `--towertest` | Pokémon Tower 2F rival battle: visible rival → OPP_RIVAL2 (party by starter) → beat flag + leaves. Headless. |
| `--dextest` | Pokédex: enemy marked seen in battle, party/box folded into owned, dex list shows name/`*`/`----`. Headless. |
| `--scrolltest` | Cursor-menu windowing: a 12-item list scrolls a 7-row window with the cursor. Headless. |

```powershell
pwsh tools/run.ps1 --selftest             # GUI build; or use the _console build headless:
& tools/godot/Godot_v4.7-stable_win64_console.exe --headless --path game -- --selftest
```

> Note: `--shot`/`--walkshot` etc. need a render target, so run them with the **GUI** build
> (`Godot_v4.7-stable_win64.exe`), not `--headless`. `--selftest` runs fully headless.

## Direct Godot invocation

```powershell
$g = "tools/godot/Godot_v4.7-stable_win64_console.exe"
& $g --headless --path game -- --selftest
```

## Regenerating verification renders

`tools/extract.py` also writes `build/preview/PalletTown.png`. Collision overlays
(`build/preview/coll_*.png`) are produced by ad-hoc scripts during collision work.
