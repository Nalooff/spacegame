"""Generates scenes/lobby_browser.tscn (host form + list of open lobbies) and scenes/lobby.tscn (pre-game room).
Run: python3 tools/gen_lobby.py"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from tscn import *
OUT = os.path.join(os.path.dirname(__file__), "..", "scenes")
def write(name, scene): open(os.path.join(OUT, name), "w").write(scene.dump()); print("wrote", name)

def title(text, name, size=28): return N(name, "Label", {"layout_mode": 2, "text": s(text), "theme_override_font_sizes/font_size": size})
def heading(text, name): return N(name, "Label", {"layout_mode": 2, "text": s(text), "theme_override_font_sizes/font_size": 20, "modulate": "Color(0.62, 0.8, 1, 1)"})
def column(name, kids, expand=True, min_w=0):
    p = {"layout_mode": 2, "theme_override_constants/separation": 8}
    if expand: p["size_flags_horizontal"] = 3
    if min_w: p["custom_minimum_size"] = f"Vector2({min_w}, 0)"
    return N(name, "VBoxContainer", p, kids)
def tree(name, cols):
    return N(name, "Tree", {"layout_mode": 2, "size_flags_vertical": 3, "columns": cols, "column_titles_visible": "true", "hide_root": "true", "select_mode": 0}, unique=True)
def margin(name, kids):
    return N(name, "MarginContainer", {**full_rect(), "theme_override_constants/margin_left": 30, "theme_override_constants/margin_top": 30,
             "theme_override_constants/margin_right": 30, "theme_override_constants/margin_bottom": 30}, kids)
bg = lambda: N("BackgroundColor", "ColorRect", {**full_rect(), "color": "Color(0.03, 0.04, 0.07, 1)"})

# =============================================================== lobby browser
def browser():
    name_edit = line("PilotNameEdit", "Pilot")
    lobby_name = line("LobbyNameEdit", "", placeholder_text=s("My lobby"))
    visibility = N("VisibilityPicker", "OptionButton", {"layout_mode": 2, "item_count": 2, "selected": 0,
                   "popup/item_0/text": s("Public (anyone can join)"), "popup/item_0/id": 0,
                   "popup/item_1/text": s("Private (password)"), "popup/item_1/id": 1}, unique=True)
    password = line("PasswordEdit", "", secret="true", placeholder_text=s("Password"))
    password_row = N("PasswordRow", "HBoxContainer", {"layout_mode": 2, "visible": "false"}, [label("Password", "PasswordLabel"), password], unique=True)
    create = button("Create lobby", "CreateLobbyButton", custom_minimum_size="Vector2(0, 48)")
    host_col = column("HostColumn", [title("PLAY", "PlayTitleLabel"), hbox("PilotNameRow", [label("Pilot name", "PilotNameLabel"), name_edit]),
        sep("HostSeparator"), heading("HOST A LOBBY", "HostHeading"), label("Lobby name", "LobbyNameLabel"), lobby_name, visibility, password_row, create,
        label("", "HostStatusLabel", unique=True, wrap=True)], expand=False, min_w=380)
    lobby_tree = tree("LobbyTree", 3)
    refresh = button("Refresh", "RefreshButton")
    join = button("Join selected lobby", "JoinLobbyButton", unique=True, disabled="true")
    back = button("Back to menu", "BackButton")
    browse_col = column("BrowseColumn", [heading("OPEN LOBBIES  (lock = private)", "BrowseHeading"), lobby_tree,
        label("Looking for lobbies on your network...", "BrowseStatusLabel", unique=True, wrap=True),
        hbox("BrowseButtonsRow", [refresh, join, back])])
    pw_edit = line("JoinPasswordEdit", "", secret="true", placeholder_text=s("Password"))
    dialog = N("PasswordDialog", "ConfirmationDialog", {"title": s("Private lobby"), "ok_button_text": s("Join"), "size": "Vector2i(360, 140)"},
        [N("PasswordDialogColumn", "VBoxContainer", {"offset_left": 8.0, "offset_top": 8.0, "offset_right": 352.0, "offset_bottom": 91.0},
           [label("This lobby needs a password:", "PasswordPromptLabel"), pw_edit])], unique=True)
    root = N("LobbyBrowser", "Control", {**full_rect()}, [bg(), margin("BrowserMargin", [N("BrowserColumns", "HBoxContainer", {"layout_mode": 2, "theme_override_constants/separation": 30}, [host_col, browse_col])]), dialog],
             script='ExtResource("1_s")')
    sc = Scene(root); sc.ext_res("1_s", "Script", "res://scripts/ui/lobby_browser.gd")
    C = sc.connect
    C("text_changed", name_edit, "_on_pilot_name_changed")
    C("item_selected", visibility, "_on_visibility_selected")
    C("pressed", create, "_on_create_pressed")
    C("pressed", refresh, "_on_refresh_pressed"); C("pressed", join, "_on_join_pressed"); C("pressed", back, "_on_back_pressed")
    C("item_selected", lobby_tree, "_on_lobby_selected"); C("item_activated", lobby_tree, "_on_join_pressed")
    C("confirmed", dialog, "_on_password_confirmed")
    write("lobby_browser.tscn", sc)

# =============================================================== pre-game room
def room():
    timer = N("TimerLabel", "Label", {"layout_mode": 2, "horizontal_alignment": 2, "size_flags_horizontal": 3, "theme_override_font_sizes/font_size": 28}, unique=True)
    header = hbox("HeaderRow", [N("LobbyTitleLabel", "Label", {"layout_mode": 2, "theme_override_font_sizes/font_size": 28}, unique=True), timer])
    ship_list = N("ShipList", "ItemList", {"layout_mode": 2, "size_flags_vertical": 3}, unique=True)
    lock = button("Lock in ship", "LockButton", unique=True, custom_minimum_size="Vector2(0, 48)", disabled="true")
    ship_col = column("ShipColumn", [heading("1. CHOOSE YOUR SHIP", "ShipHeading"), ship_list,
        label("Pick a ship, then lock in so friends can join it as crew.", "ShipInfoLabel", unique=True, wrap=True), lock])
    players = tree("PlayerTree", 4)
    join_crew = button("Join selected ship as crew", "JoinCrewButton", unique=True, disabled="true")
    leave_crew = button("Leave crew", "LeaveCrewButton", unique=True, visible="false")
    crew_col = column("CrewColumn", [heading("2. PLAYERS  (or join a friend's crew)", "PlayersHeading"), players,
        label("Crew members man the turrets of the pilot's ship. Seats are set by the ship's Commander module.", "CrewHintLabel", wrap=True, modulate="Color(1, 1, 1, 0.6)"),
        hbox("CrewButtonsRow", [join_crew, leave_crew])])
    start = button("START GAME", "StartButton", unique=True, custom_minimum_size="Vector2(220, 48)", visible="false")
    leave = button("Leave lobby", "LeaveLobbyButton", custom_minimum_size="Vector2(160, 48)")
    footer = hbox("FooterRow", [label("", "StatusLabel", unique=True, wrap=True, size_flags_horizontal=3), start, leave])
    root = N("LobbyRoom", "Control", {**full_rect()}, [bg(), margin("RoomMargin", [N("RoomColumn", "VBoxContainer", {"layout_mode": 2, "theme_override_constants/separation": 14},
        [header, sep("HeaderSeparator"), N("RoomColumns", "HBoxContainer", {"layout_mode": 2, "size_flags_vertical": 3, "theme_override_constants/separation": 30}, [ship_col, crew_col]), footer])])],
             script='ExtResource("1_s")')
    sc = Scene(root); sc.ext_res("1_s", "Script", "res://scripts/ui/lobby.gd")
    C = sc.connect
    C("item_selected", ship_list, "_on_ship_selected"); C("pressed", lock, "_on_lock_pressed")
    C("item_selected", players, "_on_player_selected"); C("nothing_selected", players, "_on_player_deselected")
    C("pressed", join_crew, "_on_join_crew_pressed"); C("pressed", leave_crew, "_on_leave_crew_pressed")
    C("pressed", start, "_on_start_pressed"); C("pressed", leave, "_on_leave_pressed")
    write("lobby.tscn", sc)

browser(); room()
