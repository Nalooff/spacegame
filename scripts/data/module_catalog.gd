class_name ModuleCatalog
extends RefCounted
## Static description of every module type (colour, weight, toughness, defaults).
## External modules = physical shells (damageable). Internal modules are NOT here:
## they live as nodes under Ship/Systems (Electricity, Gyroscope, RCS).

const HULL := "hull"
const ARMOR := "armor"
const THRUSTER := "thruster"
const TURRET := "turret"
const COMMANDER := "commander"
## Second half of a turret: the cannon. It sits on a TURRET module (the base / crew station) and turns on it.
const BARREL := "turret_barrel"
## Not a real module: faces the player has drawn but not yet put into a closed container (see ShipDesign / builder).
## A ship with loose faces cannot be saved.
const LOOSE := "loose"

## Types the builder offers (LOOSE is managed by the face tool).
const TYPES := [HULL, ARMOR, THRUSTER, TURRET, BARREL, COMMANDER]

## density kg/m^3, hp per m^3 of volume (min MIN_HP), colour
const TYPE_INFO := {
	HULL: {"density": 300.0, "hp_per_m3": 400.0, "color": Color(0.55, 0.58, 0.65)},
	ARMOR: {"density": 900.0, "hp_per_m3": 1500.0, "color": Color(0.35, 0.40, 0.50)},
	THRUSTER: {"density": 500.0, "hp_per_m3": 300.0, "color": Color(0.95, 0.55, 0.15)},
	TURRET: {"density": 450.0, "hp_per_m3": 300.0, "color": Color(0.85, 0.25, 0.25)},
	COMMANDER: {"density": 400.0, "hp_per_m3": 600.0, "color": Color(0.25, 0.75, 0.95)},
	BARREL: {"density": 600.0, "hp_per_m3": 400.0, "color": Color(0.7, 0.18, 0.18)},
	LOOSE: {"density": 0.0, "hp_per_m3": 0.0, "color": Color(1.0, 0.05, 0.4)},
}

const MIN_HP := 20.0

## Crew seats a ship can have (set on its Commander module, pilot included).
const CREW_MIN := 1
const CREW_MAX := 8

## Thruster limits for the builder
const THRUSTER_MIN_POWER := 200.0
const THRUSTER_MAX_POWER := 8000.0
const THRUSTER_DEFAULT_POWER := 2000.0


## Default starting shape + half-size (metres) the builder offers for each module type.
const DEFAULT_PRIMITIVE := {
	HULL: "box", ARMOR: "box", THRUSTER: "cylinder", TURRET: "dome", BARREL: "cylinder", COMMANDER: "box",
}
const DEFAULT_HALF_SIZE := {
	HULL: Vector3(0.6, 0.4, 0.8),
	ARMOR: Vector3(0.6, 0.12, 0.6),
	THRUSTER: Vector3(0.2, 0.25, 0.2),
	TURRET: Vector3(0.3, 0.3, 0.3),
	BARREL: Vector3(0.07, 0.07, 0.45),
	COMMANDER: Vector3(0.4, 0.3, 0.5),
}

## Short help text shown in the builder.
const TYPE_HELP := {
	HULL: "Light structure. Cheap, low HP.",
	ARMOR: "Heavy and tough. Soaks up damage.",
	THRUSTER: "Pushes the ship along its Direction setting. Position + direction decide how it turns the ship.",
	TURRET: "Turret BASE / crew station. Link a Barrel to it (Selection tab) and set its firing arc.",
	BARREL: "The cannon of a turret. It turns on its base (pivot = base centre). Long along -Z points forward.",
	COMMANDER: "A cockpit / core. Every part must be connected to a commander or it is lost. With several commanders the ship can split in two.",
}


static func color_of(type: String) -> Color:
	return TYPE_INFO[type]["color"]
