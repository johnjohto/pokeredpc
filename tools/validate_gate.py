"""Validate an ADR-011 Stage-1 gate log. A `PASS:` line is necessary, not sufficient.

Usage: python validate_gate.py <ptrun-gate.log>

The gate is GREEN iff:
  1. every stage checkpointed, in order, and the run reached the HALL OF FAME;
  2. no ALWAYS-fatal pattern appears — a crash, a dropped map callback, or a grind that did nothing.
     These don't halt the run, so they can hide inside an otherwise-complete run and still be real bugs;
  3. no RECOVERABLE-failure pattern appears UNLESS the run completed. Once the bot was hardened to
     recover from whiteouts (gh #131), a healthy run legitimately *uses* its retries — and in a run that
     checkpointed all 21 stages a `FAIL(` / `attempt N ended on` / `stayed put` line is necessarily a
     caught-and-recovered retry (a stage that ultimately gave up could not have checkpointed). The
     LAST_MAP-teleport a retry could once have exploited is fixed (gh #100), so a recovered retry
     re-navigated legitimately. In an INCOMPLETE run these same lines mark where it died, so they stay
     fatal there.
"""
import re
import sys

STAGES = ["opening", "parcel", "brock", "misty", "bill", "ssanne", "surge", "rocktunnel", "erika",
          "silphscope", "pokeflute", "snorlax", "koga", "safari", "saffron", "silph", "sabrina",
          "blaine", "giovanni", "victoryroad", "elite4"]

# Bad even in a completed run: a bug that prints but doesn't halt the run.
ALWAYS = [
    (r"SCRIPT ERROR", "a Godot runtime error"),
    (r"on_enter SKIPPED", "gh #96: a map's load callback was dropped"),
    (r"grind: no reachable grass", "a grind silently did nothing"),
]

# A leg that failed and was retried. Fine in a completed run (the run demonstrably continued past them);
# fatal in an incomplete one (they mark where it died). gh #100 (the LAST_MAP teleport a retry could
# exploit) is fixed, so a recovered retry re-navigated for real.
RECOVERABLE = [
    (r"FAIL\(", "a leg gave up and was retried"),
    (r"attempt \d+ ended on", "a persistent-player whiteout retry (gh #100 teleport is fixed)"),
    (r"stayed put", "gh #99: a crossing bumped the map edge, then retried"),
]


def main():
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    lines = text.splitlines()
    bad = 0

    # Completion: every stage checkpointed, in order, and the HALL OF FAME reached. A stage that failed
    # terminally quits the run, so all 21 checkpoints existing proves no stage ultimately gave up.
    saved = [m.group(1) for m in (re.search(r"checkpoint saved: (\w+)", l) for l in lines) if m]
    missing = [s for s in STAGES if s not in saved]
    in_order = saved == [s for s in STAGES if s in saved]
    hof = "entered the HALL OF FAME" in text
    completed = not missing and in_order and hof

    def report(pat, why, fatal):
        nonlocal bad
        hits = [l for l in lines if re.search(pat, l)]
        if not hits:
            print("ok    %-30s absent" % pat)
        elif fatal:
            bad += 1
            print("FAIL  %-30s %s" % (pat, why))
            for h in hits[:5]:
                print("        %s" % h.strip())
        else:
            print("note  %-30s %d recovered — %s" % (pat, len(hits), why))

    for pat, why in ALWAYS:
        report(pat, why, fatal=True)
    for pat, why in RECOVERABLE:
        report(pat, why, fatal=not completed)

    if missing:
        bad += 1
        print("FAIL  checkpoints: missing %s" % ", ".join(missing))
    elif not in_order:
        bad += 1
        print("FAIL  checkpoints: out of order -> %s" % saved)
    else:
        print("ok    checkpoints: all %d stages, in order" % len(STAGES))

    if not hof:
        bad += 1
        print("FAIL  never entered the HALL OF FAME")
    else:
        print("ok    entered the HALL OF FAME")

    print()
    print("GATE %s" % ("GREEN" if bad == 0 else "NOT GREEN (%d checks failed)" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
