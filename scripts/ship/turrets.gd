class_name ShipTurrets
extends Node
## DUAL-PART TURRETS.  A turret is two modules that are linked in the editor:
##
##   BASE   (type "turret")        fixed to the hull. It is the crew station and the SWIVEL: the pivot point is the
##                                 centre (centroid) of the base. Its `dir` is the mount axis ("up" of the swivel).
##   BARREL (type "turret_barrel") the cannon. It is rendered inside a pivot node (BarrelPivot<N>) that yaws and pitches
##                                 around the base's pivot. The barrel's rest direction is the line pivot -> barrel centre.
##
## Settings of the BASE (all editable in the builder's Selection tab, saved in the ship file):
##   yaw_min / yaw_max      degrees left(+) / right(-) of the rest direction the barrel may turn. -180..180 = full circle
##   pitch_min / pitch_max  degrees above(+) / below(-) the base plane
##   turn_speed             degrees per second
##
## SELF-COLLISION (so a turret can never shoot through, or turn into, its own ship):
##   * a turn that would push the barrel into another module of the ship is refused (the barrel just stops),
##   * a turret does not fire while any other module of the ship is within Data.TURRET_BLOCK_RANGE in front of the muzzle.
## Both use the cheap GJK test on small point sets (ConvexOverlap), so they cost almost nothing.
##
## NETWORK: only the owner of the ship simulates the aim; the angles are replicated (2 floats per turret) and the
## other peers just pose their copy of the barrel.

const BARREL_POINTS := 24
const OTHER_POINTS := 40

class Rig:
	var base: int
	var barrel: int
	var pivot: Vector3          # ship space
	var up: Vector3
	var fwd0: Vector3           # horizontal forward of the swivel
	var right: Vector3
	var rest_pitch: float       # radians
	var yaw_min: float
	var yaw_max: float
	var pitch_min: float
	var pitch_max: float
	var speed: float            # rad/s
	var yaw: float = 0.0
	var pitch: float = 0.0
	var muzzle_len: float       # pivot -> muzzle tip
	var barrel_pts: PackedVector3Array = PackedVector3Array()
	var node: Node3D            # BarrelPivot (visual)
	var last_shape_yaw: float = 999.0
	var last_shape_pitch: float = 999.0
	var aim_error: float = 3.14

var ship: Ship
var rigs: Array[Rig] = []
var _other_pts: Dictionary = {}     # module -> decimated points (ship space), for the self-collision tests
var _other_lo: Dictionary = {}
var _other_hi: Dictionary = {}
var aim_point: Vector3 = Vector3.ZERO   ## world point the turrets track (set by the pilot's mouse / the crew's request)
var has_aim: bool = false


## Reads the turret links from the design. Called once the hull is ready (the barrel pivots are created by the ship).
func setup(s: Ship) -> void:
	ship = s
	rigs.clear()
	var d := s.design
	for bi in d.modules.size():
		if d.modules[bi]["type"] != ModuleCatalog.TURRET:
			continue
		var bar := int(d.extra(bi, "barrel"))
		if bar < 0 or bar >= d.modules.size() or d.modules[bar]["type"] != ModuleCatalog.BARREL:
			continue
		var r := Rig.new()
		r.base = bi
		r.barrel = bar
		r.pivot = d.module_centroid(bi)
		var rest := (d.module_centroid(bar) - r.pivot)
		r.up = (d.modules[bi]["dir"] as Vector3)
		r.up = r.up.normalized() if r.up.length() > 0.001 else Vector3.UP
		var flat := rest - r.up * rest.dot(r.up)
		if flat.length() < 0.001:
			flat = Vector3.FORWARD - r.up * Vector3.FORWARD.dot(r.up)
			if flat.length() < 0.001:
				flat = Vector3.RIGHT
		r.fwd0 = flat.normalized()
		r.right = r.fwd0.cross(r.up).normalized()
		r.rest_pitch = atan2(rest.dot(r.up), flat.length())
		r.yaw_min = deg_to_rad(float(d.extra(bi, "yaw_min")))
		r.yaw_max = deg_to_rad(float(d.extra(bi, "yaw_max")))
		r.pitch_min = deg_to_rad(float(d.extra(bi, "pitch_min")))
		r.pitch_max = deg_to_rad(float(d.extra(bi, "pitch_max")))
		r.speed = deg_to_rad(maxf(float(d.extra(bi, "turn_speed")), 1.0))
		r.pitch = clampf(r.rest_pitch, r.pitch_min, r.pitch_max)
		var rest_dir := (Basis(r.right, r.rest_pitch) * r.fwd0).normalized()
		var tip := 0.0
		for p in d.module_points(bar):
			tip = maxf(tip, (p - r.pivot).dot(rest_dir))
		r.muzzle_len = tip
		r.barrel_pts = HullShapes.points(d, HullShapes.hull_ids(d, bar, BARREL_POINTS))
		rigs.append(r)
	# points of everything else, for the self-collision tests
	_other_pts.clear()
	for mi in d.modules.size():
		var t: String = d.modules[mi]["type"]
		if t == ModuleCatalog.LOOSE or t == ModuleCatalog.BARREL or t == ModuleCatalog.TURRET:
			continue
		var pts := HullShapes.points(d, HullShapes.hull_ids(d, mi, OTHER_POINTS))
		_other_pts[mi] = pts
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		_other_lo[mi] = lo
		_other_hi[mi] = hi


func is_usable(r: Rig) -> bool:
	return ship.module_hp.size() > maxi(r.base, r.barrel) and ship.module_hp[r.base] > 0.0 and ship.module_hp[r.barrel] > 0.0


func usable_count() -> int:
	var n := 0
	for r in rigs:
		if is_usable(r):
			n += 1
	return n


## Rotation of the barrel relative to its rest pose, about the pivot (ship space).
func turn_basis(r: Rig, yaw: float, pitch: float) -> Basis:
	return Basis(r.up, yaw) * Basis(r.right, pitch - r.rest_pitch)


## Direction the barrel points (ship space).
func direction(r: Rig, yaw: float, pitch: float) -> Vector3:
	return (Basis(r.up, yaw) * Basis(r.right, pitch) * r.fwd0).normalized()


## Authority: turn every usable turret towards `aim_world`. Call every physics frame.
func track(dt: float) -> void:
	if not has_aim:
		return
	var inv := ship.global_transform.affine_inverse()
	var local_aim := inv * aim_point
	for r in rigs:
		if not is_usable(r):
			continue
		var t := (local_aim - r.pivot)
		if t.length() < 0.5:
			continue
		t = t.normalized()
		var tf := t.dot(r.fwd0)
		var t_right := t.dot(r.right)
		var tu := t.dot(r.up)
		var want_yaw := _limit_yaw(r, atan2(-t_right, tf))
		var want_pitch := clampf(atan2(tu, sqrt(tf * tf + t_right * t_right)), r.pitch_min, r.pitch_max)
		var step := r.speed * dt
		var new_yaw := _approach_yaw(r, r.yaw, want_yaw, step)
		var new_pitch := move_toward(r.pitch, want_pitch, step)
		if new_yaw != r.yaw or new_pitch != r.pitch:
			if not _barrel_blocked(r, new_yaw, new_pitch) or _barrel_blocked(r, r.yaw, r.pitch):
				r.yaw = new_yaw
				r.pitch = new_pitch
		r.aim_error = direction(r, r.yaw, r.pitch).angle_to(t)
	_pose_all()


func _limit_yaw(r: Rig, yaw: float) -> float:
	if r.yaw_max - r.yaw_min >= TAU - 0.01:
		return yaw
	return clampf(yaw, r.yaw_min, r.yaw_max)


func _approach_yaw(r: Rig, cur: float, want: float, step: float) -> float:
	if r.yaw_max - r.yaw_min >= TAU - 0.01:
		return cur + clampf(wrapf(want - cur, -PI, PI), -step, step)    # full circle: take the short way round
	return move_toward(cur, want, step)


## Replicated angles: [yaw0, pitch0, yaw1, pitch1, ...] in the order of `rigs`.
func angles() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for r in rigs:
		out.append(r.yaw)
		out.append(r.pitch)
	return out


## Non-authority peers: pose the copy of the barrels (smoothly).
func apply_angles(a: PackedFloat32Array, smooth: float) -> void:
	for i in rigs.size():
		if a.size() < (i + 1) * 2:
			break
		rigs[i].yaw = lerp_angle(rigs[i].yaw, a[i * 2], smooth)
		rigs[i].pitch = lerpf(rigs[i].pitch, a[i * 2 + 1], smooth)
	_pose_all()


func _pose_all() -> void:
	for r in rigs:
		var b := turn_basis(r, r.yaw, r.pitch)
		if r.node != null:
			r.node.transform = Transform3D(b, r.pivot)
		# the barrel's collision shape follows (only when it moved noticeably: changing it is not free)
		if absf(r.yaw - r.last_shape_yaw) + absf(r.pitch - r.last_shape_pitch) > 0.02 and r.barrel < ship._shapes.size():
			ship._shapes[r.barrel].transform = Transform3D(b, r.pivot - b * r.pivot)
			r.last_shape_yaw = r.yaw
			r.last_shape_pitch = r.pitch


## Would the barrel, turned to (yaw, pitch), push into another module of the ship?
func _barrel_blocked(r: Rig, yaw: float, pitch: float) -> bool:
	var b := turn_basis(r, yaw, pitch)
	var pts := PackedVector3Array()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in r.barrel_pts:
		var q := r.pivot + b * (p - r.pivot)
		pts.append(q)
		lo = lo.min(q)
		hi = hi.max(q)
	return _hits_other(pts, lo, hi, -0.02)


## True if the point set (with its bounding box) overlaps any ALIVE module that is not part of a turret.
func _hits_other(pts: PackedVector3Array, lo: Vector3, hi: Vector3, margin: float) -> bool:
	for mi in _other_pts:
		if ship.module_hp[mi] <= 0.0:
			continue
		var l: Vector3 = _other_lo[mi]
		var h: Vector3 = _other_hi[mi]
		if lo.x > h.x or hi.x < l.x or lo.y > h.y or hi.y < l.y or lo.z > h.z or hi.z < l.z:
			continue
		if ConvexOverlap.intersects(pts, _other_pts[mi], margin):
			return true
	return false


## World-space muzzle position and direction of a rig.
func muzzle(r: Rig) -> Array:
	var b := ship.global_transform.basis
	var d_local := direction(r, r.yaw, r.pitch)
	var o_local := r.pivot + d_local * r.muzzle_len
	return [ship.global_position + b * o_local, b * d_local]


## Is the line of fire free of the ship's own hull?
func line_of_fire_blocked(r: Rig) -> bool:
	var d_local := direction(r, r.yaw, r.pitch)
	var a := r.pivot + d_local * r.muzzle_len
	var c := a + d_local * Data.TURRET_BLOCK_RANGE
	var pts := PackedVector3Array([a, c])
	return _hits_other(pts, a.min(c), a.max(c), 0.0)


## Shots for this salvo: every usable, aimed turret whose line of fire is free. [{origin, dir}] in world space.
func firing_solution() -> Array:
	var out: Array = []
	for r in rigs:
		if not is_usable(r) or r.aim_error > deg_to_rad(Data.TURRET_AIM_TOLERANCE_DEG):
			continue
		if line_of_fire_blocked(r):
			continue
		var m := muzzle(r)
		out.append({"origin": m[0], "dir": m[1]})
	return out
