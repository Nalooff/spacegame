extends Node
## Big ships are heavy: slow to accelerate and slow to turn (small ones are unchanged).
##   godot --headless --path . res://tests/test_weight.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ship(path: String) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob(path)
	add_child(s)
	return s


func _ready() -> void:
	var dart := _ship("res://ships/Dart.json")
	var dread := _ship("res://ships/Dreadnought.ship")
	for i in 20: await get_tree().physics_frame
	check(absf(dart.gyro.alpha_max - 2.0) < 0.5 and dart.gyro.omega_cap > 1.1, "a small ship turns as before (%.2f rad/s2, up to %.2f rad/s)" % [dart.gyro.alpha_max, dart.gyro.omega_cap])
	check(dread.gyro.alpha_max < 0.01, "the Dreadnought's turning acceleration is tiny (%.4f rad/s2)" % dread.gyro.alpha_max)
	check(dread.gyro.omega_cap < 0.08, "...and so is its fastest turn (%.3f rad/s)" % dread.gyro.omega_cap)
	var a_fwd := dread.alloc.f_best / dread.mass
	check(a_fwd < 1.0 and a_fwd > 0.1, "it accelerates at well under 1 m/s2 (%.2f)" % a_fwd)
	var a_dart := dart.alloc.f_best / dart.mass
	check(a_fwd < a_dart * 0.3, "...much more slowly than a fighter (%.2f vs %.2f m/s2)" % [a_fwd, a_dart])
	# a full-stick yaw for 10 s hardly gets it turning
	dread.flight_assist = true
	dread.set_physics_process(false)         # the ship does not run its own (idle) controller: the test is the pilot
	var w := 0.0
	for i in 600:
		var r: Array = dread._manual_command({"move": Vector3.ZERO, "rot": Vector3(0, 1, 0), "active": true})
		dread.apply_torque(dread.global_transform.basis * dread.gyro.clamp_torque(r[2]))
		await get_tree().physics_frame
		w = absf(dread.angular_velocity.y)
	check(w > 0.005 and w < 0.047, "after 10 s of full yaw it turns at %.4f rad/s (cap %.3f): you feel the weight" % [w, dread.gyro.omega_cap])
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
