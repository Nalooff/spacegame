class_name SettingsScreen
extends Control
## Settings: controls (movement scheme, sensitivity, key binding), camera, video, audio, player. Built in code (many rows)
## and bound to the Prefs autoload; every change applies and is saved at once.
## As a scene of its own (main menu) "Back" returns to the menu; as an overlay inside the HUD it just hides itself.

signal closed

var _tabs: TabContainer
var _scheme_help: Label
var _bind_buttons: Dictionary = {}     # action -> Button
var _waiting_action: String = ""
var _building: bool = true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var title := Label.new()
	title.text = tr("SETTINGS")
	title.add_theme_font_size_override("font_size", 32)
	col.add_child(title)
	_tabs = TabContainer.new()
	_tabs.name = "SettingsTabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_tabs)
	_build_controls()
	_build_camera()
	_build_video()
	_build_audio()
	_build_player()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var reset := Button.new()
	reset.text = tr("Reset everything to default")
	reset.pressed.connect(_on_reset)
	row.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var back := Button.new()
	back.name = "BackButton"
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(180, 44)
	back.pressed.connect(_on_back)
	row.add_child(back)
	_building = false


func _page(name_: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name_
	scroll.set_meta("title", tr(name_))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	_tabs.add_child(scroll)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, tr(name_))
	return box


func _row(parent: Control, text: String, tip: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = tr(text)
	l.custom_minimum_size = Vector2(300, 0)
	l.tooltip_text = tr(tip)
	h.add_child(l)
	parent.add_child(h)
	return h


func _slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float, unit: String = "", tip: String = "") -> HSlider:
	var h := _row(parent, text, tip)
	var s := HSlider.new()
	s.name = "Slider_" + key
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Prefs.get(key))
	s.custom_minimum_size = Vector2(320, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(90, 0)
	h.add_child(v)
	var fmt := func(x: float): v.text = ("%.2f" % x if step < 0.1 else "%.0f" % x) + unit
	fmt.call(s.value)
	s.value_changed.connect(func(x: float):
		fmt.call(x)
		_apply(key, x))
	return s


func _check(parent: Control, text: String, key: String, tip: String = "") -> CheckBox:
	var c := CheckBox.new()
	c.name = "Check_" + key
	c.text = tr(text)
	c.tooltip_text = tr(tip)
	c.button_pressed = bool(Prefs.get(key))
	c.toggled.connect(func(on: bool): _apply(key, on))
	parent.add_child(c)
	return c


func _apply(key: String, value: Variant) -> void:
	if _building:
		return
	Prefs.set(key, value)
	Prefs.apply_all()
	Prefs.save_file()


# ------------------------------------------------------------------ pages
func _build_controls() -> void:
	var p := _page("Controls")
	var h := _row(p, "Movement scheme", "How you fly the ship")
	var opt := OptionButton.new()
	opt.name = "SchemePicker"
	for n in FlightControls.NAMES:
		opt.add_item(tr(n))
	opt.select(Prefs.scheme)
	opt.custom_minimum_size = Vector2(380, 0)
	h.add_child(opt)
	_scheme_help = Label.new()
	_scheme_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scheme_help.modulate = Color(1, 1, 1, 0.75)
	_scheme_help.text = tr(FlightControls.HELP[Prefs.scheme])
	p.add_child(_scheme_help)
	opt.item_selected.connect(func(i: int):
		_apply("scheme", i)
		_scheme_help.text = tr(FlightControls.HELP[i]))
	_slider(p, "Mouse steering strength", "mouse_sens", 0.2, 4.0, 0.05, "", "Mouse flight: how quickly the turn grows when you move the cursor away from the centre")
	_slider(p, "Dead zone", "deadzone", 0.0, 0.5, 0.01, "", "Mouse flight and gamepad: no turning inside this circle")
	_check(p, "Invert mouse pitch (cursor up = nose down)", "invert_y")
	_slider(p, "Throttle lever speed", "lever_rate", 0.1, 2.0, 0.05, "/s", "Lever scheme: how fast W / S move the lever")
	_slider(p, "Orbit / keep-at-range distance", "order_range", 10.0, 2000.0, 10.0, " m", "Click-order scheme: used by O (orbit) and K (keep at range)")
	var sep := HSeparator.new()
	p.add_child(sep)
	var t := Label.new()
	t.text = tr("KEY BINDINGS  (click a key, then press the new one; Esc cancels)")
	p.add_child(t)
	for e in Prefs.REBINDABLE:
		var r := _row(p, e[1])
		var b := Button.new()
		b.name = "Bind_" + e[0]
		b.custom_minimum_size = Vector2(200, 0)
		b.text = OS.get_keycode_string(Prefs.key_of(e[0]) as Key)
		var action: String = e[0]
		b.pressed.connect(func():
			_waiting_action = action
			b.text = tr("press a key..."))
		r.add_child(b)
		_bind_buttons[action] = b


func _build_camera() -> void:
	var p := _page("Camera")
	_slider(p, "Field of view", "fov", 40.0, 120.0, 1.0, "°")
	_slider(p, "Camera distance at start", "cam_dist", 10.0, 300.0, 5.0, " m", "Mouse wheel changes it in flight")
	_slider(p, "Camera orbit speed", "cam_sens", 0.2, 4.0, 0.05, "", "Right mouse drag")
	_check(p, "Invert camera vertical", "cam_invert_y")


func _build_video() -> void:
	var p := _page("Video")
	_check(p, "Fullscreen", "fullscreen")
	_check(p, "V-Sync", "vsync")
	_slider(p, "3D render scale", "render_scale", 0.5, 1.0, 0.05, "", "Lower = faster on weak graphics cards")
	_slider(p, "Maximum frames per second (0 = unlimited)", "max_fps", 0.0, 240.0, 10.0)
	_slider(p, "Interface scale", "ui_scale", 0.75, 2.0, 0.05)
	_check(p, "Show FPS counter", "show_fps")


func _build_audio() -> void:
	var p := _page("Audio")
	_slider(p, "Master volume", "master_volume", 0.0, 1.0, 0.05)


func _build_player() -> void:
	var p := _page("Player")
	var hl := _row(p, "Language", "")
	var lang := OptionButton.new()
	lang.name = "LanguagePicker"
	lang.custom_minimum_size = Vector2(300, 0)
	lang.add_item(tr("Automatic (system language)"))
	var sel := 0
	for i in Prefs.LANGUAGES.size():
		lang.add_item(Prefs.LANGUAGES[i][1])
		if Prefs.LANGUAGES[i][0] == Prefs.language:
			sel = i + 1
	lang.select(sel)
	lang.item_selected.connect(func(i: int):
		_apply("language", "" if i == 0 else Prefs.LANGUAGES[i - 1][0])
		_on_language_changed())
	hl.add_child(lang)
	var h := _row(p, "Pilot name", "Shown to other players and on the scoreboard")
	var e := LineEdit.new()
	e.name = "NameEdit"
	e.max_length = 20
	e.text = Prefs.player_name
	e.custom_minimum_size = Vector2(300, 0)
	e.text_changed.connect(func(t: String):
		if t.strip_edges() != "":
			_apply("player_name", t.strip_edges()))
	h.add_child(e)


# ------------------------------------------------------------------ events
func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var action := _waiting_action
	_waiting_action = ""
	get_viewport().set_input_as_handled()
	if k.physical_keycode != KEY_ESCAPE:
		Prefs.rebind(action, k.physical_keycode)
		Prefs.save_file()
	(_bind_buttons[action] as Button).text = OS.get_keycode_string(Prefs.key_of(action) as Key)


func _on_language_changed() -> void:
	_rebuild.call_deferred()


## Build the screen again (new language, or defaults restored).
func _rebuild() -> void:
	var page := _tabs.current_tab if _tabs != null else 0
	for c in get_children():
		c.queue_free()
	_bind_buttons.clear()
	_building = true
	_ready()
	_tabs.current_tab = clampi(page, 0, _tabs.get_tab_count() - 1)


func _on_reset() -> void:
	Prefs.reset_defaults()
	Prefs.save_file()
	_rebuild.call_deferred()


func _on_back() -> void:
	Prefs.save_file()
	if get_tree().current_scene == self:
		Game.go_to(Game.MENU_SCENE)
	else:
		visible = false
		closed.emit()
