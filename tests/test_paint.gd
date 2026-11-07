extends Node
## Paint: colours + patterns per module, saved with the ship, used by the renderer.
##   godot --headless --path . res://tests/test_paint.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	var d := ShipDesign.from_blob(ShipDesign.read_blob("res://ships/Brick.json"))
	var type_col := ModuleCatalog.color_of(d.modules[0]["type"])
	check(d.module_color(0) == type_col, "an unpainted module has the colour of its type")
	d.set_paint(0, Color(0.2, 0.4, 0.8), Color(1, 1, 0), 3, 0.5)
	check(d.module_color(0).is_equal_approx(Color(0.2, 0.4, 0.8)), "painted colour is used")
	var d2 := ShipDesign.from_blob(d.to_blob())
	check(d2.module_color(0).is_equal_approx(Color(0.2, 0.4, 0.8)) and d2.module_color2(0).is_equal_approx(Color(1, 1, 0)) and int(d2.extra(0, "pat")) == 3, "paint survives save and load")
	check(d2.module_color(1) == ModuleCatalog.color_of(d2.modules[1]["type"]), "other modules keep their colour")
	d2.clear_paint(0)
	check(d2.module_color(0) == type_col, "clearing the paint brings the type colour back")
	# the builder paints the selection
	var b: ShipBuilder = load("res://scenes/ship_builder.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(0.6).timeout
	b.paint_c1 = Color(1, 0, 0)
	b.paint_modules([0, 1])
	check(b.design.module_color(1).is_equal_approx(Color(1, 0, 0)), "the builder paints several modules at once")
	b.undo()
	check(not b.design.module_color(1).is_equal_approx(Color(1, 0, 0)), "paint can be undone")
	b.set_paint_mode(true)
	check(b.paint_mode, "paint mode switches on")
	check(b.find_child("PaintSection", true, false) != null, "the paint section is in the properties tab")
	# a ship in the game gets the shader values + the direction marks
	var ship: Ship = load("res://scenes/ship.tscn").instantiate()
	ship.design_blob = d.to_blob()
	add_child(ship)
	for i in 6: await get_tree().physics_frame
	var found := false
	var marks := 0
	for n in ship.find_children("*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		if m != null:
			if (m.get_shader_parameter("pattern") as int) == 3:
				found = true
			if (m.get_shader_parameter("mark_axis") as Vector3) != Vector3.ZERO:
				marks += 1
	check(found, "the hull shader got the pattern")
	check(marks > 0, "thrusters / barrels / turrets carry a direction mark (%d meshes)" % marks)
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
