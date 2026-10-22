extends SceneTree
## Headless check:  godot --headless --path . -s res://tests/test_design.gd

func _init() -> void:
	# RCS sizing example from the spec: 2 x 5 N forward + 1 x 9 N backward -> 10 N best, RCS 0.5 N
	var a := ThrustAllocator.new()
	var dirs: Array[Vector3] = [Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0, 1)]
	var pos: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3.ZERO]
	a.setup(PackedFloat32Array([5.0, 5.0, 9.0]), dirs, pos)
	print("selftest F_best=%.3f RCS=%.3f axis=%s" % [a.f_best, a.rcs_max(), a.u_best])
	assert(absf(a.f_best - 10.0) < 1e-3 and absf(a.rcs_max() - 0.5) < 1e-4)

	for s in ShipDesign.list_ships():
		var d := ShipDesign.load_file(s["path"])
		var errs := d.validate()
		var p := d.compute_props()
		var pw := PackedFloat32Array()
		var dr: Array[Vector3] = []
		var ps: Array[Vector3] = []
		for t in p["thrusters"]:
			pw.append(t["power"])
			dr.append(t["dir"])
			ps.append(t["pos"] - p["com"])
		var al := ThrustAllocator.new()
		al.setup(pw, dr, ps)
		var m := d.build_mesh()
		print("%s: errors=%s mass=%.0f com=%s I=%s thrusters=%d Fbest=%.0f RCS=%.0f a=%.2f tris=%d" % [
			d.ship_name, errs, p["mass"], p["com"], p["inertia"], pw.size(), al.f_best, al.rcs_max(),
			al.f_best / p["mass"], int(m.surface_get_array_len(0) / 3.0)])
		assert(errs.is_empty())
		# allocator: ask for forward force 60 % of best, check torque is small vs thrust*lever
		var t := al.allocate(al.u_best * al.f_best * 0.6, PackedFloat32Array())
		print("   alloc 60%% best: force err %.1f N, torque %.1f N m" % [
			(al.force_of(t) - al.u_best * al.f_best * 0.6).length(), al.torque_of(t).length()])
	# every primitive must be a closed shape: each edge shared by exactly 2 faces, positive volume
	for prim in Primitives.NAMES:
		var d := ShipDesign.new()
		var mi := d.add_module("hull", prim, Vector3.ZERO, Vector3(1, 1, 1), 12)
		var counts := {}
		for f in (d.modules[mi]["fs"] as FaceSet).to_array():
			var ids: PackedInt32Array = f
			for k in ids.size():
				var ia := ids[k]
				var ib := ids[(k + 1) % ids.size()]
				var e := Vector2i(mini(ia, ib), maxi(ia, ib))
				counts[e] = counts.get(e, 0) + 1
		var open_edges := 0
		for e in counts:
			if counts[e] != 2:
				open_edges += 1
		print("primitive %-8s verts=%3d faces=%3d edges=%3d open_edges=%d volume=%.3f" % [prim, d.vertices.size(),
			(d.modules[mi]["fs"] as FaceSet).alive_count(), counts.size(), open_edges, d.module_volume(mi)])
		assert(open_edges == 0 and d.module_volume(mi) > 0.01)
	quit()
