class_name ShipElectricity
extends Node
## INTERNAL MODULE: Electricity. Powers thrusters, RCS, gyroscope and turrets.
## If demand exceeds supply every actuator is scaled down together (brown-out).

@export var idle_w: float = 5000.0
@export var w_per_newton: float = 6.0
@export var w_per_nm: float = 4.0
## 1.0 supplies 85 % of the ship's absolute worst-case demand (everything at full output).
@export var recommended_fraction: float = 0.85

var supply_w: float = 0.0
var full_demand_w: float = 1.0
var demand_w: float = 0.0
var factor: float = 1.0 ## this tick's brown-out scale (1 = fine)
var ratio: float = 1.0  ## sustainable fraction of full output, used by the autopilot for planning


func configure(total_thrust: float, rcs_max: float, gyro_max: float, turret_count: int, reactor_scale: float) -> void:
	full_demand_w = idle_w + w_per_newton * (total_thrust + rcs_max) + w_per_nm * 3.0 * gyro_max \
		+ turret_count * Data.TURRET_POWER_COST
	supply_w = recommended_fraction * reactor_scale * full_demand_w
	ratio = clampf((supply_w - idle_w) / maxf(full_demand_w - idle_w, 1.0), 0.02, 1.0)


## Returns the scale (0..1) to apply to thruster force, RCS force and gyro torque this tick.
func consume(thrust_n: float, rcs_n: float, torque_abs_sum: float, firing_w: float) -> float:
	demand_w = idle_w + w_per_newton * (thrust_n + rcs_n) + w_per_nm * torque_abs_sum + firing_w
	if demand_w <= supply_w:
		factor = 1.0
	else:
		factor = maxf(supply_w - idle_w, 0.0) / maxf(demand_w - idle_w, 1e-6)
	return factor
