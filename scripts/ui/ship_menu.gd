class_name ShipMenu
extends PopupMenu
## Nebulous-style context menu. Left click on your own ship (commander mode) or on a contact opens it; every
## entry is an order the ship keeps following until you stop it. Nested entries open as sub-menus.
##
## An entry is {"label": String, "do": Callable} or {"label": String, "sub": [entries]} or {"sep": true}.

var _actions: Array[Callable] = []
var _subs: Array[PopupMenu] = []


func _ready() -> void:
	hide_on_item_selection = true
	id_pressed.connect(_on_id)
	popup_hide.connect(func(): Data.cursor_busy = false)


func _on_id(id: int) -> void:
	if id >= 0 and id < _actions.size() and _actions[id].is_valid():
		_actions[id].call()


## Show the menu with `entries` at screen position `at`.
func open_at(entries: Array, at: Vector2, head: String = "") -> void:
	clear()
	for s in _subs:
		s.queue_free()
	_subs.clear()
	_actions.clear()
	if head != "":
		add_item(head, 9999)
		set_item_disabled(item_count - 1, true)
		add_separator()
	_fill(self, entries)
	Data.cursor_busy = true
	var win := get_viewport().get_visible_rect().size
	popup(Rect2i(Vector2i(at), Vector2i.ZERO))
	var sz := Vector2(size)
	position = Vector2i(Vector2(clampf(at.x, 0.0, maxf(win.x - sz.x, 0.0)), clampf(at.y, 0.0, maxf(win.y - sz.y, 0.0))))


func _fill(menu: PopupMenu, entries: Array) -> void:
	for e in entries:
		if e.get("sep", false):
			menu.add_separator()
		elif e.has("sub"):
			var sub := PopupMenu.new()
			sub.name = "sub%d" % _subs.size()
			sub.id_pressed.connect(_on_id)
			_subs.append(sub)
			menu.add_child(sub)
			_fill(sub, e["sub"])
			menu.add_submenu_node_item(e["label"], sub)
		else:
			var id := _actions.size()
			_actions.append(e["do"])
			if e.get("check", null) != null:
				menu.add_check_item(e["label"], id)
				menu.set_item_checked(menu.item_count - 1, bool(e["check"]))
			else:
				menu.add_item(e["label"], id)


# ------------------------------------------------------------------ the menus (pure data, tested)
## Orders for your own ship. `orders` is the OrderControls node (it owns the move circle).
func own_ship_entries(ship: Ship, orders: Node) -> Array:
	var ap := ship.autopilot
	return [
		{"label": tr("Move"), "sub": [
			{"label": tr("Go to a point…"), "do": func(): orders.open_circle(false)},
			{"label": tr("Go to a point and face a direction…"), "do": func(): orders.open_circle(true)},
			{"sep": true},
			{"label": tr("Cruise forward (until stopped)"), "do": func(): _cruise(ship, 1.0)},
			{"label": tr("Cruise forward, half thrust"), "do": func(): _cruise(ship, 0.5)},
			{"label": tr("Cruise forward, quarter thrust"), "do": func(): _cruise(ship, 0.25)},
		]},
		{"label": tr("Stop"), "sub": [
			{"label": tr("Brake to a standstill (X)"), "do": func(): ap.brake(); BusEvent.notify.emit(tr("Braking"))},
			{"label": tr("Cancel order (keep drifting)"), "do": func(): ap.cancel(); BusEvent.notify.emit(tr("Order cancelled: the ship keeps its current movement"))},
		]},
		{"label": tr("Weapons"), "sub": [
			{"label": tr("Weapons free (fire at the lock)"), "check": ship.weapons_free, "do": func(): ship.weapons_free = true; BusEvent.notify.emit(tr("WEAPONS FREE: the guns fire on their own"))},
			{"label": tr("Hold fire"), "check": not ship.weapons_free, "do": func(): ship.weapons_free = false; BusEvent.notify.emit(tr("WEAPONS HOLD: the guns wait for your order (click your ship, or H)"))},
			{"label": tr("Lock next enemy (R)"), "do": func(): _lock_next(ship)},
			{"label": tr("Release lock"), "do": func(): ship.detection.locked = null},
		]},
		{"label": tr("Flight assist"), "check": ship.flight_assist, "do": func(): ship.flight_assist = not ship.flight_assist},
		{"sep": true},
		{"label": tr("Tactical map (M)"), "do": func(): _key(KEY_M)},
		{"label": tr("Exploded 3D plan (P)"), "do": func(): _key(KEY_P)},
		{"label": tr("Crew / commander mode (V)"), "do": func(): _key(KEY_V)},
	]


## Orders against another ship (a contact marker or radar blip you clicked).
func contact_entries(ship: Ship, target: Ship) -> Array:
	var ap := ship.autopilot
	var ranges := [100.0, 300.0, 1000.0, 3000.0]
	var orbit: Array = []
	var keep: Array = []
	for r in ranges:
		orbit.append({"label": "%d m" % int(r), "do": func(): Prefs.order_range = r; ap.go_orbit(target, r); BusEvent.notify.emit(tr("Orbiting %s at %.0f m") % [target.pilot_name, r])})
		keep.append({"label": "%d m" % int(r), "do": func(): Prefs.order_range = r; ap.follow_distance = r; ap.go_follow(target); BusEvent.notify.emit(tr("Keeping %s at %.0f m") % [target.pilot_name, r])})
	return [
		{"label": tr("Target (lock)"), "do": func(): ship.detection.locked = target},
		{"label": tr("Target and open fire"), "do": func(): ship.detection.locked = target; ship.weapons_free = true; BusEvent.notify.emit(tr("WEAPONS FREE: the guns fire on their own"))},
		{"sep": true},
		{"label": tr("Approach"), "do": func(): ap.follow_distance = 15.0; ap.go_follow(target); BusEvent.notify.emit(tr("Approaching %s") % target.pilot_name)},
		{"label": tr("Keep range"), "sub": keep},
		{"label": tr("Orbit"), "sub": orbit},
		{"label": tr("Ram (full thrust at it)"), "do": func(): ap.drive_to(target.global_position, 1.0, target)},
		{"sep": true},
		{"label": tr("Brake"), "do": func(): ap.brake()},
		{"label": tr("Hold fire"), "do": func(): ship.weapons_free = false},
	]


func _cruise(ship: Ship, thr: float) -> void:
	var fwd: Vector3 = ship.global_transform.basis * ship.alloc.u_best
	ship.autopilot.drive_heading(fwd, thr)
	BusEvent.notify.emit(tr("Cruising forward until you stop it (X)"))


func _lock_next(ship: Ship) -> void:
	var list := ship.detection.enemies()
	if list.is_empty():
		BusEvent.notify.emit(tr("No target: press R to lock an enemy"))
		return
	ship.detection.locked = list[0]["ship"]


static func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
