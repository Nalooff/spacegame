class_name OrderControls
extends Node3D
## Click-to-order flying for the schemes that do not steer by hand (FlightControls.Scheme POINT_CIRCLE and EVE_ORDERS).
## Lives in the world scene. Gives the local ship autopilot orders; the ship itself does the flying.
##
## POINT_CIRCLE (Nebulous Fleet Command): press G -> a ring follows the cursor over the horizontal plane through the ship's
##   height (x, z). Hold ALT -> the cursor moves the ring up / down instead (y), x and z stay. Left click = fly there,
##   Esc or right click = cancel.
## EVE_ORDERS: double click in space = fly that way; Z approach, O orbit, K keep at range of the locked enemy (R locks).

signal order_given(text: String)

const RING_COLOR := Color(0.4, 0.9, 1.0)

var active: bool = false           ## the move circle is open
var point: Vector3 = Vector3.ZERO  ## its position
var _ship: Ship
var _ring: MeshInstance3D
var _drop: MeshInstance3D          ## the vertical line + shadow ring at the ship's height
var _label: Label3D
var _ring_mesh: TorusMesh


func _ready() -> void:
	_ring_mesh = TorusMesh.new()
	_ring = _make_ring(RING_COLOR)
	_drop = _make_ring(Color(0.4, 0.9, 1.0, 0.35))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0009
	_label.modulate = RING_COLOR
	add_child(_label)
	_show(false)


func _make_ring(col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.97
	t.outer_radius = 1.0
	m.mesh = t
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	m.material_override = mat
	add_child(m)
	return m


func _show(on: bool) -> void:
	_ring.visible = on
	_drop.visible = on
	_label.visible = on


# ------------------------------------------------------------------ pure helpers (tested)
## Where a ray (origin, direction) crosses the horizontal plane at height `y`. Returns {"ok": bool, "point": Vector3}.
static func plane_point(origin: Vector3, dir: Vector3, y: float, max_dist: float = 8000.0) -> Dictionary:
	if absf(dir.y) < 1e-4:
		return {"ok": false, "point": origin}
	var t := (y - origin.y) / dir.y
	if t < 0.0 or t > max_dist:
		return {"ok": false, "point": origin}
	return {"ok": true, "point": origin + dir * t}


## Raise / lower the circle by a mouse movement of `dy` pixels (up = positive height); scales with the camera distance.
static func adjust_height(y: float, dy_pixels: float, cam_distance: float) -> float:
	return y - dy_pixels * 0.0025 * maxf(cam_distance, 10.0)


## The enemy contact whose estimated position is closest to a ray and within `max_angle` radians of it, or null.
static func pick_contact(contacts: Array, origin: Vector3, dir: Vector3, max_angle: float = 0.06) -> Node:
	var best: Node = null
	var best_a := max_angle
	for c in contacts:
		var s: Variant = c["ship"]
		if not is_instance_valid(s):
			continue
		var to: Vector3 = (c["est_pos"] as Vector3) - origin
		if to.length() < 1.0:
			continue
		var a := dir.angle_to(to)
		if a < best_a:
			best_a = a
			best = s
	return best


# ------------------------------------------------------------------ live
func _local() -> Ship:
	var s := Data.local_ship
	if is_instance_valid(s) and s.alive and s.is_multiplayer_authority() and s.i_fly():
		return s
	return null


func _cam() -> Camera3D:
	return get_viewport().get_camera_3d()


func _process(_dt: float) -> void:
	_ship = _local()
	if active and (_ship == null or Prefs.scheme != FlightControls.Scheme.POINT_CIRCLE):
		_close()
	if not active:
		return
	var cam := _cam()
	if cam == null:
		return
	if not Input.is_key_pressed(KEY_ALT):                # x, z follow the cursor on the plane at the circle's height
		var m := get_viewport().get_mouse_position()
		var hit := plane_point(cam.project_ray_origin(m), cam.project_ray_normal(m), point.y)
		if hit["ok"]:
			point = hit["point"]
	_update_visual(cam)


func _update_visual(cam: Camera3D) -> void:
	var dist := cam.global_position.distance_to(point)
	var r := clampf(dist * 0.035, 3.0, 80.0)
	_ring.global_position = point
	_ring.scale = Vector3(r, r, r)
	var base := Vector3(point.x, _ship.global_position.y, point.z)
	_drop.global_position = base
	_drop.scale = Vector3(r, r, r)
	_label.global_position = point + Vector3(0, r * 1.4, 0)
	_label.text = "x %.0f  y %.0f  z %.0f   %.0f m%s" % [point.x, point.y, point.z, point.distance_to(_ship.global_position),
		"   [ALT: height]" if Input.is_key_pressed(KEY_ALT) else "   [hold ALT: height]"]
	_show(true)


func open_circle() -> void:
	if _ship == null:
		return
	active = true
	Data.cursor_busy = true
	point = _ship.global_position
	var cam := _cam()
	if cam != null:
		var fwd := -cam.global_basis.z
		fwd.y = 0.0
		point += fwd.normalized() * 40.0 if fwd.length() > 0.01 else Vector3.ZERO


func _close() -> void:
	active = false
	Data.cursor_busy = false
	_show(false)


func _unhandled_input(event: InputEvent) -> void:
	var ship := _local()
	if ship == null or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var scheme := Prefs.scheme
	if scheme == FlightControls.Scheme.POINT_CIRCLE:
		_circle_input(event, ship)
	elif scheme == FlightControls.Scheme.EVE_ORDERS:
		_eve_input(event, ship)


func _circle_input(event: InputEvent, ship: Ship) -> void:
	if event.is_action_pressed("move_gizmo"):
		if active:
			_close()
		else:
			open_circle()
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if event is InputEventMouseMotion and Input.is_key_pressed(KEY_ALT):
		var cam := _cam()
		point.y = adjust_height(point.y, (event as InputEventMouseMotion).relative.y, cam.global_position.distance_to(point) if cam != null else 100.0)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			ship.autopilot.go_to(point, true)
			order_given.emit("Flying to (%.0f, %.0f, %.0f)" % [point.x, point.y, point.z])
			BusEvent.notify.emit(tr("Flying to (%.0f, %.0f, %.0f)") % [point.x, point.y, point.z])
			_close()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_autopilot_panel") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
		_close()
		get_viewport().set_input_as_handled()


func _eve_input(event: InputEvent, ship: Ship) -> void:
	if event.is_action_pressed("range_more"):
		Prefs.order_range = clampf(Prefs.order_range * 1.25, 10.0, 5000.0)
		BusEvent.notify.emit(tr("Orbit / range: %.0f m") % Prefs.order_range)
		return
	if event.is_action_pressed("range_less"):
		Prefs.order_range = clampf(Prefs.order_range * 0.8, 10.0, 5000.0)
		BusEvent.notify.emit(tr("Orbit / range: %.0f m") % Prefs.order_range)
		return
	if event.is_action_pressed("order_approach") or event.is_action_pressed("order_orbit") or event.is_action_pressed("order_keep_range"):
		var target := ship.detection.locked
		if target == null:
			var list := ship.detection.enemies()
			if not list.is_empty():
				target = list[0]["ship"]
				ship.detection.locked = target
		if target == null:
			BusEvent.notify.emit(tr("No target: press R to lock an enemy"))
			return
		if event.is_action_pressed("order_approach"):
			ship.autopilot.follow_distance = 15.0
			ship.autopilot.go_follow(target)
			BusEvent.notify.emit(tr("Approaching %s") % target.pilot_name)
		elif event.is_action_pressed("order_orbit"):
			ship.autopilot.go_orbit(target, Prefs.order_range)
			BusEvent.notify.emit(tr("Orbiting %s at %.0f m") % [target.pilot_name, Prefs.order_range])
		else:
			ship.autopilot.follow_distance = Prefs.order_range
			ship.autopilot.go_follow(target)
			BusEvent.notify.emit(tr("Keeping %s at %.0f m") % [target.pilot_name, Prefs.order_range])
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).double_click \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and get_viewport().gui_get_hovered_control() == null:
		var cam := _cam()
		if cam == null:
			return
		var m := get_viewport().get_mouse_position()
		var o := cam.project_ray_origin(m)
		var d := cam.project_ray_normal(m)
		var hit := pick_contact(ship.detection.enemies(), o, d) as Ship
		if hit != null:
			ship.detection.locked = hit
			ship.autopilot.follow_distance = 15.0
			ship.autopilot.go_follow(hit)
			BusEvent.notify.emit(tr("Approaching %s") % hit.pilot_name)
		else:
			ship.autopilot.drive_heading(d, 1.0)
			BusEvent.notify.emit(tr("Aligned and accelerating that way (X to stop)"))
