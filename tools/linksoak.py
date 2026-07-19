"""gh #8 (ADR-014, Stage 1 of the 1.1 gate): the desync soak. One command launches pairs
of real headless instances over localhost, drives a battery of seeded link battles across
varied parties/movesets/seeds (--colsoak's fast path), and asserts BOTH peers' per-turn
event streams are byte-identical in every battle — the lockstep oracle at volume. Any
divergence fails the battery naming the battle, the seed/parties, and the first differing
event (which names the turn).

Run:  python tools/linksoak.py [--battles N]   (default 8)
Reuses linktest.py's launch/collect driver (the reusable two-instance harness).
"""
import argparse
import sys
import time

from linktest import launch, collect

BASE_PORT = 17601
N_PARTIES = 6


def stream(out):
    return [l.split("] ", 1)[1].strip() for l in out.splitlines() if "[battledet]" in l]


def soak_line(out, tag):
    return next((l.strip() for l in out.splitlines() if f"[soak] {tag}:" in l), "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--battles", type=int, default=8)
    args = ap.parse_args()

    failures = 0
    for k in range(args.battles):
        hp = k % N_PARTIES
        jp = (k + 3) % N_PARTIES if k != N_PARTIES else hp   # battle 6 is a MIRROR match:
        if k == N_PARTIES:                                   # same party both sides — fixed
            jp = hp                                          # DVs make every turn a speed tie
        seed = 20000 + k * 101
        port = BASE_PORT + k
        h = launch(["--colsoak", "--clubhost", f"--port={port}",
                    f"--colparty={hp}", f"--colseed={seed}"])
        time.sleep(4)
        j = launch(["--colsoak", "--clubjoin", f"--port={port}",
                    f"--colparty={jp}", f"--colseed={seed}"])
        hout = collect(h, 420)
        jout = collect(j, 360)
        hs = stream(hout)
        js = stream(jout)
        hl = soak_line(hout, "host")
        jl = soak_line(jout, "join")
        okb = bool(hs) and hs == js and "end=winner=" in hl and "end=winner=" in jl
        tag = "OK " if okb else "FAIL"
        print(f"[soak] battle {k}: {tag} parties {hp}v{jp} seed={seed} "
              f"events={len(hs)}/{len(js)}")
        if not okb:
            failures += 1
            print(f"[soak]   host: {hl or '(no soak line)'}")
            print(f"[soak]   join: {jl or '(no soak line)'}")
            for i in range(max(len(hs), len(js))):
                a = hs[i] if i < len(hs) else "<missing>"
                b = js[i] if i < len(js) else "<missing>"
                if a != b:
                    print(f"[soak]   first divergence at event {i}:")
                    print(f"[soak]     host: {a}")
                    print(f"[soak]     join: {b}")
                    break
    print(f"[soak] {'ALL GREEN' if failures == 0 else 'FAIL'} "
          f"({args.battles - failures}/{args.battles} battles in sync)")
    sys.exit(0 if failures == 0 else 1)


if __name__ == "__main__":
    main()
