extends Node
## How long do hits take? godot --headless --path . res://tests/bench_hits.tscn
func _ready() -> void:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/Brick.json")
	add_child(s)
	for i in 10: await get_tree().physics_frame
	var n := s.design.modules.size()
	print("vertices at start: %d" % s.design.vertices.size())
	for kind in [&"kinetic", &"explosive"]:
		var t0 := Time.get_ticks_usec()
		for i in 300:
			var mi := i % n
			s.apply_hit(DamageHit.weapon(kind, mi, 2.0, s.global_position, null, Vector3.FORWARD))
		print("%s: %.3f ms per hit (%d modules), vertices now %d" % [kind, (Time.get_ticks_usec() - t0) / 300000.0, n, s.design.vertices.size()])
	var t2 := Time.get_ticks_usec()
	for i in 300: s.hazards.on_hit(s, i % n, 5.0)
	print("hazards.on_hit: %.3f ms" % ((Time.get_ticks_usec() - t2) / 300000.0))
	t2 = Time.get_ticks_usec()
	for i in 300: s.crew.on_hit(s, i % n, 5.0)
	print("crew.on_hit: %.3f ms" % ((Time.get_ticks_usec() - t2) / 300000.0))
	t2 = Time.get_ticks_usec()
	for i in 300: s.apply_damage(i % n, 1.0)
	print("apply_damage: %.3f ms" % ((Time.get_ticks_usec() - t2) / 300000.0))
	t2 = Time.get_ticks_usec()
	for i in 300: s._update_function()
	print("_update_function: %.3f ms" % ((Time.get_ticks_usec() - t2) / 300000.0))
	var t1 := Time.get_ticks_usec()
	for i in 60:
		await get_tree().physics_frame
	print("idle physics frame: %.3f ms" % ((Time.get_ticks_usec() - t1) / 60000.0))
	get_tree().quit()
