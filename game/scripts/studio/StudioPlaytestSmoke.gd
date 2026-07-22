extends RefCounted
class_name StudioPlaytestSmoke
## The gh #51 leg of --studiotest: separate-process launch, ready handshake, and a stable
## save slot derived from the opened project rather than shared with another project.


const Playtest := preload("res://scripts/studio/StudioPlaytest.gd")


func run(shell, scratch: String) -> bool:
	var ok := true
	var button: Button = shell.playtest_control() if shell.has_method("playtest_control") else null
	ok = _check("live play-test button is enabled for an open project",
		button != null and not button.disabled) and ok
	var slot := Playtest.save_slot_for(scratch)
	ok = _check("play-test save slot is stable and isolated per project path",
		slot == Playtest.save_slot_for(scratch)
		and slot != Playtest.save_slot_for(scratch + "_other")) and ok
	var dirty_form = shell.edit_record("items", "potion")
	var dirty_price: SpinBox = dirty_form.field_control("/price")
	dirty_price.value += 1
	dirty_price.value_changed.emit(dirty_price.value)
	var refused_dirty = shell.launch_playtest(true, true)
	ok = _check("play-test refuses an unsaved active record",
		dirty_form.is_dirty() and refused_dirty == null) and ok
	dirty_form.revert_record()
	var child = shell.launch_playtest(true, true)
	if child == null:
		return _check("play-test child launches", false) and ok
	var ack: Dictionary = await child.wait_for_handshake(shell.get_tree(), 20000)
	var exited: bool = await child.wait_for_exit(shell.get_tree(), 5000)
	ok = _check("separate Engine child loads the project and handshakes",
		bool(ack.get("ok", false)) and int(ack.get("pid", -1)) == child.pid
		and child.pid != OS.get_process_id()
		and str(ack.get("project_dir", "")) == child.project_dir
		and str(ack.get("project_id", "")) == "kanto"
		and not bool(ack.get("automated", true)), str(ack.get("error", ""))) and ok
	ok = _check("child reports the isolated save path and probe exits cleanly",
		str(ack.get("save_slot", "")) == slot
		and str(ack.get("save_path", "")) == Playtest.save_path_for(scratch)
		and exited) and ok
	child.cleanup_handshake()
	return ok


func _check(name: String, good: bool, detail := "") -> bool:
	print("[studiotest] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good
