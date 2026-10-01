#!/usr/bin/env python3
"""Checks that cloud content can't exhaust the plugin process.

A hostile rclone stand-in floods listings and error output or hangs, and
local fixtures hold a huge folder and a huge mount log. Every probe runs in
its own process so its peak memory can be asserted.

    tests/test_limits.py              test this checkout
    tests/test_limits.py <checkout>   test another checkout's lib/
"""

import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else HERE
MAX_PEAK_MB = 150  # the plugin itself needs ~25 MB; unbounded reads reach GBs

FAKE_RCLONE = r'''#!/usr/bin/env python3
import os, sys, time
mode = os.environ.get("FAKE_MODE", "")
if sys.argv[1:2] == ["about"]:
    print('{"total": 1000, "used": 10, "free": 990}'); sys.exit(0)
if mode == "hang":
    time.sleep(60); sys.exit(0)
if mode == "flood-stderr":
    try:
        while True: sys.stderr.buffer.write(b"ERROR : " + b"x" * 1000 + b"\n")
    except BrokenPipeError: sys.exit(1)
entry = b'{"Path":"f%d","Name":"f%d","Size":1,"MimeType":"text/plain","ModTime":"2026-01-01T00:00:00Z","IsDir":false},\n'
limit = int(os.environ.get("FAKE_ENTRIES", "0"))  # 0 = endless
try:
    sys.stdout.buffer.write(b"[\n"); i = 0
    while limit == 0 or i < limit:
        sys.stdout.buffer.write(entry % (i, i)); i += 1
    sys.stdout.buffer.write(b"]\n")
except BrokenPipeError:
    pass
'''

PROBE = r'''
import os, sys, time, json, pathlib, shutil
sys.path.insert(0, os.path.join(sys.argv[1], "lib"))
import odrive.manager as mm
from odrive.manager import DriveManager
work, what = sys.argv[2], sys.argv[3]
m = DriveManager()
m.rclone_bin = os.path.join(work, "rclone")
m._ensure_onedrive_drive = lambda name: None
big = os.path.join(work, "big")
mounted = what in ("mounted-list", "recent")
if what != "rotate-live":
    m.is_remote_mounted = lambda name: (mounted, big if mounted else "/nonexistent")
t = time.time()
if what == "list":
    r = {"entries": len(m.list_dir("Hostile"))}
elif what == "test":
    ok, msg = m.test_remote("Hostile", timeout_sec=5)
    r = {"ok": ok, "msg_len": len(msg)}
elif what == "mounted-list":
    r = {"entries": len(m.list_dir("Hostile"))}
elif what == "recent":
    r = {"files": len(m.scan_recent_files("Hostile", limit=5))}
elif what == "log":
    log = m.get_log("Hostile")
    r = {"lines": len(log.splitlines()), "esc": chr(27) in log}
elif what == "mount-args":
    # A recording stand-in: the mount command must ask rclone to rotate its log
    mm.get_mount_path_for_remote = lambda n: pathlib.Path(work, "mnt", n)
    m.rclone_bin = os.path.join(work, "rclone-rec")
    m.is_remote_mounted = lambda name: (False, os.path.join(work, "mnt", name))
    m.mount("Hostile")
    r = {"args": open(os.path.join(work, "rclone-rec.args")).read().split("\0")}
elif what == "rotate-live":
    # ODrive's real mount() on a throwaway local remote, with the cap lowered to 1 MiB
    mm.MAX_LOG_MB = 1
    mnt = pathlib.Path(work, "mnt", "Hostile")
    mm.get_mount_path_for_remote = lambda n: mnt
    m.rclone_bin = shutil.which("rclone")
    ok, msg = m.mount("Hostile")
    if not ok:
        r = {"skip": msg[:200]}
    else:
        d = pathlib.Path(os.environ["XDG_STATE_HOME"], "odrive")
        try:
            writes, deadline = 0, time.time() + 60
            # Bounded in time, so the probe always gets to unmount below
            while time.time() < deadline and len(list(d.glob("mount_Hostile-*.log"))) < 1:
                for _ in range(500):
                    (mnt / f"f{writes}.txt").write_text("x")
                    writes += 1
                time.sleep(0.5)
            for _ in range(500):  # keep logging past the first rotation
                (mnt / f"g{writes}.txt").write_text("x")
                writes += 1
            time.sleep(2)
            r = {"writes": writes, "logs": {n.name: [n.stat().st_size, oct(n.stat().st_mode & 0o777)]
                                            for n in sorted(d.glob("mount_Hostile*"))}}
        finally:
            m.unmount("Hostile")
r["seconds"] = round(time.time() - t, 2)
# VmHWM (peak resident set) restarts with each exec, unlike ru_maxrss, which
# carries the parent's peak over and would report the test harness instead
with open("/proc/self/status") as fh:
    hwm_kb = next(int(l.split()[1]) for l in fh if l.startswith("VmHWM:"))
r["peak_mb"] = hwm_kb // 1024
print(json.dumps(r))
'''

passed = failed = 0


def check(name, cond, detail):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {name}  ({detail})")
    else:
        failed += 1
        print(f"  FAIL {name}  ({detail})")


def probe(work, what, **env):
    e = dict(os.environ, XDG_STATE_HOME=os.path.join(work, "state"),
             XDG_CONFIG_HOME=os.path.join(work, "cfg"), **env)
    try:
        out = subprocess.run([sys.executable, os.path.join(work, "probe.py"), REPO, work, what],
                             capture_output=True, text=True, env=e, timeout=150)
    except subprocess.TimeoutExpired:
        return {"error": "probe timed out"}
    if out.returncode != 0:
        return {"error": out.stderr.strip().splitlines()[-1:] or ["?"]}
    import json
    return json.loads(out.stdout)


def main():
    print(f"testing {REPO}/lib")
    with tempfile.TemporaryDirectory() as work:
        with open(os.path.join(work, "rclone"), "w") as f:
            f.write(FAKE_RCLONE)
        os.chmod(os.path.join(work, "rclone"), 0o755)
        with open(os.path.join(work, "probe.py"), "w") as f:
            f.write(PROBE)
        rec = os.path.join(work, "rclone-rec")
        with open(rec, "w") as f:
            f.write("#!/bin/sh\nprintf '%s\\0' \"$@\" > \"$0.args\"\n")
        os.chmod(rec, 0o755)
        os.makedirs(os.path.join(work, "big"))
        for i in range(20000):
            open(os.path.join(work, "big", f"f{i:05d}"), "w").close()
        state = os.path.join(work, "state", "odrive")
        os.makedirs(state)
        with open(os.path.join(state, "mount_Hostile.log"), "wb") as f:
            line = b"2026/09/30 10:00:00 INFO  : " + b"n" * 200 + b": vfs cache\n"
            f.write(line * (50 * 1024 * 1024 // len(line)))
            f.write(b"2026/09/30 10:00:01 ERROR : \x1b]52;c;cHduZWQ=\x07 last line\n")

        print("1. listings over rclone (lsjson)")
        r = probe(work, "list", FAKE_MODE="finite", FAKE_ENTRIES="1500000")
        check("1.5M-entry listing capped", r.get("entries", 1e9) <= 5000 and r.get("peak_mb", 1e9) < MAX_PEAK_MB, r)
        r = probe(work, "list", FAKE_MODE="endless")
        check("endless listing capped", r.get("entries", 1e9) <= 5000 and r.get("peak_mb", 1e9) < MAX_PEAK_MB, r)

        print("2. connection test (lsf)")
        r = probe(work, "test", FAKE_MODE="endless")
        check("endless listing: succeeds quickly", r.get("ok") is True and r.get("seconds", 99) < 3 and r.get("peak_mb", 1e9) < MAX_PEAK_MB, r)
        r = probe(work, "test", FAKE_MODE="finite", FAKE_ENTRIES="1500000")
        check("1.5M-entry listing: bounded", r.get("ok") is True and r.get("peak_mb", 1e9) < MAX_PEAK_MB, r)
        r = probe(work, "test", FAKE_MODE="flood-stderr")
        check("endless error output: bounded, fails", r.get("ok") is False and r.get("msg_len", 1e9) < 20000 and r.get("peak_mb", 1e9) < MAX_PEAK_MB, r)
        r = probe(work, "test", FAKE_MODE="hang")
        check("hang: cut off at the timeout", r.get("ok") is False and r.get("seconds", 99) < 8, r)

        print("3. mounted folders and logs")
        r = probe(work, "mounted-list")
        check("20k-entry mounted folder capped", r.get("entries", 1e9) <= 5000 and r.get("peak_mb", 1e9) < MAX_PEAK_MB, r)
        r = probe(work, "recent")
        check("recent-file scan bounded", "files" in r and r.get("seconds", 99) < 5 and r.get("peak_mb", 1e9) < MAX_PEAK_MB, r)
        r = probe(work, "log")
        check("50 MB log: tail only, escapes neutralised", r.get("lines", 1e9) <= 50 and r.get("esc") is False and r.get("peak_mb", 1e9) < MAX_PEAK_MB, r)

        print("4. mount logs rotate while the drive stays mounted")
        r = probe(work, "mount-args")
        args = r.get("args", [])
        check("mount asks rclone to rotate its log",
              any(a.startswith("--log-file-max-size=") and a.endswith("M") for a in args)
              and "--log-file-max-backups=1" in args, [a for a in args if a.startswith("--log")])
        live = shutil.which("rclone") and (shutil.which("fusermount3") or shutil.which("fusermount"))
        if not live:
            print("  skip live rotation (needs rclone and FUSE)")
        else:
            src = os.path.join(work, "src")
            os.makedirs(src)
            conf = os.path.join(work, "rclone.conf")
            with open(conf, "w") as f:
                f.write(f"[Hostile]\ntype = alias\nremote = {src}\n")
            # Fresh state, and rclone's VFS cache kept inside the temp dir
            shutil.rmtree(os.path.join(work, "state"), ignore_errors=True)
            mnt = os.path.join(work, "mnt", "Hostile")
            try:
                r = probe(work, "rotate-live", RCLONE_CONFIG=conf, XDG_CACHE_HOME=os.path.join(work, "cache"))
            finally:
                # Never leave a test mount behind, even if the probe was killed
                if os.path.ismount(mnt):
                    fusermount = shutil.which("fusermount3") or shutil.which("fusermount")
                    subprocess.run([fusermount, "-u", "-z", mnt], capture_output=True)
            if "skip" in r:
                print(f"  skip live rotation (mount failed: {r['skip']})")
            else:
                logs = r.get("logs", {})
                active = logs.get("mount_Hostile.log", [1 << 40, ""])
                backups = {k: v for k, v in logs.items() if k.startswith("mount_Hostile-")}
                check("live: active log stays under the cap, one backup, all private",
                      active[0] <= 1024 * 1024 and len(backups) == 1
                      and all(v[1] == "0o600" for v in logs.values()), r)

    print(f"\npassed {passed}, failed {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
