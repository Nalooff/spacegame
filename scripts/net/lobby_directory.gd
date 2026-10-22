class_name LobbyDirectory
extends RefCounted
## Finds lobbies without anyone typing an address.
##
## HOST: advertise() sends a small UDP "I am a lobby" packet once a second (broadcast + loopback).
## BROWSER: listen() receives those packets; `lobbies` is the list of lobbies seen in the last few seconds.
## Only lobbies still in the pre-game state are advertised (the host stops when the game starts).
##
## This covers LAN / same-network play with zero setup. For internet-wide listing you would swap this
## class for one that talks to a small web server (keep the same functions: advertise / listen / poll / lobbies).
## The password is NEVER sent: only a "private" flag.

const GAME_ID := "vertexships"
const SEND_EVERY := 1.0
const EXPIRE_AFTER := 3.5

## Seen lobbies: [{id, name, private, host, players, max, address, port, age}]
var lobbies: Array[Dictionary] = []

var _sender: PacketPeerUDP
var _listener: PacketPeerUDP
var _info: Dictionary = {}
var _send_timer: float = 0.0
var _seen: Dictionary = {}   # id -> {entry, last}
var _clock: float = 0.0
var _id: int = randi()


## Start (or update) advertising. `info`: {name, private, host, players, max, port}
func advertise(info: Dictionary) -> void:
	_info = info
	if _sender == null:
		_sender = PacketPeerUDP.new()
		_sender.set_broadcast_enabled(true)
	_send_timer = 0.0 # send right away


func stop_advertising() -> void:
	_info = {}
	if _sender != null:
		_sender.close()
		_sender = null


## Start listening for lobbies. Returns an Error (ERR_ALREADY_IN_USE if another game on this PC is already listening).
func listen() -> Error:
	if _listener != null:
		return OK
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(Data.DISCOVERY_PORT)
	if err != OK:
		_listener = null
	return err


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	_seen.clear()
	lobbies.clear()


func clear() -> void:
	_seen.clear()
	lobbies.clear()


func poll(dt: float) -> void:
	_clock += dt
	if not _info.is_empty() and _sender != null:
		_send_timer -= dt
		if _send_timer <= 0.0:
			_send_timer = SEND_EVERY
			_send_packet()
	if _listener != null:
		while _listener.get_available_packet_count() > 0:
			var text := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) != TYPE_DICTIONARY or parsed.get("game", "") != GAME_ID:
				continue
			var d: Dictionary = parsed
			d["address"] = ip
			_seen[int(d.get("id", 0))] = {"entry": d, "last": _clock}
		_rebuild()


func _send_packet() -> void:
	var d := _info.duplicate()
	d["game"] = GAME_ID
	d["id"] = _id
	var data := JSON.stringify(d).to_utf8_buffer()
	for dest in ["255.255.255.255", "127.0.0.1"]:
		_sender.set_dest_address(dest, Data.DISCOVERY_PORT)
		_sender.put_packet(data)


func _rebuild() -> void:
	lobbies.clear()
	for id in _seen.keys():
		var rec: Dictionary = _seen[id]
		if _clock - float(rec["last"]) > EXPIRE_AFTER:
			_seen.erase(id)
			continue
		var e: Dictionary = rec["entry"]
		lobbies.append({"id": id, "name": str(e.get("name", "?")), "private": bool(e.get("private", false)),
			"host": str(e.get("host", "?")), "players": int(e.get("players", 1)), "max": int(e.get("max", Data.MAX_PLAYERS)),
			"address": str(e["address"]), "port": int(e.get("port", Data.DEFAULT_PORT))})
	lobbies.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
