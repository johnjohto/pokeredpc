# The v2 project format (formats 1 and 2)

The **Project** is v2's shareable artifact (ADR-013, ADR-017): a portable directory of
data + maps + assets + a ruleset selection that `Engine(Project) → playable game` and
`Studio(Project) → edits the same Project`. **Format 1** was pinned by ADR-017 and
implemented from gh #22 on. **Format 2** (ADR-021, gh #52) replaces interim JSON maps with
native Tiled TMX/TSX while retaining format-1 loading; Kanto migrated in gh #53/ADR-023. From
format 2 onward, incompatible changes are format bumps plus linear migrations.

## Serialization

Project records use **JSON, validated by JSON Schema** (draft 2020-12), in **canonical form**: pretty-printed
(indent 1), sorted-key-stable where machine-emitted, UTF-8, LF, trailing newline. The
canonical bytes double as the identity-hash input (gh #23). No comments — schemas carry
`description`/`$comment`, and the editor is the primary authoring surface. Native maps are
the exception: Tiled's XML TMX/TSX is source-preserving, and a no-op Studio save is byte
identical rather than canonically reserialized. See [tiled-map-bridge.md](tiled-map-bridge.md).

## Layout (the contract lives in `core/schemas/format.json`)

```
project/
  manifest.json          format, id, name, version, ruleset, identity (gh #23)
  data/
    species/<key>.json   one record per file  (id: "species:<key>")
    moves/<key>.json     one record per file  (id: "move:<key>")
    items/<key>.json     one record per file  (id: "item:<key>")
    trainers/<key>.json  one record per file  (id: "trainer:<key>")
    types.json           table — declares the "type:" ids + the sparse chart
    encounters.json      table — slots + per-map grass/water
    text.json            table — text id -> string
    marts.json           table — map ref -> item list
    hidden_items.json    table — map ref -> placements
    trades.json          table — the in-game trades
    events/<key>.json    one record per file  (id: "event:<key>") — an AUTHORED
                         event (ADR-019, gh #39/#40): a declarative trigger {kind:
                         interact|visible|enter|step|battle_end, map, object|front|
                         cells|region, facing, when, consume} + a nested-block
                         command list; `visible` triggers carry `visible_when` and
                         are load-time queries, never command runs; `step` dispatch
                         is (map, cell)-indexed at load. Conditions are FormulaExpr
                         over story flags/vars plus the engine-state identifiers
                         item_<id>/badge_<name>/badge_count/party_count/box_count/
                         money/coins/force_bike/surfing/in_safari/player_x/player_y/
                         dex_owned/battle_won/battle_doll_escape/player_starter_<id>/
                         rival_starter_<id>/defeated_<x>_<y>
                         (EventVM._ident_value is the authority).
                         Authored in-repo (game/events/), byte-copied in by the
                         extractor — events cannot be extracted from the asm. The
                         trigger-kind and command enums grow wave by wave with the
                         beats that demand them; the runtime VM refuses at boot any
                         record it cannot execute (see event.schema.json)
    ruleset.json         table — the ruleset config record (ADR-018 §4, gh #34):
                         {base, config} — base must match the manifest's ruleset;
                         config carries ONLY knobs that were already data (badge
                         stat boosts, field-move badge gates, the two stat-stage
                         tables, the high-crit move list); absent keys fall back
                         to the ruleset's built-in faithful defaults
    world.json           format 2+ — cardinal map connections keyed by stable map id
  maps/<Label>.json      format 1 only — interim extracted map JSON (bare `name`)
  maps/<Label>.tmx       format 2+ — native Tiled map (ADR-021)
  tilesets/<name>.tsx    format 2+ — external Tiled atlas metadata
  presentation/*.json    opaque interim blobs (audio, move anims, title beats…)
  assets/**              binary assets (PNG/…), content-unchecked
```

Rules (enforced by `ProjectValidator`, `game/core/ProjectValidator.gd`):

- **Every file must be claimed** by a layout entry — an unclaimed file is an error, so a
  typo'd path can't silently ship dead data.
- Layout entries can declare `since_format`/`until_format`; format 1 claims JSON maps,
  while format 2 claims TMX maps and their external TSX files.
- **Records self-identify**: the `id` field must equal `<prefix>:<basename>` (interim maps:
  the `name` field holds the bare label). A record's filename *is* its identity.
- **References are prefixed stable string IDs** (`"species:bulbasaur"`), declared in the
  schemas via `x-ref` (string fields) / `x-ref-keys` (object keys); every reference must
  resolve to a registered id — dangling references are named errors. This is what replaces
  v1's positional-order resolution (ADR-017 d4; the runtime keeps its internals until the
  Phase-2 seam — the gh #25 loader translates).
- **`format` is an integer** with linear migrations; a project *newer* than the build is
  refused naming both versions (the link-refusal pattern).
- **Every record reserves `custom: {}`** (ADR-017 d3): the creator-extension namespace,
  free-form under validation, so Phase-6 custom fields never break format 1 projects.
  Everything else is `additionalProperties: false`.

## The runtime loads the project (gh #25)

`game/core/ProjectData.gd` opens the project once at boot (`--project=<dir>` overrides the
default `res://project`): the manifest gate (refuse-newer naming both versions), then every
record collection reconstructs into the exact v1-shaped dictionaries the engine has always
consumed — prefixes stripped, `PSYCHIC_TYPE` restored, mono-types re-doubled, evolution
arrays back to their string-level form. `legacy(name)` answers by old asset filename and
returns a **deep copy** (v1 parsed fresh per call site; mutation semantics must not
change), and maps parse fresh per load for the same reason. Reconstruction is proven
field-for-field by **`--projparitytest`** (every table + all 223 maps vs the legacy files,
modulo the two documented emission filters), and proven *behaviorally* by the standing
gates — which is not redundant: the first flip passed parity and still moved the copycat
battledet md5, because **dictionary iteration order is behavior** (Metronome/Mimic pick
over the move table's order) while dictionary equality ignores it. That is why
move/item/trainer records carry **`num`** — the canonical Gen-1 table index — and the
reconstruction sorts by it. Binary assets (textures/audio synth inputs) still load through
Godot's import pipeline from `game/assets/` this phase; the project carries byte-identical
copies, and the raw-load switch belongs to the Studio phases.

Studio's Play-test action launches a separate Engine process with `--project=<dir>` and a
normalized-path-derived `--saveslot`. The child writes a tokened ready handshake only after
the project has loaded and reports the resolved save path; separate creator projects therefore
cannot share play-test progress (ADR-020 d5, gh #51).

Studio permits a build/import to replace the opened Project directory in place. `ProjectData`
therefore keys its open-project cache by both directory string and exact manifest bytes;
map selection performs this cheap check before consulting `format`. A changed manifest reloads
Core, so a live format migration cannot keep presenting native maps as legacy (gh #63).

For format 2, `ProjectData.map_json(label)` opens `MapDocument` and returns its normalized
runtime adapter: 16×16 tile/collision/semantic rows, typed object arrays, authored spawn,
project-local tileset metadata, and the selected map's `data/world.json` connections. Main
renders those cells directly while format-1 maps continue through the blockset adapter.
`map_legacy(label)` is the explicit migration-test view: it reconstructs the old semantic
dictionary without exposing native runtime fields. Both runtime shapes cross the same
placement/collision helpers; serialization details do not leak into gameplay call sites.

## Schemas + validator (gh #22)

- `game/core/schemas/*.schema.json` — standard JSON Schema documents (external tools can
  consume them). One per content type; `format.json` maps layout paths to schemas.
- `game/core/Schema.gd` (`CoreSchema`) — the subset validator (see its header for the
  keyword list). It **errors on unknown keywords** so a schema typo can't become phantom
  validation.
- `game/core/ProjectValidator.gd` — the project walk: manifest gate, claims, per-file
  schema validation, record-id registration, reference resolution. The seed of the
  Phase-5 lint engine and the same walk the gh #25 loader trusts.
- Verified by **`--schematest`** (fixtures under `game/core/fixtures/`: both valid format-1
  JSON and format-2 TMX projects register IDs; broken variants and malformed/native-newer
  maps refuse naming file + path) and usable on any directory via **`--validate=<dir>`**.

## Provenance

The Kanto project is **emitted by the extractor** (ADR-017 d6; gh #24): pokered clone in,
`game/project/` out — `build_project()` runs as the last extraction stage, consolidating
v1's parallel per-type dicts into records (species = base stats + learnsets + evolutions +
dex + cry + icon + sprites; items absorb prices and the TM→move mapping; trainers absorb
pics) and prefixing every cross-reference. Same bring-your-own-source, personal-use model
as v1 (`pokered/` and everything extracted stay git-ignored, never redistributed).
Format 2 emits Kanto as 223 TMX maps, 24 external TSX composite atlases, and
`data/world.json`; interim map JSON remains only under `game/assets/` as the parity oracle.
Emission is **deterministic**: two extractions produce byte-identical trees (the gh #24
gate), which is what makes the gh #23 identity hash meaningful. The project root carries
a `.gdignore` so Godot never imports the tree — the runtime reads it via raw
`FileAccess`/`Image.load_from_file` (gh #25).

Dead data pokered ships is filtered at emission, not schema'd around: the
`UnusedMart`/`UnusedBikeShop` stock (maps that don't exist) and the `UNUSED` padding in
Mew's TM table. The `missingno` cry (not a species record) lands in
`presentation/cries_extra.json`.
