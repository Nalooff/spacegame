extends Node
## Autoload "BusEvent": a global signal hub. Nodes announce things here and any other node
## can listen, so scripts do not need to know about each other.
##
##   emit:    BusEvent.ship_died.emit(ship)
##   listen:  BusEvent.ship_died.connect(_on_ship_died)

## The ship flown by THIS player changed (spawned, respawned, or removed -> null).
signal local_ship_changed(ship: Ship)
## Any ship (local or remote) finished setting itself up.
signal ship_spawned(ship: Ship)
## A ship's Commander was destroyed.
signal ship_died(ship: Ship)
## One external module of a ship reached 0 HP.
signal module_destroyed(ship: Ship, module_index: int)
## A ship's autopilot reached its target and stopped.
signal autopilot_arrived(ship: Ship)
## A ship took a DamageHit. `result` says how much HP was lost / how deep the dent is.
signal ship_hit(ship: Ship, hit: DamageHit, result: DamageResult)
## A ship's hull was dented (vertices moved).
signal ship_deformed(ship: Ship, module_index: int)
## Short text for the player (HUD shows it for a few seconds).
signal notify(text: String)

## Ship builder events
signal builder_design_saved(ship_name: String)
signal builder_selection_changed
signal builder_design_changed
