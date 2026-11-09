extends Node
## Generates ships/Dreadnought.ship: a ~2.25 km capital ship, built with the same ShipDesign API the builder uses.
##   godot --headless --path . res://tools/gen_dreadnought.tscn
## Bow = -Z, stern = +Z, up = +Y. Everything overlaps its neighbours so the whole ship is one connected structure.
var d := ShipDesign.new()
const H := ModuleCatalog.HULL
const A := ModuleCatalog.ARMOR


func box(type: String, c: Vector3, h: Vector3, preset: String = "") -> int:
	return d.add_module(type, "box", c, h, 12, preset)


func cyl(type: String, c: Vector3, r: float, half_len: float, axis: Vector3, preset: String = "", seg: int = 12) -> int:
	var b := Basis.IDENTITY
	if absf(axis.z) > 0.5:
		b = Basis(Vector3.RIGHT, PI * 0.5)
	elif absf(axis.x) > 0.5:
		b = Basis(Vector3.BACK, PI * 0.5)
	return d.add_module(type, "cylinder", c, Vector3(r, half_len, r), seg, preset, b)


func thruster(c: Vector3, r: float, half_len: float, push: Vector3, preset: String = "chemical") -> int:
	var mi := cyl(ModuleCatalog.THRUSTER, c, r, half_len, push, preset)
	d.modules[mi]["dir"] = push.normalized()
	return mi


## A turret base (dome) with `n` barrels pointing along `fwd` (+-Z). Returns the base module.
func turret(c: Vector3, r: float, preset_barrel: String, n: int, barrel_r: float, barrel_len: float, fwd: float = -1.0, mount: String = "heavy") -> int:
	var tb := d.add_module(ModuleCatalog.TURRET, "dome", c, Vector3(r, r * 0.8, r), 10, mount)
	d.modules[tb]["dir"] = Vector3.UP
	var ids: Array = []
	for i in n:
		var off := (float(i) - (n - 1) * 0.5) * (barrel_r * 2.0 + r * 0.5) if n > 1 else 0.0
		var bc := c + Vector3(off, r * 0.25, fwd * barrel_len * 0.3)
		var bi := cyl(ModuleCatalog.BARREL, bc, barrel_r, barrel_len * 0.5, Vector3(0, 0, 1), preset_barrel, 8)
		ids.append(bi)
	d.modules[tb]["cfg"]["barrels"] = ids
	return tb


func build() -> void:
	d.ship_name = "Dreadnought"
	d.gyro_scale = 1.0
	# ---- hull
	box(H, Vector3(0, 0, 0), Vector3(115, 75, 650))
	box(H, Vector3(0, 10, 790), Vector3(140, 95, 160))
	box(H, Vector3(0, -5, -760), Vector3(95, 65, 130))
	var pyr := d.add_module(H, "pyramid", Vector3(0, -5, -1020), Vector3(95, 130, 65), 12, "", Basis(Vector3.RIGHT, -PI * 0.5))
	box(H, Vector3(0, -95, 100), Vector3(60, 25, 700))
	# ---- armor
	for sx in [-1.0, 1.0]:
		box(A, Vector3(sx * 125.0, 0, -50), Vector3(10, 60, 600))
		box(A, Vector3(sx * 103.0, 0, -760), Vector3(8, 55, 120))
		box(A, Vector3(sx * 148.0, 0, 800), Vector3(8, 70, 130))
	box(A, Vector3(0, 82, -150), Vector3(105, 7, 520), "composite")
	box(A, Vector3(0, 106, 790), Vector3(130, 6, 140))
	# ---- sponsons (hangars): airlocks + pod bays + retro thrusters
	for sx in [-1.0, 1.0]:
		box(H, Vector3(sx * 190.0, -20, 300), Vector3(55, 45, 180))
		box(ModuleCatalog.AIRLOCK, Vector3(sx * 251.0, -20, 250), Vector3(6, 14, 14), "standard")
		box(ModuleCatalog.AIRLOCK, Vector3(sx * 251.0, -20, 350), Vector3(6, 14, 14), "standard")
		box(ModuleCatalog.POD_BAY, Vector3(sx * 252.0, -20, 440), Vector3(7, 8, 14), "standard")
		thruster(Vector3(sx * 190.0, -20, 90), 22.0, 30.0, Vector3(0, 0, 1))
	# ---- command tower
	box(H, Vector3(0, 110, 330), Vector3(80, 35, 170))
	box(H, Vector3(0, 175, 350), Vector3(55, 30, 120))
	box(H, Vector3(0, 230, 360), Vector3(40, 25, 70))
	box(ModuleCatalog.COMMANDER, Vector3(0, 277, 350), Vector3(45, 22, 45), "bridge")
	box(ModuleCatalog.COMMANDER, Vector3(0, 100, -300), Vector3(25, 12, 40), "cockpit")      # forward conn
	# backup command posts: an armoured citadel deep in the hull, an aft engineering bridge, two flag-bridge wings
	box(ModuleCatalog.COMMANDER, Vector3(0, -10, 150), Vector3(30, 25, 40), "cockpit")
	box(ModuleCatalog.COMMANDER, Vector3(0, 25, 890), Vector3(30, 20, 30), "cockpit")
	for sx in [-1.0, 1.0]:
		box(ModuleCatalog.COMMANDER, Vector3(sx * 62.0, 175, 350), Vector3(16, 14, 28), "cockpit")
	d.add_module(ModuleCatalog.RADAR, "dome", Vector3(0, 299, 350), Vector3(16, 14, 16), 10, "electronic")
	d.add_module(ModuleCatalog.RADAR, "dome", Vector3(0, 105, -330), Vector3(10, 8, 10), 10, "electronic")
	for sx in [-1.0, 1.0]:
		d.add_module(ModuleCatalog.ANTENNA, "cone", Vector3(sx * 30.0, 313, 330), Vector3(10, 16, 10), 10, "dish")
	d.add_module(ModuleCatalog.ANTENNA, "cylinder", Vector3(0, 340, 370), Vector3(1.5, 45, 1.5), 8, "whip")
	box(ModuleCatalog.ENGINE_ROOM, Vector3(0, 0, 800), Vector3(40, 40, 40), "control")
	# ---- main engines
	for sx in [-1.0, 1.0]:
		for y in [55.0, -30.0]:
			thruster(Vector3(sx * 70.0, y, 1015), 38.0, 70.0, Vector3(0, 0, -1))
	# ---- manoeuvring thrusters (RCS): on every flank, top and bottom
	for z in [-760.0, -400.0, 0.0, 700.0]:
		var face_x := 111.0 if z < -600.0 else (135.0 if z < 600.0 else 156.0)
		thruster(Vector3(-(face_x + 18.0), 0, z), 14.0, 20.0, Vector3(1, 0, 0))      # left flank pushes right
		thruster(Vector3(face_x + 18.0, 0, z), 14.0, 20.0, Vector3(-1, 0, 0))
	for z in [-520.0, 700.0]:
		for sx in [-1.0, 1.0]:
			thruster(Vector3(sx * 95.0, 105.0 if z < 0.0 else 128.0, z), 14.0, 18.0, Vector3(0, -1, 0))
			thruster(Vector3(sx * 90.0, -95, z), 14.0, 20.0, Vector3(0, 1, 0))
	# ---- main battery: 6 twin heavy cannons
	for sx in [-1.0, 1.0]:
		turret(Vector3(sx * 40.0, 86, -520), 22.0, "cannon", 2, 2.2, 100.0)
		turret(Vector3(sx * 95.0, 86, -330), 22.0, "cannon", 2, 2.2, 100.0)
		turret(Vector3(sx * 60.0, 109, 790), 22.0, "cannon", 2, 2.2, 100.0, 1.0)
	# ---- secondary battery: twin autocannons on the hangar roofs and flanks
	for sx in [-1.0, 1.0]:
		for z in [230.0, 370.0]:
			turret(Vector3(sx * 190.0, 22, z), 9.0, "autocannon", 2, 0.8, 32.0, -1.0, "light")
		turret(Vector3(sx * 100.0, 86, -80), 9.0, "autocannon", 2, 0.8, 32.0, -1.0, "light")
		turret(Vector3(sx * 100.0, 86, 100), 9.0, "autocannon", 2, 0.8, 32.0, 1.0, "light")
	# ---- point defence: single flak guns along the top edges
	var spots := [[-640.0, 0], [-440.0, 1], [-200.0, 0], [20.0, 1], [330.0, 0], [640.0, 1]]
	for sx in [-1.0, 1.0]:
		for s in spots:
			turret(Vector3(sx * (100.0 if s[1] == 0 else 80.0), 86, s[0]), 5.0, "flak", 1, 0.5, 14.0, -1.0 if s[0] < 100.0 else 1.0, "light")


func _ready() -> void:
	build()
	var errs := d.validate()
	errs.append_array(d.turret_errors())
	print("modules: ", d.modules.size(), "  vertices: ", d.vertices.size(), "  length: ", d.extent_length(), " m")
	for e in errs:
		var parts: PackedStringArray = e.split(" ")
		var extra := ""
		if parts.size() > 1 and parts[0] == "Module" and parts[1].is_valid_int():
			extra = "  at " + str(d.module_centroid(int(parts[1])).snapped(Vector3.ONE))
		print("PROBLEM: ", e.left(90), extra)
	if OS.get_environment("NO_PAINT") == "":
		var t0 := Time.get_ticks_msec()
		var n := AutoPaint.apply(d, {"style": 0, "seed": 7, "density": 1.0, "wear": 0.35})
		print("auto paint: ", n, " details in ", Time.get_ticks_msec() - t0, " ms")
	if OS.get_environment("SAVE") != "":
		var err := d.save_premade()
		print("saved: ", error_string(err))
	get_tree().quit()
