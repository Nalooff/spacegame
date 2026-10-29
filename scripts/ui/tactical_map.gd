class_name TacticalMap
extends Control
## NEBULOUS-STYLE ORDERS. A map of the ship, everything it knows about, and its orders. Instead of typing coordinates you
## CLICK where you want to go. Two views of the same map:
##   2D   straight from above (height on the ruler at the right edge, or in the Height box)
##   3D   the camera is tilted so you SEE the height: every object stands on a thin line down to the "ground" plane at
##        your own height. Right-drag turns the view, middle-drag (or Shift + right-drag) pans, Ctrl + wheel changes the
##        height of the next order. Clicks land on the plane of the chosen height.
##
##   GO TO   fly there and stop (ShipAutopilot.Mode.GOTO). Click a SHIP and the ship follows it, holding station beside it.
##   DRIVE   an ARROW, not a point: the ship pushes that way with the chosen THRUST and never stops. Click an enemy and the
##           arrow follows it, aimed at the INTERCEPT point (where it will be when we arrive) so the ship can ram.
##
## The map shows everything known: ships the radar sees, shots in flight and the landmarks, each with an arrow in the
## direction it moves (see MapObjects). Everything lives in scenes/tactical_map.tscn; this script draws the canvas and forwards the orders.

const INK := Color(0.85, 0.93, 1.0)
const GRID := Color(0.5, 0.7, 1.0, 0.13)
const FRIEND := Color(0.4, 1.0, 0.5)
const ENEMY := Color(1.0, 0.35, 0.3)
const LOCKED := Color(1.0, 0.7, 0.2)
const SHOT := Color(1.0, 0.85, 0.4)
const ROCK := Color(0.65, 0.62, 0.58)
const RULER_W := 64.0
const VEL_SECONDS := 8.0              ## the arrow of a moving object is the distance it covers in this many seconds
const PITCH_3D := 0.7                 ## radians: default tilt of the 3D camera (90 deg would be straight down)

@onready var canvas: Control = %MapCanvas
@onready var go_button: Button = %GoToButton
@onready var drive_button: Button = %DriveButton
@onready var view2d_button: Button = %View2DButton
@onready var view3d_button: Button = %View3DButton
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
var _rotating := false
var _follow := true                ## the map keeps the own ship in the middle until the player pans
var _hover := Vector2.ZERO
var _view3d := false
var _yaw := 0.0
var _pitch := PITCH_3D
var _objects: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	canvas.draw.connect(_draw_map)
	canvas.gui_input.connect(_on_canvas_input)
	go_button.pressed.connect(func(): _set_mode(false))
	drive_button.pressed.connect(func(): _set_mode(true))
	view2d_button.pressed.connect(func(): set_view3d(false))
	view3d_button.pressed.connect(func(): set_view3d(true))
	thrust_slider.value_changed.connect(_on_thrust_changed)
	face_check.toggled.connect(func(on: bool): if is_instance_valid(ship): ship.autopilot.face_turrets = on)
	free_check.toggled.connect(func(on: bool): if is_instance_valid(ship): ship.weapons_free = on)
	%ChaseButton.pressed.connect(_on_chase_pressed)
	%MapBrakeButton.pressed.connect(func(): if is_instance_valid(ship): ship.autopilot.brake())
	%MapCancelButton.pressed.connect(func(): if is_instance_valid(ship): ship.autopilot.cancel())
	%CloseMapButton.pressed.connect(close)
	BusEvent.local_ship_changed.connect(func(s: Ship): ship = s)
	ship = Data.local_ship


func set_view3d(on: bool) -> void:
	_view3d = on
	view2d_button.set_pressed_no_signal(not on)
	view3d_button.set_pressed_no_signal(on)
	canvas.queue_redraw()


func is_view3d() -> bool:
	return _view3d


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
	view2d_button.set_pressed_no_signal(not _view3d)
	view3d_button.set_pressed_no_signal(_view3d)
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
		if drive and ap.heading != Vector3.ZERO and ap.track_ship == null:
			var h := ap.heading
			txt += "%s\nHeading %.0f deg, %+.0f deg up" % [ap.phase, fposmod(rad_to_deg(atan2(h.x, -h.z)), 360.0), rad_to_deg(asin(clampf(h.y, -1.0, 1.0)))]
		else:
			var d := ap.distance
			txt += "%s\nDistance %.0f m   ETA %s" % [ap.phase, d, ("%.0f s" % (d / spd)) if spd > 0.5 else "-"]
	else:
		txt += "No order: the ship drifts."
	_objects = MapObjects.gather(ship)
	var shots := 0
	var ships := 0
	for o in _objects:
		if o["kind"] == "projectile":
			shots += 1
		elif o["kind"] == "ship":
			ships += 1
	txt += "\nKnown: %d ships, %d shots" % [ships, shots]
	info_label.text = txt
	canvas.queue_redraw()


func _set_mode(drive: bool) -> void:
	go_button.set_pressed_no_signal(not drive)
	drive_button.set_pressed_no_signal(drive)
	if not is_instance_valid(ship) or not ship.autopilot.is_active():
		return
	# switch the running order to the other mode, keeping what it aims at
	var ap := ship.autopilot
	if drive:
		if ap.track_ship != null:
			ap.drive_to(ap.current_target(), thrust_slider.value / 100.0, ap.track_ship)
		else:
			ap.drive_heading(ap.current_target() - ship.global_position, thrust_slider.value / 100.0)
	elif ap.track_ship != null:
		ap.go_follow(ap.track_ship)
	elif ap.heading != Vector3.ZERO:
		ap.go_to(ship.global_position + ap.heading * 500.0, true)
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


# ----------------------------------------------------------------------------- projection
## ONE projection for both views. 2D is simply the camera looking straight down (pitch 90 deg, no yaw).
func _pitch_now() -> float:
	return _pitch if _view3d else PI * 0.5


func _yaw_now() -> float:
	return _yaw if _view3d else 0.0


func _focus() -> Vector3:
	return Vector3(_centre.x, ship.global_position.y if is_instance_valid(ship) else 0.0, _centre.y)


## World point -> canvas pixel (orthographic, tilted).
func _proj(w: Vector3) -> Vector2:
	var r := w - _focus()
	var c := cos(_yaw_now())
	var sn := sin(_yaw_now())
	var x1 := r.x * c + r.z * sn
	var z1 := -r.x * sn + r.z * c
	var p := _pitch_now()
	return canvas.size * 0.5 + Vector2(x1, z1 * sin(p) - r.y * cos(p)) * _scale


## Canvas pixel -> the world point on the horizontal plane at height `plane_y`.
func _unproject(px: Vector2, plane_y: float) -> Vector3:
	var f := _focus()
	var rel := (px - canvas.size * 0.5) / _scale
	var p := _pitch_now()
	var ry := plane_y - f.y
	var z1 := (rel.y + ry * cos(p)) / maxf(sin(p), 0.05)
	var x1 := rel.x
	var c := cos(_yaw_now())
	var sn := sin(_yaw_now())
	return Vector3(f.x + x1 * c - z1 * sn, plane_y, f.z + x1 * sn + z1 * c)


func _w2s(x: float, z: float) -> Vector2:
	return _proj(Vector3(x, _focus().y, z))


func _s2w(p: Vector2) -> Vector2:
	var w := _unproject(p, _focus().y)
	return Vector2(w.x, w.z)


## Height ruler on the right edge (2D only): world y of a screen y (the own ship's height is the middle of the ruler).
func _ruler_y_to_world(py: float) -> float:
	return ship.global_position.y - (py - canvas.size.y * 0.5) / _scale


func _world_y_to_ruler(wy: float) -> float:
	return canvas.size.y * 0.5 - (wy - ship.global_position.y) * _scale


# ----------------------------------------------------------------------------- input
func _on_canvas_input(event: InputEvent) -> void:
	if not is_instance_valid(ship):
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover = mm.position
		if _rotating:
			_yaw += mm.relative.x * 0.008
			_pitch = clampf(_pitch + mm.relative.y * 0.006, 0.15, 1.5)
		elif _panning:
			var d := mm.relative / _scale
			var c := cos(_yaw_now())
			var sn := sin(_yaw_now())
			var ps := maxf(sin(_pitch_now()), 0.2)
			var z1 := d.y / ps
			_centre -= Vector2(d.x * c - z1 * sn, d.x * sn + z1 * c)
			_follow = false
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if mb.ctrl_pressed and _view3d:
				_nudge_altitude(10.0)
			else:
				_scale = minf(_scale * 1.15, 20.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if mb.ctrl_pressed and _view3d:
				_nudge_altitude(-10.0)
			else:
				_scale = maxf(_scale / 1.15, 0.003)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _view3d and not mb.shift_pressed:
				_rotating = mb.pressed
				_panning = false
			else:
				_panning = mb.pressed
				_rotating = false
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _view3d and mb.position.x > canvas.size.x - RULER_W:
				altitude_spin.value = snappedf(_ruler_y_to_world(mb.position.y), 1.0)
				_apply_altitude()
			else:
				_click(mb.position)


func _nudge_altitude(dy: float) -> void:
	altitude_spin.value = altitude_spin.value + dy
	_apply_altitude()


## The Height changed: bend the running order up or down (a DRIVE arrow climbs, a GO TO point moves vertically).
func _apply_altitude() -> void:
	var ap := ship.autopilot
	if not ap.is_active() or ap.track_ship != null:
		return
	if ap.mode == ShipAutopilot.Mode.DRIVE and ap.heading != Vector3.ZERO:
		var flat := Vector3(ap.heading.x, 0.0, ap.heading.z)
		flat = flat.normalized() if flat.length() > 0.01 else Vector3(0, 0, -1)
		ap.drive_heading(flat * 500.0 + Vector3(0, altitude_spin.value - ship.global_position.y, 0), thrust_slider.value / 100.0)
	else:
		var t := ap.current_target()
		_reissue(Vector3(t.x, altitude_spin.value, t.z))


## The ship object under the cursor (or an empty dictionary).
func ship_at(p: Vector2) -> Dictionary:
	var best := {}
	var best_d := 14.0
	for o in _objects:
		if o["kind"] != "ship":
			continue
		var d := _proj(o["pos"]).distance_to(p)
		if d < best_d:
			best_d = d
			best = o
	return best


func _click(p: Vector2) -> void:
	var hit := ship_at(p)
	if not hit.is_empty():
		var other: Ship = hit["ship"]
		if not hit["friendly"]:
			ship.detection.locked = other
		ship.autopilot.face_turrets = face_check.button_pressed
		if drive_button.button_pressed:
			if hit["friendly"]:
				BusEvent.notify.emit("DRIVE would ram a friend: use GO TO to follow it")
			else:
				ship.autopilot.drive_to(other.global_position, thrust_slider.value / 100.0, other)
		else:
			ship.autopilot.go_follow(other)
		return
	var w := _unproject(p, altitude_spin.value)
	_reissue(w)


## Give the order for the chosen mode and place. DRIVE turns the place into a DIRECTION (an arrow from the ship).
func _reissue(dest: Vector3) -> void:
	var ap := ship.autopilot
	ap.face_turrets = face_check.button_pressed
	if drive_button.button_pressed:
		ap.drive_heading(dest - ship.global_position, thrust_slider.value / 100.0)
	else:
		ap.go_to(dest, true)


# ----------------------------------------------------------------------------- drawing
## An arrow from world point a to b (screen head of 10 px).
func _arrow(a: Vector3, b: Vector3, col: Color, width: float = 2.0, head: float = 10.0) -> void:
	var sa := _proj(a)
	var sb := _proj(b)
	canvas.draw_line(sa, sb, col, width, true)
	var d := sb - sa
	if d.length() < 3.0:
		return
	d = d.normalized()
	var n := Vector2(-d.y, d.x)
	canvas.draw_colored_polygon(PackedVector2Array([sb, sb - d * head + n * head * 0.45, sb - d * head - n * head * 0.45]), col)


## In 3D every object stands on a thin line down to the ground plane (the height of the own ship).
func _stilt(w: Vector3, col: Color) -> void:
	if not _view3d:
		return
	var g := Vector3(w.x, ship.global_position.y, w.z)
	canvas.draw_line(_proj(w), _proj(g), Color(col, 0.45), 1.0)
	canvas.draw_circle(_proj(g), 2.0, Color(col, 0.5))


func _draw_map() -> void:
	if not is_instance_valid(ship):
		return
	var font := ThemeDB.fallback_font
	var sz := canvas.size
	var gy := ship.global_position.y
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.06, 0.96))
	# grid on the ground plane: spacing is a power of ten that keeps lines >= 40 px apart
	var step := 1.0
	while step * _scale < 40.0:
		step *= 10.0
	var reach := maxf(sz.x, sz.y) / _scale * 0.9
	var f := _focus()
	var x := floorf((f.x - reach) / step) * step
	while x < f.x + reach:
		canvas.draw_line(_proj(Vector3(x, gy, f.z - reach)), _proj(Vector3(x, gy, f.z + reach)), GRID, 1.0)
		x += step
	var z := floorf((f.z - reach) / step) * step
	while z < f.z + reach:
		canvas.draw_line(_proj(Vector3(f.x - reach, gy, z)), _proj(Vector3(f.x + reach, gy, z)), GRID, 1.0)
		z += step
	canvas.draw_string(font, Vector2(10, sz.y - 10), "grid %s m   (%s)" % [str(step), "ground = your height, drag right button to turn" if _view3d else "north = -Z, up"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.6))
	var me3 := ship.global_position
	var me := _proj(me3)
	# range rings around the ship (on the ground plane)
	for ring in [100.0, 300.0, 700.0, 1500.0]:
		if ring * _scale > 30.0 and ring * _scale < sz.x:
			var pts := PackedVector2Array()
			for k in 97:
				var a := TAU * k / 96.0
				pts.append(_proj(Vector3(me3.x + cos(a) * ring, gy, me3.z + sin(a) * ring)))
			canvas.draw_polyline(pts, Color(INK, 0.12), 1.0)
			canvas.draw_string(font, _proj(Vector3(me3.x + ring, gy, me3.z)) + Vector2(3, -3), "%d m" % int(ring), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.35))
	# the stop point if the ship only braked now
	var v := ship.linear_velocity
	var sp := v.length()
	if sp > 0.5:
		var stop := me3 + v / sp * (sp * 2.0 + sp * sp / (2.0 * maxf(0.5 * ship.autopilot._a_eff, 0.05)))
		var ss := _proj(stop)
		canvas.draw_line(me, ss, Color(1.0, 1.0, 0.4, 0.5), 1.5)
		canvas.draw_circle(ss, 4.0, Color(1.0, 1.0, 0.4, 0.8))
		_stilt(stop, Color(1.0, 1.0, 0.4))
		canvas.draw_string(font, ss + Vector2(6, 4), "stop here if braking", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 1.0, 0.4, 0.8))
	_draw_objects(font)
	_draw_order(font)
	# own ship: a triangle lying in its own plane, and its velocity arrow
	if sp > 0.5:
		_arrow(me3, me3 + v * VEL_SECONDS, Color(INK, 0.7), 1.5, 8.0)
	_stilt(me3, INK)
	var b := ship.global_transform.basis
	var k := 1.0 / _scale
	canvas.draw_colored_polygon(PackedVector2Array([_proj(me3 + b * Vector3(0, 0, -12) * k), _proj(me3 + b * Vector3(-7, 0, 8) * k), _proj(me3 + b * Vector3(0, 0, 4) * k), _proj(me3 + b * Vector3(7, 0, 8) * k)]), Color(INK, 0.9))
	if not _view3d:
		_draw_ruler(font)
	else:
		canvas.draw_string(font, Vector2(sz.x - 330, 18), "Click sets the order at height %.0f m   (Ctrl + wheel: height)" % altitude_spin.value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.9, 1.0, 0.9))
	# cursor read-out: the point of the plane at the chosen height
	if _hover.x < sz.x - (0.0 if _view3d else RULER_W):
		var w := _unproject(_hover, altitude_spin.value if _view3d else gy)
		canvas.draw_string(font, _hover + Vector2(14, 18), "%.0f, %.0f" % [w.x, w.z], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.6))
	# legend
	var ly := 18.0
	for item in [["enemy ship", ENEMY], ["friend", FRIEND], ["shot", SHOT], ["landmark", ROCK]]:
		canvas.draw_circle(Vector2(16, ly), 4.0, item[1])
		canvas.draw_string(font, Vector2(26, ly + 4), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.7))
		ly += 16.0
	canvas.draw_string(font, Vector2(10, ly + 4), "arrows = where they are heading (%d s)" % int(VEL_SECONDS), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(INK, 0.5))


## Ships, shots and landmarks, each with the arrow of its movement.
func _draw_objects(font: Font) -> void:
	for o in _objects:
		var pos: Vector3 = o["pos"]
		var vel: Vector3 = o["vel"]
		var sp := _proj(pos)
		if sp.x < -60.0 or sp.y < -60.0 or sp.x > canvas.size.x + 60.0 or sp.y > canvas.size.y + 60.0:
			continue
		match o["kind"]:
			"landmark":
				var r := maxf(float(o["radius"]) * _scale, 3.0)
				canvas.draw_circle(sp, r, Color(ROCK, 0.35))
				canvas.draw_arc(sp, r, 0.0, TAU, 20, Color(ROCK, 0.8), 1.0)
				_stilt(pos, ROCK)
				if r > 6.0:
					canvas.draw_string(font, sp + Vector2(r + 3.0, 4.0), str(o["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ROCK, 0.7))
				if vel.length() > 0.5:
					_arrow(pos, pos + vel * VEL_SECONDS, Color(ROCK, 0.8), 1.0, 6.0)
			"projectile":
				var col := Color(SHOT, 0.5) if o["friendly"] else SHOT
				canvas.draw_circle(sp, 2.5, col)
				if vel.length() > 0.5:
					_arrow(pos, pos + vel.normalized() * minf(vel.length() * 0.3, 90.0), Color(col, 0.8), 1.0, 5.0)
			"ship":
				var ccol: Color = FRIEND if o["friendly"] else ENEMY
				if o["locked"]:
					ccol = LOCKED
					canvas.draw_arc(sp, 13.0, 0.0, TAU, 24, LOCKED, 2.0)
				canvas.draw_circle(sp, 5.0, ccol)
				_stilt(pos, ccol)
				var dh := pos.y - ship.global_position.y
				canvas.draw_string(font, sp + Vector2(9, 4), "%s  %.0f m  %+.0f  (%s)" % [o["name"], o["dist"], dh, o["how"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ccol)
				if vel.length() > 0.5:
					_arrow(pos, pos + vel * VEL_SECONDS, Color(ccol, 0.8), 1.5, 7.0)


## The running order: a ring for GO TO, an ARROW for DRIVE (which follows its ship, aimed at the intercept point).
func _draw_order(font: Font) -> void:
	var ap := ship.autopilot
	if not ap.is_active():
		return
	var me3 := ship.global_position
	var me := _proj(me3)
	var drive := ap.mode == ShipAutopilot.Mode.DRIVE
	var col := Color(1.0, 0.5, 0.25) if drive else Color(0.4, 0.9, 1.0)
	var tracked := ap.track_ship != null and is_instance_valid(ap.track_ship)
	var label := ""
	if drive:
		var dir := ap.drive_direction()
		var aim := ap.aim_point()
		var len_w := 150.0 / _scale                     # the arrow is always about 150 px long
		if tracked:
			len_w = minf(len_w, me3.distance_to(aim))
		_arrow(me3, me3 + dir * len_w, col, 4.0, 16.0)
		_stilt(me3 + dir * len_w, col)
		label = "DRIVE %d%%  %+.0f deg" % [int(ap.throttle * 100.0), rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))]
		if tracked:
			var ts := _proj(aim)
			canvas.draw_dashed_line(me, ts, Color(col, 0.6), 1.5, 8.0)
			canvas.draw_line(ts + Vector2(-8, -8), ts + Vector2(8, 8), col, 2.0)
			canvas.draw_line(ts + Vector2(-8, 8), ts + Vector2(8, -8), col, 2.0)
			_stilt(aim, col)
			label += "  intercept in %.0f s at %.0f m" % [(aim - me3).length() / maxf(ship.linear_velocity.length(), 5.0), (aim - me3).length()]
		canvas.draw_string(font, me + dir_screen(dir) * 160.0 + Vector2(8, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	else:
		var tgt := ap.current_target()
		var ts2 := _proj(tgt)
		canvas.draw_dashed_line(me, ts2, col, 2.0, 8.0)
		canvas.draw_arc(ts2, 9.0, 0.0, TAU, 24, col, 2.0)
		canvas.draw_circle(ts2, 2.5, col)
		_stilt(tgt, col)
		var what := "FOLLOW %s" % ap.track_ship.pilot_name if tracked else "GO TO"
		canvas.draw_string(font, ts2 + Vector2(14, -6), "%s  %.0f m   %+.0f m high" % [what, ap.distance, tgt.y - me3.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


## Direction on the screen of a world direction (unit vector).
func dir_screen(dir: Vector3) -> Vector2:
	var a := _proj(ship.global_position)
	var b := _proj(ship.global_position + dir * 100.0)
	var d := b - a
	return d.normalized() if d.length() > 0.5 else Vector2.UP


func _draw_ruler(font: Font) -> void:
	var sz := canvas.size
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
