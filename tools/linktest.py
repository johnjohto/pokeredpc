"""gh #3 (ADR-014): the two-instance link test. Launches a --host and a --join instance
headlessly over localhost and asserts both logs, across four scenarios:

  1. clean     — both sides log "session established", the ping/pong round-trip completes
  2. tamper-part    — the joiner's 'moves' hash is corrupted: BOTH logs refuse naming 'moves'
  3. tamper-version — the host's version is corrupted: BOTH logs refuse naming the version
  4. nobody    — a join with no host times out cleanly within its --linktimeout (no hang)

Judged by log content, not exit codes (headless Godot may exit 0xC0000005 on shutdown).
Exits 0 only if every scenario passes. Run:  python tools/linktest.py
"""
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = ROOT / "tools" / "godot" / "Godot_v4.7-stable_win64.exe"
GAME = ROOT / "game"
BASE_PORT = 17301


def launch(user_args):
    """Start a headless instance with its stdout drained by a reader thread. The drain is
    load-bearing: an unread stdout PIPE fills, the game blocks mid-print, and a blocked
    host never services ENet — the pair then 'mysteriously' times out."""
    proc = subprocess.Popen(
        [str(GODOT), "--path", str(GAME), "--headless", "--"] + user_args,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        encoding="utf-8", errors="replace")
    lines = []

    def drain():
        for line in proc.stdout:
            lines.append(line)
    t = threading.Thread(target=drain, daemon=True)
    t.start()
    proc._lt_lines = lines
    proc._lt_thread = t
    return proc


def collect(proc, timeout):
    try:
        proc.wait(timeout=timeout)
        killed = ""
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        killed = "\n[linktest] KILLED: instance exceeded the harness timeout"
    proc._lt_thread.join(timeout=5)
    return "".join(proc._lt_lines) + killed


def run_pair(name, host_extra, join_extra, port):
    host = launch(["--host", f"--port={port}", "--linktimeout=25"] + host_extra)
    time.sleep(6)                      # let the host import assets and bind the port
    join = launch(["--join", "127.0.0.1", f"--port={port}", "--linktimeout=25"] + join_extra)
    hout = collect(host, 90)
    jout = collect(join, 30)
    return hout, jout


def check(name, ok, detail=""):
    print(f"[linktest] {name}: {'PASS' if ok else 'FAIL'}{(' — ' + detail) if detail else ''}")
    return ok


def main():
    ok = True

    hout, jout = run_pair("clean", [], [], BASE_PORT)
    ok &= check("clean: host established", "session established (host)" in hout)
    ok &= check("clean: join established", "session established (join)" in jout)
    ok &= check("clean: round-trip", "echo round-trip ok" in hout and "ping received" in jout)

    hout, jout = run_pair("tamper-part", [], ["--tamper=moves"], BASE_PORT + 1)
    ok &= check("tamper-part: host refuses naming 'moves'",
                "REFUSED" in hout and "'moves'" in hout)
    ok &= check("tamper-part: join sees a refusal naming 'moves'",
                "REFUSED" in jout and "'moves'" in jout)
    ok &= check("tamper-part: no session", "session established" not in hout
                and "session established" not in jout)

    hout, jout = run_pair("tamper-version", ["--tamper=version"], [], BASE_PORT + 2)
    ok &= check("tamper-version: host sees a version refusal",
                "REFUSED" in hout and "version differs" in hout)
    ok &= check("tamper-version: join refuses naming the version",
                "REFUSED" in jout and "version differs" in jout)
    ok &= check("tamper-version: no session", "session established" not in hout
                and "session established" not in jout)

    lone = launch(["--join", "127.0.0.1", f"--port={BASE_PORT + 3}", "--linktimeout=5"])
    t0 = time.time()
    lout = collect(lone, 60)
    ok &= check("nobody: clean timeout", "[link] timeout" in lout and "KILLED" not in lout,
                f"{time.time() - t0:.0f}s")

    print(f"[linktest] {'ALL GREEN' if ok else 'FAIL'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
