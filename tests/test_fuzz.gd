extends Node
## FUZZ tests: random edits, random damage, every plan view. Anything that throws a script error, makes NaN, loses data on
## save/load or breaks a plan invariant is a bug.  Run: godot --headless --path . res://tests/test_fuzz.tscn
## Change SEEDS / ROUNDS for a longer run.

const SEEDS := 12
const ROUNDS := 25
var fails := 0
var rng := RandomNumberGenerator.new()


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL ", msg)


func _ready() -> void:
	await get_tree().process_frame
	_fuzz_editing()
	_fuzz_plan_damage()
	await _fuzz_canvas()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(1 if fails else 0)


func _ship(file: String) -> ShipDesign:
	return ShipDesign.from_blob(ShipDesign.read_blob("res://ships/%s.json" % file))


func _finite(v: Variant) -> bool:
	if v is float:
		return is_finite(v)
	if v is Vector3:
		return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
	return true


## Random modelling operators + random modules, then every derived thing must still work.
func _fuzz_editing() -> void:
	print("fuzz: random edits")
	var types := [ModuleCatalog.THRUSTER, ModuleCatalog.TURRET, ModuleCatalog.RADAR, ModuleCatalog.ANTENNA, ModuleCatalog.COMMANDER]
	var prims := ["box", "wedge", "pyramid", "tetra", "cylinder", "cone", "sphere", "dome"]
	for sd in SEEDS:
		rng.seed = 1000 + sd
		for file in ["Brick", "Dart", "Twin Hull", "Scrap Hauler"]:
			var d := _ship(file)
			for i in ROUNDS:
				var mi := rng.randi() % d.modules.size()
				var fa := d.faces_array(mi)
				var op := rng.randi() % 9
				var picks: Array[int] = []
				if fa.size() > 0:
					picks.append(rng.randi() % fa.size())
				match op:
					0:
						if picks.size() > 0:
							MeshOps.extrude_faces(d, mi, picks)
					1:
						if picks.size() > 0:
							MeshOps.inset_faces(d, mi, picks, rng.randf_range(0.01, 0.3), rng.randf_range(-0.2, 0.2))
					2:
						if picks.size() > 0:
							MeshOps.triangulate_faces(d, mi, picks)
					3:
						if picks.size() > 0:
							MeshOps.subdivide_faces(d, mi, picks)
					4:
						var es := d.module_edges(mi)
						if es.size() > 0:
							var e: Vector2i = es[rng.randi() % es.size()]
							MeshOps.subdivide_edge(d, mi, e.x, e.y)
					5:
						var es2 := d.module_edges(mi)
						if es2.size() > 0:
							var e2: Vector2i = es2[rng.randi() % es2.size()]
							MeshOps.bevel_edge(d, mi, e2.x, e2.y, rng.randf_range(0.01, 0.2))
					6:
						d.add_module(types[rng.randi() % types.size()], prims[rng.randi() % prims.size()],
							Vector3(rng.randf_range(-2, 2), rng.randf_range(-1, 1), rng.randf_range(-3, 3)),
							Vector3(rng.randf_range(0.3, 1.2), rng.randf_range(0.3, 1.2), rng.randf_range(0.3, 1.2)), rng.randi_range(3, 16))
					7:
						d.duplicate_module(mi, Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)))
					8:
						d.mirror_module(mi, 0, 0.0)
			var tag := "%s seed %d" % [file, sd]
			var props := d.compute_props()
			check(_finite(props.get("mass", 0.0)), tag + ": mass is finite")
			check(_finite(props.get("com", Vector3.ZERO)), tag + ": centre of mass is finite")
			d.validate()
			var plan := ShipPlan.generate(d)
			check(plan != null, tag + ": plan generates")
			var back := ShipDesign.from_blob(d.to_bytes())
			check(back.modules.size() == d.modules.size(), tag + ": save/load keeps the module count")
			check(back.face_count_total() == d.face_count_total(), tag + ": save/load keeps the face count")
			check(ShipPlan.generate(back).rooms.size() == plan.rooms.size(), tag + ": same rooms after reload")
	print("  edits done")


## Kill / dent random modules and corridors with comms on and off: reach and delays must stay sane.
func _fuzz_plan_damage() -> void:
	print("fuzz: random damage on the plan")
	for sd in SEEDS:
		rng.seed = 2000 + sd
		for file in ["Brick", "Dart", "Twin Hull", "Scrap Hauler"]:
			var d := _ship(file)
			var plan := ShipPlan.generate(d)
			var ps := PlanState.new(plan)
			var types := PackedStringArray()
			for m in d.modules:
				types.append(m["type"])
			for rd in 20:
				var hp := PackedFloat32Array()
				for mi in d.modules.size():
					hp.append(1.0 if rng.randf() > 0.25 else (0.0 if rng.randf() > 0.3 else -1.0))
				for ei in ps.edge_hp.size():
					ps.edge_hp[ei] = 1.0 if rng.randf() > 0.25 else 0.0
				var comms := rng.randf() > 0.5
				ps.update(types, hp, comms)
				var tag := "%s damage %d/%d" % [file, sd, rd]
				check(ps.reach.size() == d.modules.size(), tag + ": reach covers every module")
				for r in plan.rooms:
					var dl := ps.order_delay(r)
					check(not is_nan(dl) and dl >= 0.0, tag + ": order delay of room %d is a number >= 0" % r)
					if hp[r] <= 0.0:
						check(not ps.is_working(r), tag + ": dead room %d does not work" % r)
				for ei in plan.edges.size():
					var a: Vector3 = plan.nodes[plan.edges[ei]["a"]]["pos"]
					var dl2 := ps.delay_at(a)
					check(not is_nan(dl2), tag + ": delay at a point is never NaN")
	print("  damage done")


## Draw the plan in every view / paper / deck / layer combination, with a damaged live-less design.
func _fuzz_canvas() -> void:
	print("fuzz: canvas drawing in every view")
	var canvas := PlanCanvas.new()
	canvas.size = Vector2(900, 520)
	add_child(canvas)
	canvas.register_layer("below", "Deck below", Callable(canvas, "_layer_below"))
	canvas.register_layer("structure", "Hull", Callable(canvas, "_layer_structure"))
	canvas.register_layer("rooms", "Rooms and corridors", Callable(canvas, "_layer_rooms"))
	var n := 0
	for file in ["Brick", "Dart", "Twin Hull", "Scrap Hauler"]:
		var d := _ship(file)
		canvas.show_design(d, true)
		for v in [PlanCanvas.View.DECK, PlanCanvas.View.SIDE, PlanCanvas.View.FRONT, PlanCanvas.View.SHEET, PlanCanvas.View.ISO]:
			canvas.set_view(v)
			for white in [false, true]:
				canvas.set_paper_white(white)
				for k in 3:
					canvas.set_deck(k)
					for lay in [[true, true], [true, false], [false, true], [false, false]]:
						canvas.set_layer_enabled("below", lay[0])
						canvas.set_layer_enabled("structure", lay[0])
						canvas.set_layer_enabled("rooms", lay[1])
						canvas.queue_redraw()
						await get_tree().process_frame
						n += 1
	check(true, "drew %d view combinations without a script error" % n)
	# claimed rectangles never overlap each other (the whole point of the label placement)
	canvas.set_view(PlanCanvas.View.DECK)
	canvas.set_layer_enabled("structure", true)
	canvas.set_layer_enabled("rooms", true)
	canvas.queue_redraw()
	await get_tree().process_frame
	var cl: Array[Rect2] = canvas._claimed
	var bad := 0
	for i in cl.size():
		for j in range(i + 1, cl.size()):
			if cl[i].intersects(cl[j]):
				bad += 1
	check(cl.size() > 0, "labels were claimed at all (%d)" % cl.size())
	check(bad == 0, "no two claimed labels / markers overlap (%d of %d pairs)" % [bad, cl.size()])
	print("  canvas done")
