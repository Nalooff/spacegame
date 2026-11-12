extends Node
## Cost of a ram between two capital ships (headless ok): per physics frame, before / during / after the crash.
func _ship(path: String, pos: Vector3) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob(path)
	s.name = str(randi())
	s.position = pos
	add_child(s)
	return s

func _ready() -> void:
	var pool := ProjectilePool.new(); pool.name = "ProjectilePool"; add_child(pool)
	var cam := Camera3D.new(); cam.far = 60000.0; add_child(cam); cam.make_current()
	var a := _ship("res://ships/Hammerhead.ship", Vector3.ZERO)
	var b := _ship("res://ships/Hammerhead.ship", Vector3(0, 0, -700))
	for i in 600:
		await get_tree().physics_frame
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(0, 0, -520)
	a.linear_velocity = Vector3(0, 0, -40)
	b.linear_velocity = Vector3(0, 0, 40)
	var worst := 0.0; var tot := 0.0; var n := 0; var worst_f := 0
	for i in 500:
		var t0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		if i > 5: tot += dt; n += 1
		if dt > worst: worst = dt; worst_f = i
		if dt > 40.0: print("  frame ", i, " ", snappedf(dt, 0.1), " ms  lodges ", a.lodges.size())
	print("ram: avg frame %.1f ms  worst %.1f ms (frame %d)  contacts a=%d  hp lost a=%.0f" % [tot / n, worst, worst_f, a.lodges.size(), a.module_hp.size()])
	get_tree().quit()
