extends Node
## Screenshot: builder with a barrel selected (circles + tube). SHOT_OUT=/path.png
func _ready() -> void:
	var b: ShipBuilder = load("res://scenes/ship_builder.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(0.8).timeout
	b.load_from("res://ships/Brick.json")
	await get_tree().create_timer(0.5).timeout
	var bar := -1
	for mi in b.design.modules.size():
		if b.design.modules[mi]["type"] == ModuleCatalog.BARREL:
			bar = mi
			break
	b.set_mode(ShipBuilder.Mode.OBJECT)
	b.sel_modules = [bar]
	b.active_module = bar
	b.set_thruster_direction(Vector3(0, 0, -1))
	BusEvent.builder_selection_changed.emit()
	b.camera_rig.pivot = b.design.module_centroid(bar)
	b.camera_rig.distance = 7.0
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
