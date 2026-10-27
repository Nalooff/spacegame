extends Camera3D
## First-person camera of CREW mode (see ShipStations). It sits at the player's station inside the ship and follows the
## ship; the mouse looks around (relative to the ship). In commander mode it steps aside and the chase camera is used.
## Esc releases / recaptures the mouse (the cursor is needed for the HUD buttons).

var ship: Ship
var _yaw: float = 0.0
var _pitch: float = 0.0
var _captured: bool = true
var _last_station: int = -1
var _chase: Camera3D


func _ready() -> void:
	_chase = get_node_or_null("../CameraRig/Pivot/Camera3D")
	BusEvent.local_ship_changed.connect(func(s: Ship): ship = s)
	ship = Data.local_ship
	fov = 80.0
	far = 6000.0
	near = 0.1


func _active() -> bool:
	return is_instance_valid(ship) and ship.alive and ship.is_multiplayer_authority() and not ship.stations.is_commander_mode()


func _unhandled_input(event: InputEvent) -> void:
	if not _active():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.0025
		_pitch = clampf(_pitch - mm.relative.y * 0.0025, -1.5, 1.5)
	elif event.is_action_pressed("toggle_autopilot_panel"):
		_captured = not _captured


func _process(_dt: float) -> void:
	if not _active():
		if current and _chase != null:
			_chase.make_current()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if not current:
		make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _captured else Input.MOUSE_MODE_VISIBLE
	var st := ship.stations
	if st.current != _last_station and not st.walking:      # arrived at a new station: look forward
		_last_station = st.current
		_yaw = 0.0
		_pitch = 0.0
	var look := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	global_transform = ship.global_transform * Transform3D(look, st.eye_position())
