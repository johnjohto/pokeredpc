extends Control
## Boot sequence, following pokered's splash.asm / intro.asm / title.asm (order, layout,
## choreography, timing, and sounds):
##   copyright (180 frames) -> letterboxed GAME FREAK splash (64 empty frames, then the
##   shooting-star SFX + logo + big star, the logo flash, falling small stars) -> the
##   Gengar-vs-Nidorino fight (hip/hop/raise/crash/lunge cues, intro-battle music) -> title
##   (the logo bounces down with its crash, a beat, the version whooshes in, then the music
##   starts and the TitleMons cycle; the shown mon cries when the game starts).
## Each phase emits phase_changed (Main sets/stops the music; this screen plays its own SFX
## and starts the title track). A keypress skips ahead; on the title it starts the game.

signal started
signal clear_save            # Up+Select+B held as the title is dismissed (title.asm)
signal phase_changed(p: String)

const DARK := Color(0.133, 0.188, 0.224)
const LIGHT := Color(0.918, 0.984, 0.808)
const GLYPH := 8
const NEXT := {"copyright": "gamefreak", "gamefreak": "battle", "battle": "title"}
# The boot copyright tilemap (title.asm). Tiles $60-$72 come from copyright_strip, $73-$7B from
# the GAME FREAK wordmark; $7F is a space. "©'95'96'98" packs each year into one condensed tile.
const CR_ROWS := [
	[0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x7F, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A],
	[0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x7F, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x71, 0x72],
	[0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x7F, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B],
]
# Title bottom copyright: same as CR_ROWS[2] but with no space, so '98 butts against GAME FREAK inc.
const TITLE_CR := [0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B]
# Fight choreography from intro.asm's PlayIntroScene. ["anim", index1-7, nidorino_frame],
# ["wait", game_frames], ["pose", gengar_frame], ["gengar", dx_px], ["sfx", key] (the sound
# plays with whatever the next step draws).
const SEQ := [
	["sfx", "intro_hip"], ["anim", 1, 0], ["sfx", "intro_hop"], ["anim", 2, 0], ["wait", 10],
	["sfx", "intro_hip"], ["anim", 1, 0], ["sfx", "intro_hop"], ["anim", 2, 0], ["wait", 30],
	["pose", 1], ["sfx", "intro_raise"], ["gengar", -8], ["wait", 30],
	["pose", 2], ["sfx", "intro_crash"], ["gengar", 16], ["sfx", "intro_hip"], ["anim", 3, 1], ["wait", 30],
	["gengar", -8], ["pose", 0], ["wait", 60],
	["sfx", "intro_hip"], ["anim", 4, 0], ["sfx", "intro_hop"], ["anim", 5, 0], ["wait", 20],
	["anim", 6, 1], ["wait", 30],
	["sfx", "intro_lunge"], ["anim", 7, 2], ["wait", 24],
]
# The four waves of four falling small stars (title.asm SmallStarsWaveNCoords; X - OAM offset).
const STAR_WAVES := [[40, 56, 80, 112], [48, 64, 88, 104], [44, 68, 76, 92], [52, 84, 100, 108]]
# Pokémon-logo bounce-in (title.asm .TitleScreenPokemonLogoYScrolls): [scy_delta, repeats].
const LOGO_BOUNCE := [[-4, 16], [3, 4], [-3, 4], [2, 2], [-2, 2], [1, 2], [-1, 2]]

var main                          # Main: audio for the intro SFX / title music
var font_tex: Texture2D
var font_cols: int
var charmap: Dictionary
var version := ""                # build version, shown small on the title (from project.godot)
var logo: Texture2D
var gf_logo: Texture2D
var gf_text: Texture2D
var gf_game: Texture2D
var gf_freak: Texture2D
var star: Texture2D
var star_upper: Texture2D         # the star tile without its blinking lower-left mini star
var bigstar: Texture2D
var version_tex: Texture2D        # the Version_GFX graphic ("Red Version")
var logo_y: Array = []           # per-frame Pokémon-logo Y during the title bounce-in
var player: Texture2D
var ball: Texture2D               # the Poké Ball in the trainer's hand (hops on mon slide-out)
var copyright_strip: Texture2D
var nidorino: Array = []
var gengar: Array = []
var title_mons: Array = []
var intro_anims: Array = []
var timeline: Array = []         # per game-frame fight state {nx, ny, nf, gp, gx}
var _battle_dur := 10.0

var phase := "copyright"
var t := 0.0
var _blink := true
var _mon_idx := 0
var _mon_tex: Texture2D
var _mon_timer := 0.0
var _fired := {}                  # per-phase one-shot cues already played (keyed by name)
var _last_fi := -1                # last fight-timeline frame played (for its sfx cues)
var _crash_i := 0                 # logo_y index where the bounce's -3 impact begins (crash sfx)
const MON_CYCLE := 3.9            # per title mon: slide in (R), hold ~3.3s (200 frames), slide out (L)
const MON_SLIDE := 0.3           # slide-in / slide-out duration (fast, like TitleScroll)
# Splash beats (PlayShootingStar/AnimateShootingStar): 64 empty letterboxed frames; the star
# sound + logo + big star (40 frames of 4 px diagonally, from OAM (160,0) = screen (152,-16)
# until off the bottom); the logo flash (3 palette rotations, 10 frames each); the falling
# small stars; and a 40-frame hold before the fight.
const SPLASH_STAR := 64.0 / 60.0
const SPLASH_FLASH := SPLASH_STAR + 40.0 / 60.0
const SPLASH_FALL := SPLASH_FLASH + 30.0 / 60.0
const SPLASH_DUR := SPLASH_FALL + 144.0 / 60.0 + 40.0 / 60.0
# Title beats: the logo bounce (~32 frames), a 36-frame beat, the version whoosh (36 frames at
# 4 px/frame), then the title music starts (DisplayTitleScreen).
const TITLE_VERSION := 32.0 / 60.0 + 36.0 / 60.0
const TITLE_MUSIC := TITLE_VERSION + 36.0 / 60.0


func setup(tex: Texture2D, cols: int, cmap: Dictionary) -> void:
	font_tex = tex
	font_cols = cols
	charmap = cmap
	version = str(ProjectSettings.get_setting("application/config/version", ""))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)
	logo = load("res://assets/title/pokemon_logo.png")
	gf_logo = load("res://assets/title/gamefreak_logo.png")
	gf_text = load("res://assets/title/gamefreak_inc.png")
	gf_game = load("res://assets/title/gamefreak_game.png")
	gf_freak = load("res://assets/title/gamefreak_freak.png")
	star = load("res://assets/title/star.png")
	star_upper = load("res://assets/title/star_upper.png")
	bigstar = load("res://assets/title/bigstar.png")
	player = load("res://assets/title/player.png")
	ball = load("res://assets/title/ball.png")
	version_tex = load("res://assets/title/red_version.png")
	copyright_strip = load("res://assets/title/copyright_strip.png")
	nidorino = [load("res://assets/title/nidorino_1.png"),
		load("res://assets/title/nidorino_2.png"), load("res://assets/title/nidorino_3.png")]
	gengar = [load("res://assets/title/gengar_0.png"),
		load("res://assets/title/gengar_1.png"), load("res://assets/title/gengar_2.png")]
	var f := FileAccess.open("res://assets/title_mons.json", FileAccess.READ)
	title_mons = JSON.parse_string(f.get_as_text())
	var fi := FileAccess.open("res://assets/title_intro.json", FileAccess.READ)
	intro_anims = JSON.parse_string(fi.get_as_text())
	_build_timeline()
	visible = false


## Expand the choreography script into a per-game-frame state list (frame-accurate to intro.asm).
func _build_timeline() -> void:
	timeline = []
	var nx := 0; var ny := 0; var nf := 0; var gp := 0; var gx := 0.0
	var pending_sfx := ""
	# Entrance (MOVE_NIDORINO_RIGHT): Nidorino slides in from the left, 2 px per 2 frames for
	# 40 moves = 80 game-frames (IntroMoveMon); Gengar arrives with the scene scroll.
	for k in 80:
		var e := k / 79.0
		timeline.append({"nx": int((e - 1.0) * 84), "ny": 0, "nf": 0, "gp": 0, "gx": (1.0 - e) * 90.0})
	for step in SEQ:
		var before := timeline.size()
		match str(step[0]):
			"sfx":
				pending_sfx = str(step[1])
			"anim":
				nf = int(step[2])
				for row in intro_anims[int(step[1]) - 1]:
					ny += int(row[0]); nx += int(row[1])      # cumulative deltas
					for k in 5:                                # 5 game-frames per anim frame
						timeline.append({"nx": nx, "ny": ny, "nf": nf, "gp": gp, "gx": gx})
			"wait":
				for k in int(step[1]):
					timeline.append({"nx": nx, "ny": ny, "nf": nf, "gp": gp, "gx": gx})
			"pose":
				gp = int(step[1])
			"gengar":
				for k in absi(int(step[1])):                   # 2 px per 2 frames (IntroMoveMon)
					gx += signf(float(step[1]))
					timeline.append({"nx": nx, "ny": ny, "nf": nf, "gp": gp, "gx": gx})
		if pending_sfx != "" and timeline.size() > before:     # the cue plays with the next step
			timeline[before]["sfx"] = pending_sfx
			pending_sfx = ""
	_battle_dur = timeline.size() / 60.0 + 0.3
	# Logo bounce-in: screen Y = (final 6) when scy = -64; starts 64px above and drops + bounces.
	# The impact sound plays as the -3 rebound begins (.bouncePokemonLogoLoop).
	logo_y = [-58]
	_crash_i = 0
	var scy := 0
	for b in LOGO_BOUNCE:
		if int(b[0]) == -3 and _crash_i == 0:
			_crash_i = logo_y.size()
		for k in int(b[1]):
			scy += int(b[0])
			logo_y.append(-58 - scy)


func show_title() -> void:
	visible = true
	_goto("copyright")


## Straight to the title phase (B on the main menu returns HERE, not through the boot —
## MainMenu .pressedB -> DisplayTitleScreen).
func show_title_only() -> void:
	visible = true
	_goto("title")


func _goto(p: String) -> void:
	phase = p
	t = 0.0
	_fired = {}
	_last_fi = -1
	if p == "title":
		_mon_idx = 0                  # Charmander (the Red starter) first, then cycle;
		_load_mon()                   # it's already in place when the title appears
		_mon_timer = MON_SLIDE
	phase_changed.emit(p)
	queue_redraw()


func _load_mon() -> void:
	_mon_tex = load("res://assets/pokemon/front/%s.png" % str(title_mons[_mon_idx]))


## The species currently on the title (its cry plays when the game starts, DisplayTitleScreen).
func current_mon() -> String:
	return str(title_mons[_mon_idx])


func _sfx(key: String) -> void:
	if main and main.audio:
		main.audio.play_sfx(key)


## One-shot cue: true the first time t passes `at` in the current phase.
func _cue(at: float, key: String) -> bool:
	if t >= at and not _fired.has(key):
		_fired[key] = true
		return true
	return false


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	if phase == "gamefreak":
		if _cue(SPLASH_STAR, "star"):
			_sfx("shooting_star")
	elif phase == "battle":
		# Play the fight cues (hip/hop/raise/crash/lunge) as their timeline frames pass.
		var fi: int = clampi(int(t / _battle_dur * timeline.size()), 0, timeline.size() - 1)
		while _last_fi < fi:
			_last_fi += 1
			if timeline[_last_fi].has("sfx"):
				_sfx(str(timeline[_last_fi]["sfx"]))
	if phase == "title":
		_blink = int(t * 2.0) % 2 == 0
		if _cue(float(_crash_i) / 60.0, "crash"):
			_sfx("intro_crash")                        # the logo's bounce impact
		if _cue(TITLE_VERSION, "whoosh"):
			_sfx("intro_whoosh")                       # the version graphic whooshes in
		if _cue(TITLE_MUSIC, "music") and main and main.audio:
			main.audio.play_song("titlescreen")        # the music starts after the version scroll
		_mon_timer += delta
		if _mon_timer >= MON_CYCLE:
			_mon_timer -= MON_CYCLE
			# Pick a random mon (different from the current one), like TitleScreenPickNewMon.
			var idx := _mon_idx
			while idx == _mon_idx:
				idx = randi() % title_mons.size()
			_mon_idx = idx
			_load_mon()
	else:
		var dur: float = _battle_dur if phase == "battle" else (3.0 if phase == "copyright" else SPLASH_DUR)
		if t >= dur:
			_goto(str(NEXT[phase]))
	queue_redraw()


func handle_input() -> void:
	if Input.is_action_just_pressed("ui_accept"):
		if phase == "title":
			# Up+Select+B held while dismissing the title -> the clear-save dialogue
			# (title.asm: `and PAD_UP | PAD_SELECT | PAD_B` on hJoyHeld).
			if Input.is_action_pressed("ui_up") and Input.is_action_pressed("p_select") \
					and Input.is_action_pressed("ui_cancel"):
				clear_save.emit()
			else:
				started.emit()
		else:
			_goto("title")


func _draw() -> void:
	draw_rect(Rect2(0, 0, 160, 144), LIGHT)
	match phase:
		"copyright": _draw_copyright()
		"gamefreak": _draw_gamefreak()
		"battle": _draw_battle()
		"title": _draw_title()
	if phase == "gamefreak" or phase == "battle":     # letterbox bars over the sprites (clip them)
		draw_rect(Rect2(0, 0, 160, 32), DARK)
		draw_rect(Rect2(0, 112, 160, 32), DARK)
	if phase == "gamefreak":
		_draw_big_star()                              # no OAM_PRIO: the star flies over the bars


func _draw_copyright() -> void:
	for r in 3:
		_cr_row(CR_ROWS[r], 12.0, 56.0 + r * 16.0)


## Draw one copyright tilemap row from the condensed tiles (copyright_strip + GAME FREAK wordmark).
func _cr_row(row: Array, x0: float, y: float) -> void:
	var x := x0
	for id in row:
		_cr_tile(id, x, y)
		x += GLYPH


## Draw a single condensed copyright/wordmark tile (0x60-0x72 from copyright_strip, 0x73+ from gf_text).
func _cr_tile(id: int, x: float, y: float) -> void:
	if id == 0x7F:
		return
	var tex: Texture2D = copyright_strip if id <= 0x72 else gf_text
	var idx: int = id - (0x60 if id <= 0x72 else 0x73)
	draw_texture_rect_region(tex, Rect2(x, y, GLYPH, GLYPH), Rect2(idx * GLYPH, 0, GLYPH, GLYPH))


func _draw_gamefreak() -> void:
	# PlayShootingStar's beats: 64 empty letterboxed frames, then the logo appears with the star
	# sound as the big star streaks across it, the logo flashes, and the small stars fall.
	# The flash is 3 palette rotations at 10-frame steps (the logo blinks at that cadence).
	var flashing := t >= SPLASH_FLASH and t < SPLASH_FLASH + 30.0 / 60.0 \
			and int((t - SPLASH_FLASH) * 6.0) % 2 == 0
	if t >= SPLASH_STAR and not flashing:
		# Exact GameFreakLogoOAMData placement: the 16x24 figure at (72,56); "GAME" (cols 6-9)
		# and "FREAK" (cols 11-15) on the row below it at y 80 (col 10 is a blank spacer tile).
		draw_texture(gf_logo, Vector2(72, 56))
		draw_texture(gf_game, Vector2(40, 80))
		draw_texture(gf_freak, Vector2(80, 80))
	# Small stars (SmallStarsWave1-4 + MoveDownSmallStars): a wave of four enters at screen
	# y 88 every 24 frames; every star falls 1 px per 3 frames for the 6 wave-cycles, and the
	# tile's lower-left mini star blinks with each 3-frame step (the rOBP1 toggle). They carry
	# OAM_PRIO, so they vanish under the bottom letterbox bar (drawn after us).
	var ff := (t - SPLASH_FALL) * 60.0                    # frames since the fall began
	if ff > 0.0 and ff < 144.0:
		var tex: Texture2D = star if int(ff / 3.0) % 2 == 0 else star_upper
		for w in 4:
			var wf := ff - w * 24.0
			if wf > 0.0:
				var sy := 88.0 + floorf(wf / 3.0)
				if sy < 112.0:
					for sx in STAR_WAVES[w]:
						draw_texture(tex, Vector2(sx, sy))


## The big 16x16 star: from screen (152,-16), exactly (-4,+4) px per frame — a 45-degree
## diagonal across the whole screen, off the bottom after 40 frames. Its OAM entries carry no
## priority flag, so it flies OVER the letterbox bars (drawn separately, after them).
func _draw_big_star() -> void:
	var k := (t - SPLASH_STAR) * 60.0
	if k > 0.0 and k < 40.0:
		draw_texture(bigstar, Vector2(152.0 - 4.0 * k, -16.0 + 4.0 * k))


func _draw_battle() -> void:
	# Frame-accurate intro.asm choreography (Gengar left, Nidorino right), stretched to fill the
	# whole introbattle track so it ends exactly with the music. Positions match pokered: Gengar
	# at tile (13,7) scrolled to x24; Nidorino's OAM rests at x72, just overlapping Gengar.
	var fi: int = clampi(int(t / _battle_dur * timeline.size()), 0, timeline.size() - 1)
	var s: Dictionary = timeline[fi]
	# Nidorino (OAM) is drawn first so it slides BEHIND Gengar's opaque silhouette (Gengar is the
	# foreground mon, seen from behind). Bottoms rest at the bottom bar; Nidorino dips just under it.
	draw_texture(nidorino[int(s["nf"])], Vector2(72 + int(s["nx"]), 67 + int(s["ny"])))
	draw_texture(gengar[int(s["gp"])], Vector2(24 + float(s["gx"]), 56))
	# Final hit -> white flash, then fade the whole screen to white before the title.
	var fade := (t - (_battle_dur - 0.6)) / 0.6
	if fade > 0.0:
		draw_rect(Rect2(0, 0, 160, 144), Color(1, 1, 1, clampf(fade, 0.0, 1.0)))


func _draw_title() -> void:
	# Cycling mon (the back-most layer): slides in from the right (fast, easing out), holds, then
	# slides out to the left, behind the trainer. Source positions: mon 56x56 at (40,80), its
	# bottom-right overlapping the trainer's bottom-left; both bottoms at y136.
	if _mon_tex:
		# Variable-size front sprites: bottom anchored to the copyright top (y136) and centred in the
		# 7x7 mon box (x40-96, centre 68) so the big ones fill it and small ones sit centred, not
		# shoved right against the trainer.
		var rest := 68.0 - _mon_tex.get_width() / 2.0
		var mx := rest
		if _mon_timer < MON_SLIDE:                             # slide in from the right (ease out)
			var p := _mon_timer / MON_SLIDE
			mx = lerpf(176.0, rest, 1.0 - (1.0 - p) * (1.0 - p))
		elif _mon_timer >= MON_CYCLE - MON_SLIDE:              # slide out to the left (ease in)
			var p := (_mon_timer - (MON_CYCLE - MON_SLIDE)) / MON_SLIDE
			mx = lerpf(rest, -float(_mon_tex.get_width()), p * p)
		draw_texture(_mon_tex, Vector2(mx, 136 - _mon_tex.get_height()))
	# Red trainer (over the mon), holding the Poké Ball which hops when a starter slides out.
	draw_texture(player, Vector2(82, 80))
	var by := 102.0
	if _mon_timer >= MON_CYCLE - MON_SLIDE and _mon_idx < 3:
		var hp := (_mon_timer - (MON_CYCLE - MON_SLIDE)) / MON_SLIDE
		by -= sin(hp * PI) * 5.0
	draw_texture(ball, Vector2(82, by))
	# Pokémon logo drops in from the top and bounces (title.asm SCY bounce pattern).
	var li: int = clampi(int(t * 60.0), 0, logo_y.size() - 1)
	draw_texture(logo, Vector2(16, logo_y[li]))
	# Version graphic ("Red Version") whooshes in from the right after a 36-frame beat,
	# 4 px/frame (ScrollTitleScreenGameVersion), resting just right of centre.
	if t >= TITLE_VERSION:
		var vx := lerpf(176.0, 89.0 - version_tex.get_width() / 2.0,
			clampf((t - TITLE_VERSION) / 0.6, 0.0, 1.0))
		draw_texture(version_tex, Vector2(vx, 64))
	_cr_row(TITLE_CR, 16.0, 136.0)          # bottom copyright (©'95.'96.'98GAME FREAK inc.)


func _center(s: String, y: float) -> void:
	_text(s, 80.0 - s.length() * GLYPH / 2.0, y)


func _text(s: String, x0: float, y: float) -> void:
	var x := x0
	for ch in s:
		if ch != " " and charmap.has(ch):
			var ti: int = charmap[ch]
			var src := Rect2((ti % font_cols) * GLYPH, (ti / font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH
