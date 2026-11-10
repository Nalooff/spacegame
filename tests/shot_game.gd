extends Node
## Screenshot of a real solo game (xvfb). SHIP=res://... MAP=id OUT=file.png WAIT=seconds
func _ready() -> void:
	get_tree().current_scene = null
	Data.tutorial = false
	var path := OS.get_environment("SHIP") if OS.get_environment("SHIP") != "" else "res://ships/Dart.json"
	Net.start_solo(path, OS.get_environment("MAP"))
	var world: Node = null
	while world == null:
		await get_tree().create_timer(0.25).timeout
		world = get_tree().get_first_node_in_group("world")
	await get_tree().create_timer(float(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 4.0).timeout
	var rig := world.get_node_or_null("CameraRig")
	if rig != null and OS.get_environment("CAMD") != "":
		rig.set("_dist", float(OS.get_environment("CAMD")))
		await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT"))
	get_tree().quit()
