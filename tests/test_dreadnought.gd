extends Node
## The 2 km Dreadnought: valid, loads fast, simulates without choking.
##   godot --headless --path . res://tests/test_dreadnought.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	var path := "res://ships/Dreadnought.ship"
	check(FileAccess.file_exists(path), "the premade Dreadnought exists")
	var d := ShipDesign.load_file(path)
	check(d != null and d.extent_length() > 2000.0, "it is longer than 2 km (%.0f m)" % d.extent_length())
	var errs := d.validate()
	errs.append_array(d.turret_errors())
	check(errs.is_empty(), "it passes the builder's checks %s" % str(errs.slice(0, 2)))
	check(d.details.size() > 3000, "it is fully detailed (%d details)" % d.details.size())
	var t0 := Time.get_ticks_msec()
	var ship: Ship = load("res://scenes/ship.tscn").instantiate()
	ship.design_blob = d.to_blob()
	add_child(ship)
	for i in 120: await get_tree().physics_frame
	var load_ms := Time.get_ticks_msec() - t0
	print("load + 120 frames: %d ms, mass %.3g kg" % [load_ms, ship.mass])
	check(ship.mass > 1.0e10, "it weighs like a capital ship")
	var t1 := Time.get_ticks_msec()
	for i in 120: await get_tree().physics_frame
	var per_frame := (Time.get_ticks_msec() - t1) / 120.0
	print("physics frame: %.1f ms" % per_frame)
	check(per_frame < 60.0, "a frame with the dreadnought in it is cheap (%.1f ms)" % per_frame)
	check(ship.design.modules.size() >= 100, "all modules present")
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
