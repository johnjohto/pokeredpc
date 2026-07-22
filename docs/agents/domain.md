# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase. **pokeredpc is single-context.**

## Before exploring, read these

- **`CONTEXT.md`** at the repo root (created lazily — may not exist yet).
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

> **Note (pokeredpc):** this repo already keeps a running decision log at `docs/decisions.md` (ADRs for non-obvious engine choices, per AGENTS.md), and its knowledge base lives under `docs/` (start at `docs/index.md`). Those remain the primary references. `docs/adr/` is the skills' conventional location for machine-managed ADRs and is created only if/when `/domain-modeling` writes one — the two can coexist.

## File structure

Single-context repo:

```
/
├── CONTEXT.md          ← the port's working glossary
├── docs/
│   ├── index.md        ← existing knowledge base entry point
│   ├── decisions.md    ← existing running ADR log
│   └── adr/            ← skills' conventional ADR dir (created lazily)
└── game/               ← the Godot project
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR (in `docs/adr/` or `docs/decisions.md`), surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
