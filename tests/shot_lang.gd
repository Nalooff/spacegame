extends Node
## Screenshots in another language: SHOT_LANG=ja SHOT_SCENE=res://scenes/settings.tscn SHOT_OUT=/path.png
func _ready() -> void:
	Prefs.set_values({"language": OS.get_environment("SHOT_LANG")})
	Prefs.apply_all()
	var sc: Node = load(OS.get_environment("SHOT_SCENE")).instantiate()
	add_child(sc)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
