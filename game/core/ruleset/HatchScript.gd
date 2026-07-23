extends RefCounted
class_name HatchScript
## The Phase-6 scripting hatch (gh #64, ADR-028): a purpose-built DSL for custom
## puzzles and exotic formulas. Statement-level extension of the FormulaExpr lineage —
## let/assignment, if/else, bounded while, return — tree-walked with a step budget.
##
## Sandboxed BY CONSTRUCTION: the grammar has no member access, no indexing, no imports,
## and its only external call surface is functions the host explicitly registers for the
## run. Pure FormulaExpr math intrinsics are part of the language. There is nothing to
## escape to. Deterministic: no time, no IO, no ambient randomness.
##
## Usage:
##   var s := HatchScript.parse("let n = 0\nwhile n < 4 { n = n + 1 }\nreturn n")
##   if s.error == "": var result = s.run({}, {"roll": func(a, b): return a + b})
## Parse errors land in `error` naming the position; runtime errors (unknown variable,
## unregistered function, budget trip) land there too and `run` yields null.

var error := ""      # "" = parsed/ran clean; else the error, naming the position or construct
var _program: Array = []
var _source := ""
var _parse_error := ""

const DEFAULT_BUDGET := 100000
const _INTRINSICS := {"min": 2, "max": 2, "floor": 1, "ceil": 1, "sqrt": 1, "int": 1,
	"abs": 1, "if": 3}
const _KEYWORDS := ["let", "if", "else", "while", "return", "true", "false"]


static func parse(src: String) -> HatchScript:
	var script := HatchScript.new()
	script._source = src
	var toks := script._tokenize(src)
	if script.error != "":
		script._parse_error = script.error
		return script
	var res: Array = script._parse_block_body(toks, 0, true)
	if script.error != "":
		script._parse_error = script.error
		return script
	if res[1] != toks.size():
		script.error = "unexpected '%s' at %s" % [
			str(toks[res[1]][1]), script._token_position(toks, res[1])]
		script._parse_error = script.error
		return script
	script._program = res[0]
	return script


## Execute with host-provided variables (copied in as script-wide locals) and
## host-registered functions (name -> Callable). Returns the script's `return` value.
func run(vars := {}, functions := {}, budget := DEFAULT_BUDGET):
	if _parse_error != "":
		error = _parse_error
		push_error("[hatchscript] run of unparsed script: " + _parse_error)
		return null
	error = ""
	var state := {"steps": 0, "budget": budget, "returned": false, "value": null}
	_exec_body(_program, vars.duplicate(), functions, state)
	return state["value"]


# ---- tokenizer ---------------------------------------------------------------

func _tokenize(src: String) -> Array:
	var toks: Array = []
	var i := 0
	while i < src.length():
		var c := src[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
			continue
		if c == "#":                               # line comment
			while i < src.length() and src[i] != "\n":
				i += 1
			continue
		if c == "\"":
			var out := ""
			var j := i + 1
			var closed := false
			while j < src.length():
				var ch := src[j]
				if ch == "\"":
					closed = true
					j += 1
					break
				if ch == "\\" and j + 1 < src.length():
					var esc := src[j + 1]
					match esc:
						"n": out += "\n"
						"t": out += "\t"
						"f": out += "\f"
						"\"": out += "\""
						"\\": out += "\\"
						_:
							error = "bad escape '\\%s' at %s" % [esc, _position(j)]
							return []
					j += 2
					continue
				out += ch
				j += 1
			if not closed:
				error = "unterminated string at %s" % _position(i)
				return []
			toks.append(["str", out, i])
			i = j
			continue
		if c.is_valid_int() or (c == "." and i + 1 < src.length() and src[i + 1].is_valid_int()):
			var j2 := i
			var isf := false
			while j2 < src.length() and (src[j2].is_valid_int() or src[j2] == "."):
				if src[j2] == ".":
					if isf:
						error = "multiple decimal points at %s" % _position(j2)
						return []
					isf = true
				j2 += 1
			var s := src.substr(i, j2 - i)
			toks.append(["num", float(s) if isf else int(s), i])
			i = j2
			continue
		if c.to_lower() != c.to_upper() or c == "_":
			var j3 := i
			while j3 < src.length() and (src[j3].to_lower() != src[j3].to_upper()
					or src[j3] == "_" or src[j3].is_valid_int()):
				j3 += 1
			var w := src.substr(i, j3 - i)
			if w == "and" or w == "or" or w == "not":
				toks.append(["op", w, i])
			elif w in _KEYWORDS:
				toks.append(["kw", w, i])
			else:
				toks.append(["ident", w, i])
			i = j3
			continue
		var two := src.substr(i, 2)
		if two in [">=", "<=", "==", "!="]:
			toks.append(["op", two, i])
			i += 2
			continue
		if c in "+-*/%(){}=<>,":
			toks.append(["op", c, i])
			i += 1
			continue
		error = "unexpected character '%s' at %s" % [c, _position(i)]
		return []
	return toks


# ---- parser ------------------------------------------------------------------
# statements: let / assign / if / while / return / expression
# expressions: or < and < comparison < add < mul < unary < primary (FormulaExpr's chain)

func _parse_block_body(t: Array, p: int, top_level := false) -> Array:
	# Statements up to EOF (top level) or the closing brace. Returns [stmts, pos].
	var stmts: Array = []
	var q := p
	while q < t.size():
		if t[q][0] == "op" and t[q][1] == "}":
			if top_level:
				error = "unexpected '}' at %s" % _token_position(t, q)
				return [[], q]
			return [stmts, q + 1]
		var r := _parse_stmt(t, q)
		if error != "":
			return r
		stmts.append(r[0])
		q = r[1]
	if not top_level:
		error = "missing '}' at %s" % _token_position(t, q)
		return [[], q]
	return [stmts, q]


func _parse_stmt(t: Array, p: int) -> Array:
	var tok: Array = t[p]
	if tok[0] == "kw":
		match tok[1]:
			"let":
				if p + 3 >= t.size() or t[p + 1][0] != "ident" \
						or t[p + 2][0] != "op" or t[p + 2][1] != "=":
					error = "expected 'let <name> = <expr>' at %s" % _token_position(t, p)
					return [[], p]
				var r := _parse_or(t, p + 3)
				if error != "":
					return r
				return [["let", t[p + 1][1], r[0], tok[2]], r[1]]
			"if":
				var cond := _parse_or(t, p + 1)
				if error != "":
					return cond
				var then_block := _parse_braced(t, cond[1])
				if error != "":
					return then_block
				var else_block: Array = []
				var q: int = then_block[1]
				if q < t.size() and t[q][0] == "kw" and t[q][1] == "else":
					var parsed_else := _parse_braced(t, q + 1)
					if error != "":
						return parsed_else
					else_block = parsed_else[0]
					q = parsed_else[1]
				return [["if", cond[0], then_block[0], else_block, tok[2]], q]
			"while":
				var cond := _parse_or(t, p + 1)
				if error != "":
					return cond
				var body := _parse_braced(t, cond[1])
				if error != "":
					return body
				return [["while", cond[0], body[0], tok[2]], body[1]]
			"return":
				if p + 1 >= t.size() or (t[p + 1][0] == "op" and t[p + 1][1] == "}"):
					return [["return", [], tok[2]], p + 1]
				var r := _parse_or(t, p + 1)
				if error != "":
					return r
				return [["return", r[0], tok[2]], r[1]]
			_:
				error = "unexpected '%s' at %s" % [tok[1], _token_position(t, p)]
				return [[], p]
	if tok[0] == "ident" and p + 1 < t.size() \
			and t[p + 1][0] == "op" and t[p + 1][1] == "=":
		var r := _parse_or(t, p + 2)
		if error != "":
			return r
		return [["assign", tok[1], r[0], tok[2]], r[1]]
	var r := _parse_or(t, p)
	if error != "":
		return r
	if r[0][0] != "call" or _INTRINSICS.has(r[0][1]):
		error = "only a host function call may be used as a standalone statement at %s" \
			% _position(tok[2])
		return [[], p]
	return [["exprstmt", r[0], tok[2]], r[1]]


func _parse_braced(t: Array, p: int) -> Array:
	if p >= t.size() or t[p][0] != "op" or t[p][1] != "{":
		error = "expected '{' at %s" % _token_position(t, p)
		return [[], p]
	return _parse_block_body(t, p + 1)


func _parse_or(t: Array, p: int) -> Array:
	var res := _parse_and(t, p)
	if error != "":
		return res
	while res[1] < t.size() and t[res[1]][0] == "op" and t[res[1]][1] == "or":
		var r := _parse_and(t, res[1] + 1)
		if error != "":
			return r
		res = [["bin", "or", res[0], r[0], t[res[1]][2]], r[1]]
	return res


func _parse_and(t: Array, p: int) -> Array:
	var res := _parse_cmp(t, p)
	if error != "":
		return res
	while res[1] < t.size() and t[res[1]][0] == "op" and t[res[1]][1] == "and":
		var r := _parse_cmp(t, res[1] + 1)
		if error != "":
			return r
		res = [["bin", "and", res[0], r[0], t[res[1]][2]], r[1]]
	return res


func _parse_cmp(t: Array, p: int) -> Array:
	var res := _parse_add(t, p)
	if error != "":
		return res
	while res[1] < t.size() and t[res[1]][0] == "op" \
			and t[res[1]][1] in [">", "<", ">=", "<=", "==", "!="]:
		var op: String = t[res[1]][1]
		var r := _parse_add(t, res[1] + 1)
		if error != "":
			return r
		res = [["bin", op, res[0], r[0], t[res[1]][2]], r[1]]
	return res


func _parse_add(t: Array, p: int) -> Array:
	var res := _parse_mul(t, p)
	if error != "":
		return res
	while res[1] < t.size() and t[res[1]][0] == "op" and t[res[1]][1] in ["+", "-"]:
		var op: String = t[res[1]][1]
		var r := _parse_mul(t, res[1] + 1)
		if error != "":
			return r
		res = [["bin", op, res[0], r[0], t[res[1]][2]], r[1]]
	return res


func _parse_mul(t: Array, p: int) -> Array:
	var res := _parse_unary(t, p)
	if error != "":
		return res
	while res[1] < t.size() and t[res[1]][0] == "op" and t[res[1]][1] in ["*", "/", "%"]:
		var op: String = t[res[1]][1]
		var r := _parse_unary(t, res[1] + 1)
		if error != "":
			return r
		res = [["bin", op, res[0], r[0], t[res[1]][2]], r[1]]
	return res


func _parse_unary(t: Array, p: int) -> Array:
	if p < t.size() and t[p][0] == "op" and t[p][1] == "-":
		var r := _parse_unary(t, p + 1)
		if error != "":
			return r
		return [["un", "-", r[0], t[p][2]], r[1]]
	if p < t.size() and t[p][0] == "op" and t[p][1] == "not":
		var r2 := _parse_unary(t, p + 1)
		if error != "":
			return r2
		return [["un", "not", r2[0], t[p][2]], r2[1]]
	return _parse_primary(t, p)


func _parse_primary(t: Array, p: int) -> Array:
	if p >= t.size():
		error = "unexpected end of expression at %s" % _token_position(t, p)
		return [[], p]
	var tok: Array = t[p]
	if tok[0] == "num":
		return [["num", tok[1], tok[2]], p + 1]
	if tok[0] == "str":
		return [["str", tok[1], tok[2]], p + 1]
	if tok[0] == "kw" and tok[1] in ["true", "false"]:
		return [["bool", tok[1] == "true", tok[2]], p + 1]
	if tok[0] == "ident" or (tok[0] == "kw" and tok[1] == "if"
			and p + 1 < t.size() and t[p + 1][0] == "op" and t[p + 1][1] == "("):
		var name: String = tok[1]
		if p + 1 < t.size() and t[p + 1][0] == "op" and t[p + 1][1] == "(":
			var args: Array = []
			var q := p + 2
			if q < t.size() and t[q][0] == "op" and t[q][1] == ")":
				q += 1
			else:
				while true:
					var r := _parse_or(t, q)
					if error != "":
						return r
					args.append(r[0])
					q = r[1]
					if q < t.size() and t[q][0] == "op" and t[q][1] == ",":
						q += 1
						continue
					if q < t.size() and t[q][0] == "op" and t[q][1] == ")":
						q += 1
						break
					error = "expected ',' or ')' at %s" % _token_position(t, q)
					return [[], q]
			if _INTRINSICS.has(name) and args.size() != _INTRINSICS[name]:
				error = "%s() takes %d argument(s), got %d at %s" % [name,
					_INTRINSICS[name], args.size(), _token_position(t, p)]
				return [[], q]
			return [["call", name, args, tok[2]], q]
		return [["var", name, tok[2]], p + 1]
	if tok[0] == "op" and tok[1] == "(":
		var r2 := _parse_or(t, p + 1)
		if error != "":
			return r2
		if r2[1] >= t.size() or t[r2[1]][0] != "op" or t[r2[1]][1] != ")":
			error = "expected ')' at %s" % _token_position(t, r2[1])
			return [[], r2[1]]
		return [r2[0], r2[1] + 1]
	error = "unexpected '%s' at %s" % [str(tok[1]), _token_position(t, p)]
	return [[], p]


# ---- evaluator ---------------------------------------------------------------

func _exec_body(stmts: Array, env: Dictionary, funcs: Dictionary, state: Dictionary) -> void:
	for stmt in stmts:
		if state["returned"] or error != "":
			return
		state["steps"] += 1
		if state["steps"] > state["budget"]:
			_runtime_error("step budget exceeded (%d) — a loop ran away" % int(state["budget"]),
				int(stmt[-1]))
			return
		_exec_stmt(stmt, env, funcs, state)


func _exec_stmt(stmt: Array, env: Dictionary, funcs: Dictionary, state: Dictionary) -> void:
	match stmt[0]:
		"let", "assign":
			var name: String = stmt[1]
			if stmt[0] == "assign" and not env.has(name):
				_runtime_error("assignment to undeclared variable '%s' (declare it with let)" % name,
					stmt[3])
				return
			var value = _ev(stmt[2], env, funcs, state)
			if error == "":
				env[name] = value
		"exprstmt":
			_ev(stmt[1], env, funcs, state, stmt[1][0] == "call")
		"if":
			if _truthy(_ev(stmt[1], env, funcs, state)):
				_exec_body(stmt[2], env, funcs, state)
			else:
				_exec_body(stmt[3], env, funcs, state)
		"while":
			while error == "" and not state["returned"] \
					and _truthy(_ev(stmt[1], env, funcs, state)):
				# The condition and the iteration both cost a step: an empty body
				# (while 1 {}) must still trip the budget.
				state["steps"] += 1
				if state["steps"] > state["budget"]:
					_runtime_error("step budget exceeded (%d) — a loop ran away" \
						% int(state["budget"]), stmt[3])
					return
				_exec_body(stmt[2], env, funcs, state)
		"return":
			state["returned"] = true
			state["value"] = _ev(stmt[1], env, funcs, state) if not stmt[1].is_empty() else null


func _ev(n: Array, env: Dictionary, funcs: Dictionary, state: Dictionary,
		allow_null_result := false):
	if error != "":
		return null
	match n[0]:
		"num", "str", "bool":
			return n[1]
		"var":
			if not env.has(n[1]):
				_runtime_error("unknown variable '%s'" % n[1], n[2])
				return null
			var value = env[n[1]]
			if not _is_script_value(value):
				_runtime_error("variable '%s' has unsupported %s value" % [
					n[1], type_string(typeof(value))], n[2])
				return null
			return value
		"un":
			var v = _ev(n[2], env, funcs, state)
			if error != "":
				return null
			if n[1] == "not":
				return not _truthy(v)
			if not _is_numeric(v):
				_runtime_error("unary '-' requires a numeric operand", n[3])
				return null
			return -v
		"bin":
			return _ev_bin(n, env, funcs, state)
		"call":
			return _ev_call(n, env, funcs, state, allow_null_result)
	error = "bad expression node"
	return null


func _ev_bin(n: Array, env: Dictionary, funcs: Dictionary, state: Dictionary):
	var a = _ev(n[2], env, funcs, state)
	if error != "":
		return null
	if n[1] == "and":
		return _truthy(a) and _truthy(_ev(n[3], env, funcs, state))
	if n[1] == "or":
		return _truthy(a) or _truthy(_ev(n[3], env, funcs, state))
	var b = _ev(n[3], env, funcs, state)
	if error != "":
		return null
	match n[1]:
		"+":
			if a is String or b is String:
				return str(a) + str(b)
			if not _require_numeric_operands(a, b, n[1], n[4]):
				return null
			return a + b
		"-":
			if not _require_numeric_operands(a, b, n[1], n[4]):
				return null
			return a - b
		"*":
			if not _require_numeric_operands(a, b, n[1], n[4]):
				return null
			return a * b
		"/":
			if not _require_numeric_operands(a, b, n[1], n[4]):
				return null
			if b == 0 or b == 0.0:
				_runtime_error("division by zero", n[4])
				return null
			if a is int and b is int:
				@warning_ignore("integer_division")
				var q: int = a / b               # native truncating int division
				return q
			return a / b
		"%":
			if not _require_numeric_operands(a, b, n[1], n[4]):
				return null
			if b == 0 or b == 0.0:
				_runtime_error("modulo by zero", n[4])
				return null
			return a % b if (a is int and b is int) else fmod(a, b)
		">", "<", ">=", "<=":
			if not ((_is_numeric(a) and _is_numeric(b)) or (a is String and b is String)):
				_runtime_error("operator '%s' requires two numbers or two strings" % n[1], n[4])
				return null
			match n[1]:
				">": return a > b
				"<": return a < b
				">=": return a >= b
				"<=": return a <= b
		"==": return a == b
		"!=": return a != b
	error = "bad operator '%s'" % n[1]
	return null


func _ev_call(n: Array, env: Dictionary, funcs: Dictionary, state: Dictionary,
		allow_null_result: bool):
	var args: Array = []
	for x in n[2]:
		var v = _ev(x, env, funcs, state)
		if error != "":
			return null
		args.append(v)
	var name: String = n[1]
	if _INTRINSICS.has(name):
		if name != "if":
			for arg in args:
				if not _is_numeric(arg):
					_runtime_error("intrinsic '%s' requires numeric arguments" % name, n[3])
					return null
		match name:
			"min": return min(args[0], args[1])
			"max": return max(args[0], args[1])
			"floor": return int(floor(float(args[0])))
			"ceil": return int(ceil(float(args[0])))
			"sqrt": return sqrt(float(args[0]))
			"int": return int(args[0])
			"abs": return abs(args[0])
			"if": return args[1] if _truthy(args[0]) else args[2]
	if not funcs.has(name) or not (funcs[name] is Callable):
		_runtime_error("unknown function '%s' — the host registers no such name" % name, n[3])
		return null
	var callable := funcs[name] as Callable
	if not callable.is_valid():
		_runtime_error("host function '%s' is not callable" % name, n[3])
		return null
	var expected_args := callable.get_argument_count()
	if expected_args >= 0 and args.size() != expected_args:
		_runtime_error("function '%s' takes %d argument(s), got %d" % [
			name, expected_args, args.size()], n[3])
		return null
	var result = callable.callv(args)
	if result == null:
		if allow_null_result:
			return null
		_runtime_error("function '%s' returned no value" % name, n[3])
		return null
	if not _is_script_value(result):
		_runtime_error("function '%s' returned unsupported %s value" % [
			name, type_string(typeof(result))], n[3])
		return null
	return result


static func _truthy(v) -> bool:
	if v is bool:
		return v
	if v is int:
		return v != 0
	if v is float:
		return v != 0.0
	if v is String:
		return v != ""
	return false


func _require_numeric_operands(a, b, op: String, offset: int) -> bool:
	if _is_numeric(a) and _is_numeric(b):
		return true
	_runtime_error("operator '%s' requires numeric operands" % op, offset)
	return false


static func _is_numeric(value) -> bool:
	return value is int or value is float


static func _is_script_value(value) -> bool:
	return value is bool or _is_numeric(value) or value is String


func _runtime_error(message: String, offset: int) -> void:
	error = "%s at %s" % [message, _position(offset)]


func _token_position(tokens: Array, index: int) -> String:
	if index >= 0 and index < tokens.size():
		return _position(int(tokens[index][2]))
	return _position(_source.length())


func _position(offset: int) -> String:
	var prefix := _source.substr(0, clampi(offset, 0, _source.length()))
	var line := prefix.count("\n") + 1
	var last_newline := prefix.rfind("\n")
	var column := offset + 1 if last_newline < 0 else offset - last_newline
	return "line %d, column %d" % [line, column]
