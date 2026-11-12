extends Node
## Screenshot of a ship in 3D (paint + direction marks). SHOT_OUT=/path.png
func _ready() -> void:
	var path := OS.get_environment("SHIP") if OS.get_environment("SHIP") != "" else "res://ships/Brick.json"
	var d := ShipDesign.from_blob(ShipDesign.read_blob(path))
	if OS.get_environment("SHIP") == "":
		d.set_paint(0, Color(0.15, 0.3, 0.7), Color(0.95, 0.8, 0.1), 3, 1.2)
	var ship: Ship = load("res://scenes/ship.tscn").instantiate()
	ship.design_blob = d.to_blob()
	add_child(ship)
	var cam := Camera3D.new()
	cam.far = 20000.0
	add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.6)
	add_child(env)
	await get_tree().create_timer(1.0).timeout
	var c := Vector3.ZERO
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for mi in d.modules.size():
		for p in d.module_points(mi):
			lo = lo.min(p)
			hi = hi.max(p)
	c = (lo + hi) * 0.5
	var r := maxf((hi - lo).length(), 10.0)
	cam.current = true
	cam.global_position = ship.global_position + c + (Vector3(OS.get_environment("DIR").get_slice(",", 0).to_float(), OS.get_environment("DIR").get_slice(",", 1).to_float(), OS.get_environment("DIR").get_slice(",", 2).to_float()) if OS.get_environment("DIR") != "" else Vector3(0.8, 0.6, 1.0)).normalized() * r * float(OS.get_environment("ZOOM") if OS.get_environment("ZOOM") != "" else "1.3")
	cam.look_at(ship.global_position + c)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
