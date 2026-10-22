extends Node
## Run: godot --headless --fixed-fps 60 res://tests/test_damage.tscn --quit-after 3000
## Rams two ships head-on in different materials / speeds and checks dents, HP and the damage types.
var fails := 0

func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1

func make_ship(json: String, nm: String, pos: Vector3, vel: Vector3, material: String) -> Ship:
	var d: Dictionary = JSON.parse_string(json)
	if material != "":
		for m in d["modules"]:
			m["material"] = material
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_json = JSON.stringify(d)
	s.name = nm
	s.position = pos
	add_child(s)
	s.linear_velocity = vel
	return s

func dent_total(s: Ship, before: PackedVector3Array) -> float:
	var t := 0.0
	for i in before.size():
		t += (s.design.vertices[i] - before[i]).length()
	return t

## Head-on ram along Z. Returns {dent, hp_lost, bounced}
func ram(speed: float, mat_a: String, mat_b: String) -> Dictionary:
	var json := FileAccess.get_file_as_string("res://ships/Brick.json")
	var a := make_ship(json, "1", Vector3(0, 0, 12), Vector3(0, 0, -speed), mat_a)
	var b := make_ship(json, "2", Vector3(0, 0, -12), Vector3.ZERO, mat_b)
	a.rotation = Vector3(0, PI, 0)  # nose toward the other ship (their noses are -Z)
	a.linear_velocity = Vector3(0, 0, -speed)
	var before := b.design.vertices.duplicate()
	var hp_total0 := 0.0
	for h in b.module_hp: hp_total0 += h
	for i in int((24.0 / speed + 3.0) * 60.0):
		await get_tree().physics_frame
	var hp1 := 0.0
	for h in b.module_hp: hp1 += h
	var res := {"dent": dent_total(b, before), "hp_lost": hp_total0 - hp1, "dist": a.global_position.distance_to(b.global_position),
		"b_speed": b.linear_velocity.length()}
	a.free(); b.free()
	await get_tree().physics_frame
	return res

func _ready() -> void:
	# ---- pure damage-type maths
	var kin := DamageRegistry.get_type(&"kinetic")
	var steel := MaterialCatalog.info("steel"); var alu := MaterialCatalog.info("aluminium")
	var hit := DamageHit.kinetic(0, 25.0)
	check(kin.resolve(hit, steel).hp_damage < kin.resolve(hit, alu).hp_damage, "bullets do less to steel than aluminium")
	check(kin.resolve(hit, alu).dent_depth == 0.0, "bullets never dent")
	var rm := DamageRegistry.get_type(&"ramming") as RammingDamage
	var slow := DamageHit.ramming(0, 2.0, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 4000.0, 80.0)
	check(rm.resolve(slow, steel).is_empty(), "2 m/s into steel: nothing")
	var fast := DamageHit.ramming(0, 20.0, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 4000.0, 80.0)
	var r_steel := rm.resolve(fast, steel)
	var r_bronze := rm.resolve(fast, MaterialCatalog.info("bronze"))
	check(r_steel.dent_depth > 0.0 and r_bronze.dent_depth > r_steel.dent_depth, "steel dents less than bronze (%.2f < %.2f)" % [r_steel.dent_depth, r_bronze.dent_depth])
	check(DamageRegistry.get_type(&"nope") == null, "unknown type -> null")

	# ---- full ship collisions
	var slow_r := await ram(1.5, "aluminium", "aluminium")
	print("slow:", slow_r)
	check(slow_r["dent"] < 0.0001 and slow_r["hp_lost"] < 0.01, "slow bump: no dent, no damage")
	check(slow_r["b_speed"] > 0.05 or slow_r["dist"] > 4.0, "slow bump: ships are pushed apart by physics")
	var fast_alu := await ram(18.0, "aluminium", "aluminium")
	print("fast alu:", fast_alu)
	check(fast_alu["dent"] > 0.02 and fast_alu["hp_lost"] > 0.0, "fast ram: aluminium dents and loses HP")
	var mid_steel := await ram(9.0, "steel", "steel")
	print("mid steel:", mid_steel)
	check(mid_steel["dent"] < 0.0001, "9 m/s steel on steel: no dent")
	var mid_bronze := await ram(9.0, "bronze", "bronze")
	print("mid bronze:", mid_bronze)
	check(mid_bronze["dent"] > 0.01, "9 m/s bronze on bronze: dents")
	print("RESULT: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)
