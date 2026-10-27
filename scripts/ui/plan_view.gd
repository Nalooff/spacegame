class_name PlanView
extends PanelContainer
## The ship plan window: a PlanCanvas plus the buttons (view, tools, reset).
##   open_design(design)   builder: edit corridors
##   open_ship(ship)       game: live status (refreshes a few times a second)
## Every node is in scenes/plan_view.tscn.

signal edit_requested     ## forwarded: the builder makes an undo checkpoint
signal edited

@onready var canvas: PlanCanvas = %PlanCanvas
@onready var title_label: Label = %PlanTitleLabel
@onready var status_label: Label = %PlanStatusLabel
@onready var tool_row: HBoxContainer = %PlanToolRow

var _live: Ship = null
var _timer: float = 0.0


func _ready() -> void:
	canvas.edit_requested.connect(func(): edit_requested.emit())
	canvas.edited.connect(_on_edited)
	canvas.hint.connect(func(t: String): status_label.text = t)
	%ViewTopButton.pressed.connect(func(): _show_view(PlanCanvas.View.DECK))
	%ViewSideButton.pressed.connect(func(): _show_view(PlanCanvas.View.SIDE))
	%ViewFrontButton.pressed.connect(func(): _show_view(PlanCanvas.View.FRONT))
	%ViewSheetButton.pressed.connect(func(): _show_view(PlanCanvas.View.SHEET))
	%ViewIsoButton.pressed.connect(func(): _show_view(PlanCanvas.View.ISO))
	%PaperButton.toggled.connect(func(on: bool): canvas.set_paper_white(on))
	%ExplodeSlider.value_changed.connect(func(v: float): canvas.set_explode(v))
	%ToolViewButton.pressed.connect(func(): canvas.set_tool(PlanCanvas.Tool.VIEW))
	%ToolDrawButton.pressed.connect(func(): canvas.set_tool(PlanCanvas.Tool.DRAW))
	%ToolEraseButton.pressed.connect(func(): canvas.set_tool(PlanCanvas.Tool.ERASE))
	%ToolDoorButton.pressed.connect(func(): canvas.set_tool(PlanCanvas.Tool.DOOR))
	%DeckPicker.item_selected.connect(func(i: int): canvas.set_deck(i))
	canvas.decks_changed.connect(_on_decks_changed)
	canvas.layers_changed.connect(_build_layer_row)
	%PlanTabs.tab_changed.connect(func(_i: int): _show_tab())
	_build_layer_row()
	%ResetPlanButton.pressed.connect(func(): canvas.reset_plan())
	%ClosePlanButton.pressed.connect(func(): visible = false)
	visible = false


## One check box per drawing layer of the canvas (hull, rooms, and any layer added later with PlanCanvas.register_layer).
func _build_layer_row() -> void:
	var row: HBoxContainer = %LayerRow
	for c in row.get_children():
		c.queue_free()
	var lab := Label.new()
	lab.text = "Layers:"
	row.add_child(lab)
	for l in canvas.layers:
		var cb := CheckBox.new()
		cb.name = "Layer_" + str(l["id"])
		cb.text = str(l["label"])
		cb.button_pressed = bool(l["enabled"])
		var id: String = l["id"]
		cb.toggled.connect(func(on: bool): canvas.set_layer_enabled(id, on))
		row.add_child(cb)


## MAP / STATUS / LOGS tabs. STATUS and LOGS are text lists of the live ship (the plan window of the builder only has MAP).
func _show_tab() -> void:
	var tab: int = %PlanTabs.current_tab
	canvas.visible = tab == 0
	%PlanInfoText.visible = tab != 0
	%ExplodeRow.visible = tab == 0 and canvas.view == PlanCanvas.View.ISO
	_refresh_info()


func _refresh_info() -> void:
	var info: RichTextLabel = %PlanInfoText
	if not info.visible:
		return
	if _live == null or not is_instance_valid(_live):
		info.text = "Status and logs exist for a ship in flight."
		return
	var rep := _live.reports
	var t := ""
	if %PlanTabs.current_tab == 1:
		t += "[b]COMMS[/b]  %s\n\n" % ("ONLINE" if rep.known_state.comms_ok else "[color=orange]OFFLINE[/color]")
		var cut := rep.cut_off_rooms(_live)
		for mi in _live.design.modules.size():
			var type: String = _live.design.modules[mi]["type"]
			if type == ModuleCatalog.LOOSE or mi >= rep.known_hp.size():
				continue
			var hp := rep.known_hp[mi]
			var state := "[color=gray]GONE[/color]" if hp < 0.0 else ("[color=red]DESTROYED[/color]" if hp <= 0.0 else "%d%%" % int(100.0 * hp / maxf(_live.module_max_hp[mi], 0.001)))
			var note := ""
			if cut.has(mi):
				note = "   [color=orange]NO LINK: cannot be ordered[/color]"
			t += "%-3d %-12s %s%s\n" % [mi, type, state, note]
		t += "\nAs the commander KNOWS it: changes can still be on their way."
	else:
		t += "[b]REPORTS RECEIVED[/b]\n\n"
		for line in rep.history:
			t += line + "\n"
		if rep.history.is_empty():
			t += "Nothing reported yet.\n"
		if rep.unreachable_reports() > 0:
			t += "\n[color=orange]%d report(s) cannot reach the bridge (no link).[/color]" % rep.unreachable_reports()
	info.text = t


## Switch the drawing; the Explode slider only matters in the exploded 3D view.
func _show_view(v: PlanCanvas.View) -> void:
	canvas.set_view(v)
	%ExplodeRow.visible = v == PlanCanvas.View.ISO and %PlanTabs.current_tab == 0


func _on_decks_changed(count: int) -> void:
	var picker: OptionButton = %DeckPicker
	if picker.item_count != count:
		picker.clear()
		for k in count:
			picker.add_item("Deck %d" % (k + 1))
	picker.select(canvas.deck)


func open_design(d: ShipDesign) -> void:
	_live = null
	%PlanTabs.visible = false
	%PlanTabs.current_tab = 0
	title_label.text = "SHIP PLAN  (the hull holds the corridors; you draw them)"
	tool_row.visible = true
	visible = true
	canvas.show_design(d, true)
	_update_status()


func open_ship(s: Ship) -> void:
	_live = s
	%PlanTabs.visible = true
	title_label.text = "SHIP PLAN  (live)"
	tool_row.visible = false
	visible = true
	canvas.show_design(s.design, false, s)
	_update_status()


## Builder: the design changed from outside (undo, moving modules ...).
func refresh_design(d: ShipDesign) -> void:
	if visible and _live == null:
		canvas.show_design(d, true)
		_update_status()


func _on_edited() -> void:
	edited.emit()
	_update_status()


func _update_status() -> void:
	if canvas.design == null:
		return
	var lost := canvas.design.unwalkable_rooms() if _live == null else PackedInt32Array()
	if _live == null:
		status_label.text = "Every room can be reached." if lost.is_empty() else "%d room(s) have NO corridor to a commander: %s" % [lost.size(), str(Array(lost))]


func _process(dt: float) -> void:
	if not visible or _live == null:
		return
	if not is_instance_valid(_live) or not _live.alive:
		visible = false
		return
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.25
		canvas.queue_redraw()
		_refresh_info()
