extends Node
## Internet lobby board against tests/mock_ntfy.py (run via tests/run_board_test.sh).
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1

func _ready() -> void:
	Data.BOARD_URL = "http://127.0.0.1:8099"
	Data.BOARD_TOPIC = "t"
	Data.PUBLIC_IP_URLS = ["http://127.0.0.1:1/dead", "http://127.0.0.1:8099/ip"]   # first one fails on purpose: tests the fallback
	var host := LobbyBoard.new(); add_child(host)
	var viewer := LobbyBoard.new(); add_child(viewer)
	host.post({"name": "Room A", "private": true, "host": "Ann", "players": 1, "max": 8, "address": "203.0.113.7", "port": 24565})
	await get_tree().create_timer(0.6).timeout
	viewer.refresh()
	await viewer.refreshed
	print("status: ", viewer.status, " / ", host.status)
	check(viewer.lobbies.size() == 1, "viewer sees the lobby")
	if viewer.lobbies.is_empty():
		get_tree().quit(); return
	check(viewer.lobbies[0]["private"] == true and viewer.lobbies[0]["address"] == "203.0.113.7", "private flag + address")
	host.post({"name": "Room A", "private": true, "host": "Ann", "players": 3, "max": 8, "address": "203.0.113.7", "port": 24565})
	await get_tree().create_timer(0.6).timeout
	viewer.refresh(); await viewer.refreshed
	check(viewer.lobbies.size() == 1 and viewer.lobbies[0]["players"] == 3, "newest message wins (3 players)")
	check(not JSON.stringify(viewer.lobbies).contains("password"), "no password on the board")
	host.close()
	await get_tree().create_timer(0.6).timeout
	viewer.refresh(); await viewer.refreshed
	check(viewer.lobbies.is_empty(), "closed lobby disappears")
	var nat := NatHelper.new(); add_child(nat)
	nat.open(24565)
	await nat.finished
	check(nat.public_ip == "203.0.113.7", "public IP lookup (UPnP in sandbox: %s)" % nat.message)
	# whole chain: Net.host_lobby -> UPnP/IP lookup -> posted on the board -> a browser sees it
	Net.host_lobby("Chain Lobby", false, "")
	await Net.nat.ip_found
	await get_tree().create_timer(0.8).timeout
	viewer.refresh(); await viewer.refreshed
	print("nat: ", Net.nat.message, " / ip=", Net.nat.public_ip, " / board status=", Net.board.status, " / lobby open ", Net._lobby_open)
	var found := false
	for l in viewer.lobbies:
		if l["name"] == "Chain Lobby":
			found = true
			print("listed: ", l)
	check(found, "hosting a lobby posts it on the internet board by itself")
	Net.leave()
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	get_tree().quit()
