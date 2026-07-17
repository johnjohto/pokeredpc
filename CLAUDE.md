# CLAUDE.md — pokeredpc

Native PC port of pret/pokered (Pokémon Red) in **Godot 4.7**. Data-driven: extract
pokered's data → PNG/JSON, reimplement the engine natively. **Not** an emulator.

## Read first
- **`docs/`** is the knowledge base. Start at `docs/index.md`.
- **`docs/roadmap.md`** = current status & next tasks. Keep it updated as work lands.
- When you change a data format or engine rule, **update the matching `docs/` file in the
  same change**, and add an ADR to `docs/decisions.md` for non-obvious choices.

## Layout
- `pokered/` upstream disassembly (source data; git-ignored, cloned separately)
- `tools/extract.py` extractor · `tools/build.ps1` build · `tools/run.ps1` run · `tools/godot/` engine
- `game/` the Godot project: `scripts/Main.gd` (world loader — render, collision, warps,
  connections), `scripts/maps/<MapLabel>.gd` (per-map story triggers; see
  `docs/engine/map-scripts.md`), `scripts/Player.gd` (movement, ledges, grass), `shaders/`
- `build/preview/` verification renders
- Git repo: `github.com/johnjohto/pokeredpc`. Commit/push when work lands; assets
  and the `pokered/` clone are git-ignored. See `docs/guides/build-and-run.md` for the full
  list of `--` debug flags.
- **Bugs/tasks are tracked in GitHub Issues** on the repo (use `gh issue …`). Reference the issue
  number in commits and close the issue with a comment (root cause + how verified) when it lands.
  Shipped fixes are summarized in `CHANGELOG.md`.

## Build / run / verify
```powershell
pwsh tools/build.ps1            # extract assets + import
pwsh tools/run.ps1             # play (arrow keys)
pwsh tools/run.ps1 -- --selftest   # headless collision/map sanity print
pwsh tools/run.ps1 -- --shot       # render a frame to game/shot.png
```
Headless import may exit `0xC0000005` on shutdown — harmless, import still completes.

## Conventions
- Windows + PowerShell primary. Python needs **Windows-style paths** (`C:/...`), not `/c/...`.
- Mind coordinate units: pixel(1) / tile(8) / cell(16) / block(32). See `docs/engine/coordinates.md`.
- Mind timing domains: battle/text `DelayFrames` = 1/60 s, but the **overworld loop ticks at 30 Hz**
  (2 V-blanks per iteration) — see `docs/engine/timing.md` before converting frames to seconds.
- Mirror pokered's behavior exactly (use the disassembly as spec); cite the asm source in
  comments/docs when implementing a rule.
- Personal-use project: do not distribute extracted assets or builds.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in this repo's GitHub Issues via the `gh` CLI; external PRs are **not** a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root (created lazily). See `docs/agents/domain.md`.

### Codex subagent (OpenAI)

Delegate a self-contained task to an OpenAI Codex agent via `tools/codex_agent.ps1` (wraps
`codex exec`; auths through the user's ChatGPT sign-in in `~/.codex`, **no API key**, spends the
user's Codex quota). Defaults to `-Sandbox read-only` (consultant/review); use
`-Sandbox workspace-write` to let Codex edit the repo. Models on this account: `gpt-5.6-sol`
(default), `-terra`, `-luna`, `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`; pick with `-Model`.
Always run **through the wrapper**, never `codex exec` directly — a direct call inside a
backgrounded shell inherits a never-closing stdin pipe and hangs (the wrapper isolates stdin via
`Start-Job` and self-limits with `-TimeoutSec`). Example:
`pwsh tools/codex_agent.ps1 -Task "Review Player.gd ledge logic for off-by-one bugs."`
