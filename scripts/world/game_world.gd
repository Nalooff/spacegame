extends Node3D
## The multiplayer arena. Fixed nodes (spawner, spawn points, projectile pool, camera,
## landmarks, HUD, target marker) are all in scenes/game_world.tscn.
## The host spawns one Ship per peer through the MultiplayerSpawner; each peer owns
## (simulates) its own ship.

const SHIP_SCENE := preload("res://scenes/ship.tscn")

@onready var spawner: MultiplayerSpawner = $ShipSpawner
@onready var ships_root: Node3D = $Ships
@onready var spawn_points: Node3D = $SpawnPoints
@onready var hud: CanvasLayer = $HUD
@onready var target_marker: MeshInstance3D = $TargetMarker

var _local_ship: Ship
var _spawn_index: int = 0
var _derelict_counter: int = 0


func _ready() -> void:
	add_to_group("world")
	spawner.spawn_function = _make_ship
	if multiplayer.is_server():
		Net.peer_ready_in_world.connect(_spawn_for_peer)
		Net.peer_left.connect(_on_peer_left)
		Net.crew_orphaned.connect(_spawn_for_peer) # captain left: that crew member gets their own ship
	hud.leave_requested.connect(_on_leave)
	Net.world_ready.rpc_id(1) # tell the host this peer's world is loaded


# ---- host side -------------------------------------------------------------
func _spawn_for_peer(id: int) -> void:
	var entry: Dictionary = Net.players.get(id, {})
	if entry.is_empty() or entry["crew_of"] != 0:
		return # crew members share their captain's ship
	if entry["ship"] == "":
		Net._give_random_ship(id)     # e.g. a crew member whose ship was lost: they get a premade one
		Net._distribute_blobs()
		entry = Net.players[id]
	Net.srv_reset_seats(id)
	var n := spawn_points.get_child_count()
	var marker := spawn_points.get_child(_spawn_index % n) as Marker3D
	_spawn_index += 1
	spawner.spawn({"peer": id, "design": entry["ship"], "name": entry["name"], "pos": marker.global_position})


func _on_peer_left(id: int) -> void:
	var s := ships_root.get_node_or_null(str(id))
	if s != null:
		s.queue_free()


## Called by a ship's owner when its last Commander is gone. Runs on the host only.
## `ship_name` is the node name: a peer id for a flown ship, "d<N>" for a derelict (a torn-off part nobody flies).
@rpc("any_peer", "call_local", "reliable")
func report_death(ship_name: String) -> void:
	if not multiplayer.is_server():
		return
	await get_tree().create_timer(Data.RESPAWN_DELAY).timeout
	var old := ships_root.get_node_or_null(ship_name)
	if old != null:
		old.queue_free()
		await get_tree().create_timer(0.3).timeout
	if ship_name.is_valid_int() and Net.players.has(int(ship_name)):
		_spawn_for_peer(int(ship_name))


## A ship lost commanders and/or split (sent by the ship's owner, see Ship._check_structure). Host only:
## re-seats people, decides who flies each new part and spawns the new ships.
##   leaving   = [PackedInt32Array of module ids of each part that became a ship]
##   payloads  = [{xf, com_child, vel, ang, hp, max_hp, vol0}] (same order)
@rpc("any_peer", "call_local", "reliable")
func structure_changed(ship_name: String, alive_cmds: PackedInt32Array, leaving: Array, payloads: Array) -> void:
	if not multiplayer.is_server():
		return
	var parent := ships_root.get_node_or_null(ship_name) as Ship
	if parent == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != parent.get_multiplayer_authority():
		return   # only the owner of a ship may split it
	var captain := int(ship_name) if ship_name.is_valid_int() else 0
	var pilots: Array = Net.srv_structure_changed(captain, Array(alive_cmds), leaving)
	for gi in leaving.size():
		var pilot: int = pilots[gi]
		var pl: Dictionary = payloads[gi]
		var xf: Transform3D = pl["xf"]
		var child_name := str(pilot) if pilot != 0 else "d%d" % _derelict_counter
		_derelict_counter += 1
		var existing := ships_root.get_node_or_null(child_name)
		if existing != null:
			existing.queue_free()   # (a flown ship of that peer cannot exist: they were crew)
			child_name += "_%d" % _derelict_counter
		spawner.spawn({"peer": pilot if pilot != 0 else parent.get_multiplayer_authority(), "name": child_name,
			"design": "", "parent": ship_name, "ids": leaving[gi], "pos": xf * (pl["com_child"] as Vector3),
			"basis": xf.basis, "vel": pl["vel"], "ang": pl["ang"], "hp": pl["hp"], "max_hp": pl["max_hp"],
			"vol0": pl["vol0"], "pilot": pilot})


# ---- every peer ------------------------------------------------------------
func _make_ship(data: Dictionary) -> Node:
	var ship := SHIP_SCENE.instantiate() as Ship
	ship.name = str(data["name"]) if data.has("parent") else str(data["peer"])
	if data.has("parent"):
		# A part torn off another ship: cut the same modules out of OUR copy of the parent (deterministic).
		var parent := ships_root.get_node_or_null(str(data["parent"])) as Ship
		if parent != null and parent.design != null:
			ship.design_blob = parent.design.extract(data["ids"]).to_bytes()
		else:
			push_error("Split: parent ship %s not found; the new part is lost" % data["parent"])
			ship.design_blob = ShipDesign.read_blob("res://ships/Dart.json")
		ship.initial_hp = data["hp"]
		ship.initial_max_hp = data["max_hp"]
		ship.initial_volume = data["vol0"]
		var pn: String = Net.players.get(int(data["pilot"]), {}).get("name", "") if int(data["pilot"]) != 0 else "Wreck"
		ship.pilot_name = pn
		ship.transform = Transform3D(data["basis"], data["pos"])
		ship.linear_velocity = data["vel"]
		ship.angular_velocity = data["ang"]
		ship.set_multiplayer_authority(int(data["peer"]))
		return ship
	var blob: PackedByteArray = Net.blobs.get(data["design"], PackedByteArray())
	if blob.is_empty():
		push_error("Ship %s was not received; flying a premade ship instead" % data["design"])
		blob = ShipDesign.read_blob("res://ships/Dart.json")
	ship.design_blob = blob
	ship.pilot_name = data["name"]
	ship.position = data["pos"]
	ship.set_multiplayer_authority(int(data["peer"]))
	return ship


func _process(_dt: float) -> void:
	# a crew member watches (and shoots from) the captain's ship
	var mine := ships_root.get_node_or_null(str(Net.ship_owner_of(multiplayer.get_unique_id()))) as Ship
	if mine != _local_ship:
		_local_ship = mine
		Data.local_ship = mine
		BusEvent.local_ship_changed.emit(mine) # HUD and camera listen to this
	if is_instance_valid(_local_ship) and _local_ship.alive:
		target_marker.visible = _local_ship.is_multiplayer_authority() and _local_ship.autopilot.is_active()
		target_marker.global_position = _local_ship.autopilot.target
	else:
		target_marker.visible = false


func _on_leave() -> void:
	Net.leave()
	Game.go_to(Game.MENU_SCENE)
