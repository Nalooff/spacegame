class_name ShipCrew
extends RefCounted
## THE CREW of a ship: real people who walk the corridors of the ship plan (PlanState), authority peer only.
##
##   * One person per Data.CREW_M3_PER_PERSON of room volume. A ship without rooms has no crew system (and cannot die of it).
##   * ALL the crew dead = the ship is lost (Ship._die): the death counts.  A person dies when the room they stand in is
##     destroyed, and is hurt when it is hit.
##   * They work AUTOMATICALLY: idle people walk to damaged modules they know about and repair them (health comes back
##     slowly while somebody works there), otherwise they patrol from room to room.
##   * You can ORDER them (CrewPanel): go and repair a module, or go and LOOK at one ("inspect").
##   * REPORTS: with communications the commander hears everything at once. Without, a damage report only exists once
##     somebody has actually been near the damage (they notice it) and then walked it to the commander. So it may take a
##     while until somebody passes by: send somebody to have a look.
##
## member: {id, hp, node (plan node), pos (ship space), from (Vector3), to (Vector3), t_total, t_left, dest_node,
##          task: "idle"|"walk"|"repair"|"inspect", module (target), ordered: bool, patrol: float}

var members: Array[Dictionary] = []
var noticed: Dictionary = {}            ## module index -> true: somebody noticed it is damaged (without comms)
var _rng := RandomNumberGenerator.new()
var _next_id: int = 1
var _acc: float = 0.0
var _ready_done: bool = false
var log_lines: Array[String] = []
## BOARDERS: enemy people on this ship. {id, hp, node, pos, from, to, t_total, t_left, dest_node, task: "idle"|"walk"|"sabotage",
## module, home (peer id of the ship they come from), left (seconds of work in this room), hold (seconds on the bridge)}
var foes: Array[Dictionary] = []
var pods: Dictionary = {}               ## pod bay module -> pods left (filled when first needed)


func active() -> bool:
	return not members.is_empty()


func alive_count() -> int:
	var n := 0
	for m in members:
		if m["hp"] > 0.0:
			n += 1
	return n


## Called by the ship whenever its plan is (re)built. First time: create the people. Later: put them back on the new plan.
func plan_ready(ship: Ship) -> void:
	var ps := ship.plan_state
	if ps == null:
		return
	if not _ready_done:
		_ready_done = true
		_rng.seed = 7000 + int(str(ship.name).hash() % 1000)
		if ship.initial_hp.size() == 0:                  # a torn-off part has nobody on board
			_populate(ship)
		return
	for m in members:
		if m["hp"] <= 0.0:
			continue
		var ni := _nearest_node(ps.plan, m["pos"])
		if ni < 0 or (ps.plan.nodes[ni]["pos"] as Vector3).distance_to(m["pos"]) > 3.0:
			m["hp"] = 0.0                                # his part of the ship is gone
			_log("%s was lost with a part of the ship" % _name(m))
		else:
			m["node"] = ni
	for f in foes:
		if f["hp"] <= 0.0:
			continue
		var fi := _nearest_node(ps.plan, f["pos"])
		if fi < 0 or (ps.plan.nodes[fi]["pos"] as Vector3).distance_to(f["pos"]) > 3.0:
			f["hp"] = 0.0
		else:
			f["node"] = fi


func _populate(ship: Ship) -> void:
	var plan := ship.plan_state.plan
	var vol := 0.0
	for r in plan.rooms:
		vol += ship.design.module_volume(r)
	var count := clampi(int(vol / Data.CREW_M3_PER_PERSON), 0, Data.CREW_MAX)
	if count == 0 or plan.rooms.is_empty():
		return
	for i in count:
		var room := plan.rooms[i % plan.rooms.size()]
		var ni := plan.door_of(room)
		if ni < 0:
			continue
		var p: Vector3 = plan.nodes[ni]["pos"]
		members.append({"id": _next_id, "hp": Data.CREW_HP, "node": ni, "pos": p, "from": p, "to": p, "t_total": 0.0, "t_left": 0.0,
			"dest_node": ni, "task": "idle", "module": -1, "ordered": false, "patrol": _rng.randf_range(2.0, Data.CREW_PATROL_MIN)})
		_next_id += 1


static func _name(m: Dictionary) -> String:
	return "Crew #%d" % int(m["id"])


func log_event(text: String) -> void:
	_log(text)


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 100:
		log_lines.remove_at(0)


static func _nearest_node(plan: ShipPlan, p: Vector3) -> int:
	var best := INF
	var at := -1
	for ni in plan.nodes.size():
		var d := (plan.nodes[ni]["pos"] as Vector3).distance_squared_to(p)
		if d < best:
			best = d
			at = ni
	return at


func module_of(ship: Ship, m: Dictionary) -> int:
	var ps := ship.plan_state
	if ps == null or m["node"] < 0 or m["node"] >= ps.plan.nodes.size():
		return -1
	return int(ps.plan.nodes[m["node"]]["module"])


## The first plan node of module `mi` (its door when it is a room, otherwise any node inside it).
func node_for_module(ship: Ship, mi: int) -> int:
	var plan := ship.plan_state.plan
	if plan.rooms.has(mi):
		return plan.door_of(mi)
	for ni in plan.nodes.size():
		if int(plan.nodes[ni]["module"]) == mi:
			return ni
	return -1


## Authority: a module took damage. The people standing in it are hurt.
func on_hit(ship: Ship, module: int, hp_damage: float) -> void:
	if hp_damage <= 0.0 or module < 0 or module >= ship.module_max_hp.size():
		return
	var frac := hp_damage / maxf(ship.module_max_hp[module], 1.0)
	for m in members:
		if m["hp"] > 0.0 and module_of(ship, m) == module:
			m["hp"] -= Data.CREW_HIT_DAMAGE * frac
			if m["hp"] <= 0.0:
				_log("%s was killed" % _name(m))
	for f in foes:
		if f["hp"] > 0.0 and module_of(ship, f) == module:
			f["hp"] -= Data.CREW_HIT_DAMAGE * frac


## Physics-rate tick, but the logic runs 10 times a second. Returns true when the last person has died.
func tick(ship: Ship, dt: float) -> bool:
	if members.is_empty() or ship.plan_state == null:
		return false
	_acc += dt
	if _acc < 0.1:
		return false
	var step := _acc
	_acc = 0.0
	var ps := ship.plan_state
	var comms := ps.comms_ok
	# people in a dead / gone room die
	for m in members:
		if m["hp"] > 0.0:
			var mi := module_of(ship, m)
			if mi >= 0 and mi < ship.module_hp.size() and ship.module_hp[mi] <= 0.0:
				m["hp"] = 0.0
				_log("%s died when their room was destroyed" % _name(m))
	if alive_count() == 0:
		for f in foes:
			if f["hp"] > 0.0:
				ship.credit_capture(int(f["home"]))     # the boarders killed everybody: the ship is theirs
				break
		return true
	# noticing damage
	for mi in ship.module_hp.size():
		if ship.module_max_hp.size() <= mi:
			break
		var damaged: bool = ship.module_hp[mi] >= 0.0 and (ship.module_hp[mi] < ship.module_max_hp[mi] * 0.98 or _hazard_at(ship, mi))
		if not damaged:
			noticed.erase(mi)
		elif comms:
			noticed[mi] = true
	for m in members:
		if m["hp"] <= 0.0:
			continue
		for mi in ship.module_hp.size():
			if noticed.has(mi) or ship.module_hp[mi] < 0.0 or mi >= ship.module_max_hp.size() or (ship.module_hp[mi] >= ship.module_max_hp[mi] * 0.98 and not _hazard_at(ship, mi)):
				continue
			if (ship.design.module_centroid(mi) as Vector3).distance_to(m["pos"]) < maxf(Data.CREW_NOTICE_RADIUS, ship.design.module_extent(mi).length() * 0.5):
				noticed[mi] = true
				_log("%s noticed damage on module %d" % [_name(m), mi])
	# boarders
	if not foes.is_empty() and _step_foes(ship, step):
		return true
	# every person: walk, work, choose a job
	var workers: Dictionary = {}
	for m in members:
		if m["hp"] <= 0.0:
			continue
		_step_member(ship, m, step, workers)
	return false


func _step_member(ship: Ship, m: Dictionary, dt: float, workers: Dictionary) -> void:
	var ps := ship.plan_state
	if m["task"] != "walk" and foe_in(module_of(ship, m)):
		return                                         # an enemy in the room: stand and fight (see _step_foes)
	if m["task"] == "walk":
		m["t_left"] = maxf(float(m["t_left"]) - dt, 0.0)
		var k := 1.0 - float(m["t_left"]) / maxf(float(m["t_total"]), 0.001)
		m["pos"] = (m["from"] as Vector3).lerp(m["to"], k)
		if m["t_left"] <= 0.0:
			m["node"] = m["dest_node"]
			m["pos"] = m["to"]
			m["task"] = "work" if m["module"] >= 0 and m["module"] == module_of(ship, m) and not m.get("inspect", false) else "idle"
			if m.get("inspect", false):
				m["inspect"] = false
				m["ordered"] = false
				m["module"] = -1
				m["task"] = "idle"
		return
	var mi: int = m["module"]
	if m["task"] == "work" and mi >= 0:
		var live: bool = mi < ship.module_hp.size() and ship.module_hp[mi] >= 0.0
		var ok: bool = live and (ship.module_hp[mi] < ship.module_max_hp[mi] or _hazard_at(ship, mi))
		if ok and int(workers.get(mi, 0)) < Data.CREW_MAX_WORKERS:
			workers[mi] = int(workers.get(mi, 0)) + 1
			if ship.module_hp[mi] < ship.module_max_hp[mi]:
				var hp := ship.module_hp
				hp[mi] = minf(hp[mi] + ship.module_max_hp[mi] * Data.CREW_REPAIR_PER_S * dt, ship.module_max_hp[mi])
				ship.module_hp = hp
				ship._function_dirty = true
			return       # (fire and electrical faults are dealt with by ShipHazards while somebody is in the room)
		m["task"] = "idle"
		m["module"] = -1
		m["ordered"] = false
	# idle: look for work, otherwise patrol
	if not m["ordered"]:
		var job := _find_job(ship, m, workers)
		if job >= 0:
			_send(ship, m, job, false)
			return
		m["patrol"] = float(m["patrol"]) - dt
		if m["patrol"] <= 0.0:
			m["patrol"] = _rng.randf_range(Data.CREW_PATROL_MIN, Data.CREW_PATROL_MIN * 2.0)
			var rooms := ps.plan.rooms
			if not rooms.is_empty():
				_send_to_node(ship, m, ps.plan.door_of(rooms[_rng.randi() % rooms.size()]), -1, false)


## The module an idle person should repair: damaged, known, reachable, not crowded; the nearest one.
func _find_job(ship: Ship, m: Dictionary, workers: Dictionary) -> int:
	var dist := ship.plan_state.walk_from(m["node"])
	var best := -1
	var best_d := INF
	for mi in noticed:
		if mi >= ship.module_hp.size() or ship.module_hp[mi] < 0.0 or int(workers.get(mi, 0)) + _heading_to(mi, m) >= Data.CREW_MAX_WORKERS:
			continue
		var ni := node_for_module(ship, mi)
		if ni < 0 or dist[ni] == INF:
			continue
		if mi < ship.haz_air.size() and ship.haz_air[mi] < 0.4:
			continue                                  # nobody walks into a room with no air
		var score: float = dist[ni] - (200.0 if mi < ship.haz_fire.size() and ship.haz_fire[mi] > 0.03 else 0.0)
		if score < best_d:
			best_d = score
			best = mi
	return best


static func _hazard_at(ship: Ship, mi: int) -> bool:
	if ship.crew.foe_in(mi):
		return true
	return (mi < ship.haz_fire.size() and ship.haz_fire[mi] > 0.03) or (mi < ship.haz_elec.size() and ship.haz_elec[mi] > 0.0)


func _heading_to(mi: int, except: Dictionary) -> int:
	var n := 0
	for o in members:
		if o != except and o["hp"] > 0.0 and o["module"] == mi:
			n += 1
	return n


func _send(ship: Ship, m: Dictionary, module: int, ordered: bool, inspect: bool = false) -> bool:
	var ni := node_for_module(ship, module)
	if ni < 0:
		return false
	return _send_to_node(ship, m, ni, module, ordered, inspect)


func _send_to_node(ship: Ship, m: Dictionary, ni: int, module: int, ordered: bool, inspect: bool = false) -> bool:
	var dist := ship.plan_state.walk_from(m["node"])
	if ni < 0 or ni >= dist.size() or dist[ni] == INF:
		return false
	m["dest_node"] = ni
	m["from"] = m["pos"]
	m["to"] = ship.plan_state.plan.nodes[ni]["pos"]
	m["t_total"] = maxf(dist[ni] / Data.CREW_WALK_SPEED, 0.05)
	m["t_left"] = m["t_total"]
	m["module"] = module
	m["ordered"] = ordered
	m["inspect"] = inspect
	m["task"] = "walk"
	return true


# ---------------------------------------------------------------- orders (called by the CrewPanel on the owner's peer)
## Send person `id` to module `mi`: to repair it ("repair") or just to look at it ("inspect"). False = cannot get there.
func order(ship: Ship, id: int, mi: int, task: String) -> bool:
	for m in members:
		if m["id"] == id and m["hp"] > 0.0:
			var ok := _send(ship, m, mi, true, task == "inspect")
			if ok:
				_log("%s ordered to %s module %d" % [_name(m), task, mi])
			return ok
	return false


## Release a person from their order: back to automatic work.
func release(id: int) -> void:
	for m in members:
		if m["id"] == id:
			m["ordered"] = false
			if m["task"] == "work":
				m["task"] = "idle"


## The nearest idle (or free) person to module `mi`; -1 when nobody can get there.
func nearest_free(ship: Ship, mi: int) -> int:
	var ni := node_for_module(ship, mi)
	if ni < 0:
		return -1
	var dist := ship.plan_state.walk_from(ni)
	var best := -1
	var best_d := INF
	for m in members:
		if m["hp"] <= 0.0 or m["ordered"]:
			continue
		var d: float = dist[m["node"]] if m["node"] < dist.size() else INF
		if d < best_d:
			best_d = d
			best = m["id"]
	return best


## Seconds until somebody who is near ship-space point `p` has walked to a working commander; -1 = nobody is near it.
## ShipReports uses this instead of assuming that somebody is always standing right there.
func finder_delay(ship: Ship, p: Vector3) -> float:
	var ps := ship.plan_state
	var best := -1.0
	for m in members:
		if m["hp"] <= 0.0:
			continue
		if (m["pos"] as Vector3).distance_to(p) <= Data.CREW_NOTICE_RADIUS + 2.0:
			var n: int = m["node"]
			var metres: float = ps.node_dist[n] if n < ps.node_dist.size() else INF
			var t := metres / Data.CREW_WALK_SPEED if metres != INF else INF
			if best < 0.0 or t < best:
				best = t
	return best


# ---------------------------------------------------------------- boarders
func foe_in(mi: int) -> bool:
	if foes.is_empty() or mi < 0:
		return false
	for f in foes:
		if f["hp"] > 0.0 and int(f.get("module", -1)) == mi:
			return true
	return false


func foe_count() -> int:
	var n := 0
	for f in foes:
		if f["hp"] > 0.0:
			n += 1
	return n


## Enemy people arrive in module `mi` (a breach, an airlock, a pod). `home` = peer id of their ship.
func add_foes(ship: Ship, mi: int, count: int, home: int) -> void:
	var ni := node_for_module(ship, mi)
	if ni < 0 or ship.plan_state == null:
		return
	var p: Vector3 = ship.plan_state.plan.nodes[ni]["pos"]
	for i in count:
		foes.append({"id": 9000 + _next_id, "hp": Data.CREW_HP, "node": ni, "pos": p, "from": p, "to": p, "t_total": 0.0, "t_left": 0.0,
			"dest_node": ni, "task": "idle", "module": mi, "home": home, "left": Data.FOE_SABOTAGE_SECONDS, "hold": 0.0})
		_next_id += 1
	_log("BOARDERS in module %d (%d)!" % [mi, count])


## Take up to `count` free, living people out of the crew (they leave to board somewhere). Nearest to module `near` first.
func take_boarders(ship: Ship, count: int, near: int) -> int:
	var ni := node_for_module(ship, near)
	var dist := ship.plan_state.walk_from(ni) if ni >= 0 else PackedFloat32Array()
	var taken := 0
	var worst := 0.0
	count = mini(count, alive_count() - 1)           # somebody always stays aboard
	while taken < count:
		var best := -1
		var best_d := INF
		for i in members.size():
			var m: Dictionary = members[i]
			if m["hp"] <= 0.0 or m["ordered"]:
				continue
			var d: float = dist[m["node"]] if m["node"] < dist.size() else INF
			if d < best_d:
				best_d = d
				best = i
		if best < 0 or best_d == INF:
			break
		worst = maxf(worst, best_d)
		members.remove_at(best)
		taken += 1
	boarding_walk = worst / Data.CREW_WALK_SPEED
	return taken


var boarding_walk: float = 0.0           ## seconds the last group of boarders needed to reach the exit


## Returns true when the ship is taken.
func _step_foes(ship: Ship, s: float) -> bool:
	var rng := _rng
	for f in foes:
		if f["hp"] <= 0.0:
			continue
		var mi := module_of(ship, f)
		f["module"] = mi
		if mi >= 0 and mi < ship.module_hp.size() and ship.module_hp[mi] <= 0.0:
			f["hp"] = 0.0
			continue
		if f["task"] == "walk":
			f["t_left"] = maxf(float(f["t_left"]) - s, 0.0)
			var k := 1.0 - float(f["t_left"]) / maxf(float(f["t_total"]), 0.001)
			f["pos"] = (f["from"] as Vector3).lerp(f["to"], k)
			if f["t_left"] <= 0.0:
				f["node"] = f["dest_node"]
				f["pos"] = f["to"]
				f["task"] = "idle"
				f["left"] = Data.FOE_SABOTAGE_SECONDS
			continue
		# a fight: every defender in the room hits one boarder and every boarder hits one defender
		var defenders: Array[Dictionary] = []
		for m in members:
			if m["hp"] > 0.0 and module_of(ship, m) == mi:
				defenders.append(m)
		if not defenders.is_empty():
			var target: Dictionary = defenders[rng.randi() % defenders.size()]
			target["hp"] -= Data.FOE_FIGHT_DPS * s
			if target["hp"] <= 0.0:
				_log("%s was killed by boarders" % _name(target))
			f["hp"] -= Data.FOE_FIGHT_DPS * 0.8 * s * defenders.size()      # the defenders hit back (a little worse: they came prepared)
			if f["hp"] <= 0.0:
				_log("A boarder was killed")
			f["hold"] = 0.0
			continue
		# nobody defends this room
		var t: String = ship.design.modules[mi]["type"] if mi >= 0 else ""
		if t == ModuleCatalog.COMMANDER:
			f["hold"] = float(f["hold"]) + s
			if float(f["hold"]) >= Data.FOE_CAPTURE_SECONDS and _all_foes_in(mi):
				_log("The bridge has fallen: the ship is taken")
				ship.credit_capture(int(f["home"]))
				return true
		if mi >= 0 and ship.module_hp[mi] > 0.0 and float(f["left"]) > 0.0:
			f["left"] = float(f["left"]) - s
			ship._remove_module_hp(mi, ship.module_max_hp[mi] * Data.FOE_SABOTAGE_RATE * s)
			if rng.randf() < 0.02:
				ship.hazards.short_out(ship, mi)
			if rng.randf() < 0.01:
				ship.hazards.ignite(ship, mi, 0.2)
			continue
		var goal := _foe_goal(ship, f)
		if goal >= 0:
			_foe_walk(ship, f, goal)
		else:
			f["left"] = Data.FOE_SABOTAGE_SECONDS
	return false


func _all_foes_in(mi: int) -> bool:
	var n := 0
	for f in foes:
		if f["hp"] > 0.0:
			if int(f.get("module", -1)) != mi:
				return false
			n += 1
	return n > 0


## Where boarders go next: the bridge first, then engine rooms, turrets, radars, anything else reachable (not the room they stand in).
func _foe_goal(ship: Ship, f: Dictionary) -> int:
	var ps := ship.plan_state
	var dist := ps.walk_from(f["node"])
	var here := module_of(ship, f)
	var best := -1
	var best_score := INF
	for r in ps.plan.rooms:
		if r == here or ship.module_hp[r] <= 0.0:
			continue
		var ni := ps.plan.door_of(r)
		if ni < 0 or ni >= dist.size() or dist[ni] == INF:
			continue
		var t: String = ship.design.modules[r]["type"]
		var bonus := 0.0
		match t:
			ModuleCatalog.COMMANDER: bonus = 400.0
			ModuleCatalog.ENGINE_ROOM: bonus = 200.0
			ModuleCatalog.TURRET: bonus = 100.0
			ModuleCatalog.RADAR: bonus = 50.0
		var score: float = dist[ni] - bonus
		if score < best_score:
			best_score = score
			best = ni
	return best


func _foe_walk(ship: Ship, f: Dictionary, ni: int) -> void:
	var dist := ship.plan_state.walk_from(f["node"])
	if ni >= dist.size() or dist[ni] == INF:
		return
	f["dest_node"] = ni
	f["from"] = f["pos"]
	f["to"] = ship.plan_state.plan.nodes[ni]["pos"]
	f["t_total"] = maxf(dist[ni] / Data.CREW_WALK_SPEED, 0.05)
	f["t_left"] = f["t_total"]
	f["task"] = "walk"
