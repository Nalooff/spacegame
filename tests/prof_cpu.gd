extends Node
## CPU cost per frame (script + physics) with big ships (headless ok).
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
	_ship("res://ships/Spearhead.ship", Vector3.ZERO)
	if OS.get_environment("N") != "1": _ship("res://ships/Dreadnought.ship", Vector3(0, 0, -3000))
	if OS.get_environment("N") == "3": _ship("res://ships/Hammerhead.ship", Vector3(2000, 0, 0))
	for i in 600:
		await get_tree().physics_frame
	var tp := 0.0; var tr := 0.0; var n := 0
	for i in 120:
		await get_tree().process_frame
		tp += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS); tr += Performance.get_monitor(Performance.TIME_PROCESS); n += 1
	print("physics %.2f ms  process %.2f ms  shapes3d: ptv %d" % [tp / n * 1000.0, tr / n * 1000.0, Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)])
	get_tree().quit()
