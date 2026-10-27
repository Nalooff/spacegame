class_name ShipStations
extends Node
## CONTROL MODES and STATIONS of the player who flies this ship.
##
##   COMMANDER mode  You give orders. Autopilot, radar and gunnery are automatic (the guns pick the nearest enemy, lead
##                   it and fire; the ship flies to where you tell it with the autopilot panel). Third-person camera only,
##                   no first person.
##   CREW mode       You are the pilot, in first person, standing in ONE station at a time:
##                     * a COMMANDER module  = the pilot seat: you fly the ship (manual thrust / rotation).
##                       If a turret base is LINKED to that commander in the editor you can fire that turret from here.
##                     * a TURRET base       = the gun station: aim with the mouse, click to fire the barrels of that base.
##                   Changing station takes time: you WALK there (WALK_SPEED metres per second through the ship), you
##                   cannot do anything on the way. A linked turret saves you the walk.
##
## Keys: V = switch mode, F = go to the next station. Everything here only describes WHERE the player is; Ship reads it
## (can_fly(), active_base()) and StationCamera shows it.

signal changed

const WALK_SPEED := 2.5          ## metres per second
const MIN_WALK_TIME := 0.6
const EYE_CLEARANCE := 0.5      ## metres above the roof of the station's module

var ship: Ship
var mode: String = "commander"   ## "crew" or "commander" - a ship starts in COMMANDER view (V switches)
var stations: Array[Dictionary] = []   ## {module, kind: "pilot"|"gun", pos (ship space), label}
var current: int = 0
var walking: bool = false

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _dur: float = 1.0
var _t: float = 0.0
var _target: int = 0


func configure(s: Ship) -> void:
	ship = s
	rebuild()


## List the stations from the modules that are still alive. Keeps the player where they were when possible.
func rebuild() -> void:
	var keep_module := -1
	if current >= 0 and current < stations.size():
		keep_module = int(stations[current]["module"])
	stations.clear()
	var d := ship.design
	var mine := ship.my_commander()       # a player only reaches what THEIR commander is linked to (-1 = everything)
	for mi in d.modules.size():
		if not ship.is_working(mi):
			continue
		var t: String = d.modules[mi]["type"]
		if t == ModuleCatalog.COMMANDER:
			if mine >= 0 and mi != mine:
				continue              # somebody else's bridge
			var linked := d.linked_turrets(mi)
			var label := ("Pilot seat (module %d)" if d.can_pilot(mi) else "Gunner bridge (module %d)") % mi
			if not linked.is_empty():
				label += "  + turrets %s linked" % str(linked)
			stations.append({"module": mi, "kind": "pilot", "pos": _eye_above(d, mi, Vector3.UP), "label": label})
		elif t == ModuleCatalog.TURRET and not d.barrels_of(mi).is_empty() and d.controls(mine, mi):
			stations.append({"module": mi, "kind": "gun", "pos": _eye_above(d, mi, d.modules[mi]["dir"]), "label": "Gun station (turret %d)" % mi})
	current = 0
	for i in stations.size():
		if int(stations[i]["module"]) == keep_module:
			current = i
	if walking and _target >= stations.size():
		walking = false
	changed.emit()


## The eyes sit just above the module along `up` (the hull is not see-through from inside, so the view is from its roof).
func _eye_above(d: ShipDesign, mi: int, up: Vector3) -> Vector3:
	var c := d.module_centroid(mi)
	var u := up.normalized() if up.length() > 0.001 else Vector3.UP
	var reach := 0.0
	for p in d.module_points(mi):
		reach = maxf(reach, (p - c).dot(u))
	return c + u * (reach + EYE_CLEARANCE)


func current_station() -> Dictionary:
	return stations[current] if current < stations.size() else {}


func is_commander_mode() -> bool:
	return mode == "commander"


func toggle_mode() -> void:
	mode = "commander" if mode == "crew" else "crew"
	walking = false
	changed.emit()


## Seconds needed to walk from the current station to station `i`.
func travel_time(i: int) -> float:
	if i < 0 or i >= stations.size() or current >= stations.size():
		return 0.0
	return maxf(((stations[i]["pos"] as Vector3) - (stations[current]["pos"] as Vector3)).length() / WALK_SPEED, MIN_WALK_TIME)


func go_to(i: int) -> void:
	if walking or i < 0 or i >= stations.size() or i == current:
		return
	_from = stations[current]["pos"]
	_to = stations[i]["pos"]
	_dur = travel_time(i)
	_t = 0.0
	_target = i
	walking = true
	changed.emit()


## Walk to the next station in the list.
func next_station() -> void:
	if stations.size() > 1:
		go_to((current + 1) % stations.size())


func _physics_process(dt: float) -> void:
	if not walking:
		return
	_t += dt
	if _t >= _dur:
		walking = false
		current = _target
		changed.emit()


## Where the player's eyes are (ship space) - on the way while walking.
func eye_position() -> Vector3:
	if walking:
		return _from.lerp(_to, clampf(_t / _dur, 0.0, 1.0))
	var s := current_station()
	return s.get("pos", Vector3.ZERO)


## 0..1 progress of the walk.
func walk_progress() -> float:
	return clampf(_t / _dur, 0.0, 1.0) if walking else 1.0


## Can the player fly the ship (thrust / rotation keys)? Only crew mode, standing in a pilot seat.
func can_fly() -> bool:
	if mode != "crew":
		return false
	return not walking and current_station().get("kind", "") == "pilot" and ship.design.can_pilot(int(current_station()["module"]))


## Which turret base the player's guns are: -2 = all of them (commander mode: automatic gunnery),
## -1 = none (walking, or in a pilot seat without a linked turret), otherwise the module index of the base,
## -3 = several: the turrets linked to the commander (see active_set()).
func active_base() -> int:
	if mode == "commander":
		return -2
	if walking:
		return -1
	var s := current_station()
	if s.is_empty():
		return -1
	if s["kind"] == "gun":
		return int(s["module"])
	var linked := ship.design.linked_turrets(int(s["module"]))
	if linked.is_empty():
		return -1
	return linked[0] if linked.size() == 1 else -3


## The turret bases the player's guns are, as a list (see active_base()).
func active_set() -> PackedInt32Array:
	var out := PackedInt32Array()
	var b := active_base()
	if b >= 0:
		out.append(b)
	elif b == -3:
		for l in ship.design.linked_turrets(int(current_station()["module"])):
			out.append(l)
	return out


## Sets which turrets of `t` take part in aiming and firing for the player. With crew aboard (or in commander view)
## the owner works the turrets of their commander: all of them when nothing is linked.
func apply_filter(t: ShipTurrets, crew_aboard: bool) -> void:
	t.filter_set = PackedInt32Array()
	if mode == "commander" or crew_aboard:
		var mine := ship.my_commander()
		if ship.design.has_links() and mine >= 0:
			t.filter_base = -3
			t.filter_set = ship.bases_of_seat(mine)
		else:
			t.filter_base = -2
		return
	t.filter_base = active_base()
	if t.filter_base == -3:
		t.filter_set = active_set()


func status_text() -> String:
	if mode == "commander":
		return "COMMANDER  (autopilot, radar and guns are automatic)   V: switch to crew"
	if walking:
		return "CREW  walking to %s ... %.1f s" % [stations[_target]["label"], _dur * (1.0 - walk_progress())]
	var s := current_station()
	var extra := ""
	if stations.size() > 1:
		extra = "   F: next station (%.1f s walk)" % travel_time((current + 1) % stations.size())
	return "CREW  %s%s   V: commander mode" % [s.get("label", "no station"), extra]
