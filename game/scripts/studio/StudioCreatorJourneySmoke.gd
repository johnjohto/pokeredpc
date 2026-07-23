extends RefCounted
class_name StudioCreatorJourneySmoke
## The gh #58 Phase-5 gate: the complete original-map creator journey as ONE flow, driven
## only through real Studio seams — create a map, paint art and collision, undo/redo and
## Revert, place an NPC/sign/warp, get lint feedback and fix what it flags, link a second
## map into the world graph, author a branched NPC event, survive a Tiled-origin edit of
## the same file, and prove the result in a live Engine child: traversal off the map and
## the NPC's event branch executed.


func run(shell: StudioShell, scratch: String) -> bool:
	var ok := true

	# ---- create + paint + collision + undo/redo + Revert -----------------------------
	shell.select_workspace("maps")
	shell.new_map_control().pressed.emit()
	var fields: Dictionary = shell.new_map_fields()
	(fields["name"] as LineEdit).text = "JourneyTown"
	(fields["width"] as SpinBox).value = 8
	(fields["height"] as SpinBox).value = 6
	(fields["dialog"] as ConfirmationDialog).confirmed.emit()
	var town = shell.active_map_workspace()
	ok = _check("creator journey starts with a new 8x6 original map",
		town != null and town.document.label == "JourneyTown"
		and town.document.width == 8 and town.document.height == 6
		and town.document.is_walkable(town.document.default_spawn),
		shell.status_text()) and ok
	if town == null:
		return false

	var ground_tile: int = town.document.tile_at(Vector2i(3, 3))
	var accent: int = (ground_tile + 1) % int(town.document.tileset.get("tile_count", 1))
	town.select_tile(accent)
	town.select_tool("brush")
	var brushed: bool = town.paint_once(Vector2i(0, 0)) and town.paint_once(Vector2i(1, 0))
	town.undo()
	town.redo()
	ok = _check("brush art paints and undo/redo is exact",
		brushed and town.document.tile_at(Vector2i(0, 0)) == accent
		and town.document.tile_at(Vector2i(1, 0)) == accent) and ok
	# A wall row with one gap at x=7: spawn (0,0) stays connected to the town below.
	town.select_tool("solid")
	var walled := true
	for x in 7:
		walled = town.paint_once(Vector2i(x, 1)) and walled
	ok = _check("collision tool walls a row, leaving one gap",
		walled and not town.document.is_walkable(Vector2i(3, 1))
		and town.document.is_walkable(Vector2i(7, 1))) and ok
	town.save_control().pressed.emit()
	var saved_state: Dictionary = town.document.edit_state()
	town.select_tool("brush")
	town.paint_once(Vector2i(2, 0))
	var revert_error: String = town.revert_document()
	ok = _check("Revert returns the map to its last saved state",
		revert_error == "" and not town.is_dirty()
		and town.document.edit_state() == saved_state, revert_error) and ok

	# ---- companion map (receives the warp + shares a seamless edge) --------------------
	shell.select_workspace("maps")
	shell.new_map_control().pressed.emit()
	fields = shell.new_map_fields()
	(fields["name"] as LineEdit).text = "JourneyNorth"
	(fields["width"] as SpinBox).value = 4
	(fields["height"] as SpinBox).value = 4
	(fields["dialog"] as ConfirmationDialog).confirmed.emit()
	var north = shell.active_map_workspace()
	ok = _check("companion map created for the world link", north != null
		and north.document.label == "JourneyNorth", shell.status_text()) and ok
	# Its return warp goes in BEFORE the town's warp does: a warp pointing at a warp-less
	# destination fails whole-project validation, which would mask the lint leg below.
	north.select_tool("warp")
	var return_placed: bool = north.paint_once(Vector2i(1, 1))
	var north_ui: Dictionary = north.object_controls()
	(north_ui["id"] as LineEdit).text = "come_back"
	(north_ui["detail_a"] as LineEdit).text = "JourneyTown"
	(north_ui["number_a"] as SpinBox).value = 1
	(north_ui["apply"] as Button).pressed.emit()
	north.save_control().pressed.emit()
	ok = _check("companion's return warp saves through the inspector", return_placed,
		shell.status_text()) and ok
	town = shell.edit_map("JourneyTown")

	# ---- object placement -------------------------------------------------------------
	# The warp goes on the east edge: pokered's ExtraWarpCheck fn1 fires a warp on a
	# plain (non-door) tile only when the player faces the map edge (gh #80).
	town.select_tool("warp")
	var warp_placed: bool = town.paint_once(Vector2i(7, 0))
	var object_ui: Dictionary = town.object_controls()
	(object_ui["id"] as LineEdit).text = "to_north_town"
	(object_ui["detail_a"] as LineEdit).text = "JourneyNorth"
	(object_ui["number_a"] as SpinBox).value = 1
	(object_ui["apply"] as Button).pressed.emit()
	town.select_tool("npc")
	var npc_placed: bool = town.paint_once(Vector2i(5, 2))
	object_ui = town.object_controls()
	(object_ui["id"] as LineEdit).text = "guide"
	(object_ui["detail_a"] as LineEdit).text = "SPRITE_RED"
	(object_ui["detail_b"] as LineEdit).text = "STAY"
	(object_ui["detail_c"] as LineEdit).text = "DOWN"
	(object_ui["apply"] as Button).pressed.emit()
	town.select_tool("sign")
	var sign_placed: bool = town.paint_once(Vector2i(6, 4))
	object_ui = town.object_controls()
	(object_ui["id"] as LineEdit).text = "notice"
	(object_ui["detail_a"] as LineEdit).text = "Built entirely in Studio"
	(object_ui["apply"] as Button).pressed.emit()
	ok = _check("warp, NPC, and sign placed and configured through the inspector",
		warp_placed and npc_placed and sign_placed
		and town.document.warps.size() == 1 and town.document.objects.size() == 1
		and town.document.signs.size() == 1
		and str(town.document.warps[0].get("dest_map", "")) == "JourneyNorth",
		shell.status_text()) and ok

	# ---- lint feedback loop: seal the warp, read the problem, fix it ------------------
	town.select_tool("solid")
	for cell in [Vector2i(6, 0), Vector2i(7, 1)]:
		town.paint_once(cell)
	town.save_control().pressed.emit()
	shell.refresh_problems()
	var problems: ItemList = shell.problems_control()
	var sealed := _find(problems, "map.target_unreachable", "map:JourneyTown")
	ok = _check("lint flags the creator's sealed warp as an unreachable target",
		sealed >= 0, _unsuppressed_dump(problems)) and ok
	if sealed >= 0:
		problems.item_selected.emit(sealed)
		var focused = shell.active_map_workspace()
		ok = _check("selecting the problem returns focus to the broken map",
			focused != null and focused.document.label == "JourneyTown",
			shell.status_text()) and ok
	town = shell.active_map_workspace()
	town.select_tool("walkable")
	town.paint_once(Vector2i(6, 0))
	town.paint_once(Vector2i(7, 1))
	town.save_control().pressed.emit()
	shell.refresh_problems()
	# 21 = the reviewed Kanto gates from game/lint_suppressions.json (gh #57); the journey
	# maps must add zero unreviewed diagnostics of their own.
	ok = _check("the fix clears the problem; only the reviewed Kanto gates remain",
		_count(problems, "map:JourneyTown") == 0 and problems.item_count == 21,
		_unsuppressed_dump(problems)) and ok

	# ---- world link: one reciprocal edge ------------------------------------------------
	town = shell.edit_map("JourneyTown")
	var connection_ui: Dictionary = town.connection_controls()
	_select_metadata(connection_ui["direction"], "north")
	_select_text(connection_ui["map"], "JourneyNorth")
	(connection_ui["apply"] as Button).pressed.emit()
	ok = _check("world inspector links the two original maps reciprocally",
		town.world_document.connections("JourneyTown").size() == 1
		and town.world_document.connections("JourneyNorth").size() == 1
		and bool(MapDocument.open(scratch, "JourneyNorth").get("ok", false)),
		shell.status_text()) and ok
	town.save_control().pressed.emit()

	# ---- branched NPC event through the map-object seam --------------------------------
	town = shell.edit_map("JourneyTown")
	town.focus_object("npc", "guide")
	object_ui = town.object_controls()
	(object_ui["edit_event"] as Button).pressed.emit()
	var event_workspace = shell.active_event_workspace()
	ok = _check("NPC Create / Edit Event opens a linked branched event draft",
		event_workspace != null and event_workspace.document.basename == "journeytown_guide",
		shell.status_text()) and ok
	if event_workspace == null:
		return false
	event_workspace.add_command([], "if")
	event_workspace.document.replace_command([0], {"cmd": "if", "cond": "1", "then": [], "else": []})
	event_workspace.add_command([0, "then"], "notice")
	event_workspace.document.replace_command([0, "then", 0],
		{"cmd": "notice", "text": "Welcome to JourneyTown."})
	event_workspace.add_command([0, "then"], "set_flag")
	event_workspace.document.replace_command([0, "then", 1],
		{"cmd": "set_flag", "flag": "STUDIO_EVENT_BRANCH_RAN"})
	event_workspace.add_command([0, "else"], "ask")
	event_workspace.document.replace_command([0, "else", 0],
		{"cmd": "ask", "text": "Another branch?", "then": [], "else": []})
	event_workspace.add_command([0, "else", 0, "then"], "say")
	event_workspace.document.replace_command([0, "else", 0, "then", 0],
		{"cmd": "say", "text": "Yes."})
	event_workspace.add_command([0, "else", 0, "else"], "say")
	event_workspace.document.replace_command([0, "else", 0, "else", 0],
		{"cmd": "say", "text": "No."})
	event_workspace._rebuild_content()
	var event_save: String = event_workspace.save()
	var journey_report: Dictionary = ProjectValidator.validate_project(scratch)
	ok = _check("branched event saves and the grown project validates whole",
		event_save == "" and event_workspace.document.validate().is_empty()
		and bool(journey_report.get("ok", false)),
		event_save + "; " + "; ".join(PackedStringArray(journey_report.get("errors", [])))) and ok

	# ---- Tiled-origin round trip: foreign bytes enter, Studio returns unharmed --------
	var tmx_path := scratch.path_join("maps/JourneyTown.tmx")
	var tmx := FileAccess.get_file_as_string(tmx_path)
	# Simulate opening the file in Tiled and saving: an <editorsettings> block, a foreign
	# map property (first </properties> only — object property blocks must stay put), and
	# a foreign objectgroup. Studio must reopen and save without losing any of it.
	var map_props_end := tmx.find(" </properties>")
	var tiled_edit: String = tmx.substr(0, map_props_end) + \
		"  <property name=\"third-party:weather\" value=\"sun\"/>\n" + tmx.substr(map_props_end)
	tiled_edit = tiled_edit.replace(" <tileset", " <editorsettings>\n  <chunksize width=\"16\" height=\"16\"/>\n </editorsettings>\n <tileset")
	tiled_edit = tiled_edit.replace("</map>",
		" <objectgroup id=\"90\" name=\"Tiled Decor\">\n" +
		"  <object id=\"90\" name=\"stamp\" template=\"templates/stamp.tx\">\n   <point/>\n  </object>\n" +
		" </objectgroup>\n</map>")
	var write_error := _write_text(tmx_path, tiled_edit)
	town = shell.edit_map("JourneyTown")
	var town_reopened: bool = town != null
	var town_save: String = ""
	if town_reopened:
		town_save = town.document.save()
	var roundtrip := FileAccess.get_file_as_string(tmx_path)
	ok = _check("a Tiled-origin edit of the same file survives Studio open + save",
		write_error == "" and town_reopened and town_save == ""
		and roundtrip.contains("<editorsettings>")
		and roundtrip.contains("third-party:weather")
		and roundtrip.contains("template=\"templates/stamp.tx\"")
		and bool(MapDocument.open(scratch, "JourneyTown").get("ok", false)),
		write_error + town_save) and ok

	# ---- live play-test: warp out, seamless edge back, the NPC's event branch -----------
	var child = shell.launch_playtest(true, true, "JourneyTown", [], {
		"warp_cell": Vector2i(7, 0), "edge_cell": Vector2i(1, 3), "edge_direction": "down"},
		"journeytown_guide")
	if child == null:
		return _check("creator journey play-test child launches", false, shell.status_text()) and ok
	var ack: Dictionary = await child.wait_for_handshake(shell.get_tree(), 25000)
	var exited: bool = await child.wait_for_exit(shell.get_tree(), 5000)
	var traversed: Array = ack.get("traversed_maps", [])
	ok = _check("child Engine warps off the new map and returns across the seamless edge",
		bool(ack.get("ok", false)) and bool(ack.get("traverse_ok", false)) and exited
		and traversed == ["JourneyTown", "JourneyNorth", "JourneyTown"],
		str(ack.get("traverse_error", ack.get("error", ""))) + " maps=" + str(traversed)) and ok
	ok = _check("child Engine executes the journey NPC's authored branch",
		bool(ack.get("event_probe_ok", false)) and bool(ack.get("event_probe_flag", false)),
		str(ack.get("event_probe_error", ""))) and ok
	child.cleanup_handshake()
	print("[studiojourney] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


static func _find(problems: ItemList, rule: String, source_prefix: String) -> int:
	for index in problems.item_count:
		var diagnostic: Dictionary = problems.get_item_metadata(index)
		if bool(diagnostic.get("suppressed", false)): continue
		if rule != "" and str(diagnostic.get("rule", "")) != rule: continue
		if ProjectLint.source_key(diagnostic.get("source", {})).begins_with(source_prefix):
			return index
	return -1


static func _count(problems: ItemList, source_prefix: String) -> int:
	var count := 0
	for index in problems.item_count:
		var diagnostic: Dictionary = problems.get_item_metadata(index)
		if not bool(diagnostic.get("suppressed", false)) \
				and ProjectLint.source_key(diagnostic.get("source", {})).begins_with(source_prefix):
			count += 1
	return count


static func _unsuppressed_dump(problems: ItemList) -> String:
	var lines: Array[String] = []
	for index in problems.item_count:
		var diagnostic: Dictionary = problems.get_item_metadata(index)
		if not bool(diagnostic.get("suppressed", false)):
			lines.append(ProjectLint.format_line(diagnostic))
	return "%d unsuppressed: %s" % [lines.size(), "; ".join(lines)]


static func _select_text(option: OptionButton, wanted: String) -> void:
	for index in option.item_count:
		if option.get_item_text(index) == wanted:
			option.select(index)
			return


static func _select_metadata(option: OptionButton, wanted: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == wanted:
			option.select(index)
			return


static func _check(name: String, good: bool, detail := "") -> bool:
	print("[studiojourney] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


static func _write_text(path: String, value: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write " + path
	file.store_string(value)
	return ""
