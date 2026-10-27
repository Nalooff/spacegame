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
##   turn_speed             degrees per second (a preset stat, see ModulePresets)
##   A base can have SEVERAL barrels. A barrel that does not touch its base is stuck: it only fires forward.
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
	var aim_error: float = 3.14     # angle between the barrel and the TARGET
	var goal_error: float = 0.0     # angle between the barrel and the best direction this turret can reach (0 = settled)
	var pivots: bool = true     # false: the barrel does not touch its base -> it is stuck and only fires forward
	var precision: float = 0.5  # 0..1 of the turret preset (spread = barrel spread + (1 - precision) * Data.TURRET_SPREAD_DEG)
	# ---- the barrel's weapon (read from its stats x volume once, see _make_rig)
	var beam: bool = false
	var damage: float = 0.0     # per shot (projectile barrels)
	var dps: float = 0.0        # beam damage per second
	var cooldown: float = 0.25
	var muzzle_speed: float = 260.0
	var spread_deg: float = 1.0
	var penetration: float = 0.0   # beam: metres of module it can go through
	var beam_range: float = 0.0
	var elec_w: float = 0.0        # electricity while firing
	var heat_w: float = 0.0        # heat while firing
	var cool: float = 0.0          # seconds until it can fire again

var ship: Ship
var rigs: Array[Rig] = []
var _other_pts: Dictionary = {}     # module -> decimated points (ship space), for the self-collision tests
var _other_lo: Dictionary = {}
var _other_hi: Dictionary = {}
var aim_point: Vector3 = Vector3.ZERO   ## world point the turrets track (set by the pilot's mouse / the crew's request)
var has_aim: bool = false
## Which turret bases take part in aiming / firing: -2 = all, -1 = none, else the module index of ONE base (see ShipStations).
var filter_base: int = -2
## Used when filter_base == -3: the bases of the player's COMMANDER links (a commander can control several turrets).
var filter_set: PackedInt32Array = PackedInt32Array()
## Aim set by CREW members for the turrets of THEIR commander: base module -> world point. Overrides aim_point.
var base_aim: Dictionary = {}


## Crew: the turrets `bases` (those linked to the crew member's commander) track `point`.
func set_aim_for(bases: PackedInt32Array, point: Vector3) -> void:
	for b in bases:
		base_aim[b] = point
	has_aim = true


## The owner takes (back) the aim of these bases.
func clear_aim_for(bases: PackedInt32Array) -> void:
	for b in bases:
		base_aim.erase(b)


## Reads the turret links from the design. Called once the hull is ready (the barrel pivots are created by the ship).
func setup(s: Ship) -> void:
	ship = s
	rigs.clear()
	var d := s.design
	for bi in d.modules.size():
		if d.modules[bi]["type"] != ModuleCatalog.TURRET:
			continue
		for bar in d.barrels_of(bi):
			if bar < 0 or bar >= d.modules.size() or d.modules[bar]["type"] != ModuleCatalog.BARREL:
				continue
			rigs.append(_make_rig(d, bi, bar))
	_collect_others(d)


## One rig per (turret base, barrel) pair. A barrel that does not TOUCH its base cannot pivot (see _touching).
func _make_rig(d: ShipDesign, bi: int, bar: int) -> Rig:
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
	r.speed = deg_to_rad(maxf(d.stat(bi, "turn_speed"), 1.0))
	r.precision = clampf(d.stat(bi, "precision"), 0.0, 1.0)
	var vol := d.module_volume(bar)
	r.beam = d.kind_of(bar) == "beam"
	r.damage = d.stat(bar, "damage_per_m3") * vol
	r.dps = d.stat(bar, "dps_per_m3") * vol
	r.cooldown = maxf(d.stat(bar, "cooldown"), 0.05)
	r.muzzle_speed = maxf(d.stat(bar, "muzzle_speed"), 10.0)
	r.spread_deg = d.stat(bar, "spread_deg") + (1.0 - r.precision) * Data.TURRET_SPREAD_DEG
	r.penetration = d.stat(bar, "penetration")
	r.beam_range = d.stat(bar, "range")
	var dmg_rate := r.dps if r.beam else r.damage / r.cooldown
	r.elec_w = d.stat(bar, "elec_per_dmg") * dmg_rate + d.stat(bi, "servo_w") * 0.2
	r.heat_w = d.stat(bar, "heat_per_dmg") * dmg_rate
	r.pivots = _touching(d, bi, bar)
	if not r.pivots:                       # stuck: forward only, no arc
		r.yaw_min = 0.0
		r.yaw_max = 0.0
		r.pitch_min = r.rest_pitch
		r.pitch_max = r.rest_pitch
	r.pitch = clampf(r.rest_pitch, r.pitch_min, r.pitch_max)
	var rest_dir := (Basis(r.right, r.rest_pitch) * r.fwd0).normalized()
	var tip := 0.0
	for p in d.module_points(bar):
		tip = maxf(tip, (p - r.pivot).dot(rest_dir))
	r.muzzle_len = tip
	r.barrel_pts = HullShapes.points(d, HullShapes.hull_ids(d, bar, BARREL_POINTS))
	return r


## A barrel pivots only while it touches its base: shared vertices, or the two shells overlap / touch (GJK).
static func _touching(d: ShipDesign, base: int, barrel: int) -> bool:
	var ids := {}
	for id in d.module_vertex_ids(base):
		ids[id] = true
	for id in d.module_vertex_ids(barrel):
		if ids.has(id):
			return true
	var a := HullShapes.points(d, HullShapes.hull_ids(d, base, 24))
	var b := HullShapes.points(d, HullShapes.hull_ids(d, barrel, 24))
	return ConvexOverlap.intersects(a, b, 0.08)   # positive margin = a small gap still counts as touching


func _collect_others(d: ShipDesign) -> void:
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


## Mean muzzle speed of the projectile barrels (for the lead calculation); beams are instant.
func average_muzzle_speed() -> float:
	var sum := 0.0
	var n := 0
	for r in rigs:
		if not r.beam and is_usable(r):
			sum += r.muzzle_speed
			n += 1
	return sum / n if n > 0 else 1.0e6


func in_use(r: Rig) -> bool:
	if filter_base == -3:
		return filter_set.has(r.base)
	return filter_base == -2 or r.base == filter_base


func is_usable(r: Rig) -> bool:
	return ship.module_hp.size() > maxi(r.base, r.barrel) and ship.is_working(r.base) and ship.is_working(r.barrel)


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
		var own := base_aim.has(r.base)
		if not is_usable(r) or not (in_use(r) or own):
			continue
		var t := ((inv * (base_aim[r.base] as Vector3)) if own else local_aim) - r.pivot
		if t.length() < 0.5:
			continue
		t = t.normalized()
		# the BEST direction this turret can reach (inside its arc), which is not the same as clamping yaw and pitch
		# one by one: at the edge of the arc the best pitch is a different one.
		var goal := _best_reachable(r, t)
		var want_yaw := goal.x
		var want_pitch := goal.y
		var step := r.speed * dt
		var new_yaw := _approach_yaw(r, r.yaw, want_yaw, step)
		var new_pitch := move_toward(r.pitch, want_pitch, step)
		_move_rig(r, new_yaw, new_pitch)
		r.aim_error = direction(r, r.yaw, r.pitch).angle_to(t)
		r.goal_error = direction(r, r.yaw, r.pitch).angle_to(direction(r, want_yaw, want_pitch))
	_pose_all()


## Move a rig towards (yaw, pitch) unless that pushes the barrel into the ship. If the combined move is blocked, try
## turning only one axis, so a turret does not freeze when it could still swing round (or lift) a little.
func _move_rig(r: Rig, new_yaw: float, new_pitch: float) -> void:
	if new_yaw == r.yaw and new_pitch == r.pitch:
		return
	if not _barrel_blocked(r, new_yaw, new_pitch):
		r.yaw = new_yaw
		r.pitch = new_pitch
		return
	if _barrel_blocked(r, r.yaw, r.pitch):         # already inside something: let it move out freely
		r.yaw = new_yaw
		r.pitch = new_pitch
		return
	if new_pitch != r.pitch and not _barrel_blocked(r, r.yaw, new_pitch):
		r.pitch = new_pitch
	elif new_yaw != r.yaw and not _barrel_blocked(r, new_yaw, r.pitch):
		r.yaw = new_yaw


## The (yaw, pitch) inside the arc whose direction is closest to the unit vector `t` (ship space, relative to the pivot).
## dir(y, p) = cos p * (cos y * fwd + sin y * left) + sin p * up, so for a given yaw the best pitch has a closed form.
func _best_reachable(r: Rig, t: Vector3) -> Vector2:
	var tf := t.dot(r.fwd0)
	var tl := -t.dot(r.right)
	var tu := t.dot(r.up)
	var yaw0 := atan2(tl, tf)
	var full := r.yaw_max - r.yaw_min >= TAU - 0.01
	var best := Vector2(yaw0, clampf(atan2(tu, sqrt(tf * tf + tl * tl)), r.pitch_min, r.pitch_max))
	if full:
		return best
	var best_score := -2.0
	var cands := PackedFloat32Array([clampf(yaw0, r.yaw_min, r.yaw_max)])
	var n := 24
	for i in n + 1:
		cands.append(lerpf(r.yaw_min, r.yaw_max, float(i) / n))
	var span := (r.yaw_max - r.yaw_min) / n
	for pass_i in 2:                              # coarse pass, then refine around the winner
		for y in cands:
			var a := tf * cos(y) + tl * sin(y)
			var pp := clampf(atan2(tu, a), r.pitch_min, r.pitch_max)
			var score := cos(pp) * a + sin(pp) * tu
			if score > best_score + 1e-6:
				best_score = score
				best = Vector2(y, pp)
		cands = PackedFloat32Array()
		for j in range(-4, 5):
			cands.append(clampf(best.x + span * j * 0.25, r.yaw_min, r.yaw_max))
	return best


func _approach_yaw(r: Rig, cur: float, want: float, step: float) -> float:
	if r.yaw_max - r.yaw_min >= TAU - 0.01:
		return cur + clampf(wrapf(want - cur, -PI, PI), -step, step)    # full circle: take the short way round
	return move_toward(cur, want, step)


## FACING LOCK: the ship-space direction u such that, when the ship is turned so that u points at the target, the most
## turrets can bring their barrels to bear (a turret counts fully when it can point exactly at it, less when the arc
## only gets it close). Candidates are the arc centres of the turrets, the six ship axes and the average arc centre.
## `prefer` (ship space) wins ties, so the ship does not flip between equally good faces.
func best_facing_axis(prefer: Vector3) -> Vector3:
	var cands: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN]
	var sum := Vector3.ZERO
	for r in rigs:
		if not is_usable(r):
			continue
		var yc := 0.0 if r.yaw_max - r.yaw_min >= TAU - 0.01 else (r.yaw_min + r.yaw_max) * 0.5
		var d := direction(r, yc, clampf(r.rest_pitch, r.pitch_min, r.pitch_max))
		cands.append(d)
		sum += d
	if sum.length() > 0.1:
		cands.append(sum.normalized())
	var best := prefer.normalized() if prefer.length() > 0.01 else Vector3.FORWARD
	var best_score := -1.0
	for u in cands:
		var score := 0.0
		for r in rigs:
			if not is_usable(r):
				continue
			var g := _best_reachable(r, u)
			score += maxf(0.0, 1.0 - direction(r, g.x, g.y).angle_to(u) / 0.35)
		score += 0.02 * u.dot(prefer)
		if score > best_score:
			best_score = score
			best = u
	return best


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
		if ship.module_hp[mi] < 0.0:      # a dead wreck is still solid; only GONE modules do not block
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


## Rigs that can fire now: usable, cooled down, aimed (stuck barrels fire forward regardless) and with a free line of fire.
## [{rig: Rig, origin, dir}] in world space. `dir` already includes the random spread.
## `only` (crew): just these bases; empty = the owner's current filter.
func firing_solution(rng: RandomNumberGenerator, only: PackedInt32Array = PackedInt32Array(), manual: bool = false) -> Array:
	var out: Array = []
	for r in rigs:
		var wanted := only.has(r.base) if not only.is_empty() else in_use(r)
		if not is_usable(r) or not wanted or r.cool > 0.0:
			continue
		# Automatic fire needs the barrel to POINT AT the target. A person holding the trigger of their own turret
		# (`manual`, crew mode) fires anyway, along the barrel, whatever it points at; it keeps turning towards the aim.
		if not manual and r.pivots and has_aim and r.aim_error > deg_to_rad(Data.TURRET_AIM_TOLERANCE_DEG):
			continue
		if line_of_fire_blocked(r):
			continue
		var m := muzzle(r)
		out.append({"rig": r, "origin": m[0], "dir": spread_dir(m[1], r.spread_deg, rng)})
	return out


## `dir` turned by a random angle of up to `deg` (uniform inside the cone).
static func spread_dir(dir: Vector3, deg: float, rng: RandomNumberGenerator) -> Vector3:
	if deg <= 0.001:
		return dir
	var ang := deg_to_rad(deg) * sqrt(rng.randf())
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	var turned := dir.rotated(side, ang)
	return turned.rotated(dir, rng.randf() * TAU).normalized()


func tick_cooldowns(dt: float) -> void:
	for r in rigs:
		r.cool = maxf(r.cool - dt, 0.0)
