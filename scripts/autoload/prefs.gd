extends Node
## Autoload "Prefs": the player's settings (controls, camera, video, audio), saved to user://settings.cfg.
## Everything applies at once (apply_all) and is read by the camera, the flight controls and the HUD.

signal changed

const FILE := "user://settings.cfg"

## Actions the player can rebind in the settings screen: [action, label]
const REBINDABLE: Array = [
	["thrust_fwd", "Thrust forward"], ["thrust_back", "Thrust back"], ["thrust_left", "Strafe left"], ["thrust_right", "Strafe right"],
	["thrust_up", "Thrust up"], ["thrust_down", "Thrust down"],
	["pitch_up", "Pitch up"], ["pitch_down", "Pitch down"], ["yaw_left", "Yaw left"], ["yaw_right", "Yaw right"],
	["roll_left", "Roll left"], ["roll_right", "Roll right"],
	["brake", "Brake"], ["hold_attitude", "Flight assist"], ["lock_target", "Lock next enemy"], ["target_module", "Aim at next module of the target"], ["toggle_crew", "Crew panel"], ["toggle_control_mode", "Commander / crew mode"],
	["next_station", "Next station"], ["toggle_plan", "Exploded 3D plan"], ["scoreboard", "Scoreboard (hold)"],
	["move_gizmo", "Move circle (point and click)"], ["order_approach", "Approach target"], ["order_orbit", "Orbit target"],
	["order_keep_range", "Keep target at range"], ["range_less", "Orbit / range smaller"], ["range_more", "Orbit / range bigger"],
]

## Languages: [locale code, name written in that language]. Texts live in res://translations/<code>.json
## ({"English text": "translation"}); anything missing falls back to the English text.
const LANGUAGES: Array = [["en", "English"], ["fr", "Français"], ["de", "Deutsch"], ["es", "Español"], ["ru", "Русский"],
	["zh_CN", "简体中文"], ["ja", "日本語"]]

var language: String = ""            ## "" = follow the operating system (English when it is not supported)
var scheme: int = 0                  ## FlightControls.Scheme
var mouse_sens: float = 1.0          ## mouse stick: how far the cursor has to be from the centre for full turn (higher = more turn)
var invert_y: bool = false           ## mouse stick: pull down to pitch up
var deadzone: float = 0.08           ## mouse stick / gamepad dead zone (fraction)
var lever_rate: float = 0.5          ## throttle lever: change per second while W / S is held
var order_range: float = 150.0       ## EVE orders: orbit radius / keep-at-range distance (m)
var fov: float = 70.0
var cam_dist: float = 40.0           ## starting distance of the chase camera
var cam_sens: float = 1.0            ## camera orbit speed (right mouse drag)
var cam_invert_y: bool = false
var master_volume: float = 1.0
var fullscreen: bool = false
var vsync: bool = true
var render_scale: float = 1.0
var auto_scale: bool = true          ## lowers the 3D resolution by itself while the game runs under 40 FPS, and gives it back when it is fast again
var max_fps: int = 0                 ## 0 = unlimited
var show_fps: bool = false
var ui_scale: float = 1.0
var player_name: String = "Pilot"
var hints_on: bool = true            ## the contextual hint bar
var hints_done: String = ""         ## comma separated ids of the hints the player has already followed
var binds: Dictionary = {}           ## action -> physical keycode (only what the player changed)

var _fps_label: Label
var _dyn: float = 1.0                ## the automatic part of the 3D scale (0.6 .. 1)
var _dyn_t: float = 0.0
var _dyn_n: int = 0
var _defaults_binds: Dictionary = {}


func _ready() -> void:
	_load_translations()
	for e in REBINDABLE:
		var evs := InputMap.action_get_events(e[0])
		for ev in evs:
			if ev is InputEventKey:
				_defaults_binds[e[0]] = (ev as InputEventKey).physical_keycode
				break
	load_file()
	apply_all()


func values() -> Dictionary:
	return {"language": language, "scheme": scheme, "mouse_sens": mouse_sens, "invert_y": invert_y, "deadzone": deadzone, "lever_rate": lever_rate,
		"order_range": order_range, "fov": fov, "cam_dist": cam_dist, "cam_sens": cam_sens, "cam_invert_y": cam_invert_y,
		"master_volume": master_volume, "fullscreen": fullscreen, "vsync": vsync, "render_scale": render_scale, "auto_scale": auto_scale, "max_fps": max_fps,
		"show_fps": show_fps, "ui_scale": ui_scale, "player_name": player_name, "hints_on": hints_on, "hints_done": hints_done}


func set_values(d: Dictionary) -> void:
	for k in d:
		if k in values():
			set(k, d[k])
	sanitize()


## Clamp everything to sane ranges (a hand-edited or old file must not break the game).
func sanitize() -> void:
	if language != "" and not language_supported(language):
		language = ""
	scheme = clampi(scheme, 0, 4)
	mouse_sens = clampf(mouse_sens, 0.2, 4.0)
	deadzone = clampf(deadzone, 0.0, 0.5)
	lever_rate = clampf(lever_rate, 0.1, 2.0)
	order_range = clampf(order_range, 10.0, 5000.0)
	fov = clampf(fov, 40.0, 120.0)
	cam_dist = clampf(cam_dist, 10.0, 300.0)
	cam_sens = clampf(cam_sens, 0.2, 4.0)
	master_volume = clampf(master_volume, 0.0, 1.0)
	render_scale = clampf(render_scale, 0.5, 1.0)
	max_fps = clampi(max_fps, 0, 500)
	ui_scale = clampf(ui_scale, 0.75, 2.0)
	player_name = player_name.strip_edges().left(20)
	if player_name == "":
		player_name = "Pilot"


func save_file() -> void:
	var cf := ConfigFile.new()
	var v := values()
	for k in v:
		cf.set_value("settings", k, v[k])
	for a in binds:
		cf.set_value("keys", a, binds[a])
	cf.save(FILE)


func load_file(path: String = FILE) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	var d := {}
	for k in values():
		if cf.has_section_key("settings", k):
			d[k] = cf.get_value("settings", k)
	set_values(d)
	binds.clear()
	if cf.has_section("keys"):
		for a in cf.get_section_keys("keys"):
			binds[a] = int(cf.get_value("keys", a))


func reset_defaults() -> void:
	set_values({"language": "", "scheme": 0, "mouse_sens": 1.0, "invert_y": false, "deadzone": 0.08, "lever_rate": 0.5, "order_range": 150.0, "fov": 70.0,
		"cam_dist": 40.0, "cam_sens": 1.0, "cam_invert_y": false, "master_volume": 1.0, "fullscreen": false, "vsync": true,
		"render_scale": 1.0, "auto_scale": true, "max_fps": 0, "show_fps": false, "ui_scale": 1.0})
	binds.clear()
	apply_all()


## Rebind `action` to a physical key (replaces its keyboard events, keeps mouse / pad events).
func rebind(action: String, keycode: int) -> void:
	binds[action] = keycode
	_apply_bind(action, keycode)
	changed.emit()


func default_key(action: String) -> int:
	return int(_defaults_binds.get(action, 0))


func key_of(action: String) -> int:
	return int(binds.get(action, default_key(action)))


func _apply_bind(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var k := InputEventKey.new()
	k.physical_keycode = keycode as Key
	InputMap.action_add_event(action, k)


func apply_all() -> void:
	sanitize()
	for a in _defaults_binds:
		_apply_bind(a, key_of(a))
	Data.player_name = player_name
	TranslationServer.set_locale(effective_language())
	var root := get_tree().root
	root.content_scale_factor = ui_scale
	root.scaling_3d_scale = render_scale * _dyn
	Engine.max_fps = max_fps
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	_update_fps_label()
	changed.emit()


static func language_supported(code: String) -> bool:
	for l in LANGUAGES:
		if l[0] == code:
			return true
	return false


## The language in use: the chosen one, else the operating system's when we have it, else English.
func effective_language() -> String:
	if language != "":
		return language
	var os_loc := OS.get_locale()                         # e.g. "fr_FR", "zh_CN", "ja"
	if language_supported(os_loc):
		return os_loc
	var base := OS.get_locale_language()
	if base == "zh":
		return "zh_CN"
	return base if language_supported(base) else "en"


## Reads res://translations/<code>.json for every language but English (English is the text in the code and the scenes).
func _load_translations() -> void:
	for l in LANGUAGES:
		var code: String = l[0]
		if code == "en":
			continue
		var f := FileAccess.open("res://translations/%s.json" % code, FileAccess.READ)
		if f == null:
			continue
		var data: Variant = JSON.parse_string(f.get_as_text())
		if typeof(data) != TYPE_DICTIONARY:
			push_warning("translations/%s.json is not a JSON object" % code)
			continue
		var tr_res := Translation.new()
		tr_res.locale = code
		for k in data:
			tr_res.add_message(k, str(data[k]))
		TranslationServer.add_translation(tr_res)


func _update_fps_label() -> void:
	if show_fps and _fps_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 100
		_fps_label = Label.new()
		_fps_label.position = Vector2(8, 4)
		_fps_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
		_fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
		layer.add_child(_fps_label)
		add_child(layer)
	if _fps_label != null:
		_fps_label.get_parent().visible = show_fps


func _process(dt: float) -> void:
	_auto_scale_step(dt)
	if _fps_label != null and show_fps:
		_fps_label.text = tr("%d FPS") % Engine.get_frames_per_second()


## Dynamic resolution: the cheapest way to keep a crowded fight smooth. Looks at the average frame time twice a second.
func _auto_scale_step(dt: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not auto_scale:
		if _dyn != 1.0:
			_dyn = 1.0
			get_tree().root.scaling_3d_scale = render_scale
		return
	_dyn_t += dt
	_dyn_n += 1
	if _dyn_t < 0.5:
		return
	var avg := _dyn_t / float(_dyn_n)
	_dyn_t = 0.0
	_dyn_n = 0
	var want := _dyn
	if avg > 1.0 / 40.0:
		want = maxf(_dyn - 0.05, 0.6)
	elif avg < 1.0 / 58.0 and (max_fps == 0 or max_fps > 70):
		want = minf(_dyn + 0.025, 1.0)
	if want != _dyn:
		_dyn = want
		get_tree().root.scaling_3d_scale = clampf(render_scale * _dyn, 0.3, 1.0)
