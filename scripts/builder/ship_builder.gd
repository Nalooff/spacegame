class_name ShipBuilder
extends Node3D
## The ship builder ("Creation"). Root script of scenes/ship_builder.tscn.
##
## HOW THE EDITOR IS ORGANISED (one file each, all are nodes in the scene):
##   ship_builder.gd   (this)  state + picking + every editing action
##   builder_ui.gd             all buttons / panels (reads this node's state, calls its actions)
##   builder_tools.gd          the TABLE of tools shown in the left panel + the adjustable operations (bevel, extrude...)
##   operator_panel.gd         the popup where an operation's numbers can be changed afterwards ("Adjust last operation")
##   builder_view.gd           draws solid mesh, vertex dots, wireframe, highlights
##   builder_camera.gd         orbit camera
##   transform_tool.gd         Blender-style G / R / S
##   ../data/mesh_ops.gd       topology edits (extrude, add vertex on edge, connect...)
##   undo_stack.gd             Ctrl+Z / Ctrl+Y
##
## SELECTION MODES (like Blender):  1 Object   2 Vertex   3 Edge   4 Face   (Tab toggles Object <-> Vertex)
## KEYS: G grab, R rotate, S scale (then X/Y/Z to lock an axis, click/Enter = ok, Esc/RMB = cancel)
##       E extrude, I inset, B bevel, W subdivide edge, J connect vertices, L link, U unlink, M mirror,
##       Shift+D duplicate, X/Del delete, F frame selection, A select all, Alt+A select none, Ctrl+I invert,
##       H hide, Alt+H reveal, / isolate, Alt+Z x-ray, numpad 1/3/7 views (+Ctrl = opposite), numpad 5 ortho,
##       F9 adjust the last operation, Ctrl+Z undo, Ctrl+Y redo, Ctrl+S save.

enum Mode { OBJECT, VERTEX, EDGE, FACE }
## How the ship is drawn: SOLID (hidden vertices / edges cannot be seen or picked), XRAY (see through, everything can be
## picked) or WIRE (edges only).
enum Shading { SOLID, XRAY, WIRE }

## Text for the status bar / messages.
signal message(text: String)
## The adjustable operation (bevel, extrude...) opened, changed or closed: the operator panel redraws.
signal operator_changed
## The rubber-band rectangle of a box selection (empty Rect2 = finished).
signal box_changed(rect: Rect2)

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

## True only for a builder started from the editor plugin: shows "Save as PREMADE".
var premade_mode: bool = false
var shading: Shading = Shading.SOLID
## Switches of the viewport overlays (View menu): module edges, axes, thruster arrows, exhaust zones, turret arcs, problem fills.
var overlays := {"wire": true, "axes": true, "thrusters": true, "exhaust": true, "turrets": true, "problems": true}
## Modules hidden with H / isolate (indices). Forgotten when the number of modules changes.
var hidden_modules: Array[int] = []
var _hidden_for_size := -1
var snap_step: float = 0.1              # 0 = no snapping (set from the UI)
var auto_link: bool = true              # link a dropped vertex to a neighbour's vertex (set from the UI)

var _undo := UndoStack.new()
var _last_checkpoint_key := ""
var _last_checkpoint_msec := 0
var _press_pos := Vector2.ZERO          # where the left mouse button went down
var _pressing := false                  # left button is down on a selectable element
var _remembered_edit_mode: Mode = Mode.VERTEX
var _boxing := false                    # a box selection is being dragged
var _box_origin := Vector2.ZERO


func _ready() -> void:
	tool.builder = self
	tool.finished.connect(_on_transform_finished)
	camera_rig.view_changed.connect(_on_camera_moved)
	# started from the "Ships" tab of the Godot editor plugin: it leaves two small files (see addons/vertex_ships/plugin.gd)
	if OS.has_feature("editor") and FileAccess.file_exists("user://premade_mode.txt"):
		premade_mode = true
		DirAccess.remove_absolute("user://premade_mode.txt")
		if Data.builder_open_path == "" and FileAccess.file_exists("user://open_in_builder.txt"):
			Data.builder_open_path = FileAccess.get_file_as_string("user://open_in_builder.txt").strip_edges()
		DirAccess.remove_absolute("user://open_in_builder.txt")
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
	if design.modules.size() != _hidden_for_size:        # modules were added / removed: the hidden indices mean something else now
		hidden_modules.clear()
		_hidden_for_size = design.modules.size()
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
	if not _op_busy:
		_last_op_valid = false              # any other edit ends "adjust the last operation"
		if op_name != "":
			op_name = ""                    # ...and keeps whatever the open operation did
			operator_changed.emit()
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
	_last_op_valid = false
	if op_name != "":
		op_name = ""
		operator_changed.emit()
	clear_selection()
	on_design_changed()
	say(label)


# =====================================================================
#  Modes and selection
# =====================================================================
func set_mode(new_mode: Mode) -> void:
	if tool.is_active():
		return
	if op_name != "":
		confirm_operator()
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
				if not is_hidden(i):
					sel_modules.append(i)
		Mode.VERTEX:
			var shown := visible_vertex_mask()
			for id in design.vertices.size():
				if shown[id] != 0:
					sel_verts.append(id)
		Mode.EDGE:
			for mi in design.modules.size():
				if is_hidden(mi):
					continue
				for e in design.module_edges(mi):
					sel_edges.append(Vector3i(mi, e.x, e.y))
		Mode.FACE:
			for mi in design.modules.size():
				if is_hidden(mi):
					continue
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


func is_hidden(mi: int) -> bool:
	return hidden_modules.has(mi)


## 1 for every vertex that belongs to a module that is not hidden.
func visible_vertex_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(design.vertices.size())
	if hidden_modules.is_empty():
		mask.fill(1)
		return mask
	for mi in design.modules.size():
		if hidden_modules.has(mi):
			continue
		for id in design.module_vertex_ids(mi):
			mask[id] = 1
	return mask


## Can the camera see point `p`? In X-ray / wireframe everything counts as visible. In SOLID shading a ray from the point
## towards the camera must not hit a surface first (this is how vertices and edges behind a module are ignored).
func is_point_visible(p: Vector3) -> bool:
	if shading != Shading.SOLID:
		return true
	var tm := view.triangle_mesh()
	if tm == null:
		return true
	var cam_pos := camera.global_position
	var to_cam := (camera.global_basis.z) if camera_rig.orthographic else (cam_pos - p).normalized()
	var dist := p.distance_to(cam_pos)
	var start := p + to_cam * (0.012 + dist * 0.0015)
	var hit := tm.first_hit(start, to_cam.normalized(), dist)
	return hit >= dist - 0.01                              # nothing between the point and the camera (a hit behind the camera does not count)


func _pick_vertex(mouse: Vector2) -> int:
	if is_large():
		return -1
	var shown := visible_vertex_mask()
	var cand: Array = []                     # [screen distance, id]
	for id in design.vertices.size():
		if shown[id] == 0:
			continue
		var p := design.vertices[id]
		if camera.is_position_behind(p):
			continue
		var d := camera.unproject_position(p).distance_to(mouse)
		if d < PICK_VERTEX_PX:
			cand.append([d, id])
	cand.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for c in cand:                           # nearest first; the first one that is not hidden behind a surface wins
		if is_point_visible(design.vertices[c[1]]):
			return c[1]
	return -1


## Returns Vector3i(module, a, b) or Vector3i(-1, 0, 0).
func _pick_edge(mouse: Vector2) -> Vector3i:
	if is_large():
		return Vector3i(-1, 0, 0)
	var cand: Array = []                     # [screen distance, Vector3i]
	for mi in design.modules.size():
		if is_hidden(mi):
			continue
		for e in design.module_edges(mi):
			var pa := design.vertices[e.x]
			var pb := design.vertices[e.y]
			if camera.is_position_behind(pa) or camera.is_position_behind(pb):
				continue
			var d := _distance_to_segment(mouse, camera.unproject_position(pa), camera.unproject_position(pb))
			if d < PICK_EDGE_PX:
				cand.append([d, Vector3i(mi, e.x, e.y)])
	cand.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var tries := 0
	for c in cand:
		var e: Vector3i = c[1]
		if is_point_visible((design.vertices[e.y] + design.vertices[e.z]) * 0.5):
			return e
		tries += 1
		if tries > 12:
			break
	return Vector3i(-1, 0, 0)


## Returns Vector2i(module, face) or Vector2i(-1, -1).
func _pick_face(mouse: Vector2) -> Vector2i:
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if is_large():
		# large ship: pick the module whose bounding box the ray hits first (face index is not needed for modules)
		var best_m := -1
		var best_d := INF
		for mi in design.modules.size():
			if is_hidden(mi):
				continue
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
		if is_hidden(mi):
			continue
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
				_boxing = not _pressing           # nothing under the mouse: dragging draws a selection box
				_box_origin = mb.position
			else:
				_pressing = false
				if _boxing:
					_boxing = false
					var rect := Rect2(_box_origin, mb.position - _box_origin).abs()
					box_changed.emit(Rect2())
					if rect.size.length() > DRAG_START_PX * 2.0:
						box_select(rect, mb.shift_pressed)
	elif event is InputEventMouseMotion and _boxing:
		var pos := (event as InputEventMouseMotion).position
		if pos.distance_to(_box_origin) > DRAG_START_PX:
			box_changed.emit(Rect2(_box_origin, pos - _box_origin).abs())
	elif event is InputEventMouseMotion and _pressing:
		# click-and-drag on a selected element = quick grab (released button = confirm)
		if (event as InputEventMouseMotion).position.distance_to(_press_pos) > DRAG_START_PX:
			_pressing = false
			begin_transform(BuilderTransformTool.Kind.GRAB, true)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)


## Box selection: everything of the current selection type whose screen position lies inside `rect`.
## In SOLID shading things hidden behind a surface are skipped (switch to X-ray to take them too).
func box_select(rect: Rect2, additive: bool) -> void:
	if is_large():
		say("Box selection is off for very large ships.")
		return
	if not additive:
		clear_selection()
	match mode:
		Mode.OBJECT:
			for mi in design.modules.size():
				if not is_hidden(mi) and _in_rect(design.module_centroid(mi), rect) and not sel_modules.has(mi):
					sel_modules.append(mi)
					active_module = mi
		Mode.VERTEX:
			var shown := visible_vertex_mask()
			for id in design.vertices.size():
				if shown[id] != 0 and _in_rect(design.vertices[id], rect) and is_point_visible(design.vertices[id]) and not sel_verts.has(id):
					sel_verts.append(id)
		Mode.EDGE:
			for mi in design.modules.size():
				if is_hidden(mi):
					continue
				for e in design.module_edges(mi):
					var pa := design.vertices[e.x]
					var pb := design.vertices[e.y]
					if _in_rect(pa, rect) and _in_rect(pb, rect) and is_point_visible((pa + pb) * 0.5) and not is_edge_selected(mi, e.x, e.y):
						sel_edges.append(Vector3i(mi, e.x, e.y))
		Mode.FACE:
			for mi in design.modules.size():
				if is_hidden(mi):
					continue
				for fi in (design.modules[mi]["fs"] as FaceSet).alive_count():
					var c := design.face_center(mi, fi)
					if _in_rect(c, rect) and is_point_visible(c) and not sel_faces.has(Vector2i(mi, fi)):
						sel_faces.append(Vector2i(mi, fi))
	if active_module < 0 and not sel_verts.is_empty():
		var users := design.vertex_users(sel_verts[0])
		active_module = users[0] if not users.is_empty() else -1
	on_selection_changed()
	say(selection_summary() + " (box)")


func _in_rect(p: Vector3, rect: Rect2) -> bool:
	return not camera.is_position_behind(p) and rect.has_point(camera.unproject_position(p))


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
			KEY_BACKSPACE: tool.type_backspace()
			_:
				var ch := char((event as InputEventKey).unicode)
				if ch != "" and (ch.is_valid_int() or ch == "." or ch == "-" or ch == ","):
					tool.type_char("." if ch == "," else ch)


func _handle_key(e: InputEventKey) -> void:
	if op_name != "" and not e.ctrl_pressed:
		if e.keycode == KEY_ESCAPE:
			cancel_operator()
			return
		if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
			confirm_operator()
			return
	if e.ctrl_pressed:
		match e.keycode:
			KEY_Z:
				if e.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y: redo()
			KEY_S: save()
			KEY_X: dissolve_edges()
			KEY_I: select_invert()
			KEY_L: select_linked()
			KEY_T: triangulate_faces()
			KEY_EQUAL, KEY_KP_ADD: select_grow()
			KEY_KP_1: set_camera_view("back")
			KEY_KP_3: set_camera_view("left")
			KEY_KP_7: set_camera_view("bottom")
		return
	if e.alt_pressed:
		match e.keycode:
			KEY_A: clear_selection()
			KEY_Z: set_shading(Shading.SOLID if shading == Shading.XRAY else Shading.XRAY)
			KEY_H: reveal_all()
			KEY_M: merge_at_center()
			KEY_X: collapse_edges()
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
		KEY_E: start_operator("extrude")
		KEY_I: start_operator("inset")
		KEY_W: start_operator("subdivide")
		KEY_J: connect_vertices()
		KEY_C: create_face()
		KEY_N: make_module()
		KEY_B: start_operator("bevel")
		KEY_T: link_turret_barrel()
		KEY_L: link_vertices()
		KEY_U: unlink_vertices()
		KEY_M: start_operator("mirror")
		KEY_H: hide_selection()
		KEY_SLASH: isolate_selection()
		KEY_F9: reopen_last_operator()
		KEY_KP_1: set_camera_view("front")
		KEY_KP_3: set_camera_view("right")
		KEY_KP_7: set_camera_view("top")
		KEY_KP_5: set_orthographic(not camera_rig.orthographic)
		KEY_D:
			if e.shift_pressed:
				duplicate_selection()
		KEY_X, KEY_DELETE: delete_selection()
		KEY_F: frame_selection()
		KEY_A: select_all()


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
	var mi := design.add_module(type, primitive, centre, half_size, segments, new_module_preset)
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


## "Create face" (key C, Vertex mode): the selected vertices, in the order you clicked them, become one face.
## It is a LOOSE face (red) until you group faces into a closed container with "Make module".
func create_face() -> void:
	if mode != Mode.VERTEX or sel_verts.size() < 3:
		say("Press 2 (Vertex mode), click 3 or more vertices IN ORDER around the face, then C.")
		return
	checkpoint()
	design.add_loose_face(PackedInt32Array(sel_verts))
	on_design_changed()
	say("Face created (red = not in a module yet). Select its faces in Face mode (4) and press N to make a module.")


## "Make module" (key N, Face mode): the selected faces become a new module of the type picked in the Add tab.
## The faces must form a CLOSED container (every edge shared by exactly two faces), otherwise the ship cannot be saved.
func make_module() -> void:
	if mode != Mode.FACE or sel_faces.is_empty():
		say("Press 4 (Face mode), select the faces that enclose a volume (Shift+click, or A), then N.")
		return
	var src := sel_faces[0].x
	for f in sel_faces:
		if f.x != src:
			say("Select faces of ONE module at a time (loose faces are all in the red 'loose' group).")
			return
	checkpoint()
	var idx: Array[int] = []
	for f in sel_faces:
		idx.append(f.y)
	var n := design.move_faces_to_new_module(src, idx, new_module_type)
	clear_selection()
	if n >= 0:
		active_module = n
		sel_modules = [n]
		var open_edges := design.count_open_edges(n)
		say("Module %d created (%s)%s" % [n, new_module_type,
			"." if open_edges == 0 else ". NOT closed yet: %d open edge(s). Add the missing faces." % open_edges])
	on_design_changed()
	on_selection_changed()


## Link modules (Object mode, key T):
##   * turret base + barrel(s): the barrels are added to the base. A base can have SEVERAL barrels. A barrel that does
##     not touch its base is stuck (fires forward only).
##   * commander + turret base: the commander can fire that turret from its own seat (no walking needed).
func link_turret_barrel() -> void:
	var base := -1
	var barrels: Array[int] = []
	var commander := -1
	for mi in sel_modules:
		match design.modules[mi]["type"]:
			ModuleCatalog.TURRET: base = mi
			ModuleCatalog.BARREL: barrels.append(mi)
			ModuleCatalog.COMMANDER: commander = mi
	if commander >= 0 and base >= 0 and barrels.is_empty():
		checkpoint()
		var on := design.toggle_link(commander, base)
		on_design_changed()
		say("Commander %d %s turret %d." % [commander, "now controls" if on else "no longer controls", base])
		return
	if base < 0 or barrels.is_empty():
		say("Object mode: select ONE turret base and one or more barrels (Shift+click), then T. (Commander + turret base links the turret to the bridge.)")
		return
	checkpoint()
	for mi in design.modules.size():          # a barrel belongs to one base only
		if design.modules[mi]["type"] == ModuleCatalog.TURRET and mi != base:
			var list: Array = design.modules[mi]["cfg"].get("barrels", [])
			for br in barrels:
				list.erase(br)
			design.modules[mi]["cfg"]["barrels"] = list
	var mine: Array = design.modules[base]["cfg"].get("barrels", [])
	for br in barrels:
		if not mine.has(br):
			mine.append(br)
	design.modules[base]["cfg"]["barrels"] = mine
	on_design_changed()
	say("%d barrel(s) mounted on turret %d. Barrels that touch the base can turn with it." % [mine.size(), base])


func set_turret_value(key: String, value: float) -> void:
	if active_module < 0 or design.modules[active_module]["type"] != ModuleCatalog.TURRET:
		return
	checkpoint("turret_" + key)
	design.modules[active_module][key] = value     # arcs (yaw_min ...); speed and precision are preset stats
	on_design_changed()


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
	design.modules[active_module]["cfg"] = ModulePresets.make_cfg(type, ModulePresets.default_preset(type))
	design.modules[active_module]["dir"] = Vector3(0, 1, 0) if type == ModuleCatalog.TURRET else Vector3(0, 0, -1)
	on_design_changed()


## Switch the preset of the active module (its stats are replaced by the preset's).
func set_active_preset(id: String) -> void:
	if active_module < 0:
		return
	checkpoint()
	design.set_preset(active_module, id)
	on_design_changed()


## Edit the MAIN stat of the active module; the other stats follow (see ModulePresets.set_main).
func set_active_main_stat(value: float) -> void:
	if active_module < 0:
		return
	checkpoint("stat")
	design.set_main_stat(active_module, value)
	on_design_changed()


## Keep the active module's numbers as your own preset (user://presets.json).
func save_active_as_preset(label: String) -> void:
	if active_module < 0 or label.strip_edges() == "":
		say("Type a name for the preset first.")
		return
	var m: Dictionary = design.modules[active_module]
	var id := label.strip_edges().to_lower().replace(" ", "_")
	ModulePresets.save_custom(m["type"], id, label.strip_edges(), m["cfg"])
	m["cfg"]["preset"] = id
	on_design_changed()
	say("Preset '%s' saved. It now shows in the preset list of %s modules." % [label.strip_edges(), m["type"]])


func set_active_material(id: String) -> void:
	if active_module < 0:
		return
	checkpoint()
	design.modules[active_module]["material"] = id
	on_design_changed()


func set_thruster_direction(dir: Vector3) -> void:
	if active_module < 0:
		return
	checkpoint("dir")    # (also the mount axis of a turret base)
	design.modules[active_module]["dir"] = dir.normalized() if dir.length() > 0.001 else Vector3(0, 0, -1)
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
#  Which tools can be used right now? (the left panel greys the others out)
# =====================================================================
func tool_available(id: String) -> bool:
	match id:
		"move", "rotate", "scale", "delete", "frame_sel", "grow", "select_linked", "snap_grid", "hide":
			return has_selection()
		"select_all", "select_none", "select_invert": return true
		"adjust": return can_adjust_last()
		"reveal": return not hidden_modules.is_empty()
		"isolate": return has_selection() or not hidden_modules.is_empty()
		"connect": return mode == Mode.VERTEX and sel_verts.size() == 2
		"create_face": return mode == Mode.VERTEX and sel_verts.size() >= 3
		"link", "merge_center": return mode == Mode.VERTEX and sel_verts.size() >= 2
		"unlink": return mode == Mode.VERTEX and not sel_verts.is_empty()
		"flatten_x", "flatten_y", "flatten_z": return affected_vertices().size() >= 2
		"bevel", "subdivide", "dissolve", "collapse": return mode == Mode.EDGE and not sel_edges.is_empty()
		"extrude", "inset", "subdivide_face", "triangulate", "flatten_face", "make_module":
			return mode == Mode.FACE and not sel_faces.is_empty()
		"duplicate", "mirror", "array", "center_origin": return mode == Mode.OBJECT and not sel_modules.is_empty()
		"link_turret": return mode == Mode.OBJECT and sel_modules.size() >= 2
	return true


# =====================================================================
#  View: shading, camera, overlays, hiding
# =====================================================================
## Module type / preset used by "Make module" and by the Add module panel.
var new_module_type: String = ModuleCatalog.HULL
var new_module_preset: String = ""


func set_shading(value: Shading) -> void:
	shading = value
	on_selection_changed()
	say(["Solid: hidden vertices and edges cannot be seen or picked.", "X-ray: see through the ship, everything can be picked.",
		"Wireframe: edges only."][value])


func set_overlay(key: String, on: bool) -> void:
	overlays[key] = on
	view.redraw(self)


func set_camera_view(view_name: String) -> void:
	camera_rig.set_view(view_name)
	if view_name != "perspective":
		camera_rig.set_orthographic(true)       # a straight-on view is only useful without perspective
	else:
		camera_rig.set_orthographic(false)
	on_selection_changed()
	say("%s view." % view_name.capitalize())


func set_orthographic(on: bool) -> void:
	camera_rig.set_orthographic(on)
	on_selection_changed()
	say("Orthographic view." if on else "Perspective view.")


## H: hide the selected modules (Object mode) or the modules the selection belongs to.
func hide_selection() -> void:
	var targets := _selected_module_set()
	if targets.is_empty():
		say("Select something first, then H hides its module.")
		return
	for mi in targets:
		if not hidden_modules.has(mi):
			hidden_modules.append(mi)
	_hidden_for_size = design.modules.size()
	clear_selection()
	on_design_changed()
	say("%d module(s) hidden. Alt+H shows everything again." % targets.size())


## "/": hide everything EXCEPT the selected modules (good for working on one part).
func isolate_selection() -> void:
	var targets := _selected_module_set()
	if targets.is_empty():
		reveal_all()
		return
	hidden_modules.clear()
	for mi in design.modules.size():
		if not targets.has(mi):
			hidden_modules.append(mi)
	_hidden_for_size = design.modules.size()
	on_design_changed()
	say("Isolated %d module(s). Press / again (with nothing selected) or Alt+H to show everything." % targets.size())


func reveal_all() -> void:
	if hidden_modules.is_empty():
		return
	hidden_modules.clear()
	on_design_changed()
	say("Everything is visible again.")


## Modules that the current selection touches.
func _selected_module_set() -> Array[int]:
	var out: Array[int] = []
	match mode:
		Mode.OBJECT:
			out = sel_modules.duplicate()
		Mode.VERTEX:
			for v in sel_verts:
				for m in design.vertex_users(v):
					if not out.has(m):
						out.append(m)
		Mode.EDGE:
			for e in sel_edges:
				if not out.has(e.x):
					out.append(e.x)
		Mode.FACE:
			for f in sel_faces:
				if not out.has(f.x):
					out.append(f.x)
	return out


# =====================================================================
#  Selection helpers: invert, grow, linked, box
# =====================================================================
func select_invert() -> void:
	var before_v := sel_verts.duplicate()
	var before_e := sel_edges.duplicate()
	var before_f := sel_faces.duplicate()
	var before_m := sel_modules.duplicate()
	clear_selection()
	match mode:
		Mode.OBJECT:
			for i in design.modules.size():
				if not before_m.has(i) and not is_hidden(i):
					sel_modules.append(i)
		Mode.VERTEX:
			var shown := visible_vertex_mask()
			for id in design.vertices.size():
				if not before_v.has(id) and shown[id] != 0:
					sel_verts.append(id)
		Mode.EDGE:
			for mi in design.modules.size():
				if is_hidden(mi):
					continue
				for e in design.module_edges(mi):
					var key := Vector3i(mi, e.x, e.y)
					if not before_e.has(key):
						sel_edges.append(key)
		Mode.FACE:
			for mi in design.modules.size():
				if is_hidden(mi):
					continue
				for fi in (design.modules[mi]["fs"] as FaceSet).alive_count():
					if not before_f.has(Vector2i(mi, fi)):
						sel_faces.append(Vector2i(mi, fi))
	on_selection_changed()
	say(selection_summary())


## Ctrl+"+": add the neighbours of the selection (things that share a vertex with it).
func select_grow() -> void:
	if not has_selection():
		say("Select something to grow first.")
		return
	var ids := {}                                         # vertices of the current selection
	for id in affected_vertices():
		ids[id] = true
	match mode:
		Mode.OBJECT:
			for mi in design.modules.size():
				if sel_modules.has(mi) or is_hidden(mi):
					continue
				for id in design.module_vertex_ids(mi):
					if ids.has(id):
						sel_modules.append(mi)
						break
		Mode.VERTEX:
			for mi in design.modules.size():
				for e in design.module_edges(mi):
					if ids.has(e.x) and not sel_verts.has(e.y):
						sel_verts.append(e.y)
					elif ids.has(e.y) and not sel_verts.has(e.x):
						sel_verts.append(e.x)
		Mode.EDGE:
			for mi in design.modules.size():
				if is_hidden(mi):
					continue
				for e in design.module_edges(mi):
					var key := Vector3i(mi, e.x, e.y)
					if not sel_edges.has(key) and (ids.has(e.x) or ids.has(e.y)):
						sel_edges.append(key)
		Mode.FACE:
			for mi in design.modules.size():
				if is_hidden(mi):
					continue
				var faces: Array = design.faces_array(mi)
				for fi in faces.size():
					var key := Vector2i(mi, fi)
					if sel_faces.has(key):
						continue
					for id in (faces[fi] as PackedInt32Array):
						if ids.has(id):
							sel_faces.append(key)
							break
	on_selection_changed()
	say(selection_summary())


## Ctrl+L: everything that is connected to the selection (the whole module(s), or all modules joined by shared vertices).
func select_linked() -> void:
	var mods := _selected_module_set()
	if mods.is_empty():
		say("Select something first.")
		return
	if mode == Mode.OBJECT:                               # flood through shared vertices
		var seen := {}
		for m in mods:
			seen[m] = true
		var changed := true
		while changed:
			changed = false
			for mi in design.modules.size():
				if seen.has(mi) or is_hidden(mi):
					continue
				var mine := {}
				for id in design.module_vertex_ids(mi):
					mine[id] = true
				for other in seen.keys():
					for id in design.module_vertex_ids(other):
						if mine.has(id):
							seen[mi] = true
							changed = true
							break
					if seen.has(mi):
						break
		sel_modules = []
		for k in seen:
			sel_modules.append(int(k))
	else:
		match mode:
			Mode.VERTEX:
				for mi in mods:
					for id in design.module_vertex_ids(mi):
						if not sel_verts.has(id):
							sel_verts.append(id)
			Mode.EDGE:
				for mi in mods:
					for e in design.module_edges(mi):
						var key := Vector3i(mi, e.x, e.y)
						if not sel_edges.has(key):
							sel_edges.append(key)
			Mode.FACE:
				for mi in mods:
					for fi in (design.modules[mi]["fs"] as FaceSet).alive_count():
						var key := Vector2i(mi, fi)
						if not sel_faces.has(key):
							sel_faces.append(key)
	on_selection_changed()
	say(selection_summary())


# =====================================================================
#  Direct tools (no options): they act at once
# =====================================================================
## Vertices: put all selected vertices on one plane perpendicular to `axis` (0 = X, 1 = Y, 2 = Z) at their average.
func flatten_axis(axis: int) -> void:
	var ids := affected_vertices()
	if ids.size() < 2:
		say("Select two or more vertices / edges / faces to flatten.")
		return
	checkpoint()
	var mean := 0.0
	for id in ids:
		mean += design.vertices[id][axis]
	mean /= ids.size()
	for id in ids:
		var v := design.vertices[id]
		v[axis] = mean
		design.vertices[id] = v
	on_geometry_changed()
	say("Flattened on %s = %.3f m." % ["XYZ"[axis], mean])


## Faces: flatten the selected faces onto their average plane (fixes slightly bent faces).
func flatten_faces() -> void:
	if mode != Mode.FACE or sel_faces.is_empty():
		say("Press 4 (Face mode), select faces, then Flatten.")
		return
	var n := Vector3.ZERO
	for f in sel_faces:
		var ids := design.face_outward(f.x, f.y)
		n += ShipDesign.newell_normal(design.vertices, ids)
	if n.length() < 0.0001:
		return
	n = n.normalized()
	var ids2 := affected_vertices()
	var c := affected_center()
	checkpoint()
	for id in ids2:
		design.vertices[id] -= n * n.dot(design.vertices[id] - c)
	on_geometry_changed()
	say("Flattened onto one plane.")


func snap_to_grid() -> void:
	var ids := affected_vertices()
	if ids.is_empty():
		say("Select something first.")
		return
	var step := snap_step if snap_step > 0.0 else 0.1
	checkpoint()
	for id in ids:
		design.vertices[id] = design.vertices[id].snapped(Vector3.ONE * step)
	on_geometry_changed()
	say("Snapped to the %.2f m grid." % step)


## Alt+M: the selected vertices become ONE vertex in their middle.
func merge_at_center() -> void:
	if mode != Mode.VERTEX or sel_verts.size() < 2:
		say("Press 2 (Vertex mode), select two or more vertices, then Merge at centre.")
		return
	checkpoint()
	sel_verts = [design.merge_vertices(sel_verts)]
	on_design_changed()
	on_selection_changed()
	say("Merged into one vertex.")


## Edge mode: each selected edge shrinks to a single vertex in its middle.
func collapse_edges() -> void:
	if mode != Mode.EDGE or sel_edges.is_empty():
		say("Press 3 (Edge mode), select edges, then Collapse.")
		return
	checkpoint()
	var pairs: Array = []                                # endpoint POSITIONS (vertex ids change when unused ones are removed)
	for e in sel_edges:
		pairs.append([design.vertices[e.y], design.vertices[e.z]])
	for pr in pairs:
		var a := _find_vertex_at(pr[0])
		var b := _find_vertex_at(pr[1])
		if a >= 0 and b >= 0 and a != b:
			MeshOps.collapse_edge(design, a, b)
	clear_selection()
	on_design_changed()
	say("Collapsed %d edge(s)." % pairs.size())


## Ctrl+X: the two faces next to each selected edge become one face.
func dissolve_edges() -> void:
	if mode != Mode.EDGE or sel_edges.is_empty():
		say("Press 3 (Edge mode), select edges, then Dissolve (Ctrl+X).")
		return
	checkpoint()
	var done := 0
	for e in sel_edges:
		if MeshOps.dissolve_edge(design, e.x, e.y, e.z):
			done += 1
	if done == 0:
		_undo.drop_last()
		say("Nothing dissolved: each edge needs a face on both sides.")
		return
	design.prune_vertices()
	clear_selection()
	on_design_changed()
	say("Dissolved %d edge(s)." % done)


## Faces: split every selected face with more than 3 corners into triangles.
func triangulate_faces() -> void:
	if mode != Mode.FACE or sel_faces.is_empty():
		say("Press 4 (Face mode), select faces, then Triangulate.")
		return
	checkpoint()
	var per_module := {}
	for f in sel_faces:
		_add_face(per_module, f.x, f.y)
	var made := 0
	for mi in per_module:
		var list: Array[int] = []
		for fi in per_module[mi]:
			list.append(fi)
		made += MeshOps.triangulate_faces(design, mi, list)
	clear_selection()
	on_design_changed()
	say("%d triangle(s) made." % made)


## Faces: cut each selected face into one quad per corner.
func subdivide_faces() -> void:
	if mode != Mode.FACE or sel_faces.is_empty():
		say("Press 4 (Face mode), select faces, then Subdivide.")
		return
	checkpoint()
	var per_module := {}
	for f in sel_faces:
		_add_face(per_module, f.x, f.y)
	var done := 0
	for mi in per_module:
		var list: Array[int] = []
		for fi in per_module[mi]:
			list.append(fi)
		done += MeshOps.subdivide_faces(design, mi, list)
	clear_selection()
	on_design_changed()
	say("%d face(s) subdivided." % done)


## Object mode: move the selected modules so their middle is at the origin.
func center_on_origin() -> void:
	if mode != Mode.OBJECT or sel_modules.is_empty():
		say("Press 1 (Object mode), select modules, then Centre on origin.")
		return
	checkpoint()
	var c := affected_center()
	for id in affected_vertices():
		design.vertices[id] -= c
	on_geometry_changed()
	say("Centred on the origin.")


## Size (metres) of the box around the selection, and a way to set it from the Properties tab.
func selection_bounds() -> AABB:
	var ids := affected_vertices()
	if ids.is_empty():
		return AABB()
	var box := AABB(design.vertices[ids[0]], Vector3.ZERO)
	for id in ids:
		box = box.expand(design.vertices[id])
	return box


func set_selection_size(size: Vector3) -> void:
	var ids := affected_vertices()
	var box := selection_bounds()
	if ids.is_empty():
		return
	checkpoint("size")
	var c := box.get_center()
	for id in ids:
		var rel := design.vertices[id] - c
		for axis in 3:
			if box.size[axis] > 0.0001 and size[axis] > 0.0:
				rel[axis] *= size[axis] / box.size[axis]
		design.vertices[id] = c + rel
	on_geometry_changed()


func _find_vertex_at(pos: Vector3) -> int:
	for id in design.vertices.size():
		if design.vertices[id].distance_squared_to(pos) < 1.0e-8:
			return id
	return -1


# =====================================================================
#  ADJUSTABLE OPERATIONS ("operators", like Blender's Adjust Last Operation panel)
# =====================================================================
## Bevel, extrude, inset, subdivide, mirror and array run on a SNAPSHOT of the design: start_operator() takes the snapshot
## and runs the operation with its default (or last used) numbers; every number you change in the panel restores the
## snapshot and runs it again. Confirm keeps the result, Cancel throws it away. Until you do something else, F9 (or the
## "Adjust last operation" button) opens the panel again, so you can still change the bevel afterwards.
## The definitions of the numbers live in builder_tools.gd (OPERATORS); the work itself is in the _op_xxx functions below.
var op_name: String = ""                       ## the operation whose panel is open ("" = none)
var op_params: Dictionary = {}
var _op_snapshot := PackedByteArray()
var _op_sel: Dictionary = {}
var _op_memory: Dictionary = {}                ## operation -> the numbers you used last time
var _op_busy := false
var _last_op_valid := false
var _last_op_name := ""


func _snapshot_selection() -> Dictionary:
	return {"mode": mode, "modules": sel_modules.duplicate(), "verts": sel_verts.duplicate(), "edges": sel_edges.duplicate(),
		"faces": sel_faces.duplicate(), "active": active_module}


func _restore_selection(d: Dictionary) -> void:
	mode = d["mode"]
	sel_modules.assign(d["modules"])
	sel_verts.assign(d["verts"])
	sel_edges.assign(d["edges"])
	sel_faces.assign(d["faces"])
	active_module = d["active"]


## Why operation `name` cannot start now ("" = it can).
func operator_blocker(op: String) -> String:
	var def: Dictionary = BuilderTools.OPERATORS.get(op, {})
	if def.is_empty():
		return "Unknown operation."
	if mode != def["mode"]:
		return "%s works in %s mode (press %s)." % [def["title"], ["Object", "Vertex", "Edge", "Face"][def["mode"]], str(def["mode"] + 1)]
	if not has_selection():
		return "Select something first."
	return ""


func start_operator(op: String) -> void:
	if tool.is_active():
		return
	var why := operator_blocker(op)
	if why != "":
		say(why)
		return
	if op_name != "":
		confirm_operator()
	checkpoint()
	_op_snapshot = design.to_blob()
	_op_sel = _snapshot_selection()
	op_name = op
	op_params = _op_defaults(op)
	_run_operator()
	operator_changed.emit()


func _op_defaults(op: String) -> Dictionary:
	var out := {}
	for p in BuilderTools.OPERATORS[op]["params"]:
		out[p["key"]] = p["value"]
	for k in _op_memory.get(op, {}):
		if out.has(k):
			out[k] = _op_memory[op][k]
	return out


func set_operator_param(key: String, value: Variant) -> void:
	if op_name == "":
		return
	op_params[key] = value
	_op_memory[op_name] = op_params.duplicate()
	_run_operator()


func _run_operator() -> void:
	_op_busy = true
	var restored := ShipDesign.from_blob(_op_snapshot)
	if restored != null:
		design = restored
	_restore_selection(_op_sel)
	var err: String = call("_op_" + op_name, op_params)
	if err != "":
		design = ShipDesign.from_blob(_op_snapshot)
		_restore_selection(_op_sel)
		say(err)
	else:
		say("%s: change the numbers in the panel, then Apply. (Esc or Cancel throws it away.)" % BuilderTools.OPERATORS[op_name]["title"])
	_op_busy = false
	on_design_changed()
	on_selection_changed()
	operator_changed.emit()                  # lets the panel show the values now in use


func confirm_operator() -> void:
	if op_name == "":
		return
	_last_op_name = op_name
	_last_op_valid = true
	op_name = ""
	operator_changed.emit()
	say("Applied. F9 (Adjust last operation) changes it again until you do something else.")


func cancel_operator() -> void:
	if op_name == "":
		return
	_op_busy = true
	var restored := ShipDesign.from_blob(_op_snapshot)
	if restored != null:
		design = restored
	_restore_selection(_op_sel)
	_undo.drop_last()
	_op_busy = false
	op_name = ""
	_last_op_valid = false
	on_design_changed()
	on_selection_changed()
	operator_changed.emit()
	say("Cancelled.")


func can_adjust_last() -> bool:
	return _last_op_valid and op_name == ""


func reopen_last_operator() -> void:
	if not can_adjust_last():
		say("Nothing to adjust: do a bevel, extrude, inset... first (and nothing else after it).")
		return
	op_name = _last_op_name
	op_params = _op_defaults(op_name)
	_run_operator()
	operator_changed.emit()


# ---- the operations. Each returns "" when it worked, or a message saying why not.
func _op_bevel(p: Dictionary) -> String:
	var done := 0
	var strips: Array = []                         # endpoint POSITIONS of the new long edges (ids change when unused vertices go)
	var todo: Array[Vector3i] = sel_edges.duplicate()
	for e in todo:
		var w := float(p["width"])
		var current: Array[Vector2i] = [Vector2i(e.y, e.z)]
		for step in int(p["segments"]):
			var next: Array[Vector2i] = []
			for edge in current:
				next.append_array(MeshOps.bevel_edge(design, e.x, edge.x, edge.y, w))
			if step == 0 and not next.is_empty():
				done += 1
			current = next
			w *= 0.5
		for edge in current:
			strips.append([e.x, design.vertices[edge.x], design.vertices[edge.y]])
	if done == 0:
		return "Could not bevel (an edge needs a face on both sides, and room for the strip)."
	design.prune_vertices()                        # the old end points of the beveled edges are no longer used: remove them
	sel_edges.clear()
	for s_ in strips:
		var a := _find_vertex_at(s_[1])
		var b := _find_vertex_at(s_[2])
		if a >= 0 and b >= 0:
			sel_edges.append(Vector3i(s_[0], mini(a, b), maxi(a, b)))
	return ""


func _op_extrude(p: Dictionary) -> String:
	var per_module := {}
	var normal_of := {}
	for f in sel_faces:
		_add_face(per_module, f.x, f.y)
		var loop := design.face_outward(f.x, f.y)
		normal_of[f.x] = (normal_of.get(f.x, Vector3.ZERO) as Vector3) + ShipDesign.newell_normal(design.vertices, loop)
	for mi in per_module:
		var faces: Array[int] = []
		for fi in per_module[mi]:
			faces.append(fi)
		var n: Vector3 = normal_of[mi]
		var made := MeshOps.extrude_faces(design, mi, faces)
		if n.length() > 0.0001:
			for id in made:
				design.vertices[id] += n.normalized() * float(p["distance"])
	return ""


func _op_inset(p: Dictionary) -> String:
	var per_module := {}
	for f in sel_faces:
		_add_face(per_module, f.x, f.y)
	var inner: Array[Vector2i] = []
	for mi in per_module:
		var faces: Array[int] = []
		for fi in per_module[mi]:
			faces.append(fi)
		for fi in MeshOps.inset_faces(design, mi, faces, float(p["amount"]), float(p["depth"])):
			inner.append(Vector2i(mi, fi))
	sel_faces = inner
	return ""


func _op_subdivide(p: Dictionary) -> String:
	var created: Array[int] = []
	for e in sel_edges:
		created.append_array(MeshOps.subdivide_edge_n(design, e.x, e.y, e.z, int(p["cuts"])))
	if created.is_empty():
		return "These edges could not be split."
	mode = Mode.VERTEX
	_remembered_edit_mode = Mode.VERTEX
	sel_edges.clear()
	sel_verts = created
	return ""


func _op_mirror(p: Dictionary) -> String:
	var copies: Array[int] = []
	for mi in sel_modules:
		copies.append(design.mirror_module(mi, int(p["axis"]), float(p["offset"])))
	if copies.is_empty():
		return "Select a module first."
	sel_modules = copies
	active_module = copies[0]
	return ""


func _op_array(p: Dictionary) -> String:
	var originals := sel_modules.duplicate()
	var step := Vector3(float(p["dx"]), float(p["dy"]), float(p["dz"]))
	var all: Array[int] = originals.duplicate()
	for k in range(1, int(p["count"])):
		for mi in originals:
			all.append(design.duplicate_module(mi, step * k))
	sel_modules = all
	return ""


# =====================================================================
#  File actions
# =====================================================================
## `template`: "starter" = hull + bridge + engine (can be saved at once), "blank" = nothing (add the modules yourself).
func new_ship(template: String = "starter") -> void:
	checkpoint()
	design = ShipDesign.new()
	design.ship_name = "My Ship"
	if template == "starter":
		design.add_module(ModuleCatalog.HULL, "box", Vector3.ZERO, Vector3(1.5, 1.0, 2.5))
		design.add_module(ModuleCatalog.COMMANDER, "box", Vector3(0, 1.9, -0.5), Vector3(1.2, 0.95, 1.5))
		design.add_module(ModuleCatalog.THRUSTER, "cylinder", Vector3(0, 0, 3.4), Vector3(0.7, 0.7, 0.9))
	hidden_modules.clear()
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


## Only shown when the game runs from the Godot editor: writes into res://ships/ (see addons/vertex_ships).
func save_premade() -> void:
	var errors := design.validate()
	if not errors.is_empty():
		say("Cannot save: " + errors[0])
		return
	var err := design.save_premade()
	say("Saved as PREMADE ship '%s' (res://ships/). Refresh the Vertex Ships dock." % design.ship_name if err == OK else "Save failed (error %d)." % err)


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
