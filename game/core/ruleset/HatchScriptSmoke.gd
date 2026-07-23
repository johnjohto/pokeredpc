extends RefCounted
class_name HatchScriptSmoke
## gh #64 (ADR-028): HatchScript core — statement semantics, integer-exact math,
## position-named errors, the bounded sandbox surface, step-budget termination, and
## run-to-run determinism.


func run() -> bool:
	var ok := true
	ok = _check("let/assign/return with arithmetic",
		_run("let x = 2\nlet y = 3\nx = x + y\nreturn x * y + 1") == 16, "") and ok
	ok = _check("integer division truncates and stays int; modulo is exact",
		_run("return 7 / 2") == 3 and _run("return 7 / 2") is int
		and _run("return 7 % 2") == 1 and _run("return 7 / 2.0") == 3.5, "") and ok
	ok = _check("strings concatenate and compare",
		_run("let a = \"ab\"\nreturn a + \"cd\"") == "abcd"
		and _run("return \"key\" == \"key\"") == true
		and _run("return \"a\" != \"b\"") == true, "") and ok
	ok = _check("if/else branches on truthiness",
		_run("let n = 5\nif n > 3 { return \"big\" } else { return \"small\" }") == "big"
		and _run("let n = 0\nif n { return 1 } else { return 2 }") == 2
		and _run("if (true) { return 1 } else { return 2 }") == 1
		and _run("if (true) and false { return 1 } else { return 2 }") == 2, "") and ok
	ok = _check("while accumulates; comments and blank lines are ignored",
		_run("# sum 1..10\nlet total = 0\nlet n = 1\n\nwhile n <= 10 {\n  total = total + n  # add\n  n = n + 1\n}\nreturn total") == 55, "") and ok
	ok = _check("early return escapes a nested loop",
		_run("let n = 0\nwhile 1 {\n  n = n + 1\n  if n == 4 { return n }\n}\nreturn -1") == 4, "") and ok
	ok = _check("host functions are the only call surface and run",
		_run("return roll(2, 3) + min(10, 4)", {},
			{"roll": func(a, b): return a * b}) == 10
		and _run("notify()\nreturn 1", {}, {"notify": func(): return null}) == 1, "") and ok
	var host_value_error := _error_of("return payload", {"payload": [1]})
	var host_result_error := _error_of("return values()", {},
		{"values": func(): return [1]})
	var null_input_error := _error_of("return payload", {"payload": null})
	var null_value_error := _error_of("return notify()", {},
		{"notify": func(): return null})
	ok = _check("non-scalar host values are refused at the source boundary",
		host_value_error.contains("Array")
		and host_value_error.contains("line 1, column 8")
		and host_result_error.contains("Array")
		and host_result_error.contains("line 1, column 8")
		and null_input_error.contains("Nil")
		and null_input_error.contains("line 1, column 8")
		and null_value_error.contains("no value")
		and null_value_error.contains("line 1, column 8"),
		"input=%s; result=%s; null_input=%s; null_value=%s" % [
			host_value_error, host_result_error, null_input_error, null_value_error]) and ok
	var host_arity_error := _error_of("return pair(1)", {},
		{"pair": func(a, b): return a + b})
	ok = _check("registered host-call arity errors are positioned",
		host_arity_error.contains("2 argument")
		and host_arity_error.contains("line 1, column 8"), host_arity_error) and ok
	var discarded_arithmetic := HatchScript.parse("1 + 2").error
	var discarded_intrinsic := HatchScript.parse("min(1, 2)").error
	ok = _check("only host calls may be standalone statements",
		discarded_arithmetic.contains("host function call")
		and discarded_arithmetic.contains("line 1, column 1")
		and discarded_intrinsic.contains("host function call")
		and discarded_intrinsic.contains("line 1, column 1"),
		"arithmetic=%s; intrinsic=%s" % [discarded_arithmetic, discarded_intrinsic]) and ok
	ok = _check("intrinsics match FormulaExpr's set",
		_run("return max(2, abs(-5)) + floor(3.7) + ceil(3.2) + int(9.9)") == 21
		and _run("return if(true, 7, 9)") == 7, "") and ok
	var builtin_type_error := _error_of("return sqrt(\"x\")")
	ok = _check("intrinsic type failures are positioned language errors",
		builtin_type_error.contains("numeric")
		and builtin_type_error.contains("line 1, column 8"), builtin_type_error) and ok

	# The bounded sandbox probe surface: unregistered names are refused by a
	# runtime error naming the attempted capability.
	for escape in [["return frob(1)", "frob"], ["return OS()", "OS"], ["return load(\"x\")", "load"]]:
		var s := HatchScript.parse(escape[0])
		var result = s.run()
		ok = _check("escape refused by name: %s" % escape[0],
			(s.error != "" or result == null) and s.error.contains(str(escape[1])),
			s.error) and ok
	ok = _check("step budget halts a runaway loop",
		_error_of("while 1 { }", {}, {}, 1000).contains("step budget"), "") and ok
	ok = _check("assignment without let is refused",
		_error_of("x = 1").contains("let"), "") and ok
	ok = _check("unknown variable is named",
		_error_of("return missing").contains("missing"), "") and ok
	var positioned_runtime_error := _error_of("let x = 1\nreturn missing")
	ok = _check("runtime errors name line and column",
		positioned_runtime_error.contains("missing")
		and positioned_runtime_error.contains("line 2, column 8"),
		positioned_runtime_error) and ok
	var positioned_assignment := _error_of("let x = 1\nmissing = x")
	var positioned_division := _error_of("let x = 1\nreturn 1 / 0")
	var positioned_call := _error_of("let x = 1\nreturn nope()")
	var positioned_budget := _error_of("let x = 0\nwhile 1 { x = x + 1 }", {}, {}, 10)
	ok = _check("all runtime failure classes name their source position",
		positioned_assignment.contains("line 2, column 1")
		and positioned_division.contains("line 2, column 10")
		and positioned_call.contains("line 2, column 8")
		and positioned_budget.contains("line 2, column 1"),
		"assign=%s; divide=%s; call=%s; budget=%s" % [
			positioned_assignment, positioned_division, positioned_call, positioned_budget]) and ok
	ok = _check("integer division by zero is an error",
		_error_of("return 1 / 0").contains("division by zero"), "") and ok
	var modulo_error := _error_of("return 1 % 0")
	ok = _check("integer modulo by zero is a positioned error",
		modulo_error.contains("modulo by zero")
		and modulo_error.contains("line 1, column 10"), modulo_error) and ok
	var unary_type_error := _error_of("return -\"no\"")
	var binary_type_error := _error_of("return true - 1")
	var float_zero_error := _error_of("return 1.0 / 0.0")
	ok = _check("invalid operands are positioned language errors",
		unary_type_error.contains("numeric operand")
		and unary_type_error.contains("line 1, column 8")
		and binary_type_error.contains("numeric operands")
		and binary_type_error.contains("line 1, column 13")
		and float_zero_error.contains("division by zero")
		and float_zero_error.contains("line 1, column 12"),
		"unary=%s; binary=%s; divide=%s" % [
			unary_type_error, binary_type_error, float_zero_error]) and ok
	ok = _check("parse errors name the position",
		HatchScript.parse("let x = ").error != ""
		and HatchScript.parse("if 1 { return 1").error.contains("}"), "") and ok
	var positioned_parse_error := HatchScript.parse("let x = 1\nreturn @").error
	ok = _check("parse errors name line and column",
		positioned_parse_error.contains("line 2, column 8"), positioned_parse_error) and ok
	var positioned_structure_error := HatchScript.parse("let x = 1\nif x { return 1").error
	ok = _check("structural parse errors name line and column",
		positioned_structure_error.contains("line 2"), positioned_structure_error) and ok
	var malformed_number_error := HatchScript.parse("return 1.2.3").error
	ok = _check("malformed numbers fail at the extra decimal point",
		malformed_number_error.contains("decimal point")
		and malformed_number_error.contains("line 1, column 11"),
		malformed_number_error) and ok
	ok = _check("arity of intrinsics is checked at parse",
		HatchScript.parse("return min(1)").error.contains("min"), "") and ok

	# Determinism: identical source + inputs + host functions, byte-identical outcomes.
	var source := "let acc = 0\nwhile acc < limit { acc = acc + step }\nreturn acc * 2"
	var deterministic := HatchScript.parse(source)
	var first = deterministic.run({"limit": 10, "step": 3})
	var first_bytes := JSON.stringify([first, deterministic.error]).to_utf8_buffer()
	var second = deterministic.run({"limit": 10, "step": 3})
	var second_bytes := JSON.stringify([second, deterministic.error]).to_utf8_buffer()
	ok = _check("repeated runs are byte-identical", first == 24 and second == first
		and first_bytes == second_bytes,
		"%s vs %s" % [first_bytes.hex_encode(), second_bytes.hex_encode()]) and ok
	var reusable := HatchScript.parse("return value")
	var failed_run = reusable.run()
	var failed_error := reusable.error
	var recovered_run = reusable.run({"value": 7})
	ok = _check("a runtime error does not poison later runs",
		failed_run == null and failed_error.contains("value")
		and recovered_run == 7 and reusable.error == "", reusable.error) and ok
	print("[hatchscript] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _run(source: String, vars := {}, functions := {}):
	return HatchScript.parse(source).run(vars, functions)


static func _error_of(source: String, vars := {}, functions := {}, budget := 0) -> String:
	var s := HatchScript.parse(source)
	if budget > 0:
		s.run(vars, functions, budget)
	else:
		s.run(vars, functions)
	return s.error


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[hatchscript] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
