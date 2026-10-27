"""Generates scenes/ship_builder.tscn  (run:  python3 tools/gen_builder.py).

Node tree overview (names are descriptive on purpose):
  ShipBuilder (Node3D, ship_builder.gd)
    WorldEnvironment, SunLight, FillLight, GroundGrid
    CameraRig (builder_camera.gd) / Camera
    View (builder_view.gd) / ShipMesh, VertexDots, OverlayMesh
    TransformTool (transform_tool.gd)
    UI (CanvasLayer) / BuilderUI (builder_ui.gd) / TopBar, ToolPanel (left), ViewportBar, OperatorPanel, SidePanel (right), StatusBar
The buttons of the left panel are NOT in this file: builder_ui.gd builds them from the table in builder_tools.gd.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from tscn import *

def heading(text, name):
    return label(text, name, modulate="Color(0.62, 0.8, 1, 1)")

def row(title, name, *widgets):
    """Label + widgets on one line. `name` is the prefix of the generated node names."""
    return hbox(name + "Row", [label(title, name + "Label")] + list(widgets))

def opt(name, **extra):
    p = {"layout_mode": 2, "size_flags_horizontal": 3}; p.update(extra)
    return N(name, "OptionButton", p, unique=True)

def tool_button(text, name, tip, **extra):
    return button(text, name, unique=True, tooltip_text=s(tip), **extra)

def panel(name, preset_props, kids):
    p = {"layout_mode": 1}; p.update(preset_props)
    return N(name, "PanelContainer", p, [N(name + "Margin", "MarginContainer", {
        "layout_mode": 2, "theme_override_constants/margin_left": 10, "theme_override_constants/margin_right": 10,
        "theme_override_constants/margin_top": 8, "theme_override_constants/margin_bottom": 8}, kids)])

TYPES = ["hull", "armor", "thruster", "turret", "turret_barrel", "commander", "radar", "antenna"]   # = ModuleCatalog.TYPES
SHAPES = ["box", "wedge", "pyramid", "tetra", "cylinder", "cone", "sphere", "dome"]                # = Primitives.NAMES

def build():
    # ============================================================ 3D side
    shader_code = s("shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled;\n"
        "varying vec3 wp;\nvoid vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }\n"
        "void fragment() {\n\tvec2 g = abs(fract(wp.xz - 0.5) - 0.5) / fwidth(wp.xz);\n"
        "\tfloat l = 1.0 - min(min(g.x, g.y), 1.0);\n\tALBEDO = vec3(0.4, 0.6, 0.9);\n\tALPHA = l * 0.28;\n}\n")
    camera = N("Camera", "Camera3D", {"transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 9)", "current": "true", "fov": 60.0}, unique=True)
    camera_rig = N("CameraRig", "Node3D", {}, [camera], unique=True, script='ExtResource("3_cam")')
    ship_mesh = N("ShipMesh", "MeshInstance3D", {}, unique=True)
    vertex_dots = N("VertexDots", "MultiMeshInstance3D", {}, unique=True)
    overlay = N("OverlayMesh", "MeshInstance3D", {}, unique=True)
    view = N("View", "Node3D", {}, [ship_mesh, vertex_dots, overlay], unique=True, script='ExtResource("4_view")')
    transform_tool = N("TransformTool", "Node", {}, unique=True, script='ExtResource("5_tool")')
    env_node = N("WorldEnvironment", "WorldEnvironment", {})
    ground = N("GroundGrid", "MeshInstance3D", {})
    sun = N("SunLight", "DirectionalLight3D", {"transform": "Transform3D(0.8, -0.35, 0.5, 0, 0.82, 0.57, -0.6, -0.45, 0.66, 0, 6, 0)", "light_energy": 1.1})
    fill = N("FillLight", "DirectionalLight3D", {"transform": "Transform3D(-0.9, 0.2, -0.4, 0, 0.9, 0.45, 0.45, 0.4, -0.8, 0, 6, 0)", "light_energy": 0.45})

    # ============================================================ UI: top bar
    ship_name_edit = line("ShipNameEdit", "My Ship", placeholder_text=s("Ship name"))
    load_picker = opt("LoadPicker")
    back_b = button("", "BackToMenuButton", tooltip_text=s("Back to the menu"))
    new_b = button("New", "NewButton", tooltip_text=s("Start a fresh ship (see the Create tab for templates)"))
    save_b = tool_button("Save", "SaveButton", "Save to user://ships/ (Ctrl+S). Needs exactly one Commander and a thruster.")
    load_b = button("Load", "LoadButton", tooltip_text=s("Load the ship picked in the list"))
    undo_b = tool_button("", "UndoButton", "Undo (Ctrl+Z)")
    redo_b = tool_button("", "RedoButton", "Redo (Ctrl+Y)")
    plan_b = button("Plan", "PlanButton", unique=True, tooltip_text=s("The emergency plan: rooms, corridors and doors"))
    premade_b = button("Save as PREMADE", "SavePremadeButton", unique=True, visible="false", tooltip_text=s("Only when run from the Godot editor: writes into res://ships/"))
    spacer = N("TopBarSpacer", "Control", {"layout_mode": 2, "size_flags_horizontal": 3})
    top_bar = panel("TopBar", {"anchors_preset": 10, "anchor_right": 1.0, "offset_left": 8.0, "offset_top": 8.0, "offset_right": -8.0,
                               "offset_bottom": 56.0, "grow_horizontal": 2},
                    [hbox("TopBarRow", [back_b, ship_name_edit, new_b, save_b, load_picker, load_b, spacer,
                                        undo_b, redo_b, plan_b, premade_b])])
    ship_name_edit.props["custom_minimum_size"] = "Vector2(220, 0)"
    ship_name_edit.props["size_flags_horizontal"] = 1
    load_picker.props["custom_minimum_size"] = "Vector2(200, 0)"
    load_picker.props["size_flags_horizontal"] = 1

    # ============================================================ UI: tool panel (left)
    # Only the frame is here. ContextToolList (tools of the chosen selection type) and CommonToolList (tools for every type)
    # are filled by builder_ui.gd from the table in builder_tools.gd.
    mode_menu = N("ModeMenuButton", "MenuButton", {"layout_mode": 2, "text": s("Object"), "flat": "false", "alignment": 0,
                  "custom_minimum_size": "Vector2(0, 40)", "tooltip_text": s("Selection type: what a click selects (1 object, 2 vertex, 3 edge, 4 face)")}, unique=True)
    tool_panel = panel("ToolPanel", {"anchors_preset": 9, "anchor_bottom": 1.0, "offset_left": 8.0, "offset_top": 64.0,
                                    "offset_right": 244.0, "offset_bottom": -48.0, "grow_vertical": 2},
        [vbox("ToolColumn", [
            mode_menu,
            label("", "ModeInfoLabel", unique=True, wrap=True, modulate="Color(1, 1, 1, 0.6)"),
            N("ContextScroll", "ScrollContainer", {"layout_mode": 2, "size_flags_vertical": 3, "horizontal_scroll_mode": 0}, [
                vbox("ContextToolList", [], unique=True, size_flags_horizontal=3)]),
            sep("ToolDivider"),
            vbox("CommonToolList", [], unique=True)])])

    # ============================================================ UI: viewport bar (top centre, over the 3D view)
    shading_menu = N("ShadingMenuButton", "MenuButton", {"layout_mode": 2, "text": s("Solid"), "tooltip_text": s("Shading: Solid / X-ray / Wireframe (Alt+Z toggles X-ray)")}, unique=True)
    view_menu = N("ViewMenuButton", "MenuButton", {"layout_mode": 2, "text": s("View"), "tooltip_text": s("Camera: perspective / orthographic and standard views (numpad 1, 3, 7, 5)")}, unique=True)
    overlay_menu = N("OverlaysMenuButton", "MenuButton", {"layout_mode": 2, "text": s("Overlays"), "tooltip_text": s("What the viewport shows besides the modules")}, unique=True)
    snap_spin = spin("SnapSpin", 0, 1, 0.05, 0.1, expand=False, tooltip_text=s("Moves jump by this many metres. 0 = free."))
    auto_link = N("AutoLinkCheck", "CheckBox", {"layout_mode": 2, "text": s("Auto-link"), "button_pressed": "true",
                  "tooltip_text": s("Dropping a vertex on another module's vertex links them")}, unique=True)
    pilot_check = N("PilotCheck", "CheckBox", {"layout_mode": 2, "text": s("Holds the flight controls (pilot)"), "button_pressed": "true",
                    "tooltip_text": s("Untick for a gunner-only bridge: whoever sits here cannot fly the ship")}, unique=True)
    viewport_bar = panel("ViewportBar", {"anchors_preset": 5, "anchor_left": 0.5, "anchor_right": 0.5, "offset_left": -250.0, "offset_top": 64.0,
                                        "offset_right": 250.0, "offset_bottom": 104.0, "grow_horizontal": 2},
        [hbox("ViewportBarRow", [shading_menu, view_menu, overlay_menu, N("ViewportBarDivider", "VSeparator", {"layout_mode": 2}),
                                 label("Snap", "SnapLabel"), snap_spin, auto_link], alignment=1)])

    # ============================================================ UI: operator panel ("Adjust last operation")
    op_panel = panel("OperatorPanel", {"anchor_top": 1.0, "anchor_bottom": 1.0, "offset_left": 252.0, "offset_top": -52.0, "offset_right": 252.0,
                                      "offset_bottom": -52.0, "grow_vertical": 0, "custom_minimum_size": "Vector2(330, 0)", "visible": "false"},
        [vbox("OperatorColumn", [
            label("BEVEL", "OperatorTitle", unique=True, modulate="Color(1, 0.77, 0.28, 1)"),
            vbox("OperatorParams", [], unique=True),
            label("", "OperatorHint", unique=True, wrap=True, modulate="Color(1, 1, 1, 0.55)"),
            hbox("OperatorButtons", [button("Apply", "OperatorApplyButton", unique=True, size_flags_horizontal=3),
                                     button("Cancel", "OperatorCancelButton", unique=True, size_flags_horizontal=3)])])])
    op_panel.script = 'ExtResource("7_op")'
    op_panel.unique = True
    box_overlay = N("BoxSelectOverlay", "Control", {**full_rect(), "mouse_filter": 2}, unique=True, script='ExtResource("8_box")')

    # ============================================================ UI: side panel (right) with tabs
    # --- Create tab: ship creation OR module creation
    ship_btn = button("Ship", "CreateShipButton", unique=True, toggle_mode="true", button_group='SubResource("ButtonGroup_create")', size_flags_horizontal=3,
                      tooltip_text=s("Start a ship: templates and premade ships"))
    mod_btn = button("Module", "CreateModuleButton", unique=True, toggle_mode="true", button_pressed="true", button_group='SubResource("ButtonGroup_create")',
                     size_flags_horizontal=3, tooltip_text=s("Add a module (hull, thruster, turret...) to the ship"))
    type_buttons = [button("", "TypeButton_" + t, toggle_mode="true", button_group='SubResource("ButtonGroup_types")', custom_minimum_size="Vector2(0, 44)",
                           size_flags_horizontal=3, tooltip_text=s(t.replace("turret_barrel", "turret barrel").capitalize()), expand_icon="true") for t in TYPES]
    type_buttons[0].props["button_pressed"] = "true"
    shape_buttons = [button("", "ShapeButton_" + n, toggle_mode="true", button_group='SubResource("ButtonGroup_shapes")', custom_minimum_size="Vector2(0, 40)",
                            size_flags_horizontal=3, tooltip_text=s(n.capitalize()), expand_icon="true") for n in SHAPES]
    shape_buttons[0].props["button_pressed"] = "true"
    def size_cell(title, name, val):
        return vbox(name + "Cell", [label(title, name + "Label", modulate="Color(1, 1, 1, 0.6)"), spin(name + "Spin", 0.05, 10, 0.05, val)], size_flags_horizontal=3)
    ship_section = vbox("ShipCreationSection", [
        heading("START A NEW SHIP", "StartShipHeading"),
        label("A starter ship has a hull, a bridge and an engine, so it can be saved at once. A blank ship is empty: add every module yourself.", "StartShipHelp", wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
        hbox("StartShipRow", [button("Starter ship", "NewStarterShipButton", unique=True, size_flags_horizontal=3, custom_minimum_size="Vector2(0, 52)", tooltip_text=s("Hull + bridge + engine")),
                              button("Blank ship", "NewBlankShipButton", unique=True, size_flags_horizontal=3, custom_minimum_size="Vector2(0, 52)", tooltip_text=s("Nothing in it"))]),
        sep("StartShipDivider"),
        heading("OR START FROM A PREMADE SHIP", "PremadeHeading"),
        label("Pick one in the list at the top (next to Load) and press Load: you edit your own copy.", "PremadeHelp", wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
    ], unique=True)
    module_section = vbox("ModuleCreationSection", [
        heading("MODULE TYPE", "NewTypeHeading"),
        N("TypeGrid", "GridContainer", {"layout_mode": 2, "columns": 4}, type_buttons, unique=True),
        label("", "NewTypeLabel", unique=True),
        label("", "NewTypeHelp", unique=True, wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
        heading("PRESET", "NewPresetHeading"),
        opt("NewPresetPicker"),
        label("", "NewPresetHelp", unique=True, wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
        heading("SHAPE", "NewShapeHeading"),
        N("ShapeGrid", "GridContainer", {"layout_mode": 2, "columns": 4}, shape_buttons, unique=True),
        row("Round detail", "NewSegments", spin("NewSegmentsSpin", 6, 32, 2, 12, tooltip_text=s("Number of sides of cylinders, cones, spheres and domes"))),
        heading("SIZE  (half-size in metres, from the centre)", "NewSizeHeading"),
        hbox("NewSizeRow", [size_cell("X", "NewSizeX", 0.5), size_cell("Y", "NewSizeY", 0.5), size_cell("Z", "NewSizeZ", 0.5)]),
        button("Add module at the view centre", "AddModuleButton", unique=True, custom_minimum_size="Vector2(0, 44)",
               tooltip_text=s("The new module appears where the camera looks. Then press G to move it.")),
        label("Modules start unattached: move them next to each other, then link vertices (L) so they stay together.", "AddTip", wrap=True, modulate="Color(1, 1, 1, 0.55)"),
    ], unique=True)
    add_tab = vbox("Add", [hbox("CreateModeRow", [ship_btn, mod_btn]), ship_section, module_section])
    # --- Properties tab
    dir_names = [("-Z fwd", "Vector3(0, 0, -1)"), ("+Z", "Vector3(0, 0, 1)"), ("+X", "Vector3(1, 0, 0)"),
                 ("-X", "Vector3(-1, 0, 0)"), ("+Y", "Vector3(0, 1, 0)"), ("-Y", "Vector3(0, -1, 0)")]
    dir_buttons = [(button(t, "ThrustDirPreset%d" % i, tooltip_text=s("Thruster pushes the ship toward " + t)), v) for i, (t, v) in enumerate(dir_names)]
    turret_axis_buttons = [(button(t, "TurretAxisPreset%d" % i, tooltip_text=s("Turret swivel 'up' axis: " + t)), v) for i, (t, v) in enumerate(dir_names)]
    sel_tab = vbox("Selection", [
        label("", "SelectionInfoLabel", unique=True, wrap=True),
        vbox("CenterSection", [
            heading("POSITION OF SELECTION (m)", "CenterHeading"),
            hbox("CenterRow", [spin("CenterXSpin", -100, 100, 0.05, 0), spin("CenterYSpin", -100, 100, 0.05, 0), spin("CenterZSpin", -100, 100, 0.05, 0)]),
            heading("SIZE OF SELECTION (m)", "SizeHeading"),
            hbox("SizeRow", [spin("SizeXSpin", 0, 200, 0.05, 1), spin("SizeYSpin", 0, 200, 0.05, 1), spin("SizeZSpin", 0, 200, 0.05, 1)]),
            label("Type exact numbers here instead of dragging.", "CenterTip", modulate="Color(1, 1, 1, 0.55)")], unique=True),
        sep("SelectionDivider"),
        vbox("ActiveModuleSection", [
            heading("ACTIVE MODULE", "ActiveModuleHeading"),
            label("", "ActiveModuleLabel", unique=True),
            opt("ActiveTypePicker"),
            label("", "ActiveTypeHelp", unique=True, wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
            label("Material (decides damage resistance and dents)", "MaterialLabel", wrap=True), opt("MaterialPicker"),
            label("", "MaterialHelp", unique=True, wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
            vbox("ModuleStatsSection", [
                heading("PRESET & STATS", "StatsSectionHeading"),
                opt("PresetPicker"),
                label("", "PresetHelp", unique=True, wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
                vbox("StatsList", [], unique=True),
                label("", "DerivedLabel", unique=True, wrap=True, modulate="Color(0.9, 0.85, 0.6, 0.9)"),
                hbox("SavePresetRow", [N("PresetNameEdit", "LineEdit", {"layout_mode": 2, "size_flags_horizontal": 3, "placeholder_text": s("preset name")}, unique=True),
                                       tool_button("Save as preset", "SavePresetButton", "Keep these numbers as your own preset for this module type")])], unique=True),
            vbox("CommanderSection", [
                heading("COMMANDER (bridge)", "CommanderHeading"),
                label("A player only controls what THEIR commander is linked to. Select this commander + a turret base, press T to link / unlink it. Big ships can have a pilot bridge and a gunner bridge.", "CommanderHelp", wrap=True),
                pilot_check,
                label("", "CommanderLinkLabel", unique=True, wrap=True)], unique=True),
            vbox("TurretSection", [
                heading("TURRET BASE (crew station + swivel)", "TurretHeading"),
                label("The barrel (a separate 'Turret barrel' module, link it with T) swivels around the centre of this base. Mount axis = the 'up' of the swivel.", "TurretHelp", wrap=True),
                hbox("TurretAxisRow", [spin("TurretAxisXSpin", -1, 1, 0.05, 0), spin("TurretAxisYSpin", -1, 1, 0.05, 1), spin("TurretAxisZSpin", -1, 1, 0.05, 0)]),
                hbox("TurretAxisPresetRow1", [b for b, _ in turret_axis_buttons[:3]]),
                hbox("TurretAxisPresetRow2", [b for b, _ in turret_axis_buttons[3:]]),
                row("Yaw min (deg)", "TurretYawMin", spin("TurretYawMinSpin", -180, 0, 5, -180)),
                row("Yaw max (deg)", "TurretYawMax", spin("TurretYawMaxSpin", 0, 180, 5, 180)),
                row("Pitch min (deg)", "TurretPitchMin", spin("TurretPitchMinSpin", -90, 0, 5, -10)),
                row("Pitch max (deg)", "TurretPitchMax", spin("TurretPitchMaxSpin", 0, 90, 5, 85)),
                label("", "TurretLinkLabel", unique=True, wrap=True)], unique=True),
            vbox("ThrusterSection", [
                heading("THRUSTER", "ThrusterHeading"),
                label("Direction the thruster PUSHES the ship.\n(The flame goes the opposite way.)", "ThrusterDirHelp", wrap=True),
                hbox("ThrustDirRow", [spin("ThrustDirXSpin", -1, 1, 0.05, 0), spin("ThrustDirYSpin", -1, 1, 0.05, 0), spin("ThrustDirZSpin", -1, 1, 0.05, -1)]),
                hbox("ThrustDirPresetRow1", [b for b, _ in dir_buttons[:3]]),
                hbox("ThrustDirPresetRow2", [b for b, _ in dir_buttons[3:]])], unique=True)], unique=True),
    ])
    # --- Ship tab
    reactor = N("ReactorSlider", "HSlider", {"layout_mode": 2, "size_flags_horizontal": 3, "min_value": 0.15, "max_value": 2.0, "step": 0.05, "value": 1.0}, unique=True)
    gyro = N("GyroSlider", "HSlider", {"layout_mode": 2, "size_flags_horizontal": 3, "min_value": 0.25, "max_value": 3.0, "step": 0.05, "value": 1.0}, unique=True)
    ship_tab = vbox("Ship", [
        heading("STATS", "StatsHeading"),
        label("", "ShipStatsLabel", unique=True, wrap=True),
        heading("PROBLEMS", "ProblemsHeading"),
        label("", "ShipProblemsLabel", unique=True, wrap=True),
        sep("ShipDivider"),
        heading("INTERNAL MODULES (no shell, cannot be shot)", "InternalHeading"),
        hbox("ReactorRow", [label("Electricity", "ReactorTitleLabel"), reactor, label("1.00", "ReactorValueLabel", unique=True)]),
        hbox("GyroRow", [label("Gyroscope", "GyroTitleLabel"), gyro, label("1.00", "GyroValueLabel", unique=True)]),
        label("Electricity powers thrusters and turrets. The gyroscope turns the ship.\nRCS is automatic: always 5% of the ship's best-direction thrust.", "InternalTip", wrap=True, modulate="Color(1, 1, 1, 0.55)"),
    ])
    for t in (add_tab, sel_tab, ship_tab):
        t.props["size_flags_horizontal"] = 3
    tabs = N("SideTabs", "TabContainer", {"layout_mode": 2, "size_flags_vertical": 3, "current_tab": 0}, [
        N("AddScroll", "ScrollContainer", {"layout_mode": 2, "horizontal_scroll_mode": 0}, [add_tab]),
        N("SelectionScroll", "ScrollContainer", {"layout_mode": 2, "horizontal_scroll_mode": 0}, [sel_tab]),
        N("ShipScroll", "ScrollContainer", {"layout_mode": 2, "horizontal_scroll_mode": 0}, [ship_tab])])
    # tab titles come from node names -> rename the scrolls to the titles we want
    tabs.kids[0].name, tabs.kids[1].name, tabs.kids[2].name = "Create", "Properties", "Ship"
    add_tab.name, sel_tab.name, ship_tab.name = "CreateList", "PropertiesList", "ShipList"
    side_panel = panel("SidePanel", {"anchors_preset": 11, "anchor_left": 1.0, "anchor_right": 1.0, "anchor_bottom": 1.0,
                                     "offset_left": -358.0, "offset_top": 64.0, "offset_right": -8.0, "offset_bottom": -48.0,
                                     "grow_horizontal": 0, "grow_vertical": 2}, [tabs])

    # ============================================================ UI: status bar (bottom)
    status_bar = panel("StatusBar", {"anchors_preset": 12, "anchor_top": 1.0, "anchor_right": 1.0, "anchor_bottom": 1.0,
                                     "offset_left": 8.0, "offset_top": -40.0, "offset_right": -8.0, "offset_bottom": -8.0,
                                     "grow_horizontal": 2, "grow_vertical": 0},
        [hbox("StatusRow", [label("Click an element to select it. Drag on empty space = box select. Right mouse = orbit, wheel = zoom.", "StatusLabel", unique=True, size_flags_horizontal=3),
                            label("Forward is -Z  |  Shift+click = add  |  G/R/S then a number = exact  |  Ctrl+Z undo", "KeyHelpLabel", modulate="Color(1, 1, 1, 0.55)")])])
    builder_ui = N("BuilderUI", "Control", {**full_rect(), "mouse_filter": 2},
                   [box_overlay, top_bar, tool_panel, viewport_bar, op_panel, side_panel, status_bar, N("PlanView", None, {}, unique=True, instance='ExtResource("6_plan")')], script='ExtResource("2_ui")')
    ui = N("UI", "CanvasLayer", {}, [builder_ui])
    root = N("ShipBuilder", "Node3D", {}, [env_node, sun, fill, ground, camera_rig, view, transform_tool, ui], script='ExtResource("1_builder")')

    scene = Scene(root)
    scene.ext_res("1_builder", "Script", "res://scripts/builder/ship_builder.gd")
    scene.ext_res("2_ui", "Script", "res://scripts/builder/builder_ui.gd")
    scene.ext_res("3_cam", "Script", "res://scripts/builder/builder_camera.gd")
    scene.ext_res("4_view", "Script", "res://scripts/builder/builder_view.gd")
    scene.ext_res("5_tool", "Script", "res://scripts/builder/transform_tool.gd")
    scene.ext_res("6_plan", "PackedScene", "res://scenes/plan_view.tscn")
    scene.ext_res("7_op", "Script", "res://scripts/builder/operator_panel.gd")
    scene.ext_res("8_box", "Script", "res://scripts/builder/box_select_overlay.gd")
    scene.sub("ButtonGroup_create", "ButtonGroup")
    scene.sub("ButtonGroup_types", "ButtonGroup")
    scene.sub("ButtonGroup_shapes", "ButtonGroup")
    envid = scene.sub("Env_builder", "Environment", background_mode=1, background_color="Color(0.04, 0.05, 0.08, 1)",
                      ambient_light_source=2, ambient_light_color="Color(0.75, 0.8, 0.95, 1)", ambient_light_energy=0.7)
    env_node.props["environment"] = envid
    sh = scene.sub("Shader_grid", "Shader", code=shader_code)
    gm = scene.sub("Mat_grid", "ShaderMaterial", shader=sh)
    pm = scene.sub("Plane_grid", "PlaneMesh", size="Vector2(60, 60)")
    ground.props.update({"mesh": pm, "material_override": gm, "cast_shadow": 0})
    ship_mat = scene.sub("Mat_ship", "StandardMaterial3D", vertex_color_use_as_albedo="true", metallic=0.2, roughness=0.6, cull_mode=2)
    ship_mesh.props["material_override"] = ship_mat
    # (the overlay / dot materials are shaders made by builder_view.gd, they depend on the shading mode)
    dot_mesh = scene.sub("Mesh_dot", "SphereMesh", radius=0.5, height=1.0, radial_segments=10, rings=5)
    dots_mm = scene.sub("MM_dots", "MultiMesh", transform_format=1, use_colors="true", mesh=dot_mesh)
    vertex_dots.props.update({"multimesh": dots_mm, "cast_shadow": 0})
    ov_mesh = scene.sub("IM_overlay", "ImmediateMesh")
    overlay.props.update({"mesh": ov_mesh, "cast_shadow": 0})

    # ---------------- signals -> BuilderUI functions
    def C(sig, frm, method, binds=None):
        scene.connect(sig, frm, method, binds, to=builder_ui)
    C("text_changed", ship_name_edit, "_on_ship_name_changed")
    for b, m in [(new_b, "new"), (save_b, "save"), (load_b, "load"), (undo_b, "undo"), (redo_b, "redo"), (back_b, "back")]:
        C("pressed", b, "_on_%s_pressed" % m)
    C("value_changed", snap_spin, "_on_snap_changed")
    C("pressed", premade_b, "_on_save_premade_pressed")
    C("pressed", plan_b, "_on_plan_pressed")
    C("toggled", auto_link, "_on_auto_link_toggled")
    C("toggled", pilot_check, "_on_pilot_toggled")
    def find_named(node, name):
        if node.name == name: return node
        for k in node.kids:
            r = find_named(k, name)
            if r: return r
    C("pressed", ship_btn, "_on_create_mode_pressed", '"ship"')
    C("pressed", mod_btn, "_on_create_mode_pressed", '"module"')
    C("pressed", find_named(ship_section, "NewStarterShipButton"), "_on_new_ship_template_pressed", '"starter"')
    C("pressed", find_named(ship_section, "NewBlankShipButton"), "_on_new_ship_template_pressed", '"blank"')
    for t, b in zip(TYPES, type_buttons): C("pressed", b, "_on_type_button_pressed", '"%s"' % t)
    for n, b in zip(SHAPES, shape_buttons): C("pressed", b, "_on_shape_button_pressed", '"%s"' % n)
    C("pressed", find_named(add_tab, "AddModuleButton"), "_on_add_module_pressed")
    for n in ("CenterXSpin", "CenterYSpin", "CenterZSpin"): C("value_changed", find_named(sel_tab, n), "_on_center_changed")
    for n in ("SizeXSpin", "SizeYSpin", "SizeZSpin"): C("value_changed", find_named(sel_tab, n), "_on_size_changed")
    C("item_selected", find_named(sel_tab, "ActiveTypePicker"), "_on_active_type_selected")
    for n in ("ThrustDirXSpin", "ThrustDirYSpin", "ThrustDirZSpin"): C("value_changed", find_named(sel_tab, n), "_on_thrust_dir_changed")
    C("item_selected", find_named(sel_tab, "MaterialPicker"), "_on_material_selected")
    C("item_selected", find_named(sel_tab, "PresetPicker"), "_on_preset_selected")
    C("item_selected", find_named(add_tab, "NewPresetPicker"), "_on_new_preset_selected")
    C("pressed", find_named(sel_tab, "SavePresetButton"), "_on_save_preset_pressed")
    for b, v in dir_buttons: C("pressed", b, "_on_thrust_dir_preset_pressed", v)
    for b, v in turret_axis_buttons: C("pressed", b, "_on_thrust_dir_preset_pressed", v)
    for n in ("TurretAxisXSpin", "TurretAxisYSpin", "TurretAxisZSpin"): C("value_changed", find_named(sel_tab, n), "_on_turret_axis_changed")
    for n, k in (("TurretYawMinSpin", "yaw_min"), ("TurretYawMaxSpin", "yaw_max"), ("TurretPitchMinSpin", "pitch_min"), ("TurretPitchMaxSpin", "pitch_max")):
        C("value_changed", find_named(sel_tab, n), "_on_turret_value_changed", '"%s"' % k)
    C("value_changed", reactor, "_on_reactor_changed")
    C("value_changed", gyro, "_on_gyro_changed")
    return scene

scene = build()
open(os.path.join(os.path.dirname(__file__), "..", "scenes", "ship_builder.tscn"), "w").write(scene.dump())
print("ship_builder.tscn written")
