extends RefCounted
## User-editable key bindings. (Loaded via preload in Main; see `Keybinds` const there.) Reads `user://keybinds.cfg` and rebinds the game's input actions to
## the listed keys. On first launch the file is written with the defaults below, so it can be edited.
## Each value is a comma-separated list of Godot key names (e.g. "Z,Enter"); see
## OS.find_keycode_from_string for valid names (letters, digits, Up/Down/Left/Right, Enter, Escape,
## Space, Shift, Ctrl, Backspace, ...). Movement = arrows; A = confirm/interact; B = cancel / menu.

const PATH := "user://keybinds.cfg"

# config key -> the InputMap action it drives. Mirrors the Game Boy's eight inputs:
# the D-pad, A (confirm/interact), B (cancel/back), START (open the menu), SELECT (reorder items) —
# plus "turbo", a playtest helper: hold it to fast-forward the whole game.
const ACTIONS := {
	"up": "ui_up", "down": "ui_down", "left": "ui_left", "right": "ui_right",
	"a": "ui_accept", "b": "ui_cancel", "start": "p_start", "select": "p_select",
	"turbo": "p_turbo",
}
# config key -> default key name(s)
const DEFAULTS := {
	"up": "Up", "down": "Down", "left": "Left", "right": "Right",
	"a": "Z", "b": "X", "start": "Enter,Escape", "select": "Backspace",
	"turbo": "Space",
}


## Load the config (creating/migrating it with defaults) and apply it to the InputMap.
static func apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK or not cfg.has_section_key("controls", "start") \
			or not cfg.has_section_key("controls", "turbo"):
		cfg = ConfigFile.new()                    # missing or pre-START/SELECT config -> regenerate
		for k in DEFAULTS:
			cfg.set_value("controls", k, DEFAULTS[k])
		cfg.save(PATH)
		print("[keybinds] wrote default config: %s" % ProjectSettings.globalize_path(PATH))
	for k in ACTIONS:
		var action: String = ACTIONS[k]
		var spec := str(cfg.get_value("controls", k, DEFAULTS[k]))
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for name in spec.split(",", false):
			var key := OS.find_keycode_from_string(name.strip_edges())
			if key != KEY_NONE:
				var ev := InputEventKey.new()
				ev.keycode = key
				InputMap.action_add_event(action, ev)
	print("[keybinds] applied controls from %s" % ProjectSettings.globalize_path(PATH))
