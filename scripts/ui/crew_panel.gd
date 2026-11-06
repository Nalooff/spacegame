class_name CrewPanel
extends PanelContainer
## THE CREW PANEL (Y): who is on board, where they are, what they do; send somebody to repair or to look at a module.
## Orders reach the person at once with communications, otherwise after the walking time (PlanState.order_delay).
## Node names are used by tests: Row_<id>, Go_<id>, Look_<id>, Module_<id>, Log.

var ship: Ship
var _list: VBoxContainer
var _title: Label
var _log: Label
var _timer: float = 0.0
var _sig: String = ""


func _ready() -> void:
	name = "CrewPanel"
	visible = false
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -520
	offset_right = -16
	offset_top = 60
	offset_bottom = 520
	theme = SettingsScreen.make_theme()
	add_theme_stylebox_override("panel", SettingsScreen._box(Color(0.05, 0.07, 0.11, 0.94), 10, Color(0.3, 0.78, 1.0, 0.5), 1, Vector4(14, 12, 14, 12)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", SettingsScreen.ACCENT)
	col.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_log = Label.new()
	_log.name = "Log"
	_log.add_theme_font_size_override("font_size", 12)
	_log.add_theme_color_override("font_color", SettingsScreen.INK_DIM)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_log)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_crew") and not (get_viewport().gui_get_focus_owner() is LineEdit):
		set_open(not visible)
		get_viewport().set_input_as_handled()


func set_open(on: bool) -> void:
	visible = on
	Data.cursor_busy = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_sig = ""
		_refresh()


func _process(dt: float) -> void:
	if not visible:
		return
	_timer += dt
	if _timer >= 0.5:
		_timer = 0.0
		_refresh()


func _the_ship() -> Ship:
	var s := Data.local_ship
	return s if is_instance_valid(s) and s.is_multiplayer_authority() else null


func _module_label(s: Ship, mi: int) -> String:
	var pct := int(100.0 * s.module_hp[mi] / maxf(s.module_max_hp[mi], 1.0)) if s.module_hp[mi] >= 0.0 else 0
	return "%s %d  (%d%%)" % [str(s.design.modules[mi]["type"]), mi, pct]


func _refresh() -> void:
	ship = _the_ship()
	if ship == null or not ship.crew.active():
		_title.text = tr("CREW") + "  -  " + tr("nobody on board")
		for c in _list.get_children():
			c.queue_free()
		_sig = ""
		_log.text = ""
		return
	var crew := ship.crew
	_title.text = "%s  %d / %d" % [tr("CREW"), crew.alive_count(), crew.members.size()]
	var sig := "%d" % crew.members.size()
	for m in crew.members:
		sig += "|%d%d" % [m["id"], 1 if m["hp"] > 0.0 else 0]
	if sig != _sig:
		_sig = sig
		for c in _list.get_children():
			c.queue_free()
		for m in crew.members:
			_list.add_child(_make_row(m))
	for m in crew.members:
		var row := _list.get_node_or_null("Row_%d" % m["id"])
		if row != null:
			(row.get_node("Info") as Label).text = _info(ship, m)
	var lines := crew.log_lines.slice(maxi(crew.log_lines.size() - 6, 0))
	_log.text = "\n".join(lines)


func _info(s: Ship, m: Dictionary) -> String:
	if m["hp"] <= 0.0:
		return "#%d  %s" % [m["id"], tr("dead")]
	var where := s.crew.module_of(s, m)
	var task := tr("idle")
	match str(m["task"]):
		"walk":
			task = tr("walking") + " %.0f s" % float(m["t_left"])
		"work":
			task = tr("repairing")
	return "#%d  %d hp  %s %s  -  %s%s" % [m["id"], int(m["hp"]), tr("in"), (str(s.design.modules[where]["type"]) + " " + str(where)) if where >= 0 else "-", task, "  [" + tr("ordered") + "]" if m["ordered"] else ""]


func _make_row(m: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "Row_%d" % m["id"]
	var info := Label.new()
	info.name = "Info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	if m["hp"] <= 0.0:
		return box
	var h := HBoxContainer.new()
	box.add_child(h)
	var pick := OptionButton.new()
	pick.name = "Module_%d" % m["id"]
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var idx: Array[int] = []
	for mi in ship.design.modules.size():
		if ship.module_hp[mi] >= 0.0 and ship.design.modules[mi]["type"] != ModuleCatalog.LOOSE and ship.crew.node_for_module(ship, mi) >= 0:
			pick.add_item(_module_label(ship, mi))
			idx.append(mi)
	pick.set_meta("modules", idx)
	h.add_child(pick)
	var go := Button.new()
	go.name = "Go_%d" % m["id"]
	go.text = tr("Repair")
	go.pressed.connect(func(): order(int(m["id"]), _chosen(pick), "repair"))
	h.add_child(go)
	var look := Button.new()
	look.name = "Look_%d" % m["id"]
	look.text = tr("Look")
	look.pressed.connect(func(): order(int(m["id"]), _chosen(pick), "inspect"))
	h.add_child(look)
	var auto := Button.new()
	auto.text = tr("Auto")
	auto.pressed.connect(func(): if is_instance_valid(ship): ship.crew.release(int(m["id"])))
	h.add_child(auto)
	return box


func _chosen(pick: OptionButton) -> int:
	var idx: Array = pick.get_meta("modules", [])
	return int(idx[pick.selected]) if pick.selected >= 0 and pick.selected < idx.size() else -1


## Give an order. With communications it reaches the person at once, otherwise after the time somebody needs to walk to them.
func order(id: int, module: int, task: String) -> void:
	if ship == null or module < 0:
		return
	var who := {}
	for m in ship.crew.members:
		if m["id"] == id:
			who = m
	if who.is_empty():
		return
	var delay := ship.plan_state.order_delay(ship.crew.module_of(ship, who))
	if delay == INF:
		BusEvent.notify.emit(tr("Nobody can bring the order to that person (no way to them, no communications)"))
		return
	if delay <= 0.05:
		ship.crew.order(ship, id, module, task)
	else:
		var s := ship
		get_tree().create_timer(delay).timeout.connect(func(): if is_instance_valid(s): s.crew.order(s, id, module, task))
		BusEvent.notify.emit(tr("The order needs %.0f s to reach them (no communications)") % delay)
