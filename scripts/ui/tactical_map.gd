class_name TacticalMap
extends Control
## NEBULOUS-STYLE ORDERS. A top-down map of the ship, its speed, the contacts and the destination. Instead of typing
## coordinates you CLICK where you want to go (the height is set on the ruler on the right edge, or in the Height box).
##
##   GO TO   the ship flies there and stops (ShipAutopilot.Mode.GOTO)
##   DRIVE   the ship flies towards it with the chosen THRUST and never stops - for ramming. Click an enemy in DRIVE
##           mode and the ship keeps driving at it. Brake / Cancel end it.
##   "Keep turrets facing the enemy" turns the ship so the most turrets can bear on the locked enemy while it moves.
##
## Everything lives in scenes/tactical_map.tscn; this script only draws the canvas and forwards the orders.

const INK := Color(0.85, 0.93, 1.0)
const GRID := Color(0.5, 0.7, 1.0, 0.13)
const FRIEND := Color(0.4, 1.0, 0.5)
const ENEMY := Color(1.0, 0.35, 0.3)
const LOCKED := Color(1.0, 0.7, 0.2)
const RULER_W := 64.0

@onready var canvas: Control = %MapCanvas
@onready var go_button: Button = %GoToButton
@onready var drive_button: Button = %DriveButton
@onready var thrust_slider: HSlider = %ThrustSlider
@onready var thrust_label: Label = %ThrustValueLabel
@onready var altitude_spin: SpinBox = %AltitudeSpin
@onready var face_check: CheckBox = %FaceTurretsCheck
@onready var free_check: CheckBox = %WeaponsFreeCheck
@onready var info_label: Label = %OrderInfoLabel

var ship: Ship
var _centre := Vector2.ZERO        ## world (x, z) shown in the middle of the map
var _scale := 0.4                  ## pixels per metre
var _panning := false
var _follow := true                ## the map keeps the own ship in the middle until the player pans
var _hover := Vector2.ZERO


func _ready() -> void:
	visible = false
	canvas.draw.connect(_draw_map)
	canvas.gui_input.connect(_on_canvas_input)
	go_button.pressed.connect(func(): _set_mode(false))
	drive_button.pressed.connect(func(): _set_mode(true))
	thrust_slider.value_changed.connect(_on_thrust_changed)
	face_check.toggled.connect(func(on: bool): if is_instance_valid(ship): ship.autopilot.face_turrets = on)
	free_check.toggled.connect(func(on: bool): if is_instance_valid(ship): ship.weapons_free = on)
	%ChaseButton.pressed.connect(_on_chase_pressed)
	%MapBrakeButton.pressed.connect(func(): if is_instance_valid(ship): ship.autopilot.brake())
	%MapCancelButton.pressed.connect(func(): if is_instance_valid(ship): ship.autopilot.cancel())
	%CloseMapButton.pressed.connect(close)
	BusEvent.local_ship_changed.connect(func(s: Ship): ship = s)
	ship = Data.local_ship


func open() -> void:
	ship = Data.local_ship
	if not is_instance_valid(ship):
		return
	_follow = true
	_centre = Vector2(ship.global_position.x, ship.global_position.z)
	altitude_spin.set_value_no_signal(snappedf(ship.global_position.y, 1.0))
	if ship.autopilot.mode == ShipAutopilot.Mode.DRIVE:
		thrust_slider.set_value_no_signal(ship.autopilot.throttle * 100.0)
	face_check.set_pressed_no_signal(ship.autopilot.face_turrets)
	free_check.set_pressed_no_signal(ship.weapons_free)
	visible = true


func close() -> void:
	visible = false


func _process(_dt: float) -> void:
	if not visible:
		return
	if not is_instance_valid(ship) or not ship.alive:
		close()
		return
	if _follow:
		_centre = Vector2(ship.global_position.x, ship.global_position.z)
	free_check.set_pressed_no_signal(ship.weapons_free)
	var ap := ship.autopilot
	var drive := ap.mode == ShipAutopilot.Mode.DRIVE
	if ap.is_active():
		go_button.set_pressed_no_signal(not drive)
		drive_button.set_pressed_no_signal(drive)
	thrust_label.text = "%d%%" % int(thrust_slider.value)
	var spd := ship.linear_velocity.length()
	var txt := "Speed %.1f m/s\n" % spd
	if ap.is_active():
		var d := ap.distance
		txt += "%s\nDistance %.0f m   ETA %s" % [ap.phase, d, ("%.0f s" % (d / spd)) if spd > 0.5 else "-"]
	else:
		txt += "No order: the ship drifts."
	info_label.text = txt
	canvas.queue_redraw()


func _set_mode(drive: bool) -> void:
	go_button.set_pressed_no_signal(not drive)
	drive_button.set_pressed_no_signal(drive)
	if not is_instance_valid(ship) or not ship.autopilot.is_active():
		return
	# switch the running order to the other mode, keeping its destination
	var ap := ship.autopilot
	if drive:
		ap.drive_to(ap.current_target(), thrust_slider.value / 100.0, ap.track_ship)
	else:
		ap.go_to(ap.current_target(), true)


func _on_thrust_changed(_v: float) -> void:
	if is_instance_valid(ship) and ship.autopilot.mode == ShipAutopilot.Mode.DRIVE:
		ship.autopilot.throttle = thrust_slider.value / 100.0


func _on_chase_pressed() -> void:
	if is_instance_valid(ship) and ship.detection.locked != null:
		ship.autopilot.drive_to(ship.detection.locked.global_position, thrust_slider.value / 100.0, ship.detection.locked)
		drive_button.set_pressed_no_signal(true)
		go_button.set_pressed_no_signal(false)
	elif is_instance_valid(ship):
		BusEvent.notify.emit("Lock an enemy first (R, or click it on the map)")


# ----------------------------------------------------------------------------- coordinates
func _w2s(x: float, z: float) -> Vector2:
	return canvas.size * 0.5 + (Vector2(x, z) - _centre) * _scale


func _s2w(p: Vector2) -> Vector2:
	return _centre + (p - canvas.size * 0.5) / _scale


## Height ruler on the right edge: world y of a screen y (the own ship's height is the middle of the ruler).
func _ruler_y_to_world(py: float) -> float:
	return ship.global_position.y - (py - canvas.size.y * 0.5) / _scale


func _world_y_to_ruler(wy: float) -> float:
	return canvas.size.y * 0.5 - (wy - ship.global_position.y) * _scale


# ----------------------------------------------------------------------------- input
func _on_canvas_input(event: InputEvent) -> void:
	if not is_instance_valid(ship):
		return
	if event is InputEventMouseMotion:
		_hover = event.position
		if _panning:
			_centre -= (event as InputEventMouseMotion).relative / _scale
			_follow = false
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_scale = minf(_scale * 1.15, 20.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_scale = maxf(_scale / 1.15, 0.003)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.position.x > canvas.size.x - RULER_W:
				altitude_spin.value = snappedf(_ruler_y_to_world(mb.position.y), 1.0)
				if ship.autopilot.is_active():
					_reissue(ship.autopilot.current_target())
			else:
				_click(mb.position)


func _click(p: Vector2) -> void:
	# an enemy / friendly contact under the cursor: lock it (and chase it in DRIVE mode)
	for c in ship.detection.contacts:
		var other: Ship = c["ship"]
		if not is_instance_valid(other):
			continue
		if _w2s(other.global_position.x, other.global_position.z).distance_to(p) < 14.0:
			if not c["friendly"]:
				ship.detection.locked = other
				if drive_button.button_pressed:
					ship.autopilot.drive_to(other.global_position, thrust_slider.value / 100.0, other)
			return
	var w := _s2w(p)
	_reissue(Vector3(w.x, altitude_spin.value, w.y))


## Give the order for the chosen mode and destination.
func _reissue(dest: Vector3) -> void:
	var ap := ship.autopilot
	ap.face_turrets = face_check.button_pressed
	if drive_button.button_pressed:
		ap.drive_to(dest, thrust_slider.value / 100.0)
	else:
		ap.go_to(dest, true)


# ----------------------------------------------------------------------------- drawing
func _draw_map() -> void:
	if not is_instance_valid(ship):
		return
	var font := ThemeDB.fallback_font
	var sz := canvas.size
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.06, 0.96))
	# grid: spacing is a power of ten that keeps lines >= 40 px apart
	var step := 1.0
	while step * _scale < 40.0:
		step *= 10.0
	var tl := _s2w(Vector2.ZERO)
	var br := _s2w(sz)
	var x := floorf(tl.x / step) * step
	while x < br.x:
		var sx := _w2s(x, 0.0).x
		canvas.draw_line(Vector2(sx, 0), Vector2(sx, sz.y), GRID, 1.0)
		x += step
	var z := floorf(tl.y / step) * step
	while z < br.y:
		var sy := _w2s(0.0, z).y
		canvas.draw_line(Vector2(0, sy), Vector2(sz.x, sy), GRID, 1.0)
		z += step
	canvas.draw_string(font, Vector2(10, sz.y - 10), "grid %s m   (north = -Z, up)" % str(step), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.6))
	var me := _w2s(ship.global_position.x, ship.global_position.z)
	# range rings around the ship
	for ring in [100.0, 300.0, 700.0, 1500.0]:
		if ring * _scale > 30.0 and ring * _scale < sz.x:
			canvas.draw_arc(me, ring * _scale, 0.0, TAU, 96, Color(INK, 0.12), 1.0)
			canvas.draw_string(font, me + Vector2(ring * _scale + 3.0, -3.0), "%d m" % int(ring), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.35))
	# the stop point if the ship only braked now
	var v := ship.linear_velocity
	var sp := v.length()
	if sp > 0.5:
		var stop := ship.global_position + v / sp * (sp * 2.0 + sp * sp / (2.0 * maxf(0.5 * ship.autopilot._a_eff, 0.05)))
		var ss := _w2s(stop.x, stop.z)
		canvas.draw_line(me, ss, Color(1.0, 1.0, 0.4, 0.5), 1.5)
		canvas.draw_circle(ss, 4.0, Color(1.0, 1.0, 0.4, 0.8))
		canvas.draw_string(font, ss + Vector2(6, 4), "stop here if braking", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 1.0, 0.4, 0.8))
	# the order
	var ap := ship.autopilot
	if ap.is_active():
		var tgt := ap.current_target()
		var ts := _w2s(tgt.x, tgt.z)
		var col := Color(0.4, 0.9, 1.0) if ap.mode == ShipAutopilot.Mode.GOTO else Color(1.0, 0.5, 0.25)
		canvas.draw_dashed_line(me, ts, col, 2.0, 8.0)
		if ap.mode == ShipAutopilot.Mode.GOTO:
			canvas.draw_arc(ts, 9.0, 0.0, TAU, 24, col, 2.0)
			canvas.draw_circle(ts, 2.5, col)
		else:
			canvas.draw_colored_polygon(PackedVector2Array([ts + Vector2(0, -11), ts + Vector2(11, 0), ts + Vector2(0, 11), ts + Vector2(-11, 0)]), Color(col, 0.35))
			canvas.draw_polyline(PackedVector2Array([ts + Vector2(0, -11), ts + Vector2(11, 0), ts + Vector2(0, 11), ts + Vector2(-11, 0), ts + Vector2(0, -11)]), col, 2.0)
		var dy := tgt.y - ship.global_position.y
		canvas.draw_string(font, ts + Vector2(14, -6), "%s  %.0f m   %+.0f m high" % ["GO TO" if ap.mode == ShipAutopilot.Mode.GOTO else "DRIVE", ap.distance, dy], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# contacts
	for c in ship.detection.contacts:
		var other: Ship = c["ship"]
		if not is_instance_valid(other):
			continue
		var cs := _w2s(other.global_position.x, other.global_position.z)
		var ccol: Color = FRIEND if c["friendly"] else ENEMY
		if other == ship.detection.locked:
			ccol = LOCKED
			canvas.draw_arc(cs, 13.0, 0.0, TAU, 24, LOCKED, 2.0)
		canvas.draw_circle(cs, 5.0, ccol)
		var dh := other.global_position.y - ship.global_position.y
		canvas.draw_string(font, cs + Vector2(9, 4), "%s  %.0f m  %+.0f" % [other.pilot_name, c["dist"], dh], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ccol)
		var ov: Vector3 = other.linear_velocity
		canvas.draw_line(cs, cs + Vector2(ov.x, ov.z) * _scale * 5.0, Color(ccol, 0.5), 1.0)
	# own ship: triangle along its nose, velocity vector
	canvas.draw_line(me, me + Vector2(v.x, v.z) * _scale * 5.0, Color(INK, 0.7), 1.5)
	var nose := ship.global_transform.basis * Vector3(0, 0, -1)
	var fwd := Vector2(nose.x, nose.z)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector2.UP
	var side := Vector2(-fwd.y, fwd.x)
	canvas.draw_colored_polygon(PackedVector2Array([me + fwd * 12.0, me - fwd * 8.0 + side * 7.0, me - fwd * 4.0, me - fwd * 8.0 - side * 7.0]), Color(INK, 0.9))
	# height ruler
	var rx := sz.x - RULER_W
	canvas.draw_rect(Rect2(rx, 0, RULER_W, sz.y), Color(0.05, 0.07, 0.12, 0.9))
	canvas.draw_line(Vector2(rx, 0), Vector2(rx, sz.y), Color(INK, 0.3), 1.0)
	canvas.draw_string(font, Vector2(rx + 6, 16), "HEIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.6))
	var ry := _world_y_to_ruler(ship.global_position.y)
	canvas.draw_line(Vector2(rx, ry), Vector2(sz.x, ry), INK, 2.0)
	canvas.draw_string(font, Vector2(rx + 6, ry - 4), "you %.0f" % ship.global_position.y, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	var wy := _world_y_to_ruler(altitude_spin.value)
	canvas.draw_line(Vector2(rx, wy), Vector2(sz.x, wy), Color(0.4, 0.9, 1.0), 2.0)
	canvas.draw_string(font, Vector2(rx + 6, wy - 4), "go %.0f" % altitude_spin.value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.9, 1.0))
	# cursor read-out
	if _hover.x < rx:
		var w := _s2w(_hover)
		canvas.draw_string(font, _hover + Vector2(14, 18), "%.0f, %.0f" % [w.x, w.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.6))
