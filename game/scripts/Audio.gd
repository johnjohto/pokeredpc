extends Node
## Game Boy music: synthesizes pokered's channel command data (2 pulse + 1 wave + 1 noise)
## into a looping PCM stream, faithful to audio/engine_1.asm (gh #73):
##
##   - frequency: period = (pitch_table[note] >>arith (octave-1)) with +8 added to the high
##     byte, low 11 bits; pulse hz = 131072/(2048-p), wave hz = 65536/(2048-p) (the wave
##     channel's 32-sample cycle runs at half rate, so ch3 sounds an octave below ch1/2);
##   - timing: frames = (length * note_speed * tempo) / 256 at 60 fps, 8-bit carry per channel;
##   - looping: each channel walks its intro then one loop body (sound_loop 0); the song loops
##     the wav over [max intro end, + lcm of the body lengths] so intros never replay and
##     every channel keeps cycling — pieces with no infinite loop (jingles) play once;
##   - effects: vibrato (delayed ±nibble wobble of the period low byte), toggle_perfect_pitch
##     (+1 period), duty_cycle_pattern (rotates per frame), pitch_slide, the channel-1
##     hardware sweep, the real channel-3 wavetables (incl. the per-bank glitch wave 5), and
##     drum_note playing the real noise-instrument sequences through a Gen-1 LFSR.

const SR := 22050
const FPS := 60.0
const MAX_FRAMES := 15000            # walk cap per channel (250 s): intro + one loop body
const MAX_TOTAL := 15000             # render cap for the whole looped buffer (dungeon3's
                                     # slow tempo-ramped pass runs ~75 s, so two passes fit)
const PITCH := {"C": 0xF82C, "C#": 0xF89D, "D": 0xF907, "D#": 0xF96B, "E": 0xF9CA,
	"F": 0xFA23, "F#": 0xFA77, "G": 0xFAC7, "G#": 0xFB12, "A": 0xFB58, "A#": 0xFB9B, "B": 0xFBDA}
const DUTY := [0.125, 0.25, 0.5, 0.75]

var songs: Dictionary = {}
var map_music: Dictionary = {}
var sfx: Dictionary = {}
var cries: Dictionary = {}
var waves: Array = []                # channel-3 wavetables 0-4 (audio/wave_samples.asm)
var wave5: Dictionary = {}           # the glitch wave-5 bytes per audio bank ("1"/"2"/"3")
var _drums: Array = []               # noise instruments 1-19: their nnote command lists
var _cache: Dictionary = {}          # song key -> AudioStreamWAV
var _sfx_cache: Dictionary = {}      # sfx key -> AudioStreamWAV
var _player: AudioStreamPlayer       # looping music
var _sfx_player: AudioStreamPlayer   # one-shot sfx / cries
var _current := ""
var _pending := {}                   # set of song keys currently being synthesized
var enabled := true


func setup(audio: Dictionary, mm: Dictionary, sf: Dictionary, cr: Dictionary) -> void:
	songs = audio.duplicate()
	waves = songs.get("_waves", [])
	wave5 = songs.get("_wave5", {})
	songs.erase("_waves")
	songs.erase("_wave5")
	map_music = mm
	sfx = sf
	cries = cr
	# drum_note instruments are the first 19 SFX (they're triggered on the noise channel
	# exactly like an SFX; the data is identical across the three banks).
	_drums = [[]]
	for i in range(1, 20):
		var seq: Array = []
		for c in sf.get("noise_instrument%02d" % i, {}).get("channels", [{}])[0].get("cmds", []):
			if str(c[0]) == "nnote":
				seq.append(c)
		_drums.append(seq)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)


## The 11-bit frequency register value for a note (Audio1_CalculateFrequency).
func note_period(pitch: String, octave: int) -> int:
	var v: int = PITCH[pitch]
	if v & 0x8000:
		v -= 0x10000                 # treat as signed for the arithmetic shift
	v = v >> (octave - 1)
	v &= 0xFFFF
	var hi := ((v >> 8) + 8) & 0xFF
	return ((hi << 8) | (v & 0xFF)) & 0x7FF


func note_hz(pitch: String, octave: int) -> float:
	return 131072.0 / float(2048 - note_period(pitch, octave))


func play_map_music(map_label: String) -> void:
	play_song(str(map_music.get(map_label, "")))


func play_song(key: String) -> void:
	if not enabled or key == _current:
		return
	if key == "" or not songs.has(key):
		stop()
		return
	_current = key
	if _cache.has(key):
		_start(key)
	else:
		# Synthesize off the main thread (high priority) so entering a new area never
		# hitches; the previous track keeps playing until the new one is ready.
		_queue_synth(key, true)


## Length of one pass of a song in seconds (intro + one loop body; a jingle's full length).
func song_length(key: String) -> float:
	if not songs.has(key):
		return 0.0
	var song: Dictionary = songs[key]
	var tempo0 := _first_tempo(song)
	var timeline := _tempo_timeline(song, tempo0)
	var frames := 1
	for ch in song["channels"]:
		var s := _seq_channel(ch["cmds"], tempo0, 12, 0, false, int(ch["hw"]), timeline)
		frames = maxi(frames, int(s["frames"]))
	return frames / 60.0


## Pre-synthesize every song in the background so later area/battle changes are instant.
func presynth_all() -> void:
	if not enabled:
		return
	for key in songs:
		_queue_synth(str(key), false)


func _queue_synth(key: String, high: bool) -> void:
	if _cache.has(key) or _pending.has(key):
		return
	_pending[key] = true
	_tasks.append(WorkerThreadPool.add_task(_synth_task.bind(key), high))


var _tasks: Array = []               # in-flight synth task ids


func _exit_tree() -> void:
	# Quitting mid-synthesis would free this node under the worker threads' feet.
	for tid in _tasks:
		WorkerThreadPool.wait_for_task_completion(tid)


func _synth_task(key: String) -> void:
	var wav := _synth(songs[key])
	call_deferred("_on_synth_done", key, wav)


func _on_synth_done(key: String, wav: AudioStreamWAV) -> void:
	_cache[key] = wav
	_pending.erase(key)
	# Keep the PCM cache bounded (gh #44): a few MB per looped song; evicted songs just
	# re-synthesize in the background on the next visit.
	while _cache.size() > 8:
		for k in _cache:
			if k != key and k != _current:
				_cache.erase(k)
				break
	if _current == key:
		_start(key)


func _start(key: String) -> void:
	_player.stream = _cache[key]
	_player.play()


func stop() -> void:
	_current = ""
	if _player:
		_player.stop()


# ---- sequencing ------------------------------------------------------------

## Tempo is global in the GB engine (one channel sets it; the rest inherit): the first
## tempo command found seeds every channel.
func _first_tempo(song: Dictionary) -> int:
	for ch in song["channels"]:
		for c in ch["cmds"]:
			if str(c[0]) == "tempo":
				return int(c[1])
	return 128


## Mid-song tempo changes retime EVERY channel (one wMusicTempo): walk the tempo-carrying
## channel once and build a [frame, tempo] timeline for the others — Silph Co ramps
## 124..1024..160 on ch1 and channels 2-4 must follow. A looping tempo channel repeats its
## body's changes every cycle.
func _tempo_timeline(song: Dictionary, tempo0: int) -> Array:
	for ch in song["channels"]:
		var has := false
		for c in ch["cmds"]:
			if str(c[0]) == "tempo":
				has = true
				break
		if not has:
			continue
		var s := _seq_channel(ch["cmds"], tempo0, 12, 0, false, int(ch["hw"]))
		var tl: Array = s["tempos"]
		if tl.is_empty() or int(tl[0][0]) > 0:
			tl.push_front([0, tempo0])
		if int(s["body"]) > 0:
			var body_ev: Array = []
			for e in tl:
				if int(e[0]) >= int(s["loop_at"]):
					body_ev.append(e)
			if not body_ev.is_empty():
				var k := 1
				while int(s["loop_at"]) + k * int(s["body"]) < MAX_FRAMES:
					for e in body_ev:
						var f2: int = int(e[0]) + k * int(s["body"])
						if f2 < MAX_FRAMES:
							tl.append([f2, int(e[1])])
					k += 1
		return tl
	return [[0, tempo0]]


## Walk a channel's commands, emitting note events with absolute frame times. Walks the
## intro and then ONE body of the infinite loop (sound_loop 0): `loop_at` is the frame of
## the first arrival at the loop command and `body` the frames of one full cycle (0 = the
## channel never loops). `tempo0`/`speed0` are the starting tempo/note-speed (music: song
## tempo / 12; sfx: 256 / 1); `freq_add` is the cry pitch added to each sfx note's period;
## `one_shot` stops at the infinite loop instead of walking its body. A non-empty
## `timeline` ([[frame, tempo], ...]) overrides the channel's own tempo commands — the
## GB's tempo is global, read at each note's start.
func _seq_channel(cmds: Array, tempo0: int, speed0: int, freq_add: int, one_shot: bool,
		hw := 1, timeline: Array = []) -> Dictionary:
	var labels := {}
	for i in cmds.size():
		if cmds[i][0] == "label":
			labels[str(cmds[i][1])] = i
	var tempos: Array = []         # this channel's own tempo commands, as [frame, tempo]
	var t_idx := 0                 # timeline cursor (frame is monotonic)
	var events: Array = []
	var pc := 0
	var frame := 0
	var frac := 0
	var octave := 4
	var speed := speed0
	var vol := 15
	var fade := 0
	var duty := 2
	var duties: Array = []         # duty_cycle_pattern: rotates one step per frame
	var wave_id := 0               # channel 3: note_type's low nibble picks the wavetable
	var vib: Array = []            # [delay, depth, rate] (empty = off)
	var pp := false                # toggle_perfect_pitch: +1 on every note's period
	var slide: Array = []          # pending pitch_slide [len, octave, note] for the next note
	var tempo := tempo0
	var sweep_time := 0            # hardware pitch sweep (pitch_sweep): every time/128 s ...
	var sweep_shift := 0           # ... period +=/-= period >> |shift|; 0 = sweep off
	var call_stack: Array = []
	var loop_left := {}
	var loop_at := -1              # frame of the first arrival at the infinite loop
	var loop_pc := -1
	var body := 0
	var drum_tail: Array = []      # the last drum's noise events (a retrigger cuts them)
	var guard := 0
	while pc < cmds.size() and frame < MAX_FRAMES:
		guard += 1
		if guard > 200000:
			break
		var c: Array = cmds[pc]
		if not timeline.is_empty():
			while t_idx + 1 < timeline.size() and int(timeline[t_idx + 1][0]) <= frame:
				t_idx += 1
			tempo = int(timeline[t_idx][1])
		match str(c[0]):
			"tempo":
				tempos.append([frame, int(c[1])])
				if timeline.is_empty():
					tempo = int(c[1])
			"octave": octave = int(c[1])
			"duty":
				duty = int(c[1])
				duties = []
			"dutypat":
				duties = [int(c[1]), int(c[2]), int(c[3]), int(c[4])]
			"vibrato":
				vib = [int(c[1]), int(c[2]), int(c[3])]
			"ppitch":
				pp = not pp
			"slide":
				slide = [int(c[1]), int(c[2]), str(c[3])]
			"note_type":
				speed = int(c[1])
				vol = int(c[2])
				fade = int(c[3])
				if hw == 3:
					wave_id = int(c[3])    # ch3: the low nibble picks the wave instrument
			"drumspeed": speed = int(c[1])
			"note":
				var fr := _advance(int(c[2]), speed, tempo, frac)
				frac = fr[1]
				var per := note_period(str(c[1]), octave) + (1 if pp else 0)
				if hw == 3:
					events.append({"k": "wave", "f": frame, "n": fr[0], "period": per,
						"level": vol & 3, "wave": wave_id, "vib": vib})
				else:
					var e := {"k": "pulse", "f": frame, "n": fr[0], "period": per,
						"vol": vol, "fade": fade, "vib": vib}
					if duties.is_empty():
						e["duty"] = duty
					else:
						e["duties"] = duties
					if not slide.is_empty():
						e["slide_to"] = note_period(str(slide[2]), int(slide[1])) + (1 if pp else 0)
						slide = []
					events.append(e)
				frame += fr[0]
			"sweep":                               # pitch_sweep: applies to following square notes
				sweep_time = int(c[1])
				var sh := int(c[2])
				sweep_shift = 0 if (sh == 8 or sweep_time == 0) else sh   # 8 = "negative 0" = off
			"snote":                               # sfx square note: direct period (+1 length)
				var fs := _advance(int(c[1]) + 1, speed, tempo, frac)
				frac = fs[1]
				var period: int = clampi(int(c[4]) + freq_add, 1, 2046)
				events.append({"k": "pulse", "f": frame, "n": fs[0],
					"period": period, "vol": int(c[2]), "fade": int(c[3]), "duty": duty,
					"sw_t": sweep_time, "sw_s": sweep_shift})
				frame += fs[0]
			"nnote":                               # sfx noise note (4th arg = the poly register)
				var fn := _advance(int(c[1]) + 1, speed, tempo, frac)
				frac = fn[1]
				events.append({"k": "noise", "f": frame, "n": fn[0],
					"vol": int(c[2]), "fade": int(c[3]), "poly": int(c[4])})
				frame += fn[0]
			"rest":
				var frr := _advance(int(c[1]), speed, tempo, frac)
				frac = frr[1]
				frame += frr[0]
			"drum":
				# drum_note instrument, length: triggers the noise-instrument SFX on the
				# noise channel (its notes advance at speed 1 / tempo 256 = length+1 frames)
				# while this channel waits out the drum_note's own length; a new drum cuts
				# whatever the last one was still playing (Audio1_PlaySound restarts CHAN8).
				var fd := _advance(int(c[2]), speed, tempo, frac)
				frac = fd[1]
				var inst := int(c[1])
				if inst >= 1 and inst < _drums.size():
					for de in drum_tail:
						if int(de["f"]) + int(de["n"]) > frame:
							de["n"] = maxi(0, frame - int(de["f"]))
					drum_tail = []
					var off := 0
					for dn in _drums[inst]:
						var dlen := int(dn[1]) + 1
						var de := {"k": "noise", "f": frame + off, "n": dlen,
							"vol": int(dn[2]), "fade": int(dn[3]), "poly": int(dn[4])}
						events.append(de)
						drum_tail.append(de)
						off += dlen
				frame += fd[0]
			"call":
				call_stack.push_back(pc + 1)
				pc = int(labels.get(str(c[1]), pc))
			"ret":
				if call_stack.is_empty():
					break
				pc = int(call_stack.pop_back()) - 1
			"loop":
				var cnt := int(c[1])
				if cnt == 0:
					if one_shot or not labels.has(str(c[2])):
						break
					if loop_at < 0:                # first arrival: remember it, walk the body
						loop_at = frame
						loop_pc = pc
						pc = int(labels[str(c[2])])
					else:                          # back at the loop: one body walked
						body = frame - loop_at
						break
				else:
					if not loop_left.has(pc):
						loop_left[pc] = cnt
					loop_left[pc] = int(loop_left[pc]) - 1
					if int(loop_left[pc]) > 0:
						pc = int(labels.get(str(c[2]), pc))
					else:
						loop_left.erase(pc)
		pc += 1
	if loop_at >= 0 and body <= 0:                 # the walk cap hit mid-body: treat as one-shot
		loop_at = -1
	return {"events": events, "frames": frame, "loop_at": loop_at, "body": body,
		"tempos": tempos}


## frames for a note = (length * speed * tempo + carry) / 256; returns [frames, new_carry].
func _advance(length: int, speed: int, tempo: int, frac: int) -> Array:
	var acc := frac + length * speed * tempo
	return [acc >> 8, acc & 0xFF]


# ---- synthesis -------------------------------------------------------------

func _synth(song: Dictionary) -> AudioStreamWAV:
	var tempo0 := _first_tempo(song)
	var timeline := _tempo_timeline(song, tempo0)
	var bank := str(song.get("bank", 1))
	var seqs: Array = []
	var has_loop := false
	var loop_start := 0
	var body_max := 0
	var lcm := 1
	for ch in song["channels"]:
		var s := _seq_channel(ch["cmds"], tempo0, 12, 0, false, int(ch["hw"]), timeline)
		s["hw"] = int(ch["hw"])
		seqs.append(s)
		if int(s["body"]) > 0:
			has_loop = true
			loop_start = maxi(loop_start, int(s["loop_at"]))
			body_max = maxi(body_max, int(s["body"]))
			lcm = _lcm(lcm, int(s["body"]))
	var total := 1
	var loop_frame := -1
	if not has_loop:
		for s in seqs:
			total = maxi(total, int(s["frames"]))
	else:
		# The wav loops over [loop_start, loop_start + L): after every channel's own intro
		# (and any one-shot channel's full tail — the title screen's drums cycle under an
		# ended melody), each looping channel is periodic in its own body length, so L =
		# lcm of the bodies tiles all of them seamlessly.
		for s in seqs:
			if int(s["body"]) <= 0:
				loop_start = maxi(loop_start, int(s["frames"]))
		var lim := maxi(1, MAX_TOTAL - loop_start)
		var L := lcm if (lcm <= lim and lcm > 0) else mini(body_max, lim)
		total = loop_start + L
		loop_frame = loop_start
		for s in seqs:
			var b := int(s["body"])
			if b <= 0:
				continue
			var base: Array = []
			for e in s["events"]:
				if int(e["f"]) >= int(s["loop_at"]):
					base.append(e)
			var k := 1
			while int(s["loop_at"]) + k * b < total:
				for e in base:
					var f2: int = int(e["f"]) + k * b
					if f2 < total:
						var e2: Dictionary = (e as Dictionary).duplicate()
						e2["f"] = f2
						s["events"].append(e2)
				k += 1
			if int(s["hw"]) == 4:
				# a drum retrigger cuts whatever still rings — the walk clipped within one
				# pass, but a cycled body's tail can overlap the next cycle's first drum
				s["events"].sort_custom(func(x, y): return int(x["f"]) < int(y["f"]))
				for i in range(s["events"].size() - 1):
					var e: Dictionary = s["events"][i]
					var nf := int(s["events"][i + 1]["f"])
					if int(e["f"]) + int(e["n"]) > nf:
						e["n"] = nf - int(e["f"])
	# resolve each wave event's wavetable (ids 5-8 hit the bank's glitch wave 5)
	for s in seqs:
		for e in s["events"]:
			if str(e["k"]) == "wave":
				var wid := int(e["wave"])
				e["tab"] = waves[wid] if wid < waves.size() else wave5.get(bank, [])
	return _build(seqs, total, loop_frame)


func _synth_sfx(effect: Dictionary, tempo0: int, freq_add: int) -> AudioStreamWAV:
	var seqs: Array = []
	var frames := 1
	for ch in effect["channels"]:
		var s := _seq_channel(ch["cmds"], tempo0, 1, freq_add, true, int(ch["hw"]))
		s["hw"] = int(ch["hw"])
		seqs.append(s)
		frames = maxi(frames, int(s["frames"]))
	return _build(seqs, frames, -1)


func _lcm(a: int, b: int) -> int:
	if a <= 0 or b <= 0:
		return maxi(a, b)
	var x := a
	var y := b
	while y != 0:
		var t := x % y
		x = y
		y = t
	@warning_ignore("integer_division")
	return a / x * b          # x = gcd(a, b) divides a exactly


## Render the event sequences to a 16-bit wav; `loop_frame` >= 0 loops from that frame to
## the end (the Gen-1 sound_loop point), -1 plays one-shot.
func _build(seqs: Array, frames: int, loop_frame: int) -> AudioStreamWAV:
	var total := int(frames / FPS * SR) + 1
	var buf := PackedFloat32Array()
	buf.resize(total)
	for s in seqs:
		_render_channel(s, buf, total)
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = bytes
	if loop_frame >= 0:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = int(loop_frame / FPS * SR)
		wav.loop_end = total
	return wav


func _render_channel(seq: Dictionary, buf: PackedFloat32Array, total: int) -> void:
	var hw: int = seq["hw"]
	var spf := SR / FPS              # samples per frame
	for ev in seq["events"]:
		var start := int(int(ev["f"]) * spf)
		var n := int(int(ev["n"]) * spf)
		if n <= 0 or start >= total:
			continue
		n = mini(n, total - start)
		match str(ev["k"]):
			"noise":
				_render_noise(buf, start, n, int(ev["vol"]), int(ev["fade"]), int(ev.get("poly", 0x51)))
			"wave":
				_render_wave(buf, start, n, ev)
			_:
				if hw != 1 and int(ev.get("sw_t", 0)) != 0:
					ev = ev.duplicate()      # the hardware sweep exists only on channel 1 (rNR10)
					ev["sw_t"] = 0
				_render_pulse(buf, start, n, ev)


## Pulse (square) channel: duty cycle (or a per-frame duty_cycle_pattern rotation), the GB
## volume envelope, vibrato (after `delay` frames, every rate+1 frames the period low byte
## alternates +ceil(depth/2) / -floor(depth/2), saturating — Audio1_ApplyVibrato), an
## optional pitch_slide toward a target period, and (channel 1) the hardware sweep: every
## sw_t/128 s the period moves by ±(period >> |sw_s|); overflow silences the note.
func _render_pulse(buf: PackedFloat32Array, start: int, n: int, ev: Dictionary) -> void:
	var base_per := int(ev.get("period", 0))
	var vol := int(ev.get("vol", 15))
	var fade := int(ev.get("fade", 0))
	var duties: Array = ev.get("duties", [])
	var duty := int(ev.get("duty", 2))
	var vib: Array = ev.get("vib", [])
	var slide_to := int(ev.get("slide_to", -1))
	var sw_t := int(ev.get("sw_t", 0))
	var sw_s := int(ev.get("sw_s", 0))
	var f0 := int(ev.get("f", 0))
	var spf := SR / FPS
	var nframes := maxi(1, int(ceilf(n / spf)))
	# envelope
	var env := float(vol)
	var env_per := absi(fade)                # frames between envelope steps (0 = none)
	var env_dir := -1.0 if fade > 0 else 1.0
	var env_ct := 0
	# vibrato
	var vdelay := 0
	var vup := 0
	var vdown := 0
	var vrate := 0
	# vibrato is skipped entirely while a pitch slide runs (Audio1_ApplyPitchSlide never
	# falls through to the vibrato path)
	if vib.size() == 3 and int(vib[1]) > 0 and slide_to < 0:
		vdelay = int(vib[0])
		vup = (int(vib[1]) >> 1) + (int(vib[1]) & 1)
		vdown = int(vib[1]) >> 1
		vrate = int(vib[2])
	var vctr := vrate
	var vup_phase := false
	var voff := 0                            # current vibrato offset applied to the low byte
	# pitch slide: linear walk to the target period across the note
	var slide_step := 0.0
	var slide_acc := 0.0
	if slide_to >= 0:
		slide_step = float(slide_to - base_per) / float(nframes)
	# hardware sweep
	var sw_samples := float(sw_t) / 128.0 * SR if sw_t > 0 and sw_s != 0 and base_per > 0 else 0.0
	var sw_ct := 0.0
	var cur_per := base_per
	var thr: float = DUTY[clampi(int(duties[f0 % 4]) if not duties.is_empty() else duty, 0, 3)]
	var step := _pstep(cur_per)
	var phase := 0.0
	var next_frame := spf
	var frame := 0
	for i in n:
		if float(i) >= next_frame:           # a new 1/60 s frame began
			next_frame += spf
			frame += 1
			if env_per > 0:
				env_ct += 1
				if env_ct >= env_per:
					env_ct = 0
					env = clampf(env + env_dir, 0.0, 15.0)
			var changed := false
			if slide_step != 0.0:
				slide_acc += slide_step
				changed = true
			if vdelay > 0:
				vdelay -= 1
			elif vrate + vup + vdown > 0:
				if vctr > 0:
					vctr -= 1
				else:
					vctr = vrate
					voff = vup if not vup_phase else -vdown
					vup_phase = not vup_phase
					changed = true
			if not duties.is_empty():
				thr = DUTY[clampi(int(duties[(f0 + frame) % 4]), 0, 3)]
			if changed:
				var p := base_per + int(slide_acc)
				var lo := clampi((p & 0xFF) + voff, 0, 255)   # the wobble saturates the low byte
				cur_per = (p & 0x700) | lo
				step = _pstep(cur_per)
		if sw_samples > 0.0:
			sw_ct += 1.0
			if sw_ct >= sw_samples:
				sw_ct = 0.0
				var d := cur_per >> absi(sw_s)
				cur_per += d if sw_s > 0 else -d
				if cur_per > 2047:
					return               # sweep overflow silences the channel
				cur_per = maxi(cur_per, 0)
				step = _pstep(cur_per)
		var amp := env / 15.0 * 0.22
		buf[start + i] += (amp if phase < thr else -amp)
		phase += step
		if phase >= 1.0:
			phase -= 1.0


func _pstep(period: int) -> float:
	return (131072.0 / float(2048 - clampi(period, 0, 2047))) / SR


## Wave channel: the real 32-nibble wavetable at 65536/(2048-p) Hz (half the pulse rate —
## one cycle spans all 32 samples). Output level 0-3 = mute/100%/50%/25% (nibble >> shift),
## re-centered so the level only scales amplitude. Vibrato as on the pulse channels.
func _render_wave(buf: PackedFloat32Array, start: int, n: int, ev: Dictionary) -> void:
	var tab: Array = ev.get("tab", [])
	var level := int(ev.get("level", 1)) & 3
	if level == 0 or tab.size() < 32:
		return
	var shift: int = [0, 0, 1, 2][level]
	var mean := 0.0
	for v in tab:
		mean += int(v) >> shift
	mean /= 32.0
	var base_per := int(ev.get("period", 0))
	var vib: Array = ev.get("vib", [])
	var vdelay := 0
	var vup := 0
	var vdown := 0
	var vrate := 0
	if vib.size() == 3 and int(vib[1]) > 0:
		vdelay = int(vib[0])
		vup = (int(vib[1]) >> 1) + (int(vib[1]) & 1)
		vdown = int(vib[1]) >> 1
		vrate = int(vib[2])
	var vctr := vrate
	var vup_phase := false
	var spf := SR / FPS
	var next_frame := spf
	var step := (65536.0 / float(2048 - clampi(base_per, 0, 2047))) / SR
	var phase := 0.0
	for i in n:
		if float(i) >= next_frame:
			next_frame += spf
			if vdelay > 0:
				vdelay -= 1
			elif vrate + vup + vdown > 0:
				if vctr > 0:
					vctr -= 1
				else:
					vctr = vrate
					var voff := vup if not vup_phase else -vdown
					vup_phase = not vup_phase
					var lo := clampi((base_per & 0xFF) + voff, 0, 255)
					var p := (base_per & 0x700) | lo
					step = (65536.0 / float(2048 - clampi(p, 0, 2047))) / SR
		var nib := int(tab[int(phase * 32.0) & 31]) >> shift
		buf[start + i] += (float(nib) - mean) / 7.5 * 0.22
		phase += step
		if phase >= 1.0:
			phase -= 1.0


## Noise: the Gen-1 LFSR clocked by the poly register (rAUD4POLY: shift clock s in the high
## nibble, 7-bit width on bit 3, divisor r in the low 3 bits -> 524288 / r' / 2^(s+1) Hz),
## with the GB volume envelope. Drums and SFX get their real pitch/timbre from it.
func _render_noise(buf: PackedFloat32Array, start: int, n: int, vol: int, fade: int, poly: int) -> void:
	var s := (poly >> 4) & 0xF
	var width7 := (poly & 0x8) != 0
	var r := poly & 0x7
	var freq := 524288.0 / (0.5 if r == 0 else float(r)) / pow(2.0, s + 1)
	var tick := freq / SR
	var lfsr := 0x7FFF
	var out := 1.0
	var env := float(vol)
	var env_per := absi(fade)
	var env_dir := -1.0 if fade > 0 else 1.0
	var env_ct := 0
	var spf := SR / FPS
	var next_frame := spf
	var acc := 0.0
	for i in n:
		if float(i) >= next_frame:
			next_frame += spf
			if env_per > 0:
				env_ct += 1
				if env_ct >= env_per:
					env_ct = 0
					env = clampf(env + env_dir, 0.0, 15.0)
		acc += tick
		while acc >= 1.0:
			acc -= 1.0
			var bit := (lfsr ^ (lfsr >> 1)) & 1
			lfsr = (lfsr >> 1) | (bit << 14)
			if width7:
				lfsr = (lfsr & ~(1 << 6)) | (bit << 6)
			out = -1.0 if (lfsr & 1) != 0 else 1.0
		buf[start + i] += out * (env / 15.0) * 0.18


# ---- sfx / cries -----------------------------------------------------------

var log_sfx := false              # tests: record every play_sfx key (even when audio is disabled)
var sfx_log: Array = []


func play_sfx(key: String, pitch := 0) -> void:
	if log_sfx:
		sfx_log.append(key)
	if not enabled or not sfx.has(key):
		return
	var ck := key if pitch == 0 else "%s@%d" % [key, pitch]   # cache per (key, pitch)
	if not _sfx_cache.has(ck):
		_sfx_cache[ck] = _synth_sfx(sfx[key], 256, pitch)
	_sfx_player.stream = _sfx_cache[ck]
	_sfx_player.play()


func play_cry(species: String) -> void:
	if not enabled or not cries.has(species):
		return
	var cd: Dictionary = cries[species]
	var key: String = "cry:" + species
	if not _sfx_cache.has(key):
		if not sfx.has(str(cd["cry"])):
			return
		_sfx_cache[key] = _synth_sfx(sfx[str(cd["cry"])], 0x80 + int(cd["length"]), int(cd["pitch"]))
	_sfx_player.stream = _sfx_cache[key]
	_sfx_player.play()
