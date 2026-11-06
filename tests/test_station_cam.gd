extends Node
## Gun-station camera: an upside-down (or buried) turret must still put the eye OUTSIDE the hull.
##   godot --headless --path . res://tests/test_station_cam.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	for ship_name in ["Brick", "Dart", "Scrap Hauler", "Twin Hull"]:
		var ship: Ship = load("res://scenes/ship.tscn").instantiate()
		ship.design_blob = ShipDesign.read_blob("res://ships/%s.json" % ship_name)
		add_child(ship)
		await get_tree().physics_frame
		var d := ship.design
		var turrets := []
		for mi in d.modules.size():
			if d.modules[mi]["type"] == ModuleCatalog.TURRET and not d.barrels_of(mi).is_empty():
				turrets.append(mi)
		for mi in turrets:
			var orig: Vector3 = d.modules[mi]["dir"]
			for flip in [orig, -orig, Vector3.DOWN, Vector3.UP]:
				d.modules[mi]["dir"] = flip
				ship.stations.rebuild()
				var st := {}
				for s in ship.stations.stations:
					if s["kind"] == "gun" and int(s["module"]) == mi:
						st = s
				if st.is_empty():
					continue
				var eye: Vector3 = st["pos"]
				var naive := ship.stations._eye_above(d, mi, flip)
				var got := ShipStations.eye_blockage(d, mi, eye, (eye - d.module_centroid(mi)).normalized())
				var bad := ShipStations.eye_blockage(d, mi, naive, flip.normalized())
				check(got <= bad, "%s turret %d dir %s: eye blockage %.0f <= naive %.0f" % [ship_name, mi, str(flip), got, bad])
		ship.queue_free()
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
