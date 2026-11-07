class_name ShipHazards
extends RefCounted
## FIRE, AIR and ELECTRICAL FAULTS inside the ship, and the DOORS that hold them back. Simulated on the authority peer; the
## results live in Ship.haz_* (replicated) so every peer can draw them.
##
##   COMPARTMENT   every room and every hull / armor module (the spaces of the plan). Modules are joined by LINKS (a joint
##                 door, or a corridor that leaves a module); a link carries air and fire unless one of its doors is shut.
##   AIR           1 = full. A hit that hurts a module opens a BREACH: air leaks to space. Air also flows through open doors
##                 to the next compartment. A wrecked (dead) module leaks, a GONE module is vacuum. Below Data.HAZ_SUFFOCATE_AIR
##                 people choke.
##   FIRE          starts in a module that was hit hard (explosions, hot hits), grows while there is air, burns the module's
##                 health and the people in it, eats air, jumps through open doors, burns out when the fuel is gone or when the
##                 air is gone (a vented room puts the fire out - and kills whoever is inside). Crew in the room fight it.
##   ELECTRICAL    a hit can short a module: it does nothing until the fault is cleared (time, or a person in the room).
##   DOORS         state 0 open, 1 closed (by hand), 2 LOCKED (nobody walks through), 3 closed by the AUTOMATIC system (hit,
##                 fire or low air next to it; it opens again when everything is safe). Closed doors stop fire and air.
##                 Crew can open a closed door and walk through; ONLY a locked door stops them.
##                 The bridge can set doors while the communications work (Ship.set_door).

const OPEN := 0
const CLOSED := 1
const LOCKED := 2
const AUTO := 3

var n: int = 0
var holds: PackedByteArray = PackedByteArray()          ## per module: 1 = holds air (room or space)
var fuel: PackedFloat32Array = PackedFloat32Array()
var alert: PackedFloat32Array = PackedFloat32Array()
var breach: PackedFloat32Array = PackedFloat32Array()   ## per module 0..1 hole to space (from damage; closes when the module is repaired)
var links: Array[Dictionary] = []                      ## {a, b, doors: [door index]}
var doors: Array[Dictionary] = []                      ## {pos: Vector3, edges: [edge index], a, b (modules), joint: bool}
var neighbours: Array = []                             ## per module: Array of link indices
var _rng := RandomNumberGenerator.new()
var _acc: float = 0.0
var _built_for: ShipPlan = null


## Door list and links from the plan (deterministic: the same on every peer).
func build(plan: ShipPlan, count: int) -> void:
	_built_for = plan
	n = count
	holds.resize(n)
	holds.fill(0)
	for r in plan.rooms:
		holds[r] = 1
	for sp in plan.spaces:
		holds[sp] = 1
	fuel.resize(n)
	fuel.fill(1.0)
	alert.resize(n)
	alert.fill(0.0)
	breach.resize(n)
	breach.fill(0.0)
	links.clear()
	doors.clear()
	neighbours.clear()
	for i in n:
		neighbours.append([])
	var placed := {}                                 # edge index -> Array of placed door indices
	# 1. one door in every joint (wall doorway), in node order
	var joint_door := {}
	for ni in plan.nodes.size():
		if plan.nodes[ni]["kind"] != "joint":
			continue
		var inc: Array = plan._adj[ni]
		var mods: Array[int] = []
		for ei in inc:
			var m: int = plan.edges[ei]["module"]
			if m >= 0 and not mods.has(m):
				mods.append(m)
		joint_door[ni] = doors.size()
		doors.append({"pos": plan.nodes[ni]["pos"], "edges": inc.duplicate(), "a": mods[0] if mods.size() > 0 else -1,
			"b": mods[1] if mods.size() > 1 else -1, "joint": true, "node": ni, "t": 0.5})
	# 2. the doors the player put on corridors
	for dd in plan.doors:
		var ei: int = dd["edge"]
		var e: Dictionary = plan.edges[ei]
		var pa: Vector3 = plan.nodes[e["a"]]["pos"]
		var pb: Vector3 = plan.nodes[e["b"]]["pos"]
		if not placed.has(ei):
			placed[ei] = []
		placed[ei].append(doors.size())
		doors.append({"pos": pa.lerp(pb, float(dd["t"])), "edges": [ei], "a": int(e["module"]), "b": int(e["module"]), "joint": false, "node": -1, "t": float(dd["t"])})
	# 3. links between modules
	for ni in joint_door:
		var d: Dictionary = doors[joint_door[ni]]
		if d["a"] < 0 or d["b"] < 0 or d["a"] == d["b"]:
			continue
		var ds: Array[int] = [joint_door[ni]]
		for ei in plan._adj[ni]:
			if placed.has(ei):
				ds.append_array(placed[ei])
		_add_link(d["a"], d["b"], ds)
	for ei in plan.edges.size():                       # corridors drawn from module to module without a joint
		var e: Dictionary = plan.edges[ei]
		var ma: int = plan.nodes[e["a"]]["module"]
		var mb: int = plan.nodes[e["b"]]["module"]
		if ma >= 0 and mb >= 0 and ma != mb:
			var ds2: Array[int] = []
			if placed.has(ei):
				ds2.append_array(placed[ei])
			_add_link(ma, mb, ds2)
	_rng.seed = 424242 + n


func _add_link(a: int, b: int, ds: Array[int]) -> void:
	links.append({"a": a, "b": b, "doors": ds})
	neighbours[a].append(links.size() - 1)
	neighbours[b].append(links.size() - 1)


func is_built() -> bool:
	return n > 0


## Door states array (all open) for a new ship.
func fresh_doors() -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(doors.size())
	d.fill(OPEN)
	return d


## Edges nobody can walk through (locked doors).
static func locked_edges(h: ShipHazards, door_state: PackedByteArray, edge_count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(edge_count)
	if h == null:
		return out
	for i in mini(h.doors.size(), door_state.size()):
		if door_state[i] == LOCKED:
			for ei in h.doors[i]["edges"]:
				if ei < edge_count:
					out[ei] = 1
	return out


func link_open(ship: Ship, li: int) -> bool:
	for di in links[li]["doors"]:
		if di < ship.haz_doors.size() and ship.haz_doors[di] != OPEN:
			return false
	return true


# ------------------------------------------------------------------ events
## Authority: module `mi` took `hp_damage` of damage.
func on_hit(ship: Ship, mi: int, hp_damage: float) -> void:
	if not is_built() or mi < 0 or mi >= n or hp_damage <= 0.0 or mi >= ship.module_max_hp.size():
		return
	var frac := clampf(hp_damage / maxf(ship.module_max_hp[mi], 1.0), 0.0, 1.0)
	if frac < 0.015:
		return
	alert[mi] = Data.HAZ_ALERT_SECONDS
	for li in neighbours[mi]:
		var l: Dictionary = links[li]
		alert[l["b"] if l["a"] == mi else l["a"]] = Data.HAZ_ALERT_SECONDS * 0.7
	if holds[mi] != 0:
		breach[mi] = maxf(breach[mi], clampf(frac * 2.0 + 0.1, 0.0, 1.0))
		if _rng.randf() < clampf(frac * 3.0, 0.0, 0.9) * _flammable(ship, mi):
			ignite(ship, mi, 0.15 + frac)
	if _rng.randf() < clampf(frac * 2.5, 0.0, 0.8):
		short_out(ship, mi)


## Open a hole in module `mi` (ramming, boarding) of size 0..1.
## A HOLE stays open however healthy the module is: people have to seal it (stand in the room) or it stays.
func make_breach(ship: Ship, mi: int, size: float) -> void:
	if mi >= 0 and mi < n and holds[mi] != 0 and ship.haz_hole.size() == n:
		var h := ship.haz_hole
		h[mi] = maxf(h[mi], clampf(size, 0.0, 1.0))
		ship.haz_hole = h
		alert[mi] = Data.HAZ_ALERT_SECONDS
		ship.crew.log_event("Hull breach in module %d" % mi)


func ignite(ship: Ship, mi: int, amount: float) -> void:
	if mi < 0 or mi >= n or holds[mi] == 0 or ship.haz_air[mi] < Data.HAZ_FIRE_OUT_AIR or fuel[mi] <= 0.02:
		return
	var f := ship.haz_fire
	if f[mi] < amount:
		f[mi] = minf(amount, 1.0)
		ship.haz_fire = f
		ship.crew.log_event("Fire in module %d" % mi)


func short_out(ship: Ship, mi: int) -> void:
	if mi < 0 or mi >= n or ship.design.modules[mi]["type"] == ModuleCatalog.COMMANDER:
		return
	var e := ship.haz_elec
	if e[mi] <= 0.0:
		e[mi] = Data.HAZ_ELEC_SECONDS
		ship.haz_elec = e
		ship.crew.log_event("Electrical fault in module %d" % mi)


func _flammable(ship: Ship, mi: int) -> float:
	match str(ship.design.modules[mi]["type"]):
		ModuleCatalog.ENGINE_ROOM:
			return 1.6
		ModuleCatalog.ARMOR:
			return 0.3
		ModuleCatalog.HULL:
			return 0.7
	return 1.0


# ------------------------------------------------------------------ simulation
## Authority, called every frame; logic at 10 Hz.
func tick(ship: Ship, dt: float) -> void:
	if not is_built() or ship.haz_air.size() != n:
		return
	_acc += dt
	if _acc < 0.1:
		return
	var s := _acc
	_acc = 0.0
	var fire := ship.haz_fire
	var air := ship.haz_air
	var elec := ship.haz_elec
	var hp := ship.module_hp
	var people := _people(ship)
	var holes := ship.haz_hole
	var holes_before := holes.duplicate()
	for i in n:
		if hp[i] < 0.0:                               # gone: vacuum, nothing burns
			air[i] = 0.0
			fire[i] = 0.0
			elec[i] = 0.0
			continue
		alert[i] = maxf(alert[i] - s, 0.0)
		# the hole: a hit makes it, repairs close it, a wreck is wide open
		var hf: float = hp[i] / maxf(ship.module_max_hp[i], 1.0)
		breach[i] = minf(breach[i], maxf(1.0 - hf, 0.0) * 1.5 + (0.0 if hp[i] > 0.0 else 0.8))
		if hp[i] <= 0.0:
			breach[i] = maxf(breach[i], 0.8)
		if holes[i] > 0.0:
			breach[i] = maxf(breach[i], holes[i])
			var sealers: int = people.get(i, 0)
			if sealers > 0 and air[i] > Data.HAZ_SUFFOCATE_AIR:
				holes[i] = maxf(holes[i] - sealers * Data.HOLE_SEAL_PER_S * s, 0.0)
	# air flows through open doors
	for li in links.size():
		var l: Dictionary = links[li]
		var a: int = l["a"]
		var b: int = l["b"]
		if holds[a] == 0 or holds[b] == 0 or not link_open(ship, li):
			continue
		var flow := (air[a] - air[b]) * Data.HAZ_AIR_EQUALIZE * s * 0.5
		air[a] -= flow
		air[b] += flow
	for i in n:
		if holds[i] == 0 or hp[i] < 0.0:
			continue
		air[i] = clampf(air[i] - breach[i] * Data.HAZ_LEAK * s - fire[i] * Data.HAZ_FIRE_AIR_USE * s, 0.0, 1.0)
		if breach[i] < 0.02:
			air[i] = minf(air[i] + Data.HAZ_AIR_RECOVER * s, 1.0)
	# fire
	var spread: Array[int] = []
	for i in n:
		if fire[i] <= 0.0 or hp[i] < 0.0:
			continue
		var out := fire[i] > 0.0 and (air[i] < Data.HAZ_FIRE_OUT_AIR or fuel[i] <= 0.0)
		if out:
			fire[i] = maxf(fire[i] - 0.3 * s, 0.0)
		else:
			fire[i] = minf(fire[i] + Data.HAZ_FIRE_GROW * s * air[i], 1.0)
			fuel[i] = maxf(fuel[i] - Data.HAZ_FIRE_FUEL * fire[i] * s, 0.0)
			if hp[i] > 0.0:
				ship._remove_module_hp(i, fire[i] * Data.HAZ_FIRE_BURN * ship.module_max_hp[i] * s)
			for li in neighbours[i]:
				var l: Dictionary = links[li]
				var o: int = l["b"] if l["a"] == i else l["a"]
				if fire[o] <= 0.0 and holds[o] != 0 and link_open(ship, li) and _rng.randf() < fire[i] * Data.HAZ_FIRE_SPREAD * s:
					spread.append(o)
		var helpers: int = people.get(i, 0)
		if helpers > 0:
			fire[i] = maxf(fire[i] - helpers * Data.HAZ_EXTINGUISH * s, 0.0)
			if fire[i] <= 0.0:
				ship.crew.log_event("Fire in module %d put out" % i)
	for o in spread:
		if fire[o] <= 0.0 and air[o] >= Data.HAZ_FIRE_OUT_AIR and fuel[o] > 0.02:
			fire[o] = 0.1
	# electrical faults
	for i in n:
		if elec[i] > 0.0:
			var k: float = Data.HAZ_ELEC_CREW_X if people.get(i, 0) > 0 else 1.0
			elec[i] = maxf(elec[i] - s * k, 0.0)
			if elec[i] <= 0.0:
				ship.crew.log_event("Electrical fault in module %d cleared" % i)
			elif holds[i] != 0 and air[i] > 0.5 and fire[i] <= 0.0 and _rng.randf() < 0.01 * s:
				ignite(ship, i, 0.12)                 # sparks
	# doors
	var ds := ship.haz_doors
	if ds.size() == doors.size():
		for di in doors.size():
			var st: int = ds[di]
			if st == CLOSED or st == LOCKED:
				continue
			var danger := _door_danger(di, fire, air)
			if danger and st == OPEN:
				ds[di] = AUTO
			elif not danger and st == AUTO:
				ds[di] = OPEN
		if ds != ship.haz_doors:
			ship.haz_doors = ds
	# people
	_hurt_people(ship, fire, air, s)
	if fire != ship.haz_fire:
		ship.haz_fire = fire
	if air != ship.haz_air:
		ship.haz_air = air
	if elec != ship.haz_elec:
		ship.haz_elec = elec
	if holes != holes_before:
		ship.haz_hole = holes


func _door_danger(di: int, fire: PackedFloat32Array, air: PackedFloat32Array) -> bool:
	var d: Dictionary = doors[di]
	for m in [d["a"], d["b"]]:
		if m < 0 or m >= n:
			continue
		if fire[m] > 0.03 or alert[m] > 0.0 or air[m] < 0.8 or breach[m] > 0.03:
			return true
	return false


## module -> number of living crew standing in it
func _people(ship: Ship) -> Dictionary:
	var out := {}
	for m in ship.crew.members:
		if m["hp"] > 0.0:
			var mi := ship.crew.module_of(ship, m)
			if mi >= 0:
				out[mi] = int(out.get(mi, 0)) + 1
	return out


func _hurt_people(ship: Ship, fire: PackedFloat32Array, air: PackedFloat32Array, s: float) -> void:
	for f in ship.crew.foes:            # fire and thin air do not care whose side you are on
		if f["hp"] <= 0.0:
			continue
		var fm := ship.crew.module_of(ship, f)
		if fm < 0 or fm >= n or holds[fm] == 0:
			continue
		var fd := 0.0
		if air[fm] < Data.HAZ_SUFFOCATE_AIR:
			fd += Data.HAZ_SUFFOCATE_DPS * (1.0 - air[fm] / Data.HAZ_SUFFOCATE_AIR) * s
		if fire[fm] > 0.1:
			fd += Data.HAZ_FIRE_CREW_DPS * fire[fm] * s
		f["hp"] -= fd
	for m in ship.crew.members:
		if m["hp"] <= 0.0:
			continue
		var mi := ship.crew.module_of(ship, m)
		if mi < 0 or mi >= n or holds[mi] == 0:
			continue
		var dmg := 0.0
		var why := ""
		if air[mi] < Data.HAZ_SUFFOCATE_AIR:
			dmg += Data.HAZ_SUFFOCATE_DPS * (1.0 - air[mi] / Data.HAZ_SUFFOCATE_AIR) * s
			why = "suffocated"
		if fire[mi] > 0.1:
			dmg += Data.HAZ_FIRE_CREW_DPS * fire[mi] * s
			why = "burnt" if why == "" else why
		if dmg > 0.0:
			m["hp"] -= dmg
			if m["hp"] <= 0.0:
				ship.crew.log_event("%s %s to death" % [ShipCrew._name(m), why if why != "" else "died"])


## A person stands in module `mi` and is alive.
func manned(ship: Ship, mi: int) -> bool:
	for m in ship.crew.members:
		if m["hp"] > 0.0 and ship.crew.module_of(ship, m) == mi:
			return true
	return false
