class_name Ballistics
extends RefCounted
## Aiming maths. No state, just functions.

## Where to point a gun so a bullet of `speed` (relative to the shooter) meets a moving target.
## Solves |d + v*t| = speed*t with d = target - shooter, v = target velocity - shooter velocity (smallest t > 0).
## Returns the target position itself when there is no solution (target runs away faster than the bullet flies).
static func intercept(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3, speed: float) -> Vector3:
	var d := target_pos - shooter_pos
	var v := target_vel - shooter_vel
	var a := v.dot(v) - speed * speed
	var b := 2.0 * d.dot(v)
	var c := d.dot(d)
	var t := -1.0
	if absf(a) < 1e-6:
		if absf(b) > 1e-6:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			var t1 := (-b - sq) / (2.0 * a)
			var t2 := (-b + sq) / (2.0 * a)
			t = minf(t1, t2) if t1 > 0.0 and t2 > 0.0 else maxf(t1, t2)
	if t <= 0.0 or t > 30.0:
		return target_pos
	return target_pos + v * t        # where the target is, as seen from the (moving) shooter, after t seconds


## Like `intercept`, but the target also ACCELERATES (thrust, turning): its position after t is p + v t + a t^2 / 2.
## Fixed-point iteration on the flight time t = |target(t) - shooter - shooter_vel t| / speed, started from the
## constant-velocity answer. Returns the same kind of point as `intercept` (in the shooter's frame of motion).
static func intercept_acc(shooter_pos: Vector3, shooter_vel: Vector3, target_pos: Vector3, target_vel: Vector3, target_acc: Vector3, speed: float) -> Vector3:
	var aim := intercept(shooter_pos, shooter_vel, target_pos, target_vel, speed)
	if target_acc.length_squared() < 0.0001 or speed < 1.0:
		return aim
	var v := target_vel - shooter_vel
	var t := (aim - shooter_pos).length() / speed
	for _i in 6:
		var rel := (target_pos - shooter_pos) + v * t + target_acc * (0.5 * t * t)
		var nt := rel.length() / speed
		if absf(nt - t) < 0.001:
			t = nt
			break
		t = nt
	t = minf(t, 30.0)
	return target_pos + v * t + target_acc * (0.5 * t * t)
