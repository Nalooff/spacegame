extends Node
## Autoload "Net": lobby + connection logic. The HOST is the referee of the lobby; clients only ask.
##
## LOBBY FLOW
##   host_lobby(name, private, password)  -> advertised on the network (LobbyDirectory)
##   join_lobby(address, port, password)  -> host checks password / space, answers join_result()
##   submit_ship(blob)                    -> "I chose this ship"        (not final)
##   submit_lock(true)                    -> "lock in": ship is final, others can join it as crew
##   submit_join_crew(captain_id)         -> become crew of a locked ship that has a free seat
##   start_game()                         -> host only: allowed when everyone is locked, or when the timer ran out
##
## ROSTER  Net.players = { peer_id: { name, ship (HASH of the ship blob, "" = none), ship_name, locked, crew_of, seats } }
##   The ships themselves are in Net.blobs {hash: PackedByteArray}; they are sent in chunks (see 'Ship blobs').
##   crew_of = 0 -> the player pilots their own ship;  crew_of = X -> crew on player X's ship.
##   seats = total seats (pilot included) of the player's ship, from its Commander module.
##
## Ship nodes themselves are replicated by the MultiplayerSpawner in game_world.tscn.

signal roster_changed
signal joined                       # the host accepted us
signal join_rejected(reason: String)
signal connection_failed
signal disconnected_from_host
signal peer_ready_in_world(peer_id: int)
signal peer_left(peer_id: int)
signal crew_orphaned(peer_id: int)  # in game: the captain left, this crew member now gets a ship of their own

var players: Dictionary = {}
var in_game: bool = false

## Ship files by content hash. The host has every chosen ship, a client has its own + those sent at game start.
var blobs: Dictionary = {}
signal blob_received(hash: String)
const MAX_SHIP_BYTES := 64 * 1024 * 1024
const CHUNK_BYTES := 48 * 1024
var _uploads: Dictionary = {}       # host: peer id -> {hash, size, data: PackedByteArray, name}
var _peer_has: Dictionary = {}      # host: peer id -> {hash: true} (blobs that peer already holds)
var _incoming: Dictionary = {}      # any: transfer key -> PackedByteArray being assembled

# ---- lobby info (everyone knows these once joined)
var lobby_name: String = ""
var lobby_private: bool = false
## Seconds left on the pre-game timer (host counts it, clients get synced values).
var lobby_seconds_left: float = 0.0

var directory := LobbyDirectory.new()
## Internet lobby list + router port opening. Created in _ready (they need HTTPRequest/Thread children).
var board: LobbyBoard
var nat: NatHelper

var _password_hash: String = ""     # host: required hash;  client: hash we will send
var _lobby_open: bool = false       # host: still accepting players / advertising
var _sync_timer: float = 0.0
var _accepted: bool = false         # client: the host accepted us (otherwise a disconnect means 'rejected')
var _game_port: int = Data.DEFAULT_PORT


func _ready() -> void:
	get_tree().auto_accept_quit = false   # see _notification: tell the internet list before the window closes
	board = LobbyBoard.new()
	board.name = "LobbyBoard"
	add_child(board)
	nat = NatHelper.new()
	nat.name = "NatHelper"
	add_child(nat)
	# list the lobby on the internet board as soon as the public address is known, and again when UPnP is done
	nat.ip_found.connect(func(): if _lobby_open and is_host(): _advertise())
	nat.finished.connect(func(_ok): if _lobby_open and is_host(): _advertise())
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Closing the window never ran leave(), so the lobby stayed on the internet list until it went stale.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_host() and _lobby_open:
			board.close()
			await get_tree().create_timer(1.0).timeout   # give the "closed" message time to leave
		nat.stop()
		get_tree().quit()


func _process(dt: float) -> void:
	directory.poll(dt)
	if _lobby_open or (not is_host() and not in_game):
		lobby_seconds_left = maxf(lobby_seconds_left - dt, 0.0)
	if _lobby_open and is_host():
		_sync_timer -= dt
		if _sync_timer <= 0.0:
			_sync_timer = 2.0
			sync_timer.rpc(lobby_seconds_left)


# =====================================================================
#  Hosting / joining
# =====================================================================
static func hash_password(lobby: String, password: String) -> String:
	return (lobby + "|" + password).sha256_text() if password != "" else ""


func host_lobby(lobby: String, is_private: bool, password: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var port := Data.DEFAULT_PORT
	var err := peer.create_server(port, Data.MAX_PLAYERS)
	while err != OK and port < Data.DEFAULT_PORT + 20: # port busy (e.g. two games on one PC): try the next
		port += 1
		err = peer.create_server(port, Data.MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	in_game = false
	lobby_name = lobby.strip_edges() if lobby.strip_edges() != "" else "%s's lobby" % Data.player_name
	lobby_private = is_private
	_password_hash = hash_password(lobby_name, password) if is_private else ""
	lobby_seconds_left = Data.LOBBY_SECONDS
	_lobby_open = true
	_register_host()
	_game_port = port
	_advertise()
	if Data.BOARD_ENABLED and not _no_internet:
		nat.open(port)
	return OK


func join_lobby(address: String, port: int, password: String, lobby: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	lobby_name = lobby
	_password_hash = hash_password(lobby, password)
	return OK


func leave() -> void:
	directory.stop_advertising()
	board.close()
	nat.stop()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_game = false
	_lobby_open = false
	_accepted = false


func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server() \
		and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func my_id() -> int:
	return multiplayer.get_unique_id()


func _advertise() -> void:
	var info := {"name": lobby_name, "private": lobby_private, "host": Data.player_name,
		"players": players.size(), "max": Data.MAX_PLAYERS, "port": _game_port}
	directory.advertise(info)                        # LAN (UDP broadcast)
	if nat.public_ip != "" and not _no_internet:     # internet (message board), once the public IP is known
		var net_info := info.duplicate()
		net_info["address"] = nat.public_ip
		net_info["lan"] = nat.lan_ip   # players behind the SAME router cannot use the public address: they use this one
		board.post(net_info)


## Tests / LAN-only play can switch the internet part off.
var _no_internet: bool = false


## Every lobby the player can see: LAN + internet.
func all_lobbies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(directory.lobbies)
	for l in board.lobbies:
		out.append(l)
	return out


func _register_host() -> void:
	players[1] = _new_entry(Data.player_name)
	_broadcast()


func _new_entry(pname: String) -> Dictionary:
	return {"name": pname.left(20), "ship": "", "ship_name": "", "locked": false, "crew_of": 0, "seats": 1}


# =====================================================================
#  Join handshake
# =====================================================================
func _on_connected_to_server() -> void:
	request_join.rpc_id(1, Data.player_name, _password_hash)


@rpc("any_peer", "reliable")
func request_join(pname: String, pw_hash: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if not _lobby_open:
		reason = "The game has already started."
	elif players.size() >= Data.MAX_PLAYERS:
		reason = "The lobby is full."
	elif lobby_private and pw_hash != _password_hash:
		reason = "Wrong password."
	if reason != "":
		join_result.rpc_id(id, false, reason, "", false, 0.0)
		await get_tree().create_timer(0.4).timeout # let the answer arrive before the line is cut
		if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(id):
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = _new_entry(pname)
	join_result.rpc_id(id, true, "", lobby_name, lobby_private, lobby_seconds_left)
	_broadcast()


@rpc("authority", "reliable")
func join_result(ok: bool, reason: String, lobby: String, is_private: bool, seconds_left: float) -> void:
	if not ok:
		leave()
		join_rejected.emit(reason)
		return
	lobby_name = lobby
	lobby_private = is_private
	lobby_seconds_left = seconds_left
	_accepted = true
	joined.emit()


@rpc("authority", "unreliable")
func sync_timer(seconds_left: float) -> void:
	lobby_seconds_left = seconds_left


# =====================================================================
#  Choosing a ship / locking / crew   (clients ask, the host decides)
# =====================================================================
func submit_ship(blob: PackedByteArray) -> void:
	var h := hash_blob(blob)
	blobs[h] = blob
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_host_accept_ship(1, h, blob)
	else:
		_send_blob(1, h, blob, &"srv_ship_chunk")


func submit_lock(on: bool) -> void:
	_ask_host(&"srv_set_lock", [on])


func submit_join_crew(captain_id: int) -> void:
	_ask_host(&"srv_join_crew", [captain_id])


func submit_leave_crew() -> void:
	_ask_host(&"srv_leave_crew", [])


## Run `method` on the host (directly if we are the host).
func _ask_host(method: StringName, args: Array) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		callv(method, args)
	else:
		callv(&"rpc_id", [1, method] + args)


## Who is asking? 0 means the host called the function directly (no network involved).
func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return 1 if id == 0 else id


# =====================================================================
#  Ship blobs (upload / distribution in chunks, verified by hash)
# =====================================================================
static func hash_blob(blob: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(blob)
	return ctx.finish().hex_encode()


## Send `blob` to `peer` as reliable chunks through the RPC `method` (srv_ship_chunk or client_blob_chunk).
func _send_blob(peer: int, h: String, blob: PackedByteArray, method: StringName) -> void:
	var total := blob.size()
	var pos := 0
	while pos < total or pos == 0:
		var part := blob.slice(pos, mini(pos + CHUNK_BYTES, total))
		rpc_id(peer, method, h, total, pos, part)
		pos += CHUNK_BYTES
		if total == 0:
			break


## Collect one chunk (chunks of one blob arrive in order on a reliable channel, so we just append).
## Returns the finished blob, or an empty array while incomplete / if something is wrong.
func _collect(key: String, total: int, pos: int, part: PackedByteArray) -> PackedByteArray:
	if total <= 0 or total > MAX_SHIP_BYTES:
		return PackedByteArray()
	var buf: PackedByteArray = _incoming.get(key, PackedByteArray())
	if pos != buf.size() or pos + part.size() > total:
		_incoming.erase(key)       # out of order / oversized: drop the transfer
		return PackedByteArray()
	buf.append_array(part)
	if buf.size() < total:
		_incoming[key] = buf
		return PackedByteArray()
	_incoming.erase(key)
	return buf


## Host: a client uploads its ship.
@rpc("any_peer", "reliable")
func srv_ship_chunk(h: String, total: int, pos: int, part: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not players.has(id) or players[id]["locked"]:
		return
	var key := "%d:%s" % [id, h]
	var blob := _collect(key, total, pos, part)
	if blob.is_empty() or hash_blob(blob) != h:
		return
	_host_accept_ship(id, h, blob)


## Host: validate a finished upload and put it in the roster.
func _host_accept_ship(id: int, h: String, blob: PackedByteArray) -> void:
	if not players.has(id) or players[id]["locked"]:
		return
	var d := ShipDesign.from_blob(blob)
	if d == null or not d.validate().is_empty():
		return
	blobs[h] = blob
	_peer_has.get_or_add(id, {})[h] = true
	players[id]["ship"] = h
	players[id]["ship_name"] = d.ship_name
	players[id]["seats"] = d.crew_capacity()
	_broadcast()


## Client: the host sends the ships of this game.
@rpc("authority", "reliable")
func client_blob_chunk(h: String, total: int, pos: int, part: PackedByteArray) -> void:
	var blob := _collect(h, total, pos, part)
	if not blob.is_empty() and hash_blob(blob) == h:
		blobs[h] = blob
		blob_received.emit(h)


@rpc("any_peer", "reliable")
func srv_set_lock(on: bool) -> void:
	var id := _sender()
	if not multiplayer.is_server() or not players.has(id):
		return
	var p: Dictionary = players[id]
	if p["crew_of"] != 0:
		return # crew members are locked by being crew; they must leave the crew first
	if on:
		if p["ship"] == "":
			return
		p["locked"] = true
	else:
		p["locked"] = false
		_release_crew_of(id)
	_broadcast()


@rpc("any_peer", "reliable")
func srv_join_crew(captain: int) -> void:
	var id := _sender()
	if not multiplayer.is_server() or not players.has(id) or not players.has(captain) or captain == id:
		return
	var cap: Dictionary = players[captain]
	if not cap["locked"] or cap["crew_of"] != 0 or crew_count(captain) + 1 >= int(cap["seats"]):
		return
	if crew_count(id) > 0:
		return # I am a captain with crew of my own: unlock first
	players[id]["crew_of"] = captain
	players[id]["locked"] = true
	_broadcast()


@rpc("any_peer", "reliable")
func srv_leave_crew() -> void:
	var id := _sender()
	if not multiplayer.is_server() or not players.has(id) or players[id]["crew_of"] == 0:
		return
	players[id]["crew_of"] = 0
	players[id]["locked"] = false
	_broadcast()


## Everyone who was crew on `captain`'s ship becomes an unlocked, ship-less player again.
func _release_crew_of(captain: int) -> void:
	for id in players:
		if players[id]["crew_of"] == captain:
			players[id]["crew_of"] = 0
			players[id]["locked"] = false


# ---- roster helpers
func crew_count(captain: int) -> int:
	var n := 0
	for id in players:
		if players[id]["crew_of"] == captain:
			n += 1
	return n


## Free seats on a locked captain's ship.
func seats_free(captain: int) -> int:
	if not players.has(captain) or not players[captain]["locked"] or players[captain]["crew_of"] != 0:
		return 0
	return int(players[captain]["seats"]) - 1 - crew_count(captain)


## The peer whose ship `peer` is aboard (itself, unless crew).
func ship_owner_of(peer: int) -> int:
	return int(players.get(peer, {}).get("crew_of", 0)) if int(players.get(peer, {}).get("crew_of", 0)) != 0 else peer


## True if THIS peer is crew (not pilot) on `ship`.
func is_crew_on(ship: Node) -> bool:
	return int(players.get(my_id(), {}).get("crew_of", 0)) == ship.get_multiplayer_authority()


func all_locked() -> bool:
	for id in players:
		if not players[id]["locked"]:
			return false
	return true


func can_start() -> bool:
	return is_host() and _lobby_open and (all_locked() or lobby_seconds_left <= 0.0)


# =====================================================================
#  Starting the game
# =====================================================================
## Host only. Returns false if not allowed yet.
func start_game() -> bool:
	if not can_start():
		return false
	# Force launch: everybody who has not chosen a ship gets a random premade one.
	for id in players:
		var p: Dictionary = players[id]
		if p["crew_of"] == 0 and p["ship"] == "":
			_give_random_ship(id)
		p["locked"] = true
	_lobby_open = false
	directory.stop_advertising()
	board.close()
	_distribute_blobs()
	sync_roster.rpc(players)
	roster_changed.emit()
	_load_world.rpc()
	return true


## Host: send every ship that is in play to every peer that does not have it yet.
## RPCs on one reliable channel arrive IN ORDER, so the blobs are there before _load_world / spawns run.
func _distribute_blobs() -> void:
	var used := {}
	for id in players:
		if players[id]["ship"] != "":
			used[players[id]["ship"]] = true
	for peer in multiplayer.get_peers():
		var has: Dictionary = _peer_has.get_or_add(peer, {})
		for h in used:
			if not has.has(h) and blobs.has(h):
				_send_blob(peer, h, blobs[h], &"client_blob_chunk")
				has[h] = true


func _give_random_ship(id: int) -> void:
	var premade: Array[String] = []
	for s in ShipDesign.list_ships():
		if s["premade"]:
			premade.append(s["path"])
	if premade.is_empty():
		return
	var blob := ShipDesign.read_blob(premade[randi() % premade.size()])
	var d := ShipDesign.from_blob(blob)
	var h := hash_blob(blob)
	blobs[h] = blob
	players[id]["ship"] = h
	players[id]["ship_name"] = d.ship_name
	players[id]["seats"] = d.crew_capacity()


@rpc("authority", "call_local", "reliable")
func _load_world() -> void:
	in_game = true
	Game.go_to(Game.WORLD_SCENE)


## Each peer tells the host once its world scene is ready; host then spawns that peer's ship.
@rpc("any_peer", "call_local", "reliable")
func world_ready() -> void:
	if multiplayer.is_server():
		var id := multiplayer.get_remote_sender_id()
		peer_ready_in_world.emit(id if id > 0 else 1) # 0 = the host calling itself


# =====================================================================
#  Roster sync
# =====================================================================
func _broadcast() -> void:
	sync_roster.rpc(players)
	roster_changed.emit()
	if _lobby_open:
		_advertise()


@rpc("authority", "reliable")
func sync_roster(roster: Dictionary) -> void:
	players = roster
	roster_changed.emit()


# =====================================================================
#  Connection events
# =====================================================================
func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		players.erase(id)
		_peer_has.erase(id)
		_uploads.erase(id)
		# crew of the player who left
		for cid in players:
			if players[cid]["crew_of"] == id:
				players[cid]["crew_of"] = 0
				players[cid]["locked"] = false
				if in_game:
					_give_random_ship(cid)
					players[cid]["locked"] = true
					_distribute_blobs()
					crew_orphaned.emit(cid)
		_broadcast()
	peer_left.emit(id)


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if not _accepted:
		leave()
		join_rejected.emit("The host closed the connection.")
		return
	leave()
	Data.notice = "The host closed the game."
	disconnected_from_host.emit()
	Game.go_to(Game.MENU_SCENE)
