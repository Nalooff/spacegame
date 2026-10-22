class_name ShipAutopilot
extends Node
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

enum Mode { OFF, GOTO }

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

# outputs (body frame), read by Ship
var out_throttle: PackedFloat32Array = PackedFloat32Array()
var out_f_rcs: Vector3 = Vector3.ZERO
var out_tau: Vector3 = Vector3.ZERO

var _a_eff := 0.0
var _arcs_eff := 0.0
var _alpha_eff := 1.0
var _t_flip := 1.0
var _goal := Vector3(0, 0, -1)
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


func go_to(p: Vector3) -> void:
	target = p
	mode = Mode.GOTO
	_settle = 0.0
	_arrived_sent = false
	on_target = false


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
	mode = Mode.OFF
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
	var fwd := b * ship.alloc.u_best
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


## Called by Ship every physics tick while mode != OFF.
func update(dt: float) -> void:
	var s := ship
	var b := s.global_transform.basis
	var err := target - s.global_position
	var d := err.length()
	distance = d
	var speed := s.linear_velocity.length()
	var v_des := err / d * _desired_speed(d, speed) if d > 1e-9 else Vector3.ZERO
	var a_cmd := (kv * (v_des - s.linear_velocity)).limit_length(_a_eff)
	var a_mag := a_cmd.length()
	var big_push := a_mag > 0.8 * _arcs_eff and s.alloc.f_best > 0.0
	if big_push:
		_goal = a_cmd / a_mag

	var tau_att := _attitude_torque(b)
	var f_des := s.mass * (b.transposed() * a_cmd)
	if big_push and att_error < deg_to_rad(align_gate_deg):
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
	elif speed > 1e-3 and a_cmd.dot(s.linear_velocity) < 0.0:
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
