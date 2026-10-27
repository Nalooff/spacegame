class_name ShipReports
extends RefCounted
## WHAT THE COMMANDER KNOWS about the damage of the own ship (only used on the peer that flies it).
##
## The damage itself is always simulated at once (Ship.module_hp, corridor_hp, dents). What is delayed is the REPORT:
##   * communications online: the report arrives instantly (the plan always shows the truth);
##   * offline: somebody walks it from the damaged spot to a working commander (PlanState.delay_at, the same walking
##     distance as an order). Until it arrives the plan shows only a THEORISED SPHERE: "something happened around here"
##     (a deliberately offset centre and Data.REPORT_UNCERTAINTY of radius), and the old state of the module / corridor.
##     A report from a spot no open corridor leads away from never arrives (Data.ORDER_DELAY_MAX is the limit).
## Ship.apply_dent also holds back the visible dent of the own hull for the same time (no mesh work until it is known).
##
## Known state: `known_hp`, `known_edge` and `known_state` (a PlanState run on those numbers), what PlanCanvas draws.

var known_hp: PackedFloat32Array = PackedFloat32Array()
var known_edge: PackedFloat32Array = PackedFloat32Array()
var known_state: PlanState = null
var history: Array[String] = []            ## what the commander was told, newest last (the plan's LOGS tab)
var pending: Array[Dictionary] = []      ## {due, kind: "m"|"e", index, value, center: Vector3, radius}
var _seen_hp: PackedFloat32Array = PackedFloat32Array()
var _seen_edge: PackedFloat32Array = PackedFloat32Array()
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 424242


## Look at the ship's real state and turn every change into a report. Call a few times a second.
func tick(ship: Ship, dt: float) -> void:
	if ship.plan_state == null:
		return
	_clock += dt
	var ps := ship.plan_state
	if known_state == null or known_hp.size() != ship.module_hp.size() or known_edge.size() != ps.edge_hp.size():
		known_hp = ship.module_hp.duplicate()
		known_edge = ps.edge_hp.duplicate()
		_seen_hp = known_hp.duplicate()
		_seen_edge = known_edge.duplicate()
		known_state = PlanState.new(ps.plan)
		pending.clear()
		_refresh_known(ship)
		return
	var changed := false
	var batch: Array[Dictionary] = []      # reports made in this tick: they share ONE theorised sphere
	for mi in ship.module_hp.size():
		if ship.module_hp[mi] != _seen_hp[mi]:
			# only a change of STATE matters for the plan (working / dead / gone), not every scratch
			if (ship.module_hp[mi] > 0.0) != (_seen_hp[mi] > 0.0) or (ship.module_hp[mi] < 0.0) != (_seen_hp[mi] < 0.0):
				batch.append(_report("m", mi, ship.module_hp[mi], ship.design.module_centroid(mi), ship))
			else:
				known_hp[mi] = ship.module_hp[mi]
			_seen_hp[mi] = ship.module_hp[mi]
			changed = true
	for ei in ps.edge_hp.size():
		if ps.edge_hp[ei] != _seen_edge[ei]:
			var a: Vector3 = ps.plan.nodes[ps.plan.edges[ei]["a"]]["pos"]
			var b: Vector3 = ps.plan.nodes[ps.plan.edges[ei]["b"]]["pos"]
			batch.append(_report("e", ei, ps.edge_hp[ei], (a + b) * 0.5, ship))
			_seen_edge[ei] = ps.edge_hp[ei]
			changed = true
	_make_sphere(batch)
	var i := 0
	while i < pending.size():
		var r: Dictionary = pending[i]
		if r.get("nolink", false) or float(r["due"]) == INF:      # a way (or the radio) may have come back
			var dl := ship.plan_state.delay_at(r["center"])
			if dl != INF:
				r["due"] = _clock + dl
				r["nolink"] = false
		if _clock >= float(r["due"]):
			_apply(r)
			pending.remove_at(i)
			changed = true
		else:
			i += 1
	if changed or known_state.comms_ok != ship.comms.online:
		_refresh_known(ship)


func _report(kind: String, index: int, value: float, at: Vector3, ship: Ship) -> Dictionary:
	var delay := ship.plan_state.delay_at(at)
	# delay == INF: no open corridor leads from there to a working commander. The report WAITS (no link) until
	# communications come back or a corridor opens; it is NOT silently delivered after some fixed time.
	var r := {"due": _clock + delay if delay != INF else INF, "kind": kind, "index": index, "value": value, "center": at,
		"radius": Data.REPORT_UNCERTAINTY, "sphere": false, "nolink": delay == INF}
	if delay <= 0.05:
		_apply(r)
		return {}
	pending.append(r)
	return r


## One sphere for everything reported in the same moment (a single hit usually hurts a module and some corridors):
## centred near the middle of what was hit, deliberately NOT exactly on it, big enough to contain all of it.
func _make_sphere(batch: Array[Dictionary]) -> void:
	var items: Array[Dictionary] = []
	for r in batch:
		if not r.is_empty():
			items.append(r)
	if items.is_empty():
		return
	var mid := Vector3.ZERO
	for r in items:
		mid += r["center"]
	mid /= items.size()
	var radius := Data.REPORT_UNCERTAINTY
	for r in items:
		radius = maxf(radius, mid.distance_to(r["center"]) + Data.REPORT_UNCERTAINTY * 0.5)
	var off := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized() * _rng.randf() * Data.REPORT_UNCERTAINTY * 0.4
	items[0]["sphere"] = true
	items[0]["center"] = mid + off
	items[0]["radius"] = radius


func _apply(r: Dictionary) -> void:
	if r["kind"] == "m":
		known_hp[int(r["index"])] = float(r["value"])
		var v := float(r["value"])
		_log("Module %d: %s" % [int(r["index"]), "GONE" if v < 0.0 else ("DESTROYED" if v <= 0.0 else "damaged")])
	else:
		known_edge[int(r["index"])] = float(r["value"])
		_log("Corridor %d: %s" % [int(r["index"]), "BLOCKED" if float(r["value"]) <= 0.0 else "damaged"])


func _log(text: String) -> void:
	history.append("%s  %s" % [_stamp(), text])
	if history.size() > 200:
		history.remove_at(0)


func _stamp() -> String:
	return "T+%02d:%02d" % [int(_clock / 60.0), int(_clock) % 60]


func _refresh_known(ship: Ship) -> void:
	known_state.edge_hp = known_edge.duplicate()
	known_state.update(ship._types, known_hp, ship.comms.online)


## Seconds a report from ship-space point `p` needs to reach the commander (0 = instant).
func delay_at(ship: Ship, p: Vector3) -> float:
	return ship.plan_state.delay_at(p) if ship.plan_state != null else 0.0


## Rooms that are (as far as the commander knows) alive but cut off: communications are down and no open corridor
## leads to a working commander. They cannot be ordered at all until a link is back.
func cut_off_rooms(ship: Ship) -> PackedInt32Array:
	var out := PackedInt32Array()
	var ks := known_state
	if ks == null or ks.comms_ok:
		return out
	for r in ks.plan.rooms:
		if r < known_hp.size() and known_hp[r] > 0.0 and ks.reach[r] == INF and ship.design.modules[r]["type"] != ModuleCatalog.COMMANDER:
			out.append(r)
	return out


## Number of damage reports that cannot reach the commander at all right now.
func unreachable_reports() -> int:
	var n := 0
	for r in pending:
		if r.get("nolink", false):
			n += 1
	return n
