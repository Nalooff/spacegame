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

const TYPES := [HULL, ARMOR, THRUSTER, TURRET, COMMANDER]

## density kg/m^3, hp per m^3 of volume (min MIN_HP), colour
const TYPE_INFO := {
	HULL: {"density": 300.0, "hp_per_m3": 400.0, "color": Color(0.55, 0.58, 0.65)},
	ARMOR: {"density": 900.0, "hp_per_m3": 1500.0, "color": Color(0.35, 0.40, 0.50)},
	THRUSTER: {"density": 500.0, "hp_per_m3": 300.0, "color": Color(0.95, 0.55, 0.15)},
	TURRET: {"density": 450.0, "hp_per_m3": 300.0, "color": Color(0.85, 0.25, 0.25)},
	COMMANDER: {"density": 400.0, "hp_per_m3": 600.0, "color": Color(0.25, 0.75, 0.95)},
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
	HULL: "box", ARMOR: "box", THRUSTER: "cylinder", TURRET: "dome", COMMANDER: "box",
}
const DEFAULT_HALF_SIZE := {
	HULL: Vector3(0.6, 0.4, 0.8),
	ARMOR: Vector3(0.6, 0.12, 0.6),
	THRUSTER: Vector3(0.2, 0.25, 0.2),
	TURRET: Vector3(0.3, 0.3, 0.3),
	COMMANDER: Vector3(0.4, 0.3, 0.5),
}

## Short help text shown in the builder.
const TYPE_HELP := {
	HULL: "Light structure. Cheap, low HP.",
	ARMOR: "Heavy and tough. Soaks up damage.",
	THRUSTER: "Pushes the ship along its Direction setting. Position + direction decide how it turns the ship.",
	TURRET: "Fires at the mouse cursor. Round shapes (dome, cylinder) look best.",
	COMMANDER: "The cockpit. Every ship needs exactly one; if it is destroyed the ship is lost.",
}


static func color_of(type: String) -> Color:
	return TYPE_INFO[type]["color"]
