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
	var n := spawn_points.get_child_count()
	var marker := spawn_points.get_child(_spawn_index % n) as Marker3D
	_spawn_index += 1
	spawner.spawn({"peer": id, "design": entry["ship"], "name": entry["name"], "pos": marker.global_position})


func _on_peer_left(id: int) -> void:
	var s := ships_root.get_node_or_null(str(id))
	if s != null:
		s.queue_free()


## Called by a ship's owner when its Commander dies. Runs on the host only.
@rpc("any_peer", "call_local", "reliable")
func report_death(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	await get_tree().create_timer(Data.RESPAWN_DELAY).timeout
	var old := ships_root.get_node_or_null(str(peer_id))
	if old != null:
		old.queue_free()
		await get_tree().create_timer(0.3).timeout
	if Net.players.has(peer_id):
		_spawn_for_peer(peer_id)


# ---- every peer ------------------------------------------------------------
func _make_ship(data: Dictionary) -> Node:
	var ship := SHIP_SCENE.instantiate() as Ship
	ship.name = str(data["peer"])
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
