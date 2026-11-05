extends Node
## Join-in-progress test (see run_late_test.sh). host: starts alone with late join on; late: joins after the game started.
func _ready() -> void:
	var role: String = OS.get_cmdline_user_args()[0]
	Data.player_name = role
	var json := ShipDesign.read_blob("res://ships/Dart.json")
	var runner := Node.new()
	runner.set_script(load("res://tests/late_runner.gd"))
	runner.role = role
	if role == "host":
		print("[host] hosting: ", Net.host_lobby("Late test", false, ""))
		Net.set_late_join(true)
		Net.submit_ship(json)
		Net.submit_lock(true)
	else:
		print("[late] joining: ", Net.join_lobby("127.0.0.1", Data.DEFAULT_PORT, "", "Late test"))
		Net.joined.connect(func():
			print("[late] joined, game_running=", Net.game_running, " late_join=", Net.late_join)
			Net.submit_ship(ShipDesign.read_blob("res://ships/Brick.json"))
			await get_tree().create_timer(1.0).timeout
			Net.request_enter_running_game())
	get_tree().root.add_child.call_deferred(runner)
