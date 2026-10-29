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
##   TopBar          back, ship name, New / Save / Load, Undo / Redo, Plan
##   ToolPanel       (left)  the SELECTION TYPE menu (object / vertex / edge / face), the tools of that type, then the
##                   tools for every type. These buttons are built from builder_tools.gd, not placed in the scene.
##   ViewportBar     (top centre) shading (solid / x-ray / wireframe), camera views, overlays, snap
##   OperatorPanel   the numbers of the last bevel / extrude / inset... (operator_panel.gd)
##   SidePanel       (right) tabs: "Create" (ship OR module), "Properties" (selection details), "Ship" (stats, problems)
##   StatusBar       (bottom) last message + key help

## The builder is the grandparent in the scene tree: ShipBuilder / UI / BuilderUI.
@onready var builder: ShipBuilder = get_node("../..")

# ---- top bar
@onready var ship_name_edit: LineEdit = %ShipNameEdit
@onready var load_picker: OptionButton = %LoadPicker
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
# ---- tool panel + viewport bar
@onready var mode_menu: MenuButton = %ModeMenuButton
@onready var mode_info_label: Label = %ModeInfoLabel
@onready var context_tool_list: VBoxContainer = %ContextToolList
@onready var common_tool_list: VBoxContainer = %CommonToolList
@onready var shading_menu: MenuButton = %ShadingMenuButton
@onready var view_menu: MenuButton = %ViewMenuButton
@onready var overlays_menu: MenuButton = %OverlaysMenuButton
@onready var snap_spin: SpinBox = %SnapSpin
@onready var auto_link_check: CheckBox = %AutoLinkCheck
@onready var operator_panel: OperatorPanel = %OperatorPanel
@onready var box_overlay: Control = %BoxSelectOverlay
# ---- "Create" tab
@onready var create_ship_button: Button = %CreateShipButton
@onready var create_module_button: Button = %CreateModuleButton
@onready var ship_creation_section: VBoxContainer = %ShipCreationSection
@onready var module_creation_section: VBoxContainer = %ModuleCreationSection
@onready var type_grid: GridContainer = %TypeGrid
@onready var shape_grid: GridContainer = %ShapeGrid
@onready var new_type_label: Label = %NewTypeLabel
@onready var new_type_help: Label = %NewTypeHelp
@onready var new_segments_spin: SpinBox = %NewSegmentsSpin
@onready var new_axis_picker: OptionButton = %NewAxisPicker
@onready var new_axis_row: HBoxContainer = %NewAxisRow
@onready var new_round_row: HBoxContainer = %NewRoundRow
@onready var new_size_row: HBoxContainer = %NewSizeRow
@onready var new_radius_spin: SpinBox = %NewRadiusSpin
@onready var new_height_spin: SpinBox = %NewHeightSpin
@onready var new_selection_warning: Label = %NewSelectionWarning
@onready var new_size_x_spin: SpinBox = %NewSizeXSpin
@onready var new_size_y_spin: SpinBox = %NewSizeYSpin
@onready var new_size_z_spin: SpinBox = %NewSizeZSpin
# ---- "Selection" tab
@onready var selection_info_label: Label = %SelectionInfoLabel
@onready var center_section: VBoxContainer = %CenterSection
@onready var center_x_spin: SpinBox = %CenterXSpin
@onready var center_y_spin: SpinBox = %CenterYSpin
@onready var center_z_spin: SpinBox = %CenterZSpin
@onready var size_x_spin: SpinBox = %SizeXSpin
@onready var size_y_spin: SpinBox = %SizeYSpin
@onready var size_z_spin: SpinBox = %SizeZSpin
@onready var active_module_section: VBoxContainer = %ActiveModuleSection
@onready var active_module_label: Label = %ActiveModuleLabel
@onready var active_type_picker: OptionButton = %ActiveTypePicker
@onready var active_type_help: Label = %ActiveTypeHelp
@onready var material_picker: OptionButton = %MaterialPicker
@onready var material_help: Label = %MaterialHelp
@onready var stats_section: VBoxContainer = %ModuleStatsSection
@onready var preset_picker: OptionButton = %PresetPicker
@onready var preset_help: Label = %PresetHelp
@onready var stats_list: VBoxContainer = %StatsList
@onready var derived_label: Label = %DerivedLabel
@onready var preset_name_edit: LineEdit = %PresetNameEdit
@onready var new_preset_picker: OptionButton = %NewPresetPicker
@onready var new_preset_help: Label = %NewPresetHelp
@onready var save_premade_button: Button = %SavePremadeButton
@onready var plan_view: PlanView = %PlanView
@onready var turret_section: VBoxContainer = %TurretSection
@onready var commander_section: VBoxContainer = %CommanderSection
@onready var pilot_check: CheckBox = %PilotCheck
@onready var commander_link_label: Label = %CommanderLinkLabel
@onready var turret_link_label: Label = %TurretLinkLabel
@onready var turret_axis_x_spin: SpinBox = %TurretAxisXSpin
@onready var turret_axis_y_spin: SpinBox = %TurretAxisYSpin
@onready var turret_axis_z_spin: SpinBox = %TurretAxisZSpin
@onready var turret_yaw_min_spin: SpinBox = %TurretYawMinSpin
@onready var turret_yaw_max_spin: SpinBox = %TurretYawMaxSpin
@onready var turret_pitch_min_spin: SpinBox = %TurretPitchMinSpin
@onready var turret_pitch_max_spin: SpinBox = %TurretPitchMaxSpin
@onready var thruster_section: VBoxContainer = %ThrusterSection
@onready var thrust_dir_x_spin: SpinBox = %ThrustDirXSpin
@onready var thrust_dir_y_spin: SpinBox = %ThrustDirYSpin
@onready var thrust_dir_z_spin: SpinBox = %ThrustDirZSpin
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


var _tool_buttons: Dictionary = {}       ## tool id -> Button (the buttons of the panel that is shown + the common ones)
var _built_mode: int = -1
var _selected_shape: String = "box"
var _preset_ids_for_new: Array = []


func _ready() -> void:
	for label_text in ["Up (Y)", "Forward (Z, the way the ship points)", "Side (X)"]:
		new_axis_picker.add_item(label_text)
	theme = BuilderTheme.make()
	for t in ModuleCatalog.TYPES:
		active_type_picker.add_item(t.capitalize())
	for id in MaterialCatalog.IDS:
		material_picker.add_item(MaterialCatalog.info(id)["name"])
	_set_static_icons()
	_build_menus()
	_build_common_tools()
	operator_panel.setup(builder)
	builder.box_changed.connect(func(r: Rect2): box_overlay.show_box(r))
	builder.operator_changed.connect(refresh_all)
	builder.message.connect(func(text: String): status_label.text = text)
	BusEvent.builder_design_changed.connect(refresh_all)
	BusEvent.builder_selection_changed.connect(refresh_all)
	BusEvent.builder_design_saved.connect(func(_n): refresh_ship_list())
	refresh_ship_list()
	_on_create_mode_pressed("module")
	_on_type_button_pressed(ModuleCatalog.HULL)
	refresh_all()


## Icons for the buttons that are in the scene (the tool buttons get theirs when they are built).
func _set_static_icons() -> void:
	for pair in [["UndoButton", "undo"], ["RedoButton", "redo"], ["BackToMenuButton", "back"], ["SaveButton", "save"], ["NewButton", "new"],
			["PlanButton", "plan"], ["NewStarterShipButton", "ship_starter"], ["NewBlankShipButton", "ship_blank"]]:
		var b := get_node_or_null("%" + pair[0]) as Button
		if b != null:
			b.icon = BuilderIcons.get_icon(pair[1])
	for t in ModuleCatalog.TYPES:
		var tb := type_grid.get_node("TypeButton_" + t) as Button
		tb.icon = BuilderIcons.get_icon("type_" + t, 28)
		tb.expand_icon = false
		tb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for n in Primitives.NAMES:
		var sb := shape_grid.get_node("ShapeButton_" + n) as Button
		sb.icon = BuilderIcons.get_icon("shape_" + n, 26)
		sb.expand_icon = false
		sb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	create_ship_button.icon = BuilderIcons.get_icon("ship_blank", 20)
	create_module_button.icon = BuilderIcons.get_icon("shape_box", 20)


## The three drop-down menus: selection type (left panel), shading, camera + overlays (viewport bar).
func _build_menus() -> void:
	# --- selection type: one button, a menu with an icon per type; hovering shows what it is
	var pm := mode_menu.get_popup()
	for i in BuilderTools.MODES.size():
		var m: Dictionary = BuilderTools.MODES[i]
		pm.add_icon_item(BuilderIcons.get_icon(m["icon"]), "%s     [%s]" % [m["label"], m["key"]], i)
		pm.set_item_tooltip(i, m["tip"])
	pm.id_pressed.connect(func(id: int): builder.set_mode(id as ShipBuilder.Mode))
	mode_menu.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# --- shading
	var ps := shading_menu.get_popup()
	for item in [[0, "shading_solid", "Solid", "Opaque. Vertices and edges behind a module are hidden and cannot be picked."],
			[1, "shading_xray", "X-ray  [Alt+Z]", "See through the ship: every vertex, edge and face can be picked."],
			[2, "shading_wire", "Wireframe", "Only the edges, nothing in the way."]]:
		ps.add_icon_radio_check_item(BuilderIcons.get_icon(item[1]), item[2], item[0])
		ps.set_item_tooltip(item[0], item[3])
	ps.id_pressed.connect(func(id: int): builder.set_shading(id as ShipBuilder.Shading))
	shading_menu.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# --- camera
	var pv := view_menu.get_popup()
	view_menu.icon = BuilderIcons.get_icon("view")
	pv.add_icon_radio_check_item(BuilderIcons.get_icon("persp"), "Perspective", 100)
	pv.add_icon_radio_check_item(BuilderIcons.get_icon("ortho"), "Orthographic  [Num 5]", 101)
	pv.add_separator()
	for item in [[1, "Front  [Num 1]", "front"], [2, "Back  [Ctrl+Num 1]", "back"], [3, "Right  [Num 3]", "right"], [4, "Left  [Ctrl+Num 3]", "left"],
			[5, "Top  [Num 7]", "top"], [6, "Bottom  [Ctrl+Num 7]", "bottom"]]:
		pv.add_icon_item(BuilderIcons.get_icon("cam_top" if item[2] in ["top", "bottom"] else ("cam_side" if item[2] in ["left", "right"] else "cam_front")), item[1], item[0])
	pv.add_separator()
	pv.add_icon_item(BuilderIcons.get_icon("frame"), "Frame the whole ship", 200)
	pv.id_pressed.connect(_on_view_menu_id)
	# --- overlays
	var po := overlays_menu.get_popup()
	overlays_menu.icon = BuilderIcons.get_icon("overlays")
	var i := 0
	for key in OVERLAY_LABELS:
		po.add_check_item(OVERLAY_LABELS[key], i)
		po.set_item_checked(i, builder.overlays[key])
		i += 1
	po.hide_on_checkable_item_selection = false
	po.id_pressed.connect(func(id: int):
		var key: String = OVERLAY_LABELS.keys()[id]
		builder.set_overlay(key, not builder.overlays[key])
		po.set_item_checked(id, builder.overlays[key]))


const OVERLAY_LABELS := {"wire": "Module edges", "axes": "World axes", "thrusters": "Thruster arrows", "exhaust": "Exhaust zones",
	"turrets": "Turret arcs and links", "problems": "Problem highlights (loose / open)"}
const VIEW_NAMES := {1: "front", 2: "back", 3: "right", 4: "left", 5: "top", 6: "bottom"}


func _on_view_menu_id(id: int) -> void:
	if id == 100:
		builder.set_orthographic(false)
	elif id == 101:
		builder.set_orthographic(true)
	elif id == 200:
		builder.camera_rig.focus_on(Vector3.ZERO, 4.0)
	elif VIEW_NAMES.has(id):
		builder.set_camera_view(VIEW_NAMES[id])


# ---------------------------------------------------------------- the tool panel (built from builder_tools.gd)
func _build_common_tools() -> void:
	_fill_tools(common_tool_list, BuilderTools.COMMON_TOOLS)


## (Re)builds the tools of the current selection type.
func _rebuild_context_tools() -> void:
	_built_mode = builder.mode
	for c in context_tool_list.get_children():
		c.queue_free()
		context_tool_list.remove_child(c)
	_fill_tools(context_tool_list, BuilderTools.MODE_TOOLS[builder.mode])


func _fill_tools(box: VBoxContainer, entries: Array) -> void:
	for e in entries:
		if e.has("heading"):
			var h := BuilderTheme.heading(e["heading"])
			h.name = "Heading_" + str(e["heading"]).replace(" ", "")
			box.add_child(h)
		elif e.has("row"):
			var hb := HBoxContainer.new()
			hb.name = "ToolRow"
			for sub in e["row"]:
				var b := _make_tool_button(sub, true)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hb.add_child(b)
			box.add_child(hb)
		else:
			box.add_child(_make_tool_button(e, false))


func _make_tool_button(e: Dictionary, icon_only: bool) -> Button:
	var b := Button.new()
	b.name = "Tool_" + str(e["id"])
	b.icon = BuilderIcons.get_icon(e["icon"])
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	var key: String = e.get("key", "")
	b.tooltip_text = "%s%s\n%s" % [e["label"], ("   [%s]" % key) if key != "" else "", e["tip"]]
	if icon_only:
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(0, 34)
	else:
		b.text = e["label"] + (("    " + key) if key != "" else "")
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_constant_override("h_separation", 8)
	b.pressed.connect(_on_tool_pressed.bind(e))
	_tool_buttons[e["id"]] = b
	return b


func _on_tool_pressed(e: Dictionary) -> void:
	var act: Variant = e["act"]
	if act is Array:
		builder.callv(act[0], act.slice(1))
	elif str(act).begins_with("op:"):
		builder.start_operator(str(act).substr(3))
	else:
		builder.call(act)


## Greys out the tools that cannot be used with the current selection.
func _refresh_tool_states() -> void:
	for id in _tool_buttons.keys():
		var held: Variant = _tool_buttons[id]            # untyped on purpose: a freed button cannot be assigned to a typed variable
		if not is_instance_valid(held):
			_tool_buttons.erase(id)                      # its panel was rebuilt (mode change): forget it
			continue
		var b: Button = held
		b.disabled = not builder.tool_available(id)


# =====================================================================
#  Reading the builder state into the widgets
# =====================================================================
func refresh_all() -> void:
	_refresh_selection_warning()
	_refreshing = true
	var d := builder.design
	if plan_view != null and plan_view.visible:
		plan_view.refresh_design(d)
	if ship_name_edit.text != d.ship_name:
		ship_name_edit.text = d.ship_name
	undo_button.disabled = not builder.can_undo()
	redo_button.disabled = not builder.can_redo()
	save_premade_button.visible = builder.premade_mode   # only for a builder started from the editor plugin
	_refresh_toolbar()
	_refresh_selection_tab()
	_refresh_ship_tab()
	_refreshing = false


## Mode menu text, tool buttons of the chosen selection type, shading / view menus.
func _refresh_toolbar() -> void:
	var m: Dictionary = BuilderTools.MODES[builder.mode]
	mode_menu.text = "%s mode" % m["label"]
	mode_menu.icon = BuilderIcons.get_icon(m["icon"], 24)
	if _built_mode != builder.mode:
		_rebuild_context_tools()
	_refresh_tool_states()
	if builder.has_selection():
		mode_info_label.text = builder.selection_summary()
	else:
		mode_info_label.text = ["Click a module (Shift = add, drag = box).", "Click a vertex (Shift = add, drag = box).",
			"Click an edge (Shift = add, drag = box).", "Click a face (Shift = add, drag = box)."][builder.mode]
	var ps := shading_menu.get_popup()
	for i in 3:
		ps.set_item_checked(i, i == builder.shading)
	shading_menu.text = ["Solid", "X-ray", "Wireframe"][builder.shading]
	shading_menu.icon = BuilderIcons.get_icon(["shading_solid", "shading_xray", "shading_wire"][builder.shading])
	if builder.camera_rig == null:
		return                                   # first refresh can run before the camera exists
	var pv := view_menu.get_popup()
	pv.set_item_checked(pv.get_item_index(100), not builder.camera_rig.orthographic)
	pv.set_item_checked(pv.get_item_index(101), builder.camera_rig.orthographic)


func _refresh_selection_tab() -> void:
	var d := builder.design
	selection_info_label.text = builder.selection_summary()
	center_section.visible = builder.has_selection()
	if builder.has_selection():
		var c := builder.affected_center()
		center_x_spin.set_value_no_signal(c.x)
		center_y_spin.set_value_no_signal(c.y)
		center_z_spin.set_value_no_signal(c.z)
		var sz := builder.selection_bounds().size
		size_x_spin.set_value_no_signal(sz.x)
		size_y_spin.set_value_no_signal(sz.y)
		size_z_spin.set_value_no_signal(sz.z)
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
	_refresh_stats(am)
	commander_section.visible = m["type"] == ModuleCatalog.COMMANDER
	if commander_section.visible:
		pilot_check.set_pressed_no_signal(d.can_pilot(am))
		var ls := d.linked_turrets(am)
		commander_link_label.text = "Controls turrets: %s" % str(ls) if not ls.is_empty() else "No turret linked (select this commander + a turret base, press T)."
	turret_section.visible = m["type"] == ModuleCatalog.TURRET
	if turret_section.visible:
		var axis: Vector3 = m["dir"]
		turret_axis_x_spin.set_value_no_signal(axis.x)
		turret_axis_y_spin.set_value_no_signal(axis.y)
		turret_axis_z_spin.set_value_no_signal(axis.z)
		turret_yaw_min_spin.set_value_no_signal(d.extra(am, "yaw_min"))
		turret_yaw_max_spin.set_value_no_signal(d.extra(am, "yaw_max"))
		turret_pitch_min_spin.set_value_no_signal(d.extra(am, "pitch_min"))
		turret_pitch_max_spin.set_value_no_signal(d.extra(am, "pitch_max"))
		var bars := d.barrels_of(am)
		turret_link_label.text = "Barrels: %s" % str(bars) if not bars.is_empty() else "No barrel linked yet (select base + barrel(s), press T)."
	thruster_section.visible = m["type"] == ModuleCatalog.THRUSTER
	if thruster_section.visible:
		var dir: Vector3 = m["dir"]
		thrust_dir_x_spin.set_value_no_signal(dir.x)
		thrust_dir_y_spin.set_value_no_signal(dir.y)
		thrust_dir_z_spin.set_value_no_signal(dir.z)


## Preset picker + the stat rows of the active module. The rows are rebuilt only when the module / preset changes,
## otherwise the numbers are updated in place (so typing in a box is not interrupted).
var _stats_sig := ""
var _stat_widgets: Dictionary = {}     # key -> SpinBox (main) or Label


func _refresh_stats(am: int) -> void:
	var d := builder.design
	var type: String = d.modules[am]["type"]
	stats_section.visible = ModulePresets.has_presets(type) and not d.cfg(am).is_empty()
	if not stats_section.visible:
		return
	var cfg: Dictionary = d.cfg(am)
	var kind: String = str(cfg.get("kind", ""))
	var ids := ModulePresets.preset_ids(type)
	var sig := "%d|%s|%s|%s" % [am, type, kind, ",".join(ids)]
	if sig != _stats_sig:
		_stats_sig = sig
		preset_picker.clear()
		for id in ids:
			preset_picker.add_item(str(ModulePresets.preset(type, id).get("label", id)))
		for c in stats_list.get_children():
			c.queue_free()
		_stat_widgets.clear()
		for def in ModulePresets.defs_of(type, kind):
			var row := HBoxContainer.new()
			row.name = "Stat_" + str(def["key"])
			var lab := Label.new()
			lab.name = "Label"
			lab.text = "%s (%s)" % [def["label"], def["unit"]] if def["unit"] != "" else str(def["label"])
			lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(lab)
			if def.get("main", false):
				var spin := SpinBox.new()
				spin.name = "Spin"
				spin.min_value = float(def["min"])
				spin.max_value = float(def["max"])
				spin.step = 1.0 if float(def["max"]) > 500.0 else 0.1
				spin.custom_minimum_size.x = 110
				spin.value_changed.connect(_on_main_stat_changed)
				row.add_child(spin)
				_stat_widgets[def["key"]] = spin
			else:
				var val := Label.new()
				val.name = "Value"
				val.modulate = Color(1, 1, 1, 0.8)
				row.add_child(val)
				_stat_widgets[def["key"]] = val
			stats_list.add_child(row)
	var cur := ids.find(str(cfg.get("preset", "")))
	if cur >= 0:
		preset_picker.select(cur)
	preset_help.text = str(ModulePresets.preset(type, str(cfg.get("preset", ""))).get("help", ""))
	for key in _stat_widgets:
		var w: Node = _stat_widgets[key]
		var v := d.stat(am, key)
		if w is SpinBox:
			(w as SpinBox).set_value_no_signal(v)
		else:
			(w as Label).text = _big(v) if v >= 1000.0 else str(snappedf(v, 0.01))
	derived_label.text = _derived_text(d, am, type, kind)


## What the module really does at its current SIZE (stats are per m3: change the shape and these change).
func _derived_text(d: ShipDesign, mi: int, type: String, kind: String) -> String:
	var vol := d.module_volume(mi)
	var t := "Volume %.1f m3" % vol
	match type:
		ModuleCatalog.THRUSTER:
			var n := d.thruster_power(mi)
			t += "\nThrust %s N\nElectricity %s W at full thrust\nHeat %s W (makes the exhaust cone longer)" % [
				_big(n), _big(n * d.stat(mi, "elec_per_n")), _big(n * d.stat(mi, "heat_per_n"))]
		ModuleCatalog.COMMANDER:
			t += "\nSeats: %d  (volume / %.1f m3 per seat)" % [d.crew_capacity_of(mi), d.stat(mi, "seat_volume")]
		ModuleCatalog.BARREL:
			if kind == "beam":
				t += "\nBeam %s damage/s, goes through %.1f m of modules" % [_big(d.stat(mi, "dps_per_m3") * vol), d.stat(mi, "penetration")]
			else:
				t += "\nShot damage %s, one shot every %.2f s" % [_big(d.stat(mi, "damage_per_m3") * vol), d.stat(mi, "cooldown")]
		ModuleCatalog.RADAR:
			t += "\nRange %s m (before the target's signature)" % _big(d.stat(mi, "range_per_m") * pow(maxf(vol, 0.01), 1.0 / 3.0))
		ModuleCatalog.ANTENNA:
			t += "\nSignal strength %.1f (a ship needs %.1f in total for instant orders)" % [d.stat(mi, "strength") * pow(maxf(vol, 0.01), 1.0 / 3.0), Data.COMMS_MIN_STRENGTH]
	var need: float = ModuleCatalog.MIN_EXTENT.get(type, 0.0)
	if need > 0.0:
		var e := d.module_extent(mi)
		t += "\nThinnest side %.2f m (minimum %.1f m: people must fit inside)" % [minf(e.x, minf(e.y, e.z)), need]
	return t


static func _big(v: float) -> String:
	if v >= 1.0e6:
		return "%.2f M" % (v / 1.0e6)
	if v >= 1.0e3:
		return "%.1f k" % (v / 1.0e3)
	return "%.0f" % v


func _on_main_stat_changed(value: float) -> void:
	if not _refreshing:
		builder.set_active_main_stat(value)


func _on_preset_selected(index: int) -> void:
	if _refreshing or builder.active_module < 0:
		return
	var type: String = builder.design.modules[builder.active_module]["type"]
	builder.set_active_preset(ModulePresets.preset_ids(type)[index])


func _on_save_preset_pressed() -> void:
	builder.save_active_as_preset(preset_name_edit.text)
	_stats_sig = ""     # the preset list changed
	refresh_all()


func _on_new_preset_selected(index: int) -> void:
	var ids := ModulePresets.preset_ids(builder.new_module_type)
	if index >= 0 and index < ids.size():
		builder.new_module_preset = ids[index]
		new_preset_help.text = str(ModulePresets.preset(builder.new_module_type, ids[index]).get("help", ""))


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


func _on_new_pressed() -> void: builder.new_ship("starter")
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
func _on_save_premade_pressed() -> void: builder.save_premade()


## Opens the ship plan (rooms + corridors). Corridor edits are undoable like everything else.
func _on_plan_pressed() -> void:
	if plan_view.visible:
		plan_view.visible = false
		return
	if not plan_view.edit_requested.is_connected(_on_plan_edit_requested):
		plan_view.edit_requested.connect(_on_plan_edit_requested)
		plan_view.edited.connect(func(): BusEvent.builder_design_changed.emit())
	plan_view.open_design(builder.design)


func _on_plan_edit_requested() -> void:
	builder.checkpoint()

func _on_snap_changed(value: float) -> void:
	builder.snap_step = value


func _on_pilot_toggled(on: bool) -> void:
	var am := builder.active_module
	if am < 0 or builder.design.modules[am]["type"] != ModuleCatalog.COMMANDER:
		return
	builder.checkpoint()
	builder.design.modules[am]["cfg"]["pilot"] = on
	builder.on_design_changed()


func _on_auto_link_toggled(on: bool) -> void:
	builder.auto_link = on


# =====================================================================
#  "Create" tab: ship creation OR module creation
# =====================================================================
func _on_create_mode_pressed(which: String) -> void:
	ship_creation_section.visible = which == "ship"
	module_creation_section.visible = which == "module"
	create_ship_button.set_pressed_no_signal(which == "ship")
	create_module_button.set_pressed_no_signal(which == "module")


func _on_new_ship_template_pressed(template: String) -> void:
	builder.new_ship(template)


func _on_type_button_pressed(type: String) -> void:
	builder.new_module_type = type
	(type_grid.get_node("TypeButton_" + type) as Button).set_pressed_no_signal(true)
	new_type_label.text = type.replace("_", " ").capitalize()
	new_type_help.text = ModuleCatalog.TYPE_HELP[type]
	new_preset_picker.clear()
	_preset_ids_for_new = ModulePresets.preset_ids(type)
	for id in _preset_ids_for_new:
		new_preset_picker.add_item(str(ModulePresets.preset(type, id).get("label", id)))
	new_preset_picker.visible = not _preset_ids_for_new.is_empty()
	new_preset_help.visible = not _preset_ids_for_new.is_empty()
	if not _preset_ids_for_new.is_empty():
		new_preset_picker.select(0)
		_on_new_preset_selected(0)
	else:
		builder.new_module_preset = ""
	# Pick that type's usual shape and size, the player can still change them.
	_on_shape_button_pressed(ModuleCatalog.DEFAULT_PRIMITIVE[type])
	var half: Vector3 = ModuleCatalog.DEFAULT_HALF_SIZE[type]
	new_size_x_spin.value = half.x * 2.0
	new_size_y_spin.value = half.y * 2.0
	new_size_z_spin.value = half.z * 2.0
	var rd: Dictionary = ModuleCatalog.DEFAULT_ROUND.get(type, {"radius": 0.5, "height": 1.0, "axis": 0})
	new_radius_spin.value = rd["radius"]
	new_height_spin.value = rd["height"]
	new_axis_picker.select(int(rd["axis"]))


func _on_shape_button_pressed(prim: String) -> void:
	_selected_shape = prim
	(shape_grid.get_node("ShapeButton_" + prim) as Button).set_pressed_no_signal(true)
	new_segments_spin.editable = Primitives.is_round(prim)       # "round detail" only matters for round shapes
	# round shapes are described by a base radius and a height, the others by width / height / length
	new_round_row.visible = Primitives.is_round(prim)
	new_axis_row.visible = Primitives.is_round(prim) and prim != "sphere"
	new_height_spin.get_parent().visible = prim != "sphere"
	new_size_row.visible = not Primitives.is_round(prim)


## The half-size the shape needs, from the fields that are shown.
func _new_half_size() -> Vector3:
	var r := new_radius_spin.value
	var h := new_height_spin.value
	match _selected_shape:
		"cylinder", "cone": return Vector3(r, h * 0.5, r)
		"dome": return Vector3(r, h, r)                         # a dome only reaches up from its base: its height is the full half-size
		"sphere": return Vector3(r, r, r)
	return Vector3(new_size_x_spin.value, new_size_y_spin.value, new_size_z_spin.value) * 0.5


func _on_add_module_pressed() -> void:
	builder.add_shape(builder.new_module_type, _selected_shape, _new_half_size(), int(new_segments_spin.value), new_axis_picker.selected, false)


func _on_add_module_on_selection_pressed() -> void:
	builder.add_shape(builder.new_module_type, _selected_shape, _new_half_size(), int(new_segments_spin.value), new_axis_picker.selected, true)


## Warns when the shape would be welded to several selected parts at once.
func _refresh_selection_warning() -> void:
	var n: int = builder.sel_faces.size() + builder.sel_edges.size() + builder.sel_verts.size()
	new_selection_warning.text = "%d parts are selected: \"Add on the selected part\" will place the shape on all of them and try to link them in the best way it can. The result may be a strange form." % n if n > 1 else ""


# =====================================================================
#  "Selection" tab
# =====================================================================
func _on_center_changed(_value: float) -> void:
	if _refreshing:
		return
	builder.move_selection_center_to(Vector3(center_x_spin.value, center_y_spin.value, center_z_spin.value))


func _on_size_changed(_value: float) -> void:
	if _refreshing:
		return
	builder.set_selection_size(Vector3(size_x_spin.value, size_y_spin.value, size_z_spin.value))


func _on_active_type_selected(index: int) -> void:
	if not _refreshing:
		builder.set_active_type(ModuleCatalog.TYPES[index])


func _on_material_selected(index: int) -> void:
	if not _refreshing:
		builder.set_active_material(MaterialCatalog.IDS[index])


func _on_thrust_dir_changed(_value: float) -> void:
	if not _refreshing:
		builder.set_thruster_direction(Vector3(thrust_dir_x_spin.value, thrust_dir_y_spin.value, thrust_dir_z_spin.value))


## Preset buttons pass the direction as a bind (see gen_builder.py).
func _on_thrust_dir_preset_pressed(dir: Vector3) -> void:
	builder.set_thruster_direction(dir)


func _on_turret_axis_changed(_value: float) -> void:
	if not _refreshing:
		builder.set_thruster_direction(Vector3(turret_axis_x_spin.value, turret_axis_y_spin.value, turret_axis_z_spin.value))


func _on_turret_value_changed(value: float, key: String) -> void:
	if not _refreshing:
		builder.set_turret_value(key, value)


# =====================================================================
#  "Ship" tab
# =====================================================================
func _on_reactor_changed(value: float) -> void:
	if not _refreshing:
		builder.set_reactor_scale(value)


func _on_gyro_changed(value: float) -> void:
	if not _refreshing:
		builder.set_gyro_scale(value)
