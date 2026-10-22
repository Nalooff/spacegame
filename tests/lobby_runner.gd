extends Node
## Persistent part of the lobby test (see run_lobby_test.sh). Roles: host, crew (discovers + joins as crew), idle (never picks a ship).
var role := "host"
var t := 0.0
var step := 0
var done := false

func say(s: String) -> void:
	print("[%s t=%.1f] %s" % [role, t, s])

func ship_json(n: String) -> String:
	return FileAccess.get_file_as_string("res://ships/%s.json" % n)

func _ready() -> void:
	Net.joined.connect(func(): say("JOINED lobby '%s' private=%s" % [Net.lobby_name, Net.lobby_private]))
	Net.join_rejected.connect(func(r): say("REJECTED: " + r))
	if role == "host":
		Data.player_name = "Host"
		say("host_lobby -> %s" % Net.host_lobby("Test Lobby", true, "secret"))
	elif role == "crew":
		Data.player_name = "Gunner"
		say("listen -> %s" % Net.directory.listen())
	else:
		Data.player_name = "Idler"

func _process(dt: float) -> void:
	t += dt
	match role:
		"host": _host()
		"crew": _crew()
		"idle": _idle()
	if t > 22.0 and not done:
		done = true
		say("end")
		get_tree().quit()

func _idle() -> void:
	if step == 0 and t > 2.0:
		step = 1
		say("join with the right password, direct address -> %s" % Net.join_lobby("127.0.0.1", Data.DEFAULT_PORT, "secret", "Test Lobby"))

func _crew() -> void:
	if step == 0 and t > 3.0:
		var found := Net.directory.lobbies
		say("discovered lobbies: %s" % JSON.stringify(found))
		if found.is_empty():
			return
		step = 1
		var l: Dictionary = found[0]
		say("join with WRONG password -> %s" % Net.join_lobby(l["address"], l["port"], "nope", l["name"]))
	elif step == 1 and t > 5.0:
		step = 2
		var l: Dictionary = Net.directory.lobbies[0]
		say("join with right password -> %s" % Net.join_lobby(l["address"], l["port"], "secret", l["name"]))
	elif step == 2 and t > 8.0:
		var host_locked: bool = Net.players.get(1, {}).get("locked", false)
		say("roster host locked=%s seats=%s" % [host_locked, Net.players.get(1, {}).get("seats")])
		step = 3
		Net.submit_join_crew(1)
	elif step == 3 and t > 9.0:
		say("my crew_of = %s, ship owner = %s" % [Net.players.get(Net.my_id(), {}).get("crew_of"), Net.ship_owner_of(Net.my_id())])
		step = 4
	elif step == 4:
		var ship := get_tree().root.find_child("1", true, false) as Ship
		if ship != null and t > 14.0 and not ship.is_multiplayer_authority():
			say("in game; crew on ship 1: %s" % Net.is_crew_on(ship))
			ship.weapons.request_fire.rpc_id(1, ship.global_position + Vector3(0, 0, -50))
			step = 5
	elif step == 5 and t > 16.0:
		step = 6
		var ship2 := get_tree().root.find_child("1", true, false) as Ship
		say("local ship for crew: %s (authority=%s)" % [Data.local_ship, ship2.is_multiplayer_authority()])

func _host() -> void:
	if step == 0 and t > 1.0:
		Net.submit_ship(ship_json("Brick").to_utf8_buffer())
		Net.submit_lock(true)
		step = 1
	elif step == 1 and t > 10.0:
		say("players: %s" % JSON.stringify(_summary()))
		say("can_start (not all locked, timer running) = %s ; start_game() = %s" % [Net.can_start(), Net.start_game()])
		Net.lobby_seconds_left = 0.0 # simulate the 2-minute timeout
		say("after timeout can_start = %s" % Net.can_start())
		step = 2
	elif step == 2 and t > 10.5:
		say("start_game() = %s" % Net.start_game())
		step = 3
	elif step == 3 and t > 13.0:
		say("late join attempt is refused by design (lobby closed)")
		step = 4
	elif step == 4 and t > 16.0:
		var active := 0
		var pool := get_tree().get_first_node_in_group("projectile_pool")
		if pool != null:
			for p in pool.get_children():
				if (p as Projectile).active:
					active += 1
		say("ships: %s ; active bullets in pool (after crew fired): %d" % [get_tree().get_nodes_in_group("ships").map(func(s): return s.name), active])
		say("roster at start: %s" % JSON.stringify(_summary()))
		step = 5

func _summary() -> Array:
	var out := []
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		out.append({"id": id, "name": p["name"], "ship": p["ship_name"], "locked": p["locked"], "crew_of": p["crew_of"], "seats": p["seats"]})
	return out
