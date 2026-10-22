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
	# register(ExplosiveDamage.new())   <- new types go here
