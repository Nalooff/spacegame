extends Node3D
## Orbit camera that follows `target`. RMB drag = orbit, wheel = zoom.
## Node layout (in game_world.tscn): CameraRig > Pivot > Camera3D.

@export var min_dist: float = 4.0
@export var max_dist: float = 80.0

var target: Node3D
var _yaw: float = 0.0
var _pitch: float = -0.35
var _dist: float = 14.0
var _orbit: bool = false


func _ready() -> void:
	BusEvent.local_ship_changed.connect(_on_local_ship_changed)
	target = Data.local_ship


func _on_local_ship_changed(ship: Ship) -> void:
	target = ship


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbit = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(_dist * 0.9, min_dist)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(_dist * 1.1, max_dist)
	elif event is InputEventMouseMotion and _orbit:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.005
		_pitch = clampf(_pitch - mm.relative.y * 0.005, -1.45, 1.45)


func _process(_dt: float) -> void:
	if is_instance_valid(target):
		global_position = target.global_position
	rotation = Vector3(_pitch, _yaw, 0.0)
	$Pivot/Camera3D.position = Vector3(0, 0, _dist)
