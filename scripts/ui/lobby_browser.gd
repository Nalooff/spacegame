extends Control
## "Play" screen: host a lobby (name, public/private, password) or pick one from the list of open lobbies.
## Lobbies are found automatically (Net.directory, see scripts/net/lobby_directory.gd): nobody types an IP address.
## Widgets live in scenes/lobby_browser.tscn.

const LOCK_ICON := preload("res://assets/lock.png")

@onready var pilot_name_edit: LineEdit = %PilotNameEdit
@onready var lobby_name_edit: LineEdit = %LobbyNameEdit
@onready var visibility_picker: OptionButton = %VisibilityPicker
@onready var password_row: HBoxContainer = %PasswordRow
@onready var password_edit: LineEdit = %PasswordEdit
@onready var host_status_label: Label = %HostStatusLabel
@onready var lobby_tree: Tree = %LobbyTree
@onready var join_button: Button = %JoinLobbyButton
@onready var browse_status_label: Label = %BrowseStatusLabel
@onready var password_dialog: ConfirmationDialog = %PasswordDialog
@onready var join_password_edit: LineEdit = %JoinPasswordEdit

var _selected_id: int = -1
var _signature: String = ""      # to rebuild the tree only when the list really changed
var _refresh_timer: float = 0.0
var _board_timer: float = 15.0
var _tried: String = ""
var _tried_list: Array[String] = []
var _candidates: Array[String] = []
var _password: String = ""
var _joining: Dictionary = {}    # the lobby we are trying to enter


func _ready() -> void:
	Net.leave() # always start from a clean offline state
	pilot_name_edit.text = Data.player_name
	lobby_tree.set_column_title(0, "Lobby")
	lobby_tree.set_column_title(1, "Host")
	lobby_tree.set_column_title(2, "Players")
	lobby_tree.set_column_expand(1, true)
	lobby_tree.set_column_custom_minimum_width(0, 220)
	lobby_tree.set_column_custom_minimum_width(2, 80)
	lobby_tree.set_column_expand(2, false)
	lobby_tree.select_mode = Tree.SELECT_ROW
	Net.joined.connect(_on_joined)
	Net.join_rejected.connect(_on_join_rejected)
	Net.connection_failed.connect(_on_connection_failed)
	var err := Net.directory.listen()
	if err != OK:
		browse_status_label.text = "Cannot search for lobbies (UDP port %d busy, error %d). You can still host." % [Data.DISCOVERY_PORT, err]
	Net.board.refresh()
	Net.nat.detect_own_ip()   # lets us notice lobbies on our own network (they must be joined by their LAN address)
	host_status_label.text = Data.notice
	Data.notice = ""


func _exit_tree() -> void:
	Net.directory.stop_listening()


func _process(dt: float) -> void:
	_refresh_timer -= dt
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.4
	_board_timer -= 0.4
	if _board_timer <= 0.0:
		_board_timer = 15.0
		Net.board.refresh()   # internet list, every 15 s (and on the Refresh button)
	_rebuild_list()


func _rebuild_list() -> void:
	var lobbies := Net.all_lobbies()
	var sig := JSON.stringify(lobbies) + str(_selected_id)
	if sig == _signature:
		return
	_signature = sig
	lobby_tree.clear()
	var root := lobby_tree.create_item()
	for l in lobbies:
		var item := lobby_tree.create_item(root)
		item.set_text(0, l["name"])
		if l["private"]:
			item.set_icon(0, LOCK_ICON)
			item.set_tooltip_text(0, "Private: needs a password")
		item.set_text(1, l["host"] + ("  (internet)" if l.get("source", "") == "internet" else "  (LAN)"))
		item.set_text(2, "%d / %d" % [l["players"], l["max"]])
		item.set_metadata(0, l["id"])
		if l["id"] == _selected_id:
			item.select(0)
	if lobbies.is_empty():
		browse_status_label.text = "No open lobbies found. Host your own, or press Refresh. " + Net.board.status
	else:
		browse_status_label.text = "%d open lobb%s. Double-click to join." % [lobbies.size(), "y" if lobbies.size() == 1 else "ies"]
	if _find(_selected_id).is_empty():
		_selected_id = -1
		join_button.disabled = true


func _find(id: int) -> Dictionary:
	for l in Net.all_lobbies():
		if l["id"] == id:
			return l
	return {}


# ---------------------------------------------------------------- host form
func _on_pilot_name_changed(text: String) -> void:
	Data.player_name = text.strip_edges() if text.strip_edges() != "" else "Pilot"


func _on_visibility_selected(index: int) -> void:
	password_row.visible = index == 1


func _on_create_pressed() -> void:
	var is_private := visibility_picker.selected == 1
	if is_private and password_edit.text == "":
		host_status_label.text = "A private lobby needs a password."
		return
	var err := Net.host_lobby(lobby_name_edit.text, is_private, password_edit.text)
	if err != OK:
		host_status_label.text = "Could not create the lobby (error %d)." % err
		return
	Game.go_to(Game.LOBBY_SCENE)


# ---------------------------------------------------------------- lobby list
func _on_lobby_selected() -> void:
	var item := lobby_tree.get_selected()
	if item == null:
		return
	_selected_id = int(item.get_metadata(0))
	join_button.disabled = false


func _on_refresh_pressed() -> void:
	Net.directory.clear()
	Net.board.refresh()
	_signature = ""
	browse_status_label.text = "Searching..."


func _on_join_pressed() -> void:
	var lobby := _find(_selected_id)
	if lobby.is_empty():
		return
	_joining = lobby
	if lobby["private"]:
		join_password_edit.text = ""
		password_dialog.popup_centered()
		join_password_edit.grab_focus()
	else:
		_connect("")


func _on_password_confirmed() -> void:
	_connect(join_password_edit.text)


func _connect(password: String) -> void:
	# Addresses to try, in order. Same router as the host (our public IP equals theirs): the public address
	# usually does not loop back, so the local one goes first. Otherwise the public one goes first.
	var pub: String = _joining["address"]
	var lan: String = _joining.get("lan", "")
	_candidates.clear()
	if lan != "" and Net.nat.own_ip == pub:
		_candidates = [lan, pub]
	elif lan != "":
		_candidates = [pub, lan]
	else:
		_candidates = [pub]
	_password = password
	_tried_list.clear()
	_try_next_address()


## Start a connection to the next candidate address. Returns false when there is none left.
func _try_next_address() -> bool:
	if _candidates.is_empty():
		return false
	var address: String = _candidates.pop_front()
	_tried = "%s:%d" % [address, _joining["port"]]
	_tried_list.append(_tried)
	var err := Net.join_lobby(address, _joining["port"], _password, _joining["name"])
	if err != OK:
		browse_status_label.text = "Could not connect (error %d)." % err
		return false
	browse_status_label.text = "Joining '%s' via %s ..." % [_joining["name"], _tried]
	join_button.disabled = true
	return true


## The host did not answer on that address (not a refusal): try the next address, if any.
func _on_connection_failed() -> void:
	if _try_next_address():
		return
	_tried = ", ".join(_tried_list)
	_on_join_rejected("Could not reach the host.")


func _on_joined() -> void:
	Game.go_to(Game.LOBBY_SCENE)


func _on_join_rejected(reason: String) -> void:
	browse_status_label.text = "Could not join (%s): %s" % [_tried, reason]
	if reason.begins_with("Could not reach"):
		browse_status_label.text += "\nThe host's router probably blocks the connection (UPnP off / port 24565 UDP not forwarded / firewall)."
	join_button.disabled = _selected_id < 0
	# Net.leave() ran: listening continues, nothing else to reset


func _on_back_pressed() -> void:
	Game.go_to(Game.MENU_SCENE)
