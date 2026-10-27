class_name BuilderTheme
extends RefCounted
## The look of the ship builder (dark, flat, one amber accent). Built in code once and given to the BuilderUI root, so every
## button / panel / menu inside inherits it. Change colours here.

const PANEL := Color(0.075, 0.09, 0.115, 0.94)
const PANEL_EDGE := Color(0.2, 0.25, 0.33, 1.0)
const BUTTON := Color(0.13, 0.155, 0.2, 1.0)
const BUTTON_HOVER := Color(0.19, 0.23, 0.3, 1.0)
const BUTTON_ON := Color(0.28, 0.22, 0.08, 1.0)
const ACCENT := Color(1.0, 0.77, 0.28, 1.0)
const TEXT := Color(0.88, 0.92, 0.98, 1.0)
const TEXT_DIM := Color(0.88, 0.92, 0.98, 0.45)


static func _box(col: Color, edge: Color = Color(0, 0, 0, 0), border: int = 0, radius: int = 5, pad: Vector2 = Vector2(8, 5)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = edge
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	return sb


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	# panels and popup menus
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, PANEL_EDGE, 1, 8, Vector2(2, 2)))
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.09, 0.105, 0.135, 0.98), PANEL_EDGE, 1, 6, Vector2(4, 4)))
	t.set_stylebox("hover", "PopupMenu", _box(BUTTON_HOVER, Color(0, 0, 0, 0), 0, 4, Vector2(6, 3)))
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_constant("icon_max_width", "PopupMenu", 22)
	# buttons (also used by menu buttons / option buttons)
	for cls in ["Button", "MenuButton", "OptionButton"]:
		t.set_stylebox("normal", cls, _box(BUTTON, Color(0.2, 0.25, 0.33, 0.6), 1))
		t.set_stylebox("hover", cls, _box(BUTTON_HOVER, ACCENT * Color(1, 1, 1, 0.5), 1))
		t.set_stylebox("pressed", cls, _box(BUTTON_ON, ACCENT, 1))
		t.set_stylebox("hover_pressed", cls, _box(BUTTON_ON, ACCENT, 1))
		t.set_stylebox("disabled", cls, _box(Color(BUTTON, 0.45), Color(0, 0, 0, 0), 0))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, ACCENT)
		t.set_color("font_disabled_color", cls, TEXT_DIM)
		t.set_color("icon_normal_color", cls, Color.WHITE)
		t.set_color("icon_disabled_color", cls, Color(1, 1, 1, 0.3))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.05, 0.06, 0.08, 1), PANEL_EDGE, 1))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.05, 0.06, 0.08, 1), ACCENT, 1))
	t.set_stylebox("panel", "TabContainer", _box(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0), 0, 0, Vector2(4, 6)))
	t.set_stylebox("tab_selected", "TabContainer", _box(BUTTON_ON, ACCENT, 1, 5, Vector2(12, 5)))
	t.set_stylebox("tab_unselected", "TabContainer", _box(BUTTON, PANEL_EDGE, 1, 5, Vector2(12, 5)))
	t.set_stylebox("tab_hovered", "TabContainer", _box(BUTTON_HOVER, PANEL_EDGE, 1, 5, Vector2(12, 5)))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", TEXT)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("h_separation", "GridContainer", 5)
	t.set_constant("v_separation", "GridContainer", 5)
	return t


## A small section title (amber, spaced capitals).
static func heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ACCENT * Color(1, 1, 1, 0.85))
	l.add_theme_font_size_override("font_size", 11)
	return l
