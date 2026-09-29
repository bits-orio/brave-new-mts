#!/usr/bin/env python3
"""Scripted RCON probes for a headless Brave New MTS test server.

Wraps ~/factorio-dev/rig/rcon.py (reuses its packet code) with one persistent,
warmed-up connection and three Lua states:

    level  /sc <lua>                          the scenario (freeplay) state
    bnm    /sc __brave-new-mts__ <lua>         BNM's own state: its storage, and
                                               its modules via package.loaded
    mts    /sc __multi-team-support__ <lua>    MTS's state (read-only use!)

In the bnm state, BNM's modules are reachable as
    package.loaded["__brave-new-mts__/scripts/starter_base.lua"]
and `bnm_mod("scripts.starter_base")` below builds that expression for you.

CLI:
    probe.py [--port 27311] [--state level|bnm|mts] 'lua ...'
    probe.py [--port 27311] [--state ...] --file snippet.lua
    probe.py --port 27311 --json 'return game.tick'   # returns JSON of the value

Library:
    from probe import Rig
    rig = Rig(27311)
    rig.sc('rcon.print(game.tick)')
    rig.eval('game.tick')                  # -> python value (via helpers.table_to_json)
    rig.eval('storage.bnm_base', state='bnm')
"""
import argparse
import json
import os
import socket
import sys
import time

RCON_PY = os.path.expanduser(os.environ.get("RIG_RCON_PY", "~/factorio-dev/rig/rcon.py"))
PASSWORD = os.environ.get("RIG_RCON_PASSWORD", "rig")

STATE_PREFIX = {
    "level": "/sc ",
    "bnm": "/sc __brave-new-mts__ ",
    "mts": "/sc __multi-team-support__ ",
}


def _load_rcon_codec():
    """pkt()/recv() from the rig's rcon.py. That file runs main() at import, so
    exec it without its last `main()` call instead of importing it."""
    src = open(RCON_PY).read()
    src = src[: src.rstrip().rfind("main()")]
    ns = {}
    exec(compile(src, RCON_PY, "exec"), ns)
    return ns["pkt"], ns["recv"]


_pkt, _recv = _load_rcon_codec()


def bnm_mod(module):
    """Lua expression for a loaded BNM module, e.g. bnm_mod('scripts.starter_base')."""
    return 'package.loaded["__brave-new-mts__/%s.lua"]' % module.replace(".", "/")


class Rig:
    def __init__(self, port, password=PASSWORD, timeout=120):
        self.port = port
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=timeout)
        self.sock.sendall(_pkt(1, 3, password))
        rid, _, _ = _recv(self.sock)
        if rid == -1:
            raise RuntimeError("RCON auth failed on port %d" % port)
        self._id = 100
        # The first /sc per RCON session is swallowed by the achievements prompt.
        self.cmd('/sc rcon.print("warmup")')

    def close(self):
        self.sock.close()

    def cmd(self, text):
        """Send one raw console command, return the printed output."""
        self._id += 1
        self.sock.sendall(_pkt(self._id, 2, text))
        _, _, body = _recv(self.sock)
        return body.strip()

    def sc(self, lua, state="level"):
        """Run Lua in the given state; returns whatever it rcon.print()ed."""
        out = self.cmd(STATE_PREFIX[state] + lua)
        if out.startswith("Cannot execute command.") or "Error:" in out[:200]:
            raise RuntimeError("Lua error in %s state:\n%s" % (state, out))
        return out

    def eval(self, expr, state="level"):
        """Evaluate a Lua expression (or a chunk that ends in `return x`) and
        return its value decoded from JSON. Non-JSON values come back as str."""
        body = expr if expr.lstrip().startswith(("return", "local")) or "\n" in expr else "return " + expr
        lua = ("local __f = function() %s end local __ok, __v = pcall(__f) "
               "if not __ok then rcon.print('LUAERR:' .. tostring(__v)) return end "
               "if type(__v) == 'table' then rcon.print(helpers.table_to_json(__v)) "
               "else rcon.print(helpers.table_to_json({v = __v})) end" % body)
        out = self.sc(lua, state)
        if out.startswith("LUAERR:"):
            raise RuntimeError("Lua error in %s state: %s" % (state, out[7:]))
        if not out:
            return None
        data = json.loads(out)
        if isinstance(data, dict) and list(data.keys()) == ["v"]:
            return data["v"]
        return data

    def run_file(self, path, state="level"):
        return self.sc(open(path).read(), state)

    def tick(self):
        return self.eval("game.tick")

    def wait_ticks(self, n, poll=1.0, progress=None):
        """Block until game.tick has advanced by n. Returns the final tick."""
        target = self.tick() + n
        while True:
            t = self.tick()
            if progress:
                progress(t, target)
            if t >= target:
                return t
            time.sleep(poll)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=int(os.environ.get("RIG_PORT", 27311)))
    ap.add_argument("--state", choices=sorted(STATE_PREFIX), default="level")
    ap.add_argument("--file", help="run this Lua file")
    ap.add_argument("--json", action="store_true", help="evaluate an expression and print it as JSON")
    ap.add_argument("lua", nargs="?")
    a = ap.parse_args()
    rig = Rig(a.port)
    if a.file:
        print(rig.run_file(a.file, a.state))
    elif a.json:
        print(json.dumps(rig.eval(a.lua, a.state), indent=1))
    else:
        print(rig.sc(a.lua, a.state))
    rig.close()


if __name__ == "__main__":
    main()
