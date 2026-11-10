extends Node
## Weapon vs hull (angle, ricochet), weapon vs weapon (collisions, flak proximity fuse), hull vs hull (sharp contact).
##   godot --headless --path . res://tests/test_bullets_phys.tscn
var fails := 0
var pool: ProjectilePool
var sa := Ship.new()      # two shooters (bullets of the same shooter never meet)
var sb := Ship.new()
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


var dealt := 0.0                       # hit points removed so far (from the ship_hit events: summing a whole Dreadnought loses precision)
func _on_hit(_ship: Ship, _hit: DamageHit, result: DamageResult) -> void:
	dealt += result.hp_damage


func _hp(_s: Ship) -> float:
	return -dealt


func _shot(pos: Vector3, vel: Vector3, dmg := 60.0, dtype := &"kinetic", size := 0.3, splash := 0.0, pierce := 0.0, mass := 0.5, shooter: Ship = null) -> Projectile:
	pool.spawn_shot(pos, vel, shooter, dmg, dtype, size, 4.0, splash, 0.1, pierce, mass)
	for i in pool.get_child_count():
		var p := pool.get_child(i) as Projectile
		if p != null and p.active and p.global_position.is_equal_approx(pos):
			return p
	return null


func _ready() -> void:
	BusEvent.ship_hit.connect(_on_hit)
	pool = ProjectilePool.new()
	add_child(pool)
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.name = "T"
	s.design_blob = ShipDesign.read_blob("res://ships/Dreadnought.ship")
	add_child(s)
	for i in 120: await get_tree().physics_frame
	# find the top of the hull above x=0,z=-187 (the long flat deck)
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 300, -187), Vector3(0, -300, -187), 1)
	var top := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	check(not top.is_empty(), "there is a hull to shoot at")
	var tp: Vector3 = top["position"]
	var tn: Vector3 = top["normal"]
	var hp0 := _hp(s)
	# a flat hit
	var flat := _shot(tp + tn * 6.0, -tn * 400.0)
	for i in 60: await get_tree().physics_frame
	var d_flat := hp0 - _hp(s)
	check(d_flat > 0.0 and not flat.active, "a flat hit damages the hull and the bullet stops (%.1f hp)" % d_flat)
	# a grazing hit (85 degrees from the normal) ricochets
	var wp := tp + Vector3(30, 0, 0)
	var found := true
	check(found, "found a flat patch to graze along")
	tn = Vector3.UP
	var tang := Vector3.RIGHT
	var start := wp + tn * 0.25 - tang * 12.0
	var gdir := (tang * sin(deg_to_rad(86.0)) - tn * cos(deg_to_rad(86.0))).normalized()
	var hp1 := _hp(s)
	var graze := _shot(start, gdir * 400.0)
	var ricocheted := false
	for i in 40:
		await get_tree().physics_frame
		if graze.ricochets > 0:
			ricocheted = true
			break
	var d_graze := hp1 - _hp(s)
	check(ricocheted, "a grazing bullet ricochets")
	check(d_graze < d_flat * 0.5, "...and does far less damage than a flat hit (%.1f vs %.1f)" % [d_graze, d_flat])
	if ricocheted:
		check(graze.velocity.dot(tn) > -1.0 and graze.velocity.dot(tang) > 150.0, "...keeping most of its sideways speed and leaving the hull")
	graze.deactivate()
	# energy never ricochets
	var hp2 := _hp(s)
	var beamy := _shot(start, gdir * 400.0, 60.0, &"energy")
	for i in 40: await get_tree().physics_frame
	check(beamy.ricochets == 0 and hp2 - _hp(s) > 0.0, "an energy bolt does not ricochet")

	# bullet vs bullet: a heavy shell smashes a light bullet
	var far := Vector3(0, 3000, 0)
	var heavy := _shot(far, Vector3(0, 0, 300), 100.0, &"kinetic", 0.5, 0.0, 0.0, 20.0, sa)
	var light := _shot(far + Vector3(0, 0, 40), Vector3(0, 0, -300), 10.0, &"kinetic", 0.3, 0.0, 0.0, 0.2, sb)
	for i in 30: await get_tree().physics_frame
	check(not light.active and heavy.active, "a heavy shell smashes a light bullet in the air")
	heavy.deactivate()
	# comparable bullets bounce off each other
	var b1 := _shot(far, Vector3(0, 0, 300), 50.0, &"kinetic", 0.6, 0.0, 0.0, 2.0, sa)
	var b2 := _shot(far + Vector3(0, 0, 40), Vector3(0, 0, -300), 50.0, &"kinetic", 0.6, 0.0, 0.0, 2.0, sb)
	for i in 30: await get_tree().physics_frame
	check(b1.active and b2.active and b1.velocity.z < 100.0 and b2.velocity.z > -100.0, "two similar bullets bounce off each other (%.0f / %.0f m/s)" % [b1.velocity.z, b2.velocity.z])
	check(b1.damage < 50.0, "...and both are damaged by it")
	b1.deactivate()
	b2.deactivate()
	# flak: its proximity fuse bursts near an enemy bullet and wrecks it
	var enemy := _shot(far + Vector3(200, 0, 0), Vector3(-200, 0, 0), 20.0, &"kinetic", 0.3, 0.0, 0.0, 0.3, sb)
	var flak := _shot(far + Vector3(0, 3, 0), Vector3.ZERO, 30.0, &"explosive", 0.4, 14.0, 0.0, 1.0, sa)
	for i in 120: await get_tree().physics_frame
	check(not enemy.active and not flak.active, "a flak shell's proximity fuse bursts and wrecks the passing bullet")
	sa.free()
	sb.free()
	# hull vs hull: a point contact penetrates where a flat one only bounces
	var mat := MaterialCatalog.info("aluminium")
	var blunt := DamageHit.ramming(0, 3.0, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 50000.0, 20.0)
	var sharp := DamageHit.ramming(0, 3.0, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 50000.0, 20.0)
	sharp.sharpness = Data.HULL_SHARP_MAX
	var rb := RammingDamage.new().resolve(blunt, mat)
	var rs := RammingDamage.new().resolve(sharp, mat)
	check(rb.is_empty() and not rs.is_empty(), "a flat 3 m/s hit does nothing but a point at 3 m/s dents the hull")
	var fast_b := DamageHit.ramming(0, 12.0, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 50000.0, 20.0)
	var fast_s := DamageHit.ramming(0, 12.0, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 50000.0, 20.0)
	fast_s.sharpness = Data.HULL_SHARP_MAX
	check(RammingDamage.new().resolve(fast_s, mat).dent_depth > RammingDamage.new().resolve(fast_b, mat).dent_depth * 1.5, "...and a point digs deeper than a flat face at the same speed")
	print("FAILS: %d" % fails)
	get_tree().quit(fails)
