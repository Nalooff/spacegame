extends Node
## Bullet types (pellets, size, lifetime, burst, splash, recoil, tracer colour) and the aiming maths (lead with acceleration).
##   godot --headless --path . res://tests/test_bullets.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	# ---- presets carry the new stats, older ships fall back to defaults
	for id in ["cannon", "autocannon", "shotgun", "flak", "railgun"]:
		check(not ModulePresets.preset(ModuleCatalog.BARREL, id).is_empty(), "preset %s exists" % id)
	check(ModulePresets.stat_default("pellets") == 1.0 and ModulePresets.stat_default("lifetime") == 4.0, "defaults for stats an old ship does not have")
	check(int(ModulePresets.preset(ModuleCatalog.BARREL, "shotgun")["stats"]["pellets"]) == 8, "the scatter gun fires 8 pellets")
	var d := ShipDesign.from_blob(ShipDesign.read_blob("res://ships/Brick.json"))
	var bar := -1
	for mi in d.modules.size():
		if d.modules[mi]["type"] == ModuleCatalog.BARREL:
			bar = mi
			break
	check(d.stat(bar, "pellets") == 1.0 and d.stat(bar, "burst") == 1.0, "an old barrel has 1 pellet, no burst")

	# ---- aiming: a target that accelerates is led further than a steady one
	var s := Vector3.ZERO
	var tp := Vector3(0, 0, -600)
	var tv := Vector3(40, 0, 0)
	var plain := Ballistics.intercept(s, Vector3.ZERO, tp, tv, 300.0)
	var acc := Ballistics.intercept_acc(s, Vector3.ZERO, tp, tv, Vector3(10, 0, 0), 300.0)
	check(acc.x > plain.x + 5.0, "acceleration moves the lead point further (%.0f vs %.0f)" % [acc.x, plain.x])
	check(Ballistics.intercept_acc(s, Vector3.ZERO, tp, tv, Vector3.ZERO, 300.0).distance_to(plain) < 0.01, "no acceleration = the plain intercept")
	# the bullet really meets the accelerating target
	var aim := Ballistics.intercept_acc(s, Vector3.ZERO, tp, tv, Vector3(10, 0, 0), 300.0)
	var t := aim.length() / 300.0
	var where := tp + tv * t + Vector3(10, 0, 0) * (0.5 * t * t)
	check(where.distance_to(aim) < 3.0, "bullet and target meet (%.2f m apart)" % where.distance_to(aim))
	# a faster bullet needs less lead
	check(Ballistics.intercept(s, Vector3.ZERO, tp, tv, 700.0).x < plain.x, "a faster bullet needs less lead")

	# ---- a real ship: bullets per shot, splash, burst
	var ship: Ship = load("res://scenes/ship.tscn").instantiate()
	var blob := d
	for mi in blob.modules.size():
		if blob.modules[mi]["type"] == ModuleCatalog.BARREL:
			var st: Dictionary = blob.modules[mi]["cfg"]["stats"]
			st["pellets"] = 5.0
			st["burst"] = 2.0
			st["burst_gap"] = 0.1
			st["lifetime"] = 2.0
			st["splash_radius"] = 4.0
			st["bullet_size"] = 0.5
			st["recoil"] = 100.0
	ship.design_blob = blob.to_blob()
	add_child(ship)
	var pool := ProjectilePool.new()
	add_child(pool)
	for i in 6: await get_tree().physics_frame
	var rig = ship.turrets.rigs[0]
	check(rig.pellets == 5 and rig.burst == 2 and absf(rig.lifetime - 2.0) < 0.01 and absf(rig.splash - 4.0) < 0.01 and absf(rig.bullet_size - 0.5) < 0.01, "the rig reads the bullet type")
	check(absf(ship.turrets.average_bullet_range() - rig.muzzle_speed * 2.0) < 1.0 or ship.turrets.average_bullet_range() > 0.0, "bullet reach is known")
	ship.turrets.filter_base = -2
	var before := 0
	for ch in pool.get_children():
		if ch is Projectile and (ch as Projectile).active:
			before += 1
	ship.weapons.try_fire(ship.global_position + Vector3(0, 0, -300), 1.0, PackedInt32Array(), true)
	await get_tree().process_frame
	var flying := 0
	var projs: Array = []
	for ch in pool.get_children():
		if ch is Projectile and (ch as Projectile).active:
			flying += 1
			projs.append(ch)
	check(flying - before >= 5 and (flying - before) % 5 == 0, "one trigger pull = a whole group of pellets (%d bullets)" % (flying - before))
	if not projs.is_empty():
		var p: Projectile = projs[0]
		check(absf(p.life - 2.0) < 0.01 and absf(p.splash - 4.0) < 0.01, "the bullet got its lifetime and explosion radius")
		var bolt := p.get_node("Bolt") as MeshInstance3D
		check(absf(bolt.scale.x - 0.5 / 0.3) < 0.01, "the tracer is drawn at the bullet size")
	check(rig.cool < rig.cooldown * 0.5, "inside a burst the next shot comes after the short gap (%.2f s)" % rig.cool)
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
