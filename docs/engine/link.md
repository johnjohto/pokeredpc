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

## The Cable Club attendant (gh #5)

`Cutscene.cable_club_npc` runs when any Pokémon Center's `SPRITE_LINK_RECEPTIONIST` is
talked to — faithful to `engine/link/cable_club_npc.asm` (`CableClubNPC`) +
`engine/menus/main_menu.asm` (`LinkMenu`):

- **Welcome** → no Pokédex: the "We're making preparations." brush-off, as on cartridge.
- **HOST / JOIN / CANCEL** — the modern stand-in for the asm's serial-connection attempt.
  JOIN opens the naming screen's **address mode** (digits + `.`; ED confirms; the
  **last-used address** is the ED default, saved additively as `link_addr`). A wait or a
  dead address times out (`link_wait_s`, B cancels) back to the asm's failure line —
  "This area is reserved for 2 friends…". A handshake refusal surfaces **in-dialogue**
  first, naming the differing part.
- From establishment on, **the asm's script**: "Please apply here / we have to save" →
  YES/NO (NO → "Please come again!") → save + save jingle → "Please wait." while both
  sides sync the ready beat (inactivity → the asm's link-closed apology) → **LinkMenu**:
  TRADE CENTER / COLOSSEUM / CANCEL, where the first player to press wins and the **host
  arbitrates** (in Gen 1 the internally-clocked Game Boy wins) — the joiner sends
  `club_pick`, the host answers with the authoritative `club_go`.
- The chosen room loads via the **special warp** (`special_warps.asm`): host at (3,4),
  partner at (6,4), in `TradeCenter` / `Colosseum`. (The rooms' interactions are gh #6/#7.)

Verified by `--clubtest` (single instance: no-dex, cancel, host-timeout, dead-address —
each back to the overworld with no modal, no cutscene, link closed) and two
`tools/linktest.py` scenarios (the full two-instance flow onto the Trade Center floor;
a tampered joiner turned away at the desk on both sides).

## The Trade Center (gh #6)

`Cutscene.trade_center_table` runs when either the table or the partner's avatar is
interacted with in `TradeCenter` (the avatar sits in the opposite chair, as
`TradeCenter_Script` repositions it; walking onto the doormat row leaves the club and
closes the link — `scripts/maps/TradeCenter.gd`).

- **Parties exchange as mon records** (`tc_party`) when each player sits; the first sitter
  waits bounded only by the link's liveness (B stands up). Messages that arrive before a
  listener exists (the partner sat first) are held in the **Link inbox** and drained on
  room entry; the partner's protocol steps land in **ordered queues**, never scalar slots —
  under load a partner can be a whole step ahead, and a scalar reset would clobber it.
- **Pick + partner's pick + mutual confirm**: your list opens over the partner's (both
  parties on screen); picks cross as `tc_pick`, the confirm as `tc_confirm`; either side
  canceling costs nothing (spec story 12), a declined confirm returns to the pick screens.
- **The commit is two-phase**: both sides exchange the authoritative record (`tc_commit`),
  journal the pending trade to disk (`<save>_trade_journal.json`), then ack (`tc_ack`);
  only when both acks are in does either side apply — remove the given mon, play the
  in-game trade-movie ceremony, add the received mon (party, or box when full), fire a
  trade evolution on arrival (forced), **save**, and clear the journal. A drop before
  completion applies on neither side; a leftover journal at boot logs and rolls back
  (gh #9 proves the windows under injected failures).
- The received mon keeps its **nickname, OT, and trainer ID** off the record — outsider
  status is exactly what the engine's boosted-exp rule and the Name Rater already key on.

Verified by the `linktest.py` **trade** scenario: kadabra ↔ machoke across the table, both
arriving mons trade-evolving (ALAKAZAM / MACHAMP) with foreign OT/ID intact, journals
cleared, and **both save files** read back holding the traded parties.

## The Colosseum (gh #7) — lockstep link battles

`Cutscene.colosseum_table`: parties cross as mon records, the **host fixes the shared
seed**, and both engines run `Battle.start_link` — the full battle engine, each peer
simulating with itself as the "player" side (mirrored, as pokered's link battles are), and
**only chosen actions crossing the wire** (`col_act` per turn, `col_swap` for faint
replacements). A desync is a determinism bug by definition, never reconciled.

What keeps two mirrored sims identical (each faithful to the asm's `LINK_STATE_BATTLING`
special cases):

- **No badge boosts** (`ApplyBadgeStatBoosts` rets in link) and **no hidden 65/256
  stat-down miss** — both player/enemy-asymmetric rules that would diverge the sims.
- **No EXP/stat exp/money**; the whole battle is **stakeless**: the party is snapshotted at
  start and restored at the end, win or lose (spec story 17). A loss is not a whiteout.
- **Speed ties draw the shared coin canonically** — "heads = the HOST acts first" — so both
  sims order the tie identically. Switches resolve before moves; the peer's replacement
  applies synchronously on arrival so both peers digest the same post-swap state.
- **The event stream is role-canonical in link mode**: `T` lines label actions `h[…]j[…]`
  (host first), the digest orders the host's side first on both peers, faint-replacement
  `X` lines carry the role, and `END` carries `winner=host|join|draw|void`. **Byte-equality
  of the two peers' `[battledet]` streams is the definition of "in sync"** — asserted by
  the `linktest.py` colosseum scenario across two real networked instances.
- Waiting on the partner (`linkwait`) has no artificial clock — a friend may think; ENet's
  own dead-peer detection ends a vanished session, stakeless ("Waiting..." reads as the
  game working, spec story 16).

**Documented v1.1 divergences** (each refused/handled identically on both sims, so no
desync surface): items can't be used in a link battle (the cartridge allows them; the
enemy-side application of every bag item is a later faithfulness pass), and a link-battle
MIMIC copies a deterministic random technique on both sims instead of opening the mid-turn
pick menu (a menu choice can't cross the wire mid-resolution).

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
