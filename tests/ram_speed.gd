extends Node
## Ram at different speeds: godot --headless --fixed-fps 60 --path . res://tests/ram_speed.tscn -- 20 60 150
func mk(nm: String, pos: Vector3) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/Dart.json")
	s.name = nm
	s.position = pos
	add_child(s)
	return s

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var speed := float(a)
		var target := mk("1", Vector3.ZERO)
		var rammer := mk("2", Vector3(-40, 0, 0))
		rammer.rotation = Vector3(0, -PI / 2.0, 0)   # nose (-Z) toward +X
		rammer.linear_velocity = Vector3(speed, 0, 0)
		var v0 := target.design.vertices.duplicate()
		var v1 := rammer.design.vertices.duplicate()
		var hp_t := 0.0
		var hit_count := [0]
		var on_hit := func(_s, _h, _r): hit_count[0] += 1
		BusEvent.ship_hit.connect(on_hit)
		var frames := int((80.0 / speed + 2.0) * 60.0)
		var passed := false
		for i in frames:
			await get_tree().physics_frame
			if rammer.position.x > 10.0:
				passed = true
		var moved_t := 0.0
		for i in v0.size(): moved_t += (target.design.vertices[i] - v0[i]).length()
		var moved_r := 0.0
		for i in v1.size(): moved_r += (rammer.design.vertices[i] - v1[i]).length()
		for h in target.module_hp: hp_t += h
		var hp_r := 0.0
		for h in rammer.module_hp: hp_r += h
		var maxt := 0.0
		for h in target.module_max_hp: maxt += h
		print("speed %5.0f: hits=%d  passed_through=%s  target dent=%.2f hp=%.0f/%.0f  rammer dent=%.2f hp=%.0f  target.x=%.1f" % [speed, hit_count[0], passed, moved_t, hp_t, maxt, moved_r, hp_r, target.position.x])
		BusEvent.ship_hit.disconnect(on_hit)
		target.free(); rammer.free()
		await get_tree().physics_frame
	get_tree().quit()
