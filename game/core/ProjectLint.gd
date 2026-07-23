extends RefCounted
class_name ProjectLint
## Deep Phase-5 lint module (gh #57). One interface returns source-addressed diagnostics
## for Studio, CLI, and tests; callers never need to know graph or suppression mechanics.

const _NEIGHBORS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


## Returns {ok, diagnostics, errors, warnings, suppressed}. Warnings are review-required:
## an unsuppressed warning makes `ok` false, while a reviewed warning remains in the result
## with `suppressed=true` and its required reason.
static func lint_project(dir: String) -> Dictionary:
	var root := ProjectSettings.globalize_path(dir).simplify_path()
	var diagnostics: Array = []
	var validation := ProjectValidator.validate_project(root)
	for message in validation.get("errors", []):
		diagnostics.append(_diag("project.invalid", "error", str(message),
			{"kind": "project", "path": _path_from_error(str(message))}))
	if bool(validation.get("ok", false)):
		_lint_valid_project(root, diagnostics)
	return _finalize(root, diagnostics)


static func source_key(source: Dictionary) -> String:
	match str(source.get("kind", "project")):
		"map_object": return "map:%s/object:%s" % [source.get("map", ""), source.get("object", "")]
		"map_cell": return "map:%s/cell:%d,%d" % [source.get("map", ""),
			int((source.get("cell", [0, 0]) as Array)[0]),
			int((source.get("cell", [0, 0]) as Array)[1])]
		"event": return "event:%s" % source.get("event", "")
	return str(source.get("path", "project"))


## One-line rendering shared by the CLI and Studio's Problems panel, so the two can
## never drift on how a diagnostic reads.
static func format_line(diagnostic: Dictionary) -> String:
	return "%s %s %s — %s" % [str(diagnostic.get("severity", "error")).to_upper(),
		str(diagnostic.get("rule", "project.invalid")),
		source_key(diagnostic.get("source", {})), str(diagnostic.get("message", ""))]


static func _lint_valid_project(root: String, diagnostics: Array) -> void:
	var events := _load_records(root.path_join("data/events"))
	var backed := _backed_objects(events)
	var world = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("data/world.json")))
	var world_maps: Dictionary = world.get("maps", {}) if world is Dictionary else {}
	var maps := {}
	for file in DirAccess.get_files_at(root.path_join("maps")):
		if not file.to_lower().ends_with(".tmx"): continue
		var label := file.get_basename()
		var opened := MapDocument.open(root, label)
		if bool(opened.get("ok", false)): maps[label] = opened["document"]
	for label in maps:
		_lint_map(maps[label], world_maps, backed, events, diagnostics)
	_lint_event_links(maps, events, diagnostics)


static func _lint_map(document: MapDocument, world_maps: Dictionary, backed: Dictionary,
		events: Dictionary, diagnostics: Array) -> void:
	var blockers := {}
	# Imported pokered maps carry `_legacy_locked` on any record kind (warps/signs/NPCs/
	# triggers) — a map with no NPCs (Mt Moon B1F, Route 5) is still imported data, so
	# scan every kind before applying original-map rules.
	var has_legacy := false
	for records in [document.warps, document.signs, document.objects, document.triggers]:
		for record in records:
			has_legacy = has_legacy or bool(record.get("_legacy_locked", false))
	for object in document.objects:
		var cell := Vector2i(int(object.get("x", 0)), int(object.get("y", 0)))
		blockers[cell] = object
		if not bool(object.get("_legacy_locked", false)) and not document.is_walkable(cell):
			diagnostics.append(_diag("map.npc_unstandable", "error",
				"NPC '%s' stands on a solid cell" % object.get("id", ""),
				_object_source(document, object)))
	var targets := _targets(document)
	var emitted := {}
	for target in targets:
		var target_cell: Vector2i = target["cell"]
		var approaches: Array[Vector2i] = []
		for delta in _NEIGHBORS:
			var candidate: Vector2i = target_cell + delta
			if document.is_walkable(candidate): approaches.append(candidate)
		if approaches.is_empty():
			if not has_legacy:
				diagnostics.append(_diag("map.target_unreachable", "error",
					"%s '%s' has no walkable approach" % [target["kind"], target["id"]],
					_cell_source(document, target_cell)))
			continue
		var blocked: Array[Vector2i] = []
		for cell in approaches:
			if blockers.has(cell): blocked.append(cell)
		if blocked.size() != approaches.size(): continue
		for cell in blocked:
			_emit_blocker(document, blockers[cell], "seals the only approach to %s '%s'" % [
				target["kind"], target["id"]], backed, has_legacy, diagnostics, emitted)

	# Static articulation points: remove all solid objects, then ask whether putting one
	# back separates two useful regions (target/connection-bearing, not staff alcoves).
	var components := _components(document, blockers)
	for cell in blockers:
		var object: Dictionary = blockers[cell]
		if str(object.get("sprite", "")) == "SPRITE_LINK_RECEPTIONIST" \
				or not document.is_walkable(cell):
			continue
		var ids := {}
		for delta in _NEIGHBORS:
			if components.has(cell + delta): ids[components[cell + delta]] = true
		if ids.size() < 2: continue
		var useful := true
		var sizes: Array = []
		for component_id in ids:
			if not _component_worth_reaching(document, int(component_id), components,
					targets, cell, world_maps):
				useful = false
				break
			var count := 0
			for value in components.values():
				if int(value) == int(component_id): count += 1
			sizes.append(count)
		if useful:
			sizes.sort()
			sizes.reverse()
			_emit_blocker(document, object, "separates useful regions of %s cells" %
				" + ".join(PackedStringArray(sizes.map(func(n): return str(n)))),
				backed, has_legacy, diagnostics, emitted)

	# Original maps get a stronger default-spawn reachability check. Imported Kanto maps
	# can intentionally contain disconnected warp/pad pockets, so their legacy payload is
	# the explicit compatibility marker that opts them out of this generic-map rule.
	if not has_legacy:
		_lint_original_reachability(document, blockers, targets, diagnostics)


static func _emit_blocker(document: MapDocument, object: Dictionary, why: String,
		backed: Dictionary, legacy: bool, diagnostics: Array, emitted: Dictionary) -> void:
	var source := _object_source(document, object)
	var key := source_key(source)
	if emitted.has(key): return
	emitted[key] = true
	diagnostics.append(_diag("map.blocking_object", "warning",
		"Object '%s' %s" % [object.get("id", ""), why], source))
	if _engine_clears(object): return
	var backing_key := "%s|%s" % [document.label, object.get("id", "")]
	if not backed.has(backing_key):
		# On an original map an unbacked STAY blocker is an authoring bug (error).
		# Imported pokered maps also clear sprites through hard-coded engine scripts the
		# data cannot see (the POKé FLUTE's Snorlax), so there it is review-required.
		diagnostics.append(_diag("event.blocker_unbacked", "warning" if legacy else "error",
			"Blocking object '%s' has no visible/hide event that can clear it" % object.get("id", ""),
			source))


## Engine mechanics that clear a blocker without any authored event: item balls are
## picked up, boulders are shoved with STRENGTH, and a trainer with a sight line
## marches off their post to engage (pokered's trainer-spotting).
static func _engine_clears(object: Dictionary) -> bool:
	var sprite := str(object.get("sprite", ""))
	if sprite.begins_with("SPRITE_POKE_BALL") or sprite == "SPRITE_BOULDER":
		return true
	var runtime: Dictionary = object.get("_runtime", {})
	return runtime.has("sight")


static func _lint_original_reachability(document: MapDocument, blockers: Dictionary,
		targets: Array, diagnostics: Array) -> void:
	var start := document.default_spawn
	if not document.is_walkable(start):
		diagnostics.append(_diag("map.spawn_unstandable", "error",
			"Default spawn %s is not walkable" % start, _cell_source(document, start)))
		return
	var seen := _flood(document, start, blockers)
	for target in targets:
		var cell: Vector2i = target["cell"]
		var reachable := seen.has(cell)
		for delta in _NEIGHBORS: reachable = reachable or seen.has(cell + delta)
		if not reachable:
			diagnostics.append(_diag("map.target_unreachable", "error",
				"%s '%s' is unreachable from the default spawn" % [target["kind"], target["id"]],
				_cell_source(document, cell)))


static func _lint_event_links(maps: Dictionary, events: Dictionary, diagnostics: Array) -> void:
	for label in maps:
		var document: MapDocument = maps[label]
		for kind in ["npc", "trigger"]:
			for object in document.records_for_kind(kind):
				if bool(object.get("_legacy_locked", false)): continue
				var event_id := str(object.get("event", ""))
				if event_id == "": continue
				var basename := event_id.trim_prefix("event:")
				if not events.has(basename): continue # ProjectValidator owns dangling refs.
				var trigger: Dictionary = (events[basename] as Dictionary).get("trigger", {})
				var matches: bool = str(trigger.get("map", "")) == "map:" + label
				if kind == "npc": matches = matches and str(trigger.get("object", "")) == str(object.get("id", ""))
				if not matches:
					diagnostics.append(_diag("event.object_link_mismatch", "error",
						"Object '%s' links %s, but that event's trigger points elsewhere" % [
							object.get("id", ""), event_id],
						{"kind": "event", "event": basename,
							"path": "data/events/%s.json" % basename,
							"map": label, "object": str(object.get("id", ""))}))


static func _targets(document: MapDocument) -> Array:
	var out: Array = []
	for warp in document.warps:
		out.append({"kind": "warp", "id": str(warp.get("id", "")),
			"cell": Vector2i(int(warp.get("x", 0)), int(warp.get("y", 0)))})
	for sign in document.signs:
		out.append({"kind": "sign", "id": str(sign.get("id", "")),
			"cell": Vector2i(int(sign.get("x", 0)), int(sign.get("y", 0)))})
	for object in document.objects:
		if str(object.get("sprite", "")).begins_with("SPRITE_POKE_BALL"):
			out.append({"kind": "item", "id": str(object.get("id", "")),
				"cell": Vector2i(int(object.get("x", 0)), int(object.get("y", 0)))})
	return out


static func _components(document: MapDocument, blockers: Dictionary) -> Dictionary:
	var out := {}
	var component_id := 0
	for y in document.height:
		for x in document.width:
			var start := Vector2i(x, y)
			if out.has(start) or blockers.has(start) or not document.is_walkable(start): continue
			component_id += 1
			var pending: Array[Vector2i] = [start]
			out[start] = component_id
			while not pending.is_empty():
				var cell: Vector2i = pending.pop_back()
				for delta in _NEIGHBORS:
					var next: Vector2i = cell + delta
					if out.has(next) or blockers.has(next) or not document.is_walkable(next): continue
					out[next] = component_id
					pending.append(next)
	return out


static func _flood(document: MapDocument, start: Vector2i, blockers: Dictionary) -> Dictionary:
	var seen := {start: true}
	var pending: Array[Vector2i] = [start]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for delta in _NEIGHBORS:
			var next: Vector2i = cell + delta
			if seen.has(next) or blockers.has(next) or not document.is_walkable(next): continue
			seen[next] = true
			pending.append(next)
	return seen


static func _component_worth_reaching(document: MapDocument, component_id: int,
		components: Dictionary, targets: Array, blocker: Vector2i, world_maps: Dictionary) -> bool:
	for target in targets:
		var cell: Vector2i = target["cell"]
		if cell == blocker: continue
		if int(components.get(cell, -1)) == component_id: return true
		for delta in _NEIGHBORS:
			if int(components.get(cell + delta, -1)) == component_id: return true
	var directions := {}
	for connection in world_maps.get("map:" + document.label, []):
		directions[str(connection.get("direction", ""))] = true
	for cell in components:
		if int(components[cell]) != component_id: continue
		if (cell.y == 0 and directions.has("north")) \
				or (cell.y == document.height - 1 and directions.has("south")) \
				or (cell.x == 0 and directions.has("west")) \
				or (cell.x == document.width - 1 and directions.has("east")):
			return true
	return false


static func _backed_objects(events: Dictionary) -> Dictionary:
	var out := {}
	for basename in events:
		var event: Dictionary = events[basename]
		var trigger: Dictionary = event.get("trigger", {})
		var label := str(trigger.get("map", "")).trim_prefix("map:")
		if str(trigger.get("kind", "")) == "visible" and trigger.has("object"):
			out["%s|%s" % [label, trigger["object"]]] = true
		_collect_hide_commands(event.get("commands", []), label, out)
	return out


static func _collect_hide_commands(commands, label: String, out: Dictionary) -> void:
	if not (commands is Array): return
	for command in commands:
		if not (command is Dictionary): continue
		if str(command.get("cmd", "")) == "hide_object":
			out["%s|%s" % [label, command.get("object", "")]] = true
		_collect_hide_commands(command.get("then", []), label, out)
		_collect_hide_commands(command.get("else", []), label, out)


static func _load_records(dir: String) -> Dictionary:
	var out := {}
	if not DirAccess.dir_exists_absolute(dir): return out
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"): continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		if parsed is Dictionary: out[file.get_basename()] = parsed
	return out


static func _finalize(root: String, diagnostics: Array) -> Dictionary:
	var suppressions := _load_suppressions(root)
	var used := {}
	for diagnostic in diagnostics:
		if str(diagnostic.get("severity", "")) != "warning": continue
		var key := "%s|%s" % [diagnostic.get("rule", ""), source_key(diagnostic.get("source", {}))]
		if suppressions.has(key):
			diagnostic["suppressed"] = true
			diagnostic["suppression_reason"] = suppressions[key]
			used[key] = true
	for key in suppressions:
		if not used.has(key):
			diagnostics.append(_diag("suppression.unused", "warning",
				"Reviewed suppression no longer matches a diagnostic: %s" % key,
				{"kind": "project", "path": "data/lint_suppressions.json"}))
	var errors := 0
	var warnings := 0
	var suppressed := 0
	for diagnostic in diagnostics:
		if bool(diagnostic.get("suppressed", false)):
			suppressed += 1
		elif str(diagnostic.get("severity", "")) == "error": errors += 1
		elif str(diagnostic.get("severity", "")) == "warning": warnings += 1
	return {"ok": errors == 0 and warnings == 0, "diagnostics": diagnostics,
		"errors": errors, "warnings": warnings, "suppressed": suppressed}


static func _load_suppressions(root: String) -> Dictionary:
	var out := {}
	var path := root.path_join("data/lint_suppressions.json")
	if not FileAccess.file_exists(path): return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary): return out
	for entry in parsed.get("suppressions", []):
		if entry is Dictionary:
			out["%s|%s" % [entry.get("rule", ""), entry.get("source", "")]] = str(entry.get("reason", ""))
	return out


static func _diag(rule: String, severity: String, message: String, source: Dictionary) -> Dictionary:
	return {"rule": rule, "severity": severity, "message": message, "source": source,
		"suppressed": false, "suppression_reason": ""}


static func _object_source(document: MapDocument, object: Dictionary) -> Dictionary:
	return {"kind": "map_object", "path": "maps/%s.tmx" % document.label,
		"map": document.label, "object": str(object.get("id", "")), "object_kind": "npc",
		"cell": [int(object.get("x", 0)), int(object.get("y", 0))]}


static func _cell_source(document: MapDocument, cell: Vector2i) -> Dictionary:
	return {"kind": "map_cell", "path": "maps/%s.tmx" % document.label,
		"map": document.label, "cell": [cell.x, cell.y]}


static func _path_from_error(message: String) -> String:
	var dash := message.find(" — ")
	var colon := message.find(": ")
	var at := dash if dash >= 0 else colon
	return message.substr(0, at) if at >= 0 else "project"
