extends Control
## Pre-game room. Everybody: 1) picks a ship  2) locks in  (or joins a locked ship as crew).
## Host: starts the game when everyone is locked, or force-launches when the timer ran out
## (players without a ship then get a random premade one). Widgets live in scenes/lobby.tscn.

@onready var lobby_title_label: Label = %LobbyTitleLabel
@onready var timer_label: Label = %TimerLabel
@onready var ship_list: ItemList = %ShipList
@onready var ship_info_label: Label = %ShipInfoLabel
@onready var lock_button: Button = %LockButton
@onready var player_tree: Tree = %PlayerTree
@onready var join_crew_button: Button = %JoinCrewButton
@onready var leave_crew_button: Button = %LeaveCrewButton
@onready var start_button: Button = %StartButton
@onready var status_label: Label = %StatusLabel

var _ship_paths: Array[String] = []
var _chosen_valid: bool = false
var _selected_player: int = -1


func _ready() -> void:
	lobby_title_label.text = "%s%s" % [Net.lobby_name, "  (private)" if Net.lobby_private else ""]
	player_tree.set_column_title(0, "Pilot")
	player_tree.set_column_title(1, "Ship")
	player_tree.set_column_title(2, "Seats")
	player_tree.set_column_title(3, "Status")
	player_tree.set_column_expand(0, true)
	player_tree.set_column_expand(1, true)
	player_tree.set_column_expand(2, false)
	player_tree.set_column_custom_minimum_width(2, 70)
	player_tree.set_column_custom_minimum_width(3, 100)
	player_tree.select_mode = Tree.SELECT_ROW
	for e in ShipDesign.list_ships():
		ship_list.add_item(("[premade] " if e["premade"] else "[custom] ") + e["name"])
		_ship_paths.append(e["path"])
	Net.roster_changed.connect(_refresh_all)
	start_button.visible = Net.is_host()
	_refresh_all()


func _process(_dt: float) -> void:
	var t := int(ceil(Net.lobby_seconds_left))
	timer_label.text = "%d:%02d" % [int(t / 60.0), t % 60] if t > 0 else "Time is up"
	timer_label.modulate = Color(1, 0.5, 0.4) if t <= 0 else Color(1, 1, 1)
	_update_start_button()


# ---------------------------------------------------------------- my entry
func _me() -> Dictionary:
	return Net.players.get(Net.my_id(), {})


func _on_ship_selected(index: int) -> void:
	var blob := ShipDesign.read_blob(_ship_paths[index])
	var d := ShipDesign.from_blob(blob)
	if d == null:
		return
	var errors := d.validate()
	_chosen_valid = errors.is_empty()
	var p := d.compute_props()
	ship_info_label.text = "%s: %d modules, %d thrusters, %d turrets, %.0f kg, %d seat%s%s" % [d.ship_name, d.modules.size(),
		p["thrusters"].size(), p["turrets"].size(), p["mass"], d.crew_capacity(), "" if d.crew_capacity() == 1 else "s",
		"" if _chosen_valid else "\nINVALID: " + errors[0]]
	if _chosen_valid:
		Net.submit_ship(blob)
	_refresh_all()


func _on_lock_pressed() -> void:
	Net.submit_lock(not _me().get("locked", false))


func _on_join_crew_pressed() -> void:
	if _selected_player > 0:
		Net.submit_join_crew(_selected_player)


func _on_leave_crew_pressed() -> void:
	Net.submit_leave_crew()


# ---------------------------------------------------------------- players list
func _refresh_all() -> void:
	_refresh_tree()
	var me := _me()
	var is_crew: bool = me.get("crew_of", 0) != 0
	var locked: bool = me.get("locked", false)
	ship_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if (locked or is_crew) else Control.MOUSE_FILTER_STOP
	ship_list.modulate = Color(1, 1, 1, 0.5) if (locked or is_crew) else Color(1, 1, 1, 1)
	lock_button.visible = not is_crew
	lock_button.text = "Unlock ship (also releases your crew)" if locked else "Lock in ship"
	lock_button.disabled = not locked and (me.get("ship", "") == "")
	leave_crew_button.visible = is_crew
	_update_join_crew_button()
	_update_start_button()


func _refresh_tree() -> void:
	player_tree.clear()
	var root := player_tree.create_item()
	var items := {}
	# captains / solo players first
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		if p["crew_of"] != 0:
			continue
		var it := player_tree.create_item(root)
		it.set_text(0, "%s%s%s" % [p["name"], "  (host)" if id == 1 else "", "  (you)" if id == Net.my_id() else ""])
		it.set_text(1, p["ship_name"] if p["ship_name"] != "" else "- not chosen -")
		if p["ship"] != "":
			it.set_text(2, "%d / %d" % [1 + Net.crew_count(id), p["seats"]])
		it.set_text(3, "LOCKED" if p["locked"] else "choosing")
		it.set_custom_color(3, Color(0.5, 1, 0.6) if p["locked"] else Color(1, 0.8, 0.4))
		it.set_metadata(0, id)
		items[id] = it
	# crew nested under their captain
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		if p["crew_of"] != 0 and items.has(p["crew_of"]):
			var it := player_tree.create_item(items[p["crew_of"]])
			it.set_text(0, "%s%s" % [p["name"], "  (you)" if id == Net.my_id() else ""])
			it.set_text(3, "CREW")
			it.set_custom_color(3, Color(0.5, 0.8, 1))
			it.set_metadata(0, id)
	for it in items.values():
		it.collapsed = false
		if int(it.get_metadata(0)) == _selected_player:
			it.select(0)


func _on_player_selected() -> void:
	var it := player_tree.get_selected()
	_selected_player = int(it.get_metadata(0)) if it != null else -1
	_update_join_crew_button()


func _on_player_deselected() -> void:
	_selected_player = -1
	_update_join_crew_button()


func _update_join_crew_button() -> void:
	var me := _me()
	var ok: bool = _selected_player > 0 and _selected_player != Net.my_id() and Net.seats_free(_selected_player) > 0 \
		and me.get("crew_of", 0) == 0 and Net.crew_count(Net.my_id()) == 0
	join_crew_button.disabled = not ok
	if _selected_player > 0 and _selected_player != Net.my_id():
		var target: Dictionary = Net.players.get(_selected_player, {})
		if target.get("crew_of", 0) != 0 or not target.get("locked", false):
			join_crew_button.tooltip_text = "That player has not locked in a ship yet."
		elif Net.seats_free(_selected_player) <= 0:
			join_crew_button.tooltip_text = "That ship is full."
		elif Net.crew_count(Net.my_id()) > 0:
			join_crew_button.tooltip_text = "Unlock your own ship first (your crew would be released)."
		else:
			join_crew_button.tooltip_text = ""


# ---------------------------------------------------------------- start / leave
func _update_start_button() -> void:
	if not Net.is_host():
		status_label.text = "Waiting for the host to start. Lock in your ship (or join a crew) before the timer ends."
		return
	var waiting := 0
	for id in Net.players:
		if not Net.players[id]["locked"]:
			waiting += 1
	start_button.disabled = not Net.can_start()
	if Net.all_locked():
		start_button.text = "START GAME"
		status_label.text = "Everyone is locked in."
	elif Net.lobby_seconds_left <= 0.0:
		start_button.text = "FORCE LAUNCH"
		status_label.text = "%d player(s) not locked in. Players with no ship get a random premade one." % waiting
	else:
		start_button.text = "Waiting for %d player(s)..." % waiting
		status_label.text = "Force launch unlocks when the timer reaches zero."
	status_label.text += "\n" + Net.nat.message   # internet status (UPnP / public address) so the host can see why a friend cannot join


func _on_start_pressed() -> void:
	Net.start_game()


func _on_leave_pressed() -> void:
	Net.leave()
	Game.go_to(Game.BROWSER_SCENE)
