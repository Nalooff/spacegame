class_name ShipGyroscope
extends Node
## INTERNAL MODULE: Gyroscope. Turns and stabilises the ship and cancels the torque of
## off-centre thrusters. Torque limited per body axis.
##
## SIZE MATTERS. A ship's reaction wheels cannot turn a kilometre of steel as briskly as a fighter:
##  * the guaranteed turning acceleration falls with length as (30 m / L)^1.5  (a 30 m ship: 2 rad/s2, a 2.2 km Dreadnought: 0.003),
##  * the fastest turn the pilot may ask for falls as (30 m / L)^0.75          (30 m: 1.2 rad/s, 2.2 km: 0.05 rad/s).
## Ships up to 30 m are unchanged. Thrusters far from the centre of mass can still make more torque than that floor.

const REF_LENGTH := 30.0

var torque_max: float = 1000.0 ## N*m per axis
var alpha_max: float = 1.0     ## rad/s^2 guaranteed on the slowest axis
var omega_cap: float = 1.2     ## rad/s: fastest turn rate the pilot / autopilot asks for


func configure(worst_thruster_torque: float, inertia: Vector3, gyro_scale: float, length: float = REF_LENGTH) -> void:
	var imax := maxf(inertia.x, maxf(inertia.y, inertia.z))
	var size_k := REF_LENGTH / maxf(length, REF_LENGTH)
	torque_max = gyro_scale * maxf(worst_thruster_torque, 2.0 * pow(size_k, 1.5) * imax)
	alpha_max = torque_max / imax
	omega_cap = 1.2 * pow(size_k, 0.75)


func clamp_torque(tau: Vector3) -> Vector3:
	return Vector3(clampf(tau.x, -torque_max, torque_max), clampf(tau.y, -torque_max, torque_max),
		clampf(tau.z, -torque_max, torque_max))
