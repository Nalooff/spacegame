extends CanvasLayer
## Flight HUD + coordinate autopilot panel. All controls are nodes in scenes/hud.tscn
## (unique names, used as %Name). The HUD learns about the game only through BusEvent.

signal leave_requested

var ship: Ship


func _ready() -> void:
	BusEvent.local_ship_changed.connect(_on_local_ship_changed)
	BusEvent.autopilot_arrived.connect(_on_autopilot_arrived)
	BusEvent.module_destroyed.connect(_on_module_destroyed)
	BusEvent.ship_died.connect(_on_ship_died)
	BusEvent.notify.connect(show_banner)
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
		show_banner("You are CREW: aim with the mouse, hold left click to fire the turrets")
	if ship != null:
		show_coordinates(ship.global_position)


func _on_autopilot_arrived(arrived_ship: Ship) -> void:
	if arrived_ship == ship:
		show_banner("Arrived on target")


func _on_module_destroyed(hit_ship: Ship, module_index: int) -> void:
	if hit_ship == ship:
		show_banner("Module lost: %s" % str(hit_ship.design.modules[module_index]["type"]))


func _on_ship_died(dead_ship: Ship) -> void:
	if dead_ship == ship:
		show_banner("SHIP DESTROYED — respawning...")


# ------------------------------------------------------------------- helpers
func show_banner(text: String) -> void:
	%BannerLabel.text = text
	%BannerTimer.start()


func _on_banner_timer_timeout() -> void:
	%BannerLabel.text = ""


func show_coordinates(p: Vector3) -> void:
	%XSpin.value = snappedf(p.x, 0.1)
	%YSpin.value = snappedf(p.y, 0.1)
	%ZSpin.value = snappedf(p.z, 0.1)


func _process(_dt: float) -> void:
	%PlayersLabel.text = _players_text()
	if not is_instance_valid(ship):
		%FlightLabel.text = "No ship yet..."
		return
	if not ship.alive:
		return
	var ap := ship.autopilot
	var v := ship.linear_velocity
	var p := ship.global_position
	var ap_text := "OFF (manual)"
	if ap.is_active():
		ap_text = "ON TARGET" if ap.on_target else "%s  dist %.2f m" % [ap.phase, ap.distance]
	%FlightLabel.text = "Speed  %7.2f m/s\nVel    (%.1f, %.1f, %.1f)\nPos    (%.1f, %.1f, %.1f)\nAutopilot: %s\nFlight assist: %s" % [
		v.length(), v.x, v.y, v.z, p.x, p.y, p.z, ap_text, "ON" if ship.flight_assist else "OFF (T)"]
	%HullBar.value = ship.hull_ratio() * 100.0
	%CommanderBar.value = ship.commander_ratio() * 100.0
	%PowerBar.value = clampf(100.0 * ship.electricity.supply_w / maxf(ship.electricity.demand_w, 1.0), 0.0, 100.0)
	%PowerLabel.text = "Electricity  %.0f / %.0f kW%s" % [ship.electricity.demand_w / 1000.0, ship.electricity.supply_w / 1000.0,
		"  BROWN-OUT" if ship.electricity.factor < 0.99 else ""]
	%RcsLabel.text = "RCS max %.0f N (5%% of %.0f N best-axis thrust)" % [ship.rcs.force_max, ship.alloc.f_best]


func _players_text() -> String:
	var t := "PLAYERS\n"
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		t += "%s%s\n" % [p["name"], "  (crew)" if p["crew_of"] != 0 else ""]
	return t


# ------------------------------------------------------------- button handlers
func _on_go_pressed() -> void:
	if is_instance_valid(ship) and ship.alive:
		ship.autopilot.go_to(Vector3(%XSpin.value, %YSpin.value, %ZSpin.value))


func _on_cancel_pressed() -> void:
	if is_instance_valid(ship):
		ship.autopilot.cancel()


func _on_brake_pressed() -> void:
	if is_instance_valid(ship) and ship.alive:
		ship.autopilot.brake()


func _on_here_pressed() -> void:
	if is_instance_valid(ship):
		show_coordinates(ship.global_position)


func _on_leave_pressed() -> void:
	leave_requested.emit()
