class_name ExhaustZone
extends RefCounted
## The "no-go zone" behind a thruster: a cone that starts at the nozzle and points the way the exhaust leaves
## (opposite to the push direction). Nothing else may sit in it:
##   * the builder refuses to save a ship that has a module inside a zone (ShipDesign.exhaust_errors),
##   * if it happens anyway (a hand-edited file), the module takes burn damage while the thruster fires (Ship).
## Tune the numbers in Data (EXHAUST_*).

## {origin, axis, length, r0, tan_half} of thruster module `mi` (design space).
static func zone(d: ShipDesign, mi: int) -> Dictionary:
	var push: Vector3 = (d.modules[mi]["dir"] as Vector3).normalized()
	var axis := -push                          # exhaust flies this way
	var centre := d.module_centroid(mi)
	var reach := 0.0                           # how far the module extends along the exhaust direction
	for p in d.module_points(mi):
		reach = maxf(reach, (p - centre).dot(axis))
	var power := float(d.modules[mi]["power"])
	return {"origin": centre + axis * reach, "axis": axis,
		"length": Data.EXHAUST_BASE_LENGTH + Data.EXHAUST_LENGTH_PER_POWER * power,
		"r0": Data.EXHAUST_START_RADIUS, "tan_half": tan(deg_to_rad(Data.EXHAUST_HALF_ANGLE))}


static func contains(z: Dictionary, p: Vector3) -> bool:
	var rel := p - (z["origin"] as Vector3)
	var along := rel.dot(z["axis"])
	if along < 0.0 or along > float(z["length"]):
		return false
	var radial := (rel - (z["axis"] as Vector3) * along).length()
	return radial <= float(z["r0"]) + along * float(z["tan_half"])


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
