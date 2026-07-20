# The v2 project format (format 1)

The **Project** is v2's shareable artifact (ADR-013, ADR-017): a portable directory of
data + maps + assets + a ruleset selection that `Engine(Project) → playable game` and
`Studio(Project) → edits the same Project`. This doc describes **format 1** as pinned by
**ADR-017** and implemented from gh #22 on. While the only consumer is this repo, the
format may still evolve in place; the moment projects are shared (Studio-era), every
change becomes a format bump + migration.

## Serialization

**JSON, validated by JSON Schema** (draft 2020-12), in **canonical form**: pretty-printed
(indent 1), sorted-key-stable where machine-emitted, UTF-8, LF, trailing newline. The
canonical bytes double as the identity-hash input (gh #23). No comments — schemas carry
`description`/`$comment`, and the editor is the primary authoring surface.

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
  maps/<Label>.json      one record per file — INTERIM: v1's extracted map JSON
                         carried as-is (name field = bare label); replaced by the
                         Tiled TMX bridge in Phase 5 (a format bump, gh #19)
  presentation/*.json    opaque interim blobs (audio, move anims, title beats…)
  assets/**              binary assets (PNG/…), content-unchecked
```

Rules (enforced by `ProjectValidator`, `game/core/ProjectValidator.gd`):

- **Every file must be claimed** by a layout entry — an unclaimed file is an error, so a
  typo'd path can't silently ship dead data.
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

## Schemas + validator (gh #22)

- `game/core/schemas/*.schema.json` — standard JSON Schema documents (external tools can
  consume them). One per content type; `format.json` maps layout paths to schemas.
- `game/core/Schema.gd` (`CoreSchema`) — the subset validator (see its header for the
  keyword list). It **errors on unknown keywords** so a schema typo can't become phantom
  validation.
- `game/core/ProjectValidator.gd` — the project walk: manifest gate, claims, per-file
  schema validation, record-id registration, reference resolution. The seed of the
  Phase-5 lint engine and the same walk the gh #25 loader trusts.
- Verified by **`--schematest`** (fixtures under `game/core/fixtures/`: the valid mini
  project passes and registers ids; seven broken variants each produce exactly one error
  naming file + path) and usable on any directory via **`--validate=<dir>`**.

## Provenance

The Kanto project is **emitted by the extractor** (ADR-017 d6; gh #24): pokered clone in,
project folder out — the same bring-your-own-source, personal-use model as v1
(`pokered/` and everything extracted stay git-ignored, never redistributed).
