class_name MeshOps
extends RefCounted
## Editing operations on a module's polygon mesh (what the builder's tool buttons call).
## Everything here is "static": MeshOps.extrude_faces(design, module, [faces]).
## They work on plain arrays of faces (design.faces_array(mi)) and store them back with design.set_faces_array(mi, faces).


## "Add vertex on edge": puts a new vertex in the middle of edge (a, b) of module `mi`.
## The faces touching the edge gain one corner, so the shape does not change until you move the new vertex.
## Returns the new vertex id, or -1 if the module has no such edge.
static func subdivide_edge(d: ShipDesign, mi: int, a: int, b: int) -> int:
	var faces: Array = d.faces_array(mi)
	var new_id := -1
	for fi in faces.size():
		var ids: PackedInt32Array = faces[fi]
		var k := _edge_position(ids, a, b)
		if k < 0:
			continue
		if new_id < 0:
			d.vertices.append((d.vertices[a] + d.vertices[b]) * 0.5)
			new_id = d.vertices.size() - 1
		ids.insert(k + 1, new_id)
		faces[fi] = ids
	d.set_faces_array(mi, faces)
	return new_id


## "Extrude": copies the selected faces' vertices, joins old and new outline with side faces.
## The selected faces keep their indices but now sit on the NEW vertices (so you can grab them
## right away). Returns the new vertex ids.
static func extrude_faces(d: ShipDesign, mi: int, face_indices: Array[int]) -> PackedInt32Array:
	var faces: Array = d.faces_array(mi)
	var copy_of := {}                     # old vertex id -> new vertex id
	for fi in face_indices:
		for id in (faces[fi] as PackedInt32Array):
			if not copy_of.has(id):
				d.vertices.append(d.vertices[id])
				copy_of[id] = d.vertices.size() - 1
	# an edge used by only ONE selected face is on the border of the selection -> needs a side wall
	var edge_uses := {}
	var edge_dir := {}                    # remembers the edge direction as it appears in the face
	for fi in face_indices:
		var ids: PackedInt32Array = faces[fi]
		for k in ids.size():
			var a := ids[k]
			var b := ids[(k + 1) % ids.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			edge_uses[key] = edge_uses.get(key, 0) + 1
			edge_dir[key] = Vector2i(a, b)
	for fi in face_indices:
		var ids: PackedInt32Array = faces[fi]
		var moved := PackedInt32Array()
		for id in ids:
			moved.append(copy_of[id])
		faces[fi] = moved
	for key in edge_uses:
		if edge_uses[key] == 1:
			var e: Vector2i = edge_dir[key]
			faces.append(PackedInt32Array([e.x, e.y, copy_of[e.y], copy_of[e.x]]))
	d.set_faces_array(mi, faces)
	return PackedInt32Array(copy_of.values())


## "Connect vertices": cuts the face that contains both vertices into two faces, which
## adds an edge (a line) between them. Returns false if no face contains both (or they are neighbours).
static func connect_vertices(d: ShipDesign, mi: int, a: int, b: int) -> bool:
	var faces: Array = d.faces_array(mi)
	for fi in faces.size():
		var ids: PackedInt32Array = faces[fi]
		var ia := ids.find(a)
		var ib := ids.find(b)
		if ia < 0 or ib < 0:
			continue
		var n := ids.size()
		var gap := (ib - ia + n) % n
		if gap == 1 or gap == n - 1:
			continue                      # already neighbours: an edge exists
		var first := PackedInt32Array()
		var k := ia
		while true:
			first.append(ids[k])
			if k == ib:
				break
			k = (k + 1) % n
		var second := PackedInt32Array()
		k = ib
		while true:
			second.append(ids[k])
			if k == ia:
				break
			k = (k + 1) % n
		faces[fi] = first
		faces.append(second)
		d.set_faces_array(mi, faces)
		return true
	return false


## Removes faces (indices) from module `mi` and cleans unused vertices.
## Returns true if the module still has faces, false if it is now empty.
static func delete_faces(d: ShipDesign, mi: int, face_indices: Array[int]) -> bool:
	var faces: Array = d.faces_array(mi)
	var sorted := face_indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for fi in sorted:
		faces.remove_at(fi)
	d.set_faces_array(mi, faces)
	d.prune_vertices()
	return not faces.is_empty()


## Indices of faces of module `mi` that use ALL the given vertices (1 id = vertex, 2 ids = edge).
static func faces_using(d: ShipDesign, mi: int, vertex_ids: Array[int]) -> Array[int]:
	var out: Array[int] = []
	var faces: Array = d.faces_array(mi)
	for fi in faces.size():
		var ids: PackedInt32Array = faces[fi]
		var all := true
		for v in vertex_ids:
			if not ids.has(v):
				all = false
				break
		if all:
			out.append(fi)
	return out


static func _edge_position(ids: PackedInt32Array, a: int, b: int) -> int:
	for k in ids.size():
		var u := ids[k]
		var v := ids[(k + 1) % ids.size()]
		if (u == a and v == b) or (u == b and v == a):
			return k
	return -1


## "Bevel": replaces the edge (a, b) of module `mi` by a flat strip `width` metres wide (Blender's bevel with one segment).
## Each end of the edge is split into two vertices that slide along the neighbouring edges of the two faces on either side;
## the faces that meet at the corner get both vertices in the right order, so the surface stays closed when at most
## 3 faces meet at the corner (boxes, wedges, ...).
## Returns the two new long edges (so they can be beveled again = "round"), or [] when the edge cannot be beveled.
static func bevel_edge(d: ShipDesign, mi: int, a: int, b: int, width: float) -> Array[Vector2i]:
	var faces: Array = d.faces_array(mi)
	var f1 := -1      # face where the loop runs a -> b
	var f2 := -1      # face where the loop runs b -> a
	for fi in faces.size():
		var ids: PackedInt32Array = faces[fi]
		var n := ids.size()
		for k in n:
			if ids[k] == a and ids[(k + 1) % n] == b:
				f1 = fi
			elif ids[k] == b and ids[(k + 1) % n] == a:
				f2 = fi
	if f1 < 0 or f2 < 0:
		return []
	var l1: PackedInt32Array = faces[f1]
	var l2: PackedInt32Array = faces[f2]
	var ia := l1.find(a)
	var pa: int = l1[(ia - 1 + l1.size()) % l1.size()]          # neighbour of a in face 1 (not b)
	var pb: int = l1[(l1.find(b) + 1) % l1.size()]              # neighbour of b in face 1 (not a)
	var jb := l2.find(b)
	var qb: int = l2[(jb - 1 + l2.size()) % l2.size()]          # neighbour of b in face 2
	var qa: int = l2[(l2.find(a) + 1) % l2.size()]              # neighbour of a in face 2
	var w := minf(width, 0.45 * minf(minf(d.vertices[a].distance_to(d.vertices[pa]), d.vertices[a].distance_to(d.vertices[qa])),
		minf(d.vertices[b].distance_to(d.vertices[pb]), d.vertices[b].distance_to(d.vertices[qb]))))
	if w < 0.005:
		return []
	var a1 := _slide(d, a, pa, w)
	var a2 := _slide(d, a, qa, w)
	var b1 := _slide(d, b, pb, w)
	var b2 := _slide(d, b, qb, w)
	for fi in faces.size():
		var ids: PackedInt32Array = faces[fi]
		if fi == f1:
			ids[ids.find(a)] = a1
			ids[ids.find(b)] = b1
		elif fi == f2:
			ids[ids.find(a)] = a2
			ids[ids.find(b)] = b2
		else:
			ids = _split_corner(ids, a, a1, a2, pa, qa)
			ids = _split_corner(ids, b, b1, b2, pb, qb)
		faces[fi] = ids
	faces.append(PackedInt32Array([b1, a1, a2, b2]))
	d.set_faces_array(mi, faces)
	d.fix_winding(mi)
	return [Vector2i(a1, b1), Vector2i(a2, b2)]


static func _slide(d: ShipDesign, from: int, toward: int, w: float) -> int:
	var dir := (d.vertices[toward] - d.vertices[from]).normalized()
	d.vertices.append(d.vertices[from] + dir * w)
	return d.vertices.size() - 1


## In a third face that has corner `v`: replace it by the two new vertices, ordered so each sits next to the neighbour it slid towards.
static func _split_corner(ids: PackedInt32Array, v: int, v1: int, v2: int, n1: int, n2: int) -> PackedInt32Array:
	var k := ids.find(v)
	if k < 0:
		return ids
	var n := ids.size()
	var prev := ids[(k - 1 + n) % n]
	var next := ids[(k + 1) % n]
	var out := PackedInt32Array()
	var first := v1
	var second := v2
	if prev == n2 or next == n1:
		first = v2
		second = v1
	for i in n:
		if i == k:
			out.append(first)
			out.append(second)
		else:
			out.append(ids[i])
	return out
