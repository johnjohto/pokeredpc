"""gh #3 (ADR-014): the two-instance link test. Launches a --host and a --join instance
headlessly over localhost and asserts both logs, across four scenarios:

  1. clean     — both sides log "session established", the ping/pong round-trip completes
  2. tamper-part    — the joiner's 'moves' hash is corrupted: BOTH logs refuse naming 'moves'
  3. tamper-version — the host's version is corrupted: BOTH logs refuse naming the version
  4. tamper-engine  — the joiner's engine build is corrupted: BOTH logs refuse naming it (gh #12)
  5. nobody    — a join with no host times out cleanly within its --linktimeout (no hang)

Judged by log content, not exit codes (headless Godot may exit 0xC0000005 on shutdown).
Exits 0 only if every scenario passes. Run:  python tools/linktest.py
"""
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
BASE_PORT = 17301


def godot_binary():
    """The Godot 4.7 binary for this OS (tools/godot/<per-OS name>), overridable via the
    POKEREDPC_GODOT env var — a Linux/macOS peer may keep it elsewhere (gh #12)."""
    env = os.environ.get("POKEREDPC_GODOT")
    if env:
        return Path(env)
    name = {"win32": "Godot_v4.7-stable_win64.exe",
            "darwin": "Godot.app/Contents/MacOS/Godot",
            }.get(sys.platform, "Godot_v4.7-stable_linux.x86_64")
    return ROOT / "tools" / "godot" / name


def godot_user_dir():
    """Godot's per-user data dir for this OS — where user:// (saves, trade journals) lands."""
    if sys.platform == "win32":
        return Path.home() / "AppData/Roaming/Godot/app_userdata/pokeredpc"
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/Godot/app_userdata/pokeredpc"
    base = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    return base / "godot/app_userdata/pokeredpc"


GODOT = godot_binary()


def clear_slot(slot):
    """gh #36: scenario slots must be self-isolating. A leftover save — or worse, an ACKED
    trade journal from a raced earlier run — changes the next launch's behavior (an acked
    journal rolls the trade FORWARD at load), so one bad run poisons every later one.
    Delete the slot's save + journal so each scenario starts from nothing."""
    for name in (f"pokeredpc_save_{slot}.json",
                 f"pokeredpc_save_{slot}_trade_journal.json"):
        try:
            (godot_user_dir() / name).unlink()
        except OSError:
            pass


def leftover_journals():
    """Names of any trade journals left in the user dir — a FAIL diagnosis hint (gh #36)."""
    try:
        return sorted(p.name for p in godot_user_dir().glob("*_trade_journal.json"))
    except OSError:
        return []


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

    # gh #12: two peers on the same game version but different Godot builds must refuse —
    # lockstep only holds when both machines run the identical engine release.
    hout, jout = run_pair("tamper-engine", [], ["--tamper=engine"], BASE_PORT + 8)
    ok &= check("tamper-engine: host refuses naming the engine build",
                "REFUSED" in hout and "engine build differs" in hout)
    ok &= check("tamper-engine: join sees an engine-build refusal",
                "REFUSED" in jout and "engine build differs" in jout)
    ok &= check("tamper-engine: no session", "session established" not in hout
                and "session established" not in jout)

    # gh #5: the full in-game Cable Club flow — attendant -> HOST/JOIN -> save beat ->
    # LinkMenu (the joiner never picks; the host's club_go closes its menu) -> both players
    # standing on the Trade Center floor at their special-warp spots.
    club_port = BASE_PORT + 4
    h = launch(["--clubtest", "--clubhost", f"--port={club_port}"])
    time.sleep(6)
    j = launch(["--clubtest", "--clubjoin", f"--port={club_port}"])
    hout = collect(h, 120)
    jout = collect(j, 60)
    ok &= check("club: host on the Trade Center floor",
                "[club] host: map=TradeCenter cell=(3, 4) link=linked" in hout)
    ok &= check("club: joiner beside them",
                "[club] join: map=TradeCenter cell=(6, 4) link=linked" in jout)
    ok &= check("club: joiner remembered the address", "addr='127.0.0.1'" in jout)
    ok &= check("club: both clean", "modal_clear=true" in hout and "modal_clear=true" in jout)

    # gh #5: an in-club handshake refusal — the tampered joiner is turned away at the desk
    # on BOTH sides (the reason surfaces in-dialogue), and both flows end cleanly outside.
    ref_port = BASE_PORT + 5
    h = launch(["--clubtest", "--clubhost", f"--port={ref_port}"])
    time.sleep(6)
    j = launch(["--clubtest", "--clubjoin", f"--port={ref_port}", "--tamper=moves"])
    hout = collect(h, 120)
    jout = collect(j, 60)
    ok &= check("club-refusal: host refuses naming 'moves'",
                "[link] REFUSED" in hout and "'moves'" in hout)
    ok &= check("club-refusal: joiner refused too",
                "[link] REFUSED" in jout and "'moves'" in jout)
    ok &= check("club-refusal: both back at the attendant cleanly",
                "map=CeruleanPokecenter" in hout and "map=CeruleanPokecenter" in jout
                and hout.count("modal_clear=true") == 1 and jout.count("modal_clear=true") == 1)

    # gh #6: the round-trip trade — kadabra <-> machoke across the table, both arriving
    # mons trade-evolving (ALAKAZAM / MACHAMP), nickname/OT/trainer ID intact, the commit
    # two-phase, and BOTH save files holding the traded party (read directly below).
    tr_port = BASE_PORT + 6
    clear_slot("tradehost")
    clear_slot("tradejoin")
    h = launch(["--clubtest", "--clubhost", "--trade", f"--port={tr_port}",
                "--saveslot=tradehost"])
    time.sleep(6)
    j = launch(["--clubtest", "--clubjoin", "--trade", f"--port={tr_port}",
                "--saveslot=tradejoin"])
    hout = collect(h, 180)
    jout = collect(j, 120)
    trade_ok = ("result=done" in hout and "MACHAMP(JOINB/222)" in hout
                and "result=done" in jout and "ALAKAZAM(HOSTA/111)" in jout)
    if not trade_ok:                     # dump the flow trace for diagnosis
        for tag, out in (("host", hout), ("join", jout)):
            for line in out.splitlines():
                if any(k in line for k in ("[tc]", "[trade]", "[club]", "[link]")):
                    print(f"[linktest]   {tag}| {line.strip()}")
    ok &= check("trade: host done, MACHOKE arrived as MACHAMP (outsider OT kept)",
                "result=done" in hout and "MACHAMP(JOINB/222)" in hout)
    ok &= check("trade: joiner done, KADABRA arrived as ALAKAZAM (outsider OT kept)",
                "result=done" in jout and "ALAKAZAM(HOSTA/111)" in jout)
    ok &= check("trade: journals cleared", "journal=false" in hout and "journal=false" in jout)
    import json as _json
    udir = godot_user_dir()
    try:
        hsave = _json.loads((udir / "pokeredpc_save_tradehost.json").read_text(encoding="utf-8"))
        jsave = _json.loads((udir / "pokeredpc_save_tradejoin.json").read_text(encoding="utf-8"))
        hsp = [m["species"] for m in hsave["party"]]
        jsp = [m["species"] for m in jsave["party"]]
        ok &= check("trade: host SAVE holds machamp, kadabra gone",
                    "machamp" in hsp and "kadabra" not in hsp, str(hsp))
        ok &= check("trade: join SAVE holds alakazam, machoke gone",
                    "alakazam" in jsp and "machoke" not in jsp, str(jsp))
        ok &= check("trade: saves point OUTSIDE the club (no reload-strand)",
                    hsave["map"] == "CeruleanPokecenter" and jsave["map"] == "CeruleanPokecenter",
                    f"{hsave['map']} / {jsave['map']}")
    except OSError as e:
        ok &= check("trade: save files readable", False, str(e))

    # gh #7: the Colosseum lockstep battle — two real instances fight over the wire (moves,
    # faints, replacements, the win), and their [battledet] event streams must be
    # BYTE-IDENTICAL: equality of streams is ADR-014's definition of "in sync".
    col_port = BASE_PORT + 7
    clear_slot("colhost")
    clear_slot("coljoin")
    h = launch(["--clubtest", "--clubhost", "--battle", f"--port={col_port}",
                "--saveslot=colhost"])
    time.sleep(6)
    j = launch(["--clubtest", "--clubjoin", "--battle", f"--port={col_port}",
                "--saveslot=coljoin"])
    hout = collect(h, 300)
    jout = collect(j, 240)
    hcol = next((l for l in hout.splitlines() if "[col] host:" in l), "")
    jcol = next((l for l in jout.splitlines() if "[col] join:" in l), "")
    hstream = [l.split("] ", 1)[1] for l in hout.splitlines() if "[battledet]" in l]
    jstream = [l.split("] ", 1)[1] for l in jout.splitlines() if "[battledet]" in l]
    ok &= check("colosseum: battle completed on both sides",
                "winner=" in hcol and "winner=" in jcol)
    ok &= check("colosseum: peers agree on the winner",
                hcol.split("end=")[-1].split(" ")[0] == jcol.split("end=")[-1].split(" ")[0]
                if hcol and jcol else False)
    ok &= check("colosseum: LOCKSTEP — event streams byte-identical",
                len(hstream) > 3 and hstream == jstream,
                f"{len(hstream)}/{len(jstream)} events")
    ok &= check("colosseum: stakeless — both parties restored",
                "party_restored=true" in hcol and "party_restored=true" in jcol)

    lone = launch(["--join", "127.0.0.1", f"--port={BASE_PORT + 3}", "--linktimeout=5"])
    t0 = time.time()
    lout = collect(lone, 60)
    ok &= check("nobody: clean timeout", "[link] timeout" in lout and "KILLED" not in lout,
                f"{time.time() - t0:.0f}s")

    print(f"[linktest] {'ALL GREEN' if ok else 'FAIL'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
