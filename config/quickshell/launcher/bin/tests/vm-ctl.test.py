"""Tests for vm-ctl create-bg / status / cancel / shot with a stub quickget and a fake qemu process (no network, no VMs).
Run: python3 -I launcher/bin/tests/vm-ctl.test.py"""
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

VMCTL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vm-ctl")

STUB = r"""#!/bin/bash
os=$1; rel=$2; name="$os-$rel"
echo "Downloading Test OS $rel "
mkdir -p "$name"
[ -n "$STUB_FAIL" ] && { echo "ERROR! Failed to download https://example.invalid/x.iso with curl."; exit 1; }
for i in $(seq 0 10); do
  printf '\r%-60s %5s%%' "####" "$((i*10)).0" >&2
  head -c 100000 /dev/zero >> "$name/x.iso"
  sleep ${STUB_SLEEP:-0.1}
done
echo >&2
printf 'guest_os="linux"\ndisk_img="%s/disk.qcow2"\n' "$name" > "$name.conf"
"""


class T(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="vmt")
        self.root = os.path.join(self.tmp, "vms")
        os.mkdir(self.root)
        self.state = os.path.join(self.tmp, "state")
        stub = os.path.join(self.tmp, "quickget")
        with open(stub, "w") as f:
            f.write(STUB)
        os.chmod(stub, 0o755)
        self.env = dict(os.environ, QS_QUICKGET=stub, QS_VM_STATE=self.state, PATH=self.tmp + ":" + os.environ["PATH"])
        with open(os.path.join(self.tmp, "notify-send"), "w") as f:
            f.write("#!/bin/sh\necho \"$@\" >> %s/notify.log\n" % self.tmp)
        os.chmod(os.path.join(self.tmp, "notify-send"), 0o755)
        self.procs = []
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def tearDown(self):
        for p in self.procs:
            if p.poll() is None:
                p.kill()
                p.wait()

    def ctl(self, *a, **kw):
        return subprocess.run([sys.executable, "-I", VMCTL] + list(a), env=self.env, capture_output=True, text=True, **kw)

    def status(self):
        return json.loads(self.ctl("status", self.root).stdout)

    def test_job_done(self):
        p = self.ctl("create-bg", self.root, "foo", "1")
        self.assertEqual(p.returncode, 0, p.stderr)
        jobs = self.status()["jobs"]
        self.assertEqual([(j["label"], j["state"], j["name"]) for j in jobs], [("foo 1", "done", "foo-1")])
        self.assertTrue(os.path.exists(os.path.join(self.root, "foo-1.conf")))

    def test_job_progress_and_cancel(self):
        self.env["STUB_SLEEP"] = "0.4"
        p = subprocess.Popen([sys.executable, "-I", VMCTL, "create-bg", self.root, "foo", "2"], env=self.env)
        self.procs.append(p)
        job = None
        for _ in range(40):
            time.sleep(0.2)
            js = [j for j in self.status()["jobs"] if j["state"] == "running" and j["pct"] >= 20]
            if js:
                job = js[0]
                break
        self.assertIsNotNone(job, "no progress seen")
        self.assertEqual(job["phase"], "Downloading")
        self.ctl("cancel", job["id"])
        self.assertEqual(p.wait(timeout=10), 130)
        self.assertEqual(self.status()["jobs"][0]["state"], "cancelled")
        out = subprocess.run(["pgrep", "-f", self.tmp + "/quickget"], capture_output=True, text=True).stdout.strip()
        self.assertEqual(out, "", "quickget left running")

    def test_duplicate_refused(self):
        self.env["STUB_SLEEP"] = "0.3"
        p = subprocess.Popen([sys.executable, "-I", VMCTL, "create-bg", self.root, "foo", "5"], env=self.env)
        self.procs.append(p)
        time.sleep(1)
        q = self.ctl("create-bg", self.root, "foo", "5")
        self.assertEqual(q.returncode, 3)
        self.assertEqual(len([j for j in self.status()["jobs"] if j["label"] == "foo 5"]), 1)
        self.assertEqual(p.wait(timeout=20), 0)

    def test_pct_never_goes_backwards(self):
        self.env["STUB_SLEEP"] = "0.3"
        p = subprocess.Popen([sys.executable, "-I", VMCTL, "create-bg", self.root, "foo", "6"], env=self.env)
        self.procs.append(p)
        seen = []
        while p.poll() is None:
            js = self.status()["jobs"]
            if js:
                seen.append(js[0]["pct"])
            time.sleep(0.15)
        self.assertEqual(seen, sorted(seen))

    def test_job_failed(self):
        self.env["STUB_FAIL"] = "1"
        p = self.ctl("create-bg", self.root, "foo", "3")
        self.assertEqual(p.returncode, 1)
        j = self.status()["jobs"][0]
        self.assertEqual(j["state"], "failed")
        self.assertIn("Failed to download", j["error"])
        with open(os.path.join(self.tmp, "notify.log")) as f:
            self.assertIn("quickget failed", f.read())

    def test_progress_ignores_running_vm_disk(self):
        # an existing VM keeps writing its (bigger) disk image while the download runs: bytes must be the download's
        self.env["STUB_SLEEP"] = "0.3"
        os.mkdir(os.path.join(self.root, "vm1"))
        with open(os.path.join(self.root, "vm1.conf"), "w") as f:
            f.write('guest_os="linux"\ndisk_img="vm1/disk.qcow2"\n')
        disk = os.path.join(self.root, "vm1", "disk.qcow2")
        with open(disk, "wb") as f:
            f.truncate(50 * 1000 * 1000)
        p = subprocess.Popen([sys.executable, "-I", VMCTL, "create-bg", self.root, "foo", "7"], env=self.env)
        self.procs.append(p)
        seen = []
        while p.poll() is None:
            os.utime(disk)                                 # the VM writes
            js = [j for j in self.status()["jobs"] if j["state"] == "running"]
            if js:
                seen.append(js[0]["bytes"])
            time.sleep(0.2)
        self.assertTrue(seen and max(seen) > 0, seen)
        self.assertLess(max(seen), 2 * 1000 * 1000, seen)

    def test_status_keeps_frame_being_written(self):
        self.fake_vm()
        shots = os.path.join(self.state, "shots")
        os.makedirs(shots)
        tmp, stale = os.path.join(shots, "vm1.tmp.png"), os.path.join(shots, "old.tmp.png")
        for f in (tmp, stale):
            open(f, "wb").write(b"x")
        old = time.time() - 3600
        os.utime(stale, (old, old))
        self.status()
        self.assertTrue(os.path.exists(tmp))               # a `shot` in progress is not pruned under it
        self.assertFalse(os.path.exists(stale))

    def test_bad_args(self):
        self.assertNotEqual(self.ctl("create-bg", self.root, "foo; rm", "1").returncode, 0)

    def fake_vm(self):
        os.mkdir(os.path.join(self.root, "vm1"))
        with open(os.path.join(self.root, "vm1.conf"), "w") as f:
            f.write('guest_os="linux"\ndisk_img="vm1/disk.qcow2"\n')
        p = subprocess.Popen(["bash", "-c", "exec -a qemu-system-fake sleep 60", "-m", "256", "-smp", "cores=2,threads=1"])
        self.procs.append(p)
        with open(os.path.join(self.root, "vm1", "vm1.pid"), "w") as f:
            f.write("%d\n" % p.pid)
        return p

    def test_status_running_vm(self):
        self.assertEqual(self.status()["vms"], [])
        p = self.fake_vm()
        time.sleep(0.2)
        vms = self.status()["vms"]
        self.assertEqual(len(vms), 1)
        self.assertEqual((vms[0]["name"], vms[0]["pid"]), ("vm1", p.pid))
        self.assertGreater(vms[0]["rss"], 0)
        self.assertFalse(vms[0]["monitor"])
        p.kill()
        p.wait()
        self.assertEqual(self.status()["vms"], [])

    def test_shot_via_monitor_socket(self):
        self.fake_vm()
        sock = os.path.join(self.root, "vm1", "vm1-monitor.socket")
        srv = socket.socket(socket.AF_UNIX)
        srv.bind(sock)
        srv.listen(1)

        def serve():
            c, _ = srv.accept()
            c.sendall(b"QEMU monitor\r\n(qemu) ")
            data = b""
            while not data.endswith(b"\n"):
                data += c.recv(4096)
            path = data.decode().split()[1]
            open(path, "wb").write(b"\x89PNG")
            c.sendall(data.rstrip(b"\n") + b"\x1b[K\r\n(qemu) ")
            c.close()
        t = threading.Thread(target=serve, daemon=True)
        t.start()
        out = os.path.join(self.tmp, "shots", "vm1.png")
        r = self.ctl("shot", self.root, "vm1", out)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(r.stdout.startswith("screendump "))
        self.assertTrue(os.path.exists(out))
        self.assertEqual(self.ctl("shot", self.root, "vm1", "/tmp/a b.png").returncode, 2)

    def monitor_no_surface(self):
        sock = os.path.join(self.root, "vm1", "vm1-monitor.socket")
        srv = socket.socket(socket.AF_UNIX)
        srv.bind(sock)
        srv.listen(5)

        def serve():
            while True:
                try:
                    c, _ = srv.accept()
                except OSError:
                    return
                c.sendall(b"QEMU monitor\r\n(qemu) ")
                data = b""
                while not data.endswith(b"\n"):
                    data += c.recv(4096)
                c.sendall(data.rstrip(b"\n") + b"\x1b[K\r\nError: no surface\r\n(qemu) ")
                c.close()
        threading.Thread(target=serve, daemon=True).start()

    def test_shot_no_surface_keeps_last_frame(self):
        self.fake_vm()
        self.monitor_no_surface()
        out = os.path.join(self.tmp, "shots", "vm1.png")
        os.makedirs(os.path.dirname(out))
        with open(out, "wb") as f:
            f.write(b"OLDFRAME")
        r = self.ctl("shot", self.root, "vm1", out)
        self.assertEqual(r.returncode, 1)
        self.assertIn("no surface", r.stderr)
        self.assertEqual(open(out, "rb").read(), b"OLDFRAME")
        self.assertFalse(os.path.exists(out[:-4] + ".tmp.png"))

    def test_no_window_capture_code(self):
        with open(VMCTL) as f:
            src = f.read()
        self.assertNotIn("grim", src)
        self.assertNotIn("stableId", src)

    def test_status_reports_and_prunes_frames(self):
        p = self.fake_vm()
        shots = os.path.join(self.state, "shots")
        os.makedirs(shots)
        frame, gone = os.path.join(shots, "vm1.png"), os.path.join(shots, "gone.png")
        for f in (frame, gone):
            open(f, "wb").write(b"x")
        v = self.status()["vms"][0]
        self.assertGreater(v["shotAt"], 0)                 # a frame from this boot is reported with its time
        self.assertFalse(os.path.exists(gone))             # a VM that is not running has no stored frame
        old = time.time() - 3600
        os.utime(frame, (old, old))                        # older than this boot: a previous run's frame
        self.assertEqual(self.status()["vms"][0]["shotAt"], 0)
        self.assertFalse(os.path.exists(frame))


if __name__ == "__main__":
    unittest.main()
