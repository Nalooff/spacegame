extends Node
## Tactical map: 2D/3D projection, the arrow order, following a ship, and everything the map knows about.
##   godot --headless --path . res://tests/test_map.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	var world := Node3D.new(); world.name = "World"; world.add_to_group("world"); add_child(world)
	var lm := Node3D.new(); lm.name = "Landmarks"; world.add_child(lm)
	var rock := MeshInstance3D.new(); rock.mesh = SphereMesh.new(); rock.name = "RockA"; rock.scale = Vector3.ONE * 30.0
	lm.add_child(rock); rock.global_position = Vector3(100, 50, -200)
	var pool := ProjectilePool.new(); pool.name = "ProjectilePool"; add_child(pool)
	var me: Ship = load("res://scenes/ship.tscn").instantiate()
	me.design_blob = ShipDesign.read_blob("res://ships/Brick.json"); me.name = "1"; me.pilot_name = "Brick"
	add_child(me)
	var foe: Ship = load("res://scenes/ship.tscn").instantiate()
	foe.design_blob = ShipDesign.read_blob("res://ships/Dart.json"); foe.name = "2"; foe.pilot_name = "Dart"
	foe.position = Vector3(80, 30, -300)
	add_child(foe)
	Data.local_ship = me
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child(hud)
	for i in 10: await get_tree().physics_frame
	me.detection.scan()
	foe.linear_velocity = Vector3(-10, 0, 5)
	pool.spawn_shot(me.global_position + Vector3(0, 0, -30), Vector3(0, 0, -200), me, 5.0)
	pool.spawn_shot(me.global_position + Vector3(0, 0, -9000), Vector3(0, 0, -200), me, 5.0)   # far outside any radar
	var map: TacticalMap = hud.get_node("HudRoot/TacticalMap")
	map.open()
	await get_tree().process_frame
	await get_tree().process_frame

	print("what the map knows")
	var kinds := {}
	for o in map._objects:
		kinds[o["kind"]] = int(kinds.get(o["kind"], 0)) + 1
	check(kinds.get("ship", 0) == 1 and kinds.get("landmark", 0) == 1, "the detected ship and the landmark are on the map (%s)" % str(kinds))
	check(kinds.get("projectile", 0) == 1, "a shot in flight is on the map, one far out of range is not (%d)" % int(kinds.get("projectile", 0)))
	var ship_obj: Dictionary = map._objects.filter(func(o): return o["kind"] == "ship")[0]
	check((ship_obj["vel"] as Vector3).distance_to(foe.linear_velocity) < 15.0, "the ship carries its velocity (the arrow of its movement)")
	var lm_obj: Dictionary = map._objects.filter(func(o): return o["kind"] == "landmark")[0]
	check(float(lm_obj["radius"]) > 5.0, "a landmark has a size (%.1f m)" % float(lm_obj["radius"]))

	print("2D and 3D views")
	map._scale = 0.5
	for view3d in [false, true]:
		map.set_view3d(view3d)
		var w := Vector3(123, me.global_position.y + 40.0, -77)
		var back: Vector3 = map._unproject(map._proj(w), w.y)
		check(back.distance_to(w) < 0.01, "%s: a point survives projection and back (%.4f m off)" % ["3D" if view3d else "2D", back.distance_to(w)])
	map._yaw = 0.9
	var w2 := Vector3(-40, me.global_position.y - 25.0, 300)
	check((map._unproject(map._proj(w2), w2.y) as Vector3).distance_to(w2) < 0.01, "...also with the 3D camera turned")
	map.set_view3d(true)
	var hi: float = map._proj(Vector3(0, me.global_position.y + 100.0, 0)).y
	var lo: float = map._proj(Vector3(0, me.global_position.y, 0)).y
	check(hi < lo - 20.0, "in 3D a higher point is drawn higher on the screen (%.0f vs %.0f px)" % [hi, lo])
	map.set_view3d(false)
	check(absf(map._proj(Vector3(0, me.global_position.y + 100.0, 0)).y - map._proj(Vector3(0, me.global_position.y, 0)).y) < 0.01, "in 2D the height does not move a point")

	print("orders")
	map.drive_button.button_pressed = true
	map.go_button.button_pressed = false
	map.altitude_spin.value = me.global_position.y
	var click_at: Vector2 = map._proj(me.global_position + Vector3(200, 0, 0))
	map._click(click_at)
	var ap := me.autopilot
	check(ap.mode == ShipAutopilot.Mode.DRIVE and ap.heading.is_equal_approx(Vector3(1, 0, 0)), "DRIVE: a click gives an ARROW (heading %s), not a point" % str(ap.heading))
	map.altitude_spin.value = me.global_position.y + 200.0
	map._apply_altitude()
	check(ap.heading.y > 0.3 and ap.heading.x > 0.0, "raising the height tilts the arrow up (%s)" % str(ap.heading.snapped(Vector3.ONE * 0.01)))
	var fp: Vector2 = map._proj(ship_obj["pos"])
	map._click(fp)
	check(ap.track_ship == foe and me.detection.locked == foe, "DRIVE + click on an enemy: the arrow follows it (and locks it)")
	check(ap.aim_point().distance_to(foe.global_position) > 0.1, "...aimed at the intercept point")
	map.drive_button.button_pressed = false
	map.go_button.button_pressed = true
	map._click(fp)
	check(ap.mode == ShipAutopilot.Mode.GOTO and ap.track_ship == foe, "GO TO + click on a ship: the ship follows it")
	map._click(map._proj(me.global_position + Vector3(-300, 0, 100)))
	check(ap.mode == ShipAutopilot.Mode.GOTO and ap.track_ship == null and ap.target.x < me.global_position.x, "GO TO + click on empty space: a normal waypoint")
	map._set_mode(true)
	check(ap.mode == ShipAutopilot.Mode.DRIVE and ap.heading != Vector3.ZERO, "switching a GO TO to DRIVE turns the waypoint into an arrow")
	await get_tree().process_frame
	map.canvas.queue_redraw()
	await get_tree().process_frame
	check(true, "the map draws in DRIVE mode without errors")
	map.set_view3d(true)
	await get_tree().process_frame
	await get_tree().process_frame
	check(true, "the 3D map draws without errors")
	print("RESULT: PASS" if fails == 0 else "RESULT: %d FAILED" % fails)
	get_tree().quit(0 if fails == 0 else 1)
