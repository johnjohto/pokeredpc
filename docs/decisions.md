# Architecture decision records

Newest first. Each entry: context → decision → consequences.

## ADR-031 — Creator extensibility as data: map fields, singleton workspaces, declaration tables (2026-07-24)

**Context:** gh #68 (Phase 6.5) wants ruleset knobs, custom fields on records, and
creator-defined content types editable from Studio — no engine code, no hand-edited
files. The substrate almost suffices: ADR-017 reserved the `custom` bag, ADR-018 §4
made the config a schema'd record, ADR-020's form engine generates editors from
schemas, and CoreSchema already validates schema'd `additionalProperties` maps. Three
gaps: the form engine cannot render keyed maps (every knob table is one), singleton
`kind: table` files have no editor path, and nothing declares bag shapes or new record
families.
**Decision:** (1) `SchemaForm` grows exactly ONE control: the **map field** — an object
whose schema is `additionalProperties: <schema>` or a single `patternProperties` rule
renders as key/value rows with add/remove; the raw-JSON control remains only for truly
shapeless objects. One control serves the stage tables, badge maps, the type chart, and
both declaration files. (2) **Singleton table workspaces**: layout `kind: table` files
mount through the same SchemaForm + canonical save + validate-before-write path as
records (no filename-id rule); the shell lists `types`, `ruleset`, `custom_fields`, and
`content_types`, creating a missing declaration file with its schema-valid starter.
(3) **`data/custom_fields.json`** (additive): content type → {field → CoreSchema
fragment} narrows the reserved bag — declared fields validate and render as real
controls (x-ref fragments get id pickers); the bag stays `additionalProperties: true`,
so undeclared entries remain legal: ADR-017's bag is narrowed, never sealed.
(4) **`data/content_types.json`** (additive): kind → {id_prefix, schema} declares a new
record family. The validator extends the layout walk dynamically — collision with a
built-in path or prefix refuses, fragment keywords check recursively at declaration
time (a kind with zero records cannot hide a typo), the schema must declare `id`
(the filename-identity rule is universal), and two creator kinds cannot share a prefix
— and ids join the registry, so custom fields and creator kinds cross-reference
freely. Declaration semantics run in BOTH the whole-project walk and the Studio
table-draft preflight, so a semantically bad declaration can neither save nor
validate; a declaration that newly narrows a bag some EXISTING record violates saves
(it is itself valid) and the violation surfaces at the next whole-project pass — the
Problems panel and `--validate` both carry it. (5) **Engine consumption is
deliberately nil** this phase: creator
data is authored, validated, browsed, and play-test-loadable; mechanics reach it only
through future ruleset/script seams. Manifest `identity.parts` stays extractor
provenance and link identity stays ADR-029's battle subset — lockstep never reads
creator data, so it cannot desync it.
**Consequences:** the acceptance runs live end to end (a turned stage knob proven at
300% by a child Engine; a declared field with validation teeth; a creator kind
browsed, created, saved, and x-ref'd — 141 studiotest checks). Declaration schema
FRAGMENTS author as raw JSON inside the validated form this phase — a Studio-mediated,
refuse-loud surface, but a schema-builder GUI stays deferred until a real creator
demands one. Faithful defaults stay visible because the extractor emits the full
faithful config values; a ruleset.json CREATED in Studio starts with `base` alone and
added knobs begin empty — surfacing the ruleset module's built-in defaults in the
form is a noted follow-up, not a data problem (absent keys still fall back in-engine).

## ADR-030 — Formula-hatch kernel contracts: fixed inputs, host draws, loud base fallback (2026-07-23)

**Context:** gh #66 lands ADR-028's second hatch: script-backed `RulesetFormulas`
kernels. The open design questions were where bindings live, how a script receives the
battle's randomness without owning draw order, how the one dictionary-shaped kernel
(`catch_attempt`) reports, and what happens when a script fails mid-battle — the
downstream consumer (pokemon-one's non-gen1 progression layer) needs these contracts
stable, not just gen1 re-expression.
**Decision:** (1) Bindings live in `data/ruleset.json` as top-level `formula_scripts`
(kernel name → `script:` ref) beside `config`, not inside it — ADR-018's "config is
only what was already data" rule stays intact, and the schema enumerates the ten legal
kernel names so an unknown key fails validation and boot. (2) The Core wrapper
`HatchFormulas` composes over ANY base provider via the generic
`Ruleset.attach_formula_scripts()` boot step: bound kernels run scripts, unbound
kernels delegate — per-kernel granularity, no whole-module swap (ADR-028's deferral).
(3) Each kernel has fixed input variables; RNG kernels register the battle's own draw
Callables as hosts (`rand_float`/`rand_range`/`rand_int`) so scripts control formula
math, never draw order — proven by re-expressing all ten gen1 kernels as scripts and
reproducing the four `--battledettest` stream md5s byte-for-byte. (4) `catch_attempt`
reports through an `out(name, value)` host (`caught` bool + `shakes` int) rather than
an encoded scalar return. (5) Binding `exp_for_level` alone makes the wrapper derive
`level_for_exp` by walking the scripted curve, so a curve and its inverse cannot
disagree. (6) A runtime failure falls back to the base kernel LOUDLY (push_error naming
script, kernel, position): parse errors refuse at boot like events, but a mid-battle
input-dependent failure must neither crash the battle nor silently ship wrong math —
the fallback is deterministic for identical inputs and draws.
**Consequences:** creators replace exotic math with data alone (the doubled-catch and
custom-exp acceptance runs live through a child-engine play-test with zero engine
code); vanilla projects never wrap (rulesettest holds Kanto to the native provider);
the ten-kernel contract table in docs/v2/hatch-script.md is the API pokemon-one designs
against. Two known limits, accepted deliberately: scripts cannot express table-shaped
config (stage multiplier tables stay `config` knobs — a scripted table would need
language vocabulary ADR-028 excluded), and kernel inputs are exactly the ADR-018
interface's (`stat_calc` sees base/level/dv, not species or form identity), so a
per-species/per-form modifier needs the interface itself to grow — a follow-up the
downstream consumer must drive with a concrete case, not a speculative widening here.
`tools/hatchdet.ps1` automates the determinism gate: battledettest on vanilla vs the
exprtest-built gen1-scripted scratch, the four md5s diffed by the script (md5s stay
machine-relative per gh #44 — never pinned in-tree).

## ADR-029 — Red/Blue are build-time content variants; link identity stays battle-only (2026-07-23)

**Context:** gh #26 adds Pokémon Blue as a build/extraction option. The pret/pokered tree
builds both cartridges from `_RED`/`_BLUE` conditionals; the port now has the same
selection at extraction time. Blue changes content that the single-player game reads
(wild encounter tables, title presentation, credits, Game Corner prizes), while real Red
and Blue cartridges could still trade and battle. The existing v1.1 link identity refuses
when any hashed lockstep-relevant part differs.
**Decision:** (1) `tools/extract.py --version red|blue` is a build-time content-variant
switch. The emitted Project keeps one path layout; only the bytes and manifest id/name
change. (2) Link identity remains the derived subset of Project identity that lockstep
actually consumes: `species`, `moves`, and `types`. Wild tables, title art, credits,
prize counters, maps, and presentation blobs are intentionally excluded, so a faithful
Red↔Blue link session is allowed when battle/mon-record data matches. (3) The title
renderer keeps its stable asset path; the extractor writes the selected version wordmark
to that path.
**Consequences:** Red remains the default build. Blue can be produced from the same
source clone without runtime branching, and Project validation/Studio see Blue as a
normal content pack. The compatibility rule is explicit: future version differences that
affect battle simulation or mon-record interpretation must be added to the link identity
parts, while single-player-only tables must not block Cable Club sessions.

## ADR-028 — The scripting hatch is a purpose-built DSL, events + formulas first (2026-07-23)

**Context:** Phase 6 (gh #20) opens the §8 fork for the scripting hatch: sandboxed Lua
vs a purpose-built DSL vs a sandboxed GDScript subset, judged on sandbox strength
(shared games must never run arbitrary code), web/mobile export survival, and API
curation. The substrate is further along than "no scripting": EventVM already interprets
a declarative story DSL, FormulaExpr (gh #35) is a proven integer-exact expression
evaluator with a tokenizer/parser/AST walker and position-named errors, and the Ruleset
module family already isolates battle/catch/formula/progression/types behind interfaces.
**Decision:** (1) **A purpose-built DSL**, a statement-level extension of the
FormulaExpr lineage (locals, if/else, bounded loops, calls into a curated API),
tree-walked by the engine with a step budget. Sandbox strength is *by construction* —
the grammar cannot name IO, OS, or engine internals — and pure GDScript keeps every
export target. Sandboxed GDScript is eliminated (no real sandbox in Godot, no runtime
source compilation in release exports, couples projects to engine internals); sandboxed
Lua loses on the portability budget (native GDExtension kills web; a third-party
GDScript interpreter is an uncontrolled engine-version-sensitive dependency). (2) The
hatch lands **events + formulas first**: a `run_script`/`call_script` event command for
custom puzzles/minigames, and script-backed formula kernels for exotic math beyond
FormulaExpr — together delivering the issue's acceptance (new type via data, tweaked
formula, custom puzzle, no engine code). Whole-module swap authored in the DSL (the
§4.2 spectrum's far end) waits for a second sample to demand it, per the
no-speculative-generality rule. (3) The curated API is the EventVM command library +
flags/vars + read-only state queries — never engine internals; scripted battle math
must preserve byte-identical replay streams (the determinism gate). (4) Event scripts
receive stable wrappers over the generic command subset; wrappers enqueue ordinary VM
commands so existing await/abort semantics remain authoritative. Durable script variables
carry additive scalar type tags in saves because JSON number parsing must not change
HatchScript's integer-exact arithmetic after reload.
**Consequences:** the toolkit grows ~1–2k lines of owned language (parser, evaluator,
docs, Studio script field) instead of an external dependency; the §8 fork closes;
sandbox escape tests are bounded because the grammar has no escape surface to probe.
Phase 6's second workstream (ruleset config UI, custom fields/types) is unaffected by
the language choice.

## ADR-027 — Softlock lints: one diagnostic stream, review-required warnings (2026-07-23)

**Context:** v1 kept the map/story softlock checks in `tools/audit_chokepoints.py`, which
reads the extracted `game/assets/` JSON — invisible to format-2 Studio projects and to
the Core validator. gh #79/#89/#90 showed the failure shape: a door whose "opens" claim
rests on an authored record nobody re-checks. Phase 5.6 (gh #57) needs the checks in
Core so Studio, the CLI, and CI share them, plus a way to keep pokered's *intentional*
gates (Snorlax, fossils, boulders) without weakening the gate.
**Decision:** (1) `ProjectLint` is the single lint entry point: it wraps
`ProjectValidator` errors and adds map/story rules as source-addressed diagnostics
{rule, severity, message, source, suppressed, suppression_reason}; Studio's Problems
panel, `--validate`, and the Core smoke all consume the same result. (2) Two severities.
Errors (invalid schema, unstandable NPC/spawn, unreachable target on original maps,
unbacked blockers on original maps, event/object link mismatches) are never
suppressible. Warnings (`map.blocking_object`, legacy `event.blocker_unbacked`,
`suppression.unused`) are review-required: an unsuppressed warning fails the gate, and
the only way to clear one is a named entry in `data/lint_suppressions.json` with a
human reason — v1's EXPECTED list, now data with a schema. Stale suppressions
themselves warn. (3) Blockers the engine clears without authored events (item balls,
STRENGTH boulders, sight-line trainers who march off their post) never require event
backing; on imported maps the remaining unbacked STAY blockers (the POKé FLUTE's
Snorlax, cleared by engine map scripts the data cannot see) downgrade to reviewable
warnings. (4) Imported pokered maps are detected by the `_legacy_locked` marker on any
record kind — not just NPCs — and opt out of original-map rules (default-spawn
reachability), since faithful Kanto contains intentional warp/pad pockets.
**Consequences:** A clean Kanto project lints at 0 errors / 0 warnings with 21 reviewed
suppressions; deleting any of the four records behind gh #79/#89/#90 re-creates and
identifies that blocker as an unsuppressed diagnostic (proved by `ProjectLintSmoke`).
Studio shows the same stream in a Problems panel that focuses the source map object or
event on selection, and `--validate` exits non-zero on any unreviewed diagnostic, which
the determinism workflow gates on per release.

## ADR-026 — The event schema is Studio's command vocabulary (2026-07-22)

**Context:** Phase 5.5 (gh #56) must expose every Event VM command, including recursive
`if`/`ask` branches, without creating a second handwritten command model that drifts from
the runtime grammar. Event records refer to maps, objects, items, moves, and species; an
individually valid JSON record can still name a missing object or an out-of-bounds region.
Creating an NPC event also changes two files, and saving the TMX link first would briefly
leave the project with a dangling reference.
**Decision:** (1) `event.schema.json` is the command palette and field authority. Studio
resolves its local `$ref`s, derives one palette entry/default object per command `anyOf`,
and renders scalar, enum, reference, object, array, `prefixItems`, and optional fields from
the same Core-schema subset. No parallel command list or JSON text editor exists. (2)
`EventDocument` owns event state, canonical serialization, dirty state, validation, and
nested block-path mutations. `[]` addresses the root command list; alternating command
index/branch-name paths address recursive `then`/`else` lists, keeping the view ignorant of
VM vocabulary. (3) Studio renders branches as nested command lists and snapshots the whole
document for every add/delete/duplicate/reorder or field edit, giving exact undo/redo.
(4) Save preflights both generic schema/reference checks and ProjectValidator's existing
event-to-map object/cell semantics. Invalid drafts remain visible but never reach disk.
(5) Creating from a map object writes and validates the event first, then links and saves
the NPC/trigger TMX. Failure can leave only an unreferenced event, never a dangling map
link. Imported legacy objects retain ADR-025's read-only rule. (6) Event Play-test remains
the ordinary separate Engine process; the acceptance probe asks the loaded Event VM to
compile and execute the new record and reports only an observable story-flag result.
**Consequences:** Adding a schema+VM command automatically makes it available to Studio;
the schema, form, validator, and runtime cannot silently acquire different command enums.
Existing Kanto JSON remains byte-exact on no-op Save, while an edited record is canonical
JSON. Map and event files are not a filesystem transaction, but their write order preserves
project validity at the only recoverable split point. The gate round-trips all 283 Kanto
event shapes, authors a nested conversation on an original NPC, proves exact history and
whole-project validation, then observes its selected branch in a child Engine process.

## ADR-025 — Object edits keep stable names; world links are reciprocal transactions (2026-07-22)

**Context:** Phase 5.4 (gh #55) must let creators place local gameplay objects and connect
maps without turning Studio into a second TMX dialect. Tiled exposes both author-facing
names and mutable numeric object ids; Kanto objects additionally carry exact legacy runtime
payloads. Seamless connections are two directed records in `data/world.json`, although the
creator thinks of them as one spatial relationship. Independent edits could leave stale
event links, disagreeing legacy payloads, one-way edges, or geometry that never overlaps.
**Decision:** (1) The stable Tiled `name` is the gameplay object id. The numeric Tiled `id`
is a private serialization anchor used to target only that object during save; new ids are
allocated from `nextobjectid`. `MapDocument` owns add/update/remove and validation for four
types: point warps, NPCs, signs, and cell-aligned rectangular triggers. (2) Imported records
with `pokeredpc:legacy` are visibly read-only in Studio. New generic objects may coexist on
those maps, but changing a legacy common field is refused until Core can regenerate its
exact payload. (3) `WorldDocument` owns `data/world.json`. Setting `A east → B, n` also sets
`B west → A, -n`; removal deletes both. It validates one direction per map, exact reciprocal
count/direction/offset, existing maps, and positive shared-edge overlap. (4) Studio snapshots
the map and world documents together, so one gesture/link is one undo record and Save/Revert
cannot split their histories. (5) Whole-project validation resolves map/event ids and checks
each 1-based destination warp against the destination map. Play-test remains a fresh child
process; the acceptance probe drives real Player input through both an authored warp and an
authored seamless edge.
**Consequences:** The creator edits one logical connection and cannot save a half-edge;
Engine placement continues to consume the same ordered records. Tiled remains a peer editor:
no-op bytes stay exact, object saves replace/remove one owned object or append to `Gameplay`,
and unrelated XML/TSX survives. Canonical world JSON may reformat only when the graph is
actually saved. The deliberate legacy lock trades immediate Kanto-object editing for one
runtime authority; a later migration may remove it by translating every legacy-only field
into generic typed properties. The Studio gate authors two maps and all four object types,
proves unified undo/save/reopen, and traverses both connection mechanisms in an Engine child.

## ADR-024 — Map painting owns cells and an optional collision override layer (2026-07-22)

**Context:** Phase 5.3 (gh #54) must let Studio create and paint maps without making its
TMX output a second dialect or destroying content authored in Tiled. TSX tile properties
provide useful default collision, but creators also need to make one instance of a tile
walkable or solid. Kanto additionally carries reversible 32×32 block metadata, while the
canonical Project geometry remains a general 16×16 cell grid.
**Decision:** (1) `MapDocument` is the only mutation boundary. It exposes cell edits,
flood fill, optional block stamping, collision edits, state snapshots, create, dirty state,
and save; Studio owns gestures and history, not XML. (2) `Ground` remains the owned visual
CSV layer. Per-cell collision overrides use an optional hidden full-map CSV layer named
`Collision`: GID `0` means walkable and any valid tileset GID means solid. Without that
layer, `pokeredpc:walkable` on the TSX tile is authoritative. Studio adds `Collision` only
when authored collision differs from those defaults. (3) Save patches only the CSV bodies
of owned layers (and `nextlayerid` when inserting `Collision`). A no-op emits the original
bytes; comments, ordering, unknown properties/layers/objects, and the external TSX remain
untouched. (4) Native cells may intentionally mix Gen-1 block groups. A coherent 2×2 group
retains its block id; a mixed group reports no block id until a block brush stamps all four
quadrants. (5) One drag/fill/block gesture is one map-level undo record. Play-test refuses
dirty state, validates the whole Project, and launches the Engine child directly on the
authored map.
**Consequences:** Collision is instance-editable without cloning tiles or mutating a shared
TSX, and both Studio and Tiled remain valid editors for one source file. The writer is more
constrained than a general XML serializer by design. Terrain/autotile editing, multiple
tilesets, object/world editing, and TSX property editing remain later demand-driven slices.
The Studio smoke creates a scratch map through the real dialog and tools, proves exact
undo/redo and unrelated-source preservation, then checks walkable and solid cells in a
separate Engine play-test process.

## ADR-023 — Kanto maps project to reversible native cells plus a world graph (2026-07-22)

**Context:** ADR-021/gh #52 proved one conservative native TMX map, but Kanto's 223 interim
JSON maps carry 32×32 block identity, 8×8 semantic tile ids, 78 seamless connections,
runtime block replacement, 805 warps, and 1,119 signs/objects. Flattening only the pixels
would make the game look right while breaking Cut, doors, switches, collision, encounters,
or Studio's future block brush. Keeping the JSON beside TMX would create two authorities.
**Decision:** (1) The extractor emits Project format 2 directly: 223 TMX maps, 24 external
TSX files, and no project `maps/*.json`. (2) Each Gen-1 block becomes four native 16×16
atlas cells (`local_id = block_id * 4 + quadrant`). Each cell records its reversible
`pokeredpc:block`, exact four `pokeredpc:subtiles`, representative feet/bottom-right ids,
and collision/grass/counter semantics. Composite PNGs contain those exact source pixels;
the Engine still animates water and flowers at the preserved 8×8 level. (3) Seamless
cardinal connections live in schema-validated `data/world.json`, because they relate maps
rather than belonging to one map's local geometry. (4) Imported Kanto objects expose the
generic typed properties and carry an owned compact `pokeredpc:legacy` payload for exact
Gen-1-only args/trainer text (including control characters XML cannot represent directly).
It is migration provenance, not a second map source: geometry, class, name, and common
fields remain native Tiled content. (5) `MapDocument.legacy_map()` is the explicit parity
oracle; the Engine uses `runtime_map()`. TSX parse results cache by absolute path plus exact
source hash, so 223 maps sharing 24 tilesets do not multiply validation cost or go stale.
**Consequences:** Kanto now dogfoods the same native map seam creators use while format 1
remains loadable. Dynamic block changes stay faithful and later Studio block painting can
round-trip between 16×16 cells and optional 32×32 brushes. The generated Project is larger
and deliberately redundant at the TSX property level, buying transparent, independently
testable semantics. `--projparitytest` compares all 223 legacy views and all 24 native
atlases (metadata plus pixels); the seeded full playthrough remains the behavioral proof.

## ADR-022 — Agent-agnostic instructions: `AGENTS.md` is canonical (2026-07-22)

**Context:** The repo brief lived in `CLAUDE.md`, which only Claude Code reads. Other coding
agents (Codex, Cursor, Gemini CLI, Copilot, …) have converged on the cross-tool `AGENTS.md`
convention; the repo already delegates to a Codex subagent and shouldn't be tied to one harness.
**Decision:** Move the canonical instructions to `AGENTS.md` (git-mv, history preserved).
`CLAUDE.md` stays as a two-line stub whose `@AGENTS.md` import makes Claude Code load the same
content. All docs/tooling references now point at `AGENTS.md`.
**Consequences:** One source of truth for every agent; edits go to `AGENTS.md` only. If a
future tool needs its own filename (e.g. `GEMINI.md`), add another one-line pointer, never a fork.

## ADR-021 — Native maps use a lossless TMX bridge behind one MapDocument seam (2026-07-22)

**Context:** v2 Phase 5 (gh #19) must make maps editable in both Tiled and Studio without
creating two formats or two interpretations. The format-1 Project carries extractor-shaped
JSON maps made of 32×32 Gen-1 blocks; creators need a general 16×16 movement-cell grid,
per-cell collision, project-owned art, typed objects, and lossless coexistence with Tiled
features pokeredpc does not understand. Engine, Studio, validation, and tests would drift if
each learned XML independently. The tracer is gh #52.
**Decision:** (1) **Project format 2 replaces `maps/*.json` with `maps/*.tmx` plus external
`tilesets/*.tsx`; format 1 stays loadable.** Kanto's projection is specified by ADR-023/gh
#53. Each map
also carries a `pokeredpc:format` bridge version, so a newer map convention refuses naming
both sides even inside a supported Project. (2) **The canonical grid is the 16×16 movement
cell.** A 32×32 Gen-1 block is optional `pokeredpc:block` authoring metadata, never the
runtime geometry; odd cell dimensions are legal. (3) **One deep Core module,
`MapDocument`, owns the boundary:** `open(project,label)`, normalized cell/object queries,
`runtime_map()`, raw image loading, and `save()`. XMLParser trees, CSV GIDs, external-path
resolution, containment, TSX properties, and refusal details remain private. Engine,
Studio, ProjectData, ProjectValidator, and tests all call that interface. (4) The tracer
accepts a finite conservative Tiled subset: finite orthogonal TMX, one external atlas TSX,
one full CSV `Ground` layer, 16×16 tiles, and project-contained references. It refuses
empty/flipped GIDs and unsupported pokeredpc object classes loudly rather than guessing.
(5) **Gameplay metadata is namespaced.** Map properties define bridge version, border tile,
and default spawn; TSX tile properties define walkability and optional semantic feet/block
metadata; stable named point objects use `pokeredpc:warp|npc|sign|trigger` classes and
prefixed map/event references. Unknown third-party objects/properties/layers are not runtime
content. (6) **Lossless means source-preserving first:** `MapDocument` retains the original
TMX and TSX bytes, and Phase 5.1's no-op `save()` emits the TMX bytes exactly. Phase 5.3's
targeted writer must patch owned fields while preserving every unrelated node/property; it
may not reserialize the whole XML tree canonically. (7) The tracer fixture is consumed by
the real Engine adapter and the concept-shaped Studio map workspace. Their emitted 64×48
PNG bytes must match, while malformed/newer/path-escaping documents refuse before callers
receive partial state.
**Consequences:** Tiled remains a first-class power-user editor and Studio can add richer
domain controls over the same files. Project art loads from loose project paths rather than
Godot's `res://` import cache. The strict subset leaves infinite maps, multiple tilesets,
tile transforms, terrain painting, targeted XML edits, and world connections to later
demand-driven increments. See [v2/tiled-map-bridge.md](v2/tiled-map-bridge.md) and
[v2/studio-visual-direction.md](v2/studio-visual-direction.md).

## ADR-020 — Studio MVP: one project, canonical write-through, refuse-loud forms (2026-07-22)

**Context:** v2 Phase 4 (gh #18, ADR-013, plan §4.5) builds the Studio MVP — the standalone
editor app: project browser, dockable shell, schema-driven content editors
(species/moves/items/trainers), and live play-test. Phases 1–3 shipped its substrate: the
schema'd project format (ADR-017), the ruleset seam (ADR-018), and the Event VM (ADR-019);
maps stay Tiled-external until Phase 5 and event editing is Phase 5's GUI. Design
conversation held 2026-07-22.
**Decision:** (1) **One Godot project, a `--studio` launch mode** — Main defers to a
StudioShell scene on the flag; no second project. ADR-013's "its own `.exe`" is a
creator-experience promise that Phase 7's packaging satisfies with per-preset main scenes;
until then Studio shares the harness, ProjectData, CoreSchema, and rendering, and the smoke
suite is `--studiotest` in the established flag pattern. (2) **Studio never edits the
extractor-owned `game/project`** (double-extraction byte-identity stays a standing gate);
the browser opens any project folder, and dev/test flows copy Kanto to a scratch project.
The invariant with teeth: **canonical write-through** — a Core GDScript writer emits the
same canonical JSON as the extractor's Python emitter, so *loading and re-saving an
untouched record is byte-identical* (provable by round-tripping the whole Kanto tree);
creator git diffs stay minimal and "Studio didn't corrupt anything" is a trivial check.
(3) **Forms auto-generate from the same `core/schemas/*.schema.json` the validator uses**
(single source of truth); `x-ref` fields render as ID pickers fed by the validator's id
registry; custom widgets (the sprite picker, learnset table, type selector, party builder —
exactly what the four Phase-4 editors demand) register per (content-type, field-path) over
the default widgets — a registry, not a framework. (4) **Refuse-loud at edit time:** inline
per-field constraint feedback while typing, full CoreSchema + reference validation on save,
and an invalid record **cannot be saved** — the boot-refusal philosophy moved into the
editor (softlock lints stay Phase 5). (5) **Live play-test is a separate process:** Studio
spawns the engine (`--project=<dir>` — already live) as a child; a crash cannot take Studio
down, the engine stays unmodified, and in dev it is the same binary re-invoked. Play-test
saves isolate per-project (the test-save-isolation precedent). In-window embedding is
revisited with Phase 5's map editor. (6) **MVP editing model:** per-record forms, dirty
tracking, explicit validated Save and Revert-to-saved; a real undo stack earns its place in
Phase 5 where map painting demands it. (7) **The gate:** `--studiotest` headless — open a
scratch Kanto copy → edit through the real form widgets → save → canonical write-through
asserted (untouched records byte-identical, the edit minimal) → validate 0 errors → launch
the play-test child and handshake — plus a full-project load/re-save byte-identity sweep;
the phase finale is a seed-1 GATE GREEN on a Studio-round-tripped project ("a Studio save
must never produce a project the bot can no longer beat"). Out of Phase 4 by decision:
event editing (Phase 5) and any importer GUI (the pokered importer stays a CLI recipe until
Phase 7).
**Consequences:** Phase 4 decomposes into sub-issues cut from this ADR (the shell + browser
+ launch mode → the canonical writer + round-trip identity → the form engine + refusal →
the four editors' custom widgets → play-test + `--studiotest` + the phase gate), tracked
under gh #18.

## ADR-019 — The Event VM: Kanto's story as schema'd, authored event records (2026-07-21)

**Context:** v2 Phase 3 (gh #17, ADR-013, plan §4.3) replaces the hand-written per-map GDScript
adapters (~80, behind ADR-010's eight hooks — migration-complete since gh #53) and
`Cutscene.gd`'s ~139 functions with **authored events**: a command library, a deterministic
save-aware Event VM, and declarative triggers. The demand list is finite and measured: the
eight hooks with two documented faithfulness rules (the post-battle re-run; `on_step` before
trainer sight — see engine/map-scripts.md), roughly two thirds of Cutscene being story beats
and a third engine ceremonies, plus Main's data-keyed generic mechanisms (`BENCH_GUY_TEXT`,
`GIFT_NPCS`, `HIDDEN_EVENTS`, `_GYM_LEADERS`, elevators, `guard_door`/`thirsty_guard`, …).
Design conversation held 2026-07-21 over the gh #17 brief.
**Decision:** (1) **Three tiers.** Story beats become authored events; engine **ceremonies**
(Cable Club/Trade Center plumbing, credits, the naming screen, fly/fall transitions, Town Map,
slots) stay native, *invoked by* a command, never *expressed in* events; and — the
conversation widened this beyond the brief's default — **all data-keyed generic mechanisms
that are event-shaped migrate to events in Phase 3** (gift NPCs, bench guys, hidden events,
gym leaders, elevators, guard doors, …), so the event system is proven against every shape
Kanto has and the engine ends leaner. Per-frame/global *data* (`FLY_DESTS`, `DARK_MAPS`,
fishing tables) stays project data, not events. (2) **Data model per ADR-017:** per-record
`data/events/<id>.json`, an `event:` id namespace, the `custom` bag,
`additionalProperties: false`, schemas in `core/schemas/`. A command is `{cmd, args…}` in an
ordered list; **branching is nested blocks** (`if: {cond, then, else}`), no jump labels —
Kanto's branches are shallow and blocks map 1:1 onto the Phase-5 command-list editor.
(3) **Conditions reuse Phase 2's FormulaExpr** (flags/vars as named variables) — one
expression language in the toolkit, already integer-exact, schema'd, and sweep-proven.
(4) **Triggers are declared by the event record** (`{map, kind, cell|object|region, consume,
when}`), never written into map files — the interim map JSON stays geometry-only, so the
Phase-5 TMX bridge migrates no story. `object_shown` becomes a declarative `visible_when`
condition (a query, not a VM run) and `on_step` dispatch is indexed by `(map, cell)` at load
(plan risk 7: no VM in tight overworld loops). The boolean hook contracts (consume the
step/warp/interact; null fall-through on visibility) carry over as trigger fields, and the
dispatcher preserves the two faithfulness rules by construction. (5) **VM semantics:**
deterministic, coroutine-based over the same await primitives Cutscene uses today; **one event
active at a time** (`cutscene_active` *is* the mutual exclusion, proven by v1); durable state
is **flags + variables** (`story_events` generalized plus a saved vars store), event names
staying **byte-exact** with v1's — they are the save format; events are **atomic w.r.t.
saves** (the menu cannot open mid-event; the trade journal stays the engine-side exception).
(6) **Command library only on demand:** plan §4.3's list plus what the beat inventory adds
(walk/walk_together choreography, emotes, pic show/slide/clear, fades, wait/wait_button,
ask_name + presets, give_mon + the nickname offer, static-encounter battles, set_block,
show/hide_object, sfx/music cues, the ceremony natives) — each command lands with the beat
that demands it, never ahead of one. (7) **Authored events live in-repo; the extractor
byte-copies them into the emitted project** (the interim-maps pattern): events cannot be
extracted from the asm, and ADR-017 D6's "one tool" holds — no second path ever exists.
(8) **Strangler-fig migration with a tracer bullet first** — one real adapter + one Cutscene
beat through the full pipeline (schema → authored record → trigger → VM), that map's `--flag`
selftest green, before any mass migration; every migrated map keeps its selftest green and
the four `--battledettest` md5s never move.
**Consequences:** Phase 3 decomposes into sub-issues cut from this ADR (Core schemas + the VM
+ the trigger dispatcher, carrying the tracer; adapter migration in waves by mechanism family;
Cutscene beats by questline; extractor emission + event-data lints — `audit_chokepoints`
learns to read event data, since data can seal a path as easily as code; the phase gate: the
bot NEW GAME → HALL OF FAME on the fully event-driven build, seeds 1+2, the audits, the four
md5s, the link suites, cross-OS determinism). The command definitions in Core are exactly what
Phase 4's Studio forms and Phase 5's command-list editor consume.

## ADR-018 — The ruleset seam: interface modules in Core, gen1 native, expressions proven beside it (2026-07-20)

**Context:** v2 Phase 2 (gh #16, ADR-013, plan §4.2) puts battle / catch / types / formulas /
progression behind ruleset interfaces, with the Gen-1 rules becoming the built-in `gen1`
ruleset. The mechanics are fused today: `Battle.gd` (4.2k lines) mixes turn resolution, damage,
status, AI, and catch with presentation; stat-calc and exp curves live in `Main.gd`; the
manifest already names `ruleset: "gen1"` but nothing consumes it. The refactor oracle is the
strongest we own — the `--battledettest` per-scenario md5s must not move by a byte, the bot
still beats Kanto, and the link suites stay green (link battles run through the seam on both
peers). Design conversation held 2026-07-20; the issue assigned three decisions.
**Decision:** (1) **Module boundaries:** Core (`game/core/ruleset/`) defines five interfaces —
**Battle** (`battle state + chosen actions → the ordered event stream`; v1's ADR-009
message/marker queue *is* this contract already), **Types** (the data-defined chart +
resolver), **Formulas** (damage / accuracy / crit / catch-rate / stat-calc / exp-curve as a
formula provider), **Catch**, and **Progression** (flags + gate conditions, generalizing
badges and HM gates). The engine keeps presentation — drawing, HUD, move animations consume
the event stream and never compute mechanics. A built-in **registry** resolves the manifest's
`ruleset` string to an implementation; `game/rulesets/gen1/` is the only entry. (2) **The
Gen-1 trainer AI is part of gen1's battle module**, not a separate interface — the AI layers
and 19 item/switch handlers are Gen-1 mechanics; an AI seam waits until the second sample
demands one (no speculative generality). (3) **Formula layer: interface + native gen1.** The
`gen1` formulas stay native GDScript (asm-faithful, byte-identical — expressions cannot cheaply
reproduce Gen-1's integer truncation and overflow quirks under the md5 gate). The
**expression evaluator** (named variables, operators, integer-exact semantics: truncating
division, explicit clamps) still lands in Phase 2 as an *alternate* formula provider, proven by
an equivalence sweep against gen1's native formulas over a fixed test-vector matrix — real
running code, but not on gen1's hot path. Exotic math waits for the Phase-6 hatch. (4)
**Config-first knobs: only what is already data.** The type chart (already a project content
type), the badge-boost mapping, exp growth curves, stat-stage multipliers, and crit-rate
parameters are formalized as a schema'd `data/ruleset.json` singleton (base + config) emitted
by the extractor with the faithful gen1 values; absent keys fall back to gen1 built-in
defaults. No invented knobs — Phase 6's config UI decides what else earns exposure. (5)
**Strangler-fig extraction**, module by module, `--battledettest` after every move — the
oracle only localizes faults if the steps are small. ADR-017's deferred positional-index
internals migrate opportunistically as each mechanic is touched.
**Consequences:** Phase 2 decomposes into sub-issues cut from this ADR (interfaces + registry
+ a delegating gen1 skeleton; types + formulas through the seam; the battle module + link
through the seam; catch + progression + the ruleset config record; the expression evaluator +
equivalence sweep, carrying the phase gate). Battle presentation's only input becomes the
event stream, which is exactly the boundary Phase 3's Event VM and Phase 4's live play-test
need. The `data/ruleset.json` addition is additive under `format: 1` (defaults apply when
absent). The deliverable is unchanged: the bot beats the game *through* the seam and no
determinism stream moves by a byte.

## ADR-017 — The v2 project format: JSON-schema'd, per-record, ID-addressed, importer-emitted (2026-07-20)

**Context:** v2 Phase 1 (gh #15, ADR-013, plan §4.1) separates Engine from Project: today's
`game/assets/` is ~30 extractor-emitted per-type JSON monoliths + PNGs, loaded from hardcoded
`res://` paths and resolved *positionally* in pokered's constant order. The project format is a
public API from its first version, so its shape — including the escape hatches it will need
later — is a now-decision. Design conversation held 2026-07-20. Three things were treated as
settled going in: **Core lives in this repo** (`core/`: schemas + the shared loader — every
phase refactors v1 in place toward flagship-sample status, and the bot must gate each step);
the **manifest carries a content-hash identity** grown from `link_manifest.json`, hashing
*canonical* bytes (the gh #12 newline lesson generalized); and **schemas are data, not code**
(JSON Schema documents in `core/schemas/`, one per content type — the single source that later
drives Studio's forms, validation, and docs).
**Decision:** (1) **Serialization: JSON + JSON Schema** — native to Godot and the web-export
portability budget, machine-validatable, diff-friendly pretty-printed with sorted keys; the
canonical form doubles as the identity-hash input. No comments is acceptable: the editor is the
primary authoring surface, and `description`/`$comment` fields carry prose. (2) **Granularity:
hybrid by shape** — per-record files for entity collections (`data/species/bulbasaur.json`,
moves, items, trainers, maps, events: clean diffs, no merge collisions, the editor writes one
file per edit); single files for genuine tables and singletons (the type chart, per-map
encounter tables, the world graph). (3) **Extensions: a reserved `custom: {}` bag on every
record now** — validated free-form; everything else `additionalProperties: false`, so strict
validation catches typos from day one while Phase-6 creator fields land inside a namespace
Phase-1 projects already carry. Schema overlays (whole new content types) stay deferred until
demanded. (4) **Stable string IDs (`species:bulbasaur`, `move:tackle`) are the format's
addressing; the Phase-1 loader resolves them onto v1's existing internal structures** — the
positional-index internals migrate opportunistically in Phase 2, where the ruleset seam
re-touches every mechanic anyway. (5) **Maps carry v1's extracted map JSON as a documented
interim format**; the TMX switch lands with the Phase-5 Studio/Tiled bridge, whose design owns
the object/property convention — under the versioning policy below that switch is just a
format bump with a migration, not a break. (6) **One tool, not two: the extractor emits the
project.** `tools/extract.py`'s output format *becomes* the v2 project — pokered clone in,
Kanto project folder out — so the "v1 → project converter" and plan §4.6's permanent pokered
importer are the same artifact from day one and no second asset format ever exists.
(7) **Versioning: an integer `format` in the manifest + linear, explicit, tested migrations**
(1→2→3…); the engine migrates older projects forward and refuses newer ones naming both
versions — the link-identity refusal pattern applied to loading.
**Consequences:** Phase 1 decomposes into sub-issues cut from this ADR (schemas + Core loader;
manifest + identity; the extractor's project emission; the runtime's project loading — gh
#22–#25). Project identity is cross-OS by construction (canonical-form hashing). The schema
set written here is the exact input Studio's Phase-4 form engine consumes. The interim map
format is explicitly versioned data, so its TMX migration is routine rather than a compat
crisis. The deliverable and gate are unchanged: v1 runs unchanged from a project folder, the
seeded bot beats it, `--battledettest` md5s stay put, and the cross-OS determinism workflow
re-dispatches green.

## ADR-016 — Link session resume: live-transport reconnect + reconcile (2026-07-20)

**Context:** v1.1 tears down any dead link — battles end stakeless, trades resolve via the phased
journal, players walk back to the attendant — which is correct but unfriendly, and it leaves
ADR-015's documented two-generals residue: an ack lost in transit at the instant of a drop can
strand the peers on opposite sides of the trade decision. Only a reconnect + reconcile
conversation can close that window (gh #13). Design conversation held 2026-07-20; six decisions.
**Decision:** (1) **Scope: transport blips only** — both game processes still alive, the socket
died (Wi-Fi drop, cable pull). A process death keeps today's teardown + journal-recovery story;
persisting battle state for relaunch-resume is out of scope. (2) **Grace window: ~120 s,
player-cancellable** — the survivor shows "Link lost — waiting for your partner…", B gives up
immediately into today's teardown; the host keeps listening on the session port, the joiner
auto-redials with backoff. (ADR-015's human/machine-paced rule doesn't apply: during an outage
there is no liveness to bind to, so this wait gets its own bound.) (3) **Resume identity: a
session token** minted by the host at link-up rides the normal identity handshake on
reconnection; a wrong or absent token takes the ordinary fresh-session path, so a stranger can
never join into a half-open session. (4) **Reconcile rules by state:** *mid-battle* — compare
last-acknowledged turn + RNG cursor + state digest from the lockstep stream: equal → continue,
one action in flight → retransmit it, digests differ → a determinism bug by definition, void
stakeless as today, loudly logged; *trade pre-commit* — restart at the pick screens (parties
re-exchanged; nothing at stake, keeps the reconcile protocol tiny); *trade commit* — exchange
journal phases: `acked`+`acked` → both apply, `acked`+`ready` → roll the ready side forward
(**the two-generals closure**), `ready`+`ready` → roll back to picks; *pre-table states*
(attendant flow, save beat, LinkMenu) — teardown as today. (5) **The dupe easter egg is
relaunch-only:** resume reconciles honestly even for opted-in sessions — the glitch keeps its
faithful power-cut ritual (kill the game in the ack window and relaunch), and a lag spike can
never fork a mon. (6) **Ships as v1.2.0** (a player-visible capability + a new protocol surface
= a feature milestone), with the milestone kept pure: ADR-015's parked faithfulness item
(link MIMIC's real pick menu; the items half of the pair turned out to be faithful already —
see the ADR-015 correction) stays parked. **The gate is the house
two-stage:** Stage 1 — a `--blipat` injection mode that resets the ENet connection *without*
killing the process, scripted across mid-battle turns, every trade phase, and the ack window,
plus a blip-soak, asserting resume + byte-identical streams and every commit-phase case ending
consistent on both saves; Stage 2 — a real remote human session with genuine Wi-Fi drops.
**Consequences:** the two-generals residue is closed for live processes — the only case a
reconcile can reach, since a relaunch already resolves correctly (and deliberately, for the
egg) via the journal; teardown remains the universal fallback wherever resume doesn't prove
itself; the wire grows a session token and a small `resume`/reconcile vocabulary but the
lockstep and journal semantics are unchanged — reconcile only *reads* them.

## ADR-015 — Lockstep implementation: mirrored sims, canonical streams, presumed-commit trades (2026-07-19)

**Context:** Building ADR-014 (gh #2–#9) forced implementation-level choices the design left open, several
of them non-obvious and one a deliberate divergence pair.
**Decision:** (1) **Mirrored simulations with canonical labels** — each peer simulates with itself as the
"player" side (as pokered's link battles do) rather than one side rendering a flipped "host view". The
asymmetric rules are neutralized exactly as the asm neutralizes them for `LINK_STATE_BATTLING` (no badge
boosts, no hidden stat-down miss, no EXP), speed ties read the shared coin canonically ("heads = the HOST
acts first"), the opponent presents as **OPP_RIVAL1** (cable_club.asm), and the lockstep oracle emits
role-canonical lines (host side first on both peers) so byte-equality still defines "in sync". (2) **The
mon record carries `maxpp` explicitly** — deriving it from the current move table refused real saves whose
PP history predates a table fix; what the save says is what travels, bounded only by Gen 1's 64 ceiling.
(3) **Trades are presumed-commit past the ack** — the journal phases `ready` (roll back) and `acked`
(written before the ack leaves; recovery rolls forward, silent trade evo included). The un-closable
residue — an ack lost in transit at the instant of a real cable pull — is the two-generals bound,
documented in engine/link.md; closing it needs the gh #13 reconnect conversation. The dupe easter egg is
implemented as a deliberate `acked`-rollback under mutual opt-in; an asymmetric opt-in refuses the whole
session. (4) **Two documented divergences** keep both sims trivially identical until a later faithfulness
pass: items are refused in link battles (the cartridge allows them; enemy-side application of every bag
item is deferred), and link MIMIC copies a deterministic random technique (a mid-turn menu pick can't
cross the wire mid-resolution). *[Correction 2026-07-20: the items half was wrong — the cartridge
refuses items in link battles too (`core.asm` BagWasSelected's `LINK_STATE_BATTLING` guard,
`ItemsCantBeUsedHereText`), so the refusal is faithful, not a divergence; the port now refuses at
menu selection with the faithful text. Only the MIMIC pick remains a documented divergence.]* (5) **Human-paced waits are liveness-bound** — only machine-paced protocol
replies keep timers, and a machine timeout actively closes the link; a friend thinking for a minute is the
game working, not a drop (the first playtest's "frequent disconnects" were a 30 s timer).
**Consequences:** the desync soak (gh #8) validates the whole construction at volume (its first battery
caught three real lockstep bugs); every divergence and the two-generals bound are documented rather than
silent; gh #13 (session resume) and the items/Mimic faithfulness pass are the recorded follow-ups.

## ADR-014 — v1.1 multiplayer is the faithful Cable Club over deterministic lockstep (2026-07-17)

**Context:** ADR-013 committed multiplayer as a v1.1 feature whose extended design conversation happens
immediately after 1.0 — it gates v2 because it pins the requirements v2's Core would otherwise guess at
(deterministic/serializable battle state, a portable mon/state model, project identity). 1.0 shipped
2026-07-17; the conversation was held the same day. The personal-use constraint frames everything: builds
and extracted assets are never distributed, so the other player has always built pokeredpc themselves
from their own `pokered/` clone.
**Decision:** (1) **Audience: trusted peers, direct connect** — you plus friends running their own
builds, over LAN or direct IP (Godot high-level multiplayer / ENet); no servers, accounts, matchmaking,
or anti-cheat. (2) **Scope: the faithful Cable Club only** — link trades and link battles through the
Pokémon Center upstairs, asm-faithful semantics including trade evolutions; no overworld presence in 1.1
(a candidate for later). (3) **Authority: deterministic lockstep**, the cartridge's own model — a shared
RNG seed at link-up, only the players' chosen actions cross the wire, both engines simulate and must
agree; a desync is by definition a determinism bug. This ships v2 §4.7's "seed + action log → reproducible
battle" contract as tested reality. (4) **Wire format: a versioned mon-record schema** with stable string
IDs (`species:…`, `move:…`) and explicit fields, translated at the link boundary — v1 internals stay
index-based; the schema is the mon record v2's Core inherits, formalized once. (5) **Handshake: strict
identity** — exact `VERSION` match plus a content hash over link-relevant extracted data (written at
extraction time); any mismatch refuses the session naming the differing part. Lockstep turns silent data
drift into an undebuggable mid-battle desync, so refusal is the only sane failure mode; this prototypes
v2's project-identity manifest. (6) **Connect UX: the Cable Club attendant is the seam** — she offers
HOST / JOIN (IP entered on the Gen-1 naming-screen keyboard); everything after link-up follows the asm.
`--host` / `--join <ip>` debug flags exist for automation. (7) **Disconnects: atomic trades with the dupe
glitch as a mutual opt-in easter egg** — a trade commits two-phase (a drop completes on both sides or
neither; a battle drop is stakeless, as on cartridge), but the classic cable-pull duplication glitch is
deliberately preserved behind an opt-in flag that is **symmetric**: advertised in the handshake and active
only when *both* peers enabled it, refused otherwise, so the two saves can never disagree about what a
trade did. (8) **The 1.1 gate is a two-stage hybrid**, rhyming with ADR-011 — Stage 1: headless bot-vs-bot
over localhost (a seeded desync soak asserting byte-identical battle event streams every turn; a scripted
trade round-trip including a trade evolution with both saves verified; drop-injection proving no dupe and
no loss, and that the easter egg fires only under mutual opt-in). Stage 2: a real remote human session —
trades, battles both directions, at least one genuine disconnect — under ADR-011's log-and-continue policy.
**Consequences:** The battle engine must be strictly deterministic on every code path (no
frame-rate-dependent RNG draws, no float drift) — an audit v2 needed anyway, now forced early with the
soak as its permanent oracle. The no-dupe default is a **documented divergence** from cartridge behavior
(like the credits table-read clamp): the dupe is a hardware save-timing accident, not authored asm, and an
accidental Wi-Fi blip forking a friend's mon is the worst outcome 1.1 could produce — hence safe by
default, glitch by mutual consent. Three v2 Core requirements are now pinned artifacts instead of open
questions: the reproducible-battle contract, the mon-record schema, and the content-hash identity. v2 work
remains gated on 1.1 shipping, not merely on this design existing.

## ADR-013 — v2 is a generic monster-RPG creation toolkit, not just a moddable port (2026-07-12)

**Context:** Beyond 1.0, the project's direction is to become **a toolkit others use to build and ship
their own fan games** — a visual map editor (Tiled-based), graphical content editors (species, trainers,
moves, …), and in-map event/script authoring, with *every system extensible and easily modifiable*. That
goal forks four ways at the foundation, each of which reshapes the whole architecture: how far to
generalize beyond Gen-1; how creators author logic; where the editors live; and how v2 relates to v1's
hard-won, asm-faithful codebase. The full design is in [v2/plan.md](v2/plan.md).
**Decision:** (1) **A generic, module-based monster-RPG engine** — battle, catching, types, formulas,
and progression are pluggable/configurable modules ("rulesets"), not hardcoded Gen-1; the engine knows
the *interfaces*, a built-in `gen1` ruleset supplies faithful implementations. (2) **Layered event
authoring** — a GUI command-list event system for the common 90%, with a *sandboxed* scripting hatch for
the rest (not raw GDScript — shared games must not run arbitrary code). (3) **A standalone editor app**
(its own `.exe`; creators never open Godot) with the **Tiled TMX format** as the native map format. (4)
**v1 becomes the flagship sample** built on the v2 engine — rebuilding faithful Kanto as a v2 project
(and the legit-play bot still beating it) is the toolkit's acceptance test. The unifying reframe:
separate the **Engine** (code) from the **Project** (a portable, shareable folder of data + maps +
events + a ruleset), joined by a shared **Core** (schema + interfaces) so the runtime and editor cannot
drift.
**Consequences:** This is the ambitious path on every axis, so the plan is explicitly **phased and
gated**. **Multiplayer is a committed v1.1 feature that lands *before* v2** (the extended design
conversation is deferred to immediately after 1.0) — and it gates the start of v2, because it sets the
requirements for the very Core v2's Phase 1 would formalize (deterministic/serializable battle state, a
portable state/save model, project identity for compatibility). So the sequence is **1.0 → v1.1
multiplayer → v2 phases** (Core/project format → ruleset seam → event VM → Studio MVP → map/event editors
→ scripting + config → second sample), each independently shippable and regression-gated by the bot + the
audits. Platforms are asymmetric: **Studio stays desktop; finished games export as widely as feasible**
(desktop/web/mobile), which is a portability budget on the runtime + scripting sandbox. Two hard
constraints fall out immediately: a **sandboxed scripting layer** must be designed up front (security of
shared games *and* web/mobile export), and the **project format is a public API** the day people build
games (version + migrate it from the start). And a legal one: v1's
extracted Nintendo assets are personal-use, so the distributable toolkit **never ships them** — the
faithful Kanto pack is delivered as the **pokered importer** (v1's `extract.py` generalized), so each
creator supplies their own `pokered/` clone and extracts locally for personal use, exactly as v1 does;
a small **CC/original placeholder pack** ships for an out-of-box start. The guardrail against becoming "a
worse Godot" is *no speculative generality* — every abstraction must be demanded by reproducing v1 or a
second sample.

## ADR-012 — The legit-play bot clears obstacles by kind, not by proof (2026-07-09)

**Context:** `_pt_walk_dungeon` plans around NPCs, because a real player cannot walk through them.
When no NPC-free path to the goal exists, *something standing on the floor* is the door. Three kinds
occur: an undefeated sight-trainer holding a corridor (it marches off its tile to intercept); an
**item ball**, which is a solid sprite — Pokémon Tower 6F's RARE CANDY (6,8) sits on the single-tile
passage into the whole southern half of the floor, so the 7F stairs are unreachable until you take it;
and a **locked card-key door** on a Silph Co floor, which is a *block*, not a sprite, laid on load by
the floor's `GateCallbackScript`. Deciding *which* object is the articulation point is a graph problem;
the bot only has "no path".
**Decision:** On a dead plan, try the kinds in order — trip the nearest reachable guard
(`_pt_trigger_guard`), take the nearest reachable item ball (`_pt_take_blocking_item`), then open the
nearest reachable card-key door (`_pt_open_blocking_door`) — each attempted at most once per walk, then
re-plan. None is proven to be the blocker; all are ranked by path length. If all are exhausted,
`_pt_report_blocked` names every standing object and every still-locked door before failing.
**Consequences:** Simple, bounded, and terminating (a beaten trainer, a taken ball and an opened door
all stop blocking, so progress is monotone). The cost is that a stuck floor may clear a bystander first
— a one-time overworld item and a `picked_items` write, or a door it did not need — before it reaches
the real blocker. That only ever happens on a leg that had no legal move left, so it buys a dead-end
where it would otherwise report one. Proving the articulation point would be strictly better and is not
worth it on the critical path. A give-up now names the things in the way, which is what actually debugs
the leg. Doors are tried last for two reasons: the check is free to rule out (it needs the CARD KEY and
a Silph Co floor, so it returns immediately everywhere else, leaving every previously-tuned floor's
behaviour untouched), and a guard standing between us and a door makes that door unreachable anyway —
so clearing guards first never wastes a re-plan on a door the walk could not have reached.

## ADR-011 — The 1.0 sign-off is a two-stage hybrid gate (2026-07-07)

**Context:** Versioning treats `0.9.x` as **audit parity** — every system verified in isolation by
the `--<flag>test` suite — and reserves `1.0.0` for a "complete playthrough sign-off", on the
principle that audits prove systems but only a full run proves the game. That sign-off was
otherwise undefined: what proves the game, who plays, what a "pass" is, and how a mid-run bug is
handled were all open. See the glossary in `CONTEXT.md`.
**Decision:** The sign-off is a **two-stage hybrid gate**. **Stage 1 — automated legit-play run:**
a headless, **seeded** bot (a new `--seed N` hook replaces `Main.gd`'s `randomize()` for
determinism) plays the critical path *on merit* — real grinding, battles won, money earned, no
injected levels or items — as a **persistent player** (on a whiteout it heals, grinds, retries). It
runs as one continuous process from NEW GAME to credits, autosaving at each town/milestone with a
progress log, so a failing leg is debugged by resuming from the last autosave. It asserts
**completability**: the only failures are a **dead-end** (the critical path is unadvanceable by any
play), a softlock, or a crash — a lost battle is never a failure. **Stage 2 — human playthrough:**
complete the critical path plus the **side-system checklist** (each optional system touched once in
real context), on a **different starter** than the auto-run for branch coverage, under a
**log-and-continue, two-tier** bug policy — blocking bugs (softlock/crash/save-corruption) stop the
run and are fixed then resumed from the last autosave; non-blocking bugs (cosmetic/text/audio/nits)
are filed and batch-fixed. Every finding is a GitHub issue. During a sign-off run, save-schema
changes are **additive-only** (JSON tolerates missing keys → defaults); a semantic change means
reload + re-verify the affected area (no migration layer — the auto-run is NEW-GAME-immune anyway).
**To tag 1.0**, on the tagged commit: the auto-run is green, the full selftest suite is green, there
are zero open blocking bugs, all non-blocking bugs are triaged (fixed or deferred with a rationale),
and the human has spot-checked the fixed areas — **no full replay**. The sign-off is tracked in one
"1.0 sign-off" GitHub issue (checklist + auto-run seed/log + human notes + bug links + the final
gate checklist); on sign-off, bump `VERSION` + `project.godot` (`application/config/version`) to
`1.0.0`, tag `v1.0.0`, update `CHANGELOG.md` + `CHANGELOG-forum.md`, and close the issue.
**Considered alternatives:** a *sole human gate* (no automated run) — rejected: a permanent
end-to-end smoke run is wanted as a cheap pre-flight before sinking hours into a human run. A
*gate-traversal smoke* (inject levels/items, force battle outcomes, assert only that gates fire) —
rejected in favour of legit-play so the run earns its way through on merit. *Making a lost battle a
failure* — rejected: it would couple the release gate to bot-skill tuning; the persistent-retry
policy asserts completability instead.
**Consequences:** Stage 1 is a substantial build — a competent **play policy** (party management,
winning Gen-1 move choice, grind/heal/retry loops), `find_path` navigation across the 223 maps, the
`--seed` determinism hook, and milestone autosave — comparable to a mid-size game system, worth its
own milestone/issue before the sign-off begins. A weak play policy is a *bot* problem, not a game
bug, and must never block 1.0 (only dead-ends/softlocks/crashes do).

## ADR-010 — Per-map script adapters behind the MapScripts seam (2026-07-03)

**Context:** Per-map behaviour had accumulated in `Main.gd` as three flat dispatch chains
(`interact` ~380 lines, `_on_player_moved` ~155, `_on_map_loaded`), the `_object_shown`
visibility match, four warp gates inside `_do_warp`, and ~24 hand-authored gimmick tables —
while `MapScripts.gd`, the seam designed for exactly this, was instantiated and never called.
Issue #22's remaining beats would have kept growing those chains.
**Decision:** `MapScripts.gd` becomes the `MapScript` base class with five hooks — `on_enter`,
`on_step(cell)`, `on_interact(front, npc)`, `on_warp(w, dest_const, dest_label)`,
`object_shown(k)` — one adapter per scripted map at `scripts/maps/<MapLabel>.gd` (1:1 with
pokered's `scripts/<Map>.asm`), discovered by naming convention, cached per label, **stateless**
(durable state stays in `story_events`; event names/save format unchanged). Adapters own their
map's triggers + gimmick-table rows; Cutscene keeps the beat coroutines; engine-generic
machinery (sight, warp fade, encounters, ticks, spin-tile data) stays in Main. `on_step` runs
**early** — before rebase/warps/sight — restoring pokered's script-runs-first frame order (the
old sight-before-gates priority was the unfaithful one). Adapters hold `main` (as pokered
scripts hold WRAM) plus the base-helper vocabulary; see
[engine/map-scripts.md](engine/map-scripts.md).
**Consequences:** one map = one module; Main's dispatchers shrink to one call per touchpoint;
remaining #22 beats land as adapters. Migration is family-by-family (gh #53), each guarded by
its `--flag` selftest, with a per-family asm check for step-priority changes. Counter-indirect
NPCs aren't passed to `on_interact` yet (generic flow still resolves them) — revisit when the
mart-like maps migrate.
*Post-migration (same day):* the sweep grew the interface to **seven hooks** — the counter
resolution moved ahead of `on_interact` (mart-like maps), and `try_push_boulder` needed
`boulder_hole` (pre-shove hole query) + `on_boulder` (switch/fall effects). Data-keyed
mechanisms (bench guys, text-id gifts, hidden events, gym guides, fishing) stay generic in
Main by design — see [engine/map-scripts.md](engine/map-scripts.md).

## ADR-009 — Battle presentation via message-queue markers + a displayed-HP mirror (2026-07-01)

**Context:** The battle narrates a turn through a **message queue** (strings + marker dicts) that
`_next_msg` walks, one item per input/tween. New Gen-1 sequences (HP-bar drain `UpdateHPBar2`,
faint slide `SlideDownFaintedMonPic`, send-out `POOF_ANIM`, level-up `PrintStatsBox`) each need to
fire at a **specific point** in that narration, and HP changes happen up front in the turn logic
(before any message shows), so the HUD can't just read `mon.hp`.
**Decision:** Extend the same queue: animation steps are marker dicts (`{"hp"}`, `{"faint"}`,
`{"intro"}`, `{"levelstats"}`) inserted where they should play; each sets `state="anim"`, runs a
tween, and calls `_next_msg` on finish. The HUD reads a per-side **`_shown_hp`** mirror that
`_set_hp` drains toward the real value via an `{"hp"}` marker (2 frames/pixel); a `_process` sync
snaps it when a mon is (re)sent-out or between actions. A **`battle.fast_hp`** flag (set for every
test via the cmdline-user-args check) skips these animations so logic tests stay fast and their
`while state == "msg"`-style loops don't stall on `"anim"`.
**Consequences:** animations compose with the existing text flow with no separate scheduler; every
in-battle HP change routes through `_set_hp` for a consistent drain. Cost: tests must advance past
`"anim"` states (or set `fast_hp`), and render tests **pose** stages (`_intro_stage`/`_faint_who`/
`_shown_hp`) for still captures. Per-move attack animations (issue #19) will reuse this marker model.

## ADR-008 — Text resolution follows script indirection (2026-07-01)

**Context:** `build_text` mapped each `TEXT_id` to its script label's **first** `text_far` string.
Any NPC/sign whose dialogue isn't a direct `text_far` — `text_asm` handlers that `PrintText` via
`ld hl, <Label>`, trainers that `TalkToTrainer <Header>`, and shared labels defined in `home/`
or `engine/` (Poké Center/Mart signs) — resolved to nothing, leaving **~550** references blank
(≈41% of all map text). Talking to those NPCs showed an empty box (e.g. the Cable Club receptionist).
**Decision:** Resolve a `TEXT_id` by following indirection: direct `text_far`, else the trainer
header's before-battle text, else the first `ld hl, <Label>` reference — scanning `scripts/`,
`home/` and `engine/` and matching exported `Label::`. `parse_text_strings` also reads `data/text/`.
**Consequences:** text ids resolved went 666 → 1036. Trainers already carried before/after text via
ADR-007, so this mainly restores **non-trainer NPC chatter and signs**. The `ld hl` heuristic picks
the first referenced text, so an event-branched NPC may show a different-state (but valid) line; the
handful of remaining blanks are pure script NPCs already covered by engine handlers (trades, prize
vendors, elevators). Run `audit_text.py` to re-check coverage after extractor changes.

## ADR-007 — Trainer sight data folded into the map JSON (2026-06-30)

**Context:** A trainer's view range and before/end/after-battle text live in the per-map
**script** (`scripts/<Map>.asm` `trainer` headers), separate from the `object_event` it belongs
to (`data/maps/objects/<Map>.asm`). The engine only consumes the extracted map JSON.
**Decision:** At extract time, parse the ordered `trainer` headers and **zip** them onto the
trainer `object_event`s (declaration order — pokered numbers trainer sprites consecutively), so
each trainer carries `sight` + resolved `battle_text`/`end_text`/`after_text` in one record.
Detection mirrors `trainer_sight.asm` (lined up, in front, within range, **no** obstacle check);
defeat is keyed by the trainer's **home** cell since the trainer moves during the walk-up.
**Consequences:** The engine needs no separate trainer-header asset and no asm at runtime; all
trainer data is in the map JSON. Couples to pokered's convention that trainer object_events are
consecutive. The `!` indicator reuses the extracted `shock` emote (`emote_shock.png`).

> Correction (2026-07-03, gh #55): headers bind to consecutive **absolute sprite indices**
> starting at `def_trainers N`, not to trainer objects in filtered order. Gyms use
> `def_trainers 2` because the leader (sprite 1) has **no header** — leaders are talk-only;
> the filtered zip had been giving every gym leader the first trainer's sight range and battle
> text. Static-encounter mons (Voltorbs, legendaries) whose headers point at species objects
> get nothing attached (they engage on interact), reported by the extractor as `!` warnings.

## ADR-006 — Tall-grass transparency via shader, not a baked asset (2026-06-29)

**Context:** The grass leg-overlay drew the opaque grass tile, hiding legs under a solid
block. GB shows the sprite behind the blades (BG colors 1-3) but in front of the gaps (color
0). **Decision:** Apply a tiny `canvas_item` shader to the overlay sprites that discards the
grass tile's lightest shade, instead of extracting a separate transparent grass asset.
**Consequences:** No new assets; works for any tileset's grass tile automatically; the rule
("lightest shade = gap") lives in one place. Couples to the GB green palette in `extract.py`.

## ADR-005 — Overworld tile effects driven by extracted data (2026-06-29)

**Context:** Ledges and tall grass are tile-property mechanics in pokered (`LedgeTiles`,
the tileset `grass_tile`). **Decision:** Extract those tables into the tileset JSON and have
the engine apply them generically, rather than hardcoding tile ids in GDScript.
**Consequences:** Mechanics work across every applicable map/tileset from data; adding a new
effect = extract a table + a small engine rule. See `engine/ledges-and-grass.md`.

## ADR-004 — Connections as a multi-map "world" + rebase (2026-06-28)

**Context:** Maps connect seamlessly (routes ↔ towns); pokered streams a 3-block border
strip and switches maps at a threshold. **Decision:** Load the active map plus its neighbors
into a `placed[]` "world" (each at a block offset, own tileset + collision), render/collide
across the seam, and **rebase** the active map when the player steps onto a neighbor.
**Consequences:** Simple and seamless (camera-follow hides the rebase); neighbors are drawn
in full rather than as a strip (fine — drawn once per load). See `engine/connections.md`.

> Note: collision sampling was corrected from top-left to **bottom-left** of each cell
> mid-project (see `engine/collision.md` history) — a bugfix, not an ADR.

## ADR-003 — Custom `_draw()` instead of TileMap (2026-06-28)

**Context:** Need to render block-based maps; authoring scenes by hand (no editor GUI).
**Decision:** Render the overworld with a custom `Node2D._draw()` blitting 8×8 tile regions.
**Consequences:** Full control, text-authorable, trivial to map pokered's block/tile model.
May revisit `TileMapLayer` if maps get large/animated or need built-in Y-sort.

## ADR-002 — Godot 4.7, portable binary (2026-06-28)

**Context:** Need a 2D engine that exports a native Windows `.exe` with minimal toolchain
friction; user had no C compiler but did have a 2D-friendly path available.
**Decision:** Godot 4.7, GDScript. Engine binary kept **portable** in `tools/godot/` rather
than installed system-wide.
**Consequences:** No system install; self-contained repo. CLI/headless via the `_console`
build. Export to native `.exe` later via Godot export templates.

## ADR-001 — Data-driven reimplementation, not emulation or asm→C (2026-06-28)

**Context:** "Port pokered to PC." Options: (a) build ROM + emulator [rejected: user wants a
real native port], (b) static recompile asm→C, (c) reimplement the engine on extracted data.
**Decision:** (c) — extract pokered's data to PNG+JSON, reimplement the engine natively.
**Consequences:** Clean, modifiable, genuinely-native result; most *content* comes for free
via extraction. Engine logic must be hand-written against the disassembly as spec. Avoids
(b)'s unmaintainable blob that would still need PPU/APU/timing emulation. Larger up-front
engine effort, but incremental and finishable.

> Legal note: the disassembly is code, but a playable result needs Nintendo's copyrighted
> assets. Personal use only; do not distribute extracted assets or builds.
