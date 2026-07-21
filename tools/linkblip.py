"""gh #13 (ADR-016): blip-injection — the Stage-1 resume gate. Resets the ENet transport at
scripted points (--blipat: the connection dies, BOTH processes stay alive) and asserts the
reconnect + reconcile story:

  1. battle @act2 (host blips) / @act3 (joiner blips) — the session RESUMES, the battle
     completes (never void), and both peers' [battledet] streams stay byte-identical
     (the in-flight action rides the col_resume report).
  2. blip-soak — --blipevery=2 resets the transport every second turn of a whole battle;
     same asserts: every outage resumed, streams identical to the last byte.
  3. trade @pick / @confirm / @commit — the round restarts at the pick screens on resume
     and the trade then COMPLETES: both saves traded (vs. linkdrop's kill matrix, where
     both stay untraded — a blip is an outage, not a death).
  4. trade @ack — the two-generals closure: the phase exchange rolls the behind side
     forward and BOTH saves end traded, journals clear.
  5. dupe @ack — both peers opted in, and STILL no duplication: resume reconciles honestly
     (ADR-016 decision 5 — the egg keeps its relaunch-only power-cut ritual).

Judged on logs + the actual save files. Run:  python tools/linkblip.py
"""
import json
import sys
import time

from linktest import launch, collect, godot_user_dir, clear_slot, leftover_journals

BASE_PORT = 17801
UDIR = godot_user_dir()
FAST = ["--linkpeertimeout=3000", "--linkgrace=45"]


def check(name, ok, detail=""):
    print(f"[blip] {name}: {'PASS' if ok else 'FAIL'}{(' — ' + detail) if detail else ''}")
    return ok


def party_of(slot):
    try:
        data = json.loads((UDIR / f"pokeredpc_save_{slot}.json").read_text(encoding="utf-8"))
        return [m["species"] for m in data["party"]]
    except OSError:
        return ["<missing>"]


def md5_of(out):
    for line in out.splitlines():
        if "stream_md5=" in line:
            return line.split("stream_md5=")[1].split()[0]
    return "<none>"


def end_of(out):
    for line in out.splitlines():
        if "end=" in line:
            return line.split("end=")[1].split()[0]
    return "<none>"


def battle_pair(port, host_extra=(), join_extra=()):
    h = launch(["--colsoak", "--clubhost", f"--port={port}",
                "--colparty=0", "--colseed=41000", *FAST, *host_extra])
    time.sleep(4)
    j = launch(["--colsoak", "--clubjoin", f"--port={port}",
                "--colparty=1", "--colseed=41000", *FAST, *join_extra])
    return collect(h, 360), collect(j, 360)


def trade_pair(port, hslot, jslot, join_extra, host_extra=()):
    clear_slot(hslot)                    # gh #36: start from nothing, every scenario
    clear_slot(jslot)
    h = launch(["--clubtest", "--clubhost", "--trade", f"--port={port}",
                f"--saveslot={hslot}", *FAST, *host_extra])
    time.sleep(6)
    j = launch(["--clubtest", "--clubjoin", "--trade", f"--port={port}",
                f"--saveslot={jslot}", *FAST, *join_extra])
    return collect(h, 300), collect(j, 300)


def battle_case(ok, name, hout, jout):
    ok &= check(f"{name}: no runtime errors",
                "SCRIPT ERROR" not in hout and "SCRIPT ERROR" not in jout)
    ok &= check(f"{name}: blip fired", "BLIP injected" in hout or "BLIP injected" in jout)
    ok &= check(f"{name}: session RESUMED on both sides",
                "session RESUMED" in hout and "session RESUMED" in jout)
    he, je = end_of(hout), end_of(jout)
    ok &= check(f"{name}: battle completed, never void",
                he == je and he not in ("<none>", "winner=void"), f"{he} / {je}")
    hm, jm = md5_of(hout), md5_of(jout)
    ok &= check(f"{name}: LOCKSTEP — streams byte-identical across the outage",
                hm == jm and hm != "<none>", f"{hm} / {jm}")
    return ok


def main():
    ok = True

    # 1 — one blip mid-battle, each side once
    hout, jout = battle_pair(BASE_PORT, host_extra=("--blipat=act2",))
    ok = battle_case(ok, "battle@act2(host)", hout, jout)
    hout, jout = battle_pair(BASE_PORT + 1, join_extra=("--blipat=act3",))
    ok = battle_case(ok, "battle@act3(join)", hout, jout)

    # 2 — the blip-soak: a whole battle with the transport dying every second turn
    hout, jout = battle_pair(BASE_PORT + 2, host_extra=("--blipevery=2",))
    ok = battle_case(ok, "blip-soak(every 2 turns)", hout, jout)
    ok &= check("blip-soak: more than one outage survived",
                hout.count("session RESUMED") >= 2, f"{hout.count('session RESUMED')} resumes")

    # 3/4 — the trade matrix: every phase blips, and the trade still completes on both saves
    for i, point in enumerate(["pick", "confirm", "commit", "ack"]):
        hs, js = f"blh{point}", f"blj{point}"
        hout, jout = trade_pair(BASE_PORT + 3 + i, hs, js, [f"--blipat={point}"])
        hp, jp = party_of(hs), party_of(js)
        ok &= check(f"trade@{point}: no runtime errors",
                    "SCRIPT ERROR" not in hout and "SCRIPT ERROR" not in jout)
        ok &= check(f"trade@{point}: blip fired", "BLIP injected" in jout)
        ok &= check(f"trade@{point}: session RESUMED on both sides",
                    "session RESUMED" in hout and "session RESUMED" in jout)
        ok &= check(f"trade@{point}: both sides completed (result=done)",
                    "result=done" in hout and "result=done" in jout)
        ok &= check(f"trade@{point}: both saves TRADED",
                    "machamp" in hp and "kadabra" not in hp
                    and "alakazam" in jp and "machoke" not in jp, f"{hp} / {jp}")
        ok &= check(f"trade@{point}: journals cleared",
                    "journal=false" in hout and "journal=false" in jout)

    # 5 — the dupe easter egg does NOT fire on a blip: resume reconciles honestly
    hout, jout = trade_pair(BASE_PORT + 7, "blhdupe", "bljdupe",
                            ["--blipat=ack", "--dupe"], host_extra=("--dupe",))
    hp, jp = party_of("blhdupe"), party_of("bljdupe")
    ok &= check("dupe@ack blip: both completed honestly",
                "result=done" in hout and "result=done" in jout)
    ok &= check("dupe@ack blip: NO duplication (machoke traded away, not kept)",
                "machamp" in hp and "alakazam" in jp and "machoke" not in jp,
                f"{hp} / {jp}")

    if not ok and leftover_journals():
        print(f"[blip] hint: leftover trade journals in the user dir (a stale one changes "
              f"launch behavior — gh #36): {', '.join(leftover_journals())}")
    print(f"[blip] {'ALL GREEN' if ok else 'FAIL'}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
