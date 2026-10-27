class_name SteamBackend
extends Node
## OPTIONAL Steam transport (lobby list, joining by Steam friends, relay networking without port forwarding).
##
## It needs two free add-ons from the Godot Asset Library / GitHub, copied into `addons/`:
##   * GodotSteam (GDExtension)       registers the singleton `Steam`
##   * GodotSteam MultiplayerPeer     registers the class `SteamMultiplayerPeer`
## Nothing here refers to them by name at compile time, so the game runs exactly as before (LAN + internet board) when they are
## not installed: `is_available()` is false and Net never calls this node.  See docs/STEAM_AND_ITCH.md.
##
## EVERY call into the add-ons is in THIS file (names written as strings), so a change in the add-on's API is a one-file fix.
## `api` and `peer_factory` can be replaced by a fake in tests (tests/test_steam.gd).
##
## Flow, host:   create_lobby(name, private)  -> Steam lobby (data: game, ver, name, host, private, open, players)
##                                            -> `host_ready(peer)`: give the peer to `multiplayer.multiplayer_peer`
## Flow, client: list_lobbies() -> `lobbies_found(list)`;  join_lobby(id) -> `client_ready(peer)` (peer already connecting to the host)

signal lobbies_found(list: Array)        ## Array of lobby dictionaries (same keys as the LAN / internet lists, source "steam")
signal host_ready(peer: MultiplayerPeer)
signal client_ready(peer: MultiplayerPeer)
signal join_failed(reason: String)
signal invite_accepted(lobby_id: int)    ## the player clicked "Join game" on a Steam friend

const GAME_KEY := "vertex_ships"
const LOBBY_PUBLIC := 2                   # Steam lobby types: 0 private, 1 friends only, 2 public, 3 invisible

var api: Object = null                    ## the Steam singleton (or a fake)
var peer_factory: Callable = Callable()   ## () -> MultiplayerPeer-like object with create_host / create_client
var ready_ok: bool = false                ## Steam is running and initialised
var status: String = ""                   ## plain-words state for the UI
var lobby_id: int = 0                     ## the lobby we host / sit in (0 = none)
var persona_name: String = ""
var _lobby_info: Dictionary = {}          # host: what we advertise
var _hosting: bool = false


## True when both add-ons are installed (not necessarily that Steam is running).
static func is_available() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


## Start Steam. Returns true when it is running (the player is logged in). Safe to call when the add-ons are missing.
func start(fake_api: Object = null) -> bool:
	api = fake_api if fake_api != null else (Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null)
	if api == null:
		status = "Steam add-on not installed"
		return false
	if not peer_factory.is_valid():
		peer_factory = func() -> Object: return ClassDB.instantiate("SteamMultiplayerPeer")
	var res: Variant = api.call("steamInitEx") if api.has_method("steamInitEx") else api.call("steamInit")
	if res is Dictionary and int(res.get("status", 1)) != 0:
		status = "Steam did not start: %s" % str(res.get("verbal", "is the Steam client running?"))
		return false
	persona_name = str(api.call("getPersonaName"))
	_connect_signal("lobby_created", _on_lobby_created)
	_connect_signal("lobby_match_list", _on_match_list)
	_connect_signal("lobby_joined", _on_lobby_joined)
	_connect_signal("join_requested", _on_join_requested)          # GodotSteam 4.x name
	_connect_signal("lobby_join_requested", _on_join_requested)    # older name
	ready_ok = true
	status = "Steam: %s" % persona_name
	return true


func _connect_signal(sig: String, cb: Callable) -> void:
	if api.has_signal(sig):
		api.connect(sig, cb)


func _process(_dt: float) -> void:
	if ready_ok and api.has_method("run_callbacks"):
		api.call("run_callbacks")


# ---------------------------------------------------------------- hosting
## `info`: {name, private, host, players, max}. The multiplayer peer is created when Steam has made the lobby.
func create_lobby(info: Dictionary) -> void:
	if not ready_ok:
		join_failed.emit(status)
		return
	_lobby_info = info
	_hosting = true
	# private lobbies are listed too (with a lock): the PASSWORD protects them, the host checks it
	api.call("createLobby", LOBBY_PUBLIC, int(info.get("max", 16)))


func _on_lobby_created(result: int, id: int) -> void:
	if not _hosting:
		return
	if result != 1:                                           # k_EResultOK
		_hosting = false
		join_failed.emit("Steam could not create the lobby (result %d)" % result)
		return
	lobby_id = id
	_set_data("game", GAME_KEY)
	_set_data("ver", str(ProjectSettings.get_setting("application/config/version", "0")))
	update_info(_lobby_info)
	_set_data("open", "1")
	var peer: Object = peer_factory.call()
	var err: int = int(peer.call("create_host", 0))
	if err != OK:
		_hosting = false
		join_failed.emit("Could not start the Steam host (error %d)" % err)
		return
	api.call("setRichPresence", "connect", str(id))           # lets friends use "Join game"
	host_ready.emit(peer)


## Refresh what the lobby list shows (player count, name...). Call when it changes.
func update_info(info: Dictionary) -> void:
	_lobby_info = info
	if lobby_id == 0:
		return
	_set_data("name", str(info.get("name", "")))
	_set_data("host", str(info.get("host", persona_name)))
	_set_data("private", "1" if info.get("private", false) else "0")
	_set_data("players", str(int(info.get("players", 1))))
	_set_data("max", str(int(info.get("max", 16))))


## The lobby stops being listed (game started / closed).
func set_open(open: bool) -> void:
	if lobby_id != 0:
		_set_data("open", "1" if open else "0")


func _set_data(key: String, value: String) -> void:
	api.call("setLobbyData", lobby_id, key, value)


func leave() -> void:
	if ready_ok and lobby_id != 0:
		api.call("leaveLobby", lobby_id)
		api.call("setRichPresence", "connect", "")
	lobby_id = 0
	_hosting = false
	_joining = 0


# ---------------------------------------------------------------- browsing
func list_lobbies() -> void:
	if not ready_ok:
		lobbies_found.emit([])
		return
	api.call("addRequestLobbyListStringFilter", "game", GAME_KEY, 0)     # 0 = equal
	api.call("addRequestLobbyListStringFilter", "open", "1", 0)
	api.call("addRequestLobbyListDistanceFilter", 3)                      # 3 = worldwide
	api.call("requestLobbyList")


func _on_match_list(ids: Array) -> void:
	var out: Array = []
	for id in ids:
		out.append(lobby_entry(int(id)))
	lobbies_found.emit(out)


# ---------------------------------------------------------------- joining
var _joining: int = 0


func join_lobby(id: int) -> void:
	if not ready_ok:
		join_failed.emit(status)
		return
	_joining = id
	api.call("joinLobby", id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if id != _joining:
		return
	_joining = 0
	if response != 1:                                         # 1 = success
		join_failed.emit("Steam refused the join (response %d)" % response)
		return
	lobby_id = id
	var owner_id: int = int(api.call("getLobbyOwner", id))
	var peer: Object = peer_factory.call()
	var err: int = int(peer.call("create_client", owner_id, 0))
	if err != OK:
		join_failed.emit("Could not connect to the Steam host (error %d)" % err)
		return
	client_ready.emit(peer)


func _on_join_requested(id: int, _friend: int = 0) -> void:
	invite_accepted.emit(id)


## The listing entry of one lobby (also used for invites, where we only know the id).
func lobby_entry(id: int) -> Dictionary:
	return {"id": id, "name": str(api.call("getLobbyData", id, "name")), "host": str(api.call("getLobbyData", id, "host")),
		"private": str(api.call("getLobbyData", id, "private")) == "1",
		"players": int(api.call("getNumLobbyMembers", id)), "max": int(api.call("getLobbyMemberLimit", id)),
		"address": "", "port": 0, "source": "steam", "steam_lobby": id}
