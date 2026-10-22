class_name BuilderTransformTool
extends Node
## Blender-style G / R / S tool. Node "TransformTool" in ship_builder.tscn.
##
##   begin(GRAB, vertex_ids, mouse)   start moving these vertices with the mouse
##   update(mouse)                    call on every mouse move
##   set_axis(Vector3.RIGHT)          X / Y / Z key: lock to an axis (press again = free)
##   confirm() / cancel()
##
## It only changes vertex POSITIONS (design.vertices), never the topology.

enum Kind { NONE, GRAB, ROTATE, SCALE }

signal finished(confirmed: bool)

var kind: Kind = Kind.NONE
var axis_lock: Vector3 = Vector3.ZERO
## Quick-drag mode: the move ends when the mouse button is released (used for click-and-drag).
var confirm_on_release: bool = false

var builder: ShipBuilder
var _ids: PackedInt32Array = PackedInt32Array()
var _original: Dictionary = {}   # vertex id -> position when the tool started
var _pivot: Vector3 = Vector3.ZERO
var _start_mouse: Vector2 = Vector2.ZERO


func is_active() -> bool:
	return kind != Kind.NONE


func begin(new_kind: Kind, vertex_ids: PackedInt32Array, mouse: Vector2, quick_drag: bool = false) -> void:
	if vertex_ids.is_empty():
		return
	kind = new_kind
	confirm_on_release = quick_drag
	axis_lock = Vector3.ZERO
	_ids = vertex_ids
	_original.clear()
	_pivot = Vector3.ZERO
	for id in _ids:
		_original[id] = builder.design.vertices[id]
		_pivot += builder.design.vertices[id]
	_pivot /= _ids.size()
	_start_mouse = mouse
	builder.camera_rig.locked = true


func set_axis(axis: Vector3) -> void:
	axis_lock = Vector3.ZERO if axis_lock == axis else axis
	update(builder.get_viewport().get_mouse_position())


func update(mouse: Vector2) -> void:
	match kind:
		Kind.GRAB: _update_grab(mouse)
		Kind.ROTATE: _update_rotate(mouse)
		Kind.SCALE: _update_scale(mouse)
	builder.on_geometry_changed()


func confirm() -> void:
	_end(true)


func cancel() -> void:
	for id in _ids:
		builder.design.vertices[id] = _original[id]
	_end(false)


func _end(confirmed: bool) -> void:
	kind = Kind.NONE
	axis_lock = Vector3.ZERO
	builder.camera_rig.locked = false
	finished.emit(confirmed)


# ------------------------------------------------------------------ the three tools
func _update_grab(mouse: Vector2) -> void:
	var cam := builder.camera
	var delta := Vector3.ZERO
	if axis_lock == Vector3.ZERO:
		# slide on the plane that faces the camera and goes through the pivot
		var plane := Plane(-cam.global_transform.basis.z, _pivot)
		var p0: Variant = plane.intersects_ray(cam.project_ray_origin(_start_mouse), cam.project_ray_normal(_start_mouse))
		var p1: Variant = plane.intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
		if p0 == null or p1 == null:
			return
		delta = (p1 as Vector3) - (p0 as Vector3)
	else:
		var t0 := _axis_parameter(cam.project_ray_origin(_start_mouse), cam.project_ray_normal(_start_mouse))
		var t1 := _axis_parameter(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
		if is_nan(t0) or is_nan(t1):
			return
		delta = axis_lock * (t1 - t0)
	var snap := builder.snap_step
	if snap > 0.0:
		delta = (_pivot + delta).snapped(Vector3.ONE * snap) - _pivot
		if axis_lock != Vector3.ZERO:
			delta = axis_lock * delta.dot(axis_lock)
	for id in _ids:
		builder.design.vertices[id] = _original[id] + delta


func _update_rotate(mouse: Vector2) -> void:
	var cam := builder.camera
	var centre := cam.unproject_position(_pivot)
	var angle := (_start_mouse - centre).angle_to(mouse - centre)
	var axis := -cam.global_transform.basis.z           # looking direction
	if axis_lock != Vector3.ZERO:
		if axis_lock.dot(axis) < 0.0:
			angle = -angle                               # keep the turning direction natural
		axis = axis_lock
	if Input.is_key_pressed(KEY_CTRL):
		angle = snappedf(angle, deg_to_rad(15.0))
	var basis := Basis(axis.normalized(), angle)
	for id in _ids:
		builder.design.vertices[id] = _pivot + basis * ((_original[id] as Vector3) - _pivot)


func _update_scale(mouse: Vector2) -> void:
	var centre := builder.camera.unproject_position(_pivot)
	var start_len := maxf((_start_mouse - centre).length(), 20.0)
	var factor := maxf((mouse - centre).length() / start_len, 0.01)
	for id in _ids:
		var rel: Vector3 = (_original[id] as Vector3) - _pivot
		if axis_lock == Vector3.ZERO:
			rel *= factor
		else:
			rel += axis_lock * rel.dot(axis_lock) * (factor - 1.0)
		builder.design.vertices[id] = _pivot + rel


## Where on the locked axis line (through the pivot) the mouse ray comes closest. NAN if parallel.
func _axis_parameter(ray_origin: Vector3, ray_dir: Vector3) -> float:
	var w0 := _pivot - ray_origin
	var b := axis_lock.dot(ray_dir)
	var d := axis_lock.dot(w0)
	var e := ray_dir.dot(w0)
	var denom := 1.0 - b * b
	if denom < 0.0001:
		return NAN
	return (b * e - d) / denom
