class_name ShipComms
extends Node
## INTERNAL MODULE: Communications. Works together with the ANTENNA modules: external presets (fixed signal) and the
## "room" presets (adjustable signal, they need a corridor like any room).
##
## While the signal strength (sum of the working antennas: strength per m3 x cube root of volume) reaches
## Data.COMMS_MIN_STRENGTH, `online` is true and the commander's orders reach every room INSTANTLY.
## Offline, an order has to be WALKED to the room along the corridors (PlanState.order_delay).
## The system and its antennas use electricity all the time (they are in Ship._passive_watts).

var ship: Ship
var antennas: Array[Dictionary] = []       ## {module, strength}
var strength: float = 0.0
var online: bool = false


func configure(s: Ship) -> void:
	ship = s
	antennas.clear()
	var d := s.design
	for mi in d.modules.size():
		if d.modules[mi]["type"] == ModuleCatalog.ANTENNA:
			antennas.append({"module": mi, "strength": d.stat(mi, "strength") * pow(maxf(d.module_volume(mi), 0.01), 1.0 / 3.0)})
	refresh()


## Recompute from the antennas that still work. Returns true when `online` changed.
func refresh() -> bool:
	var sum := 0.0
	for a in antennas:
		var mi: int = a["module"]
		if mi < ship.module_hp.size() and ship.module_hp[mi] > 0.0:
			sum += float(a["strength"])
	strength = sum
	var was := online
	online = sum >= Data.COMMS_MIN_STRENGTH
	return online != was
