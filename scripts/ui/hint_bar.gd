class_name HintBar
extends PanelContainer
## THE HINT BAR (top centre): one short line about what could help right now. Emergencies on board first (air, fire, boarders...),
## then lessons the player has not followed yet (each disappears for good once the player does it; Prefs.hints_done).
## While the tutorial runs (Data.tutorial_text) it shows the tutorial step instead. Can be switched off in the settings.

var _label: Label
var _timer: float = 0.0
var _shown_id: String = ""
var _shown_for: float = 0.0
var _cool: Dictionary = {}              # emergency id -> seconds before it may show again
var _moved: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _have_pos: bool = false
var _locked_time: float = 0.0
var _alive_time: float = 0.0


func _ready() -> void:
	name = "HintBar"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = 64
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = SettingsScreen.make_theme()
	add_theme_stylebox_override("panel", SettingsScreen._box(Color(0.05, 0.07, 0.11, 0.85), 10, Color(1.0, 0.8, 0.3, 0.6), 1, Vector4(14, 8, 14, 8)))
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(520, 0)
	add_child(_label)
	visible = false


static func is_done(id: String) -> bool:
	return Prefs.hints_done.split(",").has(id)


static func mark_done(id: String) -> void:
	if not is_done(id):
		Prefs.hints_done = (Prefs.hints_done + "," + id).trim_prefix(",")
		Prefs.save_file()


static func _key(action: String) -> String:
	return TutorialMission.key(action)


func _process(dt: float) -> void:
	_timer += dt
	for k in _cool.keys():
		_cool[k] = maxf(float(_cool[k]) - dt, 0.0)
	if _shown_id != "":
		_shown_for += dt
	if _timer < 0.25:
		return
	_timer = 0.0
	var ship := Data.local_ship
	if Data.tutorial_text != "":
		_show("tutorial", Data.tutorial_text)
		return
	if not Prefs.hints_on or not is_instance_valid(ship) or not ship.alive or not ship.is_multiplayer_authority():
		_hide()
		return
	_track(ship, 0.25)
	var pick := _choose(ship)
	if pick.is_empty():
		_hide()
		return
	_show(pick["id"], pick["text"])


func _track(ship: Ship, dt: float) -> void:
	_alive_time += dt
	if _have_pos:
		_moved += ship.global_position.distance_to(_last_pos)
	_last_pos = ship.global_position
	_have_pos = true
	if ship.detection.locked != null:
		_locked_time += dt
		mark_done("lock")
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and ship.detection.locked != null:
		mark_done("fire")
	if ship.detection.target_module >= 0:
		mark_done("module")
	if Input.is_key_pressed(KEY_M):
		mark_done("map")
	if Input.is_action_pressed("toggle_crew"):
		mark_done("crew")
	if Input.is_action_pressed("toggle_plan"):
		mark_done("plan")
	if _moved > 30.0:
		mark_done("fly")


## {id, text} of the hint to show now, or {}.
func _choose(ship: Ship) -> Dictionary:
	# ---- emergencies (they come back after a pause, as long as they are real)
	if ship.crew != null and ship.crew.foe_count() > 0:
		return _urgent("boarders", tr("BOARDERS on your ship! Open the plan (%s): red dots. Click doors to lock them in; your crew will fight.") % _key("toggle_plan"))
	for i in ship.haz_fire.size():
		if ship.haz_fire[i] > 0.15:
			return _urgent("fire", tr("FIRE on board! Crew put it out when somebody is in the room; doors close by themselves (click them in the plan to lock)."))
	for i in ship.haz_air.size():
		if ship.hazards.holds.size() > i and ship.hazards.holds[i] != 0 and ship.haz_air[i] < 0.5 and ship.module_hp[i] >= 0.0:
			return _urgent("air", tr("AIR is leaking! Close or lock the doors around it in the plan (%s); crew standing in the room seal the hole.") % _key("toggle_plan"))
	for i in ship.haz_elec.size():
		if ship.haz_elec[i] > 5.0:
			return _urgent("elec", tr("Electrical fault: a module is dark. It clears by itself, faster with somebody in the room (%s: crew panel).") % _key("toggle_crew"))
	if not ship.lodges.is_empty():
		return _urgent("lodged", tr("Your hull is stuck in an enemy. With an airlock you can BOARD: crew panel (%s).") % _key("toggle_crew"))
	# ---- lessons
	if not is_done("fly") and _alive_time > 3.0:
		return {"id": "fly", "text": tr("Fly with the keys listed at the bottom of the screen. %s brakes.") % _key("brake")}
	var enemy := false
	for c in ship.detection.contacts:
		if not c["friendly"]:
			enemy = true
	if enemy and not is_done("lock"):
		return {"id": "lock", "text": tr("An enemy is near: press %s to lock it. Your guns then aim ahead of it.") % _key("lock_target")}
	if ship.detection.locked != null and not is_done("fire"):
		return {"id": "fire", "text": tr("Hold the left mouse button to fire. The circle shows where to aim; H = weapons free in commander mode.")}
	if ship.detection.locked != null and _locked_time > 15.0 and not is_done("module"):
		return {"id": "module", "text": tr("Press %s to aim at one module of the target (when close enough to see it).") % _key("target_module")}
	if _alive_time > 40.0 and not is_done("map"):
		return {"id": "map", "text": tr("Press M for the tactical map: orders, orbit, approach.")}
	if _alive_time > 70.0 and not is_done("crew"):
		return {"id": "crew", "text": tr("Press %s for the crew panel: your people repair, fight fires and can be sent anywhere.") % _key("toggle_crew")}
	if _alive_time > 100.0 and not is_done("plan"):
		return {"id": "plan", "text": tr("Press %s for the exploded 3D plan of your ship: rooms, doors, crew, damage.") % _key("toggle_plan")}
	return {}


## An emergency hint: shown for 8 s, then not again for 60 s.
func _urgent(id: String, text: String) -> Dictionary:
	if _shown_id == id and _shown_for < 8.0:
		return {"id": id, "text": text}
	if float(_cool.get(id, 0.0)) > 0.0:
		return {}
	return {"id": id, "text": text}


func _show(id: String, text: String) -> void:
	if id != _shown_id:
		_shown_id = id
		_shown_for = 0.0
	if _label.text != text:
		_label.text = text
	visible = true
	if id != "tutorial" and _shown_for >= 8.0 and ["boarders", "fire", "air", "elec", "lodged"].has(id):
		_cool[id] = 60.0


func _hide() -> void:
	visible = false
	_shown_id = ""
