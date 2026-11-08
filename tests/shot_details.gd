extends Node
## Screenshot: a ship with finish + hand-placed details (shader check). SHOT_OUT=/path.png SHOT_SHIP=res://ships/Dart.json
func _ready() -> void:
	var d := ShipDesign.load_file(OS.get_environment("SHOT_SHIP") if OS.get_environment("SHOT_SHIP") != "" else "res://ships/Dart.json")
	var t0 := Time.get_ticks_msec()
	if OS.get_environment("AUTO") != "0":
		var n := AutoPaint.apply(d, {"style": int(OS.get_environment("STYLE")) if OS.get_environment("STYLE") != "" else 0})
		print("auto paint: ", n, " details in ", Time.get_ticks_msec() - t0, " ms")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.02, 0.05)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.4, 0.45, 0.55)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	add_child(sun)
	var hull := HullRenderer.new()
	hull.shader = load("res://shaders/hull.gdshader")
	add_child(hull)
	hull.attach(d, HullRenderer.prepare(d))
	hull.flush()
	var cam := Camera3D.new()
	add_child(cam)
	var c := Vector3.ZERO
	for v in d.vertices:
		c += v
	c /= maxf(d.vertices.size(), 1)
	var dir := Vector3(1, 0.6, 1.2)
	if OS.get_environment("CAMDIR") != "":
		var p := OS.get_environment("CAMDIR").split(",")
		dir = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var f := float(OS.get_environment("CAMF")) if OS.get_environment("CAMF") != "" else 0.9
	if OS.get_environment("CAMAT") != "":
		var q := OS.get_environment("CAMAT").split(",")
		c = Vector3(float(q[0]), float(q[1]), float(q[2]))
	cam.far = 20000.0
	cam.position = c + dir.normalized() * d.extent_length() * f
	cam.look_at(c)
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
