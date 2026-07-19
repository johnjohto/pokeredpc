"""gh #9 (ADR-014): drop-injection + the dupe easter egg. Severs the link at scripted
points (--killat: a flushed ENet send, then the process dies with no goodbye — a cable
pull) and asserts the disconnect story:

  1. asym-dupe    — one-sided easter-egg opt-in refuses the whole session, on both logs
  2. battle-drop  — a mid-battle pull ends the survivor's session stakeless (winner=void)
  3. trade @pick / @confirm / @commit — both saves stay fully UNTRADED (rollback matrix)
  4. trade @ack   — the survivor completes; the killed side's relaunch ROLLS FORWARD from
                    its acked journal (silent trade evolution included): both saves TRADED
  5. dupe @ack    — with BOTH peers opted in, the same pull reproduces the cartridge's
                    duplication on purpose: the survivor holds the copy, the puller's
                    relaunch keeps the original — the mon lives in both saves

Judged on logs + the actual save files. Run:  python tools/linkdrop.py
"""
import json
import sys
import time
from pathlib import Path

from linktest import launch, collect

BASE_PORT = 17701
UDIR = Path.home() / "AppData/Roaming/Godot/app_userdata/pokeredpc"


def check(name, ok, detail=""):
    print(f"[drop] {name}: {'PASS' if ok else 'FAIL'}{(' — ' + detail) if detail else ''}")
    return ok


def party_of(slot):
    try:
        data = json.loads((UDIR / f"pokeredpc_save_{slot}.json").read_text(encoding="utf-8"))
        return [m["species"] for m in data["party"]]
    except OSError:
        return ["<missing>"]


def trade_pair(port, hslot, jslot, join_extra, host_extra=()):
    h = launch(["--clubtest", "--clubhost", "--trade", f"--port={port}",
                f"--saveslot={hslot}", *host_extra])
    time.sleep(6)
    j = launch(["--clubtest", "--clubjoin", "--trade", f"--port={port}",
                f"--saveslot={jslot}", *join_extra])
    return collect(h, 240), collect(j, 180)


def recover(slot):
    r = launch(["--recovertest", f"--saveslot={slot}"])
    out = collect(r, 90)
    return " | ".join(l.strip() for l in out.splitlines()
                      if "[recover]" in l or "[trade]" in l)


def main():
    ok = True

    # 1 — asymmetric opt-in refuses the session (the egg can never fire one-sided)
    h = launch(["--clubtest", "--clubhost", f"--port={BASE_PORT}", "--dupe"])
    time.sleep(6)
    j = launch(["--clubtest", "--clubjoin", f"--port={BASE_PORT}"])
    hout = collect(h, 120)
    jout = collect(j, 90)
    ok &= check("asym-dupe: session refused on both sides",
                "REFUSED" in hout and "dupe" in hout and "REFUSED" in jout and "dupe" in jout)
    ok &= check("asym-dupe: no session", "session established" not in hout)

    # 2 — a mid-battle cable pull is stakeless for the survivor
    h = launch(["--colsoak", "--clubhost", f"--port={BASE_PORT + 1}",
                "--colparty=0", "--colseed=31000", "--killat=act2"])
    time.sleep(4)
    j = launch(["--colsoak", "--clubjoin", f"--port={BASE_PORT + 1}",
                "--colparty=1", "--colseed=31000"])
    hout = collect(h, 240)
    jout = collect(j, 300)
    ok &= check("battle-drop: host pulled the cable", "[kill]" in hout and "act2" in hout)
    ok &= check("battle-drop: survivor ends stakeless (winner=void)",
                "end=winner=void" in jout)

    # 3 — rollback matrix: pick / confirm / commit all leave both saves untraded
    for i, point in enumerate(["pick", "confirm", "commit"]):
        hs, js = f"drh{point}", f"drj{point}"
        hout, jout = trade_pair(BASE_PORT + 2 + i, hs, js, [f"--killat={point}"])
        rec = recover(js)
        hp, jp = party_of(hs), party_of(js)
        ok &= check(f"trade@{point}: killed at the point", "[kill]" in jout)
        ok &= check(f"trade@{point}: survivor walked back to the Center",
                    "after-drop map=CeruleanPokecenter" in hout)
        ok &= check(f"trade@{point}: both saves untraded",
                    "machamp" not in hp and "kadabra" in hp
                    and "alakazam" not in jp and "machoke" in jp, f"{hp} / {jp}")
        ok &= check(f"trade@{point}: recovery clean", "journal=false" in rec, rec)

    # 4 — the ack window: survivor completes, the puller's relaunch rolls FORWARD
    hout, jout = trade_pair(BASE_PORT + 5, "drhack", "drjack", ["--killat=ack"])
    rec = recover("drjack")
    hp, jp = party_of("drhack"), party_of("drjack")
    ok &= check("trade@ack: survivor completed (MACHAMP in its save)",
                "result=done" in hout and "machamp" in hp, str(hp))
    ok &= check("trade@ack: puller rolled forward (ALAKAZAM in its save, machoke gone)",
                "rolled forward" in rec and "alakazam" in jp and "machoke" not in jp,
                str(jp))

    # 5 — the dupe easter egg: both opted in, the same pull duplicates on purpose
    hout, jout = trade_pair(BASE_PORT + 6, "drhdupe", "drjdupe",
                            ["--killat=ack", "--dupe"], host_extra=("--dupe",))
    rec = recover("drjdupe")
    hp, jp = party_of("drhdupe"), party_of("drjdupe")
    ok &= check("dupe@ack: survivor holds the copy (MACHAMP)",
                "result=done" in hout and "machamp" in hp, str(hp))
    ok &= check("dupe@ack: the puller KEPT the original (MACHOKE) — the classic dupe",
                "dupe easter egg" in rec and "machoke" in jp, str(jp))

    print(f"[drop] {'ALL GREEN' if ok else 'FAIL'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
