class_name RayIndex
extends RefCounted
## Tiny ray / triangle occlusion index for the builder ("is this vertex hidden behind the ship's surface?").
## Godot's TriangleMesh does not expose ray casts to GDScript, so this is our own: the triangles are sorted into a coarse
## 3D grid and a ray only tests the triangles of the cells it passes through.
##   var idx := RayIndex.new();  idx.build(mesh.get_faces());  idx.first_hit(origin, dir, max_distance)  # distance or INF

var _tris: PackedVector3Array = PackedVector3Array()   # 3 points per triangle
var _lo := Vector3.ZERO
var _cell := Vector3.ONE
var _n := 1
var _cells: Array = []                                 # cell index -> PackedInt32Array of triangle numbers
var _stamp: PackedInt32Array = PackedInt32Array()
var _tick := 0


func triangle_count() -> int:
	return int(_tris.size() / 3.0)


func build(faces: PackedVector3Array) -> void:
	_tris = faces
	var count := triangle_count()
	_cells.clear()
	if count == 0:
		return
	var lo := _tris[0]
	var hi := _tris[0]
	for p in _tris:
		lo = lo.min(p)
		hi = hi.max(p)
	_n = clampi(roundi(pow(float(count) / 3.0, 1.0 / 3.0)), 2, 24)
	_lo = lo - Vector3.ONE * 0.001
	_cell = ((hi - lo) + Vector3.ONE * 0.002) / float(_n)
	_cell = _cell.max(Vector3.ONE * 0.0001)
	_cells.resize(_n * _n * _n)
	for t in count:
		var a := _tris[t * 3]
		var b := _tris[t * 3 + 1]
		var c := _tris[t * 3 + 2]
		var cmin := _coord(a.min(b).min(c))
		var cmax := _coord(a.max(b).max(c))
		for x in range(cmin.x, cmax.x + 1):
			for y in range(cmin.y, cmax.y + 1):
				for z in range(cmin.z, cmax.z + 1):
					var i := (x * _n + y) * _n + z
					var list: PackedInt32Array = _cells[i] if _cells[i] != null else PackedInt32Array()
					list.append(t)
					_cells[i] = list                  # packed arrays are values: put the changed copy back
	_stamp.resize(count)
	_stamp.fill(0)
	_tick = 0


func _coord(p: Vector3) -> Vector3i:
	var q := (p - _lo) / _cell
	return Vector3i(clampi(int(floor(q.x)), 0, _n - 1), clampi(int(floor(q.y)), 0, _n - 1), clampi(int(floor(q.z)), 0, _n - 1))


## Distance along `dir` (unit length) to the first triangle within `max_distance`, INF when none.
func first_hit(origin: Vector3, dir: Vector3, max_distance: float) -> float:
	if _cells.is_empty():
		return INF
	_tick += 1
	var best := INF
	var step := minf(_cell.x, minf(_cell.y, _cell.z)) * 0.4
	var steps := mini(int(max_distance / step) + 1, 600)
	var last := Vector3i(-1, -1, -1)
	for s in steps + 1:
		var q := origin + dir * minf(s * step, max_distance)
		var c := _coord(q)
		if c == last:
			continue
		last = c
		var list: Variant = _cells[(c.x * _n + c.y) * _n + c.z]
		if list == null:
			continue
		for t in (list as PackedInt32Array):
			if _stamp[t] == _tick:
				continue
			_stamp[t] = _tick
			var d := _ray_triangle(origin, dir, _tris[t * 3], _tris[t * 3 + 1], _tris[t * 3 + 2])
			if d >= 0.0 and d < best and d <= max_distance:
				best = d
	return best


## Moeller-Trumbore, both sides. Returns the distance or -1.
static func _ray_triangle(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var h := d.cross(e2)
	var det := e1.dot(h)
	if absf(det) < 1e-12:
		return -1.0
	var inv := 1.0 / det
	var s := o - a
	var u := inv * s.dot(h)
	if u < 0.0 or u > 1.0:
		return -1.0
	var q := s.cross(e1)
	var v := inv * d.dot(q)
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := inv * e2.dot(q)
	return t if t > 1e-6 else -1.0
