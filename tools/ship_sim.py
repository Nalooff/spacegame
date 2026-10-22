#!/usr/bin/env python3
"""
Standalone 6-DOF spaceship physics + autopilot simulation (phase 1, v2).

Physics model
-------------
* Rigid body: mass, diagonal inertia, position, velocity, quaternion attitude,
  body-frame angular velocity (Euler's equations). Body origin = centre of mass.
* Thrusters   : ARBITRARY position (relative to CoM), direction and max power.
                Push-only, throttle 0..1. Each one applies force AT ITS POSITION,
                so it creates torque  r x F  about the CoM.
* RCS         : acts exactly at the CoM -> pure force, no torque, any direction.
                Max force = 5 % of the ship's best-orientation thrust:
                    F_best = max over unit u of  sum_i P_i * max(0, d_i . u)
                (2 x 5 N forward + 1 x 9 N backward -> F_best = 10 N, RCS = 0.5 N).
* Gyroscope   : internal torque source, limited per axis. It turns the ship and
                cancels the torque created by off-centre thrusters.
* Electricity : power budget; if demand > supply, every actuator is scaled down.
* NO speed cap anywhere: top speed is whatever the ship can brake from.

Autopilot (fly to a coordinate and stop there)
----------------------------------------------
1. Speed profile v_des(d): the fastest speed from which the ship can still stop,
   built from its braking acceleration (50 % of F_best/m), a flip-time margin that
   grows with speed, and a final RCS-only stage that meets the main stage smoothly.
2. Velocity loop      a_cmd = Kv (v_des - v).
3. Attitude           the gyroscope points the ship's BEST THRUST AXIS along a_cmd
                      (flip + retro-burn to brake).
4. Thruster allocator bounded least-squares over throttles: match the wanted force,
                      lightly penalise torque. Gyroscope feed-forward cancels the
                      remaining thruster torque.
5. RCS                supplies whatever force the thrusters could not (<= 5 % cap),
                      and does the whole job near the target.

Usage
-----
  python3 ship_sim.py [x y z]                 # one random demo ship, default 5 7 6
  python3 ship_sim.py --random 20 --seed 1    # 20 random ships / targets / attitudes
  python3 ship_sim.py --selftest
Only dependency: numpy.
"""
import argparse
import math
import numpy as np


# ----------------------------------------------------------------- math utils
def q_mul(a, b):
    w1, x1, y1, z1 = a
    w2, x2, y2, z2 = b
    return np.array([
        w1*w2 - x1*x2 - y1*y2 - z1*z2,
        w1*x2 + x1*w2 + y1*z2 - z1*y2,
        w1*y2 - x1*z2 + y1*w2 + z1*x2,
        w1*z2 + x1*y2 - y1*x2 + z1*w2])


def q_to_mat(q):
    w, x, y, z = q
    return np.array([
        [1-2*(y*y+z*z), 2*(x*y-w*z),   2*(x*z+w*y)],
        [2*(x*y+w*z),   1-2*(x*x+z*z), 2*(y*z-w*x)],
        [2*(x*z-w*y),   2*(y*z+w*x),   1-2*(x*x+y*y)]])


def q_integrate(q, omega_body, dt):
    ang = np.linalg.norm(omega_body) * dt
    if ang < 1e-12:
        return q
    axis = omega_body / np.linalg.norm(omega_body)
    dq = np.concatenate(([math.cos(ang/2)], axis * math.sin(ang/2)))
    q = q_mul(q, dq)
    return q / np.linalg.norm(q)


def clamp_vec(v, limit):
    n = np.linalg.norm(v)
    return v if n <= limit or n < 1e-12 else v * (limit / n)


def unit(v):
    v = np.asarray(v, dtype=float)
    return v / np.linalg.norm(v)


# ------------------------------------------------------------------- thrusters
class Thruster:
    def __init__(self, pos, direction, power):
        self.pos = np.asarray(pos, dtype=float)      # m, relative to CoM, body frame
        self.dir = unit(direction)                   # direction the force pushes the ship
        self.power = float(power)                    # N at full throttle


def best_thrust_axis(P, D, rng_seed=0, starts=300):
    """
    F_best = max_u h(u),  h(u) = sum_i P_i max(0, d_i.u)   (u unit, body frame).
    At a maximiser the active thrusters' net force points exactly along u, so
    the fixed point  u <- normalise(sum_{active} P_i d_i)  is found by iteration.
    """
    rng = np.random.default_rng(rng_seed)
    seeds = list(D) + [unit(rng.normal(size=3)) for _ in range(starts)]
    best_h, best_u = -1.0, None
    for u in seeds:
        u = unit(u)
        for _ in range(100):
            act = (D @ u) > 0
            if not act.any():
                break
            f = (P[act, None] * D[act]).sum(axis=0)
            n = np.linalg.norm(f)
            if n < 1e-12:
                break
            u2 = f / n
            if np.linalg.norm(u2 - u) < 1e-12:
                u = u2
                break
            u = u2
        h = float((P * np.maximum(D @ u, 0.0)).sum())
        if h > best_h + 1e-12:
            best_h, best_u = h, u
    return best_h, best_u


# ------------------------------------------------------------------- the ship
class Ship:
    RCS_FRACTION = 0.05

    def __init__(self, thrusters, mass, inertia, gyro_max=None, power_frac=1.0):
        self.th = thrusters
        self.n = len(thrusters)
        self.mass = float(mass)
        self.inertia = np.asarray(inertia, dtype=float)

        self.P = np.array([t.power for t in thrusters])
        self.D = np.array([t.dir for t in thrusters])            # n x 3
        self.R = np.array([t.pos for t in thrusters])            # n x 3
        self.A = (self.D * self.P[:, None]).T                    # 3 x n  force at full throttle
        self.B = np.cross(self.R, self.D * self.P[:, None]).T    # 3 x n  torque at full throttle

        # best-orientation thrust -> RCS size
        self.f_best, self.u_best = best_thrust_axis(self.P, self.D)
        self.rcs_max = self.RCS_FRACTION * self.f_best           # N, force only, at the CoM
        pb = np.cross(self.u_best, [1, 0, 0])
        if np.linalg.norm(pb) < 0.3:
            pb = np.cross(self.u_best, [0, 1, 0])
        self.flip_axis_body = unit(pb)                           # axis used for exact 180 deg flips

        # gyroscope must at least cancel any thruster torque and still turn the ship
        torque_worst = np.abs(self.B).sum(axis=1).max()
        self.gyro_max = float(gyro_max) if gyro_max else max(torque_worst, 2.0 * self.inertia.max())
        self.alpha_max = self.gyro_max / self.inertia.max()      # guaranteed angular accel, rad/s^2

        # electricity
        self.power_idle = 5000.0
        self.w_per_newton = 6.0
        self.w_per_nm = 4.0
        full = (self.power_idle + self.w_per_newton * (self.P.sum() + self.rcs_max)
                + self.w_per_nm * 3.0 * self.gyro_max)
        self.power_supply = power_frac * full
        self.power_factor = 1.0

        # state
        self.pos = np.zeros(3)
        self.vel = np.zeros(3)
        self.q = np.array([1.0, 0.0, 0.0, 0.0])                  # body -> world
        self.omega = np.zeros(3)                                 # body frame

    @property
    def a_best(self): return self.f_best / self.mass
    @property
    def a_rcs(self): return self.rcs_max / self.mass

    @property
    def power_ratio(self):
        """Fraction of full actuator capability the generator can sustain (1.0 = no brown-out)."""
        full = (self.power_idle + self.w_per_newton * (self.P.sum() + self.rcs_max)
                + self.w_per_nm * 3.0 * self.gyro_max)
        return float(np.clip((self.power_supply - self.power_idle) / (full - self.power_idle), 0.02, 1.0))

    def step(self, throttle, f_rcs_body, tau_gyro, dt):
        throttle = np.clip(throttle, 0.0, 1.0)
        f_rcs_body = clamp_vec(np.asarray(f_rcs_body, dtype=float), self.rcs_max)
        saturated = bool(np.any(np.abs(tau_gyro) > self.gyro_max * 1.0001))
        tau_gyro = np.clip(tau_gyro, -self.gyro_max, self.gyro_max)

        thrust = self.P * throttle                                # N per thruster
        demand = (self.power_idle + self.w_per_newton * (thrust.sum() + np.linalg.norm(f_rcs_body))
                  + self.w_per_nm * np.abs(tau_gyro).sum())
        self.power_factor = 1.0 if demand <= self.power_supply else \
            max(self.power_supply - self.power_idle, 0.0) / max(demand - self.power_idle, 1e-9)
        thrust = thrust * self.power_factor
        f_rcs_body = f_rcs_body * self.power_factor
        tau_gyro = tau_gyro * self.power_factor

        forces = self.D * thrust[:, None]                         # n x 3, body frame
        f_body = forces.sum(axis=0) + f_rcs_body                  # RCS: no torque (acts at CoM)
        tau_thr = np.cross(self.R, forces).sum(axis=0)            # thrusters: r x F
        tau = tau_thr + tau_gyro

        Rm = q_to_mat(self.q)
        self.vel += (Rm @ f_body) / self.mass * dt
        self.pos += self.vel * dt

        Iw = self.inertia * self.omega
        self.omega += (tau - np.cross(self.omega, Iw)) / self.inertia * dt
        self.q = q_integrate(self.q, self.omega, dt)
        return f_body, tau_thr, saturated


# ------------------------------------------------------------------ autopilot
class Autopilot:
    def __init__(self, ship, target):
        self.s = ship
        self.target = np.asarray(target, dtype=float)

        self.brake_frac_main = 0.5      # fraction of F_best/m used for the planned brake
        self.brake_frac_rcs = 0.5       # fraction of RCS accel used for the final brake
        self.d_fine = 1.0               # m, hand-over to RCS-only
        self.d_margin = 0.5             # m, fixed safety room
        self.kv = 2.0                   # 1/s velocity loop
        self.k_att = 6.0                # 1/s attitude rate loop
        self.k_pos_fine = 1.5
        self.align_gate = math.radians(30)   # thrusters stay off until nose is this close

        # plan with what the electrical system can really deliver (brown-out aware)
        self.pr = ship.power_ratio
        self.a_eff = ship.a_best * self.pr
        self.arcs_eff = ship.a_rcs * self.pr
        self.alpha_eff = ship.alpha_max * self.pr
        alpha = 0.6 * self.alpha_eff
        self.t_flip = 2.0 * math.sqrt(math.pi / alpha) * 0.75 + 0.2   # s, 180 deg flip budget

        self.goal = ship.u_best.copy()   # world direction the best axis should point to
        self.throttle = np.zeros(ship.n)
        # allocator matrices (force normalised by F_best, torque by F_best*L)
        fs = ship.f_best
        lref = max(float(np.linalg.norm(ship.R, axis=1).mean()), 0.1)
        ts = fs * lref
        w_tau = 0.02
        self.fs2 = fs * fs
        self.H = ship.A.T @ ship.A / self.fs2 + w_tau * ship.B.T @ ship.B / (ts * ts) \
            + 1e-5 * np.eye(ship.n)
        self.Hd = np.diag(self.H).copy()
        self.phase = "START"

    def desired_speed(self, d):
        s = self.s
        a_m = self.brake_frac_main * self.a_eff
        a_r = self.brake_frac_rcs * self.arcs_eff
        v_f = math.sqrt(2.0 * a_r * self.d_fine)
        if d > self.d_fine:
            margin = self.d_margin + self.t_flip * float(np.linalg.norm(s.vel))
            return math.sqrt(v_f**2 + 2.0 * a_m * max(d - self.d_fine - margin, 0.0))
        return min(math.sqrt(2.0 * a_r * d), self.k_pos_fine * d * 3.0)

    def attitude_torque(self, goal_dir):
        s = self.s
        Rm = q_to_mat(s.q)
        fwd = Rm @ s.u_best                                       # best axis in world frame
        axis = np.cross(fwd, goal_dir)
        sn = np.linalg.norm(axis)
        cs = float(np.dot(fwd, goal_dir))
        angle = math.atan2(sn, cs)
        if sn < 1e-6:
            axis = Rm @ s.flip_axis_body if cs < 0 else np.zeros(3)
        else:
            axis = axis / sn
        alpha = 0.6 * self.alpha_eff
        w_des = min(math.sqrt(2.0 * alpha * angle), 9.0 * angle)
        w_body = Rm.T @ (axis * w_des)                            # roll about best axis damped to 0
        return s.inertia * self.k_att * (w_body - s.omega), angle

    def allocate(self, f_des):
        """min 0.5|A t - f|^2/fs^2 + torque penalty + tiny reg, 0<=t<=1 (coordinate descent)."""
        s = self.s
        g = s.A.T @ f_des / self.fs2
        t = self.throttle.copy()
        for _ in range(200):
            delta = 0.0
            for i in range(s.n):
                ti = (g[i] - self.H[i] @ t + self.Hd[i] * t[i]) / self.Hd[i]
                ti = 0.0 if ti < 0.0 else (1.0 if ti > 1.0 else ti)
                delta = max(delta, abs(ti - t[i]))
                t[i] = ti
            if delta < 1e-7:
                break
        return t

    def update(self):
        s = self.s
        err = self.target - s.pos
        d = float(np.linalg.norm(err))
        v_des = err / d * self.desired_speed(d) if d > 1e-9 else np.zeros(3)
        a_cmd = clamp_vec(self.kv * (v_des - s.vel), self.a_eff)

        a_mag = float(np.linalg.norm(a_cmd))
        big_push = a_mag > 0.8 * self.arcs_eff
        if big_push:
            self.goal = a_cmd / a_mag

        tau_att, att_err = self.attitude_torque(self.goal)

        Rm = q_to_mat(s.q)
        f_des = s.mass * (Rm.T @ a_cmd)                           # wanted force, body frame
        if big_push and att_err < self.align_gate:
            self.throttle = self.allocate(f_des)
        else:
            self.throttle = np.zeros(s.n)
        f_thr = s.A @ self.throttle
        tau_thr = s.B @ self.throttle
        f_rcs = f_des - f_thr                                     # RCS tops up (clamped in step)
        tau_gyro = tau_att - tau_thr                              # feed-forward: cancel thruster torque

        speed = float(np.linalg.norm(s.vel))
        fired = self.throttle.sum() > 1e-6
        if not big_push:
            self.phase = "FINE-RCS"
        elif not fired:
            self.phase = "TURN"
        elif speed > 1e-3 and float(np.dot(a_cmd, s.vel)) < 0:
            self.phase = "BRAKE"
        elif speed >= 0.98 * math.sqrt(max(self.desired_speed(d), 1e-9) ** 2) and d > self.d_fine:
            self.phase = "CRUISE"
        else:
            self.phase = "ACCEL"
        return self.throttle, f_rcs, tau_gyro, att_err


# ------------------------------------------------------------------ ship factory
def random_ship(rng, power_frac=1.0):
    n = int(rng.integers(3, 11))
    mass = rng.uniform(800.0, 3000.0)
    inertia = mass * rng.uniform(0.8, 2.0, 3)
    th = []
    for _ in range(n):
        th.append(Thruster(pos=rng.uniform(-2.0, 2.0, 3),
                           direction=rng.normal(size=3),
                           power=rng.uniform(500.0, 4000.0)))
    return Ship(th, mass, inertia, power_frac=power_frac)


def describe(ship):
    print(f"mass {ship.mass:.0f} kg | inertia {np.round(ship.inertia).astype(int).tolist()} kg m^2 | "
          f"{ship.n} thrusters")
    print(f"{'#':>2} {'power[N]':>8} | {'position[m]':>22} | {'direction':>22}")
    for i, t in enumerate(ship.th):
        print(f"{i:>2} {t.power:8.0f} | {np.array2string(t.pos, precision=2):>22} | "
              f"{np.array2string(t.dir, precision=2):>22}")
    print(f"F_best {ship.f_best:.0f} N along {np.array2string(ship.u_best, precision=2)} "
          f"-> a_best {ship.a_best:.2f} m/s^2 | RCS {ship.rcs_max:.1f} N "
          f"({100*ship.rcs_max/ship.f_best:.1f}% of F_best, {ship.a_rcs:.3f} m/s^2) | "
          f"gyro {ship.gyro_max:.0f} N m ({math.degrees(ship.alpha_max):.0f} deg/s^2)")


# ------------------------------------------------------------------- simulation
def simulate(ship, target, dt=0.01, t_end=900.0, log_dt=None, csv=None, q0=None):
    if q0 is not None:
        ship.q = np.asarray(q0, dtype=float)
    ap = Autopilot(ship, target)
    tgt = np.asarray(target, dtype=float)
    start = ship.pos.copy()
    approach = unit(tgt - start)

    rows = []
    log_every = int(log_dt / dt) if log_dt else None
    if log_every:
        print(f"{'t[s]':>7} {'phase':>9} | {'x':>8} {'y':>8} {'z':>8} | {'speed':>7} {'dist':>8} | "
              f"{'thr%':>4} {'rcs%':>4} {'att°':>5}")

    settle = 0.0
    arrived = None
    peak_speed = 0.0
    max_proj = -1e18
    sat_ticks = 0
    max_tau_thr = 0.0
    n = int(t_end / dt)
    i = 0
    for i in range(n):
        thr, f_rcs, tau_g, att_err = ap.update()
        f_body, tau_thr, sat = ship.step(thr, f_rcs, tau_g, dt)
        t = (i + 1) * dt
        dist = float(np.linalg.norm(tgt - ship.pos))
        speed = float(np.linalg.norm(ship.vel))
        peak_speed = max(peak_speed, speed)
        max_proj = max(max_proj, float((ship.pos - start) @ approach))
        sat_ticks += sat
        max_tau_thr = max(max_tau_thr, float(np.linalg.norm(tau_thr)))
        if csv:
            rows.append((t, *ship.pos, *ship.vel, dist, speed, *ship.omega, *thr))
        if log_every and i % log_every == 0:
            thr_pct = 100 * (ship.P * thr).sum() / ship.P.sum()
            rcs_pct = 100 * np.linalg.norm(f_rcs) / ship.rcs_max
            print(f"{t:7.2f} {ap.phase:>9} | {ship.pos[0]:8.2f} {ship.pos[1]:8.2f} {ship.pos[2]:8.2f} | "
                  f"{speed:7.3f} {dist:8.3f} | {thr_pct:4.0f} {min(rcs_pct,999):4.0f} "
                  f"{math.degrees(att_err):5.1f}")
        if dist < 0.05 and speed < 0.05:
            settle += dt
            if settle >= 3.0:
                arrived = t - 3.0
                break
        else:
            settle = 0.0

    dist = float(np.linalg.norm(tgt - ship.pos))
    res = dict(arrived=arrived, err_cm=dist * 100, speed_cms=float(np.linalg.norm(ship.vel)) * 100,
               peak=peak_speed,
               overshoot_cm=max(0.0, max_proj - float((tgt - start) @ approach)) * 100,
               gyro_sat=sat_ticks / max(i + 1, 1), tau_thr=max_tau_thr, dist0=float(np.linalg.norm(tgt - start)))
    if csv:
        np.savetxt(csv, np.array(rows), delimiter=",", comments="",
                   header="t,x,y,z,vx,vy,vz,dist,speed,wx,wy,wz," + ",".join(f"thr{k}" for k in range(ship.n)))
    return res


# ------------------------------------------------------------------------ tests
def selftest():
    """The RCS-sizing example from the design: 2 x 5 N forward, 1 x 9 N backward."""
    th = [Thruster([0, 1, 0], [1, 0, 0], 5.0), Thruster([0, -1, 0], [1, 0, 0], 5.0),
          Thruster([0, 0, 0], [-1, 0, 0], 9.0)]
    sh = Ship(th, 100.0, [100.0, 100.0, 100.0])
    assert abs(sh.f_best - 10.0) < 1e-9 and abs(sh.rcs_max - 0.5) < 1e-9, (sh.f_best, sh.rcs_max)
    assert np.allclose(sh.u_best, [1, 0, 0], atol=1e-9)
    print("selftest OK: 5N+5N forward, 9N backward -> F_best 10 N, RCS 0.5 N (5%)")


def random_campaign(count, seed, power_frac):
    rng = np.random.default_rng(seed)
    print(f"{'#':>3} {'thr':>3} {'mass':>5} {'Fbest':>6} {'a':>5} {'rcs%':>5} | {'dist':>6} {'peak':>6} | "
          f"{'t_arr':>6} {'err[cm]':>7} {'over[cm]':>8} {'gSat%':>5}  result")
    ok = 0
    worst_over = 0.0
    for k in range(count):
        ship = random_ship(rng, power_frac)
        assert ship.rcs_max < 0.0501 * ship.f_best
        direction = unit(rng.normal(size=3))
        dist = float(np.exp(rng.uniform(math.log(5.0), math.log(300.0))))   # 5 m .. 300 m
        q0 = rng.normal(size=4)
        q0 /= np.linalg.norm(q0)
        r = simulate(ship, direction * dist, q0=q0)
        good = r["arrived"] is not None and r["err_cm"] < 5.0
        ok += good
        worst_over = max(worst_over, r["overshoot_cm"])
        print(f"{k:>3} {ship.n:>3} {ship.mass:5.0f} {ship.f_best:6.0f} {ship.a_best:5.2f} "
              f"{100*ship.rcs_max/ship.f_best:5.1f} | {r['dist0']:6.1f} {r['peak']:6.1f} | "
              f"{(r['arrived'] if r['arrived'] is not None else float('nan')):6.1f} {r['err_cm']:7.2f} "
              f"{r['overshoot_cm']:8.1f} {100*r['gyro_sat']:5.1f}  {'ok' if good else 'FAIL'}")
    print(f"\n{ok}/{count} ships stopped within 5 cm / 5 cm/s; worst overshoot {worst_over:.0f} cm")
    return ok == count


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("xyz", nargs="*", type=float, default=[5.0, 7.0, 6.0])
    p.add_argument("--random", type=int, default=0, help="run N random ships/targets")
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--power-frac", type=float, default=1.0, help="electric supply / full demand")
    p.add_argument("--log-dt", type=float, default=1.0)
    p.add_argument("--csv", default=None)
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args()
    if len(a.xyz) != 3:
        p.error("give exactly three coordinates: x y z")

    selftest()
    if a.selftest:
        raise SystemExit(0)
    if a.random:
        raise SystemExit(0 if random_campaign(a.random, a.seed, a.power_frac) else 1)

    rng = np.random.default_rng(a.seed)
    ship = random_ship(rng, a.power_frac)
    q0 = rng.normal(size=4)
    q0 /= np.linalg.norm(q0)
    describe(ship)
    print(f"\nTarget {tuple(a.xyz)} from (0,0,0), random initial attitude\n")
    r = simulate(ship, a.xyz, log_dt=a.log_dt, csv=a.csv, q0=q0)
    print("\n=== RESULT ===")
    print(f"arrived at t = {r['arrived']:.2f} s" if r["arrived"] is not None else "DID NOT SETTLE")
    print(f"final position error : {r['err_cm']:.2f} cm | final speed {r['speed_cms']:.2f} cm/s")
    print(f"peak speed           : {r['peak']:.2f} m/s (no cap)")
    print(f"overshoot            : {r['overshoot_cm']:.1f} cm")
    print(f"max thruster torque  : {r['tau_thr']:.0f} N m | gyro saturated {100*r['gyro_sat']:.1f}% of ticks")
    raise SystemExit(0 if r["arrived"] is not None else 1)
