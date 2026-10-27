extends Node
## Steam transport against a FAKE Steam singleton (the real GodotSteam add-ons are not installed here, so this checks OUR side:
## the order of calls, the lobby data, the list parsing, the join flow and the Net hooks).
## Run: godot --headless --path . res://tests/test_steam.tscn
var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


## Stand-in for the `Steam` singleton: records calls, answers like Steam does.
class FakeSteam extends Node:
	signal lobby_created(result: int, lobby_id: int)
	signal lobby_match_list(lobbies: Array)
	signal lobby_joined(lobby: int, permissions: int, locked: bool, response: int)
	signal join_requested(lobby_id: int, steam_id: int)
	var calls: Array = []
	var data: Dictionary = {}
	func steamInitEx() -> Dictionary:
		calls.append("steamInitEx")
		return {"status": 0, "verbal": "ok"}
	func getPersonaName() -> String:
		return "Tester"
	func createLobby(kind: int, maxm: int) -> void:
		calls.append("createLobby %d %d" % [kind, maxm])
		lobby_created.emit.call_deferred(1, 777)
	func setLobbyData(_id: int, key: String, value: String) -> bool:
		data[key] = value
		return true
	func getLobbyData(_id: int, key: String) -> String:
		return str(data.get(key, ""))
	func setRichPresence(k: String, v: String) -> bool:
		calls.append("rich %s=%s" % [k, v])
		return true
	func addRequestLobbyListStringFilter(k: String, v: String, _c: int) -> void:
		calls.append("filter %s=%s" % [k, v])
	func addRequestLobbyListDistanceFilter(d: int) -> void:
		calls.append("distance %d" % d)
	func requestLobbyList() -> void:
		calls.append("requestLobbyList")
		lobby_match_list.emit.call_deferred([555])
	func getNumLobbyMembers(_id: int) -> int:
		return 3
	func getLobbyMemberLimit(_id: int) -> int:
		return 16
	func getLobbyOwner(_id: int) -> int:
		return 123456
	func joinLobby(id: int) -> void:
		calls.append("joinLobby %d" % id)
		lobby_joined.emit.call_deferred(id, 0, false, 1)
	func leaveLobby(id: int) -> void:
		calls.append("leaveLobby %d" % id)
	func run_callbacks() -> void:
		pass


class FakePeer extends OfflineMultiplayerPeer:
	var host_port := -1
	var client_to := -1
	func create_host(vport: int) -> int:
		host_port = vport
		return OK
	func create_client(steam_id: int, _vport: int) -> int:
		client_to = steam_id
		return OK


func _ready() -> void:
	await get_tree().process_frame
	check(not SteamBackend.is_available(), "without the add-ons Steam is reported unavailable (the game runs as before)")
	check(not Net.steam_active(), "...and Net does not use Steam")
	var fake := FakeSteam.new()
	add_child(fake)
	var sb := Net.steam
	var made: Array = []
	sb.peer_factory = func() -> Object:
		var p := FakePeer.new()
		made.append(p)
		return p
	check(sb.start(fake), "starts against the (fake) Steam client")
	check(Net.steam_active() and sb.persona_name == "Tester", "Steam is active, the Steam name is known")

	# hosting through Net
	var result := [null, ""]
	Net.steam_host_result.connect(func(ok: bool, why: String): result[0] = ok; result[1] = why)
	Net.host_steam("Fuzz Arena", true, "pw")
	await get_tree().process_frame
	await get_tree().process_frame
	check(result[0] == true, "hosting a lobby through Steam succeeds (%s)" % str(result[1]))
	check(fake.calls.has("createLobby 2 16"), "a public-type Steam lobby for up to 16 (private lobbies are listed too: the password protects them)")
	check(fake.data.get("game", "") == SteamBackend.GAME_KEY and fake.data.get("open", "") == "1", "lobby data: game key + open")
	check(fake.data.get("name", "") == "Fuzz Arena" and fake.data.get("private", "") == "1", "lobby data: name and private flag")
	check(fake.calls.has("rich connect=777"), "rich presence 'connect' is set so friends can use Join game")
	check((made[0] as FakePeer).host_port == 0, "the Steam peer hosts on virtual port 0")
	check(Net.players.has(1) and Net.lobby_name == "Fuzz Arena", "Net registered the host in the roster")
	Net.players[2] = Net._new_entry("Guest")
	Net._advertise()
	check(fake.data.get("players", "") == "2", "player count in the Steam lobby follows the roster")
	Net.steam.set_open(false)
	check(fake.data.get("open", "") == "0", "starting the game closes the lobby listing")

	# browsing and joining
	var listed := []
	sb.lobbies_found.connect(func(l: Array): listed.append_array(l))
	sb.list_lobbies()
	await get_tree().process_frame
	await get_tree().process_frame
	check(fake.calls.has("filter game=vertex_ships") and fake.calls.has("filter open=1") and fake.calls.has("distance 3"), "the list asks only for open lobbies of this game, worldwide")
	check(listed.size() == 1 and listed[0]["source"] == "steam" and listed[0]["players"] == 3 and listed[0]["max"] == 16, "list entries carry players / max / source")
	check(Net.all_lobbies().size() == 1 or Net.all_lobbies().any(func(l): return l.get("source", "") == "steam"), "Net.all_lobbies() includes the Steam lobbies")
	Net.leave()
	check(fake.calls.has("leaveLobby 777"), "leaving the room leaves the Steam lobby")
	var joined_peer := []
	sb.client_ready.connect(func(p): joined_peer.append(p))
	Net.join_steam(listed[0], "pw")
	await get_tree().process_frame
	await get_tree().process_frame
	check(fake.calls.has("joinLobby 555") and joined_peer.size() == 1, "joining asks Steam, then connects to the lobby owner")
	check((made[1] as FakePeer).client_to == 123456, "the client connects to the Steam id of the lobby owner")
	var invited := []
	sb.invite_accepted.connect(func(id: int): invited.append(id))
	fake.join_requested.emit(555, 1)
	check(invited == [555], "a friend's 'Join game' invite is passed on")
	var failed := []
	sb.join_failed.connect(func(r: String): failed.append(r))
	fake.lobby_joined.emit(555, 0, false, 1)       # a stray answer for a lobby we are not joining: ignored
	check(failed.is_empty(), "a stray join answer is ignored")
	Net.leave()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(1 if fails else 0)
