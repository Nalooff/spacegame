extends Node
## Screenshots of the tactical map in 2D and 3D: xvfb-run -a -s "-screen 0 1600x900x24" godot --path . res://tests/shot_tactical.tscn
func _ready() -> void:
	var cam := Camera3D.new(); cam.far = 6000.0; add_child(cam)
	var world := Node3D.new(); world.name = "World"; world.add_to_group("world"); add_child(world)
	var lm := Node3D.new(); lm.name = "Landmarks"; world.add_child(lm)
	for i in 6:
		var m := MeshInstance3D.new(); m.mesh = SphereMesh.new(); m.name = "Rock%02d" % i
		m.scale = Vector3.ONE * (20.0 + i * 12.0)
		lm.add_child(m); m.global_position = Vector3(-300 + i * 130, -80 + i * 55, -250 - i * 40)
	var pool := ProjectilePool.new(); pool.name = "ProjectilePool"; add_child(pool)
	var me: Ship = load("res://scenes/ship.tscn").instantiate()
	me.design_blob = ShipDesign.read_blob("res://ships/Brick.json"); me.name = "1"; me.pilot_name = "Brick"
	add_child(me)
	var foe: Ship = load("res://scenes/ship.tscn").instantiate()
	foe.design_blob = ShipDesign.read_blob("res://ships/Dart.json"); foe.name = "2"; foe.pilot_name = "Dart"
	foe.position = Vector3(60, 90, -420)
	add_child(foe)
	Data.local_ship = me
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child(hud)
	foe.linear_velocity = Vector3(-14, 4, 6)
	for i in 20: await get_tree().physics_frame
	me.detection.scan()
	me.detection.cycle_lock()
	for i in 5:
		pool.spawn_shot(me.global_position + Vector3(i * 6, 2, -20), Vector3(0, 0, -260), me, 10.0)
		pool.spawn_shot(foe.global_position + Vector3(-i * 6, -3, 20), Vector3(0, -4, 200), foe, 10.0)
	me.autopilot.drive_to(foe.global_position, 0.7, foe, true)
	me.linear_velocity = Vector3(8, 1, -20)
	var map: TacticalMap = hud.get_node("HudRoot/TacticalMap")
	map.open()
	map._scale = 0.5
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/img/9_map_2d.png"))
	map.set_view3d(true)
	map._yaw = 0.5
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/img/10_map_3d.png"))
	get_tree().quit()
