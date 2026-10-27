class_name ShipDetection
extends Node
## INTERNAL MODULE: Detection. Finds every other ship, classes it FRIENDLY or ENEMY and keeps a list of CONTACTS.
##
## HOW A SHIP IS DETECTED
##   * By VIEW (always, no radar needed): anything within Data.VIEW_RANGE. Ships farther than that are not even RENDERED
##     (see Ship.set_rendered), and ships farther than Data.NET_RANGE do not even exchange data (Ship._net_filter).
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
var locked: Ship = null

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
		other.set_rendered(dist <= Data.VIEW_RANGE)
		if other.is_wreck() or dist > Data.NET_RANGE:
			continue
		var best_how := ""
		var best_prec := 0.0
		if dist <= Data.VIEW_RANGE:
			best_how = "view"
			best_prec = Data.VIEW_PRECISION * (1.0 - 0.5 * dist / Data.VIEW_RANGE)
		for r in radars:
			var eff := radar_range(r, other)
			if dist <= minf(eff, Data.NET_RANGE):
				var prec: float = float(r["precision"]) * (1.0 - 0.5 * dist / maxf(eff, 1.0))
				if prec > best_prec:
					best_prec = prec
					best_how = r["kind"]
		if best_how == "":
			continue
		contacts.append({
			"ship": other, "dist": dist, "how": best_how, "precision": best_prec,
			"friendly": Net.are_friends(my_owner, other.get_multiplayer_authority()) if not Net.players.is_empty() else false,
			"est_pos": other.global_position + _noise(other, 1, (1.0 - best_prec) * dist * 0.03),
			"est_vel": other.linear_velocity + _noise(other, 2, (1.0 - best_prec) * (other.linear_velocity.length() * 0.25 + 3.0)),
		})
	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	if locked != null and (not is_instance_valid(locked) or find_contact(locked).is_empty()):
		locked = null
	contacts_changed.emit()


## How far radar `r` sees `target`, given what the target gives off.
func radar_range(r: Dictionary, target: Ship) -> float:
	var sig := target.sig_elec if r["kind"] == "electronic" else target.sig_heat
	var ref := Data.ELEC_REF_W if r["kind"] == "electronic" else Data.HEAT_REF_W
	return float(r["range"]) * clampf(sqrt(maxf(sig, 1.0) / ref), Data.SIGNATURE_MIN_MULT, Data.SIGNATURE_MAX_MULT)


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
	return Ballistics.intercept(ship.global_position, ship.linear_velocity, c["est_pos"], c["est_vel"], muzzle_speed)
