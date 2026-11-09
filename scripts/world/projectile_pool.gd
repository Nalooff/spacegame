class_name ProjectilePool
extends Node3D
## Pool of reusable bullets and beam lines. They are created once in _ready() and then only switched on/off, so no node
## is created or freed while shooting. (They are made in code on purpose: nobody needs to see or edit 256 identical
## nodes in the editor.)
##
## Change how many bullets can fly at once in Data.PROJECTILE_POOL_SIZE.
## A bullet is a long glowing tracer (see TRACER_*), so it is visible from far away.

const TRACER_RADIUS := 0.3
const TRACER_LENGTH := 14.0
const TRACER_COLOR := Color(1.0, 0.75, 0.25)
const BEAM_POOL_SIZE := 16
const BEAM_SHOW_TIME := 0.14
const BEAM_COLOR := Color(0.4, 0.9, 1.0)

var _next: int = 0
var _beams: Array[MeshInstance3D] = []
var _beam_left: Array[float] = []
var _beam_next: int = 0


func _ready() -> void:
	add_to_group("projectile_pool")
	var tracer := _make_tracer()
	for i in Data.PROJECTILE_POOL_SIZE:
		var shot := Projectile.new()
		shot.name = "Shot%02d" % i
		var visual := MeshInstance3D.new()
		visual.name = "Bolt"
		visual.mesh = tracer
		visual.material_override = _glow_material(TRACER_COLOR)     # one each: the colour is set per bullet type
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.rotation_degrees.x = 90.0          # a capsule is long along Y; the bullet flies along -Z
		shot.add_child(visual)
		add_child(shot)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.5
	beam_mesh.bottom_radius = 0.5
	beam_mesh.height = 1.0
	beam_mesh.radial_segments = 8
	beam_mesh.material = _glow_material(BEAM_COLOR)
	for i in BEAM_POOL_SIZE:
		var b := MeshInstance3D.new()
		b.name = "Beam%02d" % i
		b.mesh = beam_mesh
		b.visible = false
		b.top_level = true
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		_beams.append(b)
		_beam_left.append(0.0)
	set_process(true)


func _make_tracer() -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = TRACER_RADIUS
	m.height = TRACER_LENGTH
	m.radial_segments = 6
	m.rings = 2
	m.material = _glow_material(TRACER_COLOR)
	return m


static func _glow_material(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 3.0
	return mat


## BULLET vs BULLET, once per physics frame: a swept test of every pair of nearby bullets of different ships (sorted along x so
## only neighbours are compared). Flak shells have a PROXIMITY FUSE: they burst near an enemy bullet.
func _physics_process(dt: float) -> void:
	var act: Array[Projectile] = []
	for i in get_child_count() - BEAM_POOL_SIZE:
		var p := get_child(i) as Projectile
		if p != null and p.active:
			act.append(p)
	if act.size() < 2:
		return
	act.sort_custom(func(a: Projectile, b: Projectile) -> bool: return a.global_position.x < b.global_position.x)
	for i in act.size():
		var a := act[i]
		for j in range(i + 1, act.size()):
			var b := act[j]
			if b.global_position.x - a.global_position.x > BROAD_MARGIN:
				break
			if a.active and b.active:
				_meet(a, b, dt)


const BROAD_MARGIN := 90.0

func _meet(a: Projectile, b: Projectile, dt: float) -> void:
	if a.shooter == b.shooter and is_instance_valid(a.shooter):
		return
	var a_energy := a.damage_type == &"energy"
	var b_energy := b.damage_type == &"energy"
	var d := b.global_position - a.global_position
	var w := b.velocity - a.velocity
	var ww := w.length_squared()
	var t := clampf(-d.dot(w) / ww, 0.0, dt) if ww > 0.000001 else 0.0
	var closest := d + w * t
	var dist2 := closest.length_squared()
	# proximity fuse
	for pair in [[a, b], [b, a]]:
		var f: Projectile = pair[0]
		if f.splash > 0.0 and f.damage_type == &"explosive" and dist2 < f.splash * f.splash * 0.12 and f.active:
			f.global_position += f.velocity * t
			f.airburst()
			return
	if a_energy != b_energy:
		return                               # solid bullets and plasma/energy bolts pass through each other
	var reach := a.radius + b.radius + Data.BULLET_HIT_SLACK
	if dist2 > reach * reach:
		return
	var n := closest.normalized() if closest.length_squared() > 0.000001 else (d.normalized() if d.length_squared() > 0.000001 else Vector3.UP)
	var vn := w.dot(n)
	if vn >= 0.0:
		return                               # already moving apart
	var pa := a.global_position + a.velocity * t
	var pb := b.global_position + b.velocity * t
	a.global_position = pa
	b.global_position = pb
	var ma := a.mass
	var mb := b.mass
	if a_energy and b_energy:                # two energy bolts cancel each other out, the stronger one keeps the rest
		var left := absf(a.damage - b.damage)
		var stronger := a if a.damage >= b.damage else b
		a.deactivate()
		b.deactivate()
		if left > a.damage * 0.1 + b.damage * 0.1:
			stronger.reactivate_with(left)
		return
	# a shell bursts when it hits anything
	for pair in [[a, b], [b, a]]:
		var sh: Projectile = pair[0]
		var other: Projectile = pair[1]
		if sh.damage_type == &"explosive" and sh.active:
			var share := sh.mass / (sh.mass + other.mass)
			other.velocity += (sh.velocity - other.velocity) * share * 0.5
			other.damage *= 0.5
			sh.airburst()
			return
	# solid on solid: a much lighter bullet is smashed, comparable ones bounce off each other (partly dented)
	var j := -(1.0 + 0.25) * vn / (1.0 / ma + 1.0 / mb)
	if ma > mb * 4.0 or mb > ma * 4.0:
		var light := a if ma < mb else b
		var heavy := b if ma < mb else a
		heavy.velocity += (light.velocity - heavy.velocity) * (light.mass / (light.mass + heavy.mass))
		heavy.damage *= 0.9
		light.deactivate()
		return
	a.velocity -= n * (j / ma)
	b.velocity += n * (j / mb)
	for p in [a, b]:
		(p as Projectile).damage *= 0.6
		(p as Projectile).knock_off()


## An explosion of an air-bursting shell: bullets of other ships inside its radius are shredded (light ones) or thrown aside.
func blast(shell: Projectile) -> void:
	var centre := shell.global_position
	for i in get_child_count() - BEAM_POOL_SIZE:
		var b := get_child(i) as Projectile
		if b == null or not b.active or b == shell or (b.shooter == shell.shooter and is_instance_valid(shell.shooter)):
			continue
		var dist := b.global_position.distance_to(centre)
		if dist >= shell.splash:
			continue
		var w := 1.0 - dist / shell.splash
		var dv := shell.damage * 2.0 * w / b.mass
		if w > 0.45 and b.mass < shell.mass * 3.0 or dv > b.velocity.length() * 0.6:
			b.deactivate()
		else:
			var away := (b.global_position - centre).normalized()
			b.velocity += away * dv
			b.damage *= 1.0 - 0.5 * w
			b.knock_off()


func _process(dt: float) -> void:
	for i in _beams.size():
		if _beam_left[i] > 0.0:
			_beam_left[i] -= dt
			if _beam_left[i] <= 0.0:
				_beams[i].visible = false


## Wakes up the next free bullet (round robin). Recycles the oldest if all are in flight.
func spawn_shot(pos: Vector3, vel: Vector3, from_ship: Ship, dmg: float, dtype: StringName = &"kinetic",
		size: float = TRACER_RADIUS, life: float = 4.0, splash: float = 0.0, hue: float = 0.1, pierce: float = 0.0, mass_kg: float = 0.0) -> void:
	var count := get_child_count() - BEAM_POOL_SIZE
	if count <= 0:
		return
	for i in count:
		var p := get_child((_next + i) % count) as Projectile
		if p != null and not p.active:
			_next = (_next + i + 1) % count
			p.activate(pos, vel, from_ship, dmg, dtype, size, life, splash, hue, pierce, mass_kg)
			return
	var oldest := get_child(_next % count) as Projectile
	_next = (_next + 1) % count
	oldest.activate(pos, vel, from_ship, dmg, dtype, size, life, splash, hue, pierce, mass_kg)


## One beam tick. The ray goes through modules: every module it crosses takes damage, which falls off with the
## penetration used up; hard materials use up more. Every peer traces it, the owner of a hit ship applies the damage.
func fire_beam(origin: Vector3, dir: Vector3, damage: float, penetration: float, max_range: float, shooter: Ship, dtype: StringName = &"energy") -> void:
	var space := get_world_3d().direct_space_state
	var from := origin
	var end := origin + dir * max_range
	var left := maxf(penetration, 0.1)
	for _i in 8:
		var q := PhysicsRayQueryParameters3D.create(from, origin + dir * max_range, 1)
		if is_instance_valid(shooter):
			q.exclude = [shooter.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		end = hit["position"]
		var body := hit["collider"] as Ship
		if body == null:
			break
		var owner_id: int = body.shape_find_owner(hit["shape"])
		var shape_node := body.shape_owner_get_owner(owner_id) as CollisionShape3D
		if shape_node == null or not shape_node.has_meta("module"):
			break
		var mi := int(shape_node.get_meta("module"))
		if body.is_multiplayer_authority():
			body.apply_hit(DamageHit.weapon(dtype, mi, damage * clampf(left / maxf(penetration, 0.1), 0.0, 1.0), hit["position"], shooter, dir, maxf(left, 0.5)))
		var hardness := float(MaterialCatalog.info(body.design.material_of(mi))["hardness"])
		left -= Data.BEAM_MODULE_COST * (1.0 + hardness / 100.0)
		if left <= 0.0:
			break
		from = (hit["position"] as Vector3) + dir * 0.4
	_show_beam(origin, end)


func _show_beam(a: Vector3, b: Vector3) -> void:
	var idx := _beam_next
	_beam_next = (_beam_next + 1) % _beams.size()
	var n := _beams[idx]
	var length := maxf(a.distance_to(b), 0.1)
	var z := (b - a).normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
	var y := z.cross(x).normalized()
	# CylinderMesh runs along its own Y: use `z` as the long axis
	n.global_transform = Transform3D(Basis(x * 0.35, z * length, -y * 0.35), (a + b) * 0.5)
	n.visible = true
	_beam_left[idx] = BEAM_SHOW_TIME
