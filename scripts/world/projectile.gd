class_name Projectile
extends Node3D
## One pooled bullet. Lives permanently in the scene tree (ProjectilePool/ShotNN), is just
## switched on/off. Every peer simulates it; only the peer that owns the HIT ship applies damage.

const LIFETIME := 4.0

var active: bool = false
var velocity: Vector3 = Vector3.ZERO
var damage: float = 0.0
var shooter: Ship
var _age: float = 0.0


func _ready() -> void:
	deactivate()


func activate(pos: Vector3, vel: Vector3, from_ship: Ship, dmg: float) -> void:
	global_position = pos
	if vel.length() > 0.1:
		look_at(pos + vel, Vector3.UP if absf(vel.normalized().y) < 0.95 else Vector3.RIGHT)   # the tracer lies along -Z
	velocity = vel
	shooter = from_ship
	damage = dmg
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
	if _age > LIFETIME:
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
	if body != null and body.is_multiplayer_authority():
		var owner_id: int = body.shape_find_owner(hit["shape"])
		var shape_node := body.shape_owner_get_owner(owner_id) as CollisionShape3D
		if shape_node != null and shape_node.has_meta("module"):
			body.apply_hit(DamageHit.kinetic(int(shape_node.get_meta("module")), damage, hit["position"], shooter, velocity.normalized()))
	deactivate()
