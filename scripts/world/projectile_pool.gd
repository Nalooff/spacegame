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


func _process(dt: float) -> void:
	for i in _beams.size():
		if _beam_left[i] > 0.0:
			_beam_left[i] -= dt
			if _beam_left[i] <= 0.0:
				_beams[i].visible = false


## Wakes up the next free bullet (round robin). Recycles the oldest if all are in flight.
func spawn_shot(pos: Vector3, vel: Vector3, from_ship: Ship, dmg: float, dtype: StringName = &"kinetic") -> void:
	var count := get_child_count() - BEAM_POOL_SIZE
	if count <= 0:
		return
	for i in count:
		var p := get_child((_next + i) % count) as Projectile
		if p != null and not p.active:
			_next = (_next + i + 1) % count
			p.activate(pos, vel, from_ship, dmg, dtype)
			return
	var oldest := get_child(_next % count) as Projectile
	_next = (_next + 1) % count
	oldest.activate(pos, vel, from_ship, dmg, dtype)


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
