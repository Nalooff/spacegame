extends Node
## Screenshot: builder with the plan open (env SHOT_SHIP = ship name, SHOT_DECK = deck index).
func _ready() -> void:
	var b: ShipBuilder = load("res://scenes/ship_builder.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(0.5).timeout
	var ship_name := OS.get_environment("SHOT_SHIP") if OS.get_environment("SHOT_SHIP") != "" else "Dart"
	b.design = ShipDesign.from_blob(ShipDesign.read_blob("res://ships/%s.json" % ship_name))
	BusEvent.builder_design_changed.emit()
	var ui: BuilderUI = b.get_node("UI/BuilderUI")
	ui._on_plan_pressed()
	await get_tree().create_timer(0.5).timeout
	var c: PlanCanvas = ui.plan_view.canvas
	if OS.get_environment("SHOT_DECK") != "":
		c.set_deck(int(OS.get_environment("SHOT_DECK")))
	print("decks: ", c.deck_count, " layers: ", c._layer)
	if OS.get_environment("SHOT_DOORS") != "":      # put a door on a few corridors to see them
		var pl := c._plan_edit()
		for ei in c.plan.edges.size():
			(pl["doors"] as Array).append([c.plan.edges[ei]["key"], 0.5])
		c._regenerate()
	if OS.get_environment("SHOT_VIEW") != "":        # DECK=0 SIDE=1 FRONT=2 SHEET=3 ISO=4
		ui.plan_view._show_view(int(OS.get_environment("SHOT_VIEW")) as PlanCanvas.View)
	if OS.get_environment("SHOT_WHITE") != "":
		c.set_paper_white(true)
	c._iso_yaw = 0.5
	c.queue_redraw()
	if OS.get_environment("SHOT_HOVER") != "":       # exploded view: pretend the mouse is over this module
		await get_tree().process_frame
		await get_tree().process_frame
		c._iso_hover = int(OS.get_environment("SHOT_HOVER"))
		c._mouse = Vector2(520, 300)
		for i in 30:
			c._process(0.05)
		c.queue_redraw()
