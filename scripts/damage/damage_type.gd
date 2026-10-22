class_name DamageType
extends RefCounted
## BASE CLASS of every damage type. To add a new one (explosion, laser, EMP...):
##   1. make scripts/damage/my_damage.gd:  extends DamageType, set `id`, override resolve()
##   2. add `register(MyDamage.new())` in DamageRegistry._register_defaults()
##   3. create hits with a DamageHit (set type_id = your id) and call ship.apply_hit(hit)
## Nothing else in the game needs to change.

var id: StringName = &"base"
var display_name: String = "Base"


## Turn a hit into a result. `material` is MaterialCatalog.info() of the module that was hit.
func resolve(_hit: DamageHit, _material: Dictionary) -> DamageResult:
	push_error("DamageType.resolve() must be overridden by %s" % id)
	return DamageResult.new()
