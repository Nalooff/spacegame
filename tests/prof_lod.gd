extends Node
## Draw calls and frame costs with two capital ships at different distances (needs a display: xvfb-run).
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
	var a := _ship("res://ships/Spearhead.ship", Vector3.ZERO)
	var b := _ship("res://ships/Dreadnought.ship", Vector3(0, 0, -3000))
	for s in [a, b]:
		s.set_physics_process(false)
	for i in 240:
		await get_tree().process_frame
	for dist in [150.0, 600.0, 2500.0, 9000.0]:
		cam.position = Vector3(0, 300, dist)
		cam.look_at(Vector3(0, 0, -1500))
		for i in 30:
			await get_tree().process_frame
		var t := Time.get_ticks_usec()
		for i in 30:
			await get_tree().process_frame
		print("camera %5.0f m: draw calls %4d  objects %4d  frame %.1f ms" % [dist, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), (Time.get_ticks_usec() - t) / 30000.0])
	get_tree().quit()
