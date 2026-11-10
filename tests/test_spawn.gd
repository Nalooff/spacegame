extends Node
## Spawn separation: ships of very different sizes never start inside each other.
func _ready() -> void:
	var gw: Node = load("res://scripts/world/game_world.gd").new()
	var fails := 0
	# pure geometry check of GameWorld._clear_spot using fake ships
	var lens := [2235.0, 30.0, 8000.0, 50000.0, 40.0]
	var placed: Array = []
	for L in lens:
		var dir := Vector3.RIGHT.rotated(Vector3.UP, placed.size() * 0.3)
		var p: Vector3 = gw._clear_spot(dir, L, placed.map(func(o): return [o[0], o[1] * 0.5]))
		for o in placed:
			if p.distance_to(o[0]) < (L + o[1]) * 0.5:
				fails += 1
				print("OVERLAP ", L, " vs ", o[1])
		placed.append([p, L])
	print("spawn test: fails=", fails)
	gw.free()
	get_tree().quit(fails)
