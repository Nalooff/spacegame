extends Node
func _ready() -> void:
	var pool := ProjectilePool.new()
	add_child(pool)
	var a := Ship.new()
	var rng := RandomNumberGenerator.new()
	for i in 250:
		pool.spawn_shot(Vector3(rng.randf_range(-30, 30), rng.randf_range(-30, 30), rng.randf_range(0, 400)), Vector3(rng.randf_range(-20, 20), 0, 900), null if i < 125 else a, 30.0, &"kinetic", 0.3, 4.0, 0.0, 0.1, 0.0, 0.4)
	await get_tree().physics_frame
	var t := Time.get_ticks_usec()
	for i in 10:
		pool._physics_process(0.016)
	print("pool._physics_process (250 bullets of ONE shooter) ", (Time.get_ticks_usec() - t) / 10000.0, " ms")
	get_tree().quit()
