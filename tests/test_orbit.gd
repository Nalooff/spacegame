extends SceneTree
## ORBIT autopilot: circle a parked ship at 150 m.
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_orbit.gd -- "Twin Hull"
var ship: Ship
var target: Ship
var t := 0.0
var started := false
var fails := 0
var dmin := 1e9
var dmax := 0.0
var ang0 := 0.0
var ang_total := 0.0
var last_ang := 0.0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok: fails += 1

func _mk(name_: String, pos: Vector3, ship_name: String) -> Ship:
	var f := FileAccess.open("res://ships/%s.json" % ship_name, FileAccess.READ)
	var s: Ship = (load("res://scenes/ship.tscn") as PackedScene).instantiate()
	s.design_json = f.get_as_text()
	s.name = name_
	root.add_child(s)
	s.global_position = pos
	return s

func _process(delta: float) -> bool:
	if not started:
		started = true
		var args := OS.get_cmdline_user_args()
		var nm := args[0] if args.size() > 0 else "Twin Hull"
		ship = _mk("1", Vector3(0, 0, 150), nm)
		target = _mk("2", Vector3.ZERO, nm)
		ship.autopilot.go_orbit(target, 150.0)
		return false
	t += delta
	var rel := ship.global_position - target.global_position
	var d := rel.length()
	var ang := atan2(rel.z, rel.x)
	if t > 1.0:
		ang_total += wrapf(ang - last_ang, -PI, PI)
	last_ang = ang
	if t > 40.0:
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
	if t > 70.0:
		print("min %.0f max %.0f swept %.1f rad" % [dmin, dmax, ang_total])
		check(ship.autopilot.mode == ShipAutopilot.Mode.ORBIT, "still orbiting")
		check(dmin > 90.0 and dmax < 230.0, "stays near the 150 m circle (%.0f..%.0f)" % [dmin, dmax])
		check(absf(ang_total) > 3.0, "actually goes round (%.1f rad)" % ang_total)
		print("RESULT: PASS" if fails == 0 else "RESULT: %d FAILED" % fails)
		quit(0 if fails == 0 else 1)
	return false
