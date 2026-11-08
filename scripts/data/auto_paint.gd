class_name AutoPaint
extends RefCounted
## "Auto paint": gives a ship a complete professional-looking finish in one go: livery colours, plate lines and rivets,
## window decks, running lights, hull number and name, stripes and insignia, vents, hatches, greebles, antennas, weathering.
## Everything it adds goes into the DETAIL layer flagged `auto`, so running it again replaces ITS work only; whatever the
## player placed by hand stays. The result is the same for the same seed.
##   AutoPaint.apply(design, {style = 0, seed = 1, density = 1.0, recolor = true, windows = true, lights = true,
##                            livery = true, greebles = true, wear = 0.3})

## [name, base, accent, trim, dark, glass tint, light colour, metal, rough, gloss]
const STYLES := [
	["Military grey", Color(0.46, 0.49, 0.53), Color(0.8, 0.15, 0.1), Color(0.3, 0.33, 0.37), Color(0.12, 0.13, 0.15), Color(1.0, 0.8, 0.45), Color(1.0, 0.85, 0.5), 0.45, 0.5, 0.0],
	["Navy blue", Color(0.14, 0.22, 0.38), Color(0.95, 0.8, 0.2), Color(0.35, 0.4, 0.5), Color(0.06, 0.08, 0.12), Color(0.8, 0.9, 1.0), Color(0.9, 0.95, 1.0), 0.4, 0.45, 0.2],
	["Industrial orange", Color(0.85, 0.5, 0.12), Color(0.12, 0.12, 0.14), Color(0.5, 0.5, 0.52), Color(0.1, 0.1, 0.11), Color(1.0, 0.9, 0.6), Color(1.0, 0.9, 0.6), 0.25, 0.6, 0.0],
	["Stealth black", Color(0.07, 0.075, 0.09), Color(0.5, 0.05, 0.08), Color(0.14, 0.15, 0.18), Color(0.03, 0.03, 0.035), Color(0.9, 0.2, 0.2), Color(1.0, 0.25, 0.2), 0.7, 0.35, 0.3],
	["Clean white", Color(0.88, 0.9, 0.93), Color(0.15, 0.35, 0.75), Color(0.6, 0.63, 0.68), Color(0.2, 0.22, 0.25), Color(0.7, 0.9, 1.0), Color(0.8, 0.95, 1.0), 0.2, 0.35, 0.6],
	["Desert tan", Color(0.62, 0.52, 0.36), Color(0.25, 0.3, 0.2), Color(0.42, 0.36, 0.26), Color(0.14, 0.12, 0.09), Color(1.0, 0.85, 0.5), Color(1.0, 0.8, 0.4), 0.3, 0.7, 0.0],
	["Raider rust", Color(0.4, 0.25, 0.18), Color(0.85, 0.7, 0.1), Color(0.3, 0.3, 0.3), Color(0.08, 0.07, 0.06), Color(1.0, 0.55, 0.2), Color(1.0, 0.5, 0.15), 0.35, 0.75, 0.0],
]
const MAX_AUTO := 45000


static func style_names() -> Array:
	var out: Array = []
	for s in STYLES:
		out.append(s[0])
	return out


static func default_options() -> Dictionary:
	return {"style": 0, "seed": 1, "density": 1.0, "recolor": true, "windows": true, "lights": true,
		"livery": true, "greebles": true, "wear": 0.3, "text": true}


## Returns how many details were added.
static func apply(d: ShipDesign, options: Dictionary = {}) -> int:
	var o := default_options()
	o.merge(options, true)
	d.clear_details(true)
	var st: Array = STYLES[clampi(int(o["style"]), 0, STYLES.size() - 1)]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(o["seed"]) * 7919 + 13
	# ---- finish of the whole ship
	d.set_finish("metal", st[7])
	d.set_finish("rough", st[8])
	d.set_finish("gloss", st[9])
	d.set_finish("panels", 0.65)
	d.set_finish("rivets", 1.0)
	d.set_finish("wear", clampf(float(o["wear"]), 0.0, 1.0))
	d.set_finish("panel_size", 0.0)
	if bool(o["recolor"]):
		_recolor(d, st, rng)
	if d.modules.is_empty():
		return 0
	var ctx := _Surface.new()
	ctx.build(d)
	if ctx.areas.is_empty():
		return 0
	var L := d.extent_length()
	var u := clampf(sqrt(L) / 9.0, 0.3, 5.0)
	var density := clampf(float(o["density"]), 0.1, 3.0)
	var added := 0
	var before := d.details.size()
	if bool(o["windows"]):
		_windows(d, ctx, st, rng, u, density)
	if bool(o["lights"]):
		_lights(d, ctx, st, rng, u, density)
	if bool(o["livery"]):
		_livery(d, ctx, st, rng, u, bool(o["text"]))
	_surface_details(d, ctx, st, rng, u, density, bool(o["greebles"]))
	if float(o["wear"]) > 0.02:
		_wear(d, ctx, st, rng, u, float(o["wear"]))
	added = d.details.size() - before
	return added


static func _recolor(d: ShipDesign, st: Array, rng: RandomNumberGenerator) -> void:
	var u := clampf(sqrt(d.extent_length()) / 9.0, 0.3, 5.0)
	for mi in d.modules.size():
		var t: String = d.modules[mi]["type"]
		var base: Color = st[1]
		var acc: Color = st[2]
		var trim: Color = st[3]
		var dark: Color = st[4]
		var shade := 1.0 + (rng.randf() - 0.5) * 0.18
		var c1 := Color(base.r * shade, base.g * shade, base.b * shade)
		var c2 := trim
		var pat := 0
		match t:
			ModuleCatalog.ARMOR:
				c1 = Color(base.r * 0.8 * shade, base.g * 0.8 * shade, base.b * 0.8 * shade)
				if rng.randf() < 0.08:
					c2 = acc
					pat = 3
			ModuleCatalog.THRUSTER:
				c1 = dark
				c2 = acc
				pat = 1 if rng.randf() < 0.3 else 0
			ModuleCatalog.BARREL, ModuleCatalog.ANTENNA:
				c1 = dark.lerp(trim, 0.3)
			ModuleCatalog.TURRET, ModuleCatalog.RADAR:
				c1 = trim
			ModuleCatalog.COMMANDER:
				c1 = base.lerp(acc, 0.12)
				c2 = acc
				pat = 4 if rng.randf() < 0.5 else 0
			ModuleCatalog.ENGINE_ROOM, ModuleCatalog.AIRLOCK, ModuleCatalog.POD_BAY:
				c1 = trim.lerp(base, 0.4)
				c2 = acc
				pat = 3 if t == ModuleCatalog.AIRLOCK else 0
			_:
				if rng.randf() < 0.12:
					c2 = acc
					pat = 4
		d.set_paint(mi, c1, c2, pat, maxf(u * 2.0, 0.5))


# ---------------------------------------------------------------------------------------------
#  windows: decks of window rows (and portholes) on the hull and the command modules
# ---------------------------------------------------------------------------------------------
static func _windows(d: ShipDesign, s: _Surface, st: Array, rng: RandomNumberGenerator, u: float, density: float) -> void:
	var rows := int(clampf(s.total_area / (u * u * 140.0) * density, 3.0, 1400.0))
	var glass: Color = Color(0.03, 0.05, 0.09)
	var lit: Color = st[5]
	for r in rows:
		if d.details.size() >= MAX_AUTO:
			return
		var tri := s.pick(rng, s.w_windows)
		if tri < 0:
			continue
		var pt := s.random_point(rng, tri)
		var n: Vector3 = s.normals[tri]
		if not s.exposed(pt, n, u):
			continue
		var porthole := rng.randf() < 0.2
		var count := rng.randi_range(3, 14)
		var decks := rng.randi_range(1, 3)
		var wsz := Vector2(1.1, 0.65) * u if not porthole else Vector2(0.75, 0.75) * u
		var step := wsz.x * 1.45
		var frame := DetailCatalog.frame(n, 0.0)
		var lit_amount := rng.randf_range(0.15, 0.7)
		for dk in decks:
			for i in count:
				var q := pt + frame.x * (float(i) - count * 0.5) * step - frame.y * float(dk) * wsz.y * 2.0
				var hit := s.project(q, n, u * 0.6)
				if hit.is_empty():
					continue
				var dt := DetailCatalog.make(DetailCatalog.PORTHOLE if porthole else DetailCatalog.WINDOW, hit["p"], hit["n"], 1.0)
				dt["w"] = wsz.x
				dt["h"] = wsz.y
				dt["c"] = glass
				dt["c2"] = lit
				dt["g"] = lit_amount
				dt["m"] = s.module_of[tri]
				dt["auto"] = true
				d.details.append(dt)
		if rng.randf() < 0.25:
			var sp := DetailCatalog.make(DetailCatalog.STREAK, pt - frame.y * (wsz.y * decks + u), n, u)
			sp["w"] = count * step
			sp["h"] = u * rng.randf_range(3.0, 7.0)
			sp["g"] = rng.randf_range(0.3, 0.7)
			sp["m"] = s.module_of[tri]
			sp["auto"] = true
			d.details.append(sp)
	d.detail_rev += 1


# ---------------------------------------------------------------------------------------------
#  lights: red / green / white navigation lights at the extremes, strings of little lamps
# ---------------------------------------------------------------------------------------------
static func _lights(d: ShipDesign, s: _Surface, st: Array, rng: RandomNumberGenerator, u: float, density: float) -> void:
	var picks := [[Vector3.LEFT, Color(1.0, 0.1, 0.08), 1.0], [Vector3.RIGHT, Color(0.1, 1.0, 0.2), 1.0],
		[Vector3.BACK, Color(1, 1, 1), 1.0], [Vector3.UP, Color(1, 1, 1), 1.0], [Vector3.DOWN, Color(1, 0.3, 0.2), 1.0]]
	for pk in picks:
		var dir: Vector3 = pk[0]
		var best := -1
		var best_d := -INF
		for t in s.areas.size():
			var c: Vector3 = s.centroids[t]
			var v := c.dot(dir)
			if v > best_d and (s.normals[t] as Vector3).dot(dir) > 0.1:
				best_d = v
				best = t
		if best >= 0:
			var dt := DetailCatalog.make(DetailCatalog.LIGHT, s.centroids[best], s.normals[best], u * 2.5)
			dt["c"] = pk[1]
			dt["g"] = pk[2]
			dt["m"] = s.module_of[best]
			dt["auto"] = true
			d.details.append(dt)
	# strings of small lamps
	var strings := int(clampf(s.total_area / (u * u * 900.0) * density, 2.0, 300.0))
	for r in strings:
		var tri := s.pick(rng, s.w_all)
		if tri < 0:
			continue
		var pt := s.random_point(rng, tri)
		var n: Vector3 = s.normals[tri]
		if not s.exposed(pt, n, u):
			continue
		var frame := DetailCatalog.frame(n, 0.0)
		var dirv := frame.x if rng.randf() < 0.6 else frame.y
		var col: Color = st[6]
		for i in rng.randi_range(3, 9):
			var hit := s.project(pt + dirv * float(i) * u * 2.2, n, u * 0.6)
			if hit.is_empty():
				break
			var dt := DetailCatalog.make(DetailCatalog.LIGHT, hit["p"], hit["n"], u * 0.5)
			dt["c"] = col
			dt["g"] = 0.0
			dt["m"] = s.module_of[tri]
			dt["auto"] = true
			d.details.append(dt)


# ---------------------------------------------------------------------------------------------
#  livery: name, hull number, roundels, stripes, chevrons, docking marks, hatches on bays
# ---------------------------------------------------------------------------------------------
static func _livery(d: ShipDesign, s: _Surface, st: Array, rng: RandomNumberGenerator, u: float, text: bool) -> void:
	var acc: Color = st[2]
	var ink := Color(0.93, 0.93, 0.9) if (st[1] as Color).get_luminance() < 0.5 else Color(0.1, 0.1, 0.12)
	# largest exposed flat faces on each side
	var sides := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP]
	var used := {}
	for si in sides.size():
		var dir: Vector3 = sides[si]
		var ranked: Array = s.faces_facing(dir, 0.9)
		var placed := 0
		for f in ranked:
			if placed >= 2 or used.has(f["key"]):
				continue
			var n: Vector3 = f["n"]
			var c: Vector3 = f["c"]
			if not s.exposed(c, n, u):
				continue
			used[f["key"]] = true
			var size := sqrt(f["area"] as float)
			var frame := DetailCatalog.frame(n, 0.0)
			var wid: float = f["width"]
			if size < u * 5.0:
				continue
			if text and placed == 0:
				var th := clampf(size * 0.09, u * 0.8, u * 8.0)
				var name_s := d.ship_name.to_upper().left(18)
				var tt := DetailCatalog.make(DetailCatalog.TEXT, c + frame.y * size * 0.08, n, 1.0)
				tt["t"] = name_s
				tt["w"] = minf(wid * 0.8, th * name_s.length() * 0.7)
				tt["h"] = th
				tt["c"] = ink
				tt["m"] = f["m"]
				tt["auto"] = true
				d.details.append(tt)
				var num := DetailCatalog.make(DetailCatalog.TEXT, c - frame.y * size * 0.12, n, 1.0)
				num["t"] = "SN-%04d" % (absi(hash(d.ship_name) + int(rng.seed)) % 10000)
				num["w"] = minf(wid * 0.6, th * 5.0)
				num["h"] = th * 0.7
				num["c"] = ink
				num["m"] = f["m"]
				num["auto"] = true
				d.details.append(num)
			elif placed == 1 or si == 2:
				var ro := DetailCatalog.make(DetailCatalog.ROUNDEL, c, n, 1.0)
				ro["w"] = clampf(size * 0.3, u * 2.0, u * 18.0)
				ro["h"] = ro["w"]
				ro["c"] = acc
				ro["c2"] = ink
				ro["m"] = f["m"]
				ro["auto"] = true
				d.details.append(ro)
			# stripe across the face
			var sp := DetailCatalog.make(DetailCatalog.STRIPE, c - frame.y * size * 0.3, n, 1.0)
			sp["w"] = wid * 0.95
			sp["h"] = clampf(size * 0.035, u * 0.3, u * 3.0)
			sp["c"] = acc
			sp["m"] = f["m"]
			sp["auto"] = true
			d.details.append(sp)
			placed += 1
	# chevrons / warning signs near thrusters, docking marks on airlocks, hatches on pod bays
	for mi in d.modules.size():
		var t: String = d.modules[mi]["type"]
		if t == ModuleCatalog.AIRLOCK or t == ModuleCatalog.POD_BAY or t == ModuleCatalog.THRUSTER:
			var f: Dictionary = s.best_face_of(mi)
			if f.is_empty() or not s.exposed(f["c"], f["n"], u):
				continue
			var kind := DetailCatalog.DOCK_MARK if t == ModuleCatalog.AIRLOCK else (DetailCatalog.HATCH if t == ModuleCatalog.POD_BAY else DetailCatalog.WARNING)
			var dt := DetailCatalog.make(kind, f["c"], f["n"], u * (1.6 if kind != DetailCatalog.WARNING else 1.0))
			dt["c"] = ink if kind == DetailCatalog.DOCK_MARK else dt["c"]
			dt["c2"] = acc if kind == DetailCatalog.DOCK_MARK else dt["c2"]
			dt["m"] = mi
			dt["auto"] = true
			d.details.append(dt)


# ---------------------------------------------------------------------------------------------
#  plates, vents, grilles, hatches, boxes, tanks, antennas
# ---------------------------------------------------------------------------------------------
static func _surface_details(d: ShipDesign, s: _Surface, st: Array, rng: RandomNumberGenerator, u: float, density: float, greebles: bool) -> void:
	var trim: Color = st[3]
	var dark: Color = st[4]
	var base: Color = st[1]
	var count := int(clampf(s.total_area / (u * u * 90.0) * density, 4.0, 5000.0))
	for i in count:
		if d.details.size() >= MAX_AUTO:
			return
		var tri := s.pick(rng, s.w_all)
		if tri < 0:
			continue
		var pt := s.random_point(rng, tri)
		var n: Vector3 = s.normals[tri]
		if not s.exposed(pt, n, u):
			continue
		var roll := rng.randf()
		var dt: Dictionary
		if roll < 0.4:
			dt = DetailCatalog.make(DetailCatalog.PANEL, pt, n, u * rng.randf_range(0.8, 1.6), 0.0 if rng.randf() < 0.5 else PI * 0.5)
			dt["c"] = base.lerp(trim, rng.randf())
			dt["c2"] = dark
		elif roll < 0.55:
			dt = DetailCatalog.make(DetailCatalog.VENT, pt, n, u * rng.randf_range(0.8, 1.4))
			dt["c"] = dark
			dt["c2"] = trim
		elif roll < 0.67:
			dt = DetailCatalog.make(DetailCatalog.GRILLE, pt, n, u * rng.randf_range(0.8, 1.5))
			dt["c"] = dark
			dt["c2"] = trim
		elif roll < 0.8:
			dt = DetailCatalog.make(DetailCatalog.HATCH, pt, n, u * rng.randf_range(0.8, 1.4))
			dt["c"] = trim
			dt["c2"] = dark
		elif greebles and roll < 0.96:
			var kind := DetailCatalog.BOX if rng.randf() < 0.65 else DetailCatalog.CYLINDER
			dt = DetailCatalog.make(kind, pt, n, u)
			dt["w"] = u * rng.randf_range(0.6, 2.6)
			dt["h"] = u * rng.randf_range(0.6, 2.2) if kind == DetailCatalog.BOX else dt["w"]
			dt["d"] = u * rng.randf_range(0.25, 1.1)
			dt["a"] = rng.randf() * PI
			dt["c"] = base.lerp(trim, rng.randf()).darkened(rng.randf() * 0.25)
			dt["c2"] = dark
		elif greebles and n.y > 0.4:
			dt = DetailCatalog.make(DetailCatalog.ANTENNA, pt, n, u)
			dt["w"] = u * 0.12
			dt["h"] = u * 0.12
			dt["d"] = u * rng.randf_range(2.0, 6.0)
			dt["c"] = trim
			dt["c2"] = Color(1.0, 0.2, 0.15)
		else:
			continue
		dt["m"] = s.module_of[tri]
		dt["auto"] = true
		d.details.append(dt)
	d.detail_rev += 1


# ---------------------------------------------------------------------------------------------
#  weathering: scorch marks, rust and dirt streaks, scratches
# ---------------------------------------------------------------------------------------------
static func _wear(d: ShipDesign, s: _Surface, _st: Array, rng: RandomNumberGenerator, u: float, wear: float) -> void:
	var count := int(clampf(s.total_area / (u * u * 260.0) * wear, 0.0, 1500.0))
	for i in count:
		if d.details.size() >= MAX_AUTO:
			return
		var tri := s.pick(rng, s.w_all)
		if tri < 0:
			continue
		var pt := s.random_point(rng, tri)
		var n: Vector3 = s.normals[tri]
		if not s.exposed(pt, n, u):
			continue
		var roll := rng.randf()
		var dt: Dictionary
		if roll < 0.4:
			dt = DetailCatalog.make(DetailCatalog.SCORCH, pt, n, u * rng.randf_range(1.5, 5.0))
			dt["g"] = rng.randf_range(0.3, 0.9)
		elif roll < 0.75:
			dt = DetailCatalog.make(DetailCatalog.STREAK, pt, n, u)
			dt["w"] = u * rng.randf_range(1.0, 3.0)
			dt["h"] = u * rng.randf_range(3.0, 9.0)
			dt["g"] = rng.randf_range(0.3, 0.8)
			dt["c"] = Color(0.3, 0.16, 0.08) if rng.randf() < 0.5 else Color(0.06, 0.06, 0.06)
		else:
			dt = DetailCatalog.make(DetailCatalog.SCRATCH, pt, n, u * rng.randf_range(1.5, 4.0), rng.randf() * PI)
			dt["g"] = rng.randf_range(0.4, 1.0)
		dt["m"] = s.module_of[tri]
		dt["auto"] = true
		d.details.append(dt)
	d.detail_rev += 1


# =====================================================================================
#  The ship's skin as triangles: weighted picking, random points, "is it visible from outside?"
# =====================================================================================
class _Surface extends RefCounted:
	var idx := RayIndex.new()
	var areas: PackedFloat32Array = PackedFloat32Array()
	var normals: Array = []        # Vector3 per triangle
	var centroids: Array = []
	var module_of: PackedInt32Array = PackedInt32Array()
	var face_of: PackedInt32Array = PackedInt32Array()
	var total_area := 0.0
	var reach := 100.0
	var w_all := PackedFloat64Array()      # cumulative weights per purpose
	var w_windows := PackedFloat64Array()
	var _faces := {}                       # "mi:fi" -> {key, m, area, c, n, width}
	var _design: ShipDesign

	func build(d: ShipDesign) -> void:
		_design = d
		var soup := PackedVector3Array()
		for mi in d.modules.size():
			var tf := PackedInt32Array()
			var t := d.module_tris(mi, tf)
			var type: String = d.modules[mi]["type"]
			for i in range(0, t.size(), 3):
				var n := (t[i + 1] - t[i]).cross(t[i + 2] - t[i])
				var a := n.length() * 0.5
				if a < 0.0001:
					continue
				soup.append_array([t[i], t[i + 1], t[i + 2]])
				areas.append(a)
				normals.append(n.normalized())
				centroids.append((t[i] + t[i + 1] + t[i + 2]) / 3.0)
				module_of.append(mi)
				face_of.append(tf[int(i / 3.0)])
				var ww := a
				var wa := a
				match type:
					ModuleCatalog.BARREL, ModuleCatalog.THRUSTER:
						wa = 0.0
						ww = a * 0.1
					ModuleCatalog.COMMANDER:
						wa = a * 4.0
					ModuleCatalog.TURRET, ModuleCatalog.RADAR, ModuleCatalog.ENGINE_ROOM, ModuleCatalog.ANTENNA:
						wa = a * 0.3
				var last_a := w_all[w_all.size() - 1] if not w_all.is_empty() else 0.0
				var last_w := w_windows[w_windows.size() - 1] if not w_windows.is_empty() else 0.0
				w_all.append(last_a + ww)
				w_windows.append(last_w + wa)
				total_area += a
				var key := "%d:%d" % [mi, tf[int(i / 3.0)]]
				if not _faces.has(key):
					_faces[key] = {"key": key, "m": mi, "area": 0.0, "csum": Vector3.ZERO, "n": normals[normals.size() - 1], "lo": t[i], "hi": t[i]}
				var f: Dictionary = _faces[key]
				f["area"] += a
				f["csum"] += (t[i] + t[i + 1] + t[i + 2]) / 3.0 * a
				for k in 3:
					f["lo"] = (f["lo"] as Vector3).min(t[i + k])
					f["hi"] = (f["hi"] as Vector3).max(t[i + k])
		idx.build(soup)
		reach = maxf(d.extent_length() * 1.2, 10.0)
		for key in _faces:
			var f: Dictionary = _faces[key]
			f["c"] = (f["csum"] as Vector3) / maxf(f["area"], 0.0001)
			var ext: Vector3 = (f["hi"] as Vector3) - (f["lo"] as Vector3)
			var nn: Vector3 = f["n"]
			# width along the face's own "right" axis
			f["width"] = absf(ext.dot(DetailCatalog.frame(nn, 0.0).x))

	func pick(rng: RandomNumberGenerator, cum: PackedFloat64Array) -> int:
		if cum.is_empty() or cum[cum.size() - 1] <= 0.0:
			return -1
		var x := rng.randf() * cum[cum.size() - 1]
		var lo := 0
		var hi := cum.size() - 1
		while lo < hi:
			var mid := int((lo + hi) * 0.5)
			if cum[mid] < x:
				lo = mid + 1
			else:
				hi = mid
		return lo

	func random_point(rng: RandomNumberGenerator, tri: int) -> Vector3:
		var a := idx.corner(tri, 0)
		var b := idx.corner(tri, 1)
		var c := idx.corner(tri, 2)
		var r1 := sqrt(rng.randf())
		var r2 := rng.randf()
		return a * (1.0 - r1) + b * (r1 * (1.0 - r2)) + c * (r1 * r2)

	## Is there open space above point `p` (so a detail there can be seen from outside)? Checks a limited distance.
	func exposed(p: Vector3, n: Vector3, u: float) -> bool:
		return idx.first_hit(p + n * 0.03 * u, n, minf(reach, u * 30.0)) == INF

	## Snaps a point near the surface onto it: shoots a ray down from `reach` above `q`. {} when there is no
	## matching surface (the end of a plane) so rows of windows stop at edges.
	func project(q: Vector3, n: Vector3, above: float) -> Dictionary:
		var t := idx.first_hit(q + n * above, -n, above * 2.0)
		if t == INF:
			return {}
		var tri := idx.last_tri
		if tri < 0 or tri >= normals.size():
			return {}
		var nn: Vector3 = normals[tri]
		if nn.dot(n) < 0.97:
			return {}
		var p := q + n * above - n * t
		if not exposed(p, nn, above):
			return {}
		return {"p": p, "n": nn, "tri": tri}

	## Faces (of any module) whose normal points within `cos_min` of `dir`, largest first.
	func faces_facing(dir: Vector3, cos_min: float) -> Array:
		var out: Array = []
		for key in _faces:
			var f: Dictionary = _faces[key]
			if (f["n"] as Vector3).dot(dir) >= cos_min:
				out.append(f)
		out.sort_custom(func(a, b): return a["area"] > b["area"])
		return out

	func best_face_of(mi: int) -> Dictionary:
		var best := {}
		var best_a := 0.0
		for key in _faces:
			var f: Dictionary = _faces[key]
			if f["m"] == mi and f["area"] > best_a:
				best_a = f["area"]
				best = f
		return best
