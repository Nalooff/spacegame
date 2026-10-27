extends Node
## GJK overlap + module graph: godot --headless --path . res://tests/test_graph.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1

func box(c: Vector3, h: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in 8:
		out.append(c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	return out

func _ready() -> void:
	var a := box(Vector3.ZERO, Vector3.ONE)
	check(ConvexOverlap.intersects(a, box(Vector3(1.5, 0, 0), Vector3.ONE)), "overlapping boxes")
	check(ConvexOverlap.intersects(a, box(Vector3(0.2, 0.1, 0), Vector3(0.1, 0.1, 0.1))), "box inside box")
	check(not ConvexOverlap.intersects(a, box(Vector3(3.0, 0, 0), Vector3.ONE)), "separated boxes")
	check(not ConvexOverlap.intersects(a, box(Vector3(2.5, 2.5, 2.5), Vector3.ONE)), "separated diagonally")
	check(ConvexOverlap.intersects(a, box(Vector3(2.02, 0, 0), Vector3.ONE), 0.04), "almost touching within margin")
	check(not ConvexOverlap.intersects(a, box(Vector3(2.2, 0, 0), Vector3.ONE), 0.04), "gap bigger than margin")
	# random agreement with an exact AABB test for axis-aligned boxes
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wrong := 0
	for i in 400:
		var c := Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var h := Vector3(rng.randf_range(0.2, 1), rng.randf_range(0.2, 1), rng.randf_range(0.2, 1))
		var expect := absf(c.x) <= 1.0 + h.x and absf(c.y) <= 1.0 + h.y and absf(c.z) <= 1.0 + h.z
		if absf(absf(c.x) - (1.0 + h.x)) < 0.01 or absf(absf(c.y) - (1.0 + h.y)) < 0.01 or absf(absf(c.z) - (1.0 + h.z)) < 0.01:
			continue
		if ConvexOverlap.intersects(a, box(c, h)) != expect:
			wrong += 1
	check(wrong == 0, "400 random boxes agree with the exact test (wrong=%d)" % wrong)
	# module graph: three boxes in a row (touching), one far away, one sharing a vertex only
	var d := ShipDesign.new()
	d.add_module("commander", "box", Vector3(0, 0, 0), Vector3(0.5, 0.5, 0.5))
	d.add_module("hull", "box", Vector3(1.0, 0, 0), Vector3(0.5, 0.5, 0.5))      # touches the commander
	d.add_module("thruster", "box", Vector3(2.0, 0, 0), Vector3(0.5, 0.5, 0.5))  # touches the hull only
	d.add_module("armor", "box", Vector3(10, 0, 0), Vector3(0.5, 0.5, 0.5))      # far away
	var g := ModuleGraph.build(d)
	check(g.adj[0].has(1) and g.adj[1].has(2) and not g.adj[0].has(2), "chain 0-1-2 (touching boxes)")
	check(g.adj[3].is_empty(), "far module has no neighbours")
	var alive := PackedByteArray([1, 1, 1, 1])
	check(g.components(alive).size() == 2, "two groups: the chain and the far module")
	alive[1] = 0
	var comps := g.components(alive)
	check(comps.size() == 3, "killing the middle module separates the thruster (3 groups)")
	check(ModuleGraph.unreachable(d).has(3), "validate sees the far module as unreachable")
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit()
