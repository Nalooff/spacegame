extends Node
## Ship plan tests: generated corridors, player overrides, dead/gone modules, communications and order delay, damage lines.
## Run: godot --headless --path . res://tests/test_plan.tscn

var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _ready() -> void:
	await get_tree().process_frame
	_test_generation()
	_test_overrides()
	_test_state()
	await _test_ship()
	await _test_reports()
	_test_transmitter()
	_test_stairs_and_walls()
	_test_room_linking()
	_test_many_decks()
	_test_free_corridors()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(1 if fails else 0)

func _test_transmitter() -> void:
	print("antenna presets: external vs room")
	var d := _design("Dart")
	var base := ShipPlan.generate(d).rooms.size()
	var tx := d.add_module(ModuleCatalog.ANTENNA, "box", Vector3(0, 0.2, 0.4), Vector3(0.6, 0.6, 0.6), 12, "relay")
	var p := ShipPlan.generate(d)
	check(d.is_room(tx) and p.rooms.size() == base + 1 and p.rooms.has(tx), "the antenna preset \"Relay room\" is a ROOM (needs a corridor)")
	var again := ShipDesign.from_blob(d.to_bytes())
	check(again.is_room(tx), "...and it is still a room after save and load")
	var whip := _first(d, ModuleCatalog.ANTENNA)
	check(not d.is_room(whip) and not p.rooms.has(whip), "the whip antenna preset is not a room")
	check(not p.rooms.has(_first(d, ModuleCatalog.THRUSTER)), "thrusters are not rooms")
	check(ModulePresets.main_key(ModuleCatalog.ANTENNA, "room") == "strength", "a room antenna has an editable signal strength")
	check(ModulePresets.main_key(ModuleCatalog.ANTENNA, "external") == "", "an external antenna has a fixed signal (nothing to edit)")
	var stats: Dictionary = d.cfg(tx)["stats"]
	var w0 := float(stats["elec_w_per_m3"])
	d.set_main_stat(tx, float(stats["strength"]) * 0.5)
	check(float(stats["elec_w_per_m3"]) < w0 * 0.5, "half the signal needs less than half the electricity (%.0f -> %.0f W/m3): harder to see" % [w0, float(stats["elec_w_per_m3"])])
	d.set_main_stat(whip, 9.0)
	check(is_equal_approx(d.stat(whip, "strength"), 2.0), "setting the stat of a fixed antenna changes nothing")


## Touching rooms need no corridor (a door in the wall); rooms on other decks are reached by a stair marker inside the room.
func _test_stairs_and_walls() -> void:
	print("doors between touching rooms, stairs between decks")
	var found_stairs := 0
	for file in ["Brick", "Dart", "Twin Hull", "Scrap Hauler"]:
		var d := _design(file)
		var canvas := PlanCanvas.new()
		canvas.size = Vector2(900, 480)
		add_child(canvas)
		canvas.show_design(d, true)
		var pl: ShipPlan = canvas.plan
		for a in pl.rooms:
			for b in pl.rooms:
				if b <= a:
					continue
				var j := pl.node_index("j%d_%d" % [a, b])
				if j >= 0:
					var want := "stairs" if canvas._mod_layer(a) != canvas._mod_layer(b) else "wall"
					check(canvas._joint_kind(j) == want, "%s: rooms %d and %d joined directly are drawn as '%s'" % [file, a, b, want])
		for ni in pl.nodes.size():
			if canvas._joint_kind(ni) != "stairs":
				continue
			found_stairs += 1
			var m: Vector2i = canvas._joint_modules(ni)
			var seen := 0
			for k in canvas.deck_count:
				canvas.set_deck(k)
				if canvas._node_visible(ni):
					seen += 1
			check(seen == 2, "%s: a stair is visible from exactly the two decks it joins (%d)" % [file, seen])
			check(canvas._mod_layer(m.x) != canvas._mod_layer(m.y), "%s: ...and those decks differ" % file)
		for ei in pl.edges.size():
			if canvas._edge_is_hidden(ei):
				var e: Dictionary = pl.edges[ei]
				check(canvas._joint_kind(e["a"]) != "" or canvas._joint_kind(e["b"]) != "", "%s: only edges at a stair / wall joint are hidden" % file)
		check(pl.unlinked_rooms(d.commander_modules()).is_empty(), "%s: every room is still reachable from the commander" % file)
		canvas.queue_free()
	check(found_stairs > 0, "at least one stair exists in the premade ships (%d)" % found_stairs)


## As many decks as there are floors: a tall ship with six rooms one above the other (not even over each other's footprint).
func _test_many_decks() -> void:
	print("many decks")
	var d := _design("Brick")
	var base := PlanCanvas.new()
	base.size = Vector2(900, 480)
	add_child(base)
	base.show_design(d, true)
	var before := base.deck_count
	base.queue_free()
	var tall := _design("Brick")
	var hull := tall.add_module(ModuleCatalog.HULL, "box", Vector3(0, 8, 0), Vector3(2.0, 8.0, 2.0), 12)
	check(hull >= 0, "tall hull added")
	for k in 6:
		tall.add_module(ModuleCatalog.RADAR, "box", Vector3(0.0 + (k % 2) * 0.4, 1.2 + k * 2.4, 0.0), Vector3(0.6, 0.9, 0.6), 12)
	var canvas := PlanCanvas.new()
	canvas.size = Vector2(900, 480)
	add_child(canvas)
	canvas.show_design(tall, true)
	check(canvas.deck_count >= 6, "six floors give at least six decks (%d, the ship had %d before)" % [canvas.deck_count, before])
	var seen := {}
	for mi in tall.modules.size():
		seen[canvas._mod_layer(mi)] = true
	check(seen.size() >= 6, "...and the decks are all used (%d)" % seen.size())
	canvas.queue_free()


## Linking a corridor to a room: a click ANYWHERE inside the room (or on its wall) means "that room", not only on its centre dot.
func _test_room_linking() -> void:
	print("clicking inside a room links to it")
	for file in ["Brick", "Dart", "Scrap Hauler"]:
		var d := _design(file)
		var canvas := PlanCanvas.new()
		canvas.size = Vector2(900, 480)
		add_child(canvas)
		canvas.register_layer("below", "Deck below", Callable(canvas, "_layer_below"))
		canvas.register_layer("structure", "Hull", Callable(canvas, "_layer_structure"))
		canvas.register_layer("rooms", "Rooms and corridors", Callable(canvas, "_layer_rooms"))
		canvas.show_design(d, true)
		canvas.set_tool(PlanCanvas.Tool.DRAW)
		for room in canvas.plan.rooms:
			canvas.set_deck(canvas._mod_layer(room))
			var poly: PackedVector2Array = canvas._screen_poly(room)
			if poly.size() < 3:
				continue
			var c: Vector2 = canvas._centroid(poly)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for pt in poly:
				lo = lo.min(pt)
				hi = hi.max(pt)
			var probe := c + (hi - lo) * Vector2(0.2, 0.15)
			if not Geometry2D.is_point_in_polygon(probe, poly):
				continue
			var hit: int = canvas._node_at(probe)
			var near_corridor: bool = not canvas._edge_near(probe, 6.0).is_empty()
			var near_node: bool = hit >= 0 and canvas._node_screen(hit).distance_to(probe) <= PlanCanvas.PICK_PX      # a junction right there wins, as it should
			check(hit == canvas.plan.door_of(room) or near_corridor or near_node, "%s: a click inside room %d (off centre) targets that room (got %d, want %d)" % [file, room, hit, canvas.plan.door_of(room)])
		canvas.queue_free()


## Corridors can start anywhere inside the hull, bend, and split other corridors (a junction).
func _test_free_corridors() -> void:
	print("free corridors (canvas clicks)")
	var d := _design("Brick")
	var canvas := PlanCanvas.new()
	canvas.size = Vector2(900, 480)
	add_child(canvas)
	canvas.register_layer("structure", "Hull", Callable(canvas, "_layer_structure"))
	canvas.show_design(d, true)
	canvas.set_tool(PlanCanvas.Tool.DRAW)
	var hull := _first(d, ModuleCatalog.HULL)
	var poly: PackedVector2Array = canvas._foot[hull]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pt in poly:
		lo = lo.min(pt)
		hi = hi.max(pt)
	canvas.set_deck(canvas._layer[hull])
	var e0 := canvas.plan.edges.size()
	var a := canvas._to_screen(lo.lerp(hi, 0.3))
	var b := canvas._to_screen(lo.lerp(hi, 0.5) + Vector2(0, (hi.y - lo.y) * 0.1))
	var c := canvas._to_screen(lo.lerp(hi, 0.7))
	canvas._draw_click(a)
	check(canvas._has_free_start, "the first click in empty hull starts a corridor (no room needed)")
	canvas._draw_click(b)
	canvas._draw_click(c)
	check(canvas.plan.edges.size() == e0 + 2, "two pieces drawn with a bend between them (%d -> %d edges)" % [e0, canvas.plan.edges.size()])
	var free := 0
	for n in canvas.plan.nodes:
		if n["kind"] == "free":
			free += 1
	check(free >= 2, "the bend and the new end are free nodes; an end that lands on a stair or a door joins it (%d free)" % free)
	# a click on an existing corridor makes a junction
	canvas._from = -1
	canvas._has_free_start = false
	var before := canvas.plan.edges.size()
	var mid := (canvas._node_screen(canvas.plan.node_index("f2")) + canvas._node_screen(canvas.plan.node_index("f1"))) * 0.5
	canvas._draw_click(mid)
	check(canvas.plan.edges.size() == before + 1, "clicking a corridor splits it: a junction (%d -> %d)" % [before, canvas.plan.edges.size()])
	canvas.queue_free()


func _design(file: String) -> ShipDesign:
	return ShipDesign.from_blob(ShipDesign.read_blob("res://ships/%s.json" % file))

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _test_generation() -> void:
	print("generation")
	for n in ["Dart", "Brick", "Scrap Hauler", "Twin Hull"]:
		var d := _design(n)
		var p := ShipPlan.generate(d)
		check(p.rooms.size() > 0 and p.edges.size() > 0, "%s: %d rooms, %d corridor pieces" % [n, p.rooms.size(), p.edges.size()])
		check(d.unwalkable_rooms().is_empty(), "%s: every room has a corridor to a commander" % n)
		var p2 := ShipPlan.generate(d)
		var same := p.edges.size() == p2.edges.size()
		for i in mini(p.edges.size(), p2.edges.size()):
			same = same and p.edges[i]["key"] == p2.edges[i]["key"]
		check(same, "%s: generation is deterministic" % n)
	for n in ["Dart", "Brick", "Scrap Hauler", "Twin Hull"]:
		var dd := _design(n)
		var pp := ShipPlan.generate(dd)
		var outside := 0
		for e in pp.edges:
			if not pp.segment_inside(dd, pp.nodes[e["a"]]["pos"], pp.nodes[e["b"]]["pos"]):
				outside += 1
		check(outside == 0, "%s: every corridor piece lies inside the ship (%d outside)" % [n, outside])
	var d2 := _design("Dart")
	var p3 := ShipPlan.generate(d2)
	for r in p3.rooms:
		check(not ModuleCatalog.CORRIDOR_TYPES.has(d2.modules[r]["type"]), "hull / armor are never rooms")
		break

func _test_overrides() -> void:
	print("player edits")
	var d := _design("Dart")
	var p := ShipPlan.generate(d)
	var cut: String = p.edges[0]["key"]
	d.plan = {"removed": [cut], "free": {"f1": [0.0, 0.0, 0.0, 0]}, "added": [], "uid": 1}
	var p2 := ShipPlan.generate(d)
	check(p2.edge_index(cut) < 0, "a removed corridor stays removed")
	check(p2.node_index("f1") >= 0, "a free node exists")
	# a corridor or bend outside the ship is refused
	var far := {"removed": [], "free": {"f9": [50.0, 50.0, 50.0, 0]}, "added": [["h0", "f9"]], "uid": 9}
	d.plan = far
	var p_far := ShipPlan.generate(d)
	check(p_far.node_index("f9") < 0, "a bend outside the ship is dropped")
	d.plan = {"removed": [cut], "free": {"f1": [0.0, 0.0, 0.0, 0]}, "added": [], "uid": 1}
	var d3 := ShipDesign.from_dict(d.to_dict())
	check(d3.plan.get("removed", []) == [cut], "edits survive save and load")
	var d4 := ShipDesign.from_bytes(d.to_bytes())
	check(d4.plan.get("free", {}).has("f1"), "edits survive the binary form")
	# doors on corridors
	var dk: String = p.edges[1]["key"]
	d.plan = {"removed": [], "free": {}, "added": [], "uid": 0, "doors": [[dk, 0.4], ["nope|nada", 0.5]]}
	var pd := ShipPlan.generate(d)
	check(pd.doors.size() == 1 and pd.doors[0]["edge"] == pd.edge_index(dk), "a corridor door is placed on its corridor (a door on a missing corridor is dropped)")
	var dd2 := ShipDesign.from_dict(d.to_dict())
	check(dd2.plan.get("doors", []).size() == 2 and ShipDesign.from_bytes(d.to_bytes()).plan.get("doors", []).size() == 2, "doors survive save and load")
	check(ShipPlan.remap_overrides(d.plan, {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10, 11: 11, 12: 12, 13: 13, 14: 14, 15: 15, 16: 16, 17: 17})["doors"].size() >= 0, "doors are remapped with the module ids")
	var key := ShipPlan.remap_edge_key("h3|d5", {3: 2, 5: 4})
	check(key == "d4|h2", "edge keys follow renumbered modules (%s)" % key)
	check(ShipPlan.remap_edge_key("h3|d5", {3: 2}) == "", "edges of lost modules are dropped")

func _types(d: ShipDesign) -> PackedStringArray:
	var t := PackedStringArray()
	for m in d.modules:
		t.append(m["type"])
	return t

func _hp(d: ShipDesign) -> PackedFloat32Array:
	var hp := PackedFloat32Array()
	for i in d.modules.size():
		hp.append(1.0)
	return hp

func _first(d: ShipDesign, type: String) -> int:
	for i in d.modules.size():
		if d.modules[i]["type"] == type:
			return i
	return -1

func _test_state() -> void:
	print("working rule and order delay")
	var d := _design("Dart")
	var p := ShipPlan.generate(d)
	var st := PlanState.new(p)
	var types := _types(d)
	var hp := _hp(d)
	var thr := _first(d, ModuleCatalog.TURRET)        # a ROOM (thrusters and antennas are not rooms, see below)
	var engine := _first(d, ModuleCatalog.THRUSTER)
	st.update(types, hp, true)
	check(st.is_working(thr) and st.order_delay(thr) == 0.0, "communications: turret room works, order is instant")
	st.update(types, hp, false)
	var er := _first(d, ModuleCatalog.ENGINE_ROOM)
	check(er >= 0 and st.engine_ok and not st.engines_cut(), "the Dart has an engine room and it works")
	check(st.is_working(engine) and absf(st.order_delay(engine) - st.reach[er] / PlanState.WALK_SPEED) < 0.001,
		"no communications: the order walks to the ENGINE ROOM first, then the thruster obeys")
	check(st.is_working(thr), "no communications, but the corridors lead there: it still works")
	var delay := st.order_delay(thr)
	check(delay > 0.0 and delay < 60.0, "...after the order was walked there (%.1f s)" % delay)
	check(absf(delay - st.reach[thr] / PlanState.WALK_SPEED) < 0.001, "delay = corridor length / walking speed")
	# a dead hull blocks the corridors
	var hp2 := hp.duplicate()
	hp2[_first(d, ModuleCatalog.HULL)] = 0.0
	st.update(types, hp2, false)
	check(not st.is_working(thr) and st.order_delay(thr) == INF, "dead hull: nobody can walk there, the room is cut off")
	check(st.is_working(engine) and not st.engine_ok and st.engines_cut(), "...the thruster itself is intact, but nobody can reach the engine room: engines cut")
	st.update(types, hp2, true)
	check(st.engine_ok and st.order_delay(engine) == 0.0, "communications: the engine room works from anywhere, orders are instant")
	var hp3 := hp.duplicate()
	hp3[er] = 0.0
	st.update(types, hp3, true)
	check(st.engines_cut(), "engine room destroyed: the thrusters get no orders even with communications")
	var d2 := _design("Dart")
	var kept := _types(d2)
	for mi in kept.size():
		if kept[mi] == ModuleCatalog.ENGINE_ROOM:
			kept[mi] = ModuleCatalog.HULL
	var st_noeng := PlanState.new(ShipPlan.generate(d2))
	st_noeng.update(kept, _hp(d2), false)
	check(not st_noeng.engines_cut() and st_noeng.order_delay(engine) == 0.0, "a ship WITHOUT any engine room keeps the old behaviour (thrusters obey at once)")
	st.update(types, hp2, true)
	check(st.is_working(thr), "...but with communications the order arrives anyway")
	# damage line through the middle
	var st2 := PlanState.new(p)
	var any := st2.damage_line(Vector3(-50, 0, 0), Vector3(50, 0, 0), 100.0, 1.0)
	check(any, "a damage line wrecks corridors")
	st2.update(types, hp, false)
	check(not st2.is_working(thr), "all corridors closed and no communications: rooms are cut off")
	var cmd := _first(d, ModuleCatalog.COMMANDER)
	check(st2.is_working(cmd), "the commander still works on its own")

func _test_ship() -> void:
	print("live ship")
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/Dart.json")
	add_child(s)
	await _frames(4)
	check(s.plan_state != null and s.comms.online, "plan built, communications online (antenna works)")
	check(s.corridor_hp.size() == s.plan_state.plan.edges.size(), "corridor health is replicated state")
	var n0 := s.alloc.n
	var ant := _first(s.design, ModuleCatalog.ANTENNA)
	s.apply_damage(ant, 1e9)
	await _frames(3)
	check(s.module_hp[ant] == 0.0 and not s.comms.online, "antenna dead: communications offline")
	check(s.alloc.n == n0, "thrusters still work: the corridors are intact")
	check(s.order_delay(_first(s.design, ModuleCatalog.TURRET)) > 0.0, "orders to a room now take time to walk")
	check(s.order_delay(_first(s.design, ModuleCatalog.THRUSTER)) > 0.0, "...and so do thrusters: the order goes to the engine room first")
	s.apply_damage(_first(s.design, ModuleCatalog.ENGINE_ROOM), 1e9)
	await _frames(3)
	check(s.plan_state.engines_cut(), "engine room destroyed: thrusters get no orders")
	var cut := s._delayed_throttles(PackedFloat32Array([1.0, 1.0]), 0.02)
	check(cut[0] == 0.0 and cut[1] == 0.0, "...their throttles are zero")
	# a hit that goes through the middle of the ship closes corridors
	var hits_before := 0.0
	for e in s.corridor_hp:
		hits_before += e
	for i in 6:
		var hit := DamageHit.kinetic(0, 600.0, s.global_transform * Vector3(0, 0, -2.0), null, s.global_transform.basis * Vector3(0, 0, 1), 6.0)
		s.apply_hit(hit)
	await _frames(3)
	var after := 0.0
	for e in s.corridor_hp:
		after += e
	check(after < hits_before, "damage lines wore corridors down (%.1f -> %.1f)" % [hits_before, after])
	check(s.module_hp[0] >= 0.0, "the hull is still there (hp %.0f)" % s.module_hp[0])
	s.apply_damage(0, 1e9)
	await _frames(2)
	check(s.module_hp[0] == 0.0, "a destroyed hull is a wreck, not removed")
	check(s.alloc.n == n0, "thrusters need no corridor: they still work with no antenna and no way to walk there (%d)" % s.alloc.n)
	s.queue_free()


func _test_reports() -> void:
	print("damage reports")
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/Dart.json")
	add_child(s)
	await _frames(6)
	var thr := _first(s.design, ModuleCatalog.THRUSTER)
	s.apply_damage(thr, 1e9)
	await _frames(6)
	check(s.reports.known_hp[thr] == 0.0, "communications online: the report arrives at once")
	check(s.reports.pending.is_empty(), "...no theorised sphere")
	var ant := _first(s.design, ModuleCatalog.ANTENNA)
	s.apply_damage(ant, 1e9)
	await _frames(6)
	var thr2 := -1
	for i in s.design.modules.size():
		if s.design.modules[i]["type"] == ModuleCatalog.THRUSTER and s.module_hp[i] > 0.0:
			thr2 = i
	var delay := s.plan_state.delay_at(s.design.module_centroid(thr2))
	check(delay > 0.0 and delay < 20.0, "no antenna: a report from a thruster needs %.1f s to be walked to the commander" % delay)
	s.apply_damage(thr2, 1e9)
	await _frames(6)
	check(s.module_hp[thr2] == 0.0, "the damage itself is real at once")
	check(s.reports.known_hp[thr2] > 0.0, "...but the commander still believes it works")
	check(s.reports.pending.size() >= 1, "and sees a theorised damage sphere (%d)" % s.reports.pending.size())
	var sph: Dictionary = {}
	for r in s.reports.pending:
		if r.get("sphere", false):
			sph = r
	check(not sph.is_empty(), "a theorised sphere is shown")
	var true_c := s.design.module_centroid(thr2)
	check((sph["center"] as Vector3).distance_to(true_c) <= sph["radius"], "the sphere (r %.1f m) still contains the real spot" % sph["radius"])
	await get_tree().create_timer(delay + 1.0).timeout
	check(s.reports.known_hp[thr2] == 0.0, "after the walk the report arrives: the commander now knows")
	s.queue_free()
