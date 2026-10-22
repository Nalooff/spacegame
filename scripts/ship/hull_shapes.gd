class_name HullShapes
extends RefCounted
## Collision shape helper. A module's collision is the convex hull of a SMALL set of its vertices
## (at most `cap`), chosen as the far-out vertex of each cell of a coarse grid. The physics engine
## therefore never sees millions of points, and the shape follows the module if those vertices move.

## Vertex ids to use as hull points of module `mi`.
static func hull_ids(d: ShipDesign, mi: int, cap: int = 200) -> PackedInt32Array:
	var all := d.module_vertex_ids(mi)
	if all.size() <= cap:
		return all
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var c := Vector3.ZERO
	for id in all:
		var v := d.vertices[id]
		lo = lo.min(v)
		hi = hi.max(v)
		c += v
	c /= all.size()
	var size := (hi - lo).max(Vector3.ONE * 0.001)
	var dims := maxi(int(floor(pow(cap, 1.0 / 3.0))) + 2, 3)   # about cap cells touch the surface
	var best := {}      # cell -> [distance, id]
	for id in all:
		var v := d.vertices[id]
		var r := ((v - lo) / size * dims).floor()
		var key := clampi(int(r.x), 0, dims - 1) + clampi(int(r.y), 0, dims - 1) * dims + clampi(int(r.z), 0, dims - 1) * dims * dims
		var dist := v.distance_squared_to(c)
		var cur: Variant = best.get(key)
		if cur == null or dist > cur[0]:
			best[key] = [dist, id]
	var out := PackedInt32Array()
	for key in best:
		out.append(best[key][1])
	return out


static func points(d: ShipDesign, ids: PackedInt32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for id in ids:
		out.append(d.vertices[id])
	return out
