extends Node
## Run:  godot --headless res://tests/test_builder.tscn --quit-after 600
## Drives the builder through its public actions (the same ones the buttons call).
var fails := 0

func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond: fails += 1

func _ready() -> void:
	var scene: ShipBuilder = load("res://scenes/ship_builder.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	var b: ShipBuilder = scene
	# regression: switching the mode rebuilds the tool panel (old buttons are freed a frame later); the next refresh must not crash
	for m in [ShipBuilder.Mode.VERTEX, ShipBuilder.Mode.OBJECT, ShipBuilder.Mode.EDGE, ShipBuilder.Mode.OBJECT, ShipBuilder.Mode.FACE, ShipBuilder.Mode.VERTEX, ShipBuilder.Mode.OBJECT]:
		b.set_mode(m)
		await get_tree().process_frame
		await get_tree().process_frame
		b.on_selection_changed()
		await get_tree().process_frame
	check(b.mode == ShipBuilder.Mode.OBJECT, "mode can be switched back and forth with frames in between (freed tool buttons are forgotten)")
	var d := b.design
	check(d.modules.size() == 3, "new ship has hull, commander, thruster")
	check(d.validate().is_empty(), "new ship is valid: %s" % str(d.validate()))
	var ui: BuilderUI = scene.get_node("UI/BuilderUI")
	check(ui.ship_stats_label.text != "", "UI stats filled")

	# add every primitive
	for p in Primitives.NAMES:
		var n := b.design.modules.size()
		b.add_module(ModuleCatalog.ARMOR, p, Vector3(0.3, 0.3, 0.3), 8)
		check(b.design.modules.size() == n + 1 and b.design.module_volume(n) > 0.001, "add %s (volume %.3f)" % [p, b.design.module_volume(n)])

	# extrude a face
	var mi := 0
	b.set_mode(ShipBuilder.Mode.FACE)
	b.sel_faces = [Vector2i(mi, 0)]
	var vcount := b.design.vertices.size()
	var mcount: int = (b.design.modules[mi]["fs"] as FaceSet).alive_count()
	b.start_operator("extrude")
	check(b.op_name == "extrude", "extrude opens the adjust panel")
	b.confirm_operator()
	check(b.design.vertices.size() > vcount, "extrude adds vertices")
	check((b.design.modules[mi]["fs"] as FaceSet).alive_count() > mcount, "extrude adds faces")

	# subdivide edge
	b.set_mode(ShipBuilder.Mode.EDGE)
	var e: Vector2i = b.design.module_edges(1)[0]
	b.sel_edges = [Vector3i(1, mini(e.x, e.y), maxi(e.x, e.y))]
	vcount = b.design.vertices.size()
	b.start_operator("subdivide")
	b.confirm_operator()
	check(b.design.vertices.size() == vcount + 1, "add vertex on edge")

	# connect two vertices sharing a face
	b.set_mode(ShipBuilder.Mode.VERTEX)
	var f: PackedInt32Array = (b.design.modules[1]["fs"] as FaceSet).face(0)
	if f.size() >= 4:
		b.sel_verts = [f[0], f[2]]
		var edges_before := b.design.module_edges(1).size()
		b.connect_vertices()
		check(b.design.module_edges(1).size() >= edges_before, "connect vertices")

	# link
	b.set_mode(ShipBuilder.Mode.VERTEX)
	var a_id: int = b.design.module_vertex_ids(0)[0]
	var c_id: int = b.design.module_vertex_ids(2)[0]
	var vn := b.design.vertices.size()
	b.sel_verts = [a_id, c_id]
	b.link_vertices()
	check(b.design.vertices.size() == vn - 1, "link merges two vertices")

	# undo / redo
	var json_now := b.design.to_json()
	b.undo()
	check(b.design.to_json() != json_now, "undo changes design")
	b.redo()
	check(b.design.vertices.size() == vn - 1, "redo restores design (vertex count)")

	# mirror / duplicate / delete (object mode)
	b.set_mode(ShipBuilder.Mode.OBJECT)
	var mn := b.design.modules.size()
	b.sel_modules = [1]
	b.duplicate_selection()
	b.tool.confirm()
	check(b.design.modules.size() == mn + 1, "duplicate")
	b.undo()
	b.sel_modules = [1]
	b.start_operator("mirror")
	b.set_operator_param("axis", 1)
	b.confirm_operator()
	check(b.design.modules.size() == mn + 1 and b.design.module_centroid(mn).y < 0.0 and absf(b.design.module_centroid(mn).x - b.design.module_centroid(1).x) < 0.001, "mirror across the Y plane")
	b.undo()
	b.sel_modules = [1]
	b.duplicate_selection()
	b.tool.confirm()
	b.delete_selection()
	check(b.design.modules.size() == mn, "delete")

	# numeric move
	b.sel_modules = [0]
	var c0 := b.affected_center()
	b.move_selection_center_to(c0 + Vector3(1, 0, 0))
	check(b.affected_center().distance_to(c0 + Vector3(1, 0, 0)) < 0.001, "move by centre fields")

	# thruster props
	b.active_module = 2
	b.set_active_main_stat(123000.0)
	b.set_thruster_direction(Vector3(0, 0, 1))
	check(is_equal_approx(b.design.stat(2, "thrust_per_m3"), 123000.0), "thruster thrust per m3 editable")
	check(is_equal_approx(b.design.thruster_power(2), 123000.0 * b.design.module_volume(2)), "thrust = per-m3 x volume")
	b.set_active_preset("ion")
	check(b.design.stat(2, "heat_per_n") < 3.0, "preset switch replaces the stats")
	b.set_active_main_stat(900000.0)
	check(b.design.stat(2, "elec_per_n") > 25.0 and b.design.stat(2, "heat_per_n") > 1.5, "more thrust per m3 costs electricity and heat")
	check(ShipDesign.from_json(b.design.to_pretty_json()).stat(2, "thrust_per_m3") == 900000.0, "stats survive save/load")
	# minimum size: people must fit inside
	var tiny := b.design.add_module(ModuleCatalog.COMMANDER, "box", Vector3(0, 5, 0), Vector3(0.3, 0.3, 0.3))
	check(not b.design.validate().filter(func(msg: String): return "too small" in msg).is_empty(), "too small commander is refused")
	b.design.remove_module(tiny)

	# readable JSON
	var pretty := b.design.to_pretty_json()
	check(pretty.count("\n") > 20, "pretty JSON has line breaks (%d lines)" % pretty.count("\n"))
	check(ShipDesign.from_json(pretty) != null, "pretty JSON parses back")

	# ---- new editor tools -------------------------------------------------------------------
	var nb: ShipBuilder = b
	nb.new_ship()
	# bevel an edge of the hull box: stays a closed container, loses a little volume
	var hull_i := 0
	var vol0 := nb.design.module_volume(hull_i)
	var edge := nb.design.module_edges(hull_i)[0]
	nb.set_mode(ShipBuilder.Mode.EDGE)
	nb.sel_edges = [Vector3i(hull_i, edge.x, edge.y)]
	nb.start_operator("bevel")
	nb.set_operator_param("width", 0.1)
	nb.confirm_operator()
	check(nb.design.count_open_edges(hull_i) == 0, "bevel keeps the hull closed")
	var used := {}
	for mi_ in nb.design.modules.size():
		for id_ in nb.design.module_vertex_ids(mi_):
			used[id_] = true
	check(used.size() == nb.design.vertices.size(), "bevel leaves no unused vertex behind (%d vertices, %d used)" % [nb.design.vertices.size(), used.size()])
	check(nb.design.module_volume(hull_i) < vol0 and nb.design.module_volume(hull_i) > vol0 * 0.9, "bevel removes a sliver of volume (%.3f -> %.3f)" % [vol0, nb.design.module_volume(hull_i)])
	nb.sel_edges = [Vector3i(hull_i, edge.x, edge.y)]
	var e2 := nb.design.module_edges(hull_i)[3]
	nb.sel_edges = [Vector3i(hull_i, e2.x, e2.y)]
	nb.start_operator("bevel")
	nb.set_operator_param("segments", 2)
	nb.confirm_operator()
	check(nb.design.count_open_edges(hull_i) == 0, "rounded (2 segments) edge keeps the hull closed")

	# create faces -> loose -> cannot save -> make module
	nb.new_ship()
	var base_v := nb.design.vertices.size()
	var pts := [Vector3(5, 0, 0), Vector3(6, 0, 0), Vector3(5, 1, 0), Vector3(5, 0, 1)]
	for p3 in pts:
		nb.design.vertices.append(p3)
	var quad_faces := [[0, 1, 2], [0, 1, 3], [0, 2, 3], [1, 2, 3]]   # a tetrahedron
	nb.set_mode(ShipBuilder.Mode.VERTEX)
	for qf in quad_faces:
		nb.sel_verts = [base_v + qf[0], base_v + qf[1], base_v + qf[2]]
		nb.create_face()
	check(nb.design.loose_face_count() == 4, "4 loose faces created")
	check(not nb.design.validate().is_empty(), "loose faces block saving")
	var loose_i := nb.design.loose_module()
	nb.set_mode(ShipBuilder.Mode.FACE)
	nb.sel_faces = []
	for fi in 4:
		nb.sel_faces.append(Vector2i(loose_i, fi))
	nb.new_module_type = ModuleCatalog.ARMOR
	nb.make_module()
	check(nb.design.loose_module() < 0, "loose group disappears once all faces are in a module")
	var tet := nb.design.modules.size() - 1
	check(nb.design.modules[tet]["type"] == ModuleCatalog.ARMOR and nb.design.count_open_edges(tet) == 0 and nb.design.module_volume(tet) > 0.01, "faces became a closed armor module")
	check(not nb.design.validate().is_empty(), "...but it floats unconnected, so still not savable: %s" % str(nb.design.validate()[0]))

	# turret + barrel link
	nb.new_ship()
	var tb := nb.design.add_module(ModuleCatalog.TURRET, "dome", Vector3(0, 0.45, 0.4), Vector3(0.2, 0.2, 0.2))
	var br := nb.design.add_module(ModuleCatalog.BARREL, "cylinder", Vector3(0, 0.5, 0.0), Vector3(0.06, 0.06, 0.4))
	check(not nb.design.turret_errors().is_empty(), "unlinked barrel is reported")
	nb.set_mode(ShipBuilder.Mode.OBJECT)
	nb.sel_modules = [tb, br]
	nb.link_turret_barrel()
	check(nb.design.barrels_of(tb) == [br] and nb.design.turret_errors().is_empty(), "turret + barrel linked")
	var br2 := nb.design.add_module(ModuleCatalog.BARREL, "cylinder", Vector3(0.3, 0.5, 0.0), Vector3(0.06, 0.06, 0.4))
	nb.sel_modules = [tb, br2]
	nb.link_turret_barrel()
	check(nb.design.barrels_of(tb).size() == 2, "a turret base can have several barrels")
	nb.sel_modules = [nb.design.modules.size() - 1]
	nb.active_module = tb
	nb.set_turret_value("yaw_max", 100.0)
	check(is_equal_approx(float(nb.design.extra(tb, "yaw_max")), 100.0), "arc limit editable")

	# every premade ship loads and validates
	for s in ShipDesign.list_ships():
		var sd := ShipDesign.load_file(s["path"])
		check(sd != null and sd.validate().is_empty(), "ship file %s" % s["name"])

	print("RESULT: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)
