extends Node
## The v1.1 link layer (gh #3, ADR-014): the ONE module that touches networking. It owns the
## transport (ENet, one reliable-ordered connection between two trusted peers over LAN/direct
## IP — no servers, no discovery) and the LINK IDENTITY handshake (exact game version +
## exact engine build + the extractor's content-hash manifest over link-relevant data), and
## it will carry the mon record and per-turn action exchange in later tickets. Everything outside talks to this
## interface — host()/join()/send_message()/close() + the signals — never to the network.
##
## Session lifecycle:
##   idle -> waiting (host) | connecting (join) -> handshake -> linked -> closed
## On ENet connect, BOTH sides send `hello` carrying their identity
## {version, engine, parts, flags}.
## Each side independently compares the peer's identity to its own: any difference is a
## refusal NAMING the differing part (`refuse` message + local log + disconnect) — under
## lockstep, silent data drift becomes an undebuggable mid-battle desync, so mismatched
## peers must never link (ADR-014). On a match each side sends `accept`; the session is
## established once we have validated THEM and they have accepted US. Session flags (the
## dupe easter-egg opt-in) travel in `hello`; the session records the MUTUAL result only.
## Every wait state times out cleanly (no awaits — polled in _process, headless-safe).

signal established(session: Dictionary)
signal refused(reason: String, by_peer: bool)
signal closed(reason: String)
signal message(msg: Dictionary)      # post-handshake session traffic (later tickets)
signal lost()                        # gh #13: an ARMED linked session dropped; the grace window opened
signal resumed(session: Dictionary)  # gh #13: the SAME session re-established via the resume token

const DEFAULT_PORT := 17225
const CH_CONTROL := 0                # handshake + session control
const CH_DATA := 1                   # mon records / battle actions (later tickets)

var main                             # Main (for _load_json)
var timeout_s := 30.0                # applies to waiting/connecting/handshake, not linked
var dupe_opt_in := false             # the easter-egg flag: sent in hello; mutual AND recorded
var state := "idle"                  # idle | waiting | connecting | handshake | linked | lost | closing | closed
var is_host := false
# --- session resume (gh #13, ADR-016): transport blips only — both processes alive, the socket
# died. Consumers ARM resume at the table (trade/colosseum); an unarmed drop tears down exactly
# as before, which keeps the pre-table states (attendant flow, save beat, LinkMenu) on today's
# story. While "lost", the host keeps listening on the session port and the joiner auto-redials
# with backoff; ONE grace clock bounds the whole outage (the player can give up via cancel_wait).
# The session token, minted by the host at link-up and shared in its `accept`, rides the
# reconnect `hello` — a wrong or absent token (a stranger, or a relaunched process, which by
# scope keeps the teardown + journal story) is refused and the wait continues.
var resume_armed := false            # set by the table flows; cleared on teardown
var resume_grace_s := 120.0          # the outage bound (player-cancellable)
var peer_timeout_max_ms := 60000     # ENet dead-peer bound; tests shrink it (--linkpeertimeout)
var _session_token := ""             # minted host-side at establish; both sides hold it once linked
var _join_ip := ""                   # the joiner's redial target
var _join_port := 0
var _was_lost := false               # the current handshake is a resume attempt
var _lost_elapsed := 0.0             # accumulates across lost + resume-handshake states
var _redial_in := 0.0                # seconds until the joiner's next redial
var _redial_backoff := 2.0
var session := {}                    # once linked: {"remote": identity, "dupe": bool}
var tamper := ""                     # debug (--tamper=X): corrupt OUR version/engine/part before send

var _enet: ENetConnection
var _peer: ENetPacketPeer
var _elapsed := 0.0
var inbox: Array = []                # session messages that arrived with no `message` listener
                                     # connected (e.g. the partner sat at the table before we
                                     # loaded the room) — drained via take_inbox() on connect
var lan_addr := ""                   # this machine's private IPv4 (shown while hosting)
var wan_addr := ""                   # the router's external address, via UPnP ("" until found)
var _wan_thread: Thread              # the blocking UPnP discover runs off the main thread
var _upnp_mapped_port := 0           # the UDP port we asked the router to forward
var _remote: Dictionary = {}         # the peer's hello identity
var _remote_ok := false              # we validated their identity
var _accepted := false               # they validated ours
var _close_reason := "closed"        # carried through the graceful "closing" state


## Our link identity: exact version + exact engine build + the extraction manifest's
## per-part hashes + session flags. `tamper` corrupts what we SEND (and, honestly, what we
## believe — a corrupted manifest corrupts both sides of the comparison), which is how the
## refusal path is tested.
func identity() -> Dictionary:
	var manifest: Dictionary = main._load_json("res://assets/link_manifest.json")
	if manifest.is_empty():
		# Exported build: res://assets' raw JSONs aren't packed. The link manifest is a
		# DERIVED VIEW of the project identity (gh #23) — species/moves/types re-emitted
		# from the same per-part hashes — so deriving the identical view here changes
		# nothing: source-run and exported peers compare the same values.
		var ip: Dictionary = (ProjectData.manifest.get("identity", {}) as Dictionary).get("parts", {})
		manifest = {"parts": {"species": str(ip.get("species", "?")),
			"moves": str(ip.get("moves", "?")), "types": str(ip.get("types", "?"))}}
	var ver := str(ProjectSettings.get_setting("application/config/version", "?"))
	# gh #12: the engine build is part of link identity. The two peers run the SAME sim on
	# different machines/OSes; Godot's RNG algorithm and float/string behavior are only
	# guaranteed identical for the identical engine release, so a differing build is the
	# same undebuggable-desync risk as differing data. version_info.string carries
	# major.minor.status + the build git hash — cross-OS builds of one release share it.
	var eng := str(Engine.get_version_info().get("string", "?"))
	var parts: Dictionary = (manifest.get("parts", {}) as Dictionary).duplicate()
	if tamper == "version":
		ver += "-tampered"
	elif tamper == "engine":
		eng += "-tampered"
	elif tamper != "" and parts.has(tamper):
		parts[tamper] = "0000tampered"
	# `name` rides along for display (the trade movie's farewell, the Colosseum label);
	# it is NOT part of the comparison — names may differ, that's the point of them.
	return {"version": ver, "engine": eng, "parts": parts, "flags": {"dupe": dupe_opt_in},
		"name": str(main.player_name)}


## Fresh handshake state per attempt: the one Link node serves many sessions (and the
## joiner's redial), and stale _remote_ok/_accepted from a past session could otherwise
## establish before the new peer validated anything.
func _reset_session() -> void:
	_remote = {}
	_remote_ok = false
	_accepted = false
	_peer = null
	session = {}
	inbox = []
	_elapsed = 0.0
	_session_token = ""
	_was_lost = false
	_lost_elapsed = 0.0
	resume_armed = false


func host(port := DEFAULT_PORT) -> void:
	_reset_session()
	is_host = true
	_enet = ENetConnection.new()
	var err := _enet.create_host_bound("*", port, 1, 2)
	if err != OK:
		print("[link] ERROR: could not bind port %d (%s)" % [port, error_string(err)])
		_finish("bind-error")
		return
	state = "waiting"
	_elapsed = 0.0
	print("[link] hosting on port %d — waiting for a partner..." % port)


func join(ip: String, port := DEFAULT_PORT) -> void:
	_reset_session()
	is_host = false
	_join_ip = ip
	_join_port = port
	_enet = ENetConnection.new()
	var err := _enet.create_host(1, 2)
	if err == OK:
		_peer = _enet.connect_to_host(ip, port, 2)
	if err != OK or _peer == null:
		print("[link] ERROR: could not start a connection to %s:%d" % [ip, port])
		_finish("connect-error")
		return
	state = "connecting"
	_elapsed = 0.0
	print("[link] joining %s:%d ..." % [ip, port])


## Post-handshake session traffic (reliable ordered, the data channel).
func send_message(msg: Dictionary) -> void:
	if state == "linked" and _peer != null:
		_peer.send(CH_DATA, JSON.stringify(msg).to_utf8_buffer(), ENetPacketPeer.FLAG_RELIABLE)


## Graceful close: peer_disconnect_later() delivers everything still queued (a `refuse`, the
## `bye`) BEFORE the drop — a plain disconnect discards it and the peer only ever sees the
## connection die. The "closing" state services ENet until the disconnect completes (or a
## short grace expires), then tears down.
func close(reason := "closed") -> void:
	if state == "closed" or state == "closing":
		return
	if _peer != null and _peer.get_state() == ENetPacketPeer.STATE_CONNECTED and _enet != null:
		_close_reason = reason
		state = "closing"
		_elapsed = 0.0
		_peer.peer_disconnect_later()
	else:
		_finish(reason)


## This machine's private IPv4 — the address a friend on the SAME network joins.
func lan_address() -> String:
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.begins_with("192.168.") or s.begins_with("10."):
			return s
		if s.begins_with("172."):
			var oct := int(s.get_slice(".", 1))
			if oct >= 16 and oct <= 31:
				return s
	return ""


## Ask the ROUTER (UPnP — no third-party service, true to the no-servers design) for the
## external address a remote friend joins, and map the UDP port through while we're at it,
## so internet hosting works without manual port forwarding. Runs on a thread: discover
## blocks for up to ~1.5 s and must never hitch a frame. Results land in `wan_addr`.
func start_wan_query(port: int) -> void:
	if _wan_thread != null or wan_addr != "":
		return
	_wan_thread = Thread.new()
	_wan_thread.start(_wan_worker.bind(port))


func _wan_worker(port: int) -> void:
	var upnp := UPNP.new()
	if upnp.discover(1500, 2) == UPNP.UPNP_RESULT_SUCCESS:
		var gw := upnp.get_gateway()
		if gw != null and gw.is_valid_gateway():
			upnp.add_port_mapping(port, port, "pokeredpc link", "UDP")
			var ext := str(upnp.query_external_address())
			call_deferred("_wan_found", ext, port)
	call_deferred("_wan_thread_done")


func _wan_found(ext: String, port: int) -> void:
	if ext != "":
		wan_addr = ext
		_upnp_mapped_port = port
		print("[link] reachable at %s (UPnP: UDP %d mapped)" % [ext, port])


func _wan_thread_done() -> void:
	if _wan_thread != null:
		_wan_thread.wait_to_finish()
		_wan_thread = null


## Best-effort removal of the UPnP mapping (fire-and-forget thread; leases also expire).
func _upnp_unmap() -> void:
	if _upnp_mapped_port == 0:
		return
	var port := _upnp_mapped_port
	_upnp_mapped_port = 0
	var t := Thread.new()
	t.start(func() -> void:
		var upnp := UPNP.new()
		if upnp.discover(1000, 2) == UPNP.UPNP_RESULT_SUCCESS:
			upnp.delete_port_mapping(port, "UDP")
		t.wait_to_finish.call_deferred())


## gh #13: the linked session dropped with resume armed. Hold it open: the host's bound socket
## keeps listening for the partner's redial; the joiner starts redialing. One grace clock bounds
## the whole outage (`resume_grace_s`), however many redials or failed handshakes it spans.
func _enter_lost() -> void:
	print("[link] connection lost — holding the session for a reconnect (%.0f s grace)" % resume_grace_s)
	state = "lost"
	_peer = null
	_remote_ok = false
	_accepted = false
	_was_lost = true
	_lost_elapsed = 0.0
	_redial_in = 0.5
	_redial_backoff = 2.0
	lost.emit()


## A resume attempt fizzled (failed handshake, refused stranger, dead redial): back to waiting.
## The grace clock keeps running — this never resets it.
func _back_to_lost() -> void:
	state = "lost"
	_peer = null
	_remote_ok = false
	_accepted = false


## The joiner's redial: a fresh ENet connection to the original host address. Backoff doubles
## up to 10 s between attempts; a failed attempt surfaces as EVENT_DISCONNECT and re-arms this.
func _redial() -> void:
	_redial_in = _redial_backoff
	_redial_backoff = minf(_redial_backoff * 2.0, 10.0)
	if _enet != null:
		_enet.destroy()
	_enet = ENetConnection.new()
	var err := _enet.create_host(1, 2)
	_peer = _enet.connect_to_host(_join_ip, _join_port, 2) if err == OK else null
	if _peer == null:
		print("[link] redial could not start — next try in %.0f s" % _redial_in)
	else:
		print("[link] redialing %s:%d ..." % [_join_ip, _join_port])


## gh #13: true while an armed session outage is being ridden out — the `lost` state itself,
## and the resume attempt's transient states (the redial's connect + the hello/accept round
## trip put `state` through "connecting"/"handshake" for a few frames). Consumers HOLD while
## this is true; only a truly closed link aborts their waits. Without the transient coverage
## a battle's linkwait voided INSIDE the resume handshake window.
func holding() -> bool:
	return state == "lost" or (_was_lost and state != "linked" and state != "closed")


## The player gave up waiting for the partner (B on the "Link lost" box): today's teardown.
func cancel_wait() -> void:
	if state == "lost" or _was_lost:
		_was_lost = false
		close("gave-up")


## gh #13 test hook (--blipat): kill the transport exactly as a network blip would. peer_reset()
## sends the peer NOTHING (a cable pull), and generates no local event either — so this drives
## the state change itself; the REMOTE side notices via its dead-peer timeout. The normal
## lost/resume machinery takes over from there on both sides.
func blip() -> void:
	print("[link] BLIP injected (%s)" % state)
	if _peer != null:
		_peer.reset()                      # forceful, silent: the foreign host is NOT notified
	if state == "linked" and resume_armed:
		_enter_lost()
	elif state != "closed" and state != "idle":
		_finish("disconnected")


## Hand over (and clear) the messages that arrived before a listener connected.
func take_inbox() -> Array:
	var held := inbox
	inbox = []
	return held


func _finish(reason: String) -> void:
	if state == "closed":
		return
	state = "closed"
	inbox = []
	_was_lost = false
	resume_armed = false
	_session_token = ""
	_upnp_unmap()
	if _enet != null:
		_enet.destroy()
		_enet = null
	_peer = null
	closed.emit(reason)


func _process(delta: float) -> void:
	if _enet == null or state == "closed" or state == "idle":
		return
	# Every pre-linked state times out cleanly: a dead connection must never soft-lock the
	# game (spec story 21) — and never hang a headless run (the gh #103 lesson).
	if state == "closing":
		_elapsed += delta
		if _elapsed > 3.0:                 # grace for the disconnect round-trip
			_finish(_close_reason)
			return
	elif state == "lost" or _was_lost:
		# gh #13: the outage grace is ONE clock across every redial and resume handshake —
		# a stranger's refused connect or a failed attempt never extends the wait.
		_lost_elapsed += delta
		if _lost_elapsed > resume_grace_s:
			print("[link] the partner did not return within %.0f s — closing the session" % resume_grace_s)
			_finish("resume-timeout")
			return
		if state == "lost" and not is_host:
			_redial_in -= delta
			if _redial_in <= 0.0:
				_redial()
	elif state != "linked":
		_elapsed += delta
		if _elapsed > timeout_s:
			print("[link] timeout after %.0fs (%s) — no partner" % [timeout_s, state])
			close("timeout")
			return
	# Drain this frame's ENet events. service(0) never blocks.
	while _enet != null:
		var ev: Array = _enet.service(0)
		var kind := int(ev[0])
		if kind == ENetConnection.EVENT_ERROR:
			if _was_lost:                  # a dead redial attempt is not the end of the grace
				_back_to_lost()
				return
			print("[link] transport error")
			_finish("transport-error")
			return
		if kind == ENetConnection.EVENT_NONE:
			return
		if kind == ENetConnection.EVENT_CONNECT:
			_peer = ev[1]
			# Real networks hiccup: ENet's default drop detection is tuned for LAN. Give the
			# peer up to ~60 s of unacknowledged silence before declaring it gone — combined
			# with the human-paced waits, a rough patch stalls the session instead of
			# killing it (the reported frequent "drops"). Tunable so the gh #13 blip matrix
			# doesn't wait a minute per injection for the surviving side to notice.
			_peer.set_timeout(mini(10000, peer_timeout_max_ms), mini(20000, peer_timeout_max_ms),
				peer_timeout_max_ms)
			state = "handshake"
			_elapsed = 0.0
			var me := identity()
			var env := {"t": "hello", "id": me}
			# gh #13: a resume attempt carries the session token minted at the original link-up.
			if _was_lost and _session_token != "":
				env["resume"] = _session_token
			print("[link] connected — handshake (we are version %s%s)" % [
				me["version"], ", resuming" if _was_lost else ""])
			_peer.send(CH_CONTROL, JSON.stringify(env).to_utf8_buffer(),
				ENetPacketPeer.FLAG_RELIABLE)
		elif kind == ENetConnection.EVENT_DISCONNECT:
			if state == "closing":
				_finish(_close_reason)
			elif state == "linked" and resume_armed:
				_enter_lost()              # gh #13: an armed table session holds for a reconnect
			elif _was_lost:
				_back_to_lost()            # a failed resume attempt; the grace clock decides
			else:
				if state == "linked":
					print("[link] partner disconnected")
				elif state == "handshake":
					print("[link] connection dropped during the handshake")
				else:
					print("[link] could not connect")
				_finish("disconnected")
			return
		elif kind == ENetConnection.EVENT_RECEIVE:
			var pk: PackedByteArray = (ev[1] as ENetPacketPeer).get_packet()
			var parsed = JSON.parse_string(pk.get_string_from_utf8())
			if parsed is Dictionary:
				_on_message(parsed)


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"hello":
			_remote = msg.get("id", {})
			# gh #13: a half-open session re-admits ONLY its original partner — the reconnect
			# hello must carry the token minted at link-up. A stranger, or a relaunched process
			# (which has no token and, by ADR-016 scope, keeps the teardown + journal story), is
			# turned away and the wait continues on the same grace clock.
			if _was_lost and str(msg.get("resume", "")) != _session_token:
				print("[link] resume refused: the reconnecting peer carries no session token")
				if _peer != null:
					_peer.send(CH_CONTROL, JSON.stringify({"t": "refuse",
						"reason": "this session is waiting for its original partner"})
						.to_utf8_buffer(), ENetPacketPeer.FLAG_RELIABLE)
					_peer.peer_disconnect_later()
				_back_to_lost()
				return
			var why := _mismatch(identity(), _remote)
			if why != "":
				print("[link] REFUSED: %s" % why)
				refused.emit(why, false)
				if _peer != null:
					_peer.send(CH_CONTROL, JSON.stringify({"t": "refuse", "reason": why})
						.to_utf8_buffer(), ENetPacketPeer.FLAG_RELIABLE)
				close("refused")               # graceful: the refuse is delivered first
				return
			_remote_ok = true
			if _peer != null:
				# The host mints the session token at first link-up and shares it in `accept`;
				# on a resume the token already exists and rides unchanged.
				if is_host and _session_token == "":
					_session_token = Crypto.new().generate_random_bytes(8).hex_encode()
				var acc := {"t": "accept"}
				if is_host:
					acc["token"] = _session_token
				_peer.send(CH_CONTROL, JSON.stringify(acc).to_utf8_buffer(),
					ENetPacketPeer.FLAG_RELIABLE)
			_maybe_establish()
		"accept":
			_accepted = true
			if not is_host and msg.has("token"):
				_session_token = str(msg["token"])
			_maybe_establish()
		"refuse":
			var why := str(msg.get("reason", "?"))
			if _was_lost:
				# Our resume attempt was turned away (a different host answered the port, or a
				# token disagreement). Keep waiting — the grace clock, or the player, decides.
				print("[link] resume attempt refused: %s" % why)
				_back_to_lost()
				return
			print("[link] REFUSED by partner: %s" % why)
			refused.emit(why, true)
			_finish("refused-by-peer")
		_:
			if state == "linked":
				if message.get_connections().is_empty():
					inbox.append(msg)      # nobody listening yet: hold it (ordering preserved)
				else:
					message.emit(msg)


## Compare two link identities; "" on a match, else a reason NAMING what differed. Version
## first, then each content part in sorted order — the message tells the player what to fix.
func _mismatch(ours: Dictionary, theirs: Dictionary) -> String:
	if str(theirs.get("version", "?")) != str(ours.get("version", "?")):
		return "game version differs: ours %s, theirs %s" % [
			ours.get("version", "?"), theirs.get("version", "?")]
	# gh #12: same game, different Godot build — refuse before lockstep can desync.
	if str(theirs.get("engine", "?")) != str(ours.get("engine", "?")):
		return "engine build differs: ours %s, theirs %s — both copies must run the same Godot release" % [
			ours.get("engine", "?"), theirs.get("engine", "?")]
	# gh #9: the dupe easter egg is strictly mutual — an asymmetric opt-in refuses the whole
	# session, so the egg can never fire one-sided (ADR-014 decision 7; spec story 20).
	if bool((ours.get("flags", {}) as Dictionary).get("dupe", false)) \
			!= bool((theirs.get("flags", {}) as Dictionary).get("dupe", false)):
		return "the dupe easter egg is enabled on only one side — both friends must opt in"
	var op: Dictionary = ours.get("parts", {})
	var tp: Dictionary = theirs.get("parts", {})
	var names: Array = op.keys()
	for k in tp:
		if not names.has(k):
			names.append(k)
	names.sort()
	for k in names:
		if str(op.get(k, "missing")) != str(tp.get(k, "missing")):
			return "content data '%s' differs — both copies must be extracted from the same pokered" % k
	return ""


func _maybe_establish() -> void:
	if state != "linked" and _remote_ok and _accepted:
		state = "linked"
		var rflags: Dictionary = _remote.get("flags", {})
		session = {"remote": _remote,
			"dupe": dupe_opt_in and bool(rflags.get("dupe", false))}   # mutual opt-in ONLY
		if _was_lost:
			# gh #13: the same session, re-established — the consumers reconcile from here
			# (ADR-016 rules per state); the lockstep and journal semantics are only READ.
			_was_lost = false
			_lost_elapsed = 0.0
			print("[link] session RESUMED (%s) — the partner is back" % ("host" if is_host else "join"))
			resumed.emit(session)
			return
		print("[link] session established (%s) — version %s, content hashes match%s" % [
			"host" if is_host else "join", _remote.get("version", "?"),
			", dupe easter egg ARMED" if session["dupe"] else ""])
		established.emit(session)
