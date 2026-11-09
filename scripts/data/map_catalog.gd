class_name MapCatalog
extends RefCounted
## The maps (battlefields). Each is plain data that WorldBuilder turns into a sky, suns (= the game's lights), planets,
## asteroid fields and drifting dust. Add a map = add a dictionary here (append only: the id is what is synced / saved).
##   id, name, help
##   spawn_radius   metres from the middle where the ships start (more room for bigger ships)
##   suns           [{dir, color (HDR, drawn in the sky), light (colour of the light it casts), energy, size (rad)}]  1 to 3
##   planets        [{dir, size (rad), kind 0 gas / 1 rock / 2 lava / 3 ice, a, b, c, atm, ring (bool), ring_n, ring_col, spin, seed}]
##   sky            bg_low, bg_high, neb_a/b/c, neb (amount), neb_scale, neb_drift, stars (amount), star_bright, galaxy, galaxy_n
##   rocks          {count, min, max (metres), spread (metres), mode "cloud" | "belt" | "shell", flat, tint_a, tint_b, glow, hero}
##   dust           {amount, color}
##   ambient        energy of the light the sky gives to ships

const CLASSIC := "classic"

const MAPS := [
	{"id": "classic", "name": "Rock Garden (classic)", "help": "The original small arena: a few rocks, close start.", "spawn_radius": 30.0},
	{
		"id": "dual_suns", "name": "Twin Suns", "help": "A binary system: a big warm sun and a small blue-white one light the fight from two sides.",
		"spawn_radius": 1400.0, "ambient": 0.55,
		"suns": [
			{"dir": Vector3(0.6, 0.35, -0.7), "color": Color(3.2, 2.5, 1.5), "light": Color(1.0, 0.88, 0.7), "energy": 1.5, "size": 0.035},
			{"dir": Vector3(-0.75, 0.12, 0.5), "color": Color(1.8, 2.5, 3.8), "light": Color(0.65, 0.82, 1.0), "energy": 0.9, "size": 0.018},
		],
		"planets": [],
		"sky": {"bg_low": Color(0.004, 0.006, 0.016), "bg_high": Color(0.012, 0.014, 0.034), "neb_a": Color(0.18, 0.08, 0.35), "neb_b": Color(0.08, 0.2, 0.45), "neb_c": Color(0.5, 0.15, 0.3),
			"neb": 0.25, "neb_scale": 1.2, "neb_drift": 0.004, "stars": 1.0, "star_bright": 1.0, "galaxy": 0.25, "galaxy_n": Vector3(0.2, 1.0, 0.3)},
		"rocks": {"count": 160, "min": 6.0, "max": 70.0, "spread": 4500.0, "mode": "cloud", "flat": 0.6, "tint_a": Color(0.4, 0.37, 0.33), "tint_b": Color(0.17, 0.16, 0.16), "glow": 0.0, "hero": 4},
		"dust": {"amount": 350, "color": Color(1.0, 0.95, 0.85)},
	},
	{
		"id": "crimson_nebula", "name": "Crimson Nebula", "help": "Inside a huge glowing nebula lit by a dying red giant. Dark, moody, dense with debris.",
		"spawn_radius": 1800.0, "ambient": 0.7,
		"suns": [
			{"dir": Vector3(-0.35, 0.22, -0.9), "color": Color(3.6, 1.0, 0.6), "light": Color(1.0, 0.45, 0.3), "energy": 1.3, "size": 0.055},
		],
		"planets": [],
		"sky": {"bg_low": Color(0.012, 0.003, 0.006), "bg_high": Color(0.03, 0.008, 0.02), "neb_a": Color(0.55, 0.08, 0.12), "neb_b": Color(0.7, 0.28, 0.1), "neb_c": Color(0.3, 0.06, 0.4),
			"neb": 0.55, "neb_scale": 1.0, "neb_drift": 0.006, "stars": 0.5, "star_bright": 0.8, "galaxy": 0.0, "galaxy_n": Vector3(0, 1, 0)},
		"rocks": {"count": 260, "min": 5.0, "max": 90.0, "spread": 4000.0, "mode": "cloud", "flat": 0.7, "tint_a": Color(0.32, 0.2, 0.18), "tint_b": Color(0.12, 0.07, 0.07), "glow": 0.0, "hero": 6},
		"dust": {"amount": 500, "color": Color(1.0, 0.55, 0.4)},
	},
	{
		"id": "gas_giant", "name": "Gas Giant Orbit", "help": "A banded giant with rings fills the sky; a thick asteroid belt circles around the battlefield.",
		"spawn_radius": 1700.0, "ambient": 0.6,
		"suns": [
			{"dir": Vector3(0.85, 0.4, 0.3), "color": Color(3.0, 2.8, 2.3), "light": Color(1.0, 0.95, 0.85), "energy": 1.5, "size": 0.022},
		],
		"planets": [
			{"dir": Vector3(-0.2, -0.28, -0.9), "size": 0.42, "kind": 0, "a": Color(0.78, 0.55, 0.32), "b": Color(0.93, 0.82, 0.62), "c": Color(0.6, 0.25, 0.15), "atm": Color(1.0, 0.8, 0.55),
				"ring": true, "ring_n": Vector3(0.18, 1.0, 0.3), "ring_col": Color(0.85, 0.78, 0.65), "spin": 0.01, "seed": 1.0},
			{"dir": Vector3(0.45, 0.2, -0.85), "size": 0.04, "kind": 1, "a": Color(0.35, 0.3, 0.28), "b": Color(0.55, 0.5, 0.45), "c": Color(0.9, 0.9, 0.95), "atm": Color(0.5, 0.5, 0.55),
				"ring": false, "ring_n": Vector3(0, 1, 0), "ring_col": Color(1, 1, 1), "spin": 0.02, "seed": 4.0},
		],
		"sky": {"bg_low": Color(0.004, 0.005, 0.012), "bg_high": Color(0.01, 0.012, 0.026), "neb_a": Color(0.1, 0.1, 0.25), "neb_b": Color(0.1, 0.18, 0.3), "neb_c": Color(0.3, 0.15, 0.2),
			"neb": 0.1, "neb_scale": 1.4, "neb_drift": 0.003, "stars": 1.0, "star_bright": 1.0, "galaxy": 0.15, "galaxy_n": Vector3(0.5, 1.0, 0.1)},
		"rocks": {"count": 520, "min": 4.0, "max": 60.0, "spread": 3600.0, "mode": "belt", "flat": 0.12, "tint_a": Color(0.45, 0.38, 0.3), "tint_b": Color(0.2, 0.17, 0.15), "glow": 0.0, "hero": 5},
		"dust": {"amount": 300, "color": Color(1.0, 0.9, 0.75)},
	},
	{
		"id": "star_cluster", "name": "Young Star Cluster", "help": "Three stars (white, blue and orange) in a bright blue nebula. Light comes from everywhere; a very large arena.",
		"spawn_radius": 2400.0, "ambient": 0.65,
		"suns": [
			{"dir": Vector3(0.5, 0.5, -0.7), "color": Color(2.8, 2.8, 2.8), "light": Color(1.0, 1.0, 1.0), "energy": 1.2, "size": 0.025},
			{"dir": Vector3(-0.8, 0.2, -0.3), "color": Color(1.4, 2.2, 4.0), "light": Color(0.55, 0.75, 1.0), "energy": 1.0, "size": 0.03},
			{"dir": Vector3(0.2, -0.45, 0.85), "color": Color(3.2, 1.6, 0.6), "light": Color(1.0, 0.65, 0.35), "energy": 0.8, "size": 0.02},
		],
		"planets": [],
		"sky": {"bg_low": Color(0.003, 0.008, 0.02), "bg_high": Color(0.01, 0.025, 0.05), "neb_a": Color(0.05, 0.25, 0.5), "neb_b": Color(0.05, 0.45, 0.5), "neb_c": Color(0.2, 0.15, 0.5),
			"neb": 0.5, "neb_scale": 1.1, "neb_drift": 0.005, "stars": 1.6, "star_bright": 1.3, "galaxy": 0.35, "galaxy_n": Vector3(-0.3, 1.0, 0.4)},
		"rocks": {"count": 120, "min": 5.0, "max": 40.0, "spread": 6000.0, "mode": "shell", "flat": 1.0, "tint_a": Color(0.35, 0.4, 0.5), "tint_b": Color(0.15, 0.17, 0.22), "glow": 0.0, "hero": 3},
		"dust": {"amount": 450, "color": Color(0.8, 0.9, 1.0)},
	},
	{
		"id": "graveyard", "name": "Asteroid Graveyard", "help": "A dense field of giant rocks around a dim red dwarf, with a molten world in the sky. Plenty of cover.",
		"spawn_radius": 1100.0, "ambient": 0.5,
		"suns": [
			{"dir": Vector3(-0.5, 0.3, 0.8), "color": Color(2.6, 0.8, 0.45), "light": Color(1.0, 0.5, 0.3), "energy": 1.1, "size": 0.03},
		],
		"planets": [
			{"dir": Vector3(0.7, 0.1, -0.7), "size": 0.2, "kind": 2, "a": Color(0.05, 0.04, 0.04), "b": Color(0.14, 0.08, 0.06), "c": Color(1.0, 0.35, 0.08), "atm": Color(1.0, 0.3, 0.1),
				"ring": false, "ring_n": Vector3(0, 1, 0), "ring_col": Color(1, 1, 1), "spin": 0.015, "seed": 7.0},
		],
		"sky": {"bg_low": Color(0.008, 0.004, 0.006), "bg_high": Color(0.02, 0.01, 0.015), "neb_a": Color(0.3, 0.1, 0.08), "neb_b": Color(0.25, 0.12, 0.15), "neb_c": Color(0.15, 0.1, 0.2),
			"neb": 0.3, "neb_scale": 1.3, "neb_drift": 0.003, "stars": 0.9, "star_bright": 0.9, "galaxy": 0.1, "galaxy_n": Vector3(0.1, 1.0, -0.2)},
		"rocks": {"count": 650, "min": 8.0, "max": 160.0, "spread": 3200.0, "mode": "cloud", "flat": 0.8, "tint_a": Color(0.36, 0.28, 0.24), "tint_b": Color(0.1, 0.08, 0.08), "glow": 0.22, "hero": 12},
		"dust": {"amount": 450, "color": Color(1.0, 0.7, 0.5)},
	},
	{
		"id": "deep_void", "name": "Deep Void", "help": "Empty space between galaxies: a far sun, a brilliant galaxy band and nothing to hide behind. A huge arena for long-range duels.",
		"spawn_radius": 2500.0, "ambient": 0.45,
		"suns": [
			{"dir": Vector3(-0.3, 0.55, -0.78), "color": Color(2.6, 2.7, 3.0), "light": Color(0.9, 0.95, 1.0), "energy": 1.25, "size": 0.012},
		],
		"planets": [],
		"sky": {"bg_low": Color(0.001, 0.001, 0.004), "bg_high": Color(0.004, 0.004, 0.012), "neb_a": Color(0.1, 0.06, 0.2), "neb_b": Color(0.05, 0.1, 0.2), "neb_c": Color(0.15, 0.05, 0.15),
			"neb": 0.12, "neb_scale": 0.9, "neb_drift": 0.002, "stars": 1.5, "star_bright": 1.4, "galaxy": 0.9, "galaxy_n": Vector3(0.3, 1.0, 0.5)},
		"rocks": {"count": 0, "min": 5.0, "max": 20.0, "spread": 1000.0, "mode": "cloud", "flat": 1.0, "tint_a": Color(0.3, 0.3, 0.3), "tint_b": Color(0.1, 0.1, 0.1), "glow": 0.0, "hero": 0},
		"dust": {"amount": 200, "color": Color(0.85, 0.9, 1.0)},
	},
	{
		"id": "frozen_rim", "name": "Frozen Rim", "help": "An ice world with glittering rings and a pale sun; the field is full of ice shards.",
		"spawn_radius": 1600.0, "ambient": 0.6,
		"suns": [
			{"dir": Vector3(0.7, 0.5, 0.5), "color": Color(2.4, 2.8, 3.4), "light": Color(0.85, 0.92, 1.0), "energy": 1.4, "size": 0.02},
		],
		"planets": [
			{"dir": Vector3(0.1, -0.35, -0.9), "size": 0.3, "kind": 3, "a": Color(0.55, 0.75, 0.9), "b": Color(0.85, 0.93, 1.0), "c": Color(0.95, 0.98, 1.0), "atm": Color(0.5, 0.8, 1.0),
				"ring": true, "ring_n": Vector3(-0.2, 1.0, 0.45), "ring_col": Color(0.8, 0.9, 1.0), "spin": 0.012, "seed": 9.0},
		],
		"sky": {"bg_low": Color(0.003, 0.007, 0.014), "bg_high": Color(0.01, 0.02, 0.035), "neb_a": Color(0.05, 0.3, 0.4), "neb_b": Color(0.1, 0.4, 0.35), "neb_c": Color(0.2, 0.25, 0.5),
			"neb": 0.35, "neb_scale": 1.5, "neb_drift": 0.004, "stars": 1.1, "star_bright": 1.1, "galaxy": 0.2, "galaxy_n": Vector3(-0.2, 1.0, 0.1)},
		"rocks": {"count": 380, "min": 4.0, "max": 70.0, "spread": 3800.0, "mode": "cloud", "flat": 0.5, "tint_a": Color(0.7, 0.8, 0.9), "tint_b": Color(0.3, 0.4, 0.5), "glow": 0.0, "hero": 6},
		"dust": {"amount": 450, "color": Color(0.85, 0.95, 1.0)},
	},
]


static func count() -> int:
	return MAPS.size()


static func ids() -> Array:
	var out: Array = []
	for m in MAPS:
		out.append(m["id"])
	return out


## The map dictionary for `id` (the classic one when unknown: an id from the network is never trusted).
static func get_map(id: String) -> Dictionary:
	for m in MAPS:
		if m["id"] == id:
			return m
	return MAPS[0]


static func is_valid(id: String) -> bool:
	for m in MAPS:
		if m["id"] == id:
			return true
	return false
