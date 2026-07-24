extends RefCounted
class_name ProjectLintSmoke
## gh #57: the shared map/story softlock lint. Proves a clean Kanto project has no
## unreviewed diagnostics, that reviewed faithful gates stay suppressed by name+reason,
## and that deleting the authored records behind gh #79/#89/#90 re-creates and identifies
## each blocker — the exact regression those bugs were (a door whose "opens" claim rested
## on a data record nobody checked).


func run() -> bool:
	var ok := true
	var clean: Dictionary = ProjectLint.lint_project("res://project")
	ok = _check("clean Kanto project has no unreviewed errors or warnings",
		bool(clean.get("ok", false)) and int(clean.get("errors", -1)) == 0
		and int(clean.get("warnings", -1)) == 0,
		_summary(clean)) and ok
	var suppressed: Array = (clean.get("diagnostics", []) as Array).filter(
		func(d): return bool(d.get("suppressed", false)))
	ok = _check("every reviewed gate stays suppressed with its reason",
		suppressed.size() == int(clean.get("suppressed", -1)) and suppressed.size() >= 21
		and suppressed.all(func(d): return str(d.get("suppression_reason", "")) != ""),
		"suppressed=%d/%s" % [suppressed.size(), str(clean.get("suppressed", "?"))]) and ok

	# Regression fixtures derived from Kanto data: delete the authored records that open
	# each historical softlock door. The lint must re-create and identify each blocker.
	var scratch := OS.get_user_data_dir().path_join("projectlint_scratch_%d" % OS.get_process_id())
	if DirAccess.dir_exists_absolute(scratch):
		OS.move_to_trash(scratch)
	var copy_error := ProjectData.copy_dir(ProjectSettings.globalize_path("res://project"), scratch)
	ok = _check("regression scratch copies the Kanto project", copy_error == "", copy_error) and ok
	if copy_error != "":
		return false
	# gh #79 — Silph Co's door (the Tower-rescue visible record that hides ROCKET8).
	var deleted := _delete(scratch, "data/events/saffron_silph_guard_shown.json")
	# gh #89 — the Game Corner poster's ROCKET (shown + hidden by authored records).
	deleted += _delete(scratch, "data/events/game_corner_rocket_shown.json")
	deleted += _delete(scratch, "data/events/game_corner_rocket_leaves.json")
	# gh #90 — Cerulean Cave's guard (the CHAMPION visible record).
	deleted += _delete(scratch, "data/events/cerulean_cave_guy_shown.json")
	ok = _check("the four door-opening records delete cleanly", deleted == "",
		deleted) and ok
	var regressed: Dictionary = ProjectLint.lint_project(scratch)
	var hits := {}
	for d in regressed.get("diagnostics", []):
		if bool(d.get("suppressed", false)): continue
		hits["%s|%s" % [d.get("rule", ""), ProjectLint.source_key(d.get("source", {}))]] = d
	var doors := [
		["gh #79", "event.blocker_unbacked|map:SaffronCity/object:SPRITE_ROCKET@18,22"],
		["gh #89", "event.blocker_unbacked|map:GameCorner/object:SPRITE_ROCKET@9,5"],
		["gh #90", "event.blocker_unbacked|map:CeruleanCity/object:SPRITE_SUPER_NERD@4,12"],
	]
	for door in doors:
		var hit: Dictionary = hits.get(str(door[1]), {})
		ok = _check("%s blocker is re-created and identified" % door[0],
			not hit.is_empty() and str(hit.get("severity", "")) == "warning",
			_summary(regressed)) and ok
	ok = _check("the regressed project fails the gate",
		not bool(regressed.get("ok", true)), "ok=%s" % str(regressed.get("ok"))) and ok
	if DirAccess.dir_exists_absolute(scratch):
		OS.move_to_trash(scratch)
	print("[projectlint] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _summary(result: Dictionary) -> String:
	var lines: Array[String] = []
	for d in result.get("diagnostics", []):
		if bool(d.get("suppressed", false)): continue
		lines.append("%s %s %s" % [str(d.get("severity", "")).to_upper(), str(d.get("rule", "")),
			ProjectLint.source_key(d.get("source", {}))])
	return "%d errors/%d warnings: %s" % [int(result.get("errors", -1)),
		int(result.get("warnings", -1)), "; ".join(lines)]


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[projectlint] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


static func _delete(root: String, rel: String) -> String:
	var path := root.path_join(rel)
	if not FileAccess.file_exists(path):
		return "missing " + rel
	return "" if DirAccess.remove_absolute(path) == OK else "cannot delete " + rel
