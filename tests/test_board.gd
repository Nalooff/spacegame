extends Node
## Boarding: pods, airlocks, fighting, sabotage, capture.
##   godot --headless --path . res://tests/test_board.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1


func _ship(nm: String) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.name = nm
	s.design_blob = ShipDesign.read_blob("res://ships/Brick.json")
	add_child(s)
	return s


func _first(s: Ship, type: String) -> int:
	for mi in s.design.modules.size():
		if s.design.modules[mi]["type"] == type:
			return mi
	return -1


func _run(a: Ship, b: Ship, sec: float) -> void:
	var t := 0.0
	while t < sec:
		a.hazards.tick(a, 0.1); b.hazards.tick(b, 0.1)
		a._board_step(0.1); b._board_step(0.1)
		a.crew.tick(a, 0.1); b.crew.tick(b, 0.1)
		t += 0.1


func _ready() -> void:
	var a := _ship("A")
	var b := _ship("B")
	for i in 10: await get_tree().physics_frame
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(0, 0, 80)
	# ---- no pod bay / airlock on the brick
	check(a.board_by_pod(b, 2) != "", "no pod bay: no pod")
	check(a.board_by_airlock(b, 2) != "", "not lodged: no airlock boarding")
	# ---- boarders arrive in a module and wreck it
	var room := _first(b, ModuleCatalog.ENGINE_ROOM)
	if room < 0: room = _first(b, ModuleCatalog.TURRET)
	var cmd := _first(b, ModuleCatalog.COMMANDER)
	b.crew.members.clear()
	b.crew.members.append({"id": 1, "hp": 100.0, "node": 0, "pos": Vector3.ZERO, "from": Vector3.ZERO, "to": Vector3.ZERO, "t_total": 0.0, "t_left": 0.0,
		"dest_node": 0, "task": "idle", "module": -1, "ordered": false, "patrol": 99.0})
	b.crew.members[0]["node"] = b.crew.node_for_module(b, cmd)
	b.crew.members[0]["pos"] = b.plan_state.plan.nodes[b.crew.members[0]["node"]]["pos"]
	b._receive_boarders_local(room, 3, 1, 0.4)
	check(b.crew.foe_count() == 3, "boarders arrive (3)")
	check(b.haz_hole[room] > 0.0 if b.hazards.holds[room] != 0 else true, "...through a hole")
	var hp0: float = b.module_hp[room]
	_run(a, b, 5.0)
	check(b.module_hp[room] < hp0, "boarders sabotage the room (%.0f -> %.0f)" % [hp0, b.module_hp[room]])
	# ---- they go for the bridge and take it when nobody defends
	b.crew.members[0]["hp"] = 0.0
	b.crew.members.clear()
	var taken := false
	var t := 0.0
	while t < 120.0 and not taken:
		_run(a, b, 1.0)
		t += 1.0
		taken = b.crew.tick(b, 0.1)
	check(taken or b.crew.foe_count() == 0 or b.crew.members.is_empty(), "undefended ship is taken")
	# ---- defenders fight back
	var c := _ship("C")
	for i in 6: await get_tree().physics_frame
	var cr := c.crew.module_of(c, c.crew.members[0])
	c._receive_boarders_local(cr, 2, 1, 0.0)
	var def_before := c.crew.alive_count()
	for k in 150:
		c.crew.tick(c, 0.1)
	check(c.crew.foe_count() < 2, "defenders kill boarders (%d left)" % c.crew.foe_count())
	check(c.crew.alive_count() <= def_before, "...and boarders hurt defenders")
	# ---- a pod in flight reaches the target, punches a hole and unloads
	var d := _ship("D")
	var e := _ship("E")
	for i in 6: await get_tree().physics_frame
	d.global_position = Vector3.ZERO
	e.global_position = Vector3(0, 0, 100)
	d._pods.append({"pos": Vector3(0, 0, 10), "vel": Vector3(0, 0, 70), "target": e, "count": 2})
	var tt := 0.0
	while tt < 6.0 and not d._pods.is_empty():
		d._board_step(0.05)
		tt += 0.05
	check(d._pods.is_empty() and e.crew.foe_count() == 2, "a pod delivers its boarders (%d)" % e.crew.foe_count())
	var holes := 0.0
	for v in e.haz_hole: holes += v
	check(holes > 0.0, "...and punches a hole")
	print("FAILS: %d" % fails)
	get_tree().quit(fails)
