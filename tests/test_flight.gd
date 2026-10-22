extends SceneTree
## Headless flight test of the REAL ship scene + autopilot.
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_flight.gd -- "Dart" 5 7 6
var ship: Ship
var t := 0.0
var next_log := 0.0
var target := Vector3(5, 7, 6)
var t_end := 60.0
var best := 1e9

var started := false

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var ship_name := args[0] if args.size() > 0 else "Dart"
	if args.size() >= 4:
		target = Vector3(float(args[1]), float(args[2]), float(args[3]))
	if args.size() >= 5:
		t_end = float(args[4])
	var f := FileAccess.open("res://ships/%s.json" % ship_name, FileAccess.READ)
	ship = (load("res://scenes/ship.tscn") as PackedScene).instantiate()
	ship.design_json = f.get_as_text()
	ship.name = "1"
	root.add_child(ship)
	ship.rotation = Vector3(0.7, 1.9, -0.4) # awkward start attitude
	ship.autopilot.go_to(target)
	print("%s: mass %.0f  F_best %.0f  RCS %.0f (%.1f%%)  gyro %.0f  power ratio %.2f" % [ship_name, ship.mass,
		ship.alloc.f_best, ship.rcs.force_max, 100.0 * ship.rcs.force_max / ship.alloc.f_best, ship.gyro.torque_max,
		ship.electricity.ratio])

func _process(delta: float) -> bool:
	if not started:
		started = true
		_start()
		return false
	t += delta
	var d := (target - ship.global_position).length()
	best = minf(best, d)
	if t >= next_log:
		next_log += 4.0
		print("t=%5.1f %-9s dist=%7.3f speed=%6.3f att=%5.1f deg" % [t, ship.autopilot.phase, d, ship.speed(),
			rad_to_deg(ship.autopilot.att_error)])
	if t >= t_end:
		print("FINAL dist=%.3f m speed=%.3f m/s on_target=%s" % [d, ship.speed(), ship.autopilot.on_target])
		return true
	return false
