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
## External sensor dish. It feeds the internal Detection module (see scripts/ship/detection.gd).
const RADAR := "radar"
## External antenna. With the internal Communications module it carries orders to far rooms instantly (see ShipComms).
const ANTENNA := "antenna"
## ENGINE ROOM: a room that controls every thruster. A ship that has one only fires its thrusters while one works.
const ENGINE_ROOM := "engine_room"
## Not a real module: faces the player has drawn but not yet put into a closed container (see ShipDesign / builder).
## A ship with loose faces cannot be saved.
const LOOSE := "loose"

## Types the builder offers (LOOSE is managed by the face tool).
const TYPES := [HULL, ARMOR, THRUSTER, TURRET, BARREL, COMMANDER, RADAR, ANTENNA, ENGINE_ROOM]

## Modules people can enter: each one is a ROOM on the ship plan. Hull (and armor) hold the corridors, barrels are solid.
## THRUSTERS and ANTENNAS are NOT rooms by default: they need no corridor and nobody walks there. They are controlled
## directly (orders reach a thruster at once, an antenna sends its fixed signal). A PRESET can turn any module into a room:
## its `kind` is "room" (e.g. the antenna preset "Relay room": needs a corridor, its signal strength is adjustable).
const ROOM_TYPES := [COMMANDER, TURRET, RADAR, ENGINE_ROOM]
## Modules that are drawn on the plan, but only as an outline outside the ship (no doorway, no corridor) unless their preset makes them rooms.
const EXTERNAL_TYPES := [THRUSTER, ANTENNA]
## Modules that carry corridors between the rooms (see ShipPlan).
const CORRIDOR_TYPES := [HULL, ARMOR]

## density kg/m^3, hp per m^3 of volume (min MIN_HP), colour
const TYPE_INFO := {
	HULL: {"density": 300.0, "hp_per_m3": 400.0, "color": Color(0.55, 0.58, 0.65)},
	ARMOR: {"density": 900.0, "hp_per_m3": 1500.0, "color": Color(0.35, 0.40, 0.50)},
	THRUSTER: {"density": 500.0, "hp_per_m3": 300.0, "color": Color(0.95, 0.55, 0.15)},
	TURRET: {"density": 450.0, "hp_per_m3": 300.0, "color": Color(0.85, 0.25, 0.25)},
	COMMANDER: {"density": 400.0, "hp_per_m3": 600.0, "color": Color(0.25, 0.75, 0.95)},
	BARREL: {"density": 600.0, "hp_per_m3": 400.0, "color": Color(0.7, 0.18, 0.18)},
	RADAR: {"density": 350.0, "hp_per_m3": 250.0, "color": Color(0.35, 0.9, 0.55)},
	ANTENNA: {"density": 250.0, "hp_per_m3": 200.0, "color": Color(0.9, 0.85, 0.3)},
	ENGINE_ROOM: {"density": 450.0, "hp_per_m3": 500.0, "color": Color(0.95, 0.4, 0.1)},
	LOOSE: {"density": 0.0, "hp_per_m3": 0.0, "color": Color(1.0, 0.05, 0.4)},
}

const MIN_HP := 20.0

## Smallest extent (metres, the thinnest side of the bounding box) a module of this type may have.
## People walk inside hulls, bridges and turret stations, so those need head room. Plates, engines, barrels and dishes are exempt.
const MIN_EXTENT := {HULL: 1.9, COMMANDER: 1.9, TURRET: 1.2, ENGINE_ROOM: 1.9}

## Types with a "preset" (see ModulePresets). Hull and armor have one too (just "standard").
static func needs_preset(type: String) -> bool:
	return ModulePresets.has_presets(type)


## Default starting shape + half-size (metres) the builder offers for each module type.
const DEFAULT_PRIMITIVE := {
	HULL: "box", ARMOR: "box", THRUSTER: "cylinder", TURRET: "dome", BARREL: "cylinder", COMMANDER: "box", RADAR: "dome", ANTENNA: "cylinder", ENGINE_ROOM: "box",
}
const DEFAULT_HALF_SIZE := {
	HULL: Vector3(1.5, 1.1, 2.0),
	ARMOR: Vector3(1.5, 0.15, 1.5),
	THRUSTER: Vector3(0.6, 0.7, 0.6),
	TURRET: Vector3(0.75, 0.65, 0.75),
	BARREL: Vector3(0.15, 0.15, 1.0),
	COMMANDER: Vector3(1.1, 1.0, 1.3),
	RADAR: Vector3(0.8, 0.6, 0.8),
	ANTENNA: Vector3(0.25, 0.9, 0.25),
	ENGINE_ROOM: Vector3(1.0, 1.0, 1.2),
}

## Round shapes are described by a base RADIUS, a HEIGHT (length) and the axis they point along (0 up, 1 forward, 2 side).
## Thrusters and barrels point along the ship (forward): their round face looks along the exhaust / the muzzle.
const DEFAULT_ROUND := {
	THRUSTER: {"radius": 0.6, "height": 1.4, "axis": 1},
	TURRET: {"radius": 0.75, "height": 0.65, "axis": 0},
	BARREL: {"radius": 0.15, "height": 2.0, "axis": 1},
	RADAR: {"radius": 0.8, "height": 0.6, "axis": 0},
	ANTENNA: {"radius": 0.25, "height": 1.8, "axis": 0},
	HULL: {"radius": 1.0, "height": 2.0, "axis": 1},
	ARMOR: {"radius": 1.0, "height": 0.3, "axis": 0},
	COMMANDER: {"radius": 1.1, "height": 2.0, "axis": 0},
	ENGINE_ROOM: {"radius": 1.0, "height": 2.0, "axis": 1},
}

## Short help text shown in the builder.
const TYPE_HELP := {
	HULL: "Rooms people can walk in (at least 1.9 m thick). Cheap, light, low HP.",
	ARMOR: "Heavy and tough plating. Soaks up damage.",
	THRUSTER: "Pushes the ship along its Direction. THE SHAPE decides everything: volume = thrust, nozzle size and length = the heat cone.",
	TURRET: "Turret BASE / crew station and swivel. Link one or more Barrels to it. Barrels only swivel if they TOUCH the base.",
	BARREL: "A weapon (cannon, railgun, beam). Damage grows with its volume. Link it to a turret base.",
	COMMANDER: "A bridge or cockpit. Seats = volume / volume-per-seat. Every part must connect to a commander or it is lost. Several commanders let the ship split.",
	RADAR: "External sensor. Electronic radar sees power use, thermal radar sees heat. Bigger dish = longer range.",
	ANTENNA: "Communications. Presets: whip / dish = external antenna (no corridor, fixed signal); relay room = a ROOM that needs a corridor but has an adjustable signal (turn it down to use less electricity and be harder to see on electronic radar). Signal While the signal is strong enough, orders reach every room instantly; without it somebody has to WALK the order along the corridors.",
	ENGINE_ROOM: "Controls ALL the thrusters. A ship with an engine room only fires its thrusters while one works (alive, and reachable by corridor unless you have communications). Without communications the pilot's orders are walked to the engine room first. Put it behind armor, connect it to the corridors.",
}


static func color_of(type: String) -> Color:
	return TYPE_INFO[type]["color"]
