extends Node
## Bootstrap for the two-process multiplayer smoke test (see run_net_test.sh).
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var role: String = args[0]
	Data.player_name = role
	var json := ShipDesign.read_blob("res://ships/%s.json" % args[1])
	if role == "host":
		print("[host] hosting: ", Net.host_lobby("Smoke test", false, ""))
		Net.submit_ship(json)
		Net.submit_lock(true)
	else:
		print("[client] joining: ", Net.join_lobby("127.0.0.1", Data.DEFAULT_PORT, "", "Smoke test"))
		Net.joined.connect(func():
			Net.submit_ship(json)
			Net.submit_lock(true))
	var runner := Node.new()
	runner.name = "TestRunner"
	runner.set_script(load("res://tests/net_ram_runner.gd" if args.size() > 2 and args[2] == "ram" else "res://tests/net_runner.gd"))
	runner.role = role
	get_tree().root.add_child.call_deferred(runner)
