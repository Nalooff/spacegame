class_name RammingDamage
extends DamageType
## Ship-ship collisions. `hit.amount` = closing speed along the contact normal.
##
##  threshold = yield_speed(victim) * sqrt(hardness(victim) / hardness(attacker))
##  closing speed <= threshold  ->  NOTHING (no dent, no damage): the physics engine just pushes the ships apart.
##  closing speed  > threshold  ->  HP loss from the kinetic energy above the threshold, and a dent whose depth
##                                  grows with the excess speed and shrinks with the victim's hardness.
##  sharpness (contact patch): a point / edge contact divides the threshold by sqrt(sharpness) and digs deeper.
## Tune the numbers in Data (RAM_* and DENT_*).

func _init() -> void:
	id = &"ramming"
	display_name = "Ramming"


static func threshold_speed(material: Dictionary, attacker_hardness: float) -> float:
	var h := maxf(float(material["hardness"]), 1.0)
	return float(material["yield_speed"]) * sqrt(h / maxf(attacker_hardness, 1.0))


func resolve(hit: DamageHit, material: Dictionary) -> DamageResult:
	var r := DamageResult.new()
	var sharp := maxf(hit.sharpness, 1.0)
	var threshold := threshold_speed(material, hit.attacker_hardness) / sqrt(sharp)   # a point concentrates the force: it dents sooner
	var excess := hit.amount - threshold
	if excess <= 0.0:
		return r
	var hardness := maxf(float(material["hardness"]), 1.0)
	var energy := 0.5 * hit.effective_mass * (hit.amount * hit.amount - threshold * threshold)
	r.hp_damage = energy * Data.RAM_ENERGY_TO_DAMAGE * 100.0 / (100.0 + hardness)
	r.dent_depth = minf(excess * Data.DENT_PER_MS * (50.0 / hardness) * pow(sharp, 0.7), Data.DENT_MAX_DEPTH)   # ... and goes deeper
	r.dent_radius = Data.DENT_BASE_RADIUS + r.dent_depth * 1.5
	# push the hull in the direction the attacker was travelling (into the ship)
	r.dent_direction = -hit.normal
	return r
