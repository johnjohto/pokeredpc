extends Node
## The v1.1 link layer (gh #3, ADR-014): the ONE module that touches networking. It owns the
## transport (ENet, one reliable-ordered connection between two trusted peers over LAN/direct
## IP — no servers, no discovery) and the LINK IDENTITY handshake (exact game version + the
## extractor's content-hash manifest over link-relevant data), and it will carry the mon
## record and per-turn action exchange in later tickets. Everything outside talks to this
## interface — host()/join()/send_message()/close() + the signals — never to the network.
##
## Session lifecycle:
##   idle -> waiting (host) | connecting (join) -> handshake -> linked -> closed
## On ENet connect, BOTH sides send `hello` carrying their identity {version, parts, flags}.
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

const DEFAULT_PORT := 17225
const CH_CONTROL := 0                # handshake + session control
const CH_DATA := 1                   # mon records / battle actions (later tickets)

var main                             # Main (for _load_json)
var timeout_s := 30.0                # applies to waiting/connecting/handshake, not linked
var dupe_opt_in := false             # the easter-egg flag: sent in hello; mutual AND recorded
var state := "idle"                  # idle | waiting | connecting | handshake | linked | closing | closed
var is_host := false
var session := {}                    # once linked: {"remote": identity, "dupe": bool}
var tamper := ""                     # debug (--tamper=X): corrupt OUR version/part before send

var _enet: ENetConnection
var _peer: ENetPacketPeer
var _elapsed := 0.0
var inbox: Array = []                # session messages that arrived with no `message` listener
                                     # connected (e.g. the partner sat at the table before we
                                     # loaded the room) — drained via take_inbox() on connect
var _remote: Dictionary = {}         # the peer's hello identity
var _remote_ok := false              # we validated their identity
var _accepted := false               # they validated ours
var _close_reason := "closed"        # carried through the graceful "closing" state


## Our link identity: exact version + the extraction manifest's per-part hashes + session
## flags. `tamper` corrupts what we SEND (and, honestly, what we believe — a corrupted
## manifest corrupts both sides of the comparison), which is how the refusal path is tested.
func identity() -> Dictionary:
	var manifest: Dictionary = main._load_json("res://assets/link_manifest.json")
	var ver := str(ProjectSettings.get_setting("application/config/version", "?"))
	var parts: Dictionary = (manifest.get("parts", {}) as Dictionary).duplicate()
	if tamper == "version":
		ver += "-tampered"
	elif tamper != "" and parts.has(tamper):
		parts[tamper] = "0000tampered"
	return {"version": ver, "parts": parts, "flags": {"dupe": dupe_opt_in}}


func host(port := DEFAULT_PORT) -> void:
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
	is_host = false
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
			print("[link] transport error")
			_finish("transport-error")
			return
		if kind == ENetConnection.EVENT_NONE:
			return
		if kind == ENetConnection.EVENT_CONNECT:
			_peer = ev[1]
			state = "handshake"
			_elapsed = 0.0
			var me := identity()
			print("[link] connected — handshake (we are version %s)" % me["version"])
			_peer.send(CH_CONTROL, JSON.stringify({"t": "hello", "id": me}).to_utf8_buffer(),
				ENetPacketPeer.FLAG_RELIABLE)
		elif kind == ENetConnection.EVENT_DISCONNECT:
			if state == "closing":
				_finish(_close_reason)
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
				_peer.send(CH_CONTROL, JSON.stringify({"t": "accept"}).to_utf8_buffer(),
					ENetPacketPeer.FLAG_RELIABLE)
			_maybe_establish()
		"accept":
			_accepted = true
			_maybe_establish()
		"refuse":
			var why := str(msg.get("reason", "?"))
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
		print("[link] session established (%s) — version %s, content hashes match%s" % [
			"host" if is_host else "join", _remote.get("version", "?"),
			", dupe easter egg ARMED" if session["dupe"] else ""])
		established.emit(session)
