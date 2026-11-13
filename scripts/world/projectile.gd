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
var mass: float = 1.0            ## kg (momentum handed to what it hits, and who wins when two bullets meet)
var radius: float = 0.15         ## m (bullet-bullet collisions)
var ricochets: int = 0


func _ready() -> void:
	deactivate()


## The ship that fired, or null if it has been removed since (a bullet outlives its ship: no freed object may be passed on).
## Microseconds of hit handling allowed per physics frame, summed over all bullets.
const HIT_BUDGET_US := 8000
const BLAST_MAX_MODULES := 14
static var _frame_of_cost: int = -1
static var _frame_cost_us: int = 0


func _shooter_or_null() -> Ship:
	return shooter if is_instance_valid(shooter) else null


func activate(pos: Vector3, vel: Vector3, from_ship: Ship, dmg: float, dtype: StringName = &"kinetic",
		size: float = 0.3, lifetime: float = LIFETIME, splash_radius: float = 0.0, hue: float = 0.1, pierce_m: float = 0.0, mass_kg: float = 0.0) -> void:
	pierce = pierce_m
	mass = mass_kg if mass_kg > 0.0 else maxf(dmg * Data.BULLET_KG_PER_DAMAGE, 0.01)
	radius = maxf(size * 0.5, 0.05)
	ricochets = 0
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
		if splash > 0.0 and damage_type == &"explosive":
			airburst()               # a flak shell that found nothing bursts at the end of its life
		deactivate()
		return
	if _frame_of_cost != Engine.get_physics_frames():
		_frame_of_cost = Engine.get_physics_frames()
		_frame_cost_us = 0
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
			if _frame_cost_us > HIT_BUDGET_US:
				deactivate()      # a flood of hits in one frame (a broadside into a huge ship): the rest are absorbed so the game does not freeze
				return
			var t0 := Time.get_ticks_usec()
			through = _hit_module(body, int(shape_node.get_meta("module")), hit)
			_frame_cost_us += Time.get_ticks_usec() - t0
	if not through:
		deactivate()


## What happens when the bullet reaches a module. Returns true when the bullet goes on (through it, or glancing off).
##  * the ANGLE of the impact decides: a flat hit (along the surface normal) uses all its damage and has the shortest way
##    through the armour; a slanted one meets more armour (thickness / cos) and gives less (cos), and a grazing one
##    RICOCHETS: it bounces off the hull with part of its speed and does only a scratch;
##  * hard hulls turn bullets away earlier, fast and armour-piercing bullets later; explosive shells burst on contact and
##    energy bolts cannot ricochet (they just spread over the hull when slanted);
##  * the bullet's momentum pushes the hit ship (and a ricochet pushes it along the surface).
func _hit_module(body: Ship, mi: int, hit: Dictionary) -> bool:
	var at: Vector3 = hit["position"]
	var n: Vector3 = hit.get("normal", Vector3.ZERO)
	var v_body := body.velocity_at(Engine.get_physics_frames(), at)
	var v_rel := velocity - v_body
	var speed := v_rel.length()
	var dir := v_rel / maxf(speed, 0.001)
	if n.length_squared() < 0.5:
		n = -dir                                   # a bullet that started inside the hull: treat as a flat hit
	var cos_i := clampf(-dir.dot(n), 0.0, 1.0)
	var mat := MaterialCatalog.info(body.design.material_of(mi))
	var hardness := float(mat["hardness"])
	var frac := clampf(pierce / maxf(_pierce0, 0.1), 0.0, 1.0) if _pierce0 > 0.0 else 1.0
	var spent := damage * (0.35 + 0.65 * frac)
	# ---- ricochet?
	var angle := rad_to_deg(acos(cos_i))
	if damage_type != &"energy" and damage_type != &"explosive" or (damage_type == &"explosive" and angle > Data.RICOCHET_FULL_DEG - 2.0):
		var start := Data.RICOCHET_START_DEG - (hardness - 50.0) / 50.0 * 8.0 - pierce * 3.0 - clampf(speed / 1000.0, 0.0, 2.0) * 3.0
		var full := Data.RICOCHET_FULL_DEG - pierce * 1.5
		var p := smoothstep(start, maxf(full, start + 4.0), angle)
		if p > 0.0 and _roll(at) < p:
			if body.is_multiplayer_authority():
				var h := DamageHit.weapon(damage_type, mi, spent * Data.GLANCE_DAMAGE * (1.0 - cos_i * 0.5), at, _shooter_or_null(), dir, 0.0)
				h.dents = false
				body.apply_hit(h)
				body.apply_impulse(v_rel.slide(n) * mass * 0.3, at - body.global_position)
			_ricochet(v_rel, v_body, n, at, hardness)
			return true
	# ---- a normal hit: the slope changes damage and the way through the armour
	var slope_damage := 0.45 + 0.55 * pow(cos_i, 0.7)
	if damage_type == &"energy":
		slope_damage = 0.6 + 0.4 * cos_i                  # energy spreads out over a slanted hull
	elif damage_type == &"piercing":
		slope_damage = 0.7 + 0.3 * cos_i                  # AP rounds care less
	if body.is_multiplayer_authority():
		body.apply_hit(DamageHit.weapon(damage_type, mi, spent * slope_damage, at, _shooter_or_null(), dir, maxf(pierce, 0.5)))
		body.apply_impulse(v_rel * mass * 0.9, at - body.global_position)        # (what is lost as damage, the hull keeps as a push)
		if splash > 0.0:
			_explode(body, mi, at)
	# PENETRATION: a bullet with penetration left goes on through the module (hard ones stop it sooner, slanted ones have
	# a longer way through) and hurts the next one behind it too
	if pierce > 0.0:
		pierce -= Data.BEAM_MODULE_COST * (1.0 + hardness / 100.0) / maxf(cos_i, Data.SLOPE_MIN_COS)
		if pierce > 0.0:
			global_position = at + dir * 0.4
			velocity = v_body + v_rel * 0.9
			return true
	return false


## Bounce off the hull: the sideways speed is mostly kept, the normal speed turns around (hard hulls = livelier), a little scatter.
func _ricochet(v_rel: Vector3, v_body: Vector3, n: Vector3, at: Vector3, hardness: float) -> void:
	var vn := n * v_rel.dot(n)
	var vt := v_rel - vn
	var scatter := Vector3(_roll(at + Vector3.RIGHT), _roll(at + Vector3.UP), _roll(at + Vector3.BACK)) - Vector3(0.5, 0.5, 0.5)
	var out := vt * Data.RICOCHET_KEEP_TANGENT - vn * Data.RICOCHET_KEEP_NORMAL * (0.5 + hardness / 100.0)
	out += scatter * out.length() * 0.12
	velocity = v_body + out
	damage *= 0.5
	ricochets += 1
	_age += 0.25 * life                                  # a deformed, tumbling bullet does not fly on as long
	global_position = at + n * 0.3
	if ricochets > 3 or out.length() < 20.0:
		deactivate()
		return
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.RIGHT)


## Reproducible "dice" (0..1) from a position: every player's copy of this bullet gets the same roll.
func _roll(p: Vector3) -> float:
	var h := sin(p.x * 12.9898 + p.y * 78.233 + p.z * 37.719 + _age * 91.7) * 43758.5453
	return h - floorf(h)


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
	if near.size() > BLAST_MAX_MODULES:         # only the nearest ones: a blast in a thousand-module ship must not hurt a thousand modules
		near.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y > b.y)
		near.resize(BLAST_MAX_MODULES)
		total = 0.0
		for e in near:
			total += e.y
	for e in near:
		var h := DamageHit.weapon(&"explosive", int(e.x), damage * e.y / maxf(total, 1.0), at, _shooter_or_null(), (at - body.global_position).normalized())
		h.dents = false                  # the shell itself dents; its blast only hurts (a dent per module per shell was the slowest thing in the game)
		body.apply_hit(h)


## The shell bursts in the air: bullets of other ships within `splash` metres are wrecked or knocked off course.
func airburst() -> void:
	var pool := get_parent() as ProjectilePool
	if pool != null:
		pool.blast(self)
	deactivate()


## Called after a collision changed the velocity: point the tracer along the new path and shorten its life (it is dented).
func knock_off() -> void:
	_age += 0.2 * life
	if velocity.length() > 0.1:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.RIGHT)


## An energy bolt that survived a collision with a weaker one.
func reactivate_with(new_damage: float) -> void:
	damage = new_damage
	active = true
	visible = true
	set_physics_process(true)
