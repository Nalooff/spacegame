class_name ThrustAllocator
extends RefCounted
## Thruster maths ported from the validated Python simulation (ship_sim.py).
## Thrusters sit at ARBITRARY positions with ARBITRARY directions/powers, so every
## thruster also makes torque about the centre of mass. This class
##  * finds the ship's best-orientation thrust (-> RCS = 5 % of it),
##  * turns a wanted force into per-thruster throttles (bounded least squares,
##    lightly penalising torque), and reports the resulting force/torque.
## All vectors are in the ship's body frame, positions relative to the CoM.

const W_TORQUE := 0.02

var n: int = 0
var power: PackedFloat32Array = PackedFloat32Array()
var dirs: Array[Vector3] = []
var pos: Array[Vector3] = []
var col_f: Array[Vector3] = [] # force at full throttle
var col_t: Array[Vector3] = [] # torque at full throttle
var f_best: float = 0.0
var u_best: Vector3 = Vector3(0, 0, -1)
var flip_axis: Vector3 = Vector3.RIGHT
var worst_torque: float = 0.0 # largest torque the thrusters can make on any axis
var _h: PackedFloat32Array = PackedFloat32Array()
var _fs2: float = 1.0


func setup(powers: PackedFloat32Array, directions: Array[Vector3], positions: Array[Vector3]) -> void:
	n = powers.size()
	power = powers
	dirs = directions
	pos = positions
	col_f.clear()
	col_t.clear()
	var t_abs := Vector3.ZERO
	var lref := 0.0
	for i in n:
		col_f.append(dirs[i] * power[i])
		var tq := pos[i].cross(dirs[i]) * power[i]
		col_t.append(tq)
		t_abs += tq.abs()
		lref += pos[i].length()
	worst_torque = maxf(t_abs.x, maxf(t_abs.y, t_abs.z))
	lref = maxf(lref / maxf(n, 1), 0.1)
	_compute_best_axis()
	var fs := maxf(f_best, 0.001)
	_fs2 = fs * fs
	var ts2 := pow(fs * lref, 2.0)
	_h.resize(n * n)
	for i in n:
		for j in n:
			var v := col_f[i].dot(col_f[j]) / _fs2 + W_TORQUE * col_t[i].dot(col_t[j]) / ts2
			if i == j:
				v += 1e-5
			_h[i * n + j] = v
	var pb := u_best.cross(Vector3.RIGHT)
	if pb.length() < 0.3:
		pb = u_best.cross(Vector3.UP)
	flip_axis = pb.normalized()


## F_best = max over unit u of  sum_i P_i * max(0, d_i . u).
## At a maximiser the net force of the active thrusters points along u, so the
## fixed point u <- normalise(sum_active P_i d_i) is iterated from many seeds.
func _compute_best_axis() -> void:
	f_best = 0.0
	u_best = Vector3(0, 0, -1)
	if n == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var seeds: Array[Vector3] = []
	for i in n:
		if power[i] > 0.0:
			seeds.append(dirs[i])
	for k in 120:
		seeds.append(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized())
	for s in seeds:
		var u := s
		for it in 100:
			var f := Vector3.ZERO
			for i in n:
				if dirs[i].dot(u) > 0.0:
					f += col_f[i]
			if f.length() < 1e-9:
				break
			var u2 := f.normalized()
			if (u2 - u).length() < 1e-9:
				u = u2
				break
			u = u2
		var h := 0.0
		for i in n:
			h += power[i] * maxf(dirs[i].dot(u), 0.0)
		if h > f_best + 1e-9:
			f_best = h
			u_best = u


func rcs_max() -> float:
	return Data.RCS_FRACTION * f_best


## Bounded least squares by coordinate descent. `t` is the warm start (previous throttles).
func allocate(f_des: Vector3, t: PackedFloat32Array) -> PackedFloat32Array:
	if t.size() != n:
		t = PackedFloat32Array()
		t.resize(n)
	var g := PackedFloat32Array()
	g.resize(n)
	for i in n:
		g[i] = col_f[i].dot(f_des) / _fs2
	for it in 80:
		var delta := 0.0
		for i in n:
			var hd := _h[i * n + i]
			var acc := 0.0
			for j in n:
				acc += _h[i * n + j] * t[j]
			var ti := clampf((g[i] - acc + hd * t[i]) / hd, 0.0, 1.0)
			delta = maxf(delta, absf(ti - t[i]))
			t[i] = ti
		if delta < 1e-6:
			break
	return t


func force_of(t: PackedFloat32Array) -> Vector3:
	var f := Vector3.ZERO
	for i in n:
		f += col_f[i] * t[i]
	return f


func torque_of(t: PackedFloat32Array) -> Vector3:
	var q := Vector3.ZERO
	for i in n:
		q += col_t[i] * t[i]
	return q
