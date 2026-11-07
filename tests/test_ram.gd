extends Node
## Ramming: a hard hit lodges the ships in each other (no bounce) and leaves a hole.
##   godot --headless --path . res://tests/test_ram.tscn
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


func _ready() -> void:
	var a := _ship("A")
	var b := _ship("B")
	for i in 10: await get_tree().physics_frame
	var ext: Vector3 = Vector3.ZERO
	for mi in a.design.modules.size():
		ext = ext.max(a.design.module_extent(mi))
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(0, 0, 14.0 + ext.z)
	a.linear_velocity = Vector3(0, 0, 45.0)
	b.linear_velocity = Vector3.ZERO
	for i in 90: await get_tree().physics_frame
	var rel := (a.linear_velocity - b.linear_velocity).length()
	var hurt := false
	for mi in a.module_hp.size():
		if a.module_hp[mi] < a.module_max_hp[mi] - 0.5 or b.module_hp[mi] < b.module_max_hp[mi] - 0.5:
			hurt = true
	check(hurt, "the ram damaged something")
	check(a.lodges.size() + b.lodges.size() > 0, "a hard ram lodges the ships")
	var holes := 0.0
	for v in a.haz_hole: holes += v
	for v in b.haz_hole: holes += v
	check(holes > 0.0, "...and leaves a hole (%.2f)" % holes)
	check(rel < 12.0, "they do not bounce apart (relative speed %.1f m/s)" % rel)
	for i in 1000: await get_tree().physics_frame
	check(a.lodges.is_empty() and b.lodges.is_empty(), "the grip weakens until it lets go")
	print("FAILS: %d" % fails)
	get_tree().quit(fails)
