extends Node
## Screenshot helper: builder with a thruster selected and the Selection tab open. Run under xvfb (see tools/shots.sh).
func _ready() -> void:
	var b: ShipBuilder = load("res://scenes/ship_builder.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(1.0).timeout
	var which := OS.get_environment("SHOT_MODULE")
	var mi := int(which) if which != "" else 2
	b.set_mode(ShipBuilder.Mode.OBJECT)
	b.sel_modules = [mi]
	b.active_module = mi
	BusEvent.builder_selection_changed.emit()
	b.camera_rig.pivot = b.design.module_centroid(mi)
