# Mon record (`mon/1`) — the link wire schema

The versioned wire form of **one exchanged Pokémon** (gh #4, ADR-014): what a trade sends,
what a link battle's party preview reads, and the serialized state model v2's Core inherits
(ADR-013 — formalized once, here). `MonRecord.gd` is the codec; translation to/from the
engine's internal index-based mon dict happens **only at the link boundary** — engine
internals are untouched.

Design rules:

- **Stable string IDs** — `species:<slug>` / `move:<CONST>` — never internal indices.
- **Explicit fields, versioned schema** — a fixture dict *is* a valid peer message, so the
  codec is fully testable single-process (`--monrecordtest`).
- **Stats are never trusted off the wire**: decode rebuilds them from base stats + level +
  DVs + stat exp (`make_mon` + `recompute_stats`), then clamps `hp` to the rebuilt max —
  a tampered record cannot carry impossible stats.
- **Every refusal is clean and names the field**; a malformed peer message never crashes
  the receiving game. An unknown `schema` is refused up front.

## Fields

```json
{
  "schema": "mon/1",
  "species": "species:kadabra",
  "nickname": "ABRA-CADAB",
  "level": 40,
  "exp": 64000,
  "hp": 93,
  "status": "slp",
  "sleep": 3,
  "dvs": {"atk": 8, "def": 9, "spd": 10, "spc": 11},
  "stat_exp": {"hp": 1200, "atk": 65535, "def": 40, "spd": 0, "spc": 7},
  "moves": [{"id": "move:PSYCHIC_M", "pp": 10}],
  "ot": "RED",
  "trainer_id": 31337
}
```

| Field | Type / range | Notes |
|---|---|---|
| `schema` | `"mon/1"` | Format version; anything else refuses with a message naming it. |
| `species` | `species:<slug>` | Must exist in `base_stats.json` (the link identity already guarantees both peers share it). |
| `nickname` | string, 1–10 chars | The display name — the species name if never nicknamed. Maps to internal `name`. |
| `level` | int 1–100 | |
| `exp` | int ≥ 0 | Raw experience points. |
| `hp` | int 0–999 | Current HP; clamped to the rebuilt `maxhp` on decode. |
| `status` | `"" \| psn \| par \| slp \| brn \| frz` | Party-level major status. |
| `sleep` | int 0–7 | Sleep counter; zeroed on decode unless `status == "slp"`. |
| `dvs` | 4 × int 0–15 | `atk/def/spd/spc`. The **hp DV is not sent** — Gen 1 derives it from the low bit of each of the other four, and decode re-derives it, so an illegal combination can't travel. |
| `stat_exp` | 5 × int 0–65535 | `hp/atk/def/spd/spc` (Gen-1 EVs); folded into stats by the decode-side recompute (`CalcStat`'s sqrt term). |
| `moves` | array of 1–4 | Each `{"id": "move:<CONST>", "pp": int, "maxpp": int}`. Move must exist, no duplicates, `maxpp` in `1..64` (Gen 1's absolute ceiling: 40 base + 3 PP Ups), `pp` in `0..maxpp`. `maxpp` travels **explicitly**: a real save's max PP can legitimately differ from the current move table (a move taught under an older extraction; PP Ups if ever modelled) — deriving it refused real parties. |
| `ot` | string, 1–10 chars | Original trainer name. Drives the outsider-mon checks (boosted EXP, the Name Rater's refusal). |
| `trainer_id` | int 0–65535 | The OT's ID number (`player_id` internally, `otid` on the mon). |

## Codec interface (`MonRecord.gd`)

- `encode(mon: Dictionary) -> Dictionary` — internal mon → wire record.
- `decode(rec) -> {"ok": true, "mon": …} | {"ok": false, "error": …}` — validate + rebuild.
- `decode_json(text) -> …` — the fixture-message form (JSON parse + decode).

Verified by `--monrecordtest` (selftest-flag pattern, single process): four round-trip
shapes (plain own-OT, nicknamed + statused + outsider OT + spent PP + partial HP, one move
slot, four move slots at L99) with per-field comparison **and** canonical re-encode
equality, an unknown-version refusal, and ~24 malformed/field-invalid fixtures each
rejected with a named reason and no crash.

## Versioning

The schema version bumps (`mon/2`, …) only with the format itself. v1.1 refuses any version
other than its own — cross-version link compatibility is out of scope by spec (gh #1), and
the link identity handshake (exact game version, [engine/link.md](../engine/link.md)) makes
a version mismatch unreachable in practice; the schema check is the belt to that suspender.
