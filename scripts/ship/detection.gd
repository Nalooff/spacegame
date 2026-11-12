class_name ShipDetection
extends Node
## INTERNAL MODULE: Detection. Finds every other ship, classes it FRIENDLY or ENEMY and keeps a list of CONTACTS.
##
## HOW A SHIP IS DETECTED
##   * By VIEW (always, no radar needed): anything within Data.VIEW_RANGE. Ships farther than that are not even RENDERED
##     (see Ship.set_rendered), and ships farther than Data.net_range do not even exchange data (Ship._net_filter).
##   * By RADAR (the external Radar modules of the ship, they use this module):
##       electronic radar  looks at the ELECTRICITY the target uses       (Ship.sig_elec)
##       thermal radar     looks at the HEAT the target gives off         (Ship.sig_heat): thrusters, firing weapons...
##     range = radar range (range_per_m x cube root of its volume) x multiplier from the target's signature
##     (sqrt(signature / reference), between Data.SIGNATURE_MIN_MULT and MAX_MULT). A ship that uses a lot of electricity
##     is seen from far away; a ship that drifts with everything off is hard to see.
##
## PRECISION: every contact has a precision 0..1. The position / velocity we know are the true ones plus a slowly
## changing error of (1 - precision), so a bad radar makes the turrets miss (Ballistics.intercept uses them).
##
## LOCK: cycle_lock() picks the next enemy contact. While a target is locked the turrets aim at the PREDICTED
## position (lead) instead of the mouse. See Ship._authority_step.
##
## Runs on the peer that flies this ship (pilot or crew). Contacts: Array of
##   {ship: Ship, friendly: bool, dist: float, how: "view"|"electronic"|"thermal", precision: float, est_pos, est_vel}

signal contacts_changed

var ship: Ship
var contacts: Array[Dictionary] = []
var locked: Ship = null:
	set(v):
		if v != locked:
			target_module = -1
		locked = v
## AIMING AT A PART: the module of the locked ship the guns try to hit (-1 = the ship as a whole). Only taken into
## account while the target is close enough to be SEEN (Data.VIEW_RANGE); a radar alone only knows the average point of
## the heat / electricity the ship produces (Ship.sig_heat_pt / sig_elec_pt), so that is where the guns aim.
var target_module: int = -1

var _prev: Dictionary = {}                 # ship instance id -> {vel, t, acc}: to estimate how a target accelerates
var _radars: Array[Dictionary] = []        # {module, kind, range, precision}
var _timer: float = 0.0


func configure(s: Ship) -> void:
	ship = s
	_radars.clear()
	var d := s.design
	for mi in d.modules.size():
		if d.modules[mi]["type"] != ModuleCatalog.RADAR:
			continue
		_radars.append({"module": mi, "kind": d.kind_of(mi), "range": d.stat(mi, "range_per_m") * pow(maxf(d.module_volume(mi), 0.01), 1.0 / 3.0),
			"precision": clampf(d.stat(mi, "precision"), 0.0, 1.0)})


## Radar modules that still work.
func working_radars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _radars:
		var mi: int = r["module"]
		if ship.is_working(mi):
			out.append(r)
	return out


func _physics_process(dt: float) -> void:
	if ship == null or not ship.alive or not ship.is_flown_by_me():
		return
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = Data.DETECTION_INTERVAL
	scan()


## One scan of every ship in the world.
func scan() -> void:
	contacts.clear()
	var radars := working_radars()
	var mine := ship.global_position
	var my_owner := ship.get_multiplayer_authority()
	for node in ship.get_tree().get_nodes_in_group("ships"):
		var other := node as Ship
		if other == null or other == ship or not other.alive:
			continue
		if other.is_stale():
			other.set_rendered(false)
			continue
		var dist := mine.distance_to(other.global_position)
		var sdist := maxf(dist - other.radius_m, 0.0)                   # to its HULL, not to its middle: a 2 km ship is not "far" while you scrape its side
		var vr := Data.view_range_for(other.radius_m * 2.0)
		other.set_rendered(sdist <= vr)
		if other.is_wreck() or sdist > Data.net_range:
			continue
		var best_how := ""
		var best_prec := 0.0
		if sdist <= vr:
			best_how = "view"
			best_prec = Data.VIEW_PRECISION * (1.0 - 0.5 * sdist / vr)
		for r in radars:
			var eff := radar_range(r, other)
			if sdist <= minf(eff, Data.net_range):
				var prec: float = float(r["precision"]) * (1.0 - 0.5 * sdist / maxf(eff, 1.0))
				if prec > best_prec:
					best_prec = prec
					best_how = r["kind"]
		if best_how == "":
			continue
		var acc := _acceleration(other)
		var seen := sdist <= vr
		var aim_off := Vector3.ZERO                 # from the ship's centre to the point the guns aim at (world frame)
		if seen:
			if other == locked and target_module >= 0 and target_module < other.design.modules.size() and other.module_hp.size() > target_module and other.module_hp[target_module] >= 0.0:
				aim_off = other.global_transform.basis * (other.design.module_centroid(target_module) - other._com)
		else:
			var pt: Vector3 = other.sig_heat_pt if best_how == "thermal" else (other.sig_elec_pt if best_how == "electronic" else other._com)
			aim_off = other.global_transform.basis * (pt - other._com)
		contacts.append({
			"visible": seen, "aim_off": aim_off, "stamp": Time.get_ticks_msec(), "est_acc": acc * (best_prec * 0.8),
			"ship": other, "dist": dist, "how": best_how, "precision": best_prec,
			"friendly": Net.are_friends(my_owner, other.get_multiplayer_authority()) if not Net.players.is_empty() and not other.is_drone() else false,
			"est_pos": other.global_position + _noise(other, 1, (1.0 - best_prec) * dist * 0.03),
			"est_vel": other.linear_velocity + _noise(other, 2, (1.0 - best_prec) * (other.linear_velocity.length() * 0.25 + 3.0)),
		})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	if locked != null and (not is_instance_valid(locked) or find_contact(locked).is_empty()):
		locked = null
	contacts_changed.emit()


## Smoothed acceleration of `other` from its velocity at the last two scans.
func _acceleration(other: Ship) -> Vector3:
	var id := other.get_instance_id()
	var now := Time.get_ticks_msec() * 0.001
	var rec: Dictionary = _prev.get(id, {})
	var acc := Vector3.ZERO
	if not rec.is_empty() and now - float(rec["t"]) > 0.05:
		var raw: Vector3 = (other.linear_velocity - (rec["vel"] as Vector3)) / (now - float(rec["t"]))
		acc = (rec["acc"] as Vector3).lerp(raw, 0.4)
		if acc.length() > 40.0:
			acc = acc.normalized() * 40.0
	_prev[id] = {"vel": other.linear_velocity, "t": now, "acc": acc}
	return acc


## The contact's position / velocity NOW: the scan is a few hundred ms old, the target did not stand still meanwhile.
func fresh(c: Dictionary) -> Array:
	var age := clampf((Time.get_ticks_msec() - int(c.get("stamp", Time.get_ticks_msec()))) * 0.001, 0.0, 1.0)
	var v: Vector3 = c["est_vel"]
	var a: Vector3 = c.get("est_acc", Vector3.ZERO)
	return [(c["est_pos"] as Vector3) + (c.get("aim_off", Vector3.ZERO) as Vector3) + v * age + a * (0.5 * age * age), v + a * age, a]


## How far radar `r` sees `target`, given what the target gives off.
func radar_range(r: Dictionary, target: Ship) -> float:
	var sig := target.sig_elec if r["kind"] == "electronic" else target.sig_heat
	var ref := Data.ELEC_REF_W if r["kind"] == "electronic" else Data.HEAT_REF_W
	return float(r["range"]) * ship.role_bonus(int(r["module"])) * clampf(sqrt(maxf(sig, 1.0) / ref), Data.SIGNATURE_MIN_MULT, Data.SIGNATURE_MAX_MULT)


## Slowly drifting error vector of the given size (stable between scans, different per target and per quantity).
func _noise(target: Ship, salt: int, size: float) -> Vector3:
	var t := Time.get_ticks_msec() * 0.0004 + float(target.get_instance_id() % 997) + salt * 17.0
	return Vector3(sin(t * 1.3), sin(t * 0.9 + 2.0), sin(t * 1.7 + 4.0)) * size


func find_contact(target: Ship) -> Dictionary:
	for c in contacts:
		if c["ship"] == target:
			return c
	return {}


func enemies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in contacts:
		if not c["friendly"] and is_instance_valid(c["ship"]):   # a contact may have been freed since the last scan
			out.append(c)
	return out


## Aim at the next module of the locked ship (none -> first -> ... -> the whole ship again). Only works while it is visible.
func cycle_module() -> void:
	if locked == null or not is_instance_valid(locked):
		return
	var c := find_contact(locked)
	if c.is_empty() or not bool(c.get("visible", false)):
		target_module = -1
		return
	var n := locked.design.modules.size()
	var i := target_module
	for _k in n + 1:
		i += 1
		if i >= n:
			target_module = -1
			return
		if i < locked.module_hp.size() and locked.module_hp[i] >= 0.0 and locked.design.modules[i]["type"] != ModuleCatalog.LOOSE:
			target_module = i
			return
	target_module = -1


func target_module_name() -> String:
	if locked == null or target_module < 0 or target_module >= locked.design.modules.size():
		return ""
	return "%s %d" % [str(locked.design.modules[target_module]["type"]), target_module]


## Lock the next enemy (closest first); after the last one the lock is released.
func cycle_lock() -> void:
	var list := enemies()
	if list.is_empty():
		locked = null
		return
	var idx := -1
	for i in list.size():
		if list[i]["ship"] == locked:
			idx = i
	idx += 1
	locked = list[idx]["ship"] if idx < list.size() else null


## World point to aim at for a bullet of `muzzle_speed` so that it meets the locked target (lead), or ZERO.
func lead_point(muzzle_speed: float) -> Vector3:
	if locked == null:
		return Vector3.ZERO
	var c := find_contact(locked)
	if c.is_empty():
		return Vector3.ZERO
	var f := fresh(c)
	return Ballistics.intercept_acc(ship.global_position, ship.linear_velocity, f[0], f[1], f[2], muzzle_speed)
