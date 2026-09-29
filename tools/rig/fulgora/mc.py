"""Monte Carlo model of a Fulgora starter base powered by lightning.

Calibrated by rig measurements:
  - strike-rate profile per 0.05 daytime bucket, per isolated collector / rod
  - per-strike transfer: attractor energy E leaves at (A + drain) per tick, A to
    the network (load + accumulator charge room), drain 2.5 MJ/tick lost.
  - solar: panels * 60 kW * 0.2 (Fulgora solar-power 20%), linear ramps
    dusk 0.25 -> evening 0.45, morning 0.55 -> dawn 0.75.
Vectorised over N independent bases; dt ticks per step.
"""
import json, math, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PROF = json.load(open(os.path.join(HERE, "rate_profile.json")))
TPD = 10800


def solar_frac(t):
    t = t % 1.0
    return np.where(t < 0.25, 1.0, np.where(t < 0.45, 1 - (t - 0.25) / 0.2,
           np.where(t < 0.55, 0.0, np.where(t < 0.75, (t - 0.55) / 0.2, 1.0))))


def union_factor(points, r=35.0, res=0.5):
    """Area of the union of discs (radius r) around points, over one disc's area."""
    xs = [p[0] for p in points]; ys = [p[1] for p in points]
    gx = np.arange(min(xs) - r, max(xs) + r, res); gy = np.arange(min(ys) - r, max(ys) + r, res)
    X, Y = np.meshgrid(gx, gy)
    m = np.zeros_like(X, dtype=bool)
    for px, py in points:
        m |= (X - px) ** 2 + (Y - py) ** 2 <= r * r
    return m.sum() * res * res / (math.pi * r * r)


def simulate(load_kw, panels, n_acc, acc_mj, acc_in_kw, acc_out_kw=300, att_mj=400, att_drain_kj=2500,
             att_buf_mj=1000, kind="col", area_factor=1.0, days=30, n=400, dt=5, seed=1, start_full=True,
             extra_acc=None, robo_kw=200, robo_buf_mj=400, robo_in_kw=20000):
    """Returns dict with per-base shortfall-day counts, min storage stats."""
    rng = np.random.default_rng(seed)
    prof = np.array(PROF[kind]) * area_factor / 1000.0  # strikes per tick per attractor-set
    C = n_acc * acc_mj * 1e6
    IN = n_acc * acc_in_kw * 1e3 / 60 * dt       # J per step
    OUT = n_acc * acc_out_kw * 1e3 / 60 * dt
    if extra_acc:  # (count, mj, in_kw, out_kw) second accumulator group, merged
        c2, m2, i2, o2 = extra_acc
        C += c2 * m2 * 1e6; IN += c2 * i2 * 1e3 / 60 * dt; OUT += c2 * o2 * 1e3 / 60 * dt
    L = load_kw * 1e3 / 60 * dt
    RU = robo_kw * 1e3 / 60 * dt
    LO = L - RU
    RB = robo_buf_mj * 1e6
    RIN = robo_in_kw * 1e3 / 60 * dt
    R = np.full(n, RB)
    robo_min = np.full(n, RB)
    SOL = panels * 60e3 * 0.2 / 60 * dt
    DR = att_drain_kj * 1e3 * dt
    BUF = att_buf_mj * 1e6
    E = np.full(n, C if start_full else 0.0)
    A = np.zeros(n)
    steps = days * TPD // dt
    short_steps = np.zeros(n, dtype=np.int64)
    short_days = np.zeros(n, dtype=np.int64)
    day_short = np.zeros(n, dtype=bool)
    day_min = np.full(n, np.inf)
    mins = []
    captured = 0.0
    for k in range(steps):
        tick = k * dt
        t = (tick % TPD) / TPD
        # strikes
        lam = prof[min(int(t * 20), 19)] * dt
        if lam > 0:
            hits = rng.poisson(lam, n)
            A = np.minimum(A + hits * att_mj * 1e6, BUF)
        sol = SOL * float(solar_frac(t))
        # secondary-input demand: other loads + roboport buffer refill
        R = np.maximum(R - RU, 0.0)
        rdem = np.minimum(RIN, RB - R)
        need = LO + rdem
        s_use = np.minimum(sol, need)
        rem = need - s_use
        surplus = sol - s_use
        room = np.minimum(IN, C - E)
        da = rem + np.maximum(room - surplus, 0.0)
        tot = da + DR
        give = np.where(A >= tot, da, A * da / np.maximum(tot, 1e-9))
        drain = np.where(A >= tot, DR, A * DR / np.maximum(tot, 1e-9))
        A = np.maximum(A - give - drain, 0.0)
        from_att_to_load = np.minimum(give, rem)
        rem_v = rem - from_att_to_load
        charge = np.minimum(room, surplus + (give - from_att_to_load))
        captured += float(np.sum(give))
        E = E + charge
        d = np.minimum(np.minimum(rem_v, OUT), E)
        E = E - d
        rem_v = rem_v - d
        served = need - rem_v
        frac = np.where(need > 0, served / np.maximum(need, 1e-9), 1.0)
        R = R + rdem * frac
        robo_min = np.minimum(robo_min, R)
        sh = (rem_v > 1.0) & (E <= 0)
        short_steps += sh
        day_short |= sh
        day_min = np.minimum(day_min, E)
        if (tick + dt) % TPD == 0:
            short_days += day_short
            day_short[:] = False
            mins.append(day_min.copy())
            day_min[:] = np.inf
    mins = np.array(mins)  # days x n
    return {"short_days": int(short_days.sum()), "base_days": n * days,
            "short_frac_ticks": float(short_steps.sum()) / (n * steps),
            "min_mj_p50": float(np.percentile(mins[1:], 50) / 1e6),
            "min_mj_p01": float(np.percentile(mins[1:], 1) / 1e6),
            "min_mj_min": float(mins[1:].min() / 1e6),
            "robo_min_mj": float(robo_min.min() / 1e6), "robo_low_bases": int((robo_min < RB - 1e6).sum()),
            "att_kw": captured / (n * steps * dt) * 60 / 1e3}


if __name__ == "__main__":
    print(simulate(1080, 23, 16, 5, 300, days=10, n=200))
