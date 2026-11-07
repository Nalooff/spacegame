extends Node
## DUEL SIMULATOR: identical ships (the Brick), every barrel replaced by one bullet type, fight a duel at several ranges.
## The guns aim perfectly (lead) and fire all the time; nobody flies. Prints the damage dealt, the winner and the win-rate table.
##   godot --headless --path . res://tests/duel_sim.tscn [-- seconds=20 ranges=150,400,800 types=cannon,autocannon,...]
## Use it to tune ModulePresets (bullet types): a type should win roughly as often as it loses, and each should have a range where it shines.

var types: Array[String] = ["cannon", "autocannon", "shotgun", "ap_cannon", "flak", "railgun"]
var ranges: Array[float] = [150.0, 400.0, 800.0]
var seconds: float = 20.0


func _blob_with(preset: String) -> PackedByteArray:
	var d := ShipDesign.from_blob(ShipDesign.read_blob("res://ships/Brick.json"))
	for mi in d.modules.size():
		if d.modules[mi]["type"] == ModuleCatalog.BARREL:
			d.modules[mi]["cfg"] = ModulePresets.make_cfg(ModuleCatalog.BARREL, preset)
			d.modules[mi]["cfg"]["kind"] = "projectile"
	return d.to_blob()


func _ship(nm: String, preset: String, pos: Vector3) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.name = nm
	s.design_blob = _blob_with(preset)
	s.position = pos
	add_child(s)
	return s


func _hp(s: Ship) -> float:
	var hp := 0.0
	for i in s.module_hp.size():
		hp += maxf(s.module_hp[i], 0.0)
	return hp


func _args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"seconds": seconds = float(kv[1])
			"ranges":
				ranges.clear()
				for r in kv[1].split(","):
					ranges.append(float(r))
			"types":
				types.clear()
				for t in kv[1].split(","):
					types.append(t)


func _duel(ta: String, tb: String, dist: float) -> Dictionary:
	var a := _ship("A", ta, Vector3.ZERO)
	var b := _ship("B", tb, Vector3(0, 0, dist))
	for i in 8:
		await get_tree().physics_frame
	var max_a := _hp(a)
	var max_b := _hp(b)
	var t := 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	while t < seconds and a.alive and b.alive:
		await get_tree().physics_frame
		t += dt
		_shoot(a, b, dt)
		_shoot(b, a, dt)
		for s in [a, b]:       # keep the ships where they are: only the guns are being tested
			s.linear_velocity = Vector3.ZERO
			s.angular_velocity = Vector3.ZERO
	var res := {"a": 1.0 - _hp(b) / maxf(max_b, 1.0), "b": 1.0 - _hp(a) / maxf(max_a, 1.0)}   # damage dealt as a fraction of the enemy's health
	var drain := 0.0                       # let the bullets in flight end before the ships go (they point at their shooter)
	while drain < 6.0:
		await get_tree().physics_frame
		drain += dt
	a.queue_free()
	b.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return res


func _shoot(s: Ship, e: Ship, dt: float) -> void:
	if not s.alive or not e.alive:
		return
	var v := maxf(s.turrets.average_muzzle_speed(), 50.0)
	var aim := Ballistics.intercept(s.global_position, s.linear_velocity, e.global_position, e.linear_velocity, v)
	s.turrets.aim_point = e.global_position + aim if aim.length() < 1.0e6 else e.global_position
	s.turrets.has_aim = true
	s.weapons.try_fire(s.turrets.aim_point, 1.0)
	s.turrets.track(dt)


func _ready() -> void:
	_args()
	Engine.max_fps = 0                  # as fast as the machine can
	Engine.time_scale = 8.0
	Engine.max_physics_steps_per_frame = 16
	var pool := ProjectilePool.new()
	add_child(pool)
	var wins := {}
	var dmg := {}
	for t in types:
		wins[t] = 0.0
		dmg[t] = 0.0
	print("DUEL SIM: %d types, ranges %s, %.0f s each" % [types.size(), str(ranges), seconds])
	for i in types.size():
		for j in range(i + 1, types.size()):
			for r in ranges:
				var res: Dictionary = await _duel(types[i], types[j], r)
				var winner := "draw"
				if res["a"] > res["b"] + 0.02:
					winner = types[i]
					wins[types[i]] += 1.0
				elif res["b"] > res["a"] + 0.02:
					winner = types[j]
					wins[types[j]] += 1.0
				else:
					wins[types[i]] += 0.5
					wins[types[j]] += 0.5
				dmg[types[i]] += res["a"]
				dmg[types[j]] += res["b"]
				print("%-10s vs %-10s at %4.0f m:  %3.0f%% / %3.0f%%  -> %s" % [types[i], types[j], r, res["a"] * 100.0, res["b"] * 100.0, winner])
	print("---- win score per type (win = 1, draw = 0.5), of %d duels each" % ((types.size() - 1) * ranges.size()))
	for t in types:
		print("%-10s %5.1f  (average damage dealt %3.0f%%)" % [t, wins[t], 100.0 * dmg[t] / float((types.size() - 1) * ranges.size())])
	get_tree().quit()
