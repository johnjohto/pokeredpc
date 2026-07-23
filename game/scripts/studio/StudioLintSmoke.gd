extends RefCounted
class_name StudioLintSmoke
## gh #57: the Studio Problems panel. Asserts a clean Kanto project lists only reviewed
## suppressions, that selecting one focuses its map object, and that an event-sourced
## diagnostic opens the event workspace. Runs inside --studiotest against the scratch
## project the suite already opened.


func run(shell: StudioShell, scratch: String) -> bool:
	var ok := true
	shell.refresh_problems()
	var problems: ItemList = shell.problems_control()
	var game_corner := _find(problems, "map:GameCorner/object:SPRITE_ROCKET@9,5")
	ok = _check("clean Kanto lists only reviewed suppressions",
		problems.item_count >= 21 and _unreviewed(problems) == 0 and game_corner >= 0,
		"items=%d unreviewed=%d" % [problems.item_count, _unreviewed(problems)]) and ok
	if game_corner >= 0:
		problems.item_selected.emit(game_corner)
		var workspace = shell.active_map_workspace()
		ok = _check("selecting a map-object problem focuses the object on its map",
			workspace != null and workspace.document.label == "GameCorner"
			and str((workspace.object_controls()["id"] as LineEdit).text) == "SPRITE_ROCKET@9,5",
			"workspace=%s" % (workspace.document.label if workspace != null else "none")) and ok

	# An event-sourced diagnostic: a trigger linking an event whose own trigger points
	# at a different map. (Creator-side link mistake; Kanto's imported objects carry no
	# event links, so inject one scratch trigger.)
	var tmx_path := scratch.path_join("maps/BikeShop.tmx")
	var tmx := FileAccess.get_file_as_string(tmx_path)
	var injection := "<object id=\"90\" name=\"studio_step\" class=\"pokeredpc:trigger\" " + \
		"x=\"16\" y=\"16\" width=\"16\" height=\"16\"><properties>" + \
		"<property name=\"pokeredpc:event\" value=\"event:blues_house_daisy\"/>" + \
		"</properties></object>\n </objectgroup>"
	var written := _write_text(tmx_path, tmx.replace("</objectgroup>", injection))
	ok = _check("scratch map accepts a mislinked trigger", written == "" and tmx != FileAccess.get_file_as_string(tmx_path),
		written) and ok
	shell.refresh_problems()
	var event_index := _find(problems, "event:blues_house_daisy")
	ok = _check("the mislinked trigger surfaces as an event-sourced problem",
		event_index >= 0,
		"items=%d" % problems.item_count) and ok
	if event_index >= 0:
		problems.item_selected.emit(event_index)
		var event_workspace = shell.active_event_workspace()
		ok = _check("selecting an event problem opens the event workspace",
			event_workspace != null and event_workspace.document.basename == "blues_house_daisy",
			"workspace=%s" % (event_workspace.document.basename if event_workspace != null else "none")) and ok
	print("[studiolint] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _find(problems: ItemList, source_key: String) -> int:
	for index in problems.item_count:
		var diagnostic: Dictionary = problems.get_item_metadata(index)
		if ProjectLint.source_key(diagnostic.get("source", {})) == source_key:
			return index
	return -1


static func _unreviewed(problems: ItemList) -> int:
	var count := 0
	for index in problems.item_count:
		var diagnostic: Dictionary = problems.get_item_metadata(index)
		if not bool(diagnostic.get("suppressed", false)):
			count += 1
	return count


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[studiolint] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


static func _write_text(path: String, value: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write " + path
	file.store_string(value)
	return ""
