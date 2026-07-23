extends RefCounted
class_name StudioTheme
## Shared Studio visual system. The supplied reference boards are pinned in
## docs/v2/studio-visual-direction.md; screens consume this one theme rather than
## growing unrelated local colour/style constants.

const WINDOW := Color(0.055, 0.071, 0.094, 1.0)
const SURFACE := Color(0.086, 0.102, 0.133, 1.0)
const SURFACE_RAISED := Color(0.115, 0.133, 0.169, 1.0)
const SURFACE_HOVER := Color(0.145, 0.166, 0.205, 1.0)
const BORDER := Color(0.25, 0.285, 0.34, 0.9)
const TEXT := Color(0.90, 0.92, 0.95, 1.0)
const MUTED := Color(0.61, 0.65, 0.71, 1.0)
const MINT := Color(0.31, 0.91, 0.58, 1.0)
const CYAN := Color(0.12, 0.77, 0.93, 1.0)
const MAGENTA := Color(0.86, 0.29, 0.94, 1.0)
const DANGER := Color(0.95, 0.34, 0.31, 1.0)

const FONT_TITLE := 17
const FONT_SECTION := 13


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", MINT)
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.25))
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_color("font_outline_color", "ItemList", Color.TRANSPARENT)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("separation", "VBoxContainer", 8)
	theme.set_constant("h_separation", "GridContainer", 8)
	theme.set_constant("v_separation", "GridContainer", 8)
	theme.set_constant("outline_size", "Label", 0)

	theme.set_stylebox("panel", "Panel", _box(SURFACE, 12, 1, BORDER, 10))
	theme.set_stylebox("panel", "PanelContainer", _box(SURFACE, 12, 1, BORDER, 10))
	theme.set_stylebox("normal", "Button", _box(SURFACE_RAISED, 8, 1, BORDER, 8))
	theme.set_stylebox("hover", "Button", _box(SURFACE_HOVER, 8, 1, CYAN, 8))
	theme.set_stylebox("pressed", "Button", _box(SURFACE, 8, 2, MINT, 8))
	theme.set_stylebox("focus", "Button", _outline(CYAN, 8, 2))
	theme.set_stylebox("disabled", "Button", _box(SURFACE, 8, 1, BORDER.darkened(0.25), 8))
	theme.set_stylebox("panel", "ItemList", _box(SURFACE, 10, 1, BORDER, 6))
	theme.set_stylebox("selected", "ItemList", _box(SURFACE_HOVER, 7, 2, MINT, 5))
	theme.set_stylebox("selected_focus", "ItemList", _box(SURFACE_HOVER, 7, 2, CYAN, 5))
	theme.set_stylebox("hovered", "ItemList", _box(SURFACE_RAISED, 7, 1, BORDER, 5))
	theme.set_stylebox("normal", "LineEdit", _box(SURFACE, 7, 1, BORDER, 7))
	theme.set_stylebox("focus", "LineEdit", _box(SURFACE, 7, 2, CYAN, 7))
	theme.set_stylebox("normal", "OptionButton", _box(SURFACE_RAISED, 8, 1, BORDER, 8))
	theme.set_stylebox("hover", "OptionButton", _box(SURFACE_HOVER, 8, 1, CYAN, 8))
	theme.set_stylebox("focus", "OptionButton", _outline(CYAN, 8, 2))
	theme.set_stylebox("grabber_area", "HSplitContainer", _box(WINDOW, 0, 0, BORDER, 0))
	theme.set_constant("separation", "HSplitContainer", 8)
	theme.set_constant("minimum_grab_thickness", "HSplitContainer", 8)
	# gh #61: the form-engine control family — same surfaces/borders, explicit focus.
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_stylebox("focus", "CheckBox", _outline(CYAN, 6, 2))
	theme.set_color("font_color", "TextEdit", TEXT)
	theme.set_color("caret_color", "TextEdit", MINT)
	theme.set_stylebox("normal", "TextEdit", _box(SURFACE, 7, 1, BORDER, 7))
	theme.set_stylebox("focus", "TextEdit", _box(SURFACE, 7, 2, CYAN, 7))
	theme.set_stylebox("normal", "SpinBox", _box(SURFACE, 7, 1, BORDER, 7))
	theme.set_stylebox("focus", "SpinBox", _box(SURFACE, 7, 2, CYAN, 7))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_stylebox("panel", "PopupMenu", _box(SURFACE_RAISED, 8, 1, BORDER, 8))
	theme.set_stylebox("hover", "PopupMenu", _box(SURFACE_HOVER, 6, 1, CYAN, 6))
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, _box(SURFACE, 6, 0, BORDER, 2))
		theme.set_stylebox("grabber", bar, _box(SURFACE_HOVER, 6, 0, BORDER, 2))
		theme.set_stylebox("grabber_highlight", bar, _box(SURFACE_HOVER.lightened(0.12), 6, 0, BORDER, 2))
		theme.set_stylebox("grabber_pressed", bar, _box(SURFACE_HOVER, 6, 1, CYAN, 2))
	theme.set_stylebox("panel", "TooltipPanel", _box(SURFACE_RAISED, 6, 1, BORDER, 6))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	return theme


## Card behind one form section (gh #61). A consumer-level override so generated
## section containers and the theme's plain panels can differ without a type fork.
static func card() -> StyleBoxFlat:
	return _box(SURFACE, 10, 1, BORDER, 12)


## Danger-bordered input stylebox a form applies to the invalid field's control
## (gh #61) — the error text explains, the border locates.
static func error_box() -> StyleBoxFlat:
	return _box(SURFACE, 7, 2, DANGER, 7)


static func _box(color: Color, radius: int, border_width: int,
		border_color: Color, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_top = padding
	box.content_margin_right = padding
	box.content_margin_bottom = padding
	return box


static func _outline(color: Color, radius: int, width: int) -> StyleBoxFlat:
	return _box(Color.TRANSPARENT, radius, width, color, 0)
