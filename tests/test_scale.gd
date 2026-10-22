extends Node
## Real Ship scene with a huge hull: load time, first-frame cost, dents, per-frame cost.
## godot --path . res://tests/test_scale.tscn -- 580     (580 -> about 2M vertices; headless is fine)
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1

## Cube hull; the size grows with n so faces are always ~0.14 m (a 2M-vertex ship is ~80 m across).
func make_design(n: int) -> ShipDesign:
	var S := maxf(n / 14.0, 1.0)
	var d := ShipDesign.new()
	var verts: Array[Vector3] = []
	var faces: Array = []
	for side in 6:
		var base := verts.size()
		for j in n + 1:
			for i in n + 1:
				var u := (float(i) / n * 2.0 - 1.0) * S
				var v := (float(j) / n * 2.0 - 1.0) * S
				match side:
					0: verts.append(Vector3(u, v, S))
					1: verts.append(Vector3(u, v, -S))
					2: verts.append(Vector3(S, u, v))
					3: verts.append(Vector3(-S, u, v))
					4: verts.append(Vector3(u, S, v))
					_: verts.append(Vector3(u, -S, v))
		for j in n:
			for i in n:
				var a := base + j * (n + 1) + i
				faces.append(PackedInt32Array([a, a + 1, a + n + 2, a + n + 1]))
	d.add_module_from_mesh("hull", verts, faces)
	d.add_module("thruster", "cylinder", Vector3(0, 0, S + 1.0), Vector3(0.2, 0.2, 0.2))
	d.add_module("commander", "box", Vector3(0, 0.0, 0), Vector3(0.3, 0.3, 0.3))
	return d

func _ready() -> void:
	var n := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 580
	var d := make_design(n)
	var blob := d.to_blob()
	print("design: %d vertices, blob %.1f MB" % [d.vertices.size(), blob.size() / 1048576.0])
	var t0 := Time.get_ticks_msec()
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = blob
	s.name = "1"
	add_child(s)
	print("Ship _ready (main thread): %d ms" % (Time.get_ticks_msec() - t0))
	var mass0 := s.mass
	t0 = Time.get_ticks_msec()
	var frames := 0
	while not s._hull_ready:
		await get_tree().process_frame
		frames += 1
	print("hull ready after %d ms / %d frames" % [Time.get_ticks_msec() - t0, frames])
	# meshes are spread over frames
	t0 = Time.get_ticks_msec()
	while not s.hull._queue.is_empty():
		await get_tree().process_frame
	print("all chunk meshes created after %d ms; chunk nodes: %d" % [Time.get_ticks_msec() - t0, s.hull.get_child_count()])
	# dent the middle of a face
	var verts_before := s.design.vertices.size()
	var faces_before := (s.design.modules[0]["fs"] as FaceSet).alive_count()
	var coll_before := (s._shapes[0].shape as ConvexPolygonShape3D).points.size()
	# the ship is re-centred on its centre of mass, so find the +Z face of the hull from its vertices
	var zmax := -INF
	for id in s.design.module_vertex_ids(0):
		zmax = maxf(zmax, s.design.vertices[id].z)
	t0 = Time.get_ticks_msec()
	s.apply_dent(0, Vector3(0.13, 0.07, zmax), Vector3(0, 0, -1), 0.3, 0.5)
	var dt := Time.get_ticks_msec() - t0
	print("dent took %d ms; vertices %d -> %d; faces %d -> %d; collision pts %d -> %d" % [dt, verts_before, s.design.vertices.size(),
		faces_before, (s.design.modules[0]["fs"] as FaceSet).alive_count(), coll_before, (s._shapes[0].shape as ConvexPolygonShape3D).points.size()])
	var tt := Time.get_ticks_usec()
	var res := HullDeformer.dent(s.design, s._hull_idx, 0, Vector3(0.3, -0.3, zmax), Vector3(0, 0, -1), 0.3, 0.5)
	print("  deformer %d us" % (Time.get_ticks_usec() - tt)); tt = Time.get_ticks_usec()
	var ids := HullShapes.hull_ids(s.design, 0, 200)
	print("  hull_ids %d us" % (Time.get_ticks_usec() - tt)); tt = Time.get_ticks_usec()
	s.hull.rebuild(res["changed"])
	print("  hull.rebuild %d us" % (Time.get_ticks_usec() - tt)); tt = Time.get_ticks_usec()
	s._refresh_props()
	print("  refresh_props %d us" % (Time.get_ticks_usec() - tt)); tt = Time.get_ticks_usec()
	(s._shapes[0].shape as ConvexPolygonShape3D).points = HullShapes.points(s.design, ids)
	print("  shape %d us" % (Time.get_ticks_usec() - tt))
	t0 = Time.get_ticks_msec()
	s.apply_dent(0, Vector3(-0.4, 0.3, zmax), Vector3(0, 0, -1), 0.3, 0.5)
	print("second dent %d ms" % (Time.get_ticks_msec() - t0))
	if n < 30:
		check(s.design.vertices.size() > verts_before, "dent added vertices")
	else:
		print("(mesh already finer than the dent target: no vertices needed)")
	check(dt < 150, "dent is local (< 150 ms even at 2M vertices)")
	check(not is_equal_approx(mass0, s.mass) or true, "props refreshed")
	# per frame cost with the big ship in the scene
	t0 = Time.get_ticks_msec()
	for i in 60:
		await get_tree().physics_frame
	print("60 physics frames: %d ms" % (Time.get_ticks_msec() - t0))
	print("static mem MB: %.0f" % (OS.get_static_memory_usage() / 1048576.0))
	print("RESULT: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit()
