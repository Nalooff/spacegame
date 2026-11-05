extends Node
## Movement schemes, order controls, settings: godot --headless --path . res://tests/test_controls.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _raw(over := {}) -> Dictionary:
	var r := {"strafe": 0.0, "vertical": 0.0, "fwd": 0.0, "pitch": 0.0, "yaw": 0.0, "roll": 0.0, "cut": false, "stick": Vector2.ZERO}
	r.merge(over, true)
	return r


func _ready() -> void:
	var prefs := {"deadzone": 0.1, "mouse_sens": 1.0, "invert_y": false, "lever_rate": 0.5}
	var C := FlightControls
	# --- mouse stick
	check(C.stick_to_turn(Vector2(0.05, 0.05), 0.1, 1.0, false) == Vector2.ZERO, "stick: inside the dead zone nothing turns")
	var right := C.stick_to_turn(Vector2(0.6, 0), 0.1, 1.0, false)
	check(right.x < 0.0 and absf(right.y) < 1e-6, "stick: cursor right = yaw right (negative yaw-left)")
	var up := C.stick_to_turn(Vector2(0, -0.6), 0.1, 1.0, false)
	check(up.y > 0.0, "stick: cursor up = nose up")
	check(C.stick_to_turn(Vector2(0, -0.6), 0.1, 1.0, true).y < 0.0, "stick: invert flips pitch")
	check(C.stick_to_turn(Vector2(5, 0), 0.1, 1.0, false).length() <= 1.0001, "stick: far cursor is clamped to full turn")
	check(C.stick_to_turn(Vector2(0.4, 0), 0.1, 2.0, false).length() > C.stick_to_turn(Vector2(0.4, 0), 0.1, 0.5, false).length(), "stick: sensitivity")
	# --- schemes
	var fc := FlightControls.new()
	var r := fc.compute(C.Scheme.CLASSIC, _raw({"fwd": 1.0, "strafe": -1.0, "pitch": 0.5, "stick": Vector2(0.9, 0.9)}), 0.016, prefs)
	check(r["move"] == Vector3(-1, 0, -1) and r["rot"] == Vector3(0.5, 0, 0) and r["active"], "classic: keys only, the mouse is ignored")
	r = fc.compute(C.Scheme.MOUSE_FLIGHT, _raw({"stick": Vector2(0.7, 0.0)}), 0.016, prefs)
	check(r["rot"].y < 0.0 and r["active"], "mouse flight: cursor right yaws right")
	r = fc.compute(C.Scheme.MOUSE_FLIGHT, _raw(), 0.016, prefs)
	check(not r["active"], "mouse flight: centred cursor = no input")
	for i in 60:
		r = fc.compute(C.Scheme.MOUSE_LEVER, _raw({"fwd": 1.0}), 0.0167, prefs)
	check(absf(fc.lever - 0.5) < 0.03 and r["move"].z < 0.0, "lever: 1 s of W at 0.5/s = 0.5 (got %.2f)" % fc.lever)
	r = fc.compute(C.Scheme.MOUSE_LEVER, _raw(), 0.0167, prefs)
	check(absf(fc.lever - 0.5) < 0.03 and r["move"].z < 0.0 and r["active"], "lever: stays where it is left and keeps the ship under manual control")
	r = fc.compute(C.Scheme.MOUSE_LEVER, _raw({"cut": true}), 0.0167, prefs)
	check(fc.lever == 0.0 and not r["active"], "lever: X sets it to zero")
	fc.lever = 0.8
	r = fc.compute(C.Scheme.MOUSE_LEVER, _raw(), 0.0167, prefs, true)
	check(fc.lever == 0.0 and not r["active"], "lever: an autopilot order takes over")
	for i in 400:
		fc.compute(C.Scheme.MOUSE_LEVER, _raw({"fwd": -1.0}), 0.0167, prefs)
	check(fc.lever >= -0.3 - 1e-6, "lever: reverse is limited")
	fc.compute(C.Scheme.CLASSIC, _raw(), 0.016, prefs)
	check(fc.lever == 0.0, "lever resets in other schemes")
	# --- move circle maths
	var hit := OrderControls.plane_point(Vector3(0, 100, 0), Vector3(0, -1, 1).normalized(), 0.0)
	check(hit["ok"] and absf(hit["point"].y) < 1e-3 and absf(hit["point"].z - 100.0) < 0.01, "circle: ray meets the plane at the ship's height")
	check(not OrderControls.plane_point(Vector3(0, 100, 0), Vector3(0, 1, 1).normalized(), 0.0)["ok"], "circle: ray going away from the plane does not hit")
	check(not OrderControls.plane_point(Vector3(0, 100, 0), Vector3(1, 0, 0), 0.0)["ok"], "circle: parallel ray does not hit")
	check(OrderControls.adjust_height(0.0, -40.0, 100.0) > 0.0 and OrderControls.adjust_height(0.0, 40.0, 100.0) < 0.0, "circle: mouse up raises (ALT)")
	check(absf(OrderControls.adjust_height(0.0, -40.0, 400.0)) > absf(OrderControls.adjust_height(0.0, -40.0, 100.0)), "circle: farther camera = bigger steps")
	# --- clicking on a contact (EVE)
	var dummy := Node3D.new()
	add_child(dummy)
	var contacts := [{"ship": dummy, "est_pos": Vector3(0, 0, -100)}, {"ship": dummy, "est_pos": Vector3(50, 0, -100)}]
	var near := OrderControls.pick_contact(contacts, Vector3.ZERO, Vector3(0.02, 0, -1).normalized())
	check(near != null, "eve: a click near a contact picks it")
	check(OrderControls.pick_contact(contacts, Vector3.ZERO, Vector3(-1, 0, -0.2).normalized()) == null, "eve: a click in empty space picks nothing")
	# --- orbit steering
	var v := ShipAutopilot.orbit_velocity(Vector3(100, 0, 0), 100.0, 10.0)
	check(absf(v.dot(Vector3(1, 0, 0))) < 1e-3 and v.length() > 9.9, "orbit: on the circle the velocity is purely tangent (%s)" % str(v))
	check(ShipAutopilot.orbit_velocity(Vector3(200, 0, 0), 100.0, 10.0).x < 0.0, "orbit: too far = moves inwards")
	check(ShipAutopilot.orbit_velocity(Vector3(50, 0, 0), 100.0, 10.0).x > 0.0, "orbit: too close = moves outwards")
	check(ShipAutopilot.orbit_velocity(Vector3(0, 80, 0), 100.0, 10.0).length() > 1.0, "orbit: directly above works (no NaN)")
	check(ShipAutopilot.orbit_velocity(Vector3(100, 0, 0), 100.0, 10.0, -1.0).z * ShipAutopilot.orbit_velocity(Vector3(100, 0, 0), 100.0, 10.0, 1.0).z < 0.0, "orbit: direction flips")
	# --- settings store
	var tmp := "user://test_settings.cfg"
	var saved := Prefs.values()
	var saved_binds := Prefs.binds.duplicate()
	Prefs.set_values({"scheme": 99, "fov": 500.0, "mouse_sens": -3.0, "player_name": "   ", "order_range": 1.0})
	check(Prefs.scheme == 4 and Prefs.fov == 120.0 and Prefs.mouse_sens == 0.2 and Prefs.player_name == "Pilot" and Prefs.order_range == 10.0, "prefs: values are clamped")
	Prefs.set_values({"scheme": 3, "fov": 85.0, "invert_y": true, "player_name": "Ace"})
	Prefs.binds = {"move_gizmo": KEY_J}
	var cf := ConfigFile.new()
	for k in Prefs.values():
		cf.set_value("settings", k, Prefs.values()[k])
	cf.set_value("keys", "move_gizmo", KEY_J)
	cf.save(tmp)
	Prefs.set_values({"scheme": 0, "fov": 70.0, "invert_y": false})
	Prefs.binds.clear()
	Prefs.load_file(tmp)
	check(Prefs.scheme == 3 and Prefs.fov == 85.0 and Prefs.invert_y and Prefs.player_name == "Ace" and Prefs.binds.get("move_gizmo") == KEY_J, "prefs: file round trip")
	Prefs.apply_all()
	check(Prefs.key_of("move_gizmo") == KEY_J, "prefs: rebinding applies to the InputMap")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	check(InputMap.event_is_action(ev, "move_gizmo"), "prefs: the new key triggers the action")
	ev.physical_keycode = KEY_G
	check(not InputMap.event_is_action(ev, "move_gizmo"), "prefs: the old key no longer does")
	Prefs.reset_defaults()
	check(Prefs.scheme == 0 and Prefs.key_of("move_gizmo") == KEY_G, "prefs: reset restores defaults and keys")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	# --- settings screen
	var scr := (load("res://scenes/settings.tscn") as PackedScene).instantiate() as SettingsScreen
	add_child(scr)
	await get_tree().process_frame
	var picker := scr.find_child("SchemePicker", true, false) as OptionButton
	check(picker != null and picker.item_count == FlightControls.NAMES.size(), "settings: scheme picker lists every scheme")
	picker.select(4)
	picker.item_selected.emit(4)
	check(Prefs.scheme == 4, "settings: picking a scheme sets it")
	var sl := scr.find_child("Slider_fov", true, false) as HSlider
	sl.value = 95.0
	check(Prefs.fov == 95.0, "settings: slider changes the value")
	check(scr.find_child("Bind_order_orbit", true, false) != null, "settings: key binding rows exist")
	var chk := scr.find_child("Check_show_fps", true, false) as CheckBox
	chk.button_pressed = true
	check(Prefs.show_fps, "settings: checkbox")
	chk.button_pressed = false
	Prefs.set_values(saved)
	Prefs.binds = saved_binds
	Prefs.apply_all()
	Prefs.reset_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Prefs.FILE))
	print("RESULT: PASS" if fails == 0 else "RESULT: %d FAILED" % fails)
	get_tree().quit(0 if fails == 0 else 1)
