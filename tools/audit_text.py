"""Audit map text coverage: every object/sign TEXT_id referenced across all maps that
resolves to nothing in text.json, grouped by the kind of thing it's attached to.

Most residual misses are handled by engine logic (item balls give via their item field;
mart clerks open the shop; nurses heal; trade NPCs run the trade). Run after extractor
changes to catch NPCs/signs that would show an empty box. See ADR-008."""
import json, glob, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "game", "assets")
ITEMS = {"POTION", "SUPER_POTION", "HYPER_POTION", "MAX_POTION", "FULL_RESTORE", "REVIVE",
         "MAX_REVIVE", "ANTIDOTE", "AWAKENING", "ESCAPE_ROPE", "RARE_CANDY", "NUGGET",
         "MOON_STONE", "HP_UP", "IRON", "CARBOS", "CALCIUM", "PP_UP", "ELIXER", "MAX_ELIXER",
         "X_ACCURACY", "SECRET_KEY", "LIFT_KEY", "SILPH_SCOPE", "ULTRA_BALL", "FULL_HEAL"}


def classify(sprite, tid, args):
    if any(a.startswith("OPP_") for a in args):
        return "trainer"
    if any(a in ITEMS or a.startswith("TM_") for a in args) or "POKE_BALL" in sprite:
        return "item_ball"
    if sprite == "SPRITE_NURSE":
        return "nurse"
    if sprite == "SPRITE_LINK_RECEPTIONIST":
        return "link_receptionist"
    if sprite == "SPRITE_CLERK":
        return "mart_clerk"
    return "OTHER_NPC"


def main():
    text = json.load(open(os.path.join(A, "text.json"), encoding="utf-8"))
    cats, examples = {}, {}
    for f in sorted(glob.glob(os.path.join(A, "maps", "*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        label = os.path.basename(f)[:-5]
        for o in d.get("object_events", []):
            args = [str(a) for a in o.get("args", [])]
            tid = next((a for a in args if a.startswith("TEXT_")), None)
            if not tid or tid in text:
                continue
            c = classify(str(o.get("sprite", "")), tid, args)
            cats[c] = cats.get(c, 0) + 1
            examples.setdefault(c, []).append(f"{label}:{tid}")
        for b in d.get("bg_events", []):
            t = str(b.get("text", ""))
            if t.startswith("TEXT_") and t not in text:
                cats["sign"] = cats.get("sign", 0) + 1
                examples.setdefault("sign", []).append(f"{label}:{t}")
    print(f"missing text refs by kind (of {len(text)} resolved):")
    for c in sorted(cats, key=lambda k: -cats[k]):
        print(f"  {c:18} {cats[c]:4}   e.g. {examples[c][:3]}")


if __name__ == "__main__":
    main()
