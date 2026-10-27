class_name ExhaustZone
extends RefCounted
## The "no-go zone" behind a thruster: a cone that starts at the nozzle and points the way the exhaust leaves
## (opposite to the push direction). Nothing else may sit in it:
##   * the builder refuses to save a ship that has a module inside a zone (ShipDesign.exhaust_errors),
##   * if it happens anyway (a hand-edited file), the module takes burn damage while the thruster fires (Ship).
## Tune the numbers in Data (EXHAUST_*).
## Heat: thrust (N) x heat_per_n (W/N) of the preset = watts; every MW makes the zone Data.EXHAUST_LENGTH_PER_MW metres longer.

## {origin, axis, u, v, outline (2D, in the u/v plane), length, radius} of thruster module `mi` (design space).
## The zone is NOT a cone: it is the OPENING of the thruster (the outline of its rear end, seen along the exhaust)
## pushed straight backwards for `length` metres. A huge thruster with a small nozzle only blocks a small tube, so
## something may sit right beside it; a wide nozzle blocks a wide tube.
static func zone(d: ShipDesign, mi: int) -> Dictionary:
	var push: Vector3 = (d.modules[mi]["dir"] as Vector3).normalized()
	var axis := -push                          # exhaust flies this way
	var centre := d.module_centroid(mi)
	var pts := d.module_points(mi)
	var reach := 0.0                           # how far the module extends along the exhaust direction
	var back := 0.0                            # ... and against it
	for p in pts:
		var a := (p - centre).dot(axis)
		reach = maxf(reach, a)
		back = minf(back, a)
	var u := axis.cross(Vector3.UP)
	if u.length() < 0.01:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := axis.cross(u).normalized()
	# the nozzle = every vertex in the last slice of the module along the exhaust direction
	var slice := maxf(Data.EXHAUST_NOZZLE_SLICE_M, (reach - back) * Data.EXHAUST_NOZZLE_SLICE_FRACTION)
	var flat := PackedVector2Array()
	var radius := 0.05
	for p in pts:
		var rel := p - centre
		if reach - rel.dot(axis) <= slice:
			var q := Vector2(rel.dot(u), rel.dot(v))
			flat.append(q)
			radius = maxf(radius, q.length())
	var outline := Geometry2D.convex_hull(flat) if flat.size() >= 3 else PackedVector2Array([Vector2(-0.1, -0.1), Vector2(0.1, -0.1), Vector2(0.1, 0.1), Vector2(-0.1, 0.1)])
	if outline.size() > 1 and outline[0] == outline[outline.size() - 1]:
		outline.remove_at(outline.size() - 1)      # convex_hull repeats the first point
	var grown := Geometry2D.offset_polygon(outline, Data.EXHAUST_MARGIN)
	if not grown.is_empty():
		outline = grown[0]
	var heat_mw := d.thruster_power(mi) * d.stat(mi, "heat_per_n") / 1.0e6
	return {"origin": centre + axis * reach, "axis": axis, "u": u, "v": v, "outline": outline, "radius": radius + Data.EXHAUST_MARGIN,
		"length": minf(Data.EXHAUST_BASE_LENGTH + Data.EXHAUST_LENGTH_PER_MW * heat_mw, Data.EXHAUST_MAX_LENGTH)}


static func contains(z: Dictionary, p: Vector3) -> bool:
	var rel := p - (z["origin"] as Vector3)
	var along := rel.dot(z["axis"])
	if along < 0.0 or along > float(z["length"]):
		return false
	var q := Vector2(rel.dot(z["u"]), rel.dot(z["v"]))
	if q.length() > float(z["radius"]):
		return false                                   # cheap rejection before the polygon test
	return Geometry2D.is_point_in_polygon(q, z["outline"])


## [Vector2i(thruster module, blocking module)] for the whole design. Samples at most ~200 points per module.
## `hull_ids` (optional): the per-module point ids ShipDesign/Ship already picked (HullShapes.hull_ids(d, i, 200)).
static func conflicts(d: ShipDesign, hull_ids: Array = []) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var zones := {}
	for i in d.modules.size():
		if d.modules[i]["type"] == ModuleCatalog.THRUSTER:
			zones[i] = zone(d, i)
	if zones.is_empty():
		return out
	for j in d.modules.size():
		var t: String = d.modules[j]["type"]
		if t == ModuleCatalog.LOOSE:
			continue
		var pts := HullShapes.points(d, hull_ids[j] if j < hull_ids.size() else HullShapes.hull_ids(d, j, 200))
		for i in zones:
			if i == j:
				continue
			for p in pts:
				if contains(zones[i], p):
					out.append(Vector2i(i, j))
					break
	return out
