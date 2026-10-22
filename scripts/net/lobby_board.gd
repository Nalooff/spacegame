class_name LobbyBoard
extends Node
## INTERNET-WIDE lobby list without a server of your own.
##
## How it works: a public ntfy-style "topic" (Data.BOARD_URL + Data.BOARD_TOPIC) is used as a message board.
##   * HOST  : post()      -> POST a small JSON message describing the lobby (again every Data.BOARD_HEARTBEAT s,
##                            and when the player count changes). close() posts "closed".
##   * BROWSER: refresh()  -> GET the last minutes of messages, keep the newest per lobby, hide closed / stale ones.
## The game itself is still direct peer-to-peer (ENet): the board only tells people WHERE to connect.
## Nothing secret is ever posted: the password stays in the room (only a "private" flag is shown).
##
## Needs HTTPS access from the player's PC. Created by the Net autoload (it needs HTTPRequest children).

signal refreshed

## [{id, name, private, host, players, max, address, port, source}] newest data, same shape as LobbyDirectory.
var lobbies: Array[Dictionary] = []
var status: String = ""
var busy: bool = false

var _info: Dictionary = {}
var _id: int = randi()
var _beat: float = 0.0
var _sent_players: int = -1


func _process(dt: float) -> void:
	if _info.is_empty():
		return
	_beat -= dt
	if _beat <= 0.0:
		_send(false)


## Start/update advertising. `info`: {name, private, host, players, max, address, port}
func post(info: Dictionary) -> void:
	if not Data.BOARD_ENABLED:
		return
	var changed: bool = _info.is_empty() or int(info.get("players", 0)) != _sent_players or info.get("name") != _info.get("name")
	_info = info
	if changed:
		_send(false)


func close() -> void:
	if _info.is_empty():
		return
	_send(true)
	_info = {}


func _send(closed: bool) -> void:
	_beat = Data.BOARD_HEARTBEAT
	_sent_players = int(_info.get("players", 0))
	var msg := _info.duplicate()
	msg["game"] = "vertexships"
	msg["id"] = _id
	msg["closed"] = closed
	var req := HTTPRequest.new()
	req.name = "BoardPost"
	req.timeout = 10.0
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, _b):
		if code >= 300 or code == 0:
			status = "Could not post the lobby to the internet list (HTTP %d)." % code
		req.queue_free())
	var err := req.request("%s/%s" % [Data.BOARD_URL, Data.BOARD_TOPIC], ["Content-Type: text/plain", "Title: lobby"],
		HTTPClient.METHOD_POST, JSON.stringify(msg))
	if err != OK:
		status = "Internet list unreachable (error %d)." % err
		req.queue_free()


## Fetch the list (async). `lobbies` updates and `refreshed` fires when done.
func refresh() -> void:
	if not Data.BOARD_ENABLED or busy:
		return
	busy = true
	var req := HTTPRequest.new()
	req.name = "BoardPoll"
	req.timeout = 10.0
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, body: PackedByteArray):
		busy = false
		if code == 200:
			parse(body.get_string_from_utf8())
			status = ""
		else:
			status = "Internet list unreachable (HTTP %d)." % code
		req.queue_free()
		refreshed.emit())
	var err := req.request("%s/%s/json?poll=1&since=10m" % [Data.BOARD_URL, Data.BOARD_TOPIC])
	if err != OK:
		busy = false
		status = "Internet list unreachable (error %d)." % err
		req.queue_free()


## `text` = ntfy "json" stream: one JSON event per line; event["message"] is what the host posted.
## Public so tests can feed it.
func parse(text: String) -> void:
	var newest := {}   # lobby id -> {entry, time}
	for line in text.split("\n", false):
		var ev: Variant = JSON.parse_string(line)
		if typeof(ev) != TYPE_DICTIONARY or ev.get("event", "message") != "message":
			continue
		var msg: Variant = JSON.parse_string(str(ev.get("message", "")))
		if typeof(msg) != TYPE_DICTIONARY or msg.get("game", "") != "vertexships":
			continue
		var id := int(msg.get("id", 0))
		var time := float(ev.get("time", 0))
		if not newest.has(id) or time >= newest[id]["time"]:
			newest[id] = {"entry": msg, "time": time}
	var now := Time.get_unix_time_from_system()
	lobbies.clear()
	for id in newest:
		var e: Dictionary = newest[id]["entry"]
		if bool(e.get("closed", false)) or now - float(newest[id]["time"]) > Data.BOARD_STALE or id == _id:
			continue
		lobbies.append({"id": id, "name": str(e.get("name", "?")).left(40), "private": bool(e.get("private", false)),
			"host": str(e.get("host", "?")).left(20), "players": int(e.get("players", 1)), "max": int(e.get("max", Data.MAX_PLAYERS)),
			"address": str(e.get("address", "")), "lan": str(e.get("lan", "")), "port": int(e.get("port", Data.DEFAULT_PORT)), "source": "internet"})
	lobbies.sort_custom(func(a, b): return a["name"].naturalnocasecmp_to(b["name"]) < 0)
