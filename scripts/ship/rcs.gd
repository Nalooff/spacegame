class_name ShipRCS
extends Node
## INTERNAL MODULE: Reaction Control System. Acts exactly at the centre of mass (force only,
## no torque), any direction. Strength = 5 % of the thrust the ship can make in its best
## orientation, so it trims and brakes but can never rival the main thrusters.

var force_max: float = 0.0


func configure(best_axis_thrust: float) -> void:
	force_max = Data.RCS_FRACTION * best_axis_thrust


func clamp_force(f: Vector3) -> Vector3:
	return f.limit_length(force_max)
