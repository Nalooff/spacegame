class_name ShipDesign
extends RefCounted
## A ship blueprint.
##
##  * `vertices` is ONE shared pool of points.
##  * Every external module owns a FaceSet (flat polygon faces made of vertex ids, wound outward).
##    Two modules that use the same vertex id are LINKED (Flyout-style): moving it moves both shells.
##  * Edges are not stored, they are the sides of the faces (see module_edges()).
##  * Internal modules (electricity / gyroscope / RCS) have no shell; here they are only scale factors.
##
## Module dictionary layout:
##   { "type": "hull"|"armor"|"thruster"|"turret"|"commander",
##     "fs": FaceSet,
##     "material": String ("" = default of the type),
##     "dir": Vector3,                                   (thrusters: exhaust direction, turrets: rest direction)
##     "cfg": {preset, kind, stats{per-m3 numbers}, barrels[], link}   see ModulePresets }
##   runtime only (never saved by JSON): "sums": PackedFloat64Array, see module_sums()
##
## SCALE: every function here is linear in the size of the module (no nested scans over all vertices),
## so a ship with millions of vertices loads in seconds. Small editing helpers (faces_array / set_faces_array)
## convert to plain arrays: fine for editing, not meant for the flight loop.
##
## Shapes should be roughly convex: collision uses a (decimated) convex hull of each module.

const PRETTY_JSON_MAX_VERTICES := 20000  # bigger ships are saved as compressed binary (.ship)
const BINARY_MAGIC := "VSHP"
## Extra per-module settings (turret base: arc and speed; barrel link). Saved only when present.
const MODULE_EXTRA_KEYS := ["yaw_min", "yaw_max", "pitch_min", "pitch_max"]
const EXTRA_DEFAULTS := {"yaw_min": -180.0, "yaw_max": 180.0, "pitch_min": -10.0, "pitch_max": 85.0}

var ship_name: String = "New Ship"
var vertices: PackedVector3Array = PackedVector3Array()
var modules: Array[Dictionary] = []
## Player edits of the corridor plan (see ShipPlan): {"removed": [], "free": {}, "added": [], "uid": 0}. Empty = fully automatic.
var plan: Dictionary = {}
var reactor_scale: float = 1.0 # electricity output vs. recommended
var gyro_scale: float = 1.0    # gyroscope torque vs. recommended


# =====================================================================
#  Adding / removing modules
# =====================================================================
## Adds a primitive ("box", "cylinder", ...) scaled by `half_size`, centred on `center`.
## `basis` turns the shape first (a cylinder is made along Y: Basis(RIGHT, 90 deg) lays it along Z).
func add_module(type: String, primitive: String, center: Vector3, half_size: Vector3, segments: int = 12, preset: String = "", basis: Basis = Basis.IDENTITY) -> int:
	var p: Dictionary = Primitives.make(primitive, segments)
	var local_verts: Array[Vector3] = []
	for v in p["verts"]:
		local_verts.append(center + basis * ((v as Vector3) * half_size))
	return add_module_from_mesh(type, local_verts, p["faces"], preset)


## A new module dictionary. `cfg` holds everything the module type needs beyond its shape:
##   preset (id), kind ("projectile"/"beam"/"electronic"/"thermal"), stats {per-m3 numbers}, barrels [module ids] (turret base),
##   link (commander -> turret base that can be fired from the bridge)
static func new_module(type: String, fs: FaceSet, preset: String = "") -> Dictionary:
	var id := preset if preset != "" else ModulePresets.default_preset(type)
	return {"type": type, "fs": fs, "dir": Vector3(0, 0, -1) if type != ModuleCatalog.TURRET else Vector3(0, 1, 0),
		"material": "", "cfg": ModulePresets.make_cfg(type, id)}


## Adds a module from raw data. `local_faces` index into `local_verts`.
func add_module_from_mesh(type: String, local_verts: Array[Vector3], local_faces: Array, preset: String = "") -> int:
	var first := vertices.size()
	for v in local_verts:
		vertices.append(v)
	var fs := FaceSet.new()
	for f in local_faces:
		var loop := PackedInt32Array()
		for i in (f as PackedInt32Array):
			loop.append(first + i)
		fs.append(loop)
	modules.append(new_module(type, fs, preset))
	fix_winding(modules.size() - 1)
	return modules.size() - 1


func remove_module(mi: int) -> void:
	if not plan.is_empty():
		var id_map := {}
		for i in modules.size():
			if i != mi:
				id_map[i] = i - 1 if i > mi else i
		plan = ShipPlan.remap_overrides(plan, id_map)
	modules.remove_at(mi)
	for m in modules: # keep turret -> barrel and commander -> turret links valid
		var c: Dictionary = m["cfg"]
		if c.has("barrels"):
			var out: Array = []
			for b in c["barrels"]:
				if int(b) != mi:
					out.append(int(b) - 1 if int(b) > mi else int(b))
			c["barrels"] = out
		if c.has("links"):
			var kept: Array = []
			for l in c["links"]:
				if int(l) != mi:
					kept.append(int(l) - 1 if int(l) > mi else int(l))
			c["links"] = kept
	prune_vertices()


## Setting `key` of module `mi` (EXTRA_DEFAULTS when it was never set): turret arcs.
func extra(mi: int, key: String) -> Variant:
	return modules[mi].get(key, EXTRA_DEFAULTS[key])


# ---- module configuration (see ModulePresets) --------------------------------------------------------------------
func cfg(mi: int) -> Dictionary:
	return modules[mi]["cfg"]


## One per-m3 / preset number of module `mi` (0.0 when the type does not have it).
## Is module `mi` a ROOM (people walk there: it needs a corridor)? By type, or because its preset says kind "room".
func is_room(mi: int) -> bool:
	return ModuleCatalog.ROOM_TYPES.has(modules[mi]["type"]) or kind_of(mi) == "room"


func stat(mi: int, key: String) -> float:
	return float((modules[mi]["cfg"].get("stats", {}) as Dictionary).get(key, 0.0))


## A stat of the module, or `fallback` when its preset does not have it (old ships, other types).
func _stat_or(mi: int, key: String, fallback: float) -> float:
	var st: Dictionary = modules[mi].get("cfg", {}).get("stats", {})
	return float(st[key]) if st.has(key) else fallback


func kind_of(mi: int) -> String:
	var k := str(modules[mi]["cfg"].get("kind", ""))
	if k == "" and modules[mi]["type"] == ModuleCatalog.ANTENNA:
		return "external"          # ships saved before the antenna presets had kinds
	return k


## Damage type of a weapon module: its cfg says so, else projectiles are kinetic and beams are energy.
func damage_type_id(mi: int) -> StringName:
	var t := str(modules[mi]["cfg"].get("damage_type", ""))
	if t != "" and DamageRegistry.WEAPON_TYPES.has(StringName(t)):
		return StringName(t)
	return &"energy" if kind_of(mi) == "beam" else &"kinetic"


func damage_type_index(mi: int) -> int:
	return DamageRegistry.weapon_index(damage_type_id(mi))


## Module ids of the barrels linked to turret base `mi`.
func barrels_of(mi: int) -> Array[int]:
	var out: Array[int] = []
	for b in modules[mi]["cfg"].get("barrels", []):
		out.append(int(b))
	return out


## Turret base module that barrel `bi` is linked to (-1 = none).
func base_of_barrel(bi: int) -> int:
	for i in modules.size():
		if modules[i]["type"] == ModuleCatalog.TURRET and barrels_of(i).has(bi):
			return i
	return -1


## COMMANDER LINKS. A commander module only controls what is linked to it:
##   cfg["links"] = turret bases it fires (a commander can have several; one turret may be linked to several commanders)
##   cfg["pilot"] = it holds the flight controls (default true). A big ship can have one "pilot" bridge and one "gunner" bridge.
## A ship where NO commander has any link or a pilot flag set up keeps the simple rule: every commander does everything.
func linked_turrets(mi: int) -> Array[int]:
	var out: Array[int] = []
	for l in modules[mi]["cfg"].get("links", []):
		out.append(int(l))
	return out


func can_pilot(mi: int) -> bool:
	return bool(modules[mi]["cfg"].get("pilot", true))


## Does commander `cmd` control module `mi` (a turret base)? cmd < 0 = nobody in particular (no roster): everything.
func controls(cmd: int, mi: int) -> bool:
	if cmd < 0 or cmd >= modules.size() or not has_links():
		return true
	return linked_turrets(cmd).has(mi)


## Does commander `cmd` fly the ship?
func controls_flight(cmd: int) -> bool:
	if cmd < 0 or cmd >= modules.size():
		return true
	return can_pilot(cmd)


## True if somebody set up links (then turrets WITHOUT a commander link are only reachable through the gun station).
func has_links() -> bool:
	for c in commander_modules():
		if not (modules[c]["cfg"].get("links", []) as Array).is_empty():
			return true
	return false


## Link / unlink turret base `base` to commander `cmd`. Returns true if it is linked now.
func toggle_link(cmd: int, base: int) -> bool:
	var c: Dictionary = modules[cmd]["cfg"]
	var list: Array = c.get("links", [])
	var at := list.find(base)
	if at >= 0:
		list.remove_at(at)
	else:
		list.append(base)
	c["links"] = list
	return at < 0


## Change the preset of a module: its stats are replaced by the preset's.
func set_preset(mi: int, preset: String) -> void:
	var old: Dictionary = modules[mi]["cfg"]
	var fresh := ModulePresets.make_cfg(modules[mi]["type"], preset)
	for key in ["barrels", "links", "pilot"]:
		if old.has(key):
			fresh[key] = old[key]
	modules[mi]["cfg"] = fresh


## Set the MAIN stat of a module; the other stats follow (ModulePresets.set_main).
func set_main_stat(mi: int, value: float) -> void:
	var cfg_: Dictionary = modules[mi]["cfg"]
	ModulePresets.set_main(modules[mi]["type"], kind_of(mi), cfg_["stats"], value)


## Thrust (N) of thruster module `mi` at full throttle: thrust per m3 times its volume.
func thruster_power(mi: int) -> float:
	return stat(mi, "thrust_per_m3") * module_volume(mi)

## Indices of the commander modules.
func commander_modules() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in modules.size():
		if modules[i]["type"] == ModuleCatalog.COMMANDER:
			out.append(i)
	return out


## The LOOSE module (unassigned faces), or -1.
func loose_module() -> int:
	for i in modules.size():
		if modules[i]["type"] == ModuleCatalog.LOOSE:
			return i
	return -1


## Index of the loose-faces pseudo-module, created when missing.
func ensure_loose() -> int:
	var l := loose_module()
	if l >= 0:
		return l
	modules.append(new_module(ModuleCatalog.LOOSE, FaceSet.new()))
	return modules.size() - 1


## "Create face": one polygon (vertex ids in order) that belongs to no module yet. It is drawn red until it is put into a
## closed container with "Make module"; the ship cannot be saved while loose faces exist.
func add_loose_face(ids: PackedInt32Array) -> void:
	var l := ensure_loose()
	var faces := faces_array(l)
	faces.append(ids)
	set_faces_array(l, faces)


## "Make module": moves the faces `face_indices` of module `src` into a NEW module of `type`. The loose pseudo-module
## disappears when it is empty. Returns the new module index (the indices of other modules can shift when the loose
## module is removed: use the returned value only right away).
func move_faces_to_new_module(src: int, face_indices: Array[int], type: String) -> int:
	var faces := faces_array(src)
	var taken: Array = []
	var rest: Array = []
	for fi in faces.size():
		if face_indices.has(fi):
			taken.append(faces[fi])
		else:
			rest.append(faces[fi])
	if taken.is_empty():
		return -1
	set_faces_array(src, rest)
	var fs := FaceSet.from_array(taken)
	modules.append(new_module(type, fs))
	var n := modules.size() - 1
	if rest.is_empty() and modules[src]["type"] == ModuleCatalog.LOOSE:
		modules.remove_at(src)    # (the new module was appended after it, so its index shifts down by one)
		n -= 1
	elif rest.is_empty():
		modules.remove_at(src)
		n -= 1
	if modules[n]["type"] != ModuleCatalog.LOOSE and count_open_edges(n) == 0:
		fix_winding(n)
	return n


## Indices of the alive faces of module `mi`.
func faces_alive(mi: int) -> PackedInt32Array:
	var fs: FaceSet = modules[mi]["fs"]
	var out := PackedInt32Array()
	for fi in fs.count():
		if fs.sizes[fi] >= 3:
			out.append(fi)
	return out


## Number of faces that are not part of a real module.
func loose_face_count() -> int:
	var l := loose_module()
	return 0 if l < 0 else (modules[l]["fs"] as FaceSet).alive_count()


## Drop loose faces (the game never flies them).
func strip_loose() -> void:
	var l := loose_module()
	if l >= 0:
		remove_module(l)


## New design made of only the modules in `ids` (vertices are copied and renumbered). Cached sums are kept.
## Module `ids[k]` becomes module `k`. Used when a ship splits.
func extract(ids: PackedInt32Array) -> ShipDesign:
	var s := ShipDesign.new()
	s.ship_name = ship_name
	s.reactor_scale = reactor_scale
	s.gyro_scale = gyro_scale
	var map := PackedInt32Array()
	map.resize(vertices.size())
	map.fill(-1)
	var new_index := {}
	for k in ids.size():
		new_index[ids[k]] = k
	for mi in ids:
		var m: Dictionary = modules[mi]
		var src: FaceSet = m["fs"]
		src.compact()
		var fs := src.duplicate()
		for k in fs.ids.size():
			var id := fs.ids[k]
			if map[id] < 0:
				s.vertices.append(vertices[id])
				map[id] = s.vertices.size() - 1
			fs.ids[k] = map[id]
		var entry := {"type": m["type"], "fs": fs, "dir": m["dir"], "material": m.get("material", ""),
			"cfg": _copy_cfg(m["cfg"], new_index)}
		for key in MODULE_EXTRA_KEYS:
			if m.has(key):
				entry[key] = m[key]
		if m.has("sums"):
			entry["sums"] = (m["sums"] as PackedFloat64Array).duplicate()
		s.modules.append(entry)
	if not plan.is_empty():
		s.plan = ShipPlan.remap_overrides(plan, new_index)
	return s


## Deep copy of a cfg. `id_map` (old module id -> new id) fixes barrel / link references; ids not in it are dropped.
static func _copy_cfg(cfg_: Dictionary, id_map: Dictionary = {}) -> Dictionary:
	var out := cfg_.duplicate(true)
	if out.has("barrels"):
		var list: Array = []
		for b in cfg_["barrels"]:
			if id_map.has(int(b)):
				list.append(int(id_map[int(b)]))
		out["barrels"] = list
	if out.has("links"):
		var ls: Array = []
		for l in cfg_["links"]:
			if id_map.has(int(l)):
				ls.append(int(id_map[int(l)]))
		out["links"] = ls
	return out


## Copy of module `mi` with its own (unlinked) vertices.
func duplicate_module(mi: int, offset: Vector3 = Vector3.ZERO) -> int:
	var remap_ids := PackedInt32Array()
	remap_ids.resize(vertices.size())
	remap_ids.fill(-1)
	var src: FaceSet = modules[mi]["fs"]
	src.compact()
	var fs := src.duplicate()
	for k in fs.ids.size():
		var id := fs.ids[k]
		if remap_ids[id] < 0:
			vertices.append(vertices[id] + offset)
			remap_ids[id] = vertices.size() - 1
		fs.ids[k] = remap_ids[id]
	var copy := {"type": modules[mi]["type"], "fs": fs, "dir": modules[mi]["dir"],
		"material": modules[mi].get("material", ""), "cfg": _copy_cfg(modules[mi]["cfg"])}
	copy["cfg"].erase("barrels")      # a copy of a turret base has no barrels yet; a copied commander no link
	copy["cfg"].erase("links")
	for key in MODULE_EXTRA_KEYS:
		if modules[mi].has(key):
			copy[key] = modules[mi][key]
	modules.append(copy)
	return modules.size() - 1


## Material id of module `mi` (its own, or the default of its type).
func material_of(mi: int) -> String:
	var m: String = modules[mi].get("material", "")
	return m if MaterialCatalog.MATERIALS.has(m) else MaterialCatalog.default_for(modules[mi]["type"])


## Seats of ONE commander module (pilot included).
func crew_capacity_of(mi: int) -> int:
	var per_seat := maxf(stat(mi, "seat_volume"), 0.5)
	return clampi(int(floor(module_volume(mi) / per_seat)), 1, 12)


## How many people (pilot included) this ship holds = the sum over all its commander modules.
func crew_capacity() -> int:
	var total := 0
	for i in commander_modules():
		total += crew_capacity_of(i)
	return maxi(total, 1)


## {commander module index: seats} - what the lobby shows over each commander.
func seat_slots() -> Dictionary:
	var out := {}
	for i in commander_modules():
		out[i] = crew_capacity_of(i)
	return out


## Mirror copy of module `mi` across the YZ plane (x -> -x).
## Copy of module `mi` mirrored across the plane perpendicular to `axis` (0 = X, 1 = Y, 2 = Z) at `offset` metres.
func mirror_module(mi: int, axis: int = 0, offset: float = 0.0) -> int:
	var n := duplicate_module(mi)
	for id in module_vertex_ids(n):
		var v := vertices[id]
		v[axis] = 2.0 * offset - v[axis]
		vertices[id] = v
	var d: Vector3 = modules[n]["dir"]
	d[axis] = -d[axis]
	modules[n]["dir"] = d
	fix_winding(n) # mirroring flips the winding
	return n


# ---- editing helpers: faces as plain arrays (builder / MeshOps work on these) -------------
func faces_array(mi: int) -> Array[PackedInt32Array]:
	var fs: FaceSet = modules[mi]["fs"]
	fs.compact()
	return fs.to_array()


func set_faces_array(mi: int, faces: Array) -> void:
	modules[mi]["fs"] = FaceSet.from_array(faces)
	modules[mi].erase("sums")


## Move every vertex (and keep the cached physical sums valid, so nothing has to be recomputed).
func translate_all(offset: Vector3) -> void:
	vertices = Transform3D(Basis.IDENTITY, offset) * vertices
	for k in plan.get("free", {}):      # free corridor nodes move with the ship
		var f: Array = plan["free"][k]
		f[0] += offset.x
		f[1] += offset.y
		f[2] += offset.z
	for m in modules:
		if m.has("sums"):
			var s: PackedFloat64Array = m["sums"]
			var vol := s[0]
			var vp := Vector3(s[1], s[2], s[3])
			var vp2 := Vector3(s[4], s[5], s[6])
			var o := offset
			var nvp := vp + o * vol
			var nvp2 := vp2 + 2.0 * o * vp + o * o * vol
			s[1] = nvp.x; s[2] = nvp.y; s[3] = nvp.z
			s[4] = nvp2.x; s[5] = nvp2.y; s[6] = nvp2.z
			s[8] += o.x; s[9] += o.y; s[10] += o.z
			m["sums"] = s


## Forget cached physical sums (call after moving vertices by hand).
func invalidate() -> void:
	for m in modules:
		m.erase("sums")


# =====================================================================
#  Vertex pool: linking
# =====================================================================
## Merge several vertices into ONE shared vertex (the lowest id, placed at their average).
## Returns the id of the merged vertex.
func merge_vertices(ids: Array[int]) -> int:
	if ids.is_empty():
		return -1
	var target: int = ids[0]
	var centre := Vector3.ZERO
	for id in ids:
		target = mini(target, id)
		centre += vertices[id]
	vertices[target] = centre / ids.size()
	for id in ids:
		if id != target:
			_replace_vertex_id(id, target)
	prune_vertices()
	return target


## Weld pairs [keep_id, move_id]: every `move_id` is placed on its `keep_id`'s point and replaced by it (one prune at the end,
## so the ids stay valid while the pairs are processed).
func weld_pairs(pairs: Array) -> void:
	for pr in pairs:
		vertices[int(pr[1])] = vertices[int(pr[0])]
		_replace_vertex_id(int(pr[1]), int(pr[0]))
	prune_vertices()
	invalidate()


## Merge vertex `b` into `a` (both modules now share one point).
func link_vertices(a: int, b: int) -> void:
	if a == b:
		return
	_replace_vertex_id(b, a)
	prune_vertices()


func _replace_vertex_id(old_id: int, new_id: int) -> void:
	for m in modules:
		var fs: FaceSet = m["fs"]
		for k in fs.ids.size():
			if fs.ids[k] == old_id:
				fs.ids[k] = new_id


## Give module `mi` its own copy of vertex `id` (undo a link). Returns the new id.
func unlink_vertex(mi: int, id: int) -> int:
	vertices.append(vertices[id])
	var new_id := vertices.size() - 1
	var fs: FaceSet = modules[mi]["fs"]
	for k in fs.ids.size():
		if fs.ids[k] == id:
			fs.ids[k] = new_id
	return new_id


## How many modules use each vertex (index = vertex id). 2+ means the vertex is linked.
func vertex_user_counts() -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(vertices.size())
	for i in modules.size():
		var mark := _vertex_mask(i)
		for id in mark.size():
			if mark[id] != 0:
				counts[id] += 1
	return counts


func vertex_users(id: int) -> Array[int]:
	var out: Array[int] = []
	for i in modules.size():
		if (modules[i]["fs"] as FaceSet).ids.has(id):
			out.append(i)
	return out


## Remove unused vertices and renumber the rest (also drops duplicate ids inside a face).
func prune_vertices() -> void:
	var used := PackedByteArray()
	used.resize(vertices.size())
	for m in modules:
		var fs: FaceSet = m["fs"]
		for fi in fs.count():
			var s := fs.starts[fi]
			for k in fs.sizes[fi]:
				used[fs.ids[s + k]] = 1
	var remap_ids := PackedInt32Array()
	remap_ids.resize(vertices.size())
	var new_pool := PackedVector3Array()
	for id in vertices.size():
		if used[id] != 0:
			remap_ids[id] = new_pool.size()
			new_pool.append(vertices[id])
	for m in modules:
		var fs: FaceSet = m["fs"]
		var cleaned := FaceSet.new()
		for fi in fs.count():
			if fs.sizes[fi] == 0:
				continue
			var loop := PackedInt32Array()
			for id in fs.face(fi):
				var nid := remap_ids[id]
				if loop.is_empty() or loop[loop.size() - 1] != nid:
					loop.append(nid)
			if loop.size() > 1 and loop[0] == loop[loop.size() - 1]:
				loop.remove_at(loop.size() - 1)
			if loop.size() >= 3:
				cleaned.append(loop)
		m["fs"] = cleaned
		m.erase("sums")
	vertices = new_pool


# =====================================================================
#  Geometry queries (all linear)
# =====================================================================
## 1 for every vertex id the module uses (size = vertices.size()).
func _vertex_mask(mi: int) -> PackedByteArray:
	var mark := PackedByteArray()
	mark.resize(vertices.size())
	var fs: FaceSet = modules[mi]["fs"]
	if fs.dead == 0:
		for id in fs.ids:
			mark[id] = 1
	else:
		for fi in fs.count():
			var s := fs.starts[fi]
			for k in fs.sizes[fi]:
				mark[fs.ids[s + k]] = 1
	return mark


## Sorted list of the vertex ids a module uses.
func module_vertex_ids(mi: int) -> PackedInt32Array:
	var mark := _vertex_mask(mi)
	var out := PackedInt32Array()
	for id in mark.size():
		if mark[id] != 0:
			out.append(id)
	return out


func module_points(mi: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for id in module_vertex_ids(mi):
		out.append(vertices[id])
	return out


## Average of the module's (unique) vertices.
func module_centroid(mi: int) -> Vector3:
	var mark := _vertex_mask(mi)
	var c := Vector3.ZERO
	var n := 0
	for id in mark.size():
		if mark[id] != 0:
			c += vertices[id]
			n += 1
	return c / maxf(n, 1)


## Unique edges (a < b) of a module = the sides of its faces.
func module_edges(mi: int) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	var fs: FaceSet = modules[mi]["fs"]
	for fi in fs.count():
		var n := fs.sizes[fi]
		if n == 0:
			continue
		var s := fs.starts[fi]
		for k in n:
			var a := fs.ids[s + k]
			var b := fs.ids[s + (k + 1) % n]
			var key := (mini(a, b) << 32) | maxi(a, b)
			if not seen.has(key):
				seen[key] = true
				out.append(Vector2i(mini(a, b), maxi(a, b)))
	return out


func face_center(mi: int, fi: int) -> Vector3:
	var ids := (modules[mi]["fs"] as FaceSet).face(fi)
	var c := Vector3.ZERO
	for id in ids:
		c += vertices[id]
	return c / maxf(ids.size(), 1)


## Faces are always stored wound outward, so this is just the face itself.
func face_outward(mi: int, fi: int) -> PackedInt32Array:
	return (modules[mi]["fs"] as FaceSet).face(fi)


static func newell_normal(vs: PackedVector3Array, loop: PackedInt32Array) -> Vector3:
	var n := Vector3.ZERO
	for k in loop.size():
		var a := vs[loop[k]]
		var b := vs[loop[(k + 1) % loop.size()]]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	return n


## Turn every face so it looks OUTWARD from the module's centre. Run after anything that can flip winding.
func fix_winding(mi: int) -> void:
	var fs: FaceSet = modules[mi]["fs"]
	var centroid := module_centroid(mi)
	for fi in fs.count():
		var n := fs.sizes[fi]
		if n < 3:
			continue
		var s := fs.starts[fi]
		var nrm := Vector3.ZERO
		var fc := Vector3.ZERO
		for k in n:
			var a := vertices[fs.ids[s + k]]
			var b := vertices[fs.ids[s + (k + 1) % n]]
			nrm += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
			fc += a
		if nrm.dot(fc / n - centroid) < 0.0:
			fs.reverse(fi)
	modules[mi].erase("sums")


## Triangle list (3 points per triangle), every face fanned. `tri_face` (optional out) gets each triangle's face index.
func module_tris(mi: int, tri_face: PackedInt32Array = PackedInt32Array()) -> PackedVector3Array:
	var out := PackedVector3Array()
	var fs: FaceSet = modules[mi]["fs"]
	for fi in fs.count():
		var n := fs.sizes[fi]
		if n < 3:
			continue
		var s := fs.starts[fi]
		var v0 := vertices[fs.ids[s]]
		for k in range(1, n - 1):
			out.append(v0)
			out.append(vertices[fs.ids[s + k]])
			out.append(vertices[fs.ids[s + k + 1]])
			tri_face.append(fi)
	return out


func module_volume(mi: int) -> float:
	return module_sums(mi)[0]


func face_count_total() -> int:
	var n := 0
	for m in modules:
		n += (m["fs"] as FaceSet).alive_count()
	return n


# =====================================================================
#  Physical sums (mass, centre of mass, inertia) - cached per module
# =====================================================================
## Add one face's contribution to `acc` (8 numbers) using `apex` as the tetrahedron tip:
##   acc[0] = volume,  acc[1..3] = sum(volume * position),  acc[4..6] = sum(volume * position^2),  acc[7] = self term
## Because the apex is fixed, a dent only has to subtract the old faces and add the new ones.
static func accumulate_face(vs: PackedVector3Array, ids: PackedInt32Array, start: int, n: int, apex: Vector3,
		acc: PackedFloat64Array, factor: float = 1.0) -> void:
	var v0 := vs[ids[start]]
	for k in range(1, n - 1):
		var v1 := vs[ids[start + k]]
		var v2 := vs[ids[start + k + 1]]
		var tv := (v0 - apex).dot((v1 - apex).cross(v2 - apex)) / 6.0 * factor # signed: faces are wound outward
		var tp := (v0 + v1 + v2 + apex) * 0.25
		acc[0] += tv
		acc[1] += tv * tp.x
		acc[2] += tv * tp.y
		acc[3] += tv * tp.z
		acc[4] += tv * tp.x * tp.x
		acc[5] += tv * tp.y * tp.y
		acc[6] += tv * tp.z * tp.z
		acc[7] += tv * 0.2 * pow(absf(tv), 2.0 / 3.0)


## Cached sums of a module: [volume, vp.x, vp.y, vp.z, vp2.x, vp2.y, vp2.z, self, apex.x, apex.y, apex.z]
func module_sums(mi: int) -> PackedFloat64Array:
	var m: Dictionary = modules[mi]
	if m.has("sums"):
		return m["sums"]
	var apex := module_centroid(mi)
	var acc := PackedFloat64Array()
	acc.resize(11)
	var fs: FaceSet = m["fs"]
	for fi in fs.count():
		if fs.sizes[fi] >= 3:
			accumulate_face(vertices, fs.ids, fs.starts[fi], fs.sizes[fi], apex, acc)
	acc[8] = apex.x
	acc[9] = apex.y
	acc[10] = apex.z
	m["sums"] = acc
	return acc


## Returns {mass, shell_mass, com, inertia: Vector3, modules: [{centroid, volume, mass, hp, type, material}],
##          thrusters: [{pos, dir, power, module}], turrets: [{pos, module}], commander_pos}
## Positions are in design space (origin = design origin).
## `alive` (optional, one byte per module, 0 = destroyed): destroyed / detached modules add no mass and no thrust.
## `working` (optional): modules that also FUNCTION. A dead wreck still has mass but gives no thrust, no guns, no command.
func compute_props(alive: PackedByteArray = PackedByteArray(), working: PackedByteArray = PackedByteArray()) -> Dictionary:
	var total_m := 0.0
	var mom := Vector3.ZERO
	var s2 := Vector3.ZERO
	var self_sum := 0.0
	var mod_info: Array = []
	var thr: Array = []
	var tur: Array = []
	var cmd_pos := Vector3.ZERO
	for i in modules.size():
		var type: String = modules[i]["type"]
		var info: Dictionary = ModuleCatalog.TYPE_INFO[type]
		if type == ModuleCatalog.LOOSE or (not alive.is_empty() and alive[i] == 0):
			# placeholder so that indices stay aligned (loose faces are not a real module; dead ones are gone)
			var gone_sums := module_sums(i) if type != ModuleCatalog.LOOSE else PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
			mod_info.append({"centroid": Vector3(gone_sums[8], gone_sums[9], gone_sums[10]), "volume": 0.0, "mass": 0.0,
				"type": type, "material": material_of(i), "hp": maxf(ModuleCatalog.MIN_HP, module_volume(i) * info["hp_per_m3"]) if type != ModuleCatalog.LOOSE else 0.0})
			continue
		var density: float = float(info["density"]) * float(MaterialCatalog.info(material_of(i))["density_mult"]) * _stat_or(i, "density_mult", 1.0)
		var sums := module_sums(i)
		var c := Vector3(sums[8], sums[9], sums[10])
		var vol: float = sums[0]
		total_m += vol * density
		mom += Vector3(sums[1], sums[2], sums[3]) * density
		s2 += Vector3(sums[4], sums[5], sums[6]) * density
		self_sum += sums[7] * density
		mod_info.append({
			"centroid": c, "volume": vol, "mass": vol * density, "type": type, "material": material_of(i),
			"hp": maxf(ModuleCatalog.MIN_HP, vol * info["hp_per_m3"] * _stat_or(i, "hp_mult", 1.0)),
		})
		if not working.is_empty() and working[i] == 0:
			continue   # dead wreck: heavy, but it does nothing
		if type == ModuleCatalog.THRUSTER:
			var d: Vector3 = modules[i]["dir"]
			thr.append({"pos": c, "dir": d.normalized() if d.length() > 0.0001 else Vector3(0, 0, -1),
				"power": stat(i, "thrust_per_m3") * vol, "elec_per_n": stat(i, "elec_per_n"),
				"heat_per_n": stat(i, "heat_per_n"), "module": i})
		elif type == ModuleCatalog.TURRET:
			tur.append({"pos": c, "module": i, "barrels": barrels_of(i)})
		elif type == ModuleCatalog.COMMANDER:
			cmd_pos = c
	var com := mom / total_m if total_m > 0.0 else Vector3.ZERO
	# inertia about the CoM, diagonal only (Godot RigidBody3D takes a Vector3)
	var ixx := s2.y + s2.z - total_m * (com.y * com.y + com.z * com.z) + self_sum
	var iyy := s2.x + s2.z - total_m * (com.x * com.x + com.z * com.z) + self_sum
	var izz := s2.x + s2.y - total_m * (com.x * com.x + com.y * com.y) + self_sum
	var internal_mass := 120.0 * reactor_scale + 80.0 * gyro_scale # internal systems only add mass
	var mass_all := total_m + internal_mass
	var floor_i := 0.02 * mass_all
	return {
		"mass": maxf(mass_all, 1.0), "shell_mass": total_m, "com": com,
		"inertia": Vector3(maxf(ixx, floor_i), maxf(iyy, floor_i), maxf(izz, floor_i)),
		"modules": mod_info, "thrusters": thr, "turrets": tur, "commander_pos": cmd_pos,
	}


# =====================================================================
#  Checks
# =====================================================================
func validate() -> Array[String]:
	var errors: Array[String] = []
	var commanders := 0
	var thrusters := 0
	var loose := loose_face_count()
	if loose > 0:
		errors.append("%d unassigned face(s) (red). Select them and press 'Make module', or delete them." % loose)
	for i in modules.size():
		var t: String = modules[i]["type"]
		if t == ModuleCatalog.LOOSE:
			continue
		if t == ModuleCatalog.COMMANDER:
			commanders += 1
		elif t == ModuleCatalog.THRUSTER:
			thrusters += 1
		if (modules[i]["fs"] as FaceSet).alive_count() < 4 or module_volume(i) < 0.001:
			errors.append("Module %d (%s) is flat or has no volume." % [i, t])
		elif ModuleCatalog.MIN_EXTENT.has(t):
			var need: float = ModuleCatalog.MIN_EXTENT[t]
			var ext := module_extent(i)
			if minf(ext.x, minf(ext.y, ext.z)) < need - 0.01:
				errors.append("Module %d (%s) is too small to walk in: its thinnest side is %.2f m, the minimum is %.1f m." % [
					i, t, minf(ext.x, minf(ext.y, ext.z)), need])
		var open_edges := count_open_edges(i)
		if open_edges > 0:
			errors.append("Module %d (%s) is not a closed container: %d open edge(s)." % [i, t, open_edges])
	if commanders < 1:
		errors.append("A ship needs at least one Commander module.")
	if thrusters < 1:
		errors.append("A ship needs at least one thruster.")
	if commanders > 0:
		var pl := ShipPlan.generate(self)
		for e in pl.edges:
			if not pl.segment_inside(self, pl.nodes[e["a"]]["pos"], pl.nodes[e["b"]]["pos"]):
				errors.append("A corridor between modules leaves the ship (%s): the modules touch too little. Make them overlap or share a face." % e["key"])
				break
		for r in unwalkable_rooms():
			errors.append("Room %d (%s) has no corridor to a commander: nobody could ever walk there. Draw a corridor in the plan." % [r, modules[r]["type"]])
	for m in ModuleGraph.unreachable(self):
		errors.append("Module %d (%s) is not connected to a commander (share a vertex with a module that is). It would fall off." % [m, modules[m]["type"]])
	errors.append_array(exhaust_errors())
	errors.append_array(turret_errors())
	return errors


## Rooms (modules a person has to be able to reach) that no corridor leads to from a commander.
func unwalkable_rooms() -> PackedInt32Array:
	var pl := ShipPlan.generate(self)
	var cmds := PackedInt32Array()
	for r in pl.rooms:
		if modules[r]["type"] == ModuleCatalog.COMMANDER:
			cmds.append(r)
	return pl.unlinked_rooms(cmds)


## Errors for modules standing in a thruster's exhaust (see ExhaustZone).
func exhaust_errors() -> Array[String]:
	var out: Array[String] = []
	for c in ExhaustZone.conflicts(self):
		out.append("Module %d (%s) is in the exhaust of thruster %d. Move it out of the orange cone." % [c.y, modules[c.y]["type"], c.x])
	return out


## Size (x, y, z) of the box around module `mi`.
func module_extent(mi: int) -> Vector3:
	var fs: FaceSet = modules[mi]["fs"]
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for fi in fs.count():
		if fs.sizes[fi] == 0:
			continue
		for k in fs.sizes[fi]:
			var v := vertices[fs.ids[fs.starts[fi] + k]]
			lo = lo.min(v)
			hi = hi.max(v)
	return hi - lo if lo.x != INF else Vector3.ZERO


## Errors for turret bases / barrels.
func turret_errors() -> Array[String]:
	var out: Array[String] = []
	var mounted := {}
	for i in modules.size():
		if modules[i]["type"] != ModuleCatalog.TURRET:
			continue
		for b in barrels_of(i):
			if b < 0 or b >= modules.size() or modules[b]["type"] != ModuleCatalog.BARREL:
				out.append("Turret %d is linked to module %d, which is not a Barrel." % [i, b])
			elif mounted.has(b):
				out.append("Barrel %d is linked to two turrets." % b)
			else:
				mounted[b] = i
		if float(extra(i, "yaw_min")) >= float(extra(i, "yaw_max")) or float(extra(i, "pitch_min")) >= float(extra(i, "pitch_max")):
			out.append("Turret %d has an empty firing arc (min must be below max)." % i)
	for i in modules.size():
		if modules[i]["type"] == ModuleCatalog.BARREL and not mounted.has(i):
			out.append("Barrel %d is not mounted on a turret base (select the base and link it)." % i)
	return out


## Edges of module `mi` that are not shared by exactly two of its faces (0 = closed surface).
func count_open_edges(mi: int) -> int:
	var fs: FaceSet = modules[mi]["fs"]
	var uses := {}
	for fi in fs.count():
		var n := fs.sizes[fi]
		if n == 0:
			continue
		var s := fs.starts[fi]
		for k in n:
			var a := fs.ids[s + k]
			var b := fs.ids[s + (k + 1) % n]
			var key: int = (mini(a, b) << 32) | maxi(a, b)
			uses[key] = int(uses.get(key, 0)) + 1
	var bad := 0
	for key in uses:
		if uses[key] != 2:
			bad += 1
	return bad


## Face indices of module `mi` that touch an open edge (the builder paints them).
func open_edge_faces(mi: int) -> PackedInt32Array:
	var fs: FaceSet = modules[mi]["fs"]
	var uses := {}
	for fi in fs.count():
		var n := fs.sizes[fi]
		if n == 0:
			continue
		var s := fs.starts[fi]
		for k in n:
			var a := fs.ids[s + k]
			var b := fs.ids[s + (k + 1) % n]
			var key: int = (mini(a, b) << 32) | maxi(a, b)
			uses[key] = int(uses.get(key, 0)) + 1
	var out := PackedInt32Array()
	for fi in fs.count():
		var n := fs.sizes[fi]
		var s := fs.starts[fi]
		for k in n:
			var a := fs.ids[s + k]
			var b := fs.ids[s + (k + 1) % n]
			if uses[(mini(a, b) << 32) | maxi(a, b)] != 2:
				out.append(fi)
				break
	return out


# =====================================================================
#  Meshing for the BUILDER (flat shaded, vertex colours). The game uses HullRenderer instead.
# =====================================================================
## `health_ratio[i]` in 0..1 (<= 0 = destroyed, skipped). `highlight` = module indices drawn lighter.
## `hidden` = module indices that are left out (the builder's Hide / Isolate).
func build_mesh(health_ratio: PackedFloat32Array = PackedFloat32Array(), highlight: Array = [], hidden: Array = []) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for i in modules.size():
		var ratio := 1.0
		if i < health_ratio.size():
			ratio = health_ratio[i]
		if ratio <= 0.0 or hidden.has(i):
			continue
		var col := ModuleCatalog.color_of(modules[i]["type"]).lerp(Color(0.12, 0.05, 0.04), (1.0 - ratio) * 0.8)
		if highlight.has(i):
			col = col.lightened(0.4)
		var tris := module_tris(i)
		var count := tris.size()
		var first := verts.size()
		verts.append_array(tris)
		norms.resize(first + count)
		cols.resize(first + count)
		for t in range(0, count, 3):
			var n := (tris[t + 1] - tris[t]).cross(tris[t + 2] - tris[t]).normalized()
			norms[first + t] = n
			norms[first + t + 1] = n
			norms[first + t + 2] = n
		for t in count:
			cols[first + t] = col
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# =====================================================================
#  Save / load:  readable JSON for normal ships, compressed binary for huge ones
# =====================================================================
func to_dict() -> Dictionary:
	var vs: Array = []
	for v in vertices:
		vs.append([v.x, v.y, v.z])
	var ms: Array = []
	for m in modules:
		var faces: Array = []
		for f in (m["fs"] as FaceSet).to_array():
			faces.append(Array(f))
		var entry := {"type": m["type"], "faces": faces}
		if m.get("material", "") != "":
			entry["material"] = m["material"]
		if m["type"] == ModuleCatalog.THRUSTER or m["type"] == ModuleCatalog.TURRET:
			var d: Vector3 = m["dir"]
			entry["dir"] = [d.x, d.y, d.z]
		entry["cfg"] = (m["cfg"] as Dictionary).duplicate(true)
		for key in MODULE_EXTRA_KEYS:
			if m.has(key):
				entry[key] = m[key]
		ms.append(entry)
	var out := {"name": ship_name, "reactor_scale": reactor_scale, "gyro_scale": gyro_scale,
		"vertices": vs, "modules": ms}
	if not plan.is_empty():
		out["plan"] = plan.duplicate(true)
	return out


static func from_dict(data: Dictionary) -> ShipDesign:
	var s := ShipDesign.new()
	s.ship_name = str(data.get("name", "Ship"))
	s.reactor_scale = float(data.get("reactor_scale", 1.0))
	s.gyro_scale = float(data.get("gyro_scale", 1.0))
	s.plan = _clean_plan(data.get("plan", {}))
	for v in data.get("vertices", []):
		s.vertices.append(Vector3(v[0], v[1], v[2]))
	for m in data.get("modules", []):
		var fs := FaceSet.new()
		if m.has("faces"):
			for f in m["faces"]:
				var ids := PackedInt32Array()
				for id in f:
					ids.append(int(id))
				fs.append(ids)
		else: # old format: {"shape": "box", "v": [ids]} -> expand through the primitive
			var prim: Dictionary = Primitives.make(str(m["shape"]))
			var v_ids: Array = m["v"]
			for lf in prim["faces"]:
				var ids := PackedInt32Array()
				for li in (lf as PackedInt32Array):
					ids.append(int(v_ids[li]))
				fs.append(ids)
		var d: Array = m.get("dir", [0, 0, -1])
		var entry := {"type": str(m["type"]), "fs": fs,
			"dir": Vector3(d[0], d[1], d[2]), "material": str(m.get("material", "")),
			"cfg": _clean_cfg(m.get("cfg", {}))}
		for key in MODULE_EXTRA_KEYS:
			if m.has(key):
				entry[key] = float(m[key])
		# older files: a single "barrel", a thruster "power", commander "crew", turret "turn_speed"
		entry["_legacy"] = {"barrel": int(m.get("barrel", -1)), "power": float(m.get("power", 0.0)),
			"crew": int(m.get("crew", 0)), "turn_speed": float(m.get("turn_speed", 0.0))}
		s.modules.append(entry)
	# older / hand-made files may have any winding: make it canonical once
	for i in s.modules.size():
		s.fix_winding(i)
	s._migrate()
	return s


## JSON gives floats for every number: restore the integer fields of the plan overrides.
static func _clean_plan(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		return {}
	var r: Dictionary = raw
	var out := {"removed": [], "free": {}, "added": [], "uid": int(r.get("uid", 0)), "doors": []}
	for pair in r.get("doors", []):
		out["doors"].append([str(pair[0]), float(pair[1])])
	for k in r.get("removed", []):
		out["removed"].append(str(k))
	var free: Dictionary = r.get("free", {})
	for k in free:
		var f: Array = free[k]
		out["free"][str(k)] = [float(f[0]), float(f[1]), float(f[2]), int(f[3])]
	for pair in r.get("added", []):
		out["added"].append([str(pair[0]), str(pair[1])])
	return out


## JSON gives floats for every number: restore the integer fields of a cfg.
static func _clean_cfg(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = (raw as Dictionary).duplicate(true)
	if out.has("barrels"):
		var list: Array = []
		for b in out["barrels"]:
			list.append(int(b))
		out["barrels"] = list
	if out.has("link"):       # older files: ONE linked turret
		var one := int(out["link"])
		out.erase("link")
		out["links"] = [one] if one >= 0 else []
	if out.has("links"):
		var ls: Array = []
		for l in out["links"]:
			ls.append(int(l))
		out["links"] = ls
	return out


## Fills in cfg for modules that have none (files from before the preset system) and converts the old numbers.
func _migrate() -> void:
	for i in modules.size():
		var m: Dictionary = modules[i]
		var legacy: Dictionary = m.get("_legacy", {})
		m.erase("_legacy")
		var type: String = m["type"]
		if type == ModuleCatalog.LOOSE:
			m["cfg"] = {}
			continue
		var cfg_: Dictionary = m["cfg"]
		if cfg_.has("preset") and not cfg_.has("stats"):
			cfg_["stats"] = {}
		if cfg_.has("preset") and cfg_.has("stats"):    # hand-written files may give only the numbers they change
			var base := ModulePresets.make_cfg(type, str(cfg_["preset"]))
			if not base.is_empty():
				for key in base["stats"]:
					if not (cfg_["stats"] as Dictionary).has(key):
						cfg_["stats"][key] = base["stats"][key]
				if not cfg_.has("kind") and base.has("kind"):
					cfg_["kind"] = base["kind"]
				if not cfg_.has("damage_type") and base.has("damage_type"):
					cfg_["damage_type"] = base["damage_type"]
		if cfg_.is_empty() or not cfg_.has("stats"):
			var fresh := ModulePresets.make_cfg(type, ModulePresets.default_preset(type))
			for key in cfg_:
				fresh[key] = cfg_[key]
			cfg_ = fresh
			m["cfg"] = cfg_
			var vol := maxf(module_volume(i), 0.001)
			if type == ModuleCatalog.THRUSTER and float(legacy.get("power", 0.0)) > 0.0:
				cfg_["stats"]["thrust_per_m3"] = float(legacy["power"]) / vol
			elif type == ModuleCatalog.COMMANDER and int(legacy.get("crew", 0)) > 0:
				cfg_["stats"]["seat_volume"] = vol / int(legacy["crew"])
			elif type == ModuleCatalog.TURRET and float(legacy.get("turn_speed", 0.0)) > 0.0:
				cfg_["stats"]["turn_speed"] = float(legacy["turn_speed"])
		if type == ModuleCatalog.TURRET and not cfg_.has("barrels") and int(legacy.get("barrel", -1)) >= 0:
			cfg_["barrels"] = [int(legacy["barrel"])]


## Compact JSON (small ships, tests).
func to_json() -> String:
	return JSON.stringify(to_dict())


## Human-readable JSON: one vertex per line, one face per line, one module per block.
func to_pretty_json() -> String:
	var d := to_dict()
	var out := "{\n"
	out += "\t\"name\": %s,\n" % JSON.stringify(d["name"])
	out += "\t\"reactor_scale\": %s,\n" % str(d["reactor_scale"])
	out += "\t\"gyro_scale\": %s,\n" % str(d["gyro_scale"])
	out += "\t\"vertices\": [\n"
	var vlines: Array[String] = []
	for v in d["vertices"]:
		vlines.append("\t\t[%s, %s, %s]" % [str(snappedf(v[0], 0.0001)), str(snappedf(v[1], 0.0001)), str(snappedf(v[2], 0.0001))])
	out += ",\n".join(vlines) + "\n\t],\n"
	out += "\t\"modules\": [\n"
	var mblocks: Array[String] = []
	for m in d["modules"]:
		var b := "\t\t{\n\t\t\t\"type\": %s,\n" % JSON.stringify(m["type"])
		if m.has("material"):
			b += "\t\t\t\"material\": %s,\n" % JSON.stringify(m["material"])
		if m.has("dir"):
			b += "\t\t\t\"dir\": %s,\n" % JSON.stringify(m["dir"])
		if m.has("cfg"):
			b += "\t\t\t\"cfg\": %s,\n" % JSON.stringify(m["cfg"])
		for key in MODULE_EXTRA_KEYS:
			if m.has(key):
				b += "\t\t\t%s: %s,\n" % [JSON.stringify(key), str(m[key])]
		b += "\t\t\t\"faces\": [\n"
		var flines: Array[String] = []
		for f in m["faces"]:
			flines.append("\t\t\t\t" + JSON.stringify(f))
		b += ",\n".join(flines) + "\n\t\t\t]\n\t\t}"
		mblocks.append(b)
	out += ",\n".join(mblocks) + "\n\t]"
	if d.has("plan"):
		out += ",\n\t\"plan\": %s" % JSON.stringify(d["plan"])
	out += "\n}\n"
	return out


## The small ship a NEW design starts as (hull, bridge, one engine). Used by the builder and by the editor plugin.
static func starter(p_name: String = "My Ship") -> ShipDesign:
	var d := ShipDesign.new()
	d.ship_name = p_name
	d.add_module(ModuleCatalog.HULL, "box", Vector3.ZERO, Vector3(1.5, 1.0, 2.5))
	d.add_module(ModuleCatalog.COMMANDER, "box", Vector3(0, 1.9, -0.5), Vector3(1.2, 0.95, 1.5))
	d.add_module(ModuleCatalog.THRUSTER, "cylinder", Vector3(0, 0, 3.4), Vector3(0.7, 0.9, 0.7), 12, "", Basis(Vector3.RIGHT, PI * 0.5))
	return d


static func from_json(text: String) -> ShipDesign:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)


## Compressed binary form (huge ships, network). Includes the cached physical sums so loading is instant.
func to_bytes() -> PackedByteArray:
	var mods: Array = []
	for i in modules.size():
		var m: Dictionary = modules[i]
		var fs: FaceSet = m["fs"]
		fs.compact()
		var packed := {"type": m["type"], "material": m.get("material", ""), "cfg": m["cfg"],
			"dir": m["dir"], "ids": fs.ids, "sizes": fs.sizes, "sums": module_sums(i)}
		for key in MODULE_EXTRA_KEYS:
			if m.has(key):
				packed[key] = m[key]
		mods.append(packed)
	var raw := var_to_bytes({"name": ship_name, "reactor_scale": reactor_scale, "gyro_scale": gyro_scale,
		"vertices": vertices, "modules": mods, "plan": plan})
	var out := BINARY_MAGIC.to_utf8_buffer()
	out.append_array(PackedByteArray([0, 0, 0, 0]))
	out.encode_u32(4, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func is_binary(blob: PackedByteArray) -> bool:
	return blob.size() > 8 and blob.slice(0, 4).get_string_from_ascii() == BINARY_MAGIC


static func from_bytes(blob: PackedByteArray) -> ShipDesign:
	if not is_binary(blob):
		return null
	var raw := blob.slice(8).decompress(blob.decode_u32(4), FileAccess.COMPRESSION_ZSTD)
	var data: Variant = bytes_to_var(raw) # never allow objects from the network
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var s := ShipDesign.new()
	s.ship_name = str(data["name"])
	s.reactor_scale = float(data["reactor_scale"])
	s.gyro_scale = float(data["gyro_scale"])
	s.vertices = data["vertices"]
	s.plan = _clean_plan(data.get("plan", {}))
	for m in data["modules"]:
		var fs := FaceSet.new()
		fs.ids = m["ids"]
		fs.sizes = m["sizes"]
		fs.rebuild_starts()
		var entry := {"type": str(m["type"]), "fs": fs, "dir": m["dir"],
			"material": str(m["material"]), "cfg": _clean_cfg(m.get("cfg", {}))}
		for key in MODULE_EXTRA_KEYS:
			if m.has(key):
				entry[key] = m[key]
		if m.get("sums") != null and (m["sums"] as PackedFloat64Array).size() == 11:
			entry["sums"] = m["sums"]
		s.modules.append(entry)
	return s


## Any saved form: pretty/compact JSON text or the binary blob.
static func from_blob(blob: PackedByteArray) -> ShipDesign:
	return from_bytes(blob) if is_binary(blob) else from_json(blob.get_string_from_utf8())


## Blob used on the network and in files: JSON text for small ships, binary for big ones.
func to_blob() -> PackedByteArray:
	if vertices.size() <= PRETTY_JSON_MAX_VERTICES:
		return to_json().to_utf8_buffer()
	return to_bytes()


## Editor only (the game is started from the Godot editor): save into res://ships/ as a PREMADE ship.
func save_premade() -> Error:
	var big := vertices.size() > PRETTY_JSON_MAX_VERTICES
	var path := "res://ships/" + ship_name.validate_filename() + (".ship" if big else ".json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	if big:
		f.store_buffer(to_bytes())
	else:
		f.store_string(to_pretty_json())
	return OK


func save_user() -> Error:
	DirAccess.make_dir_recursive_absolute(Data.SAVED_SHIP_DIR)
	var big := vertices.size() > PRETTY_JSON_MAX_VERTICES
	var path := Data.SAVED_SHIP_DIR + ship_name.validate_filename() + (".ship" if big else ".json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	if big:
		f.store_buffer(to_bytes())
	else:
		f.store_string(to_pretty_json())
	return OK


static func load_file(path: String) -> ShipDesign:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return from_blob(f.get_buffer(f.get_length()))


static func read_blob(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


## [{name, path, premade}] for premade (res://ships) + saved (user://ships)
static func list_ships() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in [[Data.PREMADE_SHIP_DIR, true], [Data.SAVED_SHIP_DIR, false]]:
		var dir := DirAccess.open(entry[0])
		if dir == null:
			continue
		for file in dir.get_files():
			if file.ends_with(".json") or file.ends_with(".ship"):
				out.append({"name": file.get_basename(), "path": entry[0] + file, "premade": entry[1]})
	return out
