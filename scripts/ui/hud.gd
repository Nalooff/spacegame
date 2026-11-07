extends CanvasLayer
## Flight HUD + flight orders panel (the orders themselves are given on the TacticalMap). All controls are nodes in scenes/hud.tscn
## (unique names, used as %Name). The HUD learns about the game only through BusEvent.

signal leave_requested

var ship: Ship


func _ready() -> void:
	BusEvent.local_ship_changed.connect(_on_local_ship_changed)
	BusEvent.autopilot_arrived.connect(_on_autopilot_arrived)
	BusEvent.module_destroyed.connect(_on_module_destroyed)
	BusEvent.ship_died.connect(_on_ship_died)
	BusEvent.notify.connect(show_banner)
	Net.kill_feed.connect(_on_kill_feed)
	%SettingsOverlay.visible = false
	$HudRoot.add_child(CrewPanel.new())
	$HudRoot.add_child(HintBar.new())
	Prefs.changed.connect(_refresh_help)
	_refresh_help()
	_on_local_ship_changed(Data.local_ship)


# ------------------------------------------------------------- BusEvent listeners
func _on_local_ship_changed(new_ship: Ship) -> void:
	ship = new_ship
	# crew members do not fly: hide the autopilot panel and say what they can do
	var piloting := ship == null or ship.is_multiplayer_authority()
	var panel := get_node_or_null("HudRoot/AutopilotPanel")
	if panel != null:
		panel.visible = piloting
	if ship != null and not piloting:
		show_banner(tr("You are CREW: aim with the mouse, hold left click to fire the turrets"))


func _on_autopilot_arrived(arrived_ship: Ship) -> void:
	if arrived_ship == ship:
		show_banner(tr("Arrived on target"))


func _on_module_destroyed(hit_ship: Ship, module_index: int) -> void:
	if hit_ship == ship:
		show_banner(tr("Module lost: %s") % str(hit_ship.design.modules[module_index]["type"]))


func _on_ship_died(dead_ship: Ship) -> void:
	if dead_ship == ship:
		show_banner(tr("SHIP DESTROYED — respawning..."))


# ------------------------------------------------------------------- helpers
func show_banner(text: String) -> void:
	%BannerLabel.text = text
	%BannerTimer.start()


func _on_banner_timer_timeout() -> void:
	%BannerLabel.text = ""


func _process(dt: float) -> void:
	%PlayersLabel.text = _players_text()
	if not _feed.is_empty():
		for e in _feed:
			e[1] -= dt
		var before := _feed.size()
		_feed = _feed.filter(func(e): return e[1] > 0.0)
		if _feed.size() != before:
			_show_feed()
	%RespawnButton.visible = is_instance_valid(ship) and ship.alive and ship.is_multiplayer_authority()
	if not is_instance_valid(ship):
		%FlightLabel.text = tr("No ship yet...")
		return
	if not ship.alive:
		return
	var ap := ship.autopilot
	var v := ship.linear_velocity
	var p := ship.global_position
	var ap_text := tr("OFF (manual)")
	if ap.is_active():
		ap_text = tr("ON TARGET") if ap.on_target else tr("%s  dist %.1f m") % [ap.phase, ap.distance]
	%FlightLabel.text = tr("Speed  %7.2f m/s\nVel    (%.1f, %.1f, %.1f)\nPos    (%.1f, %.1f, %.1f)\nAutopilot: %s\nFlight assist: %s") % [
		v.length(), v.x, v.y, v.z, p.x, p.y, p.z, ap_text, tr("ON") if ship.flight_assist else tr("OFF (T)")]
	%FireStateLabel.text = (tr("WEAPONS FREE") if ship.weapons_free else tr("WEAPONS HOLD (hold LMB to fire)")) if ship.stations.is_commander_mode() else ""
	%CommanderBar.value = ship.commander_ratio() * 100.0
	%PowerBar.value = clampf(100.0 * ship.electricity.supply_w / maxf(ship.electricity.demand_w, 1.0), 0.0, 100.0)
	%PowerLabel.text = tr("Electricity  %.0f / %.0f kW%s") % [ship.electricity.demand_w / 1000.0, ship.electricity.supply_w / 1000.0,
		tr("  BROWN-OUT") if ship.electricity.factor < 0.99 else ""]
	%RcsLabel.text = tr("RCS max %.0f N (5%% of %.0f N best-axis thrust)") % [ship.rcs.force_max, ship.alloc.f_best]


func _players_text() -> String:
	var t := tr("PLAYERS") + "\n"
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		t += "%s%s\n" % [p["name"], tr("  (crew)") if p["crew_of"] != 0 else ""]
	return t


# ------------------------------------------------------------- button handlers
func _on_open_map_pressed() -> void:
	%TacticalMap.open()


func _on_cancel_pressed() -> void:
	if is_instance_valid(ship):
		ship.autopilot.cancel()


func _on_brake_pressed() -> void:
	if is_instance_valid(ship) and ship.alive:
		ship.autopilot.brake()


func _on_respawn_pressed() -> void:
	if is_instance_valid(ship) and ship.alive and ship.is_multiplayer_authority():
		ship.respawn_now()


func _on_settings_pressed() -> void:
	%SettingsOverlay.visible = true


## The key help at the bottom follows the movement scheme chosen in the settings.
func _refresh_help() -> void:
	var lines := {
		0: tr("W/S forward/back  A/D strafe  Space/C up/down  Arrows pitch/yaw  Q/E roll"),
		1: tr("MOUSE steers (move the cursor away from the centre)  W/S thrust  A/D strafe  Space/C up/down  Q/E roll  RMB free look"),
		2: tr("MOUSE steers  W/S move the throttle lever  X lever to zero  A/D strafe  Space/C up/down  Q/E roll  RMB free look"),
		3: tr("G move circle: cursor = x,z   hold ALT = height   click = fly there   Esc cancel     (keys WASD / arrows still fly)"),
		4: tr("Double click space = fly that way   R lock   Z approach   O orbit   K keep at range   [ ] range     (keys still fly)"),
	}
	%ControlsHelpLabel.text = tr("%s\nLMB fire (commander mode: hold LMB to fire at the lock)   R lock next enemy   RMB drag orbit camera   Wheel zoom\nV commander/crew mode   F next station   P exploded 3D plan   X brake   T flight-assist   M tactical map   H weapons free   Tab scoreboard   J aim at next module   Y crew") % lines.get(Prefs.scheme, "")


func _on_scoreboard_pressed() -> void:
	%Scoreboard.toggle_pinned()


var _feed: Array = []   # [text, seconds left]

func _on_kill_feed(text: String) -> void:
	_feed.append([text, 8.0])
	while _feed.size() > 5:
		_feed.pop_front()
	_show_feed()


func _show_feed() -> void:
	var lines: PackedStringArray = []
	for e in _feed:
		lines.append(e[0])
	%KillFeedLabel.text = "\n".join(lines)


func _on_leave_pressed() -> void:
	leave_requested.emit()


## P opens / closes the SHIP PLAN: live state of every room and corridor (see PlanView).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M \
			and ship != null and is_instance_valid(ship) and ship.alive and ship.is_multiplayer_authority() \
			and not (get_viewport().gui_get_focus_owner() is LineEdit):
		if %TacticalMap.visible:
			%TacticalMap.close()
		else:
			%TacticalMap.open()
		return
	if event.is_action_pressed("toggle_plan") and ship != null and is_instance_valid(ship) and ship.alive:
		var view := get_node_or_null("HudRoot/PlanView") as PlanView
		if view == null:
			return
		if view.visible:
			view.visible = false
		else:
			view.open_ship(ship)
