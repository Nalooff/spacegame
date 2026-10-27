extends Node
## Radar / detection / lead prediction / multi-barrel turrets / beams / stations.
## Run: godot --headless res://tests/test_combat.tscn
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _ready() -> void:
	await get_tree().process_frame
	_test_ballistics()
	_test_teams()
	_test_touching()
	_test_exhaust_shape()
	_test_turret_goal()
	await _test_detection()
	await _test_beam()
	await _test_stations()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(1 if fails else 0)

func _ship(file: String, pos: Vector3) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/%s.json" % file)
	s.position = pos
	add_child(s)
	return s

## A turret with a limited arc must aim at the closest reachable direction, and keep firing there.
func _test_turret_goal() -> void:
	print("turret reachable aim")
	var tur := ShipTurrets.new()
	var r := ShipTurrets.Rig.new()
	r.fwd0 = Vector3(0, 0, -1)
	r.up = Vector3.UP
	r.right = r.fwd0.cross(r.up).normalized()
	r.yaw_min = deg_to_rad(-60.0)
	r.yaw_max = deg_to_rad(60.0)
	r.pitch_min = deg_to_rad(-10.0)
	r.pitch_max = deg_to_rad(70.0)
	var t := (Vector3(0, 0, -1)).normalized()
	var g := tur._best_reachable(r, t)
	check(absf(g.x) < 0.01 and absf(g.y) < 0.01, "target dead ahead -> no turn")
	t = (Vector3(-1, 0.2, -0.2)).normalized()          # left(+yaw), well inside the arc once the arc is wide enough
	r.yaw_max = deg_to_rad(120.0)
	g = tur._best_reachable(r, t)
	check(tur.direction(r, g.x, g.y).angle_to(t) < 0.01, "target inside the arc is hit exactly")
	r.yaw_max = deg_to_rad(60.0)
	t = (Vector3(-1, 0.0, 0.5)).normalized()           # behind-left: outside the arc
	g = tur._best_reachable(r, t)
	check(absf(g.x - deg_to_rad(60.0)) < 0.05, "target outside the arc -> the barrel goes to the arc's edge (%.0f deg)" % rad_to_deg(g.x))
	var best := 9.0
	for yy in range(-60, 61, 2):
		for pp in range(-10, 71, 2):
			best = minf(best, tur.direction(r, deg_to_rad(yy), deg_to_rad(pp)).angle_to(t))
	check(tur.direction(r, g.x, g.y).angle_to(t) <= best + 0.03, "...and it is the closest direction the arc allows")
	tur.free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _test_ballistics() -> void:
	print("lead prediction")
	var shooter := Vector3(0, 0, 0)
	var sv := Vector3(5, 0, 0)
	var tp := Vector3(1000, 0, 0)
	var tv := Vector3(0, 0, 60)
	var speed := 260.0
	var aim := Ballistics.intercept(shooter, sv, tp, tv, speed)
	var dir := (aim - shooter).normalized()
	# fly the bullet and the target for the time at which the bullet is closest
	var best := 1e9
	for i in 600:
		var t := i * 0.01
		var bullet := shooter + (sv + dir * speed) * t
		best = minf(best, bullet.distance_to(tp + tv * t))
	check(best < 1.0, "bullet meets the moving target (closest approach %.2f m)" % best)
	var naive := (tp - shooter).normalized()
	var best2 := 1e9
	for i in 600:
		var t := i * 0.01
		best2 = minf(best2, (shooter + (sv + naive * speed) * t).distance_to(tp + tv * t))
	check(best2 > 20.0, "without lead it misses by %.0f m" % best2)
	var run_away := Ballistics.intercept(shooter, Vector3.ZERO, tp, Vector3(400, 0, 0), speed)
	check(run_away == tp, "a target faster than the bullet: aim at it")

func _test_teams() -> void:
	print("teams")
	Net.players = {1: {"team": 1, "crew_of": 0}, 2: {"team": 1, "crew_of": 0}, 3: {"team": 0, "crew_of": 0}, 4: {"team": 0, "crew_of": 1}}
	check(Net.are_friends(1, 2), "same team is friendly")
	check(not Net.are_friends(1, 3), "other team is an enemy")
	check(not Net.are_friends(3, 3 + 100), "unknown peer is an enemy")
	check(Net.are_friends(4, 1), "crew counts as their captain")
	Net.players = {}

func _test_touching() -> void:
	print("barrels touch the base or are stuck")
	var d := ShipDesign.new()
	var base := d.add_module(ModuleCatalog.TURRET, "dome", Vector3.ZERO, Vector3(1, 1, 1))
	var near := d.add_module(ModuleCatalog.BARREL, "cylinder", Vector3(0, 0.5, -1.0), Vector3(0.2, 0.2, 1.0))
	var far := d.add_module(ModuleCatalog.BARREL, "cylinder", Vector3(8, 0.5, -1.0), Vector3(0.2, 0.2, 1.0))
	check(ShipTurrets._touching(d, base, near), "barrel overlapping the base pivots")
	check(not ShipTurrets._touching(d, base, far), "barrel far from the base is stuck")

func _test_exhaust_shape() -> void:
	print("exhaust zone follows the nozzle")
	var d := ShipDesign.new()
	var t := d.add_module(ModuleCatalog.THRUSTER, "cylinder", Vector3.ZERO, Vector3(3, 1, 3), 12)
	d.modules[t]["dir"] = Vector3(0, 1, 0)           # pushes up, the exhaust goes down
	var wide := ExhaustZone.zone(d, t)
	check(ExhaustZone.contains(wide, Vector3(2.5, -3.0, 0)), "wide nozzle blocks a wide tube")
	for i in d.vertices.size():                       # big engine, small nozzle (a funnel)
		if d.vertices[i].y < -0.9:
			d.vertices[i] = Vector3(d.vertices[i].x * 0.1, d.vertices[i].y, d.vertices[i].z * 0.1)
	var narrow := ExhaustZone.zone(d, t)
	check(not ExhaustZone.contains(narrow, Vector3(2.5, -3.0, 0)), "small nozzle: the space beside it is free")
	check(ExhaustZone.contains(narrow, Vector3(0, -3.0, 0)), "...but straight behind it is blocked")
	check(not ExhaustZone.contains(narrow, Vector3(0.0, -3.0, 1.5)), "tube does not widen like a cone")

func _test_detection() -> void:
	print("detection and radar")
	var me := _ship("Brick", Vector3.ZERO)
	var dart := _ship("Dart", Vector3(0, 0, -800))
	await _frames(3)
	me.detection.scan()
	check(me.detection.contacts.size() == 1 and me.detection.contacts[0]["how"] == "view", "ship within view range is seen by eye")
	check(dart.visible, "...and rendered")
	dart.global_position = Vector3(0, 0, -6500)
	dart.sig_elec = 0.0
	me.detection.scan()
	check(me.detection.contacts.is_empty(), "far, quiet ship is not detected")
	check(not dart.visible, "...and not rendered beyond the view range")
	var radars := me.detection.working_radars()
	check(radars.size() == 1 and radars[0]["kind"] == "electronic", "Brick has an electronic radar (range %.0f m)" % float(radars[0]["range"]))
	dart.global_position = Vector3(0, 0, -4800)
	dart.sig_elec = 600000.0          # the Dart uses a lot of electricity: visible from much farther
	me.detection.scan()
	var range_loud := me.detection.radar_range(radars[0], dart)
	check(range_loud > 5000.0, "loud ship radar range %.0f m" % range_loud)
	check(me.detection.contacts.size() == 1 and me.detection.contacts[0]["how"] == "electronic", "loud ship is detected by the electronic radar")
	check(me.detection.contacts[0]["precision"] > 0.0 and me.detection.contacts[0]["precision"] < Data.VIEW_PRECISION, "radar contact has a precision factor (%.2f)" % me.detection.contacts[0]["precision"])
	dart.sig_elec = 1000.0
	check(me.detection.radar_range(radars[0], dart) < range_loud * 0.2, "a quiet ship is seen from far less")
	# thermal: the Scrap Hauler has a thermal radar; heat decides
	var scrap := _ship("Scrap Hauler", Vector3(3000, 0, 0))
	await _frames(3)
	dart.global_position = Vector3(3000, 0, -3000)
	dart.sig_heat = 4.0e6
	scrap.detection.scan()
	var found_heat := false
	for c in scrap.detection.contacts:
		if c["ship"] == dart and c["how"] == "thermal":
			found_heat = true
	check(found_heat, "hot ship is detected by the thermal radar")
	dart.sig_heat = 10000.0
	scrap.detection.scan()
	check(scrap.detection.find_contact(dart).is_empty(), "a cold ship is not")
	# lock + lead
	dart.global_position = Vector3(0, 0, -600)
	dart.linear_velocity = Vector3(40, 0, 0)
	me.stations.mode = "crew"      # commander view auto-locks; test the manual lock
	me.detection.locked = null
	me.detection.scan()
	me.detection.cycle_lock()
	check(me.detection.locked == dart, "R locks the nearest enemy")
	var lead := me.detection.lead_point(260.0)
	check(lead.x > dart.global_position.x + 20.0, "aim point is ahead of the moving target (x %.0f vs %.0f)" % [lead.x, dart.global_position.x])
	check(me.electricity.full_demand_w > 0.0 and me.electricity.passive > 0.0, "electricity knows radar / commander passive use (%.0f W)" % me.electricity.passive)
	for s in [me, dart, scrap]:
		s.queue_free()
	await _frames(2)

func _test_beam() -> void:
	print("beam penetration")
	var pool := ProjectilePool.new()
	pool.name = "ProjectilePool"
	add_child(pool)
	var target := _ship("Brick", Vector3.ZERO)
	await _frames(3)
	target.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	await _frames(2)
	var hp0 := target.module_hp.duplicate()
	pool.fire_beam(Vector3(0.3, 0.2, -80.0), Vector3(0, 0, 1), 400.0, 1.0, 200.0, null)
	await _frames(2)
	var thin := 0
	for i in hp0.size():
		if target.module_hp[i] < hp0[i]:
			thin += 1
	var hp1 := target.module_hp.duplicate()
	pool.fire_beam(Vector3(0.3, 0.2, -80.0), Vector3(0, 0, 1), 400.0, 40.0, 200.0, null)
	await _frames(2)
	var deep := 0
	for i in hp1.size():
		if target.module_hp[i] < hp1[i]:
			deep += 1
	check(thin == 1, "a weak beam damages only the first module (%d)" % thin)
	check(deep > thin, "a penetrating beam goes through several modules (%d)" % deep)
	pool.queue_free()
	target.queue_free()
	await _frames(2)

func _test_stations() -> void:
	print("control modes and stations")
	var s := _ship("Brick", Vector3.ZERO)
	await _frames(3)
	var st := s.stations
	check(st.stations.size() == 4, "Brick: 1 pilot seat + 3 gun stations (%d)" % st.stations.size())
	check(st.mode == "commander", "a ship starts in COMMANDER view")
	st.toggle_mode()
	check(st.mode == "crew" and st.can_fly() and st.active_base() == -1, "crew mode: in the pilot seat, flying, no linked turret")
	var t := st.travel_time(1)
	check(t > 0.5, "walking to another station takes time (%.1f s)" % t)
	st.go_to(1)
	check(st.walking and not st.can_fly(), "cannot fly while walking")
	await _frames(int(t * 60.0) + 20)
	check(not st.walking and st.current == 1 and st.current_station()["kind"] == "gun", "arrived at the gun station")
	check(st.active_base() == int(st.current_station()["module"]) and not st.can_fly(), "gun station: only that turret, cannot fly")
	st.toggle_mode()
	check(st.is_commander_mode() and st.active_base() == -2 and not st.can_fly(), "commander mode: automatic, all guns, no manual flight")
	st.toggle_mode()
	# link a turret to the commander: the pilot seat can fire it
	var d := s.design
	var base := -1
	for m in d.modules.size():
		if d.modules[m]["type"] == ModuleCatalog.TURRET:
			base = m
	d.toggle_link(d.commander_modules()[0], base)
	st.current = 0
	st.walking = false
	check(st.active_base() == base, "a turret linked to the commander can be fired from the pilot seat")
	s.queue_free()
