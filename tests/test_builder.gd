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
	b.extrude()
	check(b.tool.is_active(), "extrude starts a grab")
	b.tool.confirm()
	check(b.design.vertices.size() > vcount, "extrude adds vertices")
	check((b.design.modules[mi]["fs"] as FaceSet).alive_count() > mcount, "extrude adds faces")

	# subdivide edge
	b.set_mode(ShipBuilder.Mode.EDGE)
	var e: Vector2i = b.design.module_edges(1)[0]
	b.sel_edges = [Vector3i(1, mini(e.x, e.y), maxi(e.x, e.y))]
	vcount = b.design.vertices.size()
	b.add_vertex_on_edge()
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
	b.delete_selection()
	check(b.design.modules.size() == mn, "delete")

	# numeric move
	b.sel_modules = [0]
	var c0 := b.affected_center()
	b.move_selection_center_to(c0 + Vector3(1, 0, 0))
	check(b.affected_center().distance_to(c0 + Vector3(1, 0, 0)) < 0.001, "move by centre fields")

	# thruster props
	b.active_module = 2
	b.set_thruster_power(1234.0)
	b.set_thruster_direction(Vector3(0, 0, 1))
	check(is_equal_approx(b.design.modules[2]["power"], 1234.0), "thruster power")

	# readable JSON
	var pretty := b.design.to_pretty_json()
	check(pretty.count("\n") > 20, "pretty JSON has line breaks (%d lines)" % pretty.count("\n"))
	check(ShipDesign.from_json(pretty) != null, "pretty JSON parses back")

	# every premade ship loads and validates
	for s in ShipDesign.list_ships():
		var sd := ShipDesign.load_file(s["path"])
		check(sd != null and sd.validate().is_empty(), "ship file %s" % s["name"])

	print("RESULT: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)
