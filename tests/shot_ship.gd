extends Node
## Screenshot of the chunked hull before/after a dent (needs a display: xvfb-run godot --path . res://tests/shot_ship.tscn)
func _ready() -> void:
	var cam := Camera3D.new(); add_child(cam)
	var light := DirectionalLight3D.new(); light.rotation = Vector3(-0.8, 0.6, 0); add_child(light)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.05, 0.06, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.5, 0.5, 0.6)
	add_child(env)
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/Brick.json"); s.name = "1"
	add_child(s)
	s.freeze = true
	cam.position = Vector3(7, 5, 9); cam.look_at(Vector3.ZERO)
	for i in 5: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/shot_before.png")
	# dent the first module from the +X side
	var ids := s.design.module_vertex_ids(0)
	var best := Vector3(-1e9, 0, 0)
	for id in ids: if s.design.vertices[id].x > best.x: best = s.design.vertices[id]
	s.apply_dent(0, best, Vector3(-1, 0, 0), 0.6, 1.2)
	s.apply_dent(0, best + Vector3(0, 0.5, 0.4), Vector3(-1, 0, 0), 0.5, 1.0)
	for i in 5: await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("/tmp/shot_after.png")
	print("verts now ", s.design.vertices.size())
	get_tree().quit()
