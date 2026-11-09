extends Node
## Detail layer + finish + auto paint: data, saving, builder tools, rendering in a ship.
##   godot --headless --path . res://tests/test_details.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	var d := ShipDesign.from_blob(ShipDesign.read_blob("res://ships/Brick.json"))
	d.finish = {}
	d.clear_details()                # the premade ships are painted now; a ship without any details must still work
	check(d.details.is_empty() and d.finish.is_empty(), "a ship without details has the default finish")
	var dt := DetailCatalog.make(DetailCatalog.WINDOW, Vector3(1, 2, 3), Vector3(0, 0, 1), 2.0, 0.5)
	dt["c"] = Color(0.2, 0.4, 0.6)
	d.add_detail(dt)
	var tx := DetailCatalog.make(DetailCatalog.TEXT, Vector3(0, 1, 0), Vector3(1, 0, 0))
	tx["t"] = "HELLO"
	d.add_detail(tx)
	d.set_finish("wear", 0.7)
	for blob in [d.to_blob(), d.to_bytes(), d.to_pretty_json().to_utf8_buffer()]:
		var r := ShipDesign.from_blob(blob)
		check(r.details.size() == 2 and r.details[0]["k"] == DetailCatalog.WINDOW and (r.details[0]["p"] as Vector3).is_equal_approx(Vector3(1, 2, 3)), "details survive saving (%s)" % ("binary" if ShipDesign.is_binary(blob) else "json"))
		check(r.details[1]["t"] == "HELLO" and is_equal_approx(r.finish_value("wear"), 0.7), "text and finish survive")
		check((r.details[0]["c"] as Color).is_equal_approx(Color(0.2, 0.4, 0.6)), "colour survives")
	# hostile data is cleaned
	var bad := DetailCatalog.unpack([999, INF, 0, 0, 0, 0, 0, 0, -5, 1e9, 0, 0, 0, 7, -9, 0])
	check(bad["k"] == DetailCatalog.KIND_COUNT - 1 and (bad["p"] as Vector3).is_finite() and bad["w"] >= 0.01 and bad["h"] <= 400.0 and bad["g"] <= 1.0, "bad detail data is clamped")
	# module removal keeps references right
	var e := ShipDesign.from_blob(ShipDesign.read_blob("res://ships/Brick.json"))
	e.clear_details()
	var a := DetailCatalog.make(DetailCatalog.LIGHT, Vector3.ZERO, Vector3.UP)
	a["m"] = 3
	var f := DetailCatalog.make(DetailCatalog.LIGHT, Vector3.ZERO, Vector3.UP)
	f["m"] = 1
	e.add_detail(a)
	e.add_detail(f)
	e.remove_module(1)
	check(e.details[0]["m"] == 2 and e.details[1]["m"] == -1, "removing a module renumbers / frees its details")
	# auto paint: same seed = same result, replaces only its own work, keeps the player's
	var g := ShipDesign.from_blob(ShipDesign.read_blob("res://ships/Dart.json"))
	g.add_detail(DetailCatalog.make(DetailCatalog.STAR, Vector3.ZERO, Vector3.UP))
	var n1 := AutoPaint.apply(g, {"seed": 5})
	var snap := g.to_json()
	AutoPaint.apply(g, {"seed": 5})
	check(n1 > 20 and g.to_json() == snap, "auto paint adds %d details and repeats exactly with the same seed" % n1)
	check(g.details[0]["k"] == DetailCatalog.STAR and not g.details[0]["auto"], "the player's own detail is kept")
	var kinds := {}
	for x in g.details:
		kinds[x["k"]] = true
	check(kinds.has(DetailCatalog.WINDOW) and kinds.has(DetailCatalog.LIGHT) and kinds.has(DetailCatalog.TEXT), "windows, lights and text were made (%d kinds)" % kinds.size())
	check(g.finish_value("panels") > 0.1 and g.finish_value("rivets") > 0.5, "auto paint sets plate lines and rivets")
	g.clear_details(true)
	check(g.details.size() == 1, "'Clear automatic' removes only auto details")
	# decals never hang over the edge of their surface
	var hang := 0
	for x in g.details:
		var m: int = x["m"]
		if m < 0 or DetailCatalog.is_solid(x["k"]):
			continue
		var tf := PackedInt32Array()
		var probe := x.duplicate()
		if not DetailFit.fit(probe, g.module_tris(m, tf)) or probe["w"] < x["w"] * 0.999 or probe["h"] < x["h"] * 0.999:
			hang += 1
	check(hang == 0, "every auto detail lies fully on its surface (%d overhang)" % hang)
	var big := DetailCatalog.make(DetailCatalog.TEXT, g.module_centroid(0), Vector3.UP, 1.0)
	big["w"] = 5000.0
	big["h"] = 3000.0
	big["m"] = 0
	var tf0 := PackedInt32Array()
	var tris0 := g.module_tris(0, tf0)
	var topn := Vector3.UP
	var hit_p := Vector3.ZERO
	for i in range(0, tris0.size(), 3):
		var nn := (tris0[i + 1] - tris0[i]).cross(tris0[i + 2] - tris0[i]).normalized()
		if nn.dot(topn) > 0.99:
			hit_p = (tris0[i] + tris0[i + 1] + tris0[i + 2]) / 3.0
			break
	big["p"] = hit_p
	check(not DetailFit.fit(big, tris0) or big["w"] < 5000.0, "a huge text is shrunk or refused, not left hanging off the ship")
	# builder: place, select, edit, delete, undo
	var b: ShipBuilder = load("res://scenes/ship_builder.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(0.6).timeout
	check(b.find_child("AutoPaintButton", true, false) != null and b.find_child("DetailKind", true, false) != null and b.find_child("Finish_wear", true, false) != null, "auto paint, details and finish are in the properties tab")
	var before := b.design.details.size()
	b.auto_paint({"seed": 2})
	check(b.design.details.size() > before, "the builder's Auto paint button works")
	b.undo()
	check(b.design.details.size() == before, "auto paint can be undone")
	b.set_detail_mode(true)
	b.set_detail_kind(DetailCatalog.HATCH)
	var vp := get_viewport().get_visible_rect().size
	var placed := false
	for i in 20:                      # find a pixel on the ship
		var hit := b.pick_surface(vp * Vector2(0.35 + i * 0.015, 0.5))
		if not hit.is_empty():
			b.detail_click(vp * Vector2(0.35 + i * 0.015, 0.5), false)
			placed = true
			break
	check(placed and b.design.details.size() == before + 1 and b.detail_sel >= 0, "clicking the hull places a detail")
	if placed:
		b.edit_detail("a", 1.0)
		check(is_equal_approx(b.design.details[b.detail_sel]["a"], 1.0), "the selected detail can be edited")
		b.delete_detail()
		check(b.design.details.size() == before, "and deleted")
	# a ship in the game draws them
	var s2 := ShipDesign.from_blob(ShipDesign.read_blob("res://ships/Dart.json"))
	AutoPaint.apply(s2, {})
	var ship: Ship = load("res://scenes/ship.tscn").instantiate()
	ship.design_blob = s2.to_blob()
	add_child(ship)
	for i in 8: await get_tree().physics_frame
	var det := ship.find_child("Details", true, false) as DetailRenderer
	check(det != null and det.get_child_count() > 0, "the game ship draws its detail meshes")
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
