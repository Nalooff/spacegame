class_name MaterialCatalog
extends RefCounted
## Materials a module can be made of. They decide how well a module resists damage.
##   density_mult  multiplies the module type's density (heavier metal = heavier ship)
##   hardness      resistance, 0..150. Bullet damage is divided by (1 + hardness/100).
##   yield_speed   closing speed (m/s) at which this material starts to dent when it is hit
##                 by something equally hard. Harder attacker = dents sooner.
##   restitution   how springy it is, 0..1: the share of the closing speed it gives back when it is NOT dented
##                 (the two hulls' values are averaged; see Ship._restitution)
## To add a material: add a line here (and nothing else).

const MATERIALS := {
	"aluminium": {"name": "Aluminium", "density_mult": 0.9, "hardness": 20.0, "yield_speed": 4.0, "restitution": 0.30},
	"bronze": {"name": "Bronze", "density_mult": 1.15, "hardness": 45.0, "yield_speed": 6.0, "restitution": 0.22},
	"steel": {"name": "Steel", "density_mult": 1.0, "hardness": 80.0, "yield_speed": 10.0, "restitution": 0.45},
	"titanium": {"name": "Titanium", "density_mult": 0.8, "hardness": 110.0, "yield_speed": 12.0, "restitution": 0.55},
}
const IDS: Array[String] = ["aluminium", "bronze", "steel", "titanium"]

## Material used when a module does not name one.
const TYPE_DEFAULT := {
	ModuleCatalog.HULL: "aluminium",
	ModuleCatalog.ARMOR: "steel",
	ModuleCatalog.THRUSTER: "bronze",
	ModuleCatalog.TURRET: "steel",
	ModuleCatalog.COMMANDER: "titanium",
}


static func default_for(type: String) -> String:
	return TYPE_DEFAULT.get(type, "steel")


static func info(id: String) -> Dictionary:
	return MATERIALS.get(id, MATERIALS["steel"])
