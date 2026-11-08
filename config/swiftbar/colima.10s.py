#!/usr/bin/python3
# <swiftbar.title>Colima</swiftbar.title>
# <swiftbar.desc>Start/stop Colima (Docker runtime) and manage its containers</swiftbar.desc>
# <swiftbar.version>1.0</swiftbar.version>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
"""SwiftBar menu bar item for Colima (profile "default"). Colours from config/theme/out/palette.json as light,dark pairs.

Render mode (no args): reads `colima list --json` and `docker ps` (all calls have timeouts) and prints the menu.
Action mode (`--do ACTION [ARG]`, called by the menu items): start/stop/restart launch colima detached and write a
marker file, so the next refreshes show a transitional state instead of blocking; container-stop/restart run docker.
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
SELF = os.path.realpath(__file__)
HOME = os.path.expanduser("~")
PROFILE = "default"
PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
ENV = dict(os.environ, PATH=PATH, DOCKER_HOST="unix://%s/.colima/%s/docker.sock" % (HOME, PROFILE))
MARK = os.path.join(HOME, "Library", "Caches", "colima-swiftbar.json")
MARK_TTL = 300


def which(name):
    return next((os.path.join(d, name) for d in PATH.split(":") if os.access(os.path.join(d, name), os.X_OK)), None)


COLIMA, DOCKER = which("colima"), which("docker")


def run(argv, timeout=4):
    try:
        r = subprocess.run(argv, env=ENV, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout
    except (OSError, subprocess.SubprocessError):
        return 1, ""


# ---- actions -----------------------------------------------------------------------------------------------------
def set_mark(action):
    try:
        os.makedirs(os.path.dirname(MARK), exist_ok=True)
        with open(MARK, "w") as f:
            json.dump({"action": action, "t": time.time()}, f)
    except OSError:
        pass


def detached(argv):
    subprocess.Popen(argv, env=ENV, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


if len(sys.argv) >= 3 and sys.argv[1] == "--do":
    act, arg = sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""
    if act in ("start", "stop", "restart") and COLIMA:
        set_mark(act)
        # restart = stop then start in one detached shell; the marker stays "restart" until it is running again
        if act == "restart":
            detached(["/bin/bash", "-c", '"$0" stop; "$0" start', COLIMA])
        else:
            detached([COLIMA, act])
    elif act in ("container-stop", "container-restart") and DOCKER and arg:
        detached([DOCKER, act.split("-")[1], arg])
    sys.exit(0)

# ---- colours -----------------------------------------------------------------------------------------------------
PAL = {}
for _p in (os.path.expanduser("~/.config/theme/out/palette.json"), os.path.join(HERE, "..", "theme", "out", "palette.json")):
    try:
        with open(_p, encoding="utf-8") as f:
            PAL = json.load(f)
        break
    except (OSError, ValueError):
        pass


def pal(k, d):
    v = PAL.get(k)
    return v if isinstance(v, str) and len(v) == 7 and v.startswith("#") else d


C_FG = "#1d1d1f," + pal("fg", "#d5b9bc")
C_DIM = "#6e6e73," + pal("fg_dim", "#a28d90")
C_MUTED = "#8e8e93," + pal("muted", "#736567")
C_RED = "#c4232f," + pal("red", "#e83648")
C_ORANGE = "#b25a14," + pal("orange", "#c69980")
C_GREEN = "#1f7a3a," + pal("green", "#8fbf7f")
MENLO = {"font": "Menlo", "size": 11, "trim": "false"}


def line(text, **kw):
    text = str(text).replace("|", "¦").replace("\n", " ")
    print(text + (" | " + " ".join("%s=%s" % kv for kv in kw.items()) if kw else ""))


def act(label, action, arg="", pre="", **kw):
    label = pre + label
    p = {"bash": SELF, "param1": "--do", "param2": action, "terminal": "false", "refresh": "true"}
    if arg:
        p["param3"] = arg
    line(label, **dict(p, **kw))


# ---- state -------------------------------------------------------------------------------------------------------
def gib(n):
    return "%g GiB" % round(n / 2**30, 1)


def read_state():
    """-> (status, info). status: missing | running | stopped | unknown."""
    if not COLIMA:
        return "missing", {}
    rc, out = run([COLIMA, "list", "--json"], 8)
    if rc != 0:
        return "unknown", {}
    for l in out.splitlines():
        try:
            d = json.loads(l)
        except ValueError:
            continue
        if d.get("name") == PROFILE:
            return ("running" if str(d.get("status")).lower() == "running" else "stopped"), d
    return "stopped", {}


def read_mark():
    try:
        with open(MARK) as f:
            m = json.load(f)
        if time.time() - m["t"] < MARK_TTL:
            return m["action"]
    except (OSError, ValueError, KeyError):
        pass
    return None


def clear_mark():
    try:
        os.remove(MARK)
    except OSError:
        pass


def containers():
    if not DOCKER:
        return None
    rc, out = run([DOCKER, "ps", "--format", "{{.Names}}\t{{.Status}}"], 4)
    if rc != 0:
        return None
    return [(l.split("\t", 1) + [""])[:2] for l in out.splitlines() if l.strip()]


status, info = read_state()
mark = read_mark()
# marker ends when the goal state is reached (restart: only after 10 s, so the brief still-running phase does not clear it)
if mark == "start" and status == "running" or mark == "restart" and status == "running" and time.time() - os.path.getmtime(MARK) > 10:
    clear_mark(); mark = None
elif mark == "stop" and status == "stopped":
    clear_mark(); mark = None
busy = {"start": "Starting…", "stop": "Stopping…", "restart": "Restarting…"}.get(mark)

if status == "missing":
    line("", sfimage="shippingbox", color=C_MUTED)
    print("---")
    line("Colima is not installed", sfimage="exclamationmark.triangle", color=C_ORANGE)
    line("brew install colima docker", **MENLO, color=C_DIM)
    sys.exit(0)

col = C_DIM if busy else C_FG if status == "running" else C_MUTED if status == "stopped" else C_RED
cs = containers() if status == "running" and not busy else None
n = len(cs) if cs else 0
line(str(n) if cs else "", sfimage="shippingbox.fill" if status == "running" and not busy else "shippingbox", color=col)
print("---")

if busy:
    line(busy, sfimage="hourglass", color=C_ORANGE, font="Helvetica-Bold", size=12)
elif status == "running":
    line("Colima running", sfimage="checkmark.circle.fill", color=C_GREEN, font="Helvetica-Bold", size=12)
elif status == "stopped":
    line("Colima stopped", sfimage="stop.circle", color=C_DIM, font="Helvetica-Bold", size=12)
else:
    line("Colima status unavailable", sfimage="exclamationmark.octagon", color=C_RED, size=12)

if info:
    line("profile  %s" % PROFILE, **MENLO, color=C_FG)
    line("cpu      %s" % info.get("cpus", "?"), **MENLO, color=C_FG)
    if isinstance(info.get("memory"), int):
        line("memory   %s" % gib(info["memory"]), **MENLO, color=C_FG)
    if isinstance(info.get("disk"), int):
        line("disk     %s" % gib(info["disk"]), **MENLO, color=C_FG)
    line("runtime  %s · %s" % (info.get("runtime", "?"), info.get("arch", "?")), **MENLO, color=C_FG)
    if info.get("address"):
        line("address  %s" % info["address"], **MENLO, color=C_FG)

print("---")
if status == "running" and not busy:
    if not DOCKER:
        line("docker CLI not found", sfimage="exclamationmark.triangle", color=C_ORANGE)
    elif cs is None:
        line("Containers unavailable", sfimage="exclamationmark.triangle", color=C_ORANGE)
    else:
        line("%d running container%s" % (n, "" if n == 1 else "s"), sfimage="shippingbox", color=C_FG)
        for name, st in cs:
            line("--" + name, sfimage="cube", color=C_FG)
            line("----" + st, **MENLO, color=C_DIM)
            act("Stop", "container-stop", name, pre="----", sfimage="stop")
            act("Restart", "container-restart", name, pre="----", sfimage="arrow.clockwise")
    print("---")
if not busy:
    if status != "running":
        act("Start", "start", sfimage="play.fill")
    else:
        act("Stop", "stop", sfimage="stop.fill")
        act("Restart", "restart", sfimage="arrow.clockwise")
line("Refresh", refresh="true", sfimage="arrow.triangle.2.circlepath")
