class_name BuilderUI
extends Control
## All the buttons and panels of the ship builder. Root of the UI (scene node "UI/BuilderUI").
##
## This script holds NO design logic: every button just calls a function of ShipBuilder
## (`builder.xxx()`), and refresh_*() reads the builder's state back into the widgets.
## To add a button: 1) add it in tools/gen_builder.py  2) connect it to a _on_xxx function here
## 3) make that function call a builder action.
##
## Layout (see scene tree):
##   TopBar     ship name, New / Save / Load, Undo / Redo, Back to menu
##   ToolPanel  (left)  selection mode + tool buttons
##   SidePanel  (right) tabs: "Add" new module / "Selection" details / "Ship" stats + internal modules
##   StatusBar  (bottom) last message + key help

## The builder is the grandparent in the scene tree: ShipBuilder / UI / BuilderUI.
@onready var builder: ShipBuilder = get_node("../..")

# ---- top bar
@onready var ship_name_edit: LineEdit = %ShipNameEdit
@onready var load_picker: OptionButton = %LoadPicker
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
# ---- tool panel
@onready var mode_object_button: Button = %ModeObjectButton
@onready var mode_vertex_button: Button = %ModeVertexButton
@onready var mode_edge_button: Button = %ModeEdgeButton
@onready var mode_face_button: Button = %ModeFaceButton
@onready var snap_spin: SpinBox = %SnapSpin
@onready var auto_link_check: CheckBox = %AutoLinkCheck
# ---- "Add" tab
@onready var new_type_picker: OptionButton = %NewTypePicker
@onready var new_type_help: Label = %NewTypeHelp
@onready var new_shape_picker: OptionButton = %NewShapePicker
@onready var new_segments_spin: SpinBox = %NewSegmentsSpin
@onready var new_size_x_spin: SpinBox = %NewSizeXSpin
@onready var new_size_y_spin: SpinBox = %NewSizeYSpin
@onready var new_size_z_spin: SpinBox = %NewSizeZSpin
# ---- "Selection" tab
@onready var selection_info_label: Label = %SelectionInfoLabel
@onready var center_section: VBoxContainer = %CenterSection
@onready var center_x_spin: SpinBox = %CenterXSpin
@onready var center_y_spin: SpinBox = %CenterYSpin
@onready var center_z_spin: SpinBox = %CenterZSpin
@onready var active_module_section: VBoxContainer = %ActiveModuleSection
@onready var active_module_label: Label = %ActiveModuleLabel
@onready var active_type_picker: OptionButton = %ActiveTypePicker
@onready var active_type_help: Label = %ActiveTypeHelp
@onready var material_picker: OptionButton = %MaterialPicker
@onready var material_help: Label = %MaterialHelp
@onready var crew_section: VBoxContainer = %CrewSection
@onready var crew_seats_spin: SpinBox = %CrewSeatsSpin
@onready var thruster_section: VBoxContainer = %ThrusterSection
@onready var thrust_dir_x_spin: SpinBox = %ThrustDirXSpin
@onready var thrust_dir_y_spin: SpinBox = %ThrustDirYSpin
@onready var thrust_dir_z_spin: SpinBox = %ThrustDirZSpin
@onready var thrust_power_spin: SpinBox = %ThrustPowerSpin
# ---- "Ship" tab
@onready var ship_stats_label: Label = %ShipStatsLabel
@onready var ship_problems_label: Label = %ShipProblemsLabel
@onready var reactor_slider: HSlider = %ReactorSlider
@onready var reactor_value_label: Label = %ReactorValueLabel
@onready var gyro_slider: HSlider = %GyroSlider
@onready var gyro_value_label: Label = %GyroValueLabel
# ---- status bar
@onready var status_label: Label = %StatusLabel

var _ship_paths: Array[String] = []
## True while we write values INTO widgets, so their signals do not edit the design again.
var _refreshing := false


func _ready() -> void:
	for t in ModuleCatalog.TYPES:
		new_type_picker.add_item(t.capitalize())
		active_type_picker.add_item(t.capitalize())
	for id in MaterialCatalog.IDS:
		material_picker.add_item(MaterialCatalog.info(id)["name"])
	for p in Primitives.NAMES:
		new_shape_picker.add_item(p.capitalize())
	builder.message.connect(func(text: String): status_label.text = text)
	BusEvent.builder_design_changed.connect(refresh_all)
	BusEvent.builder_selection_changed.connect(refresh_all)
	BusEvent.builder_design_saved.connect(func(_n): refresh_ship_list())
	refresh_ship_list()
	_on_new_type_selected(ModuleCatalog.TYPES.find(ModuleCatalog.HULL))
	new_type_picker.select(ModuleCatalog.TYPES.find(ModuleCatalog.HULL))
	refresh_all()


# =====================================================================
#  Reading the builder state into the widgets
# =====================================================================
func refresh_all() -> void:
	_refreshing = true
	var d := builder.design
	if ship_name_edit.text != d.ship_name:
		ship_name_edit.text = d.ship_name
	undo_button.disabled = not builder.can_undo()
	redo_button.disabled = not builder.can_redo()
	mode_object_button.set_pressed_no_signal(builder.mode == ShipBuilder.Mode.OBJECT)
	mode_vertex_button.set_pressed_no_signal(builder.mode == ShipBuilder.Mode.VERTEX)
	mode_edge_button.set_pressed_no_signal(builder.mode == ShipBuilder.Mode.EDGE)
	mode_face_button.set_pressed_no_signal(builder.mode == ShipBuilder.Mode.FACE)
	_refresh_selection_tab()
	_refresh_ship_tab()
	_refreshing = false


func _refresh_selection_tab() -> void:
	var d := builder.design
	selection_info_label.text = builder.selection_summary()
	center_section.visible = builder.has_selection()
	if builder.has_selection():
		var c := builder.affected_center()
		center_x_spin.set_value_no_signal(c.x)
		center_y_spin.set_value_no_signal(c.y)
		center_z_spin.set_value_no_signal(c.z)
	var am := builder.active_module
	active_module_section.visible = am >= 0 and am < d.modules.size()
	if not active_module_section.visible:
		return
	var m: Dictionary = d.modules[am]
	active_module_label.text = "Active module: #%d (%s)" % [am, m["type"]]
	active_type_picker.select(ModuleCatalog.TYPES.find(m["type"]))
	active_type_help.text = ModuleCatalog.TYPE_HELP[m["type"]]
	var mat_id := d.material_of(am)
	var mat := MaterialCatalog.info(mat_id)
	material_picker.select(MaterialCatalog.IDS.find(mat_id))
	material_help.text = "Hardness %.0f, dents above %.0f m/s, density x%.2f" % [mat["hardness"], mat["yield_speed"], mat["density_mult"]]
	crew_section.visible = m["type"] == ModuleCatalog.COMMANDER
	if crew_section.visible:
		crew_seats_spin.set_value_no_signal(int(m.get("crew", 1)))
	thruster_section.visible = m["type"] == ModuleCatalog.THRUSTER
	if thruster_section.visible:
		var dir: Vector3 = m["dir"]
		thrust_dir_x_spin.set_value_no_signal(dir.x)
		thrust_dir_y_spin.set_value_no_signal(dir.y)
		thrust_dir_z_spin.set_value_no_signal(dir.z)
		thrust_power_spin.set_value_no_signal(m["power"])


func _refresh_ship_tab() -> void:
	var d := builder.design
	var props := d.compute_props()
	var counts := {}
	for m in d.modules:
		counts[m["type"]] = int(counts.get(m["type"], 0)) + 1
	var parts: Array[String] = []
	for t in ModuleCatalog.TYPES:
		parts.append("%s x%d" % [t, int(counts.get(t, 0))])
	ship_stats_label.text = "Mass: %.0f kg\nVertices: %d%s\nModules: %s" % [props["mass"], d.vertices.size(), "  (large ship mode: no vertex editing)" if d.vertices.size() > ShipBuilder.DETAIL_LIMIT else "", ", ".join(parts)]
	var problems := d.validate()
	ship_problems_label.text = "Ready to save." if problems.is_empty() else "\n".join(problems)
	ship_problems_label.modulate = Color(0.5, 1, 0.6) if problems.is_empty() else Color(1, 0.6, 0.5)
	reactor_slider.set_value_no_signal(d.reactor_scale)
	gyro_slider.set_value_no_signal(d.gyro_scale)
	reactor_value_label.text = "%.2f" % d.reactor_scale
	gyro_value_label.text = "%.2f" % d.gyro_scale


func refresh_ship_list() -> void:
	load_picker.clear()
	_ship_paths.clear()
	for s in ShipDesign.list_ships():
		load_picker.add_item(s["name"] + ("  (premade)" if s["premade"] else ""))
		_ship_paths.append(s["path"])


# =====================================================================
#  Top bar
# =====================================================================
func _on_ship_name_changed(text: String) -> void:
	if not _refreshing:
		builder.set_ship_name(text)


func _on_new_pressed() -> void: builder.new_ship()
func _on_save_pressed() -> void: builder.save()
func _on_undo_pressed() -> void: builder.undo()
func _on_redo_pressed() -> void: builder.redo()
func _on_back_pressed() -> void: Game.go_to(Game.MENU_SCENE)


func _on_load_pressed() -> void:
	var i := load_picker.selected
	if i >= 0 and i < _ship_paths.size():
		builder.load_from(_ship_paths[i])


# =====================================================================
#  Tool panel (left)
# =====================================================================
func _on_mode_object_pressed() -> void: builder.set_mode(ShipBuilder.Mode.OBJECT)
func _on_mode_vertex_pressed() -> void: builder.set_mode(ShipBuilder.Mode.VERTEX)
func _on_mode_edge_pressed() -> void: builder.set_mode(ShipBuilder.Mode.EDGE)
func _on_mode_face_pressed() -> void: builder.set_mode(ShipBuilder.Mode.FACE)

func _on_grab_pressed() -> void: builder.begin_transform(BuilderTransformTool.Kind.GRAB)
func _on_rotate_pressed() -> void: builder.begin_transform(BuilderTransformTool.Kind.ROTATE)
func _on_scale_pressed() -> void: builder.begin_transform(BuilderTransformTool.Kind.SCALE)

func _on_extrude_pressed() -> void: builder.extrude()
func _on_add_vertex_pressed() -> void: builder.add_vertex_on_edge()
func _on_connect_pressed() -> void: builder.connect_vertices()
func _on_link_pressed() -> void: builder.link_vertices()
func _on_unlink_pressed() -> void: builder.unlink_vertices()
func _on_mirror_pressed() -> void: builder.mirror()
func _on_duplicate_pressed() -> void: builder.duplicate_selection()
func _on_delete_pressed() -> void: builder.delete_selection()
func _on_frame_pressed() -> void: builder.frame_selection()


func _on_snap_changed(value: float) -> void:
	builder.snap_step = value


func _on_auto_link_toggled(on: bool) -> void:
	builder.auto_link = on


# =====================================================================
#  "Add" tab
# =====================================================================
func _on_new_type_selected(index: int) -> void:
	var type: String = ModuleCatalog.TYPES[index]
	new_type_help.text = ModuleCatalog.TYPE_HELP[type]
	# Pick that type's usual shape and size, the player can still change them.
	var prim: String = ModuleCatalog.DEFAULT_PRIMITIVE[type]
	new_shape_picker.select(Primitives.NAMES.find(prim))
	var half: Vector3 = ModuleCatalog.DEFAULT_HALF_SIZE[type]
	new_size_x_spin.value = half.x
	new_size_y_spin.value = half.y
	new_size_z_spin.value = half.z
	_on_new_shape_selected(new_shape_picker.selected)


func _on_new_shape_selected(index: int) -> void:
	# "Segments" only matters for round shapes.
	new_segments_spin.editable = Primitives.is_round(Primitives.NAMES[index])


func _on_add_module_pressed() -> void:
	var type: String = ModuleCatalog.TYPES[new_type_picker.selected]
	var prim: String = Primitives.NAMES[new_shape_picker.selected]
	var half := Vector3(new_size_x_spin.value, new_size_y_spin.value, new_size_z_spin.value)
	builder.add_module(type, prim, half, int(new_segments_spin.value))


# =====================================================================
#  "Selection" tab
# =====================================================================
func _on_center_changed(_value: float) -> void:
	if _refreshing:
		return
	builder.move_selection_center_to(Vector3(center_x_spin.value, center_y_spin.value, center_z_spin.value))


func _on_active_type_selected(index: int) -> void:
	if not _refreshing:
		builder.set_active_type(ModuleCatalog.TYPES[index])


func _on_material_selected(index: int) -> void:
	if not _refreshing:
		builder.set_active_material(MaterialCatalog.IDS[index])


func _on_crew_seats_changed(value: float) -> void:
	if not _refreshing:
		builder.set_commander_crew(int(value))


func _on_thrust_dir_changed(_value: float) -> void:
	if not _refreshing:
		builder.set_thruster_direction(Vector3(thrust_dir_x_spin.value, thrust_dir_y_spin.value, thrust_dir_z_spin.value))


## Preset buttons pass the direction as a bind (see gen_builder.py).
func _on_thrust_dir_preset_pressed(dir: Vector3) -> void:
	builder.set_thruster_direction(dir)


func _on_thrust_power_changed(value: float) -> void:
	if not _refreshing:
		builder.set_thruster_power(value)


# =====================================================================
#  "Ship" tab
# =====================================================================
func _on_reactor_changed(value: float) -> void:
	if not _refreshing:
		builder.set_reactor_scale(value)


func _on_gyro_changed(value: float) -> void:
	if not _refreshing:
		builder.set_gyro_scale(value)
