extends SceneTree
## godot --headless -s res://tests/bench_design.gd -- N      (N = grid size per cube face; vertices ~ 6*N*N)
func _init() -> void:
	var n := int(OS.get_cmdline_user_args()[0])
	var t0 := Time.get_ticks_msec()
	var d := ShipDesign.new()
	var verts: Array[Vector3] = []
	var faces: Array = []
	# one cube surface, each side an NxN grid of quads (shared vertices on seams are not welded: fine for a benchmark)
	for side in 6:
		var base := verts.size()
		for j in n + 1:
			for i in n + 1:
				var u := float(i) / n * 2.0 - 1.0
				var v := float(j) / n * 2.0 - 1.0
				var pt := Vector3.ZERO
				match side:
					0: pt = Vector3(u, v, 1)
					1: pt = Vector3(u, v, -1)
					2: pt = Vector3(1, u, v)
					3: pt = Vector3(-1, u, v)
					4: pt = Vector3(u, 1, v)
					_: pt = Vector3(u, -1, v)
				verts.append(pt)
		for j in n:
			for i in n:
				var a := base + j * (n + 1) + i
				faces.append(PackedInt32Array([a, a + 1, a + n + 2, a + n + 1]))
	d.add_module_from_mesh("hull", verts, faces)
	d.add_module("thruster", "cylinder", Vector3(0, 0, 2), Vector3(0.2, 0.2, 0.2))
	d.add_module("commander", "box", Vector3(0, 1.4, 0), Vector3(0.3, 0.3, 0.3))
	print("build %d verts, %d faces: %d ms" % [d.vertices.size(), faces.size(), Time.get_ticks_msec() - t0])
	print("mem MB: %.0f" % (OS.get_static_memory_usage() / 1048576.0))
	t0 = Time.get_ticks_msec()
	d.build_mesh(PackedFloat32Array())
	print("build_mesh: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	d.compute_props()
	print("compute_props: %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var pts := d.module_points(0)
	print("module_points: %d ms (%d)" % [Time.get_ticks_msec() - t0, pts.size()])
	t0 = Time.get_ticks_msec()
	var blob := d.to_bytes()
	print("to_bytes: %d ms, %.1f MB" % [Time.get_ticks_msec() - t0, blob.size() / 1048576.0])
	t0 = Time.get_ticks_msec()
	var d2 := ShipDesign.from_bytes(blob)
	print("from_bytes: %d ms (cached sums kept: %s)" % [Time.get_ticks_msec() - t0, d2.modules[0].has("sums")])
	print("mem MB: %.0f" % (OS.get_static_memory_usage() / 1048576.0))
	quit()
