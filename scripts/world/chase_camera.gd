extends Node3D
## Orbit camera that follows `target`. RMB drag = orbit, wheel = zoom.
## Node layout (in game_world.tscn): CameraRig > Pivot > Camera3D.

@export var min_dist: float = 10.0
@export var max_dist: float = 300.0

var target: Node3D
var _yaw: float = 0.0
var _pitch: float = -0.35
var _dist: float = 40.0
var _dist_set: bool = false
var _orbit: bool = false


func _ready() -> void:
	BusEvent.local_ship_changed.connect(_on_local_ship_changed)
	target = Data.local_ship
	_fit_to_ship()


func _on_local_ship_changed(ship: Ship) -> void:
	target = ship
	_fit_to_ship()


## The camera range follows the SIZE of the ship: a 30 m fighter is watched from tens of metres, a 2 km Dreadnought from
## a kilometre or two (and the mouse wheel zooms in proportion, so a few clicks cover the whole range).
func _fit_to_ship() -> void:
	var ship_len := 30.0
	if is_instance_valid(target) and target is Ship and (target as Ship).design != null:
		ship_len = maxf((target as Ship).design.extent_length(), 10.0)
	min_dist = maxf(10.0, ship_len * 0.04)
	max_dist = maxf(300.0, ship_len * 6.0)
	_dist = clampf(maxf(Prefs.cam_dist, ship_len * 0.9), min_dist, max_dist)
	_dist_set = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbit = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(_dist * 0.88, min_dist)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(_dist * 1.136, max_dist)
	elif event is InputEventMouseMotion and _orbit:
		var mm := event as InputEventMouseMotion
		var k := 0.005 * Prefs.cam_sens
		_yaw -= mm.relative.x * k
		_pitch = clampf(_pitch - mm.relative.y * k * (-1.0 if Prefs.cam_invert_y else 1.0), -1.45, 1.45)


func _process(_dt: float) -> void:
	if not _dist_set:
		_fit_to_ship()
	$Pivot/Camera3D.fov = Prefs.fov
	if is_instance_valid(target):
		global_position = target.global_position
	rotation = Vector3(_pitch, _yaw, 0.0)
	$Pivot/Camera3D.position = Vector3(0, 0, _dist)
