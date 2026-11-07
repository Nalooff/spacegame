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
	# every person: walk, work, choose a job
	var workers: Dictionary = {}
	for m in members:
		if m["hp"] <= 0.0:
			continue
		_step_member(ship, m, step, workers)
	return false


func _step_member(ship: Ship, m: Dictionary, dt: float, workers: Dictionary) -> void:
	var ps := ship.plan_state
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
