extends Node
## Screenshot of a map. MAP=id LOOK=x,y,z SHIP=res://ships/X CAMD=distance SHOT_OUT=file.png
func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	world.add_child(WorldEnvironment.new())
	world.get_child(0).name = "WorldEnvironment"
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	world.add_child(sun)
	var lm := Node3D.new()
	lm.name = "Landmarks"
	world.add_child(lm)
	var sp := Node3D.new()
	sp.name = "SpawnPoints"
	world.add_child(sp)
	for i in 8:
		var m := Marker3D.new()
		var a := i / 8.0 * TAU
		var map := MapCatalog.get_map(OS.get_environment("MAP"))
		m.position = Vector3(cos(a), 0, sin(a)) * float(map["spawn_radius"])
		sp.add_child(m)
	WorldBuilder.build(world, MapCatalog.get_map(OS.get_environment("MAP")))
	var look := Vector3(0, 0, -1)
	if OS.get_environment("LOOK") != "":
		var p := OS.get_environment("LOOK").split(",")
		look = Vector3(float(p[0]), float(p[1]), float(p[2])).normalized()
	var ship_path := OS.get_environment("SHIP") if OS.get_environment("SHIP") != "" else "res://ships/Dart.json"
	var d := ShipDesign.load_file(ship_path)
	var hull := HullRenderer.new()
	hull.shader = load("res://shaders/hull.gdshader")
	var ship_root := Node3D.new()
	world.add_child(ship_root)
	ship_root.add_child(hull)
	hull.attach(d, HullRenderer.prepare(d))
	hull.flush()
	var c := Vector3.ZERO
	for v in d.vertices:
		c += v
	c /= maxf(d.vertices.size(), 1)
	ship_root.position = -c
	var cam := Camera3D.new()
	cam.far = 30000.0
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 70.0
	world.add_child(cam)
	var dist := float(OS.get_environment("CAMD")) if OS.get_environment("CAMD") != "" else 40.0
	var side := look.cross(Vector3.UP).normalized()
	cam.position = -look * dist + Vector3.UP * dist * 0.25 + side * dist * 0.2
	cam.look_at(cam.position + look * 100.0 + Vector3.UP * 5.0)
	await get_tree().create_timer(2.5).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
