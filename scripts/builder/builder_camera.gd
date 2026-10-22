class_name BuilderCamera
extends Node3D
## Orbit camera of the ship builder (node "CameraRig" with child "Camera").
## RMB drag = orbit, MMB drag or Shift+RMB drag = pan, mouse wheel = zoom.

signal view_changed

@export var min_distance: float = 1.5
@export var max_distance: float = 80.0

## While true (e.g. during a G/R/S transform) the camera ignores the mouse.
var locked: bool = false

var yaw: float = 0.6
var pitch: float = -0.45
var distance: float = 9.0
var pivot: Vector3 = Vector3.ZERO

var _orbiting: bool = false
var _panning: bool = false

@onready var camera: Camera3D = $Camera


func _ready() -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if locked:
		_orbiting = false
		_panning = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed and not mb.shift_pressed
				_panning = mb.pressed and mb.shift_pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(distance * 0.9, min_distance)
				_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(distance * 1.1, max_distance)
				_apply()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch - mm.relative.y * 0.006, -1.5, 1.5)
			_apply()
		elif _panning:
			pivot += (-global_transform.basis.x * mm.relative.x + global_transform.basis.y * mm.relative.y) * (distance * 0.0016)
			_apply()


## Smoothly-less "frame this": centre the view on `point` and zoom so `radius` fits.
func focus_on(point: Vector3, radius: float) -> void:
	pivot = point
	distance = clampf(radius * 3.0, min_distance, max_distance)
	_apply()


func _apply() -> void:
	position = pivot
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0, 0, distance)
	view_changed.emit()
