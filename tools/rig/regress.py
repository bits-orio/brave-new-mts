#!/usr/bin/env python3
"""Regression suite for Brave New MTS on the headless rig (fix-up plan task E2).

Stages the working tree (stage.sh --hooks), starts a fresh server of its own
(rig name bnm-reg, game port 34332, RCON 27332) and runs BNM's real code over
RCON. Each check prints PASS or FAIL with the numbers it judged; a failing
check does not stop the suite. Every server it starts is stopped at the end.

  1  clean load: no errors in the log; a bnm-planet-profiles entry for every
     planet's team-1 copy (mts-<planet>-1), as the design contract says
  2  power, sustained total with idle included: Nauvis about 855 kW, Vulcanus
     about 3.8 MW, Gleba >= 1.08 MW, Aquilo >= 1.30 MW, Fulgora >= 1.08 MW
     with no blackout night in 20 days per base
  3  Aquilo: roboport, radar and inserter unfrozen after 10 game minutes; the
     roboport has a logistic network and its robots build a ghost
  4  establish an outpost from a script-made platform over mts-vulcanus-1,
     whose surface does not exist yet, with an uncommon clone
  5  a cargo pod from that platform delivers to the outpost's landing pad
  6  outpost loss: the team survives, the outpost is forgotten and its core
     unlocked; a new clone re-founds it and the leftovers' items are pooled
     into the new storage chests
  7  home loss: MTS disbands the team
  8  save and reload, then check 6 again on Gleba (team-2), and 7 again
  9  migration: a 0.1.3 save (commit 0ad9363) loads into this code with its
     base records upgraded (separate world, rig name bnm-reg-mig)

Checks 5 and 6 build on 4, which is added when either is asked for.

Fixtures. Headless, no team slot is ever claimed, and MTS's disband_team skips
an unclaimed slot. So each team that gets a home here (team-1 in checks 4 to 7,
team-2 in check 8) has its slot marked "occupied" in MTS's own storage, the
state of a claimed team whose members are all offline. That makes check 6's
"not disbanded" meaningful and lets check 7 see a real disband. It is test
state in a throwaway world; MTS's code is never changed. Checks 7 and 8 also
give the team an (empty) parked-slot table in BNM's storage: only BNM's
on_team_released handler clears it, which proves that handler ran.

usage: regress.py [--checks 1,4,6] [--no-stage] [--keep] [--out results.json]
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from probe import Rig  # noqa: E402
from power_test import evaluate, linspace, setup_run, wait_all  # noqa: E402

RIG_HOME = os.path.expanduser("~/factorio-dev/rig")
GAME_PORT, RCON_PORT = 34332, 27332
MAIN, MIGRATION = "bnm-reg", "bnm-reg-mig"
OLD_REV = "0ad9363"   # 0.1.3, the last release before the fix-up

CLONE = "bnm-character-clone"
GAME_MINUTE = 3600    # ticks

# ── Check 2: power targets (sustained total, idle included, kW) ─────────────
# "about": the highest passing total is within POWER_TOL of the target (the
# base is unchanged). "min": it reaches the target. The 8 test loads (added on
# top of idle, about 256 kW) put the totals around the target: +-5% for
# "about", and 10 kW below to 60 kW above for "min", 10 kW apart, so a base
# that holds the target passes at a total at or above it.
POWER = [
    # planet     rule     target  test loads (kW)   cycles
    ("nauvis",   "about", 855,  (556, 642),   4),
    ("vulcanus", "about", 3807, (3361, 3741), 6),
    ("gleba",    "min",   1080, (814, 884),   4),
    ("aquilo",   "min",   1300, (1034, 1104), 3),
]
POWER_TOL = 0.025
# Fulgora's lightning is random, so it is judged by blackout nights instead:
# FULGORA_BASES bases at FULGORA_LOAD for FULGORA_DAYS days each.
FULGORA_TARGET, FULGORA_LOAD, FULGORA_DAYS, FULGORA_BASES = 1080, 835, 20, 2
IDLE_SLOT, SWEEP_SLOTS = 4, list(range(5, 13))   # slots 1-3 belong to checks 3-8

# Lines that mean trouble in the server log. "Got EOF on stdin" is the
# headless server's normal reaction to having no console.
LOG_ERROR = re.compile(r" Error (?!InterruptibleStdioStream.*Got EOF on stdin)")
BNM_TROUBLE = ("failed to place", "lost its blueprint logistic request", "no room in the base's chests",
               "is not a known item", "unknown entity", "no roboport was built", "no clone was left")


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


# ─── Server ─────────────────────────────────────────────────────────────────

def server_pids():
    """Factorio processes listening on this suite's RCON port (as stop-server.sh
    finds them)."""
    out = subprocess.run(["ps", "-eo", "pid,comm,args"], capture_output=True, text=True).stdout
    port = re.compile(r"--rcon-port %d\b" % RCON_PORT)
    return [parts[0] for parts in (line.split(None, 2) for line in out.splitlines())
            if len(parts) == 3 and parts[1] == "factorio" and port.search(parts[2])]


class Server:
    """One rig server: write-data ~/factorio-dev/rig/w-<name>, log <name>.log."""

    def __init__(self, name, mods):
        self.name, self.mods = name, mods
        self.logfile = os.path.join(RIG_HOME, name + ".log")
        self.rig = None
        self.mark = 0
        self.started = False

    def start(self, fresh):
        if server_pids():
            raise RuntimeError("a server is already listening on RCON %d; stop it first "
                               "(~/factorio-dev/rig/stop-server.sh %d)" % (RCON_PORT, RCON_PORT))
        env = dict(os.environ)
        env.pop("RIG_FRESH", None)
        if fresh:
            env["RIG_FRESH"] = "1"
        log("starting %s (%s)" % (self.name, "fresh map" if fresh else "saved world"))
        self.started = True
        r = subprocess.run([os.path.join(RIG_HOME, "start-server.sh"), "2.0", self.name,
                            str(GAME_PORT), str(RCON_PORT), self.mods],
                           env=env, capture_output=True, text=True)
        self.mark = 0
        if r.returncode != 0:
            raise RuntimeError("%s did not start: %s%s" % (self.name, r.stdout, r.stderr))
        self.rig = Rig(RCON_PORT, timeout=900)
        self.rig.run_file(os.path.join(HERE, "lua", "regress.lua"), state="bnm")

    def stop(self):
        """Stop (stop-server.sh), then wait for the process to exit: on the
        signal the server saves the world before it quits."""
        if self.rig:
            self.rig.close()
            self.rig = None
        subprocess.run([os.path.join(RIG_HOME, "stop-server.sh"), str(RCON_PORT)], capture_output=True)
        for _ in range(240):
            if not server_pids():
                log("stopped %s" % self.name)
                return
            time.sleep(0.5)
        raise RuntimeError("%s is still running after stop-server.sh" % self.name)

    def take_log(self):
        """Log lines written since the last call (or since the server started)."""
        if not os.path.exists(self.logfile):
            return []
        with open(self.logfile, errors="replace") as f:
            lines = f.read().splitlines()
        new, self.mark = lines[self.mark:], len(lines)
        return new


def log_trouble(lines):
    """Engine errors and BNM's warnings about a base it could not build fully."""
    return [ln.strip() for ln in lines
            if LOG_ERROR.search(ln) or ("[brave-new-mts]" in ln and any(t in ln for t in BNM_TROUBLE))]


# ─── Checks: bookkeeping ────────────────────────────────────────────────────

class Check:
    def __init__(self, num, title):
        self.num, self.title = num, title
        self.fails, self.notes, self.data = [], [], {}

    def expect(self, ok, what):
        """One assertion. `what` states the expectation and the measured value."""
        if not ok:
            self.fails.append(what)
        return bool(ok)

    def note(self, text):
        self.notes.append(text)

    @property
    def ok(self):
        return not self.fails

    def report(self):
        print("CHECK %d %s  %s" % (self.num, "PASS" if self.ok else "FAIL", self.title))
        for n in self.notes:
            print("      " + n)
        for f in self.fails:
            print("      FAIL: " + f)
        sys.stdout.flush()


class Ctx:
    """What the checks share: the main server and what earlier checks built."""

    def __init__(self, stage):
        self.stage = stage
        self.main = Server(MAIN, os.path.join(RIG_HOME, "mods-" + MAIN))
        self.baseline = {}   # surface -> entity counts of a freshly established outpost

    @property
    def rig(self):
        return self.main.rig


# ─── Helpers over RCON ──────────────────────────────────────────────────────

def bnm(rig, lua):
    return rig.eval(lua, state="bnm")


def run_ticks(rig, n, speed):
    rig.sc("game.speed = %g" % speed)
    try:
        return rig.wait_ticks(n, poll=0.5)
    finally:
        rig.sc("game.speed = 1")


def wait_for(rig, test, max_ticks, speed):
    """Poll test() until it returns a truthy value or max_ticks pass. Returns
    (value, ticks waited)."""
    t0 = rig.tick()
    rig.sc("game.speed = %g" % speed)
    try:
        while True:
            value = test()
            waited = rig.tick() - t0
            if value or waited >= max_ticks:
                return value, waited
            time.sleep(0.5)
    finally:
        rig.sc("game.speed = 1")


def occupy_slot(rig, slot):
    """Fixture: MTS treats the slot as a claimed team (see the module doc)."""
    rig.sc('storage.team_pool[%d] = "occupied"' % slot, state="mts")


def slot_state(rig, slot):
    return rig.eval("storage.team_pool[%d]" % slot, state="mts")


def team_home(ctx, c, slot):
    """Occupy team-<slot> and give it its home base on mts-nauvis-<slot>."""
    occupy_slot(ctx.rig, slot)
    force, surface = "team-%d" % slot, "mts-nauvis-%d" % slot
    if bases_of(ctx.rig, force).get(surface) == "home":
        return surface
    r = bnm(ctx.rig, 'REG.place("%s", "%s")' % (force, surface))
    c.expect(r["ok"] and r["home"], "home base placed on %s (got %s)" % (surface, r))
    return surface


def discover(rig, force, planet, slot):
    """Research the planet's discovery tech; MTS then unlocks the team's copy."""
    rig.sc('game.forces["%s"].technologies["planet-discovery-%s"].researched = true' % (force, planet))
    return rig.eval('game.forces["%s"].is_space_location_unlocked("mts-%s-%d")' % (force, planet, slot))


def kill_roboport(rig, surface, force):
    """roboport.die() from the level state, so BNM sees an ordinary death."""
    return rig.eval('local rp = game.surfaces["%s"].find_entities_filtered{name = "bnm-roboport", '
                    'force = "%s"}[1] return rp and rp.die() or false' % (surface, force))


def establish(ctx, c, force, planet, slot, platform, quality):
    """A platform made by script in orbit of mts-<planet>-<slot> (so the
    surface is not created), one clone of `quality` aboard, then the establish
    core. Returns the new base's summary, or None."""
    rig, surface = ctx.rig, "mts-%s-%d" % (planet, slot)
    c.expect(discover(rig, force, planet, slot), "MTS unlocked %s for %s after its discovery" % (surface, force))
    existed = rig.eval('game.planets["%s"].surface ~= nil' % surface)
    p = bnm(rig, 'REG.make_platform("%s", "%s", "%s")' % (force, surface, platform))
    c.expect(p["location"] == surface, "platform parked at %s (at %s)" % (surface, p["location"]))
    bnm(rig, 'REG.hub_insert("%s", "%s", {name = "%s", quality = "%s", count = 1})' % (force, platform, CLONE, quality))
    res = bnm(rig, 'REG.establish("%s", "%s")' % (force, platform))
    c.expect(res.get("ok"), "establish_for succeeded (reason: %s)" % res.get("reason"))
    if not res.get("ok"):
        return None, existed
    return bnm(rig, 'REG.base("%s")' % surface), existed


def as_dict(v):
    """A Lua table decoded from JSON: an empty one arrives as a list."""
    return v if isinstance(v, dict) else {}


def bases_of(rig, force):
    """{surface: "home" | "outpost"} for the bases BNM has recorded for a force."""
    return as_dict(bnm(rig, 'REG.bases_of("%s")' % force))


def logged(lines, text):
    """True if a log line ends with `text` (so team-1 never matches team-10)."""
    return any(ln.rstrip().endswith(text) for ln in lines)


def contents_str(d):
    return ", ".join("%s %d" % (k, v) for k, v in sorted(as_dict(d).items())) or "nothing"


# ─── 1. Clean load ─────────────────────────────────────────────────────────

# What the design contract gives each planet's profile (unlisted = nil / false).
PROFILES = {
    "nauvis":   {},
    "vulcanus": {},
    "gleba":    {"solar_panel": "bnm-solar-panel-gleba", "accumulator": "bnm-accumulator-gleba"},
    "fulgora":  {"accumulator": "bnm-accumulator-fulgora", "fulgora": True},
    "aquilo":   {"solar_panel": "bnm-solar-panel-aquilo", "accumulator": "bnm-accumulator-aquilo",
                 "freezing": True},
}

PROFILE_LUA = """
local md = prototypes.mod_data["bnm-planet-profiles"]
if not md then return { missing = true } end
local planets = md.get("planets") or {}
local out = { count = table_size(planets), planets = {}, protos = {} }
for _, p in pairs({ "nauvis", "vulcanus", "gleba", "fulgora", "aquilo" }) do
    out.planets[p] = planets["mts-" .. p .. "-1"] or false
end
for _, name in pairs({ "bnm-solar-panel-gleba", "bnm-accumulator-gleba", "bnm-solar-panel-aquilo",
                       "bnm-accumulator-aquilo", "bnm-accumulator-fulgora", "bnm-radar", "bnm-inserter" }) do
    local e = prototypes.entity[name]
    local src = e and e.electric_energy_source_prototype
    out.protos[name] = e and {
        panel_kw = e.type == "solar-panel" and e.get_max_energy_production() * 60 / 1000 or nil,
        buffer_mj = e.type == "accumulator" and src.buffer_capacity / 1e6 or nil,
        heating = e.heating_energy,
    } or false
end
out.roboport_heating = prototypes.entity["bnm-roboport"].heating_energy
return out
"""


def check_clean_load(ctx, c):
    lines = ctx.main.take_log()
    errors = log_trouble(lines)
    c.note("log: %d lines, %d errors" % (len(lines), len(errors)))
    c.expect(not errors, "no errors in the log: %s" % errors[:5])
    c.expect(any("[brave-new-mts] on_init fired" in ln for ln in lines), "BNM's on_init ran")
    r = ctx.rig.eval(PROFILE_LUA)
    if not c.expect(not r.get("missing"), "mod-data bnm-planet-profiles exists"):
        return
    c.note("bnm-planet-profiles: %d planet profiles" % r["count"])
    for planet, want in PROFILES.items():
        got = r["planets"][planet]
        if not c.expect(got, "a profile for mts-%s-1" % planet):
            continue
        c.expect(got.get("base") == planet, "mts-%s-1 base is %s (got %s)" % (planet, planet, got.get("base")))
        for key in ("solar_panel", "accumulator", "fulgora", "freezing"):
            expected = want.get(key, False if key in ("fulgora", "freezing") else None)
            c.expect(got.get(key) == expected, "mts-%s-1 %s = %s (got %s)" % (planet, key, expected, got.get(key)))
        c.note("mts-%s-1: %s" % (planet, ", ".join("%s=%s" % (k, got[k]) for k in sorted(got) if k != "base")))
    for name, proto in sorted(r["protos"].items()):
        if c.expect(proto, "prototype %s exists" % name):
            c.note("%s: %s" % (name, ", ".join("%s %.2f" % (k, v) for k, v in sorted(proto.items()))))
    c.expect(r["roboport_heating"] == 0, "bnm-roboport needs no heating (%s)" % r["roboport_heating"])


# ─── 2. Power ──────────────────────────────────────────────────────────────

def power_rows(reports):
    by = {}
    for rep in reports:
        rep["eval"] = evaluate(rep)
        by.setdefault(rep["planet"], []).append(rep)
    return by


def judge_solar(c, planet, rule, target, reps):
    idle = [r["eval"]["total_kw"] for r in reps if r["label"] == "idle" and "total_kw" in r["eval"]]
    passed = [r["eval"]["total_kw"] for r in reps if r["eval"]["ok"]]
    best = max(passed) if passed else None
    failed = [r["eval"]["total_kw"] for r in reps
              if not r["eval"]["ok"] and "total_kw" in r["eval"] and (best is None or r["eval"]["total_kw"] > best)]
    fails_at = min(failed) if failed else None
    if rule == "about":
        ok = best is not None and abs(best - target) <= POWER_TOL * target
        goal = "about %d (+-%.1f%%)" % (target, POWER_TOL * 100)
    else:
        ok = best is not None and best >= target
        goal = ">= %d" % target
    c.note("%-9s idle %6.1f  sustained %7.1f  next load fails at %s  target %s kW  %s" % (
        planet, idle[0] if idle else 0, best or 0, "%.1f" % fails_at if fails_at else "-", goal,
        "PASS" if ok else "FAIL"))
    c.expect(ok, "%s sustained %s kW, target %s" % (planet, "%.1f" % best if best else "none", goal))
    c.data[planet] = {"idle_kw": idle[0] if idle else None, "sustained_kw": best, "fails_at_kw": fails_at}


def judge_fulgora(c, reps):
    idle = [r["eval"]["total_kw"] for r in reps if r["label"] == "idle"]
    runs = [r for r in reps if r["label"] == "sweep"]
    days = sum(len(r["cycles"]) for r in runs)
    blackouts = sum(r["eval"]["cycles_emptied"] for r in runs)
    totals = [r["eval"]["total_kw"] for r in runs]
    starved = [r for r in runs if r["eval"]["load_got_kw"] < r["load_kw"] * 0.995]
    robo = [r for r in runs if any(cy["robo_end_mj"] < cy["robo_start_mj"] - 0.5 for cy in r["cycles"])]
    reserve = min(r["eval"]["acc_min_mj"] for r in runs) if runs else 0
    ok = (runs and days >= FULGORA_DAYS * len(runs) and blackouts == 0 and min(totals) >= FULGORA_TARGET
          and not starved and not robo)
    c.note("fulgora   idle %6.1f  %d bases x %d days at %.0f kW: %d/%d blackout nights, "
           "lowest reserve %.1f MJ  target >= %d kW, 0 blackouts  %s" % (
               idle[0] if idle else 0, len(runs), FULGORA_DAYS, min(totals) if totals else 0, blackouts, days,
               reserve, FULGORA_TARGET, "PASS" if ok else "FAIL"))
    c.expect(runs and days >= FULGORA_DAYS * len(runs), "fulgora ran %d base-days" % days)
    c.expect(blackouts == 0, "fulgora: %d blackout nights in %d base-days" % (blackouts, days))
    c.expect(totals and min(totals) >= FULGORA_TARGET, "fulgora carried %s kW" % totals)
    c.expect(not starved, "fulgora test load starved on %s" % [r["surface"] for r in starved])
    c.expect(not robo, "fulgora roboport buffer fell on %s" % [r["surface"] for r in robo])
    c.data["fulgora"] = {"idle_kw": idle[0] if idle else None, "total_kw": totals,
                         "base_days": days, "blackouts": blackouts, "lowest_reserve_mj": reserve}


def check_power(ctx, c):
    rig = ctx.rig
    rig.run_file(os.path.join(HERE, "lua", "power_rig.lua"))
    for planet, _, _, (lo, hi), cycles in POWER:
        log("placing %s bases" % planet)
        setup_run(rig, planet, IDLE_SLOT, 0, cycles, label="idle")
        for slot, kw in zip(SWEEP_SLOTS, linspace(lo, hi, len(SWEEP_SLOTS))):
            setup_run(rig, planet, slot, kw, cycles, label="sweep")
    log("placing fulgora bases")
    setup_run(rig, "fulgora", IDLE_SLOT, 0, FULGORA_DAYS, label="idle")
    for slot in SWEEP_SLOTS[:FULGORA_BASES]:
        setup_run(rig, "fulgora", slot, FULGORA_LOAD, FULGORA_DAYS, label="sweep")
    t0 = time.time()
    rig.eval("RIG.start(1000)")
    try:
        wait_all(rig)
    finally:
        rig.eval("RIG.stop()")
    log("power runs done in %.0fs" % (time.time() - t0))
    by = power_rows(rig.eval("RIG.reports()"))
    for planet, rule, target, _, _ in POWER:
        judge_solar(c, planet, rule, target, by.get(planet, []))
    judge_fulgora(c, by.get("fulgora", []))


# ─── 3. Aquilo ─────────────────────────────────────────────────────────────

def check_aquilo(ctx, c):
    rig, force, surface = ctx.rig, "team-3", "mts-aquilo-3"
    r = bnm(rig, 'REG.place("%s", "%s", true)' % (force, surface))
    c.expect(r["ok"] and r["outpost"], "outpost placed on %s (%s)" % (surface, r))
    t0 = rig.tick()
    run_ticks(rig, 10 * GAME_MINUTE, 1000)
    age = rig.tick() - t0
    b = bnm(rig, 'REG.base("%s")' % surface)
    m = bnm(rig, 'REG.machines("%s", "%s")' % (surface, force))
    rp = b.get("roboport") or {}
    c.note("after %.1f game minutes: roboport frozen %s, network %s, %d construction robots; "
           "%s frozen %s; %s frozen %s" % (age / GAME_MINUTE, rp.get("frozen"), rp.get("network"),
                                           rp.get("construction_robots", 0), m["radar"] and m["radar"]["name"],
                                           m["radar"] and m["radar"]["frozen"], m["inserter"] and m["inserter"]["name"],
                                           m["inserter"] and m["inserter"]["frozen"]))
    c.expect(age >= 10 * GAME_MINUTE, "10 game minutes passed (%d ticks)" % age)
    c.expect(rp and rp.get("frozen") is False, "roboport not frozen (%s)" % rp.get("frozen"))
    for kind in ("radar", "inserter"):
        c.expect(m[kind] and m[kind]["frozen"] is False, "%s not frozen (%s)" % (kind, m[kind]))
    c.expect(rp.get("network"), "roboport has a logistic network")
    ghost = bnm(rig, 'REG.place_ghost("%s", "%s", "transport-belt")' % (surface, force))
    built, ticks = wait_for(rig, lambda: bnm(rig, 'REG.ghost_state("%s", "transport-belt", {x = %g, y = %g})' % (
        surface, ghost["x"], ghost["y"]))["built"], 2 * GAME_MINUTE, 10)
    c.note("transport-belt ghost %.0f tiles from the roboport: %s after %d ticks" % (
        ghost["distance"], "built" if built else "NOT built", ticks))
    c.expect(built, "the ghost was built by the base's robots within %d ticks" % ticks)


# ─── 4. Establish on a planet with no surface ──────────────────────────────

def check_establish(ctx, c):
    rig = ctx.rig
    team_home(ctx, c, 1)
    base, existed = establish(ctx, c, "team-1", "vulcanus", 1, "reg-vulcanus-1", "uncommon")
    c.expect(not existed, "precondition: mts-vulcanus-1 had no surface before the establish")
    if not base:
        return
    owner = rig.eval('remote.call("mts-v1", "get_surface_owner", "mts-vulcanus-1")')
    clones = bnm(rig, 'REG.clones("team-1", "reg-vulcanus-1")')
    rp, pad = base.get("roboport") or {}, base.get("pad") or {}
    c.note("surface created: %s (owner %s), %d chunks generated, %d out-of-map tiles in the site" % (
        base["exists"], owner, base["chunks_generated"], base.get("out_of_map", -1)))
    c.note("clones aboard after: %d (was 1 uncommon); base: outpost %s, home %s, roboport network %s" % (
        clones, base.get("outpost"), base.get("home"), rp.get("network")))
    c.note("landing pad at (%s, %s), roboport at (%s, %s), gap to the south wall %s tiles" % (
        pad.get("x"), pad.get("y"), rp.get("x"), rp.get("y"), pad.get("gap")))
    c.expect(base["exists"] and owner == "team-1", "mts-vulcanus-1 exists, owned by team-1 (%s)" % owner)
    c.expect(base["chunks_generated"] >= 81, "the base's ground is generated (%d chunks)" % base["chunks_generated"])
    c.expect(base.get("out_of_map") == 0, "no out-of-map tiles in the site (%s)" % base.get("out_of_map"))
    c.expect(clones == 0, "the uncommon clone was consumed (%d left)" % clones)
    c.expect(base.get("outpost") and not base.get("home"), "recorded as an outpost")
    c.expect(rp.get("network") and rp.get("is_record"), "the recorded roboport stands with a network")
    c.expect(pad.get("is_record"), "a landing pad is recorded")
    c.expect(pad.get("gap") is not None and abs(pad["gap"] - 3) < 0.01, "pad 3 tiles below the south wall (%s)"
             % pad.get("gap"))
    c.expect(pad.get("x") == rp.get("x"), "pad centred under the roboport")
    ctx.baseline["mts-vulcanus-1"] = as_dict(base.get("counts"))


# ─── 5. Pad delivery ───────────────────────────────────────────────────────

def check_pad_delivery(ctx, c):
    rig, surface, platform = ctx.rig, "mts-vulcanus-1", "reg-vulcanus-1"
    put = bnm(rig, 'REG.hub_insert("team-1", "%s", {name = "iron-plate", count = 100})' % platform)
    bnm(rig, 'REG.pad_request("%s", "iron-plate", 100)' % surface)
    _, ticks = wait_for(rig, lambda: bnm(rig, 'REG.pad_count("%s", "iron-plate")' % surface)["pad"] >= 100,
                        6000, 20)
    counts = bnm(rig, 'REG.pad_count("%s", "iron-plate")' % surface)
    hub = bnm(rig, 'REG.hub_count("team-1", "%s", "iron-plate")' % platform)
    c.note("hub loaded with %d iron-plate, pad requests 100: pad holds %d (network %d) after %d ticks, hub %d" % (
        put, counts["pad"], counts["network"], ticks, hub))
    c.expect(counts["pad"] >= 100, "a cargo pod delivered 100 iron-plate to the pad (%d)" % counts["pad"])
    c.expect(hub == 0, "the hub sent its iron down (%d left)" % hub)


# ─── 6. Outpost loss and re-founding ───────────────────────────────────────

MARKER = {"name": "iron-gear-wheel", "count": 37}   # an item no kit carries


def outpost_loss(ctx, c, slot, surface, platform):
    """Kill an outpost's roboport, check the team and the leftovers, then
    re-found it with a new clone and check the fresh base and the salvage."""
    rig, force = ctx.rig, "team-%d" % slot
    home = "mts-nauvis-%d" % slot
    before = bnm(rig, 'REG.base("%s")' % surface)
    if not c.expect(before.get("recorded") and before.get("outpost"), "%s holds an outpost" % surface):
        return
    c.expect(before["core"] > 0 and before["core_locked"] == before["core"],
             "power core locked before the loss (%d of %d)" % (before["core_locked"], before["core"]))
    put = bnm(rig, 'REG.chest_insert("%s", "providers", {name = "%s", count = %d})' % (
        surface, MARKER["name"], MARKER["count"]))
    old_unit = before["roboport"]["unit"]

    ctx.main.take_log()
    died = kill_roboport(rig, surface, force)
    after = bnm(rig, 'REG.base("%s", "%s")' % (surface, force))
    pool, bases = slot_state(rig, slot), bases_of(rig, force)
    lines = ctx.main.take_log()
    c.note("roboport died: %s; slot %s, bases left %s; %s placed %s, recorded %s; core minable %d of %d" % (
        died, pool, bases, surface, after.get("placed"), after.get("recorded"),
        after.get("core", 0) - after.get("core_locked", 0), after.get("core", 0)))
    c.expect(died, "roboport.die() killed it")
    c.expect(pool == "occupied" and bases.get(home) == "home", "%s not disbanded (slot %s, bases %s)" % (
        force, pool, bases))
    c.expect(rig.eval('game.surfaces["%s"] ~= nil' % home), "%s still exists" % home)
    c.expect(not after.get("placed") and not after.get("recorded"), "bases_placed and the record for %s cleared"
             % surface)
    c.expect(after.get("core") == before["core"] and after.get("core_locked") == 0,
             "every locked core entity became minable (%d locked of %d)" % (after.get("core_locked", -1),
                                                                             after.get("core", 0)))
    c.expect(logged(lines, "lost its outpost on %s" % surface), "the loss was logged")

    # Re-found: the leftovers' snapshot and the new base come from the same
    # tick, so nothing moves in between.
    bnm(rig, 'REG.hub_insert("%s", "%s", {name = "%s", count = 1})' % (force, platform, CLONE))
    r = bnm(rig, 'local left = REG.base("%s", "%s") local res = REG.establish("%s", "%s") '
                 'return {left = left, res = res, new = REG.base("%s")}' % (surface, force, force, platform, surface))
    left, res, new = r["left"], r["res"], r["new"]
    lines = ctx.main.take_log()
    pattern = re.compile(r"swept (\d+) leftover entities from the base site on %s$" % re.escape(surface))
    swept = [int(m.group(1)) for m in (pattern.search(ln.rstrip()) for ln in lines) if m]
    left_counts, new_counts = as_dict(left.get("counts")), as_dict(new.get("counts"))
    stored, held = as_dict(new.get("storage_contents")), as_dict(left.get("site_contents"))
    leftover = sum(left_counts.values())
    c.note("leftovers: %d entities holding %s" % (leftover, contents_str(held)))
    c.note("re-found: %s; swept %s; new storage chests hold %s" % (res.get("ok"), swept, contents_str(stored)))
    if not c.expect(res.get("ok"), "re-founded with a new clone (reason: %s)" % res.get("reason")):
        return
    nrp = new.get("roboport") or {}
    c.expect(new.get("outpost") and nrp.get("is_record") and nrp.get("network") and nrp.get("unit") != old_unit,
             "a fresh base with a new roboport and network (unit %s, was %s)" % (nrp.get("unit"), old_unit))
    c.expect(swept == [leftover], "every leftover was swept (%s of %d)" % (swept, leftover))
    baseline = ctx.baseline.get(surface)
    if baseline:
        c.expect(new_counts == baseline, "the site holds exactly one fresh base (diff %s)" % {
            k: (baseline.get(k), new_counts.get(k)) for k in set(baseline) | set(new_counts)
            if baseline.get(k) != new_counts.get(k)})
    c.expect(put == MARKER["count"] and stored.get(MARKER["name"]) == MARKER["count"],
             "the %d %s put in a lost chest reached the new storage chests (%s)" % (
                 MARKER["count"], MARKER["name"], stored.get(MARKER["name"])))
    c.expect(stored == held, "the leftovers' items were pooled into the new storage chests, all of them "
             "(held, stored: %s)" % {k: (held.get(k), stored.get(k)) for k in set(held) | set(stored)
                                     if held.get(k) != stored.get(k)})
    c.expect(new["core_locked"] == new["core"] > 0, "the new power core is locked (%d of %d)" % (
        new["core_locked"], new["core"]))


def check_outpost_loss(ctx, c):
    outpost_loss(ctx, c, 1, "mts-vulcanus-1", "reg-vulcanus-1")


# ─── 7. Home loss ──────────────────────────────────────────────────────────

def home_loss(ctx, c, slot):
    rig, force = ctx.rig, "team-%d" % slot
    home = team_home(ctx, c, slot)
    rig.sc('storage.park_index["%s"] = storage.park_index["%s"] or {}' % (force, force), state="bnm")
    surfaces = sorted(bases_of(rig, force))
    ctx.main.take_log()
    died = kill_roboport(rig, home, force)
    run_ticks(rig, 10, 1)   # MTS deletes surfaces at the end of the tick
    pool = slot_state(rig, slot)
    alive = [s for s in surfaces if rig.eval('game.surfaces["%s"] ~= nil' % s)]
    left = bnm(rig, 'return {bases = REG.bases_of("%s"), park = storage.park_index["%s"] ~= nil}' % (force, force))
    left["bases"] = as_dict(left.get("bases"))
    platforms = rig.eval('local n = 0 for _, p in pairs(game.forces["%s"].platforms) do '
                         'if not p.scheduled_for_deletion then n = n + 1 end end return n' % force)
    lines = ctx.main.take_log()
    released = logged(lines, "released team slot: %s" % force)
    c.note("%s home roboport died: %s; slot now %s, MTS log 'released team slot': %s" % (
        force, died, pool, released))
    c.note("surfaces before %s, still there %s; BNM records left %s; parked-slot table cleared %s; "
           "platforms not scheduled for deletion %d" % (surfaces, alive, left["bases"], not left["park"], platforms))
    c.expect(died, "roboport.die() killed it")
    c.expect(pool == "available" and released, "MTS disbanded %s (slot %s)" % (force, pool))
    c.expect(not alive, "the team's surfaces were deleted (%s left)" % alive)
    c.expect(not left["bases"], "BNM forgot the team's bases (%s)" % left["bases"])
    c.expect(not left["park"], "BNM's on_team_released handler ran (parked-slot table cleared)")


def check_home_loss(ctx, c):
    home_loss(ctx, c, 1)


# ─── 8. Save and reload ────────────────────────────────────────────────────

def check_reload(ctx, c):
    rig = ctx.rig
    team_home(ctx, c, 2)
    base, _ = establish(ctx, c, "team-2", "gleba", 2, "reg-gleba-2", "normal")
    if not base:
        return
    ctx.baseline["mts-gleba-2"] = as_dict(base.get("counts"))
    tick = rig.tick()
    ctx.main.stop()
    ctx.main.start(fresh=False)
    lines = ctx.main.take_log()
    trouble = log_trouble(lines)
    rig = ctx.rig
    now = rig.tick()
    kept = bases_of(rig, "team-2")
    c.note("saved at tick %d, reloaded at tick %d; log after reload: %d errors; team-2 bases %s" % (
        tick, now, len(trouble), kept))
    c.expect(now >= tick, "the saved world was loaded (tick %d, saved at %d)" % (now, tick))
    c.expect(not trouble, "no errors on reload: %s" % trouble[:5])
    c.expect(kept.get("mts-gleba-2") == "outpost", "the Gleba outpost survived the reload")
    outpost_loss(ctx, c, 2, "mts-gleba-2", "reg-gleba-2")
    home_loss(ctx, c, 2)


# ─── 9. Migration from 0.1.3 ───────────────────────────────────────────────

OLD_PLACE_LUA = """
local sb = package.loaded["__brave-new-mts__/scripts/starter_base.lua"]
sb.place("team-1", game.surfaces["mts-nauvis-1"])
local rec = storage.bnm_base["mts-nauvis-1"]
return { recorded = rec ~= nil, provider = rec and rec.provider ~= nil, providers = rec and rec.providers ~= nil,
         home = rec and rec.home, event_ids = storage.bnm_tab_event_id ~= nil }
"""

MIGRATED_LUA = """
local rec = storage.bnm_base["mts-nauvis-1"]
if not rec then return { recorded = false } end
local valid = 0
for _, c in pairs(rec.providers or {}) do if c.valid then valid = valid + 1 end end
return { recorded = true, home = rec.home, outpost = rec.outpost, provider = rec.provider ~= nil,
         providers = rec.providers and #rec.providers or -1, providers_valid = valid,
         storage_chests = rec.storage_chests and #rec.storage_chests or -1,
         roboport = rec.roboport and rec.roboport.valid, placed = storage.bases_placed["mts-nauvis-1"] == true,
         event_ids = storage.bnm_tab_event_id ~= nil }
"""


def stage(mods, *args):
    r = subprocess.run([os.path.join(HERE, "stage.sh"), mods] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("stage.sh failed: %s%s" % (r.stdout, r.stderr))
    log(" ".join(r.stdout.split()))


def check_migration(ctx, c):
    if ctx.main.rig:
        ctx.main.stop()
    mods = os.path.join(RIG_HOME, "mods-" + MIGRATION)
    srv = Server(MIGRATION, mods)
    stage(mods, "--rev", OLD_REV)
    try:
        srv.start(fresh=True)
        old_trouble = log_trouble(srv.take_log())
        srv.rig.eval('REG.surface("mts-nauvis-1") ~= nil', state="bnm")
        old = srv.rig.eval(OLD_PLACE_LUA, state="bnm")
        c.note("%s (0.1.3): home base record %s, single provider %s, provider list %s, cached event ids %s" % (
            OLD_REV, old["recorded"], old["provider"], old["providers"], old["event_ids"]))
        c.expect(not old_trouble, "0.1.3 loaded cleanly: %s" % old_trouble[:5])
        c.expect(old["recorded"] and old["provider"] and not old["providers"],
                 "precondition: the 0.1.3 base has the old record (%s)" % old)
        srv.stop()
        stage(mods)
        srv.start(fresh=False)
        lines = srv.take_log()
        trouble = log_trouble(lines)
        changed = any("[brave-new-mts] on_configuration_changed fired" in ln for ln in lines)
        new = srv.rig.eval(MIGRATED_LUA, state="bnm")
        c.note("reloaded with this code: on_configuration_changed %s, %d errors" % (changed, len(trouble)))
        c.note("record: home %s, outpost %s, providers %s (%s valid), storage chests %s, old provider key %s, "
               "cached event ids %s" % (new.get("home"), new.get("outpost"), new.get("providers"),
                                        new.get("providers_valid"), new.get("storage_chests"), new.get("provider"),
                                        new.get("event_ids")))
        c.expect(changed, "on_configuration_changed ran")
        c.expect(not trouble, "no errors on the migrating load: %s" % trouble[:5])
        c.expect(new.get("home") is True and new.get("outpost") is False, "home flag set")
        c.expect(new.get("providers", 0) > 0 and new.get("providers_valid") == new.get("providers"),
                 "providers list present (%s)" % new.get("providers"))
        c.expect(new.get("storage_chests", -1) >= 0, "storage chest list present")
        c.expect(not new.get("provider"), "the 0.1.x provider key dropped")
        c.expect(not new.get("event_ids"), "cached mts-v1 event ids dropped")
        c.expect(new.get("roboport") and new.get("placed"), "the base itself is intact")
    finally:
        if srv.started and server_pids():
            srv.stop()


# ─── Runner ────────────────────────────────────────────────────────────────

CHECKS = [
    (1, "clean load, planet profiles", check_clean_load),
    (2, "power: sustained total per planet, idle included", check_power),
    (3, "Aquilo: base unfrozen after 10 minutes, robots build a ghost", check_aquilo),
    (4, "establish on a planet whose surface does not exist yet", check_establish),
    (5, "cargo pod delivers to the outpost's landing pad", check_pad_delivery),
    (6, "outpost loss, then re-found with a new clone", check_outpost_loss),
    (7, "home loss disbands the team", check_home_loss),
    (8, "save and reload, then outpost loss and home loss again", check_reload),
    (9, "migration from 0.1.3 (%s)" % OLD_REV, check_migration),
]
NEEDS = {5: [4], 6: [4]}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--checks", default=",".join(str(n) for n, _, _ in CHECKS), help="comma-separated check numbers")
    ap.add_argument("--no-stage", action="store_true", help="reuse the staged mods dir as it is")
    ap.add_argument("--keep", action="store_true", help="leave the main server running at the end")
    ap.add_argument("--out", help="write the results as JSON here")
    a = ap.parse_args()
    wanted = {int(n) for n in a.checks.split(",") if n}
    for n in list(wanted):
        wanted.update(NEEDS.get(n, []))

    ctx = Ctx(stage=not a.no_stage)
    results = []
    try:
        if wanted - {9}:
            if ctx.stage:
                stage(ctx.main.mods, "--hooks")
            ctx.main.start(fresh=True)
        for num, title, fn in CHECKS:
            if num not in wanted:
                continue
            c = Check(num, title)
            log("check %d: %s" % (num, title))
            t0 = time.time()
            try:
                fn(ctx, c)
            except Exception as e:  # a crashed check is a failed check; the suite goes on
                c.expect(False, "%s: %s" % (type(e).__name__, e))
            c.data["seconds"] = round(time.time() - t0)
            c.report()
            results.append(c)
    finally:
        if ctx.main.started and server_pids() and not a.keep:
            ctx.main.stop()
    print("\nSUMMARY  %d/%d passed" % (sum(c.ok for c in results), len(results)))
    for c in results:
        print("  %d %s  %s" % (c.num, "PASS" if c.ok else "FAIL", c.title))
    if a.out:
        with open(a.out, "w") as f:
            json.dump([{"check": c.num, "title": c.title, "ok": c.ok, "fails": c.fails,
                        "notes": c.notes, "data": c.data} for c in results], f, indent=1)
    sys.exit(0 if all(c.ok for c in results) else 1)


if __name__ == "__main__":
    main()
