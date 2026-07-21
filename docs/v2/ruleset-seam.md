# The ruleset seam (v2 Phase 2 — gh #16, ADR-018)

**Status:** in build-out. gh #31 (the skeleton + the Types tracer), gh #32 (the formula
kernels), gh #33 (the battle module: state + mechanics), and gh #34 (Catch + Progression +
the config record) landed; gh #35 (the expression evaluator, carrying the phase gate)
remains. Menu/item/party *flow* stays on the host — it drives mechanics through the same
delegator surface the tests use.

The engine core knows five **interfaces** (in `game/core/ruleset/`); the built-in, asm-faithful
**`gen1` ruleset** (`game/rulesets/gen1/`) implements them. A project's `manifest.json` names its
ruleset; `RulesetRegistry.resolve()` maps the name to an implementation at boot, refusing an
unknown name by naming both sides (the refuse-newer pattern applied to mechanics).

| Interface | Contract | gen1 status |
|---|---|---|
| `RulesetTypes` | `eff(move_type, def_types)` (composed, single-fire per table entry), `mult(atk, def)`, `row(move_type)` (table-ordered — Gen-1's damage loop applies each entry with its own floor, so iteration order is behavior; `row` is scaffolding that can retire once gh #32 pulls the damage loop inside) | **live** (`Gen1Types`, gh #31 — the tracer bullet) |
| `RulesetFormulas` | the pure arithmetic kernels: `stat_calc`, `exp_for_level`/`level_for_exp`, `crit_roll`, `damage_core` (GetDamageVars' byte-overflow scale + CalculateDamage), `randomize_damage`, `accuracy_roll`, `stage_apply`, `special_damage`, `catch_attempt`. Stat *selection* (which stat, unmodified-on-crit, screens, EXPLODE halving) is battle-module logic and stays with the battle state. RNG-drawing kernels take the battle's draw helpers as Callables so implementations own the math, never the draw order. | **live** (`Gen1Formulas`, gh #32 — moved verbatim from `Battle.gd`/`Main.gd`) |
| `RulesetBattle` | `battle state + chosen actions → the ordered event stream` (v1's ADR-009 queue is this contract); the Gen-1 trainer AI lives inside it (ADR-018 §2). `Gen1Battle` owns the battle STATE (mons, stages, volatiles, stored stats, safari/catch outcomes, the determinism RNG + stream, the lockstep link state) and the mechanics: turn resolution, move execution, status + residuals, the AI, action submission, EXP/level/learn. `Battle.gd` is the HOST — presentation, menus, the message pump — forwarding state via properties and delegating mechanics calls, bound once via `bind()` at setup. | **live** (`Gen1Battle`, gh #33 — moved verbatim in four gated waves) |
| `RulesetCatch` | `attempt(ball, status, rate, hp, maxhp, ri)` → {caught, shakes} (the ItemUseBall arithmetic stays the formula layer's kernel), plus the safari `bait_rate`/`rock_rate` transitions | **live** (`Gen1Catch`, gh #34) |
| `RulesetProgression` | `badge_for_stat(stat)` (BadgeStatBoosts' mapping) and `badge_for_field_move(move)` (the field-move badge gates) — both config-driven with faithful defaults | **live** (`Gen1Progression`, gh #34) |

**The migration protocol (ADR-018 §5):** strangler-fig — move one mechanic at a time into
`gen1`, leaving a delegating call at the old site, and run `--battledettest` after every move:
the per-scenario stream md5s **must not move by a byte** through the whole phase (plus the link
suites, since link battles run the seam on both peers). Method signatures are pinned on the
interfaces *as each mechanic lands*, never speculatively.

**Formulas stay native in gen1** (ADR-018 §3): expressions cannot cheaply reproduce Gen-1's
integer truncation/overflow quirks under the md5 gate. The expression evaluator (gh #35 —
live: `FormulaExpr` in Core, integer-exact, named variables + operators + min/max/floor/ceil/
sqrt/int/abs/if with comparisons and and/or) powers the *alternate* provider
`Gen1ExprFormulas`, whose expression-authored stat_calc / growth curves / damage_core are
proven equal to the native kernels by `--exprtest`'s ~1.3k-vector equivalence sweep — real
running code, never on gen1's hot path. Exotic math waits for the Phase-6 hatch.

**Config-first knobs** (ADR-018 §4, gh #34 — live): the schema'd `data/ruleset.json` singleton
(`{base, config}`, additive under `format: 1`; `base` must match the manifest's ruleset)
carries only what was already data — the badge stat-boost mapping, the field-move badge gates,
the two stat-stage multiplier tables, and the high-crit move list — emitted by the extractor
with the faithful gen1 values; absent keys fall back to built-in defaults. The type chart stays
its own content type (`data/types.json`). `--rulesettest` proves a knob actually turns (an
overridden stage table changes `stage_apply`'s answer).

**Verification:** `--rulesettest` (registry resolution, the unknown-name refusal, and the Types
tracer's full cross-product equivalence against the raw project chart) plus the standing phase
gates — see [plan.md](plan.md) §7 Phase 2 and the gh #16 checklist.
