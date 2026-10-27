class_name DamageHit
extends RefCounted
## One thing that happens to ONE module of a ship: a bullet, a collision, later an explosion...
## A hit only DESCRIBES the event. A DamageType (see damage_type.gd) turns it into a result,
## and Ship.apply_hit() applies that result.

var type_id: StringName = &"kinetic"
var module: int = -1
## Strength. Meaning depends on the type: bullet = damage points, ramming = closing speed (m/s).
var amount: float = 0.0
var point: Vector3 = Vector3.ZERO          # world position of the impact
var normal: Vector3 = Vector3.UP           # world, points OUT of the hit ship
var relative_velocity: Vector3 = Vector3.ZERO  # attacker velocity as seen by the victim
var effective_mass: float = 0.0            # ramming: reduced mass of both ships (kg)
var attacker_hardness: float = 50.0        # ramming: hardness of what hit us
var direction: Vector3 = Vector3.ZERO      # world direction the damage travelled (bullet velocity); ZERO = into the hull
var reach: float = 0.0                     # metres it travelled inside the ship (0 = estimated from the damage)
var source: Node = null                    # who did it (Ship) or null


static func kinetic(module_index: int, damage: float, at: Vector3 = Vector3.ZERO, shooter: Node = null,
		dir: Vector3 = Vector3.ZERO, depth: float = 0.0) -> DamageHit:
	var h := DamageHit.new()
	h.type_id = &"kinetic"
	h.module = module_index
	h.amount = damage
	h.point = at
	h.source = shooter
	h.direction = dir
	h.reach = depth
	return h


static func ramming(module_index: int, closing_speed: float, at: Vector3, out_normal: Vector3, rel_vel: Vector3,
		reduced_mass: float, hardness_of_attacker: float, other: Node = null) -> DamageHit:
	var h := DamageHit.new()
	h.type_id = &"ramming"
	h.module = module_index
	h.amount = closing_speed
	h.point = at
	h.normal = out_normal
	h.relative_velocity = rel_vel
	h.effective_mass = reduced_mass
	h.attacker_hardness = hardness_of_attacker
	h.source = other
	return h
