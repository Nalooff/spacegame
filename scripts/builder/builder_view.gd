class_name BuilderView
extends Node3D
## Draws everything you see in the builder from the builder's state:
##   ShipMesh     the solid modules
##   VertexDots   one small ball per vertex (hidden in Object mode)
##   OverlayMesh  lines (edges, axes, thruster arrows) and the highlighted faces
## Call redraw(builder) after anything changed. This script never changes the design.

const WIRE_COLOR := Color(0.0, 0.0, 0.0, 0.5)
const WIRE_DIM_COLOR := Color(0.0, 0.0, 0.0, 0.22)
const SELECTED_COLOR := Color(1.0, 0.85, 0.1, 1.0)
const OBJECT_OUTLINE_COLOR := Color(1.0, 0.6, 0.1, 1.0)
const FACE_FILL_COLOR := Color(1.0, 0.85, 0.1, 0.35)
const LINKED_DOT_COLOR := Color(0.35, 1.0, 0.45)
const PLAIN_DOT_COLOR := Color(0.92, 0.92, 0.97)
const THRUSTER_ARROW_COLOR := Color(0.3, 0.95, 1.0)
const EXHAUST_COLOR := Color(1.0, 0.5, 0.1)
const EXHAUST_ZONE_COLOR := Color(1.0, 0.6, 0.1, 0.55)
const TURRET_LINK_COLOR := Color(1.0, 0.4, 0.9, 0.9)
const ORPHAN_FILL_COLOR := Color(1.0, 0.0, 0.3, 0.55)    # faces that belong to no module
const OPEN_FILL_COLOR := Color(1.0, 0.7, 0.0, 0.55)      # faces next to a hole in their container

@onready var ship_mesh: MeshInstance3D = %ShipMesh
@onready var vertex_dots: MultiMeshInstance3D = %VertexDots
@onready var overlay: MeshInstance3D = %OverlayMesh


func redraw(b: ShipBuilder) -> void:
	var highlighted: Array = []
	if b.mode == ShipBuilder.Mode.OBJECT:
		highlighted = b.sel_modules
	ship_mesh.mesh = b.design.build_mesh(PackedFloat32Array(), highlighted)
	redraw_dots(b)
	_redraw_overlay(b)


## Only the dots (cheap; used when the camera zooms so they keep the same screen size).
func redraw_dots(b: ShipBuilder) -> void:
	var mm: MultiMesh = vertex_dots.multimesh
	if b.mode == ShipBuilder.Mode.OBJECT or b.is_large():
		mm.instance_count = 0
		return
	var d := b.design
	var counts := d.vertex_user_counts()
	mm.instance_count = d.vertices.size()
	var size := b.camera_rig.distance * (0.016 if b.mode == ShipBuilder.Mode.VERTEX else 0.009)
	for id in d.vertices.size():
		mm.set_instance_transform(id, Transform3D(Basis.from_scale(Vector3.ONE * size), d.vertices[id]))
		var col := LINKED_DOT_COLOR if counts[id] > 1 else PLAIN_DOT_COLOR
		if b.sel_verts.has(id):
			col = SELECTED_COLOR
		mm.set_instance_color(id, col)


func _redraw_overlay(b: ShipBuilder) -> void:
	var im: ImmediateMesh = overlay.mesh
	im.clear_surfaces()
	var d := b.design
	var in_object_mode := b.mode == ShipBuilder.Mode.OBJECT

	# ---- lines
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for mi in d.modules.size():
		var selected_module := in_object_mode and b.sel_modules.has(mi)
		var color := OBJECT_OUTLINE_COLOR if selected_module else (WIRE_DIM_COLOR if in_object_mode else WIRE_COLOR)
		if b.is_large():
			break # no wireframe on huge ships
		for e in d.module_edges(mi):
			if b.mode == ShipBuilder.Mode.EDGE and b.is_edge_selected(mi, e.x, e.y):
				color = SELECTED_COLOR
			elif b.mode == ShipBuilder.Mode.EDGE:
				color = WIRE_COLOR
			_line(im, d.vertices[e.x], d.vertices[e.y], color)
	# world axes and the forward (-Z) marker
	_line(im, Vector3.ZERO, Vector3.RIGHT, Color(0.9, 0.2, 0.2))
	_line(im, Vector3.ZERO, Vector3.UP, Color(0.2, 0.9, 0.2))
	_line(im, Vector3.ZERO, Vector3.BACK, Color(0.3, 0.4, 1.0))
	_line(im, Vector3.ZERO, Vector3(0, 0, -1.4), Color.WHITE)
	# thruster arrows: cyan = direction it pushes the ship, orange stub = exhaust
	for mi in d.modules.size():
		if d.modules[mi]["type"] != ModuleCatalog.THRUSTER:
			continue
		var c := d.module_centroid(mi)
		var dir: Vector3 = (d.modules[mi]["dir"] as Vector3).normalized()
		var length := 0.8 + 0.4 * float(d.modules[mi]["power"]) / ModuleCatalog.THRUSTER_MAX_POWER
		_line(im, c, c + dir * length, THRUSTER_ARROW_COLOR)
		_line(im, c, c - dir * 0.3, EXHAUST_COLOR)
	# exhaust cones (no-go zones): modules inside them block saving
	if not b.is_large():
		for mi in d.modules.size():
			if d.modules[mi]["type"] == ModuleCatalog.THRUSTER:
				_draw_exhaust(im, ExhaustZone.zone(d, mi))
	# turrets: link line base -> barrel and the firing arc (yaw limits)
	for mi in d.modules.size():
		if d.modules[mi]["type"] == ModuleCatalog.TURRET:
			_draw_turret(im, d, mi)
	# axis lock line while transforming
	if b.tool.is_active() and b.tool.axis_lock != Vector3.ZERO:
		var centre := b.affected_center()
		var axis_color := Color(b.tool.axis_lock.x, b.tool.axis_lock.y, b.tool.axis_lock.z).lerp(Color.WHITE, 0.25)
		_line(im, centre - b.tool.axis_lock * 50.0, centre + b.tool.axis_lock * 50.0, axis_color)
	im.surface_end()

	# ---- problems: loose faces (not in a module) and open containers are filled so they cannot be missed
	if not b.is_large():
		var problems: Array = []           # [module, face, is_loose]
		for mi in d.modules.size():
			var loose: bool = d.modules[mi]["type"] == ModuleCatalog.LOOSE
			var bad: PackedInt32Array = d.faces_alive(mi) if loose else d.open_edge_faces(mi)
			for fi in bad:
				problems.append([mi, fi, loose])
		if not problems.is_empty():
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for pr in problems:
				_fill_face(im, d, pr[0], pr[1], ORPHAN_FILL_COLOR if pr[2] else OPEN_FILL_COLOR)
			im.surface_end()
	# ---- selected faces (translucent fill)
	if b.mode == ShipBuilder.Mode.FACE and not b.sel_faces.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in b.sel_faces:
			var ids := d.face_outward(f.x, f.y)
			var n := (d.vertices[ids[1]] - d.vertices[ids[0]]).cross(d.vertices[ids[2]] - d.vertices[ids[0]]).normalized() * 0.004
			im.surface_set_color(FACE_FILL_COLOR)
			for k in range(1, ids.size() - 1):
				im.surface_add_vertex(d.vertices[ids[0]] + n)
				im.surface_add_vertex(d.vertices[ids[k]] + n)
				im.surface_add_vertex(d.vertices[ids[k + 1]] + n)
		im.surface_end()


func _fill_face(im: ImmediateMesh, d: ShipDesign, mi: int, fi: int, color: Color) -> void:
	var fs: FaceSet = d.modules[mi]["fs"]
	var n := fs.sizes[fi]
	if n < 3:
		return
	var st := fs.starts[fi]
	var v0 := d.vertices[fs.ids[st]]
	im.surface_set_color(color)
	for k in range(1, n - 1):
		for corner in [v0, d.vertices[fs.ids[st + k]], d.vertices[fs.ids[st + k + 1]]]:
			im.surface_add_vertex(corner)
		# (both sides, so it shows whatever the winding is)
		for corner in [v0, d.vertices[fs.ids[st + k + 1]], d.vertices[fs.ids[st + k]]]:
			im.surface_add_vertex(corner)


func _draw_exhaust(im: ImmediateMesh, z: Dictionary) -> void:
	var o: Vector3 = z["origin"]
	var ax: Vector3 = z["axis"]
	var len_: float = z["length"]
	var u := ax.cross(Vector3.UP)
	if u.length() < 0.01:
		u = ax.cross(Vector3.RIGHT)
	u = u.normalized()
	var w := ax.cross(u)
	var prev_ring: Array[Vector3] = []
	for ring in 4:
		var t := len_ * float(ring) / 3.0
		var r: float = float(z["r0"]) + t * float(z["tan_half"])
		var pts: Array[Vector3] = []
		for i in 12:
			var ang := TAU * i / 12.0
			pts.append(o + ax * t + (u * cos(ang) + w * sin(ang)) * r)
		for i in 12:
			_line(im, pts[i], pts[(i + 1) % 12], EXHAUST_ZONE_COLOR)
		if not prev_ring.is_empty() and ring == 3:
			for i in 12:
				_line(im, o, pts[i], EXHAUST_ZONE_COLOR)
		prev_ring = pts


func _draw_turret(im: ImmediateMesh, d: ShipDesign, mi: int) -> void:
	var c := d.module_centroid(mi)
	var bar := int(d.extra(mi, "barrel"))
	if bar >= 0 and bar < d.modules.size():
		_line(im, c, d.module_centroid(bar), TURRET_LINK_COLOR)
		var rest := d.module_centroid(bar) - c
		var up: Vector3 = (d.modules[mi]["dir"] as Vector3).normalized()
		var flat := rest - up * rest.dot(up)
		if flat.length() > 0.001:
			var fwd := flat.normalized()
			var yaw_min := deg_to_rad(float(d.extra(mi, "yaw_min")))
			var yaw_max := deg_to_rad(float(d.extra(mi, "yaw_max")))
			if yaw_max - yaw_min < TAU - 0.01:
				var r := maxf(rest.length() * 1.4, 0.5)
				_line(im, c, c + fwd.rotated(up, yaw_min) * r, TURRET_LINK_COLOR)
				_line(im, c, c + fwd.rotated(up, yaw_max) * r, TURRET_LINK_COLOR)
				var steps := 10
				for i in steps:
					var a0 := lerpf(yaw_min, yaw_max, float(i) / steps)
					var a1 := lerpf(yaw_min, yaw_max, float(i + 1) / steps)
					_line(im, c + fwd.rotated(up, a0) * r, c + fwd.rotated(up, a1) * r, TURRET_LINK_COLOR)


func _line(im: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	im.surface_set_color(color)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
