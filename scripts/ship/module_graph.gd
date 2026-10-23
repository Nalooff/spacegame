class_name ModuleGraph
extends RefCounted
## Which modules are physically connected? Two modules are connected when they SHARE A VERTEX (that covers shared
## vertices, shared edges and shared faces, because edges and faces are made of vertices).
## A module that has no path to a commander through such links is cut off: it is destroyed / detached.
##
## Built once per ship (linear in the number of face corners, so it is done in the worker thread for big ships).
## Asking for the components afterwards costs only O(modules + links).

## Modules that merely TOUCH or overlap (their surfaces meet, even without a shared vertex) are connected too:
## the decimated hulls of both are tested with ConvexOverlap (GJK) with a small tolerance.
const CONTACT_MARGIN := 0.04
const CONTACT_POINTS := 56

## adj[i] = PackedInt32Array of the modules that share at least one vertex with module i.
var adj: Array[PackedInt32Array] = []


## `hull_ids` (optional) = the per-module point ids the ship already picked for its collision hulls: reusing them saves a
## full scan of every vertex (matters for ships with millions of vertices).
static func build(d: ShipDesign, hull_ids: Array = []) -> ModuleGraph:
	var g := ModuleGraph.new()
	var n := d.modules.size()
	var owner := PackedInt32Array()          # vertex id -> first module that used it
	owner.resize(d.vertices.size())
	owner.fill(-1)
	var shared := {}                         # vertex id -> Array of modules (only for vertices used by 2+ modules)
	for mi in n:
		if d.modules[mi]["type"] == ModuleCatalog.LOOSE:
			continue
		var fs: FaceSet = d.modules[mi]["fs"]
		var ids := fs.ids
		for fi in fs.count():
			var size := fs.sizes[fi]
			if size == 0:
				continue
			var s := fs.starts[fi]
			for k in size:
				var id := ids[s + k]
				var o := owner[id]
				if o == -1:
					owner[id] = mi
				elif o != mi:
					var list: Variant = shared.get(id)
					if list == null:
						shared[id] = [o, mi]
					elif not (list as Array).has(mi):
						(list as Array).append(mi)
	var sets: Array[Dictionary] = []
	for i in n:
		sets.append({})
	for id in shared:
		var list: Array = shared[id]
		for a in list:
			for b in list:
				if a != b:
					sets[a][b] = true
	# --- contact: AABB test first (cheap), then GJK on the decimated hulls
	var pts: Array = []
	var lo: Array[Vector3] = []
	var hi: Array[Vector3] = []
	for mi in n:
		if d.modules[mi]["type"] == ModuleCatalog.LOOSE:
			pts.append(PackedVector3Array())
			lo.append(Vector3.ZERO)
			hi.append(Vector3.ZERO)
			continue
		var p := HullShapes.points(d, hull_ids[mi] if mi < hull_ids.size() else HullShapes.hull_ids(d, mi, CONTACT_POINTS))
		pts.append(p)
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for v in p:
			mn = mn.min(v)
			mx = mx.max(v)
		lo.append(mn)
		hi.append(mx)
	var m := Vector3.ONE * CONTACT_MARGIN
	for a in n:
		if (pts[a] as PackedVector3Array).is_empty():
			continue
		for b in range(a + 1, n):
			if (pts[b] as PackedVector3Array).is_empty() or sets[a].has(b):
				continue
			if lo[a].x > hi[b].x + m.x or lo[b].x > hi[a].x + m.x or lo[a].y > hi[b].y + m.y or lo[b].y > hi[a].y + m.y \
					or lo[a].z > hi[b].z + m.z or lo[b].z > hi[a].z + m.z:
				continue
			if ConvexOverlap.intersects(pts[a], pts[b], CONTACT_MARGIN):
				sets[a][b] = true
				sets[b][a] = true
	for i in n:
		g.adj.append(PackedInt32Array(sets[i].keys()))
	return g


## Connected groups of ALIVE modules (alive[i] != 0). Each group is an array of module indices.
func components(alive: PackedByteArray) -> Array[PackedInt32Array]:
	var seen := PackedByteArray()
	seen.resize(adj.size())
	var out: Array[PackedInt32Array] = []
	for start in adj.size():
		if alive[start] == 0 or seen[start] != 0:
			continue
		var group := PackedInt32Array()
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var m: int = stack.pop_back()
			group.append(m)
			for nb in adj[m]:
				if alive[nb] != 0 and seen[nb] == 0:
					seen[nb] = 1
					stack.append(nb)
		out.append(group)
	return out


## Modules that cannot reach any commander (design-time check used by ShipDesign.validate).
static func unreachable(d: ShipDesign) -> PackedInt32Array:
	var g := build(d)
	var alive := PackedByteArray()
	alive.resize(d.modules.size())
	for i in d.modules.size():
		alive[i] = 0 if d.modules[i]["type"] == ModuleCatalog.LOOSE else 1
	var lost := PackedInt32Array()
	for group in g.components(alive):
		var has_commander := false
		for m in group:
			if d.modules[m]["type"] == ModuleCatalog.COMMANDER:
				has_commander = true
				break
		if not has_commander:
			lost.append_array(group)
	return lost
