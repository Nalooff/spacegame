extends Node
## Barrel direction + muzzle tube: a barrel fires where ITS direction says, nothing may stand in the tube in front of it.
##   godot --headless --path . res://tests/test_barrel_dir.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	for ship_name in ["Brick", "Dart", "Scrap Hauler", "Twin Hull"]:
		var d := ShipDesign.from_blob(ShipDesign.read_blob("res://ships/%s.json" % ship_name))
		var errs := d.barrel_tube_errors()
		check(errs.is_empty(), "%s: no module blocks a barrel tube %s" % [ship_name, str(errs)])
		var bars := []
		for mi in d.modules.size():
			if d.modules[mi]["type"] == ModuleCatalog.BARREL:
				bars.append(mi)
		if bars.is_empty():
			continue
		var bar: int = bars[0]
		var tb := d.turret_of(bar)
		check(tb >= 0, "%s: barrel %d knows its turret (%d)" % [ship_name, bar, tb])
		# old files: no chosen direction = base -> barrel
		var old := d.barrel_dir(bar)
		check(old.distance_to((d.module_centroid(bar) - d.module_centroid(tb)).normalized()) < 0.001, "%s: unset direction = base to barrel" % ship_name)
		# choose a direction: the rig fires that way
		d.modules[bar]["dir"] = Vector3(1, 0, 0)
		d.modules[bar]["aim_set"] = 1.0
		check(d.barrel_dir(bar).distance_to(Vector3(1, 0, 0)) < 0.001, "%s: chosen direction is used" % ship_name)
		var z := ExhaustZone.barrel_zone(d, bar)
		check((z["axis"] as Vector3).distance_to(Vector3(1, 0, 0)) < 0.001 and float(z["length"]) == Data.BARREL_TUBE_LENGTH, "%s: tube runs along the barrel direction" % ship_name)
		# a module put in the tube is reported
		var inside: Vector3 = (z["origin"] as Vector3) + (z["axis"] as Vector3) * 1.0
		check(ExhaustZone.contains(z, inside), "%s: a point 1 m in front of the muzzle is in the tube" % ship_name)
		check(not ExhaustZone.contains(z, inside + (z["u"] as Vector3) * 3.0), "%s: ...and one 3 m to the side is not" % ship_name)
		# save and load keeps it
		var d2 := ShipDesign.from_blob(d.to_blob())
		check(d2.barrel_dir(bar).distance_to(Vector3(1, 0, 0)) < 0.001, "%s: the chosen direction survives save and load" % ship_name)
	# the turret itself fires along the chosen barrel direction
	var d3 := ShipDesign.from_blob(ShipDesign.read_blob("res://ships/Brick.json"))
	var b3 := -1
	for mi in d3.modules.size():
		if d3.modules[mi]["type"] == ModuleCatalog.BARREL:
			b3 = mi
			break
	d3.modules[b3]["dir"] = Vector3(0, 0, 1)
	d3.modules[b3]["aim_set"] = 1.0
	var ship: Ship = load("res://scenes/ship.tscn").instantiate()
	ship.design_blob = d3.to_blob()
	add_child(ship)
	for i in 5: await get_tree().physics_frame
	var rig = null
	for r in ship.turrets.rigs:
		if r.barrel == b3:
			rig = r
	check(rig != null, "the ship has a rig for the barrel")
	if rig != null:
		var aim: Vector3 = ship.turrets.direction(rig, 0.0, rig.rest_pitch)
		check(aim.distance_to(Vector3(0, 0, 1)) < 0.05, "rest aim follows the barrel direction (%s)" % str(aim))
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
