# Changelog

All notable changes to **pokeredpc** are recorded here. Versioning tracks how close the port is to
a 1:1 recreation of pret/pokered: **`0.9` = full audited parity** (every system verified against
the disassembly), and **`1.0.0` requires a complete playthrough sign-off** on top — audits prove
systems in isolation; only a full run proves the game. `MINOR` bumps mark content/feature
milestones, `PATCH` bumps are fixes/polish. See `docs/roadmap.md` for the live per-feature detail.

## [Unreleased]

### Added

- **HatchScript formula hatch** (gh #66, ADR-030). `data/ruleset.json` gained
  `formula_scripts`: kernel name → `script:` record, replacing that kernel's arithmetic
  behind the same `RulesetFormulas` interface gen1 uses — bound kernels run their
  HatchScript, unbound kernels keep the ruleset's native math, and any ruleset gains the
  hatch through the generic `Ruleset.attach_formula_scripts()` boot step. RNG kernels
  receive the battle's draw Callables as `rand_float`/`rand_range`/`rand_int` hosts, so
  scripts control formula math, never draw order; `catch_attempt` reports through
  `out("caught", …)`/`out("shakes", …)`; binding `exp_for_level` alone derives
  `level_for_exp` from the scripted curve. Unknown kernels, dangling script refs, and
  unparseable sources refuse at validation and boot; runtime failures fall back to the
  base kernel loudly. `--exprtest` holds all ten gen1 kernels re-expressed as scripts to
  the native outputs (value- and draw-identical) and boots a child Engine proving a
  doubled catch rate + custom exp curve live in play-test from data alone;
  `--battledettest` on the fully gen1-scripted project reproduces all four vanilla
  stream md5s byte-identically.

- **HatchScript event integration** (gh #65, ADR-028). Projects can store validated
  `data/scripts/*.json` sources and invoke them from the schema-derived event palette
  with `run_script`. Scripts receive transactional story flag/variable operations,
  read-only party/bag/map/currency/badge queries, and stable wrappers over the generic
  EventVM command subset; queued commands retain the VM's existing await/abort behavior.
  A scalar return can feed the next ordinary event branch, and additive save type tags
  preserve integer-exact variables across reloads. Bad records/source/references, runtime
  failures, and missing requested returns refuse explicitly. The Event VM smoke covers
  the puzzle, command queue, and rollback paths, and the Studio gate saves/reopens the
  event + script before observing its branch marker in a separate Engine child.

- **HatchScript Core language** (gh #64, ADR-028). The sandboxed Phase-6 DSL now
  supports locals and assignment, if/else, bounded while loops, return values,
  integer-exact FormulaExpr-compatible arithmetic, strings/booleans, and only
  explicitly registered host calls. Parse and runtime failures report line/column
  positions, runaway loops stop at a deterministic step budget, and parsed scripts
  can be reused safely across runs. `--exprtest` carries the Core semantics,
  sandbox-refusal, budget, and determinism smoke.

- **Pokémon Blue extraction/build option** (gh #26, ADR-029). `tools/extract.py
  --version blue` and `pwsh tools/build.ps1 --version blue` now select pokered's
  `_BLUE` conditionals for wild encounters, title mons/wordmark/intro mon, Oak-speech
  default names, Game Corner prizes, slot graphics, credits, and the save jingle. The
  emitted Project identifies itself as `kanto-blue`, while Red remains the default and
  Red<->Blue Cable Club compatibility is preserved by keeping link identity scoped to
  battle/mon-record data (`species`, `moves`, `types`).

- **Studio data-editor presentation pass** (gh #61). Species, moves, items, and
  trainers no longer read as raw generated forms: fields group into curated section
  cards (presentation-only — the schema stays the field authority), required fields
  carry a `*` marker beside muted optional labels, schema `$comment`s surface as
  tooltips, and an invalid draft draws a danger border on the offending input beside
  its error text. The record browser gains a filter box with an explicit empty state,
  and the theme family now covers CheckBox, TextEdit, SpinBox, popup menus,
  scrollbars, and tooltips with visible focus rings. All field-path, error-label,
  widget, and canonical-save contracts from the schema-form engine are unchanged.
  A `--studio-shot=<file>` flag captures a windowed form for visual review.

- **The Phase-5 gate: a complete original-map creator journey in Studio** (gh #58).
  One automated flow, driven only through real Studio seams, creates an original 8x6
  map, paints art and collision, undoes/redoes and reverts, places a warp/NPC/sign,
  sees the Problems panel flag a deliberately sealed warp and clears it with the fix,
  links a companion map into the world graph, authors a branched NPC event, and
  survives a Tiled-origin edit of the same TMX (editor settings, foreign properties
  and object groups all preserved across Studio open + save). A live Engine child then
  starts on the new map, warps into the companion map, returns across the authored
  seamless edge, and executes the NPC's authored branch. An explicit Tiled-origin
  fixture (`core/fixtures/tiled_origin`) locks the unknown-data round trip in Core.

- **Shared map/story softlock lints across Core, Studio, and CI** (gh #57, ADR-027).
  `ProjectLint` wraps project validation and adds source-addressed diagnostics:
  blocking objects that seal a warp/sign/item or split a map's useful regions,
  event-backed door verification, NPC/spawn standability, original-map spawn
  reachability, and object/event link mismatches. Warnings are review-required and
  clear only through named, reasoned suppressions in `data/lint_suppressions.json`;
  errors are never suppressible and stale suppressions warn. Studio's new Problems
  panel lists the same stream and focuses the source map object or event on
  selection. `--validate` prints one line per unreviewed diagnostic and exits
  non-zero, and the determinism workflow gates on it. Clean Kanto lints at 0
  errors / 0 warnings / 21 reviewed suppressions, and the Core smoke re-creates
  the gh #79/#89/#90 softlocks by deleting their door-opening records.

- **Studio now authors working NPC and trigger events** (gh #56, ADR-026). Events have a
  dedicated list/create workspace, schema-derived trigger and reference controls, and a
  complete command palette generated from the Event VM schema. Commands can be added,
  deleted, duplicated, reordered, and nested recursively under `if`/`ask` branches with
  exact undo/redo, inline validation, canonical Save/Revert, and direct play-test. Authored
  map NPCs/triggers create or open their linked event safely. The Studio gate round-trips
  all 283 Kanto event shapes, authors a branched original-NPC conversation, reopens its TMX
  link under full validation, and observes the intended branch execute in an Engine child.

- **Studio can place gameplay objects and connect authored maps** (gh #55, ADR-025).
  Warp, NPC, sign, and rectangular trigger tools share a typed inspector with stable IDs,
  cell coordinates, event links, and kind-specific fields. A world inspector edits cardinal
  adjacency as one exact reciprocal pair; map and world changes share undo/redo and
  Save/Revert. `MapDocument` targets only its owned Tiled objects while retaining unrelated
  XML, and `WorldDocument` validates reciprocal direction/offset and shared-edge geometry.
  Project validation also rejects dangling map/event references and out-of-range destination
  warp numbers. The Studio gate authors two maps through real controls, reopens them without
  drift, then has a separate Engine child cross their warp and seamless edge.

- **Studio can now create, paint, save, and immediately play-test native maps** (gh #54,
  ADR-024). The map workspace has a project-atlas palette; tile, optional 32×32 Gen-1
  block, erase, and flood-fill brushes; per-cell walkable/solid editing and overlay;
  pan/zoom; grouped map-level undo/redo; validated Save/Revert; and direct launch on the
  active map. `MapDocument` patches only owned Ground/Collision CSV data, retains exact
  no-op bytes, preserves unrelated TMX and TSX content, and allows intentionally mixed
  native cells without discarding coherent block identity. The Studio gate creates and
  edits a scratch map through real controls and verifies its collision in an Engine child.

- **All 223 Kanto maps now ship as native Tiled documents** (gh #53, ADR-023). The
  extractor deterministically emits `maps/*.tmx`, 24 reversible external `tilesets/*.tsx`
  atlases, and `data/world.json`; format-2 projects no longer contain interim map JSON.
  `MapDocument` reconstructs the original block grid and runtime object records while Main
  consumes native cells, collision, ledges, animation metadata, Cut replacements, and the
  world graph. The migration is gated by exact 223-map semantic parity, all-tileset mapping
  and pixel parity, a byte-identical double extraction, Studio and focused behavior suites,
  unchanged battle-determinism hashes, and a complete seeded Hall-of-Fame playthrough.

- **v2 Phase 5's native-map tracer** (gh #52, ADR-021): Project format 2 replaces
  interim `maps/*.json` with a lossless Tiled bridge (`maps/*.tmx` plus external
  `tilesets/*.tsx`) while format 1 stays loadable. The shared `MapDocument` boundary owns
  TMX/TSX parsing, a canonical 16×16 movement-cell grid, per-cell collision, project-local
  atlas loading, typed warp/NPC/sign/trigger objects, stable references, path containment,
  malformed/newer refusal, and a byte-identical no-op save that preserves unknown Tiled
  content. The focused format-2 fixture drives both Main's real placement/collision/atlas
  renderer (`--tmxtest`) and Studio's real preview/save controls (`--studiotest`); their
  64×48 PNG outputs are byte-identical.

- **A durable Studio visual direction and shared theme**, based on the two supplied concept
  boards. Studio now uses the reference's charcoal surfaces, muted type, mint/cyan selection
  language, and centralized control styling. The native map preview establishes the Phase-5
  tool rail + action bar + dominant canvas + inspector/layers composition, including grid,
  collision, and typed-object overlays; ADR-024 extends that surface with authoring tools.

- **Studio's root controls now explicitly fill the native client area.** The earlier gh #59
  window fix removed the Game Boy stretch but retained offsets derived from the old game
  viewport on high-DPI Windows, leaving part of a large native window unpainted. Shell,
  background, and root layout now set both anchors and offsets after parenting; the Studio
  gate asserts the root equals the scaled visible content rect after resize settles.

- **Studio UI scale is now user-adjustable and persistent.** A top-bar slider spans
  80–200% with a more readable 125% default, using Window content scaling so controls,
  spacing, and text reflow together. Map zoom remains independent. The choice is stored in
  `user://studio.cfg`, which avoids unreliable DPI guessing on Windows while keeping low-
  and high-density displays user-controlled.

### Changed

- **The run wrapper now accepts project flags directly.** Commands such as
  `pwsh tools/run.ps1 --studio` and `pwsh tools/run.ps1 --selftest` no longer expose
  Godot's standalone user-argument separator. Existing `-- --flag` invocations remain
  compatible, and direct Godot commands retain their native syntax.

- **README rewritten around both products:** the shipped native port and the active Studio
  toolkit. Setup, current phase status, Studio launch/tracer commands, architecture,
  verification, documentation routes, and the personal-use asset boundary are now visible
  from the repository front page. The personal quotation remains at the end.

### Fixed

- **Studio now refreshes a project rebuilt in place** (gh #63). An editor left open across
  Kanto's format-1-to-format-2 migration previously kept `ProjectData`'s path-only cache and
  refused native maps as legacy until restart. The cache now includes the exact manifest
  bytes, map selection checks it cheaply, and a dedicated gate reproduces the live migration
  before mounting all 223 Kanto maps through Studio.

## [1.2.0] — 2026-07-20

Link session resume — the headline — plus the endgame-unblocking engine/bot fixes that
re-earned the Stage-1 gate on both seeds, and a playable Windows export. The ADR-016
two-stage gate is closed: Stage 1 (the `linkblip.py` injection matrix, ALL GREEN twice
consecutively with every v1.1 suite still green) and Stage 2 (a real remote human session
with genuine Wi-Fi drops, signed off 2026-07-20).

### Added
- **A playable Windows export** (`pwsh tools/export.ps1`): `build/windows/pokeredpc.exe`
  (release template, embedded PCK) with the project data as a loose `project/` folder
  beside the exe — `res://project` is `.gdignore`'d raw data, invisible to Godot's exporter
  by design, so the runtime now falls back to `<exe dir>/project` in exported builds and
  derives its link identity from the project manifest (the same per-part hashes the
  extractor writes to `link_manifest.json`). Verified: the packaged build passes
  `--selftest`/`--victorytest`, and an exported host links a source-run joiner with
  matching content hashes. Personal use only — the export is for playing your own copy
  without the toolchain, never for distribution.

- **Link session resume — a Wi-Fi blip no longer ends the trade or battle** (gh #13,
  ADR-016; the headline of the next feature milestone, v1.2.0). Scope: transport blips —
  both games alive, the socket died. An armed table session now enters a `lost` state
  instead of tearing down: the host keeps listening, the joiner auto-redials with backoff,
  one ~120 s player-cancellable grace clock bounds the outage, and a host-minted session
  token gates re-admission (a stranger or a relaunched process is turned away; relaunches
  keep the teardown + journal story). On resume the peers reconcile per state: a mid-battle
  outage exchanges turn + RNG cursor + digest reports that carry the in-flight action (equal
  points continue, a differing digest at the same point voids stakeless as a determinism
  bug), a pre-commit trade restarts at the pick screens, and a mid-commit trade exchanges
  journal phases where **the max phase wins** — closing ADR-015's documented two-generals
  residue: an ack lost in transit now rolls the behind side forward on reconnection instead
  of stranding the peers on opposite sides of the trade. The dupe easter egg stays
  relaunch-only: resume reconciles honestly even when both peers opted in, so a lag spike
  can never fork a mon. Gated by `tools/linkblip.py` (`--blipat`/`--blipevery` reset the
  ENet transport without killing the process): battle blips on either side and a
  blip-every-2-turns soak end never-void with byte-identical `[battledet]` streams, trades
  blipped at pick/confirm/commit/ack all complete with both saves traded and journals
  cleared, and dupe@ack under a blip does not duplicate. The kill-injection
  (`linkdrop.py`), lockstep (`linktest.py`), and desync-soak suites stay green — the
  lockstep and journal semantics are unchanged; reconcile only reads them.

### Fixed
- **Studio no longer renders its desktop UI through the game's 160×144 viewport** (gh #59).
  The shared Godot project made `--studio` inherit the Game Boy canvas plus 3× viewport
  stretch, magnifying ordinary controls until the project browser was clipped and unusable.
  Studio now disables content scaling before constructing its UI and opens as a native,
  resizable 1280×800 desktop window with a 900×600 minimum; game mode retains its faithful
  160×144 render and 480×432 default window. `--studiotest` locks the two profiles apart.

- **A stage failure inside Victory Road now walks back out for its retry, and `_pt_warp_out`
  can no longer teleport out of a cave** (gh #30). Two recovery weaknesses the gh #28 failures
  exposed: the victoryroad stage's retry loop assumed a whiteout (which lands in a Center) and
  died with a misleading "after a whiteout" message when a failed climb left the bot standing
  *inside* the cave; and `_pt_warp_out`'s LAST_MAP forcing — honest for building doors, which
  physically open onto the town the caller names — would resolve a *cave mouth* to any map the
  caller claimed, warping the bot across the world. The retry loop now retraces the floors'
  down-ladders (explicit warps; boulders reset on re-entry, switch events persist) and exits
  the 1F mouth honestly onto Route 23 before flying home, best-effort — a boulder can genuinely
  seal a pocket, and then the stage fails where it stands, saying so. In a cavern, a LAST_MAP
  exit now walks only when it resolves truthfully to where the bot actually entered from
  (every existing green path already did: Rock Tunnel's mouths really do open onto Route 10).

- **The saffron stage now retries — one transient Celadon walk failure no longer ends the whole
  run** (gh #29). The run's longest unguarded walk (Fuchsia → Lavender → Celadon → the Mart's
  rooftop drink → Route 7's gate → Saffron) was one of two stages the gh #131 hardening pass
  deliberately left without a retry loop because it had passed both seeds — and both of today's
  full gate runs then cashed that "theoretical" gap in, each dying to a transient wander-RNG
  blockage on the Celadon Mart approach (different cells, same class). The stage now runs the
  standard ×3 location-guarded attempt: every leg is skipped once its outcome holds
  (center_label / the drink / GAVE_SAFFRON_GUARDS_DRINK), so a retry resumes from wherever the
  last attempt ended — out of the respawn Center after a whiteout, out of the Route 7 gate or
  the Mart mid-errand, or straight back to the vending machine. `_pt_warp_out` also no longer
  fails silently: it names the map+cell its walk died on, which is the whole diagnosis for a
  wander-RNG blockage.

- **Multi-tile STRENGTH shoves refused their second tile — Victory Road (and the endgame behind
  it) was unreachable** (gh #28). pokered's `TryPushingBoulder`
  (`engine/overworld/push_boulder.asm`) sets `BIT_BOULDER_DUST` the moment a shove starts and
  ignores every further push attempt (`ret nz`, before the sprite lookup or the two-push arming)
  until the dust puff ends (`DoBoulderDustAnimation` → `ResetBoulderPushFlags`) — slide + dust
  are one atomic beat. The port had no such flag: its only lock (`cutscene_active`) began *after*
  the boulder's 0.536 s slide, while the pushing player's own step lands at 0.268 s. In that gap
  the bot's next-tile press armed the two-push counter and its follow-ups then vanished into the
  dust input lock, so tile 2 of every multi-tile push read as refused — stranding the 1F switch
  route at its second shove. (`--victorytest` stayed green throughout: it only ever pushes one
  tile.) The issue's first diagnosis — stale solver routes crossing elevation pairs — was wrong:
  `tools/vr_push_check.py` (now also checking the stairs-destination rule) proves 0 of the
  route's 65 shoves illegal, and the refused tile was $20↔$20. `try_push_boulder` now mirrors
  the flag (`_boulder_dust_pending`, set at the shove, gate first after the STRENGTH check,
  cleared when the dust ends), and the bot waits the beat out between tiles.
- **Three latent navigator traps on the road to the Champion** (gh #27), surfaced by the v2
  Phase-1 gate — the first full seeded bot run since v1.1 shipped, and none is project
  fallout (all reproduce on the pre-flip build). **FLY:** the bot pressed a key *and* called
  the modal's `handle_input()` itself, but `Player._process` already dispatches there every
  frame — so the Town Map cursor advanced twice per press, the FLY cycle only visited
  same-parity entries, and a town on the other parity (Viridian, from Cinnabar) was
  unreachable forever inside an unbounded loop: 54 CPU-minutes of silence. Flying home to
  Pallet hid it completely, because Pallet is the cursor's own starting entry. Modals are
  now driven through the real input path (`_pt_press_modal`), and the loop is bounded and
  fails loudly. **Route 7:** gh #149 made a warp set into a solid
  tile (a gate door in a wall) enterable only from the side that fires it, enforced in the
  step but never modeled by the planner, so every plan west routed through the door and
  every step bumped. **Cinnabar:** the locked Gym door answers a step with a face-up, "The
  door is locked...", and a scripted walk-back — which reads either as an ordinary blocked
  step (walk gives up) or, when it moves the player, as *progress* (walk re-plans the same
  route until its budget dies, silently). The walk now treats an unplanned landing or a
  thrice-refusing cell as a fact about the map and routes around it, like a player who just
  read the sign.

- **The link-battle item refusal is faithful, not a divergence** (correction to the 1.1.0
  notes + ADR-015). Those docs claimed the cartridge allows items in link battles and framed
  the port's refusal as a documented divergence — but `core.asm`'s BagWasSelected guard
  (`LINK_STATE_BATTLING` → `ItemsCantBeUsedHereText`) refuses them on cartridge too. The port
  now mirrors the asm exactly: selecting ITEM in a link battle prints "Items can't be used
  here." and returns to the battle menu without opening the bag (previously it opened the bag
  and refused on use, with invented text). Only link MIMIC's deterministic pick remains a
  documented divergence.

### Added
- **v2 Core: the project-format schemas + validator** (gh #22, ADR-017 — the first v2
  Phase-1 brick): `core/schemas/` holds standard JSON Schema documents for every content
  type plus the `format.json` layout contract (per-record entity files, table singletons,
  interim maps, the reserved `custom` bag, prefixed stable-ID references); `CoreSchema`
  is a subset validator that errors on unknown keywords, and `ProjectValidator` walks a
  project enforcing claims, record-id↔filename identity, reference resolution, and the
  refuse-newer manifest gate. Verified by `--schematest` (fixture suite: valid project
  clean, seven broken variants each exactly one error naming file + path) and
  `--validate=<dir>`. Spec: `docs/v2/project-format.md`.

- **v2 Core: the extractor emits the Kanto project** (gh #24, ADR-017 d6): `build_project()`
  runs as extraction's final stage — pokered clone in, `game/project/` out (1255 files:
  151 species / 165 moves / 152 items / 47 trainers / 15 types / 223 interim maps / 496
  assets). Species records consolidate base stats + learnsets + evolutions + dex + cry +
  icon + sprites; items absorb prices and the TM→move mapping; every cross-reference is a
  prefixed stable string id — positional resolution ends at the project boundary. Verified:
  `--validate` reports **0 errors** across the emitted project (after the validator caught
  2189 real shape mismatches in the first honest round), and two full extractions produce
  **byte-identical trees**. The project root carries `.gdignore`; the tree is git-ignored
  (extracted Nintendo-derived data, personal use, never distributed).

- **v2 Phase 1 complete: the runtime loads a Project** (gh #23/#25, closing #15):
  `manifest.identity` carries per-part content hashes over canonical bytes (13 parts;
  the v1.1 link manifest is now a derived view of it — one identity, computed once), and
  `ProjectData` (Core) serves the engine every data table from the project folder,
  reconstructed into the exact v1 shapes and proven equal by the new `--projparitytest`
  (every table + all 223 maps). The gate stack held: `--battledettest` md5s unchanged —
  after catching one real regression the parity oracle *couldn't* see (dictionary
  iteration order is behavior: Metronome's pick space is the move table's order, so
  move/item/trainer records now carry `num`, the canonical Gen-1 table index) — plus the
  full seeded bot run NEW GAME → HALL OF FAME from the project, the link suites, and the
  audits. `--project=<dir>` points the engine at any project.

- **Cross-platform link, verified** (gh #12): the **engine build joins link identity** —
  `Engine.get_version_info().string` travels in the handshake `hello`, and a differing Godot
  build refuses naming both builds (Godot's RNG and float behavior are only guaranteed
  identical for the identical release; cross-OS builds of one release share the string —
  `--tamper=engine` + a new `linktest.py` scenario drive the refusal). The **toolchain runs
  on Linux/macOS**: `build.ps1`/`run.ps1` and the link test drivers resolve the per-OS Godot
  4.7 binary (`POKEREDPC_GODOT` overrides) and Godot's per-OS user-data dir, and
  `docs/guides/build-and-run.md` documents the other-platforms setup (no exported builds by
  design — each player builds from source). **Cross-OS determinism proven**: the dispatchable
  `determinism` GitHub workflow builds the project from scratch on Linux + macOS runners, and
  both produce battle event streams **byte-identical to the Windows baseline** (all four
  `--battledettest` stream md5s equal), with `linktest.py` (incl. the trade round-trip read
  back from both saves) and `linksoak.py` (8/8 in sync) ALL GREEN on each. The save/journal
  code was audited for platform-dependent path/newline handling: none exists (`user://` +
  single-line JSON throughout). Remaining on gh #12: one live two-machine Windows↔Linux
  session — the cross-OS analogue of the v1.1 Stage-2 human session.

## [1.1.0] - 2026-07-20

**Multiplayer.** The faithful Cable Club — link trades and link battles between two
self-built copies over LAN or direct IP, exactly as ADR-014 designed it: the attendant is
the cable, both engines run deterministic lockstep from a shared seed, trades commit
atomically, and the classic dupe glitch survives as a strictly mutual easter egg.

The ADR-014 two-stage gate is closed: **Stage 1**, the automated suites — `linktest.py`
(session/identity/club/trade/colosseum, byte-identical lockstep streams across two real
instances), `linksoak.py` (the desync soak, 8/8 battles in sync across varied parties),
and `linkdrop.py` (the drop-injection matrix + the dupe egg) — all green repeatedly;
**Stage 2**, a real remote human session (2026-07-19): trades including trade evolutions,
battles in both directions, and genuine disconnects, all functional, with the session's
fix wave (drop tolerance, human-paced waits, room exits, the mon record's explicit maxpp,
partner names and intro presentation) landed and re-verified.

Spec gh #1, sub-issues gh #2–#9 all closed. Deferred: session resume into an interrupted
trade/battle (gh #13), cross-platform builds (gh #12), overworld presence (v1.2 candidate).

### Added
- **The battle determinism oracle** (gh #2): every battle-logic random draw now comes from a
  battle-local seeded RNG with a draw cursor (`Battle._ri/_rr/_rf`), isolating battle outcomes
  from the frame-paced global RNG; every battle emits a canonical per-turn event stream (turn,
  both actions, RNG cursor, md5 state digest) — under ADR-014, byte-equality of two peers'
  streams is the definition of "in sync". `--battledettest` replays scenario battles (trainer
  AI, status, switching, items, multi-turn locks, Transform/Mimic/Metronome, catch/run) twice
  per seed and asserts byte-identical streams, with a different-seed divergence check and
  cross-process-stable per-scenario stream md5s. See `docs/engine/battle.md` "Determinism".

- **The link tracer bullet** (gh #3): `Link.gd` — the one module that touches networking —
  raises a link session between two instances over ENet (LAN/direct IP, two reliable
  channels, polled with no awaits; every wait state times out cleanly). The extractor now
  writes `link_manifest.json` (md5 per link-relevant part: base_stats, moves, types), and
  the link identity handshake (exact version + part hashes) refuses mismatched peers with a
  message naming the differing part, delivered to BOTH sides before a graceful disconnect.
  The dupe easter-egg opt-in travels in the handshake; the session records the mutual AND
  only. `--host` / `--join <ip>` script the connect flow headlessly; `tools/linktest.py`
  drives two-instance scenarios (clean link + round-trip, tampered part, tampered version,
  no-host timeout). See `docs/engine/link.md`.

- **The mon record codec** (gh #4): `MonRecord.gd` maps one exchanged Pokémon between the
  engine's internal dict and the versioned **`mon/1`** wire schema — stable string IDs
  (`species:…`, `move:…`), explicit fields (level, exp, DVs, stat exp, status, moves + PP,
  OT, trainer ID, nickname), the hp DV re-derived Gen-1-style, and stats rebuilt on decode
  rather than trusted off the wire. Unknown schema versions are refused; malformed or
  field-invalid records reject cleanly with the field named. `--monrecordtest` covers four
  round-trip shapes and ~24 bad fixtures single-process. Doc:
  `docs/data-formats/mon-record.md` — the serialized state model v2's Core inherits.

- **The Cable Club attendant** (gh #5): any Pokémon Center's link receptionist now runs the
  full `CableClubNPC` flow — HOST/JOIN/CANCEL standing in for the cable, JOIN typing a
  direct IP on the naming screen's new address mode (digits + dot; the last successfully
  used address is saved and offered as the ED default), handshake refusals surfacing
  in-dialogue naming the differing part, then the asm's script from establishment on:
  the save warning, the save + jingle, the "Please wait." sync, and LinkMenu (first press
  wins, the host arbitrating like the internally-clocked Game Boy) into the special warp
  onto the TradeCenter/Colosseum floor (host (3,4), partner (6,4)). Every wait and dead
  address times out politely back to the attendant. Verified by `--clubtest` and two new
  two-instance `linktest.py` scenarios.

- **The Trade Center** (gh #6): the full link trade — parties exchanged as mon records at
  the table, pick + partner's pick + mutual confirm, a two-phase atomic commit (authoritative
  records exchanged, the pending trade journaled to disk, both acks required before either
  side applies + saves; a drop before completion applies on neither), the in-game trade-movie
  ceremony, nickname/OT/trainer-ID preserved (outsider status feeds the existing boosted-exp
  rule), party-full overflow to the box, and trade evolutions firing on arrival. The club
  rooms got their behavior: the partner's avatar seated opposite, the doormat exit closing
  the link, a dead link walking you back out. The link layer gained an inbox (messages
  arriving before a listener connects are held, not dropped) and the trade protocol consumes
  the partner's steps from ordered queues — both load-race fixes found by the two-instance
  suite. The `linktest.py` trade scenario verifies kadabra ↔ machoke with both trade
  evolutions and both save files read back.
- **Cross-platform link identity** (gh #12, first fix): the extraction manifest hashes
  newline-normalized bytes — text-mode `json.dump` writes CRLF on Windows and LF elsewhere,
  and a Windows↔Linux pair must not refuse over line endings.

- **The Colosseum — lockstep link battles** (gh #7): both peers run the full asm-faithful
  battle engine from a shared seed (fixed by the host at the table), mirrored sims with only
  chosen actions crossing the wire (`col_act`, `col_swap` for faint replacements). Faithful
  to the asm's link special cases: no badge boosts, no hidden 65/256 enemy stat-down miss,
  no EXP, no SHIFT prompt — and the whole battle is stakeless (party snapshot restored, a
  loss is not a whiteout). Speed ties draw the shared coin as "heads = host acts first" so
  the mirrored sims agree; the lockstep oracle's event stream is role-canonical in link mode
  (host side first on both peers) and the `linktest.py` colosseum scenario asserts
  byte-identical streams across two real networked instances. Non-link battles are untouched
  (`--battledettest` stream md5s unchanged). Documented divergences: items refused in link
  battles; link MIMIC copies a deterministic random technique.

- **The desync soak** (gh #8, Stage 1 of the 1.1 gate): `tools/linksoak.py` — one command
  launches pairs of headless instances, runs a battery of seeded link battles across a
  six-party roster (status, multi-turn locks, multi-hit, crits, confusion, Transform/
  Mimic/Metronome, REST; legal fixed DVs; a mirror match that speed-ties every turn) with
  deterministic varied move policies, and gates green only when both peers' event streams
  are byte-identical in every battle — failures name the battle, seed/parties, and first
  differing event. Its first run caught three real lockstep bugs, all fixed: illegal
  fixture DVs, the forced-continuation PP asymmetry, and the one-sided Transform/Mimic
  backup/revert.

- **Drop-injection + the dupe easter egg** (gh #9): `--killat=<point>` simulates a cable
  pull (flushed send, then the process dies) and `tools/linkdrop.py` proves the disconnect
  story — a mid-battle pull is stakeless for the survivor; the trade journal is phased
  (`ready` → roll back, `acked` — written before the ack leaves — → roll forward on the
  next load, silent trade evolution included), so pulls at pick/confirm/commit leave both
  saves untraded and an ack-window pull leaves both traded: no duplication, no loss, at
  every scripted point (the in-transit-ack two-generals residue is documented). The dupe
  easter egg: an asymmetric opt-in refuses the whole session; with both peers opted in,
  the same ack-window pull deliberately reproduces the cartridge's duplication — the
  survivor keeps the copy, the puller's relaunch keeps the original.

- **The host sees their own address** (gh #5 follow-up): while waiting at the attendant,
  the box shows the machine's LAN IPv4 and — via UPnP, asking only your own router — the
  external address, with the UDP port auto-mapped through (and unmapped on close) so an
  internet friend can join without manual port forwarding.

### Fixed
- **"The trade data was invalid!" on real parties** (second playtest): the mon record
  derived each move's max PP from the current move table and refused any saved PP above it
  — a real save's VAPOREON carried BLIZZARD at 30/30 from an older extraction (the table
  says 5) and the whole trade refused. `maxpp` now travels explicitly in the record
  (bounded by Gen 1's 64 ceiling, `pp ≤ maxpp`), the refusal dialogue and `[tc]` log now
  NAME the failing field, and `--recovertest` doubles as a codec probe that round-trips
  every party mon of a save slot and prints any failure.
- **Link-session robustness** (from the first real playtest): a dead link while standing in
  a Cable Club room now walks the player back to the attendant (the closed signal usually
  fired mid-flow and the kick never re-checked — players were stuck in the room); every
  human-paced club wait (partner picking/reading/choosing, the save-beat sync) is bounded
  by link liveness instead of a 30-second timer — the timer expiring while a friend was
  still deciding was the "frequent drops"; ENet's dead-peer tolerance raised to ~60 s of
  silence; the joiner's call auto-redials twice ("No answer — redialing (2/3)..."); a
  machine-paced protocol timeout now actively closes the link; and `host()`/`join()` reset
  stale handshake state so a reused/redialed session can't establish early. Session resume
  into an interrupted trade/battle is filed as gh #13.
- **Healing-machine ball alignment** (gh #11): the right (x-flipped) ball of each pair drew
  one cell right of the machine's slot panel. A negative-width rect flips the texture but
  stays anchored at `position.x` — it does not draw leftward — so the flipped half must
  anchor at its own screen x (48, per `PokeCenterOAMData`), not at `x + width`. The same
  idiom offset every right-facing FLY-bird frame 16 px right of its asm screen coord; fixed
  together. Verified by `--healtest` / `--flytest` shots.
- `--dblkotest` no longer depends on a lucky TAKE DOWN accuracy roll: the double-KO setup
  re-arms and retries until the hit lands.

## [1.0.0] - 2026-07-17

**The 1:1 recreation is complete.** The ADR-011 two-stage gate closed today: **Stage 1**, the
seeded legit-play bot, runs one unbroken process from NEW GAME to the HALL OF FAME (all 21
stages, seeds 1 and 2, `validate_gate.py` GREEN); **Stage 2**, the complete human playthrough,
was signed off after the final bug waves (~60 issues filed and fixed across 0.9.38–0.9.43) and
the full parity-audit campaigns (gh #19–#22, #176, #185) left every system in
`pokered/engine` mapped to a completed audit against the disassembly.

On the tagged commit: the auto-run is green, the selftest suite and both repo audits are green,
and the issue tracker holds **zero open bugs**.

What 1.0 means here: the port plays Pokémon Red end-to-end — every map, script, battle
formula, menu, animation, jingle, and Gen-1 glitch that the audits could reach — natively in
Godot, from extracted data, with no emulation. Deliberately out of scope, as documented:
link-cable play, SGB color palettes (the port is DMG-green), bit-identical RNG, and
raw-memory glitch surfaces (Missingno-class).

Next: the v1.1 multiplayer design conversation, then the v2 fan-game toolkit (ADR-013).

## [0.9.43] - 2026-07-17

The gh #185 batch: the residual-parity inventory — the seven corners of `pokered/engine` the
audit record hadn't covered, each now read against the asm and reimplemented.

### Added
- **The in-game trade movie** (`movie/trade.asm` + `trade2.asm`, `InternalClockTradeAnim`) —
  the port had shown an invented two-line summary. Now: the outgoing mon's info card
  (`──№.<dex>` on the border, name, OT, 5-digit ID) + flipped pic slide in; poof → the ball
  drops with the cry; the open cable end (`SFX_HEAL_HP`); the ball rolls into the cable
  (`SFX_TINK` per step, the bulge cycling); the party icon in the TRADEBUBBLE circle crawls
  the 256px cable between the two GAME BOY screens (the BG flashing `BGP^$3c` every 8 frames);
  the farewell texts; the return crawl; the incoming card + poof + "Take good care of X.".
  The ball animations replay `TRADE_BALL_*` straight from the extracted animation data. The
  surrounding dialog is now `DoInGameTradeDialogue` too: the three dialog sets, the YES/NO
  offer, a real party pick with the wrong-mon refusal, the jingled "traded X for Y!", and the
  NPC's permanent after-trade line. Received mons carry OT "TRAINER" + a random OT ID.
- **The DIPLOMA** (`events/diploma.asm`): the full-screen card (trainer-info border, ●Diploma●,
  "Player <NAME>", the double-spaced congrats text, GAME FREAK) with the title-screen Red
  printed behind it (his title OAM spot +33px, behind-BG priority, `OBP0=$90` one shade
  lighter). The Celadon Mansion game designer awards it at ≥150 owned (Mew discounted).
- **Oak's real Pokédex rating** (`events/pokedex_rating.asm`): the seen/owned completion
  preamble + the 16-tier `DexRatingsTable` texts (the authentic "geting" typo kept), with
  `PlayPokedexRatingSfx`'s owned-band jingle once the text prints. Wired at his PC *and* his
  lab dialog — which now carries the full `OaksLabOak1Text` branch tree, including the
  one-time **5 Poké Ball gift** after the Route 22 rival and "Come see me sometimes.".
- **The MONEY_BOX outside marts**: vending machines, the Daycare fee, the Museum ticket, the
  Safari gate, and the MtMoon Magikarp salesman all show the box through their paid dialogs
  (a new overlay owning the `MONEY_BOX_TEMPLATE` geometry), refreshed right after paying.
- **The boulder-push dust puff** (`overworld/dust_smoke.asm`): the smoke block drifts 1px
  back toward the player ×8 steps, `OBP1` toggling the washed palette per step, drawn
  *beneath* the boulder (OAM 36-39), closed by `SFX_CUT` — and the slide itself now plays
  `SFX_PUSH_BOULDER`, not the generic collision thud.
- **Up+Select+B on the title** (`oak_speech/clear_save.asm`): the clear-save dialogue — NO
  first, YES deletes the save, both reboot the title.

### Fixed
- **CONVERSION was Gen 2's** (retype to the user's first move). Gen 1 copies the *defender's*
  two types onto the user, fails against a mon mid-DIG/FLY, and prints "Converted type to
  <TARGET>'s!" (`move_effects/conversion.asm`).

## [0.9.42] - 2026-07-17

### Fixed
- **The Pokémon Center heal is the real `AnimateHealingMachine`** (the gh #159 follow-up). The
  palette was the missing piece: `OBP1 = $e0` maps colour 1 to WHITE, so the machine's monitor
  renders **lit** and the balls keep their white highlights against the console's dark panel —
  the port drew everything flat-dark (invisible on the panel). The ×8 flash now **swaps the two
  grey planes** (`OBP1 ^ $28`) instead of blinking the sprites out. Restored around it: "OK.
  We'll need your POKéMON." prints with **no button wait** and sits on screen through the whole
  animation (as the reference frame shows); the map music fades out before the first chime; the
  PKMN-healed jingle **plays to its end** before "fighting fit!" (it was cut at ~2s); the heal
  itself runs before the animation; the nurse turns to the machine (`$18`) and **bows** after
  the thank-you (`$14` — the bow graphic lives in her sheet's up-facing slot) before standing
  back up; and "Shall we heal your POKéMON?" only prints on the first-ever Center visit
  (`BIT_USED_POKECENTER`).
- **The mart MONEY box matches `MONEY_BOX_TEMPLATE`.** The label's text tiles now *replace* the
  top border run as on the GB tilemap (the ─ line no longer strikes through "MONEY"), and
  `Menu`'s second money-box implementation — dead code with wrong geometry (box a tile off, the
  amount printed on the bottom border) — is rewritten to the asm spec (tiles (11,0)-(19,2),
  label in the border, the floating-¥ amount ending at tile 18), ready for the flows that
  should show it (vending/Daycare/Museum/Safari gate — tracked in #185).

### Fixed
- **The last stylised battle particles are per-OAM exact** (the gh #22 closeout). Spiral balls
  (Focus Energy/Growth/Amnesia) now trail pokered's `SpiralBallAnimationCoordinates` — three balls
  chasing one another along the 21 real coordinate pairs at 5-frame steps, ending in the authentic
  screen flash; the water droplets (Surf/Mist/Toxic) replay `AnimationWaterDropletsEverywhere`'s
  byte-wraparound arithmetic (64 one-frame screens of drifting diagonal rain); and Razor Leaf /
  Petal Dance run `AnimationFallingObjects` verbatim — the per-object movement bytes, the delta-X
  pendulum flutter, 2px falls, off-screen parking at Y 112, and the lead-object 104 termination.
  One documented divergence: two of Petal Dance's twenty petals overread the delta table into raw
  code bytes on cartridge; the port clamps them to the max delta rather than emulating memory.
- **`--champwalktest`**: the champion-ceremony walk traced cell by cell (the reopened gh #182) —
  the player provably walks *around* the rival on the current build; kept as a regression.

## [0.9.40] - 2026-07-17

### Fixed
- **The stat pipeline is exact to pokered's stored-stat model** (gh #176 phase 2). The battle
  stats now live in per-side stored dicts mutated event-by-event like `wBattleMon*` RAM, which
  makes the whole Gen-1 stat-glitch family real. **The badge→stat map was wrong on three of four
  stats**: `BadgeStatBoosts` goes by the badge byte's even bits — Boulder→Attack,
  **Thunder→Defense, Soul→Speed, Volcano→Special** (Cascade boosts nothing) — the port had the
  intuitive gym order (Cascade→Def, Thunder→Spd, Soul→Spc). Also restored: **the badge-boost
  stacking glitch** (every stage change on the player's mon re-applies ×9/8 to all four stored
  stats, compounding), **the penalty-compounding glitch** (every stat move re-quarters/re-halves
  the non-acting side's paralysis/burn penalties on top of the stored value), **curing a status
  doesn't restore the stat** (it stays quartered/halved until a recalc or switch), crits read the
  truly unmodified stats (**no badge boosts** — the snapshot predates them), a stat-up on a
  stored 999 (and a stat-down on a stored 1) fails with the stage rolled back, the ENEMY's pure
  stat-down moves carry their hidden **65/256 miss**, and a mid-FLY/DIG target can't be
  stat-lowered. Transform copies the stored stats; HAZE rebuilds both sides.

## [0.9.39] - 2026-07-17

### Fixed
- **Trainer AI is exact to `trainer_ai.asm`** (gh #176 phase 2). The move-choice layers and all
  47 classes' extracted `ai`/`ai_count`/`ai_mods` data were verified already at parity; the
  execution had five divergences. **The AI's type read is now `AIGetTypeEffectiveness`'s
  first-matching-entry lookup**, never the composed multiplier — ELECTRIC into a WATER/FLYING
  target reads 2×, not the real 4×, exactly as the AI misjudges on cartridge. The item/switch
  thresholds were off by one (`25 percent + 1` is r < 65, `50 percent + 1` is r < 129). The
  handler now rolls **unconditionally** before the enemy's move (the asm has no lock gate — a
  wrapping or mid-FLY trainer mon can still potion, its multi-turn state resuming after).
  **Switches no longer consume the `wAICount` budget** (`SwitchEnemyMon` never decrements — only
  items spend it), and the invented safety guards are gone: Blaine really does waste SUPER
  POTIONs at full HP and a maxed X item still costs its use and the turn ("Nothing happened!").
  A successful AI X SPEED/X ATTACK also wipes the paralysis/burn stat penalty, like any stage
  recalc. Confirmed faithful: the per-mon `wAICount` reset at every send-out, CooltrainerF's
  missing-`ret` fall-through, Brock's roll-free FULL HEAL, and the Mod 1/2/3 layer semantics
  with the exact Mod-2 effect ranges.

## [0.9.38] - 2026-07-17

### Added
- **Tile-pair (elevation) collisions in caves and forests** (gh #105, #128). Faithful to pokered's
  `CheckForTilePairCollisions`: you can no longer walk straight across the ledge/step boundaries that mark a
  change in elevation (Rock Tunnel, Mt. Moon, Victory Road, Seafoam — CAVERN floor↔ledge pairs, and the
  water↔shore pairs while surfing). Boulder pushes obey it too, exactly as the game does
  (`CheckForCollisionWhenPushingBoulder` compares the player's tile to the boulder's destination and refuses
  a shove across an edge or onto stairs), so STRENGTH isn't a way around it. The caves are now genuinely
  partitioned into ladder-linked pockets; Victory Road in particular becomes the real multi-floor
  boulder/switch/hole puzzle it always was.
- **Teaching a TM/HM shows who can learn it** (gh #125). When you use a TM or HM and pick a POKéMON, the
  party screen now prints **ABLE** / **NOT ABLE** beside each mon (replacing the HP bar, as in Gen 1's
  `TMHM_PARTY_MENU`), so you can see the compatible recipients at a glance.
- **CUT now plays the overworld tree animation** (gh #123). Cutting a tree removed it instantly; pokered
  animates it first — `UsedCut` → `AnimCut` squeezes the tree's two halves together over 8 frames with the
  cut sound, then the block is replaced. The port now plays that collapse before the tree disappears.

### Changed
- **`wavy_screen` (Psychic / Confusion / Psywave / Night Shade) is now the faithful raster wave.** It was a
  whole-screen sine shake; pokered's `AnimationWavyScreen` freezes the screen and shifts each *scanline*
  horizontally by a small ±2px table (`WavyScreenLineOffsets`), the wave advancing one row per frame. The port
  now captures the battle frame and redraws it row-by-row with that exact table, so the screen ripples per
  line as on the cartridge. (The frame capture is headless-guarded so it can't softlock a headless run.)
- **The turbo playtest key (hold Space) now fast-forwards battles too.** Previously it sped up only free
  overworld movement — it was suppressed during every modal after a catch-ceremony soft-lock (gh #111). It
  now also runs during a battle (4× attack animations, HP-bar drains, and auto-advancing battle text; input-
  gated battle menus just wait for you), which makes grinding and trainer fights far quicker for a human
  playthrough. It stays at normal speed during cutscenes and non-battle modals — overworld/sign text, the
  start/bag menus, and the catch ceremony's dex-entry / nickname / naming-keyboard screens — so the gh #111
  input race can't reappear (verified: the catch-ceremony regression completes with turbo held throughout).

### Fixed
- **Status and volatile machinery are exact to `CheckPlayerStatusConditions`** (gh #176 phase 2).
  The turn-start gate now runs in the asm's order — sleep ticks **before** flinch (a sleeping,
  flinched mon used to keep its sleep counter frozen) and confusion **before** paralysis (the
  confusion counter ticks even on a fully-paralyzed turn). Restored with it: the **Gen-1
  penalty-wipe quirk** — PAR's Speed ÷4 and BRN's Attack ÷2 are baked into the stat, so any
  stage recalc of that stat silently drops them (AGILITY genuinely cures a paralyzed mon's
  slowness); re-armed on infliction, switch-in, and mid-battle level-ups. The confusion self-hit
  now uses the integer damage chain against the mon's own **stage-modified** Defense (was a raw
  float formula) at the asm's exact 127/256 odds; full paralysis and a self-hit **break
  charge/Bide/thrash/trapping locks** (an interrupted FLY/DIG reappears instead of staying
  charged forever, and a Wrap victim goes free). Residual poison/burn/LEECH SEED now tick
  **after each side's own action** in act order (per `HandlePoisonBurnLeechSeed`) rather than at
  end of turn — skipped when that action ended in a faint — and the toxic counter multiplies
  (and advances) on the **Leech Seed drain too**, the documented Leech Seed glitch. Thrash's
  ending confusion is 2–5 turns (was 2–4). Already exact: sleep 1–7 with the waking turn lost,
  freeze semantics, the side-effect bytes and same-type immunity, toxic ×counter, 1/16-min-1
  residuals.
- **Wild encounters are exact to `TryDoWildEncounter`** (gh #176 phase 2). Three mechanics were
  missing or wrong: **REPEL was a blanket off-switch** — pokered runs the roll and hides only wild
  mons **below the first party slot's level** (an equal-or-higher one still jumps you), prints
  "REPEL's effect wore off." on the expiry step (which can't encounter), and doesn't tick during
  the cooldown; the **3 battle-free steps after every battle** (`wNumberOfNoRandomBattleStepsLeft`,
  re-armed by a warp mid-cooldown) didn't exist; and the rate/table now key off the asm's two
  tiles — rate from the half-block's bottom-RIGHT tile, table from the bottom-LEFT — which makes
  Route 21's left-shore column genuinely serve **grass-table mons (TANGELA) at the water rate
  while surfing**, the only legitimate surface of the "left shore" quirk (Route 19/20's version
  reads stale memory in pokered — glitch territory the port deliberately rolls as no encounter).
  The rate and slot rolls were verified already-exact (`rand < rate`, the cumulative-1 slot
  thresholds 51/51/39/25/25/25/13/13/11/3), as were the warp-tile suppression and the
  indoor/FOREST rule.
- **Experience and stat exp are exact to `GainExperience`** (gh #176 phase 2). Two boosts were
  missing outright: a **trainer battle gives ×1.5 EXP** and a **traded mon (foreign OT) gives ×1.5**,
  and the two **stack** (`BoostExp` = `q + floor(q/2)`) — the port awarded flat wild-rate EXP in
  every trainer fight. **Stat exp** now divides by the number of participants and halves under
  EXP.ALL, matching `DivideExpDataByNumMonsGainingExp` and the up-front halve (it used to hand every
  participant the full base stat); the EXP split now floors `base_exp / N` **before** the `×level/7`,
  as the asm does, and the stored EXP is capped at the level-100 value. (Stat-exp accumulation
  itself was already present and folds into the stats via `CalcStat`'s sqrt term.)
- **Catching is exact to `ItemUseBall`** (gh #176 phase 2). The wobble count on a failed throw now
  uses the X the asm does: **`min(W, 255)` — the HP factor — is computed *before* the catch-rate
  comparison**, so it is what `.failedToCapture` reads whichever stage failed; the port substituted
  the raw catch rate on a rand1-stage failure, wobbling wrong on most misses (a rate-45 full-HP
  GREAT BALL failure wobbles once, never zero). The capture rolls themselves were already exact
  (spans 255/200/150, status shaves 25/12 with underflow = certain catch, the W/Y/Z chain, the
  10/30/70 shake bands), as were the safari bait/rock factors. Also restored around the throw:
  a trainer **keeps the thrown ball and the turn passes** ("The trainer blocked the BALL!" /
  "Don't be a thief!" — the asm exits via `RemoveUsedItem`, not `ItemUseFailed`); balls thrown at
  the unidentified GHOST **dodge** instead of running a real capture calc (it could genuinely be
  caught before), with the authentic "It dodged the thrown BALL! This POKéMON can't be caught!"
  for the unveiled MAROWAK too; a full party + full box **refuses the throw** outright (no ball
  spent, no turn); catching a **transformed** wild mon assumes DITTO (pokered's noted bug — fresh
  DITTO data, DVs/HP/status carried); and the **POKé DOLL works in ghost battles** again, including
  the documented trick — a doll escape leaves `wBattleResult` at 0, so the Tower script counts the
  MAROWAK as laid to rest. Texts now match the ROM: "All right! <MON> was caught!", "transferred
  to BILL's PC!" (or "someone's PC!" before meeting BILL), "New POKéDEX data will be added for
  <MON>!".
- **The damage formula is integer-exact to `CalculateDamage`** (gh #176 phase 2). The big one: a
  **pure-type defender took squared type multipliers** — the port multiplied both stored type slots
  (`[GRASS, GRASS]`), so every super-effective hit on a single-typed Pokémon landed 4× and every
  resisted hit 0.25×; pokered applies each `TypeEffects` table entry once. Also restored from the
  asm: the floor-at-every-step integer chain (`(2L)/5` floors before multiplying), the 997 damage
  cap (999 with the +2), the both-stats **/4 scaling** when either exceeds 255 (high-level damage
  now loses the same precision the GB does), EXPLOSION halving defense, stat stages applied as
  pokered's n/100 ratios clamped to [1, 999], sequential per-entry type flooring, and the
  damage-floored-to-0 → **miss** quirk (the port used to force a minimum 1).
- **PP UP can no longer be sold** (gh #176). Gen 1's real PP UP is priceless (`ItemPrices` 0, like
  the Ethers and Elixers); the port had inherited ¥9800 from the *glitch duplicate* item slot that
  shares its display name, making it sellable for ¥4900. The clerk now also refuses priceless items
  with the authentic "I can't put a price on that." instead of a silent buzz.

### Added
- **`tools/audit_parity.py`** (gh #176 phase 1): an independent re-parse of pokered's
  gameplay-critical data diffed against what the port consumes — the type chart, all 165 moves,
  TM/HM assignments, all 151 species' stats/types/catch/exp/learnsets/growth/TM-compatibility,
  evolutions and level-up movesets, all 47 trainer classes' parties and payouts, every wild
  grass/water table with rates and slot odds, item prices, mart stock, hidden-item coordinates,
  and the in-game trades. **Everything is at parity** (one finding, fixed above). Also proved the
  roadmap's "water-table extractor gap" note stale — the tables were complete.

### Fixed
- **The player walks AROUND the rival to the Hall of Fame** (gh #182). The reporter was right and
  the earlier "authentic pass-through" ruling was wrong: pokered's simulated joypad consumes its
  list **from the end down**, so every RLE walk plays in reverse of its declaration.
  `WalkToHallOfFame_RLEMovement` (UP×4, LEFT×1) really executes LEFT first — the player sidesteps
  and follows Oak up the left column onto the (3,0) door. The champion-room entrance walk reversed
  the same way.
- **Team Rocket leaves Silph under the fade** (gh #158). Beating Giovanni now plays
  `SilphCo11FGiovanniAfterBattleScript`'s choreography: his "you ruined our plans" line, a fade to
  black, the ShowObject/HideObject sweep (Giovanni *and* this floor's two rockets vanish — new
  `Main.refresh_objects()` re-evaluates mid-scene instead of waiting for a reload), a beat, and a
  proper `GBFadeInFromBlack` (new `Transition.fade_in_black`). He used to just pop out of
  existence with the floor's rockets still standing around.
- **Credits silhouettes sit and move like the original** (gh #183). `DisplayCreditsMon` places the
  7×7 pic buffer at tile (8,6) with small pics bottom-aligned and centred inside it — the standard
  Gen-1 pic alignment — and `ScrollCreditsMonLeft` zips the silhouette one 8-px tile per frame
  (~480 px/s). The port top-left-anchored the cropped pics (small mons floated high-left) and slid
  them four times too slowly.
- **Warp arrivals step out through doors — including elevator doors** (gh #142). pokered's
  `PlayerStepOutFromDoor` runs on every tileset with door tiles (`door_tile_ids.asm`): arrive from a
  warp standing on one and the game walks you one step down off the doorway. The port only did this
  outdoors, so leaving the Celadon Mart or Silph Co elevators dumped you standing in the doorway
  instead of walking you onto the floor — and the Rocket Hideout's dark stair-doorways didn't step
  either. Fallout fixed with it: the playthrough bot's planner now knows a fire-on-step warp cell is
  a wall mid-route (stepping on one always leaves the map), the hideout elevator's panel is worked
  from the car floor (the old spot stood on a now-armed door mat), and a direct `place()` onto a
  warp no longer leaves it stale-armed (the `--b4f` harness had been teleporting itself up the
  stairs on its first keypress for that reason).
- **NIGHT SHADE deals its damage** (gh #181). It's pokered's one zero-power move that damages, and
  the port classified moves by the power byte — so NIGHT SHADE fell into the status-move path and
  did nothing. The effect now decides (as `core.asm` branches on `SPECIAL_DAMAGE_EFFECT` before its
  zero-power skip): level damage, with the Gen-1 quirk intact — fixed damage still obeys type
  immunity, so NIGHT SHADE genuinely does nothing against NORMAL-types.
- **CONTINUE after the Hall of Fame resumes in Pallet Town** (gh #184). The save is written on the
  HoF floor, but pokered's continue path special-cases it: `wCurMap == HALL_OF_FAME` with a team
  recorded fly-warps the player to Pallet Town (`main_menu.asm` → `PrepareForSpecialWarp`). The
  port resumed you on the HoF floor — with no way out, since the room below resets for a rematch.
- **Overworld item use matches `ItemUsePtrTable`** (gh #175). The COIN CASE now reports your coin
  balance (that's all it does out of battle), OAK's PARCEL refuses with its own "This isn't yours
  to use!", and everything genuinely unusable — balls, X items, key items — funnels into OAK's
  "This isn't the time to use that!"; the invented "Can't use that here!" line is gone.
- **The S.S. Anne departure leaves what the GB leaves** (gh #118). The erase now mirrors
  `VermilionDock_EraseSSAnne` literally: only the ship's lower row becomes water, and the upper
  deck row stays in the map — the real scene keeps the deck remnant above the water, and Gen 1
  keeps the whole ship in the map data forever (re-entering the dock later shows it docked, an
  authentic documented quirk the port now shares). A new playable `--dockscene` flag jumps
  straight to the departure for inspection.
- **The Pokédex looks and handles like the original** (gh #152). Contents: holding DOWN/UP now
  auto-repeats (the low-sensitivity joypad re-fires a held direction every 6 frames), LEFT/RIGHT
  page the window by 7, and the list neither draws nor scrolls past the highest *seen* dex number
  (`wDexMaxSeenMon`) — plus the screen now uses the dex's own extracted tiles: the vertical rail is
  the real `$71` line with `$70` box knobs, the SEEN/OWN ÷ DATA separator is the font's `─` double
  line, owned mons get the actual `$72` ball tile, and unseen rows print pokered's ten-dash string.
  Data screen: the page cursor blinks on the textbox cadence, and the row-9 divider and the whole
  border are the authentic tile runs (`PokedexDataDividerLine` and the `$63-$6f` frame) instead of
  hand-drawn approximations.
- **Party icons rest on the right animation frame** (gh #153). `data/icon_pointers.asm` isn't
  uniform, and the extractor had assumed it was: the MON, FAIRY, and BIRD icons rest on their
  **walk** frame and swap to standing when selected (the SEEL is the other way round), and the BUG
  and GRASS icons rest on their sheets' *second* frame. Five icon types were showing the wrong
  resting pose and flapping backwards. The selected icon's flap also runs at the exact DMG speeds
  now (6/17/33 V-blanks per frame by HP color — pokered adds one V-blank off the SGB).
- **The save screen matches the original** (gh #156). The "Would you like to SAVE the game?" prompt
  is a normal full-size textbox again (it was squeezed into a 4-row box with single-spaced lines);
  the play time is right-anchored the way `PrintPlayTime` prints it (hours right-aligned at column
  13-15, the colon at 16, zero-padded minutes at 17-18); the YES/NO box sits at pokered's (0,7); and
  confirming now runs the real save beat — "Now saving..." alone in the textbox for 120 frames, then
  "<PLAYER> saved the game!" with SFX_SAVE.
- **Menu cursors are the font's real ▶ glyph** (gh #154). Every boxed menu (the start menu, the
  party STATS/SWITCH/CANCEL popup, marts, yes/no boxes, the slot machine) drew its cursor as a small
  hand-made triangle polygon; they now render the font's own `▶` tile (`$ed`), which is a pixel
  wider, taller, and shaped like the original. Battle menus already used it.
- **The HP bar's fill is the right shade** (gh #155). The party screen and the status screen filled
  the bar with the same near-black as its outline; the real fill is GB shade 2, one step lighter —
  `font_battle_extra.png`'s full-segment tile (`$6b`) fills its middle rows with 2bpp colour 2 under
  the identity `BGP $e4`. The battle HUD already used the correct shade; both other paths now match it.
- **The Pokémon Center's healing balls land on the machine** (gh #159). The animation drew the
  monitor and the six balls a cell too low and 8px right — strung down the counter front instead of
  in the machine's slot panel. `PokeCenterOAMData`'s values are raw OAM hardware coordinates, which
  carry built-in offsets (+8 x, +16 y); the port had used them as screen positions. The balls also
  now draw dark, as `OBP1 = $e0` renders them.
- **FLY has its overworld animation** (gh #144). Picking a destination cut straight to a fade; now
  the BIRD replaces the player sprite exactly as `player_animations.asm` stages it: it flaps in
  place, SFX_FLY rings, it swoops off toward the top-right, holds a beat, then crosses back high
  across the sky right-to-left into the fade — and on arrival the map fades in first, then the bird
  dives in from the top-right down onto your tile before Red reappears and the town theme starts.
  The three screen-coordinate paths are pokered's own (`FlyAnimationScreenCoords1/2`,
  `FlyAnimationEnterScreenCoords`), 1:1 because the port keeps the GB camera framing.
- **Running out of SAFARI BALLs ends the Safari game** (gh #180). You could keep walking the park
  at 0 BALLs indefinitely — a state the original can't be in. Now the last BALL ends the encounter
  on the spot ("PA: Ding-dong! You are out of SAFARI BALLs!", `core.asm` `.outOfSafariBallsText`) —
  whether it caught or not — and back on the overworld the game-over ceremony ejects you to the gate,
  exactly as `SafariZoneCheck` does every overworld iteration. The invented in-menu "You have no
  SAFARI BALLs!" line (which exists nowhere in pokered, and whose state is now unreachable) is gone.
- **The post-Champion ceremony is the real one** (gh #179). Beating the rival jumped straight to the
  team showcase and credits with Oak's lines floating in from nowhere, and after the credits you were
  left standing in the Champion's room. The full sequence now plays out (`ChampionsRoom.asm` +
  `HallOfFame.asm`): the rival's two defeat texts; **OAK walks in** — his "OAK: RED!" sounds from the
  door, he appears and walks up beside you, congratulates you naming your **starter** (not the rival,
  as the port had it), turns on the rival and scolds him, says "Come with me!" and exits north; you
  follow him **into the Hall of Fame room** and up to the machine for his Er-hem speech; the team is
  recorded and the credits roll. And afterwards, what Gen 1 actually does: the League resets for a
  rematch (champion included), your blackout point becomes Pallet Town, **the game saves itself**,
  THE END holds until a button press, and the boot replays back to the **title screen** — CONTINUE
  resumes on the Hall of Fame floor. Oak also no longer materializes at the Champion's-room door on
  every later visit (his toggle object ships hidden; the ceremony shows and hides him).
- **The Safari battle menu is the real one** (gh #169). The port crammed BALL/BAIT/ROCK/RUN into the
  standard right-half battle menu box (BAIT rode the border) and invented a "SAFARI BALLx28" counter
  floating mid-screen over the player's back sprite. The real `SAFARI_BATTLE_MENU_TEMPLATE`
  (`data/text_boxes.asm`) is **one full-width box** reading `BALL×nn     BAIT` / `THROW ROCK  RUN`,
  with the ball count printed *inside the menu* right after `BALL×` (core.asm `.safariLeftColumn`
  `PrintNumber`s it at tile 7,14) and the cursor in columns 1/13 — there is no separate counter
  anywhere on the safari battle screen, and no player HUD (no mon is out).
- **Surfing shows the surfing sprite** (gh #170). Hopping onto the water left you as walking Red;
  the player now rides the SEEL — which is Gen 1's actual surfing player sprite
  (`LoadSurfingPlayerSpriteGraphics` loads `SeelSprite`) — and stepping ashore swaps the walking
  sheet back on the spot, as `.stopSurfing`'s `LoadPlayerSpriteGraphics` call does. Same mechanism
  as the BICYCLE sheet (gh #161), now a three-way keyed off pokered's `wWalkBikeSurfState`; a warp
  that clears surfing or biking also reloads the sheet immediately instead of one input later.
- **The Safari Zone announces time's up before it throws you out** (gh #171). Running out of the park's 500
  steps teleported you to the gate on the spot, then talked at you once you were already standing there. In
  pokered the eject is the *last* beat, not the first: `SafariZoneGameOver` rings the PA jingle
  (`SFX_SAFARI_ZONE_PA`), reads "PA: Ding-dong! Time's up!" and "PA: Your SAFARI GAME is over!" out while
  you're still in the park, and only then sets `wSafariZoneGameOver` — the flag that makes `OverworldLoop`
  take the warp. The whole arrival was missing too: you now land at the gate's park-side door facing down,
  the worker asks "Did you get a good haul? Come again!", your SAFARI BALLs go back, and he walks you three
  steps south out of the park (`SafariZoneGateLeavingSafariScript`). "Time's up!" is correctly skipped when
  you've already used every BALL.
- **Route 23's badge-check guards inspect your badge and wave you through** (gh #178). The checkpoints only
  ever showed the "you don't have the X yet" block; pokered's `Route23DefaultScript` also runs the *pass*
  case — the first time you reach a checkpoint holding its badge, the guard says "Oh! That is the [X]! OK
  then! Please, go right ahead!" and records `EVENT_PASSED_<badge>_CHECK`, so he won't stop you again. Both
  branches (and the once-only pass event per checkpoint) are now implemented; the guard sprites were already
  present.
- **An NPC walking up to you stops alongside, not on top of you** (gh #177). `walk_forward` only halted at a
  wall, so the Route 22 rival (before Victory Road / the Elite Four) walked its scripted approach straight
  onto the player's tile. It now stops on the tile beside the player, as pokered's movement halts on a
  sprite in the way — a general fix for any scripted NPC approach.
- **Cinnabar Gym quiz gate 6 now answers "No"** (gh #173). "TM28 contains TOMBSTONER?" was marked YES-correct;
  TM28 is DIG, so the statement is false and NO is correct — matching pokered's answer table
  (`data/events/hidden_events.asm`, `(TRUE << 4) | 6`). The other five gates were already right.
- **Three battle items that did nothing now work** (gh #175). DIRE HIT, GUARD SPEC., and POKé DOLL fell
  through to "It won't have any effect." They now behave as in pokered: **DIRE HIT** sets the Focus Energy
  crit bit ("getting pumped"), **GUARD SPEC.** shrouds the mon in MIST (blocking the opponent's stat-lowering
  moves), and **POKé DOLL** distracts a wild POKéMON so you flee for sure (and is useless against a trainer).
- **NPC gift items now respect the 20-slot bag limit** (gh #174). Gym-leader TMs, HMs, key items (TOWN MAP,
  COIN CASE, BIKE VOUCHER, the three rods, POKé FLUTE, MASTER BALL, S.S.TICKET), the Mt. Moon fossil, the
  Nugget Bridge NUGGET, and Game Corner TM prizes were written straight into the bag, ignoring capacity —
  so you could receive a TM from a gym leader (or anything else) with a full bag. Faithful to pokered's
  `GiveItem` → `.BagFull` branch: a full bag now shows a no-room line and withholds the item without setting
  its `GOT_` event, so the giver re-offers once you make room (the gym badge, and story sequences like the
  Nugget Bridge battle, still proceed). Trades that free a slot first (GOLD TEETH→HM04, BIKE VOUCHER→BICYCLE)
  and OAK's PARCEL (received with an empty bag) can't overflow and are unchanged.
- **You can no longer walk onto a warp set into a solid tile** (gh #149). `is_walkable` treated *every*
  warp tile as passable so you could step onto doors — but that let you walk straight onto a gate door
  embedded in a wall (e.g. Route 7's (11,9)) from the side and just stand on it, since the warp only fires
  from the approach you enter by. pokered's `CollisionCheckOnLand` blocks a solid tile whether or not it
  carries a warp; you enter such gates via the adjacent walkable mat. The player step now bumps on a solid
  warp unless the step would actually fire it (`ExtraWarpCheck`). Swept all 14 solid-collision warps in the
  game: the Route 6/7/16 gate doors are the fixed cases; the Elite Four room exits, Seafoam floor-holes, and
  gate-house edge exits fire from their approach and are unaffected (verified end-to-end).
- **The locked Cinnabar Gym door blocks you before you step onto it** (gh #172). Without the SECRET KEY
  the port let you walk right onto the Gym door and only then bounced you back off the warp. pokered's
  `CinnabarIslandDefaultScript` blocks a tile earlier: standing on the street tile below the door (18,4)
  faces you up, prints "The door is locked...", and walks you back down one tile (a `MovePlayerDownScript`),
  so you never reach the door itself — the same idiom as Viridian's shut Gym and the Route 23 badge gates.
- **Two-turn charge moves spend PP on the execution turn, not the charge turn** (gh #168, follow-up to
  #160). FLY / DIG / SOLARBEAM / Sky Attack decremented PP when they started charging; pokered's
  `DecrementPP` runs only after `CheckPlayerStatusConditions` passes on turn 2 (`PlayerCanExecuteChargingMove`
  → `…Move`). So a charge disrupted mid-air — full paralysis, a confusion self-hit — now wastes no PP, as in
  Gen 1. RECHARGE (Hyper Beam) and the Bide/Thrash/Rage continuations still correctly spend none.
- **A double KO now faints both mons** (gh #112). When both Pokémon dropped to 0 HP on the same turn
  (a recoil move like TAKE DOWN KO'ing the target and recoiling the user to 0, EXPLODE/SELFDESTRUCT, or
  end-of-turn poison/burn), `_end_of_turn` fainted only the enemy and left the player's 0-HP mon active —
  in a trainer battle it could still pick a move the next turn. Faithful to pokered's
  `HandleEnemyMonFainted`, which also removes a co-fainted player mon (`RemoveFaintedPlayerMon`): the
  player is now forced to send out a replacement (or, if that empties the party, blacks out — you lose
  even though you KO'd the enemy, the `AnyPartyAlive` → `HandlePlayerBlackOut` quirk).
- **The Silph Co 7F rival no longer walks through you** (gh #151). His approach used a BFS path that
  could route through the player, and he always exited straight right. pokered (`SilphCo7F.asm`)
  walks him straight up column 3 to just below you (`RivalMovementUp`), then exits by
  `RivalExitRightMovement` (RIGHT×2) if you triggered from (3,3) or `RivalWalkAroundPlayerMovement`
  (LEFT, UP×2, RIGHT×3, DOWN) — stepping around you — if from (3,2). Both are now reproduced.
- **The Pokémon Tower rival leaves by his real path** (gh #145). After the 2F battle the rival walked
  straight down and vanished; pokered (`PokemonTower2F.asm`) sends him on an L-shaped route to the 2F
  stairs, chosen by which side he was on — the player at (15,5) means he's on the left
  (`RivalDownThenRight`: DOWN×2, RIGHT×4, DOWN×2), at (14,6) the player is below him
  (`RivalRightThenDown`). He now walks that path to the stairs (18,9) before disappearing.
- **The "which move to forget?" box matches the real layout** (gh #137). When a mon must forget a
  move (e.g. teaching an HM/TM), the port drew the four moves as a generic menu in the top-right;
  pokered's `WhichMoveToForget` (`learn_move.asm`) puts a 14-wide box at tile (4,7) with the moves
  single-spaced at (6,8) and the cursor at (5,8). The box is now placed and spaced faithfully.
- **CUT tree animation timing audited** (gh #138). The overworld cut squeeze now matches `AnimCut`
  exactly: the two halves close cumulatively to ±8 px over 8 frames at one DelayFrame (1/60 s) each
  (was ±7 px at 1.5/60 s). The GB's per-frame `rOBP1` palette flicker is the one part the true-colour
  port can't reproduce without a shader.
- **Cycling Road forces you onto the bike** (gh #166). Faithful to `CheckForceBikeOrSurf` /
  `ForcedBikeOrSurfMaps`: stepping onto the Cycling Road entrances (Route 16 (17,10)/(17,11), Route 18
  (33,8)/(33,9)) silently mounts the bike and sets `BIT_ALWAYS_ON_BIKE`, which persists across the
  Route 16/17/18 connections; you can't dismount until a Cycling Road gate clears it. Previously you
  could walk the whole road.
- **Fly/Dig now make the user semi-invulnerable** (gh #160). During the charge turn a mon that used
  FLY or DIG is out of sight, and in Gen 1 attacks against it miss — only Swift can hit it (Bide's
  stored-damage release bypasses accuracy). The port already charged, locked the move and hid the
  pic, but the opponent still connected normally; damaging moves now miss a mid-Fly/Dig target unless
  they're Swift (pokered `MoveHitTest`, INVULNERABLE bit).
- **The Silph Co 9F healer no longer runs the Poké Center machine ceremony** (gh #150). Its NPC is a
  "nurse" sprite, so the port ran the full healing-machine animation; pokered's `SilphCo9FNurseText`
  instead heals silently with a white flash ("You look tired!" → heal → fade → "Don't give up!"),
  and only thanks you (no heal) once Giovanni is beaten. The SilphCo9F adapter now intercepts it.
- **The battle status badge no longer appears before its message** (gh #164). The HUD's status
  badge (SLP/PSN/PAR/BRN/FRZ) used to flip the instant the effect was computed, because the port
  builds a whole turn's messages up front while the HUD drew the live status — most visibly with
  **REST**, where you'd "fall asleep" before the move resolved. The badge is now decoupled into a
  `_shown_status` mirror (like the HP bar's `_shown_hp`) that flips only when its message plays, and
  re-syncs on send-in; covers inflicted status, wake-up, freeze-thaw, and item/AI cures.
- **Pokémon Tower 5F's purified zone now heals your party** (gh #147). Faithful to
  `scripts/PokemonTower5F.asm`: stepping onto the four "purified, protected zone" tiles
  ((10,8)/(11,8)/(10,9)/(11,9)) silently restores the party (HP + PP + status), flashes the screen
  white, and shows "Entered purified, protected zone!" — and suppresses wild battles while you stand
  in it, re-arming once you step out. The port had no 5F map adapter, so the tiles did nothing.
- **FLY now opens the Town Map, not a text list** (gh #143). Faithful to pokered's `LoadTownMap_Fly`
  (`engine/items/town_map.asm`): using FLY shows the Kanto map with a cursor that cycles only through the
  towns you've visited, a "To ⟨TOWN⟩" label along the top, A to fly and B to cancel — instead of the plain
  name menu the port had. (The bird-sprite cursor, the current-location marker, and the fly-off animation
  remain deferred to gh #144.)
- **Playthrough wave 4** (gh #139, #157):
  - **The Game Corner poster Rocket engaged without his line** (gh #139). His text is a map script
    (`GameCornerRocketText`), not a trainer header, so the port had no `battle_text` for him. He now says
    "I'm guarding this poster! Go away, or else!" before battling (same pattern as the Cerulean/Nugget-Bridge
    Rockets) — verified against `_GameCornerRocketImGuardingThisPosterText`.
  - **The Silph Co Lapras looked ungiven with a full party** (gh #157). pokered's `GivePokemon` sends it to
    the PC when the party is full and prints `_SentToBoxText`. The port gave it silently; the follow-up
    message now matches that text — "There's no more room for POKéMON! LAPRAS was sent to BILL's PC!" (the
    single-box port drops pokered's numbered "BOX N") — instead of the earlier bare "sent to BILL's PC!".
- **Playthrough wave 3** (gh #161, #162):
  - **The player kept the walking sprite on the bicycle** (gh #161). pokered has a dedicated bike sprite
    (`gfx/sprites/red_bike.png`) the extractor never pulled; it's extracted now, and the player swaps to it
    whenever the BICYCLE is active (and back to the walking sprite off it).
  - **The Poké Flute made no sound in the overworld** (gh #162). Using it now plays the flute tune (the
    existing `pokeflute` SFX) as it cures sleep / plays its catchy tune.
- **Playthrough wave 2** (gh #146, #148, #163, #165, #167), more from the human 1.0 playthrough:
  - **The dex entry and nickname screens were hidden after catching** (gh #146, #163). The post-catch
    ceremony left the battle scene visible, and since it's the last child on the shared UI CanvasLayer it
    drew over the (full-screen) dex-entry, nickname prompt, and naming screens — so the player saw only the
    battle. The battle is now hidden up front, so the ceremony screens show.
  - **The vending drinks couldn't heal** (gh #148). FRESH WATER / SODA POP / LEMONADE are medicine in Gen 1
    (heal 50 / 60 / 80 HP) but weren't usable. They're now in the potion table, usable in the field and in
    battle.
  - **Catching a road SNORLAX didn't clear it** (gh #165). Only a *win* set the `BEAT_SNORLAX` event, so a
    caught SNORLAX stayed blocking the road. Catching it now clears the road too.
  - **The HP bar didn't update when the opponent switched in a damaged mon** (gh #167). `_set_enemy` didn't
    reset the displayed-HP mirror, so the bar kept the previous mon's value; it now reads the incoming mon's
    current HP.
- **Celadon playthrough wave** (gh #132–#136, #140), surfaced by the human 1.0 playthrough:
  - **Celadon Mart TM prices showed as ¥0** (gh #132). TMs are priced by a *separate* table
    (`TechnicalMachinePrices`, a nybble = thousands: TM01 ¥3000, TM32 ¥1000…), which the extractor never
    pulled — so the 2F TM floor listed everything at 0. The extractor now emits TM prices.
  - **The Celadon TM18 clerk's dialogue looped** (gh #133). The generic gift handler reused the *pre-give*
    offer line ("…This might be useful!") for the already-received case, so the clerk kept re-offering the
    TM. He now gives the real explanation ("TM18 is COUNTER!…") on later talks.
  - **Stone evolutions could be canceled with B** (gh #134). pokered forces them
    (`ItemUseEvoStone` → `wForceEvolution`); only level-up evolutions are cancelable. Stone use now passes
    the forced flag, so B no longer stops a stone evolution.
  - **The evolution animation stuttered** (gh #135). The flicker froze the pic for a 16/14/12…-frame
    button-poll block before each burst; pokered checks for a cancel *once per iteration* then flickers
    continuously (`Evolution_CheckForCancel`). The loop now matches, so the back-and-forth accelerates
    smoothly.
  - **The Celadon vending machines showed no text** (gh #136). Buying a drink played only a sound; pokered
    shows the "A vending machine! Here's the menu!" intro, the "<DRINK> popped out!" delivery line, and the
    not-enough-money / bag-full / "Not thirsty!" refusals. All are in now.
  - **Turbo (hold Space) didn't speed up trainer/gym battles** (gh #140). Those run inside a cutscene
    wrapper (`Cutscene.trainer_battle` holds `cutscene_active` true across the fight), and the turbo gate
    required no cutscene — so it worked only in wild battles. Turbo now applies to any battle
    (`modal == battle`), while the catch-ceremony screens stay excluded (gh #111). *(Regression from the
    turbo-battle feature above.)*
- **A STRENGTH boulder moved on the first push; the game requires two** (gh #129). pokered's
  `TryPushingBoulder` (`BIT_TRIED_PUSH_BOULDER`) makes a boulder move only on the *second* consecutive push in
  the same direction — the first bumps in place ("the player must try pushing twice before the boulder will
  move"), and the count resets after each tile, so every tile of travel costs two pushes. Facing away,
  stepping off, facing a different boulder, or changing push direction all restart the count. The port slid the
  boulder on the first successful push. Now `try_push_boulder` arms the tried flag on the first push and only
  moves on the second (reset on every turn and step); the legit-play bot's Victory Road boulder route pushes
  twice per tile to match (the boulder destinations are unchanged). Verified end-to-end by `--victoryroadtest`
  and the mechanics tests (`--strengthtest` / `--victorytest` / `--seafoamtest`).
- **The seeded sign-off run now completes NEW GAME → HALL OF FAME in one unbroken process** (gh #131).
  Making the 25× speed-up real (gh #98) let the run reach Mt. Moon in-process for the first time, which
  surfaced that the early stages — unlike Misty onward — challenged their gyms/gauntlets with no potions and
  no whiteout retry, so an RNG-unlucky faint whited out to Pallet's default respawn and ended the run. The
  Brock, Mt. Moon (misty), and Nugget-Bridge (bill) legs now do what the later stages and a real player
  already do: heal at the town Center (registering it as the respawn), carry potions so the mid-battle heal
  can fire, and retry a lost leg from there. `--playthrough --seed 1` now runs green end-to-end as a single
  process (all 21 checkpoints in order, `tools/validate_gate.py` → GATE GREEN, Champion at L73).
- **The automated-run speed-up never actually took effect** (gh #98). Every `--playthrough` /
  `--<flag>test` driver set `Engine.time_scale = 25.0` to fast-forward the many wall-clock tweens, but
  `Main._process` overwrote it back to `1.0`/`4.0` on the very next frame — so the seeded sign-off runs
  plodded along at real time (a forced wild encounter ~5 s, the Elite Four gauntlet ~40 min). A driver now
  owns the clock (`pt_time_scale`) and `_process` leaves it alone while one is active; the interactive
  playtest turbo — and its gh #111 catch-ceremony gating — is untouched, so human play is unchanged. The
  nav step budgets already scaled by the live time scale (gh #99), and the battle RNG/damage never depended
  on it, so the runs stay faithful — only the wall clock changes. The Elite Four gauntlet now finishes in
  ~21 s and a full seeded run reaches Mt. Moon in ~82 s, so the **single-process** Stage-1 sign-off run is
  feasible for the first time (it previously had to be stitched from `--from=<stage>` segments because a
  full run at real time was 90+ minutes, past the background-job ceiling).
- **Warps fired on any step onto a warp square** (gh #80). pokered only warps when the tile under you is a
  door/warp tile, or `ExtraWarpCheck` passes — you're stepping toward the map edge, or (on the
  OVERWORLD/SHIP/SHIP_PORT/PLATEAU tilesets and a few named maps) facing a warp tile. Standing on a plain
  warp square no longer yanks you out: Silph Co. 11F's `(5,5)` no longer seals the president behind the
  MASTER BALL, and a Center mat you arrive standing on doesn't warp you the instant you land. Warp/door tile
  IDs are taken per tileset from the disassembly. Firing at a map edge reads the map's **border block** (as
  the game fills the screen margin), which is what lets you walk off the edge to leave the S.S. Anne, its
  cabins, and Vermilion Dock; the automated-playthrough bot's gate-house and elevator exits were re-aimed at
  the door-facing cell to match.
- **The S.S. Anne Bow used the generic warp-in-front check instead of its special case** (gh #130). pokered's
  `IsWarpTileInFrontOfPlayer` jumps to `IsSSAnneBowWarpTileInFrontOfPlayer` on `SS_ANNE_BOW`, which fires the
  fn2 check iff the faced tile is `$15` (the stairs) for any facing — it ignores the per-direction
  `WarpTileListPointers` list the rest of the SHIP tileset consults. The port applied the generic list, so the
  bow's exit warps would fire facing DOWN as well as facing the stairs. `_warp_should_fire` now honours the
  `$15`-only rule on `SSAnneBow` while every other SHIP map keeps the generic behaviour. (A faithfulness
  clean-up surfaced while finishing gh #80; off the critical path.)
- **The battle move-learning screen wasn't faithful** (gh #121). When a Pokémon leveled up with four moves
  already known, the port showed a plain full-screen box titled "Learn X? / Forget which?" with a "GIVE UP"
  row. pokered (`learn_move.asm`) overlays the four moves in a small bordered box over the battle and asks
  "Which move should be forgotten?" in the text box, with B to give up — no on-screen GIVE UP. The port now
  matches: the battle stays visible behind, the moves sit in a bordered box, and B cancels. (The overworld
  TM/HM teacher already had the faithful flow.)
- **A neighbouring map's trees/flowers bled into the edge of a narrower map** (gh #124). On Route 5 (10
  blocks wide) the trees and flowers of Cerulean City (20 wide, connected to the north) appeared along
  Route 5's right side and popped in and out as you walked. The port drew each connected map in full, so a
  wide neighbour overhung past the current map's edge into the corner regions. pokered draws a connection
  *strip* along the shared edge and fills the rest with the map's border block; connected maps are now
  clipped perpendicular to the connection to match, so the corners show the border block as they should.
- **Dark caves were a spotlight circle instead of the Gen-1 palette swap** (gh #127). Rock Tunnel (and the
  other dark maps) dimmed to a lit circle around the player with black beyond it. In Gen 1 there is no
  spotlight: entering sets `wMapPalOffset = $06`, so `LoadGBPal` loads `FadePal2` (`BGP = 3,3,3,2`) — the
  lightest of the four shades becomes dark grey and every other shade becomes black, uniformly across the
  whole screen. The dark overlay now remaps the rendered screen to that palette; FLASH restores the normal
  colours as before.
- **The Celadon vending machine could overflow your bag and charge for nothing** (gh #126). It wrote the
  bag directly and took your money first, so buying a drink with a full 20-slot bag pushed you past the
  cap and a refused can still cost you. pokered's `VendingMachineMenu` calls `GiveItem` and only subtracts
  the price after a successful give — a full bag jumps to `.BagFull` with no charge. The machine now routes
  through the normal add-item path and charges only on success.
- **The battle bag always snapped back to the top** (gh #120). After using an item mid-battle, reopening
  the bag put the cursor on the first item instead of the one you'd used. pokered keeps the bag cursor in
  `wBagSavedMenuItem`, shared with the overworld bag; the battle bag now restores it too (and resets to the
  top only when the item you used runs out), matching the overworld bag's existing behaviour.
- **The Poké Ball throw was skipped with BATTLE ANIMATION off** (gh #119). Turning move animations off
  replaced the ball toss, poof and wobbles with a blank beat. pokered plays them regardless — `TOSS_ANIM`
  jumps straight to `TossBallAnimation`, before the option check — so catching a Pokémon always animates.
  The ball animations now bypass the animation-off beat (move animations still honour the option).
- **DIG and FLY didn't hide the user during the charge turn** (gh #122). On the charge turn a Pokémon that
  burrows under (DIG) or flies up (FLY) goes out of sight in pokered; the port left its sprite on screen.
  It now vanishes as it charges and reappears as it strikes on the second turn.
- **The S.S. Anne rival walked through you after the battle** (gh #117). The port walked the rival up to
  the tile directly above the player; when you'd triggered the fight from the right-hand tile (37,8), his
  scripted exit then marched straight down through you. pokered instead walks him down his own column to
  (36,7) — above the trigger, not above you — so his RIGHT/DOWN exit routes *around* you either way.
- **Stepping off the S.S. Anne dock dumped you on Route 11** (gh #116). The dock's exit is a `LAST_MAP`
  warp — it goes back to wherever you came from — but boarding the ship (`board_ss_anne`) is intercepted by
  `VermilionCity.on_warp`, which returns before `_do_warp` records the map, and then loads the dock
  directly, so `last_outside_map` kept its stale pre-Vermilion value. Boarding now sets it to Vermilion
  City (as pokered's normal city→dock warp would), so after the ship sails you walk off into Vermilion.
- **The dock sailor checked your ticket one tile too late** (gh #115). pokered runs the check at (18,30)
  facing down — the tile just north of the dock warp, beside the sailor — not on the warp square itself.
  The port fired it off the warp tile (18,31), so the "Ah, the S.S.TICKET!" text popped a tile too far
  south. Moved it to the (18,30) coordinate trigger; without the ticket (or once the ship has left) the
  sailor now turns you back a tile, as he should.
- **You could walk past the Mt Moon SUPER NERD and take a fossil for free** (gh #107). The nerd who claims
  the DOME/HELIX fossils has no line of sight — pokered engages him from a coordinate trigger, not a sight
  cone: `MtMoonB2FDefaultScript` force-runs his battle the instant you stand on (13,8), the one tile the
  fossil alcove can be entered from (he occupies (12,8); (12,9)/(13,9) are the only openings from the
  south, so every route up crosses (13,8)). The port never implemented that trigger, so he just stood
  there and you strolled past. Restored: stepping onto (13,8) engages him ("Hey, stop! …they're both
  mine!" → battle → "OK! I'll share!"), and only after beating him can you reach a fossil. The legit-play
  bot now beats him before grabbing its fossil; new `--fossilguardtest` proves by reachability that (13,8)
  is the sole approach and the guard fires-then-quiets (`--mtmoontest` still clears the mountain).
- **The catch ceremony could soft-lock under the speed-up** (gh #111). With BATTLE ANIMATION off and the
  playtest turbo (speed-up) held, catching a new Pokémon could freeze — the accelerated (`time_scale`×4)
  ceremony raced your button presses, e.g. answering the nickname prompt before you could and stranding
  you on the naming keyboard. Turbo is a playtest helper for *walking*; it now applies only during free
  overworld movement and is suppressed whenever a menu, text box, battle, or cutscene is up, so those run
  at their normal, input-safe speed. New `--newcatchtest` reproduces the exact setup (new species, turbo
  held, human-paced presses) and now completes.
- **The Saffron gate guard's turn-away teleported you** (gh #113). Getting blocked by a thirsty gate guard
  snapped the player back a tile instantly, and showed the "I'm on guard duty…" line *after*. pokered's
  `Route5GateDefaultScript` shows the thirsty line first, then simulates a D-pad press so the player
  **walks** back one tile. The port now does the same (text, then a real `player.step` back), matching the
  Viridian Gym turn-away (gh #86).
- **The Cerulean City Rocket attacked with no warning** (gh #110). The Team Rocket thief who returns the
  stolen TM28 (DIG) went straight into battle silently. His pre-battle line ("Hey! Stay out! It's not your
  yard! Huh? Me?… I'm an innocent bystander!") lives in the map script (`TEXT_CERULEANCITY_ROCKET`), not a
  trainer header, so the port had no `battle_text` for him. Restored.
- **Gym trainers still fought you after you beat the leader** (gh #109). If you reached a gym leader
  without challenging every trainer, the unbeaten ones kept ambushing you afterward. pokered marks the
  whole gym's trainers beaten when the leader falls — each gym leader's post-battle script runs
  `SetEvents EVENT_BEAT_<GYM>_TRAINER_*`. The port now marks every trainer object_event on the gym map
  defeated when the leader is beaten (`--gymtest` confirms Cerulean's two trainers are cleared after Misty).
- **The Nugget Bridge boss skipped his whole spiel** (gh #108). The disguised ROCKET at the top of Route
  24's bridge just handed over the NUGGET and fought you. pokered's `Route24CooltrainerM1Text` congratulates
  you for beating the 5 contest trainers, gives the prize, then reveals himself and makes his "would you
  like to join TEAM ROCKET? … I'll make you an offer you can't refuse!" pitch before the battle, and says
  "Arrgh! You are good!" after. All restored. (The NUGGET is correctly given *before* the fight — that
  matches pokered.)
- **The underground paths looped you back the way you came** (gh #114). Walk Route 5 → Underground Path →
  and you came out on Route 5 again, never reaching Route 6 (and likewise Route 7↔8, Diglett's Cave). The
  connector buildings' exits are `LAST_MAP` warps, and pokered's per-map scripts (`UndergroundPathRoute6.asm`
  etc.) set `wLastMap` to *their own* route on load so the exit is fixed regardless of which side you
  entered from — the port never ran that, so the exit resolved to `last_outside_map` = wherever you started.
  Added the missing `on_enter` map scripts (UndergroundPathRoute5/6/7/7Copy/8, DiglettsCaveRoute11/2).
- **Caves had no wild encounters** (gh #106). Mt Moon, Rock Tunnel, the Pokémon Tower, Power Plant and
  every other cave/dungeon triggered *zero* wild battles: the port only rolled an encounter on a grass
  cell, and caves have no grass tiles. pokered's `wild_encounters.asm` rolls on **any** floor tile when
  the map is indoor (`>= FIRST_INDOOR_MAP`) and not the FOREST tileset (Viridian Forest / Safari Zone,
  which use grass). Now a cave floor encounters at its own rate (Mt Moon: 10/256 ≈ 3.9%); buildings with
  no wild data stay safe because `_try_wild_encounter` gates on `grass_rate`.

### Added
- **DIG and TELEPORT work as field moves** (gh #102). `FIELD_MOVE_BADGE` doubled as the party-menu offer
  list, and neither move is in it (both are badge-free — DIG is TM28, TELEPORT a level-up move), so they
  never appeared even on a mon that knew them. A separate `FIELD_MOVES` set now drives what the menu offers.
  `DIG` runs `ItemUseEscapeRope` exactly as pokered does (`.dig` sets `wPseudoItemID = ESCAPE_ROPE`) —
  cave/dungeon only, never Agatha's room — and `TELEPORT` works only outdoors; both warp to the last
  town's fly tile via the same `_escape_warp()` as ESCAPE ROPE and blacking out. New `--digteleporttest`.

### Fixed
- **Blacking out was free and dropped you in the wrong place** (gh #101). pokered's `HandleBlackOut`
  BCD-halves your money and then `PrepareForSpecialWarp` warps you **outdoors**, to the town you last
  healed in, standing on its `FlyWarpData` tile — in front of the Pokémon Center, not inside it. The port
  never touched money and spawned you at the Center's middle (a one-cell nook behind the Indigo Plateau
  nurse — the old gh #97 hazard). `whiteout()` now halves `player_money` and warps out via a shared
  `_escape_warp()` helper (a Center→town map onto `FLY_DESTS`). **ESCAPE ROPE** shares the same
  destination and was fixed with it (it used to drop you in the middle of the respawn map). Verified
  `--whiteouttest` (Cerulean (19,18), money 3000→1500), `--itemusetest` (ESCAPE ROPE → ViridianCity
  (23,26)), and `--surgenavtest --route9` (the bot's own whiteout recovery still reaches Route 9).
- **A failed Rock Tunnel attempt could teleport the bot to Cerulean** (gh #100). `_pt_warp_out(dest)` falls
  back to a `LAST_MAP` warp and rebinds it to whatever map you name, so `_pt_return_to_cerulean`'s catch-all
  `_pt_warp_out("CeruleanCity")` — reached when a Rock Tunnel run failed *inside* the tunnel (four `LAST_MAP`
  warps) — walked out a tunnel mouth and arrived in Cerulean, skipping Routes 9 and 10. A "legit-play" bot
  teleporting inside the sign-off run. It now navigates the tunnel/Route 10/Route 9 back explicitly and
  refuses a `LAST_MAP` exit from any map that isn't a Cerulean-side building.

## [0.9.37] - 2026-07-10

**Stage-1 sign-off gate is GREEN.** The seeded legit-play bot (gh #76, ADR-011) now plays the whole game
from NEW GAME to the **HALL OF FAME** on merit — `tools/validate_gate.py` reports all 21 stages
checkpointed in order with the Champion beaten at L65 and no dead-end, softlock or crash. Getting there
this release meant fixing the last softlocks on the critical path, every one of them found by the
continuous run and none by any isolated `--<flag>test` — which is the point: an isolated test hands each
stage a state the real run never has. `_PT_STAGES` now holds all 21 stages, so the default
`--playthrough` walks the entire gate. (The run is still proven as a chain of `--from` resume segments,
not one ~5-minute process — that awaits gh #98; the `time_scale` speedup reopens navigation timing races
at 25× and was reverted.) 1.0 is now gated only on the human playthrough.

### Fixed
- **The playthrough bot couldn't FLY, so Cinnabar and the last two badges were sealed** (gh #104). By the
  `blaine` stage the bot's party is Blastoise plus its coverage/HM slaves — Jigglypuff, Oddish (CUT),
  Diglett (Surge), Growlithe (Erika) — and per `base_stats` `tmhm`, **none of them can learn FLY**. So it
  collected HM02 and had no one to teach it to; since flying home and surfing south is the only route onto
  Cinnabar, Blaine, the SECRET KEY and the eighth-gym prep were all unreachable. `--flytest` never saw it
  because it hands the stage a party that already includes a bird (the gh #94 family). The bot now catches
  a PIDGEY on Route 7 during the `saffron` grind — a FLY learner in grass it already walks — and teaches
  FLY to it.
- **The S.S. Anne never sailed, headless** (gh #103). `Cutscene.ss_anne_departs` sets `cutscene_active`,
  then awaits `RenderingServer.frame_post_draw` to grab the screen it animates the ship over. Under
  `--headless` nothing draws, so that signal is never emitted and the coroutine suspends **forever** — the
  ship never leaves, the two gangway steps and the warp into Vermilion never run, and the player stands on
  the dock at (14,2) with no error printed, because a suspended coroutine isn't a crash. This is the
  long-standing "dock strand", twice misattributed (to gh #96, and to RNG) because the `--from=ssanne`
  replays were run windowed through `tools/run.ps1`. The ADR-011 gate is headless by definition, so it
  could never have passed. The capture is skipped when the display can't draw; the departure is not.
- **The playthrough bot's map crossings were a coin flip** (gh #99). `_pt_step` waits for the
  turn-in-place tween and then the step tween, both budgeted in *frames* — counts written for a 60 fps
  game. `_playthrough` runs at `Engine.max_fps = 500`, where the 0.08 s turn takes exactly the 40 frames
  the turn budget allowed, so the key was released mid-turn and the step never happened. `_pt_walk_to`
  retried and hid it for months; `_pt_cross` takes exactly one step to cross a map edge, so a crossing
  worked only when the walk's last step already faced the right way. The budgets scale with the frame
  rate and time scale now, and `_pt_cross` retries and reports. Also `_pt_warp_out` could not leave a mat
  it was already standing on — which is where gh #97's faithful whiteout drops you.
- **A map's load callback was dropped when a cutscene loaded the map** (gh #96). pokered runs a map's
  `*_Script` on every load; `_on_map_loaded` refused while a cutscene or modal was up, and
  `fall_down_hole`, `fly_transition` and a battle whiteout all load a map from inside one. So falling into
  the Pokémon Mansion never laid its switch-dependent doors, flying to Cinnabar never finished the fossil
  revival, and — worst — **whiting out into the Indigo Plateau lobby never reset the Elite Four**, whose
  `on_enter` *is* pokered's `ResetEventRange`. The gauntlet could be entered once and never again. The
  callback is deferred now, not dropped.
- **A whiteout could strand you inside the scenery** (gh #97). `whiteout()` let `_default_spawn()` place
  the player at the middle of the respawn map. The Indigo Plateau lobby's middle is a one-cell nook behind
  the nurse's counter. pokered's `SpecialWarpIn` puts you at the map's *entrance*; so do we now. And
  `_default_spawn` no longer lands on an `object_event` — NPCs are spawned after the player.
- **A level-up could delete an HM move** (gh #93). `learn_move.asm` checks the chosen slot with `IsMoveHM`
  and bounces you back to the list (`HMCantDeleteText` → `jr .loop`); `Battle.gd`'s in-battle learn prompt
  had no such check and overwrote the slot, while the *overworld* flow guarded it correctly. So a Blastoise
  that learned SKULL BASH at L43 with the cursor resting on slot 0 lost **SURF** — and Cinnabar Island,
  Route 23 and Seafoam are all unreachable without it, with nothing to tell you what went wrong. The
  benched-participant path (`allow_prompt == false`) overwrote slot 0 blindly too. `--learntest` only ever
  forgot a slot with no HM in it, so it passed throughout; it now asserts the refusal.
- **The Rocket Hideout could not be reached on foot** (gh #89). The Game Corner poster is a *wall tile*
  at (9,4) whose only walkable neighbour is (9,5) — and `object_event 9, 5, SPRITE_ROCKET, STAY, UP, …,
  OPP_ROCKET, 7` stands on it, facing the poster, so he never engages on sight and must be talked to.
  `toggleable_objects.asm` ships him ON, and only his own battle removes him:
  `GameCornerRocketBattleScript` walks him off, `GameCornerRocketExitScript` then `HideObject`s him. The
  port's `GameCorner.gd` modelled the poster switch, the hidden staircase, the slots and the coin clerks —
  and nothing about him. `EVENT_FOUND_ROCKET_HIDEOUT` was therefore unsettable, and the SILPH SCOPE, the
  Pokémon Tower and everything past them were sealed away. `--silphscopetest` never saw it because it
  **pre-set the event the stage exists to earn**.
- **Cerulean Cave was sealed forever** (gh #90). `CERULEANCITY_SUPER_NERD3` STAYs on (4,12), the only land
  cell touching the cave door at (4,11) — you SURF up the river to him. `HallOfFame.asm` hides him
  (`HideObject TOGGLE_CERULEAN_CAVE_GUY`) the moment you are recorded as CHAMPION; the port never did, so
  MEWTWO was unreachable.
- **`--faithtest`'s two SUBSTITUTE checks were vacuous** (gh #78). They set the substitute's HP but never
  `sub_up`, the flag `Battle.gd` actually gates on, so both measured the *absence* of a substitute. With
  the flag raised the engine agrees with `core.asm`; the test now prints a `PASS=` line.
- **Thirteen selftest drivers pressed A from inside a wall** (gh #84). `player.place()` bypasses
  collision, so each asserted an interaction no player can reach on foot — the pattern that hid gh #80 and
  gh #83. `tools/audit_places.py` now exits 0 and can gate.

### Added
- **`tools/audit_chokepoints.py`** — a solid sprite parked on the only cell that reaches something is a
  door whose key is whatever removes it. For every warp, sign and item ball on every map the tool checks
  whether *all* the walkable cells adjacent to it are occupied, and separately whether any sprite is a cut
  vertex sealing off a whole region. Run over the game it re-derives gh #79 and gh #89 from scratch, and
  it is how gh #90 turned up. Reviewed hits (Mt. Moon's fossils, both SNORLAX, the Victory Road boulders,
  the Warden's boulder, Silph 5F's CARD KEY corridor, Pokémon Tower 6F's RARE CANDY) are silenced by name
  with a reason, so it exits 0 alongside `audit_places.py`.

### Changed
- Legit-play bot (gh #76): five **stage seams** fixed — a stage verified in isolation proves nothing about
  the seam from the previous stage's checkpoint end-state. The gym plaza CUT trees and Celadon Gym's
  interior tree now cut from either side; `sabrina` pads its way back out; `_pt_warp_out` always plans
  spin-aware. **Cerulean City is cut in two by a one-way ledge**, so a Rock Tunnel whiteout has to cross
  back through the Rocket-trashed house exactly as a player would.
- Legit-play bot: it now manages its **bag** (gh #91) and drives the **LearnMove forget prompt** (gh #92).
  pokered's bag holds 20 distinct items, so a hoarding bot was silently refused the GOLD TEETH; and the
  only mon in its party that can carry SURF or STRENGTH is a Blastoise whose four move slots are full by
  L40. Both were faithful engine refusals the bot simply never handled.
- Legit-play bot: it **goes and gets HM02** (gh #95). Nothing in the chain ever did, so it could never fly
  home to Pallet and reach Cinnabar. The way to the Route 16 house is a **CUT tree at (34,9)** — the route
  is split by a fence, the gate house's two passages are disconnected inside, and `--rtprobe` reports the
  north half as a closed system until that one tile is cut. The SNORLAX and the BICYCLE are both
  irrelevant. (FLY needs a carrier the bot's coverage party doesn't have — see gh #104 below.)
- Legit-play bot: it **grinds** (gh #94). It routes around trainers, so it never earns the levels a player
  earns — it met Silph Co's five-mon rival at L41 and Route 22's *second* rival ambush (six mons, a L53
  Venusaur) at L53, and lost both. It now grinds on Route 7 before Saffron and on **Route 18** before ever
  setting foot on Route 22 (418 exp a fight, twice Route 7's — most route grass turns out to be fenced off
  from its own entrance). `_pt_should_switch` no longer feeds a L19 bench mon to a L40 leader; the late
  stages buy HYPER POTIONs rather than 50-HP SUPER POTIONs; and `victoryroad`, `silph`, `pokeflute` and
  `koga` are persistent players like the rest.

## [0.9.36] - 2026-07-10

### Fixed
- **Viridian Gym was never locked.** In pokered the door is shut until you hold every *other* badge
  (`ViridianCityCheckGymOpenScript`: `cp ~(1 << BIT_EARTHBADGE)`); stand on (32,8), the cell below it,
  without them and you get "The GYM's doors are locked..." and are turned away. The port had no such
  check, and `VIRIDIAN_GYM_OPEN` appeared nowhere — so from the very start of the game you could walk in,
  fight through the spin-tile maze, and take the **EARTHBADGE off Giovanni before Brock**. Unlike the rest
  of this family the bug made the game *easier*, not impossible. Note the turn-away is a **ledge hop**,
  not a step: (32,9) is a down-ledge (stand `0x2C` over ledge `0x37`), so `ViridianCityMovePlayerDownScript`'s
  single simulated PAD_DOWN hops the player clean over it to (32,10). `--gymtest` `load_world`s into each
  gym and teleports to the leader, so it never approached a gym door from the street (gh #86).

### Added
- Legit-play bot: the **`giovanni` stage** — the eighth badge and the last gym (`--giovannistage`). The
  door only opens once the other seven are in hand; inside, Viridian Gym is a **spin-tile maze** (step on
  an arrow and you slide until a wall stops you) with eight sight-trainers through it.
  `_pt_talk_and_battle` gained `spin_aware`, without which the floor is not walkable at all — the same
  machinery that threads the Rocket Hideout. GIOVANNI has view range 0, so he is talked to (gh #76).

## [0.9.35] - 2026-07-10

### Added
- Legit-play bot: the **`blaine` stage** — the seventh badge (`--blainestage [--gym]`). It walks the
  Pokémon Mansion for the SECRET KEY (the gym door is locked without it), then threads Cinnabar Gym's six
  **quiz gates**: each room's machine is a wall panel (stand below, face UP, press A); a right answer opens
  that room's gate for good, a wrong one and the room's trainer jumps you. The rooms snake back on
  themselves, so the order is forced — the only machine you can reach is the next one. The bot answers
  from the same `HIDDEN_EVENTS` row the engine fires from, as a player with a guide would, rather than
  brute-forcing six fights before the leader; a mis-answer would cost a fight, not the run. Then BLAINE,
  the VOLCANOBADGE and TM38. `--gym` skips the mansion for fast iteration on the gym (gh #76).

## [0.9.34] - 2026-07-10

### Fixed
- **Hole tiles are in, and with them the Pokémon Mansion's basement.** Gen 1 drops you a floor when you
  step on a hole (a *dungeon warp*); the port had no such thing, so 1F's southern half — the Scientist,
  the CARBOS and the **stairs down to B1F** — had no entrance in either switch state, the **SECRET KEY**
  was unobtainable, the Cinnabar Gym door never unlocked, and **BLAINE's badge could not be won**. The
  holes are not tiles you can find by scanning: each map's script carries an explicit coord list and
  picks the destination floor from the matched index (`PokemonMansion3FDefaultScript`'s `.holeCoords` +
  `IsPlayerOnDungeonWarp`), with the landing cell in `DungeonWarpData` (`data/maps/special_warps.asm`).
  3F's **western balcony drops to 1F (16,14)**, inside the sealed south; its eastern one drops to 2F.
  Walking the floor's other burnt tiles does nothing, and `--holetest` asserts that too. `EnterMapAnim`'s
  `.dungeonWarpAnimation` holds 50 frames on landing — no spin, unlike a teleport (gh #85).

### Added
- Legit-play bot: it **takes the SECRET KEY** (`--secretkeytest`). The Pokémon Mansion is a switch puzzle
  threaded by a hole: in the front, 1F → 2F → 3F, flip 3F's panel, **fall through the western balcony**
  into 1F's sealed south, down to B1F, flip its south panel then its north one — and the key's room opens.
  The panels are **not interchangeable**: B1F's north one seals B1F's own staircase, so the walk *out* is
  not the walk in. `_pt_mansion_flip_for` presses a panel, looks, and presses it straight back if it
  didn't open the way — which is what a player does. The bot then leaves by 1F's back door, which only the
  switch being ON opens (gh #76).

## [0.9.33] - 2026-07-09

### Fixed
- **The Pokémon Mansion switches could never be pressed.** Each is a wall panel — pokered keys them off
  the tile the player *faces* (`data/events/hidden_events.asm`, `hidden_event <x>, <y>,
  Mansion*Script_Switches, SPRITE_FACING_UP`), so you stand below one and press A facing UP. All four
  adapters instead tested the player's **own cell**, and **every switch cell is solid** (1F (2,5), 2F
  (2,11), 3F (10,5), B1F (20,3)/(18,25)), so the condition could never hold and `MANSION_SWITCH_ON` was
  unreachable on foot. `--mansiontest` flipped them with `player.place(Vector2i(2, 5))` — teleporting
  *inside the wall* — which is why it passed; it now stands at (2,6) and asserts the panel is solid while
  the cell below it is not (gh #83).

### Added
- Legit-play bot: it can **FLY**, and it has reached **Cinnabar Island**. `_pt_fly_to(town)` drives both
  menus a player does — the party field-move submenu opens the town list, filtered by `visited_fly` — and
  `_pt_reach_cinnabar` flies home to Pallet, mounts the water at its beach, and swims the 90 cells of
  Route 21, fighting the fishers and swimmers, to Cinnabar's north shore (`--cinnabarnavtest`). Cinnabar
  has no dry connection, and the Fuchsia approach runs *through* Seafoam Islands, so Route 21 is the way
  in (gh #76).

### Known issues
- Whether the **SECRET KEY** is reachable on foot now that the switches work is **not yet confirmed**. A
  static model of the mansion's four floors (block tables checked against `PokemonMansion*.asm`, which
  match) finds no route to it in either switch state — that points at either a modelling error or a
  further data bug. Tracked on gh #83, which stays open until the bot walks it.

## [0.9.32] - 2026-07-09

### Fixed
- **You could not surf from one map to a connected one**, so **Cinnabar Island was unreachable** — it has
  no dry connection, and both sea routes to it (Route 20 and Route 21) cross a map edge. BLAINE's badge,
  the Pokémon Mansion, the SECRET KEY and the fossil lab all went with it. Two causes, both in
  `Main.gd`: `_is_water` only ever consulted the **center** map (`_tile_at` returns `-1` off it), while
  `_cell_walkable` happily resolves a neighbour's collision — where water is solid — so the sea ended at
  every map edge; and `load_world` cleared `surfing` unconditionally, though it also runs on a
  *connection rebase*, which out at sea must leave you afloat. `_is_water` now resolves whichever placed
  map owns the cell (its own tileset included), and the dismount tests the landing cell instead of
  assuming dry ground. `--surftest` mounts and dismounts within one map and `--seafoamtest` moves by
  warp, so nothing had ever surfed across a connection (gh #82).

### Added
- Legit-play bot: it can **surf**. `_pt_use_field_move` drives the real party field-move submenu (so the
  badge gate and the "It can't be used here." refusal both run), `_pt_surf_on` mounts the water from a
  shore cell, and `--surfnavtest` takes the bot from Fuchsia down Route 19 — fighting the swimmers — and
  **across the connection into Route 20, still afloat**, which is the crossing gh #82 made possible.
  Recorded while deriving it: Route 20's sea is **split in two** by the Seafoam Islands landmass (walls at
  columns 43 and 62; verified against pokered's byte-identical `.blk`), and the islands' two Route-20
  doors sit in disconnected regions of Seafoam 1F — so that crossing descends into B1F. The open-water
  approach to Cinnabar is **Pallet Town → Route 21**, one water component end to end (gh #76).

## [0.9.31] - 2026-07-09

### Fixed
- `--nametest` now calls `get_tree().quit()`. It was the only driver that didn't, and it hung any
  unattended run of the flag suite.
- **Mr. Mime had no sprite, so every battle he appeared in drew a null texture** — including
  **SABRINA's**, whose second Pokémon he is (`SabrinaData`). pokered names his files `mr.mime.png` /
  `mr.mimeb.png`, the only two in `gfx/pokemon/` that aren't a bare species key; `build_battle()`
  looked for `mrmime.png`, missed, and **skipped silently** behind an `if f.exists()`. The port
  shipped 150 of 151 sprites. The extractor now maps the name and **fails loudly** if any species is
  missing a front or back sprite. `--gymtest` never caught it: a missing texture is only a *draw*
  error, which Godot logs and runs past, so the test still passed (gh #81).

### Added
- Legit-play bot: the **`sabrina` stage** — the sixth badge (`--sabrinastage [--pads]`). Saffron Gym is
  nine sealed rooms in a 3×3 grid whose entire warp table is 30 **self-warps**: the only way between
  rooms is a teleport pad. Derived on the real pad graph with every trainer treated as a permanent wall,
  the route from the door at (8,17) is `(11,15) → (15,15) → (15,5) → (1,5)`, landing on (11,11) — the one
  pad inside SABRINA's room. A pad you land on stays inert until you step off, which is what keeps the
  last hop from flinging you straight back out. The gym door itself is only clear once GIOVANNI has
  fallen in Silph Co (gh #76).

## [0.9.30] - 2026-07-09

### Fixed
- **Silph Co could not be entered on foot.** Its door in Saffron is at (18,21), and the only cell you
  can step onto it from is (18,22) — where `SAFFRONCITY_ROCKET8` stands. pokered clears him on the
  **Pokémon Tower** rescue, not on Giovanni: `PokemonTower7FMrFujiText` hides ROCKET8 and shows the
  sleeping ROCKET9 one cell east. The port ran neither toggle and kept every Rocket until
  `BEAT_SILPH_CO_GIOVANNI` — who is *inside* the building. So rescuing MR.FUJI is what opens Silph Co,
  and without it the whole endgame was walled off: Saffron Gym is gated too, by ROCKET3 standing in
  its doorway. `--silphtest` warps straight in, which is why this never surfaced (gh #79).
- **Script-placed doors now reopen the moment their last guard falls**, instead of only on the next
  visit. pokered's `EndTrainerBattle` (home/trainers.asm) sets `BIT_CUR_MAP_LOADED_1`, which re-runs
  the map's load callback after every trainer battle; the port only ran that callback on map load.
  The Rocket Hideout B1F/B4F guard doors and the **Lorelei / Bruno / Agatha exit seals** were all
  affected — and those Elite Four rooms have no other way out, so beating the member left you staring
  at a walled exit. Adapters now override an `on_battle_end()` hook (gh #76).
- **The Rocket Hideout B4F LIFT KEY and SILPH SCOPE balls no longer sit in the open.**
  `toggleable_objects.asm` ships both hidden: the LIFT KEY appears only when the beaten Rocket 3
  admits he dropped it, the SILPH SCOPE only once Giovanni steps aside. Either could previously be
  picked up without the battle that gates it (gh #76).

### Added
- Legit-play bot: the **`silphscope` stage** plays Celadon → Game Corner poster → Rocket Hideout
  B1F–B4F → LIFT KEY → elevator → Giovanni → SILPH SCOPE → back out to Celadon, on foot, end to end
  (`--silphscopetest`). B4F is two disconnected wings joined only by the LIFT-KEY elevator, and
  Giovanni's door grunts have view range 0, so they have to be talked into their fights rather than
  walked past (gh #76).
- Legit-play bot: the **`pokeflute` stage** — Celadon → the Route 7-8 Underground Path → Lavender → the
  Pokémon Tower (2F rival, channelers, the MAROWAK ghost on 6F) → MR.FUJI → POKé FLUTE
  (`--pokeflutetest [--tower]`). The navigator now also clears an **item ball parked in a corridor**:
  Tower 6F's RARE CANDY sits on the one-tile passage to the 7F stairs, so taking it is the only way
  past. A give-up now names the objects standing in the way rather than just printing a cell (gh #76).
- Legit-play bot: the **`snorlax` stage** — play the flute at the SNORLAX asleep across Route 12, then
  walk Routes 13/14/15 down to Fuchsia (`--snorlaxstage`). Crossing those routes taught the navigator
  that a **gate house can be the road** (Route 12 and Route 15 are each sealed but for a building with a
  door on either side — `_pt_warp_via` takes a named door rather than the first matching warp), and that
  **a map connection's rows are not interchangeable** (Route 13's west edge opens into a one-tile Route
  14 pocket held by a trainer who faces away, so `_pt_cross` now takes the row to leave by). `--rtprobe`
  reports, per edge, which cells are actually crossable and which of those the flood reached (gh #76).
- Legit-play bot: the **`koga` stage** — thread Fuchsia Gym's invisible-wall maze on foot, clear its six
  sight-trainers, and beat KOGA for the SOULBADGE (`--kogastage`). `--gymtest` teleports to each leader,
  so this is the first time the gym has been navigated rather than skipped (gh #76).
- Legit-play bot: the **`safari` stage** — pay into the Safari Zone, wind through it to the SECRET HOUSE
  for HM03 (SURF), take the GOLD TEETH, trade them to the WARDEN for HM04 (STRENGTH), and teach both
  (`--safaristage`). The park's areas form a loop rather than a hub: from the entrance only the East door
  is reachable, and the Center's own west door opens into a pocket that leads nowhere but back. Park
  encounters are BALL/BAIT/ROCK/RUN, so the battle policy runs instead of fighting (gh #76).
- Legit-play bot: the **`saffron` stage** — walk back north from Fuchsia to Lavender, cross to Celadon,
  climb the Mart to its rooftop vending machines for a drink, and hand it to Route 7's thirsty gate guard
  to reach Saffron (`--saffronstage [--drink]`). Route 7's east edge is walled but for the gate house,
  whose doors are both `LAST_MAP` — the east one drops you back on Route 7 past the wall (gh #76).
- Legit-play bot: the **`silph` stage** — walk the Silph Co pad maze for the CARD KEY and beat GIOVANNI,
  which is what clears Team Rocket off Saffron Gym's door (`--silphstage [--card]`). The elevator serves
  every floor without a key and is a red herring for both places that matter. The **CARD KEY** (5F) sits
  in a corridor sealed at one end by a range-1 trainer who never steps aside and at the other by a
  one-wide column with a trainer in it; the only way in is to *arrive* — ride to 9F and take its pad,
  which drops you inside. And **11F's elevator landing cannot reach Giovanni**: he sits behind the
  floor's card-key door, and the only route into that half is the 7F→11F pad, whose 7F room is itself
  sealed off and entered from 3F's pad. The navigator gained a third obstacle kind alongside guards and
  item balls — a **locked card-key door you hold the key to** (ADR-012). Silph's doors are *blocks*, not
  sprites, and which of a door block's four cells is the wall differs by floor, so the bot looks it up
  rather than assuming (gh #76).

### Known issues
- The Silph Co president's **MASTER BALL** is unobtainable on foot. pokered only fires a warp on the
  step that lands on it when the tile is that tileset's door/warp tile (`IsPlayerStandingOnDoorTileOrWarpTile`);
  the port fires on any warp cell. 11F's `warp_event 5, 5, LAST_MAP` sits on a plain floor tile that you
  must **walk across** to reach the president — a solid, non-toggleable Beauty seals the corridor's other
  end — so in the port that step throws you out of the building instead (gh #80).

## [0.9.29] - 2026-07-03
The end credits are the real scrolling roll (gh #22 checklist; engine/movie/credits.asm),
replacing the plain page-fade placeholder. The Gen-1 layout is reproduced: black letterbox
bars top and bottom over a white text band, staff lines left-aligned at their true columns
(each credit string's leading offset byte, base column 9), and at every _MON page a Pokemon
front sprite scrolls left across the band as a black silhouette (DisplayCreditsMon) - the
transition between sections. The extractor now keeps per-page fade/mon/copyright flags and
the 15-entry CreditsMons order (it previously dropped the CRED_MON tokens and centered every
line), and it emits the real spaced "T H E  E N D" letter graphic (credits_the_end.png) and
renders the copyright page from the boot © / Nintendo / Creatures / GAME FREAK tiles.
Verified by --creditstest (35 pages, 15 mon slides, 1 copyright page); posed by --creditshot
(text/mon/copyright/end in build/preview/credits/).

## [0.9.28] - 2026-07-03
The S.S. Anne departure is the real animation (gh #22 checklist; VermilionDock.asm),
replacing a fade + invented dialogue: stepping off the ship with HM01 switches the music to
MUSIC_SURFING; after the 2 s beat the horn sounds and the ship band - screen rows 80-127,
the raster window the asm scrolls - sails west 128 px at 1 px per 8 frames while white
smoke puffs (the real smoke tile, OBP1=0) pop above the smokestack every 16 px and drift
east; the ship is then erased to open water (the dock walkway stays), the horn sounds
again, and the player is walked north off the dock. The scene is purely visual (the asm has
no dialogue) and now triggers on ARRIVAL at the gangway (wDestinationWarpID == 1) rather
than when leaving the dock. Also hardened: quitting mid-synthesis no longer races the
audio worker threads. Posed by --anneshot (anne1/anne2 in build/preview/).

## [0.9.27] - 2026-07-03
The music engine audited against pokered's engine_1.asm (gh #73). Songs now loop at their
real sound_loop points: each channel walks its intro then one loop body, and the wav loops
over [max intro end, + lcm of the body lengths] - intros never replay, channels of unequal
lengths keep cycling in phase (the title screen's drums roll on under the ended melody),
and one-shot jingles (the healed chime, the intro battle) no longer repeat. Previously
whole-buffer looping replayed intros and left shorter channels silent at the tail of every
pass. The audit also landed the dropped effects - vibrato (delayed alternating wobble of
the period low byte, Audio1_ApplyVibrato), toggle_perfect_pitch (+1 period),
duty_cycle_pattern (rotates per frame), pitch_slide - plus the real channel-3 wavetables
(including the per-bank glitch wave 5 that gives Lavender Town its lead) at the correct
half-rate frequency (basslines played an octave high), drums as the real 19 noise
instruments through a Gen-1 LFSR clocked by the poly register (every drum and noise SFX
was the same white hiss before), and finalbattle's cross-channel sound_calls (bars were
silently skipped). Tempo is now global as on the GB (one wMusicTempo): Silph Co's and
Dungeon3's mid-song tempo ramps retime all four channels together via a tempo timeline
instead of desyncing them, a drum retrigger cuts the previous drum across loop seams,
and vibrato pauses during a pitch slide. Battle music now follows PlayBattleMusic: the
eight gym-leader fights and Lance play the gym-leader theme, the Champion the
final-battle theme. Listen artifacts land in build/preview/audio/.

## [0.9.26] - 2026-07-03
Menus stack like the cartridge's shared tilemap (gh #66): opening the bag no longer wipes
the START menu (it stays visible with a hollow cursor parked on ITEM - you see its top
border and EXIT peeking around the item box), and USE/TOSS opens over the still-visible
item list, with the toss quantity picker and YES/NO confirm piling on top in turn
(Menu.push_under / under-layer stack). The item list itself is now the faithful
ITEMLISTMENU: the fixed 16x11 LIST_MENU_BOX at (4,2)-(19,12), names at col 6 on rows
4/6/8/10, each quantity as xNN on the row below at col 14 (key items and HMs print none,
IsKeyItem), the down-arrow at (18,11) while more rows are below, and the Gen-1 cursor
feel - the cursor rides the top 3 window rows with the 4th as a preview, DOWN on the 3rd
scrolls while scroll+3 <= item count, no wraparound, and both cursor and scroll survive
reopens (wBagSavedMenuItem + wListScrollOffset). USE/TOSS sits at its real (13,10)-(19,14)
box (USE_TOSS_MENU_TEMPLATE), the toss picker is the 5x3 "x01" box at (15,9) (no more stray
"Y 0" total), and the toss confirm is the YES/NO at (14,7) (TossItem_). Item-menu messages
print over the stack's bottom rows like PrintText does (a textbox z-bump, reset on every
show), A on the bag's CANCEL exits to the START menu like B (ExitListMenu), choosing an
item drops a SELECT-held swap (.choseItem), and the START menu box matches DrawStartMenu
exactly (10 wide, 16/14 tall, items from row 2). Same-audit one-tile fixes: the battle
bag's rows sat one row high and its quantity column was off (core.asm uses the same list),
and the battle + mart down-arrows sat on the border row.

## [0.9.25] - 2026-07-03
Battle switches are animated (gh #72): "Come back, X!" erases the withdrawn mon's pic, and
the replacement arrives through the same ball-throw + poof + pop-out as the battle start,
with its cry - for voluntary switches, the SHIFT free switch, and the forced switch after a
faint alike. The pic swap is deferred to the message queue, so the outgoing mon stays on
screen through its recall line.

## [0.9.24] - 2026-07-03
Evolution runs the real sequence (EvolveMon): "What? X is evolving!", the mon's pic and cry,
the Safari-Zone evolution theme, the accelerating black-silhouette flicker between the two
forms, then the result's cry, the fanfare, and "X evolved into Y!". B cancels it mid-flicker
("Huh? X stopped evolving!") except for trade evolutions, and a stone is spent even on a
cancel, as on the cartridge. Level-up evolutions now wait for the battle to END
(wCanEvolveFlags/Evolution_PartyMonLoop) instead of firing mid-battle, and evolving
registers the new form in the Pokedex. Rare candy, stones, trades, and battle level-ups all
share the sequence (gh #67).

## [0.9.23] - 2026-07-03
Playtest wave 8, first half. Poison Sting (and every status side effect) rolls the asm's
exact bytes - poison sides ran at half rate - and burn/freeze/paralysis sides are blocked
when the target shares the move's type, so BODY SLAM can't paralyze NORMAL-types (gh #75).
A faint-forced switch resets the incoming mon's stat stages/volatiles (Sand Attack drops no
longer outlive the fainted mon) and joins it into the EXP split (gh #74). The gym statues
work: facing up shows the leader plaque, and the player's name joins WINNING TRAINERS once
that badge is won (gh #68). The Pokemon Center healing machine's balls actually render -
the sprite region read off the texture's edge (gh #69). The Pewter escorts end like the asm:
the guide is dropped by the gym and dashes off in a straight line (no more pathing around
the building), then returns to his post for the next challenger (gh #70). The Pewter Museum
fossil displays pop the real skeleton pics, newly extracted (gh #71).

## [0.9.22] - 2026-07-03
All three elevators work like the cartridge (engine/events/elevator.asm): the Rocket Hideout
lift needs the LIFT KEY ("It appears to need a key."), the Celadon Mart and Silph Co lifts
don't; the door warps lead back to the floor you boarded from until the panel's floor list
retargets them, and picking a floor runs the real ShakeElevator ride - the music cuts, the
car judders to the collision clack, the Safari-PA ding rings, the music returns. The Silph
elevator was previously a dead end (its map data ships UNUSED_MAP_ED doors; pokered relies
on the runtime retarget). Also the Rocket Hideout guard-door sounds: B4F's clunk plays once
on the unlock, B1F's replays every entry - the asm's own CheckEventHL-instead-of-SetEvent
bug, kept faithfully.

## [0.9.21] - 2026-07-03
MIMIC lets the player pick which of the target's techniques to copy, exactly like the
cartridge (MimicEffect .letPlayerChooseMove): the target's move list pops mid-turn when the
move executes, navigated with UP/DOWN and confirmed with A (no cancel), and the copy lands
in MIMIC's own slot keeping that slot's PP. The enemy's mimic now copies any random
non-empty move (.getRandomMove has no PP check - the old port filtered to moves with PP).

## [0.9.20] - 2026-07-03
The item-menu audit fallout batch. B now backs out of the bag / party / Pokédex / trainer
card / OPTION to the START menu (RedisplayStartMenu) instead of the overworld. Using a TM/HM
plays "Booted up a TM/HM! It contained X!" first, re-shows the party pick on can't-learn /
already-knows, and runs the full LearnMove forget flow on a 4-move mon - the abandon-learning
loop, "HM techniques can't be deleted!", and the machine consumed only when the move is
actually learned; level-up and RARE CANDY learns share the same flow. ESCAPE ROPE only works
in the escape-rope tilesets (never Agatha's room). Bag stacks cap at 99 (AddItemToInventory_)
and emptying a slot resets the remembered bag cursor. Transform and Mimic now write a
battle-only copy that reverts when the mon leaves the field, with the authentic PP handling
(transformed PP is separate; a mimicked move drains the party slot's PP). Also repaired the
broken --stonetest.

## [0.9.19] - 2026-07-03
The item menus behave like the cartridge. Using or tossing an item returns to the bag with the
cursor kept (StartMenu_Item / ItemMenuLoop + wBagSavedMenuItem) instead of dumping to the
overworld; only a successful ESCAPE ROPE / ITEMFINDER / POKé FLUTE / rod / BICYCLE closes the
menu (UsableItems_CloseMenu), and the BICYCLE skips the USE/TOSS submenu (gh #56). SELECT
reordering now matches HandleItemListSwapping on every ITEMLISTMENU surface - the bag (where a
swap used to eat the CANCEL row), the PC item lists, the battle bag, and the mart SELL list -
with the authentic hollow-arrow held marker (gh #57). SELECT also reorders moves in the battle
FIGHT menu, swapping move + PP in the party mon like SwapMovesInMenu (gh #58).

## [0.9.18] - 2026-07-03
Accuracy uses MoveHitTest''s byte math: 100% accuracy is 255/256, so every move can miss (the
famous Gen-1 1/256 quirk), with the accuracy/evasion stage multipliers applied to the byte.
Audited-and-already-faithful this pass: paralysis speed quartering, burn attack halving, and
the confusion self-hit formula.

## [0.9.17] - 2026-07-03
RARE CANDY runs the full level-up pipeline: learnset moves (with the authentic 4-move forget
prompt) and evolution both trigger, as ItemUseMedicine does - the old path bumped stats only.

## [0.9.16] - 2026-07-03
The PP restoratives and PP UP are implemented (ItemUseMedicine, with the "Restore/Raise PP of
which technique?" pick menus and asm texts): ETHER/MAX ETHER top up one move, ELIXER/MAX ELIXER
every move, and PP UP raises a move''s max by base/5 up to three applications. They were all
obtainable but dead - with this, every obtainable item in the game does something.

## [0.9.15] - 2026-07-03
Catch mechanics are ItemUseBall verbatim: all four ball kinds work in battle (GREAT/ULTRA/MASTER
previously did nothing), status ailments shave the roll with underflow captures, and failures
wobble 0-3 times with the four authentic messages; the Safari Zone rolls the same algorithm with
its bait/rock rate and now runs the dex/nickname ceremony on a catch (its caught flag was never
set). Vitamins are implemented (VitaminEffect: +2560 stat exp, the 25600 cap, immediate recalc) -
they were sold at Celadon 5F but did nothing.

## [0.9.14] - 2026-07-03
Stat experience lands (it was absent entirely): every KO feeds the defeated mon''s base stats
into the victors'' stat-exp pools (GainExperience, EXP.ALL double pass, 65535 caps), and
CalcStat''s sqrt term folds the pool into stats at level-up - teams now grow like a real
cartridge run.

## [0.9.13] - 2026-07-03
Engine parity sweep: the move-effect table reaches 100% coverage (RAGE was the last gap - lock-in
plus attack building per core.asm), and the full Gen-1 trainer AI lands (trainer_ai.asm): the
three move-choice modification layers per class and all 19 item/switch handlers (gym-leader
potions, X items, GUARD SPEC., switches, wAICount limits). Enemy trainers previously picked
moves uniformly at random and never used items. New --aitest; movefxtest gains the RAGE probe.

## [0.9.12] - 2026-07-03
Playtest batch 10 (gh #45 #51 #52): the whole game renders in BGB''s grey-green palette
(sampled from the reference shots; the recreated party screen hits 96.2% exact-RGB against
them); the options cursor sits one cell left of its value with hollow ▷ on inactive rows; and
the save file writes indented JSON.

## [0.9.11] - 2026-07-03
Playtest batch 9 (gh #24 #35 #44 #49 #50): save-loaded levels display as ints (no more :L10.0);
stale saved nidoran names migrate to the gender glyphs on load; the dex entry screen recovers
its lost second pages (an extraction regex truncated every description at its first blank line)
with the solid 4px border and through-line divider from the reference; the build version moved
to the main menu; and the project runs on the gl_compatibility renderer (~246 MB working set,
down from 400+), with a new --memtest audit.

## [0.9.10] - 2026-07-03
Playtest batch 8 (gh #30 #31 #44 #45 #46 #47 #48): the dex DATA screen no longer opens
UNDERNEATH the contents list (z-order) and the rail squares gain their 3-shade look; the nurse
machine render is framebuffer-verified (blank machines = rebuild your assets); B on the main
menu returns to the title screen, not the boot; the defeat-time trainer pic sits at the intro
anchor (was 10px low); extracted JSON is human-readable; the world draw is culled to the camera
window (fixes the Viridian slowdown) and the song cache is bounded.

## [0.9.9] - 2026-07-03
Playtest batch 6+7 (gh #25 #26 #30 #31 #37 #42 #43): the catch ceremony stays on the battle
screen with the exit fade held; asks type out fully before the YES/NO pops; the nurse anim is
AnimateHealingMachine verbatim (machine tiles, per-ball chimes, PKMN-healed jingle + flashes,
nurse facing); dex DATA works for the squashed-slug species and the rail matches the reference;
the Route 1 youngster gives his POTION sample once; trainer prize money uses the BCD base/100
(BROCK pays ¥1386); and the party + summary screens were audited by recreating the reference
screenshots and pixel-diffing - now at parity minus icon-animation phase, with Gen-1 icon
animation (HP-color speeds), the authentic HP pill, HUD "HP:" tiles, bold-P PP labels, and the
two-bracket summary layout. Species slugs are canonical everywhere (fixes NIDORAN names/entries).

## [0.9.8] - 2026-07-02
Playtest turbo (hold Space to fast-forward the game 4x, remappable via keybinds.cfg), plus the
last two scripted NPCs from the gh #22 audit: Lavender''s NAME RATER (rename ceremony with the
traded-mon refusal) and the Celadon roof girl (drink-for-TM exchange), both with the asm texts
and new tests.

## [0.9.7] - 2026-07-02
Playtest batch 5 (gh #39 #40 #41): test runs write their own save file so batteries can never
erase or overwrite a real save (the cause of the save resets); the POKéMON menu refuses to open
with an empty party; and the emote bubbles render white per the OBJ palette, matching pokered.

## [0.9.6] - 2026-07-02
Playtest batch 4, closing out the wave (gh #31 #32 #37 #38): the mart rebuilt as its own modal
matching the reference shots (BUY/SELL/QUIT + persistent MONEY box with the floating-¥ BCD
amount, the list/quantity/confirm overlays that never hide each other, full clerk dialogue,
economics preserved); the catch flow stays on the battle screen with the dex registration +
entry for new species; the overworld camera matches the GB''s off-centre framing (player at
screen x=64); and the nurse''s heal ceremony landed earlier in the batch.

## [0.9.5] - 2026-07-02
Playtest batch 3 (gh #24 #30): the Pokédex list rebuilt to the reference (film-strip rail,
poké-ball owned marker, display-name glyphs, reference columns) with all four side functions
working — AREA opens the town map as "⟨MON⟩''s NEST" with wild-data-resolved blinking nest spots
(or AREA UNKNOWN), QUIT/B returns to the START menu; and the data screen''s divider squares draw
inside the frame with the No. glyph and WT alignment fixed.

## [0.9.4] - 2026-07-02
Playtest batch 2, against the reference screenshots (gh #25 #26 #27 #28 #31): the party screen
rebuilt to the authentic columns with the condensed :L/HP glyph tiles, whole mini icons (the
extractor was pasting icon halves), and the STATS/SWITCH submenu overlaying it; the in-battle
PKMN screen is the same layout; the summary screen rebuilt page-for-page (A/B paging, glyph
tiles, brackets, box sizes, alignments); the battle ITEM pick is the framed bag overlay with
quantities and CANCEL; and the nurse runs the real heal ceremony (yes/no, balls on the machine,
the chime).

## [0.9.3] - 2026-07-02
Playtest batch 1 (gh #23 #29 #33 #34 #35 #36): options-menu cursors all stay placed as filled
arrows; the start menu hugs the top of the screen; field YES/NO prompts sit at the text box''s
top-right with the question staying visible; the catching tutorial shows the OLD MAN''s own back
pic and always captures; NIDORAN♂/♀ (and MR.MIME / FARFETCH''D) use their real names; and
stat-change battle text breaks after the possessive like the asm''s authored lines.

## [0.9.2] - 2026-07-02
### Battle
- **Pics clip to their boxes** (gh #20): slide animations cut off at the 7×7 enemy box / 2× back
  box edge instead of crossing the HUD, as the GB''s fixed tilemap window does.
- **The ball animations are unified on the generic player** (gh #20): the send-out poof draws
  straight from POOF_ANIM''s frame blocks (the hand-transcribed tables are gone), and the catch
  flow gained its real visuals — TOSS_ANIM''s arc, the vanish poof, SHAKE_ANIM per wobble (3 on
  a catch; 1 plus a breakout poof on failure) — all as queue markers, so tests skip them and
  BATTLE ANIMATION OFF gets its 30-frame beats for free. Closes #20.

## [0.9.1] - 2026-07-02
The faithfulness-audit campaign (gh #19-#22): boot intro + splash exactness, GB pitch-sweep
synthesis, real BG-priority tall grass, the OPTION menu + SHIFT battle style, the per-map script
audits (Pallet through Cinnabar) with the old-man catching demo, Pewter escorts, Tower ghost
battles, spin tiles, and quiz doors; wild-escape odds, SUBSTITUTE exactness + the doll, the
trainer card, bag rules, the League PC, Oak''s aides, and the Copycat trade. Details below.
### Audio
- **The rival's walk-off jingle is the real alternate start** (gh #22): `Music_RivalAlternateStart`
  is MEET_RIVAL entered mid-song via per-channel `_AlternateStart` labels — the extractor now
  splices those intros onto the main loop as `meetrival_alt`, used for his exits/arrivals in the
  lab, Cerulean, the S.S. Anne, and Silph 7F (encounters keep the full track).
### Battle
- **SUBSTITUTE is Gen-1 exact, with the doll** (gh #20): sub HP = maxhp/4, re-use refused,
  the self-KO-at-exactly-quarter-HP bug, "The SUBSTITUTE took damage for ⟨mon⟩!", the 0-HP
  substitute that survives exactly-equal damage, break-nullified secondary effects — and the
  MonsterSprite doll now stands in for the mon''s pic while the sub is up, appearing with
  "It created a SUBSTITUTE!" and popping with "...broke!" (presentation-timed via markers).
- **13 stubbed move-animation special effects implemented** (gh #20): spiral balls inward
  (Growth/Focus Energy/Amnesia...), the Teleport/Sky Attack ball fountains, screen-wide water
  droplets (Mist/Surf/Toxic), the Psychic wavy screen, Splash''s bounce, Double Team''s wobble,
  Teleport''s squish, Minimize''s shrink, Transform''s pic swap, Razor Leaf / Petal Dance falls,
  the enemy-HUD-only shake, and Softboiled''s half-slide.
- **Per-anim frame-block hooks wired** (gh #20): the flash cadences (every block for Mega
  Punch/Kick/Guillotine/Headbutt/Disable/Bubblebeam/Reflect/Spore; every 8 for Thunderbolt,
  4 for Hyper Beam, Blizzard''s 13/9/5/1), Explosion/Selfdestruct''s user vanish, and Rock
  Slide''s landing shakes — keyed on pokered''s counting-down subanimation block counter.
- **Wild-battle escape odds** (gh #22): running is no longer guaranteed — `TryRunningFromBattle`
  is faithful: free when you're at least as fast (and always vs ghosts/safari), else
  playerSpeed×32 ÷ ((enemySpeed/4) mod 256) + 30 per prior attempt against a byte roll, with a
  failed try costing the turn ("Can't escape!" and the wild mon attacks).
### Menus & options
- **The League PC** (gh #21): after your first Hall of Fame entry, every PC gains the POKéMON
  LEAGUE option — the records viewer replays each winning team, oldest first, pic + name/level
  under its record number (league_pc.asm). Teams are recorded at the ceremony (up to 50) and
  saved with the game.
- **The trainer card is real** (gh #21): the start menu's name entry now opens the
  DrawTrainerInfo screen — the player's front pic, NAME/MONEY/TIME, and the 8 numbered gym
  slots showing each leader's face until the badge is earned, then the badge (draw_badges.asm;
  Giovanni's face is the "?"). Previously a plain text box.
- **Bag faithfulness** (gh #21): the 20-slot capacity (full-bag pickups leave the item behind,
  marts refuse a new slot, gift NPCs re-offer), the USE/TOSS submenu with the quantity picker
  and confirm (key items refuse tossing), joining the existing SELECT-swap reordering.
- **The OPTION menu is real** (`DisplayOptionMenu`): TEXT SPEED (FAST/MEDIUM/SLOW — 1/3/5 frames
  per letter, applied to both text boxes), BATTLE ANIMATION ON/OFF (OFF plays pokered's 30-frame
  beat instead of the move animation), and BATTLE STYLE SHIFT/SET — **SHIFT (the default) now asks
  "Will ⟨PLAYER⟩ change POKéMON?"** with a free switch before a trainer's next mon, a battle
  feature the port was missing entirely. Reachable from the start menu and the title's main menu;
  saved with the game.
- **Start menu**: POKéDEX only appears once obtained, the entry above SAVE uses the player's own
  name, and EXIT is at the bottom (draw_start_menu.asm).
### Overworld
- **Fixed Oak's follow walk glitching** (playtest catch): `walk_together` gated each tile on the
  player's 8-tick step, so once NPC steps became the faithful 16 ticks the lead NPC's next tween
  started while its previous one still ran, and the two fought over its position. The loop now
  gates on the lead with the follower paced to it, gliding in lockstep.
- **Scripted NPC walks run at the player's pace** (playtest catch): the slow 1 px/tick timing is
  only the ambient wander; MoveSprite-style scripted walks (Oak's approach, rival walk-outs,
  trainer engages) are 2 px/tick on GB — `NPC.step` now uses `SCRIPT_STEP` (0.268 s/tile).
- **Cinnabar Gym quiz doors** (gh #22) — the six quiz machines are in (the interior was
  ungated): each room's gate closes on entry until its question is answered right (fanfare +
  the gate block slides open, permanently), while a wrong answer buzzes and sics the room's
  trainer on you — pokered's exact questions, answers, gate coords, and
  gate-index→trainer mapping (cinnabar_gym_quiz.asm).
- **Silph Co 7F rival beats** (gh #22): the fight is now the corridor ambush it should be —
  crossing (3,2)/(3,3) turns the player as MEET_RIVAL strikes, he calls out and walks up to meet
  you, and after "Good luck to you!" he exits toward the elevator with the jingle re-struck
  (previously talk-triggered, no approach, and he vanished in place).
- **Spin tiles** (gh #22) — the Rocket Hideout B2F/B3F and Viridian Gym arrow floors are in:
  landing on an arrow launches the player along pokered's exact pre-baked slide path (the RLE
  movement lists, newly extracted to `spinners.json` — 43/16/12 arrows per map) with the sprite
  whirling per `SpinnerPlayerFacingDirections`, SFX_ARROW_TILES, input locked, and slides that
  chain when one arrow drops you on another.
- **Pokémon Tower ghost battles** (gh #22) — the missing unidentified-GHOST system: without the
  SILPH SCOPE every Tower encounter appears as the GHOST (real ghost pic + the name "GHOST"),
  "Darn! The GHOST can't be ID'd!" at battle start, your mon is "too scared to move!" while the
  ghost wails "Get out... Get out..." — running is the only way out. The scripted MAROWAK now
  plays its reveal: appears as GHOST, "SILPH SCOPE unveiled the GHOST's identity!", the pic
  becomes MAROWAK with its cry — and it can't be caught (the capture calc is skipped outright).
- **SS Anne rival exit fixed** (gh #22): same vanish-in-place bug as Cerulean — he now sidesteps
  right around the player (unless clear at x==37) and heads down toward the stairs with the
  jingle re-struck (SSAnne2FRivalAfterBattleScript).
- **Cerulean City rival exit fixed** (gh #22): after the bridge battle he used to walk straight
  into the player's tile — the blocked step made him vanish on the spot. He now sidesteps around
  you by bridge lane (CeruleanCityMovement3/4: right if you stand at x==20, left at x==21) and
  heads off south with the rival jingle re-struck, the city theme resuming after.
- **Pewter City escorts** (gh #22) — both missing scripted drags are in: the museum guy ("Did you
  check out the MUSEUM?" → decline and he marches you to the museum steps) and the gym guide kid
  ("BROCK's looking for new challengers! Follow me!" → straight to the gym door), each walking
  their own path alongside the player to MUSIC_MUSEUM_GUY, seeing you off, and leaving. The
  pre-BROCK east-exit gate now fires the kid's drag too (PewterCityCheckPlayerLeavingEastScript).
- **Viridian City: the old man's catching demo** (gh #22) — the missing `BATTLE_TYPE_OLD_MAN`
  tutorial: post-coffee he asks "Are you in a hurry?", and the lesson is a wild L5 WEEDLE battle
  that plays itself — the cursor rests on FIGHT then hops to ITEM (core.asm's simulated
  keystrokes), OLD MAN throws his own POKé BALL with real catch odds, no player mon is sent, and
  the WEEDLE is discarded either way. The sleepy blocker and the awake old man now swap after the
  coffee (toggleable_objects.asm). Also fixed a hardcoded "RED" in the ball-throw battle text.
- **Oak's Lab parcel/Pokédex beats** (gh #22): the item fanfare plays *with* the "delivered" line,
  the rival jingle holds through the scene instead of reverting early, and it re-strikes for his
  walk-out with the lab theme resuming after (OaksLabRivalArrivesAtOaksRequest order).
- **Oak's Lab script audit** (first stop of the per-map campaign, gh #22): the rival's challenge
  now plays its asm beats — he turns south, the player turns to face him, MEET_RIVAL strikes up,
  he calls the challenge from where he stands and only *then* walks over; his exit waits the
  20-frame beat before "Smell you later!". (Known small delta: his walk-out jingle should be
  MEET_RIVAL's mid-song alternate start, not the top.)
- **Pallet Town script audit**: Oak's intercept now plays its full beats — "Hey! Wait! Don't go
  out!" prints without a button wait, the "!" bubble pops over the *player* after a 10-frame
  beat, the player turns, and only then does Oak appear and walk up (PalletTownOakText order).
  Signs/NPC texts and Daisy's sitting→walking toggle verified faithful.
- **Player names in extracted text**: `<PLAYER>`/`<RIVAL>` were baked as RED/BLUE at extraction —
  50 texts game-wide (the house signs, Oak's lab lines, trainer chatter) now keep the placeholder
  and substitute the chosen names at display time (`Main.resolve_text`).
- **Tall-grass overlap reimplemented as real BG priority** (playtest catch): instead of a grass
  graphic glued to the player, the map tiles under a grass-standing sprite's lower half are
  redrawn over it at their fixed grid positions — the GB's `OAM_PRIO` mechanism from
  `sprite_oam.asm` — with the lightest shade keyed out so the sprite shows through the blade
  gaps. Now applies to **NPCs and objects** too (it never did), follows sprites pixel-for-pixel
  mid-step, and uses the departure tile while stepping, so a sprite walking into grass stays
  fully drawn until the step lands and then pops under, as on GB.
### Boot intro
- **Boot-sequence audit** (splash.asm / intro.asm / title.asm): the intro's sound effects existed
  only in pokered's third audio bank, which the extractor never read — `sfx.json` now includes it
  (151 → 161 effects), and the whole boot plays its cues: the shooting star's twinkle, the fight's
  hip/hop/raise/crash/lunge, the title logo's bounce **crash** and the version graphic's **whoosh**.
  Faithful timing fixes: the splash holds its 64 empty letterboxed frames before the star; the
  fight's entrance is its full 80 frames and Gengar's slide durations match the asm (with the
  slash keeping Gengar's pose through the retreat); the title **music only starts after** the
  bounce + whoosh (they play over silence, as on GB); the first title mon (Charmander) is already
  in place instead of sliding in; and **starting the game plays the shown mon's cry** instead of a
  menu blip.
### Timing
- **Frame-domain audit** (pokered's overworld loop ticks at 30 Hz — two V-blanks per iteration —
  while battle/text `DelayFrames` are 1/60 s units; see `docs/engine/timing.md`): NPC walking slowed
  to the faithful 0.536 s/tile with the Gen-1 4-phase step cycle (stand/walk/stand/walk-mirrored)
  and the original wander-delay range (1–127 ticks, with the 0→256 quirk); the ledge hop now takes
  its full 32 V-blanks (0.536 s); boulders slide a tile at NPC speed instead of snapping; the
  trainer-sight `!` bubble shows for its 60 frames (1.0 s); text prints at the Gen-1 MEDIUM default
  (3 V-blanks per letter ≈ 20/s, was ~2×); and the battle hit blink (6×10 frames), decaying window
  shakes, status-move sway, Tackle lunge (3 frames), and pic slides now use the exact asm frame
  counts. Player walk/bike speeds were already correct (0.268 / 0.134 s per tile).
### Overworld / interactions
- **Sprite palette**: overworld sprites (player, NPCs, party icons) use a light body with a black
  outline (GB colors 1/2 → the two lightest shades, color 3 → black), between the too-dark
  light/dark/black and the too-bright no-outline mappings.
- **Wall bump**: walking into a wall now plays a full in-place step that finishes back at the standing
  frame (with the collision SFX), instead of freezing mid-step.
- **Walk speed**: slowed the per-tile step slightly (pokered's 8-frame step felt too fast here).
- **Walk animation**: the walk cycle now animates within each step (the leg swings out then plants)
  with the forward foot alternating every tile, matching UpdateSpriteInWalkingAnimation — so up/down
  bounces and shows both feet, instead of holding one frame.
- **Ledge shadow**: the jump shadow is the full flat oval (gfx/overworld/shadow.png is one quarter;
  the widest row is the vertical centre, mirrored top and bottom), not just the top half.
- **Battle**: the player's back sprite is drawn at 2× (the chunky Gen-1 look), not native 32×32.
- **Gift NPCs**: the Route 1 POTION giver (and the other simple gift NPCs) show their line *before*
  the "received" message again, instead of skipping straight to the item.
- **Still-NPC facing**: 3-frame sprites (mart clerk, gym guides, grampses, …) now face the direction
  set in their map data instead of always facing down — they have down/up/side frames, just no walk
  cycle. Only true 1-frame objects (poké balls, boulders) stay static.
- **Sprite offset**: overworld sprites now draw 4px above the tile grid, as in the original.
- **Animated tiles**: the overworld flower cycles its 3 frames and the water scrolls horizontally, as
  in the original.
- **Nicknames**: you're now asked to nickname caught wild mons and gift mons (Eevee/Lapras, Hitmon,
  Magikarp, revived fossils), not just the starter. Catching with a full party sends the mon to the PC.

### Battle
- **Faithful battle transitions & warp fade**: the placeholder blinds reveal is replaced by
  pokered's real 8-wipe system (`battle_transitions.asm`) — the triple screen flash + circle
  sweeps for outdoor wild battles, the inward/outward spiral for outdoor trainers, the interlaced
  stripe combs for dungeon wilds, and the shrink/split screen collapses for dungeon trainers —
  picked by the original trainer/level/dungeon-map bits (`dungeon_maps.json`), consuming the
  overworld into black before the battle screen appears. Battle **exit** cuts to white and fades in
  over the overworld (`GBFadeInFromWhite`); warps play the map-change sound and fade to black in
  the original 4 palette steps (dark caves skip both), instead of cutting instantly. The circle
  sweep also consumes the 4 pivot tiles the GB left to its final blackout (deliberate deviation).
- **Faithful battle-start intro** (audited line-by-line against `_InitBattleCommon` /
  `PrintBeginningBattleText` / `StartBattle` / `SendOutMon`): intro texts auto-advance with no A
  presses; the wild order is now cry → pokeball bracket → "appeared!" → enemy HUD → 40-frame beat;
  **trainer battles get the full intro** they were missing — the trainer's pic slides in as the
  silhouette, the encounter sting, both parties' ball brackets (the enemy's mirrored top-left),
  "wants to fight!", the trainer slides off right, and the sent-out mon **grows in** with its cry
  before its HUD (also reused for mid-battle send-outs); safari battles run the wild intro and keep
  the player's own pic on screen. Slide distances/beats match the asm (144 px slide, Delay3 reveal,
  tile-step slide-offs).
- **Per-move attack animations** (#19): moves now play their real Gen-1 animations — pokered's
  full `DrawFrameBlock` system (203 animation scripts, 86 subanimations, 122 frame blocks + the
  original tile sheets) extracted to `move_anims.json` and played back faithfully (OAM write-pointer
  semantics, enemy-turn transforms, per-subanim sounds), with the common special effects (screen
  flash/palettes, BG shake, pic hide/show/blink, lunges and slides) implemented natively. The turn
  presents in pokered's order — animation, then the hit reaction (effectiveness sting + target
  blink or screen shake by `AnimationTypePointerTable`), then the HP-bar drain — and a missed move
  plays neither animation nor sound, as in Gen 1.
- **Trainer sprites**: trainer battle pics are extracted for all 46 classes; the trainer now appears
  alone for "wants to fight!", slides off as the mons enter, and slides back in on defeat.
- **Start transition**: battles open from black with a horizontal-blinds wipe.

### UI
- **Save screen**: choosing SAVE shows the info box (PLAYER / BADGES / POKéDEX / TIME) laid out to
  match the original — a 14×8 box at (4,0), labels double-spaced, values right-aligned — with the
  YES/NO "Would you like to SAVE the game?" prompt. Play time and a trainer ID persist in the save.
- **Stats/summary screen**: STATS from the party menu opens the two-page summary matching the original —
  the front sprite is flipped to face the data, the name/HP/status and types/ID/OT sit inside their
  L-brackets (DrawLineBox), page 1 has ATTACK/DEFENSE/SPEED/SPECIAL + TYPE/IDNo/OT and page 2 has
  EXP POINTS / LEVEL UP + the four moves with PP. Left/Right flip pages.
- **Party screen**: laid out like the original — each mon's mini icon + name + level over "HP:" + bar +
  cur/max on a blank screen with a "Choose a POKéMON." box, and the selection submenu is STATS / SWITCH
  / CANCEL (SWITCH swaps two party slots). The 10 party icons are extracted from the disassembly and
  mapped per species.
- **Pokédex**: the contents screen matches the original — a scrolling numbered list (number over the
  name, cursor ▶ on the name row), a dot beside owned mons, the boxed vertical divider, SEEN/OWN
  counts, and the double-spaced DATA/CRY/AREA/QUIT side menu (DATA opens the entry, CRY plays the cry,
  AREA is stubbed). DATA restores the list as the modal on return, which previously left it stuck. The
  data screen matches the original: the
  height uses the ′/″ (feet/inches) glyphs, the box-pattern divider (PokedexDataDividerLine), and a
  double-spaced flavor description with a more-pages arrow.
- **Main menu**: CONTINUE / NEW GAME / OPTION in a padded 15-tile box, double-spaced, on a blank
  screen at the top-left — matching the original (OPTION says it's not implemented yet).
- The ¥ symbol for money and prices.

### Battle HUD
- **HP-bar drain**: taking damage, recoil/drain, poison/burn/leech, healing, etc. now animate the HP
  bar sliding to the new value (≈2 frames per pixel) with the HP number counting down, matching
  UpdateHPBar2, instead of the bar snapping. All in-battle HP changes route through an animated setter.
- **Faint slide**: a fainting mon's pic now sinks straight down out of view (SlideDownFaintedMonPic) —
  the player's mon crying, the enemy's fall sound — before the "fainted!" message, instead of vanishing.
- **Level-up stats box**: leveling up shows the new ATTACK/DEFENSE/SPEED/SPECIAL in a box on the right
  (PrintStatsBox) while "X grew to level N!" stays in the text box, instead of paginated text.
- Status boxes are laid out at pokered's exact tile coords: the enemy HUD is flush to the top of the
  screen, the level is the ":L" tile + digits (or the status badge in its place, as in the original),
  and the HP bar and the L-bracket are built from the real HUD tiles (HP:/segments/caps and the
  corner/line/triangle bracket tiles), mirrored between player and enemy. Removed the (Gen-2) EXP bar.
- The player's back sprite is drawn at 2× (the chunky Gen-1 look).
- **Battle intro**: the full Gen-1 start sequence (SlidePlayerAndEnemySilhouettesOnScreen + SendOutMon).
  After the wipe, the player's back trainer pic and the enemy mon slide in from opposite edges as dark
  silhouettes; they resolve, the party-pokeball bracket appears on the player's side, the enemy HUD
  slides in with its cry and "Wild X appeared!", then the trainer pic slides off and — after the real
  POOF_ANIM smoke burst (BallPoofAnim's 6 frame blocks, the actual move_anim_0 tiles) — the first mon
  pops out (AnimateSendingOutMon's stepped 3x3 → 5x5 → full grow, not a thrown ball) as the player HUD
  appears. Stage timing follows pokered's frame counts (silhouette slide ~1.2s at 2px/frame; poof 6×4
  frames; grow 4+5 frames). The party shows as a pokeball bracket (empty balls for unused slots), the
  "Go!" line flows straight into the send-out, and the text box blinks a ▼ "more" arrow.
- The message/menu box uses the fancy Gen-1 textbox border (rows 12-17). In the menu state the FIGHT/
  PKMN/ITEM/RUN menu is its own box on the right (BATTLE_MENU_TEMPLATE), overlaid so its left border
  splits the bottom into an (empty) message box + the menu — as in the original — not one wide box.
- "HP:" and the level are the special HUD tiles (DrawHPBar's $71/$62 "HP:" and PrintLevel's $6e ":L"),
  extracted from font_battle_extra + battle_hud, with the bar's right cap ($6d) — not the regular font.
- **FIGHT menu** (MoveSelectionMenu): the move list is its own box on the right, with a TYPE/PP box on
  the left showing the hovered move's type and current/max PP — as in the original.
- **Name screen**: matches the original — "YOUR NAME?" flush-left; the name preview with bold
  underscores and only the current slot's underscore raised (the ▶ cursor is the font glyph); the
  keyboard on a 16px column grid with the Pk/Mn/ED keys drawn as their single ligature tiles; the
  keyboard box / "lower case" label repositioned; and the preset name list double-spaced.
- **Pokécenter bench guy**: the person against the left wall of each Center is now interactable (a
  hidden-event tile, not an object) and shows that Center's hint.
- **Gift NPCs**: NPCs whose script hands you an item (Route 1 POTION + 8 TM givers) now actually give
  it. NPCs also walk around the player instead of through them.

### Text extraction — ~370 blank NPCs/signs restored
- Talking to a large fraction of NPCs (and reading Poké Center/Mart signs) showed an **empty box**:
  the extractor only kept a text's first direct `text_far`, so dialogue reached via `text_asm`
  indirection, trainer headers, or shared `home/`/`engine/` labels was dropped. The resolver now
  follows those (text ids resolved **666 → 1036**), restoring signs and non-trainer NPC chatter
  across the whole game. Added `tools/audit_text.py` to re-check coverage. See ADR-008.

### Object-visibility audit (all 33 initially-hidden objects)
- **Saffron City**: the Team Rocket grunts occupying the city now leave once you free Silph Co, and
  the residents (scientist, Silph workers, gentleman + bird, rocker) only come back out afterwards —
  previously both crowds were on screen at once.
- **Silph Co 1F**: the reception-desk NPC only appears after the building is freed.
- **Champion's room**: Prof. Oak no longer stands in the room before you win the title.

### Map-event audit (all 26 coordinate-scripted maps)
- **Cycling Road gate**: the Route 16/18 guards now turn you back without a BICYCLE ("No pedestrians
  are allowed on CYCLING ROAD!").
- **Route 22 Gate**: the guard now blocks the way north to Route 23 / the Pokémon League until you
  have the BOULDERBADGE — previously you could walk straight through.

### Battle UI
- The action menu is now the Gen-1 **2×2 grid** (FIGHT/PKMN top, ITEM/RUN bottom, with left/right +
  up/down navigation) instead of a vertical list, and the player's mon now shows an **EXP bar** under
  its HP.
- **Level-up stats**: when the active mon levels up in battle it now shows its new stats (MAX
  HP/ATTACK/DEFENSE/SPEED/SPECIAL), as in the original.
- **Nickname prompt**: after you receive your starter, the game now asks "Do you want to give a
  nickname to <MON>?" and opens the naming screen if you say yes (catch/gift nicknames to follow).

### Playtest fixes (from `bugs.md`)
- **B button advances text** (as well as A), matching the original.
- **Wall bump**: walking into a wall now plays the collision sound and keeps you facing it (no walk
  frame), instead of silently doing nothing.
- **Movement jitter**: enabled pixel-snapping, so vertical (and all) movement no longer shimmers at
  the GB's native 160×144; walking is a touch slower by feel.
- **Oak's Lab**: you can no longer leave before choosing a starter — Oak stops you ("Hey! Don't go
  away yet!") and walks you back, as in the original.
- **Rival battle name**: the rival's battles (including the Champion) now show the name you gave him,
  not the internal "RIVAL1" placeholder.
- **Viridian Mart**: the clerk won't open the shop until you've delivered OAK's PARCEL — before that
  he just says "Say hi to PROF.OAK for me!", as in the original.
- **Hidden item vs Cut tree**: a hidden item sharing a tile with a cuttable tree (the Viridian POTION)
  is now picked up first, so it's reachable.
- **Blue's house**: only one Daisy shows at a time — sitting (who gives the TOWN MAP) before you have
  the map, walking afterwards — instead of both at once.
- **Red's bedroom PC**: now opens the player's item PC (WITHDRAW/DEPOSIT/TOSS ITEM) instead of a
  do-nothing stub.
- **Cable Club receptionist**: the Pokémon Center's link-cable receptionist now greets you ("Welcome
  to the Cable Club!") instead of an empty box — her dialogue is a script text our extractor skipped.
- **Starter selection**: the rival now walks over to his Poké Ball before taking it, and the third
  (untaken) Ball stays on Oak's table — examining it says "That's PROF.OAK's last POKéMON!".
- **First rival battle**: losing it no longer whites you out — your party is healed and the story
  continues (with the rival's taunt), as in the original.
- **Ledge-hop shadow**: the shadow under you while hopping a ledge is now a hard-edged flat GB oval
  instead of a soft round blob.

- **Route 22 rival**: the rival no longer stands on Route 22 from the start — he's hidden until his
  battle is armed (after the Pokédex and before Brock for the first fight; after the 8th badge for
  the second), then walks in, battles, and leaves, as in the original.
- **Ledge hop**: the player now keeps their walking animation through the whole hop instead of
  freezing on one frame.
- **Party screen**: the POKéMON menu now shows each mon's **HP bar, current/max HP, and status**
  (not just name + level), matching Gen 1 — everywhere the party list appears (checking POKéMON,
  using an item on a mon, teaching a move).
- **Bag CANCEL**: the item list now ends with a CANCEL entry, as in the original.
- **Rocket Hideout guard doors**: the door deeper into B1F now stays shut until you beat the grunt
  guarding it, and the door to Giovanni on B4F until you beat both of his guards — previously you
  could walk straight past (same script-placed-tile cause as the E4/Silph doors).
- **Elite Four exit seals** (bug fix found in a script-placed-tile audit): each E4 room now walls its
  forward exit until you beat that member. Previously the Lorelei room was **softlocked** (you won but
  couldn't leave) and the Bruno room was **skippable** — because those doors are placed by each room's
  script, not stored in the map, so our extraction never had them.
- **Seafoam Islands strong current**: with the boulders dropped into the holes, the B4F water now
  sweeps you along its currents (up out of the fall spot, and up-and-right toward Articuno) — the
  original puzzle payoff, faithfully in.
- **Silph Co card-key doors**: the locked doors are back — every floor's doors are placed on entry
  and block the way until you press A next to one while carrying the CARD KEY, which opens it for
  good. (They'd been missing entirely: the doors are placed by each floor's script, not stored in the
  map, so our extraction never had them.)

## [0.9.0] — 2026-06-30

**Completeness pass.** The last gates, puzzles, and cosmetics land — end credits, the Route 23 badge
checkpoints, Seafoam boulder-holes, and Fly/Surf/ship transitions. Only two faithfulness items remain
deferred (both documented): the Seafoam B4F strong-current force-movement and the Silph card-key door
lock (its door tiles aren't present in the extracted maps).

- **Fly / Surf / ship transitions**: Fly now fades through with the fly cry instead of snapping, Surf
  glides you onto the water rather than teleporting, and the S.S. Anne fades out with its horn as it
  departs.
- **End credits**: beating the Champion now rolls the full staff credits (faded page by page, with
  the credits theme) before THE END, instead of a one-line placeholder.
- **Seafoam Islands boulders**: you can now shove the STRENGTH boulders into the floor holes — each
  falls through and is gone for good. (The strong B4F current those boulders enable is still TODO;
  the water stays surfable, so Articuno remains reachable.)
- **Route 23 badge gate**: the approach to the Indigo Plateau now has the original badge checkpoints
  — each latitude turns you back unless you hold the right badge (Cascade at the south end up to
  Earth near the top).

## [0.8.0] — 2026-06-30

**Infra + polish pass.** Extractor additions (complete water tables, the move→SFX map, and the town
map gfx/data) unlock several faithfulness wins, plus a new dark-cave spotlight shader.

- **Dark-cave spotlight**: dark caves (Rock Tunnel, the unlit Seafoam floors) now show the Gen-1
  circular spotlight around you — a small lit area with the rest black — instead of a flat dim.
  FLASH still lights the whole floor.
- **Town Map**: the Kanto map is in (extracted + composited from the original RLE tilemap). Use the
  TOWN MAP from the bag to view it — UP/DOWN cycle the locations (with a blinking cursor + the name),
  A/B closes. Daisy in your rival's house hands it over once you have the Pokédex.
- **Per-move attack SFX**: each move now plays its own sound when used (from the original
  MoveSoundTable, with its pitch modifier), so e.g. EMBER, GROWL and TACKLE no longer share one
  generic hit sound — the effectiveness "hit" cue still follows.
- **Wild encounters keyed by map label**: the extractor now resolves shared wild-data tables, so the
  surf-only SeaRoutes table covers Route 19 + Route 20 (their water encounters were previously lost).

## [0.7.0] — 2026-06-30

**Side-content milestone.** The main quest was already completable (0.6.0); this build fills in
Kanto's side content and a few faithfulness gates. Headless suite now 60+ tests, all green.

- **Victory Road boulder switches**: each floor's Strength-boulder floor switch now opens that
  floor's door when a boulder is pushed onto it (and stays open) — the puzzle that gates the road to
  the Indigo Plateau.
- **Pokémon Mansion + Cinnabar Gym**: the mansion's wall switches now work — flipping any one toggles
  the gate/floor blocks on every floor (the puzzle that opens the way down to the Secret Key), and the
  Cinnabar Gym door stays locked until you're carrying the SECRET KEY.
- **Fossils**: take one of the two Mt. Moon fossils (Dome or Helix — the other is then out of reach)
  and the Pewter Museum's Old Amber, then have the Cinnabar Lab scientist revive a fossil. He keeps
  it while you "go for a walk" (leave to Cinnabar Island and come back), then hands over Kabuto,
  Omanyte or Aerodactyl at L30.
- **Gift Pokémon**: the Eevee Poké Ball on the Celadon Mansion roof (L25), the Fighting Dojo's
  Hitmonlee/Hitmonchan prize (pick one — the other is gone), and the Mt. Moon Pokécenter Magikarp
  salesman (L5 for ¥500). Each joins the party, or the PC box if the party is full.
- **Static legendaries**: Articuno, Zapdos, Moltres and Mewtwo now stand on their maps (Seafoam
  Islands B4F, Power Plant, Victory Road 2F, Cerulean Cave B1F). Walk up and press A to start a
  catchable battle at the original level (birds L50, Mewtwo L70); defeating or catching one removes
  it for good. The same stationary-battle path also enables the Power Plant's disguised
  Voltorbs/Electrodes (each one a one-off wild battle).
- **Good Rod & Super Rod**: the two remaining fishing rods. The Fuchsia guru's older brother gives
  the GOOD ROD (≈⅓ bite, Goldeen/Poliwag L10); the Route 12 brother gives the SUPER ROD (per-map
  fishing groups — e.g. Cerulean's Psyduck/Goldeen/Krabby). Bite odds follow the originals.
- **Game Corner slot machines**: a faithful slots minigame in the Celadon Game Corner — bet 1-3
  coins for 1/3/5 paylines, stop the three reels with A, and win on a line of matching symbols
  (7 = 300, BAR = 100, cherry = 8, any Pokémon = 15). Each spin is rigged before it runs (mostly
  no-win, occasionally a normal match, rarely a 7/BAR jackpot), as in the original. Coins (saved,
  capped at 9999) come from the coin clerk (50 for ¥1000), the fishing guru (10, once) and wins;
  the COIN CASE is given by the Celadon Diner gambler.
- **Game Corner prize room**: the three prize counters exchange coins for the original RED prizes —
  two Pokémon counters (ABRA/CLEFAIRY/NIDORINA and DRATINI/SCYTHER/PORYGON, at their set levels) and
  a TM counter (DRAGON RAGE/HYPER BEAM/SUBSTITUTE). Prize Pokémon overflow to the PC box when the
  party is full.
- **Saffron drink-gate**: the four Saffron gate buildings (you're funnelled through them by the
  city's walled route edges) now have a thirsty guard who pushes you back until handed a Celadon
  vending drink (FRESH WATER / SODA POP / LEMONADE); one drink opens all four gates. This gates
  Saffron — and Silph Co / Sabrina — behind the vending machine, as in the original.
- **Remappable controls**: a user-editable `keybinds.cfg` (in the Godot user-data dir, auto-created
  with defaults) rebinds the inputs on launch (`Keybinds.gd`).
- **START and SELECT buttons** (faithfulness fix — the GB's eight inputs now all exist): **START**
  (Enter/Esc) opens/closes the menu — it used to open on B; **SELECT** (Backspace) reorders items in
  the bag (hold one, then SELECT another to swap). Defaults are now Z=A, X=B; old configs migrate.
- **Hall of Fame** ceremony after the Champion: each party POKéMON is registered (sprite +
  name/level, with the Hall of Fame theme), then a short credits screen — replacing the old
  "THE END" placeholder.
- **Safari Zone**: the gate charges ¥500 for 30 SAFARI BALLs + a 500-step game; encounters use a
  dedicated **BALL/BAIT/ROCK/RUN** battle (bait/rock adjust the catch rate and flee odds, the mon
  can run away, no fighting); running out of steps ends the game and ejects you to the gate.

## [0.6.0] — 2026-06-30

First versioned build. The **main quest is completable end-to-end**: Pallet Town → all 8 gyms →
Victory Road → Elite Four → Champion → Hall of Fame. Covered by a 41-test headless suite (all green).

### Engine & systems
- Data-driven world: 223 maps + 24 tilesets extracted from pokered to PNG/JSON; block→tile render,
  feet-tile collision, warps/doors, seamless map connections, ledges, tall grass.
- Full battle engine: all move effects, status, stat stages, crits/DVs, trainer battles, evolution,
  badge stat boosts, per-action SFX; in-battle items (balls, potions/tiers, status heals, X-items).
- NPCs (wander/solid/sight), text boxes + font, modal menus, the cursor/quantity/windowed lists.
- Save/continue, Pokécenter healing, overworld poison, per-map wild encounters (grass + surf water).
- Audio: GB 4-channel music synth, 151 SFX (both banks), 151 cries.
- Boot/title sequence (copyright → Game Freak logo → Gengar vs Nidorino → title), now with the
  build version shown bottom-left.

### Content
- Opening quest (Oak's speech, starter pick + sprite, first rival battle) and the full mid-game:
  Bill → S.S. Anne (HM01 Cut) → Cerulean/S.S. Anne/Tower rival fights; Rocket Hideout → Silph Scope;
  Pokémon Tower (Marowak ghost) → Mr. Fuji → Poké Flute → Snorlax; Silph Co (Saffron rival, Lapras,
  Giovanni #2, Master Ball).
- All 8 gym leaders (Brock → Giovanni) and the Elite Four + Champion → Hall of Fame.
- All 5 HM field moves: Cut, Fly (visited-town warp), Surf (water traversal), Strength (boulders),
  Flash (dark caves). HMs/TMs taught from the bag (TMs single-use).
- Items/shops: marts + talk-across-counter, Celadon Dept Store vending machine, the player's PC item
  box + mon storage, the Pokédex, fishing (Old Rod), the bicycle, the Day Care.

### Known gaps toward 1.0
Safari Zone minigame; Saffron drink-gate; Game Corner slots; Silph Co card-key door *locking* (the
floors are navigable, but the lock is unenforced pending a tileset tile-ID check); polish — Hall of
Fame credits, Fly/Surf/ship-smoke animations, per-move attack SFX, Gen-1 cave-darkness spotlight;
and a full faithfulness audit (e.g. incomplete water encounter tables).
