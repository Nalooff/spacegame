class_name KineticDamage
extends DamageType
## Bullets. Removes HP from the module; harder materials take less. No dent.
##   hp = damage * 100 / (100 + hardness)      (steel 80 -> 56 %, aluminium 20 -> 83 %)

func _init() -> void:
	id = &"kinetic"
	display_name = "Kinetic"


func resolve(hit: DamageHit, material: Dictionary) -> DamageResult:
	var r := DamageResult.new()
	r.hp_damage = hit.amount * 100.0 / (100.0 + float(material["hardness"]))
	return r
