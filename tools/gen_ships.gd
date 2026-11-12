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


var _tp: Array = []            ## turrets placed so far (the hull detail keeps clear of them)


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
## An original capital ship that mixes two looks: a DEEP BOW with stepped terraces rising towards a mast (the long arrowhead of a
## star destroyer) and a WIDE STERN with two tall bridge towers, flank gun sponsons and a row of engines (a battle-cruiser's back).
const WZ0 := -820.0            ## z of the first plate
const WP := 72.0               ## pitch of the plates (each is 80 m long, so they overlap by 8 m)
const NP := 21                 ## number of plates
const TOWER_Z := 470.0         ## the two stern towers
const MAST_I := 3              ## the bow mast stands on this plate


func _wz(i: int) -> float:
	return WZ0 + float(i) * WP


func _wf(z: float) -> float:
	return clampf((z - WZ0) / WP, 0.0, float(NP - 1))


func _wedge_w(i: int) -> float:                                       ## half width: a slim arrow at the bow, spreading towards the stern
	return 50.0 + 200.0 * pow(float(i) / float(NP - 1), 1.2)


func _wedge_h(i: int) -> float:                                       ## half height: deep at the bow, flatter behind
	return 100.0 - 56.0 * minf(float(i) / 11.0, 1.0) + maxf(float(i) - 12.0, 0.0) * 0.6


const TIER_I := [10, 8, 6, 4]                                         ## the terrace t covers the plates up to this one
func _tier_w(t: int) -> float:
	return 0.85 - 0.13 * float(t)


func _top_at(z: float, x: float) -> float:
	var n := int(roundf(_wf(z)))                                      # the plate this point is over
	var w := _wedge_w(n)
	var top := _wedge_h(n)
	for t in 4:
		if n <= int(TIER_I[t]) and absf(x) < w * _tier_w(t) - 8.0:
			top = _wedge_h(n) + 8.0 + 12.0 * float(t)
	return top


func gbox(c: Vector3, h: Vector3, type: String = ModuleCatalog.ARMOR) -> void:
	d.add_module(type, "box", c, h, 1, "", Basis.IDENTITY)


func _near_turret(x: float, y: float, z: float) -> bool:
	for t in _tp:
		var c: Vector3 = t[0]
		if Vector2(c.x - x, c.z - z).length() < float(t[1]) + 14.0 and absf(c.y - y) < 45.0:
			return true
	return false


func _in_tower_zone(z: float, x: float) -> bool:
	var hn := _wz(MAST_I)
	return (absf(z - TOWER_Z) < 130.0 and absf(x) < 170.0) or (absf(z - hn) < 50.0 and absf(x) < 40.0) or (absf(z - _wz(1)) < 45.0 and absf(x) < 40.0)


func spearhead() -> void:
	d.ship_name = "Spearhead"
	_tp.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in NP:                                                          # the hull: each plate wider than the one ahead, deep at the bow
		box(H, Vector3(0, 0, _wz(i)), Vector3(_wedge_w(i), _wedge_h(i), 40.0))
	nose(H, Vector3(0, 0, _wz(0) - 100.0), 50.0, 70.0, 100.0)              # the prow
	for t in 4:                                                           # terraces: layers that stack higher towards the bow
		for i in range(0, int(TIER_I[t]) + 1):
			box(H, Vector3(0, _wedge_h(i) + 3.0 + 12.0 * float(t), _wz(i)), Vector3(_wedge_w(i) * _tier_w(t), 5.0, 40.0))
	var ze := _wz(NP - 1) + 40.0                                          # engine block and engines
	box(H, Vector3(0, 0, ze), Vector3(_wedge_w(NP - 1), 46, 50))
	for x in [-190.0, -95.0, 0.0, 95.0, 190.0]:
		thruster(Vector3(x, 0, ze + 100.0), 34.0, 60.0, Vector3(0, 0, -1), "ion")
	var xs := _wedge_w(14) + 25.0                                         # flank sponsons: the gun batteries, brakes and manoeuvring pods
	for sx in [-1.0, 1.0]:
		box(H, Vector3(sx * xs, 0, 150), Vector3(55, 28, 110))
		pod(Vector3(sx * xs, 0, 40), Vector3(0, 0, -1), 28.0, 42.0, "ion")
		pod(Vector3(sx * (xs + 55.0), 0, 150), Vector3(sx, 0, 0), 13.0, 18.0)
		pod(Vector3(sx * (_wedge_w(NP - 1) - 18.0), 0, ze), Vector3(sx, 0, 0), 13.0, 18.0)
		pod(Vector3(sx * (_wedge_w(1) - 4.0), 0, _wz(1)), Vector3(sx, 0, 0), 11.0, 16.0)
		for sy in [-1.0, 1.0]:
			pod(Vector3(sx * 100.0, sy * 46.0, ze), Vector3(0, sy, 0), 13.0, 18.0)
			pod(Vector3(sx * xs, sy * 28.0, 150), Vector3(0, sy, 0), 13.0, 18.0)
		for z in [70.0, 150.0, 230.0]:                                    # a battery of heavy twins on each sponson
			turret(Vector3(sx * xs, 24.0, z), 14.0, "cannon", 2, 1.6, 70.0)
		box(ModuleCatalog.AIRLOCK, Vector3(sx * xs, 0, 215), Vector3(60, 12, 14), "standard")
		box(ModuleCatalog.POD_BAY, Vector3(sx * xs, 0, 100), Vector3(60, 8, 14), "standard")
	for sy in [-1.0, 1.0]:
		pod(Vector3(0, sy * _wedge_h(1), _wz(1)), Vector3(0, sy, 0), 11.0, 16.0)
	# the stern towers (battle-cruiser style): two tall stacks leaning back, joined by a bridge deck
	var n_t := int(roundf(_wf(TOWER_Z)))
	var ht := _wedge_h(n_t)
	for sx in [-1.0, 1.0]:
		var tx: float = sx * 75.0
		box(H, Vector3(tx, ht + 55.0, TOWER_Z - 30.0), Vector3(40, 60, 70))
		box(H, Vector3(tx, ht + 194.0, TOWER_Z), Vector3(34, 85, 56))
		box(H, Vector3(tx, ht + 303.0, TOWER_Z + 25.0), Vector3(46, 30, 64))
		turret(Vector3(tx, ht + 329.0, TOWER_Z + 25.0), 16.0, "cannon", 2, 1.8, 80.0)
		radar(Vector3(tx, ht + 330.0, TOWER_Z - 25.0), 12.0)
		antenna(Vector3(tx, ht + 360.0, TOWER_Z + 55.0), 1.2, 30.0)
		d.add_module(H, "dome", Vector3(sx * 130.0, ht + 12.0, TOWER_Z - 60.0), Vector3(30, 30, 30), 12, "", Basis.IDENTITY)
	box(H, Vector3(0, ht + 303.0, TOWER_Z + 20.0), Vector3(110, 14, 40))  # the deck between the towers
	commander(Vector3(0, ht + 328.0, TOWER_Z + 20.0), Vector3(30, 12, 30), "bridge")
	box(H, Vector3(0, ht + 80.0, TOWER_Z - 10.0), Vector3(90, 70, 50))    # the body that carries both towers
	# the bow mast on the highest terrace
	var zb := _wz(MAST_I)
	var tb := _top_at(zb, 0.0)
	box(H, Vector3(0, tb + 18.0, zb), Vector3(16, 24, 22))
	box(H, Vector3(0, tb + 52.0, zb + 6.0), Vector3(10, 18, 14))
	commander(Vector3(0, tb + 70.0, zb + 6.0), Vector3(12, 8, 12))
	radar(Vector3(0, tb + 76.0, zb + 6.0), 7.0)
	antenna(Vector3(0, tb + 98.0, zb + 6.0), 1.0, 24.0)
	commander(Vector3(0, 0, 100), Vector3(28, 24, 40))
	commander(Vector3(0, 0, -300), Vector3(16, 14, 30))
	commander(Vector3(0, 10, ze - 40.0), Vector3(26, 20, 30))
	box(ModuleCatalog.ENGINE_ROOM, Vector3(0, 0, 540), Vector3(36, 36, 36), "control")
	cyl(H, Vector3(0, -_wedge_h(4) - 10.0, _wz(4)), 40.0, 14.0, Vector3(0, 1, 0), "", 24)      # ventral dish near the bow
	d.add_module(A, "dome", Vector3(0, -_wedge_h(4) - 22.0, _wz(4)), Vector3(30, 30, 30), 12, "", Basis(Vector3.RIGHT, PI))
	for i in [1, 3, 5, 7, 9, 12, 15, 18]:                                 # heavy twins down the terraces and the back deck
		var z: float = _wz(i)
		for sx in [-1.0, 1.0]:
			var x: float = sx * _wedge_w(i) * 0.4
			if _in_tower_zone(z, x):
				continue
			turret(Vector3(x, _top_at(z, x) - 4.0, z), 16.0 if i > 4 else 12.0, "cannon", 2, 1.8, 80.0)
	for i in range(2, NP - 1):                                            # medium guns along the edges
		var z: float = _wz(i) + 30.0
		for sx in [-1.0, 1.0]:
			var x: float = sx * _wedge_w(i) * 0.72
			if _in_tower_zone(z, x):
				continue
			turret(Vector3(x, _top_at(z, x) - 3.0, z), 9.0, "autocannon", 2, 0.8, 28.0, -1.0, "light")
	for k in 26:                                                          # point defence
		var z2 := rng.randf_range(-640.0, ze - 60.0)
		var wz := _wedge_w(int(roundf(_wf(z2))))
		var x2 := rng.randf_range(-wz * 0.85, wz * 0.85)
		if _in_tower_zone(z2, x2):
			continue
		turret(Vector3(x2, _top_at(z2, x2) - 2.0, z2), 4.5, "flak", 1, 0.5, 14.0, -1.0, "light")
	turret(Vector3(0, 42, ze), 20.0, "cannon", 2, 2.0, 90.0, 1.0)
	for k in 300:                                                         # hull detail: slabs, vents, pipes and fins over every surface
		var z3 := rng.randf_range(-760.0, ze - 20.0)
		var n3 := int(roundf(_wf(z3)))
		var w3 := _wedge_w(n3)
		var h3 := _wedge_h(n3)
		var hx := rng.randf_range(2.0, 7.0)
		var hy := rng.randf_range(1.0, 3.0)
		var hz := rng.randf_range(2.0, 9.0)
		var side := rng.randf()
		if side < 0.7:
			var x3 := rng.randf_range(-w3 * 0.9, w3 * 0.9)
			if _in_tower_zone(z3, x3):
				continue
			var yt := _top_at(z3, x3)
			if _near_turret(x3, yt, z3):
				continue
			if rng.randf() < 0.25:
				cyl(A, Vector3(x3, yt + 1.0, z3), rng.randf_range(1.5, 4.0), rng.randf_range(2.0, 4.0), Vector3(0, 1, 0), "", 6)
			else:
				gbox(Vector3(x3, yt + hy - 1.0, z3), Vector3(hx, hy, hz))
		elif side < 0.85:
			var sgn := -1.0 if rng.randf() < 0.5 else 1.0
			gbox(Vector3(sgn * (w3 + hx - 1.0), rng.randf_range(-h3 * 0.7, h3 * 0.7), z3), Vector3(hx, rng.randf_range(2.0, 6.0), hz))
		else:
			gbox(Vector3(rng.randf_range(-w3 * 0.9, w3 * 0.9), -h3 - hy + 1.0, z3), Vector3(hx, hy, hz))


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
