class_name ShipWeapons
extends Node
## Turret control. The owner (authority) decides to fire; the shot is replicated to every
## peer, each of which takes a pre-placed Projectile node from the ProjectilePool in the
## world scene (no node is created at run time).

var ship: Ship
var _cooldown: float = 0.0
var _fire_glow: float = 0.0 ## > 0 shortly after a shot: counts as electrical load


func configure(s: Ship) -> void:
	ship = s


func _physics_process(dt: float) -> void:
	_cooldown = maxf(_cooldown - dt, 0.0)
	_fire_glow = maxf(_fire_glow - dt, 0.0)


func firing_power() -> float:
	if _fire_glow <= 0.0:
		return 0.0
	return ship.alive_turret_count() * Data.TURRET_POWER_COST


## Authority only. `aim_point` is a world position. Every usable turret that points at it (within the tolerance) and has a
## free line of fire shoots from its own muzzle (see ShipTurrets).
func try_fire(aim_point: Vector3, power_factor: float) -> void:
	if _cooldown > 0.0 or power_factor < 0.1:
		return
	ship.turrets.aim_point = aim_point
	ship.turrets.has_aim = true
	var origins := PackedVector3Array()
	var dirs := PackedVector3Array()
	for shot in ship.turrets.firing_solution():
		origins.append(shot["origin"])
		dirs.append(shot["dir"])
	if origins.is_empty():
		return
	_cooldown = Data.TURRET_COOLDOWN / maxf(power_factor, 0.25)
	_fire_glow = 0.15
	fire.rpc(origins, dirs, ship.linear_velocity)


## Called by a CREW member's peer (see Ship._crew_step). Runs on the pilot's peer, which owns the ship.
@rpc("any_peer", "call_remote", "unreliable")
func request_fire(aim_point: Vector3) -> void:
	if not is_multiplayer_authority() or not ship.alive:
		return
	var sender := multiplayer.get_remote_sender_id()
	if int(Net.players.get(sender, {}).get("crew_of", 0)) != multiplayer.get_unique_id():
		return # only registered crew of THIS ship may fire its turrets
	try_fire(aim_point, ship.electricity.ratio)


## Crew: "my mouse points here" (sent a few times per second while no shot is requested).
@rpc("any_peer", "call_remote", "unreliable")
func request_aim(aim_point: Vector3) -> void:
	if not is_multiplayer_authority() or not ship.alive or not aim_point.is_finite():
		return
	if int(Net.players.get(multiplayer.get_remote_sender_id(), {}).get("crew_of", 0)) != multiplayer.get_unique_id():
		return
	ship.turrets.aim_point = aim_point
	ship.turrets.has_aim = true


@rpc("authority", "call_local", "unreliable")
func fire(origins: PackedVector3Array, dirs: PackedVector3Array, ship_vel: Vector3) -> void:
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	if pool == null:
		return
	for i in origins.size():
		pool.spawn_shot(origins[i], dirs[i] * Data.TURRET_PROJECTILE_SPEED + ship_vel,
			ship, Data.TURRET_DAMAGE)
