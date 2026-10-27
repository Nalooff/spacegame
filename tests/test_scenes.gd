extends Node
## Loads and instantiates EVERY .tscn of the project: catches scenes that cannot be parsed (e.g. a bad generator). Run: godot --headless --path . res://tests/test_scenes.tscn
func _ready() -> void:
	await get_tree().process_frame
	var bad := 0
	var files: Array[String] = []
	var stack := ["res://"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".tscn"):
				files.append(dir + f)
		for sd in DirAccess.get_directories_at(dir):
			if not sd.begins_with("."):
				stack.append(dir + sd + "/")
	files.sort()
	for f in files:
		var res := ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null or not (res is PackedScene):
			print("FAIL load ", f); bad += 1; continue
		var inst: Node = (res as PackedScene).instantiate()
		if inst == null:
			print("FAIL instantiate ", f); bad += 1; continue
		print("ok   ", f)
		inst.queue_free()
	print("SCENES: ", files.size(), " bad=", bad)
	get_tree().quit(bad)
