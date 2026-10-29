class_name WeaponDamage
extends DamageType
## The damage types a WEAPON preset can choose (kinetic is its own class, see kinetic_damage.gd).
##   hardness_share : how much of the material's hardness protects it (1 = like a bullet, 0 = armor is useless)
##   dent_per_damage: metres of dent per damage point (0 = no dent; explosions bend the hull)
##   hp_share       : multiplier on the HP removed (what the type is worse or better at)
## hp = amount * hp_share * 100 / (100 + hardness * hardness_share)

var hardness_share: float = 1.0
var dent_per_damage: float = 0.0
var hp_share: float = 1.0
var dent_max: float = 0.5


func _init(p_id: StringName = &"energy", p_name: String = "Energy", p_hardness := 0.5, p_dent := 0.0, p_hp := 1.0) -> void:
	id = p_id
	display_name = p_name
	hardness_share = p_hardness
	dent_per_damage = p_dent
	hp_share = p_hp


func resolve(hit: DamageHit, material: Dictionary) -> DamageResult:
	var r := DamageResult.new()
	r.hp_damage = hit.amount * hp_share * 100.0 / (100.0 + float(material["hardness"]) * hardness_share)
	if dent_per_damage > 0.0:
		r.dent_depth = minf(hit.amount * dent_per_damage * (50.0 / maxf(float(material["hardness"]), 1.0)), dent_max)
		r.dent_radius = Data.DENT_BASE_RADIUS + r.dent_depth * 1.5
		r.dent_direction = hit.direction if hit.direction.length_squared() > 0.0001 else -hit.normal
	return r
