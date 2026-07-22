extends RefCounted
class_name CanonJSON
## The canonical project serializer, GDScript twin of the extractor's `_pj_write`
## (tools/extract.py: `json.dump(obj, indent=1, ensure_ascii=False, sort_keys=True)` +
## a trailing LF) — ADR-020 d2 (gh #48). Studio saves through this so loading and
## re-saving an untouched record is BYTE-IDENTICAL to the extractor's emission: creator
## git diffs stay minimal, the gh #23 identity hash consumes the same bytes, and "Studio
## didn't corrupt anything" is a trivial comparison. Proven by `--studiotest`'s
## whole-kind re-serialization sweep against the raw Kanto tree.
##
## Python-compat notes baked in: keys sort by code point (Python str ordering); strings
## escape exactly Python's set (`\"` `\\` `\b` `\f` `\n` `\r` `\t`, other control chars
## as `\u00xx`; non-ASCII verbatim under ensure_ascii=False); Godot parses every JSON
## number as float, so whole floats re-emit as ints — the sweep is the proof that this
## matches what the emitter wrote for every record Studio may touch.


static func serialize(obj) -> String:
	return _enc(obj, 0)


## Canonical file bytes: the serialization + the trailing newline, LF-only.
static func write_file(path: String, obj) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "cannot write %s" % path
	f.store_string(serialize(obj) + "\n")
	f.close()
	return ""


static func _enc(v, depth: int) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			# Godot's JSON.parse yields floats for every number; the project's data is
			# integer-valued (proven by the sweep), so whole floats re-emit as ints.
			if v == floorf(v) and absf(v) < 9.0e15:
				return str(int(v))
			return JSON.stringify(v)     # a genuine float: shortest round-trip form
		TYPE_STRING:
			return _enc_str(v)
		TYPE_ARRAY:
			var a: Array = v
			if a.is_empty():
				return "[]"
			var pad := " ".repeat(depth + 1)
			var parts: Array = []
			for e in a:
				parts.append(pad + _enc(e, depth + 1))
			return "[\n" + ",\n".join(parts) + "\n" + " ".repeat(depth) + "]"
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.is_empty():
				return "{}"
			var keys := d.keys()
			keys.sort()                  # code-point order, as Python's sort_keys
			var pad2 := " ".repeat(depth + 1)
			var parts2: Array = []
			for k in keys:
				parts2.append(pad2 + _enc_str(str(k)) + ": " + _enc(d[k], depth + 1))
			return "{\n" + ",\n".join(parts2) + "\n" + " ".repeat(depth) + "}"
	return _enc_str(str(v))              # any exotic type: its string form (never expected)


static func _enc_str(s: String) -> String:
	var out := "\""
	for ch in s:
		var c: int = ch.unicode_at(0)
		if c == 0x22:                    # "
			out += "\\\""
		elif c == 0x5C:                  # backslash
			out += "\\\\"
		elif c == 0x0A:
			out += "\\n"
		elif c == 0x0D:
			out += "\\r"
		elif c == 0x09:
			out += "\\t"
		elif c == 0x08:
			out += "\\b"
		elif c == 0x0C:
			out += "\\f"
		elif c < 0x20:
			out += "\\u%04x" % c
		else:
			out += ch                    # non-ASCII verbatim (ensure_ascii=False)
	return out + "\""
