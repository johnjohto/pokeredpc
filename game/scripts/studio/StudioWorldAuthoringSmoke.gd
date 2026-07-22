extends RefCounted
class_name StudioWorldAuthoringSmoke
## End-to-end gh #55 gate. Real Studio tools/inspectors author four typed object kinds,
## make one reciprocal world link, save/reopen without drift, then a child Engine walks
## through the authored warp and back through the authored seamless edge.


func run(shell: StudioShell, scratch: String) -> bool:
	var ok := true
	shell.select_workspace("maps")
	shell.new_map_control().pressed.emit()
	var fields: Dictionary = shell.new_map_fields()
	(fields["name"] as LineEdit).text = "StudioLinkTest"
	(fields["width"] as SpinBox).value = 4
	(fields["height"] as SpinBox).value = 4
	(fields["dialog"] as ConfirmationDialog).confirmed.emit()
	var linked = shell.active_map_workspace()
	ok = _check("second authored map opens with world/object inspectors",
		linked != null and linked.document.label == "StudioLinkTest"
		and linked.world_document != null and not linked.object_controls().is_empty()
		and not linked.connection_controls().is_empty()) and ok
	if linked == null:
		return false

	linked.select_tool("warp")
	var warp_placed: bool = linked.paint_once(Vector2i(1, 1))
	var object_ui: Dictionary = linked.object_controls()
	(object_ui["id"] as LineEdit).text = "return_to_paint"
	(object_ui["detail_a"] as LineEdit).text = "StudioPaintTest"
	(object_ui["number_a"] as SpinBox).value = 1
	(object_ui["apply"] as Button).pressed.emit()
	linked.select_tool("npc")
	var npc_placed: bool = linked.paint_once(Vector2i(2, 1))
	object_ui = linked.object_controls()
	(object_ui["id"] as LineEdit).text = "link_guide"
	(object_ui["detail_a"] as LineEdit).text = "SPRITE_RED"
	(object_ui["detail_b"] as LineEdit).text = "STAY"
	(object_ui["detail_c"] as LineEdit).text = "DOWN"
	(object_ui["apply"] as Button).pressed.emit()
	linked.select_tool("sign")
	var sign_placed: bool = linked.paint_once(Vector2i(2, 2))
	object_ui = linked.object_controls()
	(object_ui["id"] as LineEdit).text = "link_notice"
	(object_ui["detail_a"] as LineEdit).text = "Connected in Studio"
	(object_ui["apply"] as Button).pressed.emit()
	linked.select_tool("trigger")
	var trigger_placed: bool = linked.paint_once(Vector2i(0, 2))
	object_ui = linked.object_controls()
	(object_ui["id"] as LineEdit).text = "link_region"
	(object_ui["number_a"] as SpinBox).value = 2
	(object_ui["number_b"] as SpinBox).value = 1
	(object_ui["apply"] as Button).pressed.emit()
	ok = _check("real placement tools and inspector edit warp, NPC, sign, and trigger",
		warp_placed and npc_placed and sign_placed and trigger_placed
		and linked.document.warps.size() == 1 and linked.document.objects.size() == 1
		and linked.document.signs.size() == 1 and linked.document.triggers.size() == 1
		and str(linked.document.warps[0].get("id", "")) == "return_to_paint"
		and int(linked.document.triggers[0].get("width", 0)) == 2,
		shell.status_text()) and ok

	# Exercise the destructive inspector control recoverably: delete, then undo the exact
	# unified map+world snapshot so the authored sign remains in the saved fixture.
	linked._selected_object_kind = "sign"
	linked._selected_object_id = "link_notice"
	linked._refresh_object_list()
	object_ui = linked.object_controls()
	(object_ui["delete"] as Button).pressed.emit()
	var deleted: bool = linked.document.signs.is_empty()
	linked.undo()
	ok = _check("object Delete participates in the same exact undo stack",
		deleted and linked.document.signs.size() == 1
		and str(linked.document.signs[0].get("id", "")) == "link_notice") and ok

	var connection_ui: Dictionary = linked.connection_controls()
	_select_metadata(connection_ui["direction"], "west")
	_select_text(connection_ui["map"], "StudioPaintTest")
	(connection_ui["offset"] as SpinBox).value = 0
	(connection_ui["apply"] as Button).pressed.emit()
	var connected: bool = linked.world_document.connections("StudioLinkTest").size() == 1 \
		and linked.world_document.connections("StudioPaintTest").size() == 1
	linked.undo()
	var connection_undo: bool = linked.world_document.connections("StudioLinkTest").is_empty() \
		and linked.world_document.connections("StudioPaintTest").is_empty()
	linked.redo()
	ok = _check("world inspector creates one reciprocal link with unified undo/redo",
		connected and connection_undo
		and linked.world_document.connections("StudioLinkTest").size() == 1
		and linked.world_document.connections("StudioPaintTest").size() == 1,
		shell.status_text()) and ok
	linked.save_control().pressed.emit()

	var paint = shell.edit_map("StudioPaintTest")
	ok = _check("first authored map reopens against the saved reciprocal graph", paint != null
		and paint.world_document.connections("StudioPaintTest").size() == 1) and ok
	if paint == null:
		return false
	paint.select_tool("warp")
	var entry_placed: bool = paint.paint_once(Vector2i(3, 0))
	object_ui = paint.object_controls()
	(object_ui["id"] as LineEdit).text = "enter_link_map"
	(object_ui["detail_a"] as LineEdit).text = "StudioLinkTest"
	(object_ui["number_a"] as SpinBox).value = 1
	(object_ui["apply"] as Button).pressed.emit()
	paint.save_control().pressed.emit()

	var first_open := MapDocument.open(scratch, "StudioPaintTest")
	var second_open := MapDocument.open(scratch, "StudioLinkTest")
	var world_open := preload("res://core/WorldDocument.gd").open(scratch)
	var report: Dictionary = ProjectValidator.validate_project(scratch)
	ok = _check("typed TMX objects and world graph save/reopen without drift",
		entry_placed and bool(first_open.get("ok", false)) and bool(second_open.get("ok", false))
		and bool(world_open.get("ok", false)) and bool(report.get("ok", false))
		and (first_open.get("document") as MapDocument).warps.size() == 1
		and (second_open.get("document") as MapDocument).warps.size() == 1
		and (second_open.get("document") as MapDocument).objects.size() == 1
		and (second_open.get("document") as MapDocument).signs.size() == 1
		and (second_open.get("document") as MapDocument).triggers.size() == 1,
		"; ".join(PackedStringArray(report.get("errors", [])))) and ok

	var child = shell.launch_playtest(true, true, "StudioPaintTest", [], {
		"warp_cell": Vector2i(3, 0), "edge_cell": Vector2i(0, 2), "edge_direction": "left"})
	if child == null:
		return _check("two-map traversal child launches", false, shell.status_text()) and ok
	var ack: Dictionary = await child.wait_for_handshake(shell.get_tree(), 25000)
	var exited: bool = await child.wait_for_exit(shell.get_tree(), 5000)
	var traversed: Array = ack.get("traversed_maps", [])
	ok = _check("child Engine traverses authored warp and reciprocal seamless edge",
		bool(ack.get("ok", false)) and bool(ack.get("traverse_ok", false)) and exited
		and traversed == ["StudioPaintTest", "StudioLinkTest", "StudioPaintTest"],
		str(ack.get("traverse_error", ack.get("error", ""))) + " maps=" + str(traversed)) and ok
	child.cleanup_handshake()
	print("[studioworld] %s" % ("ALL GREEN" if ok else "FAIL"))
	return ok


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
	print("[studioworld] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
