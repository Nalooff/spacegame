extends Node
## Screenshot: the builder with the Dreadnought loaded (framed whole, big grid). Under xvfb.
func _ready() -> void:
	Data.builder_open_path = "res://ships/Dreadnought.ship"
	var b: ShipBuilder = load("res://scenes/ship_builder.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(2.0).timeout
	if OS.get_environment("ADD") != "":
		b.add_shape(ModuleCatalog.HULL, "box", Vector3.ONE, 12, 0, false)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
