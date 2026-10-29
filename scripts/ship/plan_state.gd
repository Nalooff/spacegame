class_name PlanState
extends RefCounted
## LIVE STATE of the ship plan (see ShipPlan for the map itself): which rooms can be reached, which modules work.
##
## MODULE STATES (Ship.module_hp)         hp > 0  working      hp == 0  DEAD wreck: still there, still solid, but nobody can
##                                                              enter it and it does nothing      hp < 0  GONE: cut off
## CORRIDOR STATES (edge_hp, 0..1)        each corridor piece has its own health; damage "lines" through the hull wear
##                                        them down (see damage_line). A piece at 0 is blocked.
##
## A corridor piece can be walked when: its health > 0 AND the module it lies in works (hp > 0).
##
## WORKING RULE for a room module (thruster, turret, radar ...):
##     hp > 0   AND   ( communications are OK   OR   a working commander can WALK to it over open corridors )
## Commanders and antennas work on their own (hp > 0). Hull / armor / barrels work while hp > 0.
##
## ORDER DELAY: with communications an order arrives at once. Thrusters and antennas are not rooms: they obey at once always.
## Without communications somebody has to walk an order from the commander to a ROOM: delay = shortest open corridor path / WALK_SPEED seconds. No open path = the room is cut off.

const WALK_SPEED := 2.5   ## metres per second (same as ShipStations.WALK_SPEED)

var plan: ShipPlan
var edge_hp: PackedFloat32Array = PackedFloat32Array()   ## 0..1 per corridor piece (same order as plan.edges)
var work: PackedByteArray = PackedByteArray()            ## per module: 1 = working
var reach: PackedFloat32Array = PackedFloat32Array()     ## per module: metres from a working commander over open corridors (INF = cut off)
var comms_ok: bool = false
var engine_rooms: PackedInt32Array = PackedInt32Array()   ## modules of type ENGINE_ROOM (alive or not)
var engine_ok: bool = true                                 ## false when the ship HAS engine rooms and none works
var is_room: PackedByteArray = PackedByteArray()          ## per module: 1 = a room (needs a corridor)
var node_dist: PackedFloat32Array = PackedFloat32Array()   ## per plan node: walking metres from the nearest working commander (INF = none)


func _init(p: ShipPlan) -> void:
	plan = p
	edge_hp.resize(p.edges.size())
	edge_hp.fill(1.0)


## `types`: module type names. `hp`: Ship.module_hp. Recomputes `work` and `reach`.
func update(types: PackedStringArray, hp: PackedFloat32Array, comms: bool) -> void:
	comms_ok = comms
	var n := types.size()
	work.resize(n)
	is_room.resize(n)
	reach.resize(n)
	reach.fill(INF)
	var ok := PackedByteArray()
	ok.resize(plan.edges.size())
	for ei in plan.edges.size():
		var m: int = plan.edges[ei]["module"]
		var open := ei < edge_hp.size() and edge_hp[ei] > 0.0
		ok[ei] = 1 if open and (m < 0 or (m < n and hp[m] > 0.0)) else 0
	var sources := PackedInt32Array()
	for r in plan.rooms:
		if types[r] == ModuleCatalog.COMMANDER and r < hp.size() and hp[r] > 0.0:
			sources.append(plan.door_of(r))
	var dist := plan.distances(ok, sources)
	node_dist = dist
	for r in plan.rooms:
		var di := plan.door_of(r)
		if di >= 0:
			reach[r] = dist[di]
	engine_rooms = PackedInt32Array()
	for mi in n:
		if types[mi] == ModuleCatalog.ENGINE_ROOM:
			engine_rooms.append(mi)
	for mi in n:
		var alive_hp := mi < hp.size() and hp[mi] > 0.0
		var t := types[mi]
		is_room[mi] = 1 if plan.rooms.has(mi) else 0
		if not alive_hp or t == ModuleCatalog.LOOSE:
			work[mi] = 0
		elif t == ModuleCatalog.COMMANDER or t == ModuleCatalog.ANTENNA or is_room[mi] == 0:
			work[mi] = 1
		else:
			work[mi] = 1 if (comms or reach[mi] < INF) else 0
	engine_ok = engine_rooms.is_empty()
	for er in engine_rooms:
		if work[er] != 0:
			engine_ok = true


## True when the ship has engine rooms and none of them works any more: the thrusters get no orders.
func engines_cut() -> bool:
	return not engine_ok


func is_working(mi: int) -> bool:
	return mi < work.size() and work[mi] != 0


## Seconds until an order given by the commander reaches room `mi`. 0 with communications; INF when nobody can get there.
func order_delay(mi: int) -> float:
	if comms_ok:
		return 0.0
	if mi < is_room.size() and is_room[mi] == 0:
		if engine_rooms.is_empty() or mi >= types_size():
			return 0.0            # thrusters and antennas are not rooms: nobody walks there, they are controlled directly
		return _engine_delay()    # ... but with engine rooms the order goes to the nearest working one first
	if mi >= reach.size() or reach[mi] == INF:
		return INF
	return reach[mi] / WALK_SPEED


func types_size() -> int:
	return work.size()


## Seconds an order needs to reach the nearest WORKING engine room (INF when none can be reached).
func _engine_delay() -> float:
	var best := INF
	for er in engine_rooms:
		if er < work.size() and work[er] != 0 and er < reach.size():
			best = minf(best, reach[er] / WALK_SPEED)
	return best


## DAMAGE LINE: something travelled from `a` to `b` (ship space) through the ship, e.g. a shell that pierced the hull.
## Every corridor piece within `radius` of that line loses `amount` (0..1) of its health. Returns true if any changed.
func damage_line(a: Vector3, b: Vector3, radius: float, amount: float) -> bool:
	var changed := false
	for ei in plan.edges.size():
		if edge_hp[ei] <= 0.0:
			continue
		if plan.edge_distance_to_line(ei, a, b) <= radius:
			edge_hp[ei] = maxf(edge_hp[ei] - amount, 0.0)
			changed = true
	return changed


## Seconds a REPORT about something that happened at ship-space point `p` needs to reach a working commander: somebody
## walks from the nearest corridor node to the commander. 0 with communications; INF when no open corridor leads there.
func delay_at(p: Vector3) -> float:
	if comms_ok:
		return 0.0
	var best := INF
	var at := -1
	for ni in plan.nodes.size():
		var d := (plan.nodes[ni]["pos"] as Vector3).distance_squared_to(p)
		if d < best:
			best = d
			at = ni
	if at < 0 or at >= node_dist.size():
		return INF
	var metres := node_dist[at]
	if metres == INF:
		# the spot itself may be a wrecked room: people walk out of it through the wreck to the nearest open corridor
		for ei in plan._adj[at]:
			var e: Dictionary = plan.edges[ei]
			var other: int = e["b"] if e["a"] == at else e["a"]
			metres = minf(metres, float(e["len"]) + node_dist[other])
	return metres / WALK_SPEED if metres != INF else INF
