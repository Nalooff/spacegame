class_name PlanCanvas
extends Control
## DRAWS THE EMERGENCY PLAN of a ship, like the plan on the wall of a real ship.
##
## WHAT YOU SEE (white "ink" on dark paper; colour only appears as damage)
##   * ONE silhouette per deck: the outside layer of everything on that deck. The hull itself is NOT drawn module by module,
##     inside it is simply black.
##   * the ROOMS (commander CMD, turret GUN, engine ENG, radar RDR, antenna ANT) as thin outlines with their code.
##     Where a corridor enters a room the wall is OPEN and narrows to a point, a doorway.
##   * the CORRIDORS as tubes from door to door. A corridor that goes to another deck ends in a STAIRS symbol (with an
##     arrow up or down).
##
## DECKS: stack the modules along the vertical axis. Two modules whose footprints overlap (seen from above) cannot be on
## the same floor, so the upper one gets the next deck. 3 modules above each other = 3 decks. Thin plates (under
## MIN_LAYER_HEIGHT) do not make a deck of their own. ONE deck is shown at a time; SIDE / FRONT are profile views.
##
## Two ways to use it (see PlanView):
##   BUILDER   `editable`: the player draws / erases corridors (the only part of the plan they can change).
##   IN GAME   `ship` set: damage colours of what the commander KNOWS (ShipReports), and the "?" spheres of reports
##             that are still on their way.

signal edit_requested     ## about to change the design (the builder makes an undo checkpoint)
signal edited             ## the plan overrides changed
signal hint(text: String)
signal decks_changed(count: int)

enum Tool { VIEW, DRAW, ERASE, DOOR }
enum View { DECK, SIDE, FRONT, SHEET, ISO }   ## SHEET: all decks on one sheet.  ISO: exploded isometric 3D

const PICK_PX := 12.0
const MIN_LAYER_HEIGHT := 1.0     ## metres: a module thinner than this does not make a deck of its own
const MIN_OVERLAP_AREA := 0.08    ## m2 of shared footprint that forces two modules onto different decks ...
const MIN_OVERLAP_SHARE := 0.2    ## ... and at least this share of the smaller one (modules that only touch stay on one deck)
const MAX_DECKS := 12
## Two "papers": white lines on dark blue (blueprint) or dark lines on white. Line art only: the inside of the ship has the
## colour of the paper, nothing is filled black (except a DEAD room, which is blacked out on purpose).
const DARK_PAPER := Color(0.07, 0.10, 0.15)
const DARK_INK := Color(0.93, 0.96, 1.0)
const LIGHT_PAPER := Color(0.97, 0.97, 0.95)
const LIGHT_INK := Color(0.07, 0.10, 0.18)
const ROOM_CODES := {"commander": "CMD", "turret": "GUN", "thruster": "ENG", "radar": "RDR", "antenna": "ANT"}

var design: ShipDesign
var plan: ShipPlan
var ship: Ship = null            ## live ship (in game); null in the builder
var editable: bool = false
var tool: Tool = Tool.VIEW
var view: View = View.DECK
var deck: int = 0                ## deck shown in DECK view (0 = lowest)
var deck_count: int = 1

var _adj: Array[PackedInt32Array] = []
var _pts3: Array = []                 ## per module: a sample of its points (ship space)
var _foot: Array = []                 ## per module: footprint (x, z) seen from above
var _polys: Array = []                ## per module: outline in the CURRENT view (plan units)
var _layer: PackedInt32Array = PackedInt32Array()   ## per module: its deck
var _deck_y: Array = []               ## per deck: Vector2(lowest y, highest y)
var _outline_cache: Dictionary = {}   ## deck (or -1 in profile views) -> Array[PackedVector2Array] silhouettes
var _elbow_cache: Dictionary = {}     ## edge key -> true when the square-cornered route stays inside the ship
var _scale: float = 10.0
var _origin: Vector2 = Vector2.ZERO
var _from: int = -1                   ## node the path being drawn starts at
var _free_start: Dictionary = {}      ## a corridor that starts in the middle of nowhere: {pos: Vector3, module: int}
var _has_free_start: bool = false
var _paper := DARK_PAPER
var _ink := DARK_INK
var _fill := DARK_PAPER               ## inside the ship (= the paper: line art)
var _grid := Color(1, 1, 1, 0.045)
var explode: float = 1.0              ## ISO: how far the decks / modules are pulled apart (0 = assembled)
var _iso_yaw: float = 0.0             ## ISO: turn of the model (drag with the mouse)
var _iso_zoom: float = 1.0
var _dragging_iso: bool = false
var _iso_hover: int = -1               ## ISO: module under the mouse
var _iso_push: Dictionary = {}         ## ISO: module -> how far it is pushed away from the hovered one (animated)
var _iso_grow: Dictionary = {}         ## ISO: module -> size factor (the hovered one is a little bigger)
var _iso_hits: Array = []              ## ISO: [{mi, poly}] from the last draw, back to front
var _iso_offs: Array[Vector3] = []     ## ISO: the resting offset of every module (decks lifted, modules spread)
var _iso_scale: float = 1.0
## DRAWING LAYERS. The plan is a stack of layers that can be switched on and off (PlanView shows a check box for each).
## Built in: "structure" (hull, outside parts) and "rooms" (rooms, corridors, doors, damage). To add one - say
## "electricity" - call register_layer("power", "Electricity", Callable(self, "_my_layer")) from any script that has the
## canvas: the callable receives the Font and draws with the canvas's own helpers (_node_screen, _screen_poly, ...).
## An optional `iso` callable draws the same layer in the exploded 3D view (receives font, a Callable that projects a
## ship-space point to the screen, and the per-module offsets).
var layers: Array[Dictionary] = []
signal layers_changed
var _mouse: Vector2 = Vector2.ZERO


func _ready() -> void:
	if layers.is_empty():
		register_layer("structure", "Hull", Callable(self, "_layer_structure"))
		register_layer("rooms", "Rooms and corridors", Callable(self, "_layer_rooms"))


## Add a drawing layer (see `layers`). Returns nothing; the PlanView lists it automatically.
func register_layer(id: String, label: String, draw_fn: Callable, iso: Callable = Callable(), enabled: bool = true) -> void:
	for l in layers:
		if l["id"] == id:
			l["draw"] = draw_fn
			l["iso"] = iso
			return
	layers.append({"id": id, "label": label, "draw": draw_fn, "iso": iso, "enabled": enabled})
	layers_changed.emit()


func set_layer_enabled(id: String, on: bool) -> void:
	for l in layers:
		if l["id"] == id:
			l["enabled"] = on
	queue_redraw()


## Load a design (builder) or a live ship (game).
func show_design(d: ShipDesign, can_edit: bool, live: Ship = null) -> void:
	design = d
	editable = can_edit
	ship = live
	_adj = ModuleGraph.build(d).adj if live == null else live._graph.adj if live._graph != null else ModuleGraph.build(d).adj
	rebuild()


## Regenerate the plan and everything drawn from it (after the design changed, or a dent).
func rebuild() -> void:
	if design == null:
		return
	if ship != null and ship.plan_state != null:
		plan = ship.plan_state.plan
	else:
		plan = ShipPlan.generate(design, _adj)
	_elbow_cache.clear()
	_outline_cache.clear()
	_pts3.clear()
	_foot.clear()
	_polys.clear()
	for mi in design.modules.size():
		var sample := PackedVector3Array()
		if design.modules[mi]["type"] != ModuleCatalog.LOOSE:
			var pts := design.module_points(mi)
			var step := maxi(1, int(pts.size() / 90.0))
			for k in range(0, pts.size(), step):
				sample.append(pts[k])
		_pts3.append(sample)
		_foot.append(_hull2d(sample, View.DECK))
		_polys.append(_hull2d(sample, view))
	_compute_layers()
	deck = clampi(deck, 0, deck_count - 1)
	_fit()
	decks_changed.emit(deck_count)
	queue_redraw()


func _hull2d(pts: PackedVector3Array, v: View) -> PackedVector2Array:
	var flat := PackedVector2Array()
	for p in pts:
		flat.append(_project_for(v, p))
	return Geometry2D.convex_hull(flat) if flat.size() >= 3 else PackedVector2Array()


# ----------------------------------------------------------------- decks
## Stack the modules: bottom to top, every module goes one deck above the highest module below it that it overlaps
## (seen from above). Modules that only slightly overlap or are very thin join the deck they overlap most.
func _compute_layers() -> void:
	var n := design.modules.size()
	_layer = PackedInt32Array()
	_layer.resize(n)
	var solid: Array[int] = []
	for mi in n:
		var t: String = design.modules[mi]["type"]
		if t == ModuleCatalog.LOOSE or t == ModuleCatalog.BARREL or (_foot[mi] as PackedVector2Array).size() < 3:
			continue
		var lo := INF
		var hi := -INF
		for p in _pts3[mi]:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		if hi - lo >= MIN_LAYER_HEIGHT and (design.is_room(mi) or ModuleCatalog.CORRIDOR_TYPES.has(t)):
			solid.append(mi)
	solid.sort_custom(func(a: int, b: int) -> bool: return design.module_centroid(a).y < design.module_centroid(b).y)
	var done: Array[int] = []
	var top := 0
	for mi in solid:
		var l := 0
		for other in done:
			if _overlaps(mi, other):
				l = maxi(l, _layer[other] + 1)
		_layer[mi] = mini(l, MAX_DECKS - 1)
		top = maxi(top, _layer[mi])
		done.append(mi)
	for mi in n:       # thin plates, barrels...: the deck of the solid module they overlap most (else the nearest)
		if solid.has(mi) or (_foot[mi] as PackedVector2Array).size() < 3:
			continue
		var best := 0.0
		var pick := -1
		for other in solid:
			var a := _overlap_area(_foot[mi], _foot[other])
			if a > best:
				best = a
				pick = other
		if pick < 0:
			var bd := INF
			for other in solid:
				var dd := design.module_centroid(mi).distance_squared_to(design.module_centroid(other))
				if dd < bd:
					bd = dd
					pick = other
		_layer[mi] = _layer[pick] if pick >= 0 else 0
	deck_count = top + 1
	_deck_y.clear()
	for k in deck_count:
		var lo := INF
		var hi := -INF
		for mi in n:
			if _layer[mi] == k:
				for p in _pts3[mi]:
					lo = minf(lo, p.y)
					hi = maxf(hi, p.y)
		_deck_y.append(Vector2(lo, hi))


## Do two modules share enough footprint that they cannot be on the same deck?
func _overlaps(a: int, b: int) -> bool:
	var area := _overlap_area(_foot[a], _foot[b])
	if area <= MIN_OVERLAP_AREA:
		return false
	var smaller := minf(_poly_area(_foot[a]), _poly_area(_foot[b]))
	return area >= smaller * MIN_OVERLAP_SHARE


static func _poly_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % poly.size()]
		s += p.x * q.y - q.x * p.y
	return absf(s) * 0.5


static func _overlap_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() < 3 or b.size() < 3:
		return 0.0
	var total := 0.0
	for poly in Geometry2D.intersect_polygons(a, b):
		var s := 0.0
		for i in poly.size():
			var p: Vector2 = poly[i]
			var q: Vector2 = poly[(i + 1) % poly.size()]
			s += p.x * q.y - q.x * p.y
		total += absf(s) * 0.5
	return total


func set_view(v: View) -> void:
	view = v
	_iso_hover = -1
	_from = -1
	rebuild()


func set_deck(k: int) -> void:
	deck = clampi(k, 0, deck_count - 1)
	_from = -1
	decks_changed.emit(deck_count)     # (the picker follows)
	queue_redraw()


func set_tool(t: Tool) -> void:
	tool = t
	_from = -1
	hint.emit(_tool_hint())
	queue_redraw()


func _tool_hint() -> String:
	match tool:
		Tool.DRAW:
			return "DRAW: start anywhere inside the ship (a door, a corridor, or empty hull) and click to add bends. Click a corridor to make a junction. Shift = 45 degree steps. Right click / Esc ends."
		Tool.ERASE:
			return "ERASE: click a corridor piece to remove it."
		Tool.DOOR:
			return "DOOR: click a corridor to put a door on it, click the door again to remove it. (Where a corridor enters a room the doorway is automatic: the dotted gap in the wall.)"
	return "Corridors are generated from the modules. Every room needs a way to a commander."


# ----------------------------------------------------------------- projection
func _project(v: Vector3) -> Vector2:
	return _project_for(view, v)


func _project_for(v_: View, v: Vector3) -> Vector2:
	match v_:
		View.SIDE:
			return Vector2(v.z, -v.y)
		View.FRONT:
			return Vector2(v.x, -v.y)
	return Vector2(v.x, v.z)


## 2D plan position -> 3D point, keeping the coordinate that the view does not show from `depth_from`.
func _unproject(p: Vector2, depth_from: Vector3) -> Vector3:
	match view:
		View.SIDE:
			return Vector3(depth_from.x, -p.y, p.x)
		View.FRONT:
			return Vector3(p.x, -p.y, depth_from.z)
	return Vector3(p.x, depth_from.y, p.y)


func _fit() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for poly in _polys:
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
	if lo.x == INF:
		lo = Vector2(-1, -1)
		hi = Vector2(1, 1)
	var extent := (hi - lo).max(Vector2(1, 1))
	var avail := size_or_default() - Vector2(40, 90)   # room for the title block above and the legend below
	_scale = minf(avail.x / extent.x, avail.y / extent.y)
	_origin = Vector2(size_or_default().x * 0.5, 50.0 + (size_or_default().y - 80.0) * 0.5) - (lo + hi) * 0.5 * _scale


func size_or_default() -> Vector2:
	return size if size.x > 50.0 and size.y > 50.0 else Vector2(600, 400)


func _to_screen(p: Vector2) -> Vector2:
	return p * _scale + _origin


func _from_screen(p: Vector2) -> Vector2:
	return (p - _origin) / _scale


func _node_screen(ni: int) -> Vector2:
	return _to_screen(_project(plan.nodes[ni]["pos"]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and design != null:
		_fit()
		queue_redraw()


# ----------------------------------------------------------------- what the commander knows
## Health 0..1 of module `mi` as the commander KNOWS it: 0 = dead, -1 = gone (builder: always 1).
func _ratio(mi: int) -> float:
	if ship == null or ship.reports == null or ship.reports.known_state == null or mi < 0 or mi >= ship.reports.known_hp.size():
		return 1.0
	var hp := ship.reports.known_hp[mi]
	if hp < 0.0:
		return -1.0
	if not ship.reports.known_state.is_working(mi):
		return 0.0 if hp <= 0.0 else minf(hp / maxf(ship.module_max_hp[mi], 0.001), 0.3)   # cut off: shown as badly hurt
	return clampf(hp / maxf(ship.module_max_hp[mi], 0.001), 0.0, 1.0)


## Damage colour: white (fine) -> yellow -> orange -> red -> black (dead).
static func damage_color(r: float, ink: Color = DARK_INK) -> Color:
	if r >= 0.9:
		return ink
	if r >= 0.65:
		return Color(1.0, 0.88, 0.2)
	if r >= 0.4:
		return Color(1.0, 0.58, 0.12)
	if r > 0.0:
		return Color(0.95, 0.18, 0.15)
	return Color(0.0, 0.0, 0.0)


func _known() -> PlanState:
	return ship.reports.known_state if ship != null and ship.reports != null else null


func _edge_ratio(ei: int) -> float:
	var ks := _known()
	if ks == null or ei >= ks.edge_hp.size():
		return 1.0
	var m: int = plan.edges[ei]["module"]
	if m >= 0 and ship.reports.known_hp[m] <= 0.0:
		return 0.0
	return ks.edge_hp[ei]


func _edge_blocked(ei: int) -> bool:
	return _edge_ratio(ei) <= 0.0


# ----------------------------------------------------------------- which deck is a node / module on
func _mod_layer(mi: int) -> int:
	return _layer[mi] if mi >= 0 and mi < _layer.size() else 0


## Deck of a plan node: its module's (a junction belongs to the ROOM it opens into).
func _node_deck(ni: int) -> int:
	var n: Dictionary = plan.nodes[ni]
	if n["kind"] == "joint":
		var ids := str(n["key"]).substr(1).split("_")
		var a := int(ids[0])
		var b := int(ids[1])
		return _mod_layer(b if plan.rooms.has(b) else a)
	return _mod_layer(int(n["module"]))


func _node_visible(ni: int) -> bool:
	if view != View.DECK:
		return true
	if _joint_kind(ni) == "stairs":                       # a stair is seen from BOTH decks it joins
		var m := _joint_modules(ni)
		return _mod_layer(m.x) == deck or _mod_layer(m.y) == deck
	return _node_deck(ni) == deck


## The two modules a joint node sits between ((-1, -1) when `ni` is not a joint).
func _joint_modules(ni: int) -> Vector2i:
	var n: Dictionary = plan.nodes[ni]
	if n["kind"] != "joint":
		return Vector2i(-1, -1)
	var ids := str(n["key"]).substr(1).split("_")
	return Vector2i(int(ids[0]), int(ids[1]))


## What a joint is drawn as: "stairs" (the two modules are on different decks: a small stair marker, no corridor),
## "wall" (two rooms side by side: just a door in the wall, no corridor) or "" (an ordinary corridor joint).
func _joint_kind(ni: int) -> String:
	var m := _joint_modules(ni)
	if m.x < 0:
		return ""
	if _mod_layer(m.x) != _mod_layer(m.y):
		return "stairs"
	if plan.rooms.has(m.x) and plan.rooms.has(m.y):
		return "wall"
	return ""


## Where a stair joint is drawn: straight below / above the room it serves (the room's middle), else at the joint itself.
func _stair_pos(ni: int) -> Vector2:
	var m := _joint_modules(ni)
	for mi in [m.x, m.y]:
		if plan.rooms.has(mi):
			return _node_screen(plan.door_of(mi))
	return _node_screen(ni)


## Edges that are not drawn as a corridor: the stub between a room and a stair, or between two rooms that share a wall.
func _edge_is_hidden(ei: int) -> bool:
	var e: Dictionary = plan.edges[ei]
	for end in [e["a"], e["b"]]:
		var k := _joint_kind(end)
		if k == "wall":
			return true
		if k == "stairs":
			var other: int = e["b"] if end == e["a"] else e["a"]
			if plan.nodes[other]["kind"] == "door":
				return true
	return false


func _poly_of(mi: int) -> PackedVector2Array:
	if view == View.DECK:
		return _foot[mi] if mi < _foot.size() and _mod_layer(mi) == deck else PackedVector2Array()
	return _polys[mi] if mi < _polys.size() else PackedVector2Array()


func _screen_poly(mi: int) -> PackedVector2Array:
	return _to_screen_poly(_poly_of(mi))


func _to_screen_poly(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(_to_screen(p))
	return out


# ----------------------------------------------------------------- the silhouette
## ONE form: the union of every room and hull part on the deck. Only its outside is drawn.
func _silhouettes() -> Array:
	var key := deck if view == View.DECK else -1
	if _outline_cache.has(key):
		return _outline_cache[key]
	var merged: Array = []
	var members: Array[int] = []
	members.append_array(plan.spaces)
	members.append_array(plan.rooms)
	for mi in members:
		if ship != null and mi < ship.module_hp.size() and ship.module_hp[mi] < 0.0:
			continue          # gone modules are not part of the ship any more
		var cur := _poly_of(mi)
		if cur.size() < 3:
			continue
		var rest: Array = []
		for other in merged:
			var res := Geometry2D.merge_polygons(cur, other)
			if res.size() >= 1 and _only_one_outer(res):
				for p in res:
					if not Geometry2D.is_polygon_clockwise(p):
						cur = p
			else:
				rest.append(other)
		rest.append(cur)
		merged = rest
	_outline_cache[key] = merged
	return merged


func _only_one_outer(res: Array) -> bool:
	var n := 0
	for p in res:
		if not Geometry2D.is_polygon_clockwise(p):
			n += 1
	return n == 1


# ----------------------------------------------------------------- doors
## Where the corridor of edge `ei` meets the wall of room `room`: {tip: where the doorway narrows to the corridor,
## hit: the point on the wall, dir: unit vector pointing out of the room}. Empty when the edge does not touch the room.
func _door(ei: int, room: int) -> Dictionary:
	var door_node := plan.door_of(room)
	var e: Dictionary = plan.edges[ei]
	if door_node < 0 or (e["a"] != door_node and e["b"] != door_node):
		return {}
	var other: int = e["b"] if e["a"] == door_node else e["a"]
	if not _node_visible(other):
		return {}
	var c := _node_screen(door_node)
	var o := _node_screen(other)
	if o.distance_to(c) < 1.0:
		return {}
	var dir := (o - c).normalized()
	var poly := _screen_poly(room)
	var best := INF
	var hit := Vector2.ZERO
	for i in poly.size():
		var x: Variant = Geometry2D.segment_intersects_segment(c, c + dir * 4000.0, poly[i], poly[(i + 1) % poly.size()])
		if x != null:
			var d := c.distance_to(x)
			if d < best:
				best = d
				hit = x
	if best == INF:
		return {}
	return {"hit": hit, "dir": dir, "tip": hit}


func _gap() -> float:
	return _tube() * 0.5 + 2.0


func _tube() -> float:
	return clampf(ShipPlan.CORRIDOR_WIDTH * _scale * 0.5, 6.0, 12.0)


## Doors of every room on the deck: room -> Array of door dictionaries.
func _doors() -> Dictionary:
	var out := {}
	for ei in plan.edges.size():
		if _joint_kind(plan.edges[ei]["a"]) == "stairs" or _joint_kind(plan.edges[ei]["b"]) == "stairs":
			continue                                   # a stair is in the room: no doorway, no corridor
		for room in plan.rooms:
			if _mod_layer(room) != deck and view == View.DECK:
				continue
			var dd := _door(ei, room)
			if not dd.is_empty():
				dd["edge"] = ei
				if not out.has(room):
					out[room] = []
				out[room].append(dd)
	return out


# ----------------------------------------------------------------- drawing
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _paper)
	if design == null or plan == null:
		return
	var font := get_theme_default_font()
	if view == View.ISO:
		_draw_iso(font)
	elif view == View.SHEET:
		_draw_sheet(font)
	else:
		_draw_grid()
		_draw_deck_content(font)
	_draw_title_block(font)


## The drawing of ONE deck (or a profile view) with the current deck / _scale / _origin.
func _draw_deck_content(font: Font) -> void:
	_claimed.clear()                                    # label / marker collision check starts afresh each frame
	for l in layers:
		if l["enabled"]:
			(l["draw"] as Callable).call(font)


## LAYER "structure": the hull as ONE glowing double outline, and the parts that are outside it (thrusters, antennas).
func _layer_structure(font: Font) -> void:
	for poly in _silhouettes():
		var sp := _to_screen_poly(poly)
		draw_colored_polygon(sp, _fill)
		draw_polyline(_closed(sp), Color(_ink, 0.10), 9.0, true)       # glow
		draw_polyline(_closed(sp), _ink, 2.6, true)
		for inner in Geometry2D.offset_polygon(sp, -6.0):                # the second wall line
			draw_polyline(_closed(inner), Color(_ink, 0.55), 1.0, true)
	# parts outside the ship: no doorway, no corridor, drawn as an outline with their code (and their damage colour)
	for mi in design.modules.size():
		var t: String = design.modules[mi]["type"]
		if design.is_room(mi) or not ModuleCatalog.EXTERNAL_TYPES.has(t) or (_foot[mi] as PackedVector2Array).size() < 3:
			continue
		if view == View.DECK and _mod_layer(mi) != deck:
			continue
		var poly := _to_screen_poly(_foot[mi] if view == View.DECK else _polys[mi])
		var r := _ratio(mi)
		if r < 0.0:
			draw_polyline(_closed(poly), Color(_ink, 0.2), 1.0)
			continue
		var col := damage_color(r, _ink)
		if r <= 0.0:
			draw_colored_polygon(poly, Color.BLACK)
		draw_polyline(_closed(poly), Color(col, 0.12), 7.0, true)
		draw_polyline(_closed(poly), col if r < 0.9 else Color(_ink, 0.9), 1.6, true)
		var bb := Rect2(poly[0], Vector2.ZERO)
		for pp in poly:
			bb = bb.expand(pp)
		_claim(bb.grow(2.0))                                     # markers and labels keep clear of the outline
		draw_string(font, _centroid(poly) + Vector2(-10, 4), ROOM_CODES.get(t, "???"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 0.9))


## LAYER "rooms": rooms, corridors, doors, damage colours and the "?" spheres.
func _layer_rooms(font: Font) -> void:
	var doors := _doors()
	var door_of_edge := {}          # edge index -> {room: door}: the corridor starts at the tip of the doorway
	for room in doors:
		for dd in doors[room]:
			if not door_of_edge.has(dd["edge"]):
				door_of_edge[dd["edge"]] = {}
			door_of_edge[dd["edge"]][room] = dd
	# 2. corridors: tubes with an outline in the damage colour
	var tube := _tube()
	for pass_i in 2:
		for ei in plan.edges.size():
			var e: Dictionary = plan.edges[ei]
			var va := _node_visible(e["a"])
			var vb := _node_visible(e["b"])
			if va != vb:
				if pass_i == 1 and _joint_kind(e["a"]) != "stairs" and _joint_kind(e["b"]) != "stairs":
					_stairs_at_edge(ei, va)
				continue
			if not va:
				continue
			if _edge_is_hidden(ei):
				continue
			var a := _stair_pos(e["a"]) if _joint_kind(e["a"]) == "stairs" else _node_screen(e["a"])
			var b := _stair_pos(e["b"]) if _joint_kind(e["b"]) == "stairs" else _node_screen(e["b"])
			# a corridor starts at the doorway of a room, not at its centre
			var cut: Dictionary = door_of_edge.get(ei, {})
			for room in cut:
				if plan.door_of(room) == e["a"]:
					a = cut[room]["tip"]
				else:
					b = cut[room]["tip"]
			var corner := _corner(ei, a, b)
			var pts := PackedVector2Array([a, corner, b])
			var r := _edge_ratio(ei)
			var col := damage_color(r, _ink)
			if pass_i == 0:
				draw_polyline(pts, col if r > 0.0 else Color(0.6, 0.6, 0.65), tube + 3.0, true)
			else:
				draw_polyline(pts, _fill if r > 0.0 else Color.BLACK, tube - 1.0, true)
				if r <= 0.0:
					_dashed(a, corner, Color(0.7, 0.7, 0.75))
					_dashed(corner, b, Color(0.7, 0.7, 0.75))
				if e["manual"]:
					draw_circle(corner, 3.0, _ink)
		for ni in plan.nodes.size():                 # bends: round joints so a drawn corridor reads as one tube
			if plan.nodes[ni]["kind"] == "free" and _node_visible(ni):
				draw_circle(_node_screen(ni), (tube + 3.0) * 0.5 if pass_i == 0 else (tube - 1.0) * 0.5, _ink if pass_i == 0 else _fill)
	# 2b. doors on corridors
	if view == View.DECK:
		for dd in plan.doors:
			var ei: int = dd["edge"]
			var e2: Dictionary = plan.edges[ei]
			if not _node_visible(e2["a"]) or not _node_visible(e2["b"]):
				continue
			var cp := _corridor_point(ei, float(dd["t"]))
			_draw_corridor_door(cp["pos"], cp["dir"], damage_color(_edge_ratio(ei), _ink))
	# 2c. stairs: a small marker where a corridor / room goes up or down to another deck
	if view == View.DECK:
		var drawn := {}                                      # one marker per spot and target deck (a room can have several stairs)
		for ni in plan.nodes.size():
			if _joint_kind(ni) == "stairs" and _node_visible(ni):
				var m := _joint_modules(ni)
				var other_deck := _mod_layer(m.y) if _mod_layer(m.x) == deck else _mod_layer(m.x)
				var sp := _stair_pos(ni)
				var dkey := "%d_%d_%d" % [roundi(sp.x / 6.0), roundi(sp.y / 6.0), other_deck]
				if drawn.has(dkey):
					continue
				drawn[dkey] = true
				if plan.rooms.has(m.x if _mod_layer(m.x) == deck else m.y):
					sp += Vector2(20, 3)                         # inside the room, beside its icon and code
				_stair_marker(sp, other_deck, other_deck > deck, Vector2.RIGHT)
	# 3. rooms: thin outline (open at the doors) + the three-letter code. Damage changes the colour once the commander knows.
	for room in plan.rooms:
		if view == View.DECK and _mod_layer(room) != deck:
			continue
		var poly := _screen_poly(room)
		if poly.size() < 3:
			continue
		var r := _ratio(room)
		if r < 0.0:
			draw_polyline(_closed(poly), Color(_ink, 0.2), 1.0)       # gone: a ghost
			continue
		var col := damage_color(r, _ink)
		if r <= 0.0:
			draw_colored_polygon(poly, Color.BLACK)
		elif r < 0.9:
			draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.2))
		var line_col := _ink if r <= 0.0 else (Color(_ink, 0.9) if r >= 0.9 else col)
		draw_polyline(_closed(poly), Color(line_col, 0.10), 8.0, true)                         # glow
		_draw_room_outline(poly, line_col, 2.0 if r >= 0.9 else 2.8, doors.get(room, []))
		if r >= 0.0:
			for inner in Geometry2D.offset_polygon(poly, -4.5):                                 # inner line of the double wall
				draw_polyline(_closed(inner), Color(line_col, 0.5), 1.0, true)
		if r <= 0.0:
			_cross(poly)
		var rtype: String = design.modules[room]["type"]
		var code: String = ROOM_CODES.get(rtype, "???")
		var c := _centroid(poly)
		var label_col := _ink if r >= 0.9 or r <= 0.0 else col
		if r > 0.0:
			_room_icon(rtype, c + Vector2(0, -11), Color(label_col, 0.9))
		var cp0 := _place_text(font, code, c + Vector2(-13, 11), 13)
		draw_string(font, cp0, code, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(label_col, 0.5) if r <= 0.0 else label_col)
		if ship != null and r > 0.0 and ship.reports != null and ship.reports.known_state != null and not ship.reports.known_state.comms_ok:
			var delay := ship.order_delay(room)
			if delay > 0.0 and delay != INF:
				var dt0 := "%.0fs" % delay
				draw_string(font, _place_text(font, dt0, cp0 + Vector2(4, 14), 10), dt0, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(_ink, 0.6))
			elif delay == INF and ship.reports.known_state.reach[room] == INF:
				draw_string(font, _place_text(font, "NO LINK", cp0 + Vector2(-6, 14), 10), "NO LINK", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.45, 0.2))
	# 4. junction marks
	for ni in plan.nodes.size():
		if not _node_visible(ni):
			continue
		var kind: String = plan.nodes[ni]["kind"]
		var pos := _node_screen(ni)
		if kind == "free" or ni == _from:
			draw_circle(pos, 5.0 if ni == _from else 3.0, _ink)
	# 4b. damage reports still on their way: "something happened around here"
	if ship != null and ship.reports != null:
		for rep in ship.reports.pending:
			if not rep.get("sphere", false):
				continue
			var c3: Vector3 = rep["center"]
			var rad: float = rep["radius"]
			var rr := rad
			if view == View.DECK:
				var yr: Vector2 = _deck_y[deck] if deck < _deck_y.size() else Vector2(-INF, INF)
				var dy := maxf(maxf(yr.x - c3.y, c3.y - yr.y), 0.0)      # how far above / below this deck the sphere is
				if dy > rad:
					continue
				rr = sqrt(maxf(rad * rad - dy * dy, 0.1))
			var cs := _to_screen(_project(c3))
			draw_circle(cs, rr * _scale, Color(_ink, 0.06))
			_dashed_circle(cs, rr * _scale)
			draw_string(font, _place_text(font, "?", cs + Vector2(-4, 5), 16), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, _ink)
			if rep.get("nolink", false):
				draw_string(font, _place_text(font, "NO LINK", cs + Vector2(-26, 22), 10), "NO LINK", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.45, 0.2))
	# 5. the path being drawn
	if _from >= 0 and _node_visible(_from):
		draw_line(_node_screen(_from), _snapped(_mouse, _node_screen(_from)), Color(_ink, 0.7), 2.0)
	elif _has_free_start:
		var fs := _to_screen(_project(_free_start["pos"]))
		draw_circle(fs, 5.0, _ink)
		draw_line(fs, _snapped(_mouse, fs), Color(_ink, 0.7), 2.0)


## A tiny symbol for the room type (the little pictograms on a wall plan).
func _room_icon(type: String, c: Vector2, col: Color) -> void:
	match type:
		ModuleCatalog.COMMANDER:                      # a star
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI * 0.5 + TAU * k / 10.0
				pts.append(c + Vector2(cos(a), sin(a)) * (6.0 if k % 2 == 0 else 2.6))
			draw_colored_polygon(pts, Color(col, 0.55))
			draw_polyline(_closed(pts), col, 1.0, true)
		ModuleCatalog.TURRET:                         # crosshair
			draw_arc(c, 5.0, 0.0, TAU, 16, col, 1.2)
			draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), col, 1.0)
			draw_line(c + Vector2(0, -8), c + Vector2(0, 8), col, 1.0)
		ModuleCatalog.RADAR:                          # dish and echo
			draw_arc(c + Vector2(0, 3), 6.0, PI, TAU, 10, col, 1.4)
			draw_line(c + Vector2(0, 3), c + Vector2(5, -5), col, 1.2)
		ModuleCatalog.ANTENNA:                        # waves
			draw_circle(c, 1.8, col)
			draw_arc(c, 5.0, -0.9, 0.9, 6, col, 1.2)
			draw_arc(c, 8.0, -0.9, 0.9, 6, col, 1.2)
			draw_arc(c, 5.0, PI - 0.9, PI + 0.9, 6, col, 1.2)
			draw_arc(c, 8.0, PI - 0.9, PI + 0.9, 6, col, 1.2)


## Frame of the sheet: cut corners, the legend of the room shapes.
func _draw_frame(font: Font) -> void:
	var cut := 14.0
	var w := size.x - 4.0
	var h := size.y - 4.0
	var frame := PackedVector2Array([Vector2(2 + cut, 2), Vector2(w - cut, 2), Vector2(w, 2 + cut), Vector2(w, h - cut), Vector2(w - cut, h), Vector2(2 + cut, h), Vector2(2, h - cut), Vector2(2, 2 + cut)])
	draw_polyline(_closed(frame), Color(_ink, 0.35), 1.5, true)
	if size.x < 560.0 or view == View.SHEET or view == View.ISO:
		return
	var x0 := size.x - 188.0
	var y0 := 12.0
	draw_rect(Rect2(x0, y0, 176.0, 74.0), Color(_paper, 0.9))
	draw_rect(Rect2(x0, y0, 176.0, 74.0), Color(_ink, 0.45), false, 1.0)
	draw_string(font, Vector2(x0 + 8, y0 + 14), "LEGEND", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(_ink, 0.7))
	# stairs: the small disc with an arrow (the number is the deck it leads to)
	var sc := Vector2(x0 + 17.0, y0 + 28.0)
	draw_circle(sc, 6.5, _paper)
	draw_arc(sc, 6.5, 0.0, TAU, 14, _ink, 1.2, true)
	draw_colored_polygon(PackedVector2Array([sc + Vector2(0, -3.2), sc + Vector2(-3.4, 2.6), sc + Vector2(3.4, 2.6)]), _ink)
	draw_string(font, Vector2(x0 + 32, y0 + 32), "Stairs (to deck n)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(_ink, 0.8))
	# corridor
	var cy := y0 + 46.0
	draw_line(Vector2(x0 + 8, cy), Vector2(x0 + 26, cy), _ink, 6.0)
	draw_line(Vector2(x0 + 8, cy), Vector2(x0 + 26, cy), _fill, 4.0)
	draw_string(font, Vector2(x0 + 32, cy + 4), "Corridor", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(_ink, 0.8))
	# every module type: one entry, the code in the box says which one it is
	var my := y0 + 62.0
	draw_rect(Rect2(x0 + 8, my - 5, 18, 10), Color(_ink, 0.8), false, 1.2)
	draw_string(font, Vector2(x0 + 10, my + 3), "ABC", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(_ink, 0.8))
	draw_string(font, Vector2(x0 + 32, my + 4), "Module (code in the box)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(_ink, 0.8))


func _draw_title_block(font: Font) -> void:
	_draw_frame(font)
	var deck_name := "DECK %d OF %d" % [deck + 1, deck_count]
	match view:
		View.SIDE: deck_name = "SIDE ELEVATION"
		View.FRONT: deck_name = "FRONT ELEVATION"
		View.SHEET: deck_name = "DECK PLANS  (%d deck%s)" % [deck_count, "" if deck_count == 1 else "s"]
		View.ISO: deck_name = "EXPLODED ISOMETRIC"
	draw_string(font, Vector2(12, 20), "%s   %s" % [design.ship_name.to_upper(), deck_name], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, _ink)
	if ship != null and ship.reports != null and ship.reports.known_state != null:
		var online := ship.reports.known_state.comms_ok
		draw_string(font, Vector2(12, 38), "COMMS  " + ("ONLINE: orders and reports are instant" if online else "OFFLINE: orders and reports are walked (seconds shown)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(_ink, 0.75))
		if not online:
			var cut := ship.reports.cut_off_rooms(ship).size()
			var lost := ship.reports.unreachable_reports()
			if cut > 0 or lost > 0:
				draw_string(font, Vector2(12, 54), "%d room(s) CUT OFF - cannot be ordered, state unknown.  %d damage report(s) cannot reach the bridge until comms or a corridor is repaired." % [cut, lost], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.45, 0.2))
	var lx := 12.0
	var ly := size.y - 10.0
	for item in [["OK", 1.0], ["WORN", 0.75], ["HURT", 0.5], ["BAD", 0.2], ["DEAD", 0.0]]:
		var cc := damage_color(item[1], _ink)
		draw_rect(Rect2(lx, ly - 9, 12, 10), Color.BLACK if item[1] == 0.0 else cc)
		draw_rect(Rect2(lx, ly - 9, 12, 10), _ink if item[1] == 0.0 else cc, false, 1.0)
		draw_string(font, Vector2(lx + 16, ly), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(_ink, 0.7))
		lx += 62.0


# ----------------------------------------------------------------- paper, sheet and exploded views
func set_paper_white(on: bool) -> void:
	_paper = LIGHT_PAPER if on else DARK_PAPER
	_ink = LIGHT_INK if on else DARK_INK
	_fill = _paper
	_grid = Color(0, 0, 0, 0.06) if on else Color(1, 1, 1, 0.045)
	queue_redraw()


func set_explode(v: float) -> void:
	explode = v
	queue_redraw()


## SHEET: every deck on one sheet, side by side, all at the same scale (like the deck plans on a ship's wall).
func _draw_sheet(font: Font) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for mi in _foot.size():
		for p in (_foot[mi] as PackedVector2Array):
			lo = lo.min(p)
			hi = hi.max(p)
	if lo.x == INF:
		return
	var extent := (hi - lo).max(Vector2(1, 1))
	var area := Rect2(Vector2(10, 52), size - Vector2(20, 100))
	var cols := 1
	var best_scale := 0.0
	for c in range(1, deck_count + 1):          # the grid (columns x rows) that gives the biggest drawing
		var rows := ceili(float(deck_count) / c)
		var sc := minf(area.size.x / c / (extent.x + 3.0), area.size.y / rows / (extent.y + 5.0))
		if sc > best_scale:
			best_scale = sc
			cols = c
	var rows_n := ceili(float(deck_count) / cols)
	var tile := Vector2(area.size.x / cols, area.size.y / rows_n)
	var keep_view := view
	var keep_deck := deck
	var keep_scale := _scale
	var keep_origin := _origin
	view = View.DECK                             # the deck drawing code is reused as it is
	_scale = best_scale
	for k in deck_count:
		var tl := area.position + Vector2((k % cols) * tile.x, floori(float(k) / cols) * tile.y)
		draw_rect(Rect2(tl + Vector2(3, 3), tile - Vector2(6, 6)), Color(_ink, 0.25), false, 1.0)
		deck = k
		_origin = tl + tile * 0.5 + Vector2(0, 8) - (lo + hi) * 0.5 * _scale
		_draw_deck_content(font)
		draw_string(font, tl + Vector2(12, 20), "DECK %d" % (k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, _ink)
	view = keep_view
	deck = keep_deck
	_scale = keep_scale
	_origin = keep_origin


## Isometric projection of a ship-space point, after the turn of the model.
func _iso(p: Vector3) -> Vector2:
	var c := cos(_iso_yaw)
	var sn := sin(_iso_yaw)
	var x := p.x * c - p.z * sn
	var z := p.x * sn + p.z * c
	return Vector2((x - z) * 0.866, (x + z) * 0.5 - p.y * 1.0)


func _iso_depth(p: Vector3) -> float:
	var c := cos(_iso_yaw)
	var sn := sin(_iso_yaw)
	return (p.x * c - p.z * sn) + (p.x * sn + p.z * c)


## EXPLODED ISOMETRIC: every deck lifted above the one below, modules pushed outwards, the corridors drawn inside their
## module and DASHED lines showing where the pieces plug together. Drawn back to front, every module hides what is behind it.
## INTERACTIVE: the module under the mouse grows a little and the other modules are pushed away from it (the nearer, the
## farther), smoothly (see _process). The two normal layers switch whole groups on and off (hull parts / rooms+corridors).
func _draw_iso(font: Font) -> void:
	var n := design.modules.size()
	var centre := Vector3.ZERO
	var cnt := 0
	for mi in plan.rooms:
		centre += design.module_centroid(mi)
		cnt += 1
	for mi in plan.spaces:
		centre += design.module_centroid(mi)
		cnt += 1
	centre /= maxf(cnt, 1)
	var avg_h := 0.0
	for k in deck_count:
		avg_h += (_deck_y[k] as Vector2).y - (_deck_y[k] as Vector2).x
	avg_h /= maxf(deck_count, 1)
	var gap := explode * (avg_h + 2.0)
	var offs: Array[Vector3] = []
	for mi in n:
		var c := design.module_centroid(mi)
		offs.append(Vector3((c.x - centre.x) * 0.35 * explode, _mod_layer(mi) * gap, (c.z - centre.z) * 0.35 * explode))
	for bi in plan.rooms:                          # a barrel travels with its turret base
		for bar in design.barrels_of(bi):
			if bar >= 0 and bar < n:
				offs[bar] = offs[bi]
	var show_hull := _layer_on("structure")
	var show_rooms := _layer_on("rooms")
	var order: Array[int] = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for mi in n:
		if design.modules[mi]["type"] == ModuleCatalog.LOOSE or (ship != null and mi < ship.module_hp.size() and ship.module_hp[mi] < 0.0):
			continue
		for p in design.module_points(mi):
			var q := _iso(p + offs[mi])                  # the fit ignores the hover push, so the picture does not jump
			lo = lo.min(q)
			hi = hi.max(q)
		var is_room := design.is_room(mi)
		if (is_room and show_rooms) or (not is_room and show_hull):
			order.append(mi)
	if order.is_empty():
		return
	var extent := (hi - lo).max(Vector2(1, 1))
	var avail := size - Vector2(120, 130)
	var sc := minf(avail.x / extent.x, avail.y / extent.y) * _iso_zoom
	var org := Vector2(size.x * 0.5, 62.0 + avail.y * 0.5 + 10.0) - (lo + hi) * 0.5 * sc
	_iso_scale = sc
	order.sort_custom(func(a: int, b: int) -> bool:
		return _iso_depth(design.module_centroid(a) + offs[a] + _iso_push.get(a, Vector3.ZERO)) < _iso_depth(design.module_centroid(b) + offs[b] + _iso_push.get(b, Vector3.ZERO)))
	_iso_hits.clear()
	_iso_offs = offs
	for mi in order:
		var t: String = design.modules[mi]["type"]
		var room := design.is_room(mi)
		var cen := design.module_centroid(mi)
		var g: float = _iso_grow.get(mi, 1.0)
		var off: Vector3 = offs[mi] + _iso_push.get(mi, Vector3.ZERO)
		var hovered := mi == _iso_hover
		var r := _ratio(mi) if (room or ModuleCatalog.EXTERNAL_TYPES.has(t)) else 1.0
		var proj := PackedVector2Array()
		for p in design.module_points(mi):
			proj.append(_iso(cen + (p - cen) * g + off) * sc + org)
		var hull2 := Geometry2D.convex_hull(proj) if proj.size() >= 3 else PackedVector2Array()
		if hull2.size() >= 3:
			draw_colored_polygon(hull2, Color.BLACK if r <= 0.0 and (room or ModuleCatalog.EXTERNAL_TYPES.has(t)) else _paper)
			_iso_hits.append({"mi": mi, "poly": hull2})
		var col := damage_color(r, _ink) if (room or ModuleCatalog.EXTERNAL_TYPES.has(t)) else Color(_ink, 0.55)
		if hovered:
			col = Color(col, 1.0)
		var w := (2.4 if hovered else 1.6) if room else (1.8 if hovered else 1.0)
		for e in design.module_edges(mi):
			var ea := _iso(cen + (design.vertices[e.x] - cen) * g + off) * sc + org
			var eb := _iso(cen + (design.vertices[e.y] - cen) * g + off) * sc + org
			draw_line(ea, eb, col if r > 0.0 or not room else Color(0.6, 0.6, 0.65), w, true)
		if hovered and hull2.size() >= 3:
			draw_polyline(_closed(hull2), Color(_ink, 0.25), 6.0, true)
		# corridors inside this module
		if show_rooms:
			for ei in plan.edges.size():
				var ed: Dictionary = plan.edges[ei]
				var owner_m := int(ed["module"])
				if owner_m < 0:
					owner_m = int(plan.nodes[ed["a"]]["module"])
				if owner_m != mi:
					continue
				var pa: Vector3 = plan.nodes[ed["a"]]["pos"]
				var pb: Vector3 = plan.nodes[ed["b"]]["pos"]
				var er := _edge_ratio(ei)
				var ec := damage_color(er, _ink) if er < 0.9 else _ink
				var qa := _iso(cen + (pa - cen) * g + off) * sc + org
				var qb := _iso(cen + (pb - cen) * g + off) * sc + org
				draw_line(qa, qb, ec if er > 0.0 else Color(0.6, 0.6, 0.65), 4.0, true)
				draw_line(qa, qb, _paper, 2.0, true)
		if room or ModuleCatalog.EXTERNAL_TYPES.has(t):
			var cs := _iso(cen + off) * sc + org
			if room and r > 0.0:
				_room_icon(t, cs + Vector2(0, -10), Color(col, 0.9))
			draw_string(font, cs + Vector2(-13, 10), ROOM_CODES.get(t, "???"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col if r > 0.0 else Color(0.8, 0.8, 0.85))
	# dashed assembly lines: where two modules join (a doorway between them)
	if show_rooms:
		for nd in plan.nodes:
			if nd["kind"] != "joint":
				continue
			var ids := str(nd["key"]).substr(1).split("_")
			var ma := int(ids[0])
			var mb := int(ids[1])
			if ma >= offs.size() or mb >= offs.size() or not order.has(ma) or not order.has(mb):
				continue
			var pj: Vector3 = nd["pos"]
			var a := _iso(pj + offs[ma] + _iso_push.get(ma, Vector3.ZERO)) * sc + org
			var b := _iso(pj + offs[mb] + _iso_push.get(mb, Vector3.ZERO)) * sc + org
			if a.distance_to(b) > 3.0:
				_dashed_thin(a, b, Color(_ink, 0.7))
				draw_circle(a, 2.5, _ink)
				draw_circle(b, 2.5, _ink)
	# extra layers added by other scripts (they draw in the same projection)
	for l in layers:
		if l["enabled"] and (l["iso"] as Callable).is_valid():
			(l["iso"] as Callable).call(font, {"offs": offs, "push": _iso_push, "scale": sc, "origin": org, "canvas": self})
	# what is under the mouse
	if _iso_hover >= 0 and _iso_hover < n:
		_draw_hover_card(font, _iso_hover)


func _layer_on(id: String) -> bool:
	for l in layers:
		if l["id"] == id:
			return bool(l["enabled"])
	return true


## Name, health and one line of numbers of the hovered module, next to the mouse.
func _draw_hover_card(font: Font, mi: int) -> void:
	var t: String = design.modules[mi]["type"]
	var lines: Array[String] = ["%s  #%d" % [t.to_upper().replace("_", " "), mi]]
	if ship != null and mi < ship.module_hp.size():
		var hp := ship.module_hp[mi]
		lines.append("GONE" if hp < 0.0 else ("DESTROYED" if hp <= 0.0 else "health %d%%" % int(100.0 * hp / maxf(ship.module_max_hp[mi], 0.001))))
	var kind := design.kind_of(mi)
	if kind != "":
		lines.append(kind)
	lines.append("volume %.1f m3" % design.module_volume(mi))
	var w := 150.0
	var h := 8.0 + lines.size() * 16.0
	var pos := (_mouse + Vector2(16, 16)).min(size - Vector2(w + 6, h + 6))
	draw_rect(Rect2(pos, Vector2(w, h)), Color(_paper, 0.92))
	draw_rect(Rect2(pos, Vector2(w, h)), Color(_ink, 0.6), false, 1.0)
	for i in lines.size():
		draw_string(font, pos + Vector2(8, 16 + i * 16), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, _ink if i == 0 else Color(_ink, 0.8))


## Hover animation: the module under the mouse grows, the others are pushed away from it (nearer ones farther).
func _process(dt: float) -> void:
	if view != View.ISO or not is_visible_in_tree() or design == null:
		return
	var n := design.modules.size()
	var moving := false
	var reach := 1.0
	var hv := Vector3.ZERO
	if _iso_hover >= 0 and _iso_hover < n:
		hv = design.module_centroid(_iso_hover)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for mi in n:
			var c := design.module_centroid(mi)
			lo = lo.min(c)
			hi = hi.max(c)
		reach = maxf((hi - lo).length(), 1.0)
	var k := 1.0 - exp(-12.0 * dt)
	for mi in n:
		var target_push := Vector3.ZERO
		var target_grow := 1.0
		if _iso_hover >= 0 and _iso_hover < n:
			if mi == _iso_hover:
				target_grow = 1.1
			elif _mod_layer(mi) >= 0:
				var away := design.module_centroid(mi) + _iso_offs_of(mi) - (hv + _iso_offs_of(_iso_hover))
				var d := away.length()
				if d > 0.01:
					target_push = away / d * reach * 0.16 * clampf(1.0 - d / (reach * 1.2), 0.08, 1.0) * explode
		var cur: Vector3 = _iso_push.get(mi, Vector3.ZERO)
		var nxt := cur.lerp(target_push, k)
		var g: float = _iso_grow.get(mi, 1.0)
		var ng := lerpf(g, target_grow, k)
		if nxt.distance_to(cur) > 0.0005 or absf(ng - g) > 0.0002:
			moving = true
		_iso_push[mi] = nxt
		_iso_grow[mi] = ng
	if moving:
		queue_redraw()


func _iso_offs_of(mi: int) -> Vector3:
	return _iso_offs[mi] if mi >= 0 and mi < _iso_offs.size() else Vector3.ZERO


## Which module is under screen point `p` (the one drawn on top), -1 for none.
func _iso_pick(p: Vector2) -> int:
	for i in range(_iso_hits.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(p, _iso_hits[i]["poly"]):
			return int(_iso_hits[i]["mi"])
	return -1


func _dashed_thin(a: Vector2, b: Vector2, col: Color) -> void:
	var length := a.distance_to(b)
	var steps := maxi(int(length / 6.0), 1)
	for i in steps:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / steps), a.lerp(b, float(i + 1) / steps), col, 1.2, true)


## Room wall as a thin line, OPEN at every doorway; the wall narrows to a point toward the corridor (a funnel).
func _draw_room_outline(poly: PackedVector2Array, col: Color, width: float, doors: Array) -> void:
	var gap := _gap()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var cuts: Array[Vector2] = []
		for dd in doors:
			var q := Geometry2D.get_closest_point_to_segment(dd["hit"], a, b)
			if q.distance_to(dd["hit"]) < 1.5:
				var t := a.distance_to(q) / length
				cuts.append(Vector2(t - gap / length, t + gap / length))
		cuts.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
		var t0 := 0.0
		for c in cuts:
			if c.x > t0:
				draw_line(a.lerp(b, t0), a.lerp(b, minf(c.x, 1.0)), col, width, true)
			t0 = maxf(t0, c.y)
		if t0 < 1.0:
			draw_line(a.lerp(b, t0), b, col, width, true)
	for dd in doors:
		_draw_doorway(dd, col, width)


## A doorway in a room wall: the wall is HALF OPEN there (dotted line), with door posts and a door leaf swung ajar.
func _draw_doorway(dd: Dictionary, col: Color, width: float) -> void:
	var gap := _gap()
	var dir: Vector2 = dd["dir"]             # out of the room, into the corridor
	var hit: Vector2 = dd["hit"]
	var side := dir.orthogonal() * gap
	draw_dashed_line(hit - side, hit + side, col, maxf(width * 0.8, 1.4), 3.0)       # the "half open" wall
	for sgn in [-1.0, 1.0]:                                                          # door posts
		draw_line(hit + side * sgn - dir * 3.0, hit + side * sgn + dir * 3.0, col, width + 0.6, true)
	var hinge := hit - side                                                          # leaf: hinged at one post, open ~55 degrees
	var closed := side.normalized()
	var leaf_len := gap * 2.0
	var open_dir := (closed * cos(deg_to_rad(55.0)) + dir * sin(deg_to_rad(55.0))).normalized()
	draw_line(hinge, hinge + open_dir * leaf_len, _ink, 2.2, true)
	var a0 := closed.angle()
	var a1 := open_dir.angle()
	draw_arc(hinge, leaf_len, a0, a0 + wrapf(a1 - a0, -PI, PI), 8, Color(_ink, 0.35), 1.0)


## A bulkhead door ON a corridor (placed with the Door tool): a bar across the tube with a seam in the middle.
func _draw_corridor_door(pos: Vector2, dir: Vector2, col: Color) -> void:
	var half := _tube() * 0.5 + 3.0
	var n := dir.orthogonal()
	var d := dir * 3.0
	draw_colored_polygon(PackedVector2Array([pos - n * half - d, pos + n * half - d, pos + n * half + d, pos - n * half + d]), Color(col, 0.95))
	draw_line(pos - n * (half - 1.5), pos + n * (half - 1.5), _fill, 1.0)
	draw_line(pos - n * half - d, pos - n * half + d, _ink, 1.0)


func _draw_grid() -> void:
	var step := _scale * 2.0         # a line every 2 m
	if step < 8.0:
		return
	var x := fposmod(_origin.x, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), _grid)
		x += step
	var y := fposmod(_origin.y, step)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), _grid)
		y += step


## Corner of the square-cornered route a -> b (screen space). The corner is used only when BOTH legs stay inside the ship;
## otherwise the corridor is drawn straight, which is what it really is.
func _corner(ei: int, a: Vector2, b: Vector2) -> Vector2:
	var straight := (a + b) * 0.5
	if absf(a.x - b.x) < 1.0 or absf(a.y - b.y) < 1.0 or bool(plan.edges[ei]["manual"]):
		return straight
	var key: String = plan.edges[ei]["key"]
	if not _elbow_cache.has(key):
		var e: Dictionary = plan.edges[ei]
		var pa: Vector3 = plan.nodes[e["a"]]["pos"]
		var pb: Vector3 = plan.nodes[e["b"]]["pos"]
		var ok := false
		if view == View.DECK:
			var mid := _unproject(_from_screen(Vector2(b.x, a.y)), pa)
			ok = plan.segment_inside(design, pa, Vector3(mid.x, pa.y, mid.z)) and plan.segment_inside(design, Vector3(mid.x, pb.y, mid.z), pb)
		_elbow_cache[key] = ok
	return Vector2(b.x, a.y) if _elbow_cache[key] else straight


## Stairs: the corridor stops with a flight-of-stairs symbol and an arrow up or down to the other deck.
func _stairs_at_edge(ei: int, a_visible: bool) -> void:
	## A corridor that leaves this deck (free corridors etc.): the marker sits just past its visible end.
	var e: Dictionary = plan.edges[ei]
	var near_node: int = e["a"] if a_visible else e["b"]
	var far_node: int = e["b"] if a_visible else e["a"]
	var near := _node_screen(near_node)
	var far := _node_screen(far_node)
	var dir := (far - near).normalized() if near.distance_to(far) > 1.0 else Vector2.RIGHT
	_stair_marker(near + dir * 13.0, _node_deck(far_node), _node_deck(far_node) > _node_deck(near_node), dir)


## SMALL deck-change marker: a little disc holding an up/down triangle, with the number of the deck it leads to next
## to it. Placed through the label collision check (it steps aside when something is already there).
func _stair_marker(pos: Vector2, to_deck: int, up: bool, dir: Vector2) -> void:
	var c := pos
	if not _claim(Rect2(c - Vector2(7, 7), Vector2(14, 14))):
		c = pos + dir.orthogonal() * 12.0
		_claim(Rect2(c - Vector2(7, 7), Vector2(14, 14)))
	draw_circle(c, 6.5, _paper)
	draw_arc(c, 6.5, 0.0, TAU, 14, _ink, 1.2, true)
	var s := 3.2 if up else -3.2
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(-3.4, s * 0.8), c + Vector2(3.4, s * 0.8)]), _ink)
	var font := ThemeDB.fallback_font
	var txt := str(to_deck + 1)
	var tp := _place_text(font, txt, c + Vector2(9, 4), 10)
	draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(_ink, 0.8))


## ---- label collision avoidance: every text / marker claims its rectangle, a later one is moved off an earlier one ----
var _claimed: Array[Rect2] = []


## Reserve `r`; false (and nothing reserved) when it overlaps something already placed.
func _claim(r: Rect2) -> bool:
	for o in _claimed:
		if o.intersects(r):
			return false
	_claimed.append(r)
	return true


## Find a free spot for a text near `pos` (baseline-left point): tries below, above, right, left, then farther below.
func _place_text(font: Font, txt: String, pos: Vector2, fsize: int) -> Vector2:
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var h := float(fsize)
	var tries := [Vector2.ZERO, Vector2(0, h + 2), Vector2(0, -h - 2), Vector2(w + 4, 0), Vector2(-w - 4, 0), Vector2(0, 2 * h + 4), Vector2(0, -2 * h - 4)]
	for off in tries:
		var p: Vector2 = pos + off
		if _claim(Rect2(p + Vector2(-1, -h), Vector2(w + 2, h + 2))):
			return p
	return pos


func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var c := poly.duplicate()
	if poly.size() > 0:
		c.append(poly[0])
	return c


func _centroid(poly: PackedVector2Array) -> Vector2:
	var s := Vector2.ZERO
	for p in poly:
		s += p
	return s / maxf(poly.size(), 1)


func _cross(poly: PackedVector2Array) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	draw_line(lo, hi, Color(_ink, 0.5), 1.0)
	draw_line(Vector2(lo.x, hi.y), Vector2(hi.x, lo.y), Color(_ink, 0.5), 1.0)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var length := a.distance_to(b)
	var steps := maxi(int(length / 10.0), 1)
	for i in steps:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / steps), a.lerp(b, float(i + 1) / steps), col, 2.0)


func _dashed_circle(c: Vector2, r: float) -> void:
	var n := 28
	for i in n:
		if i % 2 == 0:
			draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 4, _ink, 1.5)


# ----------------------------------------------------------------- editing (builder)
func _gui_input(event: InputEvent) -> void:
	if view == View.ISO:
		if event is InputEventMouseButton:
			var mb_iso := event as InputEventMouseButton
			if mb_iso.button_index == MOUSE_BUTTON_LEFT or mb_iso.button_index == MOUSE_BUTTON_RIGHT:
				_dragging_iso = mb_iso.pressed
			elif mb_iso.pressed and mb_iso.button_index == MOUSE_BUTTON_WHEEL_UP:
				_iso_zoom = minf(_iso_zoom * 1.1, 4.0)
				queue_redraw()
			elif mb_iso.pressed and mb_iso.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_iso_zoom = maxf(_iso_zoom / 1.1, 0.3)
				queue_redraw()
		elif event is InputEventMouseMotion:
			_mouse = (event as InputEventMouseMotion).position
			if _dragging_iso:
				_iso_yaw += (event as InputEventMouseMotion).relative.x * 0.01
				_iso_hover = -1
			else:
				_iso_hover = _iso_pick(_mouse)
			queue_redraw()
		return
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		if _from >= 0 or _has_free_start:
			queue_redraw()
	if not editable or tool == Tool.VIEW or design == null or plan == null:
		return
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_from = -1
		_has_free_start = false
		queue_redraw()
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_from = -1
		_has_free_start = false
		queue_redraw()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if tool == Tool.ERASE:
		_erase_at(mb.position)
	elif tool == Tool.DOOR:
		_door_click(mb.position)
	else:
		_draw_click(mb.position)


func _node_at(p: Vector2) -> int:
	var best := PICK_PX
	var out := -1
	for ni in plan.nodes.size():
		if not _node_visible(ni):
			continue
		var d := _node_screen(ni).distance_to(p)
		if d < best:
			best = d
			out = ni
	return out


func _plan_edit() -> Dictionary:
	if design.plan.is_empty():
		design.plan = {"removed": [], "free": {}, "added": [], "uid": 0, "doors": []}
	if not design.plan.has("doors"):
		design.plan["doors"] = []
	return design.plan


## SHIFT while drawing: the next piece snaps to a multiple of 45 degrees from where it starts.
func _snapped(p: Vector2, from_screen: Vector2) -> Vector2:
	if not Input.is_key_pressed(KEY_SHIFT):
		return p
	var v := p - from_screen
	if v.length() < 4.0:
		return p
	var ang := snappedf(v.angle(), PI / 4.0)
	return from_screen + Vector2.from_angle(ang) * v.length()


## Where does a click on empty space put a bend / start? Returns {pos: Vector3, module: int} or {} when outside the ship.
func _free_point(p: Vector2, from_pos: Vector3, has_from: bool) -> Dictionary:
	var owner_mi := _module_under(_from_screen(p))
	if owner_mi < 0:
		hint.emit("A corridor must stay inside the ship: click on the hull or a room.")
		return {}
	var pos3 := _unproject(_from_screen(p), Vector3(0, design.module_centroid(owner_mi).y, 0))
	if not plan.inside_ship(design, pos3):
		hint.emit("That point is outside the ship.")
		return {}
	if has_from and not plan.segment_inside(design, from_pos, pos3):
		hint.emit("That corridor would leave the ship.")
		return {}
	return {"pos": pos3, "module": owner_mi}


## The drawn corridor closest to screen point `p`: {edge, point (screen), t} or {} when none is within `max_px`.
func _edge_near(p: Vector2, max_px: float) -> Dictionary:
	var best := max_px
	var out := {}
	for ei in plan.edges.size():
		var e: Dictionary = plan.edges[ei]
		if not _node_visible(e["a"]) or not _node_visible(e["b"]):
			continue
		var a := _node_screen(e["a"])
		var b := _node_screen(e["b"])
		var c := _corner(ei, a, b)
		for seg in [[a, c], [c, b]]:
			var q := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
			var d := p.distance_to(q)
			if d < best and q.distance_to(a) > PICK_PX and q.distance_to(b) > PICK_PX:
				best = d
				out = {"edge": ei, "point": q}
	return out


## A new free node on corridor `ei` at screen point `q`: the corridor is split in two (a junction). Returns the node key.
func _split_edge(ei: int, q: Vector2) -> String:
	var e: Dictionary = plan.edges[ei]
	var pa: Vector3 = plan.nodes[e["a"]]["pos"]
	var pb: Vector3 = plan.nodes[e["b"]]["pos"]
	var sa := _node_screen(e["a"])
	var sb := _node_screen(e["b"])
	var t := clampf((q - sa).dot(sb - sa) / maxf((sb - sa).length_squared(), 0.001), 0.05, 0.95)
	var pos3 := pa.lerp(pb, t)
	var owner_m := int(e["module"]) if int(e["module"]) >= 0 else int(plan.nodes[e["a"]]["module"])
	var pl := _plan_edit()
	pl["uid"] = int(pl["uid"]) + 1
	var key := "f%d" % int(pl["uid"])
	pl["free"][key] = [pos3.x, pos3.y, pos3.z, owner_m]
	var ka: String = plan.nodes[e["a"]]["key"]
	var kb: String = plan.nodes[e["b"]]["key"]
	if e["manual"]:
		var kept: Array = []
		for pair in pl["added"]:
			var k1 := str(pair[0])
			var k2 := str(pair[1])
			if (k1 + "|" + k2 if k1 < k2 else k2 + "|" + k1) != e["key"]:
				kept.append(pair)
		pl["added"] = kept
	else:
		(pl["removed"] as Array).append(e["key"])
	pl["added"].append([ka, key])
	pl["added"].append([key, kb])
	return key


func _draw_click(p: Vector2) -> void:
	if view != View.DECK:
		hint.emit("Corridors are drawn on a deck: pick the Decks view and a deck.")
		return
	var from_screen := Vector2.ZERO
	if _from >= 0:
		from_screen = _node_screen(_from)
	elif _has_free_start:
		from_screen = _to_screen(_project(_free_start["pos"]))
	var drawing := _from >= 0 or _has_free_start
	if drawing:
		p = _snapped(p, from_screen)
	var hit := _node_at(p)
	if hit < 0:
		# a click on an existing corridor makes a JUNCTION there (the corridor is split)
		var near := _edge_near(p, 7.0)
		if not near.is_empty():
			edit_requested.emit()
			var jkey := _split_edge(int(near["edge"]), near["point"])
			if _has_free_start:
				_commit_free_start(jkey)
			elif _from >= 0:
				var pl3 := _plan_edit()
				pl3["added"].append([str(plan.nodes[_from]["key"]), jkey])
				_regenerate()
				_from = plan.node_index(jkey)
				return
			_regenerate()
			_from = plan.node_index(jkey)
			return
		var from_pos := Vector3.ZERO
		if _from >= 0:
			from_pos = plan.nodes[_from]["pos"]
		elif _has_free_start:
			from_pos = _free_start["pos"]
		var fp := _free_point(p, from_pos, drawing)
		if fp.is_empty():
			return
		if not drawing:
			_free_start = fp                       # the corridor starts here, in the middle of the hull: it needs no room
			_has_free_start = true
			hint.emit("Corridor started. Click to add bends or end it on a door, a junction or another corridor. Shift = 45 degree steps.")
			queue_redraw()
			return
		edit_requested.emit()
		var pl := _plan_edit()
		pl["uid"] = int(pl["uid"]) + 1
		var key := "f%d" % int(pl["uid"])
		pl["free"][key] = [fp["pos"].x, fp["pos"].y, fp["pos"].z, fp["module"]]
		if _has_free_start:
			_commit_free_start(key)
		else:
			pl["added"].append([str(plan.nodes[_from]["key"]), key])
		_regenerate()
		_from = plan.node_index(key)
		return
	if _has_free_start:                            # ends on an existing node
		var tgt: Vector3 = plan.nodes[hit]["pos"]
		if not plan.segment_inside(design, _free_start["pos"], tgt):
			hint.emit("That corridor would leave the ship.")
			return
		edit_requested.emit()
		_commit_free_start(str(plan.nodes[hit]["key"]))
		_regenerate()
		_from = plan.node_index(str(plan.nodes[hit]["key"]))
		return
	if _from < 0:
		_from = hit
		queue_redraw()
		return
	if hit == _from:
		return
	if not plan.segment_inside(design, plan.nodes[_from]["pos"], plan.nodes[hit]["pos"]):
		hint.emit("That corridor would leave the ship.")
		return
	edit_requested.emit()
	var pl2 := _plan_edit()
	pl2["added"].append([str(plan.nodes[_from]["key"]), str(plan.nodes[hit]["key"])])
	_regenerate()
	_from = plan.node_index(str(plan.nodes[hit]["key"])) if hit < plan.nodes.size() else -1


## The corridor that started in free space becomes real: its start node is created and joined to node `end_key`.
func _commit_free_start(end_key: String) -> void:
	var pl := _plan_edit()
	pl["uid"] = int(pl["uid"]) + 1
	var skey := "f%d" % int(pl["uid"])
	var sp: Vector3 = _free_start["pos"]
	pl["free"][skey] = [sp.x, sp.y, sp.z, int(_free_start["module"])]
	pl["added"].append([skey, end_key])
	_has_free_start = false


func _module_under(p: Vector2) -> int:
	var best := -1
	for mi in plan.spaces:
		var poly := _poly_of(mi)
		if poly.size() >= 3 and Geometry2D.is_point_in_polygon(p, poly):
			return mi
	for mi in plan.rooms:
		var poly := _poly_of(mi)
		if poly.size() >= 3 and Geometry2D.is_point_in_polygon(p, poly):
			best = mi
	return best


## Screen point and direction at fraction `t` along the drawn corridor of edge `ei` (a -> bend -> b).
func _corridor_point(ei: int, t: float) -> Dictionary:
	var e: Dictionary = plan.edges[ei]
	var a := _node_screen(e["a"])
	var b := _node_screen(e["b"])
	var c := _corner(ei, a, b)
	var l1 := a.distance_to(c)
	var l2 := c.distance_to(b)
	var at := t * (l1 + l2)
	if at <= l1 and l1 > 0.001:
		return {"pos": a.lerp(c, at / l1), "dir": (c - a).normalized()}
	if l2 > 0.001:
		return {"pos": c.lerp(b, (at - l1) / l2), "dir": (b - c).normalized()}
	return {"pos": a, "dir": Vector2.RIGHT}


## Door tool: click a corridor to add a door there; click an existing door to take it away.
func _door_click(p: Vector2) -> void:
	if view != View.DECK:
		hint.emit("Doors are placed on a deck: pick the Decks view and a deck.")
		return
	var best := 10.0
	var which := -1
	var best_t := 0.5
	for ei in plan.edges.size():
		var e: Dictionary = plan.edges[ei]
		if not _node_visible(e["a"]) or not _node_visible(e["b"]):
			continue
		for k in 41:                       # sample the corridor: close enough and where along it
			var t := k / 40.0
			var d := p.distance_to((_corridor_point(ei, t)["pos"] as Vector2))
			if d < best:
				best = d
				which = ei
				best_t = t
	if which < 0:
		return
	edit_requested.emit()
	var pl := _plan_edit()
	var key: String = plan.edges[which]["key"]
	var list: Array = pl["doors"]
	for i in list.size():                  # an existing door close to the click goes away
		if str(list[i][0]) == key and absf(float(list[i][1]) - best_t) < 0.1:
			list.remove_at(i)
			_regenerate()
			return
	list.append([key, snappedf(clampf(best_t, 0.1, 0.9), 0.01)])
	_regenerate()


func _erase_at(p: Vector2) -> void:
	var best := 8.0
	var which := -1
	for ei in plan.edges.size():
		if not _node_visible(plan.edges[ei]["a"]) or not _node_visible(plan.edges[ei]["b"]):
			continue
		var a := _node_screen(plan.edges[ei]["a"])
		var b := _node_screen(plan.edges[ei]["b"])
		var corner := _corner(ei, a, b)
		var d := minf(p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, corner)), p.distance_to(Geometry2D.get_closest_point_to_segment(p, corner, b)))
		if d < best:
			best = d
			which = ei
	if which < 0:
		return
	edit_requested.emit()
	var e: Dictionary = plan.edges[which]
	var pl := _plan_edit()
	if e["manual"]:
		var kept: Array = []
		for pair in pl["added"]:
			var ka := str(pair[0])
			var kb := str(pair[1])
			var k := ka + "|" + kb if ka < kb else kb + "|" + ka
			if k != e["key"]:
				kept.append(pair)
		pl["added"] = kept
	else:
		(pl["removed"] as Array).append(e["key"])
	_prune_free_nodes(pl)
	_regenerate()


## Drop free nodes that no drawn corridor uses any more.
func _prune_free_nodes(pl: Dictionary) -> void:
	for k in (pl["free"] as Dictionary).keys():
		var used := false
		for pair in pl["added"]:
			if str(pair[0]) == k or str(pair[1]) == k:
				used = true
		if not used:
			(pl["free"] as Dictionary).erase(k)


## Forget every change: the plan is generated again from the modules.
func reset_plan() -> void:
	if design == null or design.plan.is_empty():
		return
	edit_requested.emit()
	design.plan = {}
	_from = -1
	_regenerate()


func _regenerate() -> void:
	_elbow_cache.clear()
	plan = ShipPlan.generate(design, _adj)
	edited.emit()
	queue_redraw()
