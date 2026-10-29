extends SceneTree
## DRIVE as a DIRECTION (arrow), chasing with an intercept point, and GO TO a moving ship.
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_heading.gd
var ship: Ship
var other: Ship
var t := 0.0
var started := false
var phase := 0
var phase_t := 0.0
var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _make(name_: String, pos: Vector3) -> Ship:
	var f := FileAccess.open("res://ships/Dart.json", FileAccess.READ)
	var s: Ship = (load("res://scenes/ship.tscn") as PackedScene).instantiate()
	s.design_json = f.get_as_text()
	s.name = name_
	root.add_child(s)
	s.global_position = pos
	return s

func _static_checks() -> void:
	print("intercept maths")
	var p := ShipAutopilot.intercept_point(Vector3.ZERO, Vector3.ZERO, 5.0, Vector3(0, 0, -100), Vector3.ZERO)
	check(p.distance_to(Vector3(0, 0, -100)) < 0.01, "a target that does not move: aim at it")
	var q := ShipAutopilot.intercept_point(Vector3.ZERO, Vector3.ZERO, 5.0, Vector3(0, 0, -100), Vector3(20, 0, 0))
	check(q.x > 20.0 and absf(q.z + 100.0) < 0.01, "a target crossing to the right: aim AHEAD of it (x=%.0f)" % q.x)
	# the aim point really is reachable: time for us to cover the distance equals the time the target needs to get there
	var d := q.length()
	var t_us := (-0.0 + sqrt(2.0 * 5.0 * d)) / 5.0
	var t_it := q.x / 20.0
	check(absf(t_us - t_it) < 0.3, "...we and the target arrive together (%.2f s vs %.2f s)" % [t_us, t_it])
	var fast := ShipAutopilot.intercept_point(Vector3.ZERO, Vector3(0, 0, -300), 5.0, Vector3(0, 0, -100), Vector3(20, 0, 0))
	check(fast.x < q.x, "already moving fast towards it: it has less time to move away (x=%.0f)" % fast.x)

func _start() -> void:
	_static_checks()
	ship = _make("1", Vector3.ZERO)
	ship.autopilot.drive_heading(Vector3(1, 0, 0), 0.8)
	print("heading DRIVE along +X")

func _process(delta: float) -> bool:
	if not started:
		started = true
		_start()
		return false
	t += delta
	var ap := ship.autopilot
	match phase:
		0:
			if t > 25.0:
				var v := ship.linear_velocity
				check(ap.mode == ShipAutopilot.Mode.DRIVE and ap.heading == Vector3(1, 0, 0), "the order is still an arrow (never arrives)")
				check(v.x > 5.0 and absf(v.z) < v.x * 0.2 and absf(v.y) < v.x * 0.2, "the ship goes the way of the arrow (v = %s)" % str(v.snapped(Vector3.ONE * 0.1)))
				var before := ship.global_position.x
				phase = 1
				phase_t = t
				ap.drive_heading(Vector3(0, 1, 0), 0.8)
				check(ap.target.y > 100.0 and ap.drive_direction().is_equal_approx(Vector3(0, 1, 0)), "a new arrow replaces the old (up)")
				print("  (x was %.0f)" % before)
		1:
			if t - phase_t > 40.0:
				var v := ship.linear_velocity
				check(v.y > 3.0, "turning the arrow up bends the flight up (vy=%.1f)" % v.y)
				other = _make("2", ship.global_position + Vector3(0, 0, -400))
				other.linear_velocity = Vector3(10, 0, 0)
				ap.go_follow(other)
				phase = 2
				phase_t = t
		2:
			other.linear_velocity = Vector3(10, 0, 0)       # keeps drifting at 10 m/s
			if t - phase_t > 150.0:
				var d := ship.global_position.distance_to(other.global_position)
				var rel := (ship.linear_velocity - other.linear_velocity).length()
				check(d < ap.follow_distance + 25.0, "GO TO a moving ship: it catches it up and holds station (%.0f m)" % d)
				check(rel < 3.0, "...matching its velocity (relative speed %.1f m/s)" % rel)
				ap.drive_to(other.global_position, 0.8, other)
				phase = 3
				phase_t = t
		3:
			other.linear_velocity = Vector3(10, 0, 0)
			var lead := (ap.aim_point() - other.global_position).normalized().dot(Vector3(1, 0, 0))
			if t - phase_t > 2.0 and phase_t > 0.0:
				check(ap.aim_point().distance_to(other.global_position) > 0.5, "DRIVE at a ship aims at the intercept point, not at the ship")
				check(lead > 0.8, "...which lies AHEAD of it along its course (%.2f)" % lead)
				print("RESULT: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
				quit(fails)
				return true
	return false
