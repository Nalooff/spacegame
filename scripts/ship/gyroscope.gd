class_name ShipGyroscope
extends Node
## INTERNAL MODULE: Gyroscope. Turns and stabilises the ship and cancels the torque of
## off-centre thrusters. Torque limited per body axis.

var torque_max: float = 1000.0 ## N*m per axis
var alpha_max: float = 1.0     ## rad/s^2 guaranteed on the slowest axis


func configure(worst_thruster_torque: float, inertia: Vector3, gyro_scale: float) -> void:
	var imax := maxf(inertia.x, maxf(inertia.y, inertia.z))
	torque_max = gyro_scale * maxf(worst_thruster_torque, 2.0 * imax)
	alpha_max = torque_max / imax


func clamp_torque(tau: Vector3) -> Vector3:
	return Vector3(clampf(tau.x, -torque_max, torque_max), clampf(tau.y, -torque_max, torque_max),
		clampf(tau.z, -torque_max, torque_max))
