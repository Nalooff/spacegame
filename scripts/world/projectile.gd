class_name Projectile
extends Node3D
## One pooled bullet. Lives permanently in the scene tree (ProjectilePool/ShotNN), is just
## switched on/off. Every peer simulates it; only the peer that owns the HIT ship applies damage.

const LIFETIME := 4.0

var active: bool = false
var velocity: Vector3 = Vector3.ZERO
var damage: float = 0.0
var damage_type: StringName = &"kinetic"
var shooter: Ship
var _age: float = 0.0
var life: float = LIFETIME
var pierce: float = 0.0          ## metres of modules it can still go through (0 = stops at the first one)
var _pierce0: float = 0.0
var splash: float = 0.0          ## explosion radius (m): the modules around the impact take damage too


func _ready() -> void:
	deactivate()


func activate(pos: Vector3, vel: Vector3, from_ship: Ship, dmg: float, dtype: StringName = &"kinetic",
		size: float = 0.3, lifetime: float = LIFETIME, splash_radius: float = 0.0, hue: float = 0.1, pierce_m: float = 0.0) -> void:
	pierce = pierce_m
	_pierce0 = pierce_m
	life = lifetime
	splash = splash_radius
	var bolt := get_node_or_null("Bolt") as MeshInstance3D
	if bolt != null:
		bolt.scale = Vector3(size / 0.3, 1.0, size / 0.3)         # the tracer is 0.3 m thick by default
		var mat := bolt.material_override as StandardMaterial3D
		if mat != null:
			var c := Color.from_hsv(hue, 0.8, 1.0)
			mat.albedo_color = c
			mat.emission = c
	global_position = pos
	if vel.length() > 0.1:
		look_at(pos + vel, Vector3.UP if absf(vel.normalized().y) < 0.95 else Vector3.RIGHT)   # the tracer lies along -Z
	velocity = vel
	shooter = from_ship
	damage = dmg
	damage_type = dtype
	_age = 0.0
	active = true
	visible = true
	set_physics_process(true)


func deactivate() -> void:
	active = false
	visible = false
	set_physics_process(false)


func _physics_process(dt: float) -> void:
	_age += dt
	if _age > life:
		deactivate()
		return
	var from := global_position
	var to := from + velocity * dt
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	if is_instance_valid(shooter):
		q.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		return
	global_position = hit["position"]
	var body := hit["collider"] as Ship
	var through := false
	if body != null:
		var owner_id: int = body.shape_find_owner(hit["shape"])
		var shape_node := body.shape_owner_get_owner(owner_id) as CollisionShape3D
		if shape_node != null and shape_node.has_meta("module"):
			var mi := int(shape_node.get_meta("module"))
			var dir := velocity.normalized()
			var frac := clampf(pierce / maxf(_pierce0, 0.1), 0.0, 1.0) if _pierce0 > 0.0 else 1.0
			if body.is_multiplayer_authority():
				body.apply_hit(DamageHit.weapon(damage_type, mi, damage * (0.35 + 0.65 * frac), hit["position"], shooter, dir, maxf(pierce, 0.5)))
				if splash > 0.0:
					_explode(body, mi, hit["position"])
			# PENETRATION: a bullet with penetration left goes on through the module (hard ones stop it sooner) and hurts
			# the next one behind it too
			if pierce > 0.0:
				var hardness := float(MaterialCatalog.info(body.design.material_of(mi))["hardness"])
				pierce -= Data.BEAM_MODULE_COST * (1.0 + hardness / 100.0)
				if pierce > 0.0:
					global_position = (hit["position"] as Vector3) + dir * 0.4
					velocity *= 0.9
					through = true
	if not through:
		deactivate()


## Explosion: the other modules of the hit ship whose centre is within `splash` metres share ONE extra helping of damage (the
## shell's damage), the nearer the more. (Before, every module in the radius took a full falloff share: on a compact ship a flak
## shell did ten times its damage - found with tests/duel_sim.gd.)
func _explode(body: Ship, hit_module: int, at: Vector3) -> void:
	var near: Array[Vector2] = []                 # (module, weight)
	var total := 0.0
	for mi in body.design.modules.size():
		if mi == hit_module or mi >= body.module_hp.size() or body.module_hp[mi] < 0.0:
			continue
		if body.design.modules[mi]["type"] == ModuleCatalog.LOOSE:
			continue
		var d := at.distance_to(body.global_transform * body.design.module_centroid(mi))
		if d < splash:
			var w := 1.0 - d / splash
			near.append(Vector2(mi, w))
			total += w
	for e in near:
		body.apply_hit(DamageHit.weapon(&"explosive", int(e.x), damage * e.y / maxf(total, 1.0), at, shooter, (at - body.global_position).normalized()))
