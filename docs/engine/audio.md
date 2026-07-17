# Engine: audio (Game Boy music synthesis)

pokered's music is **not** audio files — it's Game Boy sound-chip command data driving 4 APU
channels (2 pulse/square, 1 wave, 1 noise). True to the data-driven approach, we **extract the
song commands** and **synthesize** the channels natively.

## Extracted data (`build_audio`)

- `assets/audio.json` — `song key -> {channels: [{hw, cmds:[...]}], bank}`. `hw` is the GB
  channel (1/2 = pulse, 3 = wave, 4 = noise). Commands are compact arrays: `["note","B",4]`,
  `["rest",2]`, `["octave",3]`, `["note_type",speed,vol,fade]` (on ch3 the fade nibble picks
  the **wave instrument**), `["duty",n]`, `["dutypat",a,b,c,d]`, `["tempo",n]`,
  `["drum",id,len]`, the effects `["vibrato",delay,depth,rate]` / `["ppitch"]` /
  `["slide",len,oct,note]` / `["sweep",time,shift]`, and the control ops
  `["loop",count,label]` / `["call",label]` / `["ret"]` / `["label",name]`. Parsed from
  `audio/headers/*` (song→channel labels + the song's audio **bank**) + `audio/music/*.asm`;
  `sound_call`s into another channel's block (Music_FinalBattle_Ch1 borrows Ch2's `.sub2`)
  are inlined, since per-channel label scopes can't see across blocks (gh #73).
- `audio.json` also carries `_waves` (the five real channel-3 wavetables, 32 nibbles each,
  from `audio/wave_samples.asm`) and `_wave5` — the **glitch wave 5**: ids 5-8 point at a
  definition with no data, so the hardware plays whatever ROM bytes follow, different per
  audio bank; the asm documents each bank's effective bytes and those are extracted per bank
  (Lavender Town's eerie lead is bank 1's garbage).
- `assets/map_music.json` — `MapLabel -> song key`, from `data/maps/songs.asm`.

## Synthesis (`Audio.gd`)

Faithful to `engine_1.asm` (audited for gh #73):

- **Frequency**: `period = (pitch_table[note] >>arith (octave-1))`, add `8` to the high byte,
  take the low 11 bits; pulse `hz = 131072 / (2048 - period)` but wave
  `hz = 65536 / (2048 - period)` — channel 3's 32-sample cycle runs at half rate, so the
  same written octave sounds **an octave below** the pulse channels (basslines were an
  octave high before the audit). (Verified: A/oct3 = 439.8 Hz ≈ A4.)
- **Duration**: `frames = (length × note_speed × tempo) / 256` at 60 fps, carrying the 8-bit
  remainder per channel (`note_type` sets speed/volume/fade; `tempo` is the 16-bit divisor).

### Looping (gh #73)

`_seq_channel` walks each channel's **intro and then one body** of its infinite
`sound_loop 0` (expanding finite loops and `call`/`ret`), reporting `loop_at` (the frame of
the first arrival at the loop command) and `body` (the frames of one full cycle). `_synth`
then loops the wav over `[max(loop_at, one-shot channel ends), + lcm(bodies)]`, cycling each
looping channel's body events to fill the region — intros never replay, channels of unequal
lengths keep cycling in phase (the title screen's drums roll on under the ended melody), and
pieces with **no** infinite loop (the healed jingle, the intro battle) play once and stop.

### Channels & effects

- **Pulse**: square wave with the duty cycle (12.5/25/50/75 %) or a `duty_cycle_pattern`
  (rotates one step per frame), a GB volume envelope (`fade` steps the volume toward 0/15),
  **vibrato** (after `delay` frames, every `rate+1` frames the period low byte alternates
  `+⌈depth/2⌉ / -⌊depth/2⌋`, saturating — `Audio1_ApplyVibrato`), **toggle_perfect_pitch**
  (+1 on every note's period), **pitch_slide** toward its target note, and (channel 1 only)
  the hardware `pitch_sweep`.
- **Wave**: the real 32-nibble wavetable named by `note_type`'s third arg — waves 0-4 plus
  the per-bank glitch wave 5 — at the half-rate frequency; output level 0-3 =
  mute/100%/50%/25% (nibble shifts), vibrato as on pulse.
- **Noise**: a Gen-1 **LFSR** clocked by the real poly register (`shift`/`width`/`divisor` →
  `524288 / r / 2^(s+1)` Hz, 15- or 7-bit feedback), so hats/snares/kicks differ. Music
  `drum_note id, len` triggers the real **noise instrument** (ids 1-19, the first SFX of
  each bank — identical across banks): its `noise_note` run plays out at speed 1/tempo 256
  while the channel waits out the drum's own length, and a retrigger cuts the previous drum,
  exactly as `Audio1_PlaySound` restarts CHAN8.

The mix is packed to a 16-bit `AudioStreamWAV` (loop points as above), cached per song, and
played on an `AudioStreamPlayer`. Synthesis is ~1 s per song (one-time, on first play).
Verified by `--audiotest` (correct Hz, non-silent, loop modes/points per song shape) which
also writes listen artifacts (`pallettown/lavender/gym/titlescreen/finalbattle.wav`).

> Tempo is **global** in the GB engine (only one channel sets it; the rest inherit), so the
> synth scans the song for the first `tempo` and seeds every channel with it.

## Sound effects + cries

`build_sfx` extracts `audio/sfx/*.asm` into `assets/sfx.json` (151 effects) from **both** SFX
banks: `sfxheaders1` (overworld) and `sfxheaders2` (which holds the battle SFX — damage, the two
effectiveness stings, faint, ball toss/poof, run, level-up, caught-mon). Engine 1 wins on shared
names. SFX channels 5–8 map to the same 1–4 hardware. SFX use `square_note`/`noise_note` with a
**direct GB period** rather than note+octave, and (no `note_type`) a default note-speed of 1 at
`SfxTempo = 256`. The note length is the value `+ 1` (the engine increments every length).

`build_cries` reads `data/pokemon/cries.asm` into `assets/cries.json` (`species ->
{cry, pitch, length}`, 151 mons). A cry is its base SFX with two per-species modifiers applied
exactly as `engine_1.asm` does: **`pitch` is added to every note's period** (higher = squeakier)
and **`length` sets `SfxTempo = 0x80 + length`** (smaller = faster/shorter). Cries and SFX play
one-shot on a second `AudioStreamPlayer`.

## Wiring

- **Overworld**: `load_world` calls `audio.play_map_music(center_label)` (no-op if already
  playing, so it doesn't restart when crossing connections within a region).
- **Battle**: `PlayBattleMusic`'s picks — `wildbattle`; `trainerbattle`; `gymleaderbattle`
  for the 8 gym-leader fights (Giovanni only in his gym) **and Lance**; `finalbattle` for
  the Champion (OPP_RIVAL3). The enemy **cry** plays as it appears (`Battle._set_enemy`);
  map music resumes after the battle. Per-action SFX are cued as queue
  markers (`{"sfx": key}`) so they fire in sync with their message: the hit sting by effectiveness
  (`damage` / `super_effective` / `not_very_effective`), `faint_fall`, `level_up`, `ball_toss` +
  `caught_mon`, and `run`. Verified by `--sfxtest`.
- **Menu**: the A-press blip (`press_ab`) on a menu selection.
- All synthesis is **disabled during `--test` runs** (`audio.enabled`) so headless tests stay
  fast. Verified by `--audiotest` (music + sfx + cry; writes `pallettown.wav` / `cry_charmander.wav`).

Song synthesis runs on a **worker thread** (`WorkerThreadPool`), and the result is played via
`call_deferred` once ready — entering a new area never hitches the main thread, and the previous
track keeps playing until the new one is built. At startup `presynth_all()` queues **every** song
to be built in the background (the current map's is requested first, at high priority); on a
typical machine the current track is ready in ~0.25 s and all 45 are cached within ~2.2 s, after
which every area/battle change is instant (cache hit). `play_map_music` is keyed by the **real map
labels** (built in `build_maps` from `const_to_label`), so interior maps resolve correctly:
e.g. Red's house keeps the Pallet Town theme, gyms play the gym theme, marts/Centers their own.

## Not yet done

- The low-HP alarm and the stat-up/down jingles are not yet wired. Stereo panning and the
  master `volume` command are ignored (songs keep them at 7,7). The pitch-slide walks
  linearly over the note rather than pokered's per-frame fraction stepping, and the
  vibrato rate counter/direction reset per note (on hardware only the delay does — a
  phase nuance). If a song's channel bodies didn't divide evenly (lcm past the
  render cap) the loop would fall back to the longest body and seam once per cycle — no
  extracted song hits this.
