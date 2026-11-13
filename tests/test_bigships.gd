extends Node
## Every premade capital ship: spawns, shoots, rams, and is not slow. Reports frame spikes.
##   godot --headless --path . res://tests/test_bigships.tscn
var fails := 0
var pool: ProjectilePool
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1

func _ship(file: String, pos: Vector3, nm: String = "") -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/" + file)
	s.name = nm if nm != "" else str(randi())
	s.position = pos
	add_child(s)
	return s

func _active() -> int:
	var n := 0
	for c in pool.get_children():
		if c is Projectile and (c as Projectile).active: n += 1
	return n

## Runs n physics frames; returns the slowest one in ms.
func _frames(n: int) -> float:
	var worst := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		await get_tree().physics_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	return worst

func _ready() -> void:
	pool = ProjectilePool.new(); pool.name = "ProjectilePool"; add_child(pool)
	var cam := Camera3D.new(); cam.far = 60000.0; add_child(cam); cam.make_current()
	await get_tree().process_frame
	for f in ["Dreadnought.ship", "Spearhead.ship", "Hammerhead.ship", "Nautilus.ship"]:
		print("== ", f)
		var t0 := Time.get_ticks_msec()
		var a := _ship(f, Vector3.ZERO)
		var tgt := _ship("Brick.json", Vector3(0, 0, -900))
		var worst := await _frames(30)
		print("   spawn+30 frames: %d ms, worst frame %.0f ms" % [Time.get_ticks_msec() - t0, worst])
		check(a.alive and a.design.modules.size() > 50, "%s alive, %d modules" % [f, a.design.modules.size()])
		check(worst < 2500.0, "no multi-second freeze on spawn")
		# --- shooting
		var shots := 0
		var wf := 0.0
		for k in 200:
			a.weapons.try_fire(tgt.global_position, 1.0)
			wf = maxf(wf, await _frames(1))
			shots = maxi(shots, _active())
		check(shots > 0, "fires bullets at a target 900 m ahead (max %d in flight, worst frame %.0f ms)" % [shots, wf])
		check(wf < 400.0, "firing does not stall the game (%.0f ms)" % wf)
		a.queue_free(); tgt.queue_free()
		await _frames(int(OS.get_environment("GAP")) if OS.get_environment("GAP") != "" else 5)
	# --- ramming: Hammerhead into Nautilus
	print("== ram Hammerhead -> Nautilus")
	var h := _ship("Hammerhead.ship", Vector3.ZERO, "H")
	var n := _ship("Nautilus.ship", Vector3(0, 0, -600), "N")
	await _frames(20)
	h.global_position = Vector3.ZERO
	n.global_position = Vector3(0, 0, -420)
	h.linear_velocity = Vector3(0, 0, -40)
	var rw := 0.0
	var tot := 0.0
	for i in 600:
		var t1 := Time.get_ticks_usec()
		await get_tree().physics_frame
		var d := (Time.get_ticks_usec() - t1) / 1000.0
		rw = maxf(rw, d); tot += d
	check(rw < 1500.0, "ram: worst frame %.0f ms (avg %.1f)" % [rw, tot / 600.0])
	check(h.is_inside_tree() and n.is_inside_tree(), "both ships survive the ram without crashing")
	print("FAILS: %d" % fails)
	get_tree().quit(fails)
