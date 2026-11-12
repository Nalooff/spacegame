extends Node
## Bounce: soft hits rebound by material / angle, hard hits do not, glancing hits scrape and spin.
##   godot --headless --path . res://tests/test_bounce.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ship(nm: String) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.name = nm
	s.design_blob = ShipDesign.read_blob("res://ships/Brick.json")
	add_child(s)
	return s


func _extent(s: Ship) -> Vector3:
	var ext := Vector3.ZERO
	for mi in s.design.modules.size():
		ext = ext.max(s.design.module_extent(mi))
	return ext


## Two bricks, A flies at B with velocity `va`; B starts `gap` m ahead (offset sideways by `side`). Returns [a, b, v_rel_before].
func _hit(va: Vector3, side: float) -> Array:
	var a := _ship("A%d" % randi())
	var b := _ship("B%d" % randi())
	for i in 10: await get_tree().physics_frame
	var ext := _extent(a)
	a.global_position = Vector3(1000.0 * randf(), 0, 0) * 0.0
	b.global_position = Vector3(side, 0, 4.0 + ext.z * 2.0)
	a.linear_velocity = va
	b.linear_velocity = Vector3.ZERO
	a.angular_velocity = Vector3.ZERO
	return [a, b]


func _ready() -> void:
	var r1 := await _hit(Vector3(0, 0, 3.0), 0.0)
	var ext_x := _extent(r1[0]).x
	var a: Ship = r1[0]
	var b: Ship = r1[1]
	for i in 420: await get_tree().physics_frame
	var sep := (b.linear_velocity - a.linear_velocity).z
	check(sep > 0.4, "a soft head-on hit bounces them apart (separating at %.2f m/s, closing was 3)" % sep)
	check(sep < 3.0, "...but gives back less than it came in with")
	check(a.lodges.is_empty() and b.lodges.is_empty(), "no lodging at that speed")
	var p0 := a.mass * a.linear_velocity + b.mass * b.linear_velocity
	check(absf(p0.z - a.mass * 3.0) < a.mass * 0.2, "momentum is conserved (%.0f of %.0f)" % [p0.z, a.mass * 3.0])
	a.queue_free()
	b.queue_free()
	await get_tree().physics_frame

	# an off-centre hit also spins the ships
	var r2 := await _hit(Vector3(0, 0, 3.0), ext_x * 1.5)
	var c: Ship = r2[0]
	var d: Ship = r2[1]
	for i in 420: await get_tree().physics_frame
	check(c.angular_velocity.length() + d.angular_velocity.length() > 0.01, "an off-centre hit sets them spinning (%.3f rad/s)" % (c.angular_velocity.length() + d.angular_velocity.length()))
	c.queue_free()
	d.queue_free()
	await get_tree().physics_frame

	# an oblique blow (27 degrees off the line of centres): the sideways speed is mostly kept, the hulls scrape along each other
	var r3 := await _hit(Vector3(1.5, 0, 3.0), 0.0)
	var g: Ship = r3[0]
	var h: Ship = r3[1]
	for i in 420: await get_tree().physics_frame
	var sideways := (g.mass * g.linear_velocity.x + h.mass * h.linear_velocity.x) / g.mass
	check(sideways > 0.6, "the sideways momentum is mostly kept (chaotic: 0.7..1.5) (%.2f of 1.5 m/s)" % sideways)
	check(g.linear_velocity.z < 3.0 and g.linear_velocity.x + h.linear_velocity.x > 0.5, "...while the forward motion is blocked (%.2f m/s)" % g.linear_velocity.z)
	g.queue_free()
	h.queue_free()
	await get_tree().physics_frame

	# a hard ram still lodges and does not bounce
	var r4 := await _hit(Vector3(0, 0, 45.0), 0.0)
	var m: Ship = r4[0]
	var n: Ship = r4[1]
	for i in 90: await get_tree().physics_frame
	check(m.lodges.size() + n.lodges.size() > 0 and (m.linear_velocity - n.linear_velocity).length() < 12.0, "a hard ram lodges and does not bounce")
	print("FAILS: %d" % fails)
	get_tree().quit(fails)
