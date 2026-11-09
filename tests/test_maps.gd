extends Node
## Maps: every map builds (sky, suns = lights, rocks, dust), the host's choice is synced and validated.
##   godot --headless --path . res://tests/test_maps.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	check(MapCatalog.count() >= 8, "there are %d maps" % MapCatalog.count())
	check(MapCatalog.get_map("nonsense")["id"] == MapCatalog.CLASSIC and not MapCatalog.is_valid("../x"), "unknown ids fall back to the classic map")
	for m in MapCatalog.MAPS:
		var world := Node3D.new()
		var we := WorldEnvironment.new()
		we.name = "WorldEnvironment"
		world.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		world.add_child(sun)
		var sp := Node3D.new()
		sp.name = "SpawnPoints"
		for i in 4:
			var mk := Marker3D.new()
			mk.position = Vector3(cos(i * 1.57), 0, sin(i * 1.57)) * float(m["spawn_radius"])
			sp.add_child(mk)
		world.add_child(sp)
		add_child(world)
		var b := WorldBuilder.build(world, m)
		var lights := 0
		for c in b.get_children():
			if c is DirectionalLight3D:
				lights += 1
		if m["id"] == MapCatalog.CLASSIC:
			check(b.get_child_count() == 0 and we.environment == null, "classic map leaves the scene untouched")
		else:
			check(lights == (m["suns"] as Array).size() and lights >= 1 and lights <= 3, "%s: %d sun(s) = %d light(s)" % [m["id"], (m["suns"] as Array).size(), lights])
			check(we.environment != null and we.environment.sky != null, "%s: has its own sky" % m["id"])
			check(float(m["spawn_radius"]) >= 1000.0, "%s: roomy arena (%.0f m)" % [m["id"], m["spawn_radius"]])
			if int(m["rocks"]["count"]) > 0:
				var rocks := 0
				for c in b.get_children():
					if c is MultiMeshInstance3D:
						rocks += (c as MultiMeshInstance3D).multimesh.instance_count
				check(rocks > 50, "%s: %d rocks" % [m["id"], rocks])
		world.queue_free()
	# network sync (host side): option + validation
	Net.map_id = MapCatalog.CLASSIC
	Net.sync_game({"mode": "ffa", "teams": 2, "limit": 0, "map": "gas_giant"})
	check(Net.map_id == "gas_giant", "the map choice arrives from the host")
	Net.sync_game({"mode": "ffa", "teams": 2, "limit": 0, "map": "evil/../path"})
	check(Net.map_id == MapCatalog.CLASSIC, "a bad map id from the network is ignored")
	check(Net.game_info()["map"] == MapCatalog.CLASSIC, "game_info carries the map")
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
