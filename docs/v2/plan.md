# v2 — a monster-RPG creation toolkit (the "Studio" plan)

**Status:** **active — Phase 5 (map + event editors, gh #19) began 2026-07-22.** The
build-out is tracked as gh #14 with phase issues #15–#21. Phases 1–4 are complete:
versioned Project/Core, ruleset seam, authored Event VM, and the Studio MVP. The first
format-2 native TMX map crosses the shared `MapDocument` seam into both Engine and Studio
(ADR-021, gh #52), and all 223 Kanto maps now ship through that seam (ADR-023, gh #53).
Studio can now create maps and paint tiles, optional Gen-1 blocks, and per-cell collision
with exact undo/redo, targeted source-preserving saves, and direct map play-test (ADR-024,
gh #54). Typed warp/NPC/sign/trigger placement and reciprocal world-graph editing are live,
with one undo history and a two-map Engine traversal gate (ADR-025, gh #55). The event
workspace is also live: schema-derived trigger/reference controls, the complete VM command
palette, recursive `if`/`ask` lists, exact history, map-object creation/linking, validation,
and child-process execution (ADR-026, gh #56). Softlock lints are next. The gates that guarded
the v2 start remain permanent oracles: 1.0 shipped 2026-07-17 and v1.1 multiplayer shipped
2026-07-20. ADR-013 records the foundational product decisions.

---

## 1. Vision

Turn pokeredpc from *"a faithful native port of one game"* into *"an engine + a standalone editor that
let people build and share their own monster-catching RPGs."* Think **RPG Maker for monster-catching
RPGs**, with a real, asm-faithful Gen-1 engine underneath as the reference implementation.

- **Audience:** fan-game creators across the skill range — no-coders (GUI only), tinkerers (GUI + a
  scripting hatch), and coders (the hatch, deeply).
- **Chosen scope (ADR-013):** a **generic, module-based monster-RPG engine** — the battle system,
  catching, types, formulas, and progression are all pluggable/configurable, not hardcoded Gen-1.
- **Chosen tooling:** a **standalone editor app** (its own `.exe`; creators never open the Godot
  editor), with the **Tiled map format** as the native map format.
- **Chosen event model:** **layered** — a GUI event system for the common 90%, with a **scripting
  escape hatch** for the rest.
- **Chosen migration:** **v1 becomes the flagship sample game** built on the v2 engine — the
  dogfooding proof that the toolkit can express a real, complete, correct game.

**Non-goals (bound the scope, or this becomes a worse Godot):** not a general-purpose game engine — it
stays *monster-RPG-shaped*; not 3D; not a ROM patcher. The engine is *opinionated scaffolding*, filled
in by data + rulesets — Godot remains underneath; we do not reinvent it.

**Multiplayer is in scope and lands before v2.** It is a committed **v1.1** feature (the extended design
conversation is deferred to *immediately after 1.0*). Because 1.1 ships multiplayer *on v1*, the v2
engine — which rebuilds v1 as its flagship — must treat multiplayer as a **first-class constraint from
day one**, not a later bolt-on (see §4.7).

**Platforms:** the **tools (Studio) stay desktop** (Win/Mac/Linux); **finished games export as widely as
feasible** — desktop, web, and mobile where the runtime allows. That asymmetry (desktop authoring, broad
play) shapes the engine's portability budget: the runtime, its scripting sandbox, and its save/IO must
survive web and mobile export, even though the editor never has to.

---

## 2. The core reframe: **Engine + Project + Ruleset + Content**

The single most important idea. Today the engine and the game are **fused** — the code *is* Pokémon
Red. v2 separates them cleanly:

| Concept | What it is | v1 analogue |
|---|---|---|
| **Engine** | The runtime (a Godot app). Generic systems that *execute data*. Knows monster-RPG **interfaces**, not the rules. | `game/scripts/*` (but fused with the rules) |
| **Project** | A fan game = a portable, versioned, shareable **folder** of data + assets + maps + events + a ruleset selection. | `game/assets/` + all the hardcoded logic |
| **Ruleset** | The pluggable **mechanics** layer (battle / catch / types / formulas / progression). A project picks a base ruleset and overrides it. The faithful **`gen1`** ruleset ships built-in. | the Gen-1 formulas baked into `Battle.gd` |
| **Content pack** | Species / moves / items / … data + assets. | the ~30 JSON files + PNGs |

The runtime contract: **`Engine(Project) → playable game`** and **`Studio(Project) → edits the same
Project`**. Both read and write **one well-specified project format**, so the editor and the runtime can
never drift. v1's Kanto = the `gen1` ruleset + a Kanto content pack + Tiled maps + authored events.

---

## 3. Architecture

```
 ┌──────────────────────────────────────────────────┐
 │  STUDIO  (standalone editor app, its own .exe)   │   creators live here
 │  content editors · map view (Tiled TMX) ·        │
 │  event GUI + script pane · ruleset config ·      │
 │  live play-test · validation/lints               │
 └───────────────────────────┬──────────────────────┘
                             │ reads / writes
                             ▼
 ┌──────────────────────────────────────────────────┐
 │  PROJECT  (a portable fan-game folder — the       │   the shareable artifact
 │  shippable, git-able, diff-friendly game)         │
 │  data/  maps/*.tmx  events/  scripts/  assets/    │
 │  ruleset.* + manifest                             │
 └───────────────────────────┬──────────────────────┘
                             │ loaded by
                             ▼
 ┌──────────────────────────────────────────────────┐
 │  ENGINE  (generic runtime, a Godot app)          │   plays any project
 │  world/render · entities · Event VM ·            │
 │  Ruleset host (battle/catch/types/formulas/…)    │
 └──────────────────────────────────────────────────┘

        both depend on ▼
 ┌──────────────────────────────────────────────────┐
 │  CORE (shared library)                           │   single source of truth
 │  project schema · data model · Event-VM defs ·   │
 │  ruleset interfaces · shared rendering           │
 └──────────────────────────────────────────────────┘
```

**Core** is the keystone: the project schema, the data model, the event-command definitions, and the
ruleset interfaces live in exactly one place that both Studio and Engine import. Shared rendering means
the editor's previews are pixel-identical to the game.

---

## 4. Subsystem designs

### 4.1 Project & content model — *schema-driven everything*

- A **project is a directory** (+ a manifest). Human-readable, diff-friendly, version-controllable.
  Serialization: JSON with **JSON Schema** (the editor is the primary authoring surface, so fast
  loading + machine validation beats hand-editability — but raw edits stay possible).
- **Every content type has a schema**, and the schema is the *single source* that drives four things at
  once: the **editor UI** (auto-generated forms), **validation**, **runtime loading**, and **docs**.
  This is the multiplier that makes "graphical tools for *everything*" tractable — you build a form
  engine once, not 30 bespoke editors. Adding a field is one schema edit, not three.
- **Content types** (generalized from v1's ~30 data files): species (base stats / types / learnsets /
  evolutions / dex), moves (power / type / effect / animation), types + type chart, items, trainers +
  parties, encounter tables, dialogue/text, TM·HM, marts, tilesets, sprites, audio, town map, trades…
  Each becomes *schema + editor*.
- **Stable string IDs, not indices.** v1 leans on pokered's constant *order* (positional resolution).
  v2 references content by ID (`species:bulbasaur`, `move:tackle`); the editor enforces referential
  integrity and safe renames.
- **Extensible by creators, not just us:** the schema system lets creators add **new fields** (a custom
  stat, a flag) and even **new content types** without touching engine code. That is what "every system
  extensible" demands.

### 4.2 Ruleset & pluggable mechanics — *the generic-engine answer*

The hardest, most novel part. Decompose mechanics into **modules with clear interfaces**; the engine
core knows the **interfaces**, the **`gen1` ruleset** provides faithful implementations.

- **Battle module** — turn structure, action order, damage, accuracy, status, AI. Interface: `battle
  state + chosen actions → an ordered stream of battle events` (feeds the presentation queue, à la v1's
  ADR-009 markers). `gen1` implements it asm-faithfully.
- **Type/effectiveness module** — a **data-defined type chart** (matrix) + resolver. Already nearly
  data in v1 (`types.json`).
- **Formula layer** — damage / crit / catch-rate / exp-curve / stat-calc as **configurable formulas**:
  a small expression system (named variables + operators) covers the common tweaks; the **scripting
  hatch** (§4.3) covers exotic math.
- **Progression module** — badges/keys/HM-gates generalize to **progression flags** + **gate
  conditions**.
- **Catch / encounter / evolution / condition** modules — each pluggable.
- A **Ruleset** bundles module implementations + config. A project **picks a base** (`gen1`) and
  overrides selectively.

**Design principle that avoids the "worse Godot" trap:** the engine ships *monster-RPG-shaped*
scaffolding (entities, a battle loop, an overworld, saves) and a **spectrum of extensibility** —
**config-first** (knobs cover ~80%), then **module-swap** (replace/extend a module via script) for the
rest. **No speculative generality:** every abstraction must be *demanded* by reproducing v1 (or a second
sample), never added on spec.

### 4.3 Event & scripting system — *layered*

Replaces v1's hand-written GDScript map adapters **and** `Cutscene.gd` beats. Both become **authored
data**.

- An **event** = an ordered list (with branches) of **commands**. Commands attach to map objects,
  tiles, regions, and global hooks.
- **Command library** (extensible), generalized from v1's Cutscene beats + the 8 map-script hooks:
  `say / ask`, `give / take item`, `start battle (wild|trainer)`, `warp`, `set / clear / check flag`,
  `if / branch`, `set / get variable`, `move / turn NPC`, `show / hide object`, `play sfx / music`,
  `fade`, `wait`, `teach move`, `heal party`, `give mon`, `run script`, `call event`…
- **Event VM** in the runtime interprets commands. Deterministic and **save-aware** — durable state is
  flags + variables (v1's `story_events`, generalized). This is the piece that makes stories *authored*
  rather than *coded*.
- **Trigger model** — v1's 8 hooks (`on_enter / on_step / on_interact / on_warp / object_shown /
  boulder_hole / on_boulder / on_battle_end`) proved exactly which touchpoints a real game needs. v2
  exposes them **declaratively**: triggers on map objects/regions + global event hooks. (The hook set is
  finite and known — see [engine/map-scripts.md](../engine/map-scripts.md).)
- **Authoring UI:** a **command-list / flowchart** editor (RPG-Maker-style), *not* a free-form node
  graph initially — far more approachable, covers the domain, cheaper to build. Node graphs can come
  later if demanded.
- **Scripting hatch (a key decision, §8):** the GUI can't express everything (custom puzzles,
  minigames). Shipping **arbitrary GDScript** in shared fan games means arbitrary code execution on
  players' machines and couples projects to engine internals. **Recommendation: a sandboxed scripting
  layer** — a small embedded language (sandboxed Lua, or a purpose-built DSL) with a **curated API**
  (the command library + read/write flags & variables + query state). Safe to share, stable, portable.
  This is a substantial build item and a real fork; flagged in §8.

### 4.4 Map pipeline — *Tiled as the native format*

- Adopt the **Tiled TMX/TSX format as the project's native map format.** This *is* how we "use Tiled as
  the base": creators can open a map in **Tiled directly**, or in **Studio's built-in map view** — both
  read/write the same TMX, losslessly.
- v1's map model maps cleanly onto Tiled layers: a **tile layer** for the map; **object layers** for
  warps / NPCs / triggers / signs; **custom properties** for event links + parameters.
- **The bridge** — a documented Tiled object-type/property convention (optionally a Tiled extension) so
  a warp/NPC/trigger placed in Tiled carries its event reference + params. Studio offers the richer
  integrated flow (drop an NPC → edit its events inline, pick sprites from the project), and
  **round-trips to TMX** so power users can stay in Tiled.
- **Generalize beyond GB "blocks":** support **per-tile collision** (a collision property/layer) so
  creators aren't bound to pokered's 2×2-block + collision-table concept — while still supporting
  block-based tilesets for GB-style authoring. Tiled autotiling/terrain is a free bonus.
- **Connections** (v1's seamless route↔town stitching) → a project-level **world graph** (map
  adjacency + offsets), edited in Studio.

### 4.5 Studio — *the standalone editor app*

- **Built in Godot** (reuses Core + shared rendering for pixel-accurate previews), shipped as **its own
  `.exe`** — not the Godot editor with plugins (ADR-013 chose standalone for a polished, self-contained,
  no-Godot-required experience).
- **Shell:** project browser, dockable panels, a content-type sidebar, and **live play-test** — launch
  the Engine on the current project without leaving Studio (the fast iteration loop RPG Maker nails).
- **Visual language:** the supplied reference boards and their durable shell/map-workspace
  contract live in [studio-visual-direction.md](studio-visual-direction.md); new editor
  surfaces extend the centralized theme rather than inventing local styling.
- **Schema-driven forms** render most content editors (species/moves/items/trainers) automatically,
  with custom widgets where needed (sprite pickers, learnset tables, type selectors, party builders).
- **Specialized editors** where forms aren't enough: the map view (TMX), the event editor (command
  list + script pane), a battle/animation previewer, a tileset/collision editor, a sprite/animation
  importer, an audio importer.
- **Validation & lint — a real differentiator.** v1's audits (`audit_chokepoints`, `audit_places`,
  reachability, dangling references) become **editor lints** that catch softlocks *before* the creator
  ships. No other fan-game toolkit ships "your NPC seals the only path to the badge" detection.

### 4.6 Asset pipeline

- GUI import of sprites/tilesets/audio, with slicing (sheets), palettes, and format handling done for
  the creator.
- **Audio:** default to **standard audio files**; keep v1's clever GB 4-channel synth as an *optional*
  "chiptune" audio module (creators can supply GB-style song data for authenticity, or just drop in
  `.ogg`s).
- **The pokered importer is a first-class, permanent feature — not a throwaway build step.** v1's
  `tools/extract.py` (`pokered/` → assets) generalizes into an **importer** that reads *a user's own
  pokered clone* and emits a v2 **Kanto content pack / project**. This is how the faithful Kanto assets
  reach a creator: the toolkit ships the **recipe** (the importer + its mapping config), the creator
  supplies the `pokered/` clone, and extraction happens **locally for personal use** — the exact
  bring-your-own-source model v1 already relies on (`pokered/` git-ignored, extracted assets git-ignored,
  never redistributed). See [architecture.md](../architecture.md) for the v1 extractor this grows from.
  Generalized, this is simply one **import path** ("import a content pack from a pokered-format
  disassembly"); the same importer machinery can front other asset sources later.

### 4.7 Multiplayer — *a first-class constraint (committed for v1.1, before v2)*

Multiplayer is a **committed v1.1 feature** delivered on the v1 codebase. **The design conversation was
held 2026-07-17 — see ADR-014**, which resolves the specifics this section left open: the faithful Cable
Club only (trade + link battle), trusted peers over direct connect (no servers/matchmaking),
deterministic lockstep, a versioned stable-ID mon-record wire schema, and a version+content-hash link
identity handshake. The three requirements below are therefore now **pinned artifacts, not open
questions** — the mon record is v2's serialized state model, the lockstep contract is §4.2's
reproducible battle stream, and the link identity prototypes the project manifest. Two things were
already fixed and constrain v2:

- **v2 rebuilds a v1 that already has multiplayer**, so the v2 engine cannot treat it as a bolt-on. The
  pieces that networking touches must be designed network-ready from the start:
  - **Deterministic, serializable battle state.** The battle module's `state + actions → event stream`
    contract (§4.2) must be reproducible from a seed + action log — the basis of both replays and
    lockstep/authoritative netplay. (v1's battles are already RNG-seeded and message-queue-driven, so
    this is an extension, not a rewrite.)
  - **A clean state/save model** with stable IDs (§4.1) so a mon/party/inventory can be **serialized and
    exchanged** across two games — the substrate for trading and for save portability alike.
  - **Content-hash / ruleset compatibility.** Two players (or a trade) only interoperate if their
    projects agree on the relevant content + ruleset; the project manifest needs a versioned identity so
    the engine can detect mismatches. (This reinforces "the project format is a public API," §6.6.)
- **Creators get multiplayer too, eventually.** Because the engine is generic, fan games should be able
  to opt into the same trade/battle primitives — so multiplayer belongs in the **engine/ruleset layer**,
  exposed to events (`start link battle`, `offer trade`), not hardcoded to Kanto.

Net: the post-1.0 multiplayer design conversation feeds *two* roadmaps at once — it ships in v1.1, and it
sets requirements for v2's Core (state model, save format, project identity). That's why v2's Core work
should wait until those requirements are known (§7).

---

## 5. v1 as the flagship sample (the dogfooding proof)

The **acceptance test for the whole toolkit**: *rebuild the faithful Kanto game entirely as a v2
project* — `gen1` ruleset + a Kanto content pack + Tiled maps + authored events. If the toolkit can
reproduce pokered — and **the legit-play bot still beats it** — the engine is expressive enough and the
`gen1` ruleset is complete.

v1 hands v2 four gifts:
- **Correct formulas** → the `gen1` ruleset's spec *and* its unit tests.
- **All map/species/… data** → generalize v1's extractor into the **pokered importer** (§4.6) that emits
  a v2 Kanto project *from the creator's own pokered clone*. The toolkit ships this recipe, not the
  assets — each user extracts theirs locally for personal use, exactly as v1 does today.
- **The legit-play bot** → an automated end-to-end regression that *any* engine/ruleset/event change can
  re-run (it already plays NEW GAME → HALL OF FAME).
- **The audits** → editor lints.

The **hard part** of the migration is the hand-written map adapters + Cutscene beats: they must be
**re-authored as events**. This is finite and enumerable — the 8-hook model + the Cutscene beat list
tell us *exactly* which triggers and commands the event system must support to reproduce Kanto. That
list is the concrete spec for §4.3.

---

## 6. Hard problems & risks (called out honestly)

1. **The "generic engine" trap** — infinite configurability → paralysis and a worse Godot. *Mitigation:*
   monster-RPG-shaped scaffolding, config-first with script hatches, and **no abstraction without a
   concrete demand** from v1 or a second sample.
2. **Scripting security/portability** — shared games running arbitrary code is dangerous. *Mitigation:*
   sandboxed scripting with a curated API, never raw GDScript. A major up-front decision (§8).
3. **Save-format evolution** — creators edit content, players have saves, creators ship updates.
   *Mitigation:* versioned saves, stable IDs, tolerant loading, a migration story — designed in from
   day one (v1's save is simple; generic is harder).
4. **Editor scope** — 30+ content types × polished GUIs is enormous. *Mitigation:* the schema-driven
   form engine (build once), specialized editors only where needed, ship incrementally.
5. **Two codebases drifting** (Engine vs Studio) — *Mitigation:* the shared **Core**.
6. **Project format is a public API** the moment people build games. *Mitigation:* version it from v1 of
   the format; expect to support migration forever.
7. **Performance of data-driven mechanics** — interpreting events/formulas vs compiled code. Fine for a
   turn-based RPG; watch the Event VM in tight overworld loops.
8. **Legal / IP (important).** v1 uses **extracted Nintendo assets — personal-use only** (per
   `AGENTS.md`). A *distributable* toolkit **cannot ship those** — but it can preserve v1's clean model:
   the **Engine + Studio are original code** (freely shippable), and the faithful **Kanto pack is
   delivered as the pokered *importer* (a recipe), not as bundled assets** — each creator supplies their
   own `pokered/` clone and extracts locally for personal use, so the toolkit never redistributes the IP.
   Complementarily, the toolkit ships a small **original / CC-licensed placeholder content pack** so a
   brand-new creator has *something* to start from without needing pokered at all. So there are two
   on-ramps: "start from the CC placeholder pack" (out of the box) and "extract the faithful Kanto base
   from your own pokered clone" (personal use) — and neither puts Nintendo assets in the distributed
   toolkit.

---

## 7. Phased roadmap (value at every step — no multi-year cliff)

Each phase is independently shippable and testable; **the bot + the audits gate every one.**

- **Phase 0 — Finish v1 to 1.0.** Non-negotiable: v1's correctness is the spec and the oracle.
  *(Current work.)*
- **Interlude — v1.1 multiplayer (a v1 release, before any v2 work).** *Immediately after 1.0*, hold the
  extended multiplayer design conversation, then ship multiplayer on v1 as **1.1** (§4.7). This lands
  *before* v2's Core precisely because it sets Core's requirements — the state/save model, deterministic
  battle serialization, and project identity that Phase 1 would otherwise have to guess at. **This is the
  gate on starting v2:** v2 Core work waits until multiplayer's shape is known, so it isn't formalized
  twice.
- **Phase 1 — Core & project format** (**gh #15**). Extract the shared Core (schema, data model, stable
  IDs). Write the `v1 → project` converter. The runtime loads a **Project** instead of hardcoded assets.
  **Deliverable:** v1 runs unchanged *from a project folder* — proves the split.
- **Phase 2 — Ruleset seam + `gen1`** (**gh #16**). Refactor battle/catch/types/formulas behind ruleset
  interfaces; the Gen-1 rules become *the* `gen1` ruleset. **Deliverable:** the bot still beats the game
  *through* the seam (and the `--battledettest` md5s don't move by a byte — the refactor oracle).
- **Phase 3 — Event VM** (**gh #17**). Replace map adapters + Cutscene beats with the event system
  (command library + interpreter + declarative triggers). **Deliverable:** Kanto's whole story runs on
  authored events; the bot still completes NEW GAME → HALL OF FAME.
- **Phase 4 — Studio MVP** (**gh #18**). Standalone app: project browser + schema-driven content editors
  (species/moves/items/trainers) + play-test launch. Maps still via Tiled + converter. **Deliverable:**
  edit a species/trainer in the GUI, play-test the change instantly.
- **Phase 5 — Map & event editors** (**gh #19**). TMX map view + the event GUI + the object/trigger
  bridge + validation lints. **Deliverable:** build a small *original* map with an NPC + a working event,
  entirely in Studio.
- **Phase 6 — Scripting hatch + ruleset config UI** (**gh #20**). Sandboxed scripting; GUI for ruleset
  knobs; custom fields/types. **Deliverable:** a creator makes a non-Gen-1 change (new type, tweaked
  formula) with no engine code.
- **Phase 7 — Polish, packaging, a *second* sample** (**gh #21**). A deliberately-different second sample
  game (proves genericity), export-to-`.exe` for players, creator docs/tutorials, community.

---

## 8. Open decisions (pin during design, not now)

- **Scripting-hatch language** — sandboxed Lua vs a purpose-built DSL vs a sandboxed GDScript subset.
- **Serialization** — JSON + JSON Schema vs a friendlier superset (JSON5/YAML/TOML).
- **Tiled** — how much to embed vs launch externally; whether to ship a Tiled extension.
- **Save/versioning** — the concrete migration strategy for creator updates.
- **Runtime distribution & export targets** — Studio stays **desktop** (Win/Mac/Linux); finished games
  export **as widely as feasible** (desktop, web, mobile where the runtime allows), as a bundled
  self-contained build and/or Engine + project folder. Broad game-export is a *runtime portability
  budget* on the engine, its scripting sandbox, and its save/IO (§1) — the reason to favour a sandboxed,
  web/mobile-friendly scripting layer over anything desktop-only.
- **Save/versioning** — the concrete migration strategy for creator updates (and, per §4.7, for
  cross-game serialization of party/inventory).
- **Naming/branding** of the toolkit and the editor.
- **License model** — original engine/editor (open?); the CC placeholder content pack; and the pokered
  importer as the personal-use path to the faithful Kanto base (bring-your-own-clone, extracted locally,
  never redistributed).

**Settled (this planning pass):** platforms — desktop tools, broad game export (§1); multiplayer — a
committed **v1.1** feature that precedes and constrains v2, extended design deferred to *immediately after
1.0* (§4.7, §7); reference model — GB Studio's approachability + Pokémon Essentials' depth, differentiated
by a faithful engine and softlock lints; ownership — primarily a solo build, possibly open-sourced later
(keep the Core clean/documented, don't front-load contributor infra); **no** sharing hub — the toolkit
exports a self-contained game and any community is external.

---

## 9. Post-v2 possibility — a modernized Kanto showcase (deferred)

After v2 ships, consider publishing two Kanto-derived player builds:

- **Faithful Kanto** remains the default reference project: extracted data, `gen1` rules, presentation,
  and behavior stay faithful to pokered, and the legit-play bot continues to protect it as the engine's
  end-to-end regression oracle.
- **Modernized Kanto** is an optional showcase project/profile built with the same Engine, Core, and
  Studio. It demonstrates what creators can add without compromising or replacing the faithful game.

This is deliberately **not** a second engine fork. Modernized features must be reusable project or
ruleset capabilities exposed through Studio rather than Kanto-specific branches in the runtime. The two
player builds should come from separate project profiles or content overlays over one maintained engine;
the exact packaging mechanism waits until the v2 project and export formats are stable.

Candidate demonstrations include widescreen/scalable presentation, modern input and accessibility
options, multiple saves/autosave, richer battle animation, followers or visible encounters, enhanced
weather/lighting, smoother map presentation, and additional creator/debug tooling. Two classic
player-facing modes belong in the same set:

- **Nuzlocke** — a ruleset/profile option, not a fork: faint-is-death release (or permanent box),
  first-encounter-per-map catch limits, and optional dupes/species clauses enforced by the engine
  through the same ruleset-config seam (ADR-018) the faithful game already consults, with Studio
  exposing the knobs per project.
- **Randomizer** — a seeded content overlay over a complete project: shuffled wild encounters,
  starters, static gifts/trades, items/TMs, and (optionally) trainer parties and learnsets,
  generated as project data at export or profile-build time so the runtime itself stays faithful
  and the seed is reproducible and shareable.

This list records possibilities, not commitments or v2 requirements.

The showcase is also distinct from Phase 7's deliberately different second sample: that sample proves
the engine can support a game unlike Pokémon Red; modernized Kanto would instead prove that optional
capabilities can layer cleanly onto a complete faithful project. No implementation or detailed design is
scheduled before the v2 gate closes.

---

*This plan will grow into per-subsystem docs under `docs/v2/` as each phase is designed. It is a
direction, not a contract — every abstraction earns its place by reproducing v1 or a second sample.*
