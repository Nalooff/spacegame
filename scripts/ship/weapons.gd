class_name ShipWeapons
extends Node
## Firing control. The owner (authority) decides to fire; each barrel (see ShipTurrets.Rig) has its own damage,
## cooldown, muzzle speed and spread, taken from the barrel module's stats x volume.
##
##   PROJECTILE barrels (cannon, railgun): one bolt per shot. The shot is replicated to every peer, each of which takes
##   a pre-placed Projectile from the ProjectilePool; only the peer that owns the HIT ship applies the damage.
##   BEAM barrels: while the trigger is held a "beam tick" goes out every Data.BEAM_TICK seconds. Every peer traces the
##   ray (it goes THROUGH several modules, see ProjectilePool.fire_beam) and draws it.
##
## Everything a shot costs (electricity, heat) is reported through firing_power() / firing_heat() for a short while
## after the shot, so Electricity and the ship's heat signature see it.

var ship: Ship
var _beam_timer: float = 0.0
var _glow: float = 0.0              ## > 0 shortly after a shot: counts as electrical load and heat
var _glow_elec: float = 0.0
var _glow_heat: float = 0.0
var glow_local: Vector3 = Vector3.ZERO   ## ship-space centre of the barrels that fired last (where the weapon heat comes from)
var _rng := RandomNumberGenerator.new()


func configure(s: Ship) -> void:
	ship = s
	_rng.randomize()


func _physics_process(dt: float) -> void:
	_beam_timer = maxf(_beam_timer - dt, 0.0)
	_glow = maxf(_glow - dt, 0.0)
	if ship != null and ship.turrets != null:
		ship.turrets.tick_cooldowns(dt)


func firing_power() -> float:
	return _glow_elec if _glow > 0.0 else 0.0


func firing_heat() -> float:
	return _glow_heat if _glow > 0.0 else 0.0


## Authority only. `aim_point` is a world position. Every usable barrel that points at it (within the tolerance), has
## cooled down and has a free line of fire shoots from its own muzzle.
var _hold: float = 0.0           # seconds the fire order has been given (order delay without communications)
var _last_call_ms: int = 0


## `manual`: a person is holding the trigger of THEIR turret (crew mode): it fires whether or not the barrel points at the aim.
## Not manual (commander mode, automatic gunnery): a barrel fires only while it points at the aimed target.
func try_fire(aim_point: Vector3, power_factor: float, only: PackedInt32Array = PackedInt32Array(), manual: bool = false) -> void:
	if power_factor < 0.1:
		return
	if only.is_empty():
		ship.turrets.aim_point = aim_point
		ship.turrets.has_aim = true
	else:
		ship.turrets.set_aim_for(only, aim_point)     # a crew member: only THEIR commander's turrets
	var slow := 1.0 / maxf(power_factor, 0.25)      # brown-out: everything reloads slower
	var origins := PackedVector3Array()
	var dirs := PackedVector3Array()
	var speeds := PackedFloat32Array()
	var damages := PackedFloat32Array()
	var kinds := PackedInt32Array()
	var extras := PackedFloat32Array()     # per bullet: size, lifetime, splash radius, tracer hue, penetration, mass (kg)
	var b_origins := PackedVector3Array()
	var b_dirs := PackedVector3Array()
	var b_dmg := PackedFloat32Array()
	var b_pen := PackedFloat32Array()
	var b_range := PackedFloat32Array()
	var b_kinds := PackedInt32Array()
	var elec := 0.0
	var heat := 0.0
	var fired_pos := Vector3.ZERO
	var fired_n := 0
	var now := Time.get_ticks_msec()
	if now - _last_call_ms > 300:
		_hold = 0.0            # a new burst of fire: the order starts walking to the gun stations now
	_hold += (now - _last_call_ms) * 0.001 if now - _last_call_ms <= 300 else 0.0
	_last_call_ms = now
	for shot in ship.turrets.firing_solution(_rng, only, manual):
		var r: ShipTurrets.Rig = shot["rig"]
		if _hold < ship.order_delay(r.base):
			continue           # without communications the "fire" order still has to be walked to this gun
		if r.beam:
			if _beam_timer > 0.0:
				continue
			b_origins.append(shot["origin"])
			b_dirs.append(shot["dir"])
			b_dmg.append(r.dps * Data.BEAM_TICK * minf(power_factor, 1.0))
			b_pen.append(r.penetration)
			b_range.append(r.beam_range)
			b_kinds.append(r.damage_type)
		else:
			if r.burst > 1:                    # a burst: short gaps, then the full cooldown
				r.burst_count += 1
				if r.burst_count >= r.burst:
					r.burst_count = 0
					r.cool = r.cooldown * slow / ship.role_bonus(r.base)
				else:
					r.cool = r.burst_gap * slow / ship.role_bonus(r.base)
			else:
				r.cool = r.cooldown * slow / ship.role_bonus(r.base)
			for pi in r.pellets:               # the shot damage is shared by the pellets
				origins.append(shot["origin"])
				dirs.append(shot["dir"] if pi == 0 else ShipTurrets.spread_dir(shot["base"], r.spread_deg, _rng))
				speeds.append(r.muzzle_speed * (1.0 + r.speed_jitter * _rng.randf_range(-1.0, 1.0)))
				damages.append(r.damage / r.pellets)
				kinds.append(r.damage_type)
				var spd: float = speeds[speeds.size() - 1]
				var mass_kg: float = r.recoil / maxf(spd * r.pellets, 1.0) if r.recoil > 0.0 else (r.damage / r.pellets) * Data.BULLET_KG_PER_DAMAGE
				extras.append_array(PackedFloat32Array([r.bullet_size, r.lifetime, r.splash, r.tracer_hue, r.pierce, maxf(mass_kg, 0.01)]))
			if r.recoil > 0.0 and ship.has_method("apply_impulse"):
				var o: Vector3 = shot["origin"]
				ship.apply_impulse(-(shot["base"] as Vector3) * r.recoil, o - ship.global_position)
		elec += r.elec_w
		heat += r.heat_w
		fired_pos += r.pivot
		fired_n += 1
	if origins.is_empty() and b_origins.is_empty():
		return
	if fired_n > 0:
		glow_local = fired_pos / fired_n
	_glow = 0.15
	_glow_elec = elec
	_glow_heat = heat
	if not origins.is_empty():
		fire.rpc(origins, dirs, speeds, damages, ship.linear_velocity, kinds, extras)
	if not b_origins.is_empty():
		_beam_timer = Data.BEAM_TICK
		beam.rpc(b_origins, b_dirs, b_dmg, b_pen, b_range, b_kinds)


## Called by a CREW member's peer (see Ship._crew_step). Runs on the pilot's peer, which owns the ship.
@rpc("any_peer", "call_remote", "unreliable")
func request_fire(aim_point: Vector3) -> void:
	if not is_multiplayer_authority() or not ship.alive:
		return
	var sender := multiplayer.get_remote_sender_id()
	if int(Net.players.get(sender, {}).get("crew_of", 0)) != multiplayer.get_unique_id():
		return # only registered crew of THIS ship may fire its turrets
	var bases := ship.bases_of_seat(Net.seat_of(sender))
	if bases.is_empty():
		return # their commander is not linked to any turret
	try_fire(aim_point, ship.electricity.ratio, bases, true)


## Crew: "my mouse points here" (sent a few times per second while no shot is requested).
@rpc("any_peer", "call_remote", "unreliable")
func request_aim(aim_point: Vector3) -> void:
	if not is_multiplayer_authority() or not ship.alive or not aim_point.is_finite():
		return
	if int(Net.players.get(multiplayer.get_remote_sender_id(), {}).get("crew_of", 0)) != multiplayer.get_unique_id():
		return
	var bases := ship.bases_of_seat(Net.seat_of(multiplayer.get_remote_sender_id()))
	if not bases.is_empty():
		ship.turrets.set_aim_for(bases, aim_point)


@rpc("authority", "call_local", "unreliable")
func fire(origins: PackedVector3Array, dirs: PackedVector3Array, speeds: PackedFloat32Array,
		damages: PackedFloat32Array, ship_vel: Vector3, kinds: PackedInt32Array = PackedInt32Array(),
		extras: PackedFloat32Array = PackedFloat32Array()) -> void:
	var pool := get_tree().get_first_node_in_group("projectile_pool") as ProjectilePool
	if pool == null:
		return
	for i in mini(origins.size(), mini(speeds.size(), damages.size())):
		var e := i * 6
		var has_e := extras.size() >= e + 6
		pool.spawn_shot(origins[i], dirs[i] * speeds[i] + ship_vel, ship, damages[i], DamageRegistry.weapon_type_id(kinds[i] if i < kinds.size() else 0),
			extras[e] if has_e else 0.3, extras[e + 1] if has_e else 4.0, extras[e + 2] if has_e else 0.0, extras[e + 3] if has_e else 0.1, extras[e + 4] if has_e else 0.0,
			extras[e + 5] if has_e else damages[i] * Data.BULLET_KG_PER_DAMAGE)


@rpc("authority", "call_local", "unreliable")
func beam(origins: PackedVector3Array, dirs: PackedVector3Array, damages: PackedFloat32Array,
		pens: PackedFloat32Array, ranges: PackedFloat32Array, kinds: PackedInt32Array = PackedInt32Array()) -> void:
	var pool := get_tree().get_first_node_in_group("projectile_pool") as ProjectilePool
	if pool == null:
		return
	for i in mini(origins.size(), mini(damages.size(), mini(pens.size(), ranges.size()))):
		pool.fire_beam(origins[i], dirs[i], damages[i], pens[i], ranges[i], ship, DamageRegistry.weapon_type_id(kinds[i] if i < kinds.size() else 1))
