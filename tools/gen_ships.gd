extends Node
## Generates the extra premade ships (original designs): Quadwing, Orb Interceptor, Hammerhead, Nautilus, Spearhead.
##   WHICH=Hammerhead SAVE=1 godot --headless --path . res://tools/gen_ships.tscn      (WHICH unset = all; SAVE unset = dry run)
## Bow = -Z, stern = +Z, up = +Y. Parts overlap their neighbours so every ship is one connected structure.
var d := ShipDesign.new()
const H := ModuleCatalog.HULL
const A := ModuleCatalog.ARMOR
const RIGHT := Vector3.RIGHT


func box(type: String, c: Vector3, h: Vector3, preset: String = "", basis: Basis = Basis.IDENTITY) -> int:
	return d.add_module(type, "box", c, h, 12, preset, basis)


func cyl(type: String, c: Vector3, r: float, half_len: float, axis: Vector3, preset: String = "", seg: int = 12) -> int:
	var b := Basis.IDENTITY
	if absf(axis.z) > 0.5:
		b = Basis(Vector3.RIGHT, PI * 0.5)
	elif absf(axis.x) > 0.5:
		b = Basis(Vector3.BACK, PI * 0.5)
	return d.add_module(type, "cylinder", c, Vector3(r, half_len, r), seg, preset, b)


## A pyramid whose apex points along -Z (bow) with half-length `hl` along Z.
func nose(type: String, c: Vector3, hw: float, hl: float, hh: float, preset: String = "") -> int:
	return d.add_module(type, "pyramid", c, Vector3(hw, hl, hh), 12, preset, Basis(Vector3.RIGHT, -PI * 0.5))


func thruster(c: Vector3, r: float, half_len: float, push: Vector3, preset: String = "chemical") -> int:
	var mi := cyl(ModuleCatalog.THRUSTER, c, r, half_len, push, preset)
	d.modules[mi]["dir"] = push.normalized()
	return mi


func turret(c: Vector3, r: float, preset_barrel: String, n: int, barrel_r: float, barrel_len: float, fwd: float = -1.0, mount: String = "heavy") -> int:
	_tp.append([c, r])
	var tb := d.add_module(ModuleCatalog.TURRET, "dome", c, Vector3(r, maxf(r * 0.8, 1.25), r), 10, mount)
	d.modules[tb]["dir"] = Vector3.UP
	var ids: Array = []
	for i in n:
		var off := (float(i) - (n - 1) * 0.5) * (barrel_r * 2.0 + r * 0.5) if n > 1 else 0.0
		var bc := c + Vector3(off, r * 0.25, fwd * barrel_len * 0.3)
		ids.append(cyl(ModuleCatalog.BARREL, bc, barrel_r, barrel_len * 0.5, Vector3(0, 0, 1), preset_barrel, 8))
	d.modules[tb]["cfg"]["barrels"] = ids
	return tb


## A thruster pod stuck on a surface: `face` = the surface point, `out` = the way the surface faces. The pod pushes the ship the other way.
func pod(face: Vector3, out: Vector3, r: float, hl: float, preset: String = "chemical") -> int:
	var ov := minf(2.0, hl * 0.5)
	return thruster(face + out.normalized() * (hl - ov), r, hl, -out.normalized(), preset)


func commander(c: Vector3, h: Vector3, preset: String = "cockpit") -> int:
	return box(ModuleCatalog.COMMANDER, c, h, preset)


func radar(c: Vector3, r: float) -> void:
	d.add_module(ModuleCatalog.RADAR, "dome", c, Vector3(r, r * 0.9, r), 10, "electronic")


func antenna(c: Vector3, r: float, hl: float, preset: String = "whip") -> void:
	d.add_module(ModuleCatalog.ANTENNA, "cylinder", c, Vector3(r, hl, r), 8, preset)


# ---------------------------------------------------------------------------------------------------- Quadwing (fighter, ~17 m)
func quadwing() -> void:
	d.ship_name = "Quadwing"
	box(H, Vector3(0, 0, 0.5), Vector3(1.0, 1.0, 5.0))
	nose(H, Vector3(0, 0, -7.4), 1.0, 3.0, 0.95)
	commander(Vector3(0, 1.3, -1.8), Vector3(0.95, 0.95, 1.5), "bridge")
	box(ModuleCatalog.ENGINE_ROOM, Vector3(0, 0, 2.8), Vector3(0.95, 0.95, 1.0), "control")
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			# four wings that spread in an X; every wing root overlaps the fuselage
			var wb := Basis(Vector3.BACK, sx * sy * 0.3)
			box(A, Vector3(sx * 4.0, sy * 1.3, 2.0), Vector3(3.2, 0.1, 1.7), "", wb)
			thruster(Vector3(sx * 0.9, sy * 0.9, 6.0), 0.5, 0.8, Vector3(0, 0, -1))
			turret(Vector3(sx * 6.9, sy * 2.1, 2.0), 0.9, "autocannon", 1, 0.08, 2.4, -1.0, "light")
			pod(Vector3(sx * 4.0, sy * 1.3, 0.3), Vector3(0, 0, -1), 0.25, 0.5)             # retro pods on the wing edges
	for sx in [-1.0, 1.0]:
		pod(Vector3(sx * 1.0, 0, -3.2), Vector3(sx, 0, 0), 0.25, 0.5)
		pod(Vector3(0, sx * 1.0, -4.2), Vector3(0, sx, 0), 0.25, 0.5)
	radar(Vector3(0, 0.9, 0.8), 0.45)
	antenna(Vector3(0, 1.2, 3.6), 0.05, 1.0)


# ---------------------------------------------------------------------------------------------------- Orb Interceptor (~11 m)
func orb() -> void:
	d.ship_name = "Orb Interceptor"
	d.add_module(H, "sphere", Vector3.ZERO, Vector3(2.1, 2.1, 2.1), 14, "")
	d.add_module(A, "cylinder", Vector3(0, 0, 0), Vector3(4.6, 0.18, 4.6), 20, "")               # a flat armour ring round the middle
	for sz in [-1.0, 1.0]:
		box(A, Vector3(0, 0, sz * 4.2), Vector3(0.25, 1.9, 0.9))                                  # fins fore and aft (they cross the ring)
	commander(Vector3(0, 0.0, -0.9), Vector3(0.95, 0.95, 0.95), "bridge")
	box(ModuleCatalog.ENGINE_ROOM, Vector3(0, 0, 1.0), Vector3(0.95, 0.95, 0.95), "control")
	for sx in [-1.0, 1.0]:
		thruster(Vector3(sx * 0.0 + sx * 0.0, sx * 1.0, 4.4), 0.5, 0.7, Vector3(0, 0, -1))
		turret(Vector3(sx * 2.0, 0.1, -3.4), 0.8, "autocannon", 1, 0.09, 2.2, -1.0, "light")
		pod(Vector3(sx * 4.6, 0, 0), Vector3(sx, 0, 0), 0.22, 0.5)
		pod(Vector3(0, sx * 1.4, 1.5), Vector3(0, sx, 0), 0.22, 0.5)
	pod(Vector3(0, 0, -5.1), Vector3(0, 0, -1), 0.3, 0.6)                 # the brake, on the front fin
	radar(Vector3(0, 1.8, -0.4), 0.45)
	antenna(Vector3(0, 2.0, 1.0), 0.05, 0.9)


# ---------------------------------------------------------------------------------------------------- Hammerhead (~950 m)
func hammerhead() -> void:
	d.ship_name = "Hammerhead"
	box(H, Vector3(0, 0, 80), Vector3(70, 48, 360))                     # body
	box(H, Vector3(0, 0, -300), Vector3(95, 52, 120))                   # neck
	box(H, Vector3(0, 0, -440), Vector3(330, 44, 62))                   # the hammer: a wide cross-beam with its own guns
	box(A, Vector3(0, 0, -508), Vector3(335, 36, 8), "composite")       # armoured front plate
	for sx in [-1.0, 1.0]:
		box(H, Vector3(sx * 380.0, 0, -440), Vector3(60, 36, 52))       # blunt tips
		box(A, Vector3(sx * 70.0, 0, 60), Vector3(8, 44, 330))          # flank armour
		box(H, Vector3(sx * 125.0, -30, 330), Vector3(50, 36, 140))     # engine nacelles
		for dx in [-28.0, 28.0]:
			thruster(Vector3(sx * 125.0 + dx, -30, 500), 24.0, 55.0, Vector3(0, 0, -1), "ion")
	box(H, Vector3(0, 0, 500), Vector3(90, 60, 140))                    # stern block
	box(H, Vector3(0, 68, 120), Vector3(55, 30, 120))                   # command tower
	box(H, Vector3(0, 110, 130), Vector3(36, 22, 70))
	commander(Vector3(0, 148, 135), Vector3(30, 18, 30), "bridge")
	commander(Vector3(0, 0, 40), Vector3(26, 22, 34))                   # armoured backup bridge
	commander(Vector3(0, 10, 540), Vector3(22, 18, 24))                 # aft engineering bridge
	box(ModuleCatalog.ENGINE_ROOM, Vector3(0, 0, 480), Vector3(36, 36, 36), "control")
	radar(Vector3(0, 160, 135), 14.0)
	radar(Vector3(0, 40, -480), 9.0)
	antenna(Vector3(0, 196, 150), 1.4, 40.0)
	for sx in [-1.0, 1.0]:
		box(ModuleCatalog.AIRLOCK, Vector3(sx * 79.0, 0, 20), Vector3(6, 14, 14), "standard")
		box(ModuleCatalog.AIRLOCK, Vector3(sx * 79.0, 0, 140), Vector3(6, 14, 14), "standard")
		box(ModuleCatalog.POD_BAY, Vector3(sx * 80.0, 0, 250), Vector3(7, 8, 14), "standard")
	# manoeuvring thrusters: flanks of the hammer tips, neck, body and stern; tops and bottoms
	for sx in [-1.0, 1.0]:
		pod(Vector3(sx * 440.0, 0, -440), Vector3(sx, 0, 0), 12.0, 16.0)
		pod(Vector3(sx * 95.0, 0, -230), Vector3(sx, 0, 0), 12.0, 16.0)
		pod(Vector3(sx * 78.0, 0, 150), Vector3(sx, 0, 0), 12.0, 16.0)
		pod(Vector3(sx * 90.0, 0, 540), Vector3(sx, 0, 0), 12.0, 16.0)
		for sy in [-1.0, 1.0]:
			pod(Vector3(sx * 200.0, sy * 44.0, -440), Vector3(0, sy, 0), 11.0, 15.0)
			pod(Vector3(sx * 60.0, sy * 60.0, 400), Vector3(0, sy, 0), 11.0, 15.0)
	for bx in [-250.0, -100.0, 100.0, 250.0]:
		pod(Vector3(bx, 0, -516), Vector3(0, 0, -1), 22.0, 34.0, "ion")      # the brakes
	for i in 5:                                                           # heavy twins along the hammer
		turret(Vector3((float(i) - 2.0) * 120.0, 40, -450), 20.0, "cannon", 2, 2.0, 90.0)
	for sx in [-1.0, 1.0]:
		for z in [-20.0, 150.0, 300.0]:
			turret(Vector3(sx * 62.0, 44, z), 9.0, "autocannon", 2, 0.8, 30.0, -1.0, "light")
		for x in [200.0, 300.0]:
			turret(Vector3(sx * x, 42, -440), 5.0, "flak", 1, 0.5, 14.0, -1.0, "light")
	turret(Vector3(0, 56, 540), 20.0, "cannon", 2, 2.0, 90.0, 1.0)


# ---------------------------------------------------------------------------------------------------- Nautilus (~900 m)
func nautilus() -> void:
	d.ship_name = "Nautilus"
	# the shell: rings of shrinking radius that climb and curl as they go aft   [z, radius, y]
	var rings := [[-330.0, 150.0, 0.0], [-210.0, 138.0, 4.0], [-90.0, 124.0, 12.0], [30.0, 108.0, 26.0], [140.0, 90.0, 44.0], [240.0, 72.0, 66.0], [330.0, 54.0, 92.0], [410.0, 38.0, 122.0]]
	for r in rings:
		cyl(H, Vector3(0, r[2], r[0]), r[1], 70.0, Vector3(0, 0, 1), "", 20)
	cyl(H, Vector3(0, 0, -400), 175.0, 14.0, Vector3(0, 0, 1), "", 20)                 # the lip of the aperture (a room: the turrets stand on it)
	cyl(H, Vector3(0, -105, 20), 28.0, 330.0, Vector3(0, 0, 1))                        # keel / siphon
	for i in 10:                                                                       # the "tentacles": gun turrets on short arms round the aperture
		var a := TAU * i / 10.0
		var p := Vector3(cos(a) * 176.0, sin(a) * 176.0, -392.0)
		cyl(A, p + Vector3(0, 0, 18), 6.0, 24.0, Vector3(0, 0, 1))
		if i % 2 == 0:
			turret(p + Vector3(0, 0, -6), 12.0, "cannon", 2, 1.5, 70.0, -1.0, "heavy")
		else:
			turret(p + Vector3(0, 0, -6), 8.0, "autocannon", 2, 0.7, 28.0, -1.0, "light")
	commander(Vector3(0, 10, -150), Vector3(30, 24, 36), "bridge")
	commander(Vector3(0, 40, 140), Vector3(22, 20, 28))
	commander(Vector3(0, 100, 380), Vector3(14, 14, 20))
	box(ModuleCatalog.ENGINE_ROOM, Vector3(0, 70, 300), Vector3(26, 26, 40), "control")
	radar(Vector3(0, 138, -210), 12.0)
	radar(Vector3(0, 142, 330), 8.0)
	antenna(Vector3(0, 170, 30), 1.2, 50.0)
	for sx in [-1.0, 1.0]:
		box(ModuleCatalog.AIRLOCK, Vector3(sx * 122.0, 12, -80), Vector3(6, 14, 14), "standard")
		box(ModuleCatalog.AIRLOCK, Vector3(sx * 100.0, 26, 40), Vector3(6, 14, 14), "standard")
		box(ModuleCatalog.POD_BAY, Vector3(sx * 108.0, 20, 0), Vector3(7, 8, 14), "standard")
	box(H, Vector3(0, 122, 470), Vector3(66, 66, 22))                                  # stern plate carrying the engine cluster
	for a2 in [[0.0, 0.0], [44.0, 0.0], [-44.0, 0.0], [0.0, 44.0], [0.0, -44.0]]:
		thruster(Vector3(a2[0], 122.0 + a2[1], 512.0), 20.0, 55.0, Vector3(0, 0, -1), "ion")
	for z in [-300.0, -60.0, 180.0]:                                                   # RCS pods round the shell
		var ring: Array = rings[0]
		for r in rings:
			if absf(float(r[0]) - z) < absf(float(ring[0]) - z):
				ring = r
		var rad: float = ring[1]
		var cy: float = ring[2]
		for sx in [-1.0, 1.0]:
			pod(Vector3(sx * rad, cy, z), Vector3(sx, 0, 0), 12.0, 18.0)
			pod(Vector3(sx * 60.0, cy - sqrt(rad * rad - 3600.0), z), Vector3(0, -1, 0), 12.0, 18.0)
		pod(Vector3(0, cy + rad, z), Vector3(0, 1, 0), 12.0, 18.0)
	for bx in [-60.0, 60.0]:
		pod(Vector3(bx, 0, -414), Vector3(0, 0, -1), 28.0, 34.0, "ion")              # the brakes, on the lip
	pod(Vector3(0, -105, -310), Vector3(0, 0, -1), 18.0, 20.0, "ion")
	for r in [rings[1], rings[2], rings[3], rings[4]]:                                 # point defence on the shell's back
		turret(Vector3(0, float(r[2]) + float(r[1]) - 3.0, float(r[0])), 5.0, "flak", 1, 0.5, 14.0, -1.0, "light")


# ---------------------------------------------------------------------------------------------------- Spearhead (~1.8 km)
## An original capital ship mixing two looks. SIDE VIEW: a flat top and a huge keel that sweeps down in a concave curve to a vertical
## prow with a spike at its bottom (a star-destroyer's sail). PLAN VIEW: an arrowhead spreading to a wide stern, where two tall tapering
## bridge towers rise, fused together at their base (a battle-cruiser's back). The hull is cut into thin slices so it reads as smooth.
const Z0 := -740.0             ## z of the first slice (the prow)
const P := 31.0                ## pitch of the slices (each is 40 m long, so they overlap by 4 m)
const N := 48                  ## number of slices
const TOP := 40.0              ## the flat top
const TOWER_Z := 440.0         ## the stern towers
const MAST_I := 8              ## the bow mast stands on this slice
const TIER_I := [26, 20, 14, 9]                                       ## the terrace t covers the slices up to this one
var _tp: Array = []            ## turrets placed so far (the hull detail keeps clear of them)


func _sz(i: int) -> float:
	return Z0 + float(i) * P


func _sf(z: float) -> float:
	return clampf((z - Z0) / P, 0.0, float(N - 1))


func _u(i: int) -> float:                                             ## 1 at the prow, 0 at the stern
	return 1.0 - float(i) / float(N - 1)


func _depth(i: int) -> float:                                         ## how far the keel hangs below the top: shallow at the stern, a steep sweep at the prow
	return 70.0 + 310.0 * pow(_u(i), 2.5)


func _bot(i: int) -> float:
	return TOP - _depth(i)


func _w(i: int) -> float:                                             ## half width: a slim arrow at the prow, spreading to the stern
	return 30.0 + 220.0 * pow(1.0 - _u(i), 1.1)


func _ymid(z: float) -> float:
	return (TOP + _bot(int(roundf(_sf(z))))) * 0.5


func _tier_w(t: int) -> float:
	return 0.8 - 0.15 * float(t)


func _top_at(z: float, x: float) -> float:
	var n := int(roundf(_sf(z)))
	var top := TOP
	for t in 4:
		if n <= int(TIER_I[t]) and absf(x) < _w(n) * _tier_w(t) - 8.0:
			top = TOP + 9.5 + 12.0 * float(t)
	return top


func gbox(c: Vector3, h: Vector3, type: String = ModuleCatalog.ARMOR) -> void:
	d.add_module(type, "box", c, h, 1, "", Basis.IDENTITY)


func _near_turret(x: float, y: float, z: float) -> bool:
	for t in _tp:
		var c: Vector3 = t[0]
		if Vector2(c.x - x, c.z - z).length() < float(t[1]) + 14.0 and absf(c.y - y) < 45.0:
			return true
		if absf(c.x - x) < float(t[1]) + 10.0 and z > c.z - 125.0 and z < c.z + 125.0 and absf(c.y - y) < 45.0:
			return true                     # in front of (or behind) its barrels
	return false


func _in_tower_zone(z: float, x: float) -> bool:
	return (absf(z - TOWER_Z) < 150.0 and absf(x) < 190.0) or (absf(z - _sz(MAST_I)) < 50.0 and absf(x) < 40.0)


func spearhead() -> void:
	d.ship_name = "Spearhead"
	_tp.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in N:                                                           # the hull, slice by slice: flat top, curved keel, spreading width
		var top := TOP
		var bot := _bot(i)
		box(H, Vector3(0, (top + bot) * 0.5, _sz(i)), Vector3(_w(i), (top - bot) * 0.5, 20.0))
	d.add_module(H, "pyramid", Vector3(0, TOP - 28.0, Z0 - 52.0), Vector3(30.0, 50.0, 30.0), 12, "", Basis(Vector3.RIGHT, -PI * 0.5))   # the lip of the prow
	cyl(H, Vector3(0, _bot(0) - 14.0, Z0), 6.0, 60.0, Vector3(0, 1, 0), "", 8)                   # the keel spike
	antenna(Vector3(0, _bot(0) - 76.0, Z0), 2.0, 40.0)
	for t in 4:                                                           # terraces: layers stacked on the top, higher towards the prow
		for i in range(0, int(TIER_I[t]) + 1):
			box(H, Vector3(0, TOP + 3.0 + 12.0 * float(t) + 3.5 - 3.5, _sz(i)), Vector3(_w(i) * _tier_w(t), 6.5, 20.0))
	var ze := _sz(N - 1) + 20.0                                           # engine block and engines
	box(H, Vector3(0, TOP - 35.0, ze), Vector3(_w(N - 1), 35.0, 50.0))
	for x in [-190.0, -95.0, 0.0, 95.0, 190.0]:
		thruster(Vector3(x, TOP - 35.0, ze + 100.0), 34.0, 60.0, Vector3(0, 0, -1), "ion")
	var xs := _w(int(roundf(_sf(150.0)))) + 25.0                          # flank sponsons: the gun batteries, brakes and manoeuvring pods
	var ys := _ymid(150.0)
	for sx in [-1.0, 1.0]:
		box(H, Vector3(sx * xs, ys, 150), Vector3(55, 28, 110))
		pod(Vector3(sx * xs, ys, 40), Vector3(0, 0, -1), 28.0, 42.0, "ion")
		pod(Vector3(sx * (xs + 55.0), ys, 150), Vector3(sx, 0, 0), 13.0, 18.0)
		pod(Vector3(sx * (_w(N - 1) - 18.0), TOP - 35.0, ze), Vector3(sx, 0, 0), 13.0, 18.0)
		pod(Vector3(sx * (_w(1) - 4.0), -20.0, _sz(1)), Vector3(sx, 0, 0), 11.0, 16.0)
		for sy in [-1.0, 1.0]:
			pod(Vector3(sx * 100.0, TOP if sy > 0.0 else TOP - 70.0, ze), Vector3(0, sy, 0), 13.0, 18.0)
			pod(Vector3(sx * xs, ys + sy * 28.0, 150), Vector3(0, sy, 0), 13.0, 18.0)
		for z in [70.0, 150.0, 230.0]:                                    # a battery of heavy twins on each sponson
			turret(Vector3(sx * xs, ys + 24.0, z), 14.0, "cannon", 2, 1.6, 70.0)
		box(ModuleCatalog.AIRLOCK, Vector3(sx * xs, ys, 215), Vector3(60, 12, 14), "standard")
		box(ModuleCatalog.POD_BAY, Vector3(sx * xs, ys, 100), Vector3(60, 8, 14), "standard")
	pod(Vector3(0, TOP, _sz(1)), Vector3(0, 1, 0), 11.0, 16.0)
	pod(Vector3(0, _bot(1), _sz(1)), Vector3(0, -1, 0), 11.0, 16.0)
	# the stern towers: two tapering columns that lean back, fused at the base and parted higher up, with a bridge deck across the top
	var k_top := 13
	for k in k_top:
		var yk := TOP + 14.0 + 26.0 * float(k)
		var zk := TOWER_Z + 4.0 * float(k)
		var hx := 56.0 - 1.9 * float(k)                                   # each tower narrows as it climbs, so the gap between them opens
		var hz := 78.0 - 3.6 * float(k)
		for sx in [-1.0, 1.0]:
			box(H, Vector3(sx * 58.0, yk, zk), Vector3(hx, 17.0, hz))
	var yh := TOP + 14.0 + 26.0 * float(k_top - 1) + 30.0                   # the heads
	var zh := TOWER_Z + 4.0 * float(k_top - 1)
	for sx in [-1.0, 1.0]:
		var tx: float = sx * 58.0
		box(H, Vector3(tx, yh, zh + 10.0), Vector3(48.0, 20.0, 70.0))
		turret(Vector3(tx, yh + 20.0, zh + 10.0), 16.0, "cannon", 2, 1.8, 80.0)
		radar(Vector3(tx, yh + 18.0, zh - 40.0), 11.0)
		antenna(Vector3(tx, yh + 50.0, zh + 50.0), 1.2, 30.0)
		d.add_module(H, "dome", Vector3(sx * 135.0, TOP + 6.0, TOWER_Z - 55.0), Vector3(30, 30, 30), 12, "", Basis.IDENTITY)
	box(H, Vector3(0, yh - 4.0, zh + 6.0), Vector3(90.0, 14.0, 44.0))     # the bridge deck between the heads
	commander(Vector3(0, yh + 18.0, zh + 6.0), Vector3(30, 12, 28), "bridge")
	# the bow mast on the highest terrace
	var zb := _sz(MAST_I)
	var tb := _top_at(zb, 0.0)
	box(H, Vector3(0, tb + 18.0, zb), Vector3(16, 24, 22))
	box(H, Vector3(0, tb + 52.0, zb + 6.0), Vector3(10, 18, 14))
	commander(Vector3(0, tb + 70.0, zb + 6.0), Vector3(12, 8, 12))
	radar(Vector3(0, tb + 76.0, zb + 6.0), 7.0)
	antenna(Vector3(0, tb + 98.0, zb + 6.0), 1.0, 24.0)
	commander(Vector3(0, -10, 100), Vector3(28, 24, 40))
	commander(Vector3(0, -10, -300), Vector3(16, 14, 30))
	commander(Vector3(0, TOP - 30.0, ze - 40.0), Vector3(26, 20, 30))
	box(ModuleCatalog.ENGINE_ROOM, Vector3(0, TOP - 35.0, 540), Vector3(36, 30, 36), "control")
	for i in [2, 6, 10, 14, 18, 22, 28, 33, 40]:                          # heavy twins down the terraces and the back deck
		var z: float = _sz(i)
		for sx in [-1.0, 1.0]:
			var x: float = sx * _w(i) * 0.4
			if _in_tower_zone(z, x):
				continue
			turret(Vector3(x, _top_at(z, x) - 4.0, z), 16.0 if i > 6 else 11.0, "cannon", 2, 1.8, 80.0)
	for i in range(3, N - 1, 1):                                          # medium guns along the edges
		var z: float = _sz(i) + 10.0
		for sx in [-1.0, 1.0]:
			var x: float = sx * _w(i) * 0.74
			if _in_tower_zone(z, x) or i % 2 == 1 or _near_turret(x, _top_at(z, x) - 3.0, z):
				continue
			turret(Vector3(x, _top_at(z, x) - 3.0, z), 9.0, "autocannon", 2, 0.8, 28.0, -1.0, "light")
	for k in 26:                                                          # point defence
		var z2 := rng.randf_range(Z0 + 120.0, ze - 60.0)
		var wz := _w(int(roundf(_sf(z2))))
		var x2 := rng.randf_range(-wz * 0.85, wz * 0.85)
		if _in_tower_zone(z2, x2) or _near_turret(x2, _top_at(z2, x2) - 2.0, z2):
			continue
		turret(Vector3(x2, _top_at(z2, x2) - 2.0, z2), 4.5, "flak", 1, 0.5, 14.0, -1.0, "light")
	turret(Vector3(0, TOP - 2.0, ze), 20.0, "cannon", 2, 2.0, 90.0, 1.0)
	for k in 240:                                                         # hull detail: thin panels, vents and fins (flat, not blocks)
		var z3 := rng.randf_range(Z0 + 14.0, ze - 20.0)
		var n3 := int(roundf(_sf(z3)))
		var w3 := _w(n3)
		var hx := rng.randf_range(3.0, 12.0)
		var hy := rng.randf_range(0.5, 1.6)
		var hz := rng.randf_range(3.0, 12.0)
		var side := rng.randf()
		if side < 0.55:
			var x3 := rng.randf_range(-w3 * 0.9, w3 * 0.9)
			if _in_tower_zone(z3, x3):
				continue
			var yt := _top_at(z3, x3)
			if _near_turret(x3, yt, z3):
				continue
			if rng.randf() < 0.12:
				cyl(A, Vector3(x3, yt + 1.0, z3), rng.randf_range(1.5, 3.0), rng.randf_range(1.5, 3.0), Vector3(0, 1, 0), "", 6)
			else:
				gbox(Vector3(x3, yt + hy - 1.0, z3), Vector3(hx, hy, hz))
		else:
			var sgn := -1.0 if rng.randf() < 0.5 else 1.0                 # panels on the flanks, from the top down the keel
			var yb := _bot(n3)
			gbox(Vector3(sgn * (w3 + hy - 0.5), rng.randf_range(yb + 10.0, TOP - 8.0), z3), Vector3(hy, rng.randf_range(2.0, 9.0), hz))


func _ready() -> void:
	var names := ["Quadwing", "Orb Interceptor", "Hammerhead", "Nautilus", "Spearhead"]
	var which := OS.get_environment("WHICH")
	for n in names:
		if which != "" and which != n:
			continue
		d = ShipDesign.new()
		match n:
			"Quadwing": quadwing()
			"Orb Interceptor": orb()
			"Hammerhead": hammerhead()
			"Nautilus": nautilus()
			"Spearhead": spearhead()
		d.gyro_scale = 1.0
		var errs := d.validate()
		errs.append_array(d.turret_errors())
		var props := d.compute_props()
		var fwd := 0.0
		var back := 0.0
		for t in props["thrusters"]:
			var dv: Vector3 = t["dir"]
			if dv.z < -0.9:
				fwd += float(t["power"])
			elif dv.z > 0.9:
				back += float(t["power"])
		if OS.get_environment("DBG") != "":
			for k in OS.get_environment("DBG").split(","):
				print("  module ", k, " ", d.modules[int(k)]["type"], " ", d.module_centroid(int(k)).snapped(Vector3.ONE))
		print("%s: modules %d  vertices %d  length %.0f m  mass %s kg  fwd %.3f m/s2  retro %.3f m/s2  problems %d" % [n, d.modules.size(), d.vertices.size(), d.extent_length(), str(snappedf(props["mass"], 1.0)), fwd / props["mass"], back / props["mass"], errs.size()])
		for e in errs:
			var parts: PackedStringArray = e.split(" ")
			var extra := ""
			if parts.size() > 1 and parts[0] == "Module" and parts[1].is_valid_int():
				extra = "  at " + str(d.module_centroid(int(parts[1])).snapped(Vector3.ONE))
			print("   PROBLEM: ", e.left(200), extra)
		if OS.get_environment("SAVE") != "":
			if OS.get_environment("NO_PAINT") == "":
				var styles := {"Quadwing": 1, "Orb Interceptor": 2, "Hammerhead": 5, "Nautilus": 6, "Spearhead": 0}
				AutoPaint.apply(d, {"style": styles[n], "seed": 5, "density": 1.0, "wear": 0.35})
			print("   saved: ", error_string(d.save_premade()))
	get_tree().quit()
