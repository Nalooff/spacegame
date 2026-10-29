class_name DamageRegistry
extends RefCounted
## Lookup of damage types by id:  DamageRegistry.get_type(&"kinetic")
## Register your own with  DamageRegistry.register(MyDamage.new())

static var _types: Dictionary = {}


static func get_type(id: StringName) -> DamageType:
	if _types.is_empty():
		_register_defaults()
	return _types.get(id)


static func register(t: DamageType) -> void:
	_types[t.id] = t


static func _register_defaults() -> void:
	register(KineticDamage.new())
	register(RammingDamage.new())
	register(WeaponDamage.new(&"energy", "Energy", 0.5, 0.0, 1.0))        # lasers, plasma: armor helps half as much
	register(WeaponDamage.new(&"piercing", "Piercing", 0.2, 0.0, 0.8))    # AP rounds: ignores most armor, a little less HP
	register(WeaponDamage.new(&"explosive", "Explosive", 1.0, 0.0006, 1.0)) # shells that bend the hull
	# register(MyDamage.new())   <- new types go here


## The damage types a weapon can use, in a FIXED order (the index is what travels over the network).
const WEAPON_TYPES: Array[StringName] = [&"kinetic", &"energy", &"piercing", &"explosive"]


static func weapon_index(id: StringName) -> int:
	return maxi(WEAPON_TYPES.find(id), 0)


static func weapon_type_id(index: int) -> StringName:
	return WEAPON_TYPES[clampi(index, 0, WEAPON_TYPES.size() - 1)]
