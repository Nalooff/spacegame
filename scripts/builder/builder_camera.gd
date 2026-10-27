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

## Standard views: name -> [yaw, pitch]. The ship's nose points to -Z; "front" looks at the nose.
const VIEWS := {
	"front": [PI, 0.0], "back": [0.0, 0.0], "right": [PI * 0.5, 0.0], "left": [-PI * 0.5, 0.0],
	"top": [0.0, -PI * 0.5], "bottom": [0.0, PI * 0.5], "perspective": [0.6, -0.45],
}
var orthographic: bool = false

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


## Jump to a standard view (see VIEWS). Standard views of a ship are usually wanted without perspective.
func set_view(view_name: String) -> void:
	if not VIEWS.has(view_name):
		return
	yaw = VIEWS[view_name][0]
	pitch = VIEWS[view_name][1]
	_apply()


func set_orthographic(on: bool) -> void:
	orthographic = on
	_apply()


## Smoothly-less "frame this": centre the view on `point` and zoom so `radius` fits.
func focus_on(point: Vector3, radius: float) -> void:
	pivot = point
	distance = clampf(radius * 3.0, min_distance, max_distance)
	_apply()


func _apply() -> void:
	position = pivot
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0, 0, 150.0 if orthographic else distance)   # orthographic: far back so nothing is cut
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if orthographic else Camera3D.PROJECTION_PERSPECTIVE
	camera.size = distance * 0.9        # orthographic: how many metres fit on screen (zoom = distance)
	camera.near = 0.05
	camera.far = 600.0
	view_changed.emit()
