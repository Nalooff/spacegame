extends Control
## Seat selection overlay (scenes/seat_picker.tscn). Shows the captain's ship as a 3D preview with a floating
## "taken/capacity" button over every Commander module (e.g. "0/2", "1/1"). Clicking one asks the host for that seat.
##
##   var picker := SEAT_PICKER.instantiate(); add_child(picker); picker.open(captain_peer_id)
##
## The numbers refresh whenever the roster changes (somebody else may take a seat while this is open).
## Ships with more than PREVIEW_FULL_VERTICES vertices are previewed as one box per module (cheap).

signal closed

const PREVIEW_FULL_VERTICES := 30000

@onready var preview_hull: HullRenderer = %PreviewHull
@onready var preview_camera: Camera3D = %PreviewCamera
@onready var preview_container: SubViewportContainer = %PreviewContainer
@onready var seat_markers: Control = %SeatMarkers
@onready var seat_title_label: Label = %SeatTitleLabel
@onready var preview_viewport: SubViewport = %PreviewViewport

var captain: int = 0
var _design: ShipDesign
var _centroids: Dictionary = {}       # commander module -> position (ship space)
var _buttons: Dictionary = {}         # commander module -> Button
var _yaw: float = 0.6
var _pitch: float = 0.45
var _dist: float = 6.0
var _focus: Vector3 = Vector3.ZERO
var _dragging: bool = false


func open(captain_id: int) -> void:
	captain = captain_id
	var entry: Dictionary = Net.players.get(captain, {})
	seat_title_label.text = "Choose your seat on %s's %s" % [entry.get("name", "?"), entry.get("ship_name", "ship")]
	var h: String = entry.get("ship", "")
	if Net.blobs.has(h):
		_show(Net.blobs[h])
	else:
		Net.blob_received.connect(_on_blob, CONNECT_ONE_SHOT)
		Net.request_blob(h)
	Net.roster_changed.connect(_refresh_buttons)


func _on_blob(h: String) -> void:
	if Net.blobs.has(h):
		_show(Net.blobs[h])


func _show(blob: PackedByteArray) -> void:
	_design = ShipDesign.from_blob(blob)
	if _design == null:
		return
	var props := _design.compute_props()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	if _design.vertices.size() <= PREVIEW_FULL_VERTICES:
		preview_hull.attach(_design, HullRenderer.prepare(_design))
		preview_hull.flush()
	for mi in _design.modules.size():
		var info: Dictionary = props["modules"][mi]
		if _design.modules[mi]["type"] == ModuleCatalog.COMMANDER:
			_centroids[mi] = info["centroid"]
		var box := _bounds(mi)
		lo = lo.min(box.position)
		hi = hi.max(box.end)
		if _design.vertices.size() > PREVIEW_FULL_VERTICES:
			_add_box_preview(mi, box)
	_focus = (lo + hi) * 0.5
	_dist = maxf((hi - lo).length() * 1.1, 3.0)
	for mi in _centroids:
		var b := Button.new()
		b.name = "Seat%d" % mi
		b.pressed.connect(_on_seat_pressed.bind(mi))
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		seat_markers.add_child(b)
		_buttons[mi] = b
	_refresh_buttons()


func _bounds(mi: int) -> AABB:
	var ids := _design.module_vertex_ids(mi)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for id in ids:
		lo = lo.min(_design.vertices[id])
		hi = hi.max(_design.vertices[id])
	return AABB(lo, hi - lo)


func _add_box_preview(mi: int, box: AABB) -> void:
	var m := MeshInstance3D.new()
	m.name = "Box%d" % mi
	var bm := BoxMesh.new()
	bm.size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ModuleCatalog.color_of(_design.modules[mi]["type"])
	bm.material = mat
	m.mesh = bm
	m.position = box.get_center()
	preview_hull.add_child(m)


func _refresh_buttons() -> void:
	var occupied := Net.occupancy(captain)
	var slots: Dictionary = Net.players.get(captain, {}).get("slots", {})
	for mi in _buttons:
		var b: Button = _buttons[mi]
		var cap := int(slots.get(mi, 0))
		var taken := int(occupied.get(mi, 0))
		b.text = "%d/%d" % [taken, cap]
		b.disabled = taken >= cap
		b.tooltip_text = "Commander %d: %d of %d seats taken" % [mi, taken, cap]
		b.modulate = Color(0.5, 1, 0.6) if taken < cap else Color(1, 0.5, 0.5)


func _on_seat_pressed(commander: int) -> void:
	Net.submit_join_crew(captain, commander)
	_close()


func _on_cancel_pressed() -> void:
	_close()


func _close() -> void:
	if Net.roster_changed.is_connected(_refresh_buttons):
		Net.roster_changed.disconnect(_refresh_buttons)
	closed.emit()
	queue_free()


func _process(_dt: float) -> void:
	# camera orbit + floating buttons follow their commander module
	var rot := Basis.from_euler(Vector3(-_pitch, _yaw, 0.0))
	preview_camera.global_transform = Transform3D(rot, _focus + rot * Vector3(0, 0, _dist))
	for mi in _buttons:
		var b: Button = _buttons[mi]
		var p: Vector3 = _centroids[mi]
		var behind := preview_camera.is_position_behind(p)
		b.visible = not behind
		if not behind:
			var s := preview_camera.unproject_position(p) * (Vector2(preview_container.size) / Vector2(preview_viewport.size))
			b.position = s - b.size * 0.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(_dist * 0.9, 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(_dist * 1.1, 200.0)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		_pitch = clampf(_pitch + mm.relative.y * 0.01, -1.4, 1.4)
