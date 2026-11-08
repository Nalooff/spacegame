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
	check(int(ModulePresets.preset(ModuleCatalog.BARREL, "shotgun")["stats"]["pellets"]) == 8, "the scatter gun fires 10 pellets")
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
	# ---- penetration: a piercing bullet damages every module on its way
	var tgt: Ship = load("res://scenes/ship.tscn").instantiate()
	tgt.design_blob = ShipDesign.read_blob("res://ships/Brick.json")
	tgt.position = Vector3(500, 0, 0)
	add_child(tgt)
	for i in 6: await get_tree().physics_frame
	var hp0 := tgt.module_hp.duplicate()
	for pierce in [0.0, 30.0]:
		for i in tgt.module_hp.size():
			tgt.module_hp[i] = hp0[i]
		pool.spawn_shot(tgt.global_position + Vector3(0, 0, 60), Vector3(0, 0, -300), ship, 50.0, &"piercing", 0.2, 4.0, 0.0, 0.5, pierce)
		for i in 40: await get_tree().physics_frame
		var hurt := 0
		for i in tgt.module_hp.size():
			if tgt.module_hp[i] < hp0[i]:
				hurt += 1
		print("pierce %.0f: %d module(s) damaged" % [pierce, hurt])
		if pierce == 0.0:
			check(hurt <= 1, "a bullet without penetration stops in the first module")
		else:
			check(hurt >= 2, "a piercing bullet damages several modules")
	# ---- what the guns aim at: a visible target -> the chosen module, a radar-only contact -> the heat / electric centre
	var det: ShipDetection = ship.detection
	det.scan()
	check(not det.contacts.is_empty(), "the shooter sees the target ship")
	if not det.contacts.is_empty():
		var cc: Dictionary = det.contacts[0]
		check(bool(cc["visible"]) and (cc["aim_off"] as Vector3).length() < 0.01, "visible, no module chosen: aim at the ship as a whole")
		det.locked = tgt
		det.cycle_module()
		check(det.target_module >= 0, "J cycles to a module (%s)" % det.target_module_name())
		det.scan()
		var c2: Dictionary = det.find_contact(tgt)
		var want: Vector3 = tgt.global_transform.basis * (tgt.design.module_centroid(det.target_module) - tgt._com)
		check((c2["aim_off"] as Vector3).distance_to(want) < 0.01, "the aim point moves to that module")
		det.locked = null
		check(det.target_module == -1, "unlocking forgets the module")
	# far away (radar only): the heat centre, and the module choice is ignored
	tgt.sig_heat_pt = Vector3(0, 0, 8)
	tgt.global_position = ship.global_position + Vector3(0, 0, -Data.VIEW_RANGE - 300)
	det._radars.clear()
	det._radars.append({"module": 0, "kind": "thermal", "range": 1.0e6, "precision": 0.8})
	tgt.sig_heat = 1.0e7
	det.scan()
	var c3: Dictionary = det.find_contact(tgt)
	check(not c3.is_empty() and not bool(c3["visible"]), "far target seen by radar only")
	if not c3.is_empty():
		var off: Vector3 = c3["aim_off"]
		check(off.distance_to(tgt.global_transform.basis * (Vector3(0, 0, 8) - tgt._com)) < 0.01, "radar only: the guns aim at the average heat point")
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
