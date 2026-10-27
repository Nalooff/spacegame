class_name ConvexOverlap
extends RefCounted
## Do two convex point clouds touch or overlap? (GJK, boolean version: it only needs a "support point" function,
## so no hull faces have to be computed.) `margin` makes "almost touching" count too.
## Used for module connectivity (ModuleGraph): modules that touch are attached to each other.

static func intersects(a: PackedVector3Array, b: PackedVector3Array, margin: float = 0.0) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var simplex: Array[Vector3] = []
	var dir := Vector3.RIGHT
	var first := _support(a, b, dir, margin)
	simplex.append(first)
	dir = -first
	for _i in 48:
		if dir.length_squared() < 1e-14:
			return true
		var p := _support(a, b, dir, margin)
		if p.dot(dir) < 0.0:
			return false          # the new point did not pass the origin: the shapes are apart
		simplex.push_front(p)
		var state := [dir]
		if _evolve(simplex, state):
			return true
		dir = state[0]
	return true                   # did not separate in 48 steps: treat as touching


## Farthest point of (a - b) along `d`; `margin` fattens both shapes.
static func _support(a: PackedVector3Array, b: PackedVector3Array, d: Vector3, margin: float) -> Vector3:
	var best_a := a[0]
	var best := best_a.dot(d)
	for p in a:
		var v := p.dot(d)
		if v > best:
			best = v
			best_a = p
	var nd := -d
	var best_b := b[0]
	best = best_b.dot(nd)
	for p in b:
		var v := p.dot(nd)
		if v > best:
			best = v
			best_b = p
	var n := d.normalized()
	return best_a - best_b + n * (2.0 * margin)


static func _same(a: Vector3, b: Vector3) -> bool:
	return a.dot(b) > 0.0


## Reduce the simplex to the part nearest the origin and pick the next direction. true = origin inside.
static func _evolve(s: Array[Vector3], state: Array) -> bool:
	match s.size():
		2:
			return _line(s, state)
		3:
			return _triangle(s, state)
	return _tetra(s, state)


static func _line(s: Array[Vector3], state: Array) -> bool:
	var a := s[0]
	var b := s[1]
	var ab := b - a
	var ao := -a
	if _same(ab, ao):
		state[0] = ab.cross(ao).cross(ab)
	else:
		s.clear()
		s.append(a)
		state[0] = ao
	return false


static func _triangle(s: Array[Vector3], state: Array) -> bool:
	var a := s[0]
	var b := s[1]
	var c := s[2]
	var ab := b - a
	var ac := c - a
	var ao := -a
	var abc := ab.cross(ac)
	if _same(abc.cross(ac), ao):
		if _same(ac, ao):
			s.clear()
			s.append_array([a, c])
			state[0] = ac.cross(ao).cross(ac)
			return false
		s.clear()
		s.append_array([a, b])
		return _line(s, state)
	if _same(ab.cross(abc), ao):
		s.clear()
		s.append_array([a, b])
		return _line(s, state)
	if _same(abc, ao):
		state[0] = abc
	else:
		s.clear()
		s.append_array([a, c, b])
		state[0] = -abc
	return false


static func _tetra(s: Array[Vector3], state: Array) -> bool:
	var a := s[0]
	var b := s[1]
	var c := s[2]
	var d := s[3]
	var ab := b - a
	var ac := c - a
	var ad := d - a
	var ao := -a
	var abc := ab.cross(ac)
	var acd := ac.cross(ad)
	var adb := ad.cross(ab)
	if _same(abc, ao):
		s.clear()
		s.append_array([a, b, c])
		return _triangle(s, state)
	if _same(acd, ao):
		s.clear()
		s.append_array([a, c, d])
		return _triangle(s, state)
	if _same(adb, ao):
		s.clear()
		s.append_array([a, d, b])
		return _triangle(s, state)
	return true
