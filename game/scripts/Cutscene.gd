extends Control
## Cutscene runner: await-based primitives for scripted story sequences (Oak's speech, the Pallet
## Town walk to the lab, the starter selection). Lives on the ui layer above the world so it can
## draw the intro pic + a white fade overlay. Scripts are written as `await`-driven coroutines.

const LIGHT := Color(0.918, 0.984, 0.808)   # GB lightest shade (speech background / fade target)
const DARK := Color(0.133, 0.188, 0.224)    # GB darkest shade (the evolution silhouette)

const GLYPH := 8

var main
var _pic: Texture2D                 # intro pic (Oak / Nidorino / Red / rival); covers the world
var _pic_pos := Vector2(52, 24)
var _pic_sil := false               # draw _pic as a black silhouette (PAL_BLACK, the evolution flicker)
var _fade := 0.0                    # white overlay alpha 0..1
var _in_credits := false            # the end-credits roll is drawing (letterbox + band)
var _credit_page := {}              # the current page dict: {lines:[[off,str]...], fade, mon, copyright}
var _credit_mon: Texture2D          # a mon front sprite scrolling by as a black silhouette
var _credit_mon_x := 0.0
var _credit_mon_y := 48.0           # 48 + the 7×7 bottom-align pad for small pics (gh #183)
var _credit_end := false            # the final THE END screen
var _the_end_tex: Texture2D         # the 5x2-tile THE END letter sheet (credits_the_end.png)
var _cr_strip: Texture2D            # © / Nintendo / Creatures tiles ($60-$72), lazy-loaded
var _cr_gf: Texture2D               # GAME FREAK wordmark tiles ($73-$7B)
# The © page rows (title.asm CopyrightTextString, drawn at hlcoord 2,7) — identical to
# TitleScreen.CR_ROWS; kept local so the credits render stands alone. $7F = a blank tile.
const COPYRIGHT_ROWS := [
	[0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x7F, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A],
	[0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x7F, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x71, 0x72],
	[0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x7F, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B],
]
# THE END letters (TheEndTextString "T H E  E N D"): [sheet_col, screen_tile_col], each a top+
# bottom tile at rows 8/9. E (sheet col 2) is reused for both words.
const THE_END_LAYOUT := [[0, 4], [1, 6], [2, 8], [2, 11], [3, 13], [4, 15]]
var _anne := {}                     # S.S. Anne departure: band/water/smoke textures, x, puffs
var _font_tex: Texture2D
var _font_cols: int
var _charmap: Dictionary


func setup(m, ftex: Texture2D = null, cols := 0, cmap := {}) -> void:
	main = m
	_font_tex = ftex
	_font_cols = cols
	_charmap = cmap
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -10                       # pic/bg sit behind the textbox/menu (which draw on top)


func _draw() -> void:
	if _pic:                                          # speech mode: cover the world with the GB bg
		draw_rect(Rect2(0, 0, 160, 144), LIGHT)
		if _pic_sil:                                  # PAL_BLACK: every shade goes darkest
			draw_texture(_pic, _pic_pos, DARK)
		else:
			draw_texture(_pic, _pic_pos)
	if _heal_monitor and _heal_tex_e0:                # the healing machine (PokeCenterOAMData)
		# The dbsprite entries are raw OAM hardware coords, which carry built-in offsets — screen
		# px = (x - 8, y - 16). The monitor sits at (44,20) on the console and the ball pairs land
		# in its slot panel at x 40/48, rows y 27/32/37 (gh #159). Drawn through the real OBP1
		# palettes (_heal_palette_tex): the monitor screen renders LIT, the balls keep their
		# white highlights against the console's dark panel, and the flash swaps the planes.
		var ht: Texture2D = _heal_tex_c8 if _heal_flash else _heal_tex_e0
		draw_texture_rect_region(ht, Rect2(44, 20, 8, 8), Rect2(0, 0, 8, 8))
		for i in _heal_balls:                         # ball pairs; the right half is x-flipped
			# gh #11: a negative-width rect FLIPS the texture but stays anchored at position.x —
			# it does not draw leftward. Anchoring the flipped half at 56 put the right balls one
			# cell right of the machine's slot panel; pokered's OAM has the pair at x 48/56 raw,
			# screen 40/48 (dbsprite 6,y / 7,y | OAM_XFLIP in PokeCenterOAMData).
			var bx := 40.0 if i % 2 == 0 else 48.0
			var bw := 8.0 if i % 2 == 0 else -8.0
			# heal_machine.png stacks its two tiles VERTICALLY: the ball is at (0,8), not
			# (8,0) — the old region read off the texture's right edge and drew nothing (gh #69)
			draw_texture_rect_region(ht, Rect2(bx, [27.0, 32.0, 37.0][i / 2], bw, 8),
				Rect2(0, 8, 8, 8))
	if not _anne.is_empty():                          # the S.S. Anne sails west (VermilionDock.asm)
		for i in 11:                                  # open water fills in from the east
			draw_texture(_anne["water"], Vector2(i * 16.0, 80.0))
		draw_texture(_anne["band"], Vector2(float(_anne["x"]), 80.0))
		for p in _anne["puffs"]:                      # each 16x16 puff = the 8x8 smoke tile 2x2
			for q in 4:
				draw_texture(_anne["smoke"], Vector2(p) + Vector2((q % 2) * 8.0, (q / 2) * 8.0))
	if _fly_bird_tex:                                 # the FLY bird (player_animations.asm, gh #144)
		var bf := 5 if _fly_bird_flap else 2          # the flap alternates walk-left/stand-left
		# gh #11: a negative-width rect flips the texture but stays anchored at position.x, so
		# the mirrored (right-facing) frame anchors at the SAME spot as the left-facing one —
		# the old `+ Vector2(16, 0)` anchor drew every right-facing frame 16 px right of its
		# asm screen coord.
		var brect := Rect2(_fly_bird, Vector2(-16, 16)) if _fly_bird_right \
			else Rect2(_fly_bird, Vector2(16, 16))    # right-facing = the left frame mirrored
		draw_texture_rect_region(_fly_bird_tex, brect, Rect2(0, bf * 16, 16, 16))
	if _in_credits:                                   # the end-credits roll (engine/movie/credits.asm)
		draw_rect(Rect2(0, 32, 160, 80), LIGHT)       # the text band...
		draw_rect(Rect2(0, 0, 160, 32), DARK)         # ...between the top + bottom black letterbox bars
		draw_rect(Rect2(0, 112, 160, 32), DARK)       # (FillFourRowsWithBlack, 4 rows each)
		if _credit_end:
			for e in THE_END_LAYOUT:                  # "T H E  E N D" (spaced, rows 8/9)
				if _the_end_tex:
					draw_texture_rect_region(_the_end_tex, Rect2(e[1] * GLYPH, 64, 8, 8),
						Rect2(e[0] * 8, 0, 8, 8))
					draw_texture_rect_region(_the_end_tex, Rect2(e[1] * GLYPH, 72, 8, 8),
						Rect2(e[0] * 8, 8, 8, 8))
		elif _credit_mon:                             # a mon silhouette scrolling left off-screen
			draw_texture(_credit_mon, Vector2(_credit_mon_x, _credit_mon_y), DARK)
		elif bool(_credit_page.get("copyright", false)):
			_draw_copyright()
		else:
			var y := 48.0                             # base row 6 (hlcoord _, 6), lines 2 rows apart
			for pair in _credit_page.get("lines", []):
				_cstr(str(pair[1]), (9 + int(pair[0])) * GLYPH, y)   # col 9 + the string's offset
				y += 16.0
		if _fade > 0.0:                               # fade the band content, not the black bars
			draw_rect(Rect2(0, 32, 160, 80), Color(LIGHT.r, LIGHT.g, LIGHT.b, _fade))
		return
	if _fade > 0.0:
		draw_rect(Rect2(0, 0, 160, 144), Color(1, 1, 1, _fade))


## Show one dialogue page and wait for the player to dismiss it.
func say(text: String) -> void:
	main.modal = main.textbox
	main.textbox.show_text(main.resolve_text(text))   # <PLAYER>/<RIVAL> from extracted texts
	await main.textbox.closed


## Show an intro pic (centred upper area), like IntroDisplayPicCenteredOrUpperRight.
func pic(tex: Texture2D, pos := Vector2(52, 24), flip := false) -> void:
	if flip:
		var img := tex.get_image()
		img.flip_x()
		tex = ImageTexture.create_from_image(img)
	_pic = tex
	_pic_pos = pos
	queue_redraw()


func clear_pic() -> void:
	_pic = null
	queue_redraw()


## Slide the intro pic horizontally (OakSpeechSlidePicRight/Left): the trainer/rival pic moves
## aside to make room for the name menu.
func slide_pic_to(to_x: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(x: float) -> void: _pic_pos.x = x; queue_redraw(), _pic_pos.x, to_x, 0.35)
	await tw.finished


func fade_out() -> void:             # to white
	await _tween_fade(1.0)


func fade_in() -> void:              # from white
	await _tween_fade(0.0)


func _tween_fade(target: float) -> void:
	var tw := create_tween()
	tw.tween_method(_set_fade, _fade, target, 0.4)
	await tw.finished


func _set_fade(v: float) -> void:
	_fade = v
	queue_redraw()


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _cstr(s: String, x0: float, y: float) -> void:
	if _font_tex == null:
		return
	var x := x0
	for ch in s:
		if ch != " " and _charmap.has(ch):
			var t: int = _charmap[ch]
			var src := Rect2((t % _font_cols) * GLYPH, (t / _font_cols) * GLYPH, GLYPH, GLYPH)
			draw_texture_rect_region(_font_tex, Rect2(x, y, GLYPH, GLYPH), src)
		x += GLYPH


var _fly_bird_tex: Texture2D        # the BirdSprite sheet, non-null while a FLY leg is drawing
var _fly_bird := Vector2.ZERO       # the bird's screen px — the asm coord lists are 1:1 screen coords
var _fly_bird_flap := false         # toggles every step (DoFlyAnimation's `xor $1` wing flap)
var _fly_bird_right := false        # the sheet has left frames only; facing right mirrors them

# player_animations.asm coord lists as (x, y) — the asm stores y,x pairs. The port keeps the GB
# framing (the player sprite sits at screen 64,60 = $40,$3C; gh #38), so these apply unchanged.
const _FLY_ENTER := [[0x98, 0x05], [0x90, 0x0F], [0x88, 0x18], [0x80, 0x20], [0x78, 0x27],
	[0x70, 0x2D], [0x68, 0x32], [0x60, 0x36], [0x58, 0x39], [0x50, 0x3B], [0x48, 0x3C], [0x40, 0x3C]]
const _FLY_LEAVE1 := [[0x48, 0x3C], [0x50, 0x3C], [0x58, 0x3B], [0x60, 0x3A], [0x68, 0x39],
	[0x70, 0x37], [0x78, 0x37], [0x80, 0x33], [0x88, 0x30], [0x90, 0x2D], [0x98, 0x2A], [0xA0, 0x27]]
const _FLY_LEAVE2 := [[0x90, 0x1A], [0x80, 0x19], [0x70, 0x17], [0x60, 0x15], [0x50, 0x12],
	[0x40, 0x0F], [0x30, 0x0C], [0x20, 0x09], [0x10, 0x05], [0x00, 0x00], [0x00, 0xF0]]


## One DoFlyAnimation run: the wings toggle every step (`xor $1`), and unless the bird is flapping
## in place (an empty list) it takes the next screen coord; every step holds Delay3 (3/60 s).
func _fly_leg(coords: Array, steps: int, face_right: bool) -> void:
	_fly_bird_right = face_right
	for i in steps:
		_fly_bird_flap = not _fly_bird_flap
		if i < coords.size():
			_fly_bird = Vector2(coords[i][0], coords[i][1])
		queue_redraw()
		await wait(3.0 / 60.0)


## FLY (gh #144): _LeaveMapAnim .flyAnimation + EnterMapAnim .flyAnimation. The BIRD replaces the
## player sprite (LoadBirdSpriteGraphics overwrites the player's VRAM slot): it flaps in place for
## 8 beats, SFX_FLY rings, it swoops off toward the top-right (FlyAnimationScreenCoords1), holds 40
## frames, then crosses back high across the sky right-to-left (FlyAnimationScreenCoords2) into the
## fade. On arrival the map fades in first, then the bird dives in from the top-right down onto the
## player's spot (FlyAnimationEnterScreenCoords) and Red reappears; the map music waits for the
## landing (.restoreDefaultMusic).
func fly_transition(label: String, spawn: Vector2i) -> void:
	main.cutscene_active = true
	main.modal = null
	visible = true
	if main.audio:
		main.audio.stop()                          # StopMusic before the takeoff
	main.player.spr.visible = false
	_fly_bird_tex = load("res://assets/sprites/bird.png")
	_fly_bird = Vector2(0x40, 0x3C)                # the player's screen spot
	await _fly_leg([], 8, true)                    # flap in place (counter 8, image $c)
	if main.audio:
		main.audio.play_sfx("fly")
	await _fly_leg(_FLY_LEAVE1, 12, true)          # off toward the top-right
	await wait(40.0 / 60.0)                        # ld c, 40 / call DelayFrames
	await _fly_leg(_FLY_LEAVE2, 11, false)         # the high pass back across the sky
	_fly_bird_tex = null
	await fade_out()
	main.load_world(label, -1, spawn)
	main.player.spr.visible = false                # still the bird until it lands
	if main.audio:
		main.audio.stop()                          # PlayDefaultMusic only fires after the landing
	await fade_in()                                # GBFadeInFromWhite, then the dive
	_fly_bird_tex = load("res://assets/sprites/bird.png")
	if main.audio:
		main.audio.play_sfx("fly")
	await _fly_leg(_FLY_ENTER, 12, false)
	_fly_bird_tex = null
	main.player.spr.visible = true                 # LoadPlayerSpriteGraphics
	if main.audio:
		main.audio.play_map_music(label)           # .restoreDefaultMusic
	queue_redraw()
	visible = false
	main.cutscene_active = false


## Fall through a hole to the floor below — pokered's **dungeon warp**
## (engine/overworld/special_warps.asm). The map's own script names the hole cells and the floor you
## land on (e.g. `PokemonMansion3FDefaultScript`'s `.holeCoords`); the landing cell comes from
## `DungeonWarpData`. `LeaveMapAnim` drops you with SFX_TELEPORT_EXIT_1, and `EnterMapAnim`'s
## `.dungeonWarpAnimation` plays SFX_TELEPORT_ENTER_1 and then simply holds for 50 frames — no spin,
## unlike a teleport — which is the beat that reads as "you landed".
func fall_down_hole(dest_map: String, dest_cell: Vector2i) -> void:
	main.cutscene_active = true
	main.modal = null
	visible = true
	if main.audio:
		main.audio.play_sfx("teleport_exit1")
	await fade_out()
	main.load_world(dest_map, -1, dest_cell)
	await fade_in()
	visible = false
	if main.audio:
		main.audio.play_sfx("teleport_enter1")
	if not main.battle.fast_hp:                # tests skip the landing beat
		await wait(50.0 / 60.0)                # .dungeonWarpAnimation: `ld c, 50` DelayFrames
	main.cutscene_active = false


## The end-credits roll (data/credits): fade through each page of staff text, then THE END.
## The end-credits roll (engine/movie/credits.asm Credits): black letterbox bars with a white
## text band; each page's staff text appears (fading in for the FADE variants), holds, and at a
## _MON page a Pokémon front sprite scrolls left across the band as a black silhouette — the
## transition between sections (DisplayCreditsMon). The © page and THE END screen close it out.
func run_credits(hold_end := false) -> void:
	visible = true
	_in_credits = true
	_credit_end = false
	_credit_mon = null
	_the_end_tex = load("res://assets/credits_the_end.png")
	if main.audio:
		main.audio.play_song("credits")
	var fast: bool = not (main.audio and main.audio.enabled)   # tests run with audio off
	for page in main.credits_pages:
		_credit_page = page
		_credit_mon = null
		_fade = 1.0 if bool(page.get("fade")) else 0.0
		queue_redraw()
		if fast:
			await get_tree().process_frame
			continue
		if bool(page.get("fade")):                    # FadeInCredits
			await fade_in()
		await wait(1.8)                               # the per-screen hold (90-140 frames)
		if page.get("mon") != null:
			await _credits_mon_scroll(str(page["mon"]))
	# THE END (.showTheEnd): the letter graphic fades in on the cleared band
	_credit_page = {}
	_credit_mon = null
	_credit_end = true
	_fade = 1.0
	queue_redraw()
	if fast:
		await get_tree().process_frame
	else:
		await fade_in()
		await wait(3.0)
		if hold_end:
			# HallOfFameResetEventsAndSaveScript holds THE END up: 600 DelayFrames (10 s), then
			# WaitForTextScrollButtonPress — a press of A or B lets the boot replay (gh #179).
			await wait(7.0)
			await wait_button()
	_in_credits = false
	_credit_end = false
	_fade = 0.0
	visible = false
	queue_redraw()


## Idle until A or B is pressed (WaitForTextScrollButtonPress, without a textbox on screen).
func wait_button() -> void:
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
			return


## Scroll the next Pokémon left across the band as a black silhouette. DisplayCreditsMon puts the
## 7×7 pic buffer at tile (8,6) — a small pic sits bottom-aligned and centred inside it, the
## standard Gen-1 pic alignment the battle draw already uses; the port's pngs are cropped, so the
## padding is re-added here (gh #183). ScrollCreditsMonLeft then bumps SCX one 8-px tile per
## frame — a fast ~480 px/s zip, not a glide.
func _credits_mon_scroll(species: String) -> void:
	_credit_mon = load("res://assets/pokemon/front/%s.png" % species)
	if _credit_mon == null:
		return
	var cx := 64.0 + (56.0 - _credit_mon.get_width()) / 2.0
	_credit_mon_y = 48.0 + (56.0 - _credit_mon.get_height())
	_credit_mon_x = cx
	_fade = 0.0
	queue_redraw()
	await wait(0.4)
	var tw := create_tween()
	tw.tween_method(func(x: float) -> void: _credit_mon_x = x; queue_redraw(),
		cx, -64.0, (cx + 64.0) / 480.0)
	await tw.finished
	_credit_mon = null


## Draw the © page (title.asm CopyrightTextString at hlcoord 2,7): the © + year + Nintendo /
## Creatures / GAME FREAK strip, reusing the boot copyright tiles.
func _draw_copyright() -> void:
	if _cr_strip == null:
		_cr_strip = load("res://assets/title/copyright_strip.png")
		_cr_gf = load("res://assets/title/gamefreak_inc.png")
	for r in COPYRIGHT_ROWS.size():
		var x := 16.0                                 # hlcoord 2 -> pixel x 16
		for id in COPYRIGHT_ROWS[r]:
			if id != 0x7F:
				var tex: Texture2D = _cr_strip if id <= 0x72 else _cr_gf
				var idx: int = id - (0x60 if id <= 0x72 else 0x73)
				draw_texture_rect_region(tex, Rect2(x, 56.0 + r * 16.0, 8, 8), Rect2(idx * 8, 0, 8, 8))
			x += GLYPH


# Direction enums (match Player/NPC): DOWN UP LEFT RIGHT.
enum { DOWN, UP, LEFT, RIGHT }


## Walk an actor (player or NPC) along a list of direction enums, one cell per step.
func walk(actor, dirs: Array) -> void:
	for d in dirs:
		await actor.step(int(d))


const _DIRV := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]


## Walk an actor forward in `dir` up to `max_steps`, stopping early if the next cell is blocked.
func walk_forward(actor, dir: int, max_steps: int) -> void:
	for i in max_steps:
		var target: Vector2i = actor.cell + _DIRV[dir]
		# gh #177: an NPC's scripted approach stops alongside the player, never on top of them — pokered's
		# movement halts on a sprite in the way. (When the player is the actor this never triggers, since
		# target is always player.cell + dir.)
		if actor != main.player and target == main.player.cell:
			break
		if not main.player_can_enter(target):
			break
		await actor.step(dir)


func _dir_to(from: Vector2i, to: Vector2i) -> int:
	var dv := to - from
	if dv.y > 0: return DOWN
	if dv.y < 0: return UP
	if dv.x < 0: return LEFT
	return RIGHT


## Lead walks `dirs`; the follower trails one tile behind, stepping into each cell the lead
## vacates (so it tracks the lead's sprite directly, around corners too). Scripted NPC steps
## run at the player's pace (NPC.SCRIPT_STEP), so both glide in lockstep; the steps start
## together and the loop gates on the lead (gating on the follower once overlapped the lead's
## tweens and glitched its walk).
func walk_together(lead, follower, dirs: Array) -> void:
	for d in dirs:
		var vacated: Vector2i = lead.cell          # where the follower will move next
		follower.step(_dir_to(follower.cell, vacated), lead.SCRIPT_STEP)
		await lead.step(int(d))


## Modal YES/NO prompt; returns true for YES. Reuses the cursor menu. menu_mode = "cutscene" so
## the global _on_menu_chosen handler ignores this selection (we consume it via the await below).
## The box sits at hlcoord 14,7 — the top-right corner of the text box (DisplayTextBoxID
## YES_NO_MENU) — and the question stays on screen beneath it.
func ask_yes_no() -> bool:
	main.menu_mode = "cutscene"
	main.modal = main.menu
	main.menu.open(["YES", "NO"], Vector2(112, 56))
	var idx: int = await main.menu.chosen
	main.modal = null
	return idx == 0


## Ask a question with a YES/NO: the player advances any earlier pages, and the moment the
## final page finishes typing the menu pops over the still-open box (pokered's prompt flow).
func ask(text: String) -> bool:
	main.modal = main.textbox
	main.textbox.show_ask(text)
	await main.textbox.typed
	var yes := await ask_yes_no()
	main.textbox.visible = false
	main.textbox.held = false
	return yes


## Show the naming screen and return the chosen name. title = "YOUR" / "RIVAL's". If an intro pic
## is showing, it slides right first so the preset list has room on the left (OakSpeechSlidePicRight).
func ask_name(title: String, presets: Array, prompt := "", skip_presets := false) -> String:
	if _pic:
		await slide_pic_to(96)
	main.modal = main.naming
	main.naming.open(title, presets, prompt, skip_presets)
	var n: String = await main.naming.done
	main.modal = null
	return n


## After receiving a POKéMON, offer to nickname it (engine/menus/naming_screen.asm DisplayNamingScreen).
func offer_nickname(mon: Dictionary) -> void:
	var sp: String = str(mon["name"])
	if not await ask("Do you want to give\na nickname to %s?" % sp):
		return
	var n: String = await ask_name(sp, [sp], "%s's\nnickname?" % sp, true)  # straight to the keyboard (#20)
	if n.strip_edges() != "" and n != sp:
		mon["name"] = n


## Prof. Oak's intro speech (engine/movie/oak_speech): Oak + Nidorino + Red/naming + rival/naming,
## ending with the player in the (already-loaded) world. Plays Music_Routes2.
func oak_speech() -> void:
	main.cutscene_active = true
	main.modal = null
	visible = true
	_fade = 0.0
	if main.audio:
		main.audio.play_song("routes2")
	pic(load("res://assets/title/oak.png"))
	await say("Hello there!\nWelcome to the\nworld of POKéMON!\fMy name is OAK!\nPeople call me\nthe POKéMON PROF!")
	await fade_out(); clear_pic()
	pic(load("res://assets/pokemon/front/nidorino.png"), Vector2(48, 36), true); await fade_in()
	await say("This world is\ninhabited by\ncreatures called\nPOKéMON!\fFor some people,\nPOKéMON are pets.\fOthers use them\nfor fights.\fMyself...\fI study POKéMON\nas a profession.")
	await fade_out(); clear_pic()
	pic(load("res://assets/title/redfront.png")); await fade_in()
	main.player_name = await ask_name("YOUR", ["RED", "ASH", "JACK"], "First, what is\nyour name?")
	await fade_out(); clear_pic()
	pic(load("res://assets/title/rival.png")); await fade_in()
	await say("This is my grand-\nson. He's been\nyour rival since\nyou were a baby.")
	main.rival_name = await ask_name("RIVAL's", ["BLUE", "GARY", "JOHN"], "...Erm, what is\nhis name again?")
	await fade_out(); clear_pic()
	pic(load("res://assets/title/redfront.png")); await fade_in()
	await say("%s!\fYour very own\nPOKéMON legend is\nabout to unfold!\fA world of dreams\nand adventures\nwith POKéMON\nawaits! Let's go!" % main.player_name)
	# The trainer pic shrinks down into the overworld sprite (SFX_SHRINK, ShrinkPic1/2).
	if main.audio:
		main.audio.play_sfx("shrink")
	await wait(0.3)
	pic(load("res://assets/title/shrink1.png")); await wait(0.3)
	pic(load("res://assets/title/shrink2.png")); await wait(0.5)
	await fade_out(); clear_pic()                 # fade to white, then reveal the room
	await fade_in()
	visible = false
	_fade = 0.0
	main.cutscene_active = false


## Pallet Town intercept (scripts/PalletTown.asm): the player tries to leave town without a
## POKéMON, so Oak appears, walks up to them, warns them, and leads them back to his lab.
# (oak_intercept + lab_intro dissolved into pallet_town_oak_intercept.json — wave C, gh #41.)


# (choose_starter + rival_takes_starter dissolved into the ball records — wave C, gh #41.)


## Oak's dex-rating chat (OaksLabOak1Text .HowIsYourPokedexComingText): the preamble ends in
## `prompt` and the rating prints straight after it — one flowing text (the beat form of the
## retired OaksLab adapter's call; the rating itself stays on Main).
func oak_dex_rating() -> void:
	main.oaks_dex_rating("OAK: Good to see\nyou! How is your\nPOKéDEX coming?\nHere, let me take\na look!\f")


# The rival's starter is the type-advantage counterpart of the player's.
const _COUNTERPART := {"charmander": "squirtle", "squirtle": "bulbasaur", "bulbasaur": "charmander"}


## The rival's chosen starter (the rival party tables are keyed by it, matching wRivalStarter).
func _rival_st() -> String:
	return main.rival_starter if main.rival_starter != "" else str(_COUNTERPART.get(main.player_starter, "squirtle"))




## The rival challenges the player to the first battle once they head for the exit
## (OaksLabRivalChallengesPlayerScript fires at Y==6). Triggered from Main._on_player_moved.
## Route 22 rival battle (scripts/Route22.asm). which = 1 (early, before Brock) or 2 (after the 8th
## badge). The rival walks in from the west, battles (party by the rival's starter), then leaves.
const _ROUTE22_PARTY := {
	1: {"squirtle": 4, "bulbasaur": 5, "charmander": 6},
	2: {"squirtle": 10, "bulbasaur": 11, "charmander": 12},
}
func route22_rival(which: int) -> void:
	main.cutscene_active = true
	main.modal = null
	var pn: String = main.player_name
	var rn: String = main.rival_name
	var rival = main._npc_by_key("SPRITE_BLUE@25,5")
	if main.audio:
		main.audio.play_song("meetrival")
	if rival:
		rival.set_shown(true)
		await walk_forward(rival, 3, 4)            # walk east toward the player, stopping alongside
		rival.face_to(main.player.cell)
	if which == 1:
		await say("%s: Hey!\n%s!\fYou're going to\nPOKéMON LEAGUE?\fForget it! You\nprobably don't\nhave any BADGEs!\fThe guard won't\nlet you through!\fBy the way, did\nyour POKéMON\nget any stronger?" % [rn, pn])
	else:
		await say("%s: What?\n%s! What a\nsurprise to see\nyou here!\fSo you're going to\nPOKéMON LEAGUE?\fYou collected all\nthe BADGEs too?\fThen I'll whip you\nas a warm up for\nPOKéMON LEAGUE!\fCome on!" % [rn, pn])
	var num: int = int(_ROUTE22_PARTY[which].get(_rival_st(), _ROUTE22_PARTY[which]["charmander"]))
	main.start_trainer_battle("OPP_RIVAL1" if which == 1 else "OPP_RIVAL2", num, "Route22:25,5")
	await main.battle.finished
	if not main.battle.won:
		main.cutscene_active = false
		return
	if which == 1:
		await say("I heard POKéMON\nLEAGUE has many\ntough trainers!\fI have to figure\nout how to get\npast them!\fYou should quit\ndawdling and get\na move on!")
	else:
		await say("That loosened me\nup! I'm ready for\nPOKéMON LEAGUE!\f%s, you need\nmore practice!\fBut hey, you know\nthat! I'm out of\nhere. Smell ya!" % pn)
	main.set_event("BEAT_ROUTE22_RIVAL_%d" % which)
	if rival:
		await walk_forward(rival, 2, 5)            # slink off to the west
		rival.set_shown(false)
	main.cutscene_active = false


# ---- Bill's house: the cell-separator event (scripts/BillsHouse.asm) --------

# (bill_intro + bill_separator dissolved into the Bill's-house records - wave C, gh #41.)


## gh #174: hand over a one-off gift item, obeying the 20-slot bag limit. Returns true once it's in the
## bag (the caller then plays its jingle / "got X!" line and sets its GOT_ event). On a full bag it shows
## a no-room line, clears the cutscene, and returns false so the caller bails WITHOUT setting GOT_ —
## exactly pokered's `GiveItem` -> `.BagFull` branch, so the giver re-offers next time you make room.
func _gift(item: String) -> bool:
	if main.add_item(item):
		return true
	await say("You don't have\nroom for this!")
	main.cutscene_active = false
	return false


# (bill_ticket dissolved into bills_house_bill.json - wave C.)


# ---- S.S. Anne (scripts/VermilionCity.asm, SSAnneCaptainsRoom.asm) ----------

## Vermilion sailor flashes the ticket and waves you aboard, then warps onto the dock.
func board_ss_anne(dest_label: String, dest_warp: int) -> void:
	main.cutscene_active = true
	main.modal = null
	# pokered boards via a normal VermilionCity->dock warp, so wLastMap becomes VERMILION_CITY; here the
	# warp is intercepted by VermilionCity.on_warp (which returns early, before _do_warp records the map),
	# and load_world doesn't touch last_outside_map either. Set it so the dock's LAST_MAP exit — after the
	# ship sails — resolves back to Vermilion, not to whatever outside map you were on before (gh #116).
	main.last_outside_map = "VermilionCity"
	await say("Ah, the\nS.S.TICKET!\fThank you!\nRight this way!")
	main.cutscene_active = false
	main.load_world(dest_label, dest_warp)


# (ss_anne_captain dissolved into ss_anne_captain.json - wave C.)


# (ss_anne_rival dissolved into ss_anne_2f_rival.json - wave C.)


## Leaving the dock after getting HM01: the S.S. Anne sets sail (it can't be boarded again).
## The S.S. Anne sets sail (scripts/VermilionDock.asm VermilionDockSSAnneLeavesScript):
## stepping off the ship onto the dock with HM01, the music switches to MUSIC_SURFING; after
## a 2 s beat the horn sounds and the ship band — screen rows 80-127, the LY 80-127 raster
## window the asm scrolls — slides west 128 px at 1 px per 8 frames while smoke puffs pop
## above the front smokestack every 16 px and drift east 2 px per 8 frames; the ship's
## blocks are then erased to open water, the horn sounds again, and after another 2 s the
## player is walked north off the dock (the 3 simulated UP presses). No dialogue at all.
func ss_anne_departs() -> void:
	main.cutscene_active = true
	main.modal = null
	main.set_event("SS_ANNE_LEFT")
	# `--headless` never draws — DisplayServer::can_any_window_draw() is false, so Main::iteration()
	# skips RenderingServer::draw() and `frame_post_draw` is never emitted. Awaiting it below suspended
	# this coroutine forever: `cutscene_active` stayed true, the ship never sailed, and the player was
	# stranded on the dock at (14,2) with no error printed. The sailing animation is decoration; the
	# departure is not. (gh #103 — this is what killed the ADR-011 headless gate at the `ssanne` stage.)
	var can_draw := DisplayServer.get_name() != "headless"
	var fast: bool = not can_draw or not (main.audio and main.audio.enabled)   # tests skip the crawl
	if main.audio:
		main.audio.stop()                            # SFX_STOP_ALL_MUSIC
		main.audio.play_song("surfing")              # MUSIC_SURFING
	if not fast:
		await wait(2.0)                              # ld c, 120; call DelayFrames
	if main.audio:
		main.audio.play_sfx("ss_anne_horn")
	if can_draw:
		await RenderingServer.frame_post_draw        # capture the band + an open-water strip
		var shot: Image = main.get_viewport().get_texture().get_image()
		visible = true
		_anne = {
			"band": ImageTexture.create_from_image(shot.get_region(Rect2i(0, 80, 160, 48))),
			"water": ImageTexture.create_from_image(shot.get_region(Rect2i(144, 80, 16, 48))),
			"smoke": load("res://assets/sprites/smoke.png"),
			"x": 0, "puffs": [],
		}
		queue_redraw()
	if not fast:
		for col in 8:                                # a fresh puff per 16 px of sailing
			_anne["puffs"].append(Vector2(64.0 - 16.0 * col, 84.0))
			for i in 16:
				for pi in _anne["puffs"].size():     # every existing puff drifts east
					_anne["puffs"][pi] += Vector2(2.0, 0.0)
				queue_redraw()
				for f in 8:
					await get_tree().process_frame
				_anne["x"] = int(_anne["x"]) - 1
	# VermilionDock_EraseSSAnne, literally: only the ship's LOWER row becomes water (hlowcoord
	# 5,2 -> four $0D). The upper deck row (blocks 04-07) STAYS — the GB never redraws it
	# before the walk-off, so the real scene keeps the deck remnant above the water, and Gen 1
	# keeps the whole ship in the map data forever (re-entering the dock later shows it docked —
	# an authentic, Bulbapedia-documented quirk; gh #118).
	for bx in range(5, 9):
		main.set_block(bx, 2, 0x0D)
	_anne = {}
	queue_redraw()
	if main.audio:
		main.audio.play_sfx("ss_anne_horn")
	if not fast:
		await wait(2.0)
	for i in 2:                                      # gangway (14,2) -> the door at (14,0)
		await main.player.step(1)
	main.cutscene_active = false
	visible = false
	if main.center_label == "VermilionDock":         # the door warp into Vermilion
		main._do_warp(main.map["warps"][0])


# ---- Day Care (scripts/Daycare.asm) ----------------------------------------

## The Route 5 Day-Care man: deposit a party mon, or pay to withdraw the grown one.
func daycare_man() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.daycare_mon.is_empty():
		if not await ask("Hi! I run the\nDAY-CARE.\fWould you like me\nto raise one of\nyour POKéMON?"):
			await say("Fine. Come see me\nsometime.")
			main.cutscene_active = false
			return
		if main.player_party.size() <= 1:
			await say("Oh? But you have\njust one POKéMON.")
			main.cutscene_active = false
			return
		await say("Which POKéMON\nshould I raise?")
		main.cutscene_active = false
		main.menu_mode = "daycare_deposit"
		main.modal = main.menu
		main.menu.open(main._party_labels(), Vector2(8, 8))
		return
	var mon: Dictionary = main.daycare_mon
	var lvl: int = main.level_for_exp(int(mon["exp"]), str(mon["growth"]))
	var cost: int = (lvl - main.daycare_start_level + 1) * 100
	main.moneybox.show_box()                  # MONEY_BOX up for the fee prompt (Daycare.asm)
	if not await ask("Your %s has\ngrown a lot!\fIt's now at\nlevel %d.\fThat will be\n¥%d." % [mon["name"], lvl, cost]):
		await say("Oh. Fine, then.")
		main.moneybox.hide_box()
		main.cutscene_active = false
		return
	if main.player_money < cost:
		await say("You don't have\nenough money...")
		main.moneybox.hide_box()
		main.cutscene_active = false
		return
	if main.player_party.size() >= 6:
		await say("You have no room\nfor another\nPOKéMON!")
		main.moneybox.hide_box()
		main.cutscene_active = false
		return
	main.player_money -= cost
	main.moneybox.refresh()                   # redrawn right after SubBCDPredef
	mon["level"] = lvl
	main.recompute_stats(mon)
	mon["hp"] = int(mon["maxhp"])
	main.player_party.append(mon)
	main.daycare_mon = {}
	main.daycare_start_level = 0
	await say("Here's your\nPOKéMON!\fTake good care\nof it!")
	main.moneybox.hide_box()
	main.cutscene_active = false


# ---- Bike: voucher + shop (scripts/PokemonFanClub.asm, scripts/BikeShop.asm) ----

## The Route 16 house girl gives HM02 (FLY).
func fly_house_girl() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_HM02"):
		await say("Isn't FLY the\nbest? You can go\nback to any town\nin a flash!")
		main.cutscene_active = false
		return
	await say("My bird POKéMON\nuses FLY to whisk\nme to any town!\fI want you to\nhave this!")
	if not await _gift("HM02"):
		return
	if main.audio:
		main.audio.play_sfx("get_item1")
	await say("%s received\nHM02!" % main.player_name)
	main.set_event("GOT_HM02")
	await say("HM02 is FLY!\fTeach it to a bird\nPOKéMON to soar\nto any town\nyou've visited!")
	main.cutscene_active = false


## The Fuchsia Warden gives HM04 (STRENGTH) once you return his GOLD TEETH.
func warden_strength() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_HM04"):
		await say("WARDEN: Thanks to\nyou I can wear my\ndentures again!")
		main.cutscene_active = false
		return
	if not main.player_bag.has("GOLD TEETH"):
		await say("WARDEN: OFAOFA!\nKEKEKE!\f(He has no teeth\nand can't speak\nclearly...)")
		main.cutscene_active = false
		return
	await say("WARDEN: OH! My\nGOLD TEETH!\fYou found them!\fHere, take this\nin gratitude!")
	main.player_bag.erase("GOLD TEETH")
	main.player_bag["HM04"] = 1
	if main.audio:
		main.audio.play_sfx("get_item1")
	await say("%s received\nHM04!" % main.player_name)
	main.set_event("GOT_HM04")
	await say("HM04 is STRENGTH!\fA POKéMON can use\nit to move giant\nboulders!")
	main.cutscene_active = false


## Game Corner coin clerk (scripts/GameCorner.asm GameCornerClerk1Text): 50 coins for ¥1000.
func coin_clerk() -> void:
	main.cutscene_active = true
	main.modal = null
	if not await ask("Welcome to ROCKET\nGAME CORNER!\fDo you need some\ngame coins?"):
		await say("No? Please come\nplay sometime!")
		main.cutscene_active = false
		return
	if not main.player_bag.has("COIN CASE"):
		await say("You don't have a\nCOIN CASE!")
	elif main.player_coins >= 9990:
		await say("Oops! Your COIN\nCASE is full.")
	elif main.player_money < 1000:
		await say("You can't afford\nthe coins!")
	else:
		main.player_money -= 1000
		main.player_coins = mini(9999, main.player_coins + 50)
		if main.audio:
			main.audio.play_sfx("get_item1")
		await say("Thanks! Here are\nyour 50 coins!")
	main.cutscene_active = false


## Game Corner fishing guru (GameCornerFishingGuruText): 10 free coins, once.
func coin_gift() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_10_COINS"):
		await say("Wins seem to come\nand go.")
		main.cutscene_active = false
		return
	await say("Kid, do you want\nto play?")
	if not main.player_bag.has("COIN CASE"):
		await say("Oops! Forgot the\nCOIN CASE!")
	elif main.player_coins >= 9990:
		await say("You don't need my\ncoins!")
	else:
		main.player_coins = mini(9999, main.player_coins + 10)
		main.set_event("GOT_10_COINS")
		if main.audio:
			main.audio.play_sfx("get_item1")
		await say("%s received\n10 coins!" % main.player_name)
	main.cutscene_active = false


## Game Corner prize room prizes (data/events/prizes.asm + prize_mon_levels.asm, RED). Three
## vendors: two Pokémon counters and one TM counter. TM ids per game/assets/tm_moves.json.
const _PRIZES := [
	[{"name": "ABRA", "mon": "abra", "lv": 9, "cost": 180},
	 {"name": "CLEFAIRY", "mon": "clefairy", "lv": 8, "cost": 500},
	 {"name": "NIDORINA", "mon": "nidorina", "lv": 17, "cost": 1200}],
	[{"name": "DRATINI", "mon": "dratini", "lv": 18, "cost": 2800},
	 {"name": "SCYTHER", "mon": "scyther", "lv": 25, "cost": 5500},
	 {"name": "PORYGON", "mon": "porygon", "lv": 26, "cost": 9999}],
	[{"name": "DRAGON RAGE", "tm": "TM23", "cost": 3300},
	 {"name": "HYPER BEAM", "tm": "TM15", "cost": 5500},
	 {"name": "SUBSTITUTE", "tm": "TM50", "cost": 7700}],
]


# ---- the Cable Club (gh #5, ADR-014) ---------------------------------------
# engine/link/cable_club_npc.asm CableClubNPC + engine/menus/main_menu.asm LinkMenu.
# HOST/JOIN is the modern stand-in for plugging in the cable (the asm's serial-connection
# attempt); from link establishment onward the dialogue is the asm's, beat for beat:
# apply-here + save warning -> YES/NO -> save + SFX -> "Please wait." sync -> the
# TRADE CENTER / COLOSSEUM / CANCEL menu, where the FIRST player to press wins and the
# host arbitrates a tie (the internally-clocked Game Boy wins in LinkMenu) -> the special
# warp into the room (host at (3,4), partner at (6,4) — special_warps.asm).

var _club_refusal := ""            # the handshake refusal reason (surfaced in-dialogue)
var _club_peer_ready := false      # partner passed the save beat (Serial_SyncAndExchangeNybble)
var _club_peer_pick := -1          # host: the partner's LinkMenu pick, if it arrived first
var _club_go := -1                 # joiner: the host's authoritative destination


func cable_club_npc(_npc) -> void:
	main.cutscene_active = true
	await say("Welcome to the\nCable Club!")
	if not main.has_event("GOT_POKEDEX"):
		await main.get_tree().create_timer(1.0).timeout      # ld c, 60 + DelayFrames
		await say("We're making\npreparations.\nPlease wait.")
		main.cutscene_active = false
		return
	_club_refusal = ""
	_club_peer_ready = false
	_club_peer_pick = -1
	_club_go = -1
	if not main.link.refused.is_connected(_club_on_refused):
		main.link.refused.connect(_club_on_refused)
	if not main.link.message.is_connected(_club_on_message):
		main.link.message.connect(_club_on_message)
	await _club_flow()
	if main.link.message.is_connected(_club_on_message):
		main.link.message.disconnect(_club_on_message)
	if main.link.refused.is_connected(_club_on_refused):
		main.link.refused.disconnect(_club_on_refused)
	main.cutscene_active = false


func _club_flow() -> void:
	# --- the modern cable: HOST / JOIN (spec stories 2-4) ---
	var sel := await pick(["HOST", "JOIN", "CANCEL"], Vector2(88, 40))
	var joined_addr := ""
	if sel == 0:
		await _club_wait_link(true, "")
	elif sel == 1:
		joined_addr = await ask_address()
		if joined_addr != "":
			await _club_wait_link(false, joined_addr)
	if main.link.state != "linked":
		if _club_refusal != "":
			# a mismatch names exactly what differed (spec story 5), then the asm's line
			await say(_club_refusal.replace(" — ", "!\f"))
			_club_refusal = ""
		main.link.close("club")
		await say("This area is\nreserved for 2\nfriends who are\nlinked by cable.")
		return
	if joined_addr != "":
		main.link_last_addr = joined_addr        # remembered (saved) as the next default
	# --- from establishment on, the asm's script ---
	if not await ask("Please apply here.\fBefore opening\nthe link, we have\nto save the game."):
		main.link.close("declined")
		await say("Please come again!")
		return
	main.save_game()
	if main.audio:
		main.audio.play_sfx("save")
	if not await _club_sync_ready():
		main.link.close("inactive")
		await say("The link has been\nclosed because of\ninactivity.\fPlease contact\nyour friend and\ncome again!")
		return
	var dest := await _club_link_menu()
	if dest != 0 and dest != 1:
		main.link.close("canceled")
		await say("The link was\ncanceled.")
		return
	await say("OK, please wait\njust a moment.")
	# Not the asm's line — playtest QoL: the club room has no visible door (the cartridge
	# exits by walking off the bottom edge too, it just never tells you).
	await say("When you're done,\nwalk down to the\nexit to come back!")
	main.link_return_map = main.center_label       # walking out of the room comes back here
	main.link_return_cell = main.player.cell
	var room := "TradeCenter" if dest == 0 else "Colosseum"
	var cell := Vector2i(3, 4) if main.link.is_host else Vector2i(6, 4)
	main.load_world(room, -1, cell, false)


func _club_on_refused(reason: String, _by_peer: bool) -> void:
	_club_refusal = reason


func _club_on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"club_ready":
			_club_peer_ready = true
		"club_pick":                              # joiner -> host: the partner pressed first
			if _club_peer_pick < 0:
				_club_peer_pick = int(msg.get("sel", 2))
				if main.modal == main.menu and main.menu_mode == "cutscene":
					main.menu.chosen.emit(-9)     # close our still-open menu: the partner won
		"club_go":                                # host -> joiner: the authoritative destination
			_club_go = int(msg.get("sel", 2))
			if main.modal == main.menu and main.menu_mode == "cutscene":
				main.menu.chosen.emit(-9)


## Raise the link and hold a "waiting" box until it resolves; B cancels. No awaits on
## signals that may never come — a frame-poll with Link's own timeout underneath (gh #103).
func _club_wait_link(hosting: bool, addr: String) -> void:
	main.link.timeout_s = main.link_wait_s
	var port: int = main.link_port if main.link_port > 0 else main.link.DEFAULT_PORT
	if hosting:
		# gh #5 follow-up: show the host their own address while they wait. The LAN IPv4
		# comes from the OS; the external one is asked of the ROUTER via UPnP (no
		# third-party service), which also maps the UDP port through so an internet
		# friend can actually reach us.
		main.link.lan_addr = main.link.lan_address()
		if OS.get_cmdline_user_args().is_empty():   # real play only: tests skip router chatter
			main.link.start_wan_query(port)
		main.link.host(port)
	else:
		main.link.join(addr, port)
	main.modal = main.textbox
	var wait_txt := _club_host_wait_text() if hosting else "Calling %s ..." % addr
	main.textbox.show_ask(wait_txt)
	var attempt := 1
	while true:
		var canceled := false
		while main.link.state in ["waiting", "connecting", "handshake"]:
			if Input.is_action_just_pressed("ui_cancel"):
				main.link.close("player-canceled")
				canceled = true
				break
			if hosting and _club_host_wait_text() != wait_txt:   # the router answered
				wait_txt = _club_host_wait_text()
				main.textbox.show_ask(wait_txt)
			await main.get_tree().process_frame
		# A joiner's timed-out call auto-redials twice before giving up — the host may
		# still be walking to their attendant (the requested connect retry).
		if hosting or canceled or main.link.state == "linked" or _club_refusal != "" \
				or attempt >= 3:
			break
		attempt += 1
		main.textbox.show_ask("No answer —\nredialing (%d/3)..." % attempt)
		main.link.timeout_s = main.link_wait_s
		main.link.join(addr, port)
	main.textbox.visible = false
	main.textbox.active = false
	main.textbox.held = false
	main.modal = null


## The hosting wait box: the partner types one of these at their attendant — the top line
## for a friend on the same network, the bottom (once UPnP answers) for a remote one.
func _club_host_wait_text() -> String:
	if main.link.lan_addr == "" and main.link.wan_addr == "":
		return "Waiting for a\npartner..."
	var l1: String = main.link.lan_addr if main.link.lan_addr != "" else "waiting..."
	var l2: String = main.link.wan_addr if main.link.wan_addr != "" else "waiting..."
	return "Your address:\f%s\n%s" % [l1, l2]


## The "Please wait." beat: both sides confirm the save and sync (the asm's
## Serial_SyncAndExchangeNybble with wLinkTimeoutCounter). False = inactivity.
func _club_sync_ready() -> bool:
	main.link.send_message({"t": "club_ready"})
	main.modal = main.textbox
	main.textbox.show_ask("Please wait.")
	var waited := 0.0
	# Human-paced: the partner may still be reading the save prompt — liveness-bound.
	while not _club_peer_ready and main.link.state == "linked":
		await main.get_tree().process_frame
		waited += main.get_process_delta_time()
	main.textbox.visible = false
	main.textbox.active = false
	main.textbox.held = false
	main.modal = null
	return _club_peer_ready and main.link.state == "linked"


## LinkMenu: whoever presses first wins; the host arbitrates (the internally-clocked GB).
## Returns 0 TRADE CENTER / 1 COLOSSEUM / 2 CANCEL (a dead link reads as CANCEL).
func _club_link_menu() -> int:
	await say("Where would you\nlike to go?")
	# The partner may already have decided while our text was still up — don't open a menu
	# whose closing message has already been consumed.
	if not main.link.is_host and _club_go >= 0:
		return _club_go
	if main.link.is_host and _club_peer_pick >= 0:
		main.link.send_message({"t": "club_go", "sel": _club_peer_pick})
		return _club_peer_pick
	var idx := await pick(["TRADE CENTER", "COLOSSEUM", "CANCEL"], Vector2(40, 40))
	if main.link.is_host:
		var sel := _club_peer_pick if idx == -9 else (2 if idx < 0 else idx)
		main.link.send_message({"t": "club_go", "sel": sel})
		return sel
	if idx == -9:
		return _club_go
	main.link.send_message({"t": "club_pick", "sel": 2 if idx < 0 else idx})
	var waited := 0.0                          # the host always answers with club_go —
	while _club_go < 0 and main.link.state == "linked":   # but a human host may be deciding
		await main.get_tree().process_frame
		waited += main.get_process_delta_time()
	return _club_go if _club_go >= 0 else 2


# ---- the Trade Center (gh #6, ADR-014) -------------------------------------
# Both players at the table: parties are exchanged as mon records, each player picks a mon
# and sees the partner's pick, both confirm, and the commit is TWO-PHASE — each side sends
# its mon's authoritative record (`tc_commit`), journals the pending trade to disk, then
# acknowledges (`tc_ack`); only when BOTH acks are in does either side apply and save, so a
# drop before completion applies on neither (the journal marks the window; gh #9 proves it
# under injected failures). The ceremony reuses the in-game trade movie, the received mon
# keeps its nickname/OT/trainer ID (outsider status feeds the existing boosted-exp rule),
# lands in the party or the box, and a trade-evo species evolves on arrival (forced).

# The partner's messages land in QUEUES, not scalar slots: delivery is reliable-ordered,
# and under load a partner can be a whole protocol step ahead (their pick arriving between
# our party-received and our round setup) — a scalar reset would clobber it and both sides
# would wait each other out. Queues consume in order and can lose nothing.
var _tc_peer_party: Array = []      # the partner's party, as wire records
var _tc_q_pick: Array = []          # their picks (-1 = canceled), in round order
var _tc_q_confirm: Array = []       # their confirms (bool), in round order
var _tc_q_record: Array = []        # their tc_commit records
var _tc_q_ack := 0                  # their acks (a counter)
var _tc_q_resume: Array = []        # their tc_resume phase reports (gh #13)
var _tc_resumed := false            # gh #13: the session dropped and came back mid-flow
var _tc_in_commit := false          # gh #13: inside _tc_commit/_tc_commit_reconcile (routes tc_resume)
var _tc_result := ""                # "" while running; "done"/"canceled"/"aborted"/"resumed" after


func _tc_on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"tc_party":
			_tc_peer_party = msg.get("mons", [])
		"tc_pick":
			_tc_q_pick.append(int(msg.get("idx", -1)))
		"tc_cancel":
			_tc_q_pick.append(-1)
		"tc_confirm":
			_tc_q_confirm.append(bool(msg.get("yes", false)))
		"tc_commit":
			_tc_q_record.append(msg.get("record", {}))
		"tc_ack":
			_tc_q_ack += 1
		"tc_resume":
			# gh #13: only a flow inside the COMMIT section consumes reports from the queue.
			# Anyone else must still ANSWER — a committed partner starves without one — with
			# the truth about this side: "done" (we applied; their acked side rolls forward)
			# or "" (we never reached commit; both restart at the picks).
			if _tc_in_commit:
				_tc_q_resume.append(msg)
			elif _tc_result == "done":
				main.link.send_message({"t": "tc_resume", "phase": "done"})
			else:
				main.link.send_message({"t": "tc_resume", "phase": ""})
		# ---- Colosseum (gh #7) ----
		"col_party":
			_col_peer = msg
		"col_act":
			if main.battle.link_battle:
				main.battle.link_actions.append(str(msg.get("action", "")))
		"col_swap":
			if main.battle.link_battle:
				main.battle.link_swaps.append(int(msg.get("idx", 0)))
		"col_resume":
			if main.battle.link_battle:
				main.battle.link_reconcile(msg)


## Wait for `cond` while the link lives. Machine-paced protocol replies (records, acks)
## keep the link_wait_s timer; HUMAN-paced steps (the partner is choosing/reading) pass
## `patient = true` and are bounded by link liveness alone — a friend who thinks for a
## minute is the game working, not a dead link (the "frequent drops" were this timer).
## Returns 1 ok, 0 link dead/timed out, -1 the player pressed B to give up (patient only).
## Returns 1 ok, 0 link dead/timed out, -1 the player pressed B to give up (patient only),
## 2 the session dropped and RESUMED (gh #13) — the caller reconciles per ADR-016.
func _tc_wait(cond: Callable, patient := false) -> int:
	var waited := 0.0
	var lost_box := false
	while not cond.call():
		if _tc_resumed:
			_tc_resumed = false
			return 2
		if main.link.holding():
			# gh #13: an outage (incl. the resume handshake's transient frames), not a death.
			# Show the survivor's box and hold — the grace clock (or B, polled by Main straight
			# into cancel_wait) decides. The protocol timer freezes: the outage must not count
			# toward a machine-paced timeout.
			if not lost_box:
				lost_box = true
				main.modal = main.textbox
				main.textbox.show_ask("Link lost -\nwaiting for your\npartner...")
			await main.get_tree().process_frame
			continue
		if lost_box:
			lost_box = false                    # resumed (or closed): drop the box, re-evaluate
			main.textbox.visible = false
			main.textbox.active = false
			main.textbox.held = false
			main.modal = null
			continue
		if main.link.state != "linked":
			return 0
		if patient:
			if Input.is_action_just_pressed("ui_cancel"):
				return -1
		elif waited > main.link_wait_s:
			return 0
		await main.get_tree().process_frame
		waited += main.get_process_delta_time()
	if lost_box:
		main.textbox.visible = false
		main.textbox.active = false
		main.textbox.held = false
		main.modal = null
	return 1


## Armed on ROOM ENTRY (not at the table): the partner may sit down and send `tc_party`
## seconds before we do, and a message with no listener would be dropped — both sides would
## then wait each other out. Disarmed when the room is left.
func tc_room_arm() -> void:
	_tc_peer_party = []
	_col_peer = {}
	_tc_q_pick = []
	_tc_q_confirm = []
	_tc_q_record = []
	_tc_q_ack = 0
	_tc_q_resume = []
	_tc_resumed = false
	_tc_in_commit = false
	if not main.link.message.is_connected(_tc_on_message):
		main.link.message.connect(_tc_on_message)
	if not main.link.resumed.is_connected(_tc_on_resumed):
		main.link.resumed.connect(_tc_on_resumed)
	for m in main.link.take_inbox():       # the partner may have sat down before we loaded in
		_tc_on_message(m)


func tc_room_disarm() -> void:
	if main.link.message.is_connected(_tc_on_message):
		main.link.message.disconnect(_tc_on_message)
	if main.link.resumed.is_connected(_tc_on_resumed):
		main.link.resumed.disconnect(_tc_on_resumed)


## gh #13: the session came back. Everything still queued predates the blip — an in-flight
## message died with the old connection, so post-resume arrivals are always fresh — and the
## voided round's leftovers must not satisfy the restarted round's waits. The resume reports
## themselves (tc_resume/col_resume) arrive only after this fires, so they are never stale
## here. A running link battle answers with its own state report (both sides do).
func _tc_on_resumed(_s: Dictionary) -> void:
	_tc_resumed = true
	_tc_q_pick = []
	_tc_q_confirm = []
	_tc_q_record = []
	_tc_q_resume = []
	# The parties too — the restart re-exchanges them, and clearing HERE (not in the restart
	# loop) is what makes it race-free: a faster partner's fresh tc_party/col_party can land
	# before our flow reaches its restart, and a later clear would wipe it (both sides then
	# wait each other out forever).
	_tc_peer_party = []
	_col_peer = {}
	if main.battle.link_battle and main.modal == main.battle:
		_tc_resumed = false                # the battle reconciles; no table flow is waiting
		main.battle.link_send_resume()


func trade_center_table() -> void:
	if main.link.state != "linked":
		await say("The link has been\nclosed.")
		return
	main.cutscene_active = true
	main.link.resume_armed = true          # gh #13: at the table, an outage holds for a reconnect
	_tc_resumed = false
	print("[tc] table: sitting (link=%s, peer_party=%d)" % [main.link.state, _tc_peer_party.size()])
	while true:
		_tc_result = ""
		await _tc_flow()
		_tc_in_commit = false
		if _tc_result != "resumed":
			break
		# gh #13 (ADR-016): the session dropped and came back mid-round — the round is void on
		# both sides, so both restart from the party exchange, exactly like sitting down again.
		# (_tc_on_resumed already cleared the exchanged parties, race-free.)
		print("[tc] table: session resumed — restarting at the pick screens")
	print("[tc] table: done (%s, link=%s)" % [_tc_result, main.link.state])
	main.link.resume_armed = false
	main.cutscene_active = false


func _tc_flow() -> void:
	# Exchange parties: both players must be at the table before the screens open.
	var mine: Array = []
	for m in main.player_party:
		mine.append(main.monrecord.encode(m))
	main.link.send_message({"t": "tc_party", "mons": mine})
	main.modal = main.textbox
	main.textbox.show_ask("Waiting for your\nfriend...")
	# The first player to sit waits for the other to reach the table — that can take as long
	# as the partner's attendant dialogue takes, so this wait is bounded by the LINK's
	# liveness (and B to stand up), not by the turn timer.
	var stood_up := false
	var lost_box := false
	while _tc_peer_party.is_empty():
		if _tc_resumed:
			# gh #13: our tc_party may have died in flight — restart re-sends it.
			_tc_resumed = false
			break
		if main.link.holding():
			if not lost_box:
				lost_box = true
				main.textbox.show_ask("Link lost -\nwaiting for your\npartner...")
			await main.get_tree().process_frame
			continue
		if lost_box:
			lost_box = false
			main.textbox.show_ask("Waiting for your\nfriend...")
			continue
		if main.link.state != "linked":
			break
		if Input.is_action_just_pressed("ui_cancel"):
			stood_up = true
			break
		await main.get_tree().process_frame
	main.textbox.visible = false
	main.textbox.active = false
	main.textbox.held = false
	main.modal = null
	if stood_up:
		_tc_result = "canceled"
		return
	if _tc_peer_party.is_empty():
		if main.link.state == "linked":
			_tc_result = "resumed"         # gh #13: dropped + reconnected before the partner sat
			return
		_tc_result = "aborted"
		print("[tc] abort: link died before the partner sat down")
		await say("The link has been\nclosed.")
		return
	print("[tc] parties exchanged (%d theirs)" % _tc_peer_party.size())
	while true:
		# --- pick: your list over the partner's (both parties on screen) ---
		var partner_labels: Array = []
		for r in _tc_peer_party:
			partner_labels.append("%s L%d" % [_tc_rec_name(r), int(r.get("level", 0))])
		var my_labels: Array = []
		for m in main.player_party:
			my_labels.append("%s L%d" % [str(m["name"]), int(m["level"])])
		my_labels.append("CANCEL")
		main.menu_mode = "cutscene"
		main.modal = main.menu
		main.menu.open(partner_labels, Vector2(88, 8))     # the partner's side, frozen
		main.menu.push_under()
		main.menu.open(my_labels, Vector2(8, 8), true)     # your side, live
		var idx: int = await main.menu.chosen
		main.modal = null
		if idx < 0 or idx >= main.player_party.size():
			main.link.send_message({"t": "tc_cancel"})
			_tc_result = "canceled"
			await say("The trade was\ncanceled.")          # costs nothing (spec story 12)
			return
		main.link.send_message({"t": "tc_pick", "idx": idx})
		main._maybe_kill("pick")
		# --- the partner's pick (HUMAN-paced: they may browse; B stands up) ---
		main.modal = main.textbox
		main.textbox.show_ask("Waiting for your\nfriend to choose...")
		var got := await _tc_wait(func() -> bool: return not _tc_q_pick.is_empty(), true)
		main.textbox.visible = false
		main.textbox.active = false
		main.textbox.held = false
		main.modal = null
		if got == -1:
			main.link.send_message({"t": "tc_cancel"})
			_tc_result = "canceled"
			await say("The trade was\ncanceled.")
			return
		if got == 2:
			_tc_result = "resumed"         # gh #13: pre-commit — the round restarts at the picks
			return
		if got == 0:
			_tc_result = "aborted"
			print("[tc] abort: no partner pick (link=%s)" % main.link.state)
			await say("The link has been\nclosed.")
			return
		var peer_pick := int(_tc_q_pick.pop_front())
		if peer_pick < 0 or peer_pick >= _tc_peer_party.size():
			_tc_result = "canceled"
			await say("Your friend\ncanceled the trade.")
			return
		var theirs: Dictionary = _tc_peer_party[peer_pick]
		# --- mutual confirm ---
		var yes := await ask("Trade %s\nfor %s?" % [
			str(main.player_party[idx]["name"]), _tc_rec_name(theirs)])
		main.link.send_message({"t": "tc_confirm", "yes": yes})
		main._maybe_kill("confirm")
		while true:                                        # human-paced: they're reading the offer
			got = await _tc_wait(func() -> bool: return not _tc_q_confirm.is_empty(), true)
			if got != -1:                                  # (B does nothing here — answers are quick,
				break                                      #  and a second cancel would desync rounds)
		if got == 2:
			_tc_result = "resumed"         # gh #13: pre-commit — the round restarts at the picks
			return
		if got == 0:
			_tc_result = "aborted"
			print("[tc] abort: no partner confirm (link=%s)" % main.link.state)
			await say("The link has been\nclosed.")
			return
		if not (yes and bool(_tc_q_confirm.pop_front())):
			await say("The trade was\ncanceled.")
			continue                                       # back to the pick screens, as on cartridge
		# --- two-phase commit ---
		if await _tc_commit(idx):
			return
		return


## Phase 1: exchange the authoritative records; journal. Phase 2: exchange acks; only when
## both are in does either side apply + save. Returns true when the flow is over.
func _tc_commit(idx: int) -> bool:
	var give: Dictionary = main.player_party[idx]
	_tc_in_commit = true
	_tc_q_ack = 0    # gh #13: a partner ack can never precede our tc_commit — anything counted
	                 # here is a stale leftover (a resumed round) and must not satisfy this wait
	main.link.send_message({"t": "tc_commit", "record": main.monrecord.encode(give)})
	main._maybe_kill("commit")
	var got := await _tc_wait(func() -> bool: return not _tc_q_record.is_empty())
	if got == 2:
		return await _tc_commit_reconcile(idx, give, "")   # resumed pre-journal
	if got != 1:
		_tc_result = "aborted"
		print("[tc] abort: no partner record (link=%s)" % main.link.state)
		if main.link.state == "linked":
			main.link.close("unresponsive")   # a protocol timeout IS a dead partner: close,
		await say("The link has been\nclosed.\fThe trade did not\nhappen.")   # so the room kick fires now
		return true
	var peer_record: Dictionary = _tc_q_record.pop_front()
	var decoded: Dictionary = main.monrecord.decode(peer_record)
	if not bool(decoded["ok"]):
		print("[tc] abort: partner record refused — %s" % decoded["error"])
		main.link.close("bad-record")
		_tc_result = "aborted"
		await say("The trade data\nwas invalid!\f(%s)\fThe trade did not\nhappen." % decoded["error"])
		return true
	var dupe := bool(main.link.session.get("dupe", false))
	main._tc_journal_write("ready", give, peer_record, dupe)   # pre-ack: recovery rolls back
	# The point of no return: from the instant our ack CAN reach them, they may complete —
	# so the journal flips to "acked" (recovery rolls forward) BEFORE the ack is sent.
	main._tc_journal_write("acked", give, peer_record, dupe)
	main.link.send_message({"t": "tc_ack"})
	main._maybe_kill("ack")
	got = await _tc_wait(func() -> bool: return _tc_q_ack > 0)
	if got == 2:
		return await _tc_commit_reconcile(idx, give, "acked", peer_record)
	if got != 1:
		main._tc_journal_clear()                           # never acknowledged: nothing applied
		_tc_result = "aborted"
		print("[tc] abort: no partner ack (link=%s)" % main.link.state)
		if main.link.state == "linked":
			main.link.close("unresponsive")
		await say("The link has been\nclosed.\fThe trade did not\nhappen.")
		return true
	_tc_q_ack -= 1
	return await _tc_apply(idx, give, decoded["mon"])


## gh #13 (ADR-016): the session dropped and came back MID-COMMIT. Exchange journal phases;
## the MAX phase wins — "acked" is the point of no return, so if EITHER side reached it the
## trade completes on both (the phase report itself proves the partner's commit; it carries
## the acked side's record so a pre-journal partner can complete without another round-trip),
## and if neither did, both roll back to the pick screens. A grace expiry mid-reconcile falls
## back to today's teardown: the journal decides at next boot, exactly like a drop.
func _tc_commit_reconcile(idx: int, give: Dictionary, my_phase: String, peer_record := {}) -> bool:
	print("[tc] resume reconcile: our commit phase '%s'" % my_phase)
	var report := {"t": "tc_resume", "phase": my_phase}
	if my_phase == "acked":
		report["record"] = main.monrecord.encode(give)
	main.link.send_message(report)
	var got := await _tc_wait(func() -> bool: return not _tc_q_resume.is_empty())
	if got == 2:
		return await _tc_commit_reconcile(idx, give, my_phase, peer_record)   # a second blip
	if got != 1:
		_tc_result = "aborted"
		print("[tc] abort: reconcile got no phase report (link=%s)" % main.link.state)
		await say("The link has been\nclosed.")
		return true
	var theirs: Dictionary = _tc_q_resume.pop_front()
	var their_phase := str(theirs.get("phase", ""))
	print("[tc] resume reconcile: phases '%s' + '%s'" % [my_phase, their_phase])
	# "done" = the partner already applied (their side had both acks) — committed by definition.
	# ""+"done" cannot occur: their completion needed OUR ack, which "" never sent.
	var they_committed := their_phase == "acked" or their_phase == "done"
	if my_phase != "acked" and not they_committed:
		main._tc_journal_clear()               # neither committed: the round is void
		_tc_result = "resumed"                 # -> restart at the pick screens
		return true
	if my_phase != "acked":
		# The partner is past the point of no return and we never journaled: roll forward on
		# the record their report carries (the two-generals closure, ADR-016).
		var rec: Dictionary = theirs.get("record", {})
		if not _tc_q_record.is_empty():        # rare: their tc_commit landed just before the blip
			rec = _tc_q_record.pop_front()
		var decoded: Dictionary = main.monrecord.decode(rec)
		if not bool(decoded["ok"]):
			print("[tc] abort: reconcile record refused — %s" % decoded["error"])
			main.link.close("bad-record")
			_tc_result = "aborted"
			await say("The trade data\nwas invalid!\f(%s)\fThe trade did not\nhappen." % decoded["error"])
			return true
		peer_record = rec
		var dupe := bool(main.link.session.get("dupe", false))
		main._tc_journal_write("ready", give, peer_record, dupe)
		main._tc_journal_write("acked", give, peer_record, dupe)
	var decoded2: Dictionary = main.monrecord.decode(peer_record)
	if not bool(decoded2["ok"]):
		print("[tc] abort: reconcile journal record refused — %s" % decoded2["error"])
		main.link.close("bad-record")
		_tc_result = "aborted"
		await say("The trade data\nwas invalid!\fThe trade did not\nhappen.")
		return true
	return await _tc_apply(idx, give, decoded2["mon"])


## Both sides committed: apply, ceremony, save — the shared tail of the normal commit and the
## resume reconcile (gh #13).
func _tc_apply(idx: int, give: Dictionary, received: Dictionary) -> bool:
	var give_sp := str(give["species"])
	var give_ot := str(give.get("ot", main.player_name))
	var give_otid := int(give.get("otid", main.player_id))
	var partner := str((main.link.session.get("remote", {}) as Dictionary).get("name", "TRAINER"))
	main.player_party.remove_at(idx)
	await main.trademovie.play(give_sp, give_ot, give_otid,
		str(received["species"]), int(received.get("otid", 0)),
		partner, str(received.get("ot", partner)))
	if main.player_party.size() < 6:                       # a trade never strands a mon
		main.player_party.append(received)
	else:
		main.pc_box.append(received)
	main.mark_owned(str(received["species"]))
	if main.audio:
		main.audio.play_sfx("get_key_item")
	await say("%s traded\n%s for\n%s!" % [main.player_name, give["name"], received["name"]])
	# Trade evolution on arrival, forced (InGameTrade_CheckForTradeEvo; spec story 9).
	for ev in main.mon_base[str(received["species"])]["evolutions"]:
		if str(ev[0]) == "EVOLVE_TRADE" and int(received["level"]) >= int(ev[1]):
			await main.run_evolution(received, str(ev[2]), true)
			break
	main.save_game()                                       # finalize
	main._tc_journal_clear()
	# gh #13: a partner's tc_resume report may have landed while we were applying (we were
	# still in the commit section, so it queued rather than auto-answering). Answer it NOW —
	# "done" rolls their acked side forward — and flush, so even an immediately-ending
	# process can't swallow the answer. Without this the partner starves to grace expiry.
	while not _tc_q_resume.is_empty():
		_tc_q_resume.pop_front()
		main.link.send_message({"t": "tc_resume", "phase": "done"})
		if main.link._enet != null:
			main.link._enet.flush()
	_tc_peer_party = []           # a second trade re-exchanges the (changed) parties
	_tc_result = "done"
	return true


func _tc_rec_name(rec: Dictionary) -> String:
	return str(rec.get("nickname", str(rec.get("species", "?")).replace("species:", "").to_upper()))


# ---- the Colosseum (gh #7, ADR-014) ----------------------------------------
# Both players at the battle table: parties cross as mon records, the HOST fixes the shared
# seed, and both engines run the identical lockstep battle (Battle.start_link) — only
# chosen actions cross from here on (col_act / col_swap, routed to the battle's queues by
# the room handler above).

var _col_peer := {}                 # the partner's col_party message


func colosseum_table() -> void:
	if main.link.state != "linked":
		await say("The link has been\nclosed.")
		return
	main.cutscene_active = true
	main.link.resume_armed = true          # gh #13: stays armed through the battle itself;
	_tc_resumed = false                    # cleared by _on_battle_finished / the exits below
	var my_seed := 0
	while true:
		var mine: Array = []
		for m in main.player_party:
			mine.append(main.monrecord.encode(m))
		my_seed = int(randi() & 0x7fffffff)              # only the host's is used
		main.link.send_message({"t": "col_party", "mons": mine,
			"name": main.player_name, "seed": my_seed})
		main.modal = main.textbox
		main.textbox.show_ask("Waiting for your\nfriend...")
		var stood_up := false
		var lost_box := false
		var restart := false
		while _col_peer.is_empty():
			if _tc_resumed:
				_tc_resumed = false
				restart = true             # our col_party may have died in flight — resend
				break
			if main.link.holding():
				if not lost_box:
					lost_box = true
					main.textbox.show_ask("Link lost -\nwaiting for your\npartner...")
				await main.get_tree().process_frame
				continue
			if lost_box:
				lost_box = false
				main.textbox.show_ask("Waiting for your\nfriend...")
				continue
			if main.link.state != "linked":
				break
			if Input.is_action_just_pressed("ui_cancel"):
				stood_up = true
				break
			await main.get_tree().process_frame
		main.textbox.visible = false
		main.textbox.active = false
		main.textbox.held = false
		main.modal = null
		if restart:
			# (_tc_on_resumed already cleared _col_peer, race-free.)
			print("[col] table: session resumed — re-exchanging parties")
			continue
		if stood_up:
			main.link.resume_armed = false
			main.cutscene_active = false
			return
		if _col_peer.is_empty():
			main.link.resume_armed = false
			await say("The link has been\nclosed.")
			main.cutscene_active = false
			return
		break
	var seed_v := my_seed if main.link.is_host else int(_col_peer.get("seed", 0))
	var pname := str(_col_peer.get("name", "FRIEND"))
	var records: Array = _col_peer.get("mons", [])
	_col_peer = {}                                       # a rematch re-exchanges
	main.cutscene_active = false
	if not main.start_colosseum_battle(records, seed_v, pname):
		main.link.resume_armed = false
		main.link.close("bad-party")
		await say("The battle data\nwas invalid!")


## gh #5: the joiner types a direct IP on the naming-screen keyboard (address mode); the
## last-used address is the ED default. "" = backed out empty with no default.
func ask_address() -> String:
	main.modal = main.naming
	main.naming.open_address(main.link_last_addr)
	var a: String = await main.naming.done
	main.modal = null
	main.naming.visible = false
	return a.strip_edges()


## Open a cursor menu and await the chosen index (-1 on cancel), like ask_yes_no.
func pick(labels: Array, at: Vector2) -> int:
	main.menu_mode = "cutscene"
	main.modal = main.menu
	main.menu.open(labels, at)
	var idx: int = await main.menu.chosen
	main.modal = null
	return idx


## Take coins and hand over a prize. Returns 0 = bought, 1 = not enough coins, 2 = no room.
func give_prize(p: Dictionary, is_tm: bool) -> int:
	var cost := int(p["cost"])
	if main.player_coins < cost:
		return 1
	if is_tm:
		var tm := str(p["tm"])
		if not main.add_item(tm):                    # gh #174: TM prizes obey the 20-slot bag limit too
			return 2                                 # no room -> no charge (VendingMachine-style .BagFull)
	elif main.player_party.size() < 6:
		main.player_party.append(main.make_mon(str(p["mon"]), int(p["lv"]), []))
	elif main.pc_box.size() < 20:
		main.pc_box.append(main.make_mon(str(p["mon"]), int(p["lv"]), []))
	else:
		return 2
	main.player_coins -= cost
	return 0


## Game Corner prize counter (engine/events/prize_menu.asm CeladonPrizeMenu). which = 0/1/2.
func prize_vendor(which: int) -> void:
	main.cutscene_active = true
	main.modal = null
	if not main.player_bag.has("COIN CASE"):
		await say("A COIN CASE is\nrequired!")
		main.cutscene_active = false
		return
	await say("We exchange your\ncoins for prizes.")
	var is_tm := which == 2
	var prizes: Array = _PRIZES[which]
	var labels: Array = []
	for p in prizes:
		var nm := str(p["name"])
		var price := str(int(p["cost"]))
		labels.append(nm + " ".repeat(maxi(1, 13 - nm.length() - price.length())) + price)
	labels.append("NO THANKS")
	var idx: int = await pick(labels, Vector2(8, 16))
	if idx < 0 or idx >= prizes.size():
		main.cutscene_active = false
		return
	var prize: Dictionary = prizes[idx]
	if not await ask("So, you want\n%s?" % str(prize["name"])):
		await say("Oh, fine then.")
		main.cutscene_active = false
		return
	match give_prize(prize, is_tm):
		1:
			await say("Sorry, you need\nmore coins.")
		2:
			await say("You have no room\nfor this!")
		_:
			if main.audio:
				main.audio.play_sfx("get_item1")
			await say("Here you are!")
	main.cutscene_active = false


## Daisy, the rival's sister (scripts/BluesHouse.asm): gives the TOWN MAP once you have the Pokédex.
func daisy_town_map() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_TOWN_MAP"):
		await say("Use the TOWN MAP\nto find out where\nyou are.")
		main.cutscene_active = false
		return
	if not main.has_event("GOT_POKEDEX"):
		await say("Hi %s!\n%s is out at\nGrandpa's lab." % [main.player_name, main.rival_name])
		main.cutscene_active = false
		return
	await say("Grandpa asked you\nto run an errand?\nHere, this will\nhelp you!")
	if not await _gift("TOWN MAP"):
		return
	if main.audio:
		main.audio.play_sfx("get_item1")
	await say("%s got the\nTOWN MAP!" % main.player_name)
	main.set_event("GOT_TOWN_MAP")
	await say("Use the TOWN MAP\nto find out where\nyou are.")
	main.cutscene_active = false


## Celadon Diner gambler (scripts/CeladonDiner.asm): the busted slot player gives the COIN CASE.
func coin_case_giver() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_COIN_CASE"):
		await say("I always thought\nI was going to\nwin it back...")
		main.cutscene_active = false
		return
	await say("Go ahead! Laugh!\fI'm flat out\nbusted!\fNo more slots for\nme! I'm going\nstraight!\fHere! I won't be\nneeding this any-\nmore!")
	if not await _gift("COIN CASE"):
		return
	if main.audio:
		main.audio.play_sfx("get_key_item")
	await say("%s received\na COIN CASE!" % main.player_name)
	main.set_event("GOT_COIN_CASE")
	main.cutscene_active = false


## The Safari Zone gate: pay ¥500 for 30 SAFARI BALLs + a 500-step game, then enter the park.
func safari_gate(dest_label: String, dest_warp: int) -> void:
	main.cutscene_active = true
	main.modal = null
	main.moneybox.show_box()                  # MONEY_BOX before the join prompt (SafariZoneGate.asm)
	if not await ask("Welcome to the\nSAFARI ZONE!\fFor just ¥500, you\ncan catch all the\nPOKéMON you want\nin the park!\fWould you like to\njoin the hunt?"):
		await say("OK. Please come\nagain!")
		main.moneybox.hide_box()
		main.cutscene_active = false
		return
	if main.player_money < 500:
		await say("Oh? You don't have\nenough money...")
		main.moneybox.hide_box()
		main.cutscene_active = false
		return
	main.player_money -= 500
	main.moneybox.refresh()                   # redrawn right after SubBCDPredef; the
	                                          # entry load_world clears it with the map
	main.safari_balls = 30
	main.safari_steps = 500
	main.in_safari = true
	main.set_event("IN_SAFARI_ZONE")
	if main.audio:
		main.audio.play_sfx("purchase")
	await say("That'll be ¥500!\fWe'll call you on\nthe PA when you're\nout of time.\fEnjoy!")
	main.cutscene_active = false
	main.load_world(dest_label, dest_warp)


## The Safari game ending (safari_game.asm SafariZoneGameOver, then SafariZoneGate.asm
## SafariZoneGateLeavingSafariScript). The PA rings and the announcement is read out BEFORE the
## eject: SafariZoneGameOver sets wSafariZoneGameOver last, and it is that flag that makes
## OverworldLoop take the WarpFound2 branch on a later iteration — so the warp is the closing beat,
## not the opening one (gh #171). At the gate the worker signs you out, takes the BALLs back, and
## walks you south out of the park.
func safari_game_over() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.audio:
		main.audio.stop()                            # wAudioFadeOutControl = 0, SFX_STOP_ALL_MUSIC
		main.audio.play_sfx("safari_zone_pa")        # PlayMusic SFX_SAFARI_ZONE_PA
		await get_tree().process_frame               # .waitForMusicToPlay polls CHAN5 until the PA
		await get_tree().process_frame               # has started; the announcement reads over it
	# SafariGameOverText prints TimesUpText only while BALLs remain (jr z, .noMoreSafariBalls).
	if main.safari_balls > 0:
		await say("PA: Ding-dong!\fTime's up!")
	await say("PA: Your SAFARI\nGAME is over!")
	main.load_world("SafariZoneGate", 2)             # wDestinationWarpID $3 = the park-side door
	main.end_safari_game()                           # ResetEventReuseHL EVENT_IN_SAFARI_ZONE — the
	                                                 # reset lives in the gate script, post-warp
	# PLAYER_DIR_DOWN sets wPlayerMovingDirection — the heading the auto-walk below takes, and how
	# you stand while the worker talks.
	main.player.face(DOWN)
	await say("Did you get a\ngood haul?\nCome again!")
	main.safari_balls = 0                            # wNumSafariBalls = 0, after the worker's line
	await walk_forward(main.player, DOWN, 3)         # SafariZoneEntranceAutoWalk PAD_DOWN, c = 3
	main.cutscene_active = false


## The Safari Zone secret-house guru rewards reaching him with HM03 (SURF).
func safari_surf_guru() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_HM03"):
		await say("HM03 is SURF!\fPOKéMON will be\nable to ferry you\nacross water!")
		main.cutscene_active = false
		return
	await say("Ah! Finally!\fYou're the first\nperson to reach\nthe SECRET HOUSE!\fHere is your\nprize!")
	if not await _gift("HM03"):
		return
	if main.audio:
		main.audio.play_sfx("get_key_item")
	await say("%s received\nHM03!" % main.player_name)
	main.set_event("GOT_HM03")
	await say("HM03 is SURF!\fPOKéMON will be\nable to ferry you\nacross water!")
	main.cutscene_active = false


## The Pokémon Fan Club chairman rambles about his RAPIDASH, then gives the BIKE VOUCHER.
func fan_club_chairman() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_BIKE_VOUCHER") or main.player_bag.has("BICYCLE"):
		await say("Exchange that\nVOUCHER for a\nBICYCLE!\fMy FEAROW will\nFLY me anywhere,\nso I don't need\none. Enjoy!")
		main.cutscene_active = false
		return
	if not await ask("I chair the\nPOKéMON Fan Club!\fI have collected\nover 100 POKéMON!\fSo... Did you come\nto hear about my\nPOKéMON?"):
		await say("Oh. Come back\nany time.")
		main.cutscene_active = false
		return
	await say("Good! Then listen\nup!\fMy favorite\nRAPIDASH... cute...\nlovely... smart...\namazing...\f...Oops! I kept\nyou too long!\fThanks for hearing\nme out! I want you\nto have this!")
	if not await _gift("BIKE VOUCHER"):
		return
	if main.audio:
		main.audio.play_sfx("get_key_item")
	await say("%s received\na BIKE VOUCHER!" % main.player_name)
	main.set_event("GOT_BIKE_VOUCHER")
	main.cutscene_active = false


## The Cerulean Bike Shop trades the BIKE VOUCHER for a BICYCLE.
func bike_shop_clerk() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_BICYCLE"):
		await say("How do you like\nyour BICYCLE?\fIsn't it great?")
	elif main.player_bag.has("BIKE VOUCHER"):
		await say("Oh, that's...\fA BIKE VOUCHER!\fOK! Here you go!")
		main.player_bag.erase("BIKE VOUCHER")
		main.player_bag["BICYCLE"] = 1
		if main.audio:
			main.audio.play_sfx("get_item1")
		await say("%s exchanged\nthe BIKE VOUCHER\nfor a BICYCLE." % main.player_name)
		main.set_event("GOT_BICYCLE")
	else:
		await say("Hi! Welcome to\nthe BICYCLE SHOP!\fOur bargain price\nfor that model is\n¥1,000,000!\fHaha! No one can\nafford that!")
	main.cutscene_active = false


# ---- Fishing (scripts/VermilionOldRodHouse.asm, engine/items/item_effects.asm) ----

## The Vermilion Fishing Guru gives the OLD ROD.
func old_rod_guru() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_OLD_ROD"):
		await say("Hello there,\n%s!\fHow are the fish\nbiting?" % main.player_name)
		main.cutscene_active = false
		return
	if not await ask("I'm the FISHING\nGURU!\fI simply Looove\nfishing!\fDo you like to\nfish?"):
		await say("Oh... That's so\ndisappointing...")
		main.cutscene_active = false
		return
	await say("Grand! I like\nyour style!\fTake this and\nfish, young one!")
	if not await _gift("OLD ROD"):
		return
	if main.audio:
		main.audio.play_sfx("get_item1")
	await say("%s received\nan OLD ROD!" % main.player_name)
	main.set_event("GOT_OLD_ROD")
	main.cutscene_active = false


## The Fuchsia Good Rod house guru (scripts/FuchsiaGoodRodHouse.asm).
func good_rod_guru() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_GOOD_ROD"):
		await say("Hello there,\n%s!\fHow are the fish\nbiting?" % main.player_name)
		main.cutscene_active = false
		return
	if not await ask("I'm the FISHING\nGURU's older\nbrother!\fI simply Looove\nfishing!\fDo you like to\nfish?"):
		await say("Oh... That's so\ndisappointing...")
		main.cutscene_active = false
		return
	await say("Grand! I like\nyour style!\fTake this and\nfish, young one!")
	if not await _gift("GOOD ROD"):
		return
	if main.audio:
		main.audio.play_sfx("get_item1")
	await say("%s received\na GOOD ROD!" % main.player_name)
	main.set_event("GOT_GOOD_ROD")
	main.cutscene_active = false


## The Route 12 Super Rod house guru (scripts/Route12SuperRodHouse.asm).
func super_rod_guru() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_SUPER_ROD"):
		await say("Hello there,\n%s!\fUse the SUPER ROD\nin any water!\nYou can catch\nbetter POKéMON." % main.player_name)
		main.cutscene_active = false
		return
	if not await ask("I'm the FISHING\nGURU's brother!\fI simply Looove\nfishing!\fDo you like to\nfish?"):
		await say("Oh... That's so\ndisappointing...")
		main.cutscene_active = false
		return
	await say("Grand! I like\nyour style!\fTake this and\nfish, young one!")
	if not await _gift("SUPER ROD"):
		return
	if main.audio:
		main.audio.play_sfx("get_item1")
	await say("%s received\na SUPER ROD!" % main.player_name)
	main.set_event("GOT_SUPER_ROD")
	main.cutscene_active = false


## Route 2 Oak's Aide: gives HM05 (FLASH) once you've caught 10 kinds of POKéMON.
## PROF.OAK's dex-count aides (Route11Gate2F: ITEMFINDER at 30, Route15Gate2F: EXP.ALL at 50 —
## same flow as the Route 2 FLASH aide below).
func oaks_aide(item: String, need: int, event: String, info: String) -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event(event):
		await say(info)
		main.cutscene_active = false
		return
	if not await ask("Hi! Remember me?\nI'm PROF.OAK's\nAIDE!\fIf you caught %d\nkinds of POKéMON,\nI'm supposed to\ngive you\n%s!" % [need, item]):
		await say("Oh. I see.\fWhen you get %d\nkinds, come back\nfor %s." % [need, item])
		main.cutscene_active = false
		return
	main._sync_owned()
	var owned: int = main.pokedex_owned.size()
	if owned < need:
		await say("Let's see...\fUh-oh! You have\ncaught only %d\nkinds of POKéMON!\fYou need %d kinds\nif you want\n%s." % [owned, need, item])
	elif not main.add_item(item):
		await say("You have no more\nroom for items!")
	else:
		await say("Great! You have\ncaught %d kinds\nof POKéMON!\fCongratulations!\nHere you go!" % owned)
		if main.audio:
			main.audio.play_sfx("get_key_item")
		await say("%s got\nthe %s!" % [main.player_name, item])
		main.set_event(event)
		await say(info)
	main.cutscene_active = false


func oaks_aide_flash() -> void:
	main.cutscene_active = true
	main.modal = null
	var flash_info := "The HM FLASH\nlights even the\ndarkest dungeons."
	if main.has_event("GOT_HM05"):
		await say(flash_info)
		main.cutscene_active = false
		return
	if not await ask("Hi! Remember me?\nI'm PROF.OAK's\nAIDE!\fIf you caught 10\nkinds of POKéMON,\nI'm supposed to\ngive you HM05!"):
		await say("Oh. I see.\fWhen you get 10\nkinds, come back\nfor HM05.")
		main.cutscene_active = false
		return
	main._sync_owned()
	var owned: int = main.pokedex_owned.size()
	if owned < 10:
		await say("Let's see...\fUh-oh! You have\ncaught only %d\nkinds of POKéMON!\fYou need 10 kinds\nif you want HM05." % owned)
		main.cutscene_active = false
		return
	await say("Great! You have\ncaught %d kinds\nof POKéMON!\fCongratulations!\nHere you go!" % owned)
	if not await _gift("HM05"):
		return
	if main.audio:
		main.audio.play_sfx("get_key_item")
	await say("%s got\nHM05!" % main.player_name)
	main.set_event("GOT_HM05")
	await say(flash_info)
	main.cutscene_active = false


## A bite — start the wild battle the rod hooked.
func fish(species: String, level: int) -> void:
	main.cutscene_active = true
	main.modal = null
	await say("It's a bite!")
	main.cutscene_active = false
	main.start_battle(species, level)


# ---- Cerulean rival battle (scripts/CeruleanCity.asm) ----------------------

# Player starter -> OPP_RIVAL1 party number for the Cerulean bridge battle.
const _CERULEAN_RIVAL_PARTY := {"squirtle": 7, "bulbasaur": 8, "charmander": 9}


# Player starter -> OPP_RIVAL2 party for the Pokémon Tower battle (scripts/PokemonTower2F.asm).
const _TOWER_RIVAL_PARTY := {"squirtle": 4, "bulbasaur": 5, "charmander": 6}


# ---- Pokémon Tower: Marowak ghost -> Mr. Fuji -> Poké Flute -----------------

## Add a mon to the party, or the box if the party is full. Returns false if both are full.
var _last_received: Dictionary = {}   # the mon added by the most recent _receive_mon (for nicknaming)


func _receive_mon(species: String, level: int) -> bool:
	var m: Dictionary = main.make_mon(species, level, [])
	if main.player_party.size() < 6:
		main.player_party.append(m)
	elif main.pc_box.size() < 20:
		main.pc_box.append(m)
	else:
		return false
	_last_received = m
	return true


## Fossil -> revived Pokémon (engine/events/cinnabar_lab.asm).
const _FOSSIL_MON := {"DOME FOSSIL": "kabuto", "HELIX FOSSIL": "omanyte", "OLD AMBER": "aerodactyl"}


## The Cinnabar Lab fossil scientist: take a fossil, revive it after you walk away and return.
func revive_fossil() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GAVE_FOSSIL_TO_LAB"):
		if main.has_event("LAB_STILL_REVIVING_FOSSIL"):
			await say("Come see me in a\nwhile. Go take a\nwalk.")
			main.cutscene_active = false
			return
		await say("It's done!\fYour fossil came\nback to life!")
		_receive_mon(main.fossil_mon, 30)
		if main.audio:
			main.audio.play_sfx("get_item1")
		await say("%s received\n%s!" % [main.player_name, String(main.fossil_mon).to_upper()])
		await offer_nickname(_last_received)
		main.story_events.erase("GAVE_FOSSIL_TO_LAB")
		main.story_events.erase("LAB_STILL_REVIVING_FOSSIL")
		main.fossil_mon = ""
		main.cutscene_active = false
		return
	var fossils: Array = []
	for f in _FOSSIL_MON:
		if main.player_bag.has(f):
			fossils.append(f)
	if fossils.is_empty():
		await say("Bring me a\nFOSSIL and I'll\nrevive it!")
		main.cutscene_active = false
		return
	var chosen: String = fossils[0]
	if fossils.size() > 1:
		var labels := fossils.duplicate()
		labels.append("CANCEL")
		var idx: int = await pick(labels, Vector2(8, 16))
		if idx < 0 or idx >= fossils.size():
			main.cutscene_active = false
			return
		chosen = fossils[idx]
	else:
		if not await ask("Is that a\n%s?\fShall I take a\nlook at it?" % chosen):
			main.cutscene_active = false
			return
	main.player_bag.erase(chosen)
	main.fossil_mon = _FOSSIL_MON[chosen]
	main.set_event("GAVE_FOSSIL_TO_LAB")
	main.set_event("LAB_STILL_REVIVING_FOSSIL")
	await say("All right. Leave\nit and go for a\nwalk. Come back\nlater.")
	main.cutscene_active = false


## A stationary legendary (Articuno/Zapdos/Moltres/Mewtwo): a catchable wild battle. Defeating or
## catching it removes it for good (data/maps/objects/*.asm; the trainer-header wild engagement).
func static_encounter(npc) -> void:
	main.cutscene_active = true
	main.modal = null
	var species: String = npc.wild_species
	var level: int = npc.wild_level
	main.cutscene_active = false
	main.start_battle(species, level)
	await main.battle.finished
	if main.battle.won or main.battle.caught:
		main.set_event("CAUGHT_STATIC_%s_%d_%d" % [main.center_label, npc.cell.x, npc.cell.y])
		if npc:
			npc.set_shown(false)


## The POKé FLUTE wakes a road-blocking SNORLAX -> a catchable L30 battle; beat/catch it to clear it.
func wake_snorlax(npc) -> void:
	main.cutscene_active = true
	main.modal = null
	await say("The SNORLAX woke\nup!")
	main.cutscene_active = false
	main.start_battle("snorlax", 30)
	await main.battle.finished
	if not (main.battle.won or main.battle.caught):   # catching it clears the road too, not just beating (gh #165)
		return
	main.set_event("BEAT_SNORLAX_" + main.center_label)
	if npc:
		npc.set_shown(false)


## The restless MAROWAK ghost on Tower 6F (needs the SILPH SCOPE to fight).
func marowak_ghost() -> void:
	main.cutscene_active = true
	main.modal = null
	if not main.player_bag.has("SILPH SCOPE"):
		await say("GHOST: Get out...\nGet out...")
		main.cutscene_active = false
		return
	await say("Be gone...\nIntruders...")
	main.cutscene_active = false
	main.battle.unveil = true          # appears as GHOST; the SILPH SCOPE reveal mid-intro
	main.start_battle("marowak", 30)
	await main.battle.finished
	main.battle.unveil = false
	# The script keys on wBattleResult == 0 — a win, but ALSO a POKé DOLL escape (which
	# never writes it): the documented doll trick lays the ghost to rest. RUN and a loss
	# both set it nonzero and leave the ghost blocking.
	if not (main.battle.won or main.battle.doll_escape):
		return
	main.cutscene_active = true
	main.set_event("BEAT_GHOST_MAROWAK")
	await say("The mother's soul\nwas calmed.\fIt departed to\nthe afterlife!")
	main.cutscene_active = false


## Mr. Fuji on Tower 7F: rescued, he asks you to his house (and warps you there).
func mr_fuji_tower() -> void:
	main.cutscene_active = true
	main.modal = null
	var fuji = main._npc_by_key("SPRITE_MR_FUJI@10,3")
	if fuji:
		fuji.face_to(main.player.cell)
	await say("MR.FUJI: Heh? You\ncame to save me?\fThank you. But, I\ncame here of my\nown free will.\f...Come to my\nhouse. I'll be\nwaiting.")
	main.set_event("RESCUED_MR_FUJI")
	main.cutscene_active = false
	main.load_world("MrFujisHouse")


## Mr. Fuji at his house hands over the POKé FLUTE.
func mr_fuji_flute() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.has_event("GOT_POKE_FLUTE"):
		await say("MR.FUJI: Has my\nflute helped you?")
		main.cutscene_active = false
		return
	await say("MR.FUJI: %s.\fYour POKéDEX quest\nmay fail without\nlove for your\nPOKéMON.\fI think this may\nhelp your quest." % main.player_name)
	if not await _gift("POKé FLUTE"):
		return
	if main.audio:
		main.audio.play_sfx("get_key_item")
	await say("%s received\na POKé FLUTE!" % main.player_name)
	main.set_event("GOT_POKE_FLUTE")
	main.cutscene_active = false


## scripts/HallOfFame.asm + engine/movie/credits.asm HallOfFamePC (gh #179). OAK leads you in:
## the entry walk (HallOfFameEntryMovement, UP ×5) stops beside him at the machine, he faces you
## for the Er-hem speech, the Cerulean cave guard goes off duty (HideObject
## TOGGLE_CERULEAN_CAVE_GUY -> the HALL_OF_FAME event, gh #90), the machine records the team, and
## the credits roll. Then HallOfFameResetEventsAndSaveScript: the League resets for a rematch
## (ResetEventRange INDIGO_PLATEAU_EVENTS — champion rival included), the blackout map becomes
## PALLET_TOWN, the game saves itself, and `jp Init` boots back to the title — CONTINUE resumes
## right here on the Hall of Fame floor.
func hall_of_fame() -> void:
	var pn: String = main.player_name
	main.load_world("HallOfFame", 0)                  # hWarpDestinationMap HALL_OF_FAME, warp 1
	if main.audio:
		main.audio.play_song("halloffame")
	await walk(main.player, [UP, UP, UP, UP, UP])     # HallOfFameEntryMovement -> (4,2)
	main.player.face(RIGHT)                           # PLAYER_DIR_RIGHT
	var oak = main._npc_by_key("SPRITE_OAK@5,2")
	if oak:
		oak.face(LEFT)
	await say("OAK: Er-hem!\nCongratulations\n%s!\fThis floor is the\nPOKéMON HALL OF\nFAME!\fPOKéMON LEAGUE\nchampions are\nhonored for their\nexploits here!\fTheir POKéMON are\nalso recorded in\nthe HALL OF FAME!\f%s! You have\nendeavored hard\nto become the new\nLEAGUE champion!\fCongratulations,\n%s, you and\nyour POKéMON are\nHALL OF FAMERs!" % [pn, pn, pn])
	main.set_event("HALL_OF_FAME")                    # the cave guard stands down (gh #90)
	visible = true
	# Register the winning team (sHallOfFame holds up to 50 records, oldest dropped).
	var team: Array = []
	for mon in main.player_party:
		team.append({"species": str(mon["species"]), "name": str(mon["name"]),
			"level": int(mon["level"])})
	main.hall_of_fame.append(team)
	while main.hall_of_fame.size() > 50:
		main.hall_of_fame.pop_front()
	for mon in main.player_party:
		var tex: Texture2D = load("res://assets/pokemon/front/%s.png" % str(mon["species"]))
		if tex:
			pic(tex)
		if main.audio:
			main.audio.play_sfx("get_item1")
		await say("%s\n:L%d" % [mon["name"], int(mon["level"])])
	clear_pic()
	await say("Congratulations,\n%s!\fYou and your\nPOKéMON are now\nin the HALL OF\nFAME!" % pn)
	# HallOfFameResetEventsAndSaveScript. The save is written before the roll so its contents
	# match what pokered saves after it (the resets included); the observable order — credits,
	# THE END held, a button press, the title boot — is the game's.
	main.reset_elite4_gauntlet(true)
	main.respawn_map = "PalletTown"           # wLastBlackoutMap = PALLET_TOWN
	main.save_game()                          # SaveGameData (tests write the isolated file, gh #40)
	await run_credits(true)                   # the staff-credits roll, THE END holds for a button
	visible = false
	main._show_title()                        # jp Init — the boot replays back to the title


## The POKéMON LEAGUE option on the PC (engine/menus/league_pc.asm): replays every Hall of
## Fame team, oldest first — each mon's pic with its name/level under the record number.
func league_pc() -> void:
	main.cutscene_active = true
	main.modal = null
	if main.hall_of_fame.is_empty():
		await say("There are no\nrecords yet!")
		main.cutscene_active = false
		main._open_pc()
		return
	await say("Accessed POKéMON\nLEAGUE's HALL OF\nFAME List.")
	visible = true
	for i in main.hall_of_fame.size():
		var team: Array = main.hall_of_fame[i]
		for mon in team:
			var tex: Texture2D = load("res://assets/pokemon/front/%s.png" % str(mon["species"]))
			if tex:
				pic(tex)
			await say("HALL OF FAME No.%d\f%s :L%d" % [i + 1, str(mon["name"]), int(mon["level"])])
		clear_pic()
	visible = false
	main.cutscene_active = false
	main._open_pc()


## Pokémon Tower 5F's purified zone silently heals the party, then flashes white before its message
## (scripts/PokemonTower5F.asm PokemonTower5FDefaultScript: HealParty, fades, Delay3 twice, text).
func tower_purified_zone() -> void:
	main.cutscene_active = true
	main.modal = null
	main.heal_party()
	await fade_out()
	await wait(6.0 / 60.0)
	await fade_in()
	await say("Entered purified,\nprotected zone!")
	main.cutscene_active = false


## The rival is already on Pokémon Tower 2F; stepping beside him starts the battle, then he leaves.
func tower_rival() -> void:
	main.cutscene_active = true
	main.modal = null
	var pn: String = main.player_name
	var rn: String = main.rival_name
	if main.audio:
		main.audio.play_song("meetrival")
	var rival = main._npc_by_key("SPRITE_BLUE@14,5")
	if rival:
		rival.face_to(main.player.cell)
		main.player.face_to(rival.cell)
	await say("%s: Hey,\n%s! What\nbrings you here?\nYour POKéMON\ndon't look dead!\fI can at least\nmake them faint!\nLet's go, pal!" % [rn, pn])
	var num: int = _TOWER_RIVAL_PARTY.get(_rival_st(), 6)
	main.start_trainer_battle("OPP_RIVAL2", num, "PokemonTower2F:14,5")
	await main.battle.finished
	if not main.battle.won:
		main.cutscene_active = false
		return
	await say("What?\nYou stinker!\fI took it easy on\nyou too!")
	main.set_event("BEAT_POKEMON_TOWER_RIVAL")
	if rival:
		# PokemonTower2F.asm: the rival leaves by an L-path to the stairs, chosen by which side he was
		# on (EVENT_POKEMON_TOWER_RIVAL_ON_LEFT) — the player at (15,5) means the rival is on the left
		# (RivalDownThenRight); at (14,6) the player is below him (RivalRightThenDown). Both end at the
		# 2F stairs (18,9), where he vanishes down.
		var seq: Array = [DOWN, DOWN, RIGHT, RIGHT, RIGHT, RIGHT, DOWN, DOWN] \
			if main.player.cell == Vector2i(15, 5) \
			else [RIGHT, DOWN, DOWN, RIGHT, DOWN, DOWN, RIGHT, RIGHT]
		await walk(rival, seq)
		rival.set_shown(false)
	main.cutscene_active = false


## The rival ambushes the player at the north bridge: he walks down, battles (OPP_RIVAL1, a tougher
## party by starter), then leaves with the hint to thank BILL. Fired from Main._on_player_moved.
func cerulean_rival() -> void:
	main.cutscene_active = true
	main.modal = null
	var pn: String = main.player_name
	var rn: String = main.rival_name
	main.player.face(UP)
	if main.audio:
		main.audio.play_song("meetrival")
	var rival = main._npc_by_key("SPRITE_BLUE@20,2")
	if rival:
		rival.set_shown(true)
		await walk(rival, main.find_path(rival.cell, main.player.cell + Vector2i(0, -1)))
		rival.face_to(main.player.cell)
	await say(("%s: Yo!\n%s!" % [rn, pn])
		+ "\fYou're still\nstruggling along\nback here?"
		+ "\fI'm doing great!\nI caught a bunch\nof strong and\nsmart POKéMON!"
		+ "\fHere, let me see\nwhat you caught,\n%s!" % pn)
	var num: int = _CERULEAN_RIVAL_PARTY.get(_rival_st(), 9)
	main.start_trainer_battle("OPP_RIVAL1", num, "CeruleanCity:20,2")
	await main.battle.finished
	if not main.battle.won:                          # lost / blacked out — control already restored
		main.cutscene_active = false
		return
	await say("Hey!\nTake it easy!\nYou won already!")
	main.set_event("BEAT_CERULEAN_RIVAL")
	await say(("%s: Hey,\nguess what?" % rn)
		+ "\fI went to BILL's\nand got him to\nshow me his rare\nPOKéMON!"
		+ "\fThat added a lot\nof pages to my\nPOKéDEX!"
		+ "\fAfter all, BILL's\nworld famous as a\nPOKéMANIAC!"
		+ "\fHe invented the\nPOKéMON Storage\nSystem on PC!"
		+ "\fSince you're using\nhis system, go\nthank him!"
		+ "\fWell, I better\nget rolling!\nSmell ya later!")
	if rival:
		# He sidesteps around you by bridge lane (CeruleanCityMovement3/4: x==20 steps right,
		# x==21 left), then heads off south into town with the rival jingle re-struck.
		if main.audio:
			main.audio.play_song("meetrival_alt")
		await rival.step(RIGHT if main.player.cell.x == 20 else LEFT)
		for i in 6:
			await rival.step(DOWN)
		rival.set_shown(false)
		if main.audio:
			main.audio.play_map_music(main.center_label)
	main.cutscene_active = false


## The Viridian old man's catching demo (scripts/ViridianCity.asm ViridianCityOldManText +
## BATTLE_TYPE_OLD_MAN): once he's had his coffee he offers to show how to catch — a wild L5
## WEEDLE battle that plays itself, with OLD MAN throwing his own POKé BALL. Real catch odds;
## the WEEDLE is discarded either way. YES to "Are you in a hurry?" skips the lesson.
func oldman_demo(npc) -> void:
	main.cutscene_active = true
	main.modal = null
	if npc:
		npc.face_to(main.player.cell)
	if await ask("Ahh, I've had my\ncoffee now and I\nfeel great!\fSure you can go\nthrough!\fAre you in a\nhurry?"):
		await say("Time is money...\nGo along then.")
		main.cutscene_active = false
		return
	await say("I see you're using\na POKéDEX.\fWhen you catch a\nPOKéMON, POKéDEX\nis automatically\nupdated.\fWhat? Don't you\nknow how to catch\nPOKéMON?\fI'll show you\nhow to then.")
	main.battle.demo = true
	main.start_battle("weedle", 5)
	await main.battle.finished
	main.battle.demo = false
	await say("First, you need\nto weaken the\ntarget POKéMON.")
	main.cutscene_active = false


## Let the player pick a party mon (the party screen as a modal pick); -1 on cancel.
func pick_party_mon() -> int:
	main.menu_mode = "cutscene"
	main.modal = main.menu
	main.menu.open_party(main.player_party, Vector2(8, 8))
	var idx: int = await main.menu.chosen
	main.modal = null
	return idx


## The Dept. Store roof girl (scripts/CeladonMartRoof.asm, exact texts): give her a drink
## from the bag for a TM — FRESH WATER->TM13, SODA POP->TM48, LEMONADE->TM49, each once.
func roof_girl() -> void:
	main.cutscene_active = true
	main.modal = null
	var drinks: Array = []
	for d in ["FRESH WATER", "SODA POP", "LEMONADE"]:
		if int(main.player_bag.get(d, 0)) > 0:
			drinks.append(d)
	if drinks.is_empty():
		await say("I'm thirsty!\nI want something\nto drink!")
		main.cutscene_active = false
		return
	if not await ask("I'm thirsty!\nI want something\nto drink!\fGive her a drink?"):
		await say("No thank you!\nI'm not thirsty\nafter all!")
		main.cutscene_active = false
		return
	main._say_keep("Give her which\ndrink?")
	main.menu_mode = "cutscene"
	main.modal = main.menu
	main.menu.open(drinks, Vector2(104, 40))
	var idx: int = await main.menu.chosen
	main.modal = null
	main.textbox.visible = false
	if idx < 0 or idx >= drinks.size():
		await say("No thank you!\nI'm not thirsty\nafter all!")
		main.cutscene_active = false
		return
	var drink: String = drinks[idx]
	var reward: Array = {
		"FRESH WATER": ["TM_ICE_BEAM", "GOT_TM13",
			"%s contains\nICE BEAM!\fIt can freeze the\ntarget sometimes!"],
		"SODA POP": ["TM_ROCK_SLIDE", "GOT_TM48",
			"%s contains\nROCK SLIDE!\fIt can spook the\ntarget sometimes!"],
		"LEMONADE": ["TM_TRI_ATTACK", "GOT_TM49", "%s contains\nTRI ATTACK!"],
	}[drink]
	if main.has_event(reward[1]):                     # she only wants each drink once
		await say("No thank you!\nI'm not thirsty\nafter all!")
		main.cutscene_active = false
		return
	var tm: String = str(main.item_names.get(reward[0], reward[0]))
	await say("Yay!\f%s!\fThank you!\fYou can have this\nfrom me!" % drink)
	if not main.add_item(tm):
		await say("You don't have\nspace for this!")
		main.cutscene_active = false
		return
	main.player_bag[drink] = int(main.player_bag[drink]) - 1
	if int(main.player_bag[drink]) <= 0:
		main.player_bag.erase(drink)
	main.set_event(reward[1])
	if main.audio:
		main.audio.play_sfx("get_item1")
	await say("%s received\n%s!" % [main.player_name, tm])
	await say(str(reward[2]) % tm)
	main.cutscene_active = false


## Lavender's NAME RATER (scripts/NameRatersHouse.asm, exact texts): rates a party mon's
## nickname and offers the keyboard — but a traded mon (foreign OT) gets the "truly
## impeccable name" refusal, as the asm checks the OT against the player.
func name_rater() -> void:
	main.cutscene_active = true
	main.modal = null
	if not await ask("Hello, hello!\nI am the official\nNAME RATER!\fWant me to rate\nthe nicknames of\nyour POKéMON?"):
		await say("Fine! Come any\ntime you like!")
		main.cutscene_active = false
		return
	await say("Which POKéMON\nshould I look at?")
	var idx := await pick_party_mon()
	if idx < 0 or idx >= main.player_party.size():
		await say("Fine! Come any\ntime you like!")
		main.cutscene_active = false
		return
	var mon: Dictionary = main.player_party[idx]
	var nm := str(mon["name"])
	if str(mon.get("ot", main.player_name)) != main.player_name:
		await say("%s, is it?\nThat is a truly\nimpeccable name!\fTake good care of\n%s!" % [nm, nm])
		main.cutscene_active = false
		return
	if not await ask("%s, is it?\nThat is a decent\nnickname!\fBut, would you\nlike me to give\nit a nicer name?\fHow about it?" % nm):
		await say("Fine! Come any\ntime you like!")
		main.cutscene_active = false
		return
	await say("Fine! What should\nwe name it?")
	var n: String = await ask_name(nm, [nm], "%s's\nnickname?" % nm, true)
	if n.strip_edges() != "":
		mon["name"] = n
	await say("OK! This POKéMON\nhas been renamed\n%s!\fThat's a better\nname than before!" % str(mon["name"]))
	main.cutscene_active = false


var _heal_balls := 0               # poké balls shown on the Center's healing machine
var _heal_flash := false           # OBP1 ^ $28: the two grey planes swap (nothing vanishes)
var _heal_monitor := false         # the machine overlay is up
var _heal_tex_e0: ImageTexture     # heal_machine.png through OBP1 = $e0 (colour 1 -> WHITE)
var _heal_tex_c8: ImageTexture     # ... through $e0 ^ $28 = $c8 (colours 1 and 2 swapped)

const _GB1 := Color(0.710, 0.824, 0.584)   # GB_PALETTE[1] (the sheet's colour-1 ink)
const _GB2 := Color(0.396, 0.541, 0.447)   # GB_PALETTE[2]


## AnimateHealingMachine renders its OAM through OBP1 = $e0: colour 1 maps to WHITE (the lit
## monitor screen and the balls' highlights), colour 2 stays the dark shade, colour 3 black.
## The ×8 flash XORs $28 -> $c8, which swaps colours 1 and 2 — the machine "blinks" by
## exchanging its two grey planes, not by disappearing.
func _heal_palette_tex(flash: bool) -> ImageTexture:
	var img: Image = (load("res://assets/sprites/heal_machine.png") as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var lum := (c.r + c.g + c.b) / 3.0
			if lum >= 0.6:                             # colour 1
				img.set_pixel(x, y, _GB2 if flash else LIGHT)
			elif lum >= 0.3:                           # colour 2
				img.set_pixel(x, y, LIGHT if flash else _GB2)
			else:                                      # colour 3
				img.set_pixel(x, y, DARK)
	return ImageTexture.create_from_image(img)


## The Pokémon Center nurse + AnimateHealingMachine (engine/overworld/healing_machine.asm +
## engine/events/pokecenter.asm), beat for beat: "OK. We'll need your POKéMON." prints with NO
## button wait and sits on screen through the whole animation; the nurse turns to the machine
## ($18 = her left-facing frame); the map music fades to silence; one ball per party mon lands
## with its chime 30 frames apart; the PKMN-healed jingle plays while the machine flashes 8
## times (10 frames a toggle, the palette-plane swap) and runs to its END; a 32-frame beat;
## then "fighting fit!" prints, the nurse BOWS ($14 — the bow graphic lives in her sheet's
## up-facing slot) for 20 frames, and the farewell follows before she stands back up.
func nurse_heal(npc = null) -> void:
	main.cutscene_active = true
	main.modal = null
	# The "Shall we heal your POKéMON?" question only prints the FIRST ever time
	# (BIT_USED_POKECENTER); afterwards the yes/no follows the welcome line directly.
	var q := "Welcome to our\nPOKéMON CENTER!\fWe heal your\nPOKéMON back to\nperfect health!"
	if not main.has_event("USED_POKECENTER"):
		q += "\fShall we heal your\nPOKéMON?"
	main.set_event("USED_POKECENTER")
	if not await ask(q):
		await say("We hope to see\nyou again!")
		main.cutscene_active = false
		return
	main.modal = main.textbox
	main.textbox.show_text(main.resolve_text("OK. We'll need\nyour POKéMON."))
	if _heal_tex_e0 == null:
		_heal_tex_e0 = _heal_palette_tex(false)
		_heal_tex_c8 = _heal_palette_tex(true)
	if npc:
		npc.face(npc.LEFT)                            # $18: she turns to work the machine
	main.heal_party()                                 # HealParty runs before the animation
	main.respawn_map = main.center_label              # SetLastBlackoutMap
	await wait(3.0 / 60.0)                            # Delay3
	visible = true
	_heal_monitor = true
	_heal_balls = 0
	_heal_flash = false
	queue_redraw()
	if main.audio:
		main.audio.stop()                             # the music fades out before the first ball
	await wait(0.5)
	for i in mini(main.player_party.size(), 6):       # one ball + chime per mon, 30 frames apart
		_heal_balls = i + 1
		if main.audio:
			main.audio.play_sfx("healing_machine")
		queue_redraw()
		await wait(0.5)
	var jingle := 0.0
	if main.audio:
		main.audio.play_song("pkmnhealed")            # MUSIC_PKMN_HEALED over the flashing
		jingle = main.audio.song_length("pkmnhealed")
	for i in 8:                                       # FlashSprite8Times: toggle every 10 frames
		_heal_flash = not _heal_flash
		queue_redraw()
		await wait(10.0 / 60.0)
	if jingle > 8 * 10.0 / 60.0:                      # .waitLoop2: the jingle plays to its end
		await wait(jingle - 8 * 10.0 / 60.0)
	await wait(32.0 / 60.0)
	_heal_monitor = false
	_heal_balls = 0
	visible = false
	if main.audio:
		main.audio.play_map_music(main.center_label)
	# PokemonFightingFitText prints without a wait; the bow follows while it shows.
	main.modal = main.textbox
	main.textbox.show_text(main.resolve_text("Thank you!\nYour POKéMON are\nfighting fit!"))
	await wait(0.9)                                   # the line types out
	if npc:
		npc.face(npc.UP)                              # $14: the BOW
	await wait(20.0 / 60.0)
	await say("We hope to see\nyou again!")
	if npc:
		npc.face(npc.DOWN)                            # UpdateSprites stands her back up
	main.cutscene_active = false


## Escort helper: both actors walk their own paths simultaneously (the Pewter guys' paired
## RLE movement lists), gating on whichever finishes last.
func _walk_both(npc, npc_to: Vector2i, player_to: Vector2i) -> void:
	var done := [false]
	var w := func() -> void:
		await walk(npc, main.find_path(npc.cell, npc_to))
		done[0] = true
	w.call()
	await walk(main.player, main.find_path(main.player.cell, player_to))
	while not done[0]:
		await main.get_tree().process_frame


## Pewter's museum guy (scripts/PewterCity.asm SuperNerd1 + PewterMovementScript_WalkToMuseum):
## say you haven't seen the museum and he marches you there to MUSIC_MUSEUM_GUY — the player to
## the museum steps, him alongside the door — then sees you off and wanders away south.
func pewter_museum_guy(npc) -> void:
	main.cutscene_active = true
	main.modal = null
	npc.face_to(main.player.cell)
	if await ask("Did you check out\nthe MUSEUM?"):
		await say("Weren't those\nfossils from MT.\nMOON amazing?")
		main.cutscene_active = false
		return
	await say("Really?\nYou absolutely\nhave to go!")
	if main.audio:
		main.audio.play_song("museumguy")
	await _walk_both(npc, Vector2i(13, 8), Vector2i(14, 9))   # the RLE lists' end cells
	npc.face(UP)
	if main.audio:
		main.audio.play_map_music(main.center_label)   # PlayDefaultMusic before the send-off
	await say("It's right here!\nYou have to pay\nto get in, but\nit's worth it!\fSee you around!")
	# MovementData_PewterMuseumGuyExit (gh #70): he's dropped at (13,8) and walks straight
	# down 4 steps — no pathfinding — then hides and is reset to his post, shown again
	# (PewterCityHideSuperNerd1Script + ResetSuperNerd1Script).
	npc.cell = Vector2i(13, 8)
	npc.position = Vector2(npc.cell * 16)
	for i in 4:
		await npc.step(DOWN)
	npc.set_shown(false)
	npc.cell = npc.home
	npc.position = Vector2(npc.cell * 16)
	npc.set_shown(true)
	main.cutscene_active = false


## The evolution movie (engine/movie/evolution.asm EvolveMon + evos_moves.asm, gh #67):
## "What? X is evolving!", the old pic + its cry, the Safari-Zone theme (pokered's evolution
## music), then the accelerating black-silhouette flicker between old and new — B cancels
## unless `forced` (trade evolutions) — ending on the result's pic + cry. Returns false when
## cancelled ("Huh? X stopped evolving!" is said here); the caller applies the species
## change and the evolved/into text. Tests (fast_hp) skip the waits and flicker.
func evolution(nick: String, old_species: String, new_species: String, forced := false) -> bool:
	var fast: bool = main.battle.fast_hp
	main.cutscene_active = true
	main.modal = null
	await say("What? %s\nis evolving!" % nick)
	if main.audio:
		main.audio.stop()
		main.audio.play_sfx("tink")
	var old_tex: Texture2D = load("res://assets/pokemon/front/%s.png" % old_species)
	var new_tex: Texture2D = load("res://assets/pokemon/front/%s.png" % new_species)
	visible = true
	pic(old_tex, Vector2(56, 16))                     # hlcoord 7,2
	if main.audio:
		main.audio.play_cry(old_species)
	if not fast:
		await wait(1.0)
		if main.audio:
			main.audio.play_song("safarizone")        # MUSIC_SAFARI_ZONE, 80 frames before the flicker
		await wait(80.0 / 60.0)
	_pic_sil = true                                   # PAL_BLACK: the flicker runs in silhouette
	queue_redraw()
	var cancelled := false
	var b := 1
	var c := 16
	while c > 0 and not fast:
		# Evolution_CheckForCancel: ONE frame + a B poll per iteration (not a c-frame block), so the
		# flicker stays continuous and accelerating as on the cartridge — the old c-frame poll froze the
		# pic for 16/14/12… frames before each burst, which read as a stutter (gh #135). Held B cancels
		# (pokered's JoypadLowSensitivity), matching how a player actually cancels.
		await main.get_tree().process_frame
		if not forced and Input.is_action_pressed("ui_cancel"):
			cancelled = true
			break
		for i in b:                                   # Evolution_BackAndForthAnim: new then old, b times
			pic(new_tex, Vector2(56, 16))
			await wait(3.0 / 60.0)
			pic(old_tex, Vector2(56, 16))
			await wait(3.0 / 60.0)
		b += 1
		c -= 2
	_pic_sil = false
	pic(old_tex if cancelled else new_tex, Vector2(56, 16))
	if main.audio:
		main.audio.stop()
		main.audio.play_cry(old_species if cancelled else new_species)
	if not fast:
		await wait(1.0)
	if cancelled:
		await say("Huh? %s\nstopped evolving!" % nick)
	clear_pic()
	visible = false
	if main.audio:
		main.audio.play_map_music(main.center_label)
	main.cutscene_active = false
	return not cancelled


## A museum fossil display (hidden_events/museum_fossils.asm, gh #71): the skeleton pic pops
## up (MON_SPRITE_POPUP) with the plaque line, and clears when the text closes.
func museum_fossil(pic_key: String, disp: String) -> void:
	main.cutscene_active = true
	pic(load("res://assets/%s.png" % pic_key))
	await say("%s Fossil\nA primitive and\nrare POKéMON." % disp)
	clear_pic()
	main.cutscene_active = false


## Pewter's gym guide kid (PewterCityYoungsterText + PewterMovementScript_WalkToGym): talk to
## him and he marches you straight to BROCK's gym door, then takes his leave.
func pewter_gym_guy(npc) -> void:
	main.cutscene_active = true
	main.modal = null
	npc.face_to(main.player.cell)
	await say("You're a trainer\nright? BROCK's\nlooking for new\nchallengers!\fFollow me!")
	if main.audio:
		main.audio.play_song("museumguy")
	await _walk_both(npc, Vector2i(17, 18), Vector2i(16, 18))   # just below the gym door
	npc.face_to(main.player.cell)
	if main.audio:
		main.audio.play_map_music(main.center_label)
	await say("If you have the\nright stuff, go\ntake on BROCK!")
	# MovementData_PewterGymGuyExit (gh #70): he's dropped at (12,18) and dashes right 5
	# steps — no pathfinding around the gym — then hides and is reset to his post, shown
	# again for the next challenger (PewterCityHideYoungsterScript + ResetYoungsterScript).
	npc.cell = Vector2i(12, 18)
	npc.position = Vector2(npc.cell * 16)
	for i in 5:
		await npc.step(RIGHT)
	npc.set_shown(false)
	npc.cell = npc.home
	npc.position = Vector2(npc.cell * 16)
	npc.set_shown(true)
	main.cutscene_active = false


# The six gates' block coords (cinnabar_gym_quiz.asm CinnabarGymGateCoords; the load-time
# lay is the CinnabarGym enter event record — this table is the mid-map slide on a right
# answer, which the record's next load then honours via CINNABAR_GATE_<n>).
const _QUIZ_GATE_BLOCKS := [[9, 3], [6, 3], [6, 6], [3, 8], [2, 6], [2, 3]]

# The six Cinnabar quiz questions (data/text/text_2.asm _CinnabarQuizQuestionsText1-6) and
# each gate's room trainer (wOpponentAfterWrongAnswer = gate index + 2 -> the map object).
const _QUIZ_Q := [
	"CATERPIE evolves\ninto BUTTERFREE?",
	"There are 9\ncertified POKéMON\nLEAGUE BADGEs?",
	"POLIWAG evolves 3\ntimes?",
	"Are thunder moves\neffective against\nground element-\ntype POKéMON?",
	"POKéMON of the\nsame kind and\nlevel are not\nidentical?",
	"TM28 contains\nTOMBSTONER?",
]
const _QUIZ_TRAINER := ["SPRITE_SUPER_NERD@17,8", "SPRITE_SUPER_NERD@11,4",
	"SPRITE_SUPER_NERD@11,8", "SPRITE_SUPER_NERD@11,14", "SPRITE_SUPER_NERD@3,14",
	"SPRITE_SUPER_NERD@3,8"]


## The GAME FREAK game designer's DIPLOMA (scripts/CeladonMansion3F.asm CompletedDexText ->
## callfar DisplayDiploma): at NUM_POKEMON - 1 owned (150 — Mew doesn't count) his line leads
## into the diploma card. (Moved verbatim from the retired CeladonMansion3F adapter, gh #40.)
func award_diploma() -> void:
	main.cutscene_active = true
	await say("Wow! Excellent!\nYou completed\nyour POKéDEX!\nCongratulations!\n...")
	main.modal = main.diploma
	main.diploma.open_card()
	await main.diploma.closed
	main.cutscene_active = false


## A Cinnabar Gym quiz machine (engine/events/hidden_events/cinnabar_gym_quiz.asm): a right
## answer opens the room's gate for good (fanfare + the gate slides); a wrong one buzzes and
## sics the room's trainer on you (if still standing).
func cinnabar_quiz(gate: int, yes_correct: bool) -> void:
	main.cutscene_active = true
	main.modal = null
	await say("POKéMON Quiz!\fGet it right and\nthe door opens to\nthe next room!\fGet it wrong and\nface a trainer!\fIf you want to\nconserve your\nPOKéMON for the\nGYM LEADER...\fThen get it right!")
	var yes := await ask(_QUIZ_Q[gate - 1])
	if yes == yes_correct:
		if main.audio:
			main.audio.play_sfx("get_item1")           # the CorrectText fanfare
		await say("You're absolutely\ncorrect!\fGo on through!")
		if not main.has_event("CINNABAR_GATE_%d" % gate):
			main.set_event("CINNABAR_GATE_%d" % gate)
			var gt: Array = _QUIZ_GATE_BLOCKS[gate - 1]
			main.set_block(int(gt[0]), int(gt[1]), 0xE)
			if main.audio:
				main.audio.play_sfx("go_inside")       # SFX_GO_INSIDE as the gate opens
		main.cutscene_active = false
		return
	if main.audio:
		main.audio.play_sfx("denied")
	await say("Sorry! Bad call!")
	main.cutscene_active = false
	var t = main._npc_by_key(_QUIZ_TRAINER[gate - 1])
	if t and t.shown and not main.defeated_trainers.has(main.trainer_id(t)):
		trainer_battle(t, false)                       # the room's trainer jumps you


# ---- Oak's Parcel errand: dissolved into viridian_mart_parcel.json + oaks_lab_oak.json (wave C, gh #41) ----


# ---- trainer battles (home/trainers.asm) -----------------------------------

# Trainer classes that use the special pre-battle music (data/trainers/encounter_types.asm).
const _EVIL_TRAINERS := ["OPP_UNUSED_JUGGLER", "OPP_GAMBLER", "OPP_ROCKER", "OPP_JUGGLER",
	"OPP_CHIEF", "OPP_SCIENTIST", "OPP_GIOVANNI", "OPP_ROCKET"]
const _FEMALE_TRAINERS := ["OPP_LASS", "OPP_JR_TRAINER_F", "OPP_BEAUTY", "OPP_COOLTRAINER_F"]


func _trainer_meet_song(opp_class: String) -> String:
	if opp_class in ["OPP_RIVAL1", "OPP_RIVAL2", "OPP_RIVAL3"]:
		return ""                                  # rivals keep the current track until battle
	if opp_class in _EVIL_TRAINERS:
		return "meeteviltrainer"
	if opp_class in _FEMALE_TRAINERS:
		return "meetfemaletrainer"
	return "meetmaletrainer"


## A trainer spotted the player on sight: show the "!" bubble, march up, then battle.
func trainer_spotted(npc) -> void:
	await trainer_battle(npc, true)


## Run a trainer encounter: optional walk-up (sight), before-battle text, the battle, and the
## winner's end-battle line. Defeat tracking + map music are handled by Main._on_battle_finished.
func trainer_battle(npc, walk_up: bool) -> void:
	main.cutscene_active = true
	main.modal = null
	if walk_up:
		npc.show_emote("shock")
		var song := _trainer_meet_song(npc.trainer_class)
		if main.audio and song != "":
			main.audio.play_song(song)
		await wait(1.0)              # the "!" shows for 60 frames (EmotionBubble DelayFrames 60)
		npc.hide_emote()
		var d: Vector2i = main.player.cell - npc.cell    # lined up: march straight up to the player
		for i in maxi(0, abs(d.x) + abs(d.y) - 1):
			await npc.step(npc.facing)
		npc.face_to(main.player.cell)
	main.player.face_to(npc.cell)
	if npc.battle_text != "":
		await say(npc.battle_text)
	# Route 24 Nugget Bridge boss (a disguised ROCKET): the full scripts/Route24.asm sequence — congratulate
	# the player for the 5-trainer contest, hand over the NUGGET prize, THEN reveal himself and make his
	# "join TEAM ROCKET" pitch, and only then battle (gh #108). The port used to give just the NUGGET.
	if main.center_label == "Route24" and npc.key == "SPRITE_COOLTRAINER_M@11,15" and not main.has_event("GOT_NUGGET"):
		await say("Congratulations!\nYou beat our 5\ncontest trainers!")
		await say("You just earned a\nfabulous prize!")
		if main.add_item("NUGGET"):              # gh #174: the NUGGET obeys the 20-slot bag limit
			main.set_event("GOT_NUGGET")
			if main.audio:
				main.audio.play_sfx("get_item1")
			await say("%s received\na NUGGET!" % main.player_name)
		else:
			await say("You don't have\nroom for this!")   # ...but he reveals himself and battles regardless
		await say("By the way, would\nyou like to join\nTEAM ROCKET?\fWe're a group\ndedicated to evil\nusing POKéMON!\fWant to join?\fAre you sure?\fCome on, join us!\fI'm telling you\nto join!\fOK, you need\nconvincing!\fI'll make you an\noffer you can't\nrefuse!")
	# Cerulean City ROCKET (the TM28/DIG thief): his pre-battle line lives in the map script
	# (TEXT_CERULEANCITY_ROCKET), not a trainer header, so the port had no battle_text for him (gh #110).
	if main.center_label == "CeruleanCity" and npc.key == "SPRITE_ROCKET@30,8" and not main.has_event("GOT_TM28"):
		await say("Hey! Stay out!\nIt's not your\nyard! Huh? Me?\fI'm an innocent\nbystander! Don't\nyou believe me?")
	# Game Corner poster guard: his line lives in the map script (GameCornerRocketText), not a trainer
	# header, so the port had no battle_text for him and he engaged silently (gh #139).
	if main.center_label == "GameCorner" and str(npc.key).begins_with("SPRITE_ROCKET@") and npc.battle_text == "":
		await say("I'm guarding this\nposter!\fGo away, or else!")
	main.start_trainer_battle(npc.trainer_class, npc.trainer_num, main.trainer_id(npc))
	await main.battle.finished
	if not main.battle.won:                          # lost / blacked out — control already restored
		main.cutscene_active = false
		return
	if npc.end_text != "":
		await say(npc.end_text)
	elif main.center_label == "Route24" and npc.key == "SPRITE_COOLTRAINER_M@11,15":
		await say("Arrgh!\nYou are good!")            # the Nugget Bridge ROCKET's defeat line (gh #108)
	# EndTrainerBattle re-runs the map's load callback (home/trainers.asm), so a door this trainer
	# was the last guard of opens right here rather than on the next visit.
	main.map_script(main.center_label).on_battle_end()
	main.cutscene_active = false


# ---- gym leaders (scripts/<Gym>.asm) ---------------------------------------

# wGymLeaderNo identity: the 8 gym-leader fights, class -> the leader's own party number.
# This is engine data — audio/play_battle_music.asm PlayBattleMusic keys the gym-leader
# theme off it in Main.start_trainer_battle — not story: the leaders' script beats live in
# the authored gym records (wave C, gh #41). Giovanni counts only in his gym (party 3) —
# his hideout/Silph encounters use other party numbers.
const _GYM_LEADERS := {
	"OPP_BROCK": 1, "OPP_MISTY": 1, "OPP_LT_SURGE": 1, "OPP_ERIKA": 1,
	"OPP_KOGA": 1, "OPP_SABRINA": 1, "OPP_BLAINE": 1, "OPP_GIOVANNI": 3,
}


func is_gym_leader(opp_class: String) -> bool:
	return _GYM_LEADERS.has(opp_class)


## Is this trainer battle one of the eight gym-leader fights (wGymLeaderNo)?
func is_gym_leader_battle(opp_class: String, num: int) -> bool:
	return _GYM_LEADERS.has(opp_class) and int(_GYM_LEADERS[opp_class]) == num


## Viridian City's sleepy old man blocks the road north until the player has the Pokédex
## (scripts/ViridianCity.asm ViridianCityCheckGotPokedexScript fires at X==19, Y==9).
func viridian_oldman_block() -> void:
	main.cutscene_active = true
	main.modal = null
	await say("You can't go\nthrough here!\fThis is private\nproperty!")
	await main.player.step(DOWN)                   # ViridianCityMovePlayerDownScript pushes you back
	main.cutscene_active = false
