extends Node
## Screenshot of the preset creator: xvfb-run -a -s "-screen 0 1600x900x24" godot --path . res://tests/shot_presets.tscn
func _ready() -> void:
	var sc: Control = load("res://scenes/preset_creator.tscn").instantiate()
	add_child(sc)
	await get_tree().create_timer(0.8).timeout
	sc._select_type(sc._types.find(ModuleCatalog.BARREL))
	sc.preset_list.select(1)
	sc._on_preset_selected(1)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/img/8_preset_creator.png"))
	get_tree().quit()
