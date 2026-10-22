extends Node
## Loads every script of the project (used by tools/check_warnings.sh to surface GDScript warnings).
func _ready() -> void:
	var stack := ["res://scripts", "res://tests"]
	var count := 0
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var dir := DirAccess.open(dir_path)
		for d in dir.get_directories():
			stack.append(dir_path + "/" + d)
		for f in dir.get_files():
			if f.ends_with(".gd"):
				load(dir_path + "/" + f)
				count += 1
	print("loaded %d scripts" % count)
	get_tree().quit()
