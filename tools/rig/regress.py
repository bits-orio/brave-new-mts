#!/usr/bin/env python3
"""Regression suite for Brave New MTS on the headless rig (fix-up plan task E2).

Stages the working tree (stage.sh --hooks), starts a fresh server of its own
(rig name bnm-reg, game port 34332, RCON 27332 unless --rig / --ports say
otherwise) and runs BNM's real code over RCON. Each check prints PASS or FAIL with the numbers it judged; a failing
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
  9  re-found an outpost whose chests and pad are full, with things the team
     built in the site: the fresh kit is all there, nothing held or built
     there is lost (what no chest holds is spilled, marked for the robots),
     and what the team built came back as items
 10  /bnm-forget-base over RCON refuses a home base, standing or not, and
     changes no record; it refuses a standing outpost, and wipes a lost one
     (record forgotten, core minable), which can then be founded again
 11  unlocking the power core leaves the planet-tuned copies (every bnm-*
     entity, the roboport included) locked and makes the vanilla core
     minable, on bases founded before and after the unlock; walls are never
     locked
 12  reconnect view: a simulated player's leave and reconnect put the view
     back on the spot they were looking at, once
 13  placing twice: a second place() on a surface with a base (home or
     outpost) returns false and builds, removes and restocks nothing
 14  a re-found keeps what carries data: an equipped spidertron and tank in
     the site come back as items with their equipment, spidertron items,
     armor and a blueprint in a team's chest and a base chest keep theirs, a
     train and its rails come back once each, and a spider parked outside
     with a leg in the site is left alone
 15  a team whose home surface is deleted outside a disband keeps its
     outpost, and the base founded on the recreated surface (place() with no
     opts, as a member arriving) is its home again, not an outpost
 16  admin test commands, from the console: /bnm-test-orbit refuses while
     the setting is off; on, it researches the way to Gleba and the clone
     and parks a platform with a clone above team-20's copy (again: one more
     clone; flown away, it is brought back; deleted, a new one is made),
     which founds an outpost; /bnm-test-kill-roboport wipes that outpost and
     keeps the team; bad input answers with usage, and a free team slot
     (team-15) is refused
 17  migration: a 0.1.3 save (commit 0ad9363) loads into this code with its
     base records upgraded (separate world, rig name <rig>-mig)

Checks 5 and 6 build on 4, which is added when either is asked for.

Fixtures. Headless, no team slot is ever claimed, and MTS's disband_team skips
an unclaimed slot. So each team that gets a home here (team-1 in checks 4 to 7,
team-2 in check 8, team-20 in check 16) has its slot marked "occupied" in MTS's
own storage, the state of a claimed team whose members are all offline. That
makes "not disbanded" in checks 6 and 16 meaningful and lets check 7 see a real
disband. It is test state in a throwaway world; MTS's code is never changed.
Checks 7 and 8 also give the team an (empty) parked-slot table in BNM's
storage: only BNM's on_team_released handler clears it, which proves that
handler ran.

usage: regress.py [--checks 1,4,6] [--no-stage] [--keep] [--out results.json]
                  [--rig bnm-reg] [--ports 34332,27332]
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
from probe import Rig, bnm_mod  # noqa: E402
from power_test import evaluate, linspace, setup_run, wait_all  # noqa: E402

RIG_HOME = os.path.expanduser("~/factorio-dev/rig")
# Defaults; --rig and --ports override them, so two suites can run side by side.
GAME_PORT, RCON_PORT = 34332, 27332
MAIN, MIGRATION = "bnm-reg", "bnm-reg-mig"
OLD_REV = "0ad9363"   # 0.1.3, the last release before the fix-up

CLONE = "bnm-character-clone"
GAME_MINUTE = 3600    # ticks
# Loaded into BNM's state on every server start, the shared core first.
LUA_HELPERS = ("regress.lua", "regress_platform.lua", "regress_site.lua", "regress_salvage.lua",
               "regress_records.lua", "regress_player.lua")

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
               "is not a known item", "unknown entity", "no roboport was built", "no clone was left",
               "could not sweep")


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
        for name in LUA_HELPERS:
            self.rig.run_file(os.path.join(HERE, "lua", name), state="bnm")

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


def lua(value):
    """A Python dict, list, str or number as a Lua constructor."""
    if isinstance(value, dict):
        return "{%s}" % ", ".join("%s = %s" % (k, lua(v)) for k, v in value.items())
    if isinstance(value, (list, tuple)):
        return "{%s}" % ", ".join(lua(v) for v in value)
    if isinstance(value, str):
        return json.dumps(value)
    return repr(value)


def diff(want, got):
    """{key: (want, got)} for every key where two item counts differ."""
    return {k: (want.get(k), got.get(k)) for k in sorted(set(want) | set(got)) if want.get(k) != got.get(k)}


def added(*counts):
    """Item counts summed key by key."""
    out = {}
    for d in counts:
        for k, v in as_dict(d).items():
            out[k] = out.get(k, 0) + v
    return out


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
                         'if p.scheduled_for_deletion == 0 then n = n + 1 end end return n' % force)
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


# ─── 9. Re-founding over full chests ───────────────────────────────────────

FILLER, PAD_FILLER = "stone", "coal"   # items no outpost kit carries
# What a team might have built in the gap between the south wall and the pad
# (dx, dy from the pad's centre; the pad is 8x8, 3 tiles below the wall). All
# of it comes back as items, the stone-wall and the inserter too: the base has
# its own of both, but these are one past a base's worth of each. The belt's
# lane contents come back as well; REG.base cannot see them, hence ON_BELTS.
EXTRAS = [
    {"name": "iron-chest",          "dx": -3.5, "dy": -5.5, "items": {"name": "copper-plate", "count": 100}},
    {"name": "fast-transport-belt", "dx": -2.5, "dy": -5.5, "items": {"name": "iron-plate", "count": 2}},
    {"name": "small-electric-pole", "dx": -1.5, "dy": -5.5},
    {"name": "wooden-chest",        "dx": 0.5,  "dy": -5.5, "items": {"name": "wood", "count": 30}},
    {"name": "stone-wall",          "dx": 2.5,  "dy": -5.5},
    {"name": "inserter",            "dx": 3.5,  "dy": -5.5},
]
REFUNDS = {"iron-chest": 1, "fast-transport-belt": 1, "small-electric-pole": 1, "wooden-chest": 1,
           "stone-wall": 1, "inserter": 1}
ON_BELTS = {"iron-plate": 2}


def check_full_refound(ctx, c):
    rig, force, surface = ctx.rig, "team-3", "mts-fulgora-3"
    # Place, read the kit, fill and build in one tick, so no robot moves an item in between.
    r = bnm(rig, 'local r = REG.place("%s", "%s", true) local fresh = REG.base("%s") '
                 'return {r = r, fresh = fresh, filled = REG.fill_site("%s", "%s", "%s", "%s"), '
                 'extras = REG.build_extras("%s", "%s", %s)}' % (
                     force, surface, surface, surface, force, FILLER, PAD_FILLER, surface, force, lua(EXTRAS)))
    fresh = r["fresh"]
    kit = as_dict(fresh.get("site_contents"))
    c.note("fresh outpost on %s: kit %s" % (surface, contents_str(kit)))
    c.note("filled every chest with %s and the pad with %s (%d items); built %d extras in the site" % (
        FILLER, PAD_FILLER, r["filled"], r["extras"]))
    if not c.expect(r["r"]["ok"] and r["r"]["outpost"], "outpost placed on %s (%s)" % (surface, r["r"])):
        return
    c.expect(kit and FILLER not in kit and PAD_FILLER not in kit, "the kit is known and holds no filler")
    c.expect(r["extras"] == len(EXTRAS), "all %d extras built (%d)" % (len(EXTRAS), r["extras"]))
    ctx.main.take_log()
    c.expect(kill_roboport(rig, surface, force), "roboport.die() killed it")
    r = bnm(rig, 'local left = REG.base("%s", "%s") local res = REG.place("%s", "%s", true) '
                 'return {left = left, res = res, new = REG.base("%s"), ground = REG.ground_items("%s")}' % (
                     surface, force, force, surface, surface, surface))
    left, res, new, ground = r["left"], r["res"], r["new"], r["ground"]
    lines = ctx.main.take_log()
    held, now = as_dict(left.get("site_contents")), as_dict(new.get("site_contents"))
    on_ground = as_dict(ground.get("items"))
    kept = added(held, ON_BELTS, kit)   # everything but the extras' own items
    want = added(kept, REFUNDS)
    got = added(now, on_ground)
    # What the ground and the new base gained beyond what was held is what
    # the team's extras came back as.
    returned = {x["name"]: got.get(x["name"], 0) - kept.get(x["name"], 0) for x in EXTRAS}
    spilled = [ln for ln in lines if "spilled salvage for the robots to bring in on %s:" % surface in ln]
    c.note("leftovers held %d items; re-found %s; the new base holds %d, %d on the ground in %d piles (%d marked)" % (
        sum(held.values()), res.get("ok"), sum(now.values()), sum(on_ground.values()), ground.get("piles", 0),
        ground.get("marked", 0)))
    c.note("totals: %d held + %d on belts + %d refunds + %d fresh kit = %d before; %d in the base + %d on the "
           "ground = %d after" % (sum(held.values()), sum(ON_BELTS.values()), sum(REFUNDS.values()),
                                  sum(kit.values()), sum(want.values()), sum(now.values()),
                                  sum(on_ground.values()), sum(got.values())))
    c.note("on the ground: %s" % contents_str(on_ground))
    c.note("the extras came back as: %s" % contents_str(returned))
    if not c.expect(res.get("ok") and new.get("outpost"), "re-founded (%s)" % res):
        return
    c.expect(as_dict(new.get("counts")) == as_dict(fresh.get("counts")), "the site holds exactly one fresh base "
             "(diff %s)" % diff(as_dict(fresh.get("counts")), as_dict(new.get("counts"))))
    short = {k: (v, now.get(k, 0)) for k, v in kit.items() if now.get(k, 0) < v}
    c.expect(not short, "the whole kit is in the new chests (short: %s)" % short)
    c.expect(got == want, "every item held or built in the site is in the new base or on the ground, and "
             "nothing else (want, got: %s)" % diff(want, got))
    c.expect(sum(got.values()) == sum(want.values()), "no item count lost: %d before, %d after" % (
        sum(want.values()), sum(got.values())))
    c.expect(returned == dict({x["name"]: 0 for x in EXTRAS}, **REFUNDS), "each thing the team built came back "
             "as its placing item, a base building's name beyond one base's worth included (want, got: %s)" % diff(
                 dict({x["name"]: 0 for x in EXTRAS}, **REFUNDS), returned))
    c.expect(spilled and ground.get("piles", 0) > 0, "the overflow was spilled and logged (%d log lines)" % len(spilled))
    c.expect(ground.get("marked") == ground.get("piles"), "every pile is marked for the robots (%s of %s)" % (
        ground.get("marked"), ground.get("piles")))
    c.expect(not log_trouble(lines), "no trouble in the log: %s" % log_trouble(lines)[:5])


# ─── 10. /bnm-forget-base on a home ────────────────────────────────────────

DESTROY_ROBOPORT = ('local rp = game.surfaces["%s"].find_entities_filtered{name = "bnm-roboport", force = "%s"}[1] '
                    'if not rp then return false end rp.destroy() return true')


def records_and_site(rig, surface, force):
    """BNM's base records, and what the command must not touch in the world:
    the site's entity counts and how much of its core is locked."""
    b = bnm(rig, 'REG.base("%s", "%s")' % (surface, force))
    return {"records": as_dict(bnm(rig, "REG.records()")),
            "site": {"counts": as_dict(b.get("counts")), "core": b.get("core"), "core_locked": b.get("core_locked")}}


def forget(rig, surface, force):
    """/bnm-forget-base over RCON, as the server console runs it. Returns its
    reply, and the records and the site just before and just after."""
    before = records_and_site(rig, surface, force)
    said = rig.cmd("/bnm-forget-base %s" % surface)
    return said, before, records_and_site(rig, surface, force)


def changes(before, after):
    """What differs between two records_and_site() reads: the changed fields
    of each record, and the site's changed entity counts and core locks."""
    out = {}
    rb, ra = before["records"], after["records"]
    for name in sorted(set(rb) | set(ra)):
        b, a = rb.get(name), ra.get(name)
        if a != b:
            out[name] = "gone" if a is None else "new" if b is None else sorted(
                k for k in set(a) | set(b) if a.get(k) != b.get(k))
    sb, sa = before["site"], after["site"]
    out.update(diff(dict(sb["counts"], core_locked=sb["core_locked"]),
                    dict(sa["counts"], core_locked=sa["core_locked"])))
    return out


def expect_refused(c, surface, when, reply, refusal):
    said, before, after = reply
    c.note("/bnm-forget-base %s (%s): %s" % (surface, when, said))
    c.expect(all(r in said for r in refusal), "%s, %s: refused, saying %s" % (surface, when, refusal))
    c.expect(before["records"].get(surface) and after == before,
             "%s, %s: no record, placed flag or entity changed (%s)" % (surface, when, changes(before, after)))


def check_forget_home(ctx, c):
    rig, force = ctx.rig, "team-13"
    home, outpost = "mts-nauvis-13", "mts-vulcanus-13"
    home_refusal = ("is %s's home base" % force, "cannot be re-founded", "/mts-disband %s" % force)
    h = bnm(rig, 'REG.place("%s", "%s")' % (force, home))
    o = bnm(rig, 'REG.place("%s", "%s", true)' % (force, outpost))
    c.expect(h["ok"] and h["home"] and o["ok"] and o["outpost"], "a home and an outpost placed (%s, %s)" % (h, o))
    expect_refused(c, home, "roboport standing", forget(rig, home, force), home_refusal)
    expect_refused(c, outpost, "roboport standing", forget(rig, outpost, force), ("still has a live roboport",))
    # destroy() raises no on_entity_died: the base is gone, the team is not eliminated.
    gone = [rig.eval(DESTROY_ROBOPORT % (s, force)) for s in (home, outpost)]
    c.expect(all(gone), "both roboports destroyed without a death event (%s)" % gone)
    expect_refused(c, home, "roboport gone", forget(rig, home, force), home_refusal)
    said, before, after = forget(rig, outpost, force)
    c.note("/bnm-forget-base %s (roboport gone): %s" % (outpost, said))
    kept = {k: v for k, v in before["records"].items() if k != outpost}
    c.expect("forgot the base record for %s" % outpost in said and outpost in before["records"]
             and after["records"] == kept, "the lost outpost's record and placed flag are forgotten, and no other "
             "record changed (%s)" % changes(dict(before, records=kept), after))
    sb, sa = before["site"], after["site"]
    c.note("%s's core: %d of %d locked before the forget, %d after" % (outpost, sb["core_locked"], sb["core"],
                                                                       sa["core_locked"]))
    c.expect(sa["counts"] == sb["counts"] and sa["core"] == sb["core"] and sb["core_locked"] > 0
             and sa["core_locked"] == 0, "the lost outpost's entities are untouched and its core became minable, as "
             "when its roboport dies (%d of %d locked before, %d after)" % (sb["core_locked"], sb["core"],
                                                                         sa["core_locked"]))
    again = bnm(rig, 'REG.place("%s", "%s", true)' % (force, outpost))
    rp = bnm(rig, 'REG.base("%s")' % outpost).get("roboport") or {}
    c.note("founded %s again after the forget: %s, roboport unit %s" % (outpost, again, rp.get("unit")))
    c.expect(again["ok"] and again["outpost"] and rp.get("is_record"),
             "the forgotten outpost can be founded again, with a new roboport")


# ─── 11. Unlock keeps the tuned copies locked ──────────────────────────────

def lock_line(lk):
    return "tuned %d (%d minable), bnm-* %d (%d minable), vanilla core %d (%d minable), walls %d (%d minable)" % (
        lk["tuned"], lk["tuned_minable"], lk["bnm"], lk["bnm_minable"], lk["core"], lk["core_minable"],
        lk["walls"], lk["walls_minable"])


def expect_locks_after(c, surface, lk):
    """After the unlock: every bnm-* entity (the roboport too) and every tuned
    copy stays locked, the vanilla core and the walls are minable. BNM tells a
    tuned copy by its having no placing item; the name prefix checks that."""
    tuned, bnm_names = set(as_dict(lk.get("tuned_names"))), set(as_dict(lk.get("bnm_names")))
    c.expect(lk["tuned"] > 0 and lk["tuned_minable"] == 0, "%s: every tuned copy stays locked" % surface)
    c.expect(lk["bnm"] > 0 and lk["bnm_minable"] == 0, "%s: every bnm-* entity, the roboport included, stays "
             "locked (%d of %d minable)" % (surface, lk["bnm_minable"], lk["bnm"]))
    c.expect(bnm_names - {"bnm-roboport"} == tuned and lk["bnm"] == lk["tuned"] + 1,
             "%s: the tuned copies are exactly the bnm-* entities but the roboport (tuned %s, bnm-* %s)" % (
                 surface, sorted(tuned), sorted(bnm_names)))
    c.expect(lk["core"] > 0 and lk["core_minable"] == lk["core"], "%s: the vanilla core is minable" % surface)
    c.expect(lk["walls"] > 0 and lk["walls_minable"] == lk["walls"], "%s: the walls are minable" % surface)


def check_unlock(ctx, c):
    rig, force = ctx.rig, "team-14"
    before_planets, after_planet = ("gleba", "fulgora"), "aquilo"
    for planet in before_planets:
        r = bnm(rig, 'REG.place("%s", "mts-%s-14", true)' % (force, planet))
        c.expect(r["ok"], "outpost placed on mts-%s-14 (%s)" % (planet, r))
    locks = {p: bnm(rig, 'REG.locks("mts-%s-14", "%s")' % (p, force)) for p in before_planets}
    for p, lk in locks.items():
        c.note("mts-%s-14 before the unlock: %s" % (p, lock_line(lk)))
        c.expect(lk["tuned"] > 0 and lk["core"] > 0 and lk["tuned_minable"] == 0 and lk["core_minable"] == 0
                 and lk["bnm_minable"] == 0, "mts-%s-14 before the unlock: the core and every bnm-* entity locked"
                 % p)
        c.expect(lk["walls"] > 0 and lk["walls_minable"] == lk["walls"],
                 "mts-%s-14 before the unlock: the walls were never locked" % p)
    bnm(rig, 'local sb = %s sb.unlock_minable("%s") return true' % (bnm_mod("scripts.starter_base"), force))
    r = bnm(rig, 'REG.place("%s", "mts-%s-14", true)' % (force, after_planet))
    c.expect(r["ok"], "outpost founded after the unlock on mts-%s-14 (%s)" % (after_planet, r))
    for p in before_planets + (after_planet,):
        lk = bnm(rig, 'REG.locks("mts-%s-14", "%s")' % (p, force))
        names = sorted(as_dict(lk.get("tuned_names")))
        c.note("mts-%s-14 after the unlock: %s; tuned: %s" % (p, lock_line(lk), ", ".join(names)))
        expect_locks_after(c, "mts-%s-14" % p, lk)
        if p == "aquilo":
            c.expect({"bnm-radar", "bnm-inserter"} <= set(names), "Aquilo's bnm-radar and bnm-inserter are tuned "
                     "copies (%s)" % names)


# ─── 12. Reconnect view (simulated player) ─────────────────────────────────

def check_reconnect_view(ctx, c):
    rig, force = ctx.rig, "team-14"
    a, b, rival = "mts-gleba-14", "mts-fulgora-14", "mts-nauvis-15"
    for planet in ("gleba", "fulgora"):
        bnm(rig, 'REG.place("%s", "mts-%s-14", true)' % (force, planet))   # a no-op when check 11 ran
    bnm(rig, 'REG.surface("%s") ~= nil' % rival)   # team-15's ground, no base needed
    # The landing pen, made by MTS's own code as a player's first landing would.
    rig.sc('package.loaded["__multi-team-support__/gui/landing_pen_terrain.lua"].get_or_create_surface()',
           state="mts")
    r = bnm(rig, 'REG.sim_reconnect("%s", "%s", "%s", "%s")' % (force, a, b, rival))
    c.note("left looking at %s (60.5, -30.25): stored %s, last view %s" % (a, r["stored"], r["last_view"]))
    c.note("reconnect park: %s; stored spot used up %s; next re-park: %s" % (r["reconnect"], r["consumed"], r["repark"]))
    c.note("left on a rival's ground: stored %s; left in the character controller: stored %s" % (
        r["rival_stored"], r["character_stored"]))
    c.note("left on %s, then viewing %s at the re-park: %s (spot used up %s)" % (a, b, r["moved"], r["moved_consumed"]))
    spot = {"surface": a, "x": 60.5, "y": -30.25}
    origin = {"x": 16, "y": 16}
    c.expect(r["stored"] == spot and r["last_view"] == a, "leaving stores the surface and the spot")
    c.expect(r["reconnect"] == spot, "the reconnect's park views that spot (%s)" % r["reconnect"])
    c.expect(r["consumed"] and r["repark"] == dict(origin, surface=a), "the spot is used once; the next "
             "re-park centres on the base (%s)" % r["repark"])
    c.expect(not r["rival_stored"] and not r["character_stored"], "nothing is stored off the team's own ground "
             "or outside remote view")
    c.expect(r["moved"] == dict(origin, surface=b) and r["moved_consumed"],
             "a spot on another surface is dropped, and the view centres on the base (%s)" % r["moved"])


# ─── 13. Placing twice builds once ─────────────────────────────────────────

IDEM_FORCE = "team-16"
IDEM_BASES = [("mts-nauvis-16", False), ("mts-vulcanus-16", True)]   # its home first, then an outpost


def place_twice(ctx, c, surface, outpost):
    """place() on a new surface, then twice more in the same tick (same opts,
    then the other kind). Returns the footprint after the first call."""
    kind, other = ("an outpost", "a home") if outpost else ("a home", "an outpost")
    r = bnm(ctx.rig, 'REG.place_twice("%s", "%s", %s)' % (IDEM_FORCE, surface, "true" if outpost else "false"))
    once, again = r["once"], r["again"]
    fp = once["footprint"]
    c.note("%s: first place() %s (%s, %d entities, roboport %s); again as %s: %s; asking for %s: %s" % (
        surface, r["first"], kind, fp["entities"], fp["roboport"], kind, r["second"], other, r["other"]))
    c.expect(r["first"] is True and r["home"] is (not outpost) and fp["roboport"],
             "the first place() on %s built %s with a roboport" % (surface, kind))
    c.expect(r["second"] is False and r["other"] is False, "the repeat place() calls on %s returned false (%s, %s)"
             % (surface, r["second"], r["other"]))
    c.expect(again == once, "the repeat calls built, removed and restocked nothing on %s (once, after: %s)" % (
        surface, diff(once, again)))
    c.expect(r["same_record"], "%s keeps the record the first call made" % surface)
    return fp


def check_idempotent(ctx, c):
    rig = ctx.rig
    ctx.main.take_log()
    first = {s: place_twice(ctx, c, s, outpost) for s, outpost in IDEM_BASES}
    run_ticks(rig, 60, 1)
    for surface, _ in IDEM_BASES:
        later = bnm(rig, 'REG.place_again("%s", "%s")' % (IDEM_FORCE, surface))
        c.note("%s, 60 ticks later: place() %s, %d entities" % (surface, later["ok"], later["footprint"]["entities"]))
        c.expect(later["ok"] is False and later["footprint"] == first[surface],
                 "a later place() on %s returned false and changed nothing (%s)" % (
                     surface, diff(first[surface], later["footprint"])))
    lines = ctx.main.take_log()
    for surface, outpost in IDEM_BASES:
        text = "starter %s placed for %s on %s" % ("outpost" if outpost else "home base", IDEM_FORCE, surface)
        n = sum(1 for ln in lines if ln.rstrip().endswith(text))
        c.expect(n == 1, "'%s' logged once (%d)" % (text, n))
    c.expect(not log_trouble(lines), "no trouble in the log: %s" % log_trouble(lines)[:5])


# ─── 14. What a re-found keeps whole ───────────────────────────────────────

DATA_FORCE, DATA_SURFACE = "team-17", "mts-gleba-17"
# What REG.build_data_extras builds in the site comes back as its placing
# item: the in-site spidertron and tank with their equipment, the train (6
# rails and a locomotive) and the iron chest. IN_CHESTS are the data items in
# that chest and in one of the base's own storage chests.
DATA_REFUNDS = {"spidertron": 1, "tank": 1, "rail": 6, "locomotive": 1, "iron-chest": 1}
IN_CHESTS = ["blueprint set-up", "modular-armor eq=1", "spidertron eq=1", "spidertron eq=2"]
VEHICLES = ["spidertron eq=3", "tank eq=2"]


def check_salvage_data(ctx, c):
    rig, force, surface = ctx.rig, DATA_FORCE, DATA_SURFACE
    # Place, read the kit and build in one tick, so no robot moves an item in between.
    r = bnm(rig, 'local r = REG.place("%s", "%s", true) local fresh = REG.base("%s") '
                 'return {r = r, fresh = fresh, built = REG.build_data_extras("%s", "%s")}' % (
                     force, surface, surface, surface, force))
    if not c.expect(r["r"]["ok"] and r["r"]["outpost"], "outpost placed on %s (%s)" % (surface, r["r"])):
        return
    fresh, b = r["fresh"], r["built"]
    kit, out = as_dict(fresh.get("site_contents")), b["outside"]
    c.note("built: spidertron with %d pieces, tank with %d, %d rails and a locomotive %s; the chests hold %s" % (
        b["spider_eq"], b["tank_eq"], b["rails"], b["loco"], b["data"]))
    c.note("a spidertron with %d piece parked outside the site at (%s, %s), %d of its legs inside" % (
        out["eq"], out["x"], out["y"], out["legs_in"]))
    c.expect(b["spider_eq"] == 3 and b["tank_eq"] == 2 and b["rails"] == 6 and b["loco"] and b["data"] == IN_CHESTS,
             "the vehicles, the train and the chests' data items were built as meant")
    c.expect(out["body_out"] and out["legs_in"] > 0, "the parked spider's body is outside the site, a leg inside")
    ctx.main.take_log()
    c.expect(kill_roboport(rig, surface, force), "roboport.die() killed it")
    r = bnm(rig, 'local left = REG.base("%s", "%s") local res = REG.place("%s", "%s", true) '
                 'return {left = left, res = res, new = REG.base("%s"), ground = REG.ground_items("%s"), '
                 'after = REG.data_after("%s", "%s", %d)}' % (
                     surface, force, force, surface, surface, surface, surface, force, out["unit"]))
    lines = ctx.main.take_log()
    left, res, new, after = r["left"], r["res"], r["new"], r["after"]
    held = as_dict(left.get("site_contents"))
    want = added(held, kit, DATA_REFUNDS)
    got = added(as_dict(new.get("site_contents")), as_dict(r["ground"].get("items")))
    swept = [int(m.group(1)) for m in (re.search(r"swept (\d+) leftover entities from the base site on %s$"
                                                 % re.escape(surface), ln.rstrip()) for ln in lines) if m]
    leftover = sum(as_dict(left.get("counts")).values())
    c.note("re-found %s; swept %s of %d; data items now %s" % (res.get("ok"), swept, leftover, after["data"]))
    c.note("the parked spider after: %s; rails standing %d, locomotives %d" % (
        after["outside"], after["rails"], after["locos"]))
    if not c.expect(res.get("ok") and new.get("outpost"), "re-founded (%s)" % res):
        return
    c.expect(after["data"] == sorted(IN_CHESTS + VEHICLES), "every vehicle came back as an item with its "
             "equipment, and the chests' items kept their grids and blueprint (%s)" % after["data"])
    c.expect(after["outside"] and after["outside"]["eq"] == out["eq"] and (after["outside"]["x"], after["outside"]["y"])
             == (out["x"], out["y"]), "the spider parked outside the site is untouched (%s)" % after["outside"])
    c.expect(after["rails"] == 0 and after["locos"] == 0, "no rail or locomotive left standing in the site")
    c.expect(swept == [leftover], "every leftover was swept (%s of %d)" % (swept, leftover))
    c.expect(got == want, "everything held or built in the site is in the new base or on the ground, once "
             "(want, got: %s)" % diff(want, got))
    c.expect(not log_trouble(lines), "no trouble in the log: %s" % log_trouble(lines)[:5])


# ─── 15. A home founded again after its surface was deleted ────────────────

def check_home_refound(ctx, c):
    rig, force = ctx.rig, "team-18"
    home, outpost = "mts-nauvis-18", "mts-vulcanus-18"
    h = bnm(rig, 'REG.place("%s", "%s")' % (force, home))
    o = bnm(rig, 'REG.place("%s", "%s", true)' % (force, outpost))
    if not c.expect(h["ok"] and h["home"] and o["ok"] and o["outpost"], "a home and an outpost placed (%s, %s)"
                    % (h, o)):
        return
    ctx.main.take_log()
    # Deleted outside a disband, as an admin's delete_surface would: MTS keeps the team.
    rig.sc('game.delete_surface("%s")' % home)
    run_ticks(rig, 10, 1)   # the engine deletes a surface at the end of the tick
    exists, left = rig.eval('game.surfaces["%s"] ~= nil' % home), bases_of(rig, force)
    c.note("%s deleted: surface still there %s; %s bases left %s" % (home, exists, force, left))
    c.expect(not exists and left == {outpost: "outpost"}, "deleting %s forgot its home record and kept the "
             "outpost (%s)" % (home, left))
    # place() without opts, as a member arriving on the recreated surface calls it.
    again = bnm(rig, 'REG.place("%s", "%s")' % (force, home))
    bases = bases_of(rig, force)
    lines = ctx.main.take_log()
    c.note("%s recreated and founded again: %s; %s bases %s" % (home, again, force, bases))
    c.expect(again["ok"] and again["home"], "the team had no home, so the new base on %s is its home (%s)" % (
        home, again))
    c.expect(bases == {home: "home", outpost: "outpost"}, "the team has one home and its outpost (%s)" % bases)
    c.expect(not log_trouble(lines), "no trouble in the log: %s" % log_trouble(lines)[:5])
    check_home_refound_by_clone(ctx, c)


def check_home_refound_by_clone(ctx, c):
    """The same deletion, then a clone shipped back above the home planet: with
    no home left, Establish base re-founds the home rather than an outpost."""
    rig, force = ctx.rig, "team-19"
    home, outpost, platform = "mts-nauvis-19", "mts-vulcanus-19", "P-home19"
    bnm(rig, 'REG.place("%s", "%s")' % (force, home))
    bnm(rig, 'REG.place("%s", "%s", true)' % (force, outpost))
    rig.sc('game.delete_surface("%s")' % home)
    run_ticks(rig, 10, 1)
    ctx.main.take_log()
    p = bnm(rig, 'REG.make_platform("%s", "%s", "%s")' % (force, home, platform))
    c.expect(p["location"] == home and not p["planet_surface"],
             "platform parked above %s with no surface yet (%s)" % (home, p))
    bnm(rig, 'REG.hub_insert("%s", "%s", {name = "%s", count = 1})' % (force, platform, CLONE))
    res = bnm(rig, 'REG.establish("%s", "%s")' % (force, platform))
    bases, lines = bases_of(rig, force), ctx.main.take_log()
    c.note("clone above %s with no home: %s; %s bases %s" % (home, res, force, bases))
    c.expect(res.get("ok") and res.get("home"), "Establish base re-founded the home (%s)" % res)
    c.expect(bases == {home: "home", outpost: "outpost"}, "the team has one home and its outpost (%s)" % bases)
    c.expect(bnm(rig, 'REG.clones("%s", "%s")' % (force, platform)) == 0, "the clone was consumed")
    c.expect(not log_trouble(lines), "no trouble in the log: %s" % log_trouble(lines)[:5])


# ─── 16. Admin test commands ───────────────────────────────────────────────

TC_SLOT, TC_PLANET = 20, "gleba"            # team-20: no other check uses it
TC_FREE_SLOT = 15                           # never claimed: check 12 only uses its ground
TC_PLATFORM = "BNM test: " + TC_PLANET      # the name /bnm-test-orbit gives it
TC_TECHS = ["planet-discovery-" + TC_PLANET, CLONE]
TC_SETTING = 'settings.global["bnm-test-commands"]'


def orbit_state(rig, force, planet):
    """REG.orbit_state: research, the planet's unlock and surface, platforms."""
    s = bnm(rig, 'REG.orbit_state("%s", "%s", %s)' % (force, planet, lua(TC_TECHS)))
    s["platforms"] = s["platforms"] if isinstance(s["platforms"], list) else []
    return s


def orbit_line(s):
    return "%d researched (%s), unlocked %s, surface %s, platforms %s" % (
        s["researched"], ", ".join("%s %s" % kv for kv in sorted(s["techs"].items())), s["unlocked"],
        s["surface"], s["platforms"] or "none")


def check_test_commands(ctx, c):
    """/bnm-test-orbit and /bnm-test-kill-roboport from the server console, off
    and then on. Team-20 gets a home and an occupied slot (the fixture), so
    'team kept' after the outpost's roboport dies means something."""
    rig, force = ctx.rig, "team-%d" % TC_SLOT
    planet = "mts-%s-%d" % (TC_PLANET, TC_SLOT)
    orbit = "/bnm-test-orbit %s %s" % (TC_PLANET, force)
    home = team_home(ctx, c, TC_SLOT)
    ctx.main.take_log()
    # Off, the default: refused, nothing researched or created.
    c.expect(bnm(rig, TC_SETTING + ".value") is False, "precondition: bnm-test-commands is off by default")
    before = orbit_state(rig, force, planet)
    said = rig.cmd(orbit)
    after = orbit_state(rig, force, planet)
    c.note("setting off: %s -> %s" % (orbit, said))
    c.expect("/bnm-test-orbit is off" in said, "refused while the setting is off")
    c.expect(after == before and not after["platforms"] and not any(after["techs"].values())
             and not after["unlocked"], "the refusal changed nothing: %s" % orbit_line(after))
    rig.sc(TC_SETTING + " = {value = true}", state="bnm")
    try:
        test_commands_on(ctx, c, force, planet, orbit, home)
    finally:
        rig.sc(TC_SETTING + " = {value = false}", state="bnm")
    lines = ctx.main.take_log()
    c.expect(logged(lines, "lost its outpost on %s" % planet), "the outpost's loss was logged")
    c.expect(not log_trouble(lines), "no trouble in the log: %s" % log_trouble(lines)[:5])


def moved_and_deleted(ctx, c, force, planet, orbit, home):
    """The test platform flown to the home planet comes back with one more
    clone; one pending deletion is left to die and a new one is made."""
    rig, one = ctx.rig, lambda n: [{"name": TC_PLATFORM, "at": planet, "clones": n}]
    bnm(rig, 'REG.move_platform("%s", "%s", "%s")' % (force, TC_PLATFORM, home))
    rig.cmd(orbit)
    back = orbit_state(rig, force, planet)
    c.note("flown to %s, then again: %s" % (home, orbit_line(back)))
    c.expect(back["platforms"] == one(3), "a platform flown to %s is back above %s, now 3 clones (%s)" % (
        home, planet, back["platforms"]))
    bnm(rig, 'REG.delete_platform("%s", "%s")' % (force, TC_PLATFORM))
    rig.cmd(orbit)
    anew = orbit_state(rig, force, planet)
    c.note("deleted, then again: %s" % orbit_line(anew))
    c.expect(anew["platforms"] == one(1), "a platform pending deletion is not reused: a new one, 1 clone (%s)"
             % anew["platforms"])


def test_commands_on(ctx, c, force, planet, orbit, home):
    rig = ctx.rig
    said = rig.cmd(orbit)
    first = orbit_state(rig, force, planet)
    c.note("setting on: %s -> %s" % (orbit, said))
    c.note("then: %s" % orbit_line(first))
    c.expect(all(first["techs"].values()), "researched %s" % first["techs"])
    c.expect(first["unlocked"], "%s unlocked for %s" % (planet, force))
    c.expect(first["platforms"] == [{"name": TC_PLATFORM, "at": planet, "clones": 1}],
             "\"%s\" parked above %s with 1 clone (%s)" % (TC_PLATFORM, planet, first["platforms"]))
    c.expect(not first["surface"], "%s has no surface yet" % planet)
    c.expect("A member of %s can now open its hub" % force in said,
             "the console is told a member of %s presses Establish base" % force)
    said = rig.cmd(orbit)
    again = orbit_state(rig, force, planet)
    c.note("again: %s" % orbit_line(again))
    c.expect(again["platforms"] == [{"name": TC_PLATFORM, "at": planet, "clones": 2}]
             and again["researched"] == first["researched"],
             "again: still one platform, now 2 clones, nothing more researched (%s)" % again["platforms"])
    moved_and_deleted(ctx, c, force, planet, orbit, home)

    res = bnm(rig, 'REG.establish("%s", "%s")' % (force, TC_PLATFORM))
    bases = bases_of(rig, force)
    c.note("establish_for on its hub: %s; %s bases %s" % (res, force, bases))
    c.expect(res.get("ok") and not res.get("home") and bases.get(planet) == "outpost",
             "establish_for on the test platform's hub founded an outpost on %s" % planet)

    said = rig.cmd("/bnm-test-kill-roboport %s" % planet)
    after = bnm(rig, 'REG.base("%s", "%s")' % (planet, force))
    pool, bases = slot_state(rig, TC_SLOT), bases_of(rig, force)
    c.note("/bnm-test-kill-roboport %s -> %s" % (planet, said))
    c.note("then: roboport %s, recorded %s, placed %s; slot %s, bases %s" % (
        after.get("roboport"), after.get("recorded"), after.get("placed"), pool, bases))
    c.expect("destroyed the outpost roboport on %s" % planet in said, "announced the outpost roboport's death")
    c.expect(not after.get("roboport") and not after.get("recorded") and not after.get("placed"),
             "the outpost is wiped: its roboport is dead, its record and placed flag cleared")
    c.expect(pool == "occupied" and bases == {home: "home"}, "%s kept, with its home (slot %s, bases %s)" % (
        force, pool, bases))

    # No base there: usage, and nothing changes. The console has no surface of its own.
    for cmd in ("/bnm-test-kill-roboport %s" % planet, "/bnm-test-kill-roboport"):
        records = bnm(rig, "REG.records()")
        said = rig.cmd(cmd)
        c.note("%s (no base) -> %s" % (cmd, said))
        c.expect("Usage: /bnm-test-kill-roboport" in said and bnm(rig, "REG.records()") == records,
                 "%s answered with usage and changed no record" % cmd)
    state = orbit_state(rig, force, planet)
    for cmd in ("/bnm-test-orbit plutonium %s" % force, "/bnm-test-orbit"):
        said = rig.cmd(cmd)
        c.note("%s -> %s" % (cmd, said))
        c.expect("usage: /bnm-test-orbit" in said, "%s answered with usage" % cmd)
    c.expect(orbit_state(rig, force, planet) == state, "the bad input changed nothing")
    unclaimed_refused(ctx, c)


def unclaimed_refused(ctx, c):
    """A free MTS slot: refused, since MTS's claim keeps platforms and the
    next team to claim it would inherit the clones."""
    rig, force = ctx.rig, "team-%d" % TC_FREE_SLOT
    planet = "mts-%s-%d" % (TC_PLANET, TC_FREE_SLOT)
    c.expect(slot_state(rig, TC_FREE_SLOT) == "available", "precondition: %s's slot is free" % force)
    before = orbit_state(rig, force, planet)
    cmd = "/bnm-test-orbit %s %s" % (TC_PLANET, force)
    said = rig.cmd(cmd)
    after = orbit_state(rig, force, planet)
    c.note("%s (free slot) -> %s" % (cmd, said))
    c.expect("%s is not a claimed team" % force in said, "refused a free slot")
    c.expect(after == before and not after["platforms"] and not after["unlocked"],
             "the refusal changed nothing: %s" % orbit_line(after))
    said = rig.cmd("/bnm-test-orbit %s" % TC_PLANET)
    c.note("/bnm-test-orbit %s (console, no team) -> %s" % (TC_PLANET, said))
    c.expect("no team to act for" in said, "the console with no team named has no team to act for")


# ─── 17. Migration from 0.1.3 ──────────────────────────────────────────────

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
    (9, "re-found an outpost whose chests are full: kit whole, nothing lost", check_full_refound),
    (10, "/bnm-forget-base refuses a home base, wipes a lost outpost", check_forget_home),
    (11, "unlocking keeps the planet-tuned copies locked, frees the vanilla core", check_unlock),
    (12, "a reconnect views the spot the player left (simulated player)", check_reconnect_view),
    (13, "placing twice on a surface builds once", check_idempotent),
    (14, "a re-found keeps vehicles' equipment and items' data", check_salvage_data),
    (15, "a home founded again after its surface was deleted is a home", check_home_refound),
    (16, "admin test commands: /bnm-test-orbit, /bnm-test-kill-roboport", check_test_commands),
    (17, "migration from 0.1.3 (%s)" % OLD_REV, check_migration),
]
NEEDS = {5: [4], 6: [4]}
MIGRATION_CHECK = 17   # runs in its own world, after the main server stops; stays last


def set_rig(name, ports):
    global GAME_PORT, RCON_PORT, MAIN, MIGRATION
    MAIN, MIGRATION = name, name + "-mig"
    GAME_PORT, RCON_PORT = (int(p) for p in ports.split(","))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--checks", default=",".join(str(n) for n, _, _ in CHECKS), help="comma-separated check numbers")
    ap.add_argument("--no-stage", action="store_true", help="reuse the staged mods dir as it is")
    ap.add_argument("--keep", action="store_true", help="leave the main server running at the end")
    ap.add_argument("--out", help="write the results as JSON here")
    ap.add_argument("--rig", default=MAIN, help="rig name: server <rig>, mods dir mods-<rig>, "
                    "migration world <rig>-mig (default %(default)s)")
    ap.add_argument("--ports", default="%d,%d" % (GAME_PORT, RCON_PORT), help="game port,RCON port "
                    "(default %(default)s)")
    a = ap.parse_args()
    set_rig(a.rig, a.ports)
    wanted = {int(n) for n in a.checks.split(",") if n}
    for n in list(wanted):
        wanted.update(NEEDS.get(n, []))

    ctx = Ctx(stage=not a.no_stage)
    results = []
    try:
        if wanted - {MIGRATION_CHECK}:
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
