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
    quit_ = button("Quit", "QuitButton", unique=True, custom_minimum_size="Vector2(320, 40)")
    notice = N("NoticeLabel", "Label", {"layout_mode": 2, "horizontal_alignment": 1, "modulate": "Color(1, 0.7, 0.4, 1)"}, unique=True)
    menu_column = N("MenuButtonsColumn", "VBoxContainer", {"layout_mode": 2, "theme_override_constants/separation": 14}, [title, sub, N("TitleToButtonsSpacer", "Control", {"layout_mode": 2, "custom_minimum_size": "Vector2(0, 30)"}), creation, play, quit_, notice])
    center = N("MenuCenter", "CenterContainer", {**full_rect()}, [menu_column])
    bg = N("BackgroundColor", "ColorRect", {**full_rect(), "color": "Color(0.03, 0.04, 0.07, 1)"})
    root = N("MainMenu", "Control", {**full_rect()}, [bg, center], script='ExtResource("1_s")')
    sc = Scene(root); sc.ext_res("1_s", "Script", "res://scripts/ui/main_menu.gd")
    sc.connect("pressed", creation, "_on_creation_pressed"); sc.connect("pressed", play, "_on_play_pressed"); sc.connect("pressed", quit_, "_on_quit_pressed")
    write("main_menu.tscn", sc)

# =============================================================== HUD
def hud():
    def bar(name):
        return N(name, "ProgressBar", {"layout_mode": 2, "show_percentage": "false", "value": 100.0, "custom_minimum_size": "Vector2(0, 14)"}, unique=True)
    flight = label("", "FlightLabel", unique=True)
    left_panel = N("FlightStatusPanel", "PanelContainer", {"layout_mode": 1, "offset_left": 10.0, "offset_top": 10.0, "offset_right": 360.0, "offset_bottom": 270.0},
        [vbox("StatusColumn", [flight, label("Hull", "HullLabel"), bar("HullBar"), label("Commander module", "CommanderLabel"), bar("CommanderBar"),
                      label("", "PowerLabel", unique=True), bar("PowerBar"), label("", "RcsLabel", unique=True, wrap=True)])])
    banner = N("BannerLabel", "Label", {"layout_mode": 1, "anchors_preset": 5, "anchor_left": 0.5, "anchor_right": 0.5, "offset_left": -300.0, "offset_top": 30.0, "offset_right": 300.0,
                "offset_bottom": 80.0, "grow_horizontal": 2, "horizontal_alignment": 1, "theme_override_font_sizes/font_size": 30, "modulate": "Color(1, 0.8, 0.3, 1)"}, unique=True)
    leave = button("Leave game", "LeaveButton")
    right_top = N("PlayersPanel", "PanelContainer", {"layout_mode": 1, "anchors_preset": 1, "anchor_left": 1.0, "anchor_right": 1.0, "offset_left": -220.0, "offset_top": 10.0,
                  "offset_right": -10.0, "offset_bottom": 160.0, "grow_horizontal": 0}, [vbox("PlayersColumn", [label("", "PlayersLabel", unique=True), leave])])
    xs, ys, zs = spin("XSpin", -100000, 100000, 0.1, 0, allow_greater="true", allow_lesser="true", update_on_text_changed="true"), \
                 spin("YSpin", -100000, 100000, 0.1, 0, allow_greater="true", allow_lesser="true", update_on_text_changed="true"), \
                 spin("ZSpin", -100000, 100000, 0.1, 0, allow_greater="true", allow_lesser="true", update_on_text_changed="true")
    go, brake, cancel, here = button("GO", "GoButton"), button("Brake (X)", "BrakeButton"), button("Cancel", "CancelButton"), button("Use my position", "HereButton")
    ap = N("AutopilotPanel", "PanelContainer", {"layout_mode": 1, "anchors_preset": 3, "anchor_left": 1.0, "anchor_top": 1.0, "anchor_right": 1.0, "anchor_bottom": 1.0,
              "offset_left": -430.0, "offset_top": -170.0, "offset_right": -10.0, "offset_bottom": -10.0, "grow_horizontal": 0, "grow_vertical": 0},
        [vbox("AutopilotColumn", [label("COORDINATE AUTOPILOT  (flies there and stops)", "AutopilotTitleLabel", wrap=True),
                      hbox("CoordinatesRow", [label("X", "XLabel"), xs, label("Y", "YLabel"), ys, label("Z", "ZLabel"), zs]),
                      hbox("AutopilotButtonsRow", [go, brake, cancel]), here])])
    help_ = N("ControlsHelpLabel", "Label", {"layout_mode": 1, "anchors_preset": 2, "anchor_top": 1.0, "anchor_bottom": 1.0, "offset_left": 10.0, "offset_top": -150.0, "offset_right": 600.0,
               "offset_bottom": -10.0, "grow_vertical": 0, "vertical_alignment": 2, "modulate": "Color(1, 1, 1, 0.6)",
               "text": s("W/S forward/back  A/D strafe  Space/C up/down  Arrows pitch/yaw  Q/E roll\nLMB fire at cursor   RMB drag orbit camera   Wheel zoom\nX brake   T flight-assist on/off   Any manual key cancels the autopilot")})
    banner_timer = N("BannerTimer", "Timer", {"wait_time": 3.0, "one_shot": "true"}, unique=True)
    root = N("HudRoot", "Control", {**full_rect(), "mouse_filter": 2}, [left_panel, banner, right_top, ap, help_, banner_timer])
    top = N("HUD", "CanvasLayer", {}, [root], script='ExtResource("1_s")')
    sc = Scene(top); sc.ext_res("1_s", "Script", "res://scripts/ui/hud.gd")
    C = sc.connect
    C("pressed", go, "_on_go_pressed"); C("pressed", brake, "_on_brake_pressed"); C("pressed", cancel, "_on_cancel_pressed")
    C("pressed", here, "_on_here_pressed"); C("pressed", leave, "_on_leave_pressed"); C("timeout", banner_timer, "_on_banner_timer_timeout")
    write("hud.tscn", sc)

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
        N("ProjectilePool", "Node3D", {"bolt_mesh": 'SubResource("Mesh_bolt")'}, [], script='ExtResource("2_pool")'),
        rig,
        N("TargetMarker", "MeshInstance3D", {"visible": "false", "mesh": 'SubResource("Mesh_marker")'}),
        hud_inst], script='ExtResource("1_world")')
    sc = Scene(root)
    sc.ext_res("1_world", "Script", "res://scripts/world/game_world.gd")
    sc.ext_res("2_pool", "Script", "res://scripts/world/projectile_pool.gd")
    sc.ext_res("3_cam", "Script", "res://scripts/world/chase_camera.gd")
    sc.ext_res("5_hud", "PackedScene", "res://scenes/hud.tscn")
    sh = sc.sub("Shader_sky", "Shader", code=sky_shader)
    skm = sc.sub("Mat_sky", "ShaderMaterial", shader=sh)
    sky = sc.sub("Sky_w", "Sky", sky_material=skm)
    sc.sub("Env_w", "Environment", background_mode=2, sky=sky, ambient_light_source=2, ambient_light_color="Color(0.45, 0.5, 0.65, 1)", ambient_light_energy=0.5)
    sc.sub("Mesh_rock_0", "BoxMesh")
    sc.sub("Mesh_rock_1", "SphereMesh", radius=0.5, height=1.0, radial_segments=12, rings=6)
    for i, col in enumerate(["Color(0.32, 0.30, 0.28, 1)", "Color(0.26, 0.28, 0.34, 1)", "Color(0.36, 0.30, 0.26, 1)"]):
        sc.sub(f"Mat_rock_{i}", "StandardMaterial3D", albedo_color=col, roughness=0.95)
    bm = sc.sub("Mat_bolt", "StandardMaterial3D", shading_mode=0, albedo_color="Color(1, 0.92, 0.35, 1)")
    sc.sub("Mesh_bolt", "SphereMesh", material=bm, radius=0.22, height=0.44, radial_segments=8, rings=4)
    mm = sc.sub("Mat_marker", "StandardMaterial3D", shading_mode=0, transparency=1, albedo_color="Color(0.3, 1, 0.5, 0.45)")
    sc.sub("Mesh_marker", "SphereMesh", material=mm, radius=0.8, height=1.6)
    write("game_world.tscn", sc)

main_menu(); hud(); world()
