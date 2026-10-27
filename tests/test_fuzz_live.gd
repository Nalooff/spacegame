extends Node
## LIVE fuzz: real ships fly with random autopilot orders (GOTO / DRIVE / facing lock / brake / cancel) while random
## modules are damaged, with and without an enemy. Physics must stay finite and nothing may throw.
## Run: godot --headless --path . res://tests/test_fuzz_live.tscn
var fails := 0
var rng := RandomNumberGenerator.new()


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL ", msg)


func _ready() -> void:
	await get_tree().process_frame
	for file in ["Brick", "Dart", "Twin Hull", "Scrap Hauler"]:
		for sd in 3:
			await _run(file, 3000 + sd)
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(1 if fails else 0)


func _spawn(file: String, pos: Vector3) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/%s.json" % file)
	s.position = pos
	add_child(s)
	return s


func _run(file: String, seed_: int) -> void:
	rng.seed = seed_
	var me := _spawn(file, Vector3.ZERO)
	var foe := _spawn("Dart", Vector3(rng.randf_range(-80, 80), rng.randf_range(-30, 30), rng.randf_range(-150, -60)))
	await get_tree().physics_frame
	var tag := "%s seed %d" % [file, seed_]
	for step in 40:
		var o := rng.randi() % 8
		var p := Vector3(rng.randf_range(-200, 200), rng.randf_range(-60, 60), rng.randf_range(-200, 200))
		match o:
			0: me.autopilot.go_to(p, true)
			1: me.autopilot.drive_to(p, rng.randf(), null, true)
			2: me.autopilot.drive_to(foe.global_position, rng.randf(), foe, true)
			3: me.autopilot.face_turrets = not me.autopilot.face_turrets
			4: me.autopilot.brake()
			5: me.autopilot.cancel()
			6:
				if me.module_hp.size() > 0:
					me.apply_damage(rng.randi() % me.module_hp.size(), rng.randf_range(10.0, 400.0))
			7:
				if foe.alive and me.weapons != null:
					me.weapons.try_fire(foe.global_position, 1.0, PackedInt32Array(), rng.randf() > 0.5)
		for f in 6:
			await get_tree().physics_frame
		var lv := me.linear_velocity
		var gp := me.global_position
		if not (is_finite(lv.x) and is_finite(lv.y) and is_finite(lv.z) and is_finite(gp.x) and is_finite(gp.y) and is_finite(gp.z)):
			check(false, tag + ": position / velocity became NaN at step %d (order %d)" % [step, o])
			break
		var av := me.angular_velocity
		check(is_finite(av.x) and is_finite(av.y) and is_finite(av.z), tag + ": angular velocity finite (step %d)" % step)
		if me.reports != null and me.reports.known_state != null:
			check(me.reports.known_hp.size() == me.module_hp.size(), tag + ": the commander's known state matches the ship")
	me.queue_free()
	foe.queue_free()
	await get_tree().process_frame
	print("  ", tag, " ok")
