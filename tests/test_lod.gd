extends Node
## Level of detail + visibility: small parts vanish with distance, big ships stay visible from their hull, not their middle.
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1

func _ready() -> void:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/Spearhead.ship")
	s.name = "1"
	add_child(s)
	s.set_physics_process(false)
	for i in 200:
		await get_tree().process_frame
	var shown := func() -> int:
		var n := 0
		for c in s.hull.get_children():
			if c is MeshInstance3D and c.visible:
				n += 1
		return n
	s.hull.update_lod(Vector3(0, 100, 0), 0.006)
	var near: int = shown.call()
	s.hull.update_lod(Vector3(0, 0, 5000), 0.006)
	var far: int = shown.call()
	s.hull.update_lod(Vector3(0, 100, 0), 0.006)
	var back: int = shown.call()
	check(far < near * 0.6, "far away only the big parts are drawn (%d -> %d meshes)" % [near, far])
	check(back == near, "coming back brings every part back (%d)" % back)
	check(s.radius_m > 800.0, "the ship knows its radius (%.0f m)" % s.radius_m)
	check(Data.view_range_for(s.radius_m * 2.0) > 6000.0, "a 1.7 km ship is seen by eye from %.0f m" % Data.view_range_for(s.radius_m * 2.0))
	check(Data.view_range_for(10.0) < 1300.0, "a fighter only from %.0f m" % Data.view_range_for(10.0))
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
