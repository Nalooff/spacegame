class_name HullIndex
extends RefCounted
## Spatial index of ONE module's faces, so a dent only touches the faces near the impact
## (instead of scanning millions of faces).
##
## Faces are put in a uniform grid cell by their FIRST vertex. A face bigger than a cell goes in
## `big` (always checked). Vertices move a little when ships get dented, so queries add `drift`
## (how far things may have moved since the index was built).

var design: ShipDesign
var module: int
var cell: float = 0.5
var grid: Dictionary = {}              # Vector3i -> Array of face indices (plain Arrays: appending is by reference)
var big: Array = []
var drift: float = 0.0                 # total dent depth applied since the index was built
var centroid: Vector3 = Vector3.ZERO   # module apex (fixed, see ShipDesign.module_sums)


static func build(d: ShipDesign, mi: int) -> HullIndex:
	var ix := HullIndex.new()
	ix.design = d
	ix.module = mi
	ix.rebuild()
	return ix


func rebuild() -> void:
	var fs: FaceSet = design.modules[module]["fs"]
	var sums := design.module_sums(module)
	centroid = Vector3(sums[8], sums[9], sums[10])
	# cell size: a few times the typical face size, never smaller than a dent
	var total := 0.0
	var samples := 0
	var step := maxi(int(fs.count() / 500.0), 1)
	for fi in range(0, fs.count(), step):
		if fs.sizes[fi] > 0:
			total += _extent(fs, fi)
			samples += 1
	cell = maxf(Data.DENT_BASE_RADIUS * 0.5, 2.5 * total / maxf(samples, 1))
	grid.clear()
	big = []
	drift = 0.0
	for fi in fs.count():
		if fs.sizes[fi] > 0:
			add_face(fi)


func _extent(fs: FaceSet, fi: int) -> float:
	var s := fs.starts[fi]
	var v0 := design.vertices[fs.ids[s]]
	var e := 0.0
	for k in range(1, fs.sizes[fi]):
		e = maxf(e, v0.distance_squared_to(design.vertices[fs.ids[s + k]]))
	return sqrt(e)


func _key(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))


## Register a face (also used for faces created by a dent).
func add_face(fi: int) -> void:
	var fs: FaceSet = design.modules[module]["fs"]
	if _extent(fs, fi) > cell:
		big.append(fi)
		return
	var key := _key(design.vertices[fs.ids[fs.starts[fi]]])
	var list: Variant = grid.get(key)
	if list == null:
		grid[key] = [fi]
	else:
		(list as Array).append(fi)


## Alive faces that MAY touch the ball (p, radius). A superset: the caller filters by exact distance.
func faces_near(p: Vector3, radius: float) -> PackedInt32Array:
	var fs: FaceSet = design.modules[module]["fs"]
	var out := PackedInt32Array()
	var r := radius + cell + drift
	var r2 := r * r
	var vs := design.vertices
	var ids := fs.ids
	var starts := fs.starts
	var sizes := fs.sizes
	var lo := _key(p - Vector3.ONE * r)
	var hi := _key(p + Vector3.ONE * r)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var list: Variant = grid.get(Vector3i(x, y, z))
				if list != null:
					for fi in (list as Array):
						# faces here are smaller than `cell`, so a face touching the ball has its first vertex within r
						if sizes[fi] > 0 and vs[ids[starts[fi]]].distance_squared_to(p) <= r2:
							out.append(fi)
	for fi in big:
		if fs.sizes[fi] > 0:
			out.append(fi)
	return out
