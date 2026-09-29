#!/usr/bin/env python3
"""Fulgora starter-base layout tests on the sp2 rig.

Each run: one team slot, BNM's real placement on mts-fulgora-<slot>, then the
layout's substitutions applied in the level state, then the instrumented
sampler (fulg_rig.lua) with a constant test load.

usage: fulg_test.py SPEC.json OUT.json
SPEC = {"cycles": 20, "speed": 1000,
        "layouts": {name: [[old, x, y, new, nx, ny], ...]},
        "runs": [{"slot": 2, "layout": name, "load": kw, "busy": false}, ...]}
"""
import json, os, sys, time
sys.path.insert(0, '/home/shobhitg/src/brave-new-mts/tools/rig')
from probe import Rig, bnm_mod

HERE = os.path.dirname(os.path.abspath(__file__))
ORIGIN = (16, 16)

APPLY = '''
local s = game.surfaces["%s"]; local f = game.forces["%s"]
local subs = %s
local out = {}
for _, sb in pairs(subs) do
  local old, x, y, new, nx, ny = sb[1], sb[2] + 16, sb[3] + 16, sb[4], sb[5] + 16, sb[6] + 16
  local e = s.find_entities_filtered{name = old, position = {x, y}, radius = 0.6, force = f}[1]
  if not e then out[#out+1] = "missing " .. old .. " at " .. x .. "," .. y
  else
    e.destroy()
    if new ~= "" then
      local c = s.create_entity{name = new, position = {nx, ny}, force = f}
      if not c then out[#out+1] = "failed " .. new .. " at " .. nx .. "," .. ny
      elseif c.type == "accumulator" then c.energy = c.electric_buffer_size end
    end
  end
end
return out
'''


def lua_list(subs):
    return "{" + ",".join('{"%s",%g,%g,"%s",%g,%g}' % tuple(s) for s in subs) + "}"


def main():
    spec = json.load(open(sys.argv[1]))
    out_path = sys.argv[2]
    rig = Rig(int(spec.get("port", 27312)), timeout=900)
    rig.run_file(os.path.join(HERE, "fulg_rig.lua"))
    rig.sc('storage.rig = nil')
    cycles = spec.get("cycles", 20)
    for run in spec["runs"]:
        slot = run["slot"]; force = "team-%d" % slot
        sname = rig.eval('RIG.create_surface("fulgora", %d)' % slot)
        rig.sc('%s.place("%s", game.surfaces["%s"])' % (bnm_mod("scripts.starter_base"), force, sname), state="bnm")
        subs = spec["layouts"][run["layout"]]
        if subs:
            errs = rig.eval(APPLY % (sname, force, lua_list(subs)))
            if errs:
                raise RuntimeError("%s: %s" % (sname, errs))
        opts = '{force="%s", planet="fulgora", slot=%d, load_kw=%g, cycles=%d, label="%s", busy_bots=%s}' % (
            force, slot, run["load"], cycles, run["layout"], "true" if run.get("busy") else "false")
        info = rig.eval('RIG.add_run("%s", %s)' % (sname, opts))
        if info["load_network"] != info["base_network"]:
            raise RuntimeError("load not on base network " + sname)
        run["surface"] = sname
        run["acc_cap_mj"] = info["acc_cap"] / 1e6
        print("set up", sname, run["layout"], "load", run["load"], "acc cap %.0f MJ" % run["acc_cap_mj"], flush=True)
    rig.eval("RIG.start(%g)" % spec.get("speed", 1000))
    t0 = time.time(); last = 0
    while True:
        s = rig.eval("RIG.status()")
        if s["done"] >= s["total"]:
            break
        if time.time() - last > 30:
            print("  %d/%d done, %d ticks left, %.0fs" % (s["done"], s["total"], s["ticks_left"], time.time() - t0), flush=True)
            last = time.time()
        time.sleep(3)
    rig.eval("RIG.stop()")
    reps = {}
    for run in spec["runs"]:
        reps[run["surface"]] = {"run": run, "rep": rig.eval('RIG.report("%s")' % run["surface"])}
    json.dump({"spec": spec, "reports": reps}, open(out_path, "w"))
    print("wall %.0fs" % (time.time() - t0))
    summarize(reps)


def summarize(reps):
    print("%-15s %-10s %6s %7s %7s %6s %7s %7s %7s  %s" % ("surface", "layout", "load", "total", "strk/d", "empty", "accmin", "robomin", "att kW", "damage/died"))
    for sname, v in reps.items():
        run, r = v["run"], v["rep"]
        cyc = r["cycles"]; n = len(cyc)
        if not n:
            print(sname, "no cycles"); continue
        isacc = lambda k: k == "accumulator" or k.startswith("lab-acc") or k.startswith("bnm-fulgora-acc")
        total = sum(sum(x for k, x in c["cons"].items() if not isacc(k)) for c in cyc) / n
        att = sum(sum(x for k, x in c["prod"].items() if k in ("lightning-rod", "lightning-collector") or k.startswith("lab-col") or k.startswith("lab-rod") or k.startswith("bnm-")) for c in cyc) / n
        emptied = sum(1 for c in cyc if c["empty_samples"] > 0)
        strikes = sum(c.get("strikes", 0) for c in cyc) / n
        dmg = {k: v for k, v in (r.get("damage") or {}).items()}
        died = r.get("died") or {}
        print("%-15s %-10s %6.0f %7.1f %7.2f %3d/%-2d %7.1f %7.1f %7.1f  %s %s" % (
            sname, run["layout"][:10], run["load"], total, strikes, emptied, n, r["acc_min_mj"], r["robo_min_mj"], att,
            json.dumps(dmg) if dmg else "", json.dumps(died) if died else ""))


if __name__ == "__main__":
    if sys.argv[1] == "--summarize":
        summarize(json.load(open(sys.argv[2]))["reports"])
    else:
        main()
