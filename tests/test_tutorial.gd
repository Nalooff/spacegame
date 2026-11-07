extends Node
## Solo tutorial: starts a game for one, a drone appears, the steps follow what the player does.
##   godot --headless --path . res://tests/test_tutorial.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ready() -> void:
	get_tree().current_scene = null                  # survive the scene change into the world
	Data.tutorial = true
	check(Net.start_solo("res://ships/Dart.json"), "a solo game starts")
	check(Net.solo, "...and is not advertised")
	var world: Node = null
	var t := 0.0
	while world == null and t < 15.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		world = get_tree().get_first_node_in_group("world")
	check(world != null, "the world loads")
	if world == null:
		get_tree().quit(1)
		return
	await get_tree().create_timer(4.0).timeout
	var mission := world.get_node_or_null("TutorialMission") as TutorialMission
	check(mission != null, "the tutorial mission runs")
	var drone := world.get_node_or_null("Ships/drone1") as Ship
	check(drone != null and drone.is_drone(), "a target drone is spawned")
	var me := Data.local_ship
	check(me != null and me.alive, "my ship exists")
	check(Data.tutorial_text.begins_with("TUTORIAL 1"), "step 1 is shown: %s" % Data.tutorial_text.left(40))
	me.global_position += Vector3(0, 0, 60)
	await get_tree().create_timer(1.0).timeout
	check(mission.step >= 1, "moving 40 m finishes step 1 (step %d)" % mission.step)
	if drone != null and me != null:
		var cs: Array = me.detection.contacts
		var friendly_flag := true
		for c in cs:
			if c["ship"] == drone:
				friendly_flag = c["friendly"]
		check(not friendly_flag, "the drone is an enemy on the radar")
	check(HintBar.is_done("x") == false, "hint memory works")
	print("FAILS: %d" % fails)
	get_tree().quit(fails)
