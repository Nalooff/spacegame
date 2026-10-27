extends Node
## Screenshot helper: edge mode with all edges of the hull selected and the Bevel operator panel open. Run under xvfb (tools/shots.sh).
func _ready() -> void:
	var b: ShipBuilder = load("res://scenes/ship_builder.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(1.0).timeout
	b.set_mode(ShipBuilder.Mode.EDGE)
	b.active_module = 1
	b.select_all()
	b.start_operator("bevel")
	b.set_operator_param("width", 0.15)
	b.camera_rig.pivot = b.design.module_centroid(1)
	if OS.get_environment("SHOT_MENU") != "":
		b.get_node("UI/BuilderUI").mode_menu.get_popup().popup(Rect2i(20, 80, 200, 150))
