# HatchScript (v2 Phase 6 - gh #64, ADR-028)

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

## Host boundary

Host functions are a dictionary of name to `Callable`. An unregistered call is refused
by name; fixed-arity callables are checked before invocation, and non-scalar results are
refused. A `null` result is allowed for command-style calls whose value is ignored.
Register only curated, deterministic operations for the context. Event and formula
integrations own their separate APIs in gh #65 and gh #66; script project storage and
Studio editing land in those integration issues, not in the Core language.

All parser and interpreter-owned failures set `script.error` with a one-based line and
column. This includes malformed syntax/numbers, unknown variables/functions, undeclared
assignment, invalid operands or host values, division or modulo by zero, host arity
errors, and step-budget exhaustion.

Run `pwsh tools/run.ps1 --exprtest` for the Core smoke: statement and arithmetic
semantics, positioned failures, sandbox refusal probes, budget termination,
FormulaExpr builtin compatibility, and repeated-run determinism.
