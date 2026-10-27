extends Node
## Runtime structure tests: cut-off modules, loss of mass / thrusters, commander death, crush rule, and the split of a
## two-commander ship into two ships (offline: the "world" is the real game_world.tscn with an offline peer).
## Run: godot --headless res://tests/test_structure.tscn

const NetClass := preload("res://scripts/autoload/net.gd")
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _ready() -> void:
	await get_tree().process_frame
	await _test_cutoff()
	await _test_commander_death()
	await _test_crush()
	await _test_split()
	_test_seats()
	await _test_links()
	await _test_turrets()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(1 if fails else 0)

func _ship(file: String) -> Ship:
	var s: Ship = load("res://scenes/ship.tscn").instantiate()
	s.design_blob = ShipDesign.read_blob("res://ships/%s.json" % file)
	add_child(s)
	return s

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _test_cutoff() -> void:
	print("dead vs gone modules")
	var s := _ship("Dart")
	await _frames(3)
	var m0 := s.mass
	var thr0 := s.alloc.n
	# the hull (module 0) is the only thing that links everything to the commander (module 1)
	s.apply_damage(0, 1e9)
	await _frames(3)
	check(s.module_hp[0] == 0.0, "destroyed hull is a DEAD wreck (hp 0), not removed")
	var gone := 0
	for i in s.module_hp.size():
		if s.module_hp[i] < 0.0:
			gone += 1
	check(gone == 0, "nothing is gone: the wreck still holds the ship together")
	check(absf(s.mass - m0) < m0 * 0.02, "the wreck keeps its mass %.0f -> %.0f" % [m0, s.mass])
	check(s.alive, "ship still alive")
	check(s.alloc.n == thr0, "the antenna still carries the orders: thrusters keep working (%d)" % s.alloc.n)
	for mi in s.design.modules.size():
		if s.design.modules[mi]["type"] == ModuleCatalog.ANTENNA:
			s.apply_damage(mi, 1e9)
	await _frames(3)
	check(s.alloc.n == thr0 and thr0 > 0, "antenna dead too, no corridor: thrusters are not rooms and keep working (%d -> %d)" % [thr0, s.alloc.n])
	# only when NOTHING links the others to the commander any more are they detached
	var hp := s.module_hp
	hp[0] = -1.0
	s.module_hp = hp
	s._structure_dirty = true
	await _frames(3)
	gone = 0
	for i in s.module_hp.size():
		if s.module_hp[i] < 0.0:
			gone += 1
	check(gone == s.module_hp.size() - 1, "everything but the commander is gone (%d of %d)" % [gone, s.module_hp.size()])
	check(s.mass < m0 * 0.5, "mass dropped %.0f -> %.0f" % [m0, s.mass])
	s.queue_free()

func _test_commander_death() -> void:
	print("commander death")
	var s := _ship("Dart")
	await _frames(3)
	s.apply_damage(1, 1e9)
	await _frames(3)
	check(not s.alive, "ship dies when its only commander is destroyed")
	s.queue_free()

func _test_crush() -> void:
	print("crush rule")
	var s := _ship("Brick")
	await _frames(3)
	var wall := 1   # front armor plate (0.24 m thick) lying against the hull
	var hp0 := s.module_hp[wall]
	s.apply_dent(wall, Vector3(0, 0, -5.77), Vector3(0, 0, 1), 0.05, 1.0)    # a light tap: the plate stays
	await _frames(2)
	check(s.module_hp[wall] > 0.0, "a light dent does not destroy the plate")
	s.apply_dent(wall, Vector3(0, 0, -5.77), Vector3(0, 0, 1), 1.6, 2.0)     # driven deep into the hull behind it
	await _frames(3)
	check(hp0 > 0.0 and s.module_hp[wall] == 0.0, "plate pushed through the hull is a dead wreck (hp %.0f -> %.0f)" % [hp0, s.module_hp[wall]])
	check(s.module_hp[0] > 0.0 and s.alive, "the hull behind it survives")
	s.queue_free()

func _test_split() -> void:
	print("split")
	var world: Node = load("res://scenes/game_world.tscn").instantiate()
	add_child(world)
	await _frames(2)
	Net.players = {1: Net._new_entry("Tester")}
	var blob := ShipDesign.read_blob("res://ships/Twin Hull.json")
	var d := ShipDesign.from_blob(blob)
	var h := NetClass.hash_blob(blob)
	Net.blobs[h] = blob
	Net.players[1]["ship"] = h
	Net.players[1]["locked"] = true
	Net._set_ship_slots(1, d)
	world.spawner.spawn({"peer": 1, "design": h, "name": "Tester", "pos": Vector3(0, 0, 0)})
	await _frames(5)
	var parent := world.ships_root.get_node_or_null("1") as Ship
	check(parent != null, "parent ship spawned")
	if parent == null:
		return
	check(d.commander_modules().size() == 2, "design has two commanders")
	check(Net.players[1]["seats"] == 4, "capacity = sum of commanders (4)")
	# a second player on the OTHER commander
	Net.players[2] = Net._new_entry("Crew")
	Net.players[2]["crew_of"] = 1
	Net.players[2]["seat"] = d.commander_modules()[1]
	Net.players[2]["locked"] = true
	var mass0 := parent.mass
	var bridge := 2
	check(d.modules[bridge]["type"] == "armor", "module 2 is the bridge")
	parent.apply_damage(bridge, 1e9)
	await _frames(3)
	check(world.ships_root.get_child_count() == 1, "a dead bridge does not split the ship")
	var hpb := parent.module_hp
	hpb[bridge] = -1.0           # the bridge is cut away completely
	parent.module_hp = hpb
	parent._structure_dirty = true
	await _frames(6)
	check(world.ships_root.get_child_count() == 2, "two ships now (%d)" % world.ships_root.get_child_count())
	var child := world.ships_root.get_node_or_null("2") as Ship
	check(child != null, "the crew member's part flies as ship '2'")
	if child != null:
		check(Net.players[2]["crew_of"] == 0, "crew member promoted to pilot")
		check(child.alive and child.mass > 100.0 and child.mass < mass0, "child has its own mass (%.0f of %.0f)" % [child.mass, mass0])
		check(child.alive_commanders().size() == 1, "child has one commander")
		check(child.linear_velocity.length() > 0.1, "child pushed away (%.2f m/s)" % child.linear_velocity.length())
	check(parent.alive and parent.alive_commanders().size() == 1, "parent keeps one commander")
	check(parent.mass < mass0 * 0.7, "parent lighter (%.0f of %.0f)" % [parent.mass, mass0])
	check(Net.players[1]["seats"] == 2, "captain's ship capacity now 2")
	world.queue_free()
	Net.players = {}

func _test_seats() -> void:
	print("seat bookkeeping")
	var blob := ShipDesign.read_blob("res://ships/Twin Hull.json")
	var d := ShipDesign.from_blob(blob)
	var cmds := d.commander_modules()
	Net.players = {1: Net._new_entry("Cap"), 2: Net._new_entry("A"), 3: Net._new_entry("B")}
	Net.blobs[NetClass.hash_blob(blob)] = blob
	Net.players[1]["ship"] = NetClass.hash_blob(blob)
	Net.players[1]["locked"] = true
	Net._set_ship_slots(1, d)
	check(Net.seat_of(1) == cmds[0], "pilot sits at the first commander")
	check(Net.seats_left(1, cmds[0]) == 1 and Net.seats_left(1, cmds[1]) == 2, "free seats 1 + 2")
	check(Net.seats_free(1) == 3, "3 seats free in total")
	Net.players[2]["crew_of"] = 1
	Net.players[2]["seat"] = cmds[0]
	Net.players[3]["crew_of"] = 1
	Net.players[3]["seat"] = cmds[1]
	check(Net.seats_left(1, cmds[0]) == 0 and Net.seats_left(1, cmds[1]) == 1, "after joining: 0 and 1 free")
	var orphans: Array[int] = []
	Net.crew_orphaned.connect(func(id: int): orphans.append(id))
	# the first commander is destroyed (no split): the pilot and crew A must move to the second; only 1 seat is free there
	var pilots := Net.srv_structure_changed(1, [cmds[1]], [])
	check(pilots.is_empty(), "no new ships")
	check(Net.seat_of(1) == cmds[1], "pilot moved to the surviving commander")
	check(Net.players[1]["seats"] == 2, "capacity now 2")
	check(orphans.size() == 1 and Net.players[2]["crew_of"] == 0, "crew with no free seat gets a ship of their own (orphans=%s)" % [orphans])
	Net.players = {}

func _test_links() -> void:
	print("commander links: a player controls only what their commander is linked to")
	var blob := ShipDesign.read_blob("res://ships/Twin Hull.json")
	var d := ShipDesign.from_blob(blob)
	var cmds := d.commander_modules()
	var guns: Array[int] = []
	for m in d.modules.size():
		if d.modules[m]["type"] == ModuleCatalog.TURRET:
			guns.append(m)
	check(d.has_links() and d.linked_turrets(cmds[0]) == [guns[0]] and d.linked_turrets(cmds[1]) == [guns[1]], "each bridge of Twin Hull is linked to the turret of its hull")
	check(d.controls(cmds[0], guns[0]) and not d.controls(cmds[0], guns[1]), "bridge 0 controls only its own turret")
	check(d.controls(-1, guns[1]), "no seat known: everything is allowed")
	# gunner-only bridge + JSON round trip + old single "link" files
	d.modules[cmds[1]]["cfg"]["pilot"] = false
	var back := ShipDesign.from_blob(d.to_blob())
	check(back.controls_flight(cmds[0]) and not back.controls_flight(cmds[1]), "the pilot flag survives a save")
	var raw: Dictionary = JSON.parse_string(d.to_json())
	raw["modules"][cmds[0]]["cfg"].erase("links")
	raw["modules"][cmds[0]]["cfg"]["link"] = guns[0]
	var legacy := ShipDesign.from_dict(raw)
	check(legacy.linked_turrets(cmds[0]) == [guns[0]], "an old file with ONE 'link' becomes a links list")
	check(d.toggle_link(cmds[0], guns[1]) and d.linked_turrets(cmds[0]).size() == 2 and not d.toggle_link(cmds[0], guns[1]), "T links, T again unlinks")
	# a live ship: the owner sits at the bridge with the first commander
	Net.players = {1: Net._new_entry("Cap")}
	Net.players[1]["locked"] = true
	Net._set_ship_slots(1, d)
	var ship: Ship = load("res://scenes/ship.tscn").instantiate()
	ship.name = "1"
	ship.design_blob = d.to_blob()
	add_child(ship)
	await _frames(3)
	check(ship.my_commander() == cmds[0], "the owner sits at the first bridge by default")
	check(ship.bases_of_seat(cmds[0]) == PackedInt32Array([guns[0]]), "...which controls only turret %d" % guns[0])
	var gun_stations := 0
	var pilot_stations := 0
	for st in ship.stations.stations:
		if st["kind"] == "gun":
			gun_stations += 1
		else:
			pilot_stations += 1
	check(gun_stations == 1 and pilot_stations == 1, "only my own bridge and my own turret are stations (%d + %d)" % [pilot_stations, gun_stations])
	check(ship.i_fly(), "my bridge flies the ship")
	Net.players[1]["seat"] = cmds[1]       # the owner picks the other bridge (a gunner-only one)
	ship.stations.rebuild()
	check(ship.my_commander() == cmds[1] and not ship.i_fly(), "moved to the gunner bridge: cannot fly")
	ship.stations.mode = "crew"
	ship.stations.current = 0
	check(not ship.stations.can_fly() and ship.stations.active_base() == guns[1], "a gunner bridge cannot fly, but fires its own turret")
	ship.queue_free()
	Net.players = {}
	await _frames(2)

func _test_turrets() -> void:
	print("turrets")
	var s := _ship("Dart")
	await _frames(3)
	check(s.turrets.rigs.size() == 2, "Dart has two dual-part turrets (%d)" % s.turrets.rigs.size())
	var r: ShipTurrets.Rig = s.turrets.rigs[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for q in s.turrets.rigs:      # the premade Dart turrets turn all the way round: limit them for the arc test
		q.yaw_min = deg_to_rad(-150.0)
		q.yaw_max = deg_to_rad(150.0)
	check(r.node != null and r.node.name.begins_with("BarrelPivot"), "barrel has a pivot node (%s)" % [str(r.node.name) if r.node != null else "none"])
	s.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	s.turrets.filter_base = -2        # (crew mode would only use the turret of the current station)
	# target in front and a bit up: the barrel turns to it, then the turret is allowed to fire
	s.turrets.aim_point = Vector3(0, 30, -100)
	s.turrets.has_aim = true
	for i in 60:
		s.turrets.track(1.0 / 60.0)
	check(r.aim_error < deg_to_rad(Data.TURRET_AIM_TOLERANCE_DEG), "barrel tracks a target in front (error %.1f deg)" % rad_to_deg(r.aim_error))
	check(s.turrets.firing_solution(rng).size() == 2, "both turrets fire (%d)" % s.turrets.firing_solution(rng).size())
	# straight behind: the arc (+-150 deg) stops the barrel
	s.turrets.aim_point = Vector3(0, 0, 100)
	for i in 400:
		s.turrets.track(1.0 / 60.0)
	check(absf(r.yaw) <= deg_to_rad(150.0) + 0.001, "yaw limit respected (%.0f deg)" % rad_to_deg(r.yaw))
	check(r.aim_error > deg_to_rad(Data.TURRET_AIM_TOLERANCE_DEG), "out-of-arc target is not 'aimed' (%.0f deg off)" % rad_to_deg(r.aim_error))
	check(s.turrets.firing_solution(rng).is_empty(), "no shot at a target out of the arc")
	check(not s.turrets.firing_solution(rng, PackedInt32Array(), true).is_empty(), "...but a person holding the trigger of their turret (crew mode) fires anyway")
	# speed limit: one frame turns at most speed * dt
	r.yaw = 0.0
	s.turrets.aim_point = Vector3(-100, 0, -1)
	var before := r.yaw
	s.turrets.track(0.1)
	check(absf(r.yaw - before) <= r.speed * 0.1 + 0.0001, "turn speed limit respected (%.1f deg in 0.1 s)" % rad_to_deg(absf(r.yaw - before)))
	s.queue_free()
	# self collision: a Brick turret pointing along the commander must not fire through it
	var b := _ship("Brick")
	await _frames(3)
	b.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	b.turrets.filter_base = -2
	var top: ShipTurrets.Rig = null
	for q in b.turrets.rigs:
		if q.pivot.y > 0.5 and q.pivot.x < 0.0 and (top == null or q.pivot.x < top.pivot.x):
			top = q
	check(top != null, "found the top-left Brick turret")
	if top != null:
		# turn the barrel towards the commander module (in steps) until the line of fire is blocked by it
		var found := false
		for yaw_try in range(1, 30):
			for pitch_try in range(0, 12):
				top.yaw = -0.05 * yaw_try
				top.pitch = 0.1 * pitch_try - 0.1
				if not b.turrets._barrel_blocked(top, top.yaw, top.pitch) and b.turrets.line_of_fire_blocked(top):
					found = true
		check(found, "line of fire through the own commander is blocked")
		top.yaw = 0.0
		top.pitch = top.rest_pitch
		b.turrets.aim_point = top.pivot + Vector3(-30.0, 40.0, -10.0)
		for i in 240:
			b.turrets.track(1.0 / 60.0)
		check(not b.turrets.line_of_fire_blocked(top), "free line of fire when aiming away from the hull")
		# a barrel may not turn INTO the hull: aim straight down through the ship
		b.turrets.aim_point = top.pivot + Vector3(0.0, -40.0, 0.0)
		for i in 400:
			b.turrets.track(1.0 / 60.0)
		check(b.turrets._barrel_blocked(top, top.yaw, top.pitch) == false, "barrel stops before it enters the hull (pitch %.0f deg)" % rad_to_deg(top.pitch))
	b.queue_free()
