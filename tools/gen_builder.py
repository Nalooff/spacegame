"""Generates scenes/ship_builder.tscn  (run:  python3 tools/gen_builder.py).

Node tree overview (names are descriptive on purpose):
  ShipBuilder (Node3D, ship_builder.gd)
    WorldEnvironment, SunLight, FillLight, GroundGrid
    CameraRig (builder_camera.gd) / Camera
    View (builder_view.gd) / ShipMesh, VertexDots, OverlayMesh
    TransformTool (transform_tool.gd)
    UI (CanvasLayer) / BuilderUI (builder_ui.gd) / TopBar, ToolPanel, SidePanel, StatusBar
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
    new_b = button("New", "NewButton", tooltip_text=s("Start a fresh ship"))
    save_b = tool_button("Save", "SaveButton", "Save to user://ships/ (Ctrl+S). Needs exactly one Commander and a thruster.")
    load_b = button("Load", "LoadButton", tooltip_text=s("Load the ship picked in the list"))
    undo_b = tool_button("Undo", "UndoButton", "Ctrl+Z")
    redo_b = tool_button("Redo", "RedoButton", "Ctrl+Y (or Ctrl+Shift+Z)")
    back_b = button("Back to menu", "BackToMenuButton")
    premade_b = button("Save as PREMADE", "SavePremadeButton", unique=True, visible="false", tooltip_text=s("Only when run from the Godot editor: writes into res://ships/"))
    spacer = N("TopBarSpacer", "Control", {"layout_mode": 2, "size_flags_horizontal": 3})
    top_bar = panel("TopBar", {"anchors_preset": 10, "anchor_right": 1.0, "offset_left": 8.0, "offset_top": 8.0, "offset_right": -8.0,
                               "offset_bottom": 56.0, "grow_horizontal": 2},
                    [hbox("TopBarRow", [label("Ship name", "ShipNameTitle"), ship_name_edit, new_b, save_b,
                                        label("|", "TopBarDivider1"), load_picker, load_b, spacer,
                                        undo_b, redo_b, premade_b, back_b])])
    ship_name_edit.props["custom_minimum_size"] = "Vector2(220, 0)"
    ship_name_edit.props["size_flags_horizontal"] = 1
    load_picker.props["custom_minimum_size"] = "Vector2(200, 0)"
    load_picker.props["size_flags_horizontal"] = 1

    # ============================================================ UI: tool panel (left)
    group = 'SubResource("ButtonGroup_modes")'
    def mode_button(text, name, tip):
        return button(text, name, unique=True, toggle_mode="true", button_group=group, tooltip_text=s(tip))
    mode_obj = mode_button("Object  (1)", "ModeObjectButton", "Select whole modules")
    mode_vert = mode_button("Vertex  (2)", "ModeVertexButton", "Select single points")
    mode_edge = mode_button("Edge  (3)", "ModeEdgeButton", "Select lines between two points")
    mode_face = mode_button("Face  (4)", "ModeFaceButton", "Select flat sides")
    grab_b = tool_button("Move  (G)", "GrabButton", "Move the selection. X/Y/Z locks an axis, click or Enter confirms, Esc cancels.")
    rot_b = tool_button("Rotate  (R)", "RotateButton", "Rotate the selection around its centre")
    scale_b = tool_button("Scale  (S)", "ScaleButton", "Scale the selection around its centre")
    extrude_b = tool_button("Extrude face  (E)", "ExtrudeButton", "Face mode: push the face out into a new block (new vertices)")
    addv_b = tool_button("Add vertex on edge  (W)", "AddVertexButton", "Edge mode: split the edge in the middle with a new vertex")
    conn_b = tool_button("Connect vertices  (J)", "ConnectVerticesButton", "Vertex mode: draw a new edge between 2 vertices of the same face")
    face_b = tool_button("Create face  (C)", "CreateFaceButton", "Vertex mode: click 3+ vertices in order, then make a face. It is red (loose) until it is part of a module.")
    makemod_b = tool_button("Make module  (N)", "MakeModuleButton", "Face mode: the selected faces become a new module of the type chosen in the Add tab. Must be a closed container.")
    bevel_b = tool_button("Bevel / round  (B)", "BevelButton", "Edge mode: replace the selected edges by a flat strip. Use Segments 2-3 to round them off.")
    bevel_w = spin("BevelWidthSpin", 0.01, 2, 0.01, 0.1, tooltip_text=s("Width of the bevel in metres"))
    bevel_s = spin("BevelSegmentsSpin", 1, 3, 1, 1, tooltip_text=s("1 = flat chamfer, 2-3 = rounded"))
    turret_link_b = tool_button("Link turret + barrel  (T)", "LinkTurretButton", "Object mode: select one turret base and one barrel, then link them")
    link_b = tool_button("Link vertices  (L)", "LinkButton", "Merge the selected vertices so they move together (green dots)")
    unlink_b = tool_button("Unlink vertex  (U)", "UnlinkButton", "Detach the vertex from the other modules")
    mirror_b = tool_button("Mirror  (M)", "MirrorButton", "Object mode: copy the module to the other side (X axis)")
    dup_b = tool_button("Duplicate  (Shift+D)", "DuplicateButton", "Copy the selected module(s)")
    del_b = tool_button("Delete  (X)", "DeleteButton", "Delete the selection")
    frame_b = tool_button("Frame view  (F)", "FrameButton", "Centre the camera on the selection")
    snap_spin = spin("SnapSpin", 0, 1, 0.05, 0.1, tooltip_text=s("Moves jump by this many metres. 0 = free."))
    auto_link = N("AutoLinkCheck", "CheckBox", {"layout_mode": 2, "text": s("Auto-link on drop"), "button_pressed": "true",
                  "tooltip_text": s("Dropping a vertex on another module's vertex links them")}, unique=True)
    tool_panel = panel("ToolPanel", {"anchors_preset": 9, "anchor_bottom": 1.0, "offset_left": 8.0, "offset_top": 64.0,
                                    "offset_right": 218.0, "offset_bottom": -48.0, "grow_vertical": 2},
        [N("ToolScroll", "ScrollContainer", {"layout_mode": 2, "horizontal_scroll_mode": 0}, [
            vbox("ToolList", [
                heading("SELECT", "SelectHeading"), mode_obj, mode_vert, mode_edge, mode_face, sep("SelectDivider"),
                heading("TRANSFORM", "TransformHeading"), grab_b, rot_b, scale_b, sep("TransformDivider"),
                heading("SHAPE", "ShapeHeading"), extrude_b, addv_b, conn_b, link_b, unlink_b, bevel_b, row("Width (m)", "BevelWidth", bevel_w), row("Segments", "BevelSegments", bevel_s),
                sep("ShapeDivider"), heading("FACES & MODULES", "FacesHeading"), face_b, makemod_b, turret_link_b, sep("FacesDivider"),
                heading("OBJECT", "ObjectHeading"), mirror_b, dup_b, del_b, sep("ObjectDivider"),
                heading("VIEW", "ViewHeading"), frame_b, row("Snap (m)", "Snap", snap_spin), auto_link], size_flags_horizontal=3)])])

    # ============================================================ UI: side panel (right) with tabs
    # --- Add tab
    add_tab = vbox("Add", [
        heading("NEW MODULE", "NewModuleHeading"),
        label("Type", "NewTypeLabel"), opt("NewTypePicker"),
        label("", "NewTypeHelp", unique=True, wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
        label("Shape", "NewShapeLabel"), opt("NewShapePicker"),
        row("Round shape detail", "NewSegments", spin("NewSegmentsSpin", 6, 32, 2, 12, tooltip_text=s("Number of sides of cylinders, cones, spheres and domes"))),
        label("Half size (metres, from the centre)", "NewSizeLabel"),
        hbox("NewSizeRow", [spin("NewSizeXSpin", 0.05, 10, 0.05, 0.5), spin("NewSizeYSpin", 0.05, 10, 0.05, 0.5), spin("NewSizeZSpin", 0.05, 10, 0.05, 0.5)]),
        tool_button("Add at view centre", "AddModuleButton", "The new module appears where the camera looks. Then press G to move it."),
        label("Tip: modules start unattached. Move them next to each other, then link\nvertices (L) so they stay together.", "AddTip", wrap=True, modulate="Color(1, 1, 1, 0.6)"),
    ])
    for n in add_tab.kids:
        if n.type == "OptionButton": pass
    # --- Selection tab
    dir_names = [("-Z fwd", "Vector3(0, 0, -1)"), ("+Z", "Vector3(0, 0, 1)"), ("+X", "Vector3(1, 0, 0)"),
                 ("-X", "Vector3(-1, 0, 0)"), ("+Y", "Vector3(0, 1, 0)"), ("-Y", "Vector3(0, -1, 0)")]
    dir_buttons = [(button(t, "ThrustDirPreset%d" % i, tooltip_text=s("Thruster pushes the ship toward " + t)), v) for i, (t, v) in enumerate(dir_names)]
    turret_axis_buttons = [(button(t, "TurretAxisPreset%d" % i, tooltip_text=s("Turret swivel 'up' axis: " + t)), v) for i, (t, v) in enumerate(dir_names)]
    sel_tab = vbox("Selection", [
        label("", "SelectionInfoLabel", unique=True, wrap=True),
        vbox("CenterSection", [
            heading("CENTRE OF SELECTION (m)", "CenterHeading"),
            hbox("CenterRow", [spin("CenterXSpin", -100, 100, 0.05, 0), spin("CenterYSpin", -100, 100, 0.05, 0), spin("CenterZSpin", -100, 100, 0.05, 0)]),
            label("Type exact numbers here instead of dragging.", "CenterTip", modulate="Color(1, 1, 1, 0.6)")], unique=True),
        sep("SelectionDivider"),
        vbox("ActiveModuleSection", [
            heading("ACTIVE MODULE", "ActiveModuleHeading"),
            label("", "ActiveModuleLabel", unique=True),
            opt("ActiveTypePicker"),
            label("", "ActiveTypeHelp", unique=True, wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
            label("Material (decides damage resistance and dents)", "MaterialLabel", wrap=True), opt("MaterialPicker"),
            label("", "MaterialHelp", unique=True, wrap=True, modulate="Color(0.8, 0.85, 0.95, 0.85)"),
            vbox("CrewSection", [
                heading("CREW", "CrewHeading"),
                label("Seats on the ship, pilot included. Friends can join a locked ship in the lobby as crew and man the turrets.", "CrewHelp", wrap=True),
                row("Seats", "CrewSeats", spin("CrewSeatsSpin", 1, 8, 1, 1))], unique=True),
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
                row("Turn speed (deg/s)", "TurretSpeed", spin("TurretSpeedSpin", 10, 360, 5, 90)),
                label("", "TurretLinkLabel", unique=True, wrap=True)], unique=True),
            vbox("ThrusterSection", [
                heading("THRUSTER", "ThrusterHeading"),
                label("Direction the thruster PUSHES the ship.\n(The flame goes the opposite way.)", "ThrusterDirHelp", wrap=True),
                hbox("ThrustDirRow", [spin("ThrustDirXSpin", -1, 1, 0.05, 0), spin("ThrustDirYSpin", -1, 1, 0.05, 0), spin("ThrustDirZSpin", -1, 1, 0.05, -1)]),
                hbox("ThrustDirPresetRow1", [b for b, _ in dir_buttons[:3]]),
                hbox("ThrustDirPresetRow2", [b for b, _ in dir_buttons[3:]]),
                row("Power (N)", "ThrustPower", spin("ThrustPowerSpin", 200, 8000, 50, 2000))], unique=True)], unique=True),
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
        label("Electricity powers thrusters and turrets. The gyroscope turns the ship.\nRCS is automatic: always 5% of the ship's best-direction thrust.", "InternalTip", wrap=True, modulate="Color(1, 1, 1, 0.6)"),
    ])
    for t in (add_tab, sel_tab, ship_tab):
        t.props["size_flags_horizontal"] = 3
    tabs = N("SideTabs", "TabContainer", {"layout_mode": 2, "size_flags_vertical": 3, "current_tab": 0}, [
        N("AddScroll", "ScrollContainer", {"layout_mode": 2, "horizontal_scroll_mode": 0}, [add_tab]),
        N("SelectionScroll", "ScrollContainer", {"layout_mode": 2, "horizontal_scroll_mode": 0}, [sel_tab]),
        N("ShipScroll", "ScrollContainer", {"layout_mode": 2, "horizontal_scroll_mode": 0}, [ship_tab])])
    # tab titles come from node names -> rename the scrolls to the titles we want
    tabs.kids[0].name, tabs.kids[1].name, tabs.kids[2].name = "Add", "Selection", "Ship"
    add_tab.name, sel_tab.name, ship_tab.name = "AddList", "SelectionList", "ShipList"
    side_panel = panel("SidePanel", {"anchors_preset": 11, "anchor_left": 1.0, "anchor_right": 1.0, "anchor_bottom": 1.0,
                                     "offset_left": -358.0, "offset_top": 64.0, "offset_right": -8.0, "offset_bottom": -48.0,
                                     "grow_horizontal": 0, "grow_vertical": 2}, [tabs])

    # ============================================================ UI: status bar (bottom)
    status_bar = panel("StatusBar", {"anchors_preset": 12, "anchor_top": 1.0, "anchor_right": 1.0, "anchor_bottom": 1.0,
                                     "offset_left": 8.0, "offset_top": -40.0, "offset_right": -8.0, "offset_bottom": -8.0,
                                     "grow_horizontal": 2, "grow_vertical": 0},
        [hbox("StatusRow", [label("Click an element to select it. Right mouse = orbit, wheel = zoom.", "StatusLabel", unique=True, size_flags_horizontal=3),
                            label("Forward is -Z  |  Shift+click = multi-select  |  A = all, Alt+A = none  |  Ctrl+Z / Ctrl+Y = undo / redo", "KeyHelpLabel", modulate="Color(1, 1, 1, 0.6)")])])
    builder_ui = N("BuilderUI", "Control", {**full_rect(), "mouse_filter": 2, "theme": 'SubResource("Theme_builder")'},
                   [top_bar, tool_panel, side_panel, status_bar], script='ExtResource("2_ui")')
    ui = N("UI", "CanvasLayer", {}, [builder_ui])
    root = N("ShipBuilder", "Node3D", {}, [env_node, sun, fill, ground, camera_rig, view, transform_tool, ui], script='ExtResource("1_builder")')

    scene = Scene(root)
    scene.ext_res("1_builder", "Script", "res://scripts/builder/ship_builder.gd")
    scene.ext_res("2_ui", "Script", "res://scripts/builder/builder_ui.gd")
    scene.ext_res("3_cam", "Script", "res://scripts/builder/builder_camera.gd")
    scene.ext_res("4_view", "Script", "res://scripts/builder/builder_view.gd")
    scene.ext_res("5_tool", "Script", "res://scripts/builder/transform_tool.gd")
    scene.sub("ButtonGroup_modes", "ButtonGroup")
    scene.sub("Theme_builder", "Theme", default_font_size=15)
    envid = scene.sub("Env_builder", "Environment", background_mode=1, background_color="Color(0.04, 0.05, 0.08, 1)",
                      ambient_light_source=2, ambient_light_color="Color(0.75, 0.8, 0.95, 1)", ambient_light_energy=0.7)
    env_node.props["environment"] = envid
    sh = scene.sub("Shader_grid", "Shader", code=shader_code)
    gm = scene.sub("Mat_grid", "ShaderMaterial", shader=sh)
    pm = scene.sub("Plane_grid", "PlaneMesh", size="Vector2(60, 60)")
    ground.props.update({"mesh": pm, "material_override": gm, "cast_shadow": 0})
    ship_mat = scene.sub("Mat_ship", "StandardMaterial3D", vertex_color_use_as_albedo="true", metallic=0.2, roughness=0.6, cull_mode=2)
    ship_mesh.props["material_override"] = ship_mat
    dot_mat = scene.sub("Mat_dots", "StandardMaterial3D", shading_mode=0, vertex_color_use_as_albedo="true", no_depth_test="true", render_priority=5)
    dot_mesh = scene.sub("Mesh_dot", "SphereMesh", material=dot_mat, radius=0.5, height=1.0, radial_segments=10, rings=5)
    dots_mm = scene.sub("MM_dots", "MultiMesh", transform_format=1, use_colors="true", mesh=dot_mesh)
    vertex_dots.props.update({"multimesh": dots_mm, "cast_shadow": 0})
    ov_mat = scene.sub("Mat_overlay", "StandardMaterial3D", shading_mode=0, vertex_color_use_as_albedo="true", no_depth_test="true",
                       transparency=1, cull_mode=2, render_priority=4)
    ov_mesh = scene.sub("IM_overlay", "ImmediateMesh")
    overlay.props.update({"mesh": ov_mesh, "material_override": ov_mat, "cast_shadow": 0})

    # ---------------- signals -> BuilderUI functions
    def C(sig, frm, method, binds=None):
        scene.connect(sig, frm, method, binds, to=builder_ui)
    C("text_changed", ship_name_edit, "_on_ship_name_changed")
    for b, m in [(new_b, "new"), (save_b, "save"), (load_b, "load"), (undo_b, "undo"), (redo_b, "redo"), (back_b, "back"),
                 (mode_obj, "mode_object"), (mode_vert, "mode_vertex"), (mode_edge, "mode_edge"), (mode_face, "mode_face"),
                 (grab_b, "grab"), (rot_b, "rotate"), (scale_b, "scale"), (extrude_b, "extrude"), (addv_b, "add_vertex"),
                 (conn_b, "connect"), (face_b, "create_face"), (makemod_b, "make_module"), (bevel_b, "bevel"), (turret_link_b, "link_turret"), (link_b, "link"), (unlink_b, "unlink"), (mirror_b, "mirror"), (dup_b, "duplicate"),
                 (del_b, "delete"), (frame_b, "frame")]:
        C("pressed", b, "_on_%s_pressed" % m)
    C("value_changed", snap_spin, "_on_snap_changed")
    C("pressed", premade_b, "_on_save_premade_pressed")
    C("value_changed", bevel_w, "_on_bevel_width_changed")
    C("value_changed", bevel_s, "_on_bevel_segments_changed")
    C("toggled", auto_link, "_on_auto_link_toggled")
    def find_named(node, name):
        if node.name == name: return node
        for k in node.kids:
            r = find_named(k, name)
            if r: return r
    C("item_selected", find_named(add_tab, "NewTypePicker"), "_on_new_type_selected")
    C("item_selected", find_named(add_tab, "NewShapePicker"), "_on_new_shape_selected")
    C("pressed", find_named(add_tab, "AddModuleButton"), "_on_add_module_pressed")
    for n in ("CenterXSpin", "CenterYSpin", "CenterZSpin"): C("value_changed", find_named(sel_tab, n), "_on_center_changed")
    C("item_selected", find_named(sel_tab, "ActiveTypePicker"), "_on_active_type_selected")
    for n in ("ThrustDirXSpin", "ThrustDirYSpin", "ThrustDirZSpin"): C("value_changed", find_named(sel_tab, n), "_on_thrust_dir_changed")
    C("item_selected", find_named(sel_tab, "MaterialPicker"), "_on_material_selected")
    C("value_changed", find_named(sel_tab, "CrewSeatsSpin"), "_on_crew_seats_changed")
    for b, v in dir_buttons: C("pressed", b, "_on_thrust_dir_preset_pressed", v)
    C("value_changed", find_named(sel_tab, "ThrustPowerSpin"), "_on_thrust_power_changed")
    for b, v in turret_axis_buttons: C("pressed", b, "_on_thrust_dir_preset_pressed", v)
    for n in ("TurretAxisXSpin", "TurretAxisYSpin", "TurretAxisZSpin"): C("value_changed", find_named(sel_tab, n), "_on_turret_axis_changed")
    for n, k in (("TurretYawMinSpin", "yaw_min"), ("TurretYawMaxSpin", "yaw_max"), ("TurretPitchMinSpin", "pitch_min"), ("TurretPitchMaxSpin", "pitch_max"), ("TurretSpeedSpin", "turn_speed")):
        C("value_changed", find_named(sel_tab, n), "_on_turret_value_changed", '"%s"' % k)
    C("value_changed", reactor, "_on_reactor_changed")
    C("value_changed", gyro, "_on_gyro_changed")
    return scene

scene = build()
open(os.path.join(os.path.dirname(__file__), "..", "scenes", "ship_builder.tscn"), "w").write(scene.dump())
print("ship_builder.tscn written")
