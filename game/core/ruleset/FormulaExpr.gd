extends RefCounted
class_name FormulaExpr
## The formula-expression evaluator (gh #35, ADR-018 §3): named variables + operators,
## INTEGER-EXACT — int op int stays int, and `/` on two ints truncates toward zero like
## GDScript (and, for the non-negative values Gen-1 formulas use, like the GB's divides).
## Mixing int and float promotes to float; `int(x)` truncates back (GDScript int()).
## Functions: min max floor ceil sqrt int abs if(cond, a, b). Comparisons and and/or/not
## are supported so a formula can express branchy arithmetic (the damage core's /4
## byte-overflow scale). Exotic math waits for the Phase-6 scripting hatch.
##
## Usage: var e := FormulaExpr.parse("min(a / 4, 997) + 2"); e.eval({"a": 200})
## Parse errors land in `error` (naming the position); eval of an unknown variable
## pushes an error and yields 0.

var error := ""      # "" = parsed clean; else the parse error, naming the position
var _ast: Array = []

const _FUNCS := {"min": 2, "max": 2, "floor": 1, "ceil": 1, "sqrt": 1, "int": 1,
	"abs": 1, "if": 3}


static func parse(src: String) -> FormulaExpr:
	var e := FormulaExpr.new()
	var toks := e._tokenize(src)
	if e.error != "":
		return e
	var res: Array = e._parse_or(toks, 0)
	if e.error != "":
		return e
	if res[1] != toks.size():
		e.error = "unexpected '%s' at token %d" % [str(toks[res[1]][1]), res[1]]
		return e
	e._ast = res[0]
	return e


func eval(vars: Dictionary):
	if error != "":
		push_error("[expr] eval of unparsed expression: " + error)
		return 0
	return _ev(_ast, vars)


# ---- tokenizer -------------------------------------------------------------

func _tokenize(src: String) -> Array:
	var toks: Array = []
	var i := 0
	while i < src.length():
		var c := src[i]
		if c == " " or c == "\t" or c == "\n":
			i += 1
			continue
		if c.is_valid_int() or (c == "." and i + 1 < src.length() and src[i + 1].is_valid_int()):
			var j := i
			var isf := false
			while j < src.length() and (src[j].is_valid_int() or src[j] == "."):
				if src[j] == ".":
					isf = true
				j += 1
			var s := src.substr(i, j - i)
			toks.append(["num", float(s) if isf else int(s)])
			i = j
			continue
		if c.to_lower() != c.to_upper() or c == "_":     # a letter
			var j2 := i
			while j2 < src.length() and (src[j2].to_lower() != src[j2].to_upper()
					or src[j2] == "_" or src[j2].is_valid_int()):
				j2 += 1
			var w := src.substr(i, j2 - i)
			if w == "and" or w == "or" or w == "not":
				toks.append(["op", w])
			else:
				toks.append(["ident", w])
			i = j2
			continue
		var two := src.substr(i, 2)
		if two in [">=", "<=", "==", "!="]:
			toks.append(["op", two])
			i += 2
			continue
		if c in "+-*/%()<>,":
			toks.append(["op", c])
			i += 1
			continue
		error = "unexpected character '%s' at %d" % [c, i]
		return []
	return toks


# ---- parser (precedence climbing) ------------------------------------------
# or < and < comparison < add < mul < unary < primary

func _parse_or(t: Array, p: int) -> Array:
	var res := _parse_and(t, p)
	if error != "":
		return res
	while res[1] < t.size() and t[res[1]][0] == "op" and t[res[1]][1] == "or":
		var r := _parse_and(t, res[1] + 1)
		if error != "":
			return r
		res = [["bin", "or", res[0], r[0]], r[1]]
	return res


func _parse_and(t: Array, p: int) -> Array:
	var res := _parse_cmp(t, p)
	if error != "":
		return res
	while res[1] < t.size() and t[res[1]][0] == "op" and t[res[1]][1] == "and":
		var r := _parse_cmp(t, res[1] + 1)
		if error != "":
			return r
		res = [["bin", "and", res[0], r[0]], r[1]]
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
		res = [["bin", op, res[0], r[0]], r[1]]
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
		res = [["bin", op, res[0], r[0]], r[1]]
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
		res = [["bin", op, res[0], r[0]], r[1]]
	return res


func _parse_unary(t: Array, p: int) -> Array:
	if p < t.size() and t[p][0] == "op" and t[p][1] == "-":
		var r := _parse_unary(t, p + 1)
		if error != "":
			return r
		return [["un", "-", r[0]], r[1]]
	if p < t.size() and t[p][0] == "op" and t[p][1] == "not":
		var r2 := _parse_unary(t, p + 1)
		if error != "":
			return r2
		return [["un", "not", r2[0]], r2[1]]
	return _parse_primary(t, p)


func _parse_primary(t: Array, p: int) -> Array:
	if p >= t.size():
		error = "unexpected end of expression"
		return [[], p]
	var tok: Array = t[p]
	if tok[0] == "num":
		return [["num", tok[1]], p + 1]
	if tok[0] == "ident":
		var name: String = tok[1]
		if p + 1 < t.size() and t[p + 1][0] == "op" and t[p + 1][1] == "(":
			if not _FUNCS.has(name):
				error = "unknown function '%s'" % name
				return [[], p]
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
					error = "expected ',' or ')' at token %d" % q
					return [[], q]
			if args.size() != _FUNCS[name]:
				error = "%s() takes %d argument(s), got %d" % [name, _FUNCS[name], args.size()]
				return [[], q]
			return [["call", name, args], q]
		return [["var", name], p + 1]
	if tok[0] == "op" and tok[1] == "(":
		var r2 := _parse_or(t, p + 1)
		if error != "":
			return r2
		if r2[1] >= t.size() or t[r2[1]][0] != "op" or t[r2[1]][1] != ")":
			error = "expected ')' at token %d" % r2[1]
			return [[], r2[1]]
		return [r2[0], r2[1] + 1]
	error = "unexpected '%s' at token %d" % [str(tok[1]), p]
	return [[], p]


# ---- evaluator -------------------------------------------------------------

func _ev(n: Array, vars: Dictionary):
	match n[0]:
		"num":
			return n[1]
		"var":
			if not vars.has(n[1]):
				push_error("[expr] unknown variable '%s'" % n[1])
				return 0
			return vars[n[1]]
		"un":
			var v = _ev(n[2], vars)
			return (not _truthy(v)) if n[1] == "not" else -v
		"bin":
			var a = _ev(n[2], vars)
			match n[1]:
				"and":
					return _truthy(a) and _truthy(_ev(n[3], vars))
				"or":
					return _truthy(a) or _truthy(_ev(n[3], vars))
			var bv = _ev(n[3], vars)
			match n[1]:
				"+": return a + bv
				"-": return a - bv
				"*": return a * bv
				"/":
					if a is int and bv is int:
						if bv == 0:
							push_error("[expr] integer division by zero")
							return 0
						@warning_ignore("integer_division")
						var q: int = a / bv                # native truncating int division
						return q
					return a / bv
				"%":
					return a % bv if (a is int and bv is int) else fmod(a, bv)
				">": return a > bv
				"<": return a < bv
				">=": return a >= bv
				"<=": return a <= bv
				"==": return a == bv
				"!=": return a != bv
		"call":
			var args: Array = []
			for x in n[2]:
				args.append(_ev(x, vars))
			match n[1]:
				"min": return min(args[0], args[1])
				"max": return max(args[0], args[1])
				"floor": return int(floor(float(args[0])))
				"ceil": return int(ceil(float(args[0])))
				"sqrt": return sqrt(float(args[0]))
				"int": return int(args[0])
				"abs": return abs(args[0])
				"if": return args[1] if _truthy(args[0]) else args[2]
	push_error("[expr] bad node")
	return 0


static func _truthy(v) -> bool:
	if v is bool:
		return v
	if v is int:
		return v != 0
	if v is float:
		return v != 0.0
	return false
