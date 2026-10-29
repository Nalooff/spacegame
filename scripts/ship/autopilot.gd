class_name ShipAutopilot
extends Node
## Autopilot with two flight modes:
##   GOTO   fly to a point and STOP there (speed profile below).
##   DRIVE  fly towards a point (or a tracked ship) with a chosen THRUST (0..1) and NEVER stop: no braking on arrival,
##          so the ship can ram. Only `brake()` / `cancel()` ends it. Sideways drift is cancelled while driving.
## Either mode can additionally FACE TURRETS: the ship is turned so the most turrets bear on the locked enemy (or on the
## destination) instead of pointing its best thrust axis along the push; the thrusters then push as well as they can.
##
## Coordinate autopilot: fly to (x, y, z) and stop there. GDScript port of the Python
## simulation (ship_sim.py) that was validated on random ships. No speed cap: the speed
## profile is simply the fastest speed the ship can still brake from.
##
## Pipeline each physics tick:
##  speed profile -> velocity loop -> wanted force
##  -> gyroscope points the ship's BEST thrust axis along the wanted push (flip + retro burn)
##  -> thruster allocator (arbitrary positions/directions/powers) -> throttles
##  -> RCS (at the CoM) supplies what thrusters could not (<= 5 % of best thrust)
##  -> gyroscope also cancels the torque of off-centre thrusters.

signal arrived

enum Mode { OFF, GOTO, DRIVE }

@export var brake_frac_main: float = 0.5 ## share of best-axis acceleration used by the planned brake
@export var brake_frac_rcs: float = 0.5
@export var d_fine: float = 1.0          ## m: below this only RCS works
@export var d_margin: float = 0.5        ## m: fixed safety room
@export var kv: float = 2.0              ## 1/s velocity loop gain
@export var k_att: float = 6.0           ## 1/s attitude-rate gain
@export var k_pos_fine: float = 1.5
@export var align_gate_deg: float = 30.0 ## thrusters stay off until the nose is this close

var ship: Ship
var mode: Mode = Mode.OFF
var target: Vector3 = Vector3.ZERO
var phase: String = "OFF"
var distance: float = 0.0
var att_error: float = 0.0
var on_target: bool = false
var throttle: float = 1.0               ## DRIVE: fraction of the best-axis acceleration that is asked for (0..1)
var track_ship: Ship = null             ## DRIVE: follow this ship instead of the fixed `target` (ramming a moving enemy)
var face_turrets: bool = false          ## attitude follows the turret-facing lock (see ShipTurrets.best_facing_axis)
var heading: Vector3 = Vector3.ZERO     ## DRIVE: a fixed world DIRECTION (unit vector) to fly along, forever. ZERO = fly at `target` / `track_ship`
var follow_distance: float = 40.0       ## GOTO on a ship: it holds this far from it, matching its velocity
var player_order: bool = false          ## true: the player gave this order; the commander AI must not replace it

# outputs (body frame), read by Ship
var out_throttle: PackedFloat32Array = PackedFloat32Array()
var out_f_rcs: Vector3 = Vector3.ZERO
var out_tau: Vector3 = Vector3.ZERO

var _a_eff := 0.0
var _arcs_eff := 0.0
var _alpha_eff := 1.0
var _t_flip := 1.0
var _goal := Vector3(0, 0, -1)
var _att_axis := Vector3(0, 0, -1)       # ship-space axis that the attitude loop points along `_goal`
var _face_axis := Vector3(0, 0, -1)
var _face_timer := 0.0
var _settle := 0.0
var _arrived_sent := false


## (Re)compute planning limits. Called at spawn and whenever a module is destroyed.
func configure(s: Ship) -> void:
	ship = s
	var pr := ship.electricity.ratio
	_a_eff = ship.alloc.f_best / ship.mass * pr
	_arcs_eff = ship.rcs.force_max / ship.mass * pr
	_alpha_eff = ship.gyro.alpha_max * pr
	_t_flip = 2.0 * sqrt(PI / (0.6 * _alpha_eff)) * 0.75 + 0.2 # time budget for the 180 degree flip
	out_throttle.resize(ship.alloc.n)
	_goal = ship.global_transform.basis * ship.alloc.u_best
	_att_axis = ship.alloc.u_best


func go_to(p: Vector3, by_player: bool = false) -> void:
	heading = Vector3.ZERO
	target = p
	mode = Mode.GOTO
	player_order = by_player
	track_ship = null
	_settle = 0.0
	_arrived_sent = false
	on_target = false


## GO TO a moving ship: fly to it and hold `follow_distance` from it, matching its velocity (it is the frame of reference).
func go_follow(other: Ship, by_player: bool = true) -> void:
	go_to(other.global_position, by_player)
	track_ship = other


## DRIVE along a DIRECTION (an arrow, not a point): push that way with thrust `thr` 0..1, forever. Sideways drift is cancelled.
func drive_heading(dir: Vector3, thr: float, by_player: bool = true) -> void:
	if dir.length_squared() < 1e-8:
		return
	heading = dir.normalized()
	track_ship = null
	target = ship.global_position + heading * 1000.0
	throttle = clampf(thr, 0.0, 1.0)
	mode = Mode.DRIVE
	player_order = by_player
	_arrived_sent = true
	on_target = false


## DRIVE towards `p` (or keep driving at `follow`, whose position is tracked) with thrust `thr` 0..1. Never stops by itself.
## Chasing a ship aims at its INTERCEPT point (where it will be when we get there), not where it is now.
func drive_to(p: Vector3, thr: float, follow: Ship = null, by_player: bool = true) -> void:
	heading = Vector3.ZERO
	target = p
	track_ship = follow
	throttle = clampf(thr, 0.0, 1.0)
	mode = Mode.DRIVE
	player_order = by_player
	_arrived_sent = true       # DRIVE never reports "arrived"
	on_target = false


## Where a target moving at `tvel` from `tpos` will be when this ship gets there. The ship accelerates at `accel` m/s2 from
## its own velocity `own_vel`; a few rounds of "time to cover the distance, then where is the target by then" settle it.
static func intercept_point(from: Vector3, own_vel: Vector3, accel: float, tpos: Vector3, tvel: Vector3) -> Vector3:
	var aim := tpos
	for _i in 6:
		var to := aim - from
		var d := to.length()
		if d < 0.01:
			return tpos
		var v0 := maxf(own_vel.dot(to / d), 0.0)
		var t := d / maxf(v0, 1.0)
		if accel > 0.001:
			t = (-v0 + sqrt(v0 * v0 + 2.0 * accel * d)) / accel
		aim = tpos + tvel * minf(t, 120.0)
	return aim


## The point the order really steers at: the intercept point of a tracked ship, the fixed target otherwise.
func aim_point() -> Vector3:
	if track_ship != null and is_instance_valid(track_ship) and track_ship.alive and ship != null:
		return intercept_point(ship.global_position, ship.linear_velocity, _a_eff, track_ship.global_position, track_ship.linear_velocity)
	return current_target()


## The world direction DRIVE pushes along (unit vector).
func drive_direction() -> Vector3:
	if heading != Vector3.ZERO and track_ship == null:
		return heading
	var to := aim_point() - ship.global_position
	return to.normalized() if to.length() > 1e-6 else ship.global_transform.basis * ship.alloc.u_best


## The point the ship is currently heading for (follows `track_ship`).
func current_target() -> Vector3:
	if track_ship != null and is_instance_valid(track_ship) and track_ship.alive:
		return track_ship.global_position
	return target


## Stop as fast as sensible: aim at the point where the ship would come to rest.
func brake() -> void:
	var v := ship.linear_velocity
	var sp := v.length()
	if sp < 0.05:
		go_to(ship.global_position)
		return
	var stop_dist: float = sp * _t_flip + sp * sp / (2.0 * maxf(brake_frac_main * _a_eff, 0.05))
	go_to(ship.global_position + v / sp * stop_dist)


func cancel() -> void:
	heading = Vector3.ZERO
	mode = Mode.OFF
	player_order = false
	track_ship = null
	phase = "OFF"
	on_target = false
	out_throttle.fill(0.0)


func is_active() -> bool:
	return mode != Mode.OFF


func _desired_speed(d: float, speed: float) -> float:
	var a_m := brake_frac_main * _a_eff
	var a_r := brake_frac_rcs * _arcs_eff
	var v_f := sqrt(2.0 * a_r * d_fine)
	if d > d_fine:
		var margin := d_margin + _t_flip * speed
		return sqrt(v_f * v_f + 2.0 * a_m * maxf(d - d_fine - margin, 0.0))
	return minf(sqrt(2.0 * a_r * d), k_pos_fine * d * 3.0)


func _attitude_torque(b: Basis) -> Vector3:
	var fwd := b * _att_axis
	var axis := fwd.cross(_goal)
	var sn := axis.length()
	var cs := fwd.dot(_goal)
	att_error = atan2(sn, cs)
	if sn < 1e-6:
		axis = (b * ship.alloc.flip_axis) if cs < 0.0 else Vector3.ZERO
	else:
		axis /= sn
	var alpha := 0.6 * _alpha_eff
	var w_des := minf(sqrt(2.0 * alpha * att_error), 9.0 * att_error)
	var bt := b.transposed()
	var w_body := bt * (axis * w_des)
	var omega_body := bt * ship.angular_velocity
	return ship.inertia * (k_att * (w_body - omega_body))


## World point the turrets should face: the locked enemy (if any), else the destination.
func _face_point() -> Vector3:
	if ship.detection != null and ship.detection.locked != null:
		var c := ship.detection.find_contact(ship.detection.locked)
		if not c.is_empty():
			return c["est_pos"]
	return current_target()


## Called by Ship every physics tick while mode != OFF.
func update(dt: float) -> void:
	if mode == Mode.DRIVE:
		_update_drive(dt)
		return
	var s := ship
	var b := s.global_transform.basis
	var tvel := Vector3.ZERO           # a tracked ship is the frame of reference: we steer relative to it
	if track_ship != null:
		if is_instance_valid(track_ship) and track_ship.alive:
			target = track_ship.global_position
			tvel = track_ship.linear_velocity
		else:
			track_ship = null          # it is gone: carry on to where it was
	var err := target - s.global_position
	var d := err.length()
	if track_ship != null and d > 1e-6:
		err -= err / d * minf(d, follow_distance)       # hold `follow_distance` short of it
		d = err.length()
	distance = d
	var v_rel := s.linear_velocity - tvel
	var speed := v_rel.length()
	var v_des := err / d * _desired_speed(d, speed) if d > 1e-9 else Vector3.ZERO
	var a_cmd := (kv * (v_des - v_rel)).limit_length(_a_eff)
	var a_mag := a_cmd.length()
	var big_push := a_mag > 0.8 * _arcs_eff and s.alloc.f_best > 0.0
	if big_push:
		_goal = a_cmd / a_mag

	_att_axis = s.alloc.u_best
	var faced := _apply_facing(dt)
	var tau_att := _attitude_torque(b)
	var f_des := s.mass * (b.transposed() * a_cmd)
	if big_push and (faced or att_error < deg_to_rad(align_gate_deg)):
		out_throttle = s.alloc.allocate(f_des, out_throttle)
	else:
		out_throttle.fill(0.0)
	var f_thr := s.alloc.force_of(out_throttle)
	var tau_thr := s.alloc.torque_of(out_throttle)
	out_f_rcs = f_des - f_thr          # RCS tops up (clamped by Ship through the RCS node)
	out_tau = tau_att - tau_thr        # gyroscope cancels thruster torque

	var fired := false
	for t in out_throttle:
		if t > 1e-4:
			fired = true
			break
	if not big_push:
		phase = "FINE-RCS"
	elif not fired:
		phase = "TURN"
	elif speed > 1e-3 and a_cmd.dot(v_rel) < 0.0:
		phase = "BRAKE"
	elif d > d_fine and speed >= 0.98 * _desired_speed(d, speed):
		phase = "CRUISE"
	else:
		phase = "ACCEL"

	on_target = d < 0.05 and speed < 0.05
	if on_target:
		_settle += dt
		if _settle >= 1.0 and not _arrived_sent:
			_arrived_sent = true
			arrived.emit()
	else:
		_settle = 0.0


## Facing lock: point the best-facing turret axis at the enemy instead of pointing the thrust axis along the push.
## Returns true when the facing lock is in charge of the attitude (thrust then does not wait for alignment).
func _apply_facing(dt: float) -> bool:
	if not face_turrets or ship.turrets == null or ship.turrets.rigs.is_empty():
		return false
	_face_timer -= dt
	if _face_timer <= 0.0:
		_face_timer = 1.0
		_face_axis = ship.turrets.best_facing_axis(_face_axis)
	var to := _face_point() - ship.global_position
	if to.length() < 1.0:
		return false
	_att_axis = _face_axis
	_goal = to.normalized()
	return true


## DRIVE: push towards the target with `throttle` of the best-axis acceleration, never slowing for arrival.
func _update_drive(dt: float) -> void:
	var s := ship
	var b := s.global_transform.basis
	var err := current_target() - s.global_position
	var d := err.length()
	distance = d
	var dir := drive_direction()
	var v := s.linear_velocity
	var lateral := v - dir * v.dot(dir)
	# push along the line to the target, but lean against sideways drift so the ship really goes THERE
	var push := (dir - lateral / maxf(_a_eff * 2.0, 1.0)).normalized()
	var a_cmd := push * _a_eff * throttle
	_att_axis = s.alloc.u_best
	if a_cmd.length() > 1e-4:
		_goal = push
	var faced := _apply_facing(dt)
	var tau_att := _attitude_torque(b)
	var f_des := s.mass * (b.transposed() * a_cmd)
	if s.alloc.f_best > 0.0 and throttle > 0.001 and (faced or att_error < deg_to_rad(align_gate_deg)):
		out_throttle = s.alloc.allocate(f_des, out_throttle)
	else:
		out_throttle.fill(0.0)
	var f_thr := s.alloc.force_of(out_throttle)
	var tau_thr := s.alloc.torque_of(out_throttle)
	out_f_rcs = f_des - f_thr if throttle > 0.001 else Vector3.ZERO
	out_tau = tau_att - tau_thr
	phase = "DRIVE %d%%%s" % [int(throttle * 100.0), " FACING" if faced else ""]
	on_target = false
