#!/usr/bin/env python3
"""Measure the Brave New MTS starter base's sustainable power on each planet.

Needs a server started from a mods dir staged with `stage.sh --hooks` (for the
bnm-rig-load test prototype). For every planet it builds several copies of the
starter base, one per team slot, each on that team's own planet surface
(mts-<planet>-<slot>), using BNM's real placement function:

    slot 1       idle run: no test load (measures idle draw, freezing, lightning)
    slots 2..9   load sweep: base idle + a constant test load, 8 levels in parallel
    slot 10      saturating run: 100 MW test load (the plant's raw energy per cycle)
    slot 11      Fulgora only: construction bots kept flying (lightning vs robots)

Every run starts at noon with full accumulators and a full roboport and lasts
`--cycles` full day/night cycles. A run is SUSTAINED when, in every cycle, the
accumulators never drop below 0.1% of capacity, the roboport ends the cycle at
least as full as it started, and the test load got >= 99.5% of what it asked for.
After the first round the sweep slots are re-run between the highest passing
and lowest failing load (--rounds times), reusing the same bases.

usage: power_test.py [--port 27311] [--planets nauvis,vulcanus,...] [--rounds 2]
                     [--cycles 3] [--speed 1000] [--out results.json]
"""
import argparse
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe import Rig, bnm_mod  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))

# Analytic model from the design notes (sustained total, idle included, kW) and
# the first-round TEST-load sweep range per planet (kW, added on top of idle).
PLANETS = {
    "nauvis":   {"model": 865,  "sweep": (300, 1000)},
    "vulcanus": {"model": 3821, "sweep": (2600, 4800)},
    "gleba":    {"model": 1092, "sweep": (600, 1000)},
    "fulgora":  {"model": 202,  "sweep": (25, 600)},
    "aquilo":   {"model": 1313, "sweep": (800, 1200)},
}
SWEEP_SLOTS = list(range(2, 10))
SAT_SLOT, BUSY_SLOT = 10, 11
SAT_KW = 100000
NON_LOAD = ("accumulator", "bnm-rig-load")


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def linspace(lo, hi, n):
    return [round(lo + (hi - lo) * i / (n - 1)) for i in range(n)]


def setup_run(rig, planet, slot, load_kw, cycles, **extra):
    force = "team-%d" % slot
    sname = rig.eval('RIG.create_surface("%s", %d)' % (planet, slot))
    rig.sc('%s.place("%s", game.surfaces["%s"])' % (bnm_mod("scripts.starter_base"), force, sname), state="bnm")
    opts = {"force": force, "planet": planet, "slot": slot, "load_kw": load_kw, "cycles": cycles}
    opts.update(extra)
    lua_opts = "{" + ",".join("%s=%s" % (k, json.dumps(v)) for k, v in opts.items()) + "}"
    info = rig.eval('RIG.add_run("%s", %s)' % (sname, lua_opts))
    if info["load_network"] != info["base_network"]:
        raise RuntimeError("test load on %s is not on the base's electric network" % sname)
    return sname


def wait_all(rig, poll=3.0):
    last = 0
    while True:
        s = rig.eval("RIG.status()")
        if s["done"] >= s["total"]:
            return s
        if time.time() - last > 20:
            log("  %d/%d runs done, %d ticks left (tick %d)" % (s["done"], s["total"], s["ticks_left"], s["tick"]))
            last = time.time()
        time.sleep(poll)


def evaluate(rep):
    """Summarise one run report: average total draw, idle draw, pass/fail."""
    cyc = rep["cycles"]
    n = len(cyc)
    if n == 0:
        return {"ok": False, "why": "no complete cycle"}
    total = sum(sum(v for k, v in c["cons"].items() if k != "accumulator") for c in cyc) / n
    idle = sum(sum(v for k, v in c["cons"].items() if k not in NON_LOAD) for c in cyc) / n
    load_got = sum(c["cons"].get("bnm-rig-load", 0) for c in cyc) / n
    prod = {}
    for c in cyc:
        for k, v in c["prod"].items():
            if k != "accumulator":
                prod[k] = prod.get(k, 0) + v / n
    why = []
    emptied = sum(1 for c in cyc if c["empty_samples"] > 0)
    if emptied:
        why.append("accumulators emptied in %d/%d cycles" % (emptied, n))
    # Steady state: after the first cycle (which starts from a full, noon
    # charge that is not the steady-state noon level), the accumulators must
    # not end a cycle lower than they started it. Otherwise the load is above
    # the plant's energy per cycle and only the initial charge is carrying it.
    drift = sum(c["acc_end_mj"] - c["acc_start_mj"] for c in cyc[1:])
    if n > 1 and drift < -0.5:
        why.append("accumulators drifting %.1f MJ over cycles 2..%d" % (drift, n))
    if any(c["robo_end_mj"] < c["robo_start_mj"] - 0.5 for c in cyc):
        why.append("roboport buffer fell %.1f MJ" % (cyc[0]["robo_start_mj"] - cyc[-1]["robo_end_mj"]))
    if rep["load_kw"] > 0 and load_got < rep["load_kw"] * 0.995:
        why.append("test load got %.0f of %.0f kW" % (load_got, rep["load_kw"]))
    return {"ok": not why, "why": "; ".join(why), "total_kw": total, "idle_kw": idle,
            "load_got_kw": load_got, "prod_kw": prod, "acc_min_mj": rep["acc_min_mj"],
            "robo_min_mj": rep["robo_min_mj"], "cycles_emptied": emptied, "acc_drift_mj": drift}


def placement_failures(logfile):
    """[brave-new-mts] failed to place ... lines, attributed to the surface whose
    'starter base placed ... on <surface>' line follows them."""
    out, pending = {}, []
    if not os.path.exists(logfile):
        return out
    for line in open(logfile, errors="replace"):
        m = re.search(r"\[brave-new-mts\] failed to place '([^']+)'", line)
        if m:
            pending.append(m.group(1))
            continue
        m = re.search(r"\[brave-new-mts\] starter base placed for \S+ on (\S+)", line)
        if m:
            if pending:
                out[m.group(1)] = pending
            pending = []
    if pending:
        out["<unattributed>"] = pending
    return out


def summarize(reports):
    """Per planet: idle draw, highest passing / lowest failing total, and the
    plant's raw production (from the saturating run)."""
    by = {}
    for rep in reports.values():
        rep["eval"] = evaluate(rep)  # re-judge with the current criterion
        by.setdefault(rep["planet"], []).append(rep)
    lines = ["%-9s %7s %9s %9s %9s %9s" % ("planet", "idle", "sustained", "fails at", "solar", "lightning")]
    for p in PLANETS:
        reps = by.get(p)
        if not reps:
            continue
        idle = [r["eval"]["idle_kw"] for r in reps if r["label"] == "idle"]
        runs = [r for r in reps if r["label"] in ("idle", "sweep")]
        ok = [r["eval"]["total_kw"] for r in runs if r["eval"]["ok"]]
        best = max(ok) if ok else None
        bad = [r["eval"]["total_kw"] for r in runs if not r["eval"]["ok"] and (best is None or r["eval"]["total_kw"] > best)]
        sat = [r["eval"]["prod_kw"] for r in reps if r["label"] == "saturate"]
        solar = sat[-1].get("solar-panel", 0) if sat else 0
        rod = sat[-1].get("lightning-rod", 0) if sat else 0
        fmt = lambda v: "%9.1f" % v if v is not None else "%9s" % "-"
        lines.append("%-9s %7.1f %s %s %s %s" % (p, idle[-1] if idle else 0, fmt(best),
                     fmt(min(bad) if bad else None), fmt(solar), fmt(rod)))
    return "\n".join(lines)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--summarize":
        print(summarize(json.load(open(sys.argv[2]))["reports"]))
        return
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=27311)
    ap.add_argument("--planets", default=",".join(PLANETS))
    ap.add_argument("--cycles", type=int, default=3)
    ap.add_argument("--rounds", type=int, default=2, help="refinement rounds after the first")
    ap.add_argument("--speed", type=float, default=1000)
    ap.add_argument("--log", default=os.path.expanduser("~/factorio-dev/rig/bnm-sp1.log"))
    ap.add_argument("--out", default="power_results.json")
    ap.add_argument("--sweep", action="append", default=[], metavar="PLANET:LO:HI",
                    help="override a planet's first-round test-load range (kW); repeatable")
    a = ap.parse_args()
    planets = a.planets.split(",")
    for spec in a.sweep:
        p, lo, hi = spec.split(":")
        PLANETS[p]["sweep"] = (float(lo), float(hi))

    rig = Rig(a.port, timeout=600)
    rig.run_file(os.path.join(HERE, "lua", "power_rig.lua"))

    # ── Round 1: build every base and start all runs together ───────────────
    sweeps = {}
    for p in planets:
        cfg = PLANETS[p]
        log("setting up %s" % p)
        setup_run(rig, p, 1, 0, a.cycles, label="idle")
        setup_run(rig, p, SAT_SLOT, SAT_KW, a.cycles, label="saturate")
        if p == "fulgora":
            setup_run(rig, p, BUSY_SLOT, 0, a.cycles, label="busy-bots", busy_bots=True)
        if cfg["sweep"]:
            loads = linspace(cfg["sweep"][0], cfg["sweep"][1], len(SWEEP_SLOTS))
            sweeps[p] = [setup_run(rig, p, slot, kw, a.cycles, label="sweep")
                         for slot, kw in zip(SWEEP_SLOTS, loads)]
    all_reports = {}
    rounds = []
    rig.eval("RIG.start(%g)" % a.speed)
    for rnd in range(a.rounds + 1):
        t0 = time.time()
        log("round %d running" % (rnd + 1))
        wait_all(rig)
        log("round %d done in %.0fs" % (rnd + 1, time.time() - t0))
        reports = rig.eval("RIG.reports()")
        this_round = []
        for rep in reports:
            if rep["planet"] not in planets:
                continue  # left over from an earlier invocation on this world
            if rnd > 0 and rep["label"] != "sweep":
                continue  # only the sweep slots were re-run
            ev = evaluate(rep)
            rep["eval"] = ev
            key = "%s@%d" % (rep["surface"], rnd + 1)
            all_reports[key] = rep
            this_round.append((rep["planet"], rep["label"], rep["load_kw"], ev))
            log("  %-16s %-9s load %6.0f  total %7.1f  idle %6.1f  accmin %5.1f MJ  robomin %5.1f MJ  %s %s" % (
                rep["surface"], rep["label"], rep["load_kw"], ev.get("total_kw", 0), ev.get("idle_kw", 0),
                ev.get("acc_min_mj", 0), ev.get("robo_min_mj", 0), "PASS" if ev["ok"] else "FAIL", ev["why"]))
        rounds.append(this_round)
        if rnd == a.rounds:
            break
        # ── Refine: re-run the sweep slots between the bracket ──────────────
        any_reset = False
        for p, snames in sweeps.items():
            # Every (test load, pass?) seen so far; the idle run is the load-0 point.
            tested = [(l, e["ok"]) for rr in rounds for (pp, lab, l, e) in rr
                      if pp == p and lab in ("sweep", "idle")]
            passed = [l for l, ok in tested if ok]
            lo = max(passed) if passed else None
            if lo is None:
                log("  %s: every load failed, idle included; nothing to refine" % p)
                continue
            hi = min([l for l, ok in tested if not ok and l > lo], default=None)
            if hi is None:                      # everything passed: look higher
                lo2, hi2 = lo * 1.05 + 10, lo * 1.6 + 100
            elif hi - lo <= 4:
                log("  %s: bracket %d..%d kW is fine enough" % (p, lo, hi))
                continue
            else:                               # split the bracket into n+1 equal steps
                step = (hi - lo) / (len(snames) + 1)
                lo2, hi2 = lo + step, hi - step
            loads = linspace(lo2, hi2, len(snames))
            log("  %s: refining %s" % (p, loads))
            opts = []
            for sname, kw in zip(snames, loads):
                opts.append('RIG.reset("%s", {load_kw=%d, cycles=%d})' % (sname, kw, a.cycles))
            rig.sc(" ".join(opts))  # one command, so every run starts on the same tick
            any_reset = True
        if not any_reset:
            break
    rig.eval("RIG.stop()")

    failures = placement_failures(a.log)
    out = {"reports": all_reports, "placement_failures": failures, "cycles": a.cycles}
    with open(a.out, "w") as f:
        json.dump(out, f, indent=1)
    log("wrote %s; placement failures: %s" % (a.out, failures or "none"))
    print(summarize(all_reports))


if __name__ == "__main__":
    main()
