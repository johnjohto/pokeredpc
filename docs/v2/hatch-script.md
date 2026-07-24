# HatchScript (v2 Phase 6 - gh #64/#65/#66, ADR-028/ADR-030)

HatchScript is the sandboxed scripting language for creator-authored event logic and
formula kernels. It is a statement-level extension of `FormulaExpr`, implemented as a
tokenizer, parser, and tree-walked evaluator in Core.

The sandbox is structural. HatchScript has no imports, member access, indexing,
filesystem, network, time, engine-object access, or ambient randomness. Its only
external call surface is the named `Callable`s its host explicitly registers for that
run; the pure FormulaExpr math intrinsics are part of the language itself. This keeps
the language available on every Godot export target without executing project source
as GDScript.

## Core API

```gdscript
var script := HatchScript.parse(source)
if script.error != "":
    # Parse errors include a one-based line and column.
    return

var result = script.run(
    {"limit": 10},
    {"mark": func(value): return value + 1},
    100_000
)
if script.error != "":
    # Runtime errors use the same line/column form.
    return
```

`parse(source)` compiles once. A successfully parsed object may be run repeatedly with
different inputs; runtime errors are cleared at the start of the next run. Input
variables are copied into script-wide locals, so assignment does not mutate the host
dictionary. Host variables and return values are limited to scalar script values;
arrays, dictionaries, and objects are refused at their source position. `run` returns
the script's return value, or `null` when no value is returned or execution fails.

The third argument is the step budget. It defaults to `100000`. Statements and loop
iterations consume steps, including an empty `while` body, so a runaway loop terminates
with a positioned runtime error.

## Language

Statements:

```text
let name = expression
name = expression
if expression { statements } else { statements }
while expression { statements }
return [expression]
host_function(arguments)
```

`let` declares a local. Assignment to an undeclared name is a runtime error. A registered
host function may be called as a statement when its return value is intentionally
ignored. Blocks use braces. `#` starts a line comment.

Values are integers, floats, strings, and booleans (`true` / `false`). `null` exists only
as the no-value result of bare `return` or a command-style host call; there is no `null`
literal. Integer arithmetic stays integer-exact; integer division truncates toward zero.
Mixing an integer and float promotes through Godot's numeric rules. Strings support
escapes for newline, tab, form feed, quote, and backslash. `+` concatenates when either
operand is a string.

Expression precedence, from lowest to highest:

```text
or
and
> < >= <= == !=
+ -
* / %
unary - and not
primary values, names, calls, and parenthesized expressions
```

Pure intrinsics match `FormulaExpr`: `min(a, b)`, `max(a, b)`, `floor(x)`, `ceil(x)`,
`sqrt(x)`, `int(x)`, `abs(x)`, and `if(condition, yes, no)`. The math intrinsics require
numeric arguments. They do not expose host or engine capabilities.

## Event integration

Event scripts are Project records under `data/scripts/<key>.json`:

```json
{
 "id": "script:combination_lock",
 "source": "let code = 2 * 100 + 4 * 10 + 1\nset_var(\"dial\", code)\nreturn get_var(\"dial\") == 241"
}
```

Every script is schema-validated and parsed when the Project loads. A malformed script
refuses the Project before any event can fire, with the source line and column. Event
records invoke a script with `run_script`:

```json
{
 "cmd": "run_script",
 "script": "script:combination_lock",
 "result": "lock_open"
}
```

`result` is optional. When present, the script must return a value; EventVM writes that
scalar to the saved event-variable store, where the next ordinary `if` condition can read
it. A runtime failure, or a missing requested return value, aborts the event and rolls back
the script's flag and variable writes.

Event scripts receive only this curated API:

| Function | Result / effect |
|---|---|
| `has_flag(name)` | Whether a durable story flag is set. |
| `set_flag(name)` / `clear_flag(name)` | Set or clear a durable story flag. |
| `get_var(name)` | Read a durable event variable; missing names return `0`. |
| `set_var(name, value)` / `clear_var(name)` | Set or clear a durable scalar event variable. |
| `item_count(item_id)` | Read the player's bag count for an `item:` id. |
| `party_count()` / `box_count()` | Read the current party or PC-box size. |
| `party_has(species_id)` | Whether the party contains a `species:` id. |
| `map_id()` | Read the current bare map label. |
| `player_x()` / `player_y()` / `facing()` | Read the player's map cell and facing index. |
| `money()` / `coins()` | Read the current money or Game Corner coin count. |
| `badge_count()` / `has_badge(name)` | Read badge progress. |

The following command-library equivalents enqueue ordinary EventVM commands in script
branch/loop order. EventVM executes the queue after the script returns successfully and
before it stores `result`, preserving the commands' established await and abort behavior:

```text
say(text)                    notice(text)
show_text(text)              close_text()
sfx(key)                     play_song(key)
play_map_music()             wait_frames(frames)
give_item(item_id, count)    take_item(item_id)
give_coins(count)            take_money(amount)
give_badge(name)             heal_party()
set_last_map(map_id)         set_force_bike(value)
mount_bike()
block_cell(x, y)             unblock_cell(x, y)
walk_player(dir, count)      walk_forward(dir, count)
walk_object(id, dir, count)  walk_player_to(x, y)
place_object(id, x, y)       face_object(id, dir)
face_player(dir)             hide_object(id)
show_object(id)              refresh_objects()
warp_to(map_id, warp)
```

This is the stable, generic subset of the event command library. Native Cutscene beats,
trainer/battle launchers, Kanto-specific mechanisms, recursive `run_script`, and GUI
branches are intentionally absent: HatchScript supplies its own branches/loops, while
game-specific native calls would expose internals rather than a portable creator API.
These functions expose scalar arguments and stable IDs, never engine objects.

Event variables preserve their scalar types across save/reload. Saves carry additive
type tags beside the existing `event_vars` values so HatchScript integer division cannot
silently become floating-point division after JSON parsing.

## Formula integration

Script-backed formula kernels (gh #66, ADR-030) replace a ruleset's arithmetic behind
the same `RulesetFormulas` interface the engine always calls. `data/ruleset.json` binds
kernel names to script records:

```json
{
 "base": "gen1",
 "formula_scripts": {
  "catch_attempt": "script:double_catch",
  "exp_for_level": "script:half_cube"
 }
}
```

A bound kernel runs its script; every unbound kernel keeps the base ruleset's native
implementation. An unknown kernel name, a dangling script reference, or an unparseable
source refuses the Project at validation and at Engine boot, naming the kernel and
script. `HatchFormulas` (Core) is the wrapper; any ruleset gains the hatch through the
same `Ruleset.attach_formula_scripts()` boot step.

Each kernel receives fixed input variables and, where the native kernel draws
randomness, the battle's own draw Callables as host functions — so scripts control
formula math, never draw order or the battle's RNG stream identity:

| Kernel | Inputs | Hosts | Result |
|---|---|---|---|
| `stat_calc` | `base, level, dv, is_hp, sexp` | — | integer stat |
| `exp_for_level` | `n, growth` | — | total EXP for level n |
| `level_for_exp` | `xp, growth` | — | level reached at xp |
| `crit_roll` | `base_spd, focus, move_name` | `rand_float()` | truthy = critical |
| `damage_core` | `level, crit, power, a_stat, d_stat` | — | damage before randomization |
| `randomize_damage` | `dmg` | `rand_range(lo, hi)` | final damage |
| `accuracy_roll` | `accuracy, acc_stage, eva_stage` | `rand_int(n)` | truthy = the move hits |
| `stage_apply` | `base, stage` | — | the stat under a stage |
| `special_damage` | `move, level` | `rand_range(lo, hi)` | fixed-damage amount |
| `catch_attempt` | `ball, status, rate, hp, maxhp` | `rand_int(n)`, `out(name, value)` | via `out` |

`rand_float()` yields a float in [0, 1); `rand_range(lo, hi)` an integer in [lo, hi];
`rand_int(n)` an integer in [0, n). `catch_attempt` is the one dictionary-shaped
kernel: its script must call `out("caught", <bool>)` and `out("shakes", <int>)`; the
return value is ignored.

Two rules keep bound kernels honest:

- **Inverse consistency:** binding `exp_for_level` alone makes the engine derive
  `level_for_exp` by walking the scripted curve (levels 1–100), so a custom curve and
  its level-up threshold can never disagree. Bind `level_for_exp` explicitly to take
  that over too.
- **Loud fallback:** a runtime failure (unknown variable, bad operand, missing `out`
  values, a non-numeric result) pushes an error naming the script, kernel, and source
  position, then answers with the base kernel — deterministic for identical inputs and
  draws, and battle math never crashes mid-run. Fix the script; the log will not be
  quiet about it.

Determinism holds by construction and is gated by `pwsh tools/hatchdet.ps1`: it runs
the `--exprtest` sweep (every scripted kernel held to the native outputs, value for
value and draw for draw), then replays `--battledettest` against the vanilla project
and against the fully gen1-scripted scratch exprtest builds, and diffs the four stream
md5s itself — byte-identical or the gate is red.

## Host boundary

Host functions are a dictionary of name to `Callable`. An unregistered call is refused
by name; fixed-arity callables are checked before invocation, and non-scalar results are
refused. A `null` result is allowed for command-style calls whose value is ignored.
Register only curated, deterministic operations for the context. Event and formula
integrations own separate APIs (gh #65 and gh #66 above); Studio's dedicated source
editor lands in gh #67.

All parser and interpreter-owned failures set `script.error` with a one-based line and
column. This includes malformed syntax/numbers, unknown variables/functions, undeclared
assignment, invalid operands or host values, division or modulo by zero, host arity
errors, and step-budget exhaustion.

Run `pwsh tools/run.ps1 --exprtest` for the Core smoke: statement and arithmetic
semantics, positioned failures, sandbox refusal probes, budget termination,
FormulaExpr builtin compatibility, and repeated-run determinism.
