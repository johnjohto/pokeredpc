# Link layer (v1.1 multiplayer)

**`Link.gd`** is the one module that touches networking (gh #3, ADR-014). It owns the
transport and the **link identity** handshake, and will carry the **mon record** (gh #4) and
per-turn lockstep actions (gh #7) behind the same interface. Nothing else in the engine may
open a socket: the Cable Club attendant (gh #5), the Trade Center (gh #6), and the
Colosseum (gh #7) all talk to this interface.

## Transport

Godot's low-level **ENet** (`ENetConnection` / `ENetPacketPeer`): one connection between two
trusted peers over LAN or direct IP — no servers, no discovery, no NAT traversal (out of
scope by spec). Two reliable-ordered channels: `0` control (handshake/session), `1` data
(mon records, battle actions — later tickets). Messages are JSON dictionaries with a `t`
type tag. ENet is polled in `_process` (`service(0)`, non-blocking); **no awaits anywhere**,
so a dead connection can never soft-lock the game or a headless run (spec story 21; the
gh #103 lesson).

## Interface

- `host(port)` / `join(ip, port)` — raise a session (port default `17225`).
- `send_message(dict)` — post-handshake session traffic on the data channel.
- `close(reason)` — graceful: `peer_disconnect_later()` delivers everything still queued
  (a `refuse`, the `bye`) **before** the drop, serviced through a short `closing` state.
  A plain disconnect would discard queued packets and the peer would only see the
  connection die — that is why the refusal is visible on *both* sides.
- Signals: `established(session)`, `refused(reason, by_peer)`, `closed(reason)`,
  `message(dict)`.
- `timeout_s` bounds every pre-linked state (waiting / connecting / handshake); expiry
  logs `[link] timeout` and closes cleanly.

## Session lifecycle

```
idle → waiting (host) | connecting (join) → handshake → linked → closing → closed
```

On ENet connect, **both** sides send `hello` carrying their identity. Each side
independently validates the peer's identity against its own: a match sends `accept`; the
session is **established** once we validated *them* and they accepted *us*. Any difference
is a refusal that **names the differing part**: the refuser logs `[link] REFUSED: …`, sends
`refuse` with the reason (so the peer logs `[link] REFUSED by partner: …`), and closes.

## Link identity

```
{ "version": <application/config/version>,
  "parts":   { "base_stats": md5, "moves": md5, "types": md5 },
  "flags":   { "dupe": bool } }
```

- **Version** is the exact game version — no cross-version link compatibility (spec).
- **Parts** come from `assets/link_manifest.json`, written by the extractor
  (`build_link_manifest` in `tools/extract.py`) at extraction time (spec story 24): md5s
  over the link-relevant extracted data — the tables both engines must agree on to simulate
  the identical battle and speak the same mon record (species/base stats + growth +
  evolutions + learnsets, moves, the type chart). Under lockstep, silent data drift is an
  undebuggable mid-battle desync — mismatched peers must never link, and the refusal tells
  the player which part to fix ("both copies must be extracted from the same pokered").
- **Flags** carry session opt-ins. The dupe easter egg (`dupe_opt_in`) travels here; the
  established session records the **mutual AND only** (`session["dupe"]`) — one player's
  nostalgia can't desync the other's save (spec stories 19–20). A flag difference is *not*
  a refusal.

## Debug flags (the tracer bullet)

| Flag | What it does |
|---|---|
| `--host [--port=N]` | Host and wait; on link, send a `ping`, expect `pong`, close. |
| `--join <ip>` / `--join=<ip>` | Connect to a host; answer the `ping`. |
| `--tamper=version` / `--tamper=<part>` | Corrupt this side's identity → drives the refusal path. |
| `--linktimeout=N` | Shorten the no-partner timeout (tests). |
| `--dupe` | Set this side's easter-egg opt-in flag. |

**`python tools/linktest.py`** launches host+join pairs headlessly over localhost and
asserts both logs across four scenarios: clean link (established both sides + the ping/pong
round-trip), a tampered content part (both sides refuse naming `'moves'`), a tampered
version (both sides refuse naming the version), and a join with no host (clean timeout, no
hang). Judged on log content; exits non-zero on any failure.
