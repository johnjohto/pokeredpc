# The ruleset seam (v2 Phase 2 — gh #16, ADR-018)

**Status:** in build-out. gh #31 (the skeleton + the Types tracer) landed; gh #32–#35 migrate
the remaining mechanics behind the seam module by module.

The engine core knows five **interfaces** (in `game/core/ruleset/`); the built-in, asm-faithful
**`gen1` ruleset** (`game/rulesets/gen1/`) implements them. A project's `manifest.json` names its
ruleset; `RulesetRegistry.resolve()` maps the name to an implementation at boot, refusing an
unknown name by naming both sides (the refuse-newer pattern applied to mechanics).

| Interface | Contract | gen1 status |
|---|---|---|
| `RulesetTypes` | `eff(move_type, def_types)` (composed, single-fire per table entry), `mult(atk, def)`, `row(move_type)` (table-ordered — Gen-1's damage loop applies each entry with its own floor, so iteration order is behavior; `row` is scaffolding that can retire once gh #32 pulls the damage loop inside) | **live** (`Gen1Types`, gh #31 — the tracer bullet) |
| `RulesetFormulas` | damage / accuracy / crit / catch-rate / stat-calc / exp-curve provider | fused; migrates in gh #32 |
| `RulesetBattle` | `battle state + chosen actions → the ordered event stream` (v1's ADR-009 queue is this contract); the Gen-1 trainer AI lives inside it (ADR-018 §2) | fused; migrates in gh #33 |
| `RulesetCatch` | ball + target state → caught / shake count | fused; migrates in gh #34 |
| `RulesetProgression` | progression flags + gate conditions (badges, HM gates generalized) | fused; migrates in gh #34 |

**The migration protocol (ADR-018 §5):** strangler-fig — move one mechanic at a time into
`gen1`, leaving a delegating call at the old site, and run `--battledettest` after every move:
the per-scenario stream md5s **must not move by a byte** through the whole phase (plus the link
suites, since link battles run the seam on both peers). Method signatures are pinned on the
interfaces *as each mechanic lands*, never speculatively.

**Formulas stay native in gen1** (ADR-018 §3): expressions cannot cheaply reproduce Gen-1's
integer truncation/overflow quirks under the md5 gate. The expression evaluator (gh #35) is an
*alternate* provider proven by an equivalence sweep against gen1's native outputs.

**Config-first knobs** (ADR-018 §4): only what is already data — the type chart, badge-boost
mapping, exp growth curves, stat-stage multipliers, crit parameters — formalized as a schema'd
`data/ruleset.json` singleton in gh #34, additive under `format: 1`.

**Verification:** `--rulesettest` (registry resolution, the unknown-name refusal, and the Types
tracer's full cross-product equivalence against the raw project chart) plus the standing phase
gates — see [plan.md](plan.md) §7 Phase 2 and the gh #16 checklist.
