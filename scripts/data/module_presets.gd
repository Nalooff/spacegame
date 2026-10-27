class_name ModulePresets
extends RefCounted
## MODULE PRESETS and per-m3 STATS (the "Nebulous Fleet Commander" part of the editor).
##
## You do not add a bare "thruster" any more: you add a thruster of a PRESET (chemical, ion, plasma ...), then reshape it
## with the vertex tools. The preset only gives numbers PER CUBIC METRE. What the module really does depends on its
## volume, so a bigger thruster pushes harder, a longer barrel hits harder, a bigger radar sees farther.
##
##   thrust (N)  = thrust_per_m3 * volume              electricity = elec_per_n * thrust,   heat = heat_per_n * thrust
##   shot damage = damage_per_m3 * volume              beam dps    = dps_per_m3   * volume
##   radar range = range_per_m * (volume ^ 1/3)        commander seats = floor(volume / seat_volume)
##
## Every stat has ONE main number (the one you edit). Changing it re-derives the others with the trade-offs below, so a
## thruster tuned to 900000 N/m3 also eats far more electricity per newton and makes far more heat.
## The resolved numbers are COPIED into the module (cfg.stats), so a saved ship never depends on the preset list.
## Your own presets live in user://presets.json (see save_custom()).

const CUSTOM_FILE := "user://presets.json"

## Stat definitions per type, in the order the editor lists them.
## main = the editable one.  fmt = number of decimals.
const DEFS := {
	ModuleCatalog.THRUSTER: [
		{"key": "thrust_per_m3", "label": "Thrust per m3", "unit": "N/m3", "min": 2000.0, "max": 900000.0, "main": true, "log": true},
		{"key": "elec_per_n", "label": "Electricity", "unit": "W per N", "derived": true},
		{"key": "heat_per_n", "label": "Heat", "unit": "W per N", "derived": true},
	],
	ModuleCatalog.TURRET: [
		{"key": "turn_speed", "label": "Turn speed", "unit": "deg/s", "min": 20.0, "max": 360.0, "main": true},
		{"key": "precision", "label": "Precision", "unit": "0..1", "derived": true},
		{"key": "servo_w", "label": "Servo power", "unit": "W", "derived": true},
	],
	ModuleCatalog.BARREL: [
		{"key": "damage_per_m3", "label": "Damage per shot per m3", "unit": "", "min": 20.0, "max": 3000.0, "main": true, "log": true, "kind": "projectile"},
		{"key": "dps_per_m3", "label": "Beam damage per second per m3", "unit": "", "min": 50.0, "max": 6000.0, "main": true, "log": true, "kind": "beam"},
		{"key": "cooldown", "label": "Time between shots", "unit": "s", "derived": true, "kind": "projectile"},
		{"key": "muzzle_speed", "label": "Muzzle speed", "unit": "m/s", "derived": true, "kind": "projectile"},
		{"key": "penetration", "label": "Penetration", "unit": "m", "derived": true, "kind": "beam"},
		{"key": "range", "label": "Range", "unit": "m", "derived": true, "kind": "beam"},
		{"key": "spread_deg", "label": "Spread", "unit": "deg", "derived": true},
		{"key": "elec_per_dmg", "label": "Electricity", "unit": "W per damage/s", "derived": true},
		{"key": "heat_per_dmg", "label": "Heat", "unit": "W per damage/s", "derived": true},
	],
	ModuleCatalog.COMMANDER: [
		{"key": "seat_volume", "label": "Volume per seat", "unit": "m3", "min": 2.0, "max": 40.0, "main": true},
		{"key": "elec_w_per_m3", "label": "Life support / computers", "unit": "W per m3", "derived": true},
	],
	ModuleCatalog.ANTENNA: [      # kind "external": fixed signal.  kind "room": adjustable (lower = cheaper, cooler, harder to see)
		{"key": "strength", "label": "Signal strength per metre of size", "unit": "", "min": 0.2, "max": 10.0, "main": true, "kind": "room"},
		{"key": "strength", "label": "Signal strength per metre of size (fixed)", "unit": "", "derived": true, "kind": "external"},
		{"key": "elec_w_per_m3", "label": "Electricity", "unit": "W per m3", "derived": true},
	],
	ModuleCatalog.RADAR: [
		{"key": "range_per_m", "label": "Range per metre of size", "unit": "m", "min": 300.0, "max": 6000.0, "main": true},
		{"key": "precision", "label": "Precision", "unit": "0..1", "derived": true},
		{"key": "elec_w_per_m3", "label": "Electricity", "unit": "W per m3", "derived": true},
	],
}

## Built-in presets: type -> id -> {label, kind (optional), stats, help}
const PRESETS := {
	ModuleCatalog.HULL: {"standard": {"label": "Standard hull", "stats": {}, "help": "Rooms people can walk in. Cheap, light, low HP."}},
	ModuleCatalog.ARMOR: {"standard": {"label": "Armor plate", "stats": {}, "help": "Heavy and tough. Soaks up damage."}},
	ModuleCatalog.THRUSTER: {
		"chemical": {"label": "Chemical engine", "stats": {"thrust_per_m3": 50000.0, "elec_per_n": 6.0, "heat_per_n": 10.0},
			"help": "Balanced. Cheap to run, hot exhaust."},
		"ion": {"label": "Ion drive", "stats": {"thrust_per_m3": 8000.0, "elec_per_n": 25.0, "heat_per_n": 1.5},
			"help": "Weak for its size, but almost no heat: hard to see on thermal radar."},
		"plasma": {"label": "Plasma torch", "stats": {"thrust_per_m3": 300000.0, "elec_per_n": 14.0, "heat_per_n": 30.0},
			"help": "Huge thrust for its size. Eats electricity and glows on thermal radar."},
	},
	ModuleCatalog.TURRET: {
		"light": {"label": "Light mount", "stats": {"turn_speed": 140.0, "precision": 0.55, "servo_w": 1100.0},
			"help": "Fast to swing, a little loose."},
		"heavy": {"label": "Heavy mount", "stats": {"turn_speed": 50.0, "precision": 0.9, "servo_w": 400.0},
			"help": "Slow and very precise."},
	},
	ModuleCatalog.BARREL: {
		"cannon": {"label": "Cannon", "kind": "projectile", "stats": {"damage_per_m3": 180.0, "cooldown": 0.25, "muzzle_speed": 260.0,
			"spread_deg": 1.0, "elec_per_dmg": 30.0, "heat_per_dmg": 20.0}, "help": "Shoots bullets. Good all-round damage."},
		"railgun": {"label": "Railgun", "kind": "projectile", "stats": {"damage_per_m3": 900.0, "cooldown": 1.2, "muzzle_speed": 700.0,
			"spread_deg": 0.2, "elec_per_dmg": 90.0, "heat_per_dmg": 30.0}, "help": "Slow rate of fire, very fast, precise shell."},
		"beam": {"label": "Beam laser", "kind": "beam", "stats": {"dps_per_m3": 420.0, "penetration": 9.0, "range": 450.0,
			"spread_deg": 0.05, "elec_per_dmg": 80.0, "heat_per_dmg": 40.0},
			"help": "A continuous ray: less damage than a cannon but it goes THROUGH several modules."},
	},
	ModuleCatalog.COMMANDER: {
		"bridge": {"label": "Bridge", "stats": {"seat_volume": 6.0, "elec_w_per_m3": 300.0}, "help": "Roomy: one seat per 6 m3."},
		"cockpit": {"label": "Cockpit", "stats": {"seat_volume": 3.5, "elec_w_per_m3": 450.0}, "help": "Cramped: one seat per 3.5 m3."},
		"war_room": {"label": "War room", "stats": {"seat_volume": 10.0, "elec_w_per_m3": 250.0}, "help": "Few seats, a lot of space."},
	},
	ModuleCatalog.ANTENNA: {
		"whip": {"label": "Whip antenna", "kind": "external", "stats": {"strength": 2.0, "elec_w_per_m3": 900.0}, "help": "Thin and cheap. Orders reach every room instantly while it works."},
		"dish": {"label": "Comms dish", "kind": "external", "stats": {"strength": 4.0, "elec_w_per_m3": 2200.0}, "help": "Stronger signal, more power."},
		"relay": {"label": "Relay room", "kind": "room", "stats": {"strength": 3.0, "elec_w_per_m3": 1800.0},
			"help": "A comms ROOM: it needs a corridor. Its signal is adjustable: turn it down to use less electricity and show less on electronic radar."},
		"long_range": {"label": "Long range transmitter", "kind": "room", "stats": {"strength": 6.0, "elec_w_per_m3": 4200.0},
			"help": "A room with a strong signal. Very visible on electronic radar."},
	},
	ModuleCatalog.RADAR: {
		"electronic": {"label": "Electronic radar", "kind": "electronic", "stats": {"range_per_m": 2200.0, "precision": 0.65, "elec_w_per_m3": 2500.0},
			"help": "Sees ships by how much electricity they use: a power-hungry ship is seen from farther away."},
		"thermal": {"label": "Thermal radar", "kind": "thermal", "stats": {"range_per_m": 1700.0, "precision": 0.55, "elec_w_per_m3": 1200.0},
			"help": "Sees heat: running thrusters and firing weapons light a ship up."},
	},
}


static func has_presets(type: String) -> bool:
	return PRESETS.has(type)


## Ids of the presets of a type: built-in first, then the player's own.
static func preset_ids(type: String) -> Array[String]:
	var out: Array[String] = []
	for id in PRESETS.get(type, {}):
		out.append(id)
	for id in _custom().get(type, {}):
		if not out.has(id):
			out.append(id)
	return out


static func preset(type: String, id: String) -> Dictionary:
	var custom: Dictionary = _custom().get(type, {})
	if custom.has(id):
		return custom[id]
	return PRESETS.get(type, {}).get(id, {})


static func default_preset(type: String) -> String:
	var ids := preset_ids(type)
	return ids[0] if not ids.is_empty() else ""


## Fresh cfg for a new module: {preset, kind?, stats}.
static func make_cfg(type: String, id: String) -> Dictionary:
	var p := preset(type, id)
	if p.is_empty():
		return {}
	var cfg := {"preset": id, "stats": (p["stats"] as Dictionary).duplicate()}
	if p.has("kind"):
		cfg["kind"] = p["kind"]
	return cfg


static func defs_of(type: String, kind: String = "") -> Array:
	var out: Array = []
	for d in DEFS.get(type, []):
		if d.has("kind") and kind != "" and d["kind"] != kind:
			continue
		out.append(d)
	return out


static func main_key(type: String, kind: String = "") -> String:
	for d in defs_of(type, kind):
		if d.get("main", false):
			return d["key"]
	return ""


## Change the MAIN stat and re-derive the rest. The trade-offs live here: tune them to rebalance the game.
static func set_main(type: String, kind: String, stats: Dictionary, value: float) -> void:
	var key := main_key(type, kind)
	if key == "":
		return
	var old: float = maxf(float(stats.get(key, value)), 1e-6)
	var dmin := 0.0
	var dmax := 1e12
	for d in defs_of(type, kind):
		if d["key"] == key:
			dmin = float(d.get("min", 0.0))
			dmax = float(d.get("max", 1e12))
	value = clampf(value, dmin, dmax)
	var r := value / old
	stats[key] = value
	match type:
		ModuleCatalog.THRUSTER:
			stats["elec_per_n"] = float(stats["elec_per_n"]) * pow(r, 0.30)       # dense thrust costs more power per newton
			stats["heat_per_n"] = float(stats["heat_per_n"]) * pow(r, 0.55)       # ... and much more heat
		ModuleCatalog.TURRET:
			stats["precision"] = clampf(float(stats["precision"]) * pow(r, -0.35), 0.2, 0.97)   # fast = loose
			stats["servo_w"] = float(stats["servo_w"]) * pow(r, 0.8)
		ModuleCatalog.BARREL:
			if kind == "beam":
				stats["penetration"] = float(stats["penetration"]) * pow(r, -0.25)  # more damage = less penetration
				stats["elec_per_dmg"] = float(stats["elec_per_dmg"]) * pow(r, 0.2)
				stats["heat_per_dmg"] = float(stats["heat_per_dmg"]) * pow(r, 0.4)
				stats["spread_deg"] = float(stats["spread_deg"]) * pow(r, 0.2)
			else:
				stats["cooldown"] = float(stats["cooldown"]) * pow(r, 0.35)
				stats["elec_per_dmg"] = float(stats["elec_per_dmg"]) * pow(r, 0.2)
				stats["heat_per_dmg"] = float(stats["heat_per_dmg"]) * pow(r, 0.4)
				stats["spread_deg"] = float(stats["spread_deg"]) * pow(r, 0.2)
		ModuleCatalog.COMMANDER:
			stats["elec_w_per_m3"] = float(stats["elec_w_per_m3"]) * pow(r, -0.4)   # roomier = cheaper per m3
		ModuleCatalog.ANTENNA:
			stats["elec_w_per_m3"] = float(stats["elec_w_per_m3"]) * pow(r, 1.2)     # a weaker signal costs (and shows) less
		ModuleCatalog.RADAR:
			stats["precision"] = clampf(float(stats["precision"]) * pow(r, -0.35), 0.1, 0.97)  # farther = blurrier
			stats["elec_w_per_m3"] = float(stats["elec_w_per_m3"]) * pow(r, 1.4)


# ---- the player's own presets -------------------------------------------------------------------------------------
static func _custom() -> Dictionary:
	if not FileAccess.file_exists(CUSTOM_FILE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CUSTOM_FILE))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Save the stats of a module as a named preset of its type (kept in user://presets.json).
static func save_custom(type: String, id: String, label: String, cfg: Dictionary) -> void:
	var all := _custom()
	if not all.has(type):
		all[type] = {}
	var entry := {"label": label, "stats": (cfg["stats"] as Dictionary).duplicate(),
		"help": "Your own preset."}
	if cfg.has("kind"):
		entry["kind"] = cfg["kind"]
	all[type][id] = entry
	var f := FileAccess.open(CUSTOM_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all, "\t"))
