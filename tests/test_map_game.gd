extends Node
## A real game on a big map with the Dreadnought: the map is built, the capital ship starts far enough out and runs.
##   godot --headless --path . res://tests/test_map_game.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	get_tree().current_scene = null
	Data.tutorial = false
	Net.map_id = "star_cluster"
	check(Net.start_solo("res://ships/Dreadnought.ship", "star_cluster"), "a solo game starts with the Dreadnought")
	var world: Node = null
	var t := 0.0
	while world == null and t < 20.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		world = get_tree().get_first_node_in_group("world")
	check(world != null, "the world loads")
	if world == null:
		get_tree().quit(1)
		return
	await get_tree().create_timer(3.0).timeout
	check(world.get_node_or_null("MapDecor") != null, "the map decoration is built (map %s)" % Net.map_id)
	var we := world.get_node("WorldEnvironment") as WorldEnvironment
	check(we.environment.sky != null, "the map's sky is active")
	var me := Data.local_ship
	check(me != null and me.alive, "the Dreadnought exists")
	if me != null:
		check(me.global_position.length() > 1000.0, "it starts out on the big ring (%.0f m from the middle)" % me.global_position.length())
	var rig := world.get_node_or_null("CameraRig")
	check(rig != null and float(rig.get("_dist")) > 1000.0, "the chase camera starts a kilometre or more away from a 2 km ship (%.0f m)" % (float(rig.get("_dist")) if rig != null else 0.0))
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
