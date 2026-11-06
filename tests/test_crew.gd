extends Node
## Crew: people walk the plan, repair damaged modules, die with their room; all dead = the ship is lost.
##   godot --headless --path . res://tests/test_crew.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _run(ship: Ship, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		ship.crew.tick(ship, 0.1)
		t += 0.1


func _ready() -> void:
	var ship: Ship = load("res://scenes/ship.tscn").instantiate()
	ship.design_blob = ShipDesign.read_blob("res://ships/Brick.json")
	add_child(ship)
	for i in 8: await get_tree().physics_frame
	var crew := ship.crew
	check(crew.active(), "the ship has a crew (%d people)" % crew.members.size())
	check(crew.alive_count() == crew.members.size(), "everybody is alive at the start")

	# ---- repair: damage a module, comms are on -> somebody notices, walks there and repairs it
	var target := -1
	for mi in ship.design.modules.size():
		if ship.module_hp[mi] > 0.0 and crew.node_for_module(ship, mi) >= 0 and ship.design.modules[mi]["type"] != ModuleCatalog.COMMANDER:
			target = mi
			break
	var full := ship.module_max_hp[target]
	var hp := ship.module_hp
	hp[target] = full * 0.4
	ship.module_hp = hp
	_run(ship, 2.0)
	check(crew.noticed.has(target), "damage is noticed at once while communications work")
	_run(ship, 120.0)
	check(ship.module_hp[target] > full * 0.4 + 1.0, "the crew repaired it (%.0f -> %.0f of %.0f)" % [full * 0.4, ship.module_hp[target], full])

	# ---- an order: send a person to look at / repair a module
	var id: int = crew.members[0]["id"]
	check(crew.order(ship, id, target, "inspect"), "an order to go and look is accepted")
	check(crew.members[0]["task"] == "walk" or crew.members[0]["t_left"] == 0.0, "the person walks")
	_run(ship, 60.0)
	check(not crew.members[0]["ordered"], "...and is free again after looking")
	check(crew.nearest_free(ship, target) >= 0, "somebody free can be found for a module")

	# ---- people hurt and killed by hits
	var m0: Dictionary = crew.members[1]
	var mod := crew.module_of(ship, m0)
	var before: float = m0["hp"]
	crew.on_hit(ship, mod, ship.module_max_hp[mod] * 0.25)
	check(m0["hp"] < before, "a hit hurts the people in that room")
	# ---- reports without communications need somebody near the damage
	var far := Vector3(1000, 1000, 1000)
	check(crew.finder_delay(ship, far) < 0.0, "nobody near a far away spot -> nobody can report it")
	check(crew.finder_delay(ship, m0["pos"]) >= 0.0, "somebody standing there can walk the report to the bridge")
	# ---- the panel
	Data.local_ship = ship
	var panel := CrewPanel.new()
	add_child(panel)
	panel.set_open(true)
	check(panel.find_child("Log", true, false) != null and panel.find_child("Row_%d" % id, true, false) != null, "the crew panel lists the people")
	var pick := panel.find_child("Module_%d" % id, true, false) as OptionButton
	check(pick != null and pick.item_count > 0, "...with a module picker")
	if pick != null:
		pick.select(0)
		(panel.find_child("Go_%d" % id, true, false) as Button).pressed.emit()
		check(crew.members[0]["ordered"] or crew.members[0]["task"] != "idle", "the Repair button sends the person")
	panel.set_open(false)
	check(not Data.cursor_busy, "closing the panel gives the mouse back")
	# ---- all dead = the ship is lost
	for m in crew.members:
		m["hp"] = 0.0
	check(crew.tick(ship, 0.2), "when the last person dies the ship is lost")
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
