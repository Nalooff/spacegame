class_name DetailFit
extends RefCounted
## Keeps a flat detail STUCK to the ship like a decal: its whole rectangle (turned by its own angle) must lie on the
## flat surface it was put on. If it overhangs an edge (text longer than the plate, a stripe running off a corner)
## it is shrunk until it fits. Works on the triangles of the module the detail sits on.

const SAMPLES_X := [-0.5, -0.25, 0.0, 0.25, 0.5]
const SAMPLES_Y := [-0.5, 0.0, 0.5]


## `tris` = triangle corner list (3 per triangle) of the module under the detail. Returns false when not even a tiny
## version fits (the detail is not on a surface); `dt` is then left unchanged.
static func fit(dt: Dictionary, tris: PackedVector3Array) -> bool:
	var n: Vector3 = dt["n"]
	var p: Vector3 = dt["p"]
	var w: float = dt["w"]
	var h: float = dt["h"]
	var tol := maxf(0.05, minf(w, h) * 0.03)
	var good: Array = []
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var tn := (b - a).cross(c - a)
		if tn.length_squared() < 1.0e-10:
			continue
		if absf(tn.normalized().dot(n)) < 0.99 or absf((a - p).dot(n)) > tol:
			continue
		good.append([a, b, c])
	if good.is_empty():
		return false
	var fr := DetailCatalog.frame(n, float(dt["a"]))
	var stripe: bool = int(dt["k"]) == DetailCatalog.STRIPE
	for attempt in 16:
		var ok := true
		for sx in SAMPLES_X:
			for sy in SAMPLES_Y:
				if not _inside(p + fr.x * (w * sx) + fr.y * (h * sy), good):
					ok = false
					break
			if not ok:
				break
		if ok:
			dt["w"] = w
			dt["h"] = h
			return true
		w *= 0.85
		if not stripe:
			h *= 0.85
	return false


static func _inside(q: Vector3, good: Array) -> bool:
	for t in good:
		var a: Vector3 = t[0]
		var v0: Vector3 = (t[2] as Vector3) - a
		var v1: Vector3 = (t[1] as Vector3) - a
		var v2 := q - a
		var d00 := v0.dot(v0)
		var d01 := v0.dot(v1)
		var d11 := v1.dot(v1)
		var d20 := v2.dot(v0)
		var d21 := v2.dot(v1)
		var den := d00 * d11 - d01 * d01
		if absf(den) < 1.0e-12:
			continue
		var u := (d11 * d20 - d01 * d21) / den
		var v := (d00 * d21 - d01 * d20) / den
		if u >= -0.0005 and v >= -0.0005 and u + v <= 1.0005:
			return true
	return false


## Fits every flat detail that sits on a module; the ones that cannot be fitted are removed (`drop_failed`).
## Returns how many were shrunk or removed.
static func fit_all(d: ShipDesign, only_auto: bool, drop_failed: bool) -> int:
	var cache := {}
	var keep: Array[Dictionary] = []
	var changed := 0
	for dt in d.details:
		var m: int = dt["m"]
		var k: int = dt["k"]
		if m < 0 or m >= d.modules.size() or DetailCatalog.is_solid(k) or (only_auto and not dt["auto"]):
			keep.append(dt)
			continue
		if not cache.has(m):
			var tf := PackedInt32Array()
			cache[m] = d.module_tris(m, tf)
		var w0: float = dt["w"]
		var h0: float = dt["h"]
		if fit(dt, cache[m]):
			if not is_equal_approx(w0, dt["w"]) or not is_equal_approx(h0, dt["h"]):
				changed += 1
			keep.append(dt)
		elif drop_failed:
			changed += 1
		else:
			keep.append(dt)
	d.details = keep
	d.detail_rev += 1
	return changed
