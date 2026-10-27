extends SceneTree
## Headless test of the DRIVE flight mode and the turret-facing lock.
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_drive.gd -- "Twin Hull"
var ship: Ship
var t := 0.0
var started := false
var passed_speed := 0.0
var min_d := 1e9
var phase := 0
var phase_t := 0.0
var fails := 0
const TARGET := Vector3(0, 0, -120)

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var ship_name := args[0] if args.size() > 0 else "Twin Hull"
	var f := FileAccess.open("res://ships/%s.json" % ship_name, FileAccess.READ)
	ship = (load("res://scenes/ship.tscn") as PackedScene).instantiate()
	ship.design_json = f.get_as_text()
	ship.name = "1"
	root.add_child(ship)
	if args.size() > 1 and args[1] == "face":
		ship.autopilot.face_turrets = true
		ship.autopilot.drive_to(Vector3(150, 0, 0), 0.6)      # fly sideways but keep the turrets facing the point
	else:
		ship.autopilot.drive_to(TARGET, 0.8)
	print("%s F_best %.0f mass %.0f" % [ship_name, ship.alloc.f_best, ship.mass])

func _process(delta: float) -> bool:
	if not started:
		started = true
		_start()
		return false
	t += delta
	var d := (TARGET - ship.global_position).length()
	if ship.autopilot.face_turrets:
		if t > 40.0:
			var to := (ship.autopilot.target - ship.global_position).normalized()
			var ang := rad_to_deg((ship.global_transform.basis * ship.autopilot._face_axis).angle_to(to))
			print("facing axis %s error %.1f deg, speed %.1f" % [str(ship.autopilot._face_axis), ang, ship.speed()])
			check(ang < 12.0, "ship keeps the turret-facing axis on the target (%.1f deg)" % ang)
			check(ship.speed() > 1.0, "...while still moving (%.1f m/s)" % ship.speed())
			print("RESULT: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
			quit(fails)
			return true
		return false
	if phase == 0:
		min_d = minf(min_d, d)
		if d > min_d + 20.0 or t > 90.0 or min_d < 5.0 and ship.global_position.z < TARGET.z - 30.0:
			check(min_d < 15.0, "DRIVE reached the point (closest %.1f m)" % min_d)
			check(ship.speed() > 2.0, "...and did not stop there (speed %.1f m/s, mode %s)" % [ship.speed(), ship.autopilot.phase])
			phase = 1
			phase_t = t
			ship.autopilot.brake()
	elif phase == 1:
		if ship.speed() < 0.3 or t - phase_t > 120.0:
			check(ship.speed() < 1.5, "brake stops the ship (%.2f m/s after %.0f s)" % [ship.speed(), t - phase_t])
			print("RESULT: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
			quit(fails)
			return true
	return false
