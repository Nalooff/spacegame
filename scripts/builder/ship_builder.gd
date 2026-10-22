class_name ShipBuilder
extends Node3D
## The ship builder ("Creation"). Root script of scenes/ship_builder.tscn.
##
## HOW THE EDITOR IS ORGANISED (one file each, all are nodes in the scene):
##   ship_builder.gd   (this)  state + picking + every editing action
##   builder_ui.gd             all buttons / panels (reads this node's state, calls its actions)
##   builder_view.gd           draws solid mesh, vertex dots, wireframe, highlights
##   builder_camera.gd         orbit camera
##   transform_tool.gd         Blender-style G / R / S
##   ../data/mesh_ops.gd       topology edits (extrude, add vertex on edge, connect...)
##   undo_stack.gd             Ctrl+Z / Ctrl+Y
##
## SELECTION MODES (like Blender):  1 Object   2 Vertex   3 Edge   4 Face   (Tab toggles Object <-> Vertex)
## KEYS: G grab, R rotate, S scale (then X/Y/Z to lock an axis, click/Enter = ok, Esc/RMB = cancel)
##       E extrude face, W add vertex on edge, J connect vertices, L link, U unlink, M mirror,
##       Shift+D duplicate, X/Del delete, F frame selection, A select all, Alt+A select none,
##       Ctrl+Z undo, Ctrl+Y redo, Ctrl+S save.

enum Mode { OBJECT, VERTEX, EDGE, FACE }

## Text for the status bar / messages.
signal message(text: String)

const PICK_VERTEX_PX := 14.0
const PICK_EDGE_PX := 9.0
const LINK_DISTANCE := 0.18       # auto-link when a dropped vertex is this close to another module's vertex
const DRAG_START_PX := 5.0        # mouse must move this far with the button down to start a drag

@onready var camera_rig: BuilderCamera = %CameraRig
@onready var camera: Camera3D = %Camera
@onready var view: BuilderView = %View
@onready var tool: BuilderTransformTool = %TransformTool

# ----------------------------------------------------------------- state
var design: ShipDesign = ShipDesign.new()
var mode: Mode = Mode.OBJECT
## Selections. Only the one for the current mode is used.
var sel_modules: Array[int] = []        # OBJECT: module indices
var sel_verts: Array[int] = []          # VERTEX: vertex ids
var sel_edges: Array[Vector3i] = []     # EDGE:   (module, vertex a, vertex b) with a < b
var sel_faces: Array[Vector2i] = []     # FACE:   (module, face index)
## The module the side panels talk about (type, thruster settings...). -1 = none.
var active_module: int = -1

var snap_step: float = 0.1              # 0 = no snapping (set from the UI)
var auto_link: bool = true              # link a dropped vertex to a neighbour's vertex (set from the UI)

var _undo := UndoStack.new()
var _last_checkpoint_key := ""
var _last_checkpoint_msec := 0
var _press_pos := Vector2.ZERO          # where the left mouse button went down
var _pressing := false                  # left button is down on a selectable element
var _remembered_edit_mode: Mode = Mode.VERTEX


func _ready() -> void:
	tool.builder = self
	tool.finished.connect(_on_transform_finished)
	camera_rig.view_changed.connect(_on_camera_moved)
	if Data.builder_open_path != "":
		var loaded := ShipDesign.load_file(Data.builder_open_path)
		if loaded != null:
			design = loaded
		Data.builder_open_path = ""
	else:
		new_ship()
	on_design_changed()


# =====================================================================
#  Changing state -> telling the view and the UI
# =====================================================================
## The design structure/properties changed (modules added, type changed...).
func on_design_changed() -> void:
	design.invalidate()
	view.redraw(self)
	BusEvent.builder_design_changed.emit()


## Only vertex positions changed (dragging). Cheap path, no UI rebuild of lists.
func on_geometry_changed() -> void:
	design.invalidate()
	view.redraw(self)
	BusEvent.builder_design_changed.emit()


## Selection / mode changed.
func on_selection_changed() -> void:
	view.redraw(self)
	BusEvent.builder_selection_changed.emit()


func _on_camera_moved() -> void:
	if is_node_ready() and view != null:
		view.redraw_dots(self)


func say(text: String) -> void:
	message.emit(text)


# =====================================================================
#  Undo / redo
# =====================================================================
## Call BEFORE changing the design. `key` merges rapid repeats (e.g. typing in a SpinBox) into one step.
func checkpoint(key: String = "") -> void:
	var now := Time.get_ticks_msec()
	if key != "" and key == _last_checkpoint_key and now - _last_checkpoint_msec < 1200:
		_last_checkpoint_msec = now
		return
	_last_checkpoint_key = key
	_last_checkpoint_msec = now
	_undo.push(design.to_blob())


func can_undo() -> bool:
	return _undo.can_undo()


func can_redo() -> bool:
	return _undo.can_redo()


func undo() -> void:
	_restore(_undo.undo(design.to_blob()), "Undo")


func redo() -> void:
	_restore(_undo.redo(design.to_blob()), "Redo")


func _restore(snapshot: PackedByteArray, label: String) -> void:
	if snapshot.is_empty():
		say("Nothing to %s." % label.to_lower())
		return
	var restored := ShipDesign.from_blob(snapshot)
	if restored == null:
		return
	design = restored
	_last_checkpoint_key = ""
	clear_selection()
	on_design_changed()
	say(label)


# =====================================================================
#  Modes and selection
# =====================================================================
func set_mode(new_mode: Mode) -> void:
	if tool.is_active():
		return
	if new_mode != Mode.OBJECT:
		_remembered_edit_mode = new_mode
	mode = new_mode
	sel_modules.clear()
	sel_verts.clear()
	sel_edges.clear()
	sel_faces.clear()
	on_selection_changed()


func clear_selection() -> void:
	sel_modules.clear()
	sel_verts.clear()
	sel_edges.clear()
	sel_faces.clear()
	active_module = -1
	on_selection_changed()


func select_all() -> void:
	clear_selection()
	match mode:
		Mode.OBJECT:
			for i in design.modules.size():
				sel_modules.append(i)
		Mode.VERTEX:
			for id in design.vertices.size():
				sel_verts.append(id)
		Mode.EDGE:
			for mi in design.modules.size():
				for e in design.module_edges(mi):
					sel_edges.append(Vector3i(mi, e.x, e.y))
		Mode.FACE:
			for mi in design.modules.size():
				for fi in (design.modules[mi]["fs"] as FaceSet).alive_count():
					sel_faces.append(Vector2i(mi, fi))
	on_selection_changed()


func is_edge_selected(mi: int, a: int, b: int) -> bool:
	return sel_edges.has(Vector3i(mi, a, b))


func has_selection() -> bool:
	return not (sel_modules.is_empty() and sel_verts.is_empty() and sel_edges.is_empty() and sel_faces.is_empty())


## One-line description for the UI.
func selection_summary() -> String:
	match mode:
		Mode.OBJECT: return "%d module(s) selected" % sel_modules.size()
		Mode.VERTEX: return "%d vertex(es) selected" % sel_verts.size()
		Mode.EDGE: return "%d edge(s) selected" % sel_edges.size()
		_: return "%d face(s) selected" % sel_faces.size()


## Every vertex id that a move/rotate/scale would affect, depending on the mode.
func affected_vertices() -> PackedInt32Array:
	var seen := {}
	match mode:
		Mode.OBJECT:
			for mi in sel_modules:
				for id in design.module_vertex_ids(mi):
					seen[id] = true
		Mode.VERTEX:
			for id in sel_verts:
				seen[id] = true
		Mode.EDGE:
			for e in sel_edges:
				seen[e.y] = true
				seen[e.z] = true
		Mode.FACE:
			for f in sel_faces:
				for id in (design.modules[f.x]["fs"] as FaceSet).face(f.y):
					seen[id] = true
	return PackedInt32Array(seen.keys())


func affected_center() -> Vector3:
	var ids := affected_vertices()
	if ids.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for id in ids:
		c += design.vertices[id]
	return c / ids.size()


# =====================================================================
#  Picking (what is under the mouse?)
# =====================================================================
## Above this many vertices the builder switches to "large ship" mode: no vertex dots / wireframe and no
## vertex / edge / face picking (those loops run in GDScript over every vertex). Modules can still be
## selected, moved, duplicated, deleted. Big ships are meant to come from imported meshes or generators.
const DETAIL_LIMIT := 30000

func is_large() -> bool:
	return design.vertices.size() > DETAIL_LIMIT


func _pick_vertex(mouse: Vector2) -> int:
	if is_large():
		return -1
	var best := -1
	var best_dist := PICK_VERTEX_PX
	for id in design.vertices.size():
		var p := design.vertices[id]
		if camera.is_position_behind(p):
			continue
		var d := camera.unproject_position(p).distance_to(mouse)
		if d < best_dist:
			best_dist = d
			best = id
	return best


## Returns Vector3i(module, a, b) or Vector3i(-1, 0, 0).
func _pick_edge(mouse: Vector2) -> Vector3i:
	if is_large():
		return Vector3i(-1, 0, 0)
	var best := Vector3i(-1, 0, 0)
	var best_dist := PICK_EDGE_PX
	for mi in design.modules.size():
		for e in design.module_edges(mi):
			var pa := design.vertices[e.x]
			var pb := design.vertices[e.y]
			if camera.is_position_behind(pa) or camera.is_position_behind(pb):
				continue
			var d := _distance_to_segment(mouse, camera.unproject_position(pa), camera.unproject_position(pb))
			if d < best_dist:
				best_dist = d
				best = Vector3i(mi, e.x, e.y)
	return best


## Returns Vector2i(module, face) or Vector2i(-1, -1).
func _pick_face(mouse: Vector2) -> Vector2i:
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if is_large():
		# large ship: pick the module whose bounding box the ray hits first (face index is not needed for modules)
		var best_m := -1
		var best_d := INF
		for mi in design.modules.size():
			var box := AABB()
			var first := true
			for p in design.module_points(mi):
				box = AABB(p, Vector3.ZERO) if first else box.expand(p)
				first = false
			var hit: Variant = box.intersects_ray(from, dir)
			if hit != null and from.distance_to(hit) < best_d:
				best_d = from.distance_to(hit)
				best_m = mi
		return Vector2i(best_m, 0) if best_m >= 0 else Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_t := INF
	for mi in design.modules.size():
		var faces: Array = design.faces_array(mi)
		for fi in faces.size():
			var ids := design.face_outward(mi, fi)
			for k in range(1, ids.size() - 1):
				var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir,
					design.vertices[ids[0]], design.vertices[ids[k]], design.vertices[ids[k + 1]])
				if hit != null and from.distance_to(hit) < best_t:
					best_t = from.distance_to(hit)
					best = Vector2i(mi, fi)
	return best


func _pick_module(mouse: Vector2) -> int:
	var hit := _pick_face(mouse)
	return hit.x


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Click on the viewport: select what is under the mouse in the current mode.
## Returns true if something was under the mouse.
func _select_at(mouse: Vector2, additive: bool) -> bool:
	var found := false
	match mode:
		Mode.OBJECT:
			var m := _pick_module(mouse)
			found = m >= 0
			if found:
				if additive and sel_modules.has(m):
					sel_modules.erase(m)
				else:
					if not additive:
						sel_modules.clear()
					sel_modules.append(m)
				active_module = m
		Mode.VERTEX:
			var v := _pick_vertex(mouse)
			found = v >= 0
			if found:
				if additive and sel_verts.has(v):
					sel_verts.erase(v)
				else:
					if not additive:
						sel_verts.clear()
					sel_verts.append(v)
				var users := design.vertex_users(v)
				if not users.is_empty() and not users.has(active_module):
					active_module = users[0]
		Mode.EDGE:
			var e := _pick_edge(mouse)
			found = e.x >= 0
			if found:
				if additive and sel_edges.has(e):
					sel_edges.erase(e)
				else:
					if not additive:
						sel_edges.clear()
					sel_edges.append(e)
				active_module = e.x
		Mode.FACE:
			var f := _pick_face(mouse)
			found = f.x >= 0
			if found:
				if additive and sel_faces.has(f):
					sel_faces.erase(f)
				else:
					if not additive:
						sel_faces.clear()
					sel_faces.append(f)
				active_module = f.x
	if not found and not additive:
		clear_selection()
		return false
	on_selection_changed()
	return found


# =====================================================================
#  Mouse + keyboard
# =====================================================================
func _unhandled_input(event: InputEvent) -> void:
	if tool.is_active():
		_input_while_transforming(event)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				get_viewport().gui_release_focus() # so typed keys are shortcuts again, not text
				_press_pos = mb.position
				_pressing = _select_at(mb.position, mb.shift_pressed)
			else:
				_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		# click-and-drag on a selected element = quick grab (released button = confirm)
		if (event as InputEventMouseMotion).position.distance_to(_press_pos) > DRAG_START_PX:
			_pressing = false
			begin_transform(BuilderTransformTool.Kind.GRAB, true)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)


func _input_while_transforming(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		tool.update((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not tool.confirm_on_release:
				tool.confirm()
			elif not mb.pressed and tool.confirm_on_release:
				tool.confirm()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			tool.cancel()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE: tool.cancel()
			KEY_ENTER, KEY_KP_ENTER: tool.confirm()
			KEY_X: tool.set_axis(Vector3.RIGHT)
			KEY_Y: tool.set_axis(Vector3.UP)
			KEY_Z: tool.set_axis(Vector3.BACK)


func _handle_key(e: InputEventKey) -> void:
	if e.ctrl_pressed:
		match e.keycode:
			KEY_Z:
				if e.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y: redo()
			KEY_S: save()
		return
	match e.keycode:
		KEY_1: set_mode(Mode.OBJECT)
		KEY_2: set_mode(Mode.VERTEX)
		KEY_3: set_mode(Mode.EDGE)
		KEY_4: set_mode(Mode.FACE)
		KEY_TAB: set_mode(_remembered_edit_mode if mode == Mode.OBJECT else Mode.OBJECT)
		KEY_G: begin_transform(BuilderTransformTool.Kind.GRAB)
		KEY_R: begin_transform(BuilderTransformTool.Kind.ROTATE)
		KEY_S: begin_transform(BuilderTransformTool.Kind.SCALE)
		KEY_E: extrude()
		KEY_W: add_vertex_on_edge()
		KEY_J: connect_vertices()
		KEY_L: link_vertices()
		KEY_U: unlink_vertices()
		KEY_M: mirror()
		KEY_D:
			if e.shift_pressed:
				duplicate_selection()
		KEY_X, KEY_DELETE: delete_selection()
		KEY_F: frame_selection()
		KEY_A:
			if e.alt_pressed:
				clear_selection()
			else:
				select_all()


# =====================================================================
#  Actions (called by keys AND by the buttons in builder_ui.gd)
# =====================================================================
## G / R / S. `quick_drag` = ends when the mouse button is released.
func begin_transform(kind: BuilderTransformTool.Kind, quick_drag: bool = false, make_checkpoint: bool = true) -> void:
	var ids := affected_vertices()
	if ids.is_empty():
		say("Select something first (click a %s)." % Mode.keys()[mode].to_lower())
		return
	if make_checkpoint:
		checkpoint()
	tool.begin(kind, ids, get_viewport().get_mouse_position(), quick_drag)
	_transform_made_checkpoint = make_checkpoint
	say("Move the mouse. Click/Enter = confirm, Esc/RMB = cancel, X/Y/Z = lock axis.")


var _transform_made_checkpoint := true


func _on_transform_finished(confirmed: bool) -> void:
	if not confirmed:
		if _transform_made_checkpoint:
			_undo.drop_last()
		on_design_changed()
		return
	if auto_link and mode == Mode.VERTEX and sel_verts.size() == 1 and tool.kind == BuilderTransformTool.Kind.NONE:
		_try_auto_link(sel_verts[0])
	on_design_changed()


## After dropping one vertex: if it is almost on another MODULE's vertex, link them.
func _try_auto_link(moved: int) -> void:
	var mine := design.vertex_users(moved)
	for id in design.vertices.size():
		if id == moved or design.vertices[id].distance_to(design.vertices[moved]) > LINK_DISTANCE:
			continue
		var other := design.vertex_users(id)
		var shares_module := false
		for m in other:
			if mine.has(m):
				shares_module = true
		if shares_module:
			continue
		design.vertices[moved] = design.vertices[id]
		design.link_vertices(id, moved)
		sel_verts = [id if id < moved else id - 1]
		say("Vertices linked automatically (green).")
		return


func add_module(type: String, primitive: String, half_size: Vector3, segments: int) -> void:
	checkpoint()
	var centre := camera_rig.pivot.snapped(Vector3.ONE * maxf(snap_step, 0.05))
	var mi := design.add_module(type, primitive, centre, half_size, segments)
	mode = Mode.OBJECT
	sel_modules = [mi]
	sel_verts.clear()
	sel_edges.clear()
	sel_faces.clear()
	active_module = mi
	on_design_changed()
	BusEvent.builder_selection_changed.emit()
	say("Added %s %s at the view centre. Press G to move it, S to scale." % [type, primitive])


func delete_selection() -> void:
	if not has_selection():
		return
	checkpoint()
	match mode:
		Mode.OBJECT:
			var sorted := sel_modules.duplicate()
			sorted.sort()
			sorted.reverse()
			for mi in sorted:
				design.remove_module(mi)
		_:
			_delete_in_edit_mode()
	clear_selection()
	on_design_changed()


func _delete_in_edit_mode() -> void:
	# collect the faces to remove per module, then remove (highest module index first)
	var per_module := {}
	match mode:
		Mode.VERTEX:
			for mi in design.modules.size():
				for v in sel_verts:
					for fi in MeshOps.faces_using(design, mi, [v] as Array[int]):
						_add_face(per_module, mi, fi)
		Mode.EDGE:
			for e in sel_edges:
				for fi in MeshOps.faces_using(design, e.x, [e.y, e.z] as Array[int]):
					_add_face(per_module, e.x, fi)
		Mode.FACE:
			for f in sel_faces:
				_add_face(per_module, f.x, f.y)
	var mods := per_module.keys()
	mods.sort()
	mods.reverse()
	for mi in mods:
		var faces: Array[int] = []
		for fi in per_module[mi]:
			faces.append(fi)
		if not MeshOps.delete_faces(design, mi, faces):
			design.remove_module(mi)
	say("Deleted. (In Vertex/Edge mode, the faces touching the selection are removed.)")


func _add_face(per_module: Dictionary, mi: int, fi: int) -> void:
	if not per_module.has(mi):
		per_module[mi] = []
	if not (per_module[mi] as Array).has(fi):
		per_module[mi].append(fi)


func duplicate_selection() -> void:
	if mode != Mode.OBJECT or sel_modules.is_empty():
		say("Duplicate works in Object mode (press 1, select a module).")
		return
	checkpoint()
	var copies: Array[int] = []
	for mi in sel_modules:
		copies.append(design.duplicate_module(mi))
	sel_modules = copies
	active_module = copies[0]
	on_design_changed()
	begin_transform(BuilderTransformTool.Kind.GRAB, false, false)


func mirror() -> void:
	if mode != Mode.OBJECT or sel_modules.is_empty():
		say("Mirror works in Object mode (press 1, select a module).")
		return
	checkpoint()
	var copies: Array[int] = []
	for mi in sel_modules:
		copies.append(design.mirror_module(mi))
	sel_modules = copies
	active_module = copies[0]
	on_design_changed()
	on_selection_changed()
	say("Mirrored across X. The copy is a separate module (not linked).")


func extrude() -> void:
	if mode != Mode.FACE or sel_faces.is_empty():
		say("Extrude works on faces: press 4, click a face, press E.")
		return
	checkpoint()
	var per_module := {}
	for f in sel_faces:
		_add_face(per_module, f.x, f.y)
	for mi in per_module:
		var faces: Array[int] = []
		for fi in per_module[mi]:
			faces.append(fi)
		MeshOps.extrude_faces(design, mi, faces)
	on_design_changed()
	begin_transform(BuilderTransformTool.Kind.GRAB, false, false)


func add_vertex_on_edge() -> void:
	if mode != Mode.EDGE or sel_edges.is_empty():
		say("Press 3 (Edge mode), click an edge, then press W to add a vertex on it.")
		return
	checkpoint()
	var created: Array[int] = []
	for e in sel_edges:
		var id := MeshOps.subdivide_edge(design, e.x, e.y, e.z)
		if id >= 0:
			created.append(id)
	mode = Mode.VERTEX
	_remembered_edit_mode = Mode.VERTEX
	sel_edges.clear()
	sel_verts = created
	on_design_changed()
	on_selection_changed()
	say("Vertex added. Drag it (or press G) to reshape the face. Select two vertices of one face + J adds an edge between them.")


func connect_vertices() -> void:
	if mode != Mode.VERTEX or sel_verts.size() != 2:
		say("Press 2 (Vertex mode), select exactly TWO vertices of the same face, then J.")
		return
	checkpoint()
	for mi in design.modules.size():
		if MeshOps.connect_vertices(design, mi, sel_verts[0], sel_verts[1]):
			on_design_changed()
			say("Edge added: the face was split in two.")
			return
	_undo.drop_last()
	say("Those two vertices do not share a face (or are already neighbours).")


func link_vertices() -> void:
	if mode != Mode.VERTEX or sel_verts.size() < 2:
		say("Press 2 (Vertex mode), Shift+click two or more vertices, then L to link them.")
		return
	checkpoint()
	sel_verts = [design.merge_vertices(sel_verts)]
	on_design_changed()
	on_selection_changed()
	say("Linked. Linked vertices are green and move together.")


func unlink_vertices() -> void:
	if mode != Mode.VERTEX or sel_verts.is_empty():
		say("Press 2 (Vertex mode), select a vertex, then U to unlink it from the other modules.")
		return
	checkpoint()
	for v in sel_verts:
		for m in design.vertex_users(v):
			if m != active_module:
				design.unlink_vertex(m, v)
	on_design_changed()
	on_selection_changed()
	say("Unlinked: only the active module keeps the original vertex.")


func frame_selection() -> void:
	var ids := affected_vertices()
	if ids.is_empty():
		camera_rig.focus_on(Vector3.ZERO, 3.0)
		return
	var c := affected_center()
	var r := 1.0
	for id in ids:
		r = maxf(r, design.vertices[id].distance_to(c))
	camera_rig.focus_on(c, r)


## Move the current selection so its centre is at `target` (used by the X/Y/Z fields).
func move_selection_center_to(target: Vector3) -> void:
	var ids := affected_vertices()
	if ids.is_empty():
		return
	checkpoint("center")
	var delta := target - affected_center()
	for id in ids:
		design.vertices[id] += delta
	on_geometry_changed()


# ---- properties of the active module ------------------------------------
func set_active_type(type: String) -> void:
	if active_module < 0:
		return
	checkpoint()
	design.modules[active_module]["type"] = type
	on_design_changed()


func set_active_material(id: String) -> void:
	if active_module < 0:
		return
	checkpoint()
	design.modules[active_module]["material"] = id
	on_design_changed()


func set_commander_crew(seats: int) -> void:
	if active_module < 0:
		return
	checkpoint("crew")
	design.modules[active_module]["crew"] = clampi(seats, ModuleCatalog.CREW_MIN, ModuleCatalog.CREW_MAX)
	on_design_changed()


func set_thruster_direction(dir: Vector3) -> void:
	if active_module < 0:
		return
	checkpoint("dir")
	design.modules[active_module]["dir"] = dir.normalized() if dir.length() > 0.001 else Vector3(0, 0, -1)
	on_design_changed()


func set_thruster_power(power: float) -> void:
	if active_module < 0:
		return
	checkpoint("power")
	design.modules[active_module]["power"] = clampf(power, ModuleCatalog.THRUSTER_MIN_POWER, ModuleCatalog.THRUSTER_MAX_POWER)
	on_design_changed()


func set_reactor_scale(v: float) -> void:
	checkpoint("reactor")
	design.reactor_scale = v
	on_design_changed()


func set_gyro_scale(v: float) -> void:
	checkpoint("gyro")
	design.gyro_scale = v
	on_design_changed()


# =====================================================================
#  File actions
# =====================================================================
func new_ship() -> void:
	checkpoint()
	design = ShipDesign.new()
	design.ship_name = "My Ship"
	design.add_module(ModuleCatalog.HULL, "box", Vector3.ZERO, Vector3(0.6, 0.4, 1.0))
	design.add_module(ModuleCatalog.COMMANDER, "box", Vector3(0, 0.7, -0.3), Vector3(0.4, 0.3, 0.5))
	var t := design.add_module(ModuleCatalog.THRUSTER, "cylinder", Vector3(0, 0, 1.25), Vector3(0.25, 0.25, 0.25))
	design.modules[t]["power"] = 3000.0
	clear_selection()
	on_design_changed()


func save() -> void:
	var errors := design.validate()
	if not errors.is_empty():
		say("Cannot save: " + errors[0])
		return
	var err := design.save_user()
	if err == OK:
		BusEvent.builder_design_saved.emit(design.ship_name)
		say("Saved as '%s' (user://ships/)." % design.ship_name)
	else:
		say("Save failed (error %d)." % err)


func load_from(path: String) -> void:
	var loaded := ShipDesign.load_file(path)
	if loaded == null:
		say("Could not load that file.")
		return
	checkpoint()
	design = loaded
	clear_selection()
	on_design_changed()
	say("Loaded '%s'." % design.ship_name)


func set_ship_name(text: String) -> void:
	design.ship_name = text
