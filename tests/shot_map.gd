extends Node
## Screenshot: commander-mode Brick auto-fires at a moving Dart (tracers, lock marker, lead marker, HUD).
## xvfb-run godot --path . res://tests/shot_combat.tscn   (see tools/shots.sh)
func _ready() -> void:
	var cam := Camera3D.new(); cam.far = 6000.0; add_child(cam)
	var light := DirectionalLight3D.new(); light.rotation = Vector3(-0.8, 0.6, 0); add_child(light)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.02, 0.025, 0.05)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.5, 0.5, 0.6)
	add_child(env)
	var pool := ProjectilePool.new(); pool.name = "ProjectilePool"; add_child(pool)
	var me: Ship = load("res://scenes/ship.tscn").instantiate()
	me.design_blob = ShipDesign.read_blob("res://ships/Brick.json"); me.name = "1"; me.pilot_name = "Brick"
	add_child(me)
	var foe: Ship = load("res://scenes/ship.tscn").instantiate()
	foe.design_blob = ShipDesign.read_blob("res://ships/Dart.json"); foe.name = "2"; foe.pilot_name = "Dart"
	foe.position = Vector3(40, 10, -420)
	add_child(foe)
	Data.local_ship = me
	var hud: Node = load("res://scenes/hud.tscn").instantiate()
	add_child(hud)
	var crew := OS.get_environment("SHOT_CREW") != ""
	me.stations.mode = "crew" if crew else "commander"
	if crew:
		me.stations.go_to(2)
	foe.linear_velocity = Vector3(-14, 0, 6)
	foe.freeze = false
	for i in 20: await get_tree().physics_frame
	if crew:      # first person at a gun station, the real StationCamera
		cam.set_script(load("res://scripts/world/station_camera.gd"))
		cam._captured = false
		await get_tree().create_timer(3.0).timeout
		me.detection.cycle_lock()
	else:
		cam.position = Vector3(12, 9, 26)
		cam.look_at(Vector3(10, 4, -200))
		cam.make_current()
	await get_tree().create_timer(1.6).timeout
	me.autopilot.drive_to(Vector3(150, 20, -300), 0.7, null, true)
	me.linear_velocity = Vector3(8, 1, -20)
	hud.get_node("HudRoot/TacticalMap").open()
	await get_tree().create_timer(1.0).timeout
