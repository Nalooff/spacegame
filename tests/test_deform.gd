extends SceneTree
## godot --headless -s res://tests/test_deform.gd     (design-level test of vertex-inserting dents)
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1

func manifold(d: ShipDesign, mi: int) -> int:
	var counts := {}
	var fs: FaceSet = d.modules[mi]["fs"]
	for fi in fs.count():
		var n := fs.sizes[fi]
		if n == 0: continue
		for k in n:
			var a := fs.ids[fs.starts[fi] + k]
			var b := fs.ids[fs.starts[fi] + (k + 1) % n]
			var key := (mini(a, b) << 32) | maxi(a, b)
			counts[key] = counts.get(key, 0) + 1
	var bad := 0
	for key in counts:
		if counts[key] != 2: bad += 1
	return bad

func _init() -> void:
	var run := func() -> Dictionary:
		var dd := ShipDesign.new()
		dd.add_module("hull", "box", Vector3.ZERO, Vector3(1, 1, 1))
		dd.add_module("armor", "box", Vector3(2, 0, 0), Vector3(1, 1, 1)) # a second module next to it, not linked
		var idx: Array = []
		for m in dd.modules.size(): idx.append(HullIndex.build(dd, m))
		var props0 := dd.compute_props()
		var v0 := dd.vertices.size()
		var res := HullDeformer.dent(dd, idx, 0, Vector3(0.3, 0.2, 1.0), Vector3(0, 0, -1), 0.4, 0.5)
		return {"d": dd, "idx": idx, "props0": props0, "v0": v0, "res": res}
	var a: Dictionary = run.call()
	var d: ShipDesign = a["d"]
	print("vertices %d -> %d, faces alive %d" % [a["v0"], d.vertices.size(), (d.modules[0]["fs"] as FaceSet).alive_count()])
	check(d.vertices.size() > a["v0"] + 20, "dent inserted new vertices")
	check(manifold(d, 0) == 0, "module still watertight (no cracks, every edge used twice)")
	check(manifold(d, 1) == 0, "other module untouched and watertight")
	var vol_new: float = d.module_sums(0)[0]
	d.modules[0].erase("sums")
	var vol_full: float = d.module_sums(0)[0]
	print("incremental volume %.5f   recomputed %.5f   was %.5f" % [vol_new, vol_full, a["props0"]["modules"][0]["volume"]])
	check(absf(vol_new - vol_full) < 1e-4, "incrementally updated volume equals full recompute")
	check(vol_full < a["props0"]["modules"][0]["volume"] - 0.02, "the dent removed volume")
	# deepest vertex really moved inward (z started at +1)
	var minz := 99.0
	var maxz := -99.0
	for id in d.module_vertex_ids(0):
		if d.vertices[id].z > 0.5: minz = minf(minz, d.vertices[id].z)
		maxz = maxf(maxz, d.vertices[id].z)
	check(maxz <= 1.0001 and minz < 0.8, "surface bent inward (lowest front vertex z=%.2f)" % minz)
	var p2 := d.compute_props()
	check(p2["mass"] < a["props0"]["mass"], "mass recalculated (%.1f -> %.1f)" % [a["props0"]["mass"], p2["mass"]])
	# determinism: same event on a second copy gives the same vertices
	var b: Dictionary = run.call()
	var same := (b["d"] as ShipDesign).vertices == d.vertices
	check(same, "deterministic: second run produced identical vertices")
	# a second hit nearby keeps it watertight
	var res2 := HullDeformer.dent(d, a["idx"], 0, Vector3(0.6, 0.2, 1.0), Vector3(0, 0, -1), 0.3, 0.5)
	check(manifold(d, 0) == 0, "second overlapping dent: still watertight (%d new vertices)" % res2["new_vertices"])
	# dent on the edge between two faces and a hit on the side of the module
	HullDeformer.dent(d, a["idx"], 0, Vector3(1.0, 1.0, 0.0), Vector3(-0.7, -0.7, 0).normalized(), 0.3, 0.5)
	check(manifold(d, 0) == 0, "dent on an edge between faces: watertight")
	print("RESULT: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(fails)
