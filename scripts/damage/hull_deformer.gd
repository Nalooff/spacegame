class_name HullDeformer
extends RefCounted
## Dents a hull: ADDS vertices where the impact is (so the surface can really bend), pushes the vertices
## near the impact inward, and keeps the module's mass sums correct.
##
## Everything is LOCAL: only faces near the impact are looked at (via HullIndex), so the cost does not
## depend on how many vertices the ship has. It is also DETERMINISTIC: every player runs the same call
## with the same numbers and gets the same mesh, so only the impact (point, direction, depth, radius)
## is sent over the network, never the vertices.
##
## Steps of dent():
##   1. refine   split long edges near the impact (new vertex in the middle of the edge; the neighbour faces,
##               also of other modules, get the same vertex so no crack opens), then cut big faces into smaller
##               ones around a new centre vertex. Repeats until faces near the impact are smaller than
##               radius / 3, so the dent has enough points to bend smoothly.
##   2. push     vertices within `radius` move along `direction`, strongest at the centre (smooth falloff).
##   3. sums     the volume / centre / inertia sums of every touched module are corrected by "new faces - old faces".

const MAX_PASSES := 4
const MAX_NEW_FACES := 4000        # safety limit per dent
const MAX_WORK_FACES := 500        # faces cut per refine pass (= MAX_NEW_FACES / 8)

## Result: { "changed": {module: PackedInt32Array of alive face indices near the impact},
##           "new_vertices": int,
##           "moved": PackedInt32Array (vertex ids that were pushed), "moved_from": PackedVector3Array (where they were) }
static func dent(d: ShipDesign, idx: Array, mi: int, p: Vector3, dir: Vector3, depth: float, radius: float) -> Dictionary:
	var target_edge := maxf(radius / Data.DENT_DETAIL, Data.DENT_MIN_EDGE)
	var query_r := radius * 1.3
	var vertices_before := d.vertices.size()
	var ctx := {"killed": {}, "created": []}   # face bookkeeping for the mass sums
	# --- 1. refine
	for pass_i in MAX_PASSES:
		if not _refine_pass(d, idx, mi, p, query_r, target_edge, ctx):
			break
	var delta := {}   # module -> PackedFloat64Array(8) change of the sums
	for m in d.modules.size():
		delta[m] = PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0])
	for key in ctx["killed"]:
		_add_face_sums(d, idx, delta, key.x, key.y, ctx["killed"][key], -1.0)
	for key in ctx["created"]:
		var mfs: FaceSet = d.modules[key.x]["fs"]
		var size: int = mfs.sizes[key.y]
		if size == 0:
			size = ctx["killed"].get(key, 0) # created and cut again in a later pass
		_add_face_sums(d, idx, delta, key.x, key.y, size, 1.0)
	# --- 2. push (sums of the touched faces before and after the move)
	var touched := {}
	for m in d.modules.size():
		touched[m] = (idx[m] as HullIndex).faces_near(p, radius)
		for fi in touched[m]:
			_add_face_sums(d, idx, delta, m, fi, (d.modules[m]["fs"] as FaceSet).sizes[fi], -1.0)
	var fs: FaceSet = d.modules[mi]["fs"]
	var index: HullIndex = idx[mi]
	var seen := {}
	var moved := PackedInt32Array()
	var moved_from := PackedVector3Array()
	for fi in touched[mi]:
		var s := fs.starts[fi]
		for k in fs.sizes[fi]:
			var id := fs.ids[s + k]
			if seen.has(id):
				continue
			seen[id] = true
			var v := d.vertices[id]
			var dist := v.distance_to(p)
			if dist >= radius:
				continue
			var w := 1.0 - dist / radius
			var disp := dir * depth * w * w
			var cap := 0.45 * v.distance_to(index.centroid) # never through the middle of the module
			if disp.length() > cap:
				disp = disp.normalized() * cap
			d.vertices[id] = v + disp
			moved.append(id)
			moved_from.append(v)
	for m in d.modules.size():
		for fi in touched[m]:
			_add_face_sums(d, idx, delta, m, fi, (d.modules[m]["fs"] as FaceSet).sizes[fi], 1.0)
		(idx[m] as HullIndex).drift += depth
	# --- 3. apply the sum changes, list the faces that changed
	var changed := {}
	for m in d.modules.size():
		var sums := d.module_sums(m)
		for i in 8:
			sums[i] += delta[m][i]
		d.modules[m]["sums"] = sums
		changed[m] = (idx[m] as HullIndex).faces_near(p, query_r)
	return {"changed": changed, "new_vertices": d.vertices.size() - vertices_before, "moved": moved, "moved_from": moved_from}


static func _add_face_sums(d: ShipDesign, idx: Array, delta: Dictionary, m: int, fi: int, size: int, factor: float) -> void:
	if size < 3:
		return
	var fs: FaceSet = d.modules[m]["fs"]
	ShipDesign.accumulate_face(d.vertices, fs.ids, fs.starts[fi], size, (idx[m] as HullIndex).centroid, delta[m], factor)


## One round of "split long edges, then cut faces". Returns false if nothing needed refining.
static func _refine_pass(d: ShipDesign, idx: Array, mi: int, p: Vector3, r: float, h: float, ctx: Dictionary) -> bool:
	var fs: FaceSet = d.modules[mi]["fs"]
	var index: HullIndex = idx[mi]
	# faces to refine: near the impact and with an edge longer than h
	var work: Array[int] = []
	for fi in index.faces_near(p, r):
		if _needs_refining(d, fs, fi, p, r, h):
			work.append(fi)
	if work.is_empty():
		return false
	if work.size() > MAX_WORK_FACES:
		work.resize(MAX_WORK_FACES) # safety limit
	var work_set := {}
	for fi in work:
		work_set[fi] = true
	# --- which edges get a middle vertex
	var mids := {}          # edge key -> new vertex id
	var longest := h
	for fi in work:
		var s := fs.starts[fi]
		var n := fs.sizes[fi]
		for k in n:
			var a := fs.ids[s + k]
			var b := fs.ids[s + (k + 1) % n]
			var edge_len := d.vertices[a].distance_to(d.vertices[b])
			if edge_len > h:
				var key := _edge_key(a, b)
				if not mids.has(key):
					d.vertices.append((d.vertices[a] + d.vertices[b]) * 0.5)
					mids[key] = d.vertices.size() - 1
					longest = maxf(longest, edge_len)
	# --- insert those vertices into EVERY face (of any module) that has one of the edges
	var rewritten_work := {}   # old work face index -> its new face index
	for m in d.modules.size():
		var mfs: FaceSet = d.modules[m]["fs"]
		var mindex: HullIndex = idx[m]
		for fi in mindex.faces_near(p, r + 2.0 * longest):
			var s := mfs.starts[fi]
			var n := mfs.sizes[fi]
			var loop := PackedInt32Array()
			var touched := false
			for k in n:
				var a := mfs.ids[s + k]
				var b := mfs.ids[s + (k + 1) % n]
				loop.append(a)
				var key := _edge_key(a, b)
				if mids.has(key):
					loop.append(mids[key])
					touched = true
			if not touched:
				continue
			var nf := _replace(ctx, m, mfs, mindex, fi, loop)
			if m == mi and work_set.has(fi):
				rewritten_work[fi] = nf
	# --- cut the work faces into smaller faces around a new centre vertex
	for old_fi in work:
		var fi: int = rewritten_work.get(old_fi, old_fi)
		_cut_face(d, ctx, mi, fs, index, fi)
	return true


static func _needs_refining(d: ShipDesign, fs: FaceSet, fi: int, p: Vector3, r: float, h: float) -> bool:
	var s := fs.starts[fi]
	var n := fs.sizes[fi]
	var longest := 0.0
	for k in n:
		longest = maxf(longest, d.vertices[fs.ids[s + k]].distance_to(d.vertices[fs.ids[s + (k + 1) % n]]))
	if longest <= h * 1.01:
		return false
	return face_distance(d.vertices, fs.ids, s, n, p) < r


## Distance from point p to the polygon (fan of triangles). A big face can be "near" even if its corners are far.
static func face_distance(vs: PackedVector3Array, ids: PackedInt32Array, start: int, n: int, p: Vector3) -> float:
	var best := INF
	var v0 := vs[ids[start]]
	for k in range(1, n - 1):
		best = minf(best, closest_on_triangle(v0, vs[ids[start + k]], vs[ids[start + k + 1]], p).distance_to(p))
	return best


## Closest point of triangle (a, b, c) to p (Ericson, Real-Time Collision Detection).
static func closest_on_triangle(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


## Replace face `fi` by faces that share a new centre vertex.
static func _cut_face(d: ShipDesign, ctx: Dictionary, mi: int, fs: FaceSet, index: HullIndex, fi: int) -> void:
	var loop := fs.face(fi)
	var n := loop.size()
	if n < 3:
		return
	var c := Vector3.ZERO
	for id in loop:
		c += d.vertices[id]
	c /= n
	d.vertices.append(c)
	var cid := d.vertices.size() - 1
	_kill(ctx, mi, fs, fi)
	if n == 8: # a quad whose 4 edges were all split: 4 quads (keeps the grid look)
		for i in 4:
			# corner, the middle after it, the new centre, the middle before the corner
			_append(ctx, mi, fs, index, PackedInt32Array([loop[2 * i], loop[2 * i + 1], cid, loop[(2 * i + 7) % 8]]))
	else:
		for i in n:
			_append(ctx, mi, fs, index, PackedInt32Array([loop[i], loop[(i + 1) % n], cid]))


static func _edge_key(a: int, b: int) -> int:
	return (mini(a, b) << 32) | maxi(a, b)


# ---- face bookkeeping: every killed / created face is remembered for the mass sums
static func _kill(ctx: Dictionary, m: int, fs: FaceSet, fi: int) -> void:
	ctx["killed"][Vector2i(m, fi)] = fs.sizes[fi]
	fs.kill(fi)


static func _append(ctx: Dictionary, m: int, fs: FaceSet, index: HullIndex, loop: PackedInt32Array) -> int:
	var nf := fs.append(loop)
	index.add_face(nf)
	ctx["created"].append(Vector2i(m, nf))
	return nf


static func _replace(ctx: Dictionary, m: int, fs: FaceSet, index: HullIndex, fi: int, loop: PackedInt32Array) -> int:
	_kill(ctx, m, fs, fi)
	return _append(ctx, m, fs, index, loop)
