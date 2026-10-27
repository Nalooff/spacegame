class_name ShipPlan
extends RefCounted
## THE SHIP PLAN: the emergency map of a ship, generated from its modules.
##
##   ROOMS      every Commander / Turret base / Radar module, and any module whose preset says kind "room"
##              (ShipDesign.is_room). Thrusters and antennas are NOT rooms by default: no corridor, no doorway (drawn on the plan only as an outline).
##   SPACES     Hull (and armor) modules. They are not rooms: they hold the CORRIDORS that join the rooms.
##   NODES      "h<m>" hub in the middle of space module m
##              "d<m>" door in the middle of room m
##              "j<a>_<b>" joint where two touching modules meet (a door in the wall)
##              "f<n>" free node the player drew
##   EDGES      corridor pieces between two nodes. Each lies INSIDE one module (`module`): if that module is flattened by
##              a dent (dead) or lost, the corridor is blocked. Damage lines can also block single edges (Ship).
##
## The corridors are generated automatically (generate()). The player can change them in the builder's plan view; those
## changes are stored in ShipDesign.plan as OVERRIDES on top of the generated plan, so they stay valid when modules move:
##   plan = {"removed": [edge keys], "free": {"f3": [x, y, z, module]}, "added": [[node key, node key], ...], "uid": int,
##           "doors": [[edge key, t], ...]}
## DOORS: every corridor that enters a room has a doorway in the room wall (drawn dotted: half open). The player can also put
## DOORS ON A CORRIDOR (bulkhead doors): `doors` = {edge: edge index, t: 0..1 position along the corridor from node a to node b}.
##
## Everything is deterministic: every peer builds the same node and edge order from the same design, so an edge index
## means the same corridor everywhere (Ship replicates corridor health per edge index).

const CORRIDOR_WIDTH := 1.1

var nodes: Array[Dictionary] = []       ## {key, pos: Vector3, module: int, kind: "hub"|"door"|"joint"|"free"}
var edges: Array[Dictionary] = []       ## {key, a, b (node indices), len, module (owner module), manual: bool}
var doors: Array[Dictionary] = []       ## corridor doors: {edge, t}
var rooms: PackedInt32Array = PackedInt32Array()
var spaces: PackedInt32Array = PackedInt32Array()
var _index: Dictionary = {}             ## node key -> node index
var _adj: Array = []
var _hull_pts: Dictionary = {}          ## module -> decimated hull points (lazy cache for the 'inside the ship' tests)                    ## node index -> Array of edge indices


# ---------------------------------------------------------------- generation
## `adj` (optional): ModuleGraph.adj. Built here when missing.
static func generate(d: ShipDesign, adj: Array[PackedInt32Array] = []) -> ShipPlan:
	var p := ShipPlan.new()
	if adj.is_empty():
		adj = ModuleGraph.build(d).adj
	var centroid: Array[Vector3] = []
	for mi in d.modules.size():
		centroid.append(d.module_centroid(mi) if d.modules[mi]["type"] != ModuleCatalog.LOOSE else Vector3.ZERO)
	for mi in d.modules.size():
		var t: String = d.modules[mi]["type"]
		if ModuleCatalog.CORRIDOR_TYPES.has(t):
			p.spaces.append(mi)
			p._add_node("h%d" % mi, centroid[mi], mi, "hub")
		elif d.is_room(mi):
			p.rooms.append(mi)
			p._add_node("d%d" % mi, centroid[mi], mi, "door")
	# space <-> space and room <-> space joints
	for a in d.modules.size():
		for b in adj[a]:
			if b <= a:
				continue
			var ta: String = d.modules[a]["type"]
			var tb: String = d.modules[b]["type"]
			var a_space := ModuleCatalog.CORRIDOR_TYPES.has(ta)
			var b_space := ModuleCatalog.CORRIDOR_TYPES.has(tb)
			var a_room := d.is_room(a)
			var b_room := d.is_room(b)
			if a_space and b_space:
				p._joint(d, a, b, "h%d" % a, "h%d" % b, a, b, centroid)
			elif a_space and b_room:
				p._joint(d, a, b, "h%d" % a, "d%d" % b, a, b, centroid)
			elif a_room and b_space:
				p._joint(d, a, b, "d%d" % a, "h%d" % b, a, b, centroid)
	# two rooms that touch need no corridor: a door in the shared wall (or a stair when they are on different decks)
	for a in p.rooms:
		for b in adj[a]:
			if b > a and d.is_room(b):
				p._joint(d, a, b, "d%d" % a, "d%d" % b, a, b, centroid)
	p._apply_overrides(d)
	p._finish()
	p._resolve_doors(d)
	return p


func _add_node(key: String, pos: Vector3, module: int, kind: String) -> int:
	if _index.has(key):
		return _index[key]
	nodes.append({"key": key, "pos": pos, "module": module, "kind": kind})
	_index[key] = nodes.size() - 1
	return nodes.size() - 1


## Door between touching modules a and b: a joint node on the wall, two edges (one in each module).
func _joint(d: ShipDesign, a: int, b: int, ka: String, kb: String, ma: int, mb: int, centroid: Array[Vector3]) -> void:
	var jkey := "j%d_%d" % [a, b]
	var j := _add_node(jkey, _contact_point(d, a, b, centroid), -1, "joint")
	_add_edge_between(_index[ka], j, ma, false)
	_add_edge_between(j, _index[kb], mb, false)


func _hull_of(d: ShipDesign, mi: int) -> PackedVector3Array:
	if not _hull_pts.has(mi):
		_hull_pts[mi] = HullShapes.points(d, HullShapes.hull_ids(d, mi, 64))
	return _hull_pts[mi]


## A point that lies in BOTH touching modules (so the door is in the wall and the corridor never leaves the ship):
## the corner of one module that sits inside the other, nearest to the middle of the other module.
func _contact_point(d: ShipDesign, a: int, b: int, centroid: Array[Vector3]) -> Vector3:
	# 1st choice: on the line between the two centres, where it is inside both modules (straight corridors, both legs inside)
	var ha := _hull_of(d, a)
	var hb := _hull_of(d, b)
	if not ha.is_empty() and not hb.is_empty():
		var hits: Array[Vector3] = []
		for k in 129:
			var q := centroid[a].lerp(centroid[b], k / 128.0)
			if ConvexOverlap.intersects(PackedVector3Array([q]), ha, 0.05) and ConvexOverlap.intersects(PackedVector3Array([q]), hb, 0.05):
				hits.append(q)
		if not hits.is_empty():
			return hits[int(hits.size() / 2.0)]
	var best := INF
	var out := Vector3.ZERO
	var found := false
	for pair in [[a, b], [b, a]]:
		var mine := _hull_of(d, pair[0])
		var other := _hull_of(d, pair[1])
		if other.is_empty():
			continue
		for v in mine:
			if ConvexOverlap.intersects(PackedVector3Array([v]), other, 0.06):
				var dist := v.distance_squared_to(centroid[pair[1]]) + v.distance_squared_to(centroid[pair[0]])
				if dist < best:
					best = dist
					out = v
					found = true
	if found:
		return out
	# no corner inside the other module: the middle of the closest pair of corners
	var pa := _closest_vertex(d, a, centroid[b])
	var pb := _closest_vertex(d, b, centroid[a])
	return (pa + pb) * 0.5


func _closest_vertex(d: ShipDesign, mi: int, target: Vector3) -> Vector3:
	var best := INF
	var out := target
	for v in d.module_points(mi):
		var dist := v.distance_squared_to(target)
		if dist < best:
			best = dist
			out = v
	return out


func _add_edge_between(a: int, b: int, module: int, manual: bool) -> void:
	if a == b:
		return
	var ka: String = nodes[a]["key"]
	var kb: String = nodes[b]["key"]
	var key := ka + "|" + kb if ka < kb else kb + "|" + ka
	edges.append({"key": key, "a": a, "b": b, "len": (nodes[a]["pos"] as Vector3).distance_to(nodes[b]["pos"]), "module": module, "manual": manual})


func _apply_overrides(d: ShipDesign) -> void:
	var plan: Dictionary = d.plan
	var removed: Array = plan.get("removed", [])
	if not removed.is_empty():
		var kept: Array[Dictionary] = []
		for e in edges:
			if not removed.has(e["key"]):
				kept.append(e)
		edges = kept
	var free: Dictionary = plan.get("free", {})
	for k in free:
		var f: Array = free[k]
		var fp := Vector3(f[0], f[1], f[2])
		if not inside_ship(d, fp):
			continue        # corridors can never leave the ship: a bend that is outside now (modules moved) is dropped
		_add_node(str(k), fp, int(f[3]), "free")
	for pair in plan.get("added", []):
		var ka := str(pair[0])
		var kb := str(pair[1])
		if not _index.has(ka) or not _index.has(kb):
			continue
		var a: int = _index[ka]
		var b: int = _index[kb]
		if not segment_inside(d, nodes[a]["pos"], nodes[b]["pos"]):
			continue        # ...and so is a corridor piece that would cross the outside
		var owner := int(nodes[a]["module"]) if int(nodes[a]["module"]) >= 0 else int(nodes[b]["module"])
		_add_edge_between(a, b, owner, true)


## Corridor doors of the overrides -> edge indices (a door on a corridor that no longer exists is dropped).
func _resolve_doors(d: ShipDesign) -> void:
	doors.clear()
	for pair in d.plan.get("doors", []):
		var ei := edge_index(str(pair[0]))
		if ei >= 0:
			doors.append({"edge": ei, "t": clampf(float(pair[1]), 0.05, 0.95)})


func doors_on(ei: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dd in doors:
		if dd["edge"] == ei:
			out.append(dd)
	return out


## Sort for a deterministic order, drop duplicates and build the adjacency lists.
func _finish() -> void:
	edges.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["key"]) < str(y["key"]))
	var seen := {}
	var unique: Array[Dictionary] = []
	for e in edges:
		if seen.has(e["key"]):
			continue
		seen[e["key"]] = true
		unique.append(e)
	edges = unique
	_adj.clear()
	for i in nodes.size():
		_adj.append([])
	for ei in edges.size():
		_adj[edges[ei]["a"]].append(ei)
		_adj[edges[ei]["b"]].append(ei)


# ---------------------------------------------------------------- inside the ship
## Is point `p` (ship space) inside one of the modules? Corridors may only exist where there is hull or a room.
func inside_ship(d: ShipDesign, p: Vector3) -> bool:
	for mi in d.modules.size():
		if d.modules[mi]["type"] == ModuleCatalog.LOOSE or d.modules[mi]["type"] == ModuleCatalog.BARREL:
			continue
		if not _hull_pts.has(mi):
			_hull_pts[mi] = HullShapes.points(d, HullShapes.hull_ids(d, mi, 64))
		var pts: PackedVector3Array = _hull_pts[mi]
		if pts.is_empty():
			continue
		if ConvexOverlap.intersects(PackedVector3Array([p]), pts, 0.06):
			return true
	return false


## Does the straight corridor from `a` to `b` stay inside the ship all the way?
func segment_inside(d: ShipDesign, a: Vector3, b: Vector3) -> bool:
	for k in 9:
		if not inside_ship(d, a.lerp(b, k / 8.0)):
			return false
	return true


# ---------------------------------------------------------------- queries
func node_index(key: String) -> int:
	return int(_index.get(key, -1))


func door_of(room: int) -> int:
	return node_index("d%d" % room)


func edge_index(key: String) -> int:
	for i in edges.size():
		if edges[i]["key"] == key:
			return i
	return -1


## Shortest walking distance (metres) from the nodes `sources` to every node over the edges with ok[edge] != 0.
## Unreachable = INF.
func distances(ok: PackedByteArray, sources: PackedInt32Array) -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(nodes.size())
	dist.fill(INF)
	var open: Array[int] = []
	for s in sources:
		if s >= 0:
			dist[s] = 0.0
			open.append(s)
	while not open.is_empty():
		var best := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best]]:
				best = i
		var n: int = open[best]
		open.remove_at(best)
		for ei in _adj[n]:
			if ok.size() > ei and ok[ei] == 0:
				continue
			var e: Dictionary = edges[ei]
			var other: int = e["b"] if e["a"] == n else e["a"]
			var nd: float = dist[n] + float(e["len"])
			if nd < dist[other]:
				if dist[other] == INF:
					open.append(other)
				dist[other] = nd
	return dist


## Rooms with no corridor route to any room in `from_rooms` (all corridors counted as usable).
func unlinked_rooms(from_rooms: PackedInt32Array) -> PackedInt32Array:
	var src := PackedInt32Array()
	for r in from_rooms:
		src.append(door_of(r))
	var dist := distances(PackedByteArray(), src)
	var out := PackedInt32Array()
	for r in rooms:
		var di := door_of(r)
		if di >= 0 and dist[di] == INF:
			out.append(r)
	return out


## Distance from point `p` (ship space) to the segment of edge `ei`.
func edge_distance(ei: int, p: Vector3) -> float:
	var a: Vector3 = nodes[edges[ei]["a"]]["pos"]
	var b: Vector3 = nodes[edges[ei]["b"]]["pos"]
	return p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))


## Smallest distance between segment [p0, p1] and the corridor edge `ei`.
func edge_distance_to_line(ei: int, p0: Vector3, p1: Vector3) -> float:
	var a: Vector3 = nodes[edges[ei]["a"]]["pos"]
	var b: Vector3 = nodes[edges[ei]["b"]]["pos"]
	var r := Geometry3D.get_closest_points_between_segments(p0, p1, a, b)
	return r[0].distance_to(r[1])


# ---------------------------------------------------------------- keys / overrides (used by ShipDesign)
## Key of a node after module ids were renumbered by `id_map` (old -> new). "" when its module is gone.
static func remap_node_key(key: String, id_map: Dictionary) -> String:
	if key.begins_with("f"):
		return key
	var body := key.substr(1)
	var parts := body.split("_")
	var out := key.substr(0, 1)
	for i in parts.size():
		var old := int(parts[i])
		if not id_map.has(old):
			return ""
		out += ("_" if i > 0 else "") + str(int(id_map[old]))
	return out


static func remap_edge_key(key: String, id_map: Dictionary) -> String:
	var ends := key.split("|")
	if ends.size() != 2:
		return ""
	var a := remap_node_key(ends[0], id_map)
	var b := remap_node_key(ends[1], id_map)
	if a == "" or b == "":
		return ""
	return a + "|" + b if a < b else b + "|" + a


## Copy of a plan-override dictionary with module ids renumbered (and what refers to lost modules dropped).
static func remap_overrides(plan: Dictionary, id_map: Dictionary) -> Dictionary:
	var out := {"removed": [], "free": {}, "added": [], "uid": int(plan.get("uid", 0)), "doors": []}
	for pair in plan.get("doors", []):
		var dk := remap_edge_key(str(pair[0]), id_map)
		if dk != "":
			out["doors"].append([dk, float(pair[1])])
	for k in plan.get("removed", []):
		var nk := remap_edge_key(str(k), id_map)
		if nk != "":
			out["removed"].append(nk)
	var free: Dictionary = plan.get("free", {})
	for k in free:
		var f: Array = free[k]
		if id_map.has(int(f[3])):
			out["free"][k] = [f[0], f[1], f[2], int(id_map[int(f[3])])]
	for pair in plan.get("added", []):
		var a := remap_node_key(str(pair[0]), id_map)
		var b := remap_node_key(str(pair[1]), id_map)
		if a != "" and b != "" and (not a.begins_with("f") or out["free"].has(a)) and (not b.begins_with("f") or out["free"].has(b)):
			out["added"].append([a, b])
	return out
