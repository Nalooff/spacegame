import sys, os, math, random
sys.path.insert(0, os.path.dirname(__file__))
from tscn import *
OUT = os.path.join(os.path.dirname(__file__), "..", "scenes")
def write(name, scene): open(os.path.join(OUT, name), "w").write(scene.dump()); print("wrote", name)

# =============================================================== main menu
def main_menu():
    title = N("TitleLabel", "Label", {"layout_mode": 2, "text": s("VERTEX SHIPS"), "horizontal_alignment": 1, "theme_override_font_sizes/font_size": 64})
    sub = N("SubtitleLabel", "Label", {"layout_mode": 2, "text": s("modular vertex-built spaceships"), "horizontal_alignment": 1, "modulate": "Color(1, 1, 1, 0.6)"})
    creation = button("Creation  (ship builder)", "CreationButton", custom_minimum_size="Vector2(320, 56)")
    play = button("Play  (lobbies)", "PlayButton", custom_minimum_size="Vector2(320, 56)")
    presets = button("Module presets  (weapons, thrusters, armor)", "PresetsButton", custom_minimum_size="Vector2(320, 44)")
    quit_ = button("Quit", "QuitButton", unique=True, custom_minimum_size="Vector2(320, 40)")
    notice = N("NoticeLabel", "Label", {"layout_mode": 2, "horizontal_alignment": 1, "modulate": "Color(1, 0.7, 0.4, 1)"}, unique=True)
    menu_column = N("MenuButtonsColumn", "VBoxContainer", {"layout_mode": 2, "theme_override_constants/separation": 14}, [title, sub, N("TitleToButtonsSpacer", "Control", {"layout_mode": 2, "custom_minimum_size": "Vector2(0, 30)"}), creation, play, presets, quit_, notice])
    center = N("MenuCenter", "CenterContainer", {**full_rect()}, [menu_column])
    bg = N("BackgroundColor", "ColorRect", {**full_rect(), "color": "Color(0.03, 0.04, 0.07, 1)"})
    root = N("MainMenu", "Control", {**full_rect()}, [bg, center], script='ExtResource("1_s")')
    sc = Scene(root); sc.ext_res("1_s", "Script", "res://scripts/ui/main_menu.gd")
    sc.connect("pressed", creation, "_on_creation_pressed"); sc.connect("pressed", play, "_on_play_pressed"); sc.connect("pressed", presets, "_on_presets_pressed"); sc.connect("pressed", quit_, "_on_quit_pressed")
    write("main_menu.tscn", sc)

# =============================================================== preset creator
def preset_creator():
    type_pick = N("TypePicker", "OptionButton", {"layout_mode": 2}, unique=True)
    plist = N("PresetList", "ItemList", {"layout_mode": 2, "size_flags_vertical": 3, "custom_minimum_size": "Vector2(240, 200)"}, unique=True)
    new_b = button("New preset from this one", "NewPresetButton", unique=True)
    del_b = button("Delete (your own only)", "DeletePresetButton", unique=True)
    left = vbox("PresetListColumn", [label("MODULE TYPE", "TypeTitle"), type_pick, label("PRESETS", "ListTitle"), plist, new_b, del_b], custom_minimum_size="Vector2(260, 0)")
    name = line("PresetNameEdit", "", placeholder_text=s("Preset name (e.g. Heavy plasma cannon)"))
    kind = N("KindPicker", "OptionButton", {"layout_mode": 2, "size_flags_horizontal": 3}, unique=True)
    dmg = N("DamageTypePicker", "OptionButton", {"layout_mode": 2, "size_flags_horizontal": 3}, unique=True)
    stats = vbox("StatRows", [], unique=True)
    summary = label("", "SummaryLabel", unique=True, wrap=True, modulate="Color(0.6, 0.9, 1, 1)")
    help_ = N("HelpEdit", "TextEdit", {"layout_mode": 2, "custom_minimum_size": "Vector2(0, 70)", "placeholder_text": s("What is this preset good at?"), "wrap_mode": 1}, unique=True)
    save = button("Save preset", "SavePresetButton", unique=True)
    back = button("Back to menu", "BackButton", unique=True)
    msg = label("", "MessageLabel", unique=True, wrap=True, modulate="Color(1, 0.8, 0.4, 1)")
    right = vbox("PresetEditColumn", [label("PRESET", "EditTitle"), hbox("NameRow", [label("Name", "NameLabel"), name]),
        hbox("KindRow", [label("Kind", "KindLabel"), kind]),
        hbox("DamageRow", [label("Damage type", "DamageLabel"), dmg]), sep("StatSep"), stats, summary, help_, hbox("ButtonRow", [save, back]), msg],
        size_flags_horizontal=3)
    inner = hbox("CreatorRow", [left, N("RightMargin", "MarginContainer", {"layout_mode": 2, "size_flags_horizontal": 3, "theme_override_constants/margin_left": 12}, [right])])
    panel = N("CreatorPanel", "PanelContainer", {**full_rect(), "offset_left": 60.0, "offset_top": 40.0, "offset_right": -60.0, "offset_bottom": -40.0}, [inner])
    bg = N("Backdrop", "ColorRect", {**full_rect(), "color": "Color(0.03, 0.04, 0.07, 1)"})
    root = N("PresetCreator", "Control", {**full_rect()}, [bg, panel], script='ExtResource("1_s")')
    sc = Scene(root); sc.ext_res("1_s", "Script", "res://scripts/ui/preset_creator.gd")
    sc.connect("item_selected", plist, "_on_preset_selected")
    sc.connect("item_selected", type_pick, "_on_type_selected"); sc.connect("item_selected", kind, "_on_kind_selected")
    sc.connect("pressed", new_b, "_on_new_pressed"); sc.connect("pressed", del_b, "_on_delete_pressed")
    sc.connect("pressed", save, "_on_save_pressed"); sc.connect("pressed", back, "_on_back_pressed")
    write("preset_creator.tscn", sc)

# =============================================================== HUD
def hud():
    def bar(name):
        return N(name, "ProgressBar", {"layout_mode": 2, "show_percentage": "false", "value": 100.0, "custom_minimum_size": "Vector2(0, 14)"}, unique=True)
    flight = label("", "FlightLabel", unique=True)
    left_panel = N("FlightStatusPanel", "PanelContainer", {"layout_mode": 1, "offset_left": 10.0, "offset_top": 10.0, "offset_right": 360.0, "offset_bottom": 270.0},
        [vbox("StatusColumn", [flight, label("Commander module", "CommanderLabel"), bar("CommanderBar"),
                      label("", "PowerLabel", unique=True), bar("PowerBar"), label("", "RcsLabel", unique=True, wrap=True)])])
    banner = N("BannerLabel", "Label", {"layout_mode": 1, "anchors_preset": 5, "anchor_left": 0.5, "anchor_right": 0.5, "offset_left": -300.0, "offset_top": 30.0, "offset_right": 300.0,
                "offset_bottom": 80.0, "grow_horizontal": 2, "horizontal_alignment": 1, "theme_override_font_sizes/font_size": 30, "modulate": "Color(1, 0.8, 0.3, 1)"}, unique=True)
    leave = button("Leave game", "LeaveButton")
    right_top = N("PlayersPanel", "PanelContainer", {"layout_mode": 1, "anchors_preset": 1, "anchor_left": 1.0, "anchor_right": 1.0, "offset_left": -220.0, "offset_top": 10.0,
                  "offset_right": -10.0, "offset_bottom": 160.0, "grow_horizontal": 0}, [vbox("PlayersColumn", [label("", "PlayersLabel", unique=True), leave])])
    map_btn = button("Tactical map  (M)", "OpenMapButton")
    brake, cancel = button("Brake (X)", "BrakeButton"), button("Cancel order", "CancelButton")
    fire_state = label("", "FireStateLabel", unique=True)
    ap = N("AutopilotPanel", "PanelContainer", {"layout_mode": 1, "anchors_preset": 3, "anchor_left": 1.0, "anchor_top": 1.0, "anchor_right": 1.0, "anchor_bottom": 1.0,
              "offset_left": -300.0, "offset_top": -150.0, "offset_right": -10.0, "offset_bottom": -10.0, "grow_horizontal": 0, "grow_vertical": 0},
        [vbox("AutopilotColumn", [label("FLIGHT ORDERS", "AutopilotTitleLabel"), map_btn, hbox("AutopilotButtonsRow", [brake, cancel]), fire_state])])
    help_ = N("ControlsHelpLabel", "Label", {"layout_mode": 1, "anchors_preset": 2, "anchor_top": 1.0, "anchor_bottom": 1.0, "offset_left": 10.0, "offset_top": -150.0, "offset_right": 600.0,
               "offset_bottom": -10.0, "grow_vertical": 0, "vertical_alignment": 2, "modulate": "Color(1, 1, 1, 0.6)",
               "text": s("W/S forward/back  A/D strafe  Space/C up/down  Arrows pitch/yaw  Q/E roll\nLMB fire at cursor (commander mode: hold LMB to fire at the lock)   R lock next enemy (guns lead it)   RMB drag orbit camera   Wheel zoom\nV commander/crew mode   F next station   P ship plan   X brake   T flight-assist   M tactical map (click = waypoint)   H weapons free   Any manual key cancels the autopilot")})
    banner_timer = N("BannerTimer", "Timer", {"wait_time": 3.0, "one_shot": "true"}, unique=True)
    markers = N("ContactMarkers", "Control", {**full_rect(), "mouse_filter": 2}, [], script='ExtResource("2_markers")')
    plan_view = N("PlanView", None, {}, unique=True, instance='ExtResource("3_plan")')
    tac_map = N("TacticalMap", None, {}, unique=True, instance='ExtResource("4_map")')
    root = N("HudRoot", "Control", {**full_rect(), "mouse_filter": 2}, [markers, left_panel, banner, right_top, ap, help_, banner_timer, plan_view, tac_map])
    top = N("HUD", "CanvasLayer", {}, [root], script='ExtResource("1_s")')
    sc = Scene(top); sc.ext_res("1_s", "Script", "res://scripts/ui/hud.gd"); sc.ext_res("2_markers", "Script", "res://scripts/ui/contact_markers.gd"); sc.ext_res("3_plan", "PackedScene", "res://scenes/plan_view.tscn"); sc.ext_res("4_map", "PackedScene", "res://scenes/tactical_map.tscn")
    C = sc.connect
    C("pressed", map_btn, "_on_open_map_pressed"); C("pressed", brake, "_on_brake_pressed"); C("pressed", cancel, "_on_cancel_pressed")
    C("pressed", leave, "_on_leave_pressed"); C("timeout", banner_timer, "_on_banner_timer_timeout")
    write("hud.tscn", sc)

# =============================================================== tactical map (Nebulous-style orders)
def tactical_map():
    canvas = N("MapCanvas", "Control", {"layout_mode": 2, "size_flags_horizontal": 3, "size_flags_vertical": 3, "clip_contents": "true", "focus_mode": 2}, unique=True)
    go_b = button("GO TO  (stop there)", "GoToButton", unique=True, toggle_mode="true", button_pressed="true")
    drive_b = button("DRIVE  (never stops)", "DriveButton", unique=True, toggle_mode="true")
    thrust = N("ThrustSlider", "HSlider", {"layout_mode": 2, "size_flags_horizontal": 3, "min_value": 0.0, "max_value": 100.0, "step": 1.0, "value": 100.0}, unique=True)
    thrust_val = label("100%", "ThrustValueLabel", unique=True, custom_minimum_size="Vector2(48, 0)")
    alt = spin("AltitudeSpin", -100000, 100000, 1, 0, allow_greater="true", allow_lesser="true", suffix=s(" m"))
    face = N("FaceTurretsCheck", "CheckBox", {"layout_mode": 2, "text": s("Keep turrets facing the enemy"), "tooltip_text": s("The ship turns so the most turrets can bear on the locked enemy (or the destination) while it moves.")}, unique=True)
    free = N("WeaponsFreeCheck", "CheckBox", {"layout_mode": 2, "text": s("Weapons free  (H)"), "tooltip_text": s("Off: radar locks and aims, the guns wait for you to hold the left mouse button.")}, unique=True)
    chase = button("Drive at locked target", "ChaseButton", unique=True)
    brake = button("Brake  (X)", "MapBrakeButton", unique=True)
    cancel = button("Cancel order", "MapCancelButton", unique=True)
    close = button("Close  (M)", "CloseMapButton", unique=True)
    info = label("", "OrderInfoLabel", unique=True, wrap=True)
    help_ = label("Click: set a waypoint (and go).  Click an enemy: lock it, and in DRIVE mode ram it.\nRight-drag: pan.  Wheel: zoom.  Right ruler: click to set the height.", "MapHelpLabel", wrap=True, modulate="Color(1, 1, 1, 0.6)")
    col = vbox("OrdersColumn", [label("ORDERS", "OrdersTitleLabel"), go_b, drive_b,
        hbox("ThrustRow", [label("Thrust", "ThrustLabel"), thrust, thrust_val]),
        hbox("AltitudeRow", [label("Height", "AltitudeLabel"), alt]),
        face, free, chase, hbox("StopRow", [brake, cancel]), info, help_, close], custom_minimum_size="Vector2(300, 0)")
    inner = hbox("MapRow", [canvas, N("OrdersMargin", "MarginContainer", {"layout_mode": 2, "theme_override_constants/margin_left": 8, "theme_override_constants/margin_right": 8}, [col])])
    panel = N("MapPanel", "PanelContainer", {**full_rect(), "offset_left": 40.0, "offset_top": 40.0, "offset_right": -40.0, "offset_bottom": -40.0}, [inner])
    root = N("TacticalMap", "Control", {**full_rect(), "mouse_filter": 1}, [N("MapBackdrop", "ColorRect", {**full_rect(), "color": "Color(0.01, 0.015, 0.03, 0.97)", "mouse_filter": 0}), panel], script='ExtResource("1_s")')
    sc = Scene(root); sc.ext_res("1_s", "Script", "res://scripts/ui/tactical_map.gd")
    write("tactical_map.tscn", sc)

# =============================================================== game world
def world():
    rnd = random.Random(42)
    sc = None
    sky_shader = s("shader_type sky;\nfloat hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }\n"
        "void sky() {\n\tvec3 d = normalize(EYEDIR);\n\tfloat h = hash(floor(d * 260.0));\n\tfloat star = step(0.9972, h) * (0.4 + 0.6 * fract(h * 97.0));\n"
        "\tCOLOR = vec3(0.008, 0.01, 0.022) + vec3(star) * vec3(0.9, 0.95, 1.0);\n}\n")
    # landmarks
    lm = []
    for i in range(70):
        ang = rnd.uniform(0, math.tau); r = rnd.choice([rnd.uniform(40, 160), rnd.uniform(160, 700)])
        y = rnd.uniform(-120, 120) if r > 160 else rnd.uniform(-40, 40)
        size = rnd.uniform(3, 12) if r < 160 else rnd.uniform(10, 60)
        sx, sy, sz = size * rnd.uniform(0.6, 1.4), size * rnd.uniform(0.6, 2.2), size * rnd.uniform(0.6, 1.4)
        th = rnd.uniform(0, math.tau); c, sn = math.cos(th), math.sin(th)
        t = f"Transform3D({c*sx:.3f}, 0, {-sn*sz:.3f}, 0, {sy:.3f}, 0, {sn*sx:.3f}, 0, {c*sz:.3f}, {r*math.cos(ang):.2f}, {y:.2f}, {r*math.sin(ang):.2f})"
        lm.append(N(f"Rock{i:02d}", "MeshInstance3D", {"transform": t, "mesh": 'SubResource("Mesh_rock_%d")' % (i % 2), "material_override": 'SubResource("Mat_rock_%d")' % (i % 3)}))
    spawn = []
    for i in range(8):
        a = i / 8 * math.tau
        spawn.append(N(f"Spawn{i}", "Marker3D", {"transform": f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {30*math.cos(a):.2f}, {(i%3-1)*4:.1f}, {30*math.sin(a):.2f})"}))
    rig = N("CameraRig", "Node3D", {}, [N("Pivot", "Node3D", {}, [N("Camera3D", "Camera3D", {"current": "true", "far": 6000.0, "fov": 70.0})])], script='ExtResource("3_cam")')
    hud_inst = N("HUD", None, {}, instance='ExtResource("5_hud")')
    root = N("GameWorld", "Node3D", {}, [
        N("WorldEnvironment", "WorldEnvironment", {"environment": 'SubResource("Env_w")'}),
        N("Sun", "DirectionalLight3D", {"transform": "Transform3D(0.8, -0.35, 0.5, 0, 0.82, 0.57, -0.6, -0.45, 0.66, 0, 50, 0)", "light_energy": 1.3}),
        N("Landmarks", "Node3D", {}, lm),
        N("SpawnPoints", "Node3D", {}, spawn),
        N("Ships", "Node3D", {}),
        N("ShipSpawner", "MultiplayerSpawner", {"spawn_path": 'NodePath("../Ships")'}),
        N("ProjectilePool", "Node3D", {}, [], script='ExtResource("2_pool")'),
        rig,
        N("StationCamera", "Camera3D", {"fov": 80.0, "far": 6000.0}, [], script='ExtResource("6_stcam")'),
        N("TargetMarker", "MeshInstance3D", {"visible": "false", "mesh": 'SubResource("Mesh_marker")'}),
        hud_inst], script='ExtResource("1_world")')
    sc = Scene(root)
    sc.ext_res("1_world", "Script", "res://scripts/world/game_world.gd")
    sc.ext_res("2_pool", "Script", "res://scripts/world/projectile_pool.gd")
    sc.ext_res("3_cam", "Script", "res://scripts/world/chase_camera.gd")
    sc.ext_res("6_stcam", "Script", "res://scripts/world/station_camera.gd")
    sc.ext_res("5_hud", "PackedScene", "res://scenes/hud.tscn")
    sh = sc.sub("Shader_sky", "Shader", code=sky_shader)
    skm = sc.sub("Mat_sky", "ShaderMaterial", shader=sh)
    sky = sc.sub("Sky_w", "Sky", sky_material=skm)
    sc.sub("Env_w", "Environment", background_mode=2, sky=sky, ambient_light_source=2, ambient_light_color="Color(0.45, 0.5, 0.65, 1)", ambient_light_energy=0.5)
    sc.sub("Mesh_rock_0", "BoxMesh")
    sc.sub("Mesh_rock_1", "SphereMesh", radius=0.5, height=1.0, radial_segments=12, rings=6)
    for i, col in enumerate(["Color(0.32, 0.30, 0.28, 1)", "Color(0.26, 0.28, 0.34, 1)", "Color(0.36, 0.30, 0.26, 1)"]):
        sc.sub(f"Mat_rock_{i}", "StandardMaterial3D", albedo_color=col, roughness=0.95)
    mm = sc.sub("Mat_marker", "StandardMaterial3D", shading_mode=0, transparency=1, albedo_color="Color(0.3, 1, 0.5, 0.45)")
    sc.sub("Mesh_marker", "SphereMesh", material=mm, radius=0.8, height=1.6)
    write("game_world.tscn", sc)

main_menu(); preset_creator(); tactical_map(); hud(); world()
