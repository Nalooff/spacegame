class_name Primitives
extends RefCounted
## Starting shapes for modules. Every primitive is returned as
##   {"verts": Array[Vector3], "faces": Array[PackedInt32Array]}
## in a unit size centred on (0,0,0); the builder scales it. Vertex indices in `faces` are LOCAL
## (0..verts.size()-1). A face is a polygon: a loop of vertex indices (3, 4, or more).
## Winding does not matter, the mesh code orients every face outward automatically.
##
## To add a new primitive: write a make_xxx() function and add its name to NAMES + the match below.

const NAMES: Array[String] = ["box", "wedge", "pyramid", "tetra", "cylinder", "cone", "sphere", "dome"]
## Primitives whose smoothness is controlled by the "segments" setting.
const ROUND_ONES: Array[String] = ["cylinder", "cone", "sphere", "dome"]


static func is_round(prim: String) -> bool:
	return ROUND_ONES.has(prim)


static func make(prim: String, segments: int = 12) -> Dictionary:
	segments = clampi(segments, 3, 32)
	match prim:
		"box": return make_box()
		"wedge": return make_wedge()
		"pyramid": return make_pyramid()
		"tetra": return make_tetra()
		"cylinder": return make_cylinder(segments)
		"cone": return make_cone(segments)
		"sphere": return make_sphere(segments, false)
		"dome": return make_sphere(segments, true)
	return make_box()


static func _face(ids: Array) -> PackedInt32Array:
	return PackedInt32Array(ids)


static func make_box() -> Dictionary:
	# bit0 = x, bit1 = y, bit2 = z   (0 = -1, 1 = +1)
	var verts: Array[Vector3] = []
	for i in 8:
		verts.append(Vector3(-1 if (i & 1) == 0 else 1, -1 if (i & 2) == 0 else 1, -1 if (i & 4) == 0 else 1))
	var faces: Array[PackedInt32Array] = [
		_face([0, 1, 3, 2]), _face([4, 5, 7, 6]),   # back (-z), front (+z)
		_face([0, 1, 5, 4]), _face([2, 3, 7, 6]),   # bottom, top
		_face([0, 2, 6, 4]), _face([1, 3, 7, 5]),   # left, right
	]
	return {"verts": verts, "faces": faces}


static func make_wedge() -> Dictionary:
	var verts: Array[Vector3] = [
		Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(-1, 1, 1),
	]
	var faces: Array[PackedInt32Array] = [
		_face([0, 1, 2]), _face([3, 4, 5]),
		_face([0, 1, 4, 3]), _face([1, 2, 5, 4]), _face([2, 0, 3, 5]),
	]
	return {"verts": verts, "faces": faces}


static func make_pyramid() -> Dictionary:
	var verts: Array[Vector3] = [
		Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1), Vector3(0, 1, 0),
	]
	var faces: Array[PackedInt32Array] = [
		_face([0, 1, 2, 3]),
		_face([0, 1, 4]), _face([1, 2, 4]), _face([2, 3, 4]), _face([3, 0, 4]),
	]
	return {"verts": verts, "faces": faces}


static func make_tetra() -> Dictionary:
	var verts: Array[Vector3] = [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(0, -1, 1), Vector3(0, 1, 0)]
	var faces: Array[PackedInt32Array] = [_face([0, 1, 2]), _face([0, 1, 3]), _face([1, 2, 3]), _face([2, 0, 3])]
	return {"verts": verts, "faces": faces}


## Axis along Y, radius 1, from y=-1 to y=+1.
static func make_cylinder(n: int) -> Dictionary:
	var verts: Array[Vector3] = []
	for ring in 2:
		for i in n:
			var a := TAU * i / n
			verts.append(Vector3(cos(a), -1.0 + 2.0 * ring, sin(a)))
	var faces: Array[PackedInt32Array] = []
	var bottom: Array = []
	var top: Array = []
	for i in n:
		bottom.append(i)
		top.append(n + i)
		var j := (i + 1) % n
		faces.append(_face([i, j, n + j, n + i]))
	faces.append(_face(bottom))
	faces.append(_face(top))
	return {"verts": verts, "faces": faces}


## Base ring at y=-1 (radius 1), tip at y=+1.
static func make_cone(n: int) -> Dictionary:
	var verts: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n
		verts.append(Vector3(cos(a), -1.0, sin(a)))
	verts.append(Vector3(0, 1, 0))
	var faces: Array[PackedInt32Array] = []
	var base: Array = []
	for i in n:
		base.append(i)
		faces.append(_face([i, (i + 1) % n, n]))
	faces.append(_face(base))
	return {"verts": verts, "faces": faces}


## Low-poly UV sphere (radius 1). `half` = true gives a dome: upper half + flat base ring.
static func make_sphere(n: int, half: bool) -> Dictionary:
	var steps := maxi(n >> 1, 4)                      # latitude steps from pole to pole
	if steps % 2 == 1:
		steps += 1                                   # even, so the equator is exactly a ring
	var ring_rows := (steps >> 1) if half else steps - 1
	var verts: Array[Vector3] = [Vector3(0, 1, 0)]   # index 0 = north pole
	for r in range(1, ring_rows + 1):
		var lat := PI * r / steps
		for i in n:
			var a := TAU * i / n
			verts.append(Vector3(sin(lat) * cos(a), cos(lat), sin(lat) * sin(a)))
	var faces: Array[PackedInt32Array] = []
	for i in n:                                      # cap around the north pole
		faces.append(_face([0, 1 + i, 1 + (i + 1) % n]))
	for r in range(0, ring_rows - 1):                # quads between neighbouring rings
		for i in n:
			var a := 1 + r * n + i
			var b := 1 + r * n + (i + 1) % n
			faces.append(_face([a, a + n, b + n, b]))
	if half:
		var base: Array = []
		for i in n:
			base.append(1 + (ring_rows - 1) * n + i)
		faces.append(_face(base))                    # flat bottom of the dome
	else:
		verts.append(Vector3(0, -1, 0))
		var south := verts.size() - 1
		for i in n:                                  # cap around the south pole
			var a := 1 + (ring_rows - 1) * n + i
			var b := 1 + (ring_rows - 1) * n + (i + 1) % n
			faces.append(_face([a, south, b]))
	return {"verts": verts, "faces": faces}
