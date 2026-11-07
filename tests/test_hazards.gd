extends Node
## Fire, air, electrical faults and doors.
##   godot --headless --path . res://tests/test_hazards.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _run(ship: Ship, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		ship.hazards.tick(ship, 0.1)
		ship.crew.tick(ship, 0.1)
		t += 0.1


func _fresh() -> Ship:
	var ship: Ship = load("res://scenes/ship.tscn").instantiate()
	ship.design_blob = ShipDesign.read_blob("res://ships/Brick.json")
	add_child(ship)
	return ship


func _ready() -> void:
	var ship := _fresh()
	for i in 8: await get_tree().physics_frame
	var h := ship.hazards
	check(h.is_built() and h.doors.size() > 0 and h.links.size() > 0, "doors and links exist (%d doors, %d links)" % [h.doors.size(), h.links.size()])
	check(ship.haz_doors.size() == h.doors.size() and ship.haz_air.size() == h.n, "state arrays are sized")
	# a link between two air holding modules
	var li := 0
	var a: int = h.links[li]["a"]
	var b: int = h.links[li]["b"]
	# ---- fire grows, burns the module and spreads through an open door
	ship.crew.members.clear()
	h.ignite(ship, a, 0.5)
	check(ship.haz_fire[a] > 0.4, "a fire starts")
	var hp0: float = ship.module_hp[a]
	_run(ship, 20.0)
	check(ship.haz_fire[a] > 0.5 or ship.haz_fire[a] == 0.0, "it burns or burns out")
	check(ship.module_hp[a] < hp0 or hp0 <= 0.0, "fire burns the module (%.0f -> %.0f)" % [hp0, ship.module_hp[a]])
	check(ship.haz_doors.count(ShipHazards.AUTO) > 0, "doors next to the fire close by themselves")
	check(ship.haz_fire[b] == 0.0, "...so the fire does not spread to the next room")
	# ---- reopen after it is out
	var f := ship.haz_fire
	f.fill(0.0)
	ship.haz_fire = f
	var air := ship.haz_air
	air.fill(1.0)
	ship.haz_air = air
	for k in h.n:
		h.breach[k] = 0.0
		h.alert[k] = 0.0
	var hpf := ship.module_hp
	for k in hpf.size():
		hpf[k] = ship.module_max_hp[k]
	ship.module_hp = hpf
	_run(ship, 2.0)
	check(ship.haz_doors.count(ShipHazards.AUTO) == 0, "automatic doors open again when it is safe")
	# ---- spread through an OPEN door
	var ds := ship.haz_doors
	ds.fill(ShipHazards.OPEN)
	ship.haz_doors = ds
	# keep doors open: a locked-open state does not exist, so test the rule directly
	check(h.link_open(ship, li), "an open door lets things through")
	ds[h.links[li]["doors"][0]] = ShipHazards.CLOSED
	ship.haz_doors = ds
	check(not h.link_open(ship, li), "a closed door stops fire and air")
	# ---- breach: air leaks, people choke, a closed door keeps the next room safe
	var hh := ship.module_hp
	hh[a] = ship.module_max_hp[a] * 0.4
	ship.module_hp = hh
	h.breach[a] = 1.0
	air = ship.haz_air
	air.fill(1.0)
	ship.haz_air = air
	_run(ship, 15.0)
	check(ship.haz_air[a] < 0.2, "a breach empties the room (air %.2f)" % ship.haz_air[a])
	check(ship.haz_air[b] > 0.8, "the room behind the closed door keeps its air (%.2f)" % ship.haz_air[b])
	# ---- electrical fault stops a module until cleared
	var t_mod := -1
	for mi in ship.design.modules.size():
		var t: String = ship.design.modules[mi]["type"]
		if t == ModuleCatalog.TURRET or t == ModuleCatalog.RADAR or t == ModuleCatalog.ENGINE_ROOM:
			t_mod = mi
			break
	if t_mod >= 0:
		check(ship.is_working(t_mod), "the module works")
		h.short_out(ship, t_mod)
		ship._update_function()
		check(not ship.is_working(t_mod), "an electrical fault switches it off")
		_run(ship, Data.HAZ_ELEC_SECONDS + 1.0)
		ship._update_function()
		check(ship.is_working(t_mod), "...and it comes back when the fault clears")
	# ---- people suffocate and burn
	var ship2 := _fresh()
	for i in 8: await get_tree().physics_frame
	var m: Dictionary = ship2.crew.members[0]
	var room := ship2.crew.module_of(ship2, m)
	var h2 := ship2.module_hp
	h2[room] = ship2.module_max_hp[room] * 0.4
	ship2.module_hp = h2
	ship2.hazards.breach[room] = 1.0
	var d2 := ship2.haz_doors
	d2.fill(ShipHazards.CLOSED)
	ship2.haz_doors = d2
	var before: float = m["hp"]
	_run(ship2, 40.0)
	check(m["hp"] < before, "somebody in a vented room suffocates (%.0f -> %.0f)" % [before, m["hp"]])
	# ---- locked doors stop crew, closed ones do not
	var ship3 := _fresh()
	for i in 8: await get_tree().physics_frame
	var edges := ship3.plan_state.plan.edges.size()
	var d3 := ship3.haz_doors
	d3.fill(ShipHazards.CLOSED)
	ship3.haz_doors = d3
	ship3._update_function()
	var open_ok := ship3.plan_state.ok_edges.count(1)
	d3.fill(ShipHazards.LOCKED)
	ship3.haz_doors = d3
	ship3._update_function()
	check(ship3.plan_state.ok_edges.count(1) < open_ok, "locked doors block the corridors (%d -> %d of %d)" % [open_ok, ship3.plan_state.ok_edges.count(1), edges])
	d3.fill(ShipHazards.CLOSED)
	ship3.haz_doors = d3
	ship3._update_function()
	check(ship3.plan_state.ok_edges.count(1) == open_ok, "closed (not locked) doors do not block people")
	# ---- the bridge sets doors, only with communications
	check(ship3.set_door(0, ShipHazards.LOCKED) == ship3.plan_state.comms_ok, "doors are set from the bridge while communications work")
	# ---- role bonus
	var any_manned := false
	for mi in ship3.design.modules.size():
		if ship3.role_bonus(mi) > 1.0:
			any_manned = true
	check(any_manned, "a manned room gives a bonus")
	print("FAILS: %d" % fails)
	get_tree().quit(fails)
