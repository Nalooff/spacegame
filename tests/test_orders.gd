extends Node
## Arrival facing + braking without turning round; the click menus are built.
##   godot --headless --path . res://tests/test_orders.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ship(path: String) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob(path)
	add_child(s)
	return s


func _ready() -> void:
	var dread := _ship("res://ships/Dreadnought.ship")
	for i in 20: await get_tree().physics_frame
	var ap := dread.autopilot
	check(ap._no_flip, "the Dreadnought has retro thrust: it brakes without turning round (retro %.3f of %.3f m/s2)" % [ap._a_retro, ap._a_eff])
	var fwd: Vector3 = dread.global_basis * dread.alloc.u_best
	dread.linear_velocity = fwd * 8.0
	ap.go_to(dread.global_position + fwd * 500.0, true)
	var worst := 0.0
	var minv := 8.0
	for i in 60 * 70:
		await get_tree().physics_frame
		var f: Vector3 = dread.global_basis * dread.alloc.u_best
		worst = maxf(worst, f.angle_to(fwd))
		minv = minf(minv, dread.linear_velocity.length())
	check(rad_to_deg(worst) < 12.0, "it slowed from 8 m/s to %.2f m/s turning at most %.1f degrees (no pirouette)" % [minv, rad_to_deg(worst)])
	check(minv < 6.0, "...and it really did brake")
	dread.queue_free()
	# a nimble ship ends up facing the asked direction
	var dart := _ship("res://ships/Dart.json")
	for i in 20: await get_tree().physics_frame
	var face := Vector3.RIGHT
	dart.autopilot.go_to(dart.global_position + Vector3(0, 0, -80), true, face)
	for i in 60 * 40: await get_tree().physics_frame
	check(dart.autopilot.facing_ok, "the Dart arrives and faces the wanted heading (error %.1f deg, speed %.2f)" % [rad_to_deg((dart.global_basis * dart.alloc.u_best).angle_to(face)), dart.linear_velocity.length()])
	# menus
	var menu := ShipMenu.new()
	add_child(menu)
	var own := menu.own_ship_entries(dart, null)
	check(own.size() >= 5 and own[0].has("sub"), "the ship menu has %d entries, Move first" % own.size())
	var other := _ship("res://ships/Brick.json")
	var ce := menu.contact_entries(dart, other)
	check(ce.size() >= 6, "the contact menu has %d entries" % ce.size())
	for e in ce:
		if e.get("label", "") == "Target and open fire":
			e["do"].call()
	check(dart.weapons_free and dart.detection.locked == other, "'Target and open fire' locks it and frees the weapons")
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
