"""Find `await RenderingServer.frame_post_draw` on a gameplay code path.

Under `--headless`, `DisplayServer::can_any_window_draw()` is false, so `Main::iteration()` never calls
`RenderingServer::draw()` and `frame_post_draw` is **never emitted**. Awaiting it suspends the coroutine
forever. A suspended coroutine is not a crash: no `SCRIPT ERROR`, no stack, no exit — just a character
standing still. That is gh #103, where `Cutscene.ss_anne_departs` set `cutscene_active = true`, awaited
the signal to screen-grab the water it sails the ship over, and stranded every headless run on the S.S.
Anne gangway. The ADR-011 Stage-1 gate is headless by definition, so it could never have passed.

The rule: the signal may only be awaited from a **debug driver** — a function whose name ends in `test`
or `shot`, run windowed via `tools/run.ps1` (see the `headless-screenshot-tests-hang` note). Anywhere
else it must be guarded by a `DisplayServer.get_name() != "headless"` check in the same function, or
carry an explicit `# audit: headless-guarded` annotation.

Exits 1 on any violation.
"""
import glob
import re
import sys

SIGNAL = "RenderingServer.frame_post_draw"
GUARD = 'DisplayServer.get_name() != "headless"'
ANNOTATION = "# audit: headless-guarded"


def functions(path):
    """Yield (name, start_line, [lines]) for each top-level func in a .gd file."""
    src = open(path, encoding="utf-8", errors="replace").read().splitlines()
    cur, start, body = "<toplevel>", 1, []
    for i, line in enumerate(src, 1):
        m = re.match(r"func\s+([A-Za-z_0-9]+)", line)
        if m:
            if body:
                yield cur, start, body
            cur, start, body = m.group(1), i, []
        body.append((i, line))
    if body:
        yield cur, start, body


def main():
    bad = []
    for path in sorted(glob.glob("game/scripts/**/*.gd", recursive=True)):
        for name, _start, body in functions(path):
            hits = [(i, l) for i, l in body if SIGNAL in l and "await" in l]
            if not hits:
                continue
            if name.endswith("test") or name.endswith("shot"):
                continue                                   # a debug driver; run it windowed
            text = "\n".join(l for _i, l in body)
            if GUARD in text:
                continue                                   # guarded — headless takes the other branch
            for i, l in hits:
                if ANNOTATION in l:
                    continue
                bad.append((path.replace("\\", "/"), i, name, l.strip()))

    for path, line, fn, text in bad:
        print("%s:%d  %s()  %s" % (path, line, fn, text))
    print("gameplay awaits on frame_post_draw (headless softlocks): %d" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
