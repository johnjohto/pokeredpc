extends Node2D
## Overworld game root: loads a "world" (the active map + its connected neighbors),
## renders them seamlessly, builds collision across the seam, owns the player, and
## handles warps + connection crossings (rebasing the active map).

const Keybinds = preload("res://scripts/Keybinds.gd")   # user-editable key bindings
const MapScript = preload("res://scripts/MapScripts.gd")  # per-map script adapter base (gh #53)
const EventAdapter = preload("res://scripts/EventMapScript.gd")  # authored-event maps (gh #39)
const TILE := 8
const BLOCK := 32
const CELL := 16
const SUB := [[4, 6], [12, 14]]     # bottom-left tile of each 16px cell (see docs/engine/collision.md)
const OUTSIDE_TILESETS := ["overworld", "plateau"]
const BORDER_MARGIN := 8            # blocks of border drawn around the world
# engine/overworld/player_state.asm CheckForceBikeOrSurf: BIT_ALWAYS_ON_BIKE persists while
# connected-map rebases keep the player inside the Cycling Road corridor.
const FORCE_BIKE_MAPS := {"Route16": true, "Route17": true, "Route18": true}

# HM field moves: the item that teaches each. The badge gating each field move is the
# ruleset progression module's mapping now (gh #34: ruleset.progression.badge_for_field_move).
const HM_MOVES := {"HM01": "CUT", "HM02": "FLY", "HM03": "SURF", "HM04": "STRENGTH", "HM05": "FLASH"}
# Every move with an overworld effect, i.e. what `_open_mon_menu` offers. The five HMs need a badge
# (FIELD_MOVE_BADGE); DIG (TM28) and TELEPORT (a level-up move) are TM/level moves that need none — so
# the offer set must be separate from the badge table, or they never appear in the party menu (gh #102).
const FIELD_MOVES := ["CUT", "FLASH", "STRENGTH", "SURF", "FLY", "DIG", "TELEPORT"]
# Cut-tree block -> the block after cutting (the full CutTreeBlockSwaps table,
# data/tilesets/cut_tree_blocks.asm). The faced cell's feet tile is the tileset's cut-tree tile when
# it's the tree quadrant: 0x3D on OVERWORLD, 0x50 on GYM (the Celadon Gym garden) — pokered
# engine/overworld/cut.asm `UsedCut`. The tileset's cut tile disambiguates which blocks are trees.
const CUT_TREE_BLOCKS := {0x32: 0x6D, 0x33: 0x6C, 0x34: 0x6F, 0x35: 0x4C, 0x60: 0x6E,
	0x0B: 0x0A, 0x3C: 0x35, 0x3F: 0x35, 0x3D: 0x36}
const CUT_TREE_TILES := {"overworld": 0x3D, "gym": 0x50}
# Fishing: tilesets that have water, and the water/shore tiles to fish from (item_effects.asm).
const WATER_TILESETS := ["overworld", "forest", "dojo", "gym", "ship", "shipport", "cavern", "facility", "plateau"]
const WATER_TILES := [0x14, 0x32, 0x48]
# pokered data/tilesets/pair_collision_tile_ids.asm (TilePairCollisions): the player may not step BETWEEN
# these two individually-walkable tiles, in either direction — it simulates an elevation edge (a cavern
# floor $05 vs the rocky ledge $20/$2a/$41/$21 beside it; the forest set; forest/cavern water banks). Keyed
# by tileset name; each value is a list of [tileA, tileB] pairs. LAND applies on foot, WATER while surfing.
const TILE_PAIRS_LAND := {
	"cavern": [[0x20, 0x05], [0x41, 0x05], [0x2A, 0x05], [0x05, 0x21]],
	"forest": [[0x30, 0x2E], [0x52, 0x2E], [0x55, 0x2E], [0x56, 0x2E], [0x20, 0x2E], [0x5E, 0x2E], [0x5F, 0x2E]],
}
const TILE_PAIRS_WATER := {
	"forest": [[0x14, 0x2E], [0x48, 0x2E]],
	"cavern": [[0x14, 0x05]],
}
var _lucky_slot := Vector2i(-1, -1)         # better-odds machine, re-rolled each GameCorner visit

# Fishing tables. Old Rod always hooks Magikarp; the Good Rod (data/wild/good_rod.asm) is global;
# the Super Rod (data/wild/super_rod.asm) picks from a per-map group. [level, species] pairs.
const GOOD_ROD_MONS := [[10, "goldeen"], [10, "poliwag"]]
const SUPER_ROD_GROUPS := [
	[[15, "tentacool"], [15, "poliwag"]],                                            # Group1
	[[15, "goldeen"], [15, "poliwag"]],                                              # Group2
	[[15, "psyduck"], [15, "goldeen"], [15, "krabby"]],                              # Group3
	[[15, "krabby"], [15, "shellder"]],                                              # Group4
	[[23, "poliwhirl"], [15, "slowpoke"]],                                           # Group5
	[[15, "dratini"], [15, "krabby"], [15, "psyduck"], [15, "slowpoke"]],            # Group6
	[[5, "tentacool"], [15, "krabby"], [15, "goldeen"], [15, "magikarp"]],           # Group7
	[[15, "staryu"], [15, "horsea"], [15, "shellder"], [15, "goldeen"]],             # Group8
	[[23, "slowbro"], [23, "seaking"], [23, "kingler"], [23, "seadra"]],             # Group9
	[[23, "seaking"], [15, "krabby"], [15, "goldeen"], [15, "magikarp"]],            # Group10
]
const SUPER_ROD_MAPS := {
	"PalletTown": 0, "ViridianCity": 0, "CeruleanCity": 2, "VermilionCity": 3, "CeladonCity": 4,
	"FuchsiaCity": 9, "CinnabarIsland": 7, "Route4": 2, "Route6": 3, "Route10": 4, "Route11": 3,
	"Route12": 6, "Route13": 6, "Route17": 6, "Route18": 6, "Route19": 7, "Route20": 7, "Route21": 7,
	"Route22": 1, "Route23": 8, "Route24": 2, "Route25": 2, "CeruleanGym": 2, "VermilionDock": 3,
	"SeafoamIslandsB3F": 7, "SeafoamIslandsB4F": 7, "SafariZoneEast": 5, "SafariZoneNorth": 5,
	"SafariZoneWest": 5, "SafariZoneCenter": 5, "CeruleanCave2F": 8, "CeruleanCaveB1F": 8,
	"CeruleanCave1F": 8,
}

# Active (center) map, kept for warp/selftest code. Mirrors placed[0].
var map: Dictionary
var map_w: int
var map_h: int
var gw: int                        # center cell width
var gh: int                        # center cell height
var collision: PackedByteArray     # center collision (placed[0])
var border_block := 0
var center_label := ""
var center_tileset := ""
var center_grass := -1
var center_ledges: Array = []

var placed: Array = []             # [{label,data,w,h,ox,oy,ts,collision,border}] (ox,oy in blocks; index 0 = center)
var _ts_cache := {}                # tileset slug -> {tex,cols,blockset,walkable}
var _flower_tex: Texture2D         # 3 animation frames for the overworld flower (tile $03)
var _flower_frame := 0             # index into _FLOWER_SEQ
var _flower_t := 0.0               # timer that advances the flower cycle
const _FLOWER_SEQ := [0, 0, 1, 2]  # frame order (home/vcopy.asm: counter&3 -> flower1/1/2/3)
var _water_off := 0                # overworld water (tile $14) horizontal scroll, 0..7px
var _cut_fx := {}                  # CUT tree animation overlay (empty = none): the tree quadrant
                                   # drawn shaking + flickering over the (already-cleared) cell (gh #123)
var player
var npcs: Array = []
var grass_overlay: Node2D                   # redraws BG over grass-standing sprites' legs
var spinners: Dictionary = {}               # map label -> {"x,y": [[dir, count], ...]} slide paths
var optionsscreen                           # the OPTION menu (OptionsScreen.gd)
var trainercard                             # the trainer card (TrainerCard.gd)
var diploma                                 # the dex-completion DIPLOMA (Diploma.gd, gh #185)
var moneybox                                # the MONEY_BOX overlay for paid dialogs (MoneyBox.gd)
var trademovie                              # the in-game trade movie (TradeMovie.gd, gh #185)
var _options_from := "start"                # where OPTION was opened from ("start"/"title")
# wOptions: letter delay in frames (FAST 1 / MEDIUM 3 / SLOW 5), battle animations on/off,
# battle style SHIFT (prompt to switch when a trainer sends the next mon) or SET. Saved.
var options := {"text_speed": 3, "battle_anim": true, "battle_shift": true}
var sprite_index: Dictionary = {}
var text_data: Dictionary = {}
var textbox
var menu
var naming
var dexentry                                 # Pokédex data screen modal (DexEntry.gd)
var dexlist                                  # Pokédex contents screen modal (DexList.gd)
var statsscreen                              # Pokémon stats/summary screen modal (StatsScreen.gd)
var martscreen                               # Poké Mart shop modal (MartScreen.gd)
var title
var battle
var link                                     # v1.1 link layer (Link.gd, gh #3): the one networking seam
var monrecord                                # v1.1 mon record codec (MonRecord.gd, gh #4): the link-boundary mapper
var transition                              # screen transitions: battle wipes + warp fade (Transition.gd)
var dungeon_maps: Array = []                # map labels using the dungeon battle transitions
var slots                                   # Game Corner slot machine modal
var townmap                                 # TOWN MAP viewer modal
var townmap_start: Dictionary = {}          # map label -> town-map cycle index
var mon_base: Dictionary = {}
var mon_moves: Dictionary = {}
var ruleset: Ruleset = null          # resolved from the manifest at boot (gh #31, ADR-018)
var move_sfx: Dictionary = {}        # MOVE_CONST -> [sfx_key, pitch] (MoveSoundTable)
var credits_pages: Array = []        # end-credits pages (lists of staff text lines)
var audio
var player_party: Array = []
var player_bag := {"POKé BALL": 5, "POTION": 3, "MOON STONE": 1, "FIRE STONE": 1,
	"WATER STONE": 1, "THUNDER STONE": 1, "LEAF STONE": 1}
var player_money := 3000
var player_id := 0               # trainer ID number (IDNo on the stats screen); set at new game
var link_last_addr := ""         # gh #5: the last successfully joined address (saved; the ED default)
var link_wait_s := 30.0          # Cable Club wait/connect/sync timeout (tests shrink it)
var link_port := 0               # Cable Club port override (0 = Link.DEFAULT_PORT; tests set it)
var link_return_map := ""        # gh #6: where the club room's exit leads back to
var link_return_cell := Vector2i.ZERO
var _link_lost_seized := false   # gh #13: the lost box took the battle's modal (restored on resume/close)
var _col_snapshot: Array = []    # gh #7: the party before a link battle — restored after (stakeless)
var kill_at := ""                # gh #9 drop injection: --killat=<point> pulls the cable there
var blip_at := ""                # gh #13 blip injection: --blipat=<point> resets the transport there
var blip_every := 0              # gh #13 blip-soak: reset the transport every N battle turns
var _blip_last := ""             # the last point blipped (one blip per point, or per turn in a soak)
var _club_leaving := false       # guards the room's link-closed watcher during our own exit
var play_seconds := 0.0          # total play time in seconds (shown on the save screen)
var player_coins := 0                       # Game Corner coins (BCD 0..9999 in wPlayerCoins)
var fossil_mon := ""                         # the species the Cinnabar lab is reviving (wFossilMon)
var trainers: Dictionary = {}
var trades_data: Dictionary = {}
var wild_data: Dictionary = {}
var traded_npcs := {}            # NPC trades already completed (one-shot, by text id)
var _pc_home := false            # the item PC was opened from Red's bedroom (LOG OFF just exits)
var defeated_trainers := {}
var picked_items := {}           # overworld item balls already collected (by "map:x,y")
var found_hidden := {}           # hidden items already found (by "map:x,y")
var hidden_items: Dictionary = {} # map label -> [{x,y,item const}] (assets/hidden_items.json)
var dex_order: Array = []         # species in National-dex order (assets/dex_order.json)
var pc_box: Array = []           # Pokémon stored in the PC (Someone's/Bill's PC)
var hall_of_fame: Array = []     # HoF teams (arrays of {species,name,level}), oldest first
var pc_items: Dictionary = {}    # the player's PC item-storage box (<PLAYER>'s PC)
var _pc_item_action := ""        # "withdraw" | "deposit" | "toss" in progress
var _pc_item_sel := ""           # item being quantity-picked
var _pc_item_keys: Array = []    # current item-list keys (list idx -> item name)
var pokedex_seen := {}           # species seen in battle (Pokédex)
var pokedex_owned := {}          # species caught/obtained (Pokédex)
var item_names: Dictionary = {}  # item const -> display name (assets/items.json)
var item_prices: Dictionary = {} # display name -> buy price (assets/item_prices.json)
var trainer_pics: Dictionary = {} # OPP_<class> -> battle-pic slug (assets/trainer_pics.json)
var dex_entries: Dictionary = {}  # species -> {cat,ft,in,wt,desc} (assets/dex_entries.json)
var tm_moves: Dictionary = {}    # TMnn -> move const it teaches (assets/tm_moves.json)
var marts: Dictionary = {}       # map label -> [item const, ...] sold there
var mart_keys: Array = []        # display names in the currently-open BUY or SELL list
var mart_item := ""              # item whose quantity is being chosen in the mart
var _mon_menu_idx := 0           # party index whose field-move submenu is open
var _mon_menu_opts: Array = []   # options shown in that submenu
var _swap_src := -1              # party index picked to SWITCH; next pick swaps with it
var pending_trainer = null
var menu_keys: Array = []        # bag item names currently shown in the ITEM menu
var selected_item := ""
const STONES := {"MOON STONE": "MOON_STONE", "FIRE STONE": "FIRE_STONE",
	"WATER STONE": "WATER_STONE", "THUNDER STONE": "THUNDER_STONE", "LEAF STONE": "LEAF_STONE"}
# Vitamins (VitaminEffect): +2560 stat exp to [stat key, shown name], refused at/above 25600.
const VITAMINS := {"HP UP": ["hp", "HEALTH"], "PROTEIN": ["atk", "ATTACK"],
	"IRON": ["def", "DEFENSE"], "CARBOS": ["spd", "SPEED"], "CALCIUM": ["spc", "SPECIAL"]}
# PP restoratives (ItemUseMedicine): [amount (-1 = full), restores every move?].
const PP_ITEMS := {"ETHER": [10, false], "MAX ETHER": [-1, false],
	"ELIXER": [10, true], "MAX ELIXER": [-1, true]}
# Usable items (overworld bag). POTIONS: HP restored (-1 = full). FULL RESTORE also clears status.
const POTIONS := {"POTION": 20, "SUPER POTION": 50, "HYPER POTION": 200, "MAX POTION": -1, "FULL RESTORE": -1,
	"FRESH WATER": 50, "SODA POP": 60, "LEMONADE": 80}   # the vending drinks heal too (gh #148, item_effects.asm)
const STATUS_HEALS := {"ANTIDOTE": "psn", "PARLYZ HEAL": "par", "BURN HEAL": "brn",
	"ICE HEAL": "frz", "AWAKENING": "slp", "FULL HEAL": "*"}     # "*" = any status
const REVIVES := {"REVIVE": 0.5, "MAX REVIVE": 1.0}              # fraction of maxhp on revive
const REPELS := {"REPEL": 100, "SUPER REPEL": 200, "MAX REPEL": 250}
# Test runs (any --* user arg) get their own file so batteries never touch a real save (gh #40).
var SAVE_PATH := "user://pokeredpc_save.json"
var modal = null            # active modal Control (textbox / menu / battle), or null
var menu_mode := ""
var last_outside_map := ""
var respawn_map := "PalletTown"  # where the player reappears after a whiteout (last Center)
var warped_from := {}            # {map, warp}: the warp square the player last left through
                                 # (wWarpedFromWhichMap/Warp — elevators return there)
var warp_armed := true
var poison_step := 0             # overworld poison: every 4 steps a poisoned mon loses 1 HP
var repel_steps := 0             # while > 0, REPEL hides wild mons under the lead slot's level
var wild_cooldown_steps := 0     # wNumberOfNoRandomBattleStepsLeft: 3 battle-free steps after a battle
var _blocked_cells: Dictionary = {}   # cells impassable despite a warp (a warp hidden behind a wall)
var daycare_mon: Dictionary = {} # the mon left at the Day Care ({} = none); gains 1 EXP per step
var daycare_start_level := 0     # its level when deposited (for the withdrawal fee)
var flash_lit := false           # FLASH used in the current dark area (cleared on leaving it)
var riding := false              # on the BICYCLE (2x speed; outdoor only)
var force_bike := false          # BIT_ALWAYS_ON_BIKE; transient while inside the Cycling Road corridor
var surfing := false             # riding SURF across water (water tiles become passable)
var strength_active := false     # STRENGTH used -> the lead mon can push boulders
# BIT_TRIED_PUSH_BOULDER (pokered wMiscFlags): a STRENGTH boulder moves only on the 2nd consecutive push
# in the same direction; the first arms this (the boulder + direction it was tried against), and facing
# away / a different boulder or direction / a collision resets it (see _boulder_reset_tried, gh #129).
var _boulder_tried_at := Vector2i(-9999, -9999)
var _boulder_tried_dir := Vector2i.ZERO
# BIT_BOULDER_DUST (pokered wMiscFlags): set the moment a shove starts (push_boulder.asm
# TryPushingBoulder `.done`), cleared when the dust puff ends (DoBoulderDustAnimation ->
# ResetBoulderPushFlags). While set, TryPushingBoulder `ret nz`s before the sprite lookup or the
# two-push arming — the slide + dust are one atomic beat and further pushes are ignored (gh #28).
var _boulder_dust_pending := false
var in_safari := false           # inside the Safari Zone (safari battles + step counter)
var safari_balls := 0            # SAFARI BALLs remaining
var safari_steps := 0            # steps left before the game ends
var visited_fly: Array = []      # town labels visited (unlocked as FLY destinations)
# FLY spawn points (label -> [cell, display name]), from data/maps/special_warps.asm FlyWarpDataPtr.
const FLY_DESTS := {
	"PalletTown": [Vector2i(5, 6), "PALLET TOWN"], "ViridianCity": [Vector2i(23, 26), "VIRIDIAN CITY"],
	"PewterCity": [Vector2i(13, 26), "PEWTER CITY"], "CeruleanCity": [Vector2i(19, 18), "CERULEAN CITY"],
	"LavenderTown": [Vector2i(3, 6), "LAVENDER TOWN"], "VermilionCity": [Vector2i(11, 4), "VERMILION CITY"],
	"CeladonCity": [Vector2i(41, 10), "CELADON CITY"], "FuchsiaCity": [Vector2i(19, 28), "FUCHSIA CITY"],
	"CinnabarIsland": [Vector2i(11, 12), "CINNABAR ISLAND"], "IndigoPlateau": [Vector2i(9, 6), "INDIGO PLATEAU"],
	"SaffronCity": [Vector2i(9, 30), "SAFFRON CITY"]}
var darkness                     # ColorRect overlay dimming dark caves
# Dark maps (wMapPalOffset; Rock Tunnel is the reachable one) — FLASH lights them.
const DARK_MAPS := ["RockTunnel1F", "RockTunnelB1F", "SeafoamIslands1F", "SeafoamIslandsB1F",
	"SeafoamIslandsB2F", "SeafoamIslandsB3F", "SeafoamIslandsB4F",
	"CeruleanCave1F", "CeruleanCave2F", "CeruleanCaveB1F"]
# ---- story scripting -------------------------------------------------------
var story_events := {}           # set of story EVENT flags (name -> true)
var event_vars := {}             # the Event VM's variables store (ADR-019 §5; saved)
var event_vm: EventVM = null     # the project's authored events (gh #39; null pre-boot)
var player_name := "RED"
var rival_name := "BLUE"
var player_starter := ""         # species the player chose at Oak's lab
var rival_starter := ""          # the counterpart the rival took
var badges: Array = []           # gym badges earned (e.g. "BOULDERBADGE"), in order
var _trash_first := 0            # Vermilion Gym puzzle: can index holding the 1st switch
var _trash_second := 0           # ...and the 2nd switch (picked once the 1st is found)
var cutscene_active := false     # a scripted cutscene is driving the player/NPCs (no free input)
var cutscene                     # the Cutscene runner (Control on the ui layer)
var _map_scripts := {}           # label -> MapScript adapter (stateless; no-op base if unscripted)


func set_event(ev: String) -> void:
	story_events[ev] = true


# ---- Pokédex ---------------------------------------------------------------

func mark_seen(species: String) -> void:
	pokedex_seen[species] = true


func mark_owned(species: String) -> void:
	pokedex_seen[species] = true
	pokedex_owned[species] = true


## Fold everything currently held into the owned set (covers catches/gifts/evolutions without a
## hook at every add site); kept-then-released mons stay owned via the persistent set.
func _sync_owned() -> void:
	for m in player_party:
		mark_owned(str(m["species"]))
	for m in pc_box:
		mark_owned(str(m["species"]))


func has_event(ev: String) -> bool:
	return story_events.has(ev)


func clear_event(ev: String) -> void:
	story_events.erase(ev)


## Parse an optional `--seed N` (or `--seed=N`) cmdline arg for deterministic RNG. Used by the
## test harness / the legit-play `--playthrough` run so a failure reproduces (gh #76, ADR-011).
## Shipped play passes no flag and falls back to `randomize()`. Returns the seed, or -1 if absent.
func _parse_seed_arg() -> int:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		if a == "--seed" and i + 1 < args.size() and args[i + 1].is_valid_int():
			return maxi(0, int(args[i + 1]))
		if a.begins_with("--seed=") and a.substr(7).is_valid_int():
			return maxi(0, int(a.substr(7)))
	return -1


func _ready() -> void:
	var _seed := _parse_seed_arg()
	if _seed >= 0:
		seed(_seed)
		print("[seed] deterministic RNG seed=%d" % _seed)
	else:
		randomize()
	Keybinds.apply()                  # apply user-editable key bindings (user://keybinds.cfg)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# gh #25 (ADR-017): every data table now loads from the PROJECT (res://project, the
	# extractor's emission, or --project=<dir>) through the Core loader, which rebuilds
	# the exact v1 shapes — proven equal by --projparitytest. Textures still load from
	# res://assets via Godot's import pipeline this phase (the project carries copies).
	var perr := ProjectData.open(_project_dir())
	if perr != "":
		push_error("[project] " + perr)
		print("[project] FATAL: " + perr)
		get_tree().quit(1)
		return
	# gh #31 (ADR-018): resolve the project's ruleset through the registry — an unknown
	# name refuses at boot naming both sides (the refuse-newer pattern for mechanics).
	var rs_id := str(ProjectData.manifest.get("ruleset", ""))
	ruleset = RulesetRegistry.resolve(rs_id)
	if ruleset == null:
		var rerr := "project asks for ruleset '%s'; this build knows: %s" % [
			rs_id, RulesetRegistry.known()]
		push_error("[ruleset] " + rerr)
		print("[ruleset] FATAL: " + rerr)
		get_tree().quit(1)
		return
	ruleset.configure()
	if ruleset.types == null or ruleset.formulas == null or ruleset.battle == null:
		# A module class that failed to load configures to null — refuse loudly instead
		# of limping into per-frame nil errors (gh #33).
		push_error("[ruleset] '%s' configured incompletely (a module script failed to load)" % rs_id)
		print("[ruleset] FATAL: '%s' configured incompletely (a module script failed to load)" % rs_id)
		get_tree().quit(1)
		return
	# gh #39 (ADR-019): load the project's authored events. A record this build cannot
	# execute (unknown trigger kind / command / unparseable condition) refuses at boot —
	# the refuse-newer pattern applied to event semantics.
	event_vm = EventVM.new()
	event_vm.main = self
	var everr := event_vm.load_all(ProjectData.events())
	if everr != "":
		push_error("[events] " + everr)
		print("[events] FATAL: " + everr)
		get_tree().quit(1)
		return
	sprite_index = ProjectData.legacy("sprites/index.json")
	text_data = ProjectData.legacy("text.json")
	var ui := CanvasLayer.new()
	add_child(ui)
	var ft: Texture2D = load("res://assets/font.png")
	var cmap: Dictionary = ProjectData.legacy("charmap.json")
	var fcols := int(ft.get_width() / 8)
	textbox = preload("res://scripts/TextBox.gd").new()
	ui.add_child(textbox)
	textbox.setup(ft, fcols, cmap)
	textbox.closed.connect(func() -> void:
		modal = null
		if _text_then.is_valid():          # an item-menu message: back to the bag / party pick
			var cb := _text_then
			_text_then = Callable()
			cb.call())
	menu = preload("res://scripts/Menu.gd").new()
	ui.add_child(menu)
	menu.setup(ft, fcols, cmap)
	menu.mon_icons_tex = load("res://assets/mon_icons.png")
	menu.mon_icons_map = ProjectData.legacy("mon_icons.json")
	menu.chosen.connect(_on_menu_chosen)
	menu.selected.connect(_on_menu_select)
	naming = preload("res://scripts/NamingScreen.gd").new()
	ui.add_child(naming)
	naming.setup(ft, fcols, cmap)
	title = preload("res://scripts/TitleScreen.gd").new()
	ui.add_child(title)
	title.setup(ft, fcols, cmap)
	title.main = self
	title.started.connect(_on_title_started)
	title.clear_save.connect(_on_clear_save)
	title.phase_changed.connect(_on_title_phase)
	cutscene = preload("res://scripts/Cutscene.gd").new()
	ui.add_child(cutscene)
	cutscene.setup(self, ft, fcols, cmap)
	dexentry = preload("res://scripts/DexEntry.gd").new()
	ui.add_child(dexentry)
	dexentry.setup(ft, fcols, cmap)
	dexentry.closed.connect(func() -> void: modal = null)
	dexlist = preload("res://scripts/DexList.gd").new()
	ui.add_child(dexlist)
	dexlist.setup(ft, fcols, cmap, self)
	dexlist.closed.connect(_on_dex_closed)
	statsscreen = preload("res://scripts/StatsScreen.gd").new()
	ui.add_child(statsscreen)
	statsscreen.setup(ft, fcols, cmap, self)
	statsscreen.closed.connect(func() -> void: _open_party_view())   # back to the party after STATS
	martscreen = preload("res://scripts/MartScreen.gd").new()
	ui.add_child(martscreen)
	martscreen.setup(ft, fcols, cmap, self)
	martscreen.closed.connect(func() -> void:
		modal = null
		_say("Thank you!"))                          # the clerk's farewell on any exit
	credits_pages = ProjectData.legacy("credits.json")
	darkness = ColorRect.new()                  # dark-cave palette swap (FLASH clears it; gh #127)
	darkness.color = Color(0, 0, 0, 1)
	darkness.size = Vector2(160, 144)
	darkness.z_index = -5                       # over the world, under textbox/menu/battle
	darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	darkness.visible = false
	var dark_mat := ShaderMaterial.new()        # full-screen FadePal2 remap (not a spotlight)
	dark_mat.shader = load("res://shaders/cave_dark.gdshader")
	darkness.material = dark_mat
	ui.add_child(darkness)
	mon_base = ProjectData.legacy("pokemon/base_stats.json")
	mon_moves = ProjectData.legacy("moves.json")
	move_sfx = ProjectData.legacy("move_sfx.json")
	battle = preload("res://scripts/Battle.gd").new()
	ui.add_child(battle)
	battle.setup(ft, fcols, cmap, mon_base, mon_moves, ruleset)
	battle.main = self
	battle.finished.connect(_on_battle_finished)
	link = preload("res://scripts/Link.gd").new()
	add_child(link)
	link.main = self
	monrecord = preload("res://scripts/MonRecord.gd").new()
	monrecord.main = self
	# gh #6: a link that dies while standing in a Cable Club room walks you back out
	# (during a table flow the flow's own waits handle it — cutscene_active is true there).
	link.closed.connect(func(_r: String) -> void:
		if _link_lost_seized:              # gh #13: the grace expired mid-battle — drop the box,
			_link_lost_seized = false      # give the battle its modal back so it voids visibly
			textbox.visible = false
			textbox.active = false
			textbox.held = false
			modal = battle
		if center_label in ["TradeCenter", "Colosseum"] and not cutscene_active and not _club_leaving:
			_club_room_kicked())
	# gh #13 (ADR-016): an armed table session dropped. During a BATTLE the linkwait ignores
	# input and draws its own screen, so the lost box takes the modal; the trade flow's own
	# waits show the box themselves (a pick menu may be open — seizing its modal would strand
	# the flow's await on menu.chosen). On resume the battle exchanges state reports
	# (Cutscene._tc_on_resumed routes them) and the box comes down here.
	link.lost.connect(func() -> void:
		if modal == battle:
			_link_lost_seized = true
			modal = textbox
			textbox.show_ask("Link lost -\nwaiting for your\npartner..."))
	link.resumed.connect(func(_s: Dictionary) -> void:
		if _link_lost_seized:
			_link_lost_seized = false
			textbox.visible = false
			textbox.active = false
			textbox.held = false
			modal = battle)
	slots = preload("res://scripts/SlotMachine.gd").new()
	ui.add_child(slots)
	slots.setup(ft, fcols, cmap, self)
	slots.finished.connect(func() -> void: modal = null)
	townmap = preload("res://scripts/TownMap.gd").new()
	ui.add_child(townmap)
	var tm_data: Dictionary = ProjectData.legacy("town_map.json")
	townmap_start = tm_data.get("start", {})
	townmap.setup(ft, fcols, cmap, self, tm_data)
	townmap.closed.connect(func() -> void:
		modal = null
		if townmap.is_fly_mode():
			_text_then = Callable()            # FLY cancel returns to the overworld, never the bag
		elif _text_then.is_valid():           # Bag TOWN MAP: back to the item list
			var cb := _text_then
			_text_then = Callable()
			cb.call())
	townmap.fly_chosen.connect(_on_fly_chosen)
	optionsscreen = preload("res://scripts/OptionsScreen.gd").new()
	ui.add_child(optionsscreen)
	optionsscreen.setup(self, ft, fcols, cmap)
	optionsscreen.closed.connect(_on_options_closed)
	trainercard = preload("res://scripts/TrainerCard.gd").new()
	ui.add_child(trainercard)
	trainercard.setup(self, ft, fcols, cmap)
	trainercard.closed.connect(_on_card_closed)
	diploma = preload("res://scripts/Diploma.gd").new()
	ui.add_child(diploma)
	diploma.setup(self, ft, fcols, cmap)
	diploma.closed.connect(func() -> void: modal = null)
	moneybox = preload("res://scripts/MoneyBox.gd").new()
	ui.add_child(moneybox)
	moneybox.setup(self, ft, fcols, cmap)
	trademovie = preload("res://scripts/TradeMovie.gd").new()
	ui.add_child(trademovie)
	ui.move_child(trademovie, 0)          # the movie underdraws the textbox (its texts)
	trademovie.setup(self, ft, fcols, cmap, battle)
	transition = preload("res://scripts/Transition.gd").new()
	ui.add_child(transition)                    # topmost: wipes draw over the world and UI
	transition.setup()
	dungeon_maps = ProjectData.legacy("dungeon_maps.json")
	spinners = ProjectData.legacy("spinners.json")
	_flower_tex = load("res://assets/tilesets/flower.png")
	trainers = ProjectData.legacy("trainers.json")
	trades_data = ProjectData.legacy("trades.json")
	wild_data = ProjectData.legacy("wild.json")
	item_names = ProjectData.legacy("items.json")
	item_prices = ProjectData.legacy("item_prices.json")
	trainer_pics = ProjectData.legacy("trainer_pics.json")
	dex_entries = ProjectData.legacy("dex_entries.json")
	tm_moves = ProjectData.legacy("tm_moves.json")
	marts = ProjectData.legacy("marts.json")
	hidden_items = ProjectData.legacy("hidden_items.json")
	dex_order = ProjectData.legacy("dex_order.json")
	player_party = [
		make_mon("charmander", 8, ["SCRATCH", "GROWL", "EMBER"]),
		make_mon("pidgey", 5, []),
	]
	audio = preload("res://scripts/Audio.gd").new()
	add_child(audio)
	audio.setup(ProjectData.legacy("audio.json"), ProjectData.legacy("map_music.json"),
		ProjectData.legacy("sfx.json"), ProjectData.legacy("cries.json"))
	audio.enabled = OS.get_cmdline_user_args().is_empty()   # no music synthesis during tests
	if not OS.get_cmdline_user_args().is_empty():
		SAVE_PATH = "user://pokeredpc_save_test.json"       # never clobber the real save (gh #40)
		for ua in OS.get_cmdline_user_args():
			if str(ua).begins_with("--saveslot="):          # two-instance tests keep separate slots
				SAVE_PATH = "user://pokeredpc_save_%s.json" % str(ua).substr(11)
	# gh #9: a leftover trade journal marks a trade interrupted inside the commit window.
	# Recovery runs in load_game (it needs the party); here it is only surfaced.
	if FileAccess.file_exists(_tc_journal_path()):
		print("[trade] interrupted trade journal present — will recover on load")
	battle.fast_hp = not OS.get_cmdline_user_args().is_empty()   # skip HP-drain animation in tests
	apply_options()                   # text speed etc. (defaults; a loaded save re-applies)
	player = preload("res://scripts/Player.gd").new()
	add_child(player)
	player.setup(self)
	player.moved.connect(_on_player_moved)
	# Gen-1 grass priority: the map tiles under a grass-standing sprite's lower half redraw
	# over it (sprite_oam.asm); z_index keeps it above the player and the per-map NPCs.
	grass_overlay = Node2D.new()
	grass_overlay.z_index = 1
	var gmat := ShaderMaterial.new()
	gmat.shader = load("res://shaders/grass_overlay.gdshader")   # keys out the lightest shade
	grass_overlay.material = gmat
	add_child(grass_overlay)
	grass_overlay.draw.connect(_draw_grass_overlay)
	load_world("PalletTown")
	audio.presynth_all()        # background-build every track so later changes are instant

	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--selftest" in args:
		_selftest()
	elif "--playthrough" in args:
		_playthrough()
	elif "--mtmoontest" in args:
		_mtmoontest()
	elif "--tpprobe" in args:
		_tpprobe()
	elif "--vr1fsolve" in args:
		_vr1fsolve()
	elif "--mistytest" in args:
		_mistytest()
	elif "--surgecombat" in args:
		_surgecombattest()
	elif "--surgenavtest" in args:
		_surgenavtest()
	elif "--billstage" in args:
		_billstagetest()
	elif "--annestage" in args:
		_ssannestagetest()
	elif "--rtprobe" in args:
		_rtprobe()
	elif "--rocktunneltest" in args:
		_rocktunneltest()
	elif "--erikacombat" in args:
		_erikacombattest()
	elif "--erikastage" in args:
		_erikastagetest()
	elif "--anneshot" in args:
		_anneshot()
	elif "--shot" in args:
		_screenshot()
	elif "--warptest" in args:
		_warptest()
	elif "--conntest" in args:
		_conntest()
	elif "--ledgetest" in args:
		_ledgetest()
	elif "--grasstest" in args:
		_grasstest()
	elif "--npctest" in args:
		_npctest()
	elif "--texttest" in args:
		_texttest()
	elif "--signtest" in args:
		_signtest()
	elif "--menutest" in args:
		_menutest()
	elif "--battletest" in args:
		_battletest()
	elif "--catchtest" in args:
		_catchtest()
	elif "--newcatchtest" in args:
		_newcatchtest()
	elif "--faintordertest" in args:
		_faintordertest()
	elif "--dblkotest" in args:
		_dblkotest()
	elif "--chargepptest" in args:
		_chargepptest()
	elif "--statmovetest" in args:
		_statmovetest()
	elif "--wraptest" in args:
		_wraptest()
	elif "--trainertest" in args:
		_trainertest()
	elif "--statustest" in args:
		_statustest()
	elif "--resttest" in args:
		_resttest()
	elif "--flymovetest" in args:
		_flymovetest()
	elif "--movefxtest" in args:
		_movefxtest()
	elif "--battledettest" in args:
		_battledettest()
	elif "--monrecordtest" in args:
		_monrecordtest()
	elif "--schematest" in args:
		_schematest()
	elif "--projparitytest" in args:
		_projparitytest()
	elif "--rulesettest" in args:
		_rulesettest()
	elif "--exprtest" in args:
		_exprtest()
	elif _validate_dir_arg(args) != "":
		_validateproject(_validate_dir_arg(args))
	elif "--recovertest" in args:
		_recovertest()
	elif "--clubtest" in args:
		_clubtest()
	elif "--colsoak" in args:
		_colsoaktest()
	elif "--host" in args:
		_linktest(true)
	elif _has_join_arg(args):
		_linktest(false)
	elif "--moveanimtest" in args:
		_moveanimtest()
	elif "--wipetest" in args:
		_wipetest()
	elif "--introshot" in args:
		_introshot()
	elif "--optiontest" in args:
		_optiontest()
	elif "--oldmantest" in args:
		_oldmantest()
	elif "--pewtertest" in args:
		_pewtertest()
	elif "--spintest" in args:
		_spintest()
	elif "--spinnavtest" in args:
		_spinnavtest()
	elif "--spinwalltest" in args:
		_spinwalltest()
	elif "--silphdescent" in args:
		_silphdescenttest()
	elif "--silphscopetest" in args:
		_silphscopetest()
	elif "--pokeflutetest" in args:
		_pokeflutetest()
	elif "--snorlaxstage" in args:
		_snorlaxstagetest()
	elif "--kogastage" in args:
		_kogastagetest()
	elif "--safaristage" in args:
		_safaristagetest()
	elif "--saffronstage" in args:
		_saffronstagetest()
	elif "--silphstage" in args:
		_silphstagetest()
	elif "--sabrinastage" in args:
		_sabrinastagetest()
	elif "--surfnavtest" in args:
		_surfnavtest()
	elif "--cinnabarnavtest" in args:
		_cinnabarnavtest()
	elif "--holetest" in args:
		_holetest()
	elif "--secretkeytest" in args:
		_secretkeytest()
	elif "--cinnabardoortest" in args:
		_cinnabardoortest()
	elif "--gatedoortest" in args:
		_gatedoortest()
	elif "--blainestage" in args:
		_blainestagetest()
	elif "--viridiangatetest" in args:
		_viridiangatetest()
	elif "--route22gatetest" in args:
		_route22gatetest()
	elif "--victoryroadtest" in args:
		_victoryroadtest()
	elif "--victoryroadstage" in args:
		_victoryroadstagetest()
	elif "--elite4stage" in args:
		_elite4stagetest()
	elif "--giovannistage" in args:
		_giovannistagetest()
	elif "--quiztest" in args:
		_quiztest()
	elif "--bagtest" in args:
		_bagtest()
	elif "--hoftest" in args:
		_hoftest()
	elif "--aidetest" in args:
		_aidetest()
	elif "--faithtest" in args:
		_faithtest()
	elif "--learntest" in args:
		_learntest()
	elif "--stonetest" in args:
		_stonetest()
	elif "--tradetest" in args:
		_tradetest()
	elif "--edgetest" in args:
		_edgetest()
	elif "--savetest" in args:
		_savetest()
	elif "--healtest" in args:
		_healtest()
	elif "--towerhealtest" in args:
		_towerhealtest()
	elif "--silphnursetest" in args:
		_silphnursetest()
	elif "--audiotest" in args:
		_audiotest()
	elif "--presynthtest" in args:
		_presynthtest()
	elif "--wildtest" in args:
		_wildtest()
	elif "--whiteouttest" in args:
		_whiteouttest()
	elif "--titletest" in args:
		_titletest()
	elif "--titlemenushot" in args:
		_titlemenushot()
	elif "--exitwarptest" in args:
		_exitwarptest()
	elif "--catchnicktest" in args:
		_catchnicktest()
	elif "--dexshot" in args:
		_dexshot()
	elif "--dexlistshot" in args:
		_dexlistshot()
	elif "--partyshot" in args:
		_partyshot()
	elif "--statsshot" in args:
		_statsshot()
	elif "--saveshot" in args:
		_saveshot()
	elif "--nametest" in args:
		_nametest()
	elif "--introtest" in args:
		_introtest()
	elif "--oaktest" in args:
		_oaktest()
	elif "--parceltest" in args:
		_parceltest()
	elif "--sighttest" in args:
		_sighttest()
	elif "--fossilguardtest" in args:
		_fossilguardtest()
	elif "--gymtest" in args:
		_gymtest()
	elif "--sfxtest" in args:
		_sfxtest()
	elif "--badgetest" in args:
		_badgetest()
	elif "--maptest" in args:
		_maptest()
	elif "--dockscene" in args:
		_dockscene()
	elif "--surgetest" in args:
		_surgetest()
	elif "--itemtest" in args:
		_itemtest()
	elif "--marttest" in args:
		_marttest()
	elif "--nameratertest" in args:
		_nameratertest()
	elif "--roofgirltest" in args:
		_roofgirltest()
	elif "--refshots" in args:
		_refshots()
	elif "--memtest" in args:
		_memtest()
	elif "--aitest" in args:
		_aitest()
	elif "--pctest" in args:
		_pctest()
	elif "--dexratingtest" in args:
		_dexratingtest()
	elif "--diplomatest" in args:
		_diplomatest()
	elif "--moneyboxtest" in args:
		_moneyboxtest()
	elif "--clearsavetest" in args:
		_clearsavetest()
	elif "--cuttest" in args:
		_cuttest()
	elif "--hiddentest" in args:
		_hiddentest()
	elif "--itemusetest" in args:
		_itemusetest()
	elif "--crivaltest" in args:
		_crivaltest()
	elif "--towertest" in args:
		_towertest()
	elif "--dextest" in args:
		_dextest()
	elif "--billtest" in args:
		_billtest()
	elif "--ssannetest" in args:
		_ssannetest()
	elif "--fishtest" in args:
		_fishtest()
	elif "--vendingtest" in args:
		_vendingtest()
	elif "--biketest" in args:
		_biketest()
	elif "--battleitemtest" in args:
		_battleitemtest()
	elif "--tmtest" in args:
		_tmtest()
	elif "--daycaretest" in args:
		_daycaretest()
	elif "--hideouttest" in args:
		_hideouttest()
	elif "--towerghosttest" in args:
		_towerghosttest()
	elif "--champwalktest" in args:
		_champwalktest()
	elif "--snorlaxtest" in args:
		_snorlaxtest()
	elif "--surftest" in args:
		_surftest()
	elif "--strengthtest" in args:
		_strengthtest()
	elif "--elitetest" in args:
		_elitetest()
	elif "--flytest" in args:
		_flytest()
	elif "--silphtest" in args:
		_silphtest()
	elif "--safaribattletest" in args:
		_safaribattletest()
	elif "--safaritest" in args:
		_safaritest()
	elif "--keybindtest" in args:
		_keybindtest()
	elif "--saffrontest" in args:
		_saffrontest()
	elif "--slottest" in args:
		_slottest()
	elif "--slotshot" in args:
		_slotshot()
	elif "--prizetest" in args:
		_prizetest()
	elif "--rodtest" in args:
		_rodtest()
	elif "--legendtest" in args:
		_legendtest()
	elif "--gifttest" in args:
		_gifttest()
	elif "--fossiltest" in args:
		_fossiltest()
	elif "--museumtest" in args:
		_museumtest()
	elif "--mansiontest" in args:
		_mansiontest()
	elif "--victorytest" in args:
		_victorytest()
	elif "--townmaptest" in args:
		_townmaptest()
	elif "--route23test" in args:
		_route23test()
	elif "--seafoamtest" in args:
		_seafoamtest()
	elif "--cardkeytest" in args:
		_cardkeytest()
	elif "--seafoamcurrenttest" in args:
		_seafoamcurrenttest()
	elif "--e4test" in args:
		_e4test()
	elif "--rockettest" in args:
		_rockettest()
	elif "--uishot" in args:
		_uishot()
	elif "--partytest" in args:
		_partytest()
	elif "--route22test" in args:
		_route22test()
	elif "--hiddencuttest" in args:
		_hiddencuttest()
	elif "--blueshousetest" in args:
		_blueshousetest()
	elif "--eventtest" in args:
		_eventtest()
	elif "--pcaccesstest" in args:
		_pcaccesstest()
	elif "--starterballtest" in args:
		_starterballtest()
	elif "--rivallosstest" in args:
		_rivallosstest()
	elif "--cyclinggatetest" in args:
		_cyclinggatetest()
	elif "--forcedbiketest" in args:
		_forcedbiketest()
	elif "--giftnpctest" in args:
		_giftnpctest()
	elif "--visibilitytest" in args:
		_visibilitytest()
	elif "--pcentershot" in args:
		_pcentershot()
	elif "--martshot" in args:
		_martshot()
	elif "--creditstest" in args:
		_creditstest()
	elif "--creditshot" in args:
		_creditshot()
	elif "--townmapshot" in args:
		_townmapshot()
	elif "--caveshot" in args:
		_caveshot()
	elif "--flashtest" in args:
		_flashtest()
	elif "--digteleporttest" in args:
		_digteleporttest()
	elif "--scrolltest" in args:
		_scrolltest()
	elif "--housetest" in args:
		_housetest()
	elif "--playmap" in args:
		_playmap()
	else:
		_show_title()                     # normal launch: title -> CONTINUE / NEW GAME


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "missing asset: " + path)
	return JSON.parse_string(f.get_as_text())


func _load_json_array(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "missing asset: " + path)
	return JSON.parse_string(f.get_as_text())


# ---- save / load -----------------------------------------------------------

## Write the full game state to the save slot. Returns success.
func save_game() -> bool:
	# Never record a Cable Club room as the save location (the trade commit saves while
	# standing at the table): a reload has no link session, so the save points back to
	# where the club flow started — beside the attendant (playtest: a player reloaded
	# INTO the dead Trade Center).
	var save_map := center_label
	var save_cell: Vector2i = player.cell
	if center_label in ["TradeCenter", "Colosseum"] and link_return_map != "":
		save_map = link_return_map
		save_cell = link_return_cell
	var data := {
		"map": save_map,
		"cell": [save_cell.x, save_cell.y],
		"facing": player.facing,
		"player_id": player_id,
		"play_seconds": play_seconds,
		"last_outside_map": last_outside_map,
		"respawn_map": respawn_map,
		"money": player_money,
		"coins": player_coins,
		"fossil_mon": fossil_mon,
		"bag": player_bag,
		"party": player_party,
		"defeated_trainers": defeated_trainers,
		"traded_npcs": traded_npcs,
		"picked_items": picked_items,
		"found_hidden": found_hidden,
		"repel_steps": repel_steps,
		"daycare_mon": daycare_mon,
		"daycare_start_level": daycare_start_level,
		"visited_fly": visited_fly,
		"in_safari": in_safari,
		"safari_balls": safari_balls,
		"safari_steps": safari_steps,
		"pc_box": pc_box,
		"pc_items": pc_items,
		"hall_of_fame": hall_of_fame,
		"pokedex_seen": pokedex_seen,
		"pokedex_owned": pokedex_owned,
		"events": story_events,
		"player_name": player_name,
		"rival_name": rival_name,
		"player_starter": player_starter,
		"rival_starter": rival_starter,
		"badges": badges,
		"options": options,
		"link_addr": link_last_addr,   # additive (gh #5): a 1.0 save loads unchanged
		"event_vars": event_vars,      # additive (gh #39, ADR-019 §5): the Event VM's vars
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))   # indented: the save stays human-readable (gh #45)
	f.close()
	return true


## Restore game state from the save slot (and load that map at the saved position).
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	player_money = int(data["money"])
	player_coins = int(data.get("coins", 0))
	link_last_addr = str(data.get("link_addr", ""))
	fossil_mon = str(data.get("fossil_mon", ""))
	player_bag = data["bag"]
	for k in player_bag:                       # JSON makes ints floats; bag counts must be ints
		player_bag[k] = int(player_bag[k])
	player_party = data["party"]
	defeated_trainers = data["defeated_trainers"]
	traded_npcs = data["traded_npcs"]
	picked_items = data.get("picked_items", {})
	found_hidden = data.get("found_hidden", {})
	repel_steps = int(data.get("repel_steps", 0))
	daycare_mon = data.get("daycare_mon", {})
	daycare_start_level = int(data.get("daycare_start_level", 0))
	visited_fly = data.get("visited_fly", [])
	in_safari = bool(data.get("in_safari", false))
	safari_balls = int(data.get("safari_balls", 0))
	safari_steps = int(data.get("safari_steps", 0))
	pc_box = data.get("pc_box", [])
	pc_items = data.get("pc_items", {})
	hall_of_fame = data.get("hall_of_fame", [])
	pokedex_seen = data.get("pokedex_seen", {})
	pokedex_owned = data.get("pokedex_owned", {})
	# Migrate stale species slugs and auto-names from older builds (gh #35): saved mons keep
	# their name forever, so nidorans caught before the glyph fix stay "NIDORANM"/"NIDORAN_M"
	# unless refreshed here. Custom nicknames are untouched.
	for arr in [player_party, pc_box, ([daycare_mon] if not daycare_mon.is_empty() else [])]:
		for mon in arr:
			var sp := str(mon["species"]).replace("_", "")
			mon["species"] = sp
			var nm := str(mon["name"])
			if nm == sp.to_upper() or nm.replace("_", "") == sp.to_upper() \
					or nm.replace(" ", "") == sp.to_upper():
				mon["name"] = mon_display_name(sp)
	for reg in [pokedex_seen, pokedex_owned]:          # dex registries: same slug migration
		for k in reg.keys():
			var ck := str(k).replace("_", "")
			if ck != str(k):
				reg[ck] = true
				reg.erase(k)
	last_outside_map = str(data["last_outside_map"])
	respawn_map = str(data.get("respawn_map", "PalletTown"))
	story_events = data.get("events", {})
	event_vars = data.get("event_vars", {})
	player_name = str(data.get("player_name", "RED"))
	player_id = int(data.get("player_id", 0))
	var op: Dictionary = data.get("options", {})
	options = {"text_speed": int(op.get("text_speed", 3)),
		"battle_anim": bool(op.get("battle_anim", true)),
		"battle_shift": bool(op.get("battle_shift", true))}
	apply_options()
	play_seconds = float(data.get("play_seconds", 0.0))
	rival_name = str(data.get("rival_name", "BLUE"))
	player_starter = str(data.get("player_starter", ""))
	rival_starter = str(data.get("rival_starter", ""))
	badges = data.get("badges", [])
	force_bike = false                         # transient: CheckForceBikeOrSurf re-arms it from map coords
	var cell := Vector2i(int(data["cell"][0]), int(data["cell"][1]))
	# CONTINUE after the Hall of Fame lands in PALLET TOWN, not the HoF floor: main_menu.asm's
	# .choseContinue sees wCurMap == HALL_OF_FAME (with a HoF team recorded), zeroes
	# wDestinationMap and fly-warps there via PrepareForSpecialWarp (gh #184).
	if str(data["map"]) in ["TradeCenter", "Colosseum"]:
		# A pre-fix save stranded inside the Cable Club (the trade commit used to save at
		# the table, and a reload has no link session): wake up outside the last Center,
		# like the escape warp does.
		print("[link] save was inside the Cable Club — waking up at %s instead" % respawn_map)
		_escape_warp()
	elif str(data["map"]) == "HallOfFame" and not hall_of_fame.is_empty():
		load_world("PalletTown", -1, FLY_DESTS["PalletTown"][0])
		player.facing = 0                      # PLAYER_DIR_DOWN, set just before the warp
	else:
		load_world(str(data["map"]), -1, cell, true)
		player.facing = int(data["facing"])
	player.queue_redraw()
	_tc_journal_recover()                      # gh #9: finish/roll back an interrupted trade
	return true


func _map_exists(label: String) -> bool:
	return ProjectData.map_exists(label)      # gh #25: maps ride the project


# ---- tileset / map loading -------------------------------------------------

func _get_tileset(slug: String) -> Dictionary:
	if not _ts_cache.has(slug):
		var ts: Dictionary = ProjectData.legacy("tilesets/%s.json" % slug)
		var wk := {}
		for t in ts["walkable_tiles"]:
			wk[int(t)] = true
		var cts: Array = []
		for c in ts.get("counter_tiles", []):
			cts.append(int(c))
		_ts_cache[slug] = {
			"tex": load("res://assets/tilesets/%s.png" % slug), "slug": slug,
			"cols": int(ts["tile_cols"]), "blockset": ts["blocks"], "walkable": wk,
			"grass_tile": int(ts.get("grass_tile", -1)), "ledges": ts.get("ledges", []),
			"counter_tiles": cts}
	return _ts_cache[slug]


func _compute_collision(grid: Array, blockset: Array, wk: Dictionary, w: int, h: int) -> PackedByteArray:
	var col := PackedByteArray()
	col.resize(w * 2 * h * 2)
	var cw := w * 2
	for by in range(h):
		for bx in range(w):
			var bdef: Array = blockset[int(grid[by][bx])]
			for sy in range(2):
				for sx in range(2):
					var tid := int(bdef[SUB[sy][sx]])
					col[(by * 2 + sy) * cw + (bx * 2 + sx)] = 1 if wk.has(tid) else 0
	return col


## Replace a block in the center map at runtime (e.g. an opening door), updating both its 4
## collision tiles and the render. Mirrors pokered's ReplaceTileBlock.
func set_block(bx: int, by: int, block_id: int) -> void:
	map["blocks"][by][bx] = block_id
	var ts: Dictionary = placed[0]["ts"]
	var bdef: Array = ts["blockset"][block_id]
	var wk: Dictionary = ts["walkable"]
	for sy in range(2):
		for sx in range(2):
			var tid := int(bdef[SUB[sy][sx]])
			collision[(by * 2 + sy) * gw + (bx * 2 + sx)] = 1 if wk.has(tid) else 0
	queue_redraw()


func _make_placed(label: String, data: Dictionary, ox: int, oy: int) -> Dictionary:
	var ts := _get_tileset(str(data["tileset"]))
	var w := int(data["width"])
	var h := int(data["height"])
	return {"label": label, "data": data, "w": w, "h": h, "ox": ox, "oy": oy, "ts": ts,
		"collision": _compute_collision(data["blocks"], ts["blockset"], ts["walkable"], w, h),
		"border": int(data.get("border_block", 0)),
		# Render clip in center-block coords (gh #124). Default = the map's own extent; a connected
		# neighbour is narrowed perpendicular to the connection so it can't overhang past the current
		# map's edge — that region is the border block, as in pokered (see load_world).
		"clip": [ox, ox + w, oy, oy + h]}


## (re)build the world around `center`. Spawn priority: spawn_override > warp idx > default.
func load_world(center: String, arrive_idx := -1, spawn_override = null, keep_facing := false) -> void:
	if moneybox:
		moneybox.hide_box()          # a map redraw clears the MONEY_BOX tiles on the GB
	# Port artifact, not asm: freeing the NPCs kills an in-flight boulder slide tween, so
	# _boulder_dust's `await btw.finished` never resumes and could leave the push gate stuck shut.
	_boulder_dust_pending = false
	placed = []
	var c := _make_placed(center, ProjectData.map_json(center), 0, 0)
	placed.append(c)
	map = c["data"]
	map_w = c["w"]; map_h = c["h"]
	gw = map_w * 2; gh = map_h * 2
	collision = c["collision"]
	_blocked_cells = {}
	border_block = c["border"]
	center_label = center
	# BIT_ALWAYS_ON_BIKE persists across Route 16/17/18 connections, but nowhere else. The original
	# gates explicitly clear it (scripts/Route16Gate1F.asm / Route18Gate1F.asm); this also defends
	# against leaving the corridor through a nonstandard warp.
	if not FORCE_BIKE_MAPS.has(center_label):
		force_bike = false
	center_tileset = str(map["tileset"])
	center_grass = int(c["ts"]["grass_tile"])
	center_ledges = c["ts"]["ledges"]

	for conn in map.get("connections", []):
		var label := str(conn["map"])
		if not _map_exists(label):
			continue
		var nd: Dictionary = ProjectData.map_json(label)
		var nw := int(nd["width"])
		var nh := int(nd["height"])
		var off := int(conn["offset"])
		var ox := 0
		var oy := 0
		match str(conn["dir"]):
			"north": ox = off; oy = -nh
			"south": ox = off; oy = map_h
			"west": ox = -nw; oy = off
			"east": ox = map_w; oy = off
		var np := _make_placed(label, nd, ox, oy)
		# Clip the neighbour perpendicular to the connection so it fills only the shared edge, not the
		# corners past the current map's edge (pokered draws a connection strip, not the whole map, and
		# fills the rest with the border block). Without this, a wide neighbour (e.g. Cerulean, 20 wide)
		# overhangs a narrow map (Route 5, 10 wide) and its trees pop in/out at the seam (gh #124).
		match str(conn["dir"]):
			"north", "south": np["clip"] = [maxi(ox, 0), mini(ox + nw, map_w), oy, oy + nh]
			"west", "east": np["clip"] = [ox, ox + nw, maxi(oy, 0), mini(oy + nh, map_h)]
		placed.append(np)

	queue_redraw()

	var cell: Vector2i
	if spawn_override != null:
		cell = spawn_override
	elif arrive_idx >= 0 and arrive_idx < (map["warps"] as Array).size():
		var w = map["warps"][arrive_idx]
		cell = Vector2i(int(w["x"]), int(w["y"]))
	else:
		cell = _default_spawn()
	player.place(cell, keep_facing)
	warp_armed = _warp_at(cell) == null
	_spawn_npcs()
	if audio:
		audio.play_map_music(center)
	if center_tileset not in OUTSIDE_TILESETS and riding and not force_bike:   # can't bike indoors/in caves
		riding = false
		player.step_scale = 1.0
	# A warp lands you on dry ground, so it dismounts. But `load_world` also rebases the world when the
	# player walks off the edge of the center map onto a connected neighbour — and out at sea that step
	# must keep them afloat, or they arrive standing on water (gh #82). Test the landing cell instead of
	# assuming: `_is_water` now resolves whichever placed map owns it.
	surfing = surfing and _is_water(cell)
	player._update_sprite()   # riding/surfing may have been cleared above -> reload the sheet now
	if in_safari and not center_label.begins_with("SafariZone"):
		end_safari_game()                                   # left the park -> safari game ends
	if FLY_DESTS.has(center_label) and not visited_fly.has(center_label):
		visited_fly.append(center_label)                    # unlock this town as a FLY destination
	_update_darkness()
	_on_map_loaded()


## Show/hide the dark-cave overlay (FLASH clears it; leaving a dark map resets FLASH).
func _update_darkness() -> void:
	if center_label not in DARK_MAPS:
		flash_lit = false
	if darkness:
		darkness.visible = (center_label in DARK_MAPS) and not flash_lit


## Map-arrival story triggers (mirrors per-map *_Script entry points that auto-run on load).
## The per-map script adapter for a map label (scripts/maps/<Label>.gd, cached for the session;
## docs/engine/map-scripts.md, gh #53). Unscripted maps share the no-op MapScript base.
func map_script(label: String) -> MapScript:
	if not _map_scripts.has(label):
		var path := "res://scripts/maps/%s.gd" % label
		var inst: MapScript
		if ResourceLoader.exists(path):
			# A hand-written adapter wins during a migration wave — but both existing at
			# once means a half-finished move; say so (gh #39).
			if event_vm != null and event_vm.maps.has(label):
				push_warning("[events] %s has BOTH an adapter and authored events — the adapter wins" % label)
			inst = load(path).new()
		elif event_vm != null and event_vm.maps.has(label):
			var ea := EventAdapter.new()
			ea.label = label
			inst = ea
		else:
			inst = MapScript.new()
		inst.main = self
		_map_scripts[label] = inst
	return _map_scripts[label]


## pokered runs a map's `*_Script` on **every** load. Two of our cutscenes load a map while they are still
## running — `Cutscene.fall_down_hole` and `Cutscene.fly_transition` — and a whiteout loads one out of the
## battle's own cutscene, so a callback dropped here is dropped for good: falling into the Pokémon Mansion
## never lays its switch-dependent doors, and whiting out into the Indigo Plateau lobby never resets the
## Elite Four. Defer instead, and run it the moment control comes back (gh #96).
var _pending_on_enter := ""


func _on_map_loaded() -> void:
	if cutscene_active or modal != null:
		_pending_on_enter = center_label
		return
	_pending_on_enter = ""
	map_script(center_label).on_enter()


## Flush a deferred load callback once the cutscene/modal that swallowed it has finished. Called every
## frame; the map must still be the one that was loaded (gh #96).
func _flush_pending_on_enter() -> void:
	if _pending_on_enter == "" or cutscene_active or modal != null:
		return
	var label := _pending_on_enter
	_pending_on_enter = ""
	if label == center_label:
		map_script(label).on_enter()


## Where the player lands when a load names no warp and no cell — the middle of the map, or the nearest
## walkable tile to it. It must not be an NPC's tile: a whiteout into the Indigo Plateau lobby put the
## player *on the nurse*, and an NPC-aware plan out of an occupied cell finds no path anywhere, so the
## Elite Four retry died on the spot without a word (gh #97).
func _default_spawn() -> Vector2i:
	var taken := {}
	for ev in map.get("object_events", []):
		taken[Vector2i(int(ev["x"]), int(ev["y"]))] = true
	var c := Vector2i(gw / 2, gh / 2)
	if _raw_walk(c) and not taken.has(c):
		return c
	for radius in range(0, maxi(gw, gh)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var n := c + Vector2i(dx, dy)
				if _raw_walk(n) and not taken.has(n):
					return n
	return _find_walkable(c)                          # every tile is taken: fall back to any walkable one


# ---- NPCs ------------------------------------------------------------------

const _FACE := {"UP": 1, "LEFT": 2, "RIGHT": 3}            # else (DOWN/NONE/...) -> 0
const _RANGE := {"UP_DOWN": [1, 0], "LEFT_RIGHT": [2, 3]}  # else (ANY_DIR) -> all


func _spawn_npcs() -> void:
	for n in npcs:
		n.queue_free()
	npcs = []
	for ev in map.get("object_events", []):
		var sprite := str(ev["sprite"])
		if not sprite_index.has(sprite):
			continue
		var info: Dictionary = sprite_index[sprite]
		var args: Array = ev.get("args", [])
		var movement := str(args[0]) if args.size() > 0 else "STAY"
		var dirtok := str(args[1]) if args.size() > 1 else "NONE"
		var text := ""
		for a in args:
			if str(a).begins_with("TEXT_"):
				text = str(a)
				break
		var npc := preload("res://scripts/NPC.gd").new()
		add_child(npc)
		npc.setup(self, str(info["file"]), {
			"cell": Vector2i(int(ev["x"]), int(ev["y"])),
			"frames": int(info["frames"]),
			"facing": int(_FACE.get(dirtok, 0)),
			"wander": movement == "WALK",
			"allowed": _RANGE.get(dirtok, [0, 1, 2, 3]) if movement == "WALK" else [],
			"text": text,
		})
		if args.size() >= 5 and str(args[3]).begins_with("OPP_"):
			npc.trainer_class = str(args[3])
			npc.trainer_num = int(args[4])
			npc.sight = int(ev.get("sight", 0))
			npc.battle_text = str(ev.get("battle_text", ""))
			npc.end_text = str(ev.get("end_text", ""))
			npc.after_text = str(ev.get("after_text", ""))
		elif args.size() >= 5 and mon_base.has(str(args[3]).to_lower()):
			npc.wild_species = str(args[3]).to_lower()     # a stationary legendary (species, level)
			npc.wild_level = int(args[4])
		for a in args:                              # overworld item ball: an item-const arg
			var an := str(a)
			if not an.begins_with("OPP_") and item_names.has(an):
				npc.item = str(item_names[an])
				break
		npc.key = "%s@%d,%d" % [sprite, int(ev["x"]), int(ev["y"])]
		npc.set_shown(_object_shown(center_label, npc.key))
		if npc.item != "" and picked_items.has("%s:%d,%d" % [center_label, npc.cell.x, npc.cell.y]):
			npc.set_shown(false)                    # already collected
		if npc.wild_species != "" and has_event("CAUGHT_STATIC_%s_%d_%d" % [center_label, npc.cell.x, npc.cell.y]):
			npc.set_shown(false)                    # a beaten/caught legendary/Voltorb doesn't respawn
		npcs.append(npc)


# Pokémon Center "bench guy": a person against the left wall you examine by facing LEFT — a hidden
# event (data/events/hidden_events.asm PrintBenchGuyText at 0,4), not an object. Text per Center.
const BENCH_GUY_TEXT := {
	"ViridianPokecenter": "POKéMON CENTERs\nheal your tired,\nhurt or fainted\nPOKéMON!",
	"PewterPokecenter": "Yawn!\fWhen JIGGLYPUFF\nsings, POKéMON\nget drowsy...",
	"CeruleanPokecenter": "BILL has lots of\nPOKéMON!\fHe collects rare\nones too!",
	"LavenderPokecenter": "CUBONEs wear\nskulls, right?\fPeople will pay\na lot for one!",
	"VermilionPokecenter": "It is true that a\nhigher level\nPOKéMON will be\nmore powerful...",
	"CeladonPokecenter": "If I had a BIKE,\nI would go to\nCYCLING ROAD!",
	"FuchsiaPokecenter": "If you're studying\nPOKéMON, visit\nthe SAFARI ZONE.\fIt has all sorts\nof rare POKéMON.",
	"CinnabarPokecenter": "POKéMON can still\nlearn techniques\nafter canceling\nevolution.",
	"SaffronPokecenter": "It would be great\nif the ELITE FOUR\ncame and stomped\nTEAM ROCKET!",
	"MtMoonPokecenter": "If you have too\nmany POKéMON, you\nshould store them\nvia PC!",
	"RockTunnelPokecenter": "I heard that\nGHOSTs haunt\nLAVENDER TOWN!",
}


# Simple gift NPCs (scripts/*.asm text_asm handlers with `GiveItem`) not covered by a cutscene:
# text id -> [item const, count, GOT_ event]. Handed over once, then the NPC shows its normal line.
const GIFT_NPCS := {
	"TEXT_ROUTE1_YOUNGSTER1": ["POTION", 1, "GOT_POTION_SAMPLE"],
	"TEXT_CELADONCITY_GRAMPS3": ["TM_SOFTBOILED", 1, "GOT_TM41"],
	"TEXT_CELADONMART3F_CLERK": ["TM_COUNTER", 1, "GOT_TM18",
		"TM18 is COUNTER!\nNot like the one\nI'm leaning on,\nmind you!"],
	"TEXT_CINNABARLABMETRONOMEROOM_SCIENTIST1": ["TM_METRONOME", 1, "GOT_TM35"],
	"TEXT_MRPSYCHICSHOUSE_MR_PSYCHIC": ["TM_PSYCHIC_M", 1, "GOT_TM29"],
	"TEXT_ROUTE12GATE2F_BRUNETTE_GIRL": ["TM_SWIFT", 1, "GOT_TM39"],
	"TEXT_SILPHCO2F_SILPH_WORKER_F": ["TM_SELFDESTRUCT", 1, "GOT_TM36"],
	"TEXT_VIRIDIANCITY_FISHER": ["TM_DREAM_EATER", 1, "GOT_TM42"],
}


## Story-driven initial visibility for map objects (mirrors pokered's toggleable-object states).
## Most objects are always shown; the opening-quest actors appear/disappear with story events.
func _object_shown(map_label: String, k: String) -> bool:
	if k.begins_with("SPRITE_SNORLAX@"):            # a road SNORLAX is gone once woken + beaten
		return not has_event("BEAT_SNORLAX_" + map_label)
	if k.begins_with("SPRITE_BOULDER@") and has_event("FELL_" + k):   # fell down a Seafoam hole
		return false
	# Per-map visibility rules live in the map's script adapter (docs/engine/map-scripts.md).
	# Note: dispatch is on map_label (the owning map), which can be a neighbor of the center map.
	var shown = map_script(map_label).object_shown(k)
	if shown != null:
		return shown
	return true


## Re-evaluate every current-map object's story visibility mid-scene — the ShowObject/HideObject
## sweeps some scripts run under a fade (Team Rocket leaving Silph, gh #158) — without waiting
## for the next map load.
func refresh_objects() -> void:
	for n in npcs:
		n.set_shown(_object_shown(center_label, n.key))


func _npc_by_key(k: String) -> Variant:
	for n in npcs:
		if n.key == k:
			return n
	return null


func _npc_at(cell: Vector2i) -> Variant:
	for n in npcs:
		if n.shown and n.cell == cell:
			return n
	return null


## Stable id for a trainer's defeated flag, keyed by its spawn (home) cell so it survives the
## trainer walking up to the player during a sight cutscene.
func trainer_id(npc) -> String:
	return "%s:%d,%d" % [center_label, npc.home.x, npc.home.y]


## First undefeated trainer whose line of sight (facing direction, up to `sight` tiles) reaches
## the player, else null. Mirrors TrainerEngage: lined up on the facing axis, in front, in range.
## No obstacle check (pokered's sight sees through tiles; maps are designed for it).
func _trainer_seeing_player(player_cell: Vector2i) -> Variant:
	for n in npcs:
		if not n.shown or n.trainer_class == "" or n.sight <= 0:
			continue
		if defeated_trainers.has(trainer_id(n)):
			continue
		var d: Vector2i = player_cell - n.cell
		var dist := 0
		match n.facing:                          # 0=DOWN 1=UP 2=LEFT 3=RIGHT
			0: dist = d.y if d.x == 0 and d.y > 0 else 0
			1: dist = -d.y if d.x == 0 and d.y < 0 else 0
			2: dist = -d.x if d.y == 0 and d.x < 0 else 0
			3: dist = d.x if d.y == 0 and d.x > 0 else 0
		if dist >= 1 and dist <= n.sight:
			return n
	return null


# Direction enums match Player/NPC: 0=DOWN 1=UP 2=LEFT 3=RIGHT.
const _PATH_DIRS := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]


## BFS over walkable terrain; returns the list of direction enums to walk from `start` to `goal`
## (empty if already there or unreachable). `start` and `goal` are always permitted (so an actor
## standing on / heading to a special tile still routes). Used for scripted cutscene movement.
func find_path(start: Vector2i, goal: Vector2i) -> Array:
	if start == goal:
		return []
	var came := {start: null}            # cell -> [prev_cell, dir_enum]
	var q: Array[Vector2i] = [start]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if cur == goal:
			break
		for i in 4:
			var nx: Vector2i = cur + _PATH_DIRS[i]
			# NPCs route around the player rather than walking through them (#23).
			if came.has(nx) or (nx != goal and (not is_walkable(nx) or nx == player.cell)):
				continue
			came[nx] = [cur, i]
			q.append(nx)
	if not came.has(goal):
		return []
	var dirs: Array = []
	var c: Vector2i = goal
	while came[c] != null:
		dirs.push_front(came[c][1])
		c = came[c][0]
	return dirs


func player_can_enter(cell: Vector2i) -> bool:
	return is_walkable(cell) and _npc_at(cell) == null


func npc_can_enter(cell: Vector2i, npc) -> bool:
	if not is_walkable(cell) or (player != null and player.cell == cell):
		return false
	var o = _npc_at(cell)
	return o == null or o == npc


# Hidden coordinate+facing events (data/events/hidden_events.asm). facing: -1 = any, else the
# Player dir enum (UP=1). Keyed by faced tile, like bg_events.
const HIDDEN_EVENTS := {
	"RedsHouse2F": [
		{"x": 0, "y": 1, "facing": 1, "kind": "pc"},      # OpenRedsPC (player faces UP)
		{"x": 3, "y": 5, "facing": -1, "kind": "snes"},   # PrintRedSNESText (ANY_FACING)
	],
	# The six quiz machines (PrintCinnabarQuiz args: gate index + which answer is right).
	"CinnabarGym": [
		{"x": 15, "y": 7, "facing": 1, "kind": "quiz", "gate": 1, "yes": true},
		{"x": 10, "y": 1, "facing": 1, "kind": "quiz", "gate": 2, "yes": false},
		{"x": 9, "y": 7, "facing": 1, "kind": "quiz", "gate": 3, "yes": false},
		{"x": 9, "y": 13, "facing": 1, "kind": "quiz", "gate": 4, "yes": false},
		{"x": 1, "y": 13, "facing": 1, "kind": "quiz", "gate": 5, "yes": true},
		{"x": 1, "y": 7, "facing": 1, "kind": "quiz", "gate": 6, "yes": false},   # TM28 is DIG, not "TOMBSTONER" -> NO (gh #173)
		{"x": 17, "y": 13, "facing": 1, "kind": "gym_statue"},
	],
	# The fossil-skeleton displays (hidden_events/museum_fossils.asm): the pic pops up in a
	# box with the plaque line. UP only, like the statues.
	"Museum1F": [
		{"x": 2, "y": 3, "facing": 1, "kind": "fossil", "pic": "fossil_aerodactyl", "name": "AERODACTYL"},
		{"x": 2, "y": 6, "facing": 1, "kind": "fossil", "pic": "fossil_kabutops", "name": "KABUTOPS"},
	],
	# The gym statues (hidden_events/gym_statues.asm, coords from badge_maps.asm; UP only).
	"ViridianGym": [
		{"x": 15, "y": 15, "facing": 1, "kind": "gym_statue"},
		{"x": 18, "y": 15, "facing": 1, "kind": "gym_statue"},
	],
	"PewterGym": [
		{"x": 3, "y": 10, "facing": 1, "kind": "gym_statue"},
		{"x": 6, "y": 10, "facing": 1, "kind": "gym_statue"},
	],
	"CeruleanGym": [
		{"x": 3, "y": 11, "facing": 1, "kind": "gym_statue"},
		{"x": 6, "y": 11, "facing": 1, "kind": "gym_statue"},
	],
	"VermilionGym": [
		{"x": 3, "y": 14, "facing": 1, "kind": "gym_statue"},
		{"x": 6, "y": 14, "facing": 1, "kind": "gym_statue"},
	],
	"CeladonGym": [
		{"x": 3, "y": 15, "facing": 1, "kind": "gym_statue"},
		{"x": 6, "y": 15, "facing": 1, "kind": "gym_statue"},
	],
	"FuchsiaGym": [
		{"x": 3, "y": 15, "facing": 1, "kind": "gym_statue"},
		{"x": 6, "y": 15, "facing": 1, "kind": "gym_statue"},
	],
	"SaffronGym": [
		{"x": 9, "y": 15, "facing": 1, "kind": "gym_statue"},
	],
}

# Each gym's city + leader strings (LoadGymLeaderAndCityName data, per gym script).
const _GYM_STATUE := {
	"PewterGym": ["PEWTER CITY", "BROCK"], "CeruleanGym": ["CERULEAN CITY", "MISTY"],
	"VermilionGym": ["VERMILION CITY", "LT.SURGE"], "CeladonGym": ["CELADON CITY", "ERIKA"],
	"FuchsiaGym": ["FUCHSIA CITY", "KOGA"], "SaffronGym": ["SAFFRON CITY", "SABRINA"],
	"CinnabarGym": ["CINNABAR ISLAND", "BLAINE"], "ViridianGym": ["VIRIDIAN CITY", "GIOVANNI"]}

# Which badge each gym's guide checks for its "you already won" line.
const _GYM_BADGE := {"PewterGym": "BOULDERBADGE", "CeruleanGym": "CASCADEBADGE",
	"VermilionGym": "THUNDERBADGE", "CeladonGym": "RAINBOWBADGE", "FuchsiaGym": "SOULBADGE",
	"SaffronGym": "MARSHBADGE", "CinnabarGym": "VOLCANOBADGE", "ViridianGym": "EARTHBADGE"}

## Gym guide line, branched on whether this gym's badge is already won (scripts/<Gym>.asm).
func _gym_guide_text() -> String:
	if str(_GYM_BADGE.get(center_label, "")) in badges:
		return "Just as I thought!\nYou're POKéMON\nchamp material!"
	return ("Hiya! I can tell\nyou have what it\ntakes to become a\nPOKéMON champ!"
		+ "\fThe 1st POKéMON\nout in a match is\nat the top of the\nPOKéMON LIST!"
		+ "\fBy changing the\norder of POKéMON,\nmatches could be\nmade easier!")


## Collect an overworld item ball (engine/events/pick_up_item.asm): add to the bag, mark it taken
## so it stays gone, and remove the sprite.
func _pick_up_item(npc) -> void:
	var item: String = npc.item
	if not add_item(item):                           # full: the ball stays where it is
		_say("%s found\n%s!\fBut %s has no\nroom for it!" % [player_name, item, player_name])
		return
	picked_items["%s:%d,%d" % [center_label, npc.cell.x, npc.cell.y]] = true
	npc.set_shown(false)
	if audio:
		audio.play_sfx("get_item1")
	_say("%s found\n%s!" % [player_name, item])


## Run a hidden-event script (engine/events/hidden_events/*).
func _hidden_event(kind: String, h: Dictionary = {}) -> void:
	match kind:
		"quiz":                                        # a Cinnabar Gym quiz machine
			cutscene.cinnabar_quiz(int(h["gate"]), bool(h["yes"]))
		"fossil":                                      # a museum fossil display (gh #71)
			cutscene.museum_fossil(str(h["pic"]), str(h["name"]))
		"gym_statue":                                  # GymStatues: the winners plaque (gh #68);
			var gs: Array = _GYM_STATUE[center_label]  # the player joins it once badged
			var t := "%s\nPOKéMON GYM\nLEADER: %s\fWINNING TRAINERS:\n<RIVAL>" % [gs[0], gs[1]]
			if str(_GYM_BADGE.get(center_label, "")) in badges:
				t += "\n<PLAYER>"
			_say(t)
		"snes":
			_say("%s is\nplaying the SNES!\f...Okay!\nIt's time to go!" % player_name)
		"pc":                                          # Red's bedroom PC = the player's item PC only
			if audio:                                  # (engine/.../reds_room.asm OpenRedsPC -> PlayerPC)
				audio.play_sfx("turn_on_pc")
			_pc_home = true                            # LOG OFF just exits (no full PC menu at home)
			_open_pc_item()


## Interact with whatever the player faces (NPC or sign). Returns true if handled.
func interact(p) -> bool:
	var front: Vector2i = p.front_cell()
	var tid := ""
	var npc = _npc_at(front)
	if npc == null and int(_tile_at(front)) in placed[0]["ts"].get("counter_tiles", []):
		npc = _npc_at(front + (front - p.cell))      # talk across a shop/Center counter
	# Per-map scripted interactions come first; return false falls through to the generic
	# handling below (hidden items, Cut, item balls, NPC text). See gh #53.
	if map_script(center_label).on_interact(front, npc):
		return true
	# Pokémon Center PC (hidden_event OpenPokemonCenterPC at 13,3 facing UP).
	if center_label.ends_with("Pokecenter") and front == Vector2i(13, 3) and p.facing == 1:
		_open_pc()
		return true
	# Pokémon Center bench guy: the person against the left wall (hidden_event at 0,4 facing LEFT). (#9)
	if BENCH_GUY_TEXT.has(center_label) and front == Vector2i(0, 4) and p.facing == 2:
		_say(BENCH_GUY_TEXT[center_label])
		return true
	# Hidden item on the faced tile (engine/events/hidden_items.asm) — checked before Cut so a hidden
	# item sharing a tile with a cuttable tree (e.g. the Viridian POTION at 14,4) is still reachable.
	if _try_hidden_item(front):
		return true
	# HM Cut: a cuttable tree in front (engine/overworld/cut.asm).
	if _try_cut(front):
		return true
	if npc != null:
		# Overworld item ball: collect the item, then it's gone for good.
		if npc.item != "":
			_pick_up_item(npc)
			return true
		# Stationary legendary (Articuno/Zapdos/Moltres/Mewtwo): a catchable wild battle.
		if npc.wild_species != "":
			cutscene.static_encounter(npc)
			return true
		npc.face_to(p.cell)
		# Gym guide: advice that changes once the gym's badge is won.
		if npc.key.begins_with("SPRITE_GYM_GUIDE@"):
			_say(_gym_guide_text())
			return true
		# Gym leader: pre-battle text -> battle -> badge + TM (or post-battle advice if beaten).
		if cutscene.is_gym_leader(npc.trainer_class):
			cutscene.gym_leader_battle(npc)
			return true
		# Trainer: undefeated -> before-battle text + fight; defeated -> after-battle line.
		if npc.trainer_class != "":
			if not defeated_trainers.has(trainer_id(npc)):
				cutscene.trainer_battle(npc, false)
				return true
			if npc.after_text != "":
				_say(npc.after_text)
				return true
		# Poké Mart clerk -> shop (BUY / SELL).
		if marts.has(center_label) and npc.key.begins_with("SPRITE_CLERK@"):
			_open_mart()
			return true
		tid = str(npc.text_id)
		# Pokémon Center nurse -> the heal ceremony (yes/no, the machine's balls + chime).
		if npc.file == "nurse":
			cutscene.nurse_heal(npc)
			return true
		# Cable Club receptionist (gh #5): the full CableClubNPC flow — HOST/JOIN stands in
		# for the cable, then the asm's save-warning/sync/LinkMenu beats over the link.
		if npc.file == "link_receptionist":
			cutscene.cable_club_npc(npc)
			return true
		# In-game trade NPC -> the full trade dialog (incl. the after-trade line).
		var tt: Dictionary = trades_data.get("text_trades", {})
		if tt.has(tid):
			_start_trade(tid, int(tt[tid]))
			return true
	else:
		for b in map.get("bg_events", []):
			if int(b["x"]) == front.x and int(b["y"]) == front.y:
				tid = str(b["text"])
				break
	if tid == "":
		# Hidden events (coordinate + facing scripts, data/events/hidden_events.asm).
		for h in HIDDEN_EVENTS.get(center_label, []):
			if int(h["x"]) == front.x and int(h["y"]) == front.y \
					and (int(h["facing"]) < 0 or int(h["facing"]) == p.facing):
				_hidden_event(str(h["kind"]), h)
				return true
		return false
	# The Copycat (CopycatsHouse2F): mimics you until you bring a POKé DOLL — she keeps the
	# doll and hands over TM31 (MIMIC).
	# The Route 1 mart youngster's free POTION sample, once (scripts/Route1.asm
	# EVENT_GOT_POTION_SAMPLE); after that he pitches POKé BALLs instead.
	if tid == "TEXT_ROUTE1_YOUNGSTER1":
		if has_event("GOT_POTION_SAMPLE"):
			_say("We also carry\nPOKé BALLs for\ncatching POKéMON!")
		elif not add_item("POTION"):
			_say("You have too much\nstuff with you!")
		else:
			set_event("GOT_POTION_SAMPLE")
			if audio: audio.play_sfx("get_item1")
			_say("Hi! I work at a\nPOKéMON MART.\fIt's a convenient\nshop, so please\nvisit us in\nVIRIDIAN CITY.\fI know, I'll give\nyou a sample!\nHere you go!\f%s got\nPOTION!" % player_name)
		return true
	# Lavender's NAME RATER (scripts/NameRatersHouse.asm): the rename ceremony.
	if tid == "TEXT_NAMERATERSHOUSE_NAME_RATER":
		cutscene.name_rater()
		return true
	# The Dept. Store roof girl: a drink from the bag for a TM (scripts/CeladonMartRoof.asm).
	if tid == "TEXT_CELADONMARTROOF_LITTLE_GIRL":
		cutscene.roof_girl()
		return true
	if tid == "TEXT_COPYCATSHOUSE2F_COPYCAT":
		var tm31: String = str(item_names.get("TM_MIMIC", "TM31"))
		if has_event("GOT_TM31"):
			_say("<PLAYER>: Hi!\nThanks for TM31!\f<PLAYER>: Pardon?\f<PLAYER>: Is it\nthat fun to mimic\nmy every move?\fCOPYCAT: You bet!\nIt's a scream!")
		elif int(player_bag.get("POKé DOLL", 0)) > 0:
			if not add_item(tm31):
				_say("Don't you want\nthis?")           # bag full: keeps the offer open
			else:
				player_bag["POKé DOLL"] = int(player_bag["POKé DOLL"]) - 1
				if int(player_bag["POKé DOLL"]) <= 0:
					player_bag.erase("POKé DOLL")
				set_event("GOT_TM31")
				if audio: audio.play_sfx("get_item1")
				_say("Oh wow!\nA POKé DOLL!\fFor me?\nThank you!\fYou can have\nthis, then!\f<PLAYER> received\n%s!\fTM31 contains my\nfavorite, MIMIC!\fUse it on a good\nPOKéMON!" % tm31)
		else:
			_say("<PLAYER>: Hi! Do\nyou like POKéMON?\f<PLAYER>: Uh no, I\njust asked you.\f<PLAYER>: Huh?\nYou're strange!\fCOPYCAT: Hmm?\nQuit mimicking?\fBut, that's my\nfavorite hobby!")
		return true
	if GIFT_NPCS.has(tid):                          # a simple gift NPC hands over its item once (#12)
		var g: Array = GIFT_NPCS[tid]
		if has_event(str(g[2])):
			# the "already got it" line differs from the pre-give offer (else the NPC re-offers the
			# item you already have — gh #133); use the optional 4th entry, else the NPC's text id
			_say(str(g[3]) if g.size() > 3 and str(g[3]) != "" else str(text_data.get(tid, "")))
		else:
			var gnm: String = str(item_names.get(str(g[0]), str(g[0])))
			if not add_item(gnm, int(g[1])):
				_say("You have no more\nroom for items!")   # ask again with a freer bag
				return true
			set_event(str(g[2]))
			if audio: audio.play_sfx("get_item1")
			var txt: String = str(text_data.get(tid, ""))     # the NPC's line first, then the item (#12)
			_say((txt + "\f" if txt != "" else "") + "%s received\n%s!" % [player_name, gnm])
		return true
	var s := str(text_data.get(tid, ""))
	if s == "":
		s = "(" + tid + ")"          # unresolved text id: show the id as a fallback
	_say(s)
	return true


# ---- title screen ----------------------------------------------------------

func _show_title() -> void:
	modal = title
	if audio:                # match the fight choreography to the intro-battle track length
		title._battle_dur = audio.song_length("introbattle")
	title.show_title()       # music is driven per phase via _on_title_phase


## Title boot music: silence over the star, the intro-battle theme, then the title theme.
func _on_title_phase(p: String) -> void:
	if not audio:
		return
	if p == "battle":
		audio.play_song("introbattle")
	elif p == "title":
		audio.stop()      # the bounce/whoosh play alone; TitleScreen starts the music after them
	else:
		audio.stop()


func _on_title_started() -> void:
	if audio:
		audio.play_cry(title.current_mon())   # the shown mon cries as the game starts (title.asm)
	title.visible = false
	_open_main_menu()


## Up+Select+B on the title (DoClearSaveDialogue, movie/oak_speech/clear_save.asm): a
## cleared screen asks "Clear all saved data?" over a NO/YES box at (14,7) — NO first, so
## a stray press can't wipe anything. YES clears the save; either way `jp Init` reboots
## to the title.
func _on_clear_save() -> void:
	if audio:
		audio.stop()
	title.visible = false
	menu_mode = "clear_save"
	modal = menu
	menu.open(["NO", "YES"], Vector2(112, 56), true)   # hlcoord 14,7
	menu.full_bg = true
	_say_keep("Clear all saved\ndata?")
	textbox.z_index = 1                   # the question shows through the full-bg blank


func _open_main_menu() -> void:
	var opts: Array = []
	if FileAccess.file_exists(SAVE_PATH):
		opts.append("CONTINUE")
	opts.append("NEW GAME")
	opts.append("OPTION")
	menu_mode = "title"
	modal = menu
	menu.open(opts, Vector2(0, 0))       # top-left box (engine/menus/main_menu.asm hlcoord 0,0)
	menu.box_w = 15                      # padded box width (TextBoxBorder c=13 -> 15 tiles)
	menu.full_bg = true                  # on a blank screen, not over the title
	menu.version = str(ProjectSettings.get_setting("application/config/version", ""))


func _title_choose(idx: int) -> void:
	if idx < 0:                           # B: back to the title screen itself, not the boot
		modal = title
		if audio:
			title._battle_dur = audio.song_length("introbattle")
		title.show_title_only()
		return
	var has_save := FileAccess.file_exists(SAVE_PATH)
	if idx == (2 if has_save else 1):     # OPTION (last item)
		open_options("title")
		return
	if has_save and idx == 0:             # CONTINUE
		load_game()
		if audio:
			audio.play_map_music(center_label)
		return
	if has_save:                          # NEW GAME: clear old save
		DirAccess.open("user://").remove(SAVE_PATH.get_file())
	_start_new_game()


## NEW GAME: reset state, spawn in Red's room, play Oak's speech, then hand control to the player.
func _start_new_game() -> void:
	story_events = {}
	force_bike = false
	player_name = "RED"
	rival_name = "BLUE"
	player_starter = ""
	rival_starter = ""
	badges = []
	player_party = []
	player_bag = {"POTION": 1}
	player_money = 3000
	player_id = randi() % 65536      # the trainer's ID number (shown on the stats screen)
	player_coins = 0
	fossil_mon = ""
	defeated_trainers = {}
	traded_npcs = {}
	picked_items = {}
	found_hidden = {}
	pc_box = []
	pc_items = {}
	hall_of_fame = []
	visited_fly = []
	in_safari = false
	safari_balls = 0
	safari_steps = 0
	pokedex_seen = {}
	pokedex_owned = {}
	last_outside_map = "PalletTown"                 # wLastMap = PALLET_TOWN (OakSpeech), so the
	                                                # house's LAST_MAP exit door leads outside
	load_world("RedsHouse2F", -1, Vector2i(3, 6))   # NewGameWarp: REDS_HOUSE_2F (3,6), facing down
	await cutscene.oak_speech()
	if audio:
		audio.play_map_music(center_label)


## Substitute the extracted text placeholders with the chosen names (text macros <PLAYER>
## and <RIVAL> are kept verbatim in text.json / the map JSONs).
func resolve_text(s: String) -> String:
	return s.replace("<PLAYER>", player_name).replace("<RIVAL>", rival_name)


## Show a dialogue string (becomes the active modal).
func _say(s: String) -> void:
	modal = textbox
	textbox.show_text(resolve_text(s))


## Show a textbox UNDER a modal menu (yes/no prompts like the toss confirmation): the text
## displays but input stays with the menu.
func _say_keep(s: String) -> void:
	textbox.show_text(resolve_text(s))


# ---- start menu ------------------------------------------------------------

## Apply the OPTION settings to the systems they drive: the letter delay becomes glyphs/s
## (60/frames: FAST 60, MEDIUM 20, SLOW 12) for both text boxes.
func apply_options() -> void:
	var gs := 60.0 / float(options["text_speed"])
	textbox.speed = gs
	battle.speed = gs


func open_options(from: String) -> void:
	_options_from = from
	menu_mode = ""
	modal = optionsscreen
	optionsscreen.open_menu()


func _on_card_closed() -> void:
	modal = null
	open_start_menu()                     # StartMenu_TrainerInfo -> RedisplayStartMenu (gh #59)


func _on_options_closed() -> void:
	modal = null
	if _options_from == "title":
		_open_main_menu()                 # back to CONTINUE/NEW GAME (DisplayOptionMenu returns)
	elif _options_from == "start":
		open_start_menu()                 # StartMenu_Option -> RedisplayStartMenu (gh #59)


## The start menu (draw_start_menu.asm): POKéDEX only once obtained, the player's own name
## for the trainer card, and EXIT at the bottom. Dispatch is by item text (the list shifts).
func open_start_menu() -> void:
	menu_mode = "start"
	modal = menu
	var items: Array = []
	if has_event("GOT_POKEDEX"):
		items.append("POKéDEX")
	items.append_array(["POKéMON", "ITEM", player_name, "SAVE", "OPTION", "EXIT"])
	menu.open(items, Vector2(80, 0))    # the box hugs the top-right (DrawStartMenu hlcoord 10,0)
	menu.box_w = 10                     # interior 8 wide; 14 tall with the dex, 12 without
	menu.box_h = 16 if has_event("GOT_POKEDEX") else 14
	menu.row0 = 2                       # first item at (12,2), 2 rows apart
	menu.cursor = clampi(_start_saved_idx, 0, items.size() - 1)  # wBattleAndStartSavedMenuItem
	menu.queue_redraw()


func _on_menu_chosen(idx: int) -> void:
	var mode := menu_mode
	menu.close()
	modal = null
	if audio and idx >= 0:
		audio.play_sfx("press_ab")
	if mode == "cutscene":
		return                          # a cutscene (e.g. ask_yes_no) owns this menu via its own await
	if mode == "title":
		_title_choose(idx)
		return
	if mode == "clear_save":
		textbox.visible = false
		textbox.z_index = 0
		if idx == 1 and FileAccess.file_exists(SAVE_PATH):    # YES (ClearAllSRAMBanks)
			DirAccess.open("user://").remove(SAVE_PATH.get_file())
		_show_title()                     # jp Init: either choice reboots to the title
		return
	if mode == "start":
		if idx < 0:
			_start_saved_idx = menu.cursor       # saved on any press (.buttonPressed)
			return
		_start_saved_idx = idx
		var it: String = str(menu.items[idx])
		if it == "POKéDEX":
			_open_dex()
		elif it == "POKéMON":
			_open_party_view()
		elif it == "ITEM":
			_open_bag()
		elif it == "SAVE":
			menu_mode = "yesno_save"
			modal = menu
			menu.open(["YES", "NO"], Vector2(0, 56))   # SaveTheGame_YesOrNo: hlcoord 0, 7
			menu.save_info = {
				"player": player_name, "badges": badges.size(), "dex": pokedex_owned.size(),
				# PrintPlayTime right-anchors: hours right-aligned in a 3-digit field at col 13,
				# the colon at 16, zero-padded minutes at 17-18 (gh #156).
				"time": "%3d:%02d" % [int(play_seconds / 3600.0), int(play_seconds / 60.0) % 60]}
		elif it == "OPTION":
			open_options("start")
		elif it != "EXIT":
			modal = trainercard        # the entry named after the player = the trainer card
			trainercard.open_card()
	elif mode == "yesno_save":
		if idx == 0:
			_save_ceremony()
	elif mode == "dex_list":
		if idx >= 0 and idx < dex_order.size():
			var sp: String = str(dex_order[idx])
			if pokedex_owned.has(sp) or pokedex_seen.has(sp):
				await show_dex_entry(sp, pokedex_owned.has(sp))
				_open_dex()                 # back to the list after viewing
	elif mode == "pkmn":
		if idx < 0:                             # B: abandon any pending SWITCH, back to the
			_swap_src = -1                      # START menu (StartMenu_Pokemon .exitMenu, gh #59)
			open_start_menu()
		elif _swap_src >= 0:                    # completing a SWITCH: swap the two party slots
			if _swap_src != idx:
				var tmp = player_party[_swap_src]
				player_party[_swap_src] = player_party[idx]
				player_party[idx] = tmp
			_swap_src = -1
			_open_party_view()
		else:
			_open_mon_menu(idx)
	elif mode == "mon_menu":
		if idx < 0 or idx >= _mon_menu_opts.size() or str(_mon_menu_opts[idx]) == "CANCEL":
			_open_party_view()
		elif str(_mon_menu_opts[idx]) == "STATS":
			modal = statsscreen
			statsscreen.open(player_party[_mon_menu_idx])
		elif str(_mon_menu_opts[idx]) == "SWITCH":
			_swap_src = _mon_menu_idx           # pick a second mon to swap with
			_open_party_view()
		else:
			_use_field_move(str(_mon_menu_opts[idx]))
	elif mode == "bag":
		_bag_saved_scroll = menu.scroll              # wListScrollOffset survives too
		if idx >= 0:
			_bag_saved_idx = idx                     # wBagSavedMenuItem: remembered either way
			_bag_select(idx)
		else:
			_bag_saved_idx = menu.cursor
			open_start_menu()                        # B backs out to the START menu (gh #59)
	elif mode == "bag_usetoss":
		if idx == 0:
			_bag_use()
		elif idx == 1:
			if selected_item in KEY_ITEMS:
				_say_bag("That's too impor-\ntant to toss out!")
			else:
				menu_mode = "bag_toss_qty"
				modal = menu
				menu.push_under()                    # USE/TOSS freezes under the ×NN picker
				# DisplayChooseQuantityMenu: the just-quantity box at (15,9)-(19,11)
				menu.open_qty(int(player_bag.get(selected_item, 1)), 0, Vector2(120, 72), true)
		else:
			_open_bag()                              # backed out: the bag list again
	elif mode == "bag_toss_qty":
		if idx >= 1:
			_bag_toss_n = idx
			menu_mode = "bag_toss_confirm"
			modal = menu
			menu.push_under()                        # the picker freezes at the chosen count
			menu.open(["YES", "NO"], Vector2(112, 56), true)   # TossItem_: yes/no box at (14,7)
			_say_keep("Is it OK to toss\n%s?" % selected_item)
			textbox.z_index = 1                      # the question overdraws the menu stack
		else:
			_open_bag()
	elif mode == "bag_toss_confirm":
		if idx == 0:
			player_bag[selected_item] = int(player_bag.get(selected_item, 0)) - _bag_toss_n
			if int(player_bag.get(selected_item, 0)) <= 0:
				player_bag.erase(selected_item)
				_bag_saved_idx = 0    # an emptied slot resets the cursor (RemoveItemFromInventory_)
				_bag_saved_scroll = 0
			textbox.visible = false
			menu.pop_under()          # TwoOptionMenu puts back the tiles the YES/NO box covered
			_say_bag("Threw away\n%s." % selected_item)
		else:
			textbox.visible = false
			_open_bag()
	elif mode == "bag_target":
		if idx >= 0:
			_bag_use_on(idx)
		else:
			_open_bag()                              # backed out of the party pick: the bag again
	elif mode == "bag_move_target":
		_bag_use_on_move(idx)
	elif mode == "teach_target":
		if idx >= 0:
			_teach(idx, true)
		else:
			_open_bag()
	elif mode == "vending":
		_vending_buy(idx)
	elif mode == "daycare_deposit":
		_daycare_deposit(idx)
	elif mode == "pc_top":
		match idx:
			0: _open_pc_mon()
			1: _open_pc_item()
			2: oaks_dex_rating()
			3:
				if has_event("HALL_OF_FAME"):      # POKéMON LEAGUE (only listed post-HoF)
					cutscene.league_pc()
				elif audio:
					audio.play_sfx("turn_off_pc")
			_:
				if audio: audio.play_sfx("turn_off_pc")
	elif mode == "pc_mon":
		match idx:
			0: _pc_withdraw_list()
			1: _pc_deposit_list()
			_: _open_pc()                                # SEE YA -> back to the top menu
	elif mode == "pc_withdraw":
		_pc_withdraw(idx)
	elif mode == "pc_deposit":
		_pc_deposit(idx)
	elif mode == "pc_item":
		match idx:
			0: _pc_item_list("withdraw")
			1: _pc_item_list("deposit")
			2: _pc_item_list("toss")
			_:                                       # LOG OFF: exit at home, else back to the PC menu
				if _pc_home:
					if audio: audio.play_sfx("turn_off_pc")
				else:
					_open_pc()
	elif mode == "pc_item_list":
		_pc_item_pick(idx)
	elif mode == "pc_item_qty":
		_pc_item_qty(idx)


# ---- bag / party / stone evolution -----------------------------------------

## Trainer card (start-menu name entry): name, money, badges, and Pokédex tally.
## Scrolling Pokédex list: every species in dex order, with its name once seen and a "*" once owned.
func _open_dex() -> void:
	_sync_owned()
	modal = dexlist
	dexlist.open()


func _open_party_view() -> void:
	if player_party.is_empty():           # pokered's menu simply won't open with no mons (gh #39)
		open_start_menu()
		return
	menu_mode = "pkmn"
	modal = menu
	menu.open_party(player_party, Vector2(8, 8))


## A party mon's submenu: its known field moves (CUT/FLASH/…) + STATS + CANCEL.
func _open_mon_menu(idx: int) -> void:
	_mon_menu_idx = idx
	_mon_menu_opts = []
	for mv in player_party[idx]["moves"]:
		if str(mv["move"]) in FIELD_MOVES:
			_mon_menu_opts.append(str(mv["move"]))
	_mon_menu_opts.append("STATS")
	if player_party.size() > 1:
		_mon_menu_opts.append("SWITCH")
	_mon_menu_opts.append("CANCEL")
	menu_mode = "mon_menu"
	modal = menu
	# The submenu hugs the bottom-right and grows UP with each field move (FIELD_MOVE_MON_MENU).
	menu.open(_mon_menu_opts, Vector2(88, 144 - (_mon_menu_opts.size() * 2 + 1) * 8))
	menu.keep_party = true                       # the party stays behind, its cursor hollow
	menu.party_sel = idx


## Use a field move from the party menu (FLASH lights a dark cave; CUT chops the tree in front).
func _use_field_move(move: String) -> void:
	var mon: Dictionary = player_party[_mon_menu_idx]
	var badge := ruleset.progression.badge_for_field_move(move)   # gh #34: config-driven gate
	if badge != "" and not badge in badges:
		_say("You can't use\nthat yet!")
		return
	if move == "FLASH":
		if center_label in DARK_MAPS and not flash_lit:
			flash_lit = true
			_update_darkness()
			if audio:
				audio.play_sfx("get_item1")
			_say("%s used\nFLASH!" % mon["name"])
		else:
			_say("It can't be used\nhere.")
	elif move == "CUT":
		if not _try_cut(player.front_cell()):
			_say("It can't be used\nhere.")
	elif move == "SURF":
		var fr: Vector2i = player.front_cell()
		if not surfing and _is_water(fr):
			surfing = true
			player.surf_hop(fr)                       # glide onto the water
			_say("%s used\nSURF!" % mon["name"])
		else:
			_say("It can't be used\nhere.")
	elif move == "STRENGTH":
		strength_active = true
		_say("%s used\nSTRENGTH!\fIt can now move\nboulders!" % mon["name"])
	elif move == "FLY":
		if center_tileset not in OUTSIDE_TILESETS:
			_say("Can't use that\nhere.")
		else:
			_open_fly_menu()
	elif move == "DIG":
		# start_sub_menus.asm `.dig`: DIG runs ItemUseEscapeRope verbatim (wPseudoItemID = ESCAPE_ROPE),
		# so it inherits the EscapeRopeTilesets + AGATHAS_ROOM refusal, and warps out the same way.
		if center_label == "AgathasRoom" or center_tileset not in ESCAPE_ROPE_TILESETS:
			_say("Can't use that\nhere.")
		else:
			_say("%s used DIG!" % mon["name"])
			_escape_warp()
	elif move == "TELEPORT":
		# start_sub_menus.asm `.teleport`: only outdoors (CheckIfInOutsideMap), then warp to the last
		# Pokémon Center — the same BIT_ESCAPE_WARP destination as ESCAPE ROPE / blackout.
		if center_tileset not in OUTSIDE_TILESETS:
			_say("Can't use that\nhere.")
		else:
			_say("%s teleported\nfrom the current\nlocation!" % mon["name"])
			_escape_warp()
	else:
		_say("It can't be used\nhere.")


func _party_labels() -> Array:
	var out: Array = []
	for m in player_party:
		out.append("%s :L%d" % [m["name"], m["level"]])
	return out


# ---- HM field moves (engine/overworld/cut.asm, …) --------------------------

## Bottom-left GB tile of a cell on the center map (collision/feet tile), or -1 if off-map.
func _tile_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= gw or cell.y >= gh:
		return -1
	var bid := int(map["blocks"][cell.y / 2][cell.x / 2])
	return int(placed[0]["ts"]["blockset"][bid][SUB[cell.y % 2][cell.x % 2]])


## Use the POKé FLUTE: wakes a SNORLAX you're facing (-> battle), else cures party sleep.
func _use_poke_flute() -> void:
	var fr: Vector2i = player.front_cell()
	var npc = _npc_at(fr)
	if npc != null and str(npc.key).begins_with("SPRITE_SNORLAX@"):
		cutscene.wake_snorlax(npc)
		return
	if audio:
		audio.play_sfx("pokeflute")                  # the flute's tune plays on use (gh #162)
	var cured := false
	for m in player_party:
		if str(m["status"]) == "slp":
			m["status"] = ""; m["sleep"] = 0; cured = true
	if cured:
		_say("Played the POKé\nFLUTE.\fYour POKéMON\nwoke up!")
	else:
		_say("Played the POKé\nFLUTE.\fNow, that's a\ncatchy tune!")


## Silently mount and establish the transient BIT_ALWAYS_ON_BIKE invariant (CheckForceBikeOrSurf).
func _mount_forced_bike() -> void:
	force_bike = true
	riding = true
	player.step_scale = 0.5


## Toggle the BICYCLE (2x walking speed). Outdoor maps only (ItemUseBicycle).
## Returns false when the use failed (wActionResultOrTookBattleTurn = 0).
func _toggle_bike() -> bool:
	if center_tileset not in OUTSIDE_TILESETS:
		_say("Can't get on the\nBICYCLE here!")
		return false
	# engine/menus/start_sub_menus.asm + field_move_messages.asm suppress dismount while
	# BIT_ALWAYS_ON_BIKE is set. Mounting remains allowed if state ever becomes inconsistent.
	if force_bike and riding:
		return true
	riding = not riding
	player.step_scale = 0.5 if riding else 1.0
	_say("%s got on the\nBICYCLE!" % player_name if riding else "%s got off the\nBICYCLE!" % player_name)
	return true


## FLY uses the Town Map and cycles only through visited towns, matching
## pokered/engine/items/town_map.asm LoadTownMap_Fly and BuildFlyLocationsList.
func _open_fly_menu() -> void:
	var dests: Array = []
	for lbl in FLY_DESTS:
		if not visited_fly.has(lbl) or not townmap_start.has(lbl):
			continue
		var entry_idx := int(townmap_start[lbl])
		if entry_idx < 0 or entry_idx >= townmap.entries.size():
			continue
		var entry: Dictionary = townmap.entries[entry_idx]
		dests.append({"label": lbl, "name": FLY_DESTS[lbl][1],
			"x": entry["x"], "y": entry["y"]})
	if dests.is_empty():
		_say("You haven't\nvisited any town\nyet!")
		return
	modal = townmap
	townmap.open_fly(dests)


func _on_fly_chosen(label: String) -> void:
	modal = null
	_text_then = Callable()
	if not FLY_DESTS.has(label):
		return
	cutscene.fly_transition(label, FLY_DESTS[label][0])


## Use a fishing rod (from the bag): if facing water, hook a wild mon, else nothing bites.
## Returns false when there's no water (a failed use returns to the bag).
func _use_rod() -> bool:
	var front: Vector2i = player.front_cell()
	if not (center_tileset in WATER_TILESETS and _tile_at(front) in WATER_TILES):
		_say("There's no water\nto fish in here!")
		return false
	var enc := _rod_encounter(selected_item)
	if enc["bite"]:
		cutscene.fish(str(enc["species"]), int(enc["level"]))
	else:
		_say("Not even a\nnibble!")
	return true


## Roll a rod encounter (engine/items/item_effects.asm ItemUse{Old,Good,Super}Rod). Returns
## {bite:bool, species, level}. The bit-twiddling mirrors the originals' bite/no-bite odds.
func _rod_encounter(kind: String) -> Dictionary:
	if kind == "OLD ROD":
		return {"bite": true, "species": "magikarp", "level": 5}
	var table: Array
	if kind == "GOOD ROD":
		table = GOOD_ROD_MONS
	elif SUPER_ROD_MAPS.has(center_label):
		table = SUPER_ROD_GROUPS[int(SUPER_ROD_MAPS[center_label])]
	else:
		return {"bite": false}                  # SUPER ROD with no fishing group here
	for _i in 64:                               # bounded re-roll (the 2-bit index can miss the table)
		var a := randi() % 256
		if a & 1:                               # srl a; carry set -> no bite (~50%)
			return {"bite": false}
		var sel := (a >> 1) & 3
		if sel >= table.size():                 # 2-bit index out of range -> re-roll
			continue
		return {"bite": true, "species": table[sel][1], "level": table[sel][0]}
	return {"bite": false}


func _mon_with_move(move: String) -> String:
	for m in player_party:
		for mv in m["moves"]:
			if str(mv["move"]) == move:
				return str(m["name"])
	return ""


## Whether any party mon can learn `move` from its TM/HM compatibility — i.e. whether `_pt_teach_hm`
## has a legal recipient. The legit-play bot builds a party of coverage/HM-slave mons, and none of
## Blastoise/Jigglypuff/Oddish/Diglett/Growlithe can learn FLY, so it must catch a carrier (gh #104).
func _pt_party_can_learn(move: String) -> bool:
	for m in player_party:
		if _can_learn(str(m["species"]), move):
			return true
	return false


## Whether `species` can learn `move` via its TM/HM compatibility (base_stats `tmhm` list) — e.g. the
## Squirtle line can't learn CUT in Gen 1, so a lone Wartortle needs a Cut slave (see _pt_ensure_cut_mon).
func _can_learn(species: String, move: String) -> bool:
	return move in mon_base[species].get("tmhm", [])


## Cut a tree at the faced cell, if it's a cuttable overworld tree and the party can Cut. Returns
## true if a tree was there (handled), false to fall through to other interactions.
func _try_cut(front: Vector2i) -> bool:
	if not CUT_TREE_TILES.has(center_tileset):         # cut trees exist on the OVERWORLD + GYM tilesets
		return false
	var cut_tile: int = CUT_TREE_TILES[center_tileset]
	if front.x < 0 or front.y < 0 or front.x >= gw or front.y >= gh:
		return false
	var bid := int(map["blocks"][front.y / 2][front.x / 2])
	if not CUT_TREE_BLOCKS.has(bid):
		return false
	var tile := int(placed[0]["ts"]["blockset"][bid][SUB[front.y % 2][front.x % 2]])
	if tile != cut_tile:                               # facing a non-tree quadrant of a tree block
		return false
	var cutter := _mon_with_move("CUT")
	if cutter == "" or not ruleset.progression.badge_for_field_move("CUT") in badges:   # can see it's cuttable, but can't yet (gh #34)
		_say("This tree looks\nlike it can be\nCUT down!")
		return true
	_cut_tree_anim(front, bid, cutter)                 # shake + flicker, then swap the block + text
	return true


## The CUT overworld animation (engine/overworld/cut.asm UsedCut -> cut2.asm AnimCut): the cuttable
## tree shakes horizontally and flickers its palette for 8 frames, then the tree block is replaced and
## SFX_CUT plays. Runs as its own coroutine (input locked via cutscene_active) so the caller returns at
## once; the "used CUT!" text follows the animation.
func _cut_tree_anim(front: Vector2i, bid: int, cutter: String) -> void:
	cutscene_active = true
	var ts: Dictionary = placed[0]["ts"]
	var bdef: Array = ts["blockset"][bid]
	var qx := front.x % 2                              # which 16x16 quadrant of the 32x32 block the tree is
	var qy := front.y % 2
	var tiles: Array = []
	for ty in 2:
		for tx in 2:
			tiles.append({"tid": int(bdef[(qy * 2 + ty) * 4 + (qx * 2 + tx)]), "ox": tx * TILE, "oy": ty * TILE})
	_cut_fx = {"cell": front, "dx": 0.0, "tiles": tiles, "tex": ts["tex"], "cols": int(ts["cols"])}
	set_block(front.x / 2, front.y / 2, int(CUT_TREE_BLOCKS[bid]))   # clear the tree behind the overlay
	if audio:
		audio.play_sfx("cut")
	# AnimCut: over 8 frames the tree's two halves squeeze toward centre — sprite36 X+1 / sprite38 X-1
	# cumulatively each frame (so ±8 px by the last frame), one DelayFrame (1/60 s) apart, then it's
	# gone. (The GB also flickers rOBP1 ^= $64 each frame; the port renders the tileset in true colour,
	# not palette indices, so an exact OBP1 swap would need a shader — the squeeze is faithful, the
	# per-frame colour flicker is the one part we can't reproduce cheaply.)
	for i in 8:
		_cut_fx["dx"] = float(i + 1)
		queue_redraw()
		await get_tree().create_timer(1.0 / 60.0).timeout
	_cut_fx = {}
	queue_redraw()
	cutscene_active = false
	_say("%s used CUT!" % cutter)


## Find a hidden item on the faced tile (engine/events/hidden_items.asm). One-shot per spot.
func _try_hidden_item(front: Vector2i) -> bool:
	for h in hidden_items.get(center_label, []):
		if int(h["x"]) == front.x and int(h["y"]) == front.y:
			var id := "%s:%d,%d" % [center_label, front.x, front.y]
			if found_hidden.has(id):
				return false                       # already taken — empty tile
			var nm: String = str(item_names.get(str(h["item"]), str(h["item"])))
			if not add_item(nm):                   # full: the hidden item stays put
				_say("%s found\n%s!\fBut %s has no\nroom for it!" % [player_name, nm, player_name])
				return true
			found_hidden[id] = true
			if audio:
				audio.play_sfx("get_item1")
			_say("%s found\n%s!" % [player_name, nm])
			return true
	return false


## Re-show the TM/HM target party menu (ItemUseTMHM .chooseMon).
func _reopen_teach_party() -> void:
	menu_mode = "teach_target"
	modal = menu
	# Show ABLE/NOT ABLE per mon so you can see who can learn the move (party_menu.asm .teachMoveMenu).
	var is_tm: bool = tm_moves.has(selected_item)
	var move: String = str(tm_moves[selected_item]) if is_tm else str(HM_MOVES.get(selected_item, ""))
	var flags: Array = []
	for m in player_party:
		flags.append(_can_learn(str(m["species"]), move))
	menu.open_party(player_party, Vector2(8, 8), flags)


## Teach an HM/TM move to a party mon (ItemUseTMHM). HMs aren't consumed; a TM is consumed
## only when the move is actually learned. `selected_item` is the machine's display name
## (e.g. "HM01"); only species whose TM/HM list includes the move can learn it.
## `from_bag` = taught from the item menu: can't-learn / already-knows re-show the party
## pick (.chooseMon) and the other outcomes return to the bag (StartMenu_Item's party-menu
## path); map-script givers (Cut, Fly, ...) leave the message on its own.
func _teach(idx: int, from_bag := false) -> void:
	if idx < 0 or idx >= player_party.size():
		return
	var is_tm: bool = tm_moves.has(selected_item)
	var move: String = str(tm_moves[selected_item]) if is_tm else str(HM_MOVES.get(selected_item, ""))
	var disp: String = str(mon_moves[move]["name"]) if mon_moves.has(move) else move
	var mon: Dictionary = player_party[idx]
	var compat: Array = mon_base[str(mon["species"])].get("tmhm", [])
	if move == "" or not move in compat:
		if from_bag:
			if audio: audio.play_sfx("denied")       # SFX_DENIED + back to the party pick
			_text_then = _reopen_teach_party
		_say("%s can't\nlearn %s!" % [mon["name"], disp])
		return
	for mv in mon["moves"]:
		if str(mv["move"]) == move:
			if from_bag:
				_text_then = _reopen_teach_party     # CheckIfMoveIsKnown -> .chooseMon
			_say("%s knows\n%s!" % [mon["name"], disp])
			return
	if (mon["moves"] as Array).size() >= 4:
		# Full moveset: the LearnMove forget flow (learn_move.asm, gh #60); the machine
		# is only consumed when the move was actually learned.
		await _overworld_learn(mon, move)
		var learned := false
		for mv in mon["moves"]:
			learned = learned or str(mv["move"]) == move
		if learned and is_tm:
			_consume(selected_item)
		if from_bag:
			_open_bag()
		return
	var pp := int(mon_moves[move]["pp"])
	mon["moves"].append({"move": move, "pp": pp, "maxpp": pp})
	if is_tm:                                        # TMs are single-use; HMs are not
		_consume(selected_item)
	if audio:
		audio.play_sfx("get_item1")
	if from_bag:
		_say_bag("%s learned\n%s!" % [mon["name"], disp])
	else:
		_say("%s learned\n%s!" % [mon["name"], disp])


# ---- Pokémon Center PC: Pokémon storage (engine/menus/pc.asm) --------------

func _open_pc() -> void:                           # top level (engine/menus/pc.asm)
	_pc_home = false                               # the full PC menu (Pokécenter) -> LOG OFF returns here
	if audio:
		audio.play_sfx("turn_on_pc")
	menu_mode = "pc_top"
	modal = menu
	var box := "BILL's PC" if has_event("USED_CELL_SEPARATOR_ON_BILL") else "SOMEONE'S PC"
	var items: Array = [box, "%s's PC" % player_name, "PROF.OAK's PC"]
	if has_event("HALL_OF_FAME"):
		items.append("POKéMON LEAGUE")     # the Hall of Fame records (engine/menus/pc.asm)
	items.append("LOG OFF")
	menu.open(items, Vector2(24, 8))


func _open_pc_mon() -> void:                       # Someone's/Bill's PC: Pokémon storage
	menu_mode = "pc_mon"
	modal = menu
	menu.open(["WITHDRAW POKéMON", "DEPOSIT POKéMON", "SEE YA"], Vector2(24, 8))


func _pc_box_labels() -> Array:
	var out: Array = []
	for m in pc_box:
		out.append("%s :L%d" % [m["name"], int(m["level"])])
	out.append("CANCEL")
	return out


## WITHDRAW: move a stored mon back to the party (needs a free party slot).
func _pc_withdraw_list() -> void:
	if pc_box.is_empty():
		if audio: audio.play_sfx("denied")
		_open_pc_mon()
		return
	menu_mode = "pc_withdraw"
	modal = menu
	menu.open(_pc_box_labels(), Vector2(8, 8))


func _pc_withdraw(idx: int) -> void:
	if idx < 0 or idx >= pc_box.size():             # CANCEL / B
		_open_pc_mon()
		return
	if player_party.size() >= 6:                    # party full -> can't withdraw
		if audio: audio.play_sfx("denied")
		_pc_withdraw_list()
		return
	player_party.append(pc_box[idx])
	pc_box.remove_at(idx)
	if audio: audio.play_sfx("withdraw_deposit")
	if pc_box.is_empty():
		_open_pc_mon()
	else:
		_pc_withdraw_list()


## DEPOSIT: store a party mon (can't deposit your last one).
func _pc_deposit_list() -> void:
	if player_party.size() <= 1:
		if audio: audio.play_sfx("denied")
		_open_pc_mon()
		return
	menu_mode = "pc_deposit"
	modal = menu
	menu.open(_party_labels() + ["CANCEL"], Vector2(8, 8))


func _pc_deposit(idx: int) -> void:
	if idx < 0 or idx >= player_party.size():       # CANCEL / B
		_open_pc_mon()
		return
	if player_party.size() <= 1:
		if audio: audio.play_sfx("denied")
		_open_pc_mon()
		return
	pc_box.append(player_party[idx])
	player_party.remove_at(idx)
	if audio: audio.play_sfx("withdraw_deposit")
	if player_party.size() <= 1:
		_open_pc_mon()
	else:
		_pc_deposit_list()


# ---- <PLAYER>'s PC: item storage (engine/menus/pc.asm RedsPCMenu) -----------

## PROF.OAK's POKéDEX rating (engine/events/pokedex_rating.asm DisplayDexRating): the
## DexCompletionText preamble (seen/owned counts), then one of DexRatingsTable's 16 tier
## texts keyed on species owned ("geting" is pokered's own typo — kept). PlayPokedexRatingSfx
## picks a jingle by owned band and plays it once the text has fully printed.
const _DEX_RATING_TIERS: Array = [
	[10, "You still have\nlots to do.\nLook for POKéMON\nin grassy areas!"],
	[20, "You're on the\nright track!\nGet a FLASH HM\nfrom my AIDE!"],
	[30, "You still need\nmore POKéMON!\nTry to catch\nother species!"],
	[40, "Good, you're\ntrying hard!\nGet an ITEMFINDER\nfrom my AIDE!"],
	[50, "Looking good!\nGo find my AIDE\nwhen you get 50!"],
	[60, "You finally got at\nleast 50 species!\nBe sure to get\nEXP.ALL from my\nAIDE!"],
	[70, "Ho! This is geting\neven better!"],
	[80, "Very good!\nGo fish for some\nmarine POKéMON!"],
	[90, "Wonderful!\nDo you like to\ncollect things?"],
	[100, "I'm impressed!\nIt must have been\ndifficult to do!"],
	[110, "You finally got at\nleast 100 species!\nI can't believe\nhow good you are!"],
	[120, "You even have the\nevolved forms of\nPOKéMON! Super!"],
	[130, "Excellent! Trade\nwith friends to\nget some more!"],
	[140, "Outstanding!\nYou've become a\nreal pro at this!"],
	[150, "I have nothing\nleft to say!\nYou're the\nauthority now!"],
	[152, "Your POKéDEX is\nentirely complete!\nCongratulations!"],
]
const _DEX_RATING_JINGLES: Array = [                 # audio/pokedex_rating_sfx.asm OwnedMonValues
	[10, "denied"], [40, "pokedex_rating"], [60, "get_item1"], [90, "caught_mon"],
	[120, "level_up"], [150, "get_key_item"], [256, "get_item2"],
]


func oaks_dex_rating(preamble := "") -> void:
	_sync_owned()
	var own := pokedex_owned.size()
	var tier := ""
	for t in _DEX_RATING_TIERS:
		tier = str(t[1])
		if own < int(t[0]):
			break
	var jingle := ""
	for j in _DEX_RATING_JINGLES:
		jingle = str(j[1])
		if own < int(j[0]):
			break
	_say(preamble + "POKéDEX comp-\nletion is:\f%d POKéMON seen\n%d POKéMON owned\fPROF.OAK's\nRating:\f%s"
			% [pokedex_seen.size(), own, tier])
	textbox.on_typed = func() -> void:
		if audio:
			audio.play_sfx(jingle)


func _open_pc_item() -> void:
	menu_mode = "pc_item"
	modal = menu
	menu.open(["WITHDRAW ITEM", "DEPOSIT ITEM", "TOSS ITEM", "LOG OFF"], Vector2(24, 8))


## List the box (withdraw/toss) or the bag (deposit) for the chosen action.
func _pc_item_list(action: String) -> void:
	_pc_item_action = action
	var src: Dictionary = player_bag if action == "deposit" else pc_items
	if src.is_empty():
		if audio: audio.play_sfx("denied")
		_open_pc_item()
		return
	_swap_first = -1                                 # SELECT reorders here too (players_pc.asm)
	_pc_item_keys = src.keys()
	var labels: Array = []
	for nm in _pc_item_keys:
		labels.append("%s x%d" % [nm, int(src[nm])])
	labels.append("CANCEL")
	menu_mode = "pc_item_list"
	modal = menu
	menu.open(labels, Vector2(8, 8))


func _pc_item_pick(idx: int) -> void:
	if idx < 0 or idx >= _pc_item_keys.size():       # CANCEL / B
		_open_pc_item()
		return
	_pc_item_sel = str(_pc_item_keys[idx])
	var src: Dictionary = player_bag if _pc_item_action == "deposit" else pc_items
	menu_mode = "pc_item_qty"
	modal = menu
	menu.open_qty(int(src.get(_pc_item_sel, 1)), 0, Vector2(72, 8))


func _pc_item_qty(n: int) -> void:
	if n <= 0:                                       # cancelled the quantity pick
		_pc_item_list(_pc_item_action)
		return
	match _pc_item_action:
		"withdraw": _move_item(pc_items, player_bag, _pc_item_sel, n)
		"deposit": _move_item(player_bag, pc_items, _pc_item_sel, n)
		"toss":
			pc_items[_pc_item_sel] = int(pc_items[_pc_item_sel]) - n
			if int(pc_items[_pc_item_sel]) <= 0:
				pc_items.erase(_pc_item_sel)
	if audio: audio.play_sfx("withdraw_deposit")
	_pc_item_list(_pc_item_action)


## Move up to n of an item between two count dictionaries (bag <-> PC box).
func _move_item(src: Dictionary, dst: Dictionary, item: String, n: int) -> void:
	n = min(n, int(src.get(item, 0)))
	if n <= 0:
		return
	src[item] = int(src[item]) - n
	if int(src[item]) <= 0:
		src.erase(item)
	dst[item] = int(dst.get(item, 0)) + n


# ---- Celadon vending machine (engine/events/vending_machine.asm) -----------

## Interacting with a machine shows the intro line, then opens the drink menu when it closes
## (VendingMachineText1, engine/events/vending_machine.asm; the result lines are in _vending_buy, gh #136).
func _vending_enter() -> void:
	moneybox.show_box()                              # ld a, MONEY_BOX before VendingMachineText1
	_say("A vending machine!\nHere's the menu!")     # VendingMachineText1 (prompt -> the menu)
	_text_then = _open_vending


func _open_vending() -> void:
	mart_keys = ["FRESH WATER", "SODA POP", "LEMONADE"]
	var labels: Array = []
	for nm in mart_keys:
		labels.append("%s ¥%d" % [nm, int(item_prices.get(nm, 0))])
	labels.append("CANCEL")
	menu_mode = "vending"
	modal = menu
	menu.open(labels, Vector2(8, 8))


func _vending_buy(idx: int) -> void:
	if idx < 0 or idx >= mart_keys.size():          # CANCEL / B -> VendingMachineText7, back to the map
		if audio:
			audio.play_sfx("press_ab")
		_say("Not thirsty!")
		_text_then = moneybox.hide_box              # the box clears with the script's end
		return
	var nm: String = mart_keys[idx]
	var price := int(item_prices.get(nm, 0))
	# pokered order (VendingMachineMenu): HasEnoughMoney, then GiveItem, then SubBCDPredef charges only
	# on a successful give. A full bag jumps to .BagFull with no charge — so the machine can't overflow
	# the 20-slot bag, and a refused can costs nothing (gh #126). Each outcome says its own line (gh #136).
	if player_money < price:                        # .enoughMoney fails -> VendingMachineText4
		if audio:
			audio.play_sfx("denied")
		_say("Oops, not enough\nmoney!")
	elif not add_item(nm):                           # GiveItem carry clear -> .BagFull (VendingMachineText6)
		if audio:
			audio.play_sfx("denied")
		_say("There's no more\nroom for stuff!")
	else:                                            # delivered: charge only now (SubBCDPredef after GiveItem)
		player_money -= price
		moneybox.refresh()                           # the box redraws the new balance (line 73)
		if audio:
			audio.play_sfx("purchase")
		_say("%s\npopped out!" % nm)                 # VendingMachineText5 ("<item> popped out!")
	_text_then = _open_vending                       # after the line closes, stay at the machine for another can


# ---- Poké Mart (engine/items/mart) -----------------------------------------

## The shop is its own modal now (MartScreen.gd): BUY/SELL/QUIT + MONEY boxes, the item list
## overlay, the ×NN strip, and the YES/NO confirm, all stacked as in the reference (gh #32).
func _open_mart() -> void:
	var names: Array = []
	for ic in marts[center_label]:
		names.append(str(item_names.get(ic, ic)))
	modal = martscreen
	martscreen.open(names)


var _swap_first := -1            # bag item "held" by SELECT for reordering (-1 = none)
var _bag_saved_idx := 0          # bag cursor, remembered across reopens (wBagSavedMenuItem)
var _bag_saved_scroll := 0       # bag window scroll, also remembered (wListScrollOffset)
var _start_saved_idx := 0        # start-menu cursor, restored on every redisplay
                                 # (wBattleAndStartSavedMenuItem, home/start_menu.asm)
var _text_then := Callable()     # one-shot: run when the current textbox/town-map closes
                                 # (ItemMenuLoop's return to the bag, TM teach's party reloop)
var _bag_idx := -1               # the bag row a USE/TOSS submenu is open for
var _bag_toss_n := 0             # quantity pending the toss confirmation
var _bag_target_idx := -1        # the party mon an ETHER/PP UP technique pick applies to

const BAG_CAPACITY := 20         # distinct item slots (wNumBagItems)
# Tilesets the ESCAPE ROPE (and Dig) can escape from (data/tilesets/escape_rope_tilesets.asm).
const ESCAPE_ROPE_TILESETS := ["forest", "cemetery", "cavern", "facility", "interior"]
# Items the bag refuses to TOSS ("too important"): pokered's key-item bit.
const KEY_ITEMS := ["TOWN MAP", "BICYCLE", "OLD ROD", "GOOD ROD", "SUPER ROD", "POKé FLUTE",
	"SILPH SCOPE", "S.S.TICKET", "SECRET KEY", "CARD KEY", "LIFT KEY", "GOLD TEETH",
	"DOME FOSSIL", "HELIX FOSSIL", "OLD AMBER", "BIKE VOUCHER", "COIN CASE", "ITEMFINDER",
	"EXP.ALL", "OAK's PARCEL", "HM01", "HM02", "HM03", "HM04", "HM05"]


## Add to the bag unless it's full — 20 distinct slots (wNumBagItems), 99 per stack
## (AddItemToInventory_). Returns false with nothing added so callers can leave the item
## behind. A stack overflow refuses the whole add: pokered would split the excess into a
## second slot when one is free, but slots here are name-keyed so duplicates can't exist.
func add_item(item: String, n := 1) -> bool:
	if not player_bag.has(item) and player_bag.size() >= BAG_CAPACITY:
		return false
	if int(player_bag.get(item, 0)) + n > 99:
		return false
	player_bag[item] = int(player_bag.get(item, 0)) + n
	return true


## The item rows for an ITEMLISTMENU over `keys` of `src`: [names (+CANCEL), quantities]
## paired arrays — key items print no ×NN (IsKeyItem).
func _item_rows(keys: Array, src: Dictionary) -> Array:
	var names: Array = []
	var qtys: Array = []
	for k in keys:
		names.append(str(k))
		qtys.append(-1 if k in KEY_ITEMS else int(src[k]))
	names.append("CANCEL")                           # the CANCEL entry (engine/menus/pack.asm)
	qtys.append(-1)
	return [names, qtys]


func _open_bag() -> void:
	_text_then = Callable()
	if player_bag.is_empty():
		_say("Your BAG is\nempty.")
		return
	_swap_first = -1
	menu_keys = player_bag.keys()
	var rows := _item_rows(menu_keys, player_bag)
	# The item list draws over the still-open START menu (StartMenu_Item never clears it —
	# you see its top border and EXIT peeking around the box): freeze it underneath with
	# its cursor parked hollow on ITEM.
	open_start_menu()
	menu.cursor = menu.items.find("ITEM")
	menu.push_under()
	menu_mode = "bag"
	modal = menu
	menu.open_itemlist(rows[0], rows[1], _bag_saved_idx, _bag_saved_scroll, true)


## An item-menu message that returns to the bag when dismissed. StartMenu_Item: using or
## tossing an item redisplays the item list (ItemMenuLoop) unless the item is in
## UsableItems_CloseMenu (escape rope / itemfinder / flute / rods) or is the BICYCLE.
## The open menus stay on the tilemap while the message shows (pokered prints the text
## after them, so the message box overdraws their bottom rows).
func _say_bag(s: String) -> void:
	_text_then = _open_bag
	_say(s)
	_keep_bag_shown()


## Keep whatever bag-flow boxes are up visible under a message: pokered leaves them on the
## tilemap and prints into the message box over their bottom rows. The live cursor turns
## hollow (PlaceUnfilledArrowMenuCursor runs before every item-menu action).
func _keep_bag_shown() -> void:
	menu.hollow = true
	menu.visible = true
	menu.queue_redraw()
	textbox.z_index = 1        # the message box overdraws the menu stack (drawn last)


## SELECT in an item list: hold one item, then SELECT another to swap their order
## (HandleItemListSwapping). ITEMLISTMENU surfaces only: the bag and the player's PC
## item lists. CANCEL can't be swapped; re-SELECTing the held item keeps it held.
func _on_menu_select(idx: int) -> void:
	var keys: Array
	var src: Dictionary
	if menu_mode == "bag":
		keys = menu_keys
		src = player_bag
	elif menu_mode == "pc_item_list":
		keys = _pc_item_keys
		src = player_bag if _pc_item_action == "deposit" else pc_items
	else:
		return
	if idx < 0 or idx >= keys.size():
		return
	if _swap_first < 0:
		_swap_first = idx                            # hold this item
	elif idx != _swap_first:
		var held = keys[_swap_first]                 # swap the two items' positions
		keys[_swap_first] = keys[idx]
		keys[idx] = held
		var reordered: Dictionary = {}
		for k in keys:
			reordered[k] = src[k]
		src.clear()                                  # reorder the dict in place
		src.merge(reordered)
		if menu_mode == "bag":                       # names + the ×NN quantity column
			var rows := _item_rows(keys, src)
			menu.items = rows[0]
			menu.qtys = rows[1]
		else:
			var labels: Array = []
			for k in keys:
				labels.append("%s x%d" % [k, int(src[k])])
			labels.append("CANCEL")
			menu.items = labels
		_swap_first = -1
	menu.swap_mark = _swap_first
	menu.queue_redraw()


## Selecting a bag item opens the USE/TOSS submenu first (engine/items/pack: ItemMenu).
## The BICYCLE skips the submenu and mounts/dismounts directly (StartMenu_Item).
func _bag_select(idx: int) -> void:
	if idx >= menu_keys.size():                      # CANCEL exits to the START menu (ExitListMenu)
		open_start_menu()
		return
	_bag_idx = idx
	selected_item = str(menu_keys[idx])
	_swap_first = -1                                 # choosing an item drops a held swap (.choseItem)
	menu.swap_mark = -1
	menu.cursor = idx                                # tests call this directly: park the ▷ on the row
	menu.scroll = clampi(menu.scroll, maxi(0, idx - 2), maxi(0, mini(idx, menu.items.size() - 3)))
	if selected_item == "BICYCLE":
		if not _toggle_bike():
			_text_then = _open_bag                   # failed use: back to the item list
			_keep_bag_shown()
		return
	menu_mode = "bag_usetoss"
	modal = menu
	menu.push_under()                                # the list keeps a hollow ▷ on the chosen row
	menu.open(["USE", "TOSS"], Vector2(104, 80), true)  # USE_TOSS_MENU_TEMPLATE: (13,10)-(19,14)


func _bag_use() -> void:
	if POTIONS.has(selected_item) or STATUS_HEALS.has(selected_item) or REVIVES.has(selected_item) \
			or selected_item == "RARE CANDY" or STONES.has(selected_item) \
			or VITAMINS.has(selected_item) or PP_ITEMS.has(selected_item) \
			or selected_item == "PP UP":
		menu_mode = "bag_target"
		modal = menu
		menu.open_party(player_party, Vector2(8, 8))
	elif HM_MOVES.has(selected_item) or tm_moves.has(selected_item):   # teach an HM/TM move
		# ItemUseTMHM: "Booted up a TM/HM! It contained X! Teach X to a POKéMON?" first;
		# NO returns to the bag (result 2 -> ItemMenuLoop), YES opens the party pick.
		var is_tm: bool = tm_moves.has(selected_item)
		var mv := str(tm_moves[selected_item]) if is_tm else str(HM_MOVES[selected_item])
		var disp := str(mon_moves[mv]["name"]) if mon_moves.has(mv) else mv
		if await cutscene.ask("Booted up %s!\fIt contained\n%s!\fTeach %s\nto a POKéMON?" % [
				"a TM" if is_tm else "an HM", disp, disp]):
			_reopen_teach_party()
		else:
			_open_bag()
	elif selected_item in ["OLD ROD", "GOOD ROD", "SUPER ROD"]:
		if not _use_rod():
			_text_then = _open_bag                   # no water: a failed use returns to the bag
	elif selected_item == "TOWN MAP":
		_text_then = _open_bag                       # not in UsableItems_CloseMenu: bag after the map
		_open_town_map()
	elif selected_item == "ITEMFINDER":              # sniffs the current map for unfound hidden items
		var near := false                            # UsableItems_CloseMenu: closes even when empty
		for h in hidden_items.get(center_label, []):
			if not found_hidden.has("%s:%d,%d" % [center_label, int(h["x"]), int(h["y"])]):
				near = true
				break
		_say("Yes! ITEMFINDER\nindicates there's\nan item nearby." if near
			else "Nope! ITEMFINDER\nisn't responding.")
	elif selected_item == "BICYCLE":                 # normally short-circuited in _bag_select
		if not _toggle_bike():
			_text_then = _open_bag
	elif selected_item == "POKé FLUTE":
		_use_poke_flute()                            # UsableItems_CloseMenu
	elif REPELS.has(selected_item):                 # field item, no target; back to the bag after
		repel_steps = int(REPELS[selected_item])
		_consume(selected_item)
		_say_bag("%s used.\nWild POKéMON will\nbe repelled." % selected_item)
	elif selected_item == "ESCAPE ROPE":
		# ItemUseEscapeRope: only in EscapeRopeTilesets (forest/cemetery/cavern/facility/
		# interior) and never in AGATHAS_ROOM; a failed use returns to the bag.
		if center_label == "AgathasRoom" or center_tileset not in ESCAPE_ROPE_TILESETS:
			_say_bag("OAK: %s!\nThis isn't the\ntime to use that!" % player_name)
		else:
			_consume(selected_item)                  # UsableItems_CloseMenu
			_say("%s used\nthe ESCAPE ROPE." % player_name)
			_escape_warp()                           # outside, at the last town's fly tile (gh #101)
	elif selected_item == "COIN CASE":
		# ItemUseCoinCase just reports the balance (text_bcd 2 | LEADING_ZEROES: 4 digits).
		_say_bag("Coins\n%04d" % player_coins)
	elif selected_item == "OAK's PARCEL":
		_say_bag("This isn't yours\nto use!")        # ItemUseNotYoursToUse
	else:
		# Everything else — balls, X items, key items — funnels into ItemUseNotTime out of
		# battle (UnusableItem and every routine's wIsInBattle gate; gh #175). The old
		# "Can't use that here!" line exists nowhere in pokered.
		_say_bag("OAK: %s!\nThis isn't the\ntime to use that!" % player_name)


func _bag_use_on(idx: int) -> void:
	if idx >= player_party.size():
		return
	var mon: Dictionary = player_party[idx]
	var fainted: bool = int(mon["hp"]) <= 0
	if POTIONS.has(selected_item):
		if fainted:
			_say_bag("It won't have\nany effect.")
			return
		var amt: int = int(POTIONS[selected_item])
		var heal: int = (int(mon["maxhp"]) - int(mon["hp"])) if amt < 0 else min(amt, int(mon["maxhp"]) - int(mon["hp"]))
		if heal <= 0 and not (selected_item == "FULL RESTORE" and str(mon["status"]) != ""):
			_say_bag("%s's HP is\nalready full!" % mon["name"])
			return
		mon["hp"] = int(mon["hp"]) + heal
		if selected_item == "FULL RESTORE":
			mon["status"] = ""; mon["sleep"] = 0
		_consume(selected_item)
		_say_bag("%s\nrecovered %d HP!" % [mon["name"], heal])
	elif STATUS_HEALS.has(selected_item):
		var cur := str(STATUS_HEALS[selected_item])
		if mon["status"] == "" or (cur != "*" and str(mon["status"]) != cur):
			_say_bag("It won't have\nany effect.")
			return
		mon["status"] = ""; mon["sleep"] = 0
		_consume(selected_item)
		_say_bag("%s's status\nwas healed!" % mon["name"])
	elif REVIVES.has(selected_item):
		if not fainted:
			_say_bag("It won't have\nany effect.")
			return
		mon["hp"] = maxi(1, int(int(mon["maxhp"]) * float(REVIVES[selected_item])))
		mon["status"] = ""; mon["sleep"] = 0
		_consume(selected_item)
		_say_bag("%s is\nrevived!" % mon["name"])
	elif selected_item == "RARE CANDY":
		if int(mon["level"]) >= 100:
			_say_bag("It won't have\nany effect.")
			return
		_consume(selected_item)
		await _rare_candy(mon)
		_open_bag()                                  # the level-up flow done: back to the item list
	elif VITAMINS.has(selected_item):
		# VitaminEffect: +2560 stat exp to the stat, refused at/above 25600; unlike battle
		# gains, vitamins recalculate the stats immediately.
		var vk: String = VITAMINS[selected_item][0]
		var se: Dictionary = mon.get("sexp", {"hp": 0, "atk": 0, "def": 0, "spd": 0, "spc": 0})
		if int(se.get(vk, 0)) >= 25600:
			_say_bag("It won't have\nany effect.")
			return
		se[vk] = mini(65535, int(se.get(vk, 0)) + 2560)
		mon["sexp"] = se
		var oldmax2 := int(mon["maxhp"])
		recompute_stats(mon)
		mon["hp"] = int(mon["hp"]) + (int(mon["maxhp"]) - oldmax2)
		_consume(selected_item)
		_say_bag("%s's\n%s rose!" % [mon["name"], str(VITAMINS[selected_item][1])])
	elif STONES.has(selected_item):
		if not await _try_stone(mon, str(STONES[selected_item])):
			_say_bag("It won't have\nany effect.")
	elif PP_ITEMS.has(selected_item) and bool(PP_ITEMS[selected_item][1]):
		# ELIXER / MAX ELIXER: every technique at once.
		var any := false
		for mv in mon["moves"]:
			var amt := int(PP_ITEMS[selected_item][0])
			var to := int(mv["maxpp"]) if amt < 0 else mini(int(mv["maxpp"]), int(mv["pp"]) + amt)
			any = any or to > int(mv["pp"])
			mv["pp"] = to
		if not any:
			_say_bag("It won't have\nany effect.")
			return
		_consume(selected_item)
		_say_bag("PP was restored.")
	elif PP_ITEMS.has(selected_item) or selected_item == "PP UP":
		# ETHER / MAX ETHER / PP UP: pick the technique next.
		_bag_target_idx = idx
		menu_mode = "bag_move_target"
		modal = menu
		var names: Array = []
		for mv in mon["moves"]:
			var key := str(mv["move"])
			names.append(str(mon_moves[key]["name"]) if mon_moves.has(key) else key)
		_say_keep("Raise PP of which\ntechnique?" if selected_item == "PP UP"
			else "Restore PP of\nwhich technique?")
		menu.open(names, Vector2(88, 8))


func _consume(item: String) -> void:
	player_bag[item] = int(player_bag[item]) - 1
	if int(player_bag[item]) <= 0:
		player_bag.erase(item)
		_bag_saved_idx = 0        # an emptied slot resets the bag cursor (RemoveItemFromInventory_)
		_bag_saved_scroll = 0


## Use a stone on `mon`: if it matches an EVOLVE_ITEM entry the stone is consumed and the evolution
## movie runs — **forced**, so B can't cancel it (pokered `ItemUseEvoStone` sets `wForceEvolution`,
## engine/items/item_effects.asm, unlike a level-up evolution; gh #134). Returns false when the stone
## had no effect (kept).
func _try_stone(mon: Dictionary, stone_const: String) -> bool:
	for ev in mon_base[str(mon["species"])]["evolutions"]:
		if str(ev[0]) == "EVOLVE_ITEM" and str(ev[1]) == stone_const and int(mon["level"]) >= int(ev[2]):
			_consume(selected_item)
			await run_evolution(mon, str(ev[3]), true)   # stone evolutions are not cancelable (gh #134)
			_open_bag()                              # ItemMenuLoop: back to the item list
			return true
	return false


# The three trade dialog sets (in_game_trades.asm InGameTradeTextPointers; texts from
# data/text/text_7.asm), with {GIVE}/{GET} the species display names.
const _TRADE_DIALOGS := [
	{   # TRADE_DIALOGSET_CASUAL
		"wanna": "I'm looking for\n{GIVE}! Wanna\ftrade one for\n{GET}? ",
		"no": "Awww!\nOh well...",
		"wrong": "What? That's not\n{GIVE}!\fIf you get one,\ncome back here!",
		"thanks": "Hey thanks!",
		"after": "Isn't my old\n{GET} great?",
	},
	{   # TRADE_DIALOGSET_EVOLUTION
		"wanna": "Hello there! Do\nyou want to trade\fyour {GIVE}\nfor {GET}?",
		"no": "Well, if you\ndon't want to...",
		"wrong": "Hmmm? This isn't\n{GIVE}.\fThink of me when\nyou get one.",
		"thanks": "Thanks!",
		"after": "The {GIVE} you\ntraded to me\fwent and evolved!",
	},
	{   # TRADE_DIALOGSET_HAPPY
		"wanna": "Hi! Do you have\n{GIVE}?\fWant to trade it\nfor {GET}?",
		"no": "That's too bad.",
		"wrong": "...This is no\n{GIVE}.\fIf you get one,\ntrade it with me!",
		"thanks": "Thanks pal!",
		"after": "How is my old\n{GET}?\fMy {GIVE} is\ndoing great!",
	},
]


## The in-game trade NPC flow (in_game_trades.asm DoInGameTradeDialogue): the dialog-set
## offer + YES/NO, the party pick (cancel = the no-trade line, wrong species refused),
## "Okay, connect the cable like so!", the trade movie, the swap + trade evo, then the
## jingled TradedFor line and the thanks. A completed trade leaves the AfterTrade line.
func _start_trade(tid: String, trade_idx: int) -> void:
	var trade: Dictionary = trades_data["trades"][trade_idx]
	var give: String = str(trade["give"])
	var dlg: Dictionary = _TRADE_DIALOGS[int(trade.get("dialogset", 0))]
	var names := {"GIVE": mon_display_name(give), "GET": mon_display_name(str(trade["get"]))}
	if traded_npcs.has(tid):
		_say(str(dlg["after"]).format(names))
		return
	cutscene_active = true
	modal = null
	if not await cutscene.ask(str(dlg["wanna"]).format(names)):
		await cutscene.say(str(dlg["no"]).format(names))
		cutscene_active = false
		return
	# InGameTrade_DoTrade: DisplayPartyMenu — pick the mon to hand over.
	menu_mode = "cutscene"
	modal = menu
	menu.open_party(player_party, Vector2(8, 8))
	var idx: int = await menu.chosen
	modal = null
	menu.close()
	if idx < 0:
		await cutscene.say(str(dlg["no"]).format(names))
		cutscene_active = false
		return
	if str(player_party[idx]["species"]) != give:
		await cutscene.say(str(dlg["wrong"]).format(names))
		cutscene_active = false
		return
	traded_npcs[tid] = true                       # FLAG_SET before the ceremony, as the asm
	await cutscene.say("Okay, connect the\ncable like so!")
	await _do_trade(idx, str(trade["get"]), str(trade["nick"]))
	if audio:
		audio.play_sfx("get_key_item")            # TradedForText's sound_get_key_item
	await cutscene.say("%s traded\n%s for\n%s!" % [player_name, names["GIVE"], names["GET"]])
	await cutscene.say(str(dlg["thanks"]).format(names))
	cutscene_active = false


## The trade proper: the movie (movie/trade.asm InternalClockTradeAnim), then the party
## swap — the received mon keeps the OT's nickname, OT "TRAINER", a random OT ID
## (InGameTrade_PrepareTradeData `call Random`) — then the forced trade evolution
## (InGameTrade_CheckForTradeEvo -> wForceEvolution; gh #67).
func _do_trade(found_idx: int, get_species: String, nick := "") -> void:
	var level: int = int(player_party[found_idx]["level"])
	var give_sp: String = str(player_party[found_idx]["species"])
	var give_ot: String = str(player_party[found_idx].get("ot", player_name))
	var give_otid: int = int(player_party[found_idx].get("otid", player_id))
	var newmon: Dictionary = make_mon(get_species, level, [])
	newmon["ot"] = "TRAINER"                     # a foreign OT: the NAME RATER refuses these
	newmon["otid"] = randi() % 65536
	if nick != "":
		newmon["name"] = nick                    # received mon keeps the OT's nickname
	await trademovie.play(give_sp, give_ot, give_otid, get_species, int(newmon["otid"]))
	player_party[found_idx] = newmon
	mark_owned(get_species)
	# Trade evolution: a received trade-evo species evolves immediately through the full
	# sequence, uncancellable (InGameTrade_CheckForTradeEvo -> wForceEvolution; gh #67).
	for ev in mon_base[get_species]["evolutions"]:
		if str(ev[0]) == "EVOLVE_TRADE" and level >= int(ev[1]):
			await run_evolution(newmon, str(ev[2]), true)
			break


func _evolve_mon(mon: Dictionary, into_const: String) -> void:
	var into := into_const.to_lower().replace("_", "")
	if not mon_base.has(into):
		return
	var b: Dictionary = mon_base[into]
	mon["species"] = into
	mon["name"] = mon_display_name(into)
	mon["types"] = b["types"]
	mon["base"] = {"hp": b["hp"], "atk": b["atk"], "def": b["def"], "spd": b["spd"], "spc": b["spc"]}
	mon["base_spd"] = int(b["spd"])
	recompute_stats(mon)
	mon["hp"] = min(int(mon["hp"]), int(mon["maxhp"]))
	mark_seen(into)                                  # the evolved form registers in the dex
	pokedex_owned[into] = true                       # (evos_moves.asm sets the own flag)


## The full evolution sequence for `mon` -> `into_const` (gh #67): the EvolveMon movie, the
## species change, the fanfare, and "<X> evolved into <Y>!". Returns false when the player
## cancelled with B ("Huh? X stopped evolving!" already shown; nothing applied).
func run_evolution(mon: Dictionary, into_const: String, forced := false) -> bool:
	var into := into_const.to_lower().replace("_", "")
	if not mon_base.has(into):
		return false
	var old := str(mon["name"])
	if not await cutscene.evolution(old, str(mon["species"]), into, forced):
		return false
	_evolve_mon(mon, into_const)
	if audio:
		audio.play_sfx("get_item2")                  # the evolution fanfare (SFX_GET_ITEM_2)
	await cutscene.say("%s evolved\ninto %s!" % [old, mon["name"]])
	return true


# ---- collision -------------------------------------------------------------

func is_walkable(cell: Vector2i) -> bool:
	if _blocked_cells.has(cell):
		return false                  # a warp tile hidden behind a wall (e.g. the Game Corner stairs)
	if _warp_at(cell) != null:
		return true
	if surfing and _is_water(cell):   # SURF: water is passable while riding
		return true
	return _cell_walkable(cell)


## A water/shore tile anywhere in the loaded world — the center map *or* a connected neighbour (for
## SURF traversal + fishing). Resolving the owning map is what makes surfing **across a connection**
## work: `_cell_walkable` already reads a neighbour's collision, where water is solid, so if this only
## knew the center map the sea would end at every map edge — sealing off Cinnabar Island, which has no
## dry connection at all (gh #82). Mirrors `_cell_walkable`'s walk over `placed`.
func _is_water(cell: Vector2i) -> bool:
	for pm in placed:
		var lx: int = cell.x - pm["ox"] * 2
		var ly: int = cell.y - pm["oy"] * 2
		if lx < 0 or ly < 0 or lx >= pm["w"] * 2 or ly >= pm["h"] * 2:
			continue
		if not (str(pm["data"]["tileset"]) in WATER_TILESETS):
			return false
		var bid := int(pm["data"]["blocks"][ly / 2][lx / 2])
		return int(pm["ts"]["blockset"][bid][SUB[ly % 2][lx % 2]]) in WATER_TILES
	return false


## STRENGTH: if the player walks into a boulder and the cell beyond is clear, shove it one tile — but
## only on the second consecutive push (see below). Returns true on the tile-moving push (the player may
## then step into the boulder's old cell).
# pokered TryPushingBoulder (engine/overworld/push_boulder.asm): a STRENGTH boulder moves only on the
# SECOND consecutive push in the same direction. The first sets BIT_TRIED_PUSH_BOULDER and bumps in place
# ("the player must try pushing twice before the boulder will move"), and after each tile moves the flag
# is reset (DoBoulderDustAnimation -> ResetBoulderPushFlags), so every tile of travel costs two pushes.
# Returns true only on the tile-moving push. (gh #129)
func try_push_boulder(cell: Vector2i, d: Vector2i) -> bool:
	if not strength_active:
		return false
	# pokered TryPushingBoulder: `bit BIT_BOULDER_DUST / ret nz` — while a shove is in flight
	# (slide + dust), a push attempt is ignored outright, before the sprite lookup or the arming.
	# Without this gate the bot's next-tile press armed mid-slide and then vanished into the dust
	# input lock, refusing every multi-tile shove's second tile (gh #28).
	if _boulder_dust_pending:
		return false
	var npc = _npc_at(cell)
	if npc == null or not str(npc.key).begins_with("SPRITE_BOULDER@"):
		_boulder_reset_tried()             # not facing a boulder: ResetBoulderPushFlags
		return false
	# First push against this boulder+direction only arms the tried flag and bumps in place; the boulder
	# does not move until the next same-direction push (a different boulder or direction re-arms instead).
	if cell != _boulder_tried_at or d != _boulder_tried_dir:
		_boulder_tried_at = cell
		_boulder_tried_dir = d
		return false
	var beyond: Vector2i = cell + d
	# A boulder can be shoved into a Seafoam hole even though the hole cell is unwalkable.
	var into_hole: bool = map_script(center_label).boulder_hole(beyond)
	if not into_hole:
		if not is_walkable(beyond) or _npc_at(beyond) != null:
			_boulder_reset_tried()         # collision: ResetBoulderPushFlags
			return false
		# pokered CheckForCollisionWhenPushingBoulder (engine/overworld/player_state.asm): after the
		# passability + sprite checks, the shove is ALSO refused across an elevation edge — a tile-pair
		# (LAND) mismatch between the player's tile (`cell - d`) and the destination two steps ahead
		# (`beyond`) — or onto a stairs tile ($15). Boulders are not exempt from tile-pairs.
		if _feet_tile(beyond) == 0x15 or _tile_pair_blocked(cell - d, beyond, true):
			_boulder_reset_tried()
			return false
	npc.cell = beyond
	var btw: Tween = npc.create_tween()    # the boulder slides one tile at NPC walk speed, not a snap
	btw.tween_property(npc, "position", Vector2(beyond * 16), npc.STEP_TIME)
	if audio:
		audio.play_sfx("push_boulder")     # SFX_PUSH_BOULDER as the slide starts (TryPushingBoulder)
	_boulder_dust_pending = true           # set BIT_BOULDER_DUST at the shove (TryPushingBoulder .done)
	_boulder_dust(btw, beyond, d)
	# Per-map boulder effects: Victory Road floor switches, Seafoam hole falls (gh #53).
	map_script(center_label).on_boulder(beyond, npc)
	_boulder_reset_tried()                 # boulder moved: the next tile needs two pushes again
	return true


# GB_PALETTE 0-3 as exact 8-bit fractions, so is_equal_approx matches extracted pixels.
const GB_SHADES := [
	Color(234.0 / 255.0, 251.0 / 255.0, 206.0 / 255.0),
	Color(181.0 / 255.0, 210.0 / 255.0, 149.0 / 255.0),
	Color(101.0 / 255.0, 138.0 / 255.0, 114.0 / 255.0),
	Color(34.0 / 255.0, 48.0 / 255.0, 57.0 / 255.0)]
var _smoke_texs: Array = []   # the 16x16 dust block: [OBP1 %11100100 normal, %10000000 washed]


## AnimateBoulderDust (engine/overworld/dust_smoke.asm): once the shoved boulder's slide
## lands, a 16x16 puff (the smoke tile x4) sits on the boulder's cell and drifts 1 px back
## toward the player each of 8 steps (Delay3 apart), OBP1 toggling %11100100 <-> %10000000
## per step so the puff flickers washed-out. It writes OAM sprites 36-39, which draw BEHIND
## every other sprite on the DMG — the puff emerges from under the boulder. Input stays
## locked for the run (the GB loop is synchronous) and SFX_CUT closes the beat
## (push_boulder.asm DoBoulderDustAnimation).
func _boulder_dust(btw: Tween, at: Vector2i, d: Vector2i) -> void:
	await btw.finished
	if _smoke_texs.is_empty():
		_smoke_texs = _build_smoke_texs()
	var s := Sprite2D.new()
	s.texture = _smoke_texs[0]
	s.centered = false
	s.position = Vector2(at * 16)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(s)
	move_child(s, 0)                            # beneath the boulder + player sprites
	var locked := not cutscene_active           # don't clear a cutscene on_boulder started
	cutscene_active = true
	for step in 8:
		s.position += Vector2(-d)               # the per-facing drift back toward the player
		s.texture = _smoke_texs[1 - step % 2]   # XOR %01100100: washed first, then alternating
		for f in 3:                             # Delay3 between steps
			await get_tree().create_timer(1.0 / 60.0).timeout
	s.queue_free()
	_boulder_dust_pending = false               # ResetBoulderPushFlags: the shove beat is over
	if locked:
		cutscene_active = false
	if audio:
		audio.play_sfx("cut")                   # DoBoulderDustAnimation's closing SFX_CUT


func _build_smoke_texs() -> Array:
	var tile: Image = (load("res://assets/sprites/smoke_dust.png") as Texture2D).get_image()
	if tile.is_compressed():
		tile.decompress()
	tile.convert(Image.FORMAT_RGBA8)
	var block := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for qy in 2:                                # LoadSmokeTileFourTimes: the same tile 2x2
		for qx in 2:
			block.blit_rect(tile, Rect2i(0, 0, 8, 8), Vector2i(qx * 8, qy * 8))
	var washed := Image.new()                   # OBP1 %10000000: colour 3 -> shade 2, 2/1 -> shade 0
	washed.copy_from(block)
	for y in 16:
		for x in 16:
			var c := washed.get_pixel(x, y)
			if c.a < 0.5:
				continue
			washed.set_pixel(x, y, GB_SHADES[2] if c.is_equal_approx(GB_SHADES[3]) else GB_SHADES[0])
	return [ImageTexture.create_from_image(block), ImageTexture.create_from_image(washed)]


## Clear BIT_TRIED_PUSH_BOULDER — the player faced away from the boulder, moved, or the shove collided,
## so the two-push count restarts (pokered ResetBoulderPushFlags). Called on turns and every real step.
func _boulder_reset_tried() -> void:
	_boulder_tried_at = Vector2i(-9999, -9999)
	_boulder_tried_dir = Vector2i.ZERO


func _cell_walkable(cell: Vector2i) -> bool:
	for pm in placed:
		var lx: int = cell.x - pm["ox"] * 2
		var ly: int = cell.y - pm["oy"] * 2
		var cw: int = pm["w"] * 2
		if lx >= 0 and ly >= 0 and lx < cw and ly < pm["h"] * 2:
			return pm["collision"][ly * cw + lx] == 1
	return false


func _owner_of(cell: Vector2i) -> Variant:
	for pm in placed:
		var lx: int = cell.x - pm["ox"] * 2
		var ly: int = cell.y - pm["oy"] * 2
		if lx >= 0 and ly >= 0 and lx < pm["w"] * 2 and ly < pm["h"] * 2:
			return pm
	return null


## The raw tile id at a cell's "feet" — the bottom-left tile of its 16px cell (pokered's coord 8,9 for
## the standing tile / GetTileAndCoordsInFront for the faced tile). -1 if the cell is off every map.
func _feet_tile(cell: Vector2i) -> int:
	for pm in placed:
		var lx: int = cell.x - pm["ox"] * 2
		var ly: int = cell.y - pm["oy"] * 2
		if lx >= 0 and ly >= 0 and lx < pm["w"] * 2 and ly < pm["h"] * 2:
			var bid := int(pm["data"]["blocks"][ly / 2][lx / 2])
			return int(pm["ts"]["blockset"][bid][SUB[ly % 2][lx % 2]])
	return -1


## The feet tile pokered sees at `cell` for the warp/tile-in-front check, reading the border block when the
## cell lies off the current map with no connected neighbour. LoadCurrentMapView fills the screen margin
## with the map's border block, so _GetTileAndCoordsInFrontOfPlayer reads that block's tile at a map edge —
## e.g. the S.S. Anne exit fires because facing up off the top edge sees the border tile $01, which is a
## fn2 warp-in-front tile (gh #80). Uniform border blocks (the common case) make the sub-tile choice moot.
func _feet_tile_or_border(cell: Vector2i) -> int:
	var t := _feet_tile(cell)
	if t != -1:
		return t
	if placed.is_empty():
		return -1
	var center: Dictionary = placed[0]
	return int(center["ts"]["blockset"][border_block][SUB[posmod(cell.y, 2)][posmod(cell.x, 2)]])


## pokered CheckForTilePairCollisions: forbid a step *between* two individually-walkable tiles at
## different elevations (e.g. cavern floor <-> the ledge beside it). Bidirectional, matched against the
## current map's tileset — LAND pairs on foot, WATER pairs while surfing. Ledge jumps bypass this (pokered
## checks jumping first), so callers only consult it for ordinary steps.
func _tile_pair_blocked(from_cell: Vector2i, to_cell: Vector2i, force_land := false) -> bool:
	var use_water := surfing and not force_land   # a boulder push always tests LAND pairs (see try_push_boulder)
	var pairs: Array = (TILE_PAIRS_WATER if use_water else TILE_PAIRS_LAND).get(center_tileset, [])
	if pairs.is_empty():
		return false
	var standing := _feet_tile(from_cell)
	var front := _feet_tile(to_cell)
	for p in pairs:
		if (standing == p[0] and front == p[1]) or (standing == p[1] and front == p[0]):
			return true
	return false


## Representative tile id (bottom-left of the cell) at a world cell, or -1.
func tile_at_cell(cell: Vector2i) -> int:
	var pm = _owner_of(cell)
	if pm == null:
		return -1
	var lx: int = cell.x - pm["ox"] * 2
	var ly: int = cell.y - pm["oy"] * 2
	var bid := int(pm["data"]["blocks"][ly / 2][lx / 2])
	return int(pm["ts"]["blockset"][bid][SUB[ly % 2][lx % 2]])


func is_grass_cell(cell: Vector2i) -> bool:
	var pm = _owner_of(cell)
	if pm == null:
		return false
	var gt := int(pm["ts"]["grass_tile"])
	return gt >= 0 and tile_at_cell(cell) == gt


## The bottom-right 8px tile of the half-block at `cell` (pokered's `hlcoord 9, 9`) — the
## wild-encounter RATE selector. _feet_tile reads its bottom-LEFT neighbour (`lda_coord 8, 9`),
## the TABLE selector.
func _bottom_right_tile(cell: Vector2i) -> int:
	for pm in placed:
		var lx: int = cell.x - pm["ox"] * 2
		var ly: int = cell.y - pm["oy"] * 2
		if lx >= 0 and ly >= 0 and lx < pm["w"] * 2 and ly < pm["h"] * 2:
			var bid := int(pm["data"]["blocks"][ly / 2][lx / 2])
			return int(pm["ts"]["blockset"][bid][SUB[ly % 2][lx % 2] + 1])
	return -1


## TryDoWildEncounter's tile rule: the encounter RATE keys off the half-block's bottom-RIGHT
## tile (the tileset's grass tile -> grass rate; water $14 -> water rate; else, indoors outside
## the FOREST tileset, any tile -> grass rate, gh #106) while the TABLE keys off the bottom-LEFT
## tile ($14 -> water table, else grass). The split is real: a "left shore" half-block has water
## bottom-right but land bottom-left, so Route 21's coast serves grass-table mons at the water
## rate. Returns [rate_kind, table_kind], or [] when this tile can't encounter.
func _wild_encounter_kinds(cell: Vector2i) -> Array:
	var pm = _owner_of(cell)
	if pm == null:
		return []
	var br := _bottom_right_tile(cell)
	var gt := int(pm["ts"].get("grass_tile", -1))
	var rate_kind := ""
	if gt >= 0 and br == gt:
		rate_kind = "grass"
	elif br == 0x14:                       # "in all tilesets with a water tile, this is its id"
		rate_kind = "water"
	elif center_tileset not in OUTSIDE_TILESETS and center_tileset != "forest":
		rate_kind = "grass"
	else:
		return []
	return [rate_kind, "water" if _feet_tile(cell) == 0x14 else "grass"]


## The 8x8 tile graphic at an absolute tile coordinate (8-px units), or {} outside every map.
func tile_gfx_at(tx: int, ty: int) -> Dictionary:
	var pm = _block_owner(tx >> 2, ty >> 2)
	if pm == null:
		return {}
	var bid := int(pm["data"]["blocks"][(ty >> 2) - pm["oy"]][(tx >> 2) - pm["ox"]])
	var tid := int(pm["ts"]["blockset"][bid][(ty & 3) * 4 + (tx & 3)])
	var cols: int = pm["ts"]["cols"]
	return {"tex": pm["ts"]["tex"], "src": Rect2((tid % cols) * TILE, (tid / cols) * TILE, TILE, TILE)}


const DIRV4 := {0: Vector2i(0, 1), 1: Vector2i(0, -1), 2: Vector2i(-1, 0), 3: Vector2i(1, 0)}


## Gen-1 grass priority (sprite_oam.asm + movement.asm): a sprite standing on the tileset's
## grass tile gets OAM_PRIO on its bottom two tiles, putting its lower half behind BG colors
## 1-3 — so the map tiles under that 16x8 band are redrawn on top, with the lightest shade
## keyed out by the overlay's shader (BG color 0 lets the sprite show through). The standing
## tile is the one being LEFT during a step (it updates on arrival), which is why legs pop
## under the grass as a step lands. Applies to the player, NPCs, and objects alike.
func _draw_grass_overlay() -> void:
	if placed.is_empty() or player == null:
		return
	var sprites: Array = npcs.duplicate()
	if not player.jumping:                # a ledge hop is airborne (and never starts on grass)
		sprites.append(player)
	for s in sprites:
		if s != player and not s.shown:
			continue
		var sc: Vector2i = s.cell
		if s.moving:
			sc -= DIRV4[int(s.facing)]    # mid-step: still standing on the departure tile
		if not is_grass_cell(sc):
			continue
		var band := Rect2(s.position.x, s.position.y + 4.0, 16.0, 8.0)   # the sprite's lower half
		for ty in range(floori(band.position.y / 8.0), ceili(band.end.y / 8.0)):
			for tx in range(floori(band.position.x / 8.0), ceili(band.end.x / 8.0)):
				var g := tile_gfx_at(tx, ty)
				if g.is_empty():
					continue
				var dst := Rect2(tx * 8.0, ty * 8.0, 8.0, 8.0).intersection(band)
				if dst.size.x <= 0.0 or dst.size.y <= 0.0:
					continue
				var src: Rect2 = g["src"]
				src.position += dst.position - Vector2(tx * 8.0, ty * 8.0)
				src.size = dst.size
				grass_overlay.draw_texture_rect_region(g["tex"], dst, src)


## True if stepping `dir` from `cell` should hop a ledge (overworld tileset only).
func ledge_match(cell: Vector2i, dir: String, delta: Vector2i) -> bool:
	if center_tileset != "overworld":
		return false
	var stand := tile_at_cell(cell)
	var front := tile_at_cell(cell + delta)
	for l in center_ledges:
		if str(l["dir"]) == dir and int(l["stand"]) == stand and int(l["ledge"]) == front:
			return true
	return false


## Center-map-only passability (ignores warp override; used by tests).
func _raw_walk(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= gw or cell.y >= gh:
		return false
	return collision[cell.y * gw + cell.x] == 1


func _find_walkable(near: Vector2i) -> Vector2i:
	for radius in range(0, max(gw, gh)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := near + Vector2i(dx, dy)
				if _raw_walk(c):
					return c
	return Vector2i.ZERO


# ---- warps & connection crossing -------------------------------------------

func _warp_at(cell: Vector2i) -> Variant:
	for w in map["warps"]:
		if int(w["x"]) == cell.x and int(w["y"]) == cell.y:
			return w
	return null


# --- Warp firing (gh #80) -----------------------------------------------------
# pokered doesn't warp just because you stand on a warp square. `CheckWarpsNoCollision` warps only if
# the tile under you is a door/warp tile (IsPlayerStandingOnDoorTileOrWarpTile -> immediate), OR the
# ExtraWarpCheck passes: fn1 IsPlayerFacingEdgeOfMap (you're stepping toward the map edge) / fn2
# IsWarpTileInFrontOfPlayer (the faced tile is a warp tile). Without this a warp on a plain tile fires
# from any direction — Silph 11F's (5,5) yanked you out and sealed the president, and Victory Road's
# entrance ejects you when you stand on it to push a boulder. Feet/door/warp tile IDs are per tileset
# (data/tilesets/{warp,door}_tile_ids.asm), unioned here since both mean "warp on step".
const _WARP_DOOR_TILES := {
	"overworld": [0x1B, 0x58], "redshouse1": [0x1A, 0x1C], "redshouse2": [0x1A, 0x1C],
	"mart": [0x5E], "pokecenter": [0x5E], "forest": [0x5A, 0x5C, 0x3A], "dojo": [0x4A], "gym": [0x4A],
	"house": [0x54, 0x5C, 0x32], "forestgate": [0x3B, 0x1A, 0x1C], "museum": [0x3B, 0x1A, 0x1C],
	"gate": [0x3B, 0x1A, 0x1C], "ship": [0x37, 0x39, 0x1E, 0x4A], "shipport": [], "club": [],
	"cemetery": [0x1B, 0x13], "interior": [0x15, 0x55, 0x04], "cavern": [0x18, 0x1A, 0x22],
	"lobby": [0x1A, 0x1C, 0x38], "mansion": [0x1A, 0x1C, 0x53], "lab": [0x34],
	"facility": [0x43, 0x58, 0x20, 0x1B, 0x13], "underground": [0x13], "plateau": [0x1B, 0x3B]}
# DOOR tiles per tileset (data/tilesets/door_tile_ids.asm — doors ONLY, unlike the warp union
# above): a warp arrival standing on one steps the player DOWN off the doorway
# (PlayerStepOutFromDoor, gh #142). Tilesets absent here (pokecenter, cavern, interior…) never step.
const _DOOR_TILES := {
	"overworld": [0x1B, 0x58], "forest": [0x3A], "mart": [0x5E], "house": [0x54],
	"forestgate": [0x3B], "museum": [0x3B], "gate": [0x3B], "ship": [0x1E],
	"lobby": [0x1C, 0x38, 0x1A], "mansion": [0x1A, 0x1C, 0x53], "lab": [0x34],
	"facility": [0x43, 0x58, 0x1B], "plateau": [0x3B, 0x1B]}
# fn2 warp tiles by facing (data/tilesets/../warp_tile_ids.asm WarpTileListPointers). DOWN/UP/LEFT/RIGHT.
const _WARP_FRONT_TILES := {
	0: [0x01, 0x12, 0x17, 0x3D, 0x04, 0x18, 0x33], 1: [0x01, 0x5C], 2: [0x1A, 0x4B], 3: [0x0F, 0x4E]}
# Maps/tilesets whose ExtraWarpCheck uses fn2 (warp-tile-in-front) instead of fn1 (facing edge).
const _WARP_FN2_MAPS := ["RocketHideoutB1F", "RocketHideoutB2F", "RocketHideoutB4F", "RockTunnel1F"]
const _WARP_FN2_TILESETS := ["overworld", "ship", "shipport", "plateau"]


## pokered's ExtraWarpCheck dispatch: fn2 for the Rocket Hideout basements, Rock Tunnel 1F, and the
## OVERWORLD/SHIP/SHIP_PORT/PLATEAU tilesets — but SS_ANNE_3F is a fn1 exception.
func _extra_warp_fn2() -> bool:
	if center_label == "SSAnne3F":
		return false
	return center_label in _WARP_FN2_MAPS or center_tileset in _WARP_FN2_TILESETS


## Should standing on warp `cell` facing `facing` (default the player's) actually fire it? (gh #80)
func _warp_should_fire(cell: Vector2i, facing := -1) -> bool:
	var f: int = facing if facing >= 0 else player.facing
	var t := _feet_tile(cell)
	if t in _WARP_DOOR_TILES.get(center_tileset, []):
		return true                                  # door/warp tile: warps on step (doors, ladders, stairs)
	if _extra_warp_fn2():                             # fn2: the faced tile is a warp tile (border-aware at edges)
		var front := _feet_tile_or_border(cell + DIRV4[f])
		if center_label == "SSAnneBow":              # IsSSAnneBowWarpTileInFrontOfPlayer: $15 only, any facing
			return front == 0x15                     # (bypasses the generic WarpTileListPointers list, gh #130)
		return front in _WARP_FRONT_TILES[f]
	match f:                                          # fn1: stepping toward the map edge
		0: return cell.y == gh - 1                    # DOWN
		1: return cell.y == 0                         # UP
		2: return cell.x == 0                         # LEFT
		3: return cell.x == gw - 1                    # RIGHT
	return false


func _neighbor_owning(cell: Vector2i) -> Variant:
	for i in range(1, placed.size()):
		var pm: Dictionary = placed[i]
		var lx: int = cell.x - pm["ox"] * 2
		var ly: int = cell.y - pm["oy"] * 2
		if lx >= 0 and ly >= 0 and lx < pm["w"] * 2 and ly < pm["h"] * 2:
			return pm
	return null


func _on_player_moved(cell: Vector2i) -> void:
	_boulder_reset_tried()   # a real step (incl. after a shove) ends the two-push attempt (gh #129)
	# Spin tiles (RocketHideoutB2F/B3F + ViridianGym): landing on an arrow launches the slide.
	if not cutscene_active and modal == null:
		var spin: Array = spinners.get(center_label, {}).get("%d,%d" % [cell.x, cell.y], [])
		if not spin.is_empty():
			_do_spin(spin)
			return
	# Per-map step triggers run before rebase / warps / trainer sight, as pokered's *_Script
	# state machines run first each overworld frame (docs/engine/map-scripts.md, gh #53).
	if not cutscene_active and modal == null and map_script(center_label).on_step(cell):
		return
	# Crossed off the center map into a connected neighbor? Rebase the world onto it.
	if cell.x < 0 or cell.y < 0 or cell.x >= gw or cell.y >= gh:
		var nb = _neighbor_owning(cell)
		if nb != null:
			if str(map["tileset"]) in OUTSIDE_TILESETS:
				last_outside_map = str(map["name"])
			var local := Vector2i(cell.x - nb["ox"] * 2, cell.y - nb["oy"] * 2)
			load_world(str(nb["label"]), -1, local, true)
		return
	# Otherwise handle warp tiles (inside the center map).
	var w = _warp_at(cell)
	if w == null:
		warp_armed = true
		# Trainer line-of-sight: a trainer facing the player within range engages (home/trainers.asm
		# CheckFightingMapTrainers). Takes priority over poison/wild encounters.
		if modal == null and not cutscene_active:
			var seer = _trainer_seeing_player(cell)
			if seer != null:
				cutscene.trainer_spotted(seer)
				return
		if not daycare_mon.is_empty():   # the Day Care mon earns 1 EXP per step
			daycare_mon["exp"] = int(daycare_mon["exp"]) + 1
		if in_safari:                    # the Safari game ends when the step counter runs out
			safari_steps -= 1
			if safari_steps <= 0:
				cutscene.safari_game_over()
				return
		if _overworld_poison():       # poison tick may faint a mon (shows a message)
			return
		if surfing and not _is_water(cell):   # stepped from water onto land -> dismount
			surfing = false
			player._update_sprite()           # .stopSurfing reloads the walking sheet on the spot
		if wild_cooldown_steps > 0:
			# The 3 battle-free steps after every battle (wNumberOfNoRandomBattleStepsLeft):
			# DetermineWildOpponent returns before TryDoWildEncounter, so the REPEL counter
			# doesn't tick on these steps either.
			wild_cooldown_steps -= 1
		elif modal == null:
			# REPEL ticks every encounter-capable step (TryDoWildEncounter's top); the step it
			# expires prints the wear-off text and cannot encounter. While active it does NOT
			# block the roll — the level filter in _try_wild_encounter decides per wild mon.
			var repel_expired := false
			if repel_steps > 0:
				repel_steps -= 1
				if repel_steps == 0:
					_say("REPEL's effect\nwore off.")
					repel_expired = true
			if not repel_expired:
				var kinds := _wild_encounter_kinds(cell)
				if kinds.size() == 2:
					_try_wild_encounter(kinds[1], false, kinds[0])
	elif warp_armed and _warp_should_fire(cell):
		_do_warp(w)


## A Saffron gate guard: give a drink to pass (opening all four gates), else get pushed back.
## Open the TOWN MAP viewer, starting the cursor at the player's current location if it's listed.
func _open_town_map() -> void:
	var start: Dictionary = townmap_start
	modal = townmap
	townmap.open(int(start.get(center_label, 0)))


## The four members' trainer ids (`<map>:<home x>,<home y>`), which is how the port records a defeat.
const E4_TRAINER_IDS := ["LoreleisRoom:5,2", "BrunosRoom:5,2", "AgathasRoom:5,2", "LancesRoom:6,1"]


## SaveMenu's save beat (engine/menus/save.asm): "Now saving..." sits alone in the textbox for
## 120 frames, then "<PLAYER> saved the game!" prints and SFX_SAVE rings out (gh #156).
func _save_ceremony() -> void:
	if not save_game():
		_say("Save failed!")
		return
	modal = textbox
	textbox.show_text("Now saving...")
	await get_tree().create_timer(2.0).timeout       # ld c, 120 / call DelayFrames
	_say("%s saved\nthe game!" % player_name)        # GameSavedText, then SFX_SAVE rings out
	if audio:
		audio.play_sfx("save")


## The Indigo Plateau event-range wipe (`ResetEventRange INDIGO_PLATEAU_EVENTS_*`): the four stand
## back up and LANCE's door locks shut again. Shared by the lobby's gauntlet reset (gh #96, which
## stops at EVENT_LANCES_ROOM_LOCK_DOOR) and the Hall of Fame's post-credits reset (gh #179, which
## runs to INDIGO_PLATEAU_EVENTS_END and so also fells the champion rival for the rematch).
func reset_elite4_gauntlet(include_champion := false) -> void:
	clear_event("STARTED_ELITE_4")
	for tid in E4_TRAINER_IDS:
		defeated_trainers.erase(tid)
	clear_event("LANCES_ROOM_LOCK_DOOR")
	if include_champion:
		clear_event("BEAT_CHAMPION")     # EVENT_BEAT_CHAMPION_RIVAL sits inside the wider range


## The Safari game ends (ResetEvent EVENT_IN_SAFARI_ZONE) — either the gate script signs you out
## after time-out (`Cutscene.safari_game_over`) or you simply walk out of the park. The counters
## keep their values; the gate resets them on the way back in (SafariZoneGate.asm: 30 BALLs, 502
## steps), and nothing reads them while `in_safari` is false.
func end_safari_game() -> void:
	in_safari = false
	clear_event("IN_SAFARI_ZONE")


## Overworld poison: every 4 steps each poisoned mon loses 1 HP. Returns true if it
## fainted a mon (a message is shown). Whites out (heals) if the party is wiped.
func _overworld_poison() -> bool:
	var poisoned := false
	for m in player_party:
		if int(m["hp"]) > 0 and str(m["status"]) == "psn":
			poisoned = true
	if not poisoned:
		return false
	poison_step += 1
	if poison_step < 4:
		return false
	poison_step = 0
	var fainted: Array = []
	var alive := false
	for m in player_party:
		if int(m["hp"]) > 0 and str(m["status"]) == "psn":
			m["hp"] = int(m["hp"]) - 1
			if int(m["hp"]) <= 0:
				fainted.append(str(m["name"]))
		if int(m["hp"]) > 0:
			alive = true
	if fainted.is_empty():
		return false
	var msg := ""
	for nm in fainted:
		msg += "%s fainted\nfrom poison!\f" % nm
	if not alive:
		msg += "%s is out of\nuseable POKéMON!\f%s whited out!" % [player_name, player_name]
		_say(msg.trim_suffix("\f"))
		whiteout()
		return true
	_say(msg.trim_suffix("\f"))
	return true


## Roll a grass encounter for the current map using its extracted wild table. `force` skips the
## per-step rate gate (the legit-play grind wants a fight every try, not one in ~12 — gh #76).
## One TryDoWildEncounter roll: `kind` picks the TABLE, `rate_kind` (when given) the RATE —
## they differ on a left-shore half-block (see _wild_encounter_kinds). The slot thresholds are
## WildMonEncounterSlotChances' cumulative-1 bytes: slot i is chosen when r <= slots[i].
func _try_wild_encounter(kind := "grass", force := false, rate_kind := "") -> void:
	var wm: Dictionary = wild_data.get("maps", {}).get(center_label, {})
	var rate := int(wm.get((rate_kind if rate_kind != "" else kind) + "_rate", 0))
	var table: Array = wm.get(kind, [])
	if rate <= 0 or table.is_empty():
		return
	if not force and randi() % 256 >= rate:
		return
	var r := randi() % 256
	var slots: Array = wild_data.get("slots", [])
	var slot := table.size() - 1
	for i in slots.size():
		if r <= int(slots[i]):
			slot = i
			break
	slot = clampi(slot, 0, table.size() - 1)
	var entry: Array = table[slot]
	# REPEL's filter runs AFTER the slot roll: a rolled wild mon below the FIRST party slot's
	# level (wPartyMon1Level — fainted or not) is suppressed; equal or higher still appears.
	if not force and repel_steps > 0 and int(entry[0]) < int(player_party[0]["level"]):
		return
	if in_safari:
		start_safari_battle(str(entry[1]), int(entry[0]))
	else:
		start_battle(str(entry[1]), int(entry[0]))


## Begin a wild battle against a freshly built enemy mon.
## Which of the 8 battle wipes to play (BattleTransitions, engine/battle/battle_transitions.asm):
## picked by trainer battle? / enemy at least 3 levels above the first usable party mon? /
## dungeon map? The wild non-dungeon wipes are preceded by the triple screen flash.
func _battle_transition_kind(enemy_level: int, trainer: bool) -> String:
	var lead := 0
	for m in player_party:
		if int(m["hp"]) > 0:
			lead = int(m["level"])
			break
	var stronger := enemy_level >= lead + 3
	if center_label in dungeon_maps:
		if trainer:
			return "split" if stronger else "shrink"
		return "v_stripes" if stronger else "h_stripes"
	if trainer:
		return "spiral_out" if stronger else "spiral_in"
	return "circle" if stronger else "double_circle"


## Run the battle wipe over the frozen overworld before the battle screen appears (as in
## pokered, where BattleTransition consumes the overworld into black before _InitBattleCommon).
## Skipped in tests (fast_hp), keeping start_battle effectively synchronous for them.
func _battle_wipe(enemy_level: int, trainer: bool) -> void:
	if battle.fast_hp:
		return
	battle.visible = false
	battle.state = "anim"              # ignore stale-state input while the wipe plays
	await transition.battle_wipe(_battle_transition_kind(enemy_level, trainer))


func start_battle(species: String, level: int) -> void:
	# Pokémon Tower without the SILPH SCOPE: every encounter presents as the unidentified
	# GHOST (IsGhostBattle) — unfightable and uncatchable-as-itself; you can only run.
	battle.ghost = center_label.begins_with("PokemonTower") \
		and not player_bag.has("SILPH SCOPE") and not battle.unveil
	if audio:
		audio.play_song("wildbattle")
	modal = battle
	await _battle_wipe(level, false)
	battle.start(player_party, species, level)
	transition.clear()


## A Safari Zone encounter (BALL/BAIT/ROCK/RUN, no fighting).
func start_safari_battle(species: String, level: int) -> void:
	if audio:
		audio.play_song("wildbattle")
	modal = battle
	await _battle_wipe(level, false)
	battle.start_safari(player_party, species, level)
	transition.clear()


func start_trainer_battle(opp_class: String, num: int, npc_id := "") -> void:
	if not trainers.has(opp_class):
		return
	var t: Dictionary = trainers[opp_class]
	if num - 1 < 0 or num - 1 >= (t["parties"] as Array).size():
		return
	pending_trainer = npc_id
	if audio:
		# PlayBattleMusic: the 8 gym-leader fights (wGymLeaderNo) and Lance share the
		# gym-leader theme; the Champion (OPP_RIVAL3) gets the final battle; everyone
		# else the trainer theme. Giovanni counts only in his gym (party 3).
		var song := "trainerbattle"
		if opp_class == "OPP_RIVAL3":
			song = "finalbattle"
		elif opp_class == "OPP_LANCE" or cutscene.is_gym_leader_battle(opp_class, num):
			song = "gymleaderbattle"
		audio.play_song(song)
	modal = battle
	var party_data: Array = t["parties"][num - 1]
	await _battle_wipe(int(party_data[0]["level"]), true)
	# The rival battles (OPP_RIVAL1/2/3, incl. the Champion) use the name you gave him, not "RIVAL1".
	var tname: String = rival_name if opp_class in ["OPP_RIVAL1", "OPP_RIVAL2", "OPP_RIVAL3"] else str(t["name"])
	var pic_slug: String = str(trainer_pics.get(opp_class, ""))
	var pic_tex: Texture2D = load("res://assets/trainers/pics/%s.png" % pic_slug) if pic_slug != "" else null
	battle.start_trainer(player_party, party_data, tname, int(t["money"]), pic_tex)
	# Gen-1 trainer AI config for the class (trainer_ai.asm / move_choices.asm).
	battle.ai_mods = t.get("ai_mods", [])
	battle.ai_kind = str(t.get("ai", "Generic"))
	battle.ai_count_max = int(t.get("ai_count", 3))
	battle._ai_uses = battle.ai_count_max
	transition.clear()


func _on_battle_finished() -> void:
	# gh #7: a link battle changes no lasting party state, win or lose — the party is
	# restored from the pre-battle snapshot (the battle mutated the live dicts).
	if battle.link_battle and not _col_snapshot.is_empty():
		player_party = _col_snapshot
		_col_snapshot = []
	if battle.link_battle:
		link.resume_armed = false          # gh #13: the table beat is over — a later drop tears down
	# EndOfBattle sets BIT_WILD_ENCOUNTER_COOLDOWN and the post-battle map reload arms
	# wNumberOfNoRandomBattleStepsLeft = 3: three battle-free steps after EVERY battle.
	wild_cooldown_steps = 3
	_sync_owned()                         # fold any newly caught mon into the Pokédex
	if pending_trainer != null and battle.won:
		defeated_trainers[pending_trainer] = true
	pending_trainer = null
	modal = null
	if battle.blacked_out and not battle.no_blackout:   # first rival battle heals + continues instead
		whiteout()
		return
	# A fresh catch shows its dex registration + entry first, then the nickname offer
	# (engine/battle/core.asm order) — the exit fade and overworld music wait until the ceremony ends.
	# The battle is hidden up front: the dex-entry and naming screens (and the nickname prompt) are
	# full-screen UI drawn on the same CanvasLayer as the battle, which is added last and so would draw
	# OVER them — leaving the player seeing only the battle (gh #146, #163). (#6, gh #37)
	if battle.caught:
		cutscene_active = true
		battle.visible = false
		var csp := str(battle.enemy_mon["species"])
		if battle.newly_caught and dex_entries.has(csp):
			await cutscene.say("New POKéDEX data\nwill be added for\n%s!" % battle.enemy_mon["name"])
			await show_dex_entry(csp, true)
		await cutscene.offer_nickname(battle.enemy_mon)
		cutscene_active = false
		modal = null
	# Level-up evolutions run AFTER the battle, one full sequence per flagged mon
	# (Evolution_PartyMonLoop over wCanEvolveFlags; gh #67). Only mons that leveled this
	# battle are checked — a caught over-leveled mon waits for its next level-up.
	if battle.won:
		for idx in battle.can_evolve:
			if idx >= player_party.size():
				continue
			var m: Dictionary = player_party[idx]
			for ev in mon_base[str(m["species"])]["evolutions"]:
				if str(ev[0]) == "EVOLVE_LEVEL" and int(m["level"]) >= int(ev[1]):
					await run_evolution(m, str(ev[2]))
					break
	if audio:
		audio.play_map_music(center_label)   # back to overworld music
	# Battle exit: cut to white, a 10-frame beat, then fade in over the overworld
	# (.battleOccurred -> MapEntryAfterBattle -> GBFadeInFromWhite). Dark maps skip it
	# (the wMapPalOffset check goes to LoadGBPal instead), as do tests.
	if not battle.fast_hp and not DARK_MAPS.has(center_label):
		transition.battle_exit()
	# SafariZoneCheck (farcalled every OverworldLoop iteration): with EVENT_IN_SAFARI_ZONE set and
	# wNumSafariBalls at 0, the hunt ends the moment you are back on the overworld — throwing your
	# last BALL ends the game whether or not it caught (gh #180).
	if in_safari and safari_balls == 0:
		cutscene.safari_game_over()


## Spin-tile slide (scripts/RocketHideoutB2F.asm etc. + engine/overworld/spinners.asm): the
## arrow tile launches the player along its pre-baked path — sprite whirling, input locked —
## to the matching stop tile; landing on another arrow chains straight into the next slide.
func _do_spin(path: Array) -> void:
	cutscene_active = true
	if audio:
		audio.play_sfx("arrow_tiles")
	player.spinning = true
	for seg in path:
		for i in int(seg[1]):
			await player.step(int(seg[0]))
	player.spinning = false
	player._update_sprite()
	cutscene_active = false
	_on_player_moved(player.cell)      # chain onto the next arrow / run the normal move checks


## `respawn_map` is a Pokémon Center interior (or a town) — the map you last healed in. This maps it to
## the **town** a blackout / ESCAPE ROPE / DIG / TELEPORT warps you out to. pokered stores `wLastBlackoutMap`
## (the outside map, set by the nurse) and `PrepareForSpecialWarp` warps to its `FlyWarpData` tile — so you
## come out *outdoors*, in front of the Center, not inside it. Mt. Moon / Rock Tunnel Centers sit on routes
## (not fly destinations); pokered's behaviour there is a quirk, so they map to the adjacent fly town.
const _RESPAWN_TOWN := {
	"ViridianPokecenter": "ViridianCity", "PewterPokecenter": "PewterCity",
	"CeruleanPokecenter": "CeruleanCity", "VermilionPokecenter": "VermilionCity",
	"LavenderPokecenter": "LavenderTown", "CeladonPokecenter": "CeladonCity",
	"FuchsiaPokecenter": "FuchsiaCity", "SaffronPokecenter": "SaffronCity",
	"CinnabarPokecenter": "CinnabarIsland", "IndigoPlateauLobby": "IndigoPlateau",
	"MtMoonPokecenter": "CeruleanCity", "RockTunnelPokecenter": "LavenderTown"}


## pokered's `BIT_ESCAPE_WARP` destination (`PrepareForSpecialWarp` → `.usedFlyWarp` on `wLastBlackoutMap`):
## warp OUTSIDE, to the town you last healed in, standing on its `FlyWarpData` tile. Shared by blacking out,
## ESCAPE ROPE, DIG and TELEPORT — all set `BIT_ESCAPE_WARP` (gh #101).
func _escape_warp() -> void:
	var town: String = _RESPAWN_TOWN.get(respawn_map, respawn_map)   # a town respawn_map maps to itself
	var dest: Array = FLY_DESTS.get(town, [])
	if dest.is_empty():
		load_world(town)                            # unknown map: fall back to its default spawn
	else:
		load_world(town, -1, dest[0] as Vector2i)   # the town's fly-in tile, in front of the Center


## Blacking out: heal, halve the player's money, and warp outside to the last town healed in.
## pokered's `HandleBlackOut` → `ResetStatusAndHalveMoneyOnBlackout` (BCD-halves `wPlayerMoney`) →
## `HealParty` → `PrepareForSpecialWarp`. The port used to spawn the player at the Center's middle/mat and
## never touched money, so blacking out was free and could strand you in the scenery (gh #97, #101).
func whiteout() -> void:
	heal_party()
	player_money /= 2                               # ResetStatusAndHalveMoneyOnBlackout (integer = BCD trunc)
	_escape_warp()


## Closing the Pokédex returns to the START menu it was opened from (ShowPokedexMenu ->
## RedisplayStartMenu).
func _on_dex_closed() -> void:
	modal = null
	open_start_menu()


## The Pokédex AREA view: mark every map whose wild lists hold the species (TownMapNestIcons).
func show_nest(species: String) -> void:
	# wild_data keys are map labels; the town-map entries carry display names — derive one
	# from the other ("Route1" -> "ROUTE 1"), with the odd spellings special-cased.
	var special := {"MtMoon1F": "MT.MOON", "MtMoonB1F": "MT.MOON", "MtMoonB2F": "MT.MOON",
		"RockTunnel1F": "ROCK TUNNEL", "RockTunnelB1F": "ROCK TUNNEL",
		"SeafoamIslands1F": "SEAFOAM ISLANDS", "PokemonTower3F": "POKéMON TOWER",
		"PokemonTower4F": "POKéMON TOWER", "PokemonTower5F": "POKéMON TOWER",
		"PokemonTower6F": "POKéMON TOWER", "PokemonTower7F": "POKéMON TOWER",
		"PokemonMansion1F": "POKéMON MANSION", "VictoryRoad1F": "VICTORY ROAD",
		"DiglettsCave": "DIGLETT's CAVE", "ViridianForest": "VIRIDIAN FOREST"}
	var names := {}
	var rx := RegEx.new()
	rx.compile("([a-z])([A-Z0-9])")
	for map_label in wild_data.get("maps", {}):
		var w: Dictionary = wild_data["maps"][map_label]
		var found := false
		for kind in ["grass", "water"]:
			for e in w.get(kind, []):                    # entries are [level, species] pairs
				if str(e[1]) == species:
					found = true
		if found:
			var nm: String = special.get(map_label,
				rx.sub(map_label, "$1 $2", true).to_upper())
			names[nm] = true
	var spots: Array = []
	for e in townmap.entries:
		if names.has(str(e["name"])):
			spots.append(e)
	dexlist.visible = false
	modal = townmap
	townmap.open_nest("%s's NEST" % mon_display_name(species), spots)


## Show a species' Pokédex data screen (engine/menus/pokedex.asm); awaits the player closing it.
func show_dex_entry(species: String, owned := true) -> void:
	if not dex_entries.has(species):
		return
	var num: int = dex_order.find(species) + 1
	var tex: Texture2D = load("res://assets/pokemon/front/%s.png" % species)
	modal = dexentry
	dexentry.open(mon_display_name(species), dex_entries[species], tex, num, owned)
	await dexentry.closed


# ---- Pokémon (persistent party mons) ---------------------------------------

## Gen-1 stat (CalcStat with the stat-exp sqrt term) — the ruleset's stat_calc kernel
## now (gh #32, ADR-018).
func stat(base: int, level: int, dv: int, is_hp: bool, sexp := 0) -> int:
	return ruleset.formulas.stat_calc(base, level, dv, is_hp, sexp)


## Random Gen-1 DVs (0..15 per stat; the HP DV is the LSBs of the other four).
func _random_dvs() -> Dictionary:
	var a := randi() % 16
	var d := randi() % 16
	var s := randi() % 16
	var c := randi() % 16
	var hp := ((a & 1) << 3) | ((d & 1) << 2) | ((s & 1) << 1) | (c & 1)
	return {"hp": hp, "atk": a, "def": d, "spd": s, "spc": c}


## The growth curves live in the ruleset's formula layer now (gh #32, ADR-018).
func exp_for_level(n: int, growth: String) -> int:
	return ruleset.formulas.exp_for_level(n, growth)


## Highest level whose EXP threshold the mon has reached (inverse of exp_for_level).
func level_for_exp(xp: int, growth: String) -> int:
	return ruleset.formulas.level_for_exp(xp, growth)


## Day Care: store the chosen party mon (it then earns EXP per overworld step).
func _daycare_deposit(idx: int) -> void:
	if idx < 0 or idx >= player_party.size():
		return
	var mon: Dictionary = player_party[idx]
	daycare_mon = mon
	daycare_start_level = int(mon["level"])
	player_party.remove_at(idx)
	_say("Fine, I'll raise\nyour %s.\fCome back for it\nlater!" % mon["name"])


func recompute_stats(mon: Dictionary) -> void:
	var b: Dictionary = mon["base"]
	var dv: Dictionary = mon.get("dvs", {})
	var se: Dictionary = mon.get("sexp", {})
	var lvl: int = mon["level"]
	mon["maxhp"] = stat(int(b["hp"]), lvl, int(dv.get("hp", 0)), true, int(se.get("hp", 0)))
	mon["atk"] = stat(int(b["atk"]), lvl, int(dv.get("atk", 0)), false, int(se.get("atk", 0)))
	mon["def"] = stat(int(b["def"]), lvl, int(dv.get("def", 0)), false, int(se.get("def", 0)))
	mon["spc"] = stat(int(b["spc"]), lvl, int(dv.get("spc", 0)), false, int(se.get("spc", 0)))
	mon["spd"] = stat(int(b["spd"]), lvl, int(dv.get("spd", 0)), false, int(se.get("spd", 0)))


## Moves a mon of `level` knows: the most recent 4 from base + level-up learnset.
func auto_moves(species: String, level: int) -> Array:
	var b: Dictionary = mon_base[species]
	var ms: Array = (b["learnset"] as Array).duplicate()
	for lm in b["level_moves"]:
		if int(lm[0]) <= level:
			ms.append(lm[1])
	var out: Array = []
	for mv in ms:
		out.erase(mv)
		out.append(mv)
	return out.slice(max(0, out.size() - 4))


## Species display name, pokered-exact: the gender glyphs and punctuation names.
## (Species slugs are the squashed form: nidoranm, mrmime, farfetchd.)
func mon_display_name(species: String) -> String:
	match species:
		"nidoranm": return "NIDORAN♂"
		"nidoranf": return "NIDORAN♀"
		"mrmime": return "MR.MIME"
		"farfetchd": return "FARFETCH'D"
	return species.to_upper()


func make_mon(species: String, level: int, moves_override: Array, dvs := {}) -> Dictionary:
	var b: Dictionary = mon_base[species]
	var mon := {
		"species": species, "name": mon_display_name(species), "level": level,
		"types": b["types"], "base_spd": int(b["spd"]), "base_exp": int(b["base_exp"]),
		"growth": str(b["growth"]), "dvs": dvs if not dvs.is_empty() else _random_dvs(),
		"base": {"hp": b["hp"], "atk": b["atk"], "def": b["def"], "spd": b["spd"], "spc": b["spc"]},
		"exp": exp_for_level(level, str(b["growth"])), "status": "", "sleep": 0, "moves": [],
		"sexp": {"hp": 0, "atk": 0, "def": 0, "spd": 0, "spc": 0},
	}
	var ml: Array = moves_override if moves_override.size() > 0 else auto_moves(species, level)
	for mv in ml:
		var pp := int(mon_moves[mv]["pp"])
		mon["moves"].append({"move": mv, "pp": pp, "maxpp": pp})
	recompute_stats(mon)
	mon["hp"] = mon["maxhp"]
	return mon


func heal_party() -> void:
	for m in player_party:
		m["hp"] = m["maxhp"]
		m["status"] = ""
		for mv in m["moves"]:
			mv["pp"] = mv["maxpp"]


func _do_warp(w: Dictionary) -> void:
	# EnterMap re-arms the post-battle cooldown to 3 whenever BIT_WILD_ENCOUNTER_COOLDOWN is
	# still set (it clears only after the steps are walked) — a warp mid-cooldown restarts it.
	# Seamless connection crossings don't come through here and don't re-arm, as in pokered.
	if wild_cooldown_steps > 0:
		wild_cooldown_steps = 3
	var dest_const := str(w["dest_const"])
	var dest_label: String
	if dest_const == "LAST_MAP":
		dest_label = last_outside_map if last_outside_map != "" else str(map["name"])
	else:
		dest_label = str(w.get("dest_map", ""))
	if dest_label == "" or dest_label == "null":
		return
	# Per-map warp gates (docs/engine/map-scripts.md, gh #53): a script may block the warp or
	# replace it with a cutscene beat.
	if map_script(center_label).on_warp(w, dest_const, dest_label):
		return
	if str(map["tileset"]) in OUTSIDE_TILESETS:
		last_outside_map = str(map["name"])
	# Which warp square the player left through (wWarpedFromWhichMap/Warp): elevators
	# retarget their exit warps to lead back here (StoreWarpEntries).
	warped_from = {"map": center_label, "warp": map["warps"].find(w) + 1}
	# The map-change sound + a 4-step fade to black, then the new map appears in a cut
	# (PlayMapChangeSound + GBFadeOutToBlack). Dark caves skip the fade, as in pokered
	# (wMapPalOffset check); tests skip it too so warp timing stays instant for them.
	if not battle.fast_hp and not DARK_MAPS.has(center_label):
		if audio:
			audio.play_sfx("go_outside" if dest_const == "LAST_MAP" else "go_inside")
		var was_cs := cutscene_active
		cutscene_active = true             # no free movement while the screen fades
		await transition.fade_black()
		cutscene_active = was_cs
	load_world(dest_label, int(w["dest_warp"]) - 1, null, true)   # keep facing through the warp (#18)
	transition.clear()
	# Stepping out through a door: you land on the door tile, then walk one tile clear of it
	# (BIT_STANDING_ON_DOOR -> PlayerStepOutFromDoor simulates one PAD_DOWN). pokered runs this
	# on EVERY tileset in DoorTileIDPointers — houses onto the street, and equally the mart /
	# Silph ELEVATOR doors onto the floor (gh #142); the port used to gate it to outside maps.
	if int(_tile_at(player.cell)) in _DOOR_TILES.get(str(map["tileset"]), []) \
			and player_can_enter(player.cell + Vector2i(0, 1)):
		player.step(player.DOWN)
		warp_armed = true   # step() doesn't fire moved; re-arm so re-entering the door warps (issue #1)


## ShakeElevator (engine/overworld/elevator.asm): the music cuts, the car judders ±1 px for
## 100 iterations (2 frames each) to the collision clack, then the Safari-PA ding rings out
## and the map music returns. Tests (fast_hp) skip the ride.
func shake_elevator() -> void:
	if battle.fast_hp:
		return
	var was_cs := cutscene_active
	cutscene_active = true
	if audio:
		audio.stop()
	var base: float = player.cam.offset.y
	for i in 100:
		player.cam.offset.y = base + (1.0 if i % 2 == 0 else -1.0)
		if audio:
			audio.play_sfx("collision")
		await get_tree().process_frame
		await get_tree().process_frame
	player.cam.offset.y = base
	if audio:
		audio.play_sfx("safari_zone_pa")
		await get_tree().create_timer(1.7).timeout   # the PA ding rings out (pokered polls CHAN5)
		audio.play_map_music(center_label)
	cutscene_active = was_cs


# ---- rendering -------------------------------------------------------------

const TURBO_SCALE := 4.0         # hold the turbo key (Space) to fast-forward everything
var pt_time_scale := 0.0         # > 0: a --playthrough / --<flag>test driver owns Engine.time_scale (gh #98)
# gh #38: the playthrough watchdog. A wedged leg is invisible from outside — nested nav/battle
# budgets multiply into hours of silent CPU (the gh #27 FLY-cursor lesson, seen again after
# 'Surge coverage'). Once per second, sample a PROGRESS signature; if it freezes for the whole
# window, dump the wedge state with a FAIL( the gate validator counts, and quit loudly.
var _pt_watch_window_ms := 0     # 0 = watchdog off (only --playthrough arms it)
var _pt_watch_sig := ""
var _pt_watch_since_ms := 0
var _pt_watch_check_ms := 0
var _pt_stage := ""              # the stage being run, named in the watchdog's dump
var _last_cam_block := Vector2i(-9999, -9999)   # the culled world redraws on block crossings


func _process(delta: float) -> void:
	_flush_pending_on_enter()                         # a load callback a cutscene swallowed (gh #96)
	# A dead link in a Cable Club room walks the player back out — POLLED, not signal-driven:
	# the closed signal usually fires mid-flow (cutscene_active), whose own abort message
	# handles that moment but leaves the player standing in the room; this catches them the
	# moment they're free and returns them to the attendant (the reported stuck-in-room bug).
	if link != null and link.state != "linked" and link.state != "idle" and not link.holding() \
			and center_label in ["TradeCenter", "Colosseum"] \
			and modal == null and not cutscene_active and not _club_leaving:
		_club_room_kicked()
	# gh #13: while the session is held for a reconnect, B anywhere gives up the wait —
	# into today's teardown. Polled here because the lost box may sit over any modal.
	if link != null and link.holding() and Input.is_action_just_pressed("ui_cancel"):
		link.cancel_wait()
	# Clock. When a --playthrough / --<flag>test driver owns it (pt_time_scale > 0, gh #98) it applies
	# everywhere: the bot's nav budgets already scale by Engine.time_scale (_pt_frames, gh #99), battles
	# survive it, and the bot drives input from state rather than human pacing, so the gh #111 race can't
	# bite (that fix noted "no bot impact"). Otherwise the interactive playtest turbo (hold Space)
	# fast-forwards free overworld movement AND battles — the auto-advancing beats (attack animations, HP
	# drain, auto-text) speed up while input-gated battle menus simply wait for you. **Any battle counts,
	# even a TRAINER battle** — those run inside `Cutscene.trainer_battle`, which holds cutscene_active true
	# across `battle.finished`, so gating turbo on `not cutscene_active` wrongly killed it for every trainer/
	# gym fight (gh #140). So: turbo runs in free overworld (modal null, no cutscene) OR in any battle
	# (modal == battle). It stays OFF during a cutscene walk and during every NON-battle modal — notably the
	# catch ceremony's dex-entry / nickname / naming-keyboard screens (modal == dexentry/menu/naming), where
	# accelerating per-frame input stranded the player on the keyboard (gh #111); those aren't the battle
	# modal, so that fix stays intact.
	if pt_time_scale > 0.0:
		Engine.time_scale = pt_time_scale
		if _pt_watch_window_ms > 0:                   # gh #38: the playthrough watchdog
			var wnow := Time.get_ticks_msec()
			if wnow >= _pt_watch_check_ms:
				_pt_watch_check_ms = wnow + 1000
				var sig := _pt_progress_sig()
				if sig != _pt_watch_sig:
					_pt_watch_sig = sig
					_pt_watch_since_ms = wnow
				elif wnow - _pt_watch_since_ms >= _pt_watch_window_ms:
					_pt_watchdog_bark(wnow - _pt_watch_since_ms)
	else:
		var can_turbo: bool = (modal == null and not cutscene_active) or modal == battle
		var turbo: bool = Input.is_action_pressed("p_turbo") and can_turbo
		Engine.time_scale = TURBO_SCALE if turbo else 1.0
	play_seconds += delta / Engine.time_scale         # play time stays wall-clock under turbo
	if grass_overlay:
		grass_overlay.queue_redraw()                  # sprites move every frame; the band follows
	if player and player.placed:                      # rebuild the culled world draw when the
		var cb := Vector2i(int(floorf((player.position.x - 64.0) / BLOCK)),   # camera crosses
			int(floorf((player.position.y - 64.0) / BLOCK)))                  # a block boundary
		if cb != _last_cam_block:
			_last_cam_block = cb
			queue_redraw()
	if _flower_tex == null:                           # cycle the overworld flower (~0.33s/frame)
		return
	_flower_t += delta
	if _flower_t >= 0.33:
		_flower_t -= 0.33
		_flower_frame = (_flower_frame + 1) % _FLOWER_SEQ.size()
		_water_off = (_water_off + 1) % 8              # scroll the water 1px/tick (home/vcopy.asm)
		if placed.size() > 0 and str(placed[0]["ts"].get("slug", "")) in WATER_TILESETS:
			queue_redraw()


func _draw_block(pm: Dictionary, bid: int, bx: int, by: int) -> void:
	var ts: Dictionary = pm["ts"]
	var cols: int = ts["cols"]
	var bdef: Array = ts["blockset"][bid]
	var slug: String = str(ts.get("slug", ""))
	var is_ow: bool = slug == "overworld"
	var is_water_ts: bool = slug in WATER_TILESETS
	for ty in range(4):
		for tx in range(4):
			var tid := int(bdef[ty * 4 + tx])
			var dst := Rect2(bx * BLOCK + tx * TILE, by * BLOCK + ty * TILE, TILE, TILE)
			if tid == 3 and is_ow and _flower_tex != null:   # animated flower (home/vcopy.asm)
				var fcol: int = _FLOWER_SEQ[_flower_frame]
				draw_texture_rect_region(_flower_tex, dst, Rect2(fcol * TILE, 0, TILE, TILE))
			elif tid == 0x14 and is_water_ts and _water_off > 0:   # scrolling water (home/vcopy.asm)
				var sx := float((tid % cols) * TILE)
				var sy := float((tid / cols) * TILE)
				var wo := float(_water_off)
				draw_texture_rect_region(ts["tex"], Rect2(dst.position + Vector2(wo, 0), Vector2(TILE - wo, TILE)), Rect2(sx, sy, TILE - wo, TILE))
				draw_texture_rect_region(ts["tex"], Rect2(dst.position, Vector2(wo, TILE)), Rect2(sx + TILE - wo, sy, wo, TILE))
			else:
				draw_texture_rect_region(ts["tex"], dst, Rect2((tid % cols) * TILE, (tid / cols) * TILE, TILE, TILE))


func _block_owner(bx: int, by: int) -> Variant:
	for pm in placed:
		var cl: Array = pm["clip"]                     # [bx0, bx1, by0, by1] in center-block coords (gh #124)
		if bx >= cl[0] and bx < cl[1] and by >= cl[2] and by < cl[3]:
			return pm
	return null


func _draw() -> void:
	# Cull to the camera window (gh #48): multi-connection maps (Viridian + three routes)
	# retained tens of thousands of tile quads and lagged. Only the visible blocks +1 margin
	# draw now; _process rebuilds the list when the camera crosses a block boundary.
	if placed.is_empty():
		return
	var cam_tl := Vector2.ZERO
	if player and player.placed:
		cam_tl = player.position + Vector2(16, 8) - Vector2(80, 72)
	var bx0 := int(floorf(cam_tl.x / BLOCK)) - 1
	var by0 := int(floorf(cam_tl.y / BLOCK)) - 1
	var center: Dictionary = placed[0]
	for by in range(by0, by0 + 8):
		for bx in range(bx0, bx0 + 9):
			var pm = _block_owner(bx, by)
			if pm != null:
				_draw_block(pm, int(pm["data"]["blocks"][by - pm["oy"]][bx - pm["ox"]]), bx, by)
			else:
				_draw_block(center, center["border"], bx, by)
	# CUT tree animation (gh #123): the cut-tree sprite shakes horizontally and flickers before the tree
	# is gone (engine/overworld/cut2.asm AnimCut). Drawn over the already-swapped (treeless) cell.
	if not _cut_fx.is_empty():
		var cf: Dictionary = _cut_fx
		var base := Vector2(cf["cell"].x * TILE * 2, cf["cell"].y * TILE * 2)   # a cell is 16 px
		var cols: int = cf["cols"]
		var sq: float = cf["dx"]                            # the two halves squeeze toward centre as it's cut
		for t in cf["tiles"]:
			var tid: int = t["tid"]
			var hx: float = sq if t["ox"] == 0 else -sq     # left half drifts right, right half left (AnimCut)
			draw_texture_rect_region(cf["tex"], Rect2(base + Vector2(t["ox"] + hx, t["oy"]), Vector2(TILE, TILE)),
				Rect2((tid % cols) * TILE, (tid / cols) * TILE, TILE, TILE))


# ---- verification helpers --------------------------------------------------

func _selftest() -> void:
	var n_walk := 0
	for b in collision:
		n_walk += b
	print("[selftest] map=%s %dx%d blocks, neighbors=%d" % [map["name"], map_w, map_h, placed.size() - 1])
	print("[selftest] walkable cells: %d / %d, warps: %d" % [n_walk, gw * gh, (map["warps"] as Array).size()])
	print("[selftest] start(5,6) walkable=%s (expect true: path)" % is_walkable(Vector2i(5, 6)))
	print("[selftest] reds-house body(5,3) walkable=%s (expect false: building)" % is_walkable(Vector2i(5, 3)))
	print("[selftest] grass(5,11) walkable=%s (expect true)" % _raw_walk(Vector2i(5, 11)))
	print("[selftest] water(5,15) walkable=%s (expect false)" % _raw_walk(Vector2i(5, 15)))
	assert(n_walk > 0 and n_walk < gw * gh, "collision grid looks degenerate")
	print("[selftest] OK")
	get_tree().quit()


func _screenshot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://shot.png")
	get_tree().quit()


## gh #149: you can't walk ONTO a warp set into a solid tile (a gate door in a wall) from a side that
## doesn't fire the warp. Route 7's gate door (11,9) is solid; approaching it from the west must bump.
## Real movement (arrow keys), not place().
func _gatedoortest() -> void:
	await get_tree().process_frame
	player_name = "RED"
	player_party = [make_mon("blastoise", 40, ["SURF"])]
	story_events = {"GOT_POKEDEX": true}
	load_world("Route7")
	await get_tree().process_frame
	var ok := true
	# Approach the solid door (11,9) from the WEST (from (10,9) stepping right) -> must bump, staying put.
	for from_cell in [Vector2i(10, 9)]:      # (10,9) is walkable street just west of the door
		player.place(from_cell); warp_armed = false; player.facing = 3
		await _press("ui_right")
		var g := 0
		while player.moving and g < 60:
			await get_tree().process_frame; g += 1
		var stayed: bool = player.cell == from_cell and str(center_label) == "Route7"
		ok = ok and stayed
		print("[gatedoor] step onto solid door (11,9) from %s: player @%s map=%s -> %s" % [
			str(from_cell), str(player.cell), center_label, "BLOCKED (ok)" if stayed else "WALKED ONTO IT (BUG)"])
	# The gate must still be enterable via its walkable mats (11,10)/(18,10) — my fix only touches SOLID
	# warps, so this should be unchanged. Walk east onto (11,10) and confirm we reach Route7Gate.
	load_world("Route7"); await get_tree().process_frame
	var entered := ""
	for approach in [[Vector2i(10, 10), 3], [Vector2i(19, 10), 2]]:   # onto (11,10) from W, onto (18,10) from E
		load_world("Route7"); await get_tree().process_frame
		player.place(approach[0]); warp_armed = true; player.facing = approach[1]   # armed, as if walked up
		await _press(["ui_down", "ui_up", "ui_left", "ui_right"][approach[1]])
		var g := 0
		while str(center_label) == "Route7" and g < 60:
			await get_tree().process_frame; g += 1
		if str(center_label) == "Route7Gate":
			entered = "from %s" % str(approach[0]); break
	ok = ok and entered != ""
	print("[gatedoor] gate still enterable via a walkable mat: %s (%s)" % [entered != "", entered if entered != "" else "NONE reached Route7Gate"])
	print("[gatedoor] %s" % ("PASS" if ok else "FAIL(BUG)"))
	get_tree().quit()


## Debug: drop straight into interactive play on a chosen map (skips the title), so a specific spot can
## be checked by hand. Usage: `pwsh tools/run.ps1 -- --playmap Route7`. Defaults to Route 7, placed just
## below the gate/bollards. Free movement with the arrow keys; does not quit.
func _playmap() -> void:
	var mapname := _pt_arg_value("--playmap")
	if mapname == "":
		mapname = "Route7"
	player_name = "RED"
	player_party = [make_mon("blastoise", 40, ["SURF", "STRENGTH", "CUT"])]
	player_bag = {"POKé BALL": 5}
	story_events = {"GOT_POKEDEX": true}
	load_world(mapname)
	await get_tree().process_frame
	if mapname == "Route7":
		player.place(Vector2i(10, 13))    # walkable street just below the gate + bollard fence
		warp_armed = false
	print("[playmap] interactive on %s @%s — walk with the arrow keys" % [mapname, str(player.cell)])


## GUI-only: pose the S.S. Anne departure (gh #22) — anne1.png mid-sail (band + smoke puffs),
## anne2.png after the erase to open water. Runs the real-time scene (audio on, muted).
func _anneshot() -> void:
	await get_tree().process_frame
	audio.enabled = true                       # the scene's fast path keys off audio.enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	set_event("GOT_HM01")
	player_name = "RED"
	last_outside_map = "VermilionCity"
	load_world("VermilionDock", 1)             # the gangway arrival triggers the scene
	await get_tree().create_timer(7.0).timeout # 2 s beat + ~4.7 s of sailing
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://anne1.png")
	print("[anneshot] mid-sail posed")
	while center_label == "VermilionDock" and int(map["blocks"][2][5]) != 0x0D:
		await get_tree().process_frame         # the rest of the crawl (~13 s), then the erase
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://anne2.png")
	print("[anneshot] erased-to-water posed")
	get_tree().quit()


## GUI-only: render the slot machine at the bet prompt + a resolved jackpot (run via run.ps1).
func _slotshot() -> void:
	await get_tree().process_frame
	load_world("GameCorner")
	player_bag["COIN CASE"] = 1
	player_coins = 200
	modal = slots
	slots.start(false)
	slots._to_bet()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://slot_bet.png")
	slots.pos = [4, 17, 17]            # a 7-7-7 middle line
	slots.bet = 3
	slots.win_sym = "SEVEN"
	slots.payout = 300
	slots.phase = "result"
	slots.msg = "7 lined up!\nScored 300 coins!"
	slots.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://slot_win.png")
	get_tree().quit()


func _warptest() -> void:
	await get_tree().process_frame
	player.place(Vector2i(5, 6))
	warp_armed = true
	print("[warptest] on %s, walking into door..." % map["name"])
	Input.action_press("ui_up")
	await get_tree().create_timer(0.6).timeout   # turn (0.08) + step (0.268) + warp, with slack
	Input.action_release("ui_up")
	print("[warptest] entered -> %s (expect RedsHouse1F)" % map["name"])
	await get_tree().create_timer(0.1).timeout
	player.place(Vector2i(2, 6))
	warp_armed = true
	Input.action_press("ui_down")
	await get_tree().create_timer(0.6).timeout
	Input.action_release("ui_down")
	print("[warptest] exited  -> %s (expect PalletTown)" % map["name"])
	# gh #130: SS_ANNE_BOW's fn2 warp-in-front is IsSSAnneBowWarpTileInFrontOfPlayer ($15-only), not the
	# generic ship WarpTileListPointers. Its two exit warps (13,6)/(13,7) must fire ONLY facing RIGHT (=3,
	# toward the $15 stairs) — the generic list would over-fire them facing DOWN.
	load_world("SSAnneBow")
	await get_tree().process_frame
	var bow_ok := true
	for wc in [Vector2i(13, 6), Vector2i(13, 7)]:
		for f in range(4):
			var got: bool = _warp_should_fire(wc, f)
			var want: bool = (f == 3)   # RIGHT
			if got != want:
				bow_ok = false
				print("[warptest] FAIL bow %s facing %d: got=%s want=%s" % [wc, f, got, want])
	print("[warptest] SS_ANNE_BOW fn2 $15-only (gh #130): %s" % ("PASS" if bow_ok else "FAIL"))
	get_tree().quit()


func _conntest() -> void:
	await get_tree().process_frame
	# Find a walkable column at the top edge of Pallet Town (the north exit).
	var col := -1
	for x in range(gw):
		if _raw_walk(Vector2i(x, 0)) and _raw_walk(Vector2i(x, 1)):
			col = x
			break
	print("[conntest] north-exit column=%d, neighbors=%d" % [col, placed.size() - 1])
	player.place(Vector2i(col, 1))
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://conn_before.png")
	print("[conntest] before: center=%s player=%s" % [center_label, player.cell])
	Input.action_press("ui_up")
	await get_tree().create_timer(1.4).timeout
	Input.action_release("ui_up")
	print("[conntest] after:  center=%s player=%s (expect Route1)" % [center_label, player.cell])
	get_viewport().get_texture().get_image().save_png("res://conn_after.png")
	get_tree().quit()


func _ledgetest() -> void:
	load_world("Route1")
	await get_tree().process_frame
	var spot := Vector2i(-1, -1)
	for y in range(gh - 1):
		for x in range(gw):
			var c := Vector2i(x, y)
			if _raw_walk(c) and ledge_match(c, "down", Vector2i(0, 1)):
				spot = c
				break
		if spot.x >= 0:
			break
	print("[ledgetest] down-ledge spot=%s" % spot)
	player.place(spot)
	await get_tree().process_frame
	var before: Vector2i = player.cell
	Input.action_press("ui_down")
	await get_tree().create_timer(0.15).timeout    # mid-hop: capture arc + shadow
	Input.action_release("ui_down")
	get_viewport().get_texture().get_image().save_png("res://ledgetest.png")
	print("[ledgetest] mid-hop jumping=%s before=%s target=%s" % [player.jumping, before, player.cell])
	await get_tree().create_timer(0.3).timeout
	print("[ledgetest] landed=%s (expect y +2 from before)" % player.cell)
	get_tree().quit()


func _grasstest() -> void:
	load_world("Route1")
	await get_tree().process_frame
	var spot := Vector2i(-1, -1)
	for y in range(gh):
		for x in range(gw):
			var c := Vector2i(x, y)
			if _raw_walk(c) and is_grass_cell(c):
				spot = c
				break
		if spot.x >= 0:
			break
	print("[grasstest] grass spot=%s grass_tile=0x%x" % [spot, center_grass])
	player.place(spot)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("[grasstest] is_grass=%s (legs behind the grass tile's dark pixels)" % is_grass_cell(player.cell))
	get_viewport().get_texture().get_image().save_png("res://grasstest.png")
	# Walking INTO grass from a clear tile: the standing tile is the departure tile until the
	# step lands (movement.asm), so the sprite stays fully drawn mid-step.
	var done_mid := false
	for y in range(gh):
		for x in range(gw):
			if done_mid:
				break
			var g := Vector2i(x, y)
			if not (_raw_walk(g) and is_grass_cell(g)):
				continue
			for d in [player.UP, player.DOWN, player.LEFT, player.RIGHT]:
				var dv: Vector2i = DIRV4[int(d)]
				var from: Vector2i = g - dv
				if not _raw_walk(from) or is_grass_cell(from):
					continue
				player.place(from)
				player.step(d)                        # fire-and-forget; sample mid-step
				await get_tree().create_timer(0.13).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://grass_midstep.png")
				print("[grasstest] mid-step into grass at %s: standing-on-grass=%s (expect false)"
					% [g, is_grass_cell(player.cell - dv)])
				done_mid = true
				break
		if done_mid:
			break
	if not done_mid:
		print("[grasstest] no clear->grass edge found for the mid-step check")
	get_tree().quit()


func _npctest() -> void:
	await get_tree().process_frame
	print("[npctest] map=%s npcs=%d" % [center_label, npcs.size()])
	# Probe the first VISIBLE npc (Pallet's Oak is rightly hidden until the intercept, which
	# is what silently broke the old Oak-based probes — gh #21).
	var subject = null
	for n in npcs:
		print("  npc file=%s cell=%s wander=%s shown=%s text=%s" % [n.file, n.cell, n.wander, n.shown, n.text_id])
		if subject == null and n.shown:
			subject = n
	if subject != null:
		player.place(subject.cell + Vector2i(0, 1))   # just below; same frame, so it can't move
		player.facing = 1                             # face UP toward the npc
		print("[npctest] can_enter(npc cell)=%s (expect false: NPC solid)" % player_can_enter(subject.cell))
		print("[npctest] interact returned=%s (expect true)" % interact(player))
		modal = null
		textbox.visible = false                       # close the dialogue so the wander check runs
	# Wander check: track a WALK npc over a few seconds.
	var walker = null
	for n in npcs:
		if n.wander:
			walker = n
			break
	if walker != null:
		var start: Vector2i = walker.cell
		await get_tree().create_timer(3.5).timeout
		print("[npctest] wander %s: %s -> %s (expect changed)" % [walker.file, start, walker.cell])
	get_viewport().get_texture().get_image().save_png("res://npctest.png")
	get_tree().quit()


func _texttest() -> void:
	await get_tree().process_frame
	# 1) Oak (single page) — screenshot the box fully typed.
	var oak = null
	var girl = null
	for n in npcs:
		if n.file == "oak":
			oak = n
		elif n.file == "girl":
			girl = n
	player.place(oak.cell + Vector2i(0, 1))
	player.facing = 1
	interact(player)
	await get_tree().create_timer(0.9).timeout
	get_viewport().get_texture().get_image().save_png("res://texttest.png")
	print("[texttest] oak: active=%s revealed=%d/%d" % [(modal != null), int(textbox.revealed), textbox._page_glyphs()])
	textbox.advance()    # close Oak
	print("[texttest] after close active=%s (expect false)" % (modal != null))

	# 2) Girl (multi-page) — exercise pagination + close via advance().
	if girl != null:
		girl.wander = false
		player.place(girl.cell + Vector2i(0, 1))
		player.facing = 1
		interact(player)
		var npages: int = textbox.pages.size()
		textbox.advance()                       # finish typing page 1
		var ok1: bool = textbox.advance()       # -> page 2
		var p2: int = textbox.page_idx
		textbox.advance()                       # finish typing page 2
		textbox.advance()                       # -> close
		print("[texttest] girl: pages=%d page_after_adv=%d advance_ok=%s closed_active=%s" % [npages, p2, ok1, (modal != null)])
	get_tree().quit()


func _press_accept() -> void:
	await _press("ui_accept")


func _press(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


func _menutest() -> void:
	await get_tree().process_frame
	await _press("p_start")            # open the start menu (START button)
	print("[menutest] opened: modal_is_menu=%s items=%d" % [modal == menu, menu.items.size()])
	get_viewport().get_texture().get_image().save_png("res://menu1.png")
	await _press("ui_down")
	await _press("ui_down")            # cursor -> the player-name entry (index 2, no dex yet)
	print("[menutest] cursor=%d (expect 2)" % menu.cursor)
	await _press("ui_accept")          # select the name -> the trainer card
	print("[menutest] after select: modal_is_card=%s" % (modal == trainercard))
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://menu2.png")
	await get_tree().process_frame     # re-align to the process phase after frame_post_draw
	await _press("ui_accept")          # close the card -> the START menu redisplays (gh #59)
	print("[menutest] after close: back_to_start=%s" % (modal == menu and menu_mode == "start"))
	await _press("ui_cancel")          # B: leave the START menu itself
	print("[menutest] after B: modal_null=%s" % (modal == null))
	# SAVE -> yes/no -> "saved" chain (drive directly; look SAVE up — the list shifts with the dex)
	open_start_menu()
	_on_menu_chosen(menu.items.find("SAVE"))
	print("[menutest] SAVE: mode=%s items=%s modal_is_menu=%s" % [menu_mode, menu.items, modal == menu])
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://menu3.png")
	_on_menu_chosen(0)                 # YES -> "saved" text
	print("[menutest] YES: modal_is_text=%s save_exists=%s" % [modal == textbox, FileAccess.file_exists(SAVE_PATH)])
	DirAccess.open("user://").remove(SAVE_PATH.get_file())   # clean the test save
	get_tree().quit()


func _battletest() -> void:
	await get_tree().process_frame
	var pmon: Dictionary = player_party[0]
	# Put the lead one win away from leveling up, to exercise EXP + level-up.
	pmon["exp"] = exp_for_level(int(pmon["level"]) + 1, str(pmon["growth"])) - 10
	var s_lvl: int = pmon["level"]
	var s_max: int = pmon["maxhp"]
	start_battle("rattata", 3)
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept")
		g += 1
	var names := []
	for mv in battle.player_mon["moves"]:
		names.append(mv["move"])
	print("[battletest] party=%d  lead=%s L%d  moves=%s  state=%s" % [
		player_party.size(), battle.player_mon["name"], battle.player_mon["level"], names, battle.state])
	get_viewport().get_texture().get_image().save_png("res://battle1.png")
	# Open the PKMN party menu, screenshot, cancel back.
	await _press("ui_right")           # FIGHT -> PKMN (2x2 grid: right flips the column)
	await _press("ui_accept")
	print("[battletest] party menu: state=%s size=%d" % [battle.state, party_hp_list().size()])
	get_viewport().get_texture().get_image().save_png("res://battle_party.png")
	await _press("ui_cancel")
	await _press("ui_accept")          # FIGHT -> move menu
	get_viewport().get_texture().get_image().save_png("res://battle_moves.png")
	# Fight to a win (cursor stays on first move).
	g = 0
	while modal == battle and g < 200:
		await _press("ui_accept")
		g += 1
	print("[battletest] over: modal_null=%s  exp_gain=%s  level %d->%d  maxhp %d->%d" % [
		modal == null, int(pmon["exp"]) >= exp_for_level(int(pmon["level"]), str(pmon["growth"])),
		s_lvl, pmon["level"], s_max, pmon["maxhp"]])
	get_tree().quit()


func _catchtest() -> void:
	await get_tree().process_frame
	var psize: int = player_party.size()
	start_battle("rattata", 3)
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	battle.enemy_mon["hp"] = 1          # weaken so the catch is (near) guaranteed
	await _press("ui_down")             # FIGHT -> ITEM (2x2 grid: down flips the row)
	await _press("ui_accept")           # open ITEM menu
	print("[catchtest] item menu: state=%s items=%s" % [battle.state, battle.bag_keys])
	get_viewport().get_texture().get_image().save_png("res://catch1.png")
	await _press("ui_accept")           # use POKé BALL
	g = 0
	while modal == battle and g < 30:
		await _press("ui_accept"); g += 1
	print("[catchtest] party %d->%d (expect +1)  modal_null=%s  balls=%d" % [
		psize, player_party.size(), modal == null, int(player_bag.get("POKé BALL", 0))])
	get_tree().quit()


## gh #111 regression: catch a NEW species (Pokédex registration path) with the reporter's setup — BATTLE
## ANIMATION off and the speed-up (turbo) held — and drive the ceremony with *human-paced* presses. Under
## turbo the accelerated ceremony used to race the input timing and soft-lock (the nickname prompt got
## answered before you could, stranding you on the naming keyboard). With turbo suppressed during
## modals/cutscenes (the fix) it completes: party grows, control returns to the overworld.
func _newcatchtest() -> void:
	await get_tree().process_frame
	options["battle_anim"] = false          # gh #111: the reporter had BATTLE ANIMATION off...
	if not InputMap.has_action("p_turbo"):  # ...and the speed-up (turbo) held. p_turbo is only in the map
		InputMap.add_action("p_turbo")      # after Keybinds.apply(); register it so _process sees it held.
	Input.action_press("p_turbo")           # _process -> Engine.time_scale = TURBO_SCALE (4)
	if audio:
		audio.enabled = true                # windowed reality: audio ON flips the cutscene `fast` path
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	pokedex_owned = {}                      # nothing owned -> the catch is a new species (dex registers)
	pokedex_seen = {}
	player_party = [make_mon("charmander", 12, [])]
	player_bag = {"POKé BALL": 10}
	var psize := player_party.size()
	# Trigger a REAL wild encounter on Route 5 grass (the reported scenario), not a bare start_battle.
	load_world("Route5")
	repel_steps = 0
	_try_wild_encounter("grass", true)      # force a Route 5 encounter (oddish/pidgey/mankey)
	await get_tree().process_frame
	if modal != battle:
		print("[newcatch] HANG: no encounter forced"); get_tree().quit(); return
	# Wait for the battle to be ready before touching enemy_mon: start_battle awaits _battle_wipe (async
	# unless fast_hp) before battle.start populates enemy_mon, and this test keeps the real wipe/anims (no
	# fast_hp) to exercise the gh #111 turbo path — so reading enemy_mon after a single frame KeyError'd.
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	print("[newcatch] encounter: %s (new=%s)" % [str(battle.enemy_mon["species"]), not pokedex_owned.has(str(battle.enemy_mon["species"]))])
	battle.enemy_mon["hp"] = 1               # weaken so the throw catches
	await _press("ui_down")                  # FIGHT -> ITEM
	await _press("ui_accept")                # open ITEM menu
	await _press("ui_accept")                # throw the POKé BALL
	# Mash A through the whole ceremony (Gotcha -> dex registration -> dex entry -> nickname -> naming
	# keyboard -> overworld), answering YES to the nickname so the naming screen is exercised too (the
	# beat my first fix warned could strand you); log each distinct modal/state so a hang shows where.
	var last := ""
	var battle_over_dex := false            # gh #146/#163: the battle must NOT draw over the dex/naming screens
	g = 0
	while g < 400:
		g += 1
		if (modal == dexentry or modal == naming) and battle.visible:
			battle_over_dex = true
		var mname := "battle" if modal == battle else "textbox" if modal == textbox \
			else "dexentry" if modal == dexentry else "menu" if modal == menu \
			else "naming" if modal == naming else "null"
		var here := "modal=%s state=%s cutscene=%s" % [mname, (battle.state if modal == battle else "-"), cutscene_active]
		if here != last:
			print("[newcatch] step %d: %s" % [g, here])
			last = here
		if modal == null and not cutscene_active:
			break
		if modal == menu:                    # nickname YES/NO — answer YES (open the keyboard: the fuller path)
			menu.chosen.emit(0)
			await get_tree().process_frame
		elif modal == naming:                # drive the naming keyboard to a confirmed nickname
			naming.done.emit("NICK")
			await get_tree().process_frame
		else:
			for _f in 15:                    # human pace: let the game run free between presses, so the
				await get_tree().process_frame   # turbo-accelerated ceremony has time to race the input
			await _press("ui_accept")
	var done: bool = modal == null and not cutscene_active and player_party.size() > psize
	print("[newcatch] %s: party %d->%d modal_null=%s cutscene=%s dex/naming_visible(gh#163)=%s" % [
		"PASS" if done else "HANG", psize, player_party.size(), modal == null, cutscene_active, not battle_over_dex])
	get_tree().quit()


## Reproduce gh #112: a mon KO'd this turn must NOT still execute its move. Two directions, since the
## KO guard runs for whichever mon acts second.
##   A) fast player one-shots a 1-HP enemy -> the fainted enemy must not attack back.
##   B) fast enemy one-shots the 1-HP player -> the fainted player's chosen move must not land.
func _faintordertest() -> void:
	await get_tree().process_frame
	var ok := true

	# --- A: player faster, KOs enemy ---
	player_party = [make_mon("jolteon", 25, ["TACKLE"])]   # fast, acts first
	var pmax := int(player_party[0]["maxhp"])
	player_party[0]["hp"] = pmax
	start_battle("slowpoke", 25)                            # slow, acts second
	battle.enemy_mon["hp"] = 1                              # any hit KOs it -> it should not get to act
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	await _press("ui_accept")                              # FIGHT -> moves
	await _press("ui_accept")                              # TACKLE (KOs the enemy)
	g = 0
	while modal == battle and battle.state != "menu" and g < 200:
		await _press("ui_accept"); g += 1
	var a_ok: bool = int(battle.enemy_mon["hp"]) <= 0 and int(player_party[0]["hp"]) == pmax
	ok = ok and a_ok
	print("[faintorder] A(player KOs enemy) %s: enemy_fainted=%s player_hp=%d/%d" % [
		"PASS" if a_ok else "FAIL(BUG)", int(battle.enemy_mon["hp"]) <= 0, int(player_party[0]["hp"]), pmax])

	# --- B: enemy faster, KOs player; the KO'd player's TACKLE must not land ---
	player_party = [make_mon("slowpoke", 25, ["TACKLE"]), make_mon("pidgey", 10, ["TACKLE"])]  # slow + backup (no blackout)
	player_party[0]["hp"] = 1                               # enemy one-shots it
	start_battle("jolteon", 25)                            # fast enemy acts first
	battle.enemy_mon["moves"] = [{"move": "TACKLE", "pp": 30, "maxpp": 30}]  # force a damaging move
	var emax := int(battle.enemy_mon["maxhp"])
	battle.enemy_mon["hp"] = emax
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	await _press("ui_accept")                              # FIGHT -> moves
	await _press("ui_accept")                              # player's TACKLE (should be blocked: player KO'd first)
	var enemy_min := emax                                  # lowest enemy HP seen -> < emax means the fainted player still hit
	g = 0
	while modal == battle and g < 300:
		enemy_min = mini(enemy_min, int(battle.enemy_mon["hp"]))
		if battle.state == "menu":
			break
		await _press("ui_accept"); g += 1
	var b_ok: bool = int(player_party[0]["hp"]) <= 0 and enemy_min == emax
	ok = ok and b_ok
	print("[faintorder] B(enemy KOs player) %s: player_fainted=%s enemy_hp_min=%d/%d (BUG if the fainted player still hit us)" % [
		"PASS" if b_ok else "FAIL(BUG)", int(player_party[0]["hp"]) <= 0, enemy_min, emax])

	print("[faintorder] %s" % ("PASS" if ok else "FAIL(BUG)"))
	get_tree().quit()


## gh #112 (double KO): a recoil move that KOs the enemy AND recoils the player to 0 the same turn, in a
## trainer battle with backups on both sides, must faint BOTH mons — the player is forced to switch, not
## left able to act with a 0-HP mon. Before the fix _end_of_turn fainted only the enemy and returned to
## the move menu with a fainted lead (the reported bug).
func _dblkotest() -> void:
	await get_tree().process_frame
	player_name = "RED"
	player_party = [make_mon("jolteon", 30, ["TAKE_DOWN"]), make_mon("pidgey", 20, ["TACKLE"])]
	player_party[0]["hp"] = 5                       # low enough that TAKE DOWN's recoil KOs the user
	modal = battle
	await _battle_wipe(3, false)
	battle.start_trainer(player_party, [{"species": "rattata", "level": 3},
		{"species": "rattata", "level": 3}], "YOUNGSTER", 10)
	transition.clear()
	var g := 0
	while battle.state != "menu" and modal == battle and g < 800:  # skip the trainer intro
		await _press("ui_accept"); g += 1
	# TAKE DOWN KOs the rattata and its recoil KOs JOLTEON — but it can MISS (85%), which
	# burns the turn without recoil. Re-arm the setup and retry until the hit lands, so the
	# test asserts the double-KO handling, not one lucky accuracy roll (gh #2 RNG hygiene).
	var tries := 0
	while modal == battle and battle.state == "menu" and int(player_party[0]["hp"]) > 0 and tries < 10:
		tries += 1
		player_party[0]["hp"] = 5
		battle.enemy_mon["hp"] = int(battle.enemy_mon["maxhp"])
		await _press("ui_accept")                   # FIGHT -> moves
		await _press("ui_accept")                   # TAKE DOWN
		g = 0
		while modal == battle and battle.state != "menu" and battle.state != "party_forced" and g < 400:
			await _press("ui_accept"); g += 1
	var player_fainted: bool = int(player_party[0]["hp"]) <= 0
	var enemy_sent_next: bool = battle.enemy_active == 1        # trainer sent its second mon
	var forced_switch: bool = battle.state == "party_forced"   # player must replace the fainted lead (not "menu")
	var ok: bool = player_fainted and enemy_sent_next and forced_switch
	print("[dblko] %s: player0_hp=%d enemy_active=%d state=%s (expect fainted, enemy_active=1, party_forced; BUG if state=menu)" % [
		"PASS" if ok else "FAIL(BUG)", int(player_party[0]["hp"]), battle.enemy_active, battle.state])
	get_tree().quit()


## gh #168: a two-turn charge move (FLY) spends PP on the EXECUTION turn, not the charge turn.
## P1 a normal FLY: PP is unchanged all through the charge, then drops by 1 when it fires.
## P2 a FLY frozen mid-charge (a deterministic turn-2 disruption): PP is kept (pokered DecrementPP runs
## only after the status check passes — a disrupted charge wastes no PP).
func _chargepptest() -> void:
	await get_tree().process_frame
	var ok := true

	# --- P1: normal FLY spends its PP on turn 2 (the fire), not turn 1 (the charge) ---
	player_party = [make_mon("pidgeotto", 40, ["FLY", "TACKLE"])]
	start_battle("snorlax", 40)
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	battle.player_mon["hp"] = 999; battle.player_mon["maxhp"] = 999   # neither side KOs, so the turn plays out
	battle.enemy_mon["hp"] = 999; battle.enemy_mon["maxhp"] = 999
	var maxpp := int(battle.player_mon["moves"][0]["pp"])             # FLY at full PP
	await _press("ui_accept")                        # FIGHT -> moves
	await _press("ui_accept")                        # FLY (idx 0): turn 1 charges
	var pp_charge := -1
	var pp_fired := -1
	var was_charging := false
	g = 0
	while modal == battle and g < 400:
		var ch := str(battle.p_vol["charging"])
		var pp := int(battle.player_mon["moves"][0]["pp"])
		if ch == "FLY":
			was_charging = true
			pp_charge = pp
		elif was_charging:                           # charge cleared -> FLY has fired this turn
			pp_fired = pp
			break
		await _press("ui_accept"); g += 1
	var p1: bool = was_charging and pp_charge == maxpp and pp_fired == maxpp - 1
	ok = ok and p1
	print("[chargepp] P1(normal FLY) %s: maxpp=%d during_charge=%d after_fire=%d (expect %d then %d)" % [
		"PASS" if p1 else "FAIL", maxpp, pp_charge, pp_fired, maxpp, maxpp - 1])

	# --- P2: FLY disrupted mid-charge (frozen on the fire turn) keeps its PP ---
	player_party = [make_mon("pidgeotto", 40, ["FLY", "TACKLE"])]
	start_battle("snorlax", 40)
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	battle.player_mon["hp"] = 999; battle.player_mon["maxhp"] = 999
	battle.enemy_mon["hp"] = 999; battle.enemy_mon["maxhp"] = 999
	var maxpp2 := int(battle.player_mon["moves"][0]["pp"])
	await _press("ui_accept")                        # FIGHT -> moves
	await _press("ui_accept")                        # FLY: turn 1 charges
	var froze := false
	g = 0
	while modal == battle and g < 200:
		if str(battle.p_vol["charging"]) == "FLY" and not froze:
			battle.player_mon["status"] = "frz"      # deterministic turn-2 disruption
			froze = true
		await _press("ui_accept"); g += 1
		if froze and g > 90:                         # the frozen mon is stuck re-charging; sample and stop
			break
	var pp_frozen := int(battle.player_mon["moves"][0]["pp"])
	var p2: bool = froze and pp_frozen == maxpp2
	ok = ok and p2
	print("[chargepp] P2(frozen FLY) %s: pp=%d/%d (expect kept at %d; BUG if %d)" % [
		"PASS" if p2 else "FAIL", pp_frozen, maxpp2, maxpp2, maxpp2 - 1])

	print("[chargepp] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()


func _statmovetest() -> void:
	await get_tree().process_frame
	start_battle("rattata", 3)
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	await _press("ui_accept")           # FIGHT -> moves
	await _press("ui_down")             # cursor SCRATCH(0) -> GROWL(1)
	var before: int = battle.e_stages["atk"]
	await _press("ui_accept")           # use GROWL (lowers enemy ATTACK)
	g = 0
	while battle.state == "msg" and modal == battle and g < 25:
		await _press("ui_accept"); g += 1
	print("[statmovetest] move=%s  enemy ATK stage %d->%d (expect -1)" % [
		battle.player_mon["moves"][1]["move"], before, battle.e_stages["atk"]])
	get_tree().quit()


func _wraptest() -> void:
	await get_tree().process_frame
	start_battle("rattata", 3)
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	print("[wraptest] wrap('Enemy RATTATA used SUPER FANG!') = %s" % str(battle._wrap("Enemy RATTATA used SUPER FANG!")))
	battle._say(["Enemy RATTATA used\nSUPER FANG!", "RATTATA was caught by RED!"], "menu")
	await get_tree().create_timer(0.9).timeout
	get_viewport().get_texture().get_image().save_png("res://wrap1.png")
	get_tree().quit()


## gh #4 (ADR-014): the mon record codec, tested single-process on fixture messages — a
## fixture dict IS a valid peer message by construction of the versioned schema, so no
## second instance is needed. Round-trips varied mons (nicknamed, statused, outsider OT,
## every move-slot shape), refuses an unknown schema version, and rejects malformed and
## gh #22 (ADR-017): the v2 Core schema suite — the valid fixture project validates clean
## (ids registered per prefix) and every broken fixture is rejected with exactly one error
## naming the file + path. Run: `pwsh tools/run.ps1 -- --schematest`. Headless.
func _schematest() -> void:
	await get_tree().process_frame
	var ok := true
	var r: Dictionary = ProjectValidator.validate_project("res://core/fixtures/valid")
	ok = _schema_check("valid: no errors", (r["errors"] as Array).is_empty() and bool(r["ok"]),
		"; ".join(PackedStringArray(r["errors"]))) and ok
	var ids: Dictionary = r["ids"]
	ok = _schema_check("valid: ids registered (2 species, 1 move, 2 items, 1 trainer, 1 map, 2 types, 1 event)",
		int(ids.get("species", 0)) == 2 and int(ids.get("move", 0)) == 1
		and int(ids.get("item", 0)) == 2 and int(ids.get("trainer", 0)) == 1
		and int(ids.get("map", 0)) == 1 and int(ids.get("type", 0)) == 2
		and int(ids.get("event", 0)) == 1,
		str(ids)) and ok
	var cases := [
		["broken_unknown_field", "unknown field 'prise'"],
		["broken_wrong_type", "expected integer"],
		["broken_missing_required", "missing required field 'stats'"],
		["broken_dangling_ref", "dangling reference 'type:fire'"],
		["broken_unclaimed", "unclaimed file"],
		["broken_newer_format", "supports format 1"],
		["broken_id_mismatch", "does not match its filename"],
		["broken_bad_command", "matches no anyOf branch"],
	]
	for c in cases:
		var b: Dictionary = ProjectValidator.validate_project("res://core/fixtures/" + str(c[0]))
		var errs: Array = b["errors"]
		var hit := errs.size() == 1 and str(errs[0]).contains(str(c[1]))
		ok = _schema_check("%s: exactly one error naming it" % c[0], hit,
			"; ".join(PackedStringArray(errs))) and ok
	print("[schema] %s" % ("ALL GREEN" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _schema_check(name: String, good: bool, detail: String) -> bool:
	print("[schema] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


## gh #31 (ADR-018): the ruleset seam's registry + the Types tracer bullet. The boot
## ruleset must be the manifest's (gen1), an unknown name must refuse (null), and the
## seam's type resolver must answer exactly as the raw project chart over the full type
## cross-product — a PLUMBING proof (the chart reached Gen1Types, delegation works);
## the algorithm itself is held by --battledettest's md5s.
## Run: `pwsh tools/run.ps1 -- --rulesettest`. Headless.
func _rulesettest() -> void:
	await get_tree().process_frame
	var ok := true
	ok = _rs_check("boot resolved the manifest ruleset",
		ruleset != null and ruleset.id() == str(ProjectData.manifest.get("ruleset", "")),
		"got '%s'" % (ruleset.id() if ruleset != null else "<null>")) and ok
	ok = _rs_check("gen1 carries a Types module", ruleset != null and ruleset.types != null,
		"") and ok
	ok = _rs_check("unknown ruleset refuses (null)",
		RulesetRegistry.resolve("gen9") == null, "") and ok
	ok = _rs_check("battle resolves types through the seam", battle.rset == ruleset, "") and ok
	# ground truth through the seam (mono-type stored doubled; single-fire per entry)
	ok = _rs_check("WATER vs FIRE,FIRE is 2x (not squared)",
		battle._type_eff("WATER", ["FIRE", "FIRE"]) == 2.0, "") and ok
	ok = _rs_check("ELECTRIC vs GROUND is immune",
		battle._type_eff("ELECTRIC", ["GROUND", "GROUND"]) == 0.0, "") and ok
	# full cross-product equivalence vs the raw project chart
	var chart: Dictionary = ProjectData.legacy("types.json")
	var all := {}
	for a in chart:
		all[a] = true
		for d in chart[a]:
			all[d] = true
	var tnames := all.keys()
	var checked := 0
	var mism := 0
	for a in tnames:
		for d1 in tnames:
			if ruleset.types.mult(a, d1) != float(chart.get(a, {}).get(d1, 1.0)):
				mism += 1
			for d2 in tnames:
				var want := 1.0
				var row: Dictionary = chart.get(a, {})
				for dt in row:
					if str(d1) == dt or str(d2) == dt:
						want *= float(row[dt])
				checked += 1
				if battle._type_eff(a, [d1, d2]) != want:
					mism += 1
	ok = _rs_check("type resolver matches the chart over %d combos" % checked, mism == 0,
		"%d mismatches" % mism) and ok
	# gh #32: the formula kernels — spot ground truths (Gen-1's book values); the md5
	# oracle + the bot hold everything these compose into.
	var F: RulesetFormulas = ruleset.formulas
	ok = _rs_check("gen1 carries a Formulas module", F != null, "") and ok
	ok = _rs_check("exp curves: L100 book values (800k/1M/1.05986M/1.25M)",
		F.exp_for_level(100, "GROWTH_FAST") == 800000
		and F.exp_for_level(100, "GROWTH_MEDIUM_FAST") == 1000000
		and F.exp_for_level(100, "GROWTH_MEDIUM_SLOW") == 1059860
		and F.exp_for_level(100, "GROWTH_SLOW") == 1250000, "") and ok
	ok = _rs_check("level_for_exp inverts the curve",
		F.level_for_exp(1059860, "GROWTH_MEDIUM_SLOW") == 100
		and F.level_for_exp(7, "GROWTH_MEDIUM_FAST") == 1, "") and ok
	ok = _rs_check("stat_calc: Mew L100 maxed = 298 / HP 403",
		F.stat_calc(100, 100, 15, false, 65535) == 298
		and F.stat_calc(100, 100, 15, true, 65535) == 403, "") and ok
	ok = _rs_check("stage_apply: 200% at +2, floor-clamped at -6",
		F.stage_apply(100, 2) == 200 and F.stage_apply(100, -6) == 25
		and F.stage_apply(1, -6) == 1, "") and ok
	ok = _rs_check("damage_core: L50 p100 150/100 = 68",
		F.damage_core(50, false, 100, 150, 100) == 68, "") and ok
	ok = _rs_check("crit_roll: SLASH caps the byte at 255, plain spd-90 reads 45/256",
		F.crit_roll(90, false, "SLASH", func(): return 0.99)
		and not F.crit_roll(90, false, "TACKLE", func(): return 0.5), "") and ok
	ok = _rs_check("accuracy_roll: the 1/256 sure-miss quirk",
		F.accuracy_roll(100, 0, 0, func(_n): return 254)
		and not F.accuracy_roll(100, 0, 0, func(_n): return 255), "") and ok
	ok = _rs_check("catch_attempt: MASTER BALL always catches",
		bool(F.catch_attempt("MASTER BALL", "", 3, 10, 10, func(_n): return 0)["caught"]),
		"") and ok
	# gh #34: the Catch + Progression modules and the data/ruleset.json config record.
	ok = _rs_check("gen1 carries Catch + Progression modules",
		ruleset.catching != null and ruleset.progression != null, "") and ok
	var rc := ProjectData.ruleset_config()
	ok = _rs_check("data/ruleset.json present with base gen1",
		str(rc.get("base", "")) == "gen1" and rc.get("config") is Dictionary,
		str(rc)) and ok
	ok = _rs_check("progression: BadgeStatBoosts mapping + field-move gates",
		ruleset.progression.badge_for_stat("atk") == "BOULDERBADGE"
		and ruleset.progression.badge_for_stat("spc") == "VOLCANOBADGE"
		and ruleset.progression.badge_for_field_move("SURF") == "SOULBADGE"
		and ruleset.progression.badge_for_field_move("DIG") == "", "") and ok
	ok = _rs_check("catch module: safari bait halves / rock doubles (cap 255)",
		ruleset.catching.bait_rate(90) == 45 and ruleset.catching.rock_rate(200) == 255,
		"") and ok
	# the knobs are LIVE, not decorative: an overridden stage table answers differently
	var f2 := Gen1Formulas.new()
	f2.apply_config({"stat_stage_multipliers": {"2": 300}})
	ok = _rs_check("config override turns a knob (stage +2 -> 300%)",
		f2.stage_apply(100, 2) == 300 and F.stage_apply(100, 2) == 200, "") and ok
	print("[ruleset] %s" % ("ALL GREEN" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _rs_check(name: String, good: bool, detail: String) -> bool:
	print("[ruleset] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


## gh #35 (ADR-018 §3): the formula-expression evaluator — unit semantics (integer
## exactness, precedence, branching, named errors) plus the EQUIVALENCE SWEEP: the
## expression-authored Gen-1 kernels (Gen1ExprFormulas) must equal the native
## Gen1Formulas outputs over a fixed vector matrix, value for value.
## Run: `pwsh tools/run.ps1 -- --exprtest`. Headless.
func _exprtest() -> void:
	await get_tree().process_frame
	var ok := true
	# unit semantics
	ok = _ex_check("precedence: 2 + 3 * 4 == 14",
		FormulaExpr.parse("2 + 3 * 4").eval({}) == 14, "") and ok
	ok = _ex_check("int division truncates: 7 / 2 == 3, stays int",
		FormulaExpr.parse("7 / 2").eval({}) == 3
		and FormulaExpr.parse("7 / 2").eval({}) is int, "") and ok
	ok = _ex_check("float promotion: 7 / 2.0 == 3.5",
		FormulaExpr.parse("7 / 2.0").eval({}) == 3.5, "") and ok
	ok = _ex_check("if/and/or/comparisons branch",
		FormulaExpr.parse("if(a > 255 or b > 255, 1, 0)").eval({"a": 999, "b": 1}) == 1
		and FormulaExpr.parse("if(a > 255 and b > 255, 1, 0)").eval({"a": 999, "b": 1}) == 0,
		"") and ok
	ok = _ex_check("functions: min/max/ceil/sqrt/int",
		FormulaExpr.parse("min(255, ceil(sqrt(65535)))").eval({}) == 255
		and FormulaExpr.parse("int(min(255, ceil(sqrt(65535)))) / 4").eval({}) == 63, "") and ok
	ok = _ex_check("parse error is named",
		FormulaExpr.parse("1 + ").error != "", FormulaExpr.parse("1 + ").error) and ok
	ok = _ex_check("unknown function is named",
		FormulaExpr.parse("frob(1)").error.contains("frob"), "") and ok
	# the equivalence sweep: expression-authored kernels vs native, value for value
	var native := Gen1Formulas.new()
	var expr := Gen1ExprFormulas.new()
	var mism := 0
	var checked := 0
	for base in [1, 30, 100, 255]:
		for level in [1, 5, 50, 100]:
			for dv in [0, 8, 15]:
				for sexp in [0, 1, 27, 100, 65535]:
					for is_hp in [false, true]:
						checked += 1
						if native.stat_calc(base, level, dv, is_hp, sexp) \
								!= expr.stat_calc(base, level, dv, is_hp, sexp):
							mism += 1
	ok = _ex_check("stat_calc sweep (%d vectors)" % checked, mism == 0,
		"%d mismatches" % mism) and ok
	checked = 0
	mism = 0
	for g in ["GROWTH_FAST", "GROWTH_SLOW", "GROWTH_MEDIUM_SLOW", "GROWTH_MEDIUM_FAST"]:
		for n in range(1, 101):
			checked += 1
			if native.exp_for_level(n, g) != expr.exp_for_level(n, g):
				mism += 1
	ok = _ex_check("exp-curve sweep (%d vectors)" % checked, mism == 0,
		"%d mismatches" % mism) and ok
	checked = 0
	mism = 0
	for level in [1, 50, 100]:
		for crit in [false, true]:
			for power in [0, 20, 100, 250]:
				for a in [1, 150, 255, 999]:
					for d in [1, 100, 255, 999]:
						checked += 1
						if native.damage_core(level, crit, power, a, d) \
								!= expr.damage_core(level, crit, power, a, d):
							mism += 1
	ok = _ex_check("damage_core sweep (%d vectors, incl. the /4 overflow branch)" % checked,
		mism == 0, "%d mismatches" % mism) and ok
	print("[expr] %s" % ("ALL GREEN" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _ex_check(name: String, good: bool, detail: String) -> bool:
	print("[expr] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


## gh #25: the reconstruction parity oracle — ProjectData.legacy(name) must equal the
## legacy res://assets file for EVERY data table (and all 223 interim maps byte-load
## identically), with exactly two documented exceptions where emission filters dead
## pokered data: Mew's UNUSED TM padding and the UnusedMart/UnusedBikeShop stock.
## Run: `pwsh tools/run.ps1 -- --projparitytest`. Headless.
func _projparitytest() -> void:
	await get_tree().process_frame
	var ok := true
	var perr := ProjectData.open(_project_dir())
	ok = _schema_check("project opened", perr == "", perr) and ok
	if perr != "":
		print("[parity] FAIL")
		get_tree().quit(1)
		return
	var names := ["pokemon/base_stats.json", "dex_entries.json", "cries.json",
		"mon_icons.json", "dex_order.json", "moves.json", "move_sfx.json", "items.json",
		"item_prices.json", "tm_moves.json", "trainers.json", "trainer_pics.json",
		"types.json", "wild.json", "marts.json", "hidden_items.json", "trades.json",
		"text.json", "audio.json", "sfx.json", "charmap.json", "credits.json",
		"dungeon_maps.json", "map_music.json", "move_anims.json", "spinners.json",
		"title_intro.json", "title_mons.json", "town_map.json", "trade_gfx.json",
		"warp_rules.json", "sprites/index.json"]
	for name in names:
		var want = _load_json_any("res://assets/" + name)
		var got = ProjectData.legacy(name)
		# documented emission filters (see docs/v2/project-format.md "Provenance")
		if name == "pokemon/base_stats.json":
			var tm: Array = (want["mew"]["tmhm"] as Array).duplicate()
			tm.erase("UNUSED")
			want["mew"]["tmhm"] = tm
		elif name == "marts.json":
			for dead in ["UnusedMart", "UnusedBikeShop"]:
				want.erase(dead)
		var diff := _deep_diff(want, got, "/")
		ok = _schema_check("parity %s" % name, diff == "", diff) and ok
	var ts_ok := true
	for slug in ["overworld", "gym", "facility", "interior", "cavern"]:
		var d := _deep_diff(_load_json_any("res://assets/tilesets/%s.json" % slug),
			ProjectData.legacy("tilesets/%s.json" % slug), "/")
		ts_ok = ts_ok and d == ""
	ok = _schema_check("parity tilesets (5 sampled)", ts_ok, "") and ok
	var map_ok := true
	var map_n := 0
	var mda := DirAccess.open("res://assets/maps")
	mda.list_dir_begin()
	var mf := mda.get_next()
	while mf != "":
		if mf.ends_with(".json"):
			map_n += 1
			var label := mf.get_basename()
			if _deep_diff(_load_json_any("res://assets/maps/" + mf),
					ProjectData.map_json(label), "/") != "" or not ProjectData.map_exists(label):
				map_ok = false
				print("[schema] map parity FAIL: %s" % label)
		mf = mda.get_next()
	mda.list_dir_end()
	ok = _schema_check("parity maps (%d compared)" % map_n, map_ok and map_n > 200, "") and ok
	print("[parity] %s" % ("ALL GREEN" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _load_json_any(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else null


## First difference between two parsed-JSON values as "path: what", "" when equal.
func _deep_diff(a, b, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: type %s vs %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a is Dictionary:
		for k in a:
			if not b.has(k):
				return "%s: missing key '%s'" % [path, k]
			var d := _deep_diff(a[k], b[k], path + str(k) + "/")
			if d != "":
				return d
		for k in b:
			if not a.has(k):
				return "%s: extra key '%s'" % [path, k]
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: size %d vs %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := _deep_diff(a[i], b[i], "%s%d/" % [path, i])
			if d != "":
				return d
		return ""
	if a != b:
		return "%s: %s vs %s" % [path, str(a).left(40), str(b).left(40)]
	return ""


## gh #22: validate any project directory (res:// or an OS path) against the format.
## Run: `pwsh tools/run.ps1 -- --validate=<dir>`. Exit 0 only when the project is clean.
func _validateproject(dir: String) -> void:
	await get_tree().process_frame
	var r: Dictionary = ProjectValidator.validate_project(dir)
	for e in r["errors"]:
		print("[validate] %s" % e)
	print("[validate] %s — %d files, ids %s, %d errors" % [
		"OK" if bool(r["ok"]) else "INVALID", int(r["files"]), str(r["ids"]),
		(r["errors"] as Array).size()])
	get_tree().quit(0 if bool(r["ok"]) else 1)


func _validate_dir_arg(args) -> String:
	for a in args:
		if str(a).begins_with("--validate="):
			return str(a).substr(11)
	return ""


## gh #25: the project directory the runtime loads — res://project (the extractor's
## emission) unless --project=<dir> points elsewhere. An EXPORTED build carries no
## res://project at all (the dir is .gdignore'd raw data — invisible to the exporter by
## design, keeping the files md5-stable with no import artifacts), so there the default
## is the loose `project/` folder tools/export.ps1 places beside the executable.
func _project_dir() -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--project="):
			return str(a).substr(10)
	if not OS.has_feature("editor"):
		var side := OS.get_executable_path().get_base_dir().path_join("project")
		if FileAccess.file_exists(side.path_join("manifest.json")):
			return side
	return "res://project"


## field-invalid records without crashing. Run: `pwsh tools/run.ps1 -- --monrecordtest`.
func _monrecordtest() -> void:
	await get_tree().process_frame
	player_name = "RED"
	player_id = 31337
	var ok := true

	# --- round-trips: encode -> JSON wire string -> decode -> field compare + re-encode ---
	var a: Dictionary = make_mon("kadabra", 40, [])                       # plain, own OT
	var b: Dictionary = make_mon("dragonair", 35, ["WRAP", "THRASH", "AGILITY", "SLAM"])
	b["name"] = "NOODLE"                                                  # nicknamed
	b["status"] = "slp"; b["sleep"] = 3                                   # statused
	b["ot"] = "TRADER"; b["otid"] = 555                                   # outsider mon
	b["sexp"] = {"hp": 1200, "atk": 65535, "def": 40, "spd": 0, "spc": 7}
	recompute_stats(b)
	b["hp"] = 11                                                          # partial HP
	b["moves"][0]["pp"] = 0; b["moves"][2]["pp"] = 5                      # spent PP
	var c: Dictionary = make_mon("magikarp", 5, ["SPLASH"])               # one move slot
	var d: Dictionary = make_mon("mrmime", 99, ["MIMIC", "METRONOME", "SUBSTITUTE", "CONFUSION"])
	d["status"] = "psn"
	for pair in [["plain", a], ["traded+status", b], ["one-move", c], ["four-move", d]]:
		var mon: Dictionary = pair[1]
		var wire := JSON.stringify(monrecord.encode(mon))                 # the peer-message form
		var back: Dictionary = monrecord.decode_json(wire)
		var good: bool = bool(back["ok"])
		if good:
			var m2: Dictionary = back["mon"]
			for k in ["species", "name", "level", "exp", "hp", "maxhp", "status", "sleep",
					"atk", "def", "spd", "spc", "ot", "otid"]:
				good = good and str(m2.get(k)) == str(mon.get(k, m2.get(k)))
			for k2 in ["hp", "atk", "def", "spd", "spc"]:   # per-key: dict ORDER may differ
				good = good and int(m2["dvs"][k2]) == int(mon["dvs"][k2]) \
					and int(m2["sexp"][k2]) == int(mon["sexp"][k2])
			good = good and JSON.stringify(monrecord.encode(m2)) == wire  # canonical re-encode
		print("[monrecord] round-trip %s: %s" % [pair[0], "ok" if good else
			"FAIL (%s)" % back.get("error", "field mismatch")])
		ok = ok and good

	# --- unknown format version: refused cleanly, naming the schema ---
	var vrec: Dictionary = monrecord.encode(a)
	vrec["schema"] = "mon/9"
	var vres: Dictionary = monrecord.decode(vrec)
	var vok: bool = not bool(vres["ok"]) and "mon/9" in str(vres["error"])
	print("[monrecord] unknown version refused: %s (%s)" % [vok, vres.get("error", "?")])
	ok = ok and vok

	# --- malformed / field-invalid fixtures: rejected, never crashing ---
	var base: Dictionary = monrecord.encode(a)
	var bad_fixtures: Array = [
		["not JSON", "{nope"],
		["not a dict", "[1, 2, 3]"],
		["empty dict", "{}"],
	]
	for f in bad_fixtures:
		var r: Dictionary = monrecord.decode_json(str(f[1]))
		var rj: bool = not bool(r["ok"]) and str(r["error"]) != ""
		print("[monrecord] reject %s: %s (%s)" % [f[0], rj, r.get("error", "?")])
		ok = ok and rj
	var tweaks: Array = [
		["missing species", func(r: Dictionary) -> void: r.erase("species")],
		["bare species id", func(r: Dictionary) -> void: r["species"] = "kadabra"],
		["unknown species", func(r: Dictionary) -> void: r["species"] = "species:missingno"],
		["level 0", func(r: Dictionary) -> void: r["level"] = 0],
		["level 101", func(r: Dictionary) -> void: r["level"] = 101],
		["level as text", func(r: Dictionary) -> void: r["level"] = "forty"],
		["negative exp", func(r: Dictionary) -> void: r["exp"] = -1],
		["bad status", func(r: Dictionary) -> void: r["status"] = "pox"],
		["sleep 9", func(r: Dictionary) -> void: r["sleep"] = 9],
		["dv 16", func(r: Dictionary) -> void: (r["dvs"] as Dictionary)["atk"] = 16],
		["dv -1", func(r: Dictionary) -> void: (r["dvs"] as Dictionary)["spd"] = -1],
		["stat exp 70000", func(r: Dictionary) -> void: (r["stat_exp"] as Dictionary)["hp"] = 70000],
		["no moves", func(r: Dictionary) -> void: r["moves"] = []],
		["five moves", func(r: Dictionary) -> void: r["moves"] = [
			{"id": "move:POUND", "pp": 1}, {"id": "move:TACKLE", "pp": 1},
			{"id": "move:GROWL", "pp": 1}, {"id": "move:SCRATCH", "pp": 1},
			{"id": "move:EMBER", "pp": 1}]],
		["unknown move", func(r: Dictionary) -> void: r["moves"] = [{"id": "move:FISSURE_X", "pp": 1}]],
		["duplicate move", func(r: Dictionary) -> void: r["moves"] = [
			{"id": "move:POUND", "pp": 1}, {"id": "move:POUND", "pp": 1}]],
		["missing maxpp", func(r: Dictionary) -> void: r["moves"] = [{"id": "move:POUND", "pp": 5}]],
		["pp over maxpp", func(r: Dictionary) -> void: r["moves"] = [
			{"id": "move:POUND", "pp": 20, "maxpp": 10}]],
		["maxpp over the Gen-1 ceiling", func(r: Dictionary) -> void: r["moves"] = [
			{"id": "move:POUND", "pp": 5, "maxpp": 99}]],
		["numeric nickname", func(r: Dictionary) -> void: r["nickname"] = 12345],
		["11-char nickname", func(r: Dictionary) -> void: r["nickname"] = "ABCDEFGHIJK"],
		["trainer_id 70000", func(r: Dictionary) -> void: r["trainer_id"] = 70000],
	]
	for t in tweaks:
		var rec: Dictionary = JSON.parse_string(JSON.stringify(base))     # deep copy via the wire
		(t[1] as Callable).call(rec)
		var r: Dictionary = monrecord.decode(rec)
		var rj: bool = not bool(r["ok"]) and str(r["error"]) != ""
		print("[monrecord] reject %s: %s (%s)" % [t[0], rj, r.get("error", "?")])
		ok = ok and rj

	print("[monrecord] %s" % ("ALL GREEN" if ok else "FAIL"))
	get_tree().quit()


## gh #7: raise the Colosseum link battle. The peer's party arrives as mon records (decoded
## and validated at the boundary), the seed is the shared one the host fixed at the table,
## and the party is snapshotted for the stakeless restore. The event stream always logs in
## a link battle — the [battledet] lines ARE the sync oracle.
func start_colosseum_battle(peer_records: Array, seed_v: int, pname: String) -> bool:
	var eparty: Array = []
	for r in peer_records:
		var d: Dictionary = monrecord.decode(r)
		if not bool(d["ok"]):
			print("[col] refused peer party: %s" % d["error"])
			return false
		eparty.append(d["mon"])
	if eparty.is_empty():
		return false
	_col_snapshot = []
	for m in player_party:
		_col_snapshot.append(JSON.parse_string(JSON.stringify(m)))   # deep copy
	if audio:
		audio.play_song("trainerbattle")
	battle.det_log = true
	link.resume_armed = true               # gh #13: a mid-battle outage holds for a reconnect
	modal = battle                         # (covers the club flow AND the headless --colsoak path;
	battle.start_link(player_party, eparty, link.is_host, seed_v, pname)   # cleared on finish)
	return true


# ---- Cable Club rooms (gh #6) ----------------------------------------------

## Entering a club room: seat the partner's avatar in the opposite chair, facing the player
## (TradeCenter_Script moves TRADECENTER_OPPONENT to (6,4)/LEFT for the host's view,
## (3,4)/RIGHT for the partner's).
func club_room_enter() -> void:
	cutscene.tc_room_arm()        # catch a partner's tc_party sent before we reach the table
	var opp = _npc_by_key("SPRITE_RED@2,2")
	if opp == null:
		print("[club] WARNING: opponent avatar not found in %s" % center_label)
		return
	var seat := Vector2i(6, 4) if link.is_host else Vector2i(3, 4)
	opp.cell = seat
	opp.home = seat
	opp.position = Vector2(seat * 16)
	opp.face(opp.LEFT if link.is_host else opp.RIGHT)


## Stepping onto the room's doormat row leaves the club: the link closes and the player is
## back beside the attendant (cable_club.asm watches the exit the same way).
func club_room_step(cell: Vector2i) -> bool:
	if cell.y >= 6:
		club_room_leave()
		return true
	return false


func club_room_leave() -> void:
	_club_leaving = true
	cutscene.tc_room_disarm()
	if link.state == "linked":
		link.close("left-room")
	var back := link_return_map if link_return_map != "" else respawn_map
	load_world(back, -1, link_return_cell, false)
	_club_leaving = false


## The partner's link died while we stood in the room: say so and walk back out.
func _club_room_kicked() -> void:
	cutscene_active = true
	await cutscene.say("The link has been\nclosed.")
	cutscene_active = false
	club_room_leave()


## gh #6/#9: the two-phase trade journal. Phase "ready" = records exchanged, our ack NOT
## yet sent — the peer cannot have completed, so an interrupted trade ROLLS BACK. Phase
## "acked" = written immediately before our ack goes out — from that instant the peer may
## complete on our ack, so recovery ROLLS FORWARD (presumed commit). Cleared after
## apply + save. The un-closable residue — the ack lost in transit the same instant the
## cable is pulled — is the two-generals bound, documented in engine/link.md.
func _tc_journal_path() -> String:
	return SAVE_PATH.get_basename() + "_trade_journal.json"


func _tc_journal_write(phase: String, give: Dictionary, peer_record: Dictionary, dupe: bool) -> void:
	var f := FileAccess.open(_tc_journal_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"phase": phase, "dupe": dupe,
			"give": monrecord.encode(give), "get": peer_record}))
		f.close()


func _tc_journal_clear() -> void:
	if FileAccess.file_exists(_tc_journal_path()):
		DirAccess.open("user://").remove(_tc_journal_path().get_file())


## Recovery, run when a save loads (gh #9). ready -> roll back (nothing was applied here,
## and the peer can't have our ack). acked + dupe armed -> roll back ON PURPOSE: that IS
## the cartridge's cable-pull duplication — we keep our mon, their save keeps the copy.
## acked otherwise -> roll forward: apply the journaled trade (with its silent trade
## evolution) and save, matching the peer who completed on our ack.
func _tc_journal_recover() -> void:
	if not FileAccess.file_exists(_tc_journal_path()):
		return
	var f := FileAccess.open(_tc_journal_path(), FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text()) if f else null
	_tc_journal_clear()
	if not j is Dictionary:
		return
	if str(j.get("phase", "ready")) != "acked":
		print("[trade] interrupted before the point of no return — rolled back (both sides untraded)")
		return
	if bool(j.get("dupe", false)):
		print("[trade] dupe easter egg: the cable pull kept your mon — their copy lives on")
		return
	var d: Dictionary = monrecord.decode(j.get("get", {}))
	if not bool(d["ok"]):
		return
	# Canonicalize the journaled give record through decode->encode before comparing:
	# JSON parsing turned its ints into floats, and "level":40.0 never string-matches
	# the fresh encode's "level":40.
	var gived: Dictionary = monrecord.decode(j.get("give", {}))
	if bool(gived["ok"]):
		var give_wire := JSON.stringify(monrecord.encode(gived["mon"]))
		for i in player_party.size():
			if JSON.stringify(monrecord.encode(player_party[i])) == give_wire:
				player_party.remove_at(i)
				break
	var got: Dictionary = d["mon"]
	if player_party.size() < 6:
		player_party.append(got)
	else:
		pc_box.append(got)
	mark_owned(str(got["species"]))
	for ev in mon_base[str(got["species"])]["evolutions"]:
		if str(ev[0]) == "EVOLVE_TRADE" and int(got["level"]) >= int(ev[1]):
			_evolve_mon(got, str(ev[2]))
			break
	save_game()
	print("[trade] recovered an interrupted trade — rolled forward (both sides traded)")


## gh #9: the drop-injection hook — a simulated cable pull. The ENet flush first means the
## datagram just sent DID get out (the scripted points test protocol windows, not packet
## loss); then the process dies with no goodbye.
func _maybe_kill(point: String) -> void:
	# gh #13: the blip injection rides the same scripted points as the kill injection — the
	# transport resets (no process death) and the ADR-016 resume machinery takes over. One
	# blip per point (a resumed flow re-crosses the same point and must not re-blip), or one
	# per qualifying turn under --blipevery=N (the blip-soak).
	if _blip_last != point:
		if blip_at == point:
			_blip_last = point
			link.blip()
		elif blip_every > 0 and point.begins_with("act") and int(point.substr(3)) % blip_every == 0:
			_blip_last = point
			link.blip()
	if kill_at != point:
		return
	if link._enet != null:
		link._enet.flush()
	print("[kill] simulated cable pull at '%s'" % point)
	get_tree().quit()


# gh #8: the desync-soak party roster. Fixed DVs so mirror matches produce REAL speed ties
# (the shared-coin path), and the sets span the RNG-heavy surface: status, multi-turn locks,
# multi-hit, crit-heavy, confusion, trapping, Transform/Mimic/Metronome, REST/recovery.
const _SOAK_PARTIES := [
	[["tauros", 50, ["BODY_SLAM", "EARTHQUAKE", "BLIZZARD", "TACKLE"]],
		["lapras", 50, ["SURF", "ICE_BEAM", "BODY_SLAM", "GROWL"]]],
	[["arcanine", 50, ["BODY_SLAM", "QUICK_ATTACK", "AGILITY", "BITE"]],
		["slowbro", 50, ["SURF", "PSYCHIC_M", "AMNESIA", "POUND"]]],
	[["gengar", 50, ["CONFUSE_RAY", "HYPNOSIS", "NIGHT_SHADE", "LICK"]],
		["arbok", 50, ["GLARE", "ACID", "WRAP", "SCREECH"]]],
	[["dragonair", 50, ["WRAP", "THRASH", "AGILITY", "SLAM"]],
		["primeape", 50, ["KARATE_CHOP", "FURY_SWIPES", "FOCUS_ENERGY", "THRASH"]]],
	[["ditto", 50, ["TRANSFORM"]],
		["mrmime", 50, ["MIMIC", "METRONOME", "SUBSTITUTE", "CONFUSION"]]],
	[["tauros", 50, ["BODY_SLAM", "EARTHQUAKE", "BLIZZARD", "TACKLE"]],
		["snorlax", 50, ["REST", "HYPER_BEAM", "EARTHQUAKE", "AMNESIA"]]],
]


## gh #8: one soak battle — the fast path to a link battle, no club walk. The instances
## link (--clubhost/--clubjoin), exchange col_party + the host's seed, and fight with a
## deterministic varied move policy (each side cycles its moves by turn + party index, so
## the battery reaches moves the always-m0 script never would). Driven in pairs by
## tools/linksoak.py; any stream divergence is the battery's failure.
func _colsoaktest() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var hosting := "--clubhost" in args
	var pidx := 0
	var seed_v := 1
	link_wait_s = 60.0
	for a in args:
		if str(a).begins_with("--port="):
			link_port = int(str(a).substr(7))
		elif str(a).begins_with("--colparty="):
			pidx = int(str(a).substr(11)) % _SOAK_PARTIES.size()
		elif str(a).begins_with("--colseed="):
			seed_v = int(str(a).substr(10))
		elif str(a).begins_with("--killat="):
			kill_at = str(a).substr(9)          # gh #9: mid-battle cable pull
		elif str(a).begins_with("--blipat="):
			blip_at = str(a).substr(9)          # gh #13: transport reset, process alive
		elif str(a).begins_with("--blipevery="):
			blip_every = int(str(a).substr(12))
		elif str(a).begins_with("--linkpeertimeout="):
			link.peer_timeout_max_ms = int(str(a).substr(18))
		elif str(a).begins_with("--linkgrace="):
			link.resume_grace_s = float(str(a).substr(12))
	player_name = "HOSTA" if hosting else "JOINB"
	player_id = 111 if hosting else 222
	# Fixed DVs so mirror matches really tie — and LEGAL ones: Gen 1 derives the hp DV from
	# the low bits of the other four ((8,9,10,11) -> 5), and the mon record re-derives it,
	# so an illegal hp DV would make the peer's decoded copy differ from the local mon.
	var dvs := {"hp": 5, "atk": 8, "def": 9, "spd": 10, "spc": 11}
	player_party = []
	for spec in _SOAK_PARTIES[pidx]:
		player_party.append(make_mon(str(spec[0]), int(spec[1]), spec[2], dvs))
	var port: int = link_port if link_port > 0 else link.DEFAULT_PORT
	link.timeout_s = 45.0
	if hosting:
		link.host(port)
	else:
		link.join("127.0.0.1", port)
	var g := 0
	while link.state != "linked" and link.state != "closed" and g < 60 * 90:
		await get_tree().process_frame
		g += 1
	if link.state != "linked":
		print("[soak] FAIL: no link (%s)" % link.state)
		get_tree().quit()
		return
	# the Colosseum exchange, headless: parties + the host's seed
	cutscene.tc_room_arm()
	var mine: Array = []
	for m in player_party:
		mine.append(monrecord.encode(m))
	link.send_message({"t": "col_party", "mons": mine, "name": player_name, "seed": seed_v})
	g = 0
	while cutscene._col_peer.is_empty() and link.state == "linked" and g < 60 * 90:
		await get_tree().process_frame
		g += 1
	if cutscene._col_peer.is_empty():
		print("[soak] FAIL: no peer party (%s)" % link.state)
		get_tree().quit()
		return
	var peer: Dictionary = cutscene._col_peer
	cutscene._col_peer = {}
	if not start_colosseum_battle(peer.get("mons", []), seed_v, str(peer.get("name", "?"))):
		print("[soak] FAIL: bad peer party")
		get_tree().quit()
		return
	g = 0
	while (modal == battle or _link_lost_seized) and g < 60000:   # gh #13: hold through an outage
		if link.holding():
			await get_tree().process_frame             # gh #13: an outage must not eat the budget
			continue
		if battle.state == "menu":
			battle.cursor = 0
			await _press("ui_accept")                  # FIGHT
			if battle.state == "moves":
				# varied but deterministic: cycle the moveset by turn + party index,
				# falling forward to the next slot with PP
				var mvs: Array = battle.player_mon["moves"]
				var want := (int(battle.turn_no) + pidx) % mvs.size()
				for off in mvs.size():
					var i2 := (want + off) % mvs.size()
					if int(mvs[i2]["pp"]) > 0:
						want = i2
						break
				battle.cursor = want
				await _press("ui_accept")
				if battle.state == "moves":            # all PP gone: back out, STRUGGLE path
					await _press("ui_cancel")
		elif battle.state == "party_forced":
			battle.cursor = battle._first_usable()
			await _press("ui_accept")
		elif battle.state == "msg":
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	var stream: Array = battle.det_stream
	print("[soak] %s: party=%d seed=%d end=%s events=%d stream_md5=%s" % [
		"host" if hosting else "join", pidx, seed_v,
		str(stream[-1]).split("|")[1] if stream.size() > 0 else "unfinished", stream.size(),
		"\n".join(PackedStringArray(stream)).md5_text()])
	get_tree().quit()


## gh #9: relaunch a killed instance's slot — loading the save runs the trade-journal
## recovery (ready -> rollback, acked -> roll-forward, dupe -> the egg); print the outcome.
func _recovertest() -> void:
	await get_tree().process_frame
	var okl := load_game()
	var sp: Array = []
	for m in player_party:
		sp.append(str(m["species"]))
	print("[recover] loaded=%s party=%s box=%d journal=%s" % [
		okl, sp, pc_box.size(), FileAccess.file_exists(_tc_journal_path())])
	# Codec probe: run every party mon through the wire round-trip and name any failure —
	# the exact check the Trade Center runs on the partner's records.
	for m in player_party:
		var rec: Dictionary = monrecord.encode(m)
		var back: Dictionary = monrecord.decode(JSON.parse_string(JSON.stringify(rec)))
		if bool(back["ok"]):
			print("[codec] %s: ok" % m["species"])
		else:
			print("[codec] %s: FAIL — %s" % [m["species"], back["error"]])
			print("[codec]   record: %s" % JSON.stringify(rec))
	get_tree().quit()


## gh #5: the Cable Club attendant. Single-instance (`--clubtest`) drives every refusal/
## timeout path scripted: the no-Pokédex brush-off, CANCEL at the cable menu, a HOST wait
## that times out, and a JOIN to a dead address — each must land back on the overworld with
## no modal, no cutscene, and the link closed (no soft-lock; spec story 21). The full
## two-instance flow (`--clubtest --clubhost` / `--clubjoin`, from the attendant to the
## Trade Center floor) is driven by `python tools/linktest.py`.
func _clubtest() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var hosting := "--clubhost" in args
	var joining := "--clubjoin" in args
	for a in args:
		if str(a).begins_with("--port="):
			link_port = int(str(a).substr(7))
		elif str(a).begins_with("--tamper="):
			link.tamper = str(a).substr(9)      # drive the in-dialogue refusal path
		elif str(a).begins_with("--killat="):
			kill_at = str(a).substr(9)          # gh #9: pull the cable at a scripted point
		elif str(a).begins_with("--blipat="):
			blip_at = str(a).substr(9)          # gh #13: transport reset, process alive
		elif str(a).begins_with("--linkpeertimeout="):
			link.peer_timeout_max_ms = int(str(a).substr(18))
		elif str(a).begins_with("--linkgrace="):
			link.resume_grace_s = float(str(a).substr(12))
		elif str(a) == "--dupe":
			link.dupe_opt_in = true             # gh #9: the easter-egg opt-in
	player_name = "RED"
	load_world("CeruleanPokecenter", -1, Vector2i(11, 3), false)
	player.facing = player.UP                      # the receptionist is at (11,2), STAY DOWN

	if hosting or joining:
		# --- the two-instance in-game flow: attendant -> link -> save beat -> LinkMenu ->
		# the Trade Center floor. The joiner never picks a destination: the host's choice
		# arrives as club_go and closes its menu (the LinkMenu arbiter path).
		link_wait_s = 25.0
		story_events = {"GOT_POKEDEX": true}
		player_name = "HOSTA" if hosting else "JOINB"      # distinct OTs: outsider status is visible
		player_id = 111 if hosting else 222
		interact(player)
		var club_room := "Colosseum" if "--battle" in args else "TradeCenter"
		var g := 0
		while center_label != club_room and (cutscene_active or g < 200) and g < 6000:
			if modal == menu and menu_mode == "cutscene":
				var items: Array = menu.items
				if items.size() == 3 and str(items[0]) == "HOST":
					menu.chosen.emit(0 if hosting else 1)
				elif items.size() == 2:            # the save-warning YES/NO
					menu.chosen.emit(0)
				elif items.size() == 3 and str(items[0]) == "TRADE CENTER" and hosting:
					await get_tree().create_timer(0.5).timeout   # let the joiner's menu open
					if modal == menu:
						menu.chosen.emit(1 if "--battle" in args else 0)
				await get_tree().process_frame
			elif modal == naming:
				naming.done.emit(str(naming.presets[0]))         # ED on empty -> the default
				await get_tree().process_frame
			elif modal == textbox and textbox.active:
				await _press("ui_accept")
			else:
				await get_tree().process_frame
			g += 1
		print("[club] %s: map=%s cell=%s link=%s addr='%s' modal_clear=%s" % [
			"host" if hosting else "join", center_label, player.cell, link.state,
			link_last_addr, modal == null and not cutscene_active])
		# --- gh #7: the Colosseum lockstep battle — scripted m0 on both sides ---
		if "--battle" in args and center_label == "Colosseum":
			player_party = [make_mon("tauros", 50, ["BODY_SLAM", "EARTHQUAKE", "BLIZZARD", "TACKLE"]),
					make_mon("lapras", 50, ["SURF", "ICE_BEAM", "BODY_SLAM", "GROWL"])] if hosting \
				else [make_mon("arcanine", 50, ["BODY_SLAM", "QUICK_ATTACK", "AGILITY", "BITE"]),
					make_mon("slowbro", 50, ["SURF", "PSYCHIC_M", "AMNESIA", "POUND"])]
			player.facing = player.RIGHT if hosting else player.LEFT
			interact(player)
			g = 0
			while modal != battle and g < 18000:           # the first sitter waits on the link
				await get_tree().process_frame
				g += 1
			g = 0
			while modal == battle and g < 36000:
				if battle.state == "menu":
					battle.cursor = 0
					await _press("ui_accept")              # FIGHT
					if battle.state == "moves":
						battle.cursor = 0
						await _press("ui_accept")          # the first move
				elif battle.state == "party_forced":
					battle.cursor = battle._first_usable()
					await _press("ui_accept")
				elif battle.state == "msg":
					await _press("ui_accept")
				else:
					await get_tree().process_frame
				g += 1
			var stream: Array = battle.det_stream
			print("[col] %s: end=%s events=%d stream_md5=%s party_restored=%s" % [
				"host" if hosting else "join",
				str(stream[-1]).split("|")[1] if stream.size() > 0 else "?", stream.size(),
				"\n".join(PackedStringArray(stream)).md5_text(),
				int(player_party[0]["hp"]) == int(player_party[0]["maxhp"])])
		# --- gh #6: the trade — kadabra <-> machoke, both trade evolutions on arrival ---
		if "--trade" in args and center_label == "TradeCenter":
			player_party = [make_mon("kadabra" if hosting else "machoke", 40, []),
				make_mon("pidgey", 20, [])]
			save_game()          # the trade party is save-truth, as a real player's would be
			var rounds: int = 2 if "--trade2" in args else 1
			for round_n in rounds:
				cutscene._tc_result = ""
				player.facing = player.RIGHT if hosting else player.LEFT   # face the table
				interact(player)
				g = 0
				while str(cutscene._tc_result) == "" and g < 12000:
					if modal == menu and menu_mode == "cutscene":
						menu.chosen.emit(0)                # pick the first mon / YES
						await get_tree().process_frame
					elif modal == textbox and textbox.active:
						await _press("ui_accept")
					else:
						await get_tree().process_frame
					if not link.holding():             # gh #13: an outage must not eat the budget
						g += 1
				var names: Array = []
				for m in player_party:
					names.append("%s(%s/%d)" % [m["name"], str(m.get("ot", "?")), int(m.get("otid", -1))])
				print("[trade] %s: result=%s party=%s box=%d journal=%s" % [
					"host" if hosting else "join", cutscene._tc_result, names, pc_box.size(),
					FileAccess.file_exists(_tc_journal_path())])
				if str(cutscene._tc_result) != "done":
					break
			if str(cutscene._tc_result) != "done":
				# the dead-link kick must walk us back out (the stuck-in-room bug)
				var t3 := Time.get_ticks_msec()
				while center_label == "TradeCenter" and Time.get_ticks_msec() - t3 < 75000:
					if modal == textbox and textbox.active:
						await _press("ui_accept")
					else:
						await get_tree().process_frame
				print("[trade] after-drop map=%s" % center_label)
		get_tree().quit()
		return

	# --- single-instance: every path that must come back to the attendant cleanly ---
	link_wait_s = 2.0
	# (a) no Pokédex: "We're making preparations."
	story_events = {}
	interact(player)
	await _club_pump(-1)
	print("[club] no-dex brush-off: clean=%s link=%s" % [_club_clean(), link.state])
	# (b) CANCEL at the cable menu -> the area-reserved line.
	story_events = {"GOT_POKEDEX": true}
	interact(player)
	await _club_pump(2)
	print("[club] cancel: clean=%s link=%s" % [_club_clean(), link.state])
	# (c) HOST with nobody coming: the wait times out politely.
	interact(player)
	await _club_pump(0)
	print("[club] host timeout: clean=%s link=%s" % [_club_clean(), link.state])
	# (d) JOIN a dead address (the ED default): the connect times out politely.
	interact(player)
	await _club_pump(1)
	print("[club] join dead addr: clean=%s link=%s" % [_club_clean(), link.state])
	get_tree().quit()


func _club_clean() -> bool:
	return modal == null and not cutscene_active and link.state in ["idle", "closed"]


## Pump one attendant visit: answer the cable menu with `pickidx`, confirm the naming
## screen's default, A through text, and wait out the link's own timeouts.
func _club_pump(pickidx: int, budget := 3000) -> void:
	var g := 0
	while (cutscene_active or modal != null) and g < budget:
		if modal == menu and menu_mode == "cutscene":
			menu.chosen.emit(pickidx)
			await get_tree().process_frame
		elif modal == naming:
			naming.done.emit(str(naming.presets[0]) if naming.presets.size() > 0 else "")
			await get_tree().process_frame
		elif modal == textbox and textbox.active:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1


func _has_join_arg(args: Array) -> bool:
	for a in args:
		if str(a) == "--join" or str(a).begins_with("--join="):
			return true
	return false


## gh #3 (ADR-014): the link tracer bullet. `--host [--port=N]` waits for a partner;
## `--join <ip>` / `--join=<ip>` connects to one. The whole connect flow runs headlessly:
## Link.gd raises the session (link identity handshake: exact version + the extraction
## manifest's content hashes), then the host sends a ping, the joiner answers pong, and both
## quit — `tools/linktest.py` launches a pair and asserts both logs. `--tamper=version`,
## `--tamper=engine`, or `--tamper=<part>` (species/moves/types) corrupts this side's
## identity so the refusal path can be driven; `--linktimeout=N` shortens the no-partner
## timeout for tests.
func _linktest(hosting: bool) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var port: int = link.DEFAULT_PORT
	var ip := "127.0.0.1"
	link.timeout_s = 20.0
	for i in args.size():
		var a := str(args[i])
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--tamper="):
			link.tamper = a.substr(9)
		elif a.begins_with("--linktimeout="):
			link.timeout_s = float(a.substr(14))
		elif a.begins_with("--join="):
			ip = a.substr(7)
		elif a == "--join" and i + 1 < args.size() and not str(args[i + 1]).begins_with("--"):
			ip = str(args[i + 1])
		elif a == "--dupe":
			link.dupe_opt_in = true
	link.established.connect(_linktest_on_established)
	link.message.connect(_linktest_on_message)
	_linktest_hosting = hosting
	_linktest_done = false
	link.closed.connect(func(_reason: String) -> void: _linktest_done = true)
	if hosting:
		link.host(port)
	else:
		link.join(ip, port)
	var g := 0
	while not _linktest_done and g < 60 * 120:  # hard cap ~2 min; Link's own timeout fires first
		await get_tree().process_frame
		g += 1
	print("[link] exit state=%s" % link.state)
	get_tree().quit()


var _linktest_hosting := false
var _linktest_done := false


func _linktest_on_established(_session: Dictionary) -> void:
	if _linktest_hosting:
		link.send_message({"t": "ping"})


func _linktest_on_message(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	if t == "ping":
		print("[link] ping received — answering")
		link.send_message({"t": "pong"})
	elif t == "pong":
		print("[link] echo round-trip ok")
		link.send_message({"t": "bye"})
		link.close("done")
	elif t == "bye":
		link.close("done")


## gh #2 (ADR-014): the battle determinism oracle. Each scenario drives a REAL battle — the
## input state machine, not direct _do_move calls — twice from the same battle seed with the
## same scripted decisions, and asserts the two canonical per-turn event streams (turn, both
## actions, RNG cursor, state digest) are BYTE-IDENTICAL; a third run on a different seed
## must produce a different stream, so the oracle can't pass vacuously (the gh #84 lesson).
## Scenarios cover status moves, trainer-AI items/switches, player switching, bag items,
## multi-turn locks (WRAP/THRASH/HYPER BEAM), confusion, multi-hit, Transform/Mimic/
## Metronome/Disable/Substitute, and the wild catch/run rolls.
## Run: `pwsh tools/run.ps1 -- --battledettest [--verbose]` (verbose echoes every event).
func _battledettest() -> void:
	await get_tree().process_frame
	var scns: Array = [
		{"name": "core", "enemy_trainer": true,
			"party": [["nidoking", 40, ["THUNDER_WAVE", "BODY_SLAM", "TOXIC", "BLIZZARD"]],
				["snorlax", 38, ["REST", "HYPER_BEAM", "EARTHQUAKE", "AMNESIA"]]],
			"bag": {"POTION": 3, "X ATTACK": 1},
			"enemy": [["dewgong", 36], ["cloyster", 36], ["slowbro", 36]],
			"ai": "Lorelei", "ai_mods": [1, 3],
			"script": [["m", 0], ["m", 2], ["s", 1], ["m", 1], ["i", "POTION"], ["m", 2]]},
		{"name": "multiturn", "enemy_trainer": true,
			"party": [["dragonair", 35, ["WRAP", "THRASH", "AGILITY", "SLAM"]],
				["primeape", 35, ["KARATE_CHOP", "FURY_SWIPES", "FOCUS_ENERGY", "THRASH"]]],
			"bag": {},
			"enemy": [["gengar", 35], ["golbat", 33], ["arbok", 33]],
			"ai": "Agatha", "ai_mods": [1, 3],
			"enemy_moves": {0: ["CONFUSE_RAY", "HYPNOSIS", "NIGHT_SHADE", "LICK"],
				2: ["GLARE", "ACID", "WRAP", "SCREECH"]},
			"script": [["m", 1], ["m", 0], ["s", 1], ["m", 2], ["m", 1], ["m", 0]]},
		{"name": "copycat", "enemy_trainer": true,
			"party": [["mrmime", 35, ["MIMIC", "METRONOME", "SUBSTITUTE", "CONFUSION"]],
				["kadabra", 35, ["PSYWAVE", "DISABLE", "REFLECT", "PSYCHIC_M"]]],
			"bag": {},
			"enemy": [["ditto", 35], ["porygon", 30]],
			"ai": "Generic", "ai_mods": [],
			"script": [["m", 0], ["m", 1], ["m", 2], ["s", 1], ["m", 1], ["m", 0], ["m", 3]]},
		{"name": "wild", "wild": ["fearow", 30],
			"party": [["slowbro", 30, []]],       # slower than the wild mon: escapes must ROLL
			"bag": {"POKé BALL": 3, "GREAT BALL": 2},
			"script": [["i", "POKé BALL"], ["r"], ["i", "GREAT BALL"], ["r"], ["m", 0], ["r"]]},
	]
	var all_ok := true
	for scn in scns:
		var s1: Array = await _det_scn_run(scn, 12345)
		var s2: Array = await _det_scn_run(scn, 12345)
		var s3: Array = await _det_scn_run(scn, 54321)
		var j1 := "\n".join(PackedStringArray(s1))
		var same: bool = j1 == "\n".join(PackedStringArray(s2))
		var differs: bool = j1 != "\n".join(PackedStringArray(s3))
		# The stream md5 is printed so two INVOCATIONS can be compared too — lockstep peers
		# are separate processes, so the stream must be stable across processes, not just
		# across replays inside one.
		print("[battledet] %s: events=%d/%d replay_identical=%s other_seed_differs=%s stream_md5=%s" % [
			scn["name"], s1.size(), s2.size(), same, differs, j1.md5_text()])
		if not same:
			for i in mini(s1.size(), s2.size()):
				if str(s1[i]) != str(s2[i]):
					print("[battledet]   first divergence at event %d:" % i)
					print("[battledet]     run1: %s" % s1[i])
					print("[battledet]     run2: %s" % s2[i])
					break
			if s1.size() != s2.size():
				print("[battledet]   stream lengths differ: %d vs %d" % [s1.size(), s2.size()])
		all_ok = all_ok and same and differs
	print("[battledet] %s" % ("ALL GREEN" if all_ok else "FAIL"))
	get_tree().quit()


## One oracle run: rebuild the parties from the scenario spec (fixed DVs; the global RNG is
## re-seeded so make_mon's auto-move path is identical across runs), start the battle on the
## given battle seed, drive the scripted decisions through the real input machine, and return
## the battle's canonical event stream.
func _det_scn_run(scn: Dictionary, seed_v: int) -> Array:
	seed(4242)                                # make_mon (DVs / auto moves) off the global RNG
	player_party = []
	for spec in scn["party"]:
		player_party.append(make_mon(str(spec[0]), int(spec[1]), spec[2],
			{"hp": 8, "atk": 8, "def": 9, "spd": 10, "spc": 11}))
	player_bag = (scn.get("bag", {}) as Dictionary).duplicate()
	_bag_saved_idx = 0
	_bag_saved_scroll = 0
	pokedex_seen = {}
	pokedex_owned = {}
	battle.det_log = "--verbose" in OS.get_cmdline_user_args()
	battle.next_seed = seed_v
	modal = battle
	if scn.has("wild"):
		pokedex_owned[str(scn["wild"][0])] = true   # skip the new-species dex ceremony
		battle.start(player_party, str(scn["wild"][0]), int(scn["wild"][1]))
	else:
		var edata: Array = []
		for spec in scn["enemy"]:
			edata.append({"species": str(spec[0]), "level": int(spec[1])})
		battle.start_trainer(player_party, edata, "ORACLE", 30)
		battle.ai_kind = str(scn.get("ai", "Generic"))
		battle.ai_mods = scn.get("ai_mods", [])
		battle.ai_count_max = int(scn.get("ai_count", 3))
		battle._ai_uses = battle.ai_count_max
		var eover: Dictionary = scn.get("enemy_moves", {})
		for i in eover:
			var mvs: Array = []
			for mv in eover[i]:
				var pp := int(mon_moves[mv]["pp"])
				mvs.append({"move": mv, "pp": pp, "maxpp": pp})
			battle.enemy_party[int(i)]["moves"] = mvs
	var script: Array = scn["script"]
	var si := 0
	var presses := 0
	while modal == battle and presses < 20000:
		presses += 1
		if battle.state == "menu":
			var tok: Array
			if si < script.size():
				tok = script[si]
			else:                                  # script exhausted: first damaging move with PP
				var mi := 0
				for i in (battle.player_mon["moves"] as Array).size():
					var mv: Dictionary = battle.player_mon["moves"][i]
					if int(mv["pp"]) > 0 and int(mon_moves.get(str(mv["move"]), {}).get("power", 0)) > 0:
						mi = i
						break
				tok = ["m", mi]
			si += 1
			match str(tok[0]):
				"m":
					battle.cursor = 0
					await _press("ui_accept")          # FIGHT
					if battle.state == "moves":
						battle.cursor = clampi(int(tok[1]), 0, (battle.player_mon["moves"] as Array).size() - 1)
						await _press("ui_accept")
						if battle.state == "moves":    # picked a 0-PP move: recover to the menu
							await _press("ui_cancel")
				"s":
					battle.cursor = 1
					await _press("ui_accept")          # PKMN
					if battle.state == "party":
						battle.cursor = clampi(int(tok[1]), 0, player_party.size() - 1)
						await _press("ui_accept")
						if battle.state == "party":    # refused (fainted/active): recover
							await _press("ui_cancel")
				"i":
					battle.cursor = 2
					await _press("ui_accept")          # ITEM
					if battle.state == "item":
						var idx: int = (battle.bag_keys as Array).find(str(tok[1]))
						if idx < 0:
							await _press("ui_cancel")
						else:
							battle.cursor = idx
							await _press("ui_accept")
				"r":
					battle.cursor = 3
					await _press("ui_accept")          # RUN
		elif battle.state == "party_forced":
			battle.cursor = battle._first_usable()
			await _press("ui_accept")
		elif battle.state in ["moves", "party", "item"]:
			await _press("ui_cancel")                  # stray sub-menu: back out
		else:
			await _press("ui_accept")                  # messages / prompts (mimic + learn pick row 0)
	if presses >= 20000:
		print("[battledet]   WARNING: %s press budget hit (battle did not end)" % scn["name"])
	# The catch ceremony (dex + nickname offer) runs after the battle: answer NO and close out.
	var g := 0
	while modal != null and g < 300:
		g += 1
		if modal == menu:
			menu.chosen.emit(1)                        # nickname offer -> NO
			await get_tree().process_frame
		elif modal == naming:
			naming.done.emit("")
			await get_tree().process_frame
		else:
			await _press("ui_accept")
	return (battle.det_stream as Array).duplicate()


func _trainertest() -> void:
	await get_tree().process_frame
	var money0: int = player_money
	start_trainer_battle("OPP_BUG_CATCHER", 1)   # WEEDLE L6 + CATERPIE L6
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://trainer_intro.png")
	print("[trainertest] intro: pic_x=%s has_tex=%s" % [battle.trainer_pic_x, battle.trainer_pic_tex != null])
	for _i in 180:                               # ~3.0 s: "wants to fight!" typing, both ball brackets
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://trainer_fight.png")
	print("[trainertest] wants-to-fight: stage=%s balls=%s" % [battle._intro_stage, battle._intro_pokeballs])
	for _i in 150:                               # ~5.5 s in: trainer slid off, the mon grew in + HUD
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://trainer_sendout.png")
	print("[trainertest] enemy send-out: stage=%s hud=%s" % [battle._intro_stage, battle._intro_enemy_hud])
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	print("[trainertest] %s: enemy_party=%d first=%s state=%s" % [
		battle.trainer_name, battle.enemy_party.size(), battle.enemy_mon["name"], battle.state])
	# gh #140: turbo (hold Space) must fast-forward a battle even when it runs inside a cutscene wrapper
	# (Cutscene.trainer_battle holds cutscene_active true across the whole fight — the old gate killed
	# turbo for every trainer/gym battle). Simulate that condition here (modal == battle already).
	if not InputMap.has_action("p_turbo"):
		InputMap.add_action("p_turbo")
	cutscene_active = true
	Input.action_press("p_turbo")
	await get_tree().process_frame                # _process reads p_turbo -> Engine.time_scale
	var turbo_on: bool = Engine.time_scale == TURBO_SCALE
	Input.action_release("p_turbo")
	cutscene_active = false
	await get_tree().process_frame
	var turbo_off: bool = Engine.time_scale == 1.0
	print("[trainertest] turbo in cutscene-wrapped battle (gh #140): on=%s off_after=%s (expect true/true)" % [
		turbo_on, turbo_off])
	# gh #167: when the opponent switches in an already-damaged mon, the HP bar must show THAT mon's HP.
	battle.enemy_party[1]["hp"] = 4                      # pre-damage the second mon (CATERPIE)
	battle._set_enemy(1)
	var shown_at_switch := int(battle._shown_hp["enemy"])
	var switch_hp_ok: bool = shown_at_switch == 4
	battle._set_enemy(0)                                 # restore for the rest of the test
	print("[trainertest] switch shows new mon HP (gh #167): shown=%d (expect 4) ok=%s" % [
		shown_at_switch, switch_hp_ok])
	get_viewport().get_texture().get_image().save_png("res://trainer1.png")
	# Capture the FIGHT / moves menu, then back out.
	if battle.state == "menu":
		battle.cursor = 0
		await _press("ui_accept")                # FIGHT -> moves menu
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://moves.png")
		print("[trainertest] moves: state=%s" % battle.state)
		await _press("ui_cancel")                # back to the main menu
	# RUN should be blocked in a trainer battle.
	await _press("ui_down"); await _press("ui_down"); await _press("ui_down")
	await _press("ui_accept")                    # RUN
	print("[trainertest] RUN: in_battle=%s (expect true, blocked)" % (modal == battle))
	g = 0
	while battle.state == "msg" and modal == battle and g < 10:
		await _press("ui_accept"); g += 1
	# Fight to a win (FIGHT -> first move, repeat).
	g = 0
	var defeat_shot := false
	while modal == battle and g < 300:
		await _press("ui_accept"); g += 1
		if not defeat_shot and battle.trainer_pic_x <= 113.0:  # trainer pic fully slid in on defeat (#11)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://trainer_defeat.png")
			print("[trainertest] defeat pic_x=%.0f" % battle.trainer_pic_x)
			defeat_shot = true
	print("[trainertest] over: modal_null=%s won=%s money %d->%d" % [
		modal == null, battle.won, money0, player_money])
	get_tree().quit()


func _statustest() -> void:
	await get_tree().process_frame
	start_battle("rattata", 3)
	for _i in 8:                                   # ~0.13s in: the start wipe is mid-blinds (#7)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://battle_wipe.png")
	print("[statustest] intro stage=%s (wipe skipped in tests)" % battle._intro_stage)
	for _i in 47:                                  # ~55 frames in: mid silhouette slide
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intro_silhouette.png")
	print("[statustest] intro stage=%s pback_x=%.0f" % [battle._intro_stage, battle._intro_pback_x])
	for _i in 50:                                  # reveal + pokeballs + enemy HUD
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intro_reveal.png")
	print("[statustest] intro stage=%s pokeballs=%s enemy_hud=%s" % [battle._intro_stage, battle._intro_pokeballs, battle._intro_enemy_hud])
	var w := 0                                     # the "appeared" text (blink + line spacing)
	while battle.state != "msg" and modal == battle and w < 150:
		await get_tree().process_frame; w += 1
	for _i in 45:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intro_text.png")
	var g := 0
	while battle.state != "menu" and modal == battle and g < 300:
		await _press("ui_accept"); g += 1
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intro_menu.png")
	battle.player_mon["moves"] = battle.player_mon["moves"].slice(0, 2)   # force 2 moves to show "-" slots
	battle.state = "moves"; battle.cursor = 0; battle.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intro_moves.png")
	battle.state = "menu"
	battle._intro_player_hud = true; battle._intro_enemy_hud = true   # pose the send-out poof frames + grow
	for bt in [0.02, 0.1, 0.18, 0.26, 0.34, 0.48]:
		battle._intro_stage = "throw"; battle._intro_ball_t = bt; battle.queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://intro_throw_%02d.png" % int(bt * 100))
	battle._intro_stage = ""
	battle.state = "anim"                          # pose a mid-drain: enemy bar part-way down
	battle._shown_hp["enemy"] = float(battle.enemy_mon["maxhp"]) * 0.6
	battle.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://drain.png")
	battle.state = "menu"
	await get_tree().process_frame                 # let the menu settle before driving input
	# 1) Poison residual: enemy poisoned, player uses GROWL (no damage) -> enemy still loses HP.
	battle.enemy_mon["status"] = "psn"
	var e0: int = battle.enemy_mon["hp"]
	await _press("ui_accept"); await _press("ui_down"); await _press("ui_accept")   # GROWL
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	print("[statustest] poison: enemy hp %d->%d (residual=%d, >=1 expected)" % [e0, battle.enemy_mon["hp"], e0 - battle.enemy_mon["hp"]])
	# 2) Sleep: player asleep -> its move does nothing; sleep counter ticks down.
	battle.enemy_mon["status"] = ""
	battle.player_mon["status"] = "slp"; battle.player_mon["sleep"] = 2
	var e1: int = battle.enemy_mon["hp"]
	await _press("ui_accept"); await _press("ui_accept")                             # SCRATCH (asleep)
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	print("[statustest] sleep: enemy hp %d->%d (expect equal), sleep now %d (expect 1)" % [e1, battle.enemy_mon["hp"], battle.player_mon["sleep"]])
	# 3) Paralysis quarters Speed (turn order) — applied to the STORED stat at infliction.
	battle.player_mon["status"] = ""; battle.player_mon["sleep"] = 0   # still asleep from leg 2
	battle._apply_status(battle.player_mon, "par", [])
	print("[statustest] paralysis: spd %d -> eff %d (expect ~1/4)" % [battle.player_mon["spd"], battle._eff_speed(true)])
	battle.queue_redraw()
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://status1.png")
	battle.state = "levelstats"                    # pose the level-up stats box
	battle._level_stats = {"atk": 12, "def": 11, "spd": 15, "spc": 11}
	battle.msg = "CHARMANDER grew to\nlevel 8!"
	battle.revealed = 999
	battle.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://levelup.png")
	battle._faint_who = "enemy"                    # pose the enemy pic mid-faint-slide
	battle._faint_t = 0.45
	battle.enemy_mon["hp"] = 0
	battle.state = "anim"
	battle.queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://faint.png")
	get_tree().quit()


func _resttest() -> void:
	await get_tree().process_frame
	start_battle("rattata", 3)
	var b = battle
	var p: Dictionary = b.player_mon
	p["hp"] = int(p["maxhp"]) - 1
	p["status"] = ""; p["sleep"] = 0
	b._shown_status["player"] = ""
	var msgs: Array = []
	var rest_accuracy: int = int(b.moves_db["REST"]["accuracy"])
	b.moves_db["REST"]["accuracy"] = 0                 # avoid Gen-1's 1/256 accuracy miss in this test
	b._do_move(p, b.enemy_mon, "REST", msgs, b.p_stages, b.e_stages, true)
	b.moves_db["REST"]["accuracy"] = rest_accuracy
	var marker_idx := -1
	for i in msgs.size():
		var item = msgs[i]
		if item is Dictionary and item.get("status") == "player":
			marker_idx = i
			break
	var status_lag: bool = str(p["status"]) == "slp" and str(b._shown_status["player"]) == ""
	var marker_after_message: bool = marker_idx > 0 and msgs[marker_idx - 1] is String \
		and str(msgs[marker_idx - 1]).contains("started\nsleeping")
	assert(status_lag)
	assert(marker_after_message)
	b._say(msgs, "menu")
	var guard := 0
	while b.state == "msg" and guard < 20:
		b._next_msg()
		guard += 1
	var badge_after: String = str(b._shown_status["player"])
	assert(b.state == "menu")
	assert(badge_after == "slp")
	print("[resttest] status_lag=%s badge_after=%s marker_after_message=%s" % [
		status_lag, badge_after, marker_after_message])
	get_tree().quit()


func _flymovetest() -> void:
	await get_tree().process_frame
	battle.fast_hp = true
	player_party = [make_mon("pidgeot", 40, ["FLY", "GUST"])]
	start_battle("rattata", 10)
	var b = battle
	var p: Dictionary = b.player_mon
	var e: Dictionary = b.enemy_mon
	e["moves"] = [{"move": "TACKLE", "pp": 35, "maxpp": 35}]
	var fly_idx := -1
	for i in (p["moves"] as Array).size():
		if str(p["moves"][i]["move"]) == "FLY":
			fly_idx = i
			break
	assert(fly_idx >= 0, "fly move test requires FLY in the player's move set")
	var fly_slot: Dictionary = p["moves"][fly_idx]
	var pp_before: int = int(fly_slot["pp"])
	var player_hp_before: int = int(p["hp"])
	var fly_accuracy: int = int(b.moves_db["FLY"]["accuracy"])
	var tackle_accuracy: int = int(b.moves_db["TACKLE"]["accuracy"])
	b.moves_db["FLY"]["accuracy"] = 0               # deterministic turn-2 hit; charge behavior is unchanged
	b.moves_db["TACKLE"]["accuracy"] = 0            # deterministic hit if semi-invulnerability regresses
	b._resolve({"kind": "move", "idx": fly_idx})
	b.moves_db["TACKLE"]["accuracy"] = tackle_accuracy
	var charged: bool = str(b.p_vol["charging"]) == "FLY"
	var attack_missed: bool = str(b.msg).contains("attack missed")
	var present_guard := 0
	while not bool(b._pic_gone["player"]) and b.state == "msg" and present_guard < 10:
		b._next_msg()
		attack_missed = attack_missed or str(b.msg).contains("attack missed")
		present_guard += 1
	var vanished: bool = bool(b._pic_gone["player"])
	for item in b.queue:
		if item is String and str(item).contains("attack missed"):
			attack_missed = true
	attack_missed = attack_missed and int(p["hp"]) == player_hp_before
	var enemy_hp_before: int = int(e["hp"])
	b._resolve({"kind": "forced", "move": "FLY"})
	var fly_hit: bool = int(e["hp"]) < enemy_hp_before and str(b.p_vol["charging"]) == ""
	var pp_spent_once: bool = int(fly_slot["pp"]) == pp_before - 1
	b.moves_db["FLY"]["accuracy"] = fly_accuracy

	# SwiftEffect skips MoveHitTest's INVULNERABLE check and must connect during the charge turn.
	start_battle("rattata", 10)
	b = battle
	p = b.player_mon
	e = b.enemy_mon
	e["moves"] = [{"move": "SWIFT", "pp": 20, "maxpp": 20}]
	fly_idx = -1
	for i in (p["moves"] as Array).size():
		if str(p["moves"][i]["move"]) == "FLY":
			fly_idx = i
			break
	var swift_hp_before: int = int(p["hp"])
	b._resolve({"kind": "move", "idx": fly_idx})
	var swift_hit: bool = str(b.p_vol["charging"]) == "FLY" and int(p["hp"]) < swift_hp_before

	assert(charged and vanished, "FLY turn 1 should charge and make the player's pic vanish")
	assert(attack_missed, "ordinary attacks should miss a semi-invulnerable FLY user")
	assert(fly_hit, "FLY should deal damage on turn 2")
	assert(pp_spent_once, "FLY should spend exactly one PP across both turns")
	assert(swift_hit, "SWIFT should hit a semi-invulnerable FLY user")
	print("[flymovetest] charged=%s attack_missed=%s fly_hit=%s pp_spent_once=%s swift_hit=%s" % [
		charged and vanished, attack_missed, fly_hit, pp_spent_once, swift_hit])
	get_tree().quit()


func _movefxtest() -> void:
	await get_tree().process_frame
	start_battle("rattata", 3)
	var b = battle
	var P: Dictionary = b.player_mon
	var E: Dictionary = b.enemy_mon
	var em: int = E["maxhp"]
	var ms: Array = []

	E["hp"] = em; b._do_move(P, E, "DRAGON_RAGE", ms, b.p_stages, b.e_stages, true)
	print("[movefx] DRAGON_RAGE dealt %d (expect %d)" % [em - int(E["hp"]), min(40, em)])
	E["hp"] = em; b._do_move(P, E, "SEISMIC_TOSS", ms, b.p_stages, b.e_stages, true)
	print("[movefx] SEISMIC_TOSS dealt %d (expect player L %d)" % [em - int(E["hp"]), int(P["level"])])
	# gh #176 phase 2: the type multiplier composes per TypeEffects TABLE ENTRY — a pure-type
	# defender (stored TYPE,TYPE) matches once, never squared.
	var te_ok: bool = b._type_eff("FIRE", ["GRASS", "GRASS"]) == 2.0 \
		and b._type_eff("FIRE", ["GRASS", "POISON"]) == 2.0 \
		and b._type_eff("WATER", ["FIRE", "ROCK"]) == 4.0 \
		and b._type_eff("ELECTRIC", ["GROUND", "GROUND"]) == 0.0 \
		and b._type_eff("NORMAL", ["GHOST", "GHOST"]) == 0.0
	print("[movefx] type_eff per-entry (gh#176): pure_2x=%s dual_4x=%s immune=%s ALL=%s" % [
		b._type_eff("FIRE", ["GRASS", "GRASS"]) == 2.0,
		b._type_eff("WATER", ["FIRE", "ROCK"]) == 4.0,
		b._type_eff("ELECTRIC", ["GROUND", "GROUND"]) == 0.0, te_ok])
	# gh #181: NIGHT SHADE has base power 0 yet damages — the effect, not the power byte, picks
	# the path. And the Gen-1 quirk holds: fixed damage still obeys type IMMUNITY.
	E["hp"] = em; E["types"] = ["POISON", "POISON"]
	ms = []; b._do_move(P, E, "NIGHT_SHADE", ms, b.p_stages, b.e_stages, true)
	print("[movefx] NIGHT_SHADE dealt %d (expect player L %d)" % [em - int(E["hp"]), int(P["level"])])
	E["hp"] = em; E["types"] = ["NORMAL", "NORMAL"]
	ms = []; b._do_move(P, E, "NIGHT_SHADE", ms, b.p_stages, b.e_stages, true)
	print("[movefx] NIGHT_SHADE vs NORMAL dealt %d (expect 0 — Gen-1 immunity)" % [em - int(E["hp"])])
	# gh #185: Gen-1 CONVERSION copies the DEFENDER's types onto the user (ConversionEffect_,
	# not Gen 2's own-first-move version) and fails against a dug/flown target (INVULNERABLE).
	E["types"] = ["POISON", "FLYING"]
	P["types"] = ["NORMAL", "NORMAL"]
	ms = []; b._do_move(P, E, "CONVERSION", ms, b.p_stages, b.e_stages, true)
	var conv_ok: bool = P["types"] == ["POISON", "FLYING"] and str(ms[-1]).ends_with("'s!")
	b.e_vol["charging"] = "FLY"
	P["types"] = ["NORMAL", "NORMAL"]
	ms = []; b._do_move(P, E, "CONVERSION", ms, b.p_stages, b.e_stages, true)
	var conv_fail: bool = P["types"] == ["NORMAL", "NORMAL"] and str(ms[-1]) == "But it failed!"
	b.e_vol["charging"] = ""
	E["types"] = ["NORMAL", "NORMAL"]
	print("[movefx] CONVERSION (gh#185): copies_defender=%s fails_vs_invulnerable=%s" % [
		conv_ok, conv_fail])

	# SUBSTITUTE (gh #20): Gen-1 exact — sub HP = maxhp/4, re-use fails, damage-equal leaves a
	# 0-HP sub standing, any further hit pops it, and exactly-quarter HP self-KOs.
	P["maxhp"] = 40; P["hp"] = 40; b.p_vol = b._new_vol()
	ms = []; b._do_move(P, E, "SUBSTITUTE", ms, b.p_stages, b.e_stages, true)
	print("[movefx] SUB create: sub=%d (expect 10) hp=%d (expect 30) up=%s" % [
		int(b.p_vol["sub"]), int(P["hp"]), b.p_vol["sub_up"]])
	ms = []; b._do_move(P, E, "SUBSTITUTE", ms, b.p_stages, b.e_stages, true)
	print("[movefx] SUB re-use: hp=%d (expect 30, refused) msg=%s" % [int(P["hp"]), str(ms[-1]).left(24)])
	ms = []; b._deal(P, b.p_vol, 10, ms)
	var zero_up: bool = b.p_vol["sub_up"] and int(b.p_vol["sub"]) == 0
	ms = []; b._deal(P, b.p_vol, 1, ms)
	var popped: bool = not b.p_vol["sub_up"] and int(P["hp"]) == 30
	print("[movefx] SUB damage: zero_hp_sub_stands=%s next_hit_pops=%s" % [zero_up, popped])
	P["hp"] = 9; ms = []; b._do_move(P, E, "SUBSTITUTE", ms, b.p_stages, b.e_stages, true)
	var too_weak: bool = not b.p_vol["sub_up"] and int(P["hp"]) == 9
	P["hp"] = 10; ms = []; b._do_move(P, E, "SUBSTITUTE", ms, b.p_stages, b.e_stages, true)
	print("[movefx] SUB edges: too_weak_at_9=%s self_ko_at_10: hp=%d (expect 0) up=%s" % [
		too_weak, int(P["hp"]), b.p_vol["sub_up"]])
	P["hp"] = 40; b.p_vol = b._new_vol()
	E["hp"] = em; b._do_move(P, E, "SUPER_FANG", ms, b.p_stages, b.e_stages, true)
	print("[movefx] SUPER_FANG -> enemy hp %d (expect ~%d)" % [int(E["hp"]), int(em / 2)])
	P["hp"] = 1; E["hp"] = em; b._do_move(P, E, "ABSORB", ms, b.p_stages, b.e_stages, true)
	print("[movefx] ABSORB drained -> player hp %d (expect > 1)" % int(P["hp"]))
	P["hp"] = int(P["maxhp"]); E["hp"] = em; b._do_move(P, E, "DOUBLE_EDGE", ms, b.p_stages, b.e_stages, true)
	print("[movefx] DOUBLE_EDGE recoil -> player hp %d / %d" % [int(P["hp"]), int(P["maxhp"])])
	E["hp"] = em; b.e_vol["leech"] = false; b._do_move(P, E, "LEECH_SEED", ms, b.p_stages, b.e_stages, true)
	print("[movefx] LEECH_SEED -> seeded=%s" % b.e_vol["leech"])
	P["hp"] = 1; b._do_move(P, E, "RECOVER", ms, b.p_stages, b.e_stages, true)
	print("[movefx] RECOVER -> player hp %d (expect ~%d)" % [int(P["hp"]), int(int(P["maxhp"]) / 2)])
	E["hp"] = em; b.e_vol["confuse"] = 0; b._confuse(E, b.e_vol, ms)
	print("[movefx] CONFUSE -> enemy confuse turns=%d" % int(b.e_vol["confuse"]))
	# RAGE (HandleBuildingRage): locks the user in, and its ATTACK climbs when hit.
	b.p_vol = b._new_vol(); b.p_stages = {"atk": 0, "def": 0, "spd": 0, "spc": 0, "acc": 0, "eva": 0}
	ms = []; E["hp"] = em; b._do_move(P, E, "RAGE", ms, b.p_stages, b.e_stages, true)
	var rage_lock: bool = b.p_vol["raging"] and b._forced_move(b.p_vol) == "RAGE"
	P["hp"] = int(P["maxhp"])
	ms = []; b._do_move(E, P, "TACKLE", ms, b.e_stages, b.p_stages, false)
	var built: bool = int(b.p_stages["atk"]) == 1 and str(ms[-1]).contains("RAGE is building")
	print("[movefx] RAGE: locked=%s atk_built=%s (expect true true)" % [rage_lock, built])
	# Stat experience: a KO feeds the enemy's raw base stats into each participant's pool
	# (GainExperience), and CalcStat's sqrt term folds it into the stats.
	b.participants = [0]
	var pre_se: int = int(P.get("sexp", {}).get("atk", 0))
	var ms2: Array = []
	b._award_exp(ms2)
	print("[movefx] stat exp: atk pool +%d (expect enemy base atk %d)" % [
		int(P["sexp"]["atk"]) - pre_se, int(E["base"]["atk"])])
	print("[movefx] CalcStat sexp term: %d -> %d (expect 27 -> 40)" % [
		stat(48, 20, 8, false), stat(48, 20, 8, false, 65535)])
	# gh #176 phase 2: exp boosts (BoostExp x1.5) — a trainer battle and a traded (foreign-OT)
	# mon each multiply the award, and they STACK; the amount floors (be/N)*L/7 before boosting.
	b.participants = [0]
	var lvl: int = int(E["level"])
	var raw: int = int(int(E["base_exp"]) / 1) * lvl / 7
	P["ot"] = player_name; b.is_trainer = false; P["exp"] = 0
	var ms3: Array = []; b._award_exp(ms3)
	var wild_gain: int = int(P["exp"])
	b.is_trainer = true; P["exp"] = 0
	ms3 = []; b._award_exp(ms3)
	var trainer_gain: int = int(P["exp"])
	P["ot"] = "TRAINER"; P["exp"] = 0
	ms3 = []; b._award_exp(ms3)
	var both_gain: int = int(P["exp"])
	b.is_trainer = false; P["ot"] = player_name
	print("[movefx] exp boosts: wild=%d (expect %d) trainer=%d (expect %d) traded+trainer=%d (expect %d)" % [
		wild_gain, raw, trainer_gain, raw + int(raw / 2),
		both_gain, (raw + int(raw / 2)) + int((raw + int(raw / 2)) / 2)])
	# stat exp divides by the mons gaining exp and halves under EXP.ALL (core.asm's halve then
	# DivideExpDataByNumMonsGainingExp): floor(base/2) then /2 for two participants.
	var probe: Dictionary = {"sexp": {"hp": 0, "atk": 0, "def": 0, "spd": 0, "spc": 0}}
	b._gain_stat_exp(probe, 2, true)
	print("[movefx] stat exp /N +halve: atk +%d (expect %d)" % [
		int(probe["sexp"]["atk"]), int(int(E["base"]["atk"]) >> 1) / 2])
	# ItemUseBall: MASTER always captures; a sleeping full-catch-rate mon underflows often.
	var mb: Dictionary = b._attempt_catch("MASTER BALL")
	print("[movefx] MASTER BALL: caught=%s (expect true)" % mb["caught"])
	# ItemUseBall wobbles (gh #176): X = min(W,255) on EITHER failure path. Rate 45 at full
	# HP 120/120 with a GREAT BALL: W = (120*255/8)/30 = 127, Y = 45*100/200 = 22, so EVERY
	# failure lands Z = 127*22/255 = 10 -> exactly 1 shake (the old rate-as-X path gave 0).
	E["maxhp"] = 120; E["hp"] = 120; E["status"] = ""
	var wob := {}
	var wob_fails := 0
	for i in 400:
		var wr: Dictionary = b._attempt_catch("GREAT BALL", 45)
		if not bool(wr["caught"]):
			wob_fails += 1
			wob[int(wr["shakes"])] = int(wob.get(int(wr["shakes"]), 0)) + 1
	print("[movefx] GREAT BALL wobbles @rate45 fullHP: fails=%d spread=%s (expect all 1s)" % [
		wob_fails, wob])
	# gh #176 phase 2 — status machinery + the STORED stat pipeline (p_mod/e_mod):
	b.p_stages = b._new_stages()             # the RAGE leg above left atk at +1
	badges = []
	b._rebuild_mod_stats(true)
	# (a) paralysis quarters the STORED speed in place; a SPEED stage recalc rebuilds from
	# the unmodified stat WITHOUT it (AGILITY cures the slowness) — and (a2) the trailer of
	# an ENEMY stat-down re-quarters it (the compounding glitch).
	var spd_base: int = int(P["spd"])
	var ms4: Array = []
	b._apply_status(P, "par", ms4)
	var s_pen: int = b._eff_speed(true)
	b._change_stage(P, b.p_stages, "SPEED", 1, ms4)
	var s_wiped: int = b._eff_speed(true)
	var s_15: int = b._stage_apply(spd_base, 1)
	b._change_stage(P, b.p_stages, "ATTACK", -1, ms4)   # an enemy Growl: the trailer re-penalizes
	var s_comp: int = b._eff_speed(true)
	print("[movefx] par quirk: eff %d (expect %d = spd/4) -> AGILITY -> %d (expect %d) -> foe's GROWL -> %d (expect %d, compounded)" % [
		s_pen, maxi(1, spd_base / 4), s_wiped, s_15, s_comp, maxi(1, s_15 / 4)])
	P["status"] = ""
	b.p_stages = b._new_stages()
	b._rebuild_mod_stats(true)
	# (b) burn halves the STORED attack — visible through the confusion self-hit (power 40,
	# stored atk vs own stored def, integer chain) — until an ATTACK stage recalc drops it.
	# (CHARMANDER is FIRE — burn-immune — so borrow neutral types for the leg.)
	var fire_types: Array = P["types"]
	P["types"] = ["NORMAL", "NORMAL"]
	b._apply_status(P, "brn", ms4)
	P["types"] = fire_types
	var cd_burn: int = b._confusion_self_damage(P, b.p_vol)
	var a_h: int = maxi(1, int(P["atk"]) / 2)
	var exp_burn: int = mini(int(int((2 * int(P["level"])) / 5 + 2) * 40 * a_h / maxi(1, int(P["def"]))) / 50, 997) + 2
	b._change_stage(P, b.p_stages, "ATTACK", 1, ms4)    # the recalc wipes the halve
	var cd_free: int = b._confusion_self_damage(P, b.p_vol)
	var a_15: int = b._stage_apply(int(P["atk"]), 1)
	var exp_free: int = mini(int(int((2 * int(P["level"])) / 5 + 2) * 40 * a_15 / maxi(1, int(P["def"]))) / 50, 997) + 2
	print("[movefx] confusion self-hit: burned=%d (expect %d) after SWORDS DANCE=%d (expect %d, halve gone)" % [
		cd_burn, exp_burn, cd_free, exp_free])
	P["status"] = ""
	b.p_stages = b._new_stages()
	b._rebuild_mod_stats(true)
	# (c) the Leech Seed glitch: the toxic counter multiplies (and advances) on the leech
	# drain too — psn tick base*1 (counter->2), leech drain base*2 (counter->3).
	P["status"] = "psn"; P["hp"] = P["maxhp"]
	b.p_vol["toxic"] = 1; b.p_vol["leech"] = true
	E["hp"] = 10
	var ms5: Array = []
	b._residual(P, b.p_vol, E, ms5)
	var rbase: int = maxi(1, int(P["maxhp"]) / 16)
	print("[movefx] leech+toxic glitch: lost=%d (expect %d) enemy_healed=%d (expect %d) counter=%d (expect 3)" % [
		int(P["maxhp"]) - int(P["hp"]), rbase * 3, int(E["hp"]) - 10, rbase * 2, int(b.p_vol["toxic"])])
	b.p_vol["leech"] = false; b.p_vol["toxic"] = 0; P["hp"] = P["maxhp"]
	# (d) check order: a sleeping mon never reaches the flinch check — sleep ticks first.
	P["status"] = "slp"; P["sleep"] = 2; b.p_vol["flinch"] = true
	var ms6: Array = []
	var acted: bool = b._can_act(P, b.p_vol, b.e_vol, ms6)
	print("[movefx] sleep-before-flinch: acted=%s (expect false) sleep=%d (expect 1) msg=%s (expect asleep)" % [
		acted, int(P["sleep"]), str(ms6[-1]).replace("\n", " ")])
	b.p_vol["flinch"] = false; P["status"] = ""; P["sleep"] = 0
	# (e) .MonHurtItselfOrFullyParalysed: an interrupted FLY abandons the charge and a held
	# opponent goes free (the hold lives on the attacker's USING_TRAPPING_MOVE bit).
	b.p_vol["charging"] = "FLY"; b.p_vol["bind"] = 2; b.e_vol["bound"] = 2
	b._break_locks(b.p_vol, b.e_vol, ms6)
	print("[movefx] break locks: charging='%s' (expect '') bind=%d bound=%d (expect 0 0)" % [
		str(b.p_vol["charging"]), int(b.p_vol["bind"]), int(b.e_vol["bound"])])
	# gh #176 phase 2 — trainer AI: AIGetTypeEffectiveness reads only the FIRST matching
	# TypeEffects entry (ELECTRIC into WATER/FLYING reads 2x, the damage engine composes 4x);
	# and the AI item budget: items spend a use, switches never do (SwitchEnemyMon skips
	# DecrementAICount), and a maxed X item still costs its use and the turn.
	var p_types_save: Array = P["types"]
	P["types"] = ["WATER", "FLYING"]
	var ai_first: float = b._ai_eff("THUNDERBOLT")
	var real_eff: float = b._type_eff("ELECTRIC", P["types"])
	b.is_trainer = true
	b.enemy_party = [E, make_mon("rattata", 3, [])]
	b.enemy_active = 0
	b.trainer_name = "TESTER"
	b._ai_uses = 3
	var ms7: Array = []
	b._ai_switch(ms7)
	var uses_after_switch: int = b._ai_uses
	b.e_stages["atk"] = 6
	b._ai_x_item("atk", "X ATTACK", ms7)
	var uses_after_maxed_x: int = b._ai_uses
	b.e_stages["atk"] = 0
	b.is_trainer = false
	P["types"] = p_types_save
	print("[movefx] AI: first_match=%.1f (expect 2.0; real %.1f) switch_free=%s (expect 3) maxed_x_spends=%s (expect 2)" % [
		ai_first, real_eff, uses_after_switch, uses_after_maxed_x])
	# gh #176 phase 2 — badges by BIT position: THUNDER boosts DEFENSE (bit 2), and the stat-
	# move trailer REAPPLIES boosts to every stored stat, stacking them (the badge glitch).
	badges = ["THUNDERBADGE"]
	b._rebuild_mod_stats(true)
	var def_once: int = int(b.p_mod["def"])
	var d0: int = int(P["def"])
	var ms9: Array = []
	b._change_stage(P, b.p_stages, "ATTACK", 1, ms9)     # any player stage change reapplies all
	var def_twice: int = int(b.p_mod["def"])
	print("[movefx] badge: THUNDER->def %d (expect %d) restack -> %d (expect %d) spd_unboosted=%s" % [
		def_once, d0 + (d0 >> 3), def_twice, def_once + (def_once >> 3),
		int(b.p_mod["spd"]) == int(P["spd"])])
	badges = []
	b.p_stages = b._new_stages()
	b._rebuild_mod_stats(true)
	# Vitamins: PROTEIN feeds 2560 atk stat exp and recalcs immediately; the 25600 cap refuses.
	player_bag = {"PROTEIN": 12}
	selected_item = "PROTEIN"
	P["sexp"] = {"hp": 0, "atk": 0, "def": 0, "spd": 0, "spc": 0}
	var atk0: int = int(P["atk"])
	for i in 10:
		_bag_use_on(0)
	var capped_atk: int = int(P.get("sexp", {}).get("atk", 0))
	_bag_use_on(0)                                        # the 11th: at 25600, refused
	print("[movefx] PROTEIN x10: atk %d->%d sexp=%d (expect 25600) refused_kept=%s" % [
		atk0, int(P["atk"]), capped_atk, int(player_bag.get("PROTEIN", 0)) == 2])
	# ETHER restores a technique 10 PP; PP UP raises its max thrice then refuses; MAX ELIXER fills all.
	player_bag = {"ETHER": 1, "PP UP": 4, "MAX ELIXER": 1}
	P["moves"][0]["pp"] = 0
	selected_item = "ETHER"; _bag_target_idx = 0
	_bag_use_on_move(0)
	var eth_ok: bool = int(P["moves"][0]["pp"]) == 10
	selected_item = "PP UP"
	var mp0: int = int(P["moves"][0]["maxpp"])
	_bag_use_on_move(0); _bag_use_on_move(0); _bag_use_on_move(0)
	var mp3: int = int(P["moves"][0]["maxpp"])
	_bag_use_on_move(0)                                   # the 4th: maxed out, bottle kept
	print("[movefx] ETHER +10=%s | PP UP x3: max %d->%d (expect 35->56) fourth_kept=%s" % [
		eth_ok, mp0, mp3, int(player_bag.get("PP UP", 0)) == 1])
	selected_item = "MAX ELIXER"
	P["moves"][0]["pp"] = 1
	_bag_use_on(0)
	print("[movefx] MAX ELIXER: pp=%d/%d (expect full)" % [
		int(P["moves"][0]["pp"]), int(P["moves"][0]["maxpp"])])
	# RARE CANDY runs the full pipeline now: learnset move + evolution (both were skipped).
	var rc: Dictionary = make_mon("rattata", 13, ["TACKLE"])
	player_party = [rc]
	player_bag = {"RARE CANDY": 2}
	selected_item = "RARE CANDY"
	_bag_use_on(0)
	for i in 40:
		if modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
	var learned_hf := false
	for mv in rc["moves"]:
		learned_hf = learned_hf or str(mv["move"]) == "HYPER_FANG"
	rc["level"] = 19
	_bag_use_on(0)
	for i in 40:
		if modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
	print("[movefx] RARE CANDY: L14 learned HYPER FANG=%s | L20 species=%s (expect true raticate)" % [
		learned_hf, str(rc["species"])])
	# Evolution: Charmander -> Charmeleon at L16, through the full sequence (gh #67).
	P["level"] = 16
	var evo_state := [false]
	var evo_runner := func() -> void:
		await run_evolution(P, "CHARMELEON")
		evo_state[0] = true
	evo_runner.call()
	for i in 60:
		if evo_state[0]:
			break
		if modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
	print("[movefx] EVOLVE at L16 -> species=%s sequence_done=%s (expect charmeleon true)" % [
		str(P["species"]), evo_state[0]])
	# gh #58: SELECT in the FIGHT menu reorders moves — move + PP together, in the party dict.
	b.player_mon["moves"] = [{"move": "TACKLE", "pp": 3, "maxpp": 35},
		{"move": "GROWL", "pp": 7, "maxpp": 40}]
	b.state = "moves"; b.cursor = 0
	b._swap_moves()                                       # hold row 0
	var mv_held: bool = b._move_swap == 0
	b.cursor = 1
	b._swap_moves()                                       # swap rows 0 <-> 1
	var bm: Array = b.player_mon["moves"]
	var pm: Array = b.party[b.active]["moves"]
	print("[movefx] move swap: held=%s first=%s pp=%d party_shared=%s deselected=%s (expect true GROWL 7 true true)" % [
		mv_held, str(bm[0]["move"]), int(bm[0]["pp"]),
		str(pm[0]["move"]) == "GROWL", b._move_swap == -1])
	# gh #57: the battle bag is an ITEMLISTMENU too — SELECT reorders the real bag.
	player_bag = {"POTION": 1, "ANTIDOTE": 2}
	b.bag_keys = player_bag.keys()
	b.state = "item"; b.cursor = 0
	b._swap_bag_items()                                   # hold row 0
	b.cursor = 1
	b._swap_bag_items()                                   # swap rows 0 <-> 1
	print("[movefx] battle bag swap: first=%s x%d (expect ANTIDOTE x2)" % [
		str(player_bag.keys()[0]), int(player_bag[player_bag.keys()[0]])])
	# gh #62: Transform/Mimic write a battle-only copy — the party data reverts on exit.
	var tp: Dictionary = b.player_mon
	var real_moves: Array = tp["moves"]
	var real_atk: int = int(tp["atk"])
	ms = []; b._do_move(tp, E, "TRANSFORM", ms, b.p_stages, b.e_stages, true)
	var t_copy: bool = not is_same(tp["moves"], real_moves) and b.p_vol.has("transform_backup") \
		and int(tp["atk"]) == int(E["atk"])
	b._revert_battle_copy(tp, b.p_vol)
	var t_revert: bool = is_same(tp["moves"], real_moves) and int(tp["atk"]) == real_atk
	print("[movefx] transform: battle_copy=%s reverted=%s (expect true true)" % [t_copy, t_revert])
	tp["moves"] = [{"move": "MIMIC", "pp": 10, "maxpp": 16}, {"move": "GROWL", "pp": 7, "maxpp": 40}]
	real_moves = tp["moves"]
	ms = []; b._do_move(tp, E, "MIMIC", ms, b.p_stages, b.e_stages, true)
	# The player's mimic queues a pick of the target's moves (gh #65); drive it directly.
	var mk: Dictionary = {}
	for it in ms:
		if it is Dictionary and it.has("mimic_pick"):
			mk = it
	var pick_ok: bool = not mk.is_empty() and not is_same(tp["moves"], real_moves)
	b._mimic_moves = mk.get("mimic_pick", ["TACKLE"])
	b._mimic_slot = int(mk.get("slot", 0))
	b.queue = []; b.cursor = 0
	b._mimic_choose()                                     # pick the target's first move
	var m_copy: bool = str(tp["moves"][0]["move"]) != "MIMIC" \
		and int(tp["moves"][0]["pp"]) == 10               # MIMIC's slot keeps its PP (MimicEffect)
	tp["moves"][0]["pp"] = 3                              # spend PP on the mimicked move
	b._revert_battle_copy(tp, b.p_vol)
	var m_revert: bool = is_same(tp["moves"], real_moves) and str(tp["moves"][0]["move"]) == "MIMIC" \
		and int(tp["moves"][0]["pp"]) == 3                # the drain reached the party slot
	print("[movefx] mimic: pick_menu=%s slot0_copy=%s revert_with_pp_drain=%s (expect true true true)" % [
		pick_ok, m_copy, m_revert])
	# gh #75: POISON_SIDE_EFFECT1 poisons at 52/256 (PoisonEffect "20 percent + 1").
	tp["moves"] = [{"move": "POISON_STING", "pp": 35, "maxpp": 35}]
	var poisons := 0
	for i in 400:
		E["status"] = ""; E["hp"] = int(E["maxhp"])
		ms = []
		b._do_move(tp, E, "POISON_STING", ms, b.p_stages, b.e_stages, true)
		if str(E["status"]) == "psn":
			poisons += 1
	print("[movefx] POISON STING: %d/400 poisoned (expect ~81, 52/256; >45 required)=%s" % [
		poisons, poisons > 45 and poisons < 130])
	# FreezeBurnParalyzeEffect: BODY SLAM can't paralyze a NORMAL-type (shared move type).
	var pars := 0
	for i in 200:
		E["status"] = ""; E["hp"] = int(E["maxhp"])
		ms = []
		b._do_move(tp, E, "BODY_SLAM", ms, b.p_stages, b.e_stages, true)
		if str(E["status"]) == "par":
			pars += 1
	print("[movefx] BODY SLAM vs NORMAL-type: %d/200 paralyzed (expect 0)" % pars)
	# gh #74: a faint-forced switch resets stat stages and volatiles (and joins the exp split).
	b.party = [b.player_mon, make_mon("pidgey", 10, ["TACKLE"])]
	b.active = 0
	b.p_stages["acc"] = -2
	b.p_vol["confuse"] = 3
	b.state = "party_forced"
	b.cursor = 1
	b._choose_party()
	print("[movefx] faint-switch reset: acc=%d confuse=%d active=%d participant=%s (expect 0 0 1 true)" % [
		int(b.p_stages["acc"]), int(b.p_vol["confuse"]), b.active, b.participants.has(1)])
	# gh #72: a voluntary switch queues the recall + throw animation markers.
	b.active = 0
	b.player_mon = b.party[0]
	ms = []
	b._player_act({"kind": "switch", "idx": 1}, ms)
	var mk_recall := false
	var mk_send := false
	for it in ms:
		if it is Dictionary and it.has("recall"):
			mk_recall = true
		if it is Dictionary and it.has("send_player"):
			mk_send = true
	print("[movefx] switch anim markers: recall=%s send=%s (expect true true)" % [mk_recall, mk_send])
	get_tree().quit()


## Screen transitions: runs each battle wipe over the live overworld, screenshotting mid-effect,
## and checks the transition pick + the warp fade. fast_hp is forced off so the wipes run.
func _wipetest() -> void:
	await get_tree().process_frame
	battle.fast_hp = false
	print("[wipetest] pick outdoors: wild=%s strong-wild=%s trainer=%s strong-trainer=%s" % [
		_battle_transition_kind(3, false), _battle_transition_kind(99, false),
		_battle_transition_kind(3, true), _battle_transition_kind(99, true)])
	center_label = "ViridianForest"                # a dungeon map (dungeon_maps.json)
	print("[wipetest] pick dungeon: wild=%s strong-wild=%s trainer=%s strong-trainer=%s in_list=%s" % [
		_battle_transition_kind(3, false), _battle_transition_kind(99, false),
		_battle_transition_kind(3, true), _battle_transition_kind(99, true),
		"ViridianForest" in dungeon_maps])
	center_label = "PalletTown"
	# [kind, seconds into the effect to screenshot (the circles flash for ~1.2 s first)]
	for probe in [["double_circle", 1.45], ["spiral_out", 1.0], ["spiral_in", 1.3],
			["h_stripes", 0.5], ["shrink", 0.45], ["split", 0.45]]:
		var kind := str(probe[0])
		_wipe_shot(kind, float(probe[1]))            # side task: screenshot mid-effect
		var t0 := Time.get_ticks_msec()
		await transition.battle_wipe(kind)
		print("[wipetest] %s: done in %d ms" % [kind, Time.get_ticks_msec() - t0])
		transition.clear()
		await get_tree().process_frame
	# The circle sweep must consume every tile, including the 4 at the pivot that the GB
	# left to its final whole-palette blackout.
	transition.visible = true
	transition._reset()
	await transition._circle(true)
	var holes := 0
	for c in transition._cells:
		if not c:
			holes += 1
	print("[wipetest] double_circle coverage: %d unpainted tiles (expect 0)" % holes)
	transition.clear()
	transition.fade_black()                        # the warp fade (GBFadeOutToBlack)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://wipe_fade.png")
	var g2 := 0
	while not transition._hold and g2 < 120:
		await get_tree().process_frame; g2 += 1
	print("[wipetest] fade_black: held=%s" % str(transition._hold))
	transition.clear()
	transition.battle_exit()                       # the exit fade (GBFadeInFromWhite)
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://wipe_exit.png")
	var g3 := 0
	while transition.visible and g3 < 120:
		await get_tree().process_frame; g3 += 1
	print("[wipetest] battle_exit: cleared=%s" % str(not transition.visible))
	get_tree().quit()


## The Route 11/15 gate aides: refused under the dex count, granted at/above it.
func _aidetest() -> void:
	await get_tree().process_frame
	load_world("Route11Gate2F")
	await get_tree().process_frame
	player.place(Vector2i(3, 6), true); player.facing = 2      # face LEFT -> the aide at (2,6)
	interact(player)
	var g := 0
	while (cutscene_active or modal != null) and g < 600:      # under 30 species: refused
		if modal == menu:
			await _press("ui_accept")                          # YES
		elif modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	var refused: bool = not player_bag.has("ITEMFINDER") and not has_event("GOT_ITEMFINDER")
	for i in 30:
		pokedex_owned["fake%d" % i] = true
	interact(player)
	g = 0
	while (cutscene_active or modal != null) and g < 600:
		if modal == menu:
			await _press("ui_accept")
		elif modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	print("[aidetest] itemfinder: refused_below=%s granted_at_30=%s" % [
		refused, player_bag.has("ITEMFINDER") and has_event("GOT_ITEMFINDER")])
	load_world("Route15Gate2F")
	await get_tree().process_frame
	for i in 50:
		pokedex_owned["fake%d" % i] = true
	player.place(Vector2i(4, 3), true); player.facing = 1      # face UP -> the aide at (4,2)
	interact(player)
	g = 0
	while (cutscene_active or modal != null) and g < 600:
		if modal == menu:
			await _press("ui_accept")
		elif modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	print("[aidetest] exp.all: granted_at_50=%s" % (player_bag.has("EXP.ALL") and has_event("GOT_EXP_ALL")))
	get_tree().quit()


## The League PC: hidden pre-HoF, listed post-HoF, and the records viewer replays the teams.
func _hoftest() -> void:
	await get_tree().process_frame
	load_world("ViridianPokecenter")
	_open_pc()
	var without: bool = not ("POKéMON LEAGUE" in menu.items)
	menu.close(); modal = null
	set_event("HALL_OF_FAME")
	hall_of_fame = [[{"species": "charizard", "name": "CHARIZARD", "level": 55},
		{"species": "pidgeot", "name": "PIDGEOT", "level": 50}]]
	_open_pc()
	var with_it: bool = "POKéMON LEAGUE" in menu.items
	print("[hoftest] pc menu: hidden_before=%s listed_after=%s" % [without, with_it])
	_on_menu_chosen(menu.items.find("POKéMON LEAGUE"))
	var g := 0
	var shown := 0
	while cutscene_active and g < 900:
		if modal == textbox:
			if cutscene.visible:
				shown += 1
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	await get_tree().process_frame
	print("[hoftest] viewer: pics_seen=%s back_at_pc=%s" % [
		shown > 0, modal == menu and menu_mode == "pc_top"])
	get_tree().quit()


## Bag faithfulness: the USE/TOSS submenu, key items refusing the toss, 20-slot capacity.
func _bagtest() -> void:
	await get_tree().process_frame
	player_bag = {"POTION": 3, "TOWN MAP": 1}
	_open_bag()
	_bag_select(0)                                   # POTION -> USE/TOSS
	var submenu: bool = menu_mode == "bag_usetoss" and menu.items == ["USE", "TOSS"]
	_on_menu_chosen(1)                               # TOSS -> qty picker
	var qty_ok: bool = menu_mode == "bag_toss_qty"
	_on_menu_chosen(2)                               # toss 2 -> confirm
	var confirm_ok: bool = menu_mode == "bag_toss_confirm"
	_on_menu_chosen(0)                               # YES
	print("[bagtest] submenu=%s qty=%s confirm=%s potions_left=%d (expect 1)" % [
		submenu, qty_ok, confirm_ok, int(player_bag.get("POTION", 0))])
	# gh #56: dismissing the "Threw away" message returns to the bag (ItemMenuLoop).
	for i in 6:
		if modal == textbox:
			await _press("ui_accept")
	print("[bagtest] toss returns to bag=%s" % (modal == menu and menu_mode == "bag"))
	_bag_select(menu_keys.find("TOWN MAP"))
	_on_menu_chosen(1)                               # TOSS a key item -> refused
	print("[bagtest] key item kept=%s" % (player_bag.has("TOWN MAP") and modal == textbox))
	modal = null; textbox.visible = false; _text_then = Callable()
	# gh #56: using an item returns to the bag with the cursor kept (wBagSavedMenuItem);
	# the bag is reached through the real chosen path so the cursor gets saved.
	player_party = [make_mon("pidgey", 10, ["TACKLE"])]
	player_party[0]["hp"] = 1
	player_bag = {"ANTIDOTE": 1, "POTION": 2}
	_open_bag()
	_on_menu_chosen(1)                               # POTION -> USE/TOSS (saves cursor 1)
	_on_menu_chosen(0)                               # USE -> the party target menu
	var target_up: bool = menu_mode == "bag_target"
	_on_menu_chosen(0)                               # on the pidgey -> "recovered" message
	for i in 6:
		if modal == textbox:
			await _press("ui_accept")
	print("[bagtest] use returns to bag=%s cursor_kept=%s consumed=%s target=%s" % [
		modal == menu and menu_mode == "bag", menu.cursor == 1,
		int(player_bag.get("POTION", 0)) == 1, target_up])
	modal = null; textbox.visible = false; _text_then = Callable()
	player_bag = {}
	for i in 20:
		player_bag["ITEM%02d" % i] = 1
	print("[bagtest] full: new_refused=%s stack_ok=%s size=%d (expect false true 20 -> refused=true)" % [
		not add_item("POTION"), add_item("ITEM00"), player_bag.size()])
	# gh #63: a stack holds at most 99 (AddItemToInventory_); an overflow adds nothing.
	player_bag = {"POTION": 98}
	var cap_ok: bool = add_item("POTION") and not add_item("POTION", 5) \
		and int(player_bag["POTION"]) == 99
	print("[bagtest] stack cap: 98+1_ok_then_overflow_refused=%s (expect true)" % cap_ok)
	# gh #126: the Celadon vending machine must obey the 20-slot bag (GiveItem -> .BagFull) and only
	# charge on a successful give (SubBCDPredef runs after GiveItem) — it used to write the bag directly.
	player_bag = {}
	for i in 20:
		player_bag["ITEM%02d" % i] = 1                   # 20 slots: no room for a drink
	player_money = 1000
	_open_vending()                                     # sets mart_keys = the three drinks
	_vending_buy(0)                                      # FRESH WATER, bag full -> refused, no charge
	var vend_full_ok: bool = not player_bag.has("FRESH WATER") and player_money == 1000 and player_bag.size() == 20
	player_bag = {"POTION": 1}                           # room now
	_vending_buy(0)                                      # delivered -> charged ¥200
	var vend_buy_ok: bool = int(player_bag.get("FRESH WATER", 0)) == 1 and player_money == 800
	player_money = 100
	_vending_buy(1)                                      # SODA POP ¥300 > ¥100 -> refused, no charge
	var vend_poor_ok: bool = not player_bag.has("SODA POP") and player_money == 100
	print("[bagtest] vending: full_refused_no_charge=%s bought_charged=%s poor_refused=%s (expect true x3)" % [
		vend_full_ok, vend_buy_ok, vend_poor_ok])
	get_tree().quit()


## Cinnabar Gym quiz machines: a right answer opens the room's gate block; a wrong one sics
## the room's trainer on you.
func _quiztest() -> void:
	await get_tree().process_frame
	player_party = [make_mon("charmander", 50, ["EMBER"])]
	load_world("CinnabarGym")
	await get_tree().process_frame
	var cells := [Vector2i(18, 6), Vector2i(19, 6), Vector2i(18, 7), Vector2i(19, 7)]
	var before := 0
	for c in cells:
		if is_walkable(c):
			before += 1
	cutscene.cinnabar_quiz(1, true)
	var g := 0
	while (cutscene_active or modal != null) and g < 900:
		if modal == menu:
			await _press("ui_accept")              # YES — correct for gate 1
		elif modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	var after := 0
	for c in cells:
		if is_walkable(c):
			after += 1
	print("[quiztest] right answer: gate-1 walkable %d -> %d (expect more) event=%s" % [
		before, after, has_event("CINNABAR_GATE_1")])
	cutscene.cinnabar_quiz(2, false)               # YES is wrong for gate 2 -> trainer fight
	g = 0
	var battled := false
	while g < 2000 and not battled:
		if modal == menu:
			await _press("ui_accept")
		elif modal == battle:
			battled = true
		elif modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	print("[quiztest] wrong answer: battle_engaged=%s" % battled)
	get_tree().quit()


## Spin tiles: landing on a hideout arrow slides the player along the extracted path (sprite
## whirling), stopping on the matching stop tile; a slide onto another arrow chains.
func _spintest() -> void:
	await get_tree().process_frame
	print("[spintest] tables: B2F=%d B3F=%d Gym=%d" % [spinners.get("RocketHideoutB2F", {}).size(),
		spinners.get("RocketHideoutB3F", {}).size(), spinners.get("ViridianGym", {}).size()])
	load_world("RocketHideoutB2F")
	await get_tree().process_frame
	player.place(Vector2i(4, 9), true)              # standing on the arrow at (4,9): PAD_LEFT x2
	var spun_seen := false
	_on_player_moved(Vector2i(4, 9))
	var g := 0
	while (cutscene_active or player.spinning) and g < 600:
		spun_seen = spun_seen or player.spinning
		await get_tree().process_frame
		g += 1
	print("[spintest] slide: end=%s (expect (2, 9)) spun=%s unlocked=%s" % [
		player.cell, spun_seen, not cutscene_active])
	get_tree().quit()


## gh#141 regression: every spin arrow tile must be walkable (you can step onto it) and its baked slide
## must COME TO REST on a walkable, non-warp floor tile. The slide itself deliberately ignores collision
## mid-path — pokered does the same (CollisionCheckOnLand bails when wSimulatedJoypadStatesIndex != 0), so
## crossing a wall tile en route is faithful and NOT flagged; only a bad landing (in a wall, or on a warp
## that would yank the player off-floor) means a mis-baked path.
func _spinwalltest() -> void:
	await get_tree().process_frame
	var deltas := {0: Vector2i(0, 1), 1: Vector2i(0, -1), 2: Vector2i(-1, 0), 3: Vector2i(1, 0)}
	var total_bad := 0
	for label in ["RocketHideoutB2F", "RocketHideoutB3F", "ViridianGym"]:
		load_world(label)
		await get_tree().process_frame
		var tbl: Dictionary = spinners.get(label, {})
		var bad := 0
		for key in tbl.keys():
			var parts: PackedStringArray = key.split(",")
			var start := Vector2i(int(parts[0]), int(parts[1]))
			var problems: Array = []
			if not _raw_walk(start):
				problems.append("arrow tile itself non-walkable")
			var c := start
			for seg in tbl[key]:
				var d: Vector2i = deltas[int(seg[0])]
				c += d * int(seg[1])
			if not _raw_walk(c):
				problems.append("lands IN WALL @%s" % str(c))
			if _warp_at(c) != null:
				problems.append("lands on WARP @%s" % str(c))
			if not problems.is_empty():
				bad += 1
				print("[spinwall] %s tile %s: %s" % [label, key, ", ".join(PackedStringArray(problems))])
		total_bad += bad
		print("[spinwall] %s: %d/%d tiles land on floor" % [label, tbl.size() - bad, tbl.size()])
	print("[spinwall] %s (%d bad landings across all arrow-floor maps)" % ["PASS" if total_bad == 0 else "FAIL", total_bad])
	get_tree().quit()


## Spin-aware navigation (gh #76): cross the Rocket Hideout spin-tile mazes on foot. B2F from the B1F
## entry (27,8) to the B3F stairs (21,8), then B3F from (25,6) to the B4F stairs (19,18), using
## _pt_walk_dungeon(..., spin_aware=true) — which models a step onto an arrow as landing on its stop
## tile. Run: `--spinnavtest`.
func _spinnavtest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"
	player_party = [make_mon("charmander", 45, ["EMBER"])]
	player_bag = {"SUPER POTION": 8}
	story_events = {"GOT_POKEDEX": true}
	load_world("RocketHideoutB2F")
	await get_tree().process_frame
	player.place(Vector2i(27, 8))                          # where the B1F stairs land
	warp_armed = _warp_at(player.cell) == null             # arrive-via-warp: place() leaves this stale (else the up-stairs re-fires)
	print("[spinnav] B2F start @%s -> B3F stairs (21,8)" % str(player.cell))
	var b2 := await _pt_walk_dungeon(Vector2i(21, 8), 3000, true)
	var on_b3 := str(center_label) == "RocketHideoutB3F"
	print("[spinnav] B2F crossed=%s now on %s @%s" % [b2, center_label, str(player.cell)])
	if on_b3:
		player.place(Vector2i(25, 6))                      # B3F arrival from B2F  # audit: map=RocketHideoutB3F
		warp_armed = _warp_at(player.cell) == null
		var b3 := await _pt_walk_dungeon(Vector2i(19, 18), 3000, true)
		print("[spinnav] B3F crossed=%s now on %s @%s" % [b3, center_label, str(player.cell)])
	print("[spinnav] %s" % ("PASS" if str(center_label) == "RocketHideoutB4F" else "FAIL (reached %s)" % center_label))
	get_tree().quit()


## Fast iteration on the Silph Scope stage (gh #76). `--b4f`: start on B4F at the B3F-stairs landing and
## drive just the Giovanni leg (grunts -> door -> Giovanni -> SILPH SCOPE). Default: the whole stage from
## Celadon. Run: `--silphscopetest [--b4f]`.
func _silphscopetest() -> void:
	await get_tree().process_frame
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"
	player_party = [make_mon("charmander", 50, ["EMBER", "SLASH"]), make_mon("pidgeotto", 40, [])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE"]
	# Do NOT pre-set FOUND_ROCKET_HIDEOUT: earning it is half this stage, and handing it over hid a
	# softlock — the ROCKET on the poster cell (9,5) was never fought, so he never left (gh #89).
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	respawn_map = "CeladonPokecenter"
	if "--b4f" in OS.get_cmdline_user_args():
		story_events["FOUND_ROCKET_HIDEOUT"] = true        # b4f-only: skip straight to Giovanni's wing
		load_world("RocketHideoutB4F")
		await get_tree().process_frame
		player.place(Vector2i(19, 10))                     # where the B3F stairs land
		print("[silphscope] b4f-only @%s" % str(player.cell))
		var ok := await _pt_hideout_b4f()
		var out := ok and await _pt_hideout_exit()          # the wing's only way out is the elevator
		print("[silphscope] %s: beat_giovanni=%s got_scope=%s map=%s" % [
			"PASS" if (out and player_bag.has("SILPH SCOPE") and str(center_label) == "CeladonCity") else "FAIL",
			has_event("BEAT_ROCKET_HIDEOUT_GIOVANNI"), player_bag.has("SILPH SCOPE"), center_label])
		get_tree().quit()
		return
	load_world("CeladonCity")
	await get_tree().process_frame
	player.place(Vector2i(19, 20))                     # the street cell; (20,20) is a building (gh #84)
	print("[silphscope] full start on %s" % center_label)
	var okf := await _pt_stage_silphscope()
	print("[silphscope] %s: got_scope=%s map=%s" % [
		"PASS" if (okf and player_bag.has("SILPH SCOPE") and str(center_label) == "CeladonCity") else "FAIL",
		player_bag.has("SILPH SCOPE"), center_label])
	get_tree().quit()


## POKé FLUTE stage (gh #76). `--pokeflutetest` plays it whole from Celadon; `--tower` starts in
## Lavender and skips the Underground Path crossing (the Tower climb is the interesting half).
func _pokeflutetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"
	player_starter = "charmander"                          # the 2F rival's party keys off the counterpart
	player_party = [make_mon("charmander", 50, ["EMBER", "SLASH"]), make_mon("pidgeotto", 42, [])]
	player_bag = {"SUPER POTION": 16, "SILPH SCOPE": 1}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE"]
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	var tower: bool = "--tower" in OS.get_cmdline_user_args()
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("LavenderTown" if tower else "CeladonCity")
	await get_tree().process_frame
	player.place(Vector2i(10, 9) if tower else Vector2i(20, 20))
	respawn_map = "LavenderPokecenter" if tower else "CeladonPokecenter"
	print("[pokeflute] start on %s @%s" % [center_label, str(player.cell)])
	var ok := await _pt_stage_pokeflute()
	print("[pokeflute] %s: rival=%s marowak=%s rescued=%s flute=%s map=%s" % [
		"PASS" if (ok and player_bag.has("POKé FLUTE")) else "FAIL", has_event("BEAT_POKEMON_TOWER_RIVAL"),
		has_event("BEAT_GHOST_MAROWAK"), has_event("RESCUED_MR_FUJI"), player_bag.has("POKé FLUTE"),
		center_label])
	get_tree().quit()


## SNORLAX stage (gh #76): from Lavender, through the Route 12 gate, wake + beat the SNORLAX blocking
## the road, then Routes 12/13/14/15 down to Fuchsia. Run: `--snorlaxstage [--verbose]`.
func _snorlaxstagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "charmander"
	player_party = [make_mon("charmeleon", 52, ["EMBER", "SLASH"]), make_mon("pidgeotto", 44, [])]
	player_bag = {"SUPER POTION": 16, "POKé FLUTE": 1}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE"]
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("LavenderTown")
	await get_tree().process_frame
	player.place(Vector2i(10, 9))
	respawn_map = "LavenderPokecenter"
	print("[snorlax] start on %s @%s" % [center_label, str(player.cell)])
	var ok := await _pt_stage_snorlax()
	print("[snorlax] %s: beat_snorlax=%s map=%s lead=%s" % [
		"PASS" if (ok and str(center_label) == "FuchsiaCity") else "FAIL",
		has_event("BEAT_SNORLAX_Route12"), center_label, str(_pt_party_summary())])
	get_tree().quit()


## KOGA stage (gh #76): thread Fuchsia Gym's invisible-wall maze on foot, clearing its six sight-
## trainers, and beat KOGA for the SOULBADGE. Run: `--kogastage [--verbose]`.
func _kogastagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "charmander"
	player_party = [make_mon("charizard", 53, ["FLAMETHROWER", "SLASH"]), make_mon("pidgeotto", 44, [])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE"]
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("FuchsiaCity")
	await get_tree().process_frame
	player.place(Vector2i(19, 28))                         # the street, below the Pokémon Center door
	respawn_map = "FuchsiaPokecenter"
	print("[koga] start on %s @%s" % [center_label, str(player.cell)])
	var ok := await _pt_stage_koga()
	print("[koga] %s: beat=%s badges=%s tm06=%s map=%s" % [
		"PASS" if (ok and has_event("BEAT_KOGA") and "SOULBADGE" in badges) else "FAIL",
		has_event("BEAT_KOGA"), str(badges), player_bag.has("TM06"), center_label])
	get_tree().quit()


## SAFARI stage (gh #76): pay into the park, walk to the secret house for HM03 (SURF), take the GOLD
## TEETH, trade them to the WARDEN for HM04 (STRENGTH), teach both. Run: `--safaristage [--verbose]`.
func _safaristagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	# The run's starter is SQUIRTLE (_pt_stage_opening), and the Squirtle line is the only party mon that
	# learns SURF — Charizard learns CUT and STRENGTH but not SURF or FLY in Gen 1.
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("blastoise", 53, ["WATER_GUN", "BITE"]), make_mon("pidgeotto", 44, [])]
	player_bag = {"SUPER POTION": 10}
	player_money = 5000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE"]
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("FuchsiaCity")
	await get_tree().process_frame
	player.place(Vector2i(19, 28))
	respawn_map = "FuchsiaPokecenter"
	print("[safari] start on %s @%s (¥%d)" % [center_label, str(player.cell), player_money])
	var ok := await _pt_stage_safari()
	var surf := _mon_with_move("SURF")
	var strength := _mon_with_move("STRENGTH")
	print("[safari] %s: hm03=%s teeth_traded=%s hm04=%s surf=%s strength=%s map=%s" % [
		"PASS" if (ok and surf != "" and strength != "") else "FAIL", has_event("GOT_HM03"),
		not player_bag.has("GOLD TEETH"), has_event("GOT_HM04"), surf, strength, center_label])
	get_tree().quit()


## SAFFRON stage (gh #76): Fuchsia -> Lavender -> Celadon (drink off the Mart roof) -> Route 7's thirsty
## gate -> Saffron. `--drink` starts in Celadon, skipping the long walk north. Run: `--saffronstage`.
func _saffronstagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("blastoise", 53, ["SURF", "BITE"]), make_mon("pidgeotto", 44, [])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE"]
	story_events = {"GOT_POKEDEX": true, "BEAT_SNORLAX_Route12": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	var short: bool = "--drink" in OS.get_cmdline_user_args()
	load_world("CeladonCity" if short else "FuchsiaCity")
	await get_tree().process_frame
	player.place(Vector2i(19, 20) if short else Vector2i(19, 28))   # (20,20) is a building (gh #84)
	print("[saffron] start on %s @%s" % [center_label, str(player.cell)])
	var ok := false
	if short:
		ok = await _pt_buy_drink()
		print("[saffron] drink-only: %s drink=%s map=%s" % [
			"PASS" if (ok and _pt_have_drink()) else "FAIL", _pt_have_drink(), center_label])
		get_tree().quit()
		return
	ok = await _pt_stage_saffron()
	print("[saffron] %s: gate_open=%s map=%s lead=%s" % [
		"PASS" if (ok and str(center_label) == "SaffronCity") else "FAIL",
		has_event("GAVE_SAFFRON_GUARDS_DRINK"), center_label, str(_pt_party_summary())])
	get_tree().quit()


## SILPH CO stage (gh #76): from Saffron's street, in the front door — which only opens once MR.FUJI is
## rescued (gh #79) — through the pad maze for the CARD KEY, and on to GIOVANNI. `--card` stops once the
## key is in the bag. Pair with `--seed` — the 7F rival and GIOVANNI are real fights.
## Run: `--silphstage [--card] [--verbose]`.
func _silphstagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("blastoise", 53, ["SURF", "BITE"]), make_mon("pidgeotto", 44, [])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE"]
	story_events = {"GOT_POKEDEX": true, "BEAT_SNORLAX_Route12": true, "RESCUED_MR_FUJI": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("SaffronCity")
	await get_tree().process_frame
	player.place(Vector2i(18, 24))
	respawn_map = "SaffronPokecenter"
	print("[silphstage] start on %s @%s" % [center_label, str(player.cell)])
	if "--card" in OS.get_cmdline_user_args():
		var okc := await _pt_warp_via(Vector2i(18, 21), "SilphCo1F", "", true) and await _pt_silph_card_key()
		print("[silphstage] card-only: %s card_key=%s map=%s" % [
			"PASS" if (okc and player_bag.has("CARD KEY")) else "FAIL", player_bag.has("CARD KEY"), center_label])
		get_tree().quit()
		return
	var ok := await _pt_stage_silph()
	# The gym door is the point: SAFFRONCITY_ROCKET3 stands on (34,4) until Giovanni falls.
	var gym_open := _npc_at(Vector2i(34, 4)) == null
	print("[silphstage] %s: card_key=%s rival=%s giovanni=%s gym_door_clear=%s map=%s lead=%s" % [
		"PASS" if (ok and str(center_label) == "SaffronCity" and gym_open) else "FAIL",
		player_bag.has("CARD KEY"), has_event("BEAT_SILPH_CO_RIVAL"),
		has_event("BEAT_SILPH_CO_GIOVANNI"), gym_open, center_label, str(_pt_party_summary())])
	get_tree().quit()


## SABRINA stage (gh #76): from Saffron's street, in the gym door (only clear once GIOVANNI has fallen),
## through the pad maze to her room, and beat her for the MARSHBADGE. `--pads` stops once the chain has
## landed us in her room. Pair with `--seed` — SABRINA is a real fight.
## Run: `--sabrinastage [--pads] [--verbose]`.
func _sabrinastagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("blastoise", 53, ["SURF", "BITE"]), make_mon("pidgeotto", 44, [])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE"]
	story_events = {"GOT_POKEDEX": true, "RESCUED_MR_FUJI": true, "BEAT_SILPH_CO_GIOVANNI": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("SaffronCity")
	await get_tree().process_frame
	player.place(Vector2i(34, 6))            # the street below the gym; (34,5) is the sign — a wall (#84)
	respawn_map = "SaffronPokecenter"
	print("[sabrinastage] start on %s @%s" % [center_label, str(player.cell)])
	if "--pads" in OS.get_cmdline_user_args():
		var okp := await _pt_warp_via(Vector2i(34, 3), "SaffronGym", "", true) and await _pt_sabrina_room()
		print("[sabrinastage] pads-only: %s cell=%s map=%s" % [
			"PASS" if (okp and player.cell == Vector2i(11, 11)) else "FAIL", str(player.cell), center_label])
		get_tree().quit()
		return
	var ok := await _pt_stage_sabrina()
	print("[sabrinastage] %s: sabrina=%s badge=%s tm=%s map=%s lead=%s" % [
		"PASS" if (ok and has_event("BEAT_SABRINA")) else "FAIL", has_event("BEAT_SABRINA"),
		badges.has("MARSHBADGE"), player_bag.has("TM46"), center_label, str(_pt_party_summary())])
	get_tree().quit()


## Pokémon Mansion balcony holes (gh #85): stepping on 3F's western drops falls to 1F (16,14) — the only
## entrance to 1F's southern half, and so the only route to the B1F stairs and the SECRET KEY — while the
## eastern drop falls to 2F (18,14). Walking the *other* burnt-floor tiles must do nothing.
## Run: `--holetest`.
func _holetest() -> void:
	await get_tree().process_frame
	battle.fast_hp = true                      # skip the 50-frame landing beat
	story_events = {}
	player_party = [make_mon("blastoise", 40, [])]

	# 1) The western balcony (16,14) drops to 1F (16,14).
	load_world("PokemonMansion3F")
	await get_tree().process_frame
	player.place(Vector2i(16, 13))
	await _pt_step(0)                          # step DOWN onto the hole
	await _drive_until(func() -> bool: return str(center_label) == "PokemonMansion1F" \
		and not cutscene_active, 900)
	var west_ok: bool = str(center_label) == "PokemonMansion1F" and player.cell == Vector2i(16, 14)
	# The landing is what unseals 1F's south: the B1F stairs must be reachable from it.
	var stairs_ok: bool = west_ok and not find_path(player.cell, Vector2i(21, 23)).is_empty()

	# 2) The eastern balcony (19,14) drops to 2F (18,14).
	load_world("PokemonMansion3F")
	await get_tree().process_frame
	player.place(Vector2i(19, 13))
	await _pt_step(0)
	await _drive_until(func() -> bool: return str(center_label) == "PokemonMansion2F" \
		and not cutscene_active, 900)
	var east_ok: bool = str(center_label) == "PokemonMansion2F" and player.cell == Vector2i(18, 14)

	# 3) A burnt-floor tile that is NOT in .holeCoords must not drop you: (18,14) sits between the two
	# drops. Approach it from below — (18,13) above it is a wall, and its neighbours on row 14 are the
	# holes themselves — so step UP from (18,15), which is ordinary burnt floor.
	load_world("PokemonMansion3F")
	await get_tree().process_frame
	var approach_ok: bool = is_walkable(Vector2i(18, 15)) and is_walkable(Vector2i(18, 14))
	player.place(Vector2i(18, 15))
	await _pt_step(1)                          # UP onto the non-hole tile
	await _drive_until(func() -> bool: return not cutscene_active, 200)
	var stayed_ok: bool = str(center_label) == "PokemonMansion3F" and player.cell == Vector2i(18, 14) \
		and approach_ok

	var pass_all: bool = west_ok and stairs_ok and east_ok and stayed_ok
	print("[holetest] west->1F=%s b1f_stairs_reachable=%s east->2F=%s non_hole_tile_stays=%s" % [
		west_ok, stairs_ok, east_ok, stayed_ok])
	print("[holetest] PASS=%s" % pass_all)
	get_tree().quit()


## gh #172: without the SECRET KEY, WALKING up to the Cinnabar Gym door must bounce the player back off
## the tile below it (18,4) — they never step onto the door warp (18,3) or enter the Gym. With the key the
## door works. Real movement (not place()), so it actually exercises reachability.
func _cinnabardoortest() -> void:
	await get_tree().process_frame
	player_name = "RED"
	player_party = [make_mon("blastoise", 55, ["SURF"])]
	story_events = {"GOT_POKEDEX": true}

	# --- P1: no SECRET KEY -> the door is locked; walking up never reaches (18,3) or the Gym ---
	player_bag = {}
	load_world("CinnabarIsland")
	await get_tree().process_frame
	player.place(Vector2i(18, 5))
	var reached_door := false
	var min_y := 5
	for i in 12:
		await _press("ui_up")
		var g := 0
		while (player.moving or cutscene_active) and g < 80:
			min_y = mini(min_y, player.cell.y)       # catch (18,4) mid-bounce, before step_back_down returns us
			await get_tree().process_frame; g += 1
		min_y = mini(min_y, player.cell.y)
		if player.cell == Vector2i(18, 3) or str(center_label) == "CinnabarGym":
			reached_door = true
			break
		g = 0
		while modal != null and g < 30:               # dismiss "The door is locked..." before trying again
			await _press("ui_accept"); g += 1
	var p1: bool = not reached_door and str(center_label) == "CinnabarIsland"
	print("[cinnabardoor] P1(no key) %s: reached_door=%s min_y=%d map=%s (expect blocked: y never 3, on CinnabarIsland)" % [
		"PASS" if p1 else "FAIL", reached_door, min_y, center_label])

	# --- P2: with the SECRET KEY -> the door works; walking up enters the Gym ---
	player_bag = {"SECRET KEY": 1}
	load_world("CinnabarIsland")
	await get_tree().process_frame
	player.place(Vector2i(18, 5))
	warp_armed = true
	var g2 := 0
	while str(center_label) == "CinnabarIsland" and g2 < 12:
		await _press("ui_up")
		var g := 0
		while (player.moving or cutscene_active) and g < 80:
			await get_tree().process_frame; g += 1
		g2 += 1
	var p2: bool = str(center_label) == "CinnabarGym"
	print("[cinnabardoor] P2(with key) %s: map=%s (expect CinnabarGym)" % ["PASS" if p2 else "FAIL", center_label])

	print("[cinnabardoor] %s" % ("PASS" if (p1 and p2) else "FAIL"))
	get_tree().quit()


## The SECRET KEY on foot (gh #76 / #85): from Cinnabar's street, thread the Pokémon Mansion's switch
## puzzle — up to 3F, flip its switch, fall through the western balcony into 1F's sealed south, down to
## B1F, flip both of its switches — and take the key. Then out the back door.
## Run: `--secretkeytest [--verbose]`.
func _secretkeytest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	battle.fast_hp = true
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("blastoise", 55, ["SURF", "STRENGTH", "BITE"]), make_mon("pidgeotto", 44, [])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE"]
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("CinnabarIsland")
	await get_tree().process_frame
	player.place(Vector2i(6, 4))               # the street below the Mansion's door at (6,3)
	respawn_map = "CinnabarPokecenter"
	print("[secretkey] start on %s @%s" % [center_label, str(player.cell)])
	var ok := await _pt_mansion_secret_key()
	# The point of the key: the Cinnabar Gym door is locked without it.
	var have := player_bag.has("SECRET KEY")
	print("[secretkey] %s: secret_key=%s switch_on=%s map=%s lead=%s" % [
		"PASS" if (ok and have and str(center_label) == "CinnabarIsland") else "FAIL",
		have, has_event("MANSION_SWITCH_ON"), center_label, str(_pt_party_summary())])
	get_tree().quit()


## GIOVANNI stage (gh #76): the eighth badge. From Viridian's street, in the gym door (shut until you hold
## the other seven, gh #86), through the spin-tile maze and its eight sight-trainers, and beat GIOVANNI
## for the EARTHBADGE. Pair with `--seed` (GIOVANNI is a real fight).
## Run: `--giovannistage [--verbose]`.
func _giovannistagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	battle.fast_hp = true
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("blastoise", 58, ["SURF", "STRENGTH", "BITE"]), make_mon("pidgeotto", 48, [])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = _PT_SEVEN_BADGES.duplicate()
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("ViridianCity")
	await get_tree().process_frame
	player.place(Vector2i(32, 11))
	respawn_map = "ViridianPokecenter"
	print("[giovanni] start on %s @%s badges=%d" % [center_label, str(player.cell), badges.size()])
	var ok := await _pt_stage_giovanni()
	print("[giovanni] %s: gym_open=%s giovanni=%s badge=%s tm=%s badges=%d map=%s lead=%s" % [
		"PASS" if (ok and has_event("BEAT_GIOVANNI") and badges.size() == 8) else "FAIL",
		has_event("VIRIDIAN_GYM_OPEN"), has_event("BEAT_GIOVANNI"), badges.has("EARTHBADGE"),
		player_bag.has("TM27"), badges.size(), center_label, str(_pt_party_summary())])
	get_tree().quit()


## Viridian Gym's badge lock (gh #86, ViridianCityCheckGymOpenScript): the door is shut until you hold
## every other badge. Standing on (32,8) without them says "The GYM's doors are locked..." and walks you
## back down; with them, VIRIDIAN_GYM_OPEN latches and the door lets you in. Run: `--viridiangatetest`.
func _viridiangatetest() -> void:
	await get_tree().process_frame
	battle.fast_hp = true
	story_events = {"GOT_POKEDEX": true}
	badges = []
	load_world("ViridianCity")
	await get_tree().process_frame

	# The street is row 8; (32,9) below the door step is a down-ledge, so we approach from the side.
	var geometry_ok: bool = is_walkable(Vector2i(31, 8)) and is_walkable(Vector2i(32, 8)) \
		and not is_walkable(Vector2i(32, 9)) and is_walkable(Vector2i(32, 10))

	# 1) No badges: stepping onto the door cell turns us away, hopped back down the ledge to (32,10).
	player.place(Vector2i(31, 8))
	await _pt_step(3)                          # RIGHT onto the door step (32,8)
	await _drive_until(func() -> bool: return modal == null and not cutscene_active, 400)
	textbox.visible = false
	var pushed_ok: bool = str(center_label) == "ViridianCity" and player.cell == Vector2i(32, 10)
	var latch_off: bool = not has_event("VIRIDIAN_GYM_OPEN")

	# 2) Six badges is still not enough — the lock wants all seven.
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE"]
	player.place(Vector2i(31, 8))
	await _pt_step(3)
	await _drive_until(func() -> bool: return modal == null and not cutscene_active, 400)
	textbox.visible = false
	var six_ok: bool = str(center_label) == "ViridianCity" and not has_event("VIRIDIAN_GYM_OPEN") \
		and player.cell == Vector2i(32, 10)

	# 3) The seventh latches the gym open, and the door then admits us.
	badges.append("VOLCANOBADGE")
	player.place(Vector2i(31, 8))
	await _pt_step(3)                          # onto (32,8): the latch fires this step, no turn-away
	await _drive_until(func() -> bool: return modal == null and not cutscene_active, 400)
	var latched: bool = has_event("VIRIDIAN_GYM_OPEN") and player.cell == Vector2i(32, 8)
	await _pt_step(1)                          # UP onto the door (32,7)
	await _drive_until(func() -> bool: return str(center_label) == "ViridianGym", 600)
	var entered: bool = str(center_label) == "ViridianGym"

	var pass_all: bool = geometry_ok and pushed_ok and latch_off and six_ok and latched and entered
	print("[viridiangate] ledge_geometry=%s no_badges_turned_away=%s latch_off=%s six_badges_still_shut=%s latched_on_7th=%s entered=%s" % [
		geometry_ok, pushed_ok, latch_off, six_ok, latched, entered])
	print("[viridiangate] PASS=%s" % pass_all)
	get_tree().quit()


## The Route 22 gate house (gh #87, Route22Gate_Script): the ONLY gate in Kanto that is entered from two
## different maps (Route 22 to the south, Route 23 to the north), so it is the only one whose four
## `LAST_MAP` doors are ambiguous. pokered picks `wLastMap` by which half of the building you stand in —
## north of the counter (Y < 4) it is ROUTE_23, south of it ROUTE_22 — and the port had no such rule, so
## both doors resolved to wherever you came from. This walks the gate the way a player does: in from
## Route 22, past the BOULDERBADGE guard, out the north door. Also checks the guard's turn-away and that
## the trip works in reverse. Run: `--route22gatetest`.
func _route22gatetest() -> void:
	await get_tree().process_frame
	battle.fast_hp = true
	story_events = {"GOT_POKEDEX": true}
	player_party = [make_mon("wartortle", 40, [])]

	# 1) No BOULDERBADGE: the guard turns you back at (4,2)/(5,2), one step south of where you stood.
	badges = []
	load_world("Route22Gate")
	await get_tree().process_frame
	player.place(Vector2i(4, 3))
	await _pt_step(1)                              # UP onto (4,2), the guard's coord row
	await _drive_until(func() -> bool: return modal == null and not cutscene_active, 400)
	textbox.visible = false
	var guard_ok: bool = str(center_label) == "Route22Gate" and player.cell == Vector2i(4, 3)

	# 2) With it, walk in off Route 22 and straight out the north door: that must land on Route 23.
	badges = ["BOULDERBADGE"]
	load_world("Route22")
	await get_tree().process_frame
	player.place(Vector2i(8, 6))
	var into_gate: bool = await _pt_warp_out("Route22Gate")
	var north_ok := false
	var north_cell := Vector2i(-1, -1)
	if into_gate:
		if await _pt_walk_to(Vector2i(4, 1), 400, true):
			await _pt_step(1)                      # UP onto the north door (4,0)
			await _drive_until(func() -> bool: return str(center_label) != "Route22Gate", 600)
		north_ok = str(center_label) == "Route23"
		north_cell = player.cell

	# 3) And back the other way: the same doors resolve to Route 22 from the building's south half.
	var south_ok := false
	if north_ok:
		# We land on Route 23's doormat, so step off it before stepping back on (a warp you stand on
		# is inert until you leave it).
		if await _pt_walk_to(Vector2i(8, 138), 400, true) and await _pt_warp_via(Vector2i(8, 139), "Route22Gate") \
				and await _pt_walk_to(Vector2i(5, 6), 400, true):
			await _pt_step(0)                      # DOWN onto the south door (5,7)
			await _drive_until(func() -> bool: return str(center_label) != "Route22Gate", 600)
		south_ok = str(center_label) == "Route22"

	var pass_all: bool = guard_ok and into_gate and north_ok and south_ok
	print("[route22gate] guard_turns_away=%s entered_from_route22=%s north_door->Route23=%s (landed %s) south_door->Route22=%s" % [
		guard_ok, into_gate, north_ok, str(north_cell), south_ok])
	print("[route22gate] PASS=%s (on %s @%s)" % [pass_all, center_label, str(player.cell)])
	get_tree().quit()


## Post-eighth-badge party for the last two stages (the run's real team: a SURF/STRENGTH Blastoise plus
## the FLY bird), plus the bag and events the earlier stages leave behind.
func _pt_league_party() -> void:
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"; rival_starter = "bulbasaur"
	player_party = [make_mon("blastoise", 62, ["SURF", "STRENGTH", "BITE"]),
		make_mon("pidgeot", 52, ["FLY", "WING_ATTACK"]), make_mon("arcanine", 55, ["EMBER", "BITE"])]
	player_bag = {"SUPER POTION": 16, "FULL RESTORE": 6}
	player_money = 30000
	badges = _PT_SEVEN_BADGES + ["EARTHBADGE"]
	story_events = {"GOT_POKEDEX": true, "BEAT_GIOVANNI": true}
	defeated_trainers = {}
	# No IndigoPlateau here: reaching it is what the victoryroad stage proves, and the stage's own
	# "already done (resumed)" check keys off visited_fly. Map load appends it the moment we arrive.
	visited_fly = ["ViridianCity"]


## Victory Road on foot (gh #76), in fast slices. `--r23` drives just Route 23 — out of the gate house, up
## the south footpath, SURF the river, ashore at the cave door. `--cave` starts inside Victory Road 1F and
## drives the three floors (the 2F boulder push included) back out onto Route 23. With neither, the whole
## stage runs from Viridian. Run: `--victoryroadtest [--r23|--cave] [--verbose]`.
func _victoryroadtest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	battle.fast_hp = true
	_pt_league_party()
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	respawn_map = "ViridianPokecenter"
	if "--cave" in OS.get_cmdline_user_args():
		strength_active = true
		load_world("VictoryRoad1F")
		await get_tree().process_frame
		# Victory Road's exit is a LAST_MAP warp, so the climb only lands on Route 23 if we "came" from
		# it — a real entrance sets this when the door on Route 23 closes behind us.
		last_outside_map = "Route23"
		player.place(Vector2i(8, 16))                  # one cell off the entrance mat (a warp we stand on is inert)
		print("[victoryroad] cave-only: from %s @%s" % [center_label, str(player.cell)])
		var cok := await _pt_climb_victory_road()
		print("[victoryroad] %s: climbed=%s vr2_switch=%s map=%s (expect Route23) @%s" % [
			"PASS" if (cok and str(center_label) == "Route23") else "FAIL", cok,
			has_event("VR2_SWITCH1"), center_label, str(player.cell)])
		get_tree().quit()
		return
	if "--r23" in OS.get_cmdline_user_args():
		load_world("Route22")
		await get_tree().process_frame
		player.place(Vector2i(8, 6))
		print("[victoryroad] route23-only: from %s @%s" % [center_label, str(player.cell)])
		var rok := await _pt_reach_route23()
		print("[victoryroad] %s: reached=%s map=%s (expect VictoryRoad1F) @%s surfing=%s" % [
			"PASS" if (rok and str(center_label) == "VictoryRoad1F") else "FAIL", rok, center_label,
			str(player.cell), surfing])
		get_tree().quit()
		return
	load_world("ViridianCity")
	await get_tree().process_frame
	player.place(Vector2i(23, 26))
	print("[victoryroad] start on %s @%s badges=%d" % [center_label, str(player.cell), badges.size()])
	var ok := await _pt_stage_victoryroad()
	print("[victoryroad] %s: map=%s (expect IndigoPlateau) @%s lead=%s" % [
		"PASS" if (ok and str(center_label) == "IndigoPlateau") else "FAIL", center_label,
		str(player.cell), str(_pt_party_summary())])
	get_tree().quit()


## Victory Road's stage entry point, unabridged (gh #76). Alias of `--victoryroadtest` with no sub-flag,
## kept so every stage has a `--<name>stage` driver. Run: `--victoryroadstage`.
func _victoryroadstagetest() -> void:
	await _victoryroadtest()


## The ELITE FOUR stage (gh #76): from the Indigo Plateau, in through the lobby, then LORELEI -> BRUNO ->
## AGATHA -> LANCE -> the CHAMPION -> the HALL OF FAME, on foot and on merit. `--gauntlet` skips the walk
## in and starts in the lobby. This is the run's last stage; pair with `--seed`.
## Run: `--elite4stage [--gauntlet] [--verbose]`.
func _elite4stagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	battle.fast_hp = true
	_pt_league_party()
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	# The lead has to carry five fights ending in a L62-65 champion, so the league team is a real one.
	player_party[0] = make_mon("blastoise", 65, ["SURF", "STRENGTH", "BITE", "ICE_BEAM"])
	load_world("IndigoPlateauLobby" if "--gauntlet" in OS.get_cmdline_user_args() else "IndigoPlateau")
	await get_tree().process_frame
	player.place(Vector2i(7, 10) if str(center_label) == "IndigoPlateauLobby" else Vector2i(9, 7))
	respawn_map = "IndigoPlateauLobby"
	print("[elite4] start on %s @%s lead=%s" % [center_label, str(player.cell), str(_pt_party_summary())])
	var ok := await _pt_stage_elite4()
	var beaten: Array = []
	for room in _PT_E4_ROOMS:
		if defeated_trainers.has("%s:%d,%d" % [room[0], room[1].x, room[1].y]):
			beaten.append(str(room[0]).replace("sRoom", ""))
	print("[elite4] %s: beat=%s champion=%s hall_of_fame=%s map=%s" % [
		"PASS" if (ok and has_event("HALL_OF_FAME")) else "FAIL", str(beaten),
		has_event("BEAT_CHAMPION"), has_event("HALL_OF_FAME"), center_label])
	get_tree().quit()


## BLAINE stage (gh #76): the seventh badge. `--gym` skips the Pokémon Mansion and starts on Cinnabar with
## the SECRET KEY already in the bag, so the six quiz gates and the leader can be iterated on quickly;
## the default run walks the mansion for the key first. Pair with `--seed` (BLAINE is a real fight).
## Run: `--blainestage [--gym] [--verbose]`.
func _blainestagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	battle.fast_hp = true
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("blastoise", 55, ["SURF", "STRENGTH", "BITE"]), make_mon("pidgeotto", 46, [])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE"]
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	if "--gym" in OS.get_cmdline_user_args():
		player_bag["SECRET KEY"] = 1                       # gym-only: skip the mansion
	load_world("CinnabarIsland")
	await get_tree().process_frame
	player.place(Vector2i(6, 4))
	respawn_map = "CinnabarPokecenter"
	print("[blaine] start on %s @%s (secret_key=%s)" % [center_label, str(player.cell), player_bag.has("SECRET KEY")])
	var ok := await _pt_stage_blaine()
	var gates := 0
	for g in range(1, 7):
		if has_event("CINNABAR_GATE_%d" % g):
			gates += 1
	print("[blaine] %s: gates_opened=%d/6 blaine=%s badge=%s tm=%s map=%s lead=%s" % [
		"PASS" if (ok and has_event("BEAT_BLAINE") and gates == 6) else "FAIL", gates,
		has_event("BEAT_BLAINE"), badges.has("VOLCANOBADGE"), player_bag.has("TM38"),
		center_label, str(_pt_party_summary())])
	get_tree().quit()


## SURF navigation (gh #76, `blaine` prep): the bot's first water crossing — Fuchsia → Route 19 → Route
## 20, mounting the water at Route 19's shore and fighting the swimmers en route. The point of the test is
## the **map connection crossed afloat**, which was impossible before gh #82.
## Run: `--surfnavtest [--verbose]`. Pair with `--seed` (the swimmers are real fights).
func _surfnavtest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("blastoise", 53, ["SURF", "STRENGTH", "BITE"]), make_mon("pidgeotto", 44, [])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE"]
	story_events = {"GOT_POKEDEX": true, "BEAT_SNORLAX_Route12": true}
	defeated_trainers = {}
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("FuchsiaCity")
	await get_tree().process_frame
	player.place(Vector2i(19, 28))
	respawn_map = "FuchsiaPokecenter"
	print("[surfnav] start on %s @%s" % [center_label, str(player.cell)])
	var ok := await _pt_surf_to_route20()
	print("[surfnav] %s: map=%s cell=%s surfing=%s lead=%s" % [
		"PASS" if (ok and str(center_label) == "Route20" and surfing) else "FAIL",
		center_label, str(player.cell), surfing, str(_pt_party_summary())])
	get_tree().quit()


## Reach Cinnabar Island (gh #76, `blaine` prep): FLY home to Pallet, SURF out of its beach, and swim the
## 90 cells of Route 21 — fishers and swimmers engage on sight — to Cinnabar's north shore.
## Run: `--cinnabarnavtest [--verbose]`. Pair with `--seed` (the swimmers are real fights).
func _cinnabarnavtest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("blastoise", 53, ["SURF", "STRENGTH", "BITE"]),
		make_mon("pidgeotto", 44, ["FLY", "GUST"])]
	player_bag = {"SUPER POTION": 16}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE"]
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	visited_fly = ["PalletTown", "SaffronCity"]
	_pt_verbose = "--verbose" in OS.get_cmdline_user_args()
	load_world("SaffronCity")
	await get_tree().process_frame
	player.place(Vector2i(18, 24))
	respawn_map = "SaffronPokecenter"
	print("[cinnabarnav] start on %s @%s" % [center_label, str(player.cell)])
	var ok := await _pt_reach_cinnabar()
	print("[cinnabarnav] %s: map=%s cell=%s surfing=%s lead=%s" % [
		"PASS" if (ok and str(center_label) == "CinnabarIsland" and not surfing) else "FAIL",
		center_label, str(player.cell), surfing, str(_pt_party_summary())])
	get_tree().quit()


## Rocket Hideout descent (gh #76, silphscope prep): from the Game Corner staircase landing on B1F,
## descend B1F -> B2F -> B3F -> B4F (spin-aware on B2F/B3F), fighting Rocket grunts en route, to reach
## Giovanni's floor. Down-stairs: B1F (23,2), B2F (21,8), B3F (19,18). Run: `--silphdescent`.
func _silphdescenttest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"
	player_party = [make_mon("charmander", 45, ["EMBER", "SLASH"])]
	player_bag = {"SUPER POTION": 12}
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE"]
	story_events = {"GOT_POKEDEX": true}
	defeated_trainers = {}
	respawn_map = "CeladonPokecenter"
	load_world("RocketHideoutB1F")
	await get_tree().process_frame
	player.place(Vector2i(21, 2))                          # where the Game Corner staircase lands
	var route := [["RocketHideoutB1F", Vector2i(23, 2), false], ["RocketHideoutB2F", Vector2i(21, 8), true],
		["RocketHideoutB3F", Vector2i(19, 18), true]]
	for leg in route:
		var want: String = leg[0]
		if str(center_label) != want:
			print("[silphdescent] FAIL: expected %s, on %s @%s" % [want, center_label, str(player.cell)])
			get_tree().quit(); return
		print("[silphdescent] on %s @%s -> stairs %s" % [center_label, str(player.cell), str(leg[1])])
		var before := str(center_label)
		if not await _pt_walk_dungeon(leg[1], 4000, bool(leg[2])):
			print("[silphdescent] FAIL: stuck reaching %s on %s @%s" % [str(leg[1]), center_label, str(player.cell)])
			get_tree().quit(); return
		await _drive_until(func() -> bool: return str(center_label) != before, 400)
	print("[silphdescent] %s: reached %s @%s (lead L%d)" % ["PASS" if str(center_label) == "RocketHideoutB4F" else "FAIL",
		center_label, str(player.cell), int(player_party[0]["level"])])
	get_tree().quit()


## Pewter's two escorts: decline the museum question / greet the gym kid, get marched across
## town to the destination cell, and the guide walks off hidden afterwards.
func _pewtertest() -> void:
	await get_tree().process_frame
	load_world("PewterCity")
	await get_tree().process_frame
	var nerd = _npc_by_key("SPRITE_SUPER_NERD@27,17")
	player.place(Vector2i(27, 18))
	cutscene.pewter_museum_guy(nerd)
	var g := 0
	var picked_no := false
	while g < 4000 and (cutscene_active or modal != null):
		if modal == menu and not picked_no:
			picked_no = true
			await _press("ui_down")                # "Did you check out the MUSEUM?" -> NO
			await _press("ui_accept")
		elif modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	# The guide walks off, hides, and is RESET to his post shown (ResetSuperNerd1Script, gh #70).
	print("[pewtertest] museum drag: player=%s (expect (14, 9)) nerd_back_home=%s" % [
		player.cell, nerd.shown and nerd.cell == nerd.home])
	var kid = _npc_by_key("SPRITE_YOUNGSTER@35,16")
	player.place(Vector2i(35, 17))
	cutscene.pewter_gym_guy(kid)
	g = 0
	while g < 4000 and (cutscene_active or modal != null):
		if modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	print("[pewtertest] gym drag: player=%s (expect (16, 18)) kid_back_home=%s" % [
		player.cell, kid.shown and kid.cell == kid.home])
	# The leaving-east gate: pre-BROCK, stepping on (35,17) fires the same drag.
	load_world("PewterCity")
	await get_tree().process_frame
	player.place(Vector2i(34, 17), true)
	player.facing = 3
	_on_player_moved(Vector2i(35, 17))
	player.place(Vector2i(35, 17), true)
	await get_tree().process_frame
	print("[pewtertest] east gate fired=%s (expect true)" % cutscene_active)
	get_tree().quit()


## The Viridian old man: object swap after the coffee, then the catching demo — the battle
## plays itself (OLD MAN throws his own ball at a wild WEEDLE; nothing is kept or consumed).
func _oldmantest() -> void:
	await get_tree().process_frame
	set_event("GOT_POKEDEX")
	load_world("ViridianCity")
	await get_tree().process_frame
	var om = _npc_by_key("SPRITE_GAMBLER@17,5")
	var asleep = _npc_by_key("SPRITE_GAMBLER_ASLEEP@18,9")
	print("[oldmantest] awake shown=%s asleep shown=%s (expect true false)" % [om.shown, asleep.shown])
	var balls0 := int(player_bag.get("POKé BALL", 0))
	var psize := player_party.size()
	cutscene.oldman_demo(om)                       # fire the coroutine; drive it below
	var saw_demo := false
	var g := 0
	while g < 3000 and (cutscene_active or modal != null):
		if modal == menu:
			await _press("ui_down")                # yes/no -> NO ("not in a hurry": the lesson)
			await _press("ui_accept")
		elif modal == textbox or (modal == battle and battle.state == "msg"):
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		if modal == battle and battle.demo:
			saw_demo = true
		g += 1
	print("[oldmantest] demo battle ran=%s over=%s" % [saw_demo, modal == null])
	print("[oldmantest] party unchanged=%s balls unchanged=%s caught_flag=%s (expect true true false)"
		% [player_party.size() == psize, int(player_bag.get("POKé BALL", 0)) == balls0, battle.caught])
	get_tree().quit()


## The OPTION menu + its three effects: text speed applies to both text boxes, BATTLE
## ANIMATION OFF turns the moveanim marker into a 30-frame beat, and BATTLE STYLE SHIFT
## offers the free switch before a trainer's next mon (declined and accepted paths).
func _optiontest() -> void:
	await get_tree().process_frame
	open_options("start")
	print("[optiontest] open: modal_is_options=%s" % (modal == optionsscreen))
	options["text_speed"] = 1
	apply_options()
	print("[optiontest] FAST text: textbox=%.0f battle=%.0f glyphs/s (expect 60)" % [textbox.speed, battle.speed])
	options["text_speed"] = 3
	apply_options()
	optionsscreen.visible = false
	modal = null
	# Animations OFF: the marker waits ~30 frames instead of playing (~2.5 s for THUNDER).
	options["battle_anim"] = false
	start_trainer_battle("OPP_BUG_CATCHER", 1)
	var b = battle
	var g := 0
	while b.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	b.fast_hp = false
	var t0 := Time.get_ticks_msec()
	b.queue = [{"moveanim": "THUNDER", "attacker": "player"}]
	b.after = "menu"
	b._next_msg()
	g = 0
	while b.state != "menu" and g < 300:
		await get_tree().process_frame; g += 1
	print("[optiontest] anim OFF: marker took %d ms (expect ~500, not ~2500)" % (Time.get_ticks_msec() - t0))
	options["battle_anim"] = true
	# SHIFT prompt, declined: the next mon comes out unswitched.
	b.enemy_mon["hp"] = 1
	await _press("ui_accept")
	await _press("ui_accept")
	g = 0
	while b.state != "shift" and modal == battle and g < 900:
		await _press("ui_accept"); g += 1
	print("[optiontest] shift prompt shown=%s" % (b.state == "shift"))
	await _press("ui_down")               # -> NO
	await _press("ui_accept")
	g = 0
	while b.state != "menu" and modal == battle and g < 900:
		await _press("ui_accept"); g += 1
	print("[optiontest] declined: enemy#2 out=%s (%s) active=%d" % [b.enemy_active == 1, b.enemy_mon["name"], b.active])
	b.enemy_mon["hp"] = 1                 # finish battle 1
	g = 0
	while modal == battle and g < 900:
		await _press("ui_accept"); g += 1
	# SHIFT prompt, accepted: free switch, then the next mon comes out.
	b.fast_hp = true
	start_trainer_battle("OPP_BUG_CATCHER", 1)
	g = 0
	while b.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	b.fast_hp = false
	b.enemy_mon["hp"] = 1
	await _press("ui_accept")
	await _press("ui_accept")
	g = 0
	while b.state != "shift" and modal == battle and g < 900:
		await _press("ui_accept"); g += 1
	await _press("ui_accept")             # YES
	print("[optiontest] YES -> party menu=%s" % (b.state == "party_shift"))
	await _press("ui_down")               # the other mon
	await _press("ui_accept")             # free switch
	g = 0
	while b.state != "menu" and modal == battle and g < 900:
		await _press("ui_accept"); g += 1
	print("[optiontest] shifted: active=%d (expect 1) vs enemy#2=%s state=%s" % [b.active, b.enemy_mon["name"], b.state])
	get_tree().quit()


## Pose the boot-intro phases at key beats and screenshot them (the draws are pure in t).
func _introshot() -> void:
	await get_tree().process_frame
	title.show_title()
	modal = title
	for probe in [["gamefreak", 1.12, "intro_star"], ["gamefreak", 3.55, "intro_stars"],
			["battle", 2.0, "intro_fight"], ["battle", 6.5, "intro_slash"],
			["title", 0.2, "title_bounce"], ["title", 1.5, "title_version"],
			["title", 3.0, "title_full"]]:
		title._goto(str(probe[0]))
		title.t = float(probe[1])
		title.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://%s.png" % str(probe[2]))
	print("[introshot] saved 7 shots")
	# Synthesize the sweep-heavy SFX directly (tests run with audio disabled, so the pitch-sweep
	# path would otherwise never execute) — a crash or zero-length stream fails here.
	for k in ["intro_hip", "intro_hop", "intro_lunge", "intro_whoosh", "shooting_star",
			"collision", "faint_fall", "ball_toss"]:
		var st = audio._synth_sfx(audio.sfx[k], 256, 0)
		print("[introshot] synth %s: %.2f s" % [k, st.get_length()])
	get_tree().quit()


func _wipe_shot(kind: String, after: float) -> void:
	await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://wipe_%s.png" % kind)


## gh #19 phase 2: the generic subanim player. Checks frame building (counts, the enemy-turn
## transform, TACKLE = SE-only = no frames yet), plays a real {"moveanim"} marker through the
## queue, and poses mid-animation frames for two moves as screenshots.
func _moveanimtest() -> void:
	await get_tree().process_frame
	start_battle("rattata", 3)
	var b = battle
	# 1) Step building, straight from the data (no timing involved).
	for mv in ["POUND", "THUNDER", "EMBER", "GUST", "ROCK_SLIDE", "GROWL", "TACKLE", "SEISMIC_TOSS"]:
		var fs: Array = b._build_move_anim(mv, true)
		var ses := 0
		for f in fs:
			if f.has("se"):
				ses += 1
		print("[moveanim] %s: %d steps (%d special effects)" % [mv, fs.size(), ses])
	var covered := 0
	var with_sprites := 0
	for mv in b._manim["anims"]:
		var fs: Array = b._build_move_anim(str(mv), true)
		if not fs.is_empty():
			covered += 1
		for f in fs:
			if not f.has("se"):
				with_sprites += 1
				break
	print("[moveanim] %d/%d anims produce steps, %d with sprite frames"
		% [covered, b._manim["anims"].size(), with_sprites])
	# The enemy-turn transform must move the sprites (POUND's star subanim is HFLIP).
	var pp: Array = b._build_move_anim("POUND", true)[0]["sprites"]
	var pe: Array = b._build_move_anim("POUND", false)[0]["sprites"]
	print("[moveanim] POUND first sprite player=(%d,%d) enemy=(%d,%d) (expect mirrored+down)"
		% [pp[0][2], pp[0][3], pe[0][2], pe[0][3]])
	# 2) Drive to the battle menu, then play a marker through the queue with real timing
	# (fast_hp is auto-set for tests and would skip the animation -- undo it here).
	var g := 0
	while b.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	b.fast_hp = false
	var t0 := Time.get_ticks_msec()
	b.queue = [{"moveanim": "THUNDER", "attacker": "player"}]
	b.after = "menu"
	b._next_msg()
	g = 0
	while b.state != "menu" and g < 900:
		await get_tree().process_frame; g += 1
	print("[moveanim] THUNDER marker: %d ms (expect >500), sprites cleared=%s, state=%s"
		% [Time.get_ticks_msec() - t0, str(b._anim_sprites.is_empty()), b.state])
	t0 = Time.get_ticks_msec()                          # an SE-heavy anim: lunge + screen flash
	b.queue = [{"moveanim": "TACKLE", "attacker": "player"}]
	b.after = "menu"
	b._next_msg()
	g = 0
	while b.state != "menu" and g < 900:
		await get_tree().process_frame; g += 1
	print("[moveanim] TACKLE (SE-only) marker: %d ms, offset reset=%s, pal reset=%s"
		% [Time.get_ticks_msec() - t0, str(b._anim_off["player"] == Vector2.ZERO), str(b._anim_pal == "")])
	# 2a2) The gh #20 special effects: smoke-play each new one; transient state must clear.
	for se in ["spiral_balls_inward", "shoot_balls_upward", "water_droplets_everywhere",
			"wavy_screen", "bounce_up_and_down", "shake_back_and_forth", "squish_mon_pic",
			"minimize_mon", "leaves_falling", "petals_falling", "shake_enemy_hud",
			"slide_mon_half_off", "transform_mon"]:
		await b._do_special_effect(se, true)
	var se_clean: bool = b._fx.is_empty() and b._anim_shake == Vector2.ZERO \
		and b._anim_hud_off == Vector2.ZERO
	b._anim_hidden = {"player": false, "enemy": false}
	b._anim_scale = {"player": Vector2.ONE, "enemy": Vector2.ONE}
	b._anim_off = {"player": Vector2.ZERO, "enemy": Vector2.ZERO}
	b._load_back()                                       # undo transform_mon's texture swap
	print("[moveanim] gh#20 SEs smoke-played: state_clean=%s" % se_clean)
	# Per-anim frame-block hooks: the builder attaches the counting-down block counter, and a
	# hooked anim (MEGA_PUNCH flashes after every block) plays through with clean state.
	var tb: Array = b._build_move_anim("THUNDERBOLT", true)
	var counters := 0
	for st2 in tb:
		if st2.has("counter"):
			counters += 1
	b.queue = [{"moveanim": "MEGA_PUNCH", "attacker": "player"}]
	b.after = "menu"
	b._next_msg()
	g = 0
	while b.state != "menu" and g < 900:
		await get_tree().process_frame; g += 1
	print("[moveanim] hooks: THUNDERBOLT counted_blocks=%d (>0) hook=%s | MEGA_PUNCH played flash_reset=%s"
		% [counters, b._manim["anim_special_effects"].get("THUNDERBOLT"), str(not b._anim_flash)])
	# The ball anims play from the generic data (gh #20 poof unification): POOF_ANIM's steps
	# land in the player-mon box, and TOSS/SHAKE build too.
	var pf: Array = b._build_move_anim("POOF_ANIM", true)      # default = the enemy box (catch)
	var pfp: Array = b._build_move_anim("POOF_ANIM", false)    # flipped = our box (send-out)
	var s0: Array = pf[0]["sprites"][0] if not pf.is_empty() else [0, 0, -1, -1]
	var s1: Array = pfp[0]["sprites"][0] if not pfp.is_empty() else [0, 0, -1, -1]
	print("[moveanim] ball anims: POOF steps=%d catch_side=(%d,%d) sendout_side=(%d,%d) TOSS=%d SHAKE=%d"
		% [pf.size(), int(s0[2]), int(s0[3]), int(s1[2]), int(s1[3]),
		b._build_move_anim("TOSS_ANIM", true).size(), b._build_move_anim("SHAKE_ANIM", true).size()])
	# 2b) A real fight turn through _do_move (gh #19 phase 4): the move's animation is queued in
	# place of the old hit flash and its sprites appear while the turn plays out. The displayed
	# enemy HP must still be the pre-damage value while the animation runs — the bar drains only
	# at its queued {"hp"} marker, after the animation and hit reaction.
	var saw_sprites := false
	var shown_at_anim := -1.0
	var e0: int = b.enemy_mon["hp"]
	await _press("ui_accept")                 # FIGHT
	await _press("ui_accept")                 # first move
	g = 0
	while b.state != "menu" and modal == battle and g < 900:
		if not b._anim_sprites.is_empty():
			saw_sprites = true
			if shown_at_anim < 0.0:
				shown_at_anim = float(b._shown_hp["enemy"])
		await _press("ui_accept")
		g += 1
	print("[moveanim] real turn: anim sprites shown=%s dealt dmg=%s state=%s"
		% [str(saw_sprites), str(e0 - int(b.enemy_mon["hp"]) > 0), b.state])
	print("[moveanim] drain order: enemy bar during anim=%.0f (expect pre-damage %d), after=%.0f"
		% [shown_at_anim, e0, float(b._shown_hp["enemy"])])
	# 2c) The hit-reaction order (PlayApplyingAttackAnimation): the queue must run
	# animation -> sting -> blink/shake -> HP drain, and status moves get the slow shake.
	e0 = b.enemy_mon["hp"]
	for probe in [["POUND", "expect moveanim, sfx, anim(hit), hp"],
			["EMBER", "expect moveanim, sfx, anim(shake), hp"],
			["GROWL", "expect moveanim, anim(sway)"]]:
		var ms: Array = []
		b.enemy_mon["hp"] = b.enemy_mon["maxhp"]     # each probe needs a live target
		b._do_move(b.player_mon, b.enemy_mon, str(probe[0]), ms, b.p_stages, b.e_stages, true)
		var kinds: Array = []
		for it in ms:
			if it is Dictionary:
				kinds.append(str(it.keys()[0]) + ("(%s)" % str(it["anim"]) if it.has("anim") else ""))
		print("[moveanim] %s markers: %s (%s)" % [probe[0], str(kinds), probe[1]])
	b.enemy_mon["hp"] = e0
	b.e_stages = b._new_stages()
	# 3) Pose mid-animation frames over the live scene and screenshot them.
	var fth: Array = b._build_move_anim("THUNDER", true)
	b._anim_sprites = fth[fth.size() >> 1]["sprites"]
	b.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://moveanim_thunder.png")
	var fg: Array = b._build_move_anim("GUST", false)   # enemy's turn: transform in effect
	b._anim_sprites = fg[fg.size() >> 1]["sprites"]
	b.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://moveanim_gust_enemy.png")
	# gh #20 faithful wavy_screen: freeze the live battle frame and pose the raster wave at a phase
	# that spans the full ±2 px offset range, so the shot shows the per-scanline ripple.
	b._anim_sprites = []
	b.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	b._wavy_tex = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	b._wavy_phase = 8
	b.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://moveanim_wavy.png")
	b._wavy_tex = null
	b.queue_redraw()
	print("[moveanim] shots: moveanim_thunder.png, moveanim_gust_enemy.png, moveanim_wavy.png")
	# 2d) Killing blow: the fainted mon's pic must survive the anim/hit/drain sequence and go
	# away only when its faint slide finishes (SlideDownFaintedMonPic), not at damage time.
	b._anim_sprites = []                      # clear the posed screenshot frame
	b.queue_redraw()
	b.enemy_mon["hp"] = 1
	var pic_during_anim := false
	var gone_after := false
	await _press("ui_accept")                 # FIGHT
	await _press("ui_accept")                 # first move -> the killing blow
	g = 0
	var faint_shot := false
	while modal == battle and g < 900:
		if not b._anim_sprites.is_empty() and not b._pic_gone["enemy"]:
			pic_during_anim = true
		if b._pic_gone["enemy"]:
			gone_after = true
		if not faint_shot and b._faint_who == "enemy" and b._faint_t > 0.3:
			faint_shot = true                 # mid-slide: only the sinking copy may be drawn
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://faint_mid.png")
		await _press("ui_accept")
		g += 1
	print("[moveanim] killing blow: pic held through anim=%s removed by faint slide=%s over=%s mid-shot=%s"
		% [str(pic_during_anim), str(gone_after), str(modal != battle), str(faint_shot)])
	get_tree().quit()


func _faithtest() -> void:
	await get_tree().process_frame
	start_battle("rattata", 3)
	var b = battle
	var P: Dictionary = b.player_mon
	var E: Dictionary = b.enemy_mon
	var ms: Array = []
	# Toxic: damage escalates each tick (base, 2*base, ...).
	E["maxhp"] = 100; E["hp"] = 100; E["status"] = "psn"; b.e_vol["toxic"] = 1
	b._residual(E, b.e_vol, P, ms); var t1: int = 100 - int(E["hp"])
	var hpb: int = int(E["hp"]); b._residual(E, b.e_vol, P, ms); var t2: int = hpb - int(E["hp"])
	var toxic_ok: bool = t1 > 0 and t2 == 2 * t1
	print("[faith] TOXIC ticks: %d then %d (expect 2nd = 2x)" % [t1, t2])
	# Substitute blocks a stat-down move. The engine gates on sub_up, not sub HP (gh #78 — without
	# the flag these two checks measured the *absence* of a substitute and passed vacuously).
	E["status"] = ""; b.e_vol["toxic"] = 0; b.e_vol["sub"] = 25; b.e_vol["sub_up"] = true; b.e_stages["atk"] = 0
	b._do_move(P, E, "GROWL", ms, b.p_stages, b.e_stages, true)
	var sub_blocks_ok: bool = int(b.e_stages["atk"]) == 0
	print("[faith] SUB vs GROWL: enemy ATK stage=%d (expect 0)" % int(b.e_stages["atk"]))
	# Substitute absorbs damage (enemy HP unchanged, sub shrinks).
	E["hp"] = 100; var s0: int = int(b.e_vol["sub"]); var h0: int = int(E["hp"])
	for i in range(8):
		b._do_move(P, E, "TACKLE", ms, b.p_stages, b.e_stages, true)
		if int(b.e_vol["sub"]) < s0:
			break
	var sub_soaks_ok: bool = int(b.e_vol["sub"]) < s0 and int(E["hp"]) == h0
	print("[faith] SUB absorbs: sub %d->%d, enemy hp %d->%d (expect sub shrinks, hp unchanged)" % [
		s0, int(b.e_vol["sub"]), h0, int(E["hp"])])
	# Trapping locks the target and the user.
	b.e_vol["sub"] = 0; b.e_vol["sub_up"] = false
	for i in range(12):
		b.e_vol["bound"] = 0; b.p_vol["bind"] = 0; E["hp"] = 100
		b._do_move(P, E, "WRAP", ms, b.p_stages, b.e_stages, true)
		if int(b.e_vol["bound"]) > 0:
			break
	var wrap_ok: bool = int(b.e_vol["bound"]) > 0 and int(b.p_vol["bind"]) > 0
	print("[faith] WRAP: target bound=%d, user bind=%d (expect > 0)" % [int(b.e_vol["bound"]), int(b.p_vol["bind"])])
	# Transform copies the target's stats/types.
	P["types"] = ["FIRE"]; P["atk"] = 1; b.p_vol["sub"] = 0; b.e_vol["sub"] = 0
	b._do_move(P, E, "TRANSFORM", ms, b.p_stages, b.e_stages, true)
	var transform_ok: bool = P["types"] == E["types"] and int(P["atk"]) == int(E["atk"])
	print("[faith] TRANSFORM: player types=%s atk=%d (enemy atk=%d)" % [str(P["types"]), int(P["atk"]), int(E["atk"])])
	# EXP split between two participants.
	b.participants = [0, 1]
	var a0: int = int(player_party[0]["exp"]); var a1: int = int(player_party[1]["exp"])
	var sm: Array = []; b._award_exp(sm)
	var exp_ok: bool = int(player_party[0]["exp"]) > a0 and int(player_party[1]["exp"]) > a1
	print("[faith] EXP split: mon0 +%d, mon1 +%d (both > 0)" % [int(player_party[0]["exp"]) - a0, int(player_party[1]["exp"]) - a1])
	print("[faith] PASS=%s (toxic=%s sub_blocks=%s sub_soaks=%s wrap=%s transform=%s exp=%s)" % [
		toxic_ok and sub_blocks_ok and sub_soaks_ok and wrap_ok and transform_ok and exp_ok,
		toxic_ok, sub_blocks_ok, sub_soaks_ok, wrap_ok, transform_ok, exp_ok])
	get_tree().quit()


func _learntest() -> void:
	await get_tree().process_frame
	var pmon: Dictionary = player_party[0]
	pmon["moves"] = [{"move": "SCRATCH", "pp": 35, "maxpp": 35}, {"move": "GROWL", "pp": 40, "maxpp": 40},
		{"move": "EMBER", "pp": 25, "maxpp": 25}, {"move": "TACKLE", "pp": 35, "maxpp": 35}]
	pmon["level"] = 14
	pmon["exp"] = exp_for_level(15, str(pmon["growth"])) - 5     # one win from L15 (learns LEER)
	start_battle("rattata", 2)
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	battle.enemy_mon["hp"] = 1
	g = 0
	while battle.state != "learn" and modal == battle and g < 60:
		await _press("ui_accept"); g += 1
	print("[learntest] reached state=%s (expect learn), level=%d" % [battle.state, int(pmon["level"])])
	get_viewport().get_texture().get_image().save_png("res://learn1.png")
	if battle.state == "learn":
		await _press("ui_accept")              # forget slot 0 (SCRATCH) for LEER
		g = 0
		while modal == battle and g < 30:
			await _press("ui_accept"); g += 1
		var names := []
		for mv in pmon["moves"]:
			names.append(mv["move"])
		print("[learntest] after prompt: moves=%s (expect LEER in slot 0)" % str(names))
	# gh #93: an HM in the chosen slot must be refused — learn_move.asm checks IsMoveHM, prints
	# HMCantDeleteText and jumps back to the list. Without it a level-up silently deletes SURF, and
	# Cinnabar, Route 23 and Seafoam all need it: the save is stranded with no way to notice.
	pmon["moves"] = [{"move": "SURF", "pp": 15, "maxpp": 15}, {"move": "GROWL", "pp": 40, "maxpp": 40},
		{"move": "EMBER", "pp": 25, "maxpp": 25}, {"move": "TACKLE", "pp": 35, "maxpp": 35}]
	pmon["level"] = 14
	pmon["exp"] = exp_for_level(15, str(pmon["growth"])) - 5
	start_battle("rattata", 2)
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	battle.enemy_mon["hp"] = 1
	g = 0
	while battle.state != "learn" and modal == battle and g < 60:
		await _press("ui_accept"); g += 1
	var refused := false
	var surf_kept := false
	if battle.state == "learn":
		battle.cursor = 0                      # try to delete SURF
		await _press("ui_accept")
		g = 0
		while battle.state != "learn" and modal == battle and g < 60:
			await _press("ui_accept"); g += 1  # "HM techniques can't be deleted!" -> back to the list
		refused = battle.state == "learn"
		surf_kept = str(pmon["moves"][0]["move"]) == "SURF"
		battle.cursor = 1                      # give up GROWL instead
		await _press("ui_accept")
		g = 0
		while modal == battle and g < 40:
			await _press("ui_accept"); g += 1
	var kept: Array = []
	for mv in pmon["moves"]:
		kept.append(mv["move"])
	var learned: bool = "LEER" in kept and "SURF" in kept
	print("[learntest] HM guard: re-prompted=%s surf_kept=%s final=%s" % [refused, surf_kept, str(kept)])
	# gh #121: B on the move-forget screen gives up learning (learn_move.asm .cancel), no move replaced.
	pmon["moves"] = [{"move": "SCRATCH", "pp": 35, "maxpp": 35}, {"move": "GROWL", "pp": 40, "maxpp": 40},
		{"move": "EMBER", "pp": 25, "maxpp": 25}, {"move": "TACKLE", "pp": 35, "maxpp": 35}]
	pmon["level"] = 14
	pmon["exp"] = exp_for_level(15, str(pmon["growth"])) - 5   # one win from L15 (would learn LEER)
	start_battle("rattata", 2)
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	battle.enemy_mon["hp"] = 1
	g = 0
	while battle.state != "learn" and modal == battle and g < 60:
		await _press("ui_accept"); g += 1
	var gave_up := false
	if battle.state == "learn":
		await _press("ui_cancel")                # B -> give up learning
		g = 0
		while modal == battle and g < 40:
			await _press("ui_accept"); g += 1
		var after: Array = []
		for m in pmon["moves"]:
			after.append(str(m["move"]))
		gave_up = "LEER" not in after            # LEER not learned; original 4 moves kept
	print("[learntest] give-up (B): move_not_learned=%s" % gave_up)
	print("[learntest] PASS=%s" % (refused and surf_kept and learned and gave_up))
	get_tree().quit()


func _stonetest() -> void:
	await get_tree().process_frame
	battle.fast_hp = true                                # skip the evolution flicker so the logic check
	                                                     # completes quickly (the animation is ~4 s otherwise)
	player_party.append(make_mon("clefairy", 12, []))
	var idx: int = player_party.size() - 1
	var mon: Dictionary = player_party[idx]
	print("[stonetest] party mon = %s" % mon["name"])
	open_start_menu()
	_on_menu_chosen(menu.items.find("ITEM"))             # the list shifts: find ITEM by text (gh #64)
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://stone_bag.png")
	print("[stonetest] bag = %s" % str(menu_keys))
	_on_menu_chosen(int(menu_keys.find("MOON STONE")))   # pick MOON STONE -> USE/TOSS
	_on_menu_chosen(0)                                   # USE -> party target
	await get_tree().process_frame
	_on_menu_chosen(idx)               # use it on Clefairy -> the evolution sequence (gh #67)
	var g := 0
	while str(mon["name"]) != "CLEFABLE" and g < 200:
		if modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	get_viewport().get_texture().get_image().save_png("res://stone_evo.png")
	print("[stonetest] after: %s (expect CLEFABLE), stones left=%d (expect 0)" % [
		mon["name"], int(player_bag.get("MOON STONE", 0))])
	# gh #134: a stone evolution is FORCED — B must NOT cancel it. Drive one non-fast with B held; it
	# must still evolve (a level-up evolution, forced=false, WOULD cancel and stay CLEFAIRY here).
	battle.fast_hp = false
	var mon2: Dictionary = make_mon("clefairy", 12, [])
	player_party.append(mon2)
	Input.action_press("ui_cancel")                      # hold B throughout the animation
	run_evolution(mon2, "CLEFABLE", true)                # forced (stone) — fire-and-forget coroutine
	var g2 := 0
	while str(mon2["name"]) != "CLEFABLE" and g2 < 800:
		await get_tree().process_frame
		if modal == textbox and textbox.visible:
			textbox.advance()
		g2 += 1
	Input.action_release("ui_cancel")
	print("[stonetest] forced+B-held: %s (expect CLEFABLE — a stone evo can't be canceled, gh #134)" % mon2["name"])
	get_tree().quit()


func _tradetest() -> void:
	await get_tree().process_frame
	print("[tradetest] %d NPC trade texts mapped" % int(trades_data.get("text_trades", {}).size()))
	Engine.time_scale = 5.0
	pt_time_scale = 5.0
	# Real NPC trade (Cerulean gambler, dialogset EVOLUTION): give POLIWHIRL, receive JYNX
	# through the full dialog (YES -> party pick) and the trade movie (gh #185).
	var lola: Dictionary = trades_data["trades"][6]
	player_party.append(make_mon(str(lola["give"]), 20, []))
	var i1: int = player_party.size() - 1
	_start_trade("TEXT_CERULEANTRADEHOUSE_GAMBLER", 6)
	var strip := "--strip" in OS.get_cmdline_user_args()   # save a frame every 12 for review
	var strip_n := 0
	var g := 0
	var shot := false
	var card_shot := false
	var ball_shot := false
	var roll_shot := false
	while cutscene_active and g < 9000:
		await get_tree().process_frame
		if strip and trademovie.visible and g % 12 == 0 and strip_n < 90:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://strip/tm_%03d.png" % strip_n)
			strip_n += 1
			await get_tree().process_frame
		if trademovie._phase == "show_mon" and trademovie._t > 63.0 and not card_shot:
			card_shot = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://trade_card.png")
			await get_tree().process_frame
		elif trademovie._phase == "show_mon" and not trademovie._anim_sprites.is_empty() \
				and not ball_shot:
			ball_shot = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://trade_ball.png")
			await get_tree().process_frame
		elif trademovie._phase == "ball_roll" and trademovie._t > 20 and not roll_shot:
			roll_shot = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://trade_roll.png")
			await get_tree().process_frame
		elif trademovie._phase == "crawl" and not shot:
			shot = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://trade_crawl.png")
			await get_tree().process_frame
		elif modal == menu and menu_mode == "cutscene":
			menu.chosen.emit(i1 if menu.party_mode else 0)   # YES, then the POLIWHIRL slot
		elif modal == textbox and textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	var got_lola: bool = str(player_party[i1]["name"]) == str(lola["nick"]) \
		and str(player_party[i1]["species"]) == str(lola["get"]) \
		and str(player_party[i1]["ot"]) == "TRAINER"
	print("[tradetest] LOLA trade: slot=%s ot=%s crawl_shot=%s (expect LOLA/TRAINER)" % [
		player_party[i1]["name"], player_party[i1]["ot"], shot])
	# Talking again: the dialog-set after-trade line ("went and evolved", set EVOLUTION).
	_start_trade("TEXT_CERULEANTRADEHOUSE_GAMBLER", 6)
	await get_tree().process_frame
	var after_ok: bool = "went and evolved!" in "\n".join(textbox.pages)
	g = 0
	while textbox.active and g < 60:
		textbox.advance()
		await get_tree().process_frame
		g += 1
	textbox.visible = false
	print("[tradetest] after-trade line=%s" % after_ok)
	# Trade evolution: a trade-evo species runs the full uncancellable sequence (gh #67).
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_party.append(make_mon("abra", 30, []))
	var i2: int = player_party.size() - 1
	var st := {"done": false}
	var run2 := func() -> void:
		await _do_trade(i2, "haunter")
		st["done"] = true
	run2.call()
	g = 0
	while not bool(st["done"]) and g < 9000:
		await get_tree().process_frame
		if modal == textbox and textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	get_viewport().get_texture().get_image().save_png("res://trade_evo.png")
	print("[tradetest] trade-evo: slot=%s (expect GENGAR)" % player_party[i2]["name"])
	print("[tradetest] PASS=%s" % (got_lola and shot and after_ok
		and str(player_party[i2]["name"]) == "GENGAR"))
	Engine.time_scale = 1.0
	get_tree().quit()


func _edgetest() -> void:
	await get_tree().process_frame
	# DVs: a max-DV mon out-stats a min-DV one of the same species/level.
	var lo := make_mon("rattata", 50, [], {"hp": 0, "atk": 0, "def": 0, "spd": 0, "spc": 0})
	var hi := make_mon("rattata", 50, [], {"hp": 15, "atk": 15, "def": 15, "spd": 15, "spc": 15})
	print("[edge] DV rattata L50: atk %d->%d, maxhp %d->%d (hi>lo)" % [
		lo["atk"], hi["atk"], lo["maxhp"], hi["maxhp"]])
	var distinct := {}
	for i in range(24):
		distinct[make_mon("pidgey", 40, [])["maxhp"]] = true
	print("[edge] random-DV pidgey L40: %d distinct maxHP in 24 rolls" % distinct.size())
	# Crit edge cases via _calc_hit.
	start_battle("rattata", 60)
	var b = battle
	var P: Dictionary = b.player_mon
	var E: Dictionary = b.enemy_mon
	var md: Dictionary = b.moves_db["TACKLE"]
	E["def"] = 20                                  # lower DEF so damage isn't floored to 1
	var st_lo := {"atk": -6, "def": 0, "spc": 0, "spd": 0, "acc": 0, "eva": 0}
	var st_0 := {"atk": 0, "def": 0, "spc": 0, "spd": 0, "acc": 0, "eva": 0}
	# Crit ignores the ATK stage: crit dmg is ~equal at -6 and 0; non-crit dmg is far lower at -6.
	var cl := 0; var cln := 0; var ch := 0; var chn := 0; var nl := 0; var nln := 0; var nh := 0; var nhn := 0
	for i in range(4000):
		var rl: Dictionary = b._calc_hit(P, E, md, st_lo, st_0, b._new_vol(), b._new_vol())
		if rl["crit"]: cl += int(rl["dmg"]); cln += 1
		else: nl += int(rl["dmg"]); nln += 1
		var rh: Dictionary = b._calc_hit(P, E, md, st_0, st_0, b._new_vol(), b._new_vol())
		if rh["crit"]: ch += int(rh["dmg"]); chn += 1
		else: nh += int(rh["dmg"]); nhn += 1
	print("[edge] crit avg: -6 ATK=%d, 0 ATK=%d (≈equal, stage ignored)" % [cl / max(1, cln), ch / max(1, chn)])
	print("[edge] non-crit avg: -6 ATK=%d, 0 ATK=%d (-6 far lower)" % [nl / max(1, nln), nh / max(1, nhn)])
	var vf: Dictionary = b._new_vol(); vf["focus"] = true
	var c_no := 0; var c_fc := 0
	for i in range(3000):
		if bool(b._calc_hit(P, E, md, st_0, st_0, b._new_vol(), b._new_vol())["crit"]): c_no += 1
		if bool(b._calc_hit(P, E, md, st_0, st_0, vf, b._new_vol())["crit"]): c_fc += 1
	print("[edge] Focus Energy bug: crits/3000 no-focus=%d focus=%d (focus fewer)" % [c_no, c_fc])
	get_tree().quit()


func _savetest() -> void:
	await get_tree().process_frame
	# Save/load round-trip.
	player_money = 4242
	player_bag["POTION"] = 7
	defeated_trainers["map:1,1"] = true
	player_party[0]["hp"] = 3
	player_party[0]["level"] = 17
	print("[savetest] saved=%s" % save_game())
	player_money = 0; player_bag = {}; defeated_trainers = {}
	player_party = [make_mon("rattata", 2, [])]
	var ok := load_game()
	print("[savetest] loaded=%s money=%d potions=%d party0=%s L%d hp=%d defeated=%s" % [
		ok, player_money, int(player_bag.get("POTION", 0)), player_party[0]["name"],
		int(player_party[0]["level"]), int(player_party[0]["hp"]), defeated_trainers.has("map:1,1")])
	# Overworld poison tick (every 4 steps -> -1 HP).
	var pm := make_mon("charmander", 50, [])
	pm["status"] = "psn"
	player_party = [pm]
	var hp0: int = pm["hp"]
	for i in range(4):
		_overworld_poison()
	print("[savetest] poison: hp %d->%d after 4 steps (expect -1)" % [hp0, int(pm["hp"])])
	# gh #184: a save made on the Hall of Fame floor (with a team recorded) CONTINUEs in Pallet
	# Town at the fly point — main_menu.asm .choseContinue's HALL_OF_FAME special warp.
	hall_of_fame = [[{"species": "pidgey", "name": "PIDGEY", "level": 40}]]
	load_world("HallOfFame", 0)
	save_game()
	load_world("ViridianCity")                           # scramble so the load must move us
	var hof_ok := load_game()
	print("[savetest] hof_continue(gh#184): loaded=%s map=%s (expect PalletTown) cell=%s facing=%d" % [
		hof_ok, center_label, str(player.cell), player.facing])
	DirAccess.open("user://").remove(SAVE_PATH.get_file())   # clean the test save
	get_tree().quit()


## PLAYABLE setup for gh #118: stand on the Vermilion Dock with HM01 in hand — the S.S. ANNE
## sets sail on arrival (VermilionDock.on_enter) — then keep playing to inspect the dock tiles.
## Uses the isolated test save. Run: `pwsh tools/run.ps1 -- --dockscene`.
func _dockscene() -> void:
	await get_tree().process_frame
	if audio:
		audio.enabled = true                        # a viewing session, not a headless test
	player_name = "RED"
	player_party = [make_mon("squirtle", 20, ["TACKLE"])]
	set_event("GOT_HM01")
	load_world("VermilionDock", -1, Vector2i(14, 2))


func _healtest() -> void:
	await get_tree().process_frame
	load_world("CeruleanPokecenter", -1, Vector2i(3, 3), false)
	player.facing = player.UP                      # stand below the counter, heal across it (#17)
	player_party[0]["hp"] = 1
	player_party[0]["status"] = "psn"
	player_party[1]["hp"] = 1
	for mv in player_party[0]["moves"]:
		mv["pp"] = 0
	await RenderingServer.frame_post_draw
	var base_img := get_viewport().get_texture().get_image()   # the machine area, no balls yet
	var healed := interact(player)
	var g := 0
	var saw_balls := false                          # the machine ceremony shows the party's balls
	var ball_px := false                            # ...and they actually RENDER (gh #31/#69):
	while (cutscene_active or modal != null) and g < 900:      # the ball rows must CHANGE pixels
		saw_balls = saw_balls or cutscene._heal_balls > 0
		if not ball_px and cutscene._heal_balls >= 2 and not cutscene._heal_flash:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			# gh #159: the balls draw in the machine's slot panel (screen 40..56 × 27..35 for the
			# first pair — the OAM coords minus the hardware offsets), not on the counter front.
			for sx in range(40, 56):
				for sy in range(27, 35):
					if img.get_pixel(sx, sy) != base_img.get_pixel(sx, sy):
						ball_px = true
			if ball_px:
				img.save_png("res://heal_machine_shot.png")
		if modal == menu:
			await _press("ui_accept")               # "Shall we heal your POKéMON?" -> YES
		elif modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	print("[healtest] nurse interact=%s, p0 hp=%d/%d status='%s' pp0=%d, p1 hp=%d/%d, balls=%s rendered=%s" % [
		healed, int(player_party[0]["hp"]), int(player_party[0]["maxhp"]),
		str(player_party[0]["status"]), int(player_party[0]["moves"][0]["pp"]),
		int(player_party[1]["hp"]), int(player_party[1]["maxhp"]), saw_balls, ball_px])
	get_tree().quit()


func _towerhealtest() -> void:
	await get_tree().process_frame
	var dvs := {"hp": 0, "atk": 0, "def": 0, "spd": 0, "spc": 0}
	player_party = [make_mon("charmander", 10, ["SCRATCH", "GROWL"], dvs)]
	player_party[0]["hp"] = 1
	player_party[0]["status"] = "psn"
	for mv in player_party[0]["moves"]:
		mv["pp"] = 0
	# Start below the purified zone, then drive a real step into (10,9); scripts/PokemonTower5F.asm
	# uses map-cell coordinates (10,8), (11,8), (10,9), and (11,9).
	load_world("PokemonTower5F", -1, Vector2i(10, 10), false)
	var stepped: bool = await _pt_step(player.UP)
	var g := 0
	var saw_battle: bool = modal == battle
	while modal != textbox and g < 300:
		await get_tree().process_frame
		saw_battle = saw_battle or modal == battle
		g += 1
	var message_shown: bool = modal == textbox and not textbox.pages.is_empty() \
			and str(textbox.pages[0]) == "Entered purified,\nprotected zone!"
	var mon: Dictionary = player_party[0]
	var healed := int(mon["hp"]) == int(mon["maxhp"]) and str(mon["status"]) == ""
	for mv in mon["moves"]:
		healed = healed and int(mv["pp"]) == int(mv["maxpp"])
	var encounter_suppressed: bool = not saw_battle
	assert(stepped and player.cell == Vector2i(10, 9), "tower heal test must step into the purified zone")
	assert(healed, "Pokemon Tower purified zone should fully heal HP, PP, and status")
	assert(message_shown, "Pokemon Tower purified-zone message should be shown")
	assert(encounter_suppressed, "Pokemon Tower purified zone should suppress wild encounters")
	print("[towerhealtest] healed=%s message_shown=%s stepped=%s encounter_suppressed=%s hp=%d/%d status='%s' pp=%d/%d" % [
		healed, message_shown, stepped, encounter_suppressed, int(mon["hp"]), int(mon["maxhp"]),
		str(mon["status"]), int(mon["moves"][0]["pp"]), int(mon["moves"][0]["maxpp"])])
	textbox.advance()
	await get_tree().process_frame
	get_tree().quit()


func _silphnursetest() -> void:
	await get_tree().process_frame
	var dvs := {"hp": 0, "atk": 0, "def": 0, "spd": 0, "spc": 0}
	player_party = [make_mon("charmander", 10, ["SCRATCH", "GROWL"], dvs)]
	var mon: Dictionary = player_party[0]
	mon["hp"] = 1
	mon["status"] = "psn"
	for mv in mon["moves"]:
		mv["pp"] = 0
	clear_event("BEAT_SILPH_CO_GIOVANNI")
	load_world("SilphCo9F", -1, Vector2i(3, 15), false)
	player.facing = player.UP
	var interacted: bool = interact(player)
	var g := 0
	var nurse_ceremony := false
	var tired_text := false
	var encouragement_text := false
	while (cutscene_active or modal != null) and g < 900:
		nurse_ceremony = nurse_ceremony or cutscene._heal_monitor \
				or cutscene._heal_balls > 0 or modal == menu
		if modal == textbox:
			var shown: String = "\f".join(textbox.pages)
			tired_text = tired_text or shown == "You look tired!\nYou should take a\fquick nap!"
			encouragement_text = encouragement_text or shown == "Don't give up!"
			textbox.advance()
		await get_tree().process_frame
		g += 1
	var healed: bool = int(mon["hp"]) == int(mon["maxhp"]) and str(mon["status"]) == ""
	for mv in mon["moves"]:
		healed = healed and int(mv["pp"]) == int(mv["maxpp"])
	assert(interacted, "Silph Co. 9F nurse interaction should be handled by the map adapter")
	assert(healed, "Silph Co. 9F nurse should fully heal HP, PP, and status before Giovanni")
	assert(not nurse_ceremony, "Silph Co. 9F nurse must not run the Poké Center healing-machine ceremony")
	assert(tired_text and encouragement_text, "Silph Co. 9F nurse should show both pre-Giovanni messages")

	set_event("BEAT_SILPH_CO_GIOVANNI")
	mon["hp"] = 1
	mon["status"] = "psn"
	for mv in mon["moves"]:
		mv["pp"] = 0
	var thanks_interacted: bool = interact(player)
	var thanks_text := false
	g = 0
	while (cutscene_active or modal != null) and g < 300:
		if modal == textbox:
			thanks_text = thanks_text or "\f".join(textbox.pages) == "Thank you so\nmuch!"
			textbox.advance()
		await get_tree().process_frame
		g += 1
	var thanks_no_heal: bool = int(mon["hp"]) == 1 and str(mon["status"]) == "psn"
	for mv in mon["moves"]:
		thanks_no_heal = thanks_no_heal and int(mv["pp"]) == 0
	assert(thanks_interacted and thanks_text, "Silph Co. 9F nurse should only thank the player after Giovanni")
	assert(thanks_no_heal, "Silph Co. 9F nurse should not heal after Giovanni")
	print("[silphnursetest] healed=%s nurse_ceremony=%s thanks_no_heal=%s tired_text=%s encouragement_text=%s thanks_text=%s" % [
		healed, nurse_ceremony, thanks_no_heal, tired_text, encouragement_text, thanks_text])
	get_tree().quit()


func _audiotest() -> void:
	await get_tree().process_frame
	audio.enabled = true
	print("[audiotest] note_hz A oct3=%.1f (expect 440), C oct3=%.1f (expect 261.6)" % [
		audio.note_hz("A", 3), audio.note_hz("C", 3)])
	# silphco/dungeon3 ramp the global tempo mid-song — all channels must retime together
	for key in ["pallettown", "wildbattle", "routes1", "silphco", "dungeon3"]:
		var t0 := Time.get_ticks_msec()
		var wav: AudioStreamWAV = audio._synth(audio.songs[key])
		var ms := Time.get_ticks_msec() - t0
		var data := wav.data
		var n := int(data.size() / 2)
		var peak := 0
		var nz := 0
		var cap: int = min(n, 300000)
		for i in cap:
			var s: int = data.decode_s16(i * 2)
			peak = max(peak, abs(s))
			if s != 0:
				nz += 1
		print("[audiotest] %s: %.1fs, synth %dms, peak=%d, nonzero=%d%%" % [
			key, n / 22050.0, ms, peak, nz * 100 / max(1, cap)])
	for sk in ["press_ab", "cry04"]:
		var sw: AudioStreamWAV = audio._synth_sfx(audio.sfx[sk], 256, 0)
		var sn := int(sw.data.size() / 2)
		var sp := 0
		for i in sn:
			sp = max(sp, abs(sw.data.decode_s16(i * 2)))
		print("[audiotest] sfx %s: %.2fs peak=%d" % [sk, sn / 22050.0, sp])
	audio.enabled = true
	var cd: Dictionary = audio.cries["charmander"]
	var cry: AudioStreamWAV = audio._synth_sfx(audio.sfx[str(cd["cry"])], 0x80 + int(cd["length"]), int(cd["pitch"]))
	print("[audiotest] cry charmander: base=%s pitch=%d len=%d -> %.2fs" % [
		cd["cry"], cd["pitch"], cd["length"], cry.data.size() / 2 / 22050.0])
	# gh #73: loop points — a looping song's wav loops from its sound_loop 0 point (never
	# replaying the intro), a jingle doesn't loop at all, and the title screen's drums keep
	# cycling after its one-shot melody channels end.
	var pw: AudioStreamWAV = audio._synth(audio.songs["pallettown"])
	var iw: AudioStreamWAV = audio._synth(audio.songs["introbattle"])
	var tw: AudioStreamWAV = audio._synth(audio.songs["titlescreen"])
	var dw: AudioStreamWAV = audio._synth(audio.songs["dungeon3"])
	print("[audiotest] loops: pallettown mode=%d begin=%.1fs end=%.1fs | introbattle mode=%d (expect 0) | titlescreen begin=%.1fs of %.1fs | dungeon3 mode=%d (expect 1) begin=%.1fs" % [
		pw.loop_mode, pw.loop_begin / 22050.0, pw.data.size() / 2.0 / 22050.0, iw.loop_mode,
		tw.loop_begin / 22050.0, tw.data.size() / 2.0 / 22050.0, dw.loop_mode,
		dw.loop_begin / 22050.0])
	pw.save_to_wav("user://pallettown.wav")
	cry.save_to_wav("user://cry_charmander.wav")
	for lk in ["lavender", "gym", "titlescreen", "finalbattle"]:   # listen artifacts (gh #73)
		audio._synth(audio.songs[lk]).save_to_wav("user://%s.wav" % lk)
	# Threaded play: synthesis happens off-thread, then starts (no main-thread hitch).
	audio.play_song("routes1")
	await get_tree().create_timer(1.5).timeout
	print("[audiotest] threaded play: current=%s cached=%s playing=%s" % [
		audio._current, audio._cache.has("routes1"), audio._player.playing])
	print("[audiotest] wrote wavs to " + OS.get_user_data_dir())
	get_tree().quit()


func _presynthtest() -> void:
	await get_tree().process_frame
	audio.enabled = true
	var t0 := Time.get_ticks_msec()
	audio.play_song("pallettown")           # high-priority current song
	audio.presynth_all()                     # background the rest
	var first := -1
	var queued := false
	# The PCM cache is capped at 8 (gh #44), so wait for the synth queue to drain, not for
	# every song to stay cached.
	while Time.get_ticks_msec() - t0 < 90000:
		if first < 0 and audio._cache.has("pallettown"):
			first = Time.get_ticks_msec() - t0
		queued = queued or not audio._pending.is_empty()
		if queued and audio._pending.is_empty() and first >= 0:
			break
		await get_tree().process_frame
	print("[presynthtest] pallettown ready in %dms; %d/%d songs synthesized in %dms (cache capped at 8: %d)" % [
		first, audio.songs.size() - audio._pending.size(), audio.songs.size(),
		Time.get_ticks_msec() - t0, audio._cache.size()])
	get_tree().quit()


func _wildtest() -> void:
	await get_tree().process_frame
	load_world("Route1")
	print("[wildtest] map=%s grass_rate=%d" % [
		center_label, int(wild_data["maps"][center_label]["grass_rate"])])
	var counts := {}
	var enc := 0
	var steps := 5000
	for i in steps:
		modal = null
		_try_wild_encounter()
		if modal == battle:
			enc += 1
			var sp: String = battle.enemy_mon["species"]
			counts[sp] = int(counts.get(sp, 0)) + 1
	modal = null
	print("[wildtest] %d encounters / %d steps = %.1f%% (expect ~9.8%%)" % [enc, steps, enc * 100.0 / steps])
	print("[wildtest] species seen: %s (expect only pidgey/rattata)" % str(counts))
	# gh #106: a cave encounters on ANY floor tile. Confirm Mt Moon now fires (it never did — no grass).
	load_world("MtMoonB1F")
	var cave_cell: Vector2i = player.cell
	var cave_enc := 0
	for i in 3000:
		modal = null
		repel_steps = 0
		if center_tileset not in OUTSIDE_TILESETS and center_tileset != "forest" and not is_grass_cell(cave_cell):
			_try_wild_encounter("grass")
		if modal == battle:
			cave_enc += 1
	modal = null
	var crate := int(wild_data["maps"]["MtMoonB1F"]["grass_rate"])
	print("[wildtest] MtMoonB1F cave: %d/3000 = %.1f%% (expect ~%.1f%% = rate %d/256, was 0 before gh #106)" % [
		cave_enc, cave_enc * 100.0 / 3000, crate * 100.0 / 256, crate])
	# gh #176 phase 2 — TryDoWildEncounter's tile rule: rate from the bottom-RIGHT tile, table
	# from the bottom-LEFT. Route 21's left-shore column (x=4) is water-rate + GRASS-table (the
	# only dual-table map: TANGELA while surfing the coast); open water and grass match plainly.
	load_world("Route21")
	var k_shore := _wild_encounter_kinds(Vector2i(4, 2))
	var k_water := _wild_encounter_kinds(Vector2i(6, 2))
	var k_grass := _wild_encounter_kinds(Vector2i(8, 4))
	print("[wildtest] tile rule: shore=%s (expect [water, grass]) water=%s grass=%s" % [
		str(k_shore), str(k_water), str(k_grass)])
	# REPEL's level filter (not a blanket off-switch): the roll still runs; only wild mons BELOW
	# the first party slot's level are hidden. Lead L100 -> Route 1's L2-5 all hide; lead L2 ->
	# they appear at the normal rate.
	load_world("Route1")
	player_party = [make_mon("charmander", 100, [])]
	repel_steps = 200
	var high_hits := 0
	for i in 800:
		modal = null
		_try_wild_encounter()
		if modal == battle:
			high_hits += 1
	player_party = [make_mon("charmander", 2, [])]
	var low_hits := 0
	for i in 800:
		modal = null
		_try_wild_encounter()
		if modal == battle:
			low_hits += 1
	modal = null
	repel_steps = 0
	print("[wildtest] repel filter: lead_L100=%d (expect 0) lead_L2=%d (expect >0, ~%.0f)" % [
		high_hits, low_hits, 800.0 * int(wild_data["maps"]["Route1"]["grass_rate"]) / 256])
	# The 3-step post-battle cooldown: no roll (and no repel tick) for 3 steps.
	player.place(Vector2i(11, 6))                      # a Route 1 grass cell
	wild_cooldown_steps = 3
	var cool_enc := false
	for i in 3:
		modal = null
		_on_player_moved(Vector2i(11, 6))
		if modal == battle:
			cool_enc = true
	print("[wildtest] cooldown: encounter_in_3_steps=%s (expect false) left=%d (expect 0)" % [
		cool_enc, wild_cooldown_steps])
	get_tree().quit()


func _whiteouttest() -> void:
	await get_tree().process_frame
	respawn_map = "CeruleanPokecenter"        # as if last healed there
	player_money = 3000
	for m in player_party:
		m["hp"] = 0
	battle.blacked_out = true
	_on_battle_finished()                     # battle-loss path -> whiteout
	var healed := true
	for m in player_party:
		if int(m["hp"]) != int(m["maxhp"]):
			healed = false
	# pokered warps you OUTSIDE to the town's fly tile (Cerulean (19,18), below the Center door), and
	# halves your money (gh #101) — not into the Pokémon Center at full wallet.
	print("[whiteouttest] after blackout: map=%s cell=%s (expect CeruleanCity (19,18)), party_healed=%s, money=%d (expect 1500), hp=%s" % [
		center_label, str(player.cell), healed, player_money, str(party_hp_list())])
	get_tree().quit()


func _introtest() -> void:
	await get_tree().process_frame
	_start_new_game()                                  # kicks off the Oak speech (coroutine)
	await get_tree().create_timer(0.6).timeout         # let it reach the Oak pic + first text page
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intro_oak.png")
	cutscene.pic(load("res://assets/pokemon/front/nidorino.png"), Vector2(48, 36), true)  # flipped + lower
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intro_nido.png")
	print("[introtest] map=%s cutscene_active=%s party=%d bag=%s player=%s facing=%d" % [
		center_label, cutscene_active, player_party.size(), str(player_bag),
		str(player.cell), player.facing])
	cutscene.pic(load("res://assets/title/shrink2.png"))   # end-of-speech shrink frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intro_shrink.png")
	cutscene.clear_pic(); cutscene._fade = 0.0; cutscene.visible = false   # peek at the room itself
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intro_room.png")
	get_tree().quit()


func _oaktest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_party = []
	menu_mode = "title"            # as after the boot menu: a stale mode that must NOT hijack ask_yes_no
	load_world("PalletTown")
	# Find the north-exit column (walkable at both y=0 and y=1).
	var exit_x := -1
	for x in gw:
		if is_walkable(Vector2i(x, 0)) and is_walkable(Vector2i(x, 1)):
			exit_x = x
			break
	var oak = _npc_by_key("SPRITE_OAK@8,5")
	print("[oaktest] exit_x=%d oak=%s oak_shown=%s" % [exit_x, str(oak.cell) if oak else "nil",
		str(oak.shown) if oak else "?"])
	player.place(Vector2i(exit_x, 1))
	player.facing = 1
	print("[oaktest] player placed at %s, path oak->belowPlayer=%s" % [
		str(player.cell), str(find_path(oak.cell, player.cell + Vector2i(0, 1)))])
	player_name = "RED"
	rival_name = "BLUE"
	cutscene.oak_intercept()                       # fire the coroutine (gate -> lab intro)
	var shot_taken := false
	var inlab_shot := false
	var picked := false
	var challenged := false
	var oak_before := ""
	var oak_after_starter := ""
	for i in 2400:                                 # drive dialogue + tweens + menu to the starter
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			if not shot_taken and oak and oak.shown and oak.cell == player.cell + Vector2i(0, 1):
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://oak_intercept.png")
				shot_taken = true
			textbox.advance()
		elif modal == naming:
			naming.done.emit("")                  # skip the nickname prompt (keep species name)
		elif modal == dexentry:
			dexentry.visible = false              # dismiss the StarterDex data screen (added to
			dexentry.closed.emit()                # choose_starter after this driver was written)
		elif modal == menu:
			menu.chosen.emit(0)                    # answer YES to "you want this POKéMON?"
		elif modal == battle and not battle.won:
			print("[oaktest] rival battle: trainer=%s party_species=%s lv=%d" % [
				battle.trainer_name, battle.enemy_mon["species"], int(battle.enemy_mon["level"])])
			battle.won = true                  # force a win to verify the cutscene continuation
			battle.blacked_out = false
			battle.finished.emit()
		# Lab choose-mon speech done -> snapshot the lab, then pick SQUIRTLE.
		if not picked and has_event("OAK_ASKED_TO_CHOOSE_MON") and not cutscene_active \
				and modal == null:
			oak_before = map_script("OaksLab")._oak_text()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://oak_choosemon.png")
			inlab_shot = true
			cutscene.choose_starter(_npc_by_key("SPRITE_POKE_BALL@7,3"))   # pick SQUIRTLE
			picked = true
		# Starter taken, control returned -> verify no immediate battle, then head to the exit (Y==6).
		if picked and not challenged and has_event("GOT_STARTER") and not cutscene_active \
				and modal == null:
			oak_after_starter = map_script("OaksLab")._oak_text()
			print("[oaktest] after pick: battle_now=%s (expect false), heading to exit..." % (modal == battle))
			player.place(Vector2i(5, 6))
			_on_player_moved(Vector2i(5, 6))       # crossing Y==6 triggers the rival challenge
			challenged = true
		if has_event("BEAT_RIVAL1") and not cutscene_active and modal == null:
			break
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://oak_gotstarter.png")
	var pmon := ""
	if player_party.size() > 0:
		pmon = "%s Lv%d hp%d/%d" % [player_party[0]["species"], int(player_party[0]["level"]),
			int(player_party[0]["hp"]), int(player_party[0]["maxhp"])]
	print("[oaktest] end: map=%s (expect OaksLab) got_starter=%s starter=%s rival=%s beat_rival=%s party=[%s] inlab_shot=%s" % [
		center_label, has_event("GOT_STARTER"), player_starter, rival_starter,
		has_event("BEAT_RIVAL1"), pmon, inlab_shot])
	print("[oaktest] oak text: before='%s' after_starter='%s' after_rival='%s'" % [
		oak_before.replace("\n", " "), oak_after_starter.replace("\n", " "),
		map_script("OaksLab")._oak_text().replace("\n", " ")])
	get_tree().quit()


## Legit-play run — Stage 1 of the 1.0 sign-off (gh #76, ADR-011). Increment 1: drive the *seeded*
## NEW GAME opening on merit — name, pick a starter, and play the first rival battle (losing it is
## non-fatal in Red, so a naive first-move policy is safe here) — then assert the opening milestone.
## Navigation to Route 1+ and the town-by-town progression-gate waypoints come in later increments.
## Failure for now = a stall past the frame budget (a proxy for a dead-end until the gate list
## exists). Run: `--playthrough --seed N`.
## Ordered critical-path stages — the full sign-off gate, NEW GAME → HALL OF FAME. All 21 went green on
## seed 1 on 2026-07-10 (validate_gate.py: GATE GREEN), so the default `--playthrough` run walks the whole
## chain; each stage is checkpointed for `--from=<stage>` resume. See the WIP note below for what each does.
const _PT_STAGES := ["opening", "parcel", "brock", "misty", "bill", "ssanne", "surge", "rocktunnel",
	"erika", "silphscope", "pokeflute", "snorlax", "koga", "safari", "saffron", "silph", "sabrina",
	"blaine", "giovanni", "victoryroad", "elite4"]
## What each promoted stage does (all now in _PT_STAGES above): `bill` earns the S.S.TICKET; `ssanne`
## boards the S.S. Anne for HM01 CUT (rival ambush
## en route), teaches CUT to a slave (the Squirtle line can't learn it — a caught Oddish does), and cuts
## the tree gating the Vermilion Gym; `surge` then clears the trash puzzle + Lt. Surge; `rocktunnel`
## pushes east back through Cerulean, across Route 9/10 and the Rock Tunnel maze, to Lavender; `erika`
## crosses to Celadon (Underground Path 7-8), cuts the gym tree, and beats Erika for RAINBOWBADGE;
## `silphscope` opens the Game Corner poster, descends the Rocket Hideout, takes the LIFT KEY and rides
## the elevator into Giovanni's B4F wing for the SILPH SCOPE; `pokeflute` carries it back to Lavender,
## climbs the Pokémon Tower past the MAROWAK ghost, and frees MR.FUJI for the POKé FLUTE; `snorlax`
## plays that flute at the SNORLAX blocking Route 12 and walks on down to Fuchsia; `koga` threads that
## town's invisible-wall gym for the SOULBADGE; `safari` buys HM03 SURF + HM04 STRENGTH out of the
## Safari Zone and the WARDEN, and teaches them; `saffron` walks back north, buys a drink off the Celadon
## Mart roof, and gets past the thirsty gate guard into Saffron; `silph` threads the Silph Co pad maze
## for the CARD KEY and beats GIOVANNI, which clears the Rockets off Saffron Gym's door; `sabrina` rides
## that gym's own pad maze for the MARSHBADGE; `blaine` takes the SECRET KEY out of the Pokémon Mansion
## and answers Cinnabar Gym's quiz gates; `giovanni` opens Viridian Gym with the other seven badges and
## walks its spin maze for the eighth; `victoryroad` swims Route 23's river and solves Victory Road's
## boulder puzzle to the Indigo Plateau; `elite4` runs the gauntlet — Lorelei, Bruno, Agatha, Lance and
## the CHAMPION — into the HALL OF FAME (gh #76).
## All promoted into _PT_STAGES on 2026-07-10 (0.9.37) once the continuous chain went green; kept as an
## empty list so `_PT_STAGES + _PT_STAGES_WIP` and the `--all` flag still resolve. New WIP stages append here.
const _PT_STAGES_WIP := []
var _pt_verbose := false                         # per-step dungeon nav tracing (set by --mtmoontest)
var _pt_battle_log := false                      # per-turn battle tracing (set by --mistytest)


## The legit-play run (gh #76, ADR-011). Runs the critical-path stages in order, writing a resumable
## checkpoint (a real save) after each. `--from=<stage>` loads the previous stage's checkpoint and
## continues — so a leg is debugged in ~1 min instead of replaying from NEW GAME. The sign-off gate
## is still a single continuous run with no --from. Run: `--playthrough --seed N [--from=brock]`.
func _playthrough() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500                        # lift the headless fps cap (battles/steps run ~8x faster)
	Engine.time_scale = 25.0                    # accelerate the many 0.27s walk steps (headless)
	pt_time_scale = 25.0
	# gh #38: arm the wedge watchdog. 120 wall-clock seconds of a frozen progress signature is
	# ~50 in-game minutes at 25x — no legit leg sits that still. --ptwatchdog=<secs> overrides
	# (0 disables, for debugging a wedge by hand).
	var wd := _pt_arg_value("--ptwatchdog")
	_pt_watch_window_ms = (int(wd) if wd != "" else 120) * 1000
	_pt_watch_since_ms = Time.get_ticks_msec()
	print("[playthrough] start seed=%d" % _parse_seed_arg())
	# The default run now walks the whole gate (all 21 stages are in _PT_STAGES since 0.9.37); _PT_STAGES_WIP
	# is empty, so `--all` is a no-op kept for compatibility. `--from=<stage>` resumes from a checkpoint.
	var all: Array = _PT_STAGES + _PT_STAGES_WIP
	var start := 0
	var last := _PT_STAGES.size()                   # the full sign-off chain
	if "--all" in OS.get_cmdline_user_args():
		last = all.size()                           # includes any WIP stages (none at present)
	var target := _pt_arg_value("--from")
	if target != "":
		var ti: int = all.find(target)
		if ti < 0:
			print("[playthrough] unknown --from '%s' (stages: %s)" % [target, str(all)])
			get_tree().quit()
			return
		if ti > 0 and not _pt_load_ckpt(all[ti - 1]):
			print("[playthrough] no checkpoint '%s' — run the earlier stages once first" % all[ti - 1])
			get_tree().quit()
			return
		start = ti
		last = all.size()                           # from a resume, run through the WIP stages too
		print("[playthrough] resume '%s' (loaded '%s': map=%s lead L%d)" % [target,
			all[ti - 1] if ti > 0 else "-", center_label,
			int(player_party[0]["level"]) if not player_party.is_empty() else 0])
	for i in range(start, last):
		if not await _pt_run_stage(all[i]):
			get_tree().quit()
			return
		_pt_save_ckpt(all[i])
		print("[playthrough] checkpoint saved: %s" % all[i])
	print("[playthrough] PASS: %s complete (lead L%d)" % [str(all.slice(start, last)),
		int(player_party[0]["level"]) if not player_party.is_empty() else 0])
	get_tree().quit()


## Fast iteration on the Mt. Moon crossing (gh #76): set up a post-Brock team on Route 4's west side
## and drive _pt_reach_cerulean — no NEW GAME / grind needed. Run: `--mtmoontest`.
## gh #105: map the *tile-pair-aware* ladder connectivity of Mt Moon — BFS from each warp using the
## engine's own is_walkable + _tile_pair_blocked, and report which other warps it can reach. Reveals the
## real components so the bot's route can be re-derived on the faithful graph (the pure-collision route
## crosses elevation edges a real player can't).
func _tpprobe() -> void:
	await get_tree().process_frame
	var maps: Array = ["MtMoon1F", "MtMoonB1F", "MtMoonB2F", "RockTunnel1F", "RockTunnelB1F",
		"SeafoamIslands1F", "SeafoamIslandsB1F", "SeafoamIslandsB2F", "SeafoamIslandsB3F", "SeafoamIslandsB4F",
		"VictoryRoad1F", "VictoryRoad2F", "VictoryRoad3F", "ViridianForest", "DiglettsCave"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--maps="):
			maps = arg.trim_prefix("--maps=").split(",")
	for mapname in maps:
		load_world(mapname)
		await get_tree().process_frame
		var warps: Array = []
		for w in map.get("warps", []):
			warps.append([Vector2i(int(w["x"]), int(w["y"])), str(w.get("dest_map", "?")), int(w.get("dest_warp", 0))])
		print("[tpprobe] %s tileset=%s (%d warps)" % [mapname, center_tileset, warps.size()])
		for wi in warps.size():
			var start: Vector2i = warps[wi][0]
			var seen := {start: true}
			var q: Array[Vector2i] = [start]
			while not q.is_empty():
				var c: Vector2i = q.pop_front()
				for d in DIRV4.values():
					var n: Vector2i = c + d
					if seen.has(n) or not is_walkable(n) or _tile_pair_blocked(c, n):
						continue
					seen[n] = true
					q.append(n)
			var reach: Array = []
			for wj in warps.size():
				if wj != wi and seen.has(warps[wj][0]):
					reach.append(str(warps[wj][0]))
			print("[tpprobe]   #%d %s ->%s#%d | %d cells; same-floor warps=%s" % [
				wi, str(start), warps[wi][1], warps[wi][2], seen.size(), str(reach)])
	get_tree().quit()


## Player-reachable cells from `from`, walking normally: boulders (`bset`) and warp tiles are walls, and
## tile-pairs apply (unlike a boulder push). Used by the in-engine Sokoban solver.
func _reach_region(from: Vector2i, bset: Dictionary, warps: Dictionary) -> Dictionary:
	var seen := {from: true}
	var q: Array[Vector2i] = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in DIRV4.values():
			var nx: Vector2i = c + d
			if seen.has(nx) or bset.has(nx) or warps.has(nx) or not is_walkable(nx) or _tile_pair_blocked(c, nx):
				continue
			seen[nx] = true
			q.append(nx)
	return seen


## gh #105: in-engine Sokoban solver for Victory Road 1F. With TilePairCollisions the 1F->2F ladder (1,1)
## is only reachable once a boulder sits on the (17,13) switch, so search push-states (using the engine's
## own is_walkable + _tile_pair_blocked + warp tiles, and the boulder-push tile-pair exemption) for the
## shortest way to get any boulder there. Prints the [from, dir, times] legs to hardcode into the bot.
func _vr1fsolve() -> void:
	await get_tree().process_frame
	load_world("VictoryRoad1F")
	await get_tree().process_frame
	var switch := Vector2i(17, 13)
	var start := Vector2i(8, 16)
	var boulders: Array[Vector2i] = []
	for n in npcs:
		if str(n.key).begins_with("SPRITE_BOULDER@"):
			boulders.append(n.cell)
	var warps := {}
	for w in map.get("warps", []):
		warps[Vector2i(int(w["x"]), int(w["y"]))] = true
	print("[vr1fsolve] boulders=%s switch=%s warps=%s" % [str(boulders), str(switch), str(warps.keys())])
	var queue: Array = [[boulders.duplicate(), start, []]]
	var seen := {}
	var iters := 0
	while not queue.is_empty() and iters < 400000:
		iters += 1
		var st = queue.pop_front()
		var bs: Array = st[0]
		var pc: Vector2i = st[1]
		var path: Array = st[2]
		if switch in bs:
			_vr1fsolve_print(path)
			get_tree().quit()
			return
		var bset := {}
		for b in bs:
			bset[b] = true
		var region := _reach_region(pc, bset, warps)
		var rmin: Vector2i = pc
		for c in region:
			if c.y < rmin.y or (c.y == rmin.y and c.x < rmin.x):
				rmin = c
		var bsorted: Array = bs.duplicate()
		bsorted.sort()
		var key := str(bsorted) + "|" + str(rmin)
		if seen.has(key):
			continue
		seen[key] = true
		for bi in bs.size():
			var b: Vector2i = bs[bi]
			for d in 4:
				var dv: Vector2i = DIRV4[d]
				var behind: Vector2i = b - dv
				var ahead: Vector2i = b + dv
				if warps.has(ahead) or bset.has(ahead) or not is_walkable(ahead):
					continue
				if not region.has(behind):
					continue
				var nbs: Array = bs.duplicate()
				nbs[bi] = ahead
				queue.append([nbs, b, path + [[b, d]]])
	print("[vr1fsolve] NO SOLUTION (iters=%d, states=%d)" % [iters, seen.size()])
	get_tree().quit()


func _vr1fsolve_print(path: Array) -> void:
	# Compress consecutive same-direction pushes of the same boulder into [from, dir, times].
	var legs: Array = []
	for step in path:
		var frm: Vector2i = step[0]
		var d: int = step[1]
		if not legs.is_empty() and legs[-1][1] == d and (legs[-1][0] + DIRV4[d] * legs[-1][2]) == frm:
			legs[-1][2] += 1
		else:
			legs.append([frm, d, 1])
	print("[vr1fsolve] SOLVED in %d pushes, %d legs:" % [path.size(), legs.size()])
	for leg in legs:
		print("\t[Vector2i(%d, %d), %d, %d],   # %s x%d" % [leg[0].x, leg[0].y, leg[1], leg[2], _PT_DIR_NAME[leg[1]], leg[2]])


func _mtmoontest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	player_party = [make_mon("wartortle", 20, []), make_mon("spearow", 12, [])]
	player_bag = {"POKé BALL": 10}
	badges = ["BOULDERBADGE"]
	story_events = {"GOT_POKEDEX": true, "BEAT_BROCK": true}
	load_world("Route4")
	await get_tree().process_frame
	for spot in [Vector2i(18, 6), Vector2i(18, 7), Vector2i(11, 6), Vector2i(7, 17)]:
		if is_walkable(spot):
			player.place(spot)
			break
	player.facing = 1
	print("[mtmoontest] start on %s @%s" % [center_label, str(player.cell)])
	var ok: bool = await _pt_reach_cerulean()
	var passed: bool = ok and str(center_label) == "CeruleanCity"
	print("[mtmoontest] %s: map=%s cell=%s lead=%s L%d" % ["PASS" if passed else "FAIL",
		center_label, str(player.cell), player_party[0]["species"], int(player_party[0]["level"])])
	get_tree().quit()


## Fast iteration on the Misty fight (gh #76): set up a post-Mt.-Moon team + potions in the Cerulean
## Gym and drive the real leader fight with per-turn battle logging — no NEW GAME / grind / nav. Run:
## `--mistytest [--lvl N] [--pots N]`.
func _mistytest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	_pt_battle_log = true
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	var lvl: int = int(_pt_arg_value("--lvl")) if _pt_arg_value("--lvl") != "" else 20
	var pots: int = int(_pt_arg_value("--pots")) if _pt_arg_value("--pots") != "" else 4
	player_party = [make_mon("wartortle", lvl, []), make_mon("pidgey", 13, [])]
	player_bag = {"SUPER POTION": pots}
	badges = ["BOULDERBADGE"]
	story_events = {"GOT_POKEDEX": true, "BEAT_BROCK": true}
	load_world("CeruleanGym")
	await get_tree().process_frame
	player.place(Vector2i(4, 11)); player.facing = 1
	print("[mistytest] start: wartortle L%d + %d SUPER POTION" % [lvl, pots])
	var ok: bool = await _pt_talk_and_battle(Vector2i(4, 3), 1, "BEAT_MISTY")
	print("[mistytest] %s: beat_misty=%s map=%s party0=%s" % ["PASS" if ok else "FAIL",
		has_event("BEAT_MISTY"), center_label,
		"%s L%d hp=%d" % [player_party[0]["species"], int(player_party[0]["level"]), int(player_party[0]["hp"])] if not player_party.is_empty() else "-"])
	get_tree().quit()


## Fast combat check for Lt. Surge (gh #76): door pre-opened, drive the leader fight with a
## configurable lead. `--lead sandshrew:20` puts a Ground mon (immune to Surge's electric) up front.
func _surgecombattest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	_pt_battle_log = true
	player_name = "RED"; rival_name = "BLUE"
	var bench := _pt_arg_value("--bench")               # e.g. "sandshrew:20" — Wartortle always leads
	player_party = [make_mon("wartortle", 24, [])]
	if bench != "":
		var parts := bench.split(":")
		player_party.append(make_mon(str(parts[0]), int(parts[1]) if parts.size() > 1 else 20, []))
	player_bag = {"SUPER POTION": 8}
	badges = ["BOULDERBADGE", "CASCADEBADGE"]
	story_events = {"GOT_POKEDEX": true, "VERMILION_1ST_LOCK": true, "VERMILION_2ND_LOCK": true}
	load_world("VermilionGym")
	await get_tree().process_frame
	set_block(2, 2, 0x05)                               # ensure the motorized door is open
	player.place(Vector2i(5, 8)); player.facing = 1
	print("[surgecombat] wartortle lead, bench=%s vs Lt. Surge" % (bench if bench != "" else "-"))
	var ok: bool = await _pt_talk_and_battle(Vector2i(5, 2), 1, "BEAT_LT_SURGE")   # Surge @ (5,1)
	print("[surgecombat] %s: beat=%s party0=%s" % ["PASS" if ok else "FAIL", has_event("BEAT_LT_SURGE"),
		"%s L%d hp=%d" % [player_party[0]["species"], int(player_party[0]["level"]), int(player_party[0]["hp"])] if not player_party.is_empty() else "-"])
	get_tree().quit()


## Walk back to Cerulean City from where a prior stage left off (Bill's Sea Cottage, Route 24/25, the
## gym or another Cerulean building), OR from inside Rock Tunnel / its approach after a failed attempt
## that didn't white out. Trainers are already beaten, so it's just navigation.
##
## Every step here names a *real onward warp/connection*, never `_pt_warp_out("<town>")` from a map we
## didn't enter from that town: `_pt_warp_out` falls back to a LAST_MAP warp and rebinds it to whatever
## you ask for, so calling it with "CeruleanCity" while standing in RockTunnel1F (which has four LAST_MAP
## warps) would walk out a tunnel mouth and *teleport* to Cerulean, skipping Routes 9 and 10 (gh #100).
func _pt_return_to_cerulean() -> bool:
	for _i in 12:
		match str(center_label):
			"CeruleanCity":
				return true
			"BillsHouse":
				if not await _pt_warp_out("Route25"): return false
			"Route25":
				if not await _pt_hop(2, "Route24"): return false
			"Route24":
				if not await _pt_hop(0, "CeruleanCity"): return false
			"RockTunnelB1F":
				if not await _pt_warp_out("RockTunnel1F"): return false   # named warp — no LAST_MAP rebind
			"RockTunnel1F", "RockTunnelPokecenter":
				if not await _pt_warp_out("Route10"): return false        # LAST_MAP here really is Route 10
			"Route10":
				if not await _pt_hop(2, "Route9"): return false           # west into the Route 9 side
			"Route9":
				if not await _pt_hop(2, "CeruleanCity"): return false     # west into Cerulean (gym side)
			_:
				# Only a Cerulean-side interior may take a LAST_MAP exit to the city; anywhere else,
				# _pt_warp_out would rebind LAST_MAP and teleport us home (gh #100).
				if not (str(center_label).begins_with("Cerulean") or str(center_label) == "BikeShop"):
					return false
				if not await _pt_warp_out("CeruleanCity"): return false   # a Cerulean building
	return str(center_label) == "CeruleanCity"


## Cross Cerulean City's ONE-WAY region split, from the gym side to the rest of the city.
## The city is cut in two. The gym side — the Pokécenter (19,17), mart, bike shop, gym door, and the
## Route 4 (west) and Route 24 (north) edges — can be *entered* from the rest over the down-ledges at
## (32..34,18), but never left that way, and it reaches NEITHER the Route 5 (south) nor the Route 9
## (east) exit. The one crossing is a WARP: the Team Rocket-trashed house north of the gym has a hole in
## its back wall — in the front door (27,11), through the hole (house 3,0), out behind the house at
## (27,9), which is on the far side. The front door is guarded until you get the S.S.TICKET from Bill
## (BillsHouse.asm hides GUARD2 @27,12 on GOT_SS_TICKET; see CeruleanCity.gd), so this only works
## post-ticket. Both house exits are LAST_MAP, so the back hole must be walked to explicitly (a plain
## _pt_warp_out would take the front door back). (gh #76.)
func _pt_cerulean_cross_trashed_house() -> bool:
	if str(center_label) != "CeruleanCity":
		return false
	if not await _pt_warp_out("CeruleanTrashedHouse"):
		return false                                         # front door (27,11); needs the guard gone
	if not await _pt_walk_to(Vector2i(3, 0)):
		return false                                         # step through the back-wall hole
	await _drive_until(func() -> bool: return str(center_label) == "CeruleanCity" and modal == null, 400)
	return str(center_label) == "CeruleanCity"               # behind the house now, at (27,9)


## Cerulean -> Route 5 (south) on foot, crossing the region split through the trashed house when the
## south edge isn't reachable from where we stand.
func _pt_cerulean_to_route5() -> bool:
	if str(center_label) != "CeruleanCity":
		return false
	if await _pt_cross_south() and str(center_label) == "Route5":
		return true                                          # already on the far side
	if not await _pt_cerulean_cross_trashed_house():
		return false
	return await _pt_cross_south() and str(center_label) == "Route5"


## Cerulean -> Route 9 (east) on foot, across the same one-way split. Arriving from Route 5 (the normal
## Vermilion -> Cerulean leg) lands on the far side, where the east edge is a straight walk — so try the
## direct hop first. But a whiteout on the Rock Tunnel run respawns in the Cerulean Pokécenter, and its
## door (19,18) is on the GYM side, from which _pt_cross reports "no reachable right edge cell": that
## retry has to go through the trashed house like a real player would. (gh #76.)
func _pt_cerulean_to_route9() -> bool:
	if str(center_label) != "CeruleanCity":
		return false
	if await _pt_hop(3, "Route9"):
		return true
	if str(center_label) != "CeruleanCity":
		return false                                         # a failed hop that still left the city
	if not await _pt_cerulean_cross_trashed_house():
		return false
	return await _pt_hop(3, "Route9")


## Fast iteration on Cerulean -> Route 5 -> ... -> Vermilion (gh #76), from a post-Misty state in the
## Cerulean gym region. No catch / grind / fight. `--route9` instead drives the whiteout-recovery seam
## (Center door -> Route 9, across the city's one-way split); `--diglett` the cave catch.
## Run: `--surgenavtest [--route9] [--diglett]`.
func _surgenavtest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"
	player_party = [make_mon("wartortle", 22, [])]
	player_bag = {"POKé BALL": 12}
	badges = ["BOULDERBADGE", "CASCADEBADGE"]
	if "--diglett" in OS.get_cmdline_user_args():           # verify the cave catch + exit in isolation
		load_world("DiglettsCave")
		await get_tree().process_frame
		player.place(Vector2i(37, 31)); warp_armed = false  # mimic arriving on the exit warp via a warp
		var caught := await _pt_catch_species("diglett", 50, 19)
		var exited := await _pt_warp_out("DiglettsCaveRoute11")
		print("[surgenav] diglett catch=%s exit=%s (%s) party=%s" % [caught, exited, center_label, str(_pt_party_summary())])
		get_tree().quit()
		return
	# GOT_SS_TICKET is set (post-Bill): the trashed-house guard is gone, so Route 5 is reachable.
	story_events = {"GOT_POKEDEX": true, "BEAT_BROCK": true, "BEAT_MISTY": true,
		"BEAT_CERULEAN_RIVAL": true, "GOT_SS_TICKET": true}
	if "--route9" in OS.get_cmdline_user_args():
		# The gh #76 whiteout seam: a Rock Tunnel whiteout respawns the bot in the Cerulean Center, and
		# its door (19,18) is on the gym side of the city's one-way split, from which the east exit to
		# Route 9 is unreachable — the recovery has to cross back through the trashed house. Drive the
		# real thing (whiteout + the stage's own recovery calls), never a place() past the geometry.
		respawn_map = "CeruleanPokecenter"
		load_world("RockTunnel1F")                         # where the seed-1 run actually whited out
		await get_tree().process_frame
		whiteout()
		await get_tree().process_frame
		print("[surgenav] whiteout -> %s @%s" % [center_label, str(player.cell)])
		var back := await _pt_return_to_cerulean()
		print("[surgenav] leave the Center: ok=%s -> %s @%s" % [back, center_label, str(player.cell)])
		var east := await _pt_cerulean_to_route9()
		print("[surgenav] %s: route9=%s map=%s @%s" % [
			"PASS" if (east and str(center_label) == "Route9") else "FAIL", east, center_label, str(player.cell)])
		get_tree().quit()
		return
	load_world("CeruleanGym")
	await get_tree().process_frame
	print("[surgenav] start on %s" % center_label)
	await _pt_warp_out("CeruleanCity")
	print("[surgenav] leave gym -> %s @%s" % [center_label, str(player.cell)])
	print("[surgenav] to Route5: %s -> %s @%s" % [await _pt_cerulean_to_route5(), center_label, str(player.cell)])
	for leg in ["UndergroundPathRoute5", "UndergroundPathNorthSouth", "UndergroundPathRoute6", "Route6"]:
		print("[surgenav]   warp %s -> %s (%s)" % [leg, center_label, "ok" if await _pt_warp_out(leg) else "FAIL"])
	print("[surgenav] Route6 south -> %s (%s) @%s" % [center_label, await _pt_cross_south(), str(player.cell)])
	get_tree().quit()


## Fast iteration on the Bill / S.S.TICKET questline (gh #76): a post-Misty team in Cerulean drives the
## rival ambush, Nugget Bridge, Route 25, and Bill's cottage. Tune the lead with `--lvl N`. Run: `--billstage`.
func _billstagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"
	var lvl := int(_pt_arg_value("--lvl")) if _pt_arg_value("--lvl") != "" else 22
	player_party = [make_mon("wartortle", lvl, []), make_mon("pidgey", 15, [])]
	player_bag = {"SUPER POTION": 8, "POKé BALL": 5}
	badges = ["BOULDERBADGE", "CASCADEBADGE"]
	story_events = {"GOT_POKEDEX": true, "BEAT_BROCK": true, "BEAT_MISTY": true, "GOT_STARTER": true}
	if _pt_arg_value("--house") != "" or "--house" in OS.get_cmdline_user_args():
		story_events["BEAT_CERULEAN_RIVAL"] = true         # fast path: just the cottage interaction
		load_world("BillsHouse")
		await get_tree().process_frame
		print("[billtest] house-only: do_bill=%s GOT_SS_TICKET=%s" % [await _pt_do_bill(), has_event("GOT_SS_TICKET")])
		get_tree().quit()
		return
	load_world("CeruleanCity")
	await get_tree().process_frame
	player.place(Vector2i(30, 20))                         # where leaving the gym drops you
	print("[billtest] start on %s lead wartortle L%d" % [center_label, lvl])
	var ok := await _pt_stage_bill()
	print("[billtest] result=%s GOT_SS_TICKET=%s on %s lead %s L%d" % [ok, has_event("GOT_SS_TICKET"),
		center_label, str(player_party[0]["species"]), int(player_party[0]["level"])])
	get_tree().quit()


## Fast iteration on the S.S. Anne stage (gh #76). Default: from a post-Bill state in Vermilion (ticket
## in hand + an Oddish Cut slave in the party) drive board -> HM01 -> teach CUT -> cut the gym tree.
##   --catch : start on Route 6 with a lone Wartortle and drive _pt_ensure_cut_mon (the Oddish catch).
##   --full  : start in Cerulean and drive the whole stage (nav + catch + ship + tree). Run: `--annestage`.
func _ssannestagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	var lvl := int(_pt_arg_value("--lvl")) if _pt_arg_value("--lvl") != "" else 24
	badges = ["BOULDERBADGE", "CASCADEBADGE"]
	var uargs := OS.get_cmdline_user_args()
	if "--catch" in uargs:                                  # just the Route 6 Cut-slave catch
		player_party = [make_mon("wartortle", lvl, [])]
		player_bag = {"POKé BALL": 12}
		story_events = {"GOT_POKEDEX": true, "BEAT_BROCK": true, "BEAT_MISTY": true}
		load_world("Route6")
		await get_tree().process_frame
		for y in gh:                                        # drop onto any walkable cell so the grass BFS works
			var placed_ok := false
			for x in gw:
				if is_walkable(Vector2i(x, y)):
					player.place(Vector2i(x, y)); placed_ok = true; break
			if placed_ok: break
		var caught := await _pt_ensure_cut_mon()
		print("[annestage] catch: ensure_cut_mon=%s party=%s knows_learner=%s" % [caught,
			str(_pt_party_summary()), _pt_party_can_cut()])
		print("[annestage] %s" % ("PASS" if (caught and _pt_party_can_cut()) else "FAIL"))
		get_tree().quit()
		return
	if "--full" in uargs:                                   # the whole stage from Cerulean
		player_party = [make_mon("wartortle", lvl, []), make_mon("pidgey", 15, [])]
		player_bag = {"SUPER POTION": 12, "POKé BALL": 12, "S.S.TICKET": 1}
		story_events = {"GOT_POKEDEX": true, "BEAT_BROCK": true, "BEAT_MISTY": true,
			"BEAT_CERULEAN_RIVAL": true, "GOT_SS_TICKET": true}
		load_world("CeruleanCity")
		await get_tree().process_frame
		player.place(Vector2i(30, 20))                      # where leaving the Cerulean gym drops you
		print("[annestage] full start on %s lead wartortle L%d" % [center_label, lvl])
		var okf := await _pt_stage_ssanne()
		print("[annestage] full result=%s HM01=%s knows_cut=%s map=%s party=%s" % [okf,
			has_event("GOT_HM01"), _mon_with_move("CUT") != "", center_label, str(_pt_party_summary())])
		get_tree().quit()
		return
	# Default: the ship + teach + tree, from Vermilion with a pre-caught Oddish slave.
	player_party = [make_mon("wartortle", lvl, []), make_mon("oddish", 14, [])]
	player_bag = {"SUPER POTION": 8, "S.S.TICKET": 1}
	story_events = {"GOT_POKEDEX": true, "BEAT_BROCK": true, "BEAT_MISTY": true, "GOT_SS_TICKET": true}
	load_world("VermilionCity")
	await get_tree().process_frame
	player.place(Vector2i(18, 26))                          # north region, near the dock approach
	print("[annestage] start on %s lead wartortle L%d + oddish slave" % [center_label, lvl])
	var got := await _pt_board_and_get_hm01()
	var taught := await _pt_teach_cut()
	var cut := await _pt_cut_vermilion_gym_tree()
	print("[annestage] board=%s HM01=%s left=%s taught=%s knows_cut=%s tree_cut=%s map=%s cell=%s party=%s" % [got,
		has_event("GOT_HM01"), has_event("SS_ANNE_LEFT"), taught, _mon_with_move("CUT") != "", cut,
		center_label, str(player.cell), str(_pt_party_summary())])
	print("[annestage] %s" % ("PASS" if (got and taught and cut and has_event("GOT_HM01")) else "FAIL"))
	get_tree().quit()


## Fast iteration on the Erika stage (gh #76): a post-Rock-Tunnel team in Lavender drives the whole leg
## to Celadon + the gym. `--nav` stops after reaching Celadon + cutting the gym tree (skips the fight).
## Tune the lead with `--lvl N`. Run: `--erikastage [--nav] [--lvl N]`.
func _erikastagetest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	var lvl := int(_pt_arg_value("--lvl")) if _pt_arg_value("--lvl") != "" else 30
	# Post-`rocktunnel` party: Wartortle lead + the Oddish Cut slave (knows CUT) for the gym tree.
	player_party = [make_mon("wartortle", lvl, []), make_mon("diglett", 22, []), make_mon("oddish", 18, ["ABSORB", "CUT"])]
	player_bag = {"SUPER POTION": 16, "POKé BALL": 8}
	player_money = 9000
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE"]
	story_events = {"GOT_POKEDEX": true, "BEAT_BROCK": true, "BEAT_MISTY": true, "BEAT_CERULEAN_RIVAL": true,
		"GOT_SS_TICKET": true, "GOT_HM01": true, "BEAT_LT_SURGE": true}
	if "--gym" in OS.get_cmdline_user_args():             # gym-only: from the door, navigate trainers -> Erika
		story_events["VERMILION_1ST_LOCK"] = true          # (no bearing; keep events minimal)
		load_world("CeladonGym")
		await get_tree().process_frame
		for c in [Vector2i(4, 16), Vector2i(5, 16), Vector2i(4, 15)]:
			if is_walkable(c):
				player.place(c); break
		print("[erikastage] gym-only: from %s drive Erika (lead L%d)" % [str(player.cell), lvl])
		var cutok := await _pt_cut_gym_interior_tree()     # cut the (5,7) tree gating Erika's platform
		var gok := cutok and await _pt_talk_and_battle(Vector2i(4, 4), 1, "BEAT_ERIKA")
		print("[erikastage] %s: cut_interior=%s beat_erika=%s map=%s" % [
			"PASS" if (gok and has_event("BEAT_ERIKA")) else "FAIL", cutok, has_event("BEAT_ERIKA"), center_label])
		get_tree().quit()
		return
	load_world("LavenderTown")
	await get_tree().process_frame
	for c in [Vector2i(10, 12), Vector2i(9, 12), Vector2i(11, 12), Vector2i(10, 10)]:
		if is_walkable(c):
			player.place(c); break
	print("[erikastage] start on %s lead wartortle L%d" % [center_label, lvl])
	if "--nav" in OS.get_cmdline_user_args():             # nav-only: reach Celadon + cut the gym tree
		# grind one level en route so the grind -> Route-7-cross fix is exercised without the slow Erika fight
		var navok := await _pt_lavender_to_celadon(lvl + 1)
		var cutok := navok and await _pt_cut_celadon_gym_tree()
		print("[erikastage] %s: nav=%s lead=L%d map=%s cut_tree=%s" % [
			"PASS" if (cutok and str(center_label) == "CeladonCity") else "FAIL", navok,
			int(player_party[0]["level"]) if not player_party.is_empty() else 0, center_label, cutok])
		get_tree().quit()
		return
	var ok := await _pt_stage_erika()
	print("[erikastage] %s: beat_erika=%s badges=%s map=%s lead=%s" % [
		"PASS" if (ok and has_event("BEAT_ERIKA")) else "FAIL", has_event("BEAT_ERIKA"), str(badges), center_label,
		"%s L%d" % [player_party[0]["species"], int(player_party[0]["level"])] if not player_party.is_empty() else "-"])
	get_tree().quit()


## Fast combat check for Erika (gh #76): Celadon Gym, drive the leader fight with a configurable lead +
## bench. Erika is grass/poison (Victreebel/Tangela/Vileplume L24-29) — a bad matchup for the water/ground
## team — so this sizes up the brute force: Wartortle's BITE (Normal, neutral) + potions carry it with a
## level lead. Starts right in front of Erika (the gym trainers are exercised by the full stage test).
## `--lvl N` sets the Wartortle level; `--bench sp:lv` adds a bench mon. Run: `--erikacombat [--lvl N]`.
func _erikacombattest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	_pt_battle_log = true
	player_name = "RED"; rival_name = "BLUE"
	var lvl := int(_pt_arg_value("--lvl")) if _pt_arg_value("--lvl") != "" else 32
	player_party = [make_mon("wartortle", lvl, [])]
	var bench := _pt_arg_value("--bench")
	if bench != "":
		var parts := bench.split(":")
		player_party.append(make_mon(str(parts[0]), int(parts[1]) if parts.size() > 1 else 20, []))
	player_bag = {"SUPER POTION": 16}
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE"]
	story_events = {"GOT_POKEDEX": true}
	load_world("CeladonGym")
	await get_tree().process_frame
	player.place(Vector2i(4, 4))                            # directly below Erika (4,3); no sight trainer covers this cell
	print("[erikacombat] wartortle L%d lead, bench=%s vs Erika; moves=%s" % [lvl, bench if bench != "" else "-",
		str((player_party[0]["moves"] as Array).map(func(m): return m["move"]))])
	var ok := await _pt_talk_and_battle(Vector2i(4, 4), 1, "BEAT_ERIKA")
	print("[erikacombat] %s: beat=%s party0=%s" % ["PASS" if ok else "FAIL", has_event("BEAT_ERIKA"),
		"%s L%d hp=%d" % [player_party[0]["species"], int(player_party[0]["level"]), int(player_party[0]["hp"])] if not player_party.is_empty() else "-"])
	get_tree().quit()


## Fast iteration on the Rock Tunnel stage (gh #76): a post-Surge team in Vermilion drives the whole leg
## to Lavender. `--tunnel` starts on Route 10's north entrance and drives just the maze crossing (the
## novel part) + the south exit, skipping the Cerulean/Route 9-10 approach. Tune the lead with `--lvl N`.
## Run: `--rocktunneltest [--tunnel] [--lvl N]`.
func _rocktunneltest() -> void:
	await get_tree().process_frame
	Engine.max_fps = 500
	Engine.time_scale = 25.0
	pt_time_scale = 25.0
	player_name = "RED"; rival_name = "BLUE"; player_starter = "squirtle"
	var lvl := int(_pt_arg_value("--lvl")) if _pt_arg_value("--lvl") != "" else 28
	# Post-`ssanne` party: an Oddish Cut slave (the Squirtle line can't learn CUT) that knows CUT, needed
	# to cut the tree gating Cerulean -> Route 9.
	player_party = [make_mon("wartortle", lvl, []), make_mon("diglett", 22, []), make_mon("oddish", 16, ["ABSORB", "CUT"])]
	player_bag = {"SUPER POTION": 12, "POKé BALL": 8}
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE"]
	story_events = {"GOT_POKEDEX": true, "BEAT_BROCK": true, "BEAT_MISTY": true, "BEAT_CERULEAN_RIVAL": true,
		"GOT_SS_TICKET": true, "GOT_HM01": true, "BEAT_LT_SURGE": true}
	if "--tunnel" in OS.get_cmdline_user_args():           # just the maze: start near Route 10's north entrance
		load_world("Route10")
		await get_tree().process_frame
		for c in [Vector2i(8, 20), Vector2i(8, 19), Vector2i(9, 20), Vector2i(7, 20), Vector2i(11, 20)]:
			if is_walkable(c) and _warp_at(c) == null:     # start off the warp mat, then walk onto it
				player.place(c); break
		var crossed := await _pt_traverse_rock_tunnel()
		var south := crossed and await _pt_cross_south()
		print("[rocktunnel] %s: tunnel=%s map=%s (expect LavenderTown) @%s" % [
			"PASS" if (south and str(center_label) == "LavenderTown") else "FAIL", crossed, center_label, str(player.cell)])
		get_tree().quit()
		return
	load_world("VermilionCity")
	await get_tree().process_frame
	player.place(Vector2i(18, 26))                          # Vermilion north plaza (near the dock approach)
	print("[rocktunnel] start on %s lead wartortle L%d" % [center_label, lvl])
	var ok := await _pt_stage_rocktunnel()
	print("[rocktunnel] %s: reached=%s map=%s lead=%s party=%s" % [
		"PASS" if (ok and str(center_label) == "LavenderTown") else "FAIL", ok, center_label,
		"%s L%d" % [player_party[0]["species"], int(player_party[0]["level"])] if not player_party.is_empty() else "-",
		str(_pt_party_summary())])
	get_tree().quit()


## Connectivity probe (gh #76): flood-fill reachable cells (walkable + ledge hops) on a map from a start
## cell and report which map edges + warp tiles it reaches. Used to derive dungeon ladder routes (Rock
## Tunnel) and to diagnose on-foot traversal dead-ends (e.g. Route 9's sealed western connection strip).
## `--grid` dumps an ASCII walkability/ledge map. Run: `--rtprobe --map X --sx N --sy N [--grid]`.
func _rtprobe() -> void:
	await get_tree().process_frame
	var mp := _pt_arg_value("--map"); if mp == "": mp = "RockTunnel1F"
	# `--event NAME` sets a story event before the map loads, so a floor whose `on_enter` lays blocks
	# from an event (the Pokémon Mansion switch, a Silph card-key door) can be probed in both states.
	var ev := _pt_arg_value("--event")
	if ev != "":
		set_event(ev)
		print("[rtprobe] event %s set before load" % ev)
	load_world(mp)
	await get_tree().process_frame
	var start := Vector2i(int(_pt_arg_value("--sx")), int(_pt_arg_value("--sy")))
	var seen := {start: true}
	var q: Array[Vector2i] = [start]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		for d in 4:
			var nx: Vector2i = cur + DIRV4[d]
			if not seen.has(nx) and _pt_on_center(nx) and is_walkable(nx):
				seen[nx] = true; q.append(nx)
			if ledge_match(cur, _PT_DIR_NAME[d], DIRV4[d]):
				var lx: Vector2i = cur + DIRV4[d] * 2
				if not seen.has(lx) and _pt_on_center(lx) and is_walkable(lx):
					seen[lx] = true; q.append(lx)
	var reach: Array = []
	for w in map["warps"]:
		var wc := Vector2i(int(w["x"]), int(w["y"]))
		if seen.has(wc):
			reach.append("(%d,%d)->%s#%d" % [wc.x, wc.y, w.get("dest_map", w.get("dest_const")), w.get("dest_warp", 0)])
	var edges := {"N": false, "S": false, "E": false, "W": false}
	for c in seen:
		if c.y == 0: edges["N"] = true
		if c.y == gh - 1: edges["S"] = true
		if c.x == 0: edges["W"] = true
		if c.x == gw - 1: edges["E"] = true
	print("[rtprobe] %s from %s: %d cells; edges=%s; reachable warps: %s" % [mp, str(start), seen.size(), str(edges), str(reach)])
	# Reaching an edge is not the same as being able to *cross* it: _pt_cross also needs the cell just
	# beyond (on the connected neighbour) to be walkable. Report the cells that actually pass that test.
	for dir in 4:
		var step: Vector2i = DIRV4[dir]
		var horizontal: bool = dir >= 2
		var crossable: Array = []
		for i in (gh if horizontal else gw):
			var edge: Vector2i = (Vector2i(0 if dir == 2 else gw - 1, i) if horizontal
				else Vector2i(i, 0 if dir == 1 else gh - 1))
			if is_walkable(edge) and is_walkable(edge - step) and is_walkable(edge + step):
				crossable.append(edge.y if horizontal else edge.x)
		print("[rtprobe]   %-5s crossable at %s=%s%s" % [_PT_DIR_NAME[dir], "y" if horizontal else "x",
			str(crossable), "" if crossable.is_empty() else (" (reached: %s)" % str(crossable.filter(
				func(v: int) -> bool: return seen.has(Vector2i(0 if dir == 2 else gw - 1, v) if horizontal
					else Vector2i(v, 0 if dir == 1 else gh - 1)))))])
	if "--grid" in OS.get_cmdline_user_args():
		# ASCII dump: S=start, o=flood-reached, .=walkable, #=blocked; ledge glyphs show one-way exits.
		for y in gh:
			var row := ""
			for x in gw:
				var c := Vector2i(x, y)
				var glyph := "#"
				if c == start: glyph = "S"
				elif seen.has(c): glyph = "o"
				elif is_walkable(c): glyph = "."
				var lg := ""
				for d in 4:
					if is_walkable(c) and ledge_match(c, _PT_DIR_NAME[d], DIRV4[d]):
						lg = ["v", "^", "<", ">"][d]
				row += lg if lg != "" else glyph
			print("[grid] %s" % row)
	get_tree().quit()


## True if any party mon's species can learn HM01 CUT (so we already have a Cut slave / can teach it).
func _pt_party_can_cut() -> bool:
	for m in player_party:
		if _can_learn(str(m["species"]), "CUT"):
			return true
	return false


## gh #38: everything legitimate the bot does moves at least one of these within seconds — a
## step (map/cell), a battle turn (det events), a story beat (events/money), damage or exp
## (party). A signature frozen for the whole watchdog window is a wedge, not a slow leg.
func _pt_progress_sig() -> String:
	var party := ""
	for m in player_party:
		party += "%s:%d:%d:%d;" % [str(m["species"]), int(m["level"]), int(m["hp"]),
			int(m.get("exp", 0))]
	return "%s|%s|%d|%d|%d|%s" % [str(center_label), str(player.cell),
		battle.det_stream.size() if modal == battle else -1,
		story_events.size(), player_money, party]


## gh #38: the watchdog fired — dump everything a diagnosis needs (which modal holds the
## screen, the battle's state, the cutscene/textbox flags), fail loudly, and end the process.
func _pt_watchdog_bark(frozen_ms: int) -> void:
	var modal_name := "null"
	if modal != null:
		modal_name = "battle" if modal == battle else ("menu" if modal == menu
			else ("textbox" if modal == textbox else modal.get_class()))
	print("[playthrough] WATCHDOG: stage '%s' frozen for %ds — modal=%s battle_state=%s cutscene=%s textbox(active=%s,visible=%s) player(moving=%s,jumping=%s) sig=%s" % [
		_pt_stage, frozen_ms / 1000, modal_name,
		str(battle.state) if modal == battle else "-", cutscene_active,
		textbox.active, textbox.visible, player.moving, player.jumping, _pt_watch_sig])
	_pt_fail("watchdog: stage '%s' made no progress for %ds" % [_pt_stage, frozen_ms / 1000])
	_pt_watch_window_ms = 0                           # bark once, not every second until exit
	get_tree().quit()


func _pt_run_stage(stage: String) -> bool:
	_pt_stage = stage
	if _pt_arg_value("--ptwedge") == stage:
		# gh #38: simulate the silent-wedge shape (CPU alive, zero output, no progress) so the
		# watchdog itself is testable: --playthrough --ptwatchdog=10 --ptwedge=opening
		print("[playthrough] ptwedge: spinning silently in '%s' for the watchdog" % stage)
		while true:
			await get_tree().process_frame
	match stage:
		"opening": return await _pt_stage_opening()
		"parcel": return await _pt_stage_parcel()
		"brock": return await _pt_stage_brock()
		"misty": return await _pt_stage_misty()
		"bill": return await _pt_stage_bill()
		"ssanne": return await _pt_stage_ssanne()
		"surge": return await _pt_stage_surge()
		"rocktunnel": return await _pt_stage_rocktunnel()
		"erika": return await _pt_stage_erika()
		"silphscope": return await _pt_stage_silphscope()
		"pokeflute": return await _pt_stage_pokeflute()
		"snorlax": return await _pt_stage_snorlax()
		"koga": return await _pt_stage_koga()
		"safari": return await _pt_stage_safari()
		"saffron": return await _pt_stage_saffron()
		"silph": return await _pt_stage_silph()
		"sabrina": return await _pt_stage_sabrina()
		"blaine": return await _pt_stage_blaine()
		"giovanni": return await _pt_stage_giovanni()
		"victoryroad": return await _pt_stage_victoryroad()
		"elite4": return await _pt_stage_elite4()
	return _pt_fail("unknown stage " + stage)


## NEW GAME opening: name, pick a starter, play the first rival battle (mirrors _oaktest but *plays*
## the battle). Sets up state from scratch — only runs when starting fresh, never on resume.
func _pt_stage_opening() -> bool:
	story_events = {}
	player_party = []
	menu_mode = "title"
	player_name = "RED"
	rival_name = "BLUE"
	load_world("PalletTown")
	var exit_x := -1
	for x in gw:
		if is_walkable(Vector2i(x, 0)) and is_walkable(Vector2i(x, 1)):
			exit_x = x
			break
	player.place(Vector2i(exit_x, 1))
	player.facing = 1
	cutscene.oak_intercept()                       # gate -> lab intro -> choose-a-mon
	var picked := false
	var challenged := false
	var done := false
	for i in 8000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == naming:
			naming.done.emit("")                   # keep the preset name (skip the keyboard)
		elif modal == dexentry:
			dexentry.visible = false
			dexentry.closed.emit()                 # dismiss the StarterDex data screen
		elif modal == menu:
			menu.chosen.emit(0)                    # YES to "you want this POKéMON?"
		elif modal == battle:
			await _press("ui_accept")              # minimal battle policy: FIGHT -> first move
		if not picked and has_event("OAK_ASKED_TO_CHOOSE_MON") and not cutscene_active and modal == null:
			cutscene.choose_starter(_npc_by_key("SPRITE_POKE_BALL@7,3"))
			picked = true
			print("[playthrough] chose the first starter ball")
		if picked and not challenged and has_event("GOT_STARTER") and not cutscene_active and modal == null:
			print("[playthrough] MILESTONE got-starter: %s" % player_starter)
			player.place(Vector2i(5, 6))
			_on_player_moved(Vector2i(5, 6))
			challenged = true
		if has_event("BEAT_RIVAL1") and not cutscene_active and modal == null:
			done = true
			break
	if not (done and has_event("GOT_STARTER") and player_party.size() > 0):
		return _pt_fail("stalled in opening")
	print("[playthrough] MILESTONE opening-complete: map=%s starter=%s rival=%s" % [
		center_label, player_starter, rival_starter])
	return true


## Oak's Parcel errand: Viridian Mart hands over the parcel, deliver it to Oak for the POKéDEX
## (which unblocks the Viridian north gate).
func _pt_stage_parcel() -> bool:
	if not await _pt_warp_out("PalletTown"):
		return _pt_fail("leave Oak's Lab")
	if not await _pt_hop(1, "Route1"):
		return _pt_fail("Pallet -> Route1")
	if not await _pt_hop(1, "ViridianCity"):
		return _pt_fail("Route1 -> Viridian")
	print("[playthrough] MILESTONE reached ViridianCity (parcel run)")
	if not await _pt_warp_out("ViridianMart"):
		return _pt_fail("enter Viridian Mart")
	await _drive_until(func() -> bool: return has_event("GOT_OAKS_PARCEL") and modal == null and not cutscene_active, 800)
	if not has_event("GOT_OAKS_PARCEL"):
		return _pt_fail("clerk did not hand over the parcel")
	print("[playthrough] MILESTONE got OAK's PARCEL")
	if not await _pt_warp_out("ViridianCity"):
		return _pt_fail("exit Viridian Mart")
	if not await _pt_hop(0, "Route1"):
		return _pt_fail("Viridian -> Route1 (south)")
	if not await _pt_hop(0, "PalletTown"):
		return _pt_fail("Route1 -> Pallet (south)")
	if not await _pt_warp_out("OaksLab"):
		return _pt_fail("enter Oak's Lab")
	if not await _pt_interact_from(Vector2i(5, 3), 1):     # stand below Oak (5,2), face UP
		return _pt_fail("reach Oak to deliver")
	await _drive_until(func() -> bool: return has_event("GOT_POKEDEX") and modal == null and not cutscene_active, 1200)
	if not has_event("GOT_POKEDEX"):
		return _pt_fail("deliver parcel / no POKéDEX")
	print("[playthrough] MILESTONE got POKéDEX")
	return true


## Grind on Route 1's safe wilds, cross the now-open Viridian gate, take the Viridian Forest detour,
## and beat Brock for the BOULDERBADGE.
func _pt_stage_brock() -> bool:
	if not await _pt_warp_out("PalletTown"):
		return _pt_fail("leave Oak's Lab #2")
	if not await _pt_hop(1, "Route1"):
		return _pt_fail("Pallet -> Route1 #2")
	await _pt_grind_to(12)                             # Route 1's wilds are safe (no poison-stingers)
	print("[playthrough] MILESTONE grind on Route 1 -> lead L%d" % int(player_party[0]["level"]))
	if not await _pt_hop(1, "ViridianCity"):
		return _pt_fail("Route1 -> Viridian #2")
	if not await _pt_hop(1, "Route2"):
		return _pt_fail("Viridian -> Route2 (POKeDEX gate)")
	print("[playthrough] MILESTONE reached Route2 (Viridian gate passed with the POKeDEX)")
	if not await _pt_traverse_viridian_forest():
		return _pt_fail("Viridian Forest -> Pewter")
	print("[playthrough] MILESTONE reached PewterCity (lead L%d)" % int(player_party[0]["level"]))
	# Register the Pewter Center as the respawn and carry potions before challenging Brock, then retry on a
	# whiteout — heal, re-approach, go again — so one RNG-unlucky fight can't end the run (gh #131). Without a
	# potion the mid-battle heal (`_pt_should_heal`) can't fire, so an Onix Bind-lock + Rock Throw chip can
	# faint a winnable L12 Squirtle; at 25× the frame-timing-shifted RNG makes that non-negligible. A real
	# player heals at the Center and tries again — the Misty / Elite Four loops already do exactly this.
	respawn_map = "PewterPokecenter"
	heal_party()
	for attempt in 4:
		_pt_buy("POTION", 8)
		if str(center_label) != "PewterCity" and not await _pt_warp_out("PewterCity"):
			return _pt_fail("return to Pewter for Brock (on %s)" % center_label)
		if await _pt_beat_brock() or has_event("BEAT_BROCK"):
			break
		print("[playthrough] Brock attempt %d lost (whited out to %s) — heal + retry" % [attempt + 1, center_label])
		heal_party()
	if not has_event("BEAT_BROCK"):
		return _pt_fail("Pewter Gym / Brock (all attempts)")
	print("[playthrough] MILESTONE beat BROCK — %s (lead L%d)" % [str(badges), int(player_party[0]["level"])])
	return true


## --- Checkpoint / resume plumbing (gh #76, ADR-011): each stage's end-state is a real save so a
## later stage can be debugged without replaying the whole run. ---
func _pt_ckpt_path(stage: String) -> String:
	return "user://pt_ckpt_%s.json" % stage


func _pt_save_ckpt(stage: String) -> void:
	var prev := SAVE_PATH
	SAVE_PATH = _pt_ckpt_path(stage)
	save_game()
	SAVE_PATH = prev


func _pt_load_ckpt(stage: String) -> bool:
	var p := _pt_ckpt_path(stage)
	if not FileAccess.file_exists(p):
		return false
	var prev := SAVE_PATH
	SAVE_PATH = p
	var ok := load_game()
	SAVE_PATH = prev
	return ok


## Value of a `--flag=<v>` or `--flag <v>` cmdline arg, or "".
func _pt_arg_value(flag: String) -> String:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		if a == flag and i + 1 < args.size():
			return args[i + 1]
		if a.begins_with(flag + "="):
			return a.substr(flag.length() + 1)
	return ""


## BFS from the player over walkable, NPC-free cells; return the nearest reachable grass cell (or
## (-1,-1)). Used by the grind so it never teleports into a walled-off patch.
func _pt_nearest_grass() -> Vector2i:
	if is_grass_cell(player.cell):
		return player.cell                     # already standing on grass (e.g. after a catch) — grind here
	var seen := {player.cell: true}
	var q: Array[Vector2i] = [player.cell]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if cur != player.cell and is_grass_cell(cur):
			return cur
		for d in 4:
			var nx: Vector2i = cur + DIRV4[d]
			if not seen.has(nx) and _pt_on_center(nx) and player_can_enter(nx):   # center map only
				seen[nx] = true
				q.append(nx)
	return Vector2i(-1, -1)


## Route 2 is walled straight through; the faithful path north is via the forest gate buildings and
## the Viridian Forest maze. Returns true once Pewter City is reached.
func _pt_traverse_viridian_forest() -> bool:
	if not await _pt_warp_out("ViridianForestSouthGate"):
		return false
	if not await _pt_warp_out("ViridianForest"):
		return false
	if not await _pt_warp_out("ViridianForestNorthGate"):
		return false
	if not await _pt_warp_out("Route2"):
		return false
	return await _pt_hop(1, "PewterCity")


## Reach a leader/NPC and beat it on merit. `stand_cell`+`face_dir` name the primary spot, but the
## gym's own trainers engage on sight as we approach and can march onto it, so we try every cell
## adjacent to the leader (guard-aware walk — clearing those sight-trainers en route), face back toward
## it, interact, and drive the dialogue + battle(s) (YES to any challenge, heal when low) until
## `win_event` is set. `avoid_warps` keeps the approach off the floor's warps — Saffron Gym's rooms are
## floored with teleport pads. `spin_aware` models a step onto an arrow as landing on its stop tile —
## Viridian Gym's floor is a spinner maze and is not walkable without it. Returns false on a loss (a
## whiteout changes the map) or if it can't be reached.
func _pt_talk_and_battle(stand_cell: Vector2i, face_dir: int, win_event: String, budget := 8000,
		avoid_warps := false, spin_aware := false) -> bool:
	var here := str(center_label)
	var leader: Vector2i = stand_cell + DIRV4[face_dir]           # the NPC we came to fight
	var stands: Array = [[stand_cell, face_dir]]                  # primary first, then the other sides
	for d in 4:
		var s: Vector2i = leader + DIRV4[d]
		if s != stand_cell:
			stands.append([s, d ^ 1])                            # face back toward the leader (0<->1, 2<->3)
	for sc in stands:
		if has_event(win_event):
			return true
		var cell: Vector2i = sc[0]
		if not _pt_on_center(cell):
			continue
		if not await _pt_walk_dungeon(cell, 3000, spin_aware, avoid_warps):
			if str(center_label) != here:
				return false                                     # whited out approaching
			continue
		if player.cell != cell:
			continue
		heal_party()                                         # top up (HP + PP) before the leader — a real
		player.facing = int(sc[1])                           # player heals at the town Center first
		interact(player)
		var won := func() -> bool: return has_event(win_event)
		match await _pt_drive_talk(won, here, budget):
			_PtTalk.DONE:
				return true
			_PtTalk.WHITEOUT:
				return false                                     # whited out — the battle was lost
			_:
				pass                                             # dialogue ended, no win — try another side
	return has_event(win_event)


## Outcome of one talk-to attempt (see _pt_drive_talk).
enum _PtTalk {
	DONE,        # `done` came true with control handed back
	ENDED,       # dialogue closed without it — approach from another side and retry
	WHITEOUT,    # the battle was lost; we respawned on another map
}


## Drive one talk-to attempt to a conclusion: the battle it starts (won on merit, healing when the
## lead drops below half), YES to any "want to challenge?" prompt, and the dialogue in between —
## until `done` holds. `here` is the map we started on, so a whiteout is detectable.
func _pt_drive_talk(done: Callable, here: String, budget: int) -> _PtTalk:
	for _i in budget:
		if done.call() and modal == null and not cutscene_active:
			return _PtTalk.DONE
		if str(center_label) != here:
			return _PtTalk.WHITEOUT
		if modal == battle:
			await _pt_win_battle()
			if not player_party.is_empty() and int(player_party[0]["hp"]) < int(player_party[0]["maxhp"]) / 2:
				heal_party()
			await _drive_until(func() -> bool: return modal == null, 300)
			continue
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == menu:
			menu.chosen.emit(0)                                  # YES to a "want to challenge?" prompt
		elif modal == null and not cutscene_active:
			return _PtTalk.ENDED
		await get_tree().process_frame
	return _PtTalk.ENDED


## Enter Pewter Gym and beat Brock (OPP_BROCK is SPRITE_SUPER_NERD@4,1; stand at (4,2) facing up).
func _pt_beat_brock() -> bool:
	if not await _pt_warp_out("PewterGym"):
		return false
	return await _pt_talk_and_battle(Vector2i(4, 2), 1, "BEAT_BROCK")


## --- Legit-play navigation helpers (gh #76): faithful on-foot movement ---
## Direction enum (find_path / Player: 0=DOWN 1=UP 2=LEFT 3=RIGHT) -> input action / ledge name.
const _PT_DIR_ACTION := {0: "ui_down", 1: "ui_up", 2: "ui_left", 3: "ui_right"}
const _PT_DIR_NAME := {0: "down", 1: "up", 2: "left", 3: "right"}


## True while `cell` lies on the active center map (placed[0], offset 0) — used to keep the bot's
## intra-map pathfinding off connected neighbor maps.
func _pt_on_center(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < gw and cell.y < gh


## Ledge-aware pathfinder for the bot: like find_path, but also follows one-way ledge hops (a step in
## a ledge direction lands 2 tiles ahead). Route 1 south, for one, is impassable without this.
## Returns a list of Player-enum dirs, or [] if unreachable.
## The rest cell a spin-arrow slides the player to: apply its extracted RLE path once (Rocket Hideout
## arrows never chain onto another arrow — verified). A non-arrow cell returns itself, so this is a
## no-op off the spinner maps. Used by spin_aware planning so a step ONTO an arrow is modelled as
## landing on its stop tile (RocketHideoutB2F/B3F, ViridianGym).
func _pt_spin_dest(cell: Vector2i) -> Vector2i:
	var path: Array = spinners.get(center_label, {}).get("%d,%d" % [cell.x, cell.y], [])
	var cur := cell
	for seg in path:
		cur += DIRV4[int(seg[0])] * int(seg[1])
	return cur


func _pt_plan(start: Vector2i, goal: Vector2i, avoid_warps := false, spin_aware := false,
		blocked := {}) -> Array:
	if start == goal:
		return []
	var came := {start: null}          # cell -> [prev_cell, dir]
	var q: Array[Vector2i] = [start]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if cur == goal:
			break
		for d in 4:
			var dv: Vector2i = DIRV4[d]
			var nx: Vector2i = cur + dv
			# The cell we actually come to rest on: normally `nx`, but on a spinner map a step ONTO an
			# arrow slides us to its stop tile (spin_aware), so the graph edge lands there.
			var eff: Vector2i = _pt_spin_dest(nx) if spin_aware else nx
			# player_can_enter (not is_walkable) so the plan routes AROUND solid NPCs — matching what
			# a real step allows; the goal cell is exempt (it may be an occupied warp mat). Stay on the
			# CENTER map: _cell_walkable also reports connected neighbors as passable, so without this
			# bound the BFS would detour through a neighbor (e.g. across Route 3 to reach Route 4's far
			# edge) and the walk would slide onto the wrong map (gh #76). avoid_warps also treats any
			# non-goal warp mat as impassable, so a walk to a specific warp (a ship's captain's-room door)
			# routes around the other warps sharing the map instead of tripping one en route.
			# A warp cell whose feet tile FIRES ON STEP (stairs, mats, doors) always ejects the
			# walker off the map — in pokered and the port alike — so mid-route it is a wall, not
			# floor (the goal exemption above still lets a walk END on one). Without this, the
			# gh #142 door-step (which pushes an arrival OFF its landing warp, re-arming it) makes
			# the planner bounce straight back through paired stairs like Rocket Hideout B3F's.
			# gh #27: mirror the step's solid-warp rule (gh #149, Player.gd) — a warp set
			# into a SOLID tile (a gate door in a wall, e.g. Route 7's (11,9)) bumps unless
			# this step's facing fires it, so from a non-firing side it is not an edge at
			# all (not even as the goal); from the firing side it ejects the walker, i.e.
			# it behaves like fires_en_route. Before #149 the bot crossed Route 7 by
			# walking THROUGH the solid door; after it, an unmodeled planner stranded the
			# sabrina->blaine leg at the gate mat.
			var solid_warp: bool = _warp_at(nx) != null and not _cell_walkable(nx)
			var solid_warp_bump: bool = solid_warp and not _warp_should_fire(nx, d)
			var fires_en_route: bool = (_warp_at(nx) != null \
					and _feet_tile(nx) in _WARP_DOOR_TILES.get(center_tileset, [])) \
					or (solid_warp and not solid_warp_bump)
			if not came.has(eff) and not _tile_pair_blocked(cur, nx) and not blocked.has(nx) \
					and (eff == goal or (_pt_on_center(nx) and player_can_enter(nx) \
					and _pt_on_center(eff) and not fires_en_route and not solid_warp_bump \
					and not (avoid_warps and _warp_at(nx) != null))):
				came[eff] = [cur, d]
				q.append(eff)
			if ledge_match(cur, _PT_DIR_NAME[d], dv):     # one-way hop -> lands 2 tiles ahead
				var lx: Vector2i = cur + dv * 2
				if not came.has(lx) and (lx == goal or (_pt_on_center(lx) and player_can_enter(lx) \
						and not (avoid_warps and _warp_at(lx) != null))):
					came[lx] = [cur, d]
					q.append(lx)
	if not came.has(goal):
		return []
	var dirs: Array = []
	var c: Vector2i = goal
	while came[c] != null:
		dirs.push_front(came[c][1])
		c = came[c][0]
	return dirs


## How many frames `seconds` of tween takes at the current frame rate and time scale, plus slack. The
## bot's budgets used to be fixed frame counts written for 60 fps, but `_playthrough` sets
## `Engine.max_fps = 500`, where a 0.08 s turn-in-place takes **40** frames — exactly the old turn budget.
## The key was released mid-turn and the step never happened. `_pt_walk_to` retried and hid it;
## `_pt_cross` takes exactly one step, so the continuous run died crossing Route 1 into Pallet (gh #99).
func _pt_frames(seconds: float) -> int:
	var fps := float(Engine.max_fps) if Engine.max_fps > 0 else 60.0
	return int(ceil(seconds / maxf(Engine.time_scale, 0.01) * fps)) + 30


## Take one faithful step in `dir` by driving real input. Going through the real movement means the
## step emits `moved`, so warps, connections, trainer sight, and wild encounters all trigger
## natively (a scripted step() would skip them). Returns true if the player advanced a tile or the
## step changed the map (a connection/warp crossing).
func _pt_step(dir: int) -> bool:
	var action: String = _PT_DIR_ACTION[dir]
	var before: Vector2i = player.cell
	var from_map := str(center_label)
	Input.action_press(action)
	var g := 0
	var turn_budget := _pt_frames(0.08)                      # Player.TURN_TIME
	var move_budget := turn_budget + _pt_frames(0.6)         # a 0.536s ledge jump is the longest move
	# turn-in-place then the step/ledge-jump starts; wait for it, or bail early if the step
	# triggered a battle / cutscene / map change
	while not player.moving and not player.jumping and player.cell == before and center_label == from_map \
			and modal == null and not cutscene_active and g < turn_budget:
		await get_tree().process_frame
		g += 1
	while (player.moving or player.jumping) and g < move_budget:
		await get_tree().process_frame
		g += 1
	Input.action_release(action)
	await get_tree().process_frame            # let moved.emit + its handler run (warp/encounter/rebase)
	return player.cell != before or center_label != from_map


## Fight or wait out whatever the last step put on screen, so the caller's next `_pt_step` isn't
## refused by `modal != null`.
func _pt_settle(budget := 600) -> void:
	if modal == battle:
		await _pt_win_battle()
		await _drive_until(func() -> bool: return modal == null, budget)
		if not player_party.is_empty() and int(player_party[0]["hp"]) < int(player_party[0]["maxhp"]) / 3:
			heal_party()                      # persistent-player: top up when low (abstracts a Center trip)
	await _drive_until(func() -> bool: return modal == null and not cutscene_active, budget)


## Walk to `goal` on the current map on foot, replanning each step and pausing for any battle or
## cutscene a step triggers. Returns true on arrival, or if a step crossed into a different map.
func _pt_walk_to(goal: Vector2i, budget := 1200, avoid_warps := false, spin_aware := false) -> bool:
	var start_map := str(center_label)
	var stuck := 0
	# gh #27: cells this walk has been PUSHED OFF. A map script can answer a step by shoving
	# the player somewhere else — Cinnabar's locked Gym door (18,4) faces you up, says "The
	# door is locked...", and walks you back down. That lands the player on a *different*
	# cell than planned, so `_pt_step` reports success and `stuck` never trips: the walk
	# re-plans the same route and bounces forever until its budget dies, silently. Treating
	# an unplanned landing as "that cell is impassable, for this walk" makes the planner
	# route around exactly like a player who just read the sign.
	var bumped := {}
	for _i in budget:
		if center_label != start_map:
			return true                       # a step crossed a warp/connection — arrived elsewhere
		if player.cell == goal:
			# The step that lands on `goal` can start a wild battle, and this used to return with it
			# still up — so the caller's next _pt_step refused and the walk looked like it had failed.
			# Route 1's south edge is grass, which is how it killed the continuous run (gh #99).
			await _pt_settle()
			return true
		if modal == battle:
			await _pt_win_battle()
			await _drive_until(func() -> bool: return modal == null, 300)
			if not player_party.is_empty() and int(player_party[0]["hp"]) < int(player_party[0]["maxhp"]) / 3:
				heal_party()                  # persistent-player: top up when low (abstracts a Center trip)
			continue
		if modal != null or cutscene_active:
			await _drive_until(func() -> bool: return modal == null and not cutscene_active, 300)
			continue
		var dirs := _pt_plan(player.cell, goal, avoid_warps, spin_aware, bumped)
		if dirs.is_empty():
			return false
		var want: Vector2i = player.cell + DIRV4[int(dirs[0])]
		if await _pt_step(int(dirs[0])):
			# Landed somewhere the plan never chose — a script pushed us off (see `bumped`).
			# A ledge hop legitimately lands two cells ahead, so it is not a bump.
			if center_label == start_map and player.cell != want \
					and player.cell != want + DIRV4[int(dirs[0])]:
				bumped[want] = true
				stuck += 1
				print("[playthrough] bumped off %s (pushed to %s) — routing around" % [
					str(want), str(player.cell)])
			else:
				stuck = 0
		else:
			# The step was refused. A wandering NPC clears on its own, so retry a few
			# times first; a cell that keeps refusing is a fact about the map (Cinnabar's
			# locked Gym door answers a step by facing you up, printing "The door is
			# locked..." and walking you back — the player never leaves the cell, so this
			# is the same silent trap as a push-back). Mark it and re-plan around it.
			stuck += 1
			if stuck >= 3:
				bumped[want] = true
				stuck = 0
				print("[playthrough] %s refuses (%d tries) — routing around" % [str(want), 3])
		if bumped.size() > 40:                # too much of the map refuses us: give up
			return false
	return player.cell == goal


## Leave the current building on foot via its warp back to `dest_map`: walk onto the mat, which —
## through real movement — fires the warp. Returns true once the active map is `dest_map`.
## Walk onto the warp whose destination is `dest_map` (a building exit's LAST_MAP mat, or an
## overworld warp naming the building it enters) so real movement fires the warp. Returns true once
## the active map is `dest_map`.
func _pt_warp_out(dest_map: String, avoid_warps := false) -> bool:
	var exit_cell := Vector2i(-1, -1)
	var is_last_map := false
	# Prefer a warp that explicitly names dest_map (e.g. the ladder to the tunnel); only fall back to a
	# LAST_MAP warp (which resolves to where we came from) when there's no explicit one. A map can have
	# both (an entrance building has LAST_MAP exits AND a specific onward warp).
	for w in map["warps"]:
		if str(w.get("dest_map", "")) == dest_map:
			exit_cell = Vector2i(int(w["x"]), int(w["y"]))
			break
	if exit_cell.x < 0:
		for w in map["warps"]:
			if str(w.get("dest_const", "")) == "LAST_MAP":
				exit_cell = Vector2i(int(w["x"]), int(w["y"]))
				is_last_map = true
				break
	if exit_cell.x < 0:
		print("[playthrough] warp_out(%s): %s has no warp to it" % [dest_map, center_label])
		return false
	if is_last_map:
		# gh #30: forcing the LAST_MAP resolution is honest for buildings — the door physically opens
		# onto the town/route the caller names (a Center door, a gate house's street side) — but from
		# a cave it is a teleport cheat: a cave mouth's LAST_MAP edge warps lead wherever we genuinely
		# entered from, and naming anywhere else would warp the bot across the world. In a cavern,
		# only a truthful resolution may walk.
		if center_tileset == "cavern" and str(last_outside_map) != dest_map:
			print("[playthrough] warp_out(%s): %s's mouth leads to %s — refusing to force a cave exit" % [
				dest_map, center_label, str(last_outside_map)])
			return false
		last_outside_map = dest_map            # make the LAST_MAP exit resolve to where we came from
	# A warp only fires on the `moved` that lands on it (`warp_armed` is cleared when we arrive standing
	# on one), so we cannot exit from under our own feet. That happens after a blackout: pokered's
	# SpecialWarpIn drops you on the Pokécenter's door mat (gh #97). Step off and let the walk land on it.
	if player.cell == exit_cell and not warp_armed:
		for d in 4:
			var off: Vector2i = exit_cell + DIRV4[d]
			if _pt_on_center(off) and player_can_enter(off) and _warp_at(off) == null:
				if await _pt_step(d):
					break
	# Always plan spin-aware: on the three arrow-floor maps (Rocket Hideout B2F/B3F, Viridian Gym) a
	# non-spin plan is simply wrong — the engine slides the walker off it — and on every other map the
	# flag is a no-op (no spinner table). Walking OUT of Viridian Gym is what surfaced this (gh #76).
	await _pt_walk_to(exit_cell, 1200, avoid_warps, true)   # stepping onto the mat fires the warp via moved
	await _drive_until(func() -> bool: return center_label == dest_map and modal == null, 300)
	# An edge warp whose feet tile isn't a door/warp tile (e.g. a Poké Mart exit) fires only on a step
	# TOWARD the map edge (gh #80); if the walk arrived facing along the edge, press out to leave.
	if center_label != dest_map and player.cell == exit_cell:
		var edge := -1
		if exit_cell.y == gh - 1: edge = 0          # DOWN
		elif exit_cell.y == 0: edge = 1             # UP
		elif exit_cell.x == 0: edge = 2             # LEFT
		elif exit_cell.x == gw - 1: edge = 3        # RIGHT
		if edge >= 0:
			await _pt_step(edge)
			await _drive_until(func() -> bool: return center_label == dest_map and modal == null, 300)
	if center_label != dest_map:
		# gh #29: this walk used to fail silently, and a whole stage died with nothing in the log.
		# Name where it actually ended — "which cell" is the diagnosis for a wander-RNG blockage.
		print("[playthrough] warp_out(%s): walk ended on %s @%s (aimed for the %s door)" % [
			dest_map, center_label, str(player.cell), str(exit_cell)])
	return center_label == dest_map


## Cross a map edge on foot in `dir` (Player enum: 0=DOWN 1=UP 2=LEFT 3=RIGHT): walk to the nearest
## reachable edge cell whose neighbor beyond is walkable, then step off so the connection rebases
## natively. Returns true if the map changed.
## `prefer` names the perpendicular coordinate (y when crossing left/right, else x) to leave by, for the
## seams where the rows on the far side are not interchangeable: Route 13's west edge lines up with
## Route 14's row-6 pocket, a one-tile corridor a BIRD KEEPER stands in facing away, so a bot that walks
## straight across has to back out. Default (-1) leaves by the edge cell nearest the player.
func _pt_cross(dir: int, budget := 1200, prefer := -1) -> bool:
	var from := str(center_label)
	var step: Vector2i = DIRV4[dir]
	var horizontal := dir >= 2
	var best := Vector2i(-1, -1)
	var best_dist := 1 << 30
	var n: int = gh if horizontal else gw
	for i in n:
		var edge: Vector2i = (Vector2i(0 if dir == 2 else gw - 1, i) if horizontal
			else Vector2i(i, 0 if dir == 1 else gh - 1))
		if not (is_walkable(edge) and is_walkable(edge - step) and is_walkable(edge + step)):
			continue
		var ref: int = prefer if prefer >= 0 else (player.cell.y if horizontal else player.cell.x)
		var ec: int = edge.y if horizontal else edge.x
		var d: int = absi(ec - ref)
		if d >= best_dist:
			continue
		if player.cell == edge or not _pt_plan(player.cell, edge).is_empty():
			best_dist = d
			best = edge
	if best.x < 0:
		print("[cross] %s: no reachable %s edge cell (from %s)" % [from, _PT_DIR_NAME[dir], str(player.cell)])
		return false
	if not await _pt_walk_to(best, budget):
		print("[cross] %s: stuck reaching the %s edge %s (at %s)" % [
			from, _PT_DIR_NAME[dir], str(best), str(player.cell)])
		return false
	for _i in 3:                                # step off the edge -> connection rebase
		await _pt_settle()                      # an edge cell in grass can hand us a wild battle
		await _pt_step(dir)                     # a step that only turned us leaves the facing set: retry
		await _drive_until(func() -> bool: return center_label != from and modal == null, 300)
		if center_label != from:
			return true
	print("[cross] %s: stepped %s off %s but stayed put (at %s, modal=%s cutscene=%s)" % [
		from, _PT_DIR_NAME[dir], str(best), str(player.cell), modal != null, cutscene_active])
	return false


func _pt_cross_north(budget := 1200) -> bool:
	return await _pt_cross(1, budget)


func _pt_cross_south(budget := 1200) -> bool:
	return await _pt_cross(0, budget)


## Cross an edge and require arrival at `target`.
func _pt_hop(dir: int, target: String, prefer := -1) -> bool:
	var ok := await _pt_cross(dir, 1200, prefer)
	return ok and center_label == target


## Walk to `stand_cell` on foot, face `face_dir`, and interact (talk / read a sign). The caller
## waits on the resulting event.
func _pt_interact_from(stand_cell: Vector2i, face_dir: int) -> bool:
	if not await _pt_walk_to(stand_cell):
		return false
	player.facing = face_dir
	interact(player)
	return true


## Solve the Vermilion Gym trash-can switch puzzle (scripts/VermilionGym.asm): the two hidden switches
## are transient state on Main (_trash_first, then _trash_second once the first is flipped), so the bot
## reads them and faces exactly those two cans in order — exercising the real 1st/2nd-lock → motorized-
## door path (block 2,2 opens). Returns true once VERMILION_2ND_LOCK is set.
func _pt_solve_trash() -> bool:
	if has_event("VERMILION_2ND_LOCK"):
		return true
	if not has_event("VERMILION_1ST_LOCK") and not await _pt_flip_trash(_trash_first):
		return false
	if not await _pt_flip_trash(_trash_second):
		return false
	return has_event("VERMILION_2ND_LOCK")


## Walk to trash can `ci` (a 5x3 grid: x in {1,3,5,7,9}, y in {7,9,11}), face it, and interact.
func _pt_flip_trash(ci: int) -> bool:
	var can := Vector2i(int(ci / 3) * 2 + 1, int(ci % 3) * 2 + 7)
	for d in 4:                                         # try an adjacent cell we can reach, facing the can
		var stand: Vector2i = can + DIRV4[d]
		if not (_pt_on_center(stand) and (player.cell == stand or not _pt_plan(player.cell, stand).is_empty())):
			continue
		if not await _pt_walk_to(stand):
			continue
		player.facing = d ^ 1                          # face back toward the can (0<->1 down/up, 2<->3 l/r)
		interact(player)
		await _drive_until(func() -> bool: return modal == null and not cutscene_active, 300)
		return true
	return false


## Report a dead-end. Stages do `return _pt_fail("...")` (-> bool false); the driver then quits.
func _pt_fail(reason: String) -> bool:
	var lead := "-"
	if not player_party.is_empty():
		lead = "%s L%d" % [player_party[0]["species"], int(player_party[0]["level"])]
	print("[playthrough] FAIL(%s): map=%s cell=%s lead=%s" % [reason, center_label, str(player.cell), lead])
	return false


## Battle policy: at the action menu, HEAL if low, else voluntarily SWITCH when the active mon is at a
## type disadvantage and a safer live mon can take over (a Ground mon vs Lt. Surge — see
## _pt_should_switch), else FIGHT with the strongest usable move; on a faint send out the best-matchup
## mon. Drives the current battle until its modal closes; the outcome is in battle.won / .blacked_out.
func _pt_win_battle(budget := 800) -> void:
	var g := 0
	while modal == battle and g < budget:
		g += 1
		if battle.state == "menu" and battle.is_safari:
			battle.cursor = 3                          # BALL/BAIT/ROCK/*RUN* — nothing to fight in the park,
			await _press("ui_accept")                  # and a safari mon never holds you (TryRunningFromBattle)
		elif battle.state == "menu":
			var heal := _pt_should_heal()
			var swap := not heal and _pt_should_switch()
			if _pt_battle_log:
				print("[battle] %s %d/%d vs %s %d/%d -> %s (potions=%d)" % [
					battle.player_mon["species"], int(battle.player_mon["hp"]), int(battle.player_mon["maxhp"]),
					battle.enemy_mon["species"], int(battle.enemy_mon["hp"]), int(battle.enemy_mon["maxhp"]),
					"HEAL" if heal else ("SWITCH" if swap else "FIGHT"), int(player_bag.get(_pt_heal_item_key(), 0))])
			battle.cursor = 2 if heal else (1 if swap else 0)   # ITEM (heal) / PKMN (switch) / FIGHT
			await _press("ui_accept")
		elif battle.state == "moves":
			battle.cursor = _pt_best_move_idx()        # strongest damaging move by power x type
			await _press("ui_accept")
		elif battle.state == "item":                   # heal the active mon with the best potion
			var hk := _pt_heal_item_key()
			var idx: int = battle.bag_keys.find(hk)
			battle.cursor = idx if (hk != "" and idx >= 0) else battle.bag_keys.size()   # else CANCEL
			await _press("ui_accept")
		elif battle.state == "party":                  # voluntary switch: send in the safe attacker
			battle.cursor = _pt_best_switch_target()
			await _press("ui_accept")
		elif battle.state == "party_forced":           # lead fainted: send out the best matchup
			battle.cursor = _pt_best_actor()
			await _press("ui_accept")
		elif battle.state == "learn":
			# A level-up with four moves already known. The cursor starts on slot 0, so the old `else`
			# below pressed A on it — which is how a L43 Blastoise traded SURF for SKULL BASH and
			# stranded the run one stage later (gh #93). Give up the worst non-HM move instead, or GIVE
			# UP entirely when the incoming move is a status move and the alternative still hits.
			var mon: Dictionary = battle.player_mon
			var w := _pt_worst_move(mon)
			var give_up: int = (mon["moves"] as Array).size()
			var new_power := int(mon_moves.get(str(battle.learn_move), {}).get("power", 0))
			var old_power: int = 0 if w < 0 else int(mon_moves.get(str(mon["moves"][w]["move"]), {}).get("power", 0))
			battle.cursor = w if (w >= 0 and (new_power > 0 or old_power == 0)) else give_up
			await _press("ui_accept")
		else:
			await _press("ui_accept")                  # advance messages / level-up boxes
	if modal == battle:
		# gh #38: a battle the budget couldn't finish used to return SILENTLY — and every caller
		# (e.g. _pt_walk_to's battle branch) just re-enters, multiplying budgets into hours of
		# quiet CPU. Say so; the watchdog ends the run if the state really is frozen.
		print("[playthrough] win_battle: budget (%d) died with the battle still up — state=%s vs %s" % [
			budget, str(battle.state), str(battle.enemy_mon.get("species", "?"))])


## The best healing potion in the bag (biggest heal first), or "" if none.
func _pt_heal_item_key() -> String:
	for h in ["FULL RESTORE", "MAX POTION", "HYPER POTION", "SUPER POTION", "POTION"]:
		if int(player_bag.get(h, 0)) > 0:
			return h
	return ""


## Heal mid-battle when the active mon drops below ~40% HP and we're holding a potion — the
## persistent-player survivability the whole run leans on (issue #76 user story 11). A water-resisting
## Wartortle that keeps topping up out-lasts Misty's Starmie regardless of the damage rolls.
## Reach for an item when the lead is low — or when it is asleep or frozen and the bag holds something
## that cures that. A full-HP mon put to sleep never acts again, and it never got low enough to trigger
## the HP rule: the CHAMPION's L65 VENUSAUR knows SLEEP POWDER and SOLAR BEAM (2x on water), and it beat
## a L71 Blastoise four times running with eight FULL RESTOREs sitting unused in the bag (gh #94).
func _pt_should_heal() -> bool:
	var m: Dictionary = battle.player_mon
	if int(m["hp"]) <= 0:
		return false
	if str(m["status"]) in ["slp", "frz"] and int(player_bag.get("FULL RESTORE", 0)) > 0:
		return true                                    # FULL RESTORE clears status as well as HP
	if _pt_heal_item_key() == "":
		return false
	return float(m["hp"]) < 0.4 * float(m["maxhp"])


## Moves that cost a turn to use: CHARGE_EFFECT winds up (SKULL BASH, SOLARBEAM, DIG, SKY ATTACK, RAZOR
## WIND), FLY_EFFECT does the same, and HYPER_BEAM_EFFECT spends the turn after. Halve their score.
const _PT_TWO_TURN := ["CHARGE_EFFECT", "FLY_EFFECT", "HYPER_BEAM_EFFECT"]


## Pick the lead's best usable move against the current enemy: expected damage per *turn*, which is base
## power x type effectiveness x STAB x accuracy, halved for a move that costs two turns. Status (power 0)
## and out-of-PP moves are skipped; falls back to the first move with PP.
##
## Ranking raw `power * effectiveness` sent the run's Blastoise into SKULL BASH (100, and it charges) over
## a same-turn STRENGTH (80) against VENUSAUR, and over a STAB HYDRO PUMP worth 180 against ALAKAZAM. It
## fought the CHAMPION at half speed, and lost to him four times running (gh #94).
func _pt_best_move_idx() -> int:
	var moves: Array = battle.player_mon["moves"]
	var enemy_types: Array = battle.enemy_mon.get("types", [])
	var own_types: Array = battle.player_mon.get("types", [])
	var best := -1
	var best_score := 0.0
	for i in moves.size():
		if int(moves[i]["pp"]) <= 0:
			continue
		var md: Dictionary = battle.moves_db.get(str(moves[i]["move"]), {})
		var power := float(md.get("power", 0))
		if power <= 0.0:
			continue
		var mtype := str(md.get("type", ""))
		var eff := 1.0
		for dt in enemy_types:
			eff *= battle._type_mult(mtype, str(dt))
		var score := power * eff
		if mtype in own_types:
			score *= 1.5                                # same-type attack bonus
		score *= float(md.get("accuracy", 100)) / 100.0
		if str(md.get("effect", "")) in _PT_TWO_TURN:
			score *= 0.5                               # half the damage per turn spent
		if score > best_score:
			best_score = score
			best = i
	if best >= 0:
		return best
	for i in moves.size():                             # no damaging move usable -> first with PP
		if int(moves[i]["pp"]) > 0:
			return i
	return 0


## Grind the lead to `target_level` on merit — win real wild encounters on the current map's grass,
## healing to full (a Poké Center trip) whenever the lead drops low so a lone starter never blacks
## out (a blackout would whiteout to a respawn and swap the map out from under us). Returns the
## lead's resulting level.
func _pt_grind_to(target_level: int, budget := 400) -> int:
	if player_party.is_empty():
		return 0
	var grass := _pt_nearest_grass()               # reachable grass only (avoids a walled-off patch)
	if grass.x < 0:
		# Silence here is how a grind that never happened looks like a grind that did: Route 15's grass
		# sits east of its gate house, so a bot flown to Fuchsia found none and walked on unchanged.
		print("[playthrough] grind: no reachable grass on %s — lead stays L%d" % [
			center_label, int(player_party[0]["level"])])
		return int(player_party[0]["level"])
	var lead: Dictionary = player_party[0]
	var gmap := str(center_label)
	var tries := 0
	var fights := 0
	while int(lead["level"]) < target_level and tries < budget:
		tries += 1
		heal_party()                              # full heal before every fight so a lone starter
		player.place(grass)                       # can't be chipped down to a blackout across fights
		repel_steps = 0
		_try_wild_encounter("grass", true)        # force a fight every try (grind fast, headless)
		if modal == battle:
			fights += 1
			await _pt_win_battle()
			# wait out any post-battle cutscene too (a level-up evolution — Squirtle->Wartortle
			# at L16 — runs here) before the next iteration teleports onto grass.
			await _drive_until(func() -> bool: return modal == null and not cutscene_active, 400)
		if center_label != gmap:                  # blacked out / left the map -> stop grinding here
			break
	heal_party()                                       # leave the grind at full health
	print("[playthrough] MILESTONE grind: lead=L%d hp=%d/%d (%d fights) map=%s" % [
		int(lead["level"]), int(lead["hp"]), int(lead["maxhp"]), fights, center_label])
	return int(lead["level"])


## --- Team management (gh #76): a real, managed team — a bench so one faint can't white out the
## run, best-matchup send-outs, and balls bought with earned money. ---

## The cheapest Poké Ball in the bag (conserve the good ones), or "" if we're out.
func _pt_ball_key() -> String:
	for b in ["POKé BALL", "GREAT BALL", "ULTRA BALL", "MASTER BALL"]:
		if int(player_bag.get(b, 0)) > 0:
			return b
	return ""


## Buy `qty` of `item` at its real mart price, capped by money on hand (money earned in real
## battles — legit play) and the 99-per-slot cap. Abstracts a mart trip: the bot spends real
## money at the real price rather than driving the shop UI. Returns the number bought.
func _pt_buy(item: String, qty: int) -> int:
	var price := int(item_prices.get(item, 0))
	if price <= 0:
		return 0
	var n := mini(qty, player_money / price)
	n = mini(n, 99 - int(player_bag.get(item, 0)))
	if n <= 0:
		return 0
	player_money -= n * price
	add_item(item, n)
	print("[playthrough] bought %d %s (money now ¥%d)" % [n, item, player_money])
	return n


## The bot's bag fills up, and pokered's holds only 20 distinct items (wNumBagItems). A 21st item ball
## prints "But RED has no room for it!" and stays on the floor (_pick_up_item) — so a hoarding bot
## silently fails to take the GOLD TEETH, and can never trade them to the WARDEN for HM04 (gh #91).
## Stash the things it never uses, in the order it misses them least. Menus are abstracted here exactly
## as _pt_buy abstracts the mart; the PC is reachable from any Pokécenter, so no geometry is skipped.
const _PT_BAG_SPARE := ["HELIX FOSSIL", "DOME FOSSIL", "OLD AMBER", "FIRE STONE", "LEAF STONE",
	"MOON STONE", "THUNDER STONE", "WATER STONE", "NUGGET", "TM34", "TM11", "TM24", "TM21", "TM06"]
## ...and the things it must never stash: what it throws, what it heals with, and (via KEY_ITEMS) the
## HMs and story items. Everything else — vitamins, status heals, a stray TM, an ESCAPE ROPE — is fair
## game once the named list above runs dry, which it does: the bot picks up every ball in a corridor.
const _PT_BAG_KEEP := ["POKé BALL", "GREAT BALL", "ULTRA BALL", "MASTER BALL", "SAFARI BALL",
	"POTION", "SUPER POTION", "HYPER POTION", "MAX POTION", "FULL RESTORE", "REVIVE", "MAX REVIVE"]


## Free `n` bag slots into the player's PC. Returns true once that many are free (a no-op with room).
func _pt_bag_room(n := 1) -> bool:
	var order: Array = _PT_BAG_SPARE.duplicate()
	for k in player_bag.keys():
		var key := str(k)
		if key in order or key in KEY_ITEMS or key in _PT_BAG_KEEP:
			continue
		order.append(key)                                  # a fallback the named list can't cover
	var stashed: Array = []
	for key in order:
		if BAG_CAPACITY - player_bag.size() >= n:
			break
		if not player_bag.has(key):
			continue
		pc_items[key] = int(pc_items.get(key, 0)) + int(player_bag[key])
		player_bag.erase(key)
		stashed.append(str(key))
	if not stashed.is_empty():
		print("[playthrough] stashed %s in the PC (bag %d/%d)" % [
			", ".join(stashed), player_bag.size(), BAG_CAPACITY])
	return BAG_CAPACITY - player_bag.size() >= n


## Best move score (base power x type effectiveness) `mon` could land on the current enemy — the
## same weighting as _pt_best_move_idx, but for an arbitrary party mon (used to pick a send-out).
func _pt_mon_score(mon: Dictionary) -> float:
	var enemy_types: Array = battle.enemy_mon.get("types", [])
	var best := 0.0
	for mv in mon["moves"]:
		if int(mv["pp"]) <= 0:
			continue
		var md: Dictionary = battle.moves_db.get(str(mv["move"]), {})
		var power := float(md.get("power", 0))
		if power <= 0.0:
			continue
		var mtype := str(md.get("type", ""))
		var eff := 1.0
		for dt in enemy_types:
			eff *= battle._type_mult(mtype, str(dt))
		best = maxf(best, power * eff)
	return best


## The live party member with the best matchup vs the current enemy (excludes the active/fainted
## mon). Used on a forced faint-switch; falls back to the engine's first-usable pick.
func _pt_best_actor() -> int:
	var best: int = battle._first_usable()
	var best_score := -1.0
	for i in battle.party.size():
		var m: Dictionary = battle.party[i]
		if int(m["hp"]) <= 0 or i == battle.active:
			continue
		var s := _pt_mon_score(m)
		if s > best_score:
			best_score = s
			best = i
	return best


## How hard the current enemy's STAB hits `mon` — the max over the enemy's types of the type chart
## against the mon's (de-duped) types. >=2 = the mon is at a disadvantage; 0 = immune.
func _pt_incoming_mult(mon: Dictionary) -> float:
	var enemy_types: Array = battle.enemy_mon.get("types", [])
	var seen := {}
	var mon_types: Array = []
	for mt in mon.get("types", []):
		if not seen.has(mt):
			seen[mt] = true
			mon_types.append(mt)
	var worst := 1.0
	for et in enemy_types:
		var m := 1.0
		for mt in mon_types:
			m *= battle._type_mult(str(et), str(mt))
		worst = maxf(worst, m)
	return worst


## Proactively switch when the active mon is at a type disadvantage (the enemy's STAB is >=2x on it)
## and a live bench mon takes it better AND can still damage the foe (a Ground mon vs Lt. Surge, say).
## Loop-safe: once we switch to a non-disadvantaged mon, the active is no longer weak, so we stop.
func _pt_should_switch() -> bool:
	var active_in := _pt_incoming_mult(battle.player_mon)
	if active_in < 2.0:
		return false
	var enemy_level := int(battle.enemy_mon.get("level", 0))
	for i in battle.party.size():
		var m: Dictionary = battle.party[i]
		if int(m["hp"]) <= 0 or i == battle.active:
			continue
		# Don't feed the bench to something that will one-shot it. The bot's bench trails the lead badly
		# (it routes around trainers, gh #94), and switching a L48 Blastoise out of a L40 VENUSAUR's way
		# sent in a L19 Growlithe that fainted on the spot — the chain-faint whited out Silph Co. The
		# coverage switches this policy exists for are all made by a mon within reach of the enemy's
		# level (DIGLETT L21 vs Surge's L24, GROWLITHE L18 vs Erika's L29), so 60% keeps them.
		if int(m["level"]) * 100 < enemy_level * 60:
			continue
		if _pt_incoming_mult(m) < active_in and _pt_mon_score(m) > 0.0:
			return true
	return false


## The live bench mon to switch to: among those that take the enemy better than the active mon, the
## strongest attacker (falls back to the best actor).
func _pt_best_switch_target() -> int:
	var active_in := _pt_incoming_mult(battle.player_mon)
	var best := -1
	var best_score := -1.0
	for i in battle.party.size():
		var m: Dictionary = battle.party[i]
		if int(m["hp"]) <= 0 or i == battle.active:
			continue
		if _pt_incoming_mult(m) < active_in and _pt_mon_score(m) > best_score:
			best_score = _pt_mon_score(m)
			best = i
	return best if best >= 0 else _pt_best_actor()


## Catch the current wild mon on merit: throw balls until it's caught, or KO it if we're out of
## balls (so the encounter always ends). Early wilds have very high catch rates, so full-HP throws
## land in a few balls — enough to build a bench without risking a KO from over-weakening. Returns
## true if caught. Assumes modal == battle, a wild (non-trainer) fight.
func _pt_catch(budget := 600) -> bool:
	var party0 := player_party.size()
	var box0 := pc_box.size()
	var g := 0
	while modal == battle and g < budget:
		g += 1
		if battle.caught:
			break
		match battle.state:
			"menu":
				battle.cursor = 2 if _pt_ball_key() != "" else 0   # ITEM (throw) else FIGHT (KO)
				await _press("ui_accept")
			"moves":                                     # no balls left: KO it to end the fight
				battle.cursor = _pt_best_move_idx()
				await _press("ui_accept")
			"item":
				var bk := _pt_ball_key()
				var idx: int = battle.bag_keys.find(bk)
				if bk == "" or idx < 0:
					battle.cursor = battle.bag_keys.size()   # CANCEL
				else:
					battle.cursor = idx
				await _press("ui_accept")
			"party_forced":
				battle.cursor = _pt_best_actor()         # our mon fainted mid-catch — send the next
				await _press("ui_accept")
			_:
				await _press("ui_accept")                # advance "Gotcha!" / broke-free messages
	await _pt_drive_catch_ceremony()
	return player_party.size() > party0 or pc_box.size() > box0


## After a successful throw, drive the catch ceremony to its end: advance texts, dismiss the
## POKéDEX-entry screen for a new species, and answer NO to the nickname offer.
func _pt_drive_catch_ceremony(budget := 1500) -> void:
	for _i in budget:
		if modal == null and not cutscene_active:
			return
		if modal == battle and battle.state in ["msg", "levelstats"]:
			await _press("ui_accept")
		elif textbox.active and textbox.visible:
			textbox.advance()
		elif modal == dexentry:
			dexentry.visible = false
			dexentry.closed.emit()
		elif modal == menu:
			menu.chosen.emit(1)                          # NO to the nickname offer
		await get_tree().process_frame


## Build a bench so a single faint can't white out the run: catch wild mons on the current map's
## grass until the party reaches `target_size`. High-catch early wilds land in a few balls. Uses
## the grind's teleport-onto-grass + forced-encounter trick (headless, accelerated).
func _pt_build_team(target_size := 2, budget := 60) -> void:
	if player_party.size() >= target_size:
		return
	var grass := _pt_nearest_grass()
	if grass.x < 0:
		return
	var gmap := str(center_label)
	var tries := 0
	while player_party.size() < target_size and tries < budget:
		tries += 1
		if _pt_ball_key() == "":
			break                                        # out of balls — carry on without a bench
		heal_party()
		player.place(grass)
		repel_steps = 0
		_try_wild_encounter("grass", true)               # force an encounter to catch
		if modal == battle:
			if battle.is_trainer:
				await _pt_win_battle()
			else:
				await _pt_catch()
			await _drive_until(func() -> bool: return modal == null and not cutscene_active, 500)
		if str(center_label) != gmap:                    # blacked out / left the map — stop
			break
	heal_party()
	print("[playthrough] MILESTONE team: party=%d %s" % [player_party.size(), str(_pt_party_summary())])


func _pt_party_summary() -> Array:
	var s: Array = []
	for m in player_party:
		s.append("%s L%d" % [str(m["species"]), int(m["level"])])
	return s


func _pt_has_species(sp: String) -> bool:
	for m in player_party:
		if str(m["species"]) == sp:
			return true
	return false


## Catch a specific wild species (optionally at `min_level`+, e.g. a Diglett L19+ so it already knows
## DIG) on the current map's grass: force encounters, catch a match, KO anything else and keep fishing.
## Returns true once it's in the party. Needs balls in the bag.
func _pt_catch_species(sp: String, budget := 50, min_level := 0) -> bool:
	if _pt_has_species(sp):
		return true
	var grass := _pt_nearest_grass()
	var spot := grass
	if grass.x < 0:                                          # a cave (Diglett's Cave) has no grass tiles —
		if int(wild_data.get("maps", {}).get(str(center_label), {}).get("grass_rate", 0)) <= 0:
			return false                                    # ...and no floor encounters either
		spot = player.cell                                  # wild mons are on the cave floor; force there
		if _warp_at(spot) != null:                          # but not sitting on the entrance/exit warp
			for d in 4:
				var n: Vector2i = spot + DIRV4[d]
				if _pt_on_center(n) and player_can_enter(n) and _warp_at(n) == null:
					spot = n
					break
	var gmap := str(center_label)
	var tries := 0
	while not _pt_has_species(sp) and tries < budget:
		tries += 1
		if _pt_ball_key() == "":
			break
		heal_party()
		player.place(spot)
		repel_steps = 0
		_try_wild_encounter("grass", true)
		if modal == battle:
			var e: Dictionary = battle.enemy_mon
			if not battle.is_trainer and str(e["species"]) == sp and int(e["level"]) >= min_level:
				await _pt_catch()
			else:
				await _pt_win_battle()                       # wrong species/level — KO it and fish again
			await _drive_until(func() -> bool: return modal == null and not cutscene_active, 500)
		if str(center_label) != gmap:
			break
	heal_party()
	warp_armed = _warp_at(player.cell) == null              # player.place left this stale; re-arm so the
	return _pt_has_species(sp)                               # caller can warp out of the cave (the exit warp)


## --- Misty stage (gh #76): Pewter -> Route 3 -> (Mt. Moon) -> Route 4 -> Cerulean -> MISTY. ---

## From the BOULDERBADGE win (inside Pewter Gym): stock balls, cross Route 3 (fighting its
## trainers on sight), climb to Route 4, build a small bench + grind past the Squirtle->Wartortle
## evolution, traverse to Cerulean (directly if Route 4 is open, else through the Mt. Moon maze),
## and beat MISTY for the CASCADEBADGE.
func _pt_stage_misty() -> bool:
	if not await _pt_warp_out("PewterCity"):
		return _pt_fail("leave Pewter Gym")
	_pt_buy("POKé BALL", 8)                             # stock up (Pewter Mart) with earned money
	if not await _pt_hop(3, "Route3"):
		return _pt_fail("Pewter -> Route3 (east)")
	print("[playthrough] MILESTONE reached Route3")
	# Grind + build a bench on Route 3's grass (Route 4's is walled off from the Mt. Moon-side
	# entrance): a 2nd mon is faint insurance, and ~L20 (topped up by Mt. Moon's Rockets to ~L21)
	# clears Misty's L21 Starmie on merit — a water-resisting Wartortle out-tanks her with TACKLE.
	await _pt_build_team(2)
	await _pt_grind_to(20, 80)                          # Wartortle by L16; Mt. Moon's Rockets top it up
	print("[playthrough] MILESTONE Route 3 grind -> lead L%d (%d mons)" % [
		int(player_party[0]["level"]), player_party.size()])
	# Carry healing + a Center respawn INTO Mt. Moon (gh #131). The cave's wild fights and Rocket grunts
	# grind the lead down, and with no potion the mid-battle heal can't fire — an RNG-unlucky faint used to
	# white out to Pallet's *default* respawn (no potions are bought until Cerulean, past the cave), which
	# ejected the run with no way back. A real player heals at the Pewter Center — making it the respawn —
	# and stocks up before the cave. `_pt_buy` self-caps to what's affordable.
	respawn_map = "PewterPokecenter"
	_pt_buy("SUPER POTION", 8)
	if not await _pt_cross_north():
		return _pt_fail("Route3 -> Route4 (north)")
	if str(center_label) != "Route4":
		return _pt_fail("Route3 north led to %s, not Route4" % center_label)
	print("[playthrough] MILESTONE reached Route4")
	if not await _pt_reach_cerulean():
		return _pt_fail("Route4 -> CeruleanCity")
	print("[playthrough] MILESTONE reached CeruleanCity (lead L%d)" % int(player_party[0]["level"]))
	# Heal + register the Cerulean Center as the respawn (a real player heals here before the gym), so a
	# lost Misty fight whites out to next door and the persistent-player loop retries it (story 12) —
	# heal, re-stock, and go again — rather than failing the run on one bad fight.
	heal_party()
	respawn_map = "CeruleanPokecenter"
	for attempt in 4:
		_pt_buy("SUPER POTION", 12)                     # heal-war fuel (Cerulean Mart, earned ¥)
		if str(center_label) != "CeruleanCity" and not await _pt_warp_out("CeruleanCity"):
			return _pt_fail("return to Cerulean for Misty (on %s)" % center_label)
		if not await _pt_warp_out("CeruleanGym"):
			return _pt_fail("enter Cerulean Gym")
		if await _pt_talk_and_battle(Vector2i(4, 3), 1, "BEAT_MISTY") or has_event("BEAT_MISTY"):
			break                                       # won
		print("[playthrough] Misty attempt %d lost (whited out to %s) — heal + retry" % [attempt + 1, center_label])
		heal_party()
	if not has_event("BEAT_MISTY"):
		return _pt_fail("Cerulean Gym / Misty (all attempts)")
	print("[playthrough] MILESTONE beat MISTY — %s (lead L%d)" % [str(badges), int(player_party[0]["level"])])
	return true


## --- Bill stage (gh #76): Cerulean -> north-bridge rival ambush -> Route 24 (Nugget Bridge) -> Route 25
## -> Bill's Sea Cottage -> cell-separator -> S.S.TICKET. The ticket is the gate for the trashed-house
## shortcut to Route 5 (CeruleanCity.gd) and for the S.S. Anne later, so it comes before Surge. ---
func _pt_stage_bill() -> bool:
	if str(center_label) == "CeruleanGym" and not await _pt_warp_out("CeruleanCity"):
		return _pt_fail("leave Cerulean Gym")
	if has_event("GOT_SS_TICKET"):
		return true                                        # already done (resumed)
	heal_party()
	respawn_map = "CeruleanPokecenter"                     # white out back next door, not to Pallet
	# The Nugget Bridge gauntlet (rival ambush at CeruleanCity 20,6/21,6, then five trainers) and Route 25's
	# trainers can white the under-teamed party out; buy potions, heal, and retry from Cerulean if a leg is
	# lost (persistent player) — beaten trainers stay beaten, so a retry resumes rather than refights.
	# Mirrors _pt_cerulean_to_vermilion and the surge/rocktunnel loops (gh #131).
	for _attempt in 4:
		if has_event("GOT_SS_TICKET"):
			break
		if not await _pt_return_to_cerulean():             # home base (and where a whiteout lands us)
			return _pt_fail("back to Cerulean for Bill (on %s)" % center_label)
		_pt_buy("SUPER POTION", 12)
		heal_party()
		# North: the rival ambushes on the bridge (_pt_walk_to drives the cutscene + battle), up the Nugget
		# Bridge trainers to Route 24, then east across the rest to Route 25 and the Sea Cottage.
		if not await _pt_cross_north() or str(center_label) != "Route24":
			continue                                       # whited out crossing the bridge — retry
		print("[playthrough] MILESTONE beat Cerulean rival, reached Route24 (lead L%d)" % int(player_party[0]["level"]))
		if not await _pt_hop(3, "Route25"):                # east across the rest of the bridge trainers
			continue                                       # whited out on the east bridge trainers — retry
		print("[playthrough] MILESTONE reached Route25")
		if not await _pt_warp_out("BillsHouse"):           # the Sea Cottage at the east end
			continue                                       # whited out on Route 25 — retry
		print("[playthrough] MILESTONE reached Bill's Sea Cottage")
		if not await _pt_do_bill():
			return _pt_fail("Bill / cell-separator / S.S.TICKET (on %s)" % center_label)
	if not has_event("GOT_SS_TICKET"):
		return _pt_fail("Bill's Sea Cottage / S.S.TICKET (all attempts), on %s" % center_label)
	print("[playthrough] MILESTONE got S.S.TICKET — the trashed-house shortcut is open")
	return true


## Inside Bill's Sea Cottage: talk to Bill-as-a-POKéMON (6,5) to start the story, work the cell-
## separator PC (face up into 1,4), then talk to the restored Bill (4,4) for the S.S.TICKET. Each step
## is gated by its event so a resumed run skips finished ones. (scripts/BillsHouse.asm.)
func _pt_do_bill() -> bool:
	# _drive_bill (not _drive_until) advances the cell-separator cutscene's YES/NO + nickname prompts.
	if not has_event("BILL_SAID_USE_CELL_SEPARATOR"):
		await _pt_interact_from(Vector2i(6, 6), 1)         # stand below Bill-as-mon, face up
		await _drive_bill(func() -> bool: return has_event("BILL_SAID_USE_CELL_SEPARATOR") and not cutscene_active and modal == null)
	if not has_event("USED_CELL_SEPARATOR_ON_BILL"):
		await _pt_interact_from(Vector2i(1, 5), 1)         # stand below the cell-separator PC, face up
		await _drive_bill(func() -> bool: return has_event("USED_CELL_SEPARATOR_ON_BILL") and not cutscene_active and modal == null)
	if not has_event("GOT_SS_TICKET"):
		await _pt_interact_from(Vector2i(4, 5), 1)         # stand below the restored Bill, face up
		await _drive_bill(func() -> bool: return has_event("GOT_SS_TICKET") and not cutscene_active and modal == null)
	return has_event("GOT_SS_TICKET")


## Cerulean -> Vermilion on foot: (trashed-house shortcut) Route 5 -> Underground Path -> Route 6 ->
## Vermilion, bypassing the drink-gated Saffron gates. Needs GOT_SS_TICKET (the trashed-house guard is
## gone). The Route 5/6 trainer gauntlet can white the under-teamed party out, so buy potions, heal,
## register the Cerulean Center, and retry from home if a leg is lost (persistent-player). When
## `catch_cut` is set, pick up a Cut slave (an Oddish) from Route 6's grass before dropping to Vermilion
## — the `ssanne` stage needs one because the Squirtle line can't learn Cut. Returns true once in Vermilion.
func _pt_cerulean_to_vermilion(catch_cut := false) -> bool:
	for _attempt in 4:
		if str(center_label) == "VermilionCity":
			return true
		if not await _pt_return_to_cerulean():             # home base (and where a whiteout lands us)
			return false
		_pt_buy("SUPER POTION", 12)
		if catch_cut:
			_pt_buy("POKé BALL", 12)                        # headroom for the Oddish Cut-slave catch
		heal_party()
		respawn_map = "CeruleanPokecenter"
		if not await _pt_cerulean_to_route5() or str(center_label) != "Route5":
			continue                                       # whited out on the way — retry from Cerulean
		print("[playthrough] MILESTONE reached Route5")
		var legs_ok := true
		for leg in ["UndergroundPathRoute5", "UndergroundPathNorthSouth", "UndergroundPathRoute6", "Route6"]:
			if not await _pt_warp_out(leg):
				legs_ok = false
				break
		if not legs_ok:
			continue
		print("[playthrough] MILESTONE reached Route6 (Underground Path)")
		if catch_cut and not await _pt_ensure_cut_mon():
			return false                                   # no reachable Cut slave — a genuine dead-end
		if not await _pt_cross_south() or str(center_label) != "VermilionCity":
			continue                                       # whited out on Route 6 — retry
	return str(center_label) == "VermilionCity"


## --- S.S. Anne stage (gh #76): earn HM01 CUT and open the Vermilion Gym. From the `bill` checkpoint
## (S.S.TICKET in hand) cross Cerulean -> Vermilion (catching a Cut slave en route — the Squirtle line
## can't learn Cut), board the S.S. Anne for HM01 (rival ambush + seasick captain), teach CUT, and cut
## the tree gating the Vermilion Gym. Leaves the bot in Vermilion, ready for the `surge` stage. ---
func _pt_stage_ssanne() -> bool:
	if str(center_label) == "CeruleanGym" and not await _pt_warp_out("CeruleanCity"):
		return _pt_fail("leave Cerulean Gym")
	if has_event("GOT_HM01") and _mon_with_move("CUT") != "" and str(center_label) == "VermilionCity":
		return true                                        # already done (resumed)
	if not await _pt_cerulean_to_vermilion(true):          # catch a Cut slave (Oddish) on Route 6 en route
		return _pt_fail("Cerulean -> Vermilion (S.S. Anne), on %s" % center_label)
	print("[playthrough] MILESTONE reached Vermilion for the S.S. Anne (party %s)" % str(_pt_party_summary()))
	# Board the ship for HM01 (persistent-player retry: a lost rival battle whites out to the Vermilion
	# Center next door, from where we re-board — SS_ANNE_LEFT isn't set until we actually leave with HM01).
	heal_party()
	respawn_map = "VermilionPokecenter"
	for attempt in 4:
		if has_event("GOT_HM01"):
			break
		if str(center_label) != "VermilionCity" and not await _pt_warp_out("VermilionCity"):
			return _pt_fail("return to Vermilion for the S.S. Anne (on %s)" % center_label)
		_pt_buy("SUPER POTION", 8)
		heal_party()
		if await _pt_board_and_get_hm01():
			break
		print("[playthrough] S.S. Anne attempt %d incomplete (on %s) — heal + retry" % [attempt + 1, center_label])
		heal_party()
	if not has_event("GOT_HM01"):
		return _pt_fail("board S.S. Anne / rival / captain / HM01")
	if str(center_label) != "VermilionCity" and not await _pt_leave_ship():
		return _pt_fail("leave the S.S. Anne (on %s)" % center_label)
	# Teach CUT, then cut the tree gating the Vermilion Gym (proves the whole chain end-to-end).
	if not await _pt_teach_cut():
		return _pt_fail("teach CUT to a party mon")
	print("[playthrough] MILESTONE taught CUT to %s" % _mon_with_move("CUT"))
	if not await _pt_cut_vermilion_gym_tree():
		return _pt_fail("cut the Vermilion Gym tree")
	print("[playthrough] MILESTONE cut the gym tree — Vermilion Gym reachable (%s)" % str(_pt_party_summary()))
	return true


## Board the S.S. Anne (the Vermilion dock sailor waves the S.S.TICKET through), climb to the 2F deck
## where the rival ambushes (a required OPP_RIVAL2 battle en route to the captain's room), rub the
## seasick captain's back for HM01 CUT, then leave — the departure cutscene sails the ship and drops us
## back in Vermilion City. Idempotent: a resume that already has HM01 just heads back out.
## (scripts/VermilionCity.asm, SSAnne2F.asm, SSAnneCaptainsRoom.asm, VermilionDock.asm.)
func _pt_board_and_get_hm01() -> bool:
	if not has_event("GOT_HM01"):
		if not await _pt_warp_out("VermilionDock"):        # the sailor -> board_ss_anne cutscene -> the dock
			return false
		if str(center_label) != "VermilionDock":
			return false
		if not await _pt_warp_out("SSAnne1F", true):       # up the gangway (avoid the ship's other warps)
			return false
		if not await _pt_warp_out("SSAnne2F", true):       # stairs to the 2F deck
			return false
		# Walk to the captain's-room door (36,4); the rival trips the ambush at (36,8) on the way and
		# blocks the door until beaten — _pt_walk_to drives the battle + the rival's walk-away. avoid_warps
		# keeps the route off the neighbouring 3F/rooms warp mats (e.g. the SSAnne3F stairs at 2,12).
		if not await _pt_warp_out("SSAnneCaptainsRoom", true) or not has_event("BEAT_SS_ANNE_RIVAL"):
			return false                                   # lost the rival (whited out) — caller retries
		if not await _pt_interact_from(Vector2i(4, 3), 1):  # stand below the captain (4,2), face up
			return false
		await _drive_until(func() -> bool: return has_event("GOT_HM01") \
			and modal == null and not cutscene_active, 1000)
		if not has_event("GOT_HM01"):
			return false
		print("[playthrough] MILESTONE got HM01 (CUT) from the S.S. Anne captain")
	return await _pt_leave_ship()


## From anywhere aboard the S.S. Anne, warp back out to Vermilion City. Arriving on the dock with HM01
## (before SS_ANNE_LEFT) auto-fires the departure cutscene, which walks the player off the dock into the
## city — so we just drive frames until we land there. (scripts/VermilionDock.asm.)
func _pt_leave_ship() -> bool:
	for _i in 8:
		match str(center_label):
			"VermilionCity":
				return true
			"SSAnneCaptainsRoom":
				if not await _pt_warp_out("SSAnne2F", true): return false
			"SSAnne2F":
				if not await _pt_warp_out("SSAnne1F", true): return false
			"SSAnne1F":
				last_outside_map = "VermilionCity"          # the dock's LAST_MAP departure warp resolves here
				# Arriving on the dock fires ss_anne_departs, which sails the ship and walks us straight
				# off into Vermilion City — so _pt_warp_out often reports "failure" (center_label has
				# already moved past VermilionDock). Don't gate on its result; the next turn drives
				# whichever map we actually landed on (the dock, mid-departure, or the city).
				await _pt_warp_out("VermilionDock", true)
			"VermilionDock":
				await _drive_until(func() -> bool: return str(center_label) == "VermilionCity" \
					and modal == null and not cutscene_active, 1500)
			_:
				return false
	return str(center_label) == "VermilionCity"


## Guarantee a party mon that can learn HM01 CUT. The Squirtle line (the bot's starter) can't learn Cut
## in Gen 1, so a lone Wartortle dead-ends at the Vermilion Gym tree. If no current party mon is Cut-
## capable, catch one from the grass we're standing on — Route 5/6/24/25 all carry Oddish (catch rate
## 255, learns CUT), a cheap HM slave picked up on the way to Vermilion. (gh #76 user story 31.)
func _pt_ensure_cut_mon() -> bool:
	if _pt_party_can_cut():
		return true
	var target := ""
	for entry in wild_data.get("maps", {}).get(str(center_label), {}).get("grass", []):
		var sp := str(entry[1])
		if _can_learn(sp, "CUT"):
			target = sp
			break
	if target == "":
		return false                                       # no Cut-capable wild here — caller must reroute
	print("[playthrough] catching a CUT slave (%s) on %s" % [target, center_label])
	return await _pt_catch_species(target, 60)


## Teach HM01 CUT to the first Cut-capable party mon (ItemUseTMHM); the HM is not consumed. Called after
## the captain hands over HM01 — _pt_ensure_cut_mon has already put a learner (a low-level Oddish, so
## < 4 moves: a plain append, no forget prompt) in the party. Returns true once a mon knows CUT.
func _pt_teach_cut() -> bool:
	return await _pt_teach_hm("HM01", "CUT")


## Teach `move` to a party mon that can learn it, preferring one with a free move slot. When the only
## carrier is full — and by the Safari Zone the Squirtle line is exactly that: a L40 Blastoise with four
## moves, and the *only* mon in the party that can take SURF or STRENGTH — drive pokered's real LearnMove
## forget flow (`_overworld_learn`, gh #60) and give up the weakest non-HM move, which is the choice a
## player makes (gh #92). Idempotent — true if some mon already knows the move.
func _pt_teach_hm(hm: String, move: String) -> bool:
	if _mon_with_move(move) != "":
		return true
	if not player_bag.has(hm):
		return false
	var idx := -1
	for i in player_party.size():                       # a free slot needs no forget prompt at all
		if _can_learn(str(player_party[i]["species"]), move) and (player_party[i]["moves"] as Array).size() < 4:
			idx = i
			break
	if idx < 0:
		for i in player_party.size():
			if _can_learn(str(player_party[i]["species"]), move):
				idx = i
				break
	if idx < 0:
		return false
	var drop := _pt_worst_move(player_party[idx])
	if (player_party[idx]["moves"] as Array).size() >= 4 and drop < 0:
		return false                                    # four HMs: none of them can be deleted
	selected_item = hm
	_teach(idx)                                         # appends, or opens the forget flow (a coroutine)
	for _i in 1200:
		await get_tree().process_frame
		if _mon_with_move(move) != "" and modal == null and not cutscene_active:
			break
		if modal == menu:                               # YES/NO (2 rows), else "which move to forget"
			menu.chosen.emit(0 if menu.items.size() <= 2 else drop)
		elif textbox.active and textbox.visible:
			textbox.advance()
	modal = null
	textbox.visible = false
	return _mon_with_move(move) != ""


## The move a player gives up to make room. HMs can't be deleted (IsMoveHM), so they are skipped;
## -1 when every slot holds one. Ranking raw power alone is wrong: teaching SURF to a Blastoise that
## knows BUBBLE, WATER_GUN and BITE would give up BITE (60) and keep two weaker copies of the move it
## just learned. So give up a status move first, then a **redundant** attack — one whose type another,
## stronger move already covers — and only then the weakest thing left. That is the choice a player
## makes, and it is what keeps a coverage move on the team (gh #92).
func _pt_worst_move(mon: Dictionary) -> int:
	var moves: Array = mon["moves"]
	var worst := -1
	var worst_score := 1 << 30
	for i in moves.size():
		var key := str(moves[i]["move"])
		if key in HM_MOVES.values():
			continue
		var d: Dictionary = mon_moves.get(key, {})
		var power := int(d.get("power", 0))
		var mtype := str(d.get("type", ""))
		var score := power
		if power == 0:
			score = -1000                                  # a status move: the first thing to go
		else:
			for j in moves.size():                         # HMs count here — SURF outranks WATER_GUN
				var o: Dictionary = mon_moves.get(str(moves[j]["move"]), {})
				if j != i and str(o.get("type", "")) == mtype and int(o.get("power", 0)) > power:
					score = power - 500                    # a weaker copy of something we already have
					break
		if score < worst_score:
			worst_score = score
			worst = i
	return worst


## Use a field move the way a player does: open the party submenu of the mon that knows it
## (`_open_mon_menu` → FIELD_MOVE_MON_MENU) and pick the move, so the badge gate and the
## "It can't be used here." refusal both run for real. False if nobody knows it.
## `settle` waits for the move to finish; FLY leaves a second menu open, so it passes false.
func _pt_use_field_move(move: String, settle := true) -> bool:
	var idx := -1
	for i in player_party.size():
		for mv in player_party[i]["moves"]:
			if str(mv["move"]) == move:
				idx = i
				break
		if idx >= 0:
			break
	if idx < 0:
		return false
	_open_mon_menu(idx)
	var opt: int = _mon_menu_opts.find(move)
	if opt < 0:
		modal = null
		return false                                  # not a field move (no FIELD_MOVE_BADGE entry)
	menu.chosen.emit(opt)
	if settle:
		await _drive_until(func() -> bool: return modal == null and not cutscene_active, 600)
	else:
		await get_tree().process_frame                # let the handler open whatever comes next
	return true


## FLY to a town we have already visited. The party field-move submenu opens the Town Map picker,
## filtered by `visited_fly`, and picking one runs the fly transition. FLY is
## Thunder-Badge gated and refuses indoors, so surface first.
## Press one action AT a modal and let the real input path consume it (Player._process
## dispatches to `modal.handle_input()` each frame). Driving a modal by calling its
## handle_input() directly on top of a press double-steps it — gh #27.
func _pt_press_modal(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame


func _pt_fly_to(town: String) -> bool:
	if str(center_label) == town:
		return true
	if _mon_with_move("FLY") == "" or not visited_fly.has(town):
		return false
	if center_tileset not in OUTSIDE_TILESETS and not await _pt_warp_out(str(last_outside_map)):
		return false                                  # "Can't use that here." indoors
	if not await _pt_use_field_move("FLY", false):
		return false
	await _drive_until(func() -> bool: return modal == townmap and townmap.is_fly_mode(), 300)
	if modal != townmap or not townmap.is_fly_mode():
		return false
	if not townmap.fly_dests.any(func(dest: Dictionary) -> bool: return str(dest["label"]) == town):
		Input.action_press("ui_cancel")
		townmap.handle_input()
		Input.action_release("ui_cancel")
		return false
	# gh #27: step the FLY cursor to `town`, BOUNDED by the cycle length. Two traps, and the
	# run that found them burned 54 CPU-minutes in total silence:
	#  * the cursor moved TWICE per press. Player._process already dispatches every frame to
	#    `game.modal.handle_input()`, so calling `townmap.handle_input()` ourselves after a
	#    press double-stepped `idx` — the cycle then only ever visited same-parity entries and
	#    a town on the other parity (VIRIDIAN, from Cinnabar) was unreachable forever. Press
	#    the action and let the REAL input path consume it, exactly like a player.
	#  * the loop must end. It used to be `while label != town` with no cap, so a cursor that
	#    can't reach the town spins forever — no log line, no timeout, just a headless process
	#    pinning a core. Flying home to Pallet hid both: Pallet is the cursor's own start, so
	#    the loop body never ran.
	var hops := 0
	while townmap.current_fly_label() != town:
		if hops > townmap.fly_dests.size():
			print("[playthrough] FLY: cursor never reached %s (stuck on '%s' after %d hops)" % [
				town, townmap.current_fly_label(), hops])
			await _pt_press_modal("ui_cancel")
			return false
		await _pt_press_modal("ui_up")
		hops += 1
	await _pt_press_modal("ui_accept")
	await _drive_until(func() -> bool: return str(center_label) == town and modal == null \
		and not cutscene_active, 1200)
	return str(center_label) == town


## Mount the water: face a water cell from the shore and SURF onto it. Gated on the SOULBADGE and on a
## party mon knowing SURF — both come from the `koga` / `safari` stages. Returns true once afloat.
func _pt_surf_on(face_dir: int) -> bool:
	if surfing:
		return true
	player.facing = face_dir
	if not _is_water(player.front_cell()):
		return false                                  # not actually looking at water
	if not await _pt_use_field_move("SURF"):
		return false
	await _drive_until(func() -> bool: return surfing and modal == null and not cutscene_active, 600)
	return surfing


## Cut the tree at Vermilion (15,18) — the sole channel from the north plaza into the walled-off gym
## plaza (flood-fill verified). Stand north of it at (15,17), face DOWN, and CUT (needs a CUT-knowing mon
## + the CASCADEBADGE, both in hand by now). The tree regrows on every Vermilion reload, so this is
## idempotent and re-run per gym attempt. Returns true once (15,18) is walkable.
func _pt_cut_vermilion_gym_tree() -> bool:
	if str(center_label) != "VermilionCity":
		return false
	var tree := Vector2i(15, 18)
	if is_walkable(tree):
		return true                                        # already cut this visit
	# Cut from whichever side we're on, like _pt_cut_celadon_gym_tree: (15,17) north (city, face DOWN)
	# or (15,19) south (gym plaza, face UP). The plaza-side cut is what un-traps a bot that walked out
	# of the gym after a reload regrew the tree — the `surge` checkpoint ends inside the gym (gh #76).
	for side in [[Vector2i(15, 17), 0], [Vector2i(15, 19), 1]]:
		var stand: Vector2i = side[0]
		if not _pt_plan(player.cell, stand).is_empty() or player.cell == stand:
			if not await _pt_walk_to(stand) or player.cell != stand:
				continue
			player.facing = int(side[1])                   # face the tree
			_try_cut(player.front_cell())
			modal = null
			textbox.visible = false
			if is_walkable(tree):
				return true
	return is_walkable(tree)


## --- Lt. Surge stage (gh #76): Cerulean -> (trashed-house shortcut) Route 5 -> Underground Path ->
## Route 6 -> Vermilion -> Diglett's Cave -> trash-can puzzle -> LT.SURGE. Electric hits Wartortle 2x,
## so the bot fetches a Diglett (Ground — immune to electric + Thunder Wave) and the battle policy
## proactively switches to it. Needs GOT_SS_TICKET (from the `bill` stage) to clear the trashed-house
## guard, and HM01 CUT + a Cut-capable mon (from the `ssanne` stage) to clear the tree gating the gym. ---
func _pt_stage_surge() -> bool:
	if not await _pt_cerulean_to_vermilion():
		return _pt_fail("Cerulean -> Vermilion (all attempts), on %s" % center_label)
	print("[playthrough] MILESTONE reached VermilionCity")
	# Lt. Surge is electric (2x on Wartortle + Thunder Wave paralysis), so fetch a DIGLETT — a Ground
	# mon immune to both — from Diglett's Cave, east via Route 11. Catch one L19+ so it already knows DIG
	# (2x on electric); the battle policy proactively switches to it. (Sandshrew is Blue-exclusive.)
	if not _pt_has_species("diglett"):
		_pt_buy("POKé BALL", 8)
		if not await _pt_hop(3, "Route11"):
			return _pt_fail("Vermilion -> Route11 (east)")
		for leg in ["DiglettsCaveRoute11", "DiglettsCave"]:
			if not await _pt_warp_out(leg):
				return _pt_fail("into Diglett's Cave (%s), on %s" % [leg, center_label])
		if not await _pt_catch_species("diglett", 50, 19):
			return _pt_fail("catch a DIGLETT (L19+) in Diglett's Cave")
		print("[playthrough] MILESTONE Surge coverage: %s" % str(_pt_party_summary()))
		for leg in ["DiglettsCaveRoute11", "Route11"]:
			if not await _pt_warp_out(leg):
				return _pt_fail("out of Diglett's Cave (%s), on %s" % [leg, center_label])
		if not await _pt_hop(2, "VermilionCity"):
			return _pt_fail("Route11 -> Vermilion (west)")
	# Heal + register the Vermilion Center as the respawn, then the gym (trash puzzle -> Surge), with
	# the persistent-player retry.
	heal_party()
	respawn_map = "VermilionPokecenter"
	for attempt in 4:
		_pt_buy("SUPER POTION", 12)
		if str(center_label) != "VermilionCity" and not await _pt_warp_out("VermilionCity"):
			return _pt_fail("return to Vermilion for Surge (on %s)" % center_label)
		# The gym-gating tree regrows whenever Vermilion reloads (a fresh whiteout re-entry), so re-cut
		# it each attempt before heading for the door (needs the `ssanne` stage's HM01 + Cut-capable mon).
		if not await _pt_cut_vermilion_gym_tree():
			return _pt_fail("cut the Vermilion Gym tree")
		if not await _pt_warp_out("VermilionGym"):
			return _pt_fail("enter Vermilion Gym")
		if not await _pt_solve_trash():
			return _pt_fail("Vermilion trash-can puzzle")
		if await _pt_talk_and_battle(Vector2i(5, 2), 1, "BEAT_LT_SURGE") or has_event("BEAT_LT_SURGE"):
			break
		print("[playthrough] Surge attempt %d lost (whited out to %s) — heal + retry" % [attempt + 1, center_label])
		heal_party()
	if not has_event("BEAT_LT_SURGE"):
		return _pt_fail("Vermilion Gym / Lt. Surge (all attempts)")
	print("[playthrough] MILESTONE beat LT.SURGE — %s (lead L%d)" % [str(badges), int(player_party[0]["level"])])
	return true


## --- Rock Tunnel stage (gh #76): with THUNDERBADGE in hand, push east to Lavender Town. From Vermilion:
## back up to Cerulean (the Route 5/6 Underground Path), east across Route 9/10's trainer gauntlet to the
## Rock Tunnel, through the dark 1F/B1F ladder maze, out onto Route 10's south half, then south into
## Lavender. No FLASH is needed — the darkness is a render-only overlay (_update_darkness), so the bot
## navigates the tunnel by cell like any other dungeon. Leaves the bot in Lavender for the next stage.
## Route 9 is entered from Cerulean into a small grassy pocket walled off from the route by a CUT tree
## (block 0x35 at (5,8)); cutting it (HM01, earned in the `ssanne` stage) opens the way east — the same
## Cut gate as the Vermilion Gym. ---
func _pt_stage_rocktunnel() -> bool:
	if str(center_label) == "VermilionGym" and not await _pt_warp_out("VermilionCity"):
		return _pt_fail("leave Vermilion Gym")
	if str(center_label) == "LavenderTown":
		return true                                        # already done (resumed)
	# The `surge` stage ends inside the gym, and the city reload regrew the plaza's CUT tree — cut
	# back out before heading north, or every edge of the city is unreachable (gh #76 seam).
	if str(center_label) == "VermilionCity" and not await _pt_cut_vermilion_gym_tree():
		return _pt_fail("cut back out of the Vermilion Gym plaza")
	if not await _pt_vermilion_to_cerulean():
		return _pt_fail("Vermilion -> Cerulean, on %s" % center_label)
	print("[playthrough] MILESTONE back in Cerulean, heading east for Rock Tunnel")
	# Persistent player (ADR-011): the tunnel is ~7 sight-trainers deep and a whiteout anywhere on
	# Route 9/10 or inside drops us at the Cerulean Center — heal, restock, and march east again
	# (beaten trainers stay beaten, so a retry resumes rather than refights the gauntlet).
	for attempt in 3:
		if str(center_label) != "CeruleanCity" and not await _pt_return_to_cerulean():
			return _pt_fail("back to Cerulean after a whiteout (on %s)" % center_label)
		heal_party()
		respawn_map = "CeruleanPokecenter"
		_pt_buy("SUPER POTION", 12)
		# East across Route 9 then Route 10 to the Rock Tunnel's north entrance (Route 10 is split by
		# the mountain: the Route 9 side reaches only the north entrance, never Lavender). Cerulean's own
		# one-way split matters on a retry: a whiteout puts us out of the Pokécenter on the gym side,
		# which cannot reach the east edge — _pt_cerulean_to_route9 crosses via the trashed house.
		if not await _pt_cerulean_to_route9() or not await _pt_cut_route9_tree() \
				or not await _pt_hop(3, "Route10"):
			print("[playthrough] Rock Tunnel approach attempt %d ended on %s — heal + retry" % [
				attempt + 1, center_label])
			continue
		print("[playthrough] MILESTONE reached Route10 (Rock Tunnel approach)")
		if await _pt_traverse_rock_tunnel() and await _pt_cross_south() \
				and str(center_label) == "LavenderTown":
			break
		print("[playthrough] Rock Tunnel attempt %d ended on %s @%s — heal + retry" % [
			attempt + 1, center_label, str(player.cell)])
	if str(center_label) != "LavenderTown":
		return _pt_fail("Rock Tunnel -> Lavender (all attempts), on %s @%s" % [
			center_label, str(player.cell)])
	print("[playthrough] MILESTONE reached Lavender Town (lead L%d)" % int(player_party[0]["level"]))
	return true


## Vermilion -> Cerulean on foot — the reverse of _pt_cerulean_to_vermilion: north to Route 6, through the
## Route 5/6 Underground Path (bypassing the drink-gated Saffron gates), out onto Route 5, then north into
## Cerulean. Arriving via Route 5 lands in Cerulean's SOUTH region, which — unlike the walled-off gym/
## Route-4 region — reaches the east exit to Route 9 directly (rtprobe-verified), so no trashed-house
## shortcut is needed this way. Heals + retries per attempt (persistent player). Returns true in Cerulean.
func _pt_vermilion_to_cerulean() -> bool:
	for _attempt in 3:
		if str(center_label) == "CeruleanCity":
			return true
		if str(center_label) != "VermilionCity" and not await _pt_warp_out("VermilionCity"):
			return false                                   # whited out somewhere unexpected
		heal_party()
		respawn_map = "VermilionPokecenter"
		if not await _pt_cross_north() or str(center_label) != "Route6":
			continue                                       # Vermilion -> Route 6 (north)
		var legs_ok := true
		for leg in ["UndergroundPathRoute6", "UndergroundPathNorthSouth", "UndergroundPathRoute5", "Route5"]:
			if not await _pt_warp_out(leg):
				legs_ok = false
				break
		if not legs_ok:
			continue
		if not await _pt_cross_north() or str(center_label) != "CeruleanCity":
			continue                                       # Route 5 -> Cerulean (south region)
	return str(center_label) == "CeruleanCity"


## Cut the tree gating Cerulean -> Route 9. Entering Route 9 from Cerulean drops you in a small grassy
## pocket (~0,9) walled off from the route to the east by a CUT tree — block 0x35, whose (5,8) quadrant
## is CUT_TREE_TILE; cutting it (0x35 -> 0x4C) makes (5,8) walkable and joins the pocket to the route
## (verified against pokered's blockset). Stand west of it at (4,8), face RIGHT, and CUT (needs a CUT mon
## + CASCADEBADGE, both in hand post-`ssanne`). Idempotent: the tree regrows on each Route 9 reload, so
## this re-cuts per entry. Returns true once (5,8) is walkable.
func _pt_cut_route9_tree() -> bool:
	if str(center_label) != "Route9":
		return false
	var tree := Vector2i(5, 8)
	if is_walkable(tree):
		return true                                        # already cut this visit
	if not await _pt_walk_to(Vector2i(4, 8)):
		return false                                       # stand just west of the tree
	player.facing = 3                                      # RIGHT -> front cell (5,8) is the tree
	_try_cut(player.front_cell())
	modal = null
	textbox.visible = false
	return is_walkable(tree)


## Cross the Rock Tunnel from the Route 10 north entrance to the south exit. Its `cavern` elevation ledges
## (`TilePairCollisions`, gh #105) fracture both floors into ladder-linked pockets you can see across but
## not step, so the route is a five-leg wind mapped with `--tpprobe` — 1F pockets {north (15,3),(37,3)},
## {mid (5,3),(17,11)}, {south (15,33),(37,17)}; B1F pockets {(33,25),(27,3)}, {(23,11),(3,3)}:
##   1F(15,3)→(37,3) ↓ B1F(33,25)→(27,3) ↓ 1F(5,3)→(17,11) ↓ B1F(23,11)→(3,3) ↓ 1F(37,17)→(15,33) →Route 10.
## Each leg stays inside one pocket; avoid_warps keeps the walk off the *other* ladders sharing a floor.
## Trainers dot the corridors; _pt_walk_dungeon fights any that sight us and routes around the rest.
## Returns true once back on Route 10 (south).
func _pt_traverse_rock_tunnel() -> bool:
	# NB: failures here return false without _pt_fail's terminal "FAIL(" — the rocktunnel stage retries this
	# whole traversal (a whiteout inside the tunnel is expected and recovered), so a caught attempt must not
	# masquerade as a run-ending failure in the log (would trip validate_gate on an otherwise-green run).
	if not await _pt_warp_out("RockTunnel1F"):
		print("[playthrough] rocktunnel: could not enter RockTunnel1F from %s @%s" % [center_label, str(player.cell)])
		return false
	var route := [["RockTunnel1F", Vector2i(37, 3)], ["RockTunnelB1F", Vector2i(27, 3)],
		["RockTunnel1F", Vector2i(17, 11)], ["RockTunnelB1F", Vector2i(3, 3)],
		["RockTunnel1F", Vector2i(15, 33)]]
	for leg in route:
		var want: String = leg[0]
		var target: Vector2i = leg[1]
		if str(center_label) != want:
			print("[playthrough] rocktunnel: expected %s, on %s @%s (retrying)" % [want, center_label, str(player.cell)])
			return false
		var before := str(center_label)
		if not await _pt_walk_dungeon(target, 3000, false, true):
			return false
		if str(center_label) == before:                    # reached the tile but the warp didn't fire — nudge
			await _pt_step(0)
			await _pt_walk_dungeon(target, 3000, false, true)
		await _drive_until(func() -> bool: return str(center_label) != before, 400)
	return str(center_label) == "Route10"


## --- Erika stage (gh #76): from the `rocktunnel` checkpoint (Lavender) push to Celadon and take the
## RAINBOWBADGE. West to Route 8, through the Route 7-8 Underground Path (bypassing the drink-gated
## Saffron gates), out onto Route 7, west into Celadon; cut the tree gating the gym (block 0x32 @ (35,32),
## the sole link from the city to the walled gym plaza); then beat Erika. She's grass/poison (bad for the
## water/ground team), so catch a GROWLITHE on Route 7 (Fire — resists her grass, hits it 2x, knows EMBER
## at L18+): the battle policy auto-switches to it (verified by `--erikacombat --bench growlithe:21`),
## like Diglett vs Surge, with the persistent-player whiteout-retry. Inside the gym, a GYM-tileset CUT
## tree at (5,7) walls Erika off from the entrance — cut it (_pt_cut_gym_interior_tree) to reach her.
## Two overworld Cut gates + a gym Cut gate + the fight, all on the way to the RAINBOWBADGE. ---
func _pt_stage_erika() -> bool:
	if has_event("BEAT_ERIKA"):
		return true                                        # already done (resumed)
	if not await _pt_lavender_to_celadon(0, true):         # catch a Growlithe on Route 7 — Erika Fire coverage
		return _pt_fail("Lavender -> Celadon, on %s" % center_label)
	print("[playthrough] MILESTONE reached Celadon (party %s)" % str(_pt_party_summary()))
	heal_party()
	respawn_map = "CeladonPokecenter"
	for attempt in 4:
		_pt_buy("SUPER POTION", 16)
		if str(center_label) != "CeladonCity" and not await _pt_warp_out("CeladonCity"):
			return _pt_fail("return to Celadon for Erika (on %s)" % center_label)
		# The gym plaza is walled off from the city; a single CUT tree links them, and it regrows on each
		# Celadon reload (fresh whiteout re-entry), so re-cut before every attempt.
		if not await _pt_cut_celadon_gym_tree():
			return _pt_fail("cut the Celadon Gym (city) tree")
		if not await _pt_warp_out("CeladonGym"):
			return _pt_fail("enter Celadon Gym")
		# The garden maze walls Erika off from the door; a GYM cut tree at (5,7) is the only link (regrows
		# on reload, so re-cut each attempt) — see _pt_cut_gym_interior_tree.
		if not await _pt_cut_gym_interior_tree():
			return _pt_fail("cut the Celadon Gym (interior) tree to Erika")
		if await _pt_talk_and_battle(Vector2i(4, 4), 1, "BEAT_ERIKA") or has_event("BEAT_ERIKA"):  # Erika @ (4,3)
			break
		print("[playthrough] Erika attempt %d lost (whited out to %s) — heal + retry" % [attempt + 1, center_label])
		heal_party()
	if not has_event("BEAT_ERIKA"):
		return _pt_fail("Celadon Gym / Erika (all attempts)")
	print("[playthrough] MILESTONE beat ERIKA — %s (lead L%d)" % [str(badges), int(player_party[0]["level"])])
	return true


## Lavender -> Celadon on foot: west to Route 8, through the Route 7-8 Underground Path (bypassing the
## drink-gated Saffron gates), out onto Route 7, then west into Celadon. On Route 7's grass (Route 8's
## patch is fenced off from the path, and Celadon has no grass): if `catch_fire`, catch a GROWLITHE — the
## Erika answer (Fire resists her grass and hits it 2x; knows EMBER at L18+; the battle policy auto-
## switches to it, just like Diglett vs Surge); if `grind_to` > 0, grind the lead to that level. Both use
## a teleport-onto-grass, so restore the exit spot before crossing. Returns true in Celadon.
func _pt_lavender_to_celadon(grind_to := 0, catch_fire := false, catch_fly := false) -> bool:
	if str(center_label) == "CeladonCity":
		return true
	heal_party()
	respawn_map = "LavenderPokecenter"
	if not await _pt_hop(2, "Route8"):                     # Lavender -> Route 8 (west)
		return false
	print("[playthrough] MILESTONE reached Route8")
	for leg in ["UndergroundPathRoute8", "UndergroundPathWestEast", "UndergroundPathRoute7Copy", "Route7"]:
		if not await _pt_warp_out(leg):
			return false
	print("[playthrough] MILESTONE reached Route7 (Underground Path)")
	var arrival: Vector2i = player.cell                    # the Underground Path exit spot (crossing-friendly)
	if catch_fire and not _pt_has_species("growlithe"):    # Fire coverage for Erika (Route 7 Growlithe, L18-20)
		_pt_buy("POKé BALL", 12)
		if not await _pt_catch_species("growlithe", 80, 18):
			return _pt_fail("catch a GROWLITHE (Erika Fire coverage) on Route 7")
		print("[playthrough] MILESTONE caught GROWLITHE for Erika (%s)" % str(_pt_party_summary()))
	# The party is all coverage/HM-slave mons — none of them can learn FLY, which the `blaine` stage needs
	# to reach Cinnabar. Route 7 has PIDGEY (a FLY learner) in the same grass we grind, reachable from the
	# Underground Path exit. Catch it here, well before HM02 (gh #104 — the isolated --flytest handed the
	# stage a bird, so it never saw this; same disease as #94).
	if catch_fly and not _pt_party_can_learn("FLY") and not _pt_has_species("pidgey"):
		_pt_buy("POKé BALL", 12)
		if not await _pt_catch_species("pidgey", 80):
			return _pt_fail("catch a PIDGEY (FLY carrier) on Route 7")
		print("[playthrough] MILESTONE caught PIDGEY (FLY carrier) on Route 7 (%s)" % str(_pt_party_summary()))
	if grind_to > 0 and not player_party.is_empty() and int(player_party[0]["level"]) < grind_to:
		await _pt_grind_to(grind_to, 900)                  # Route 7 grass — extra levels if asked
	if player.cell != arrival:                             # catch/grind teleport onto grass; return to the exit
		player.place(arrival)
		warp_armed = _warp_at(arrival) == null             # re-arm warp state (place leaves it stale)
	if not await _pt_hop(2, "CeladonCity"):                # Route 7 -> Celadon (west)
		return false
	return str(center_label) == "CeladonCity"


## Cut the tree gating the Celadon Gym. The gym sits in a plaza walled off from the city; the only link
## is a CUT tree at (35,32) (block 0x32, in the fence between the two — verified against pokered's blocks:
## cutting it 0x32->0x6D makes (35,32) walkable and joins the city to the gym-warp region). Cut it from
## whichever side we're on — (35,31) north (city, face DOWN) or (35,33) south (gym plaza, face UP): a lost
## gym attempt drops us back in the plaza with the tree regrown, so the plaza-side cut is what un-traps us.
## Needs a CUT mon + CASCADEBADGE (in hand). Idempotent / re-cut per visit. Returns true once (35,32) walks.
func _pt_cut_celadon_gym_tree() -> bool:
	if str(center_label) != "CeladonCity":
		return false
	var tree := Vector2i(35, 32)
	if is_walkable(tree):
		return true                                        # already cut this visit
	for side in [[Vector2i(35, 31), 0], [Vector2i(35, 33), 1]]:   # city-side (DOWN) then plaza-side (UP)
		var stand: Vector2i = side[0]
		if not _pt_plan(player.cell, stand).is_empty() or player.cell == stand:
			if not await _pt_walk_to(stand) or player.cell != stand:
				continue
			player.facing = int(side[1])                   # face the tree
			_try_cut(player.front_cell())
			modal = null
			textbox.visible = false
			if is_walkable(tree):
				return true
	return is_walkable(tree)


## Inside the Celadon Gym, cut the tree gating Erika's platform. The garden is a maze walled off from the
## leader; a single GYM-tileset cut tree at (5,7) (feet tile 0x50, block 0x3F->0x35) is the sole link from
## the maze up to Erika's room (flood-verified). Needs a CUT mon + CASCADEBADGE. Regrows on reload, so
## re-cut per entry — and cut from whichever side we stand on, since the tree splits the gym in two:
## (5,8) below it (the maze, face UP) on the way in, (5,6) above it (Erika's platform, face DOWN) on the
## way out. That second side is not optional: the `erika` checkpoint ends standing on the platform, and
## loading it regrows the tree into a 16-cell pocket holding no door at all (gh #76 seam).
## (Bulbapedia: the Celadon Gym requires CUT to progress; pokered engine/overworld/cut.asm cut tile 0x50.)
func _pt_cut_gym_interior_tree() -> bool:
	if str(center_label) != "CeladonGym":
		return false
	var tree := Vector2i(5, 7)
	if is_walkable(tree):
		return true                                        # already cut this visit
	var sides := [[Vector2i(5, 8), 1], [Vector2i(5, 6), 0]]   # [stand, facing] south-in, then north-out
	if player.cell.y < tree.y:
		sides.reverse()                                    # already on Erika's platform: cut our way out
	for side in sides:
		var stand: Vector2i = side[0]
		if not await _pt_walk_dungeon(stand) or player.cell != stand:
			continue                                       # the other side of the tree — try the far stand
		player.facing = int(side[1])                       # face the tree
		_try_cut(player.front_cell())
		modal = null
		textbox.visible = false
		if is_walkable(tree):
			return true
	return is_walkable(tree)


## --- Silph Scope stage (gh #76): from Celadon, flip the Game Corner poster to reveal the Team Rocket
## Hideout, descend B1F -> B4F (spin-aware through the B2F/B3F arrow mazes), take the LIFT KEY, ride
## the elevator into Giovanni's wing, beat him for the SILPH SCOPE, and climb back out to Celadon.
## Verified end-to-end by `--silphscopetest`; the legs have fast tests of their own (`--silphdescent`,
## `--silphscopetest --b4f`). See _pt_hideout_b4f for why B4F needs the elevator. ---
func _pt_stage_silphscope() -> bool:
	if player_bag.has("SILPH SCOPE"):                      # already done (resumed) — but a run resumed
		if str(center_label).begins_with("RocketHideout"): # inside the hideout still has to climb out
			return await _pt_hideout_exit()
		return true
	# The `erika` checkpoint ends on Erika's platform, behind the gym's interior CUT tree — which the
	# map load regrew, sealing the bot into a doorless pocket. Cut back off it first (gh #76 seam).
	if str(center_label) == "CeladonGym" and not await _pt_cut_gym_interior_tree():
		return _pt_fail("cut back off Erika's platform")
	if str(center_label) != "CeladonCity" and not await _pt_warp_out("CeladonCity"):
		return _pt_fail("reach Celadon for the hideout (on %s)" % center_label)
	if not await _pt_warp_out("GameCorner"):
		# The `erika` stage ends inside the gym; walking out lands in the walled gym plaza with the
		# CUT tree regrown, so no city door is reachable — cut back out and retry (gh #76 seam).
		if not await _pt_cut_celadon_gym_tree() or not await _pt_warp_out("GameCorner"):
			return _pt_fail("enter the Celadon Game Corner")
	if not has_event("FOUND_ROCKET_HIDEOUT"):              # flip the poster switch (9,4)
		# A ROCKET (OPP_ROCKET 7) stands on (9,5) — the only walkable cell the poster can be read
		# from — and STAYs facing UP into it, so he never engages on sight. Talk to him, beat him,
		# and he walks off for good (GameCorner.gd on_battle_end, gh #89). Heal first: he is a real
		# fight and the run arrives here straight off Erika.
		heal_party()
		if not defeated_trainers.has("GameCorner:9,5") and not await _pt_fight_trainer(Vector2i(9, 5)):
			return _pt_fail("beat the ROCKET standing on the Game Corner poster")
		await _pt_interact_from(Vector2i(9, 5), 1)
		await _drive_until(func() -> bool: return has_event("FOUND_ROCKET_HIDEOUT") and modal == null and not cutscene_active, 300)
	if not has_event("FOUND_ROCKET_HIDEOUT"):
		return _pt_fail("flip the Rocket Hideout poster")
	print("[playthrough] MILESTONE revealed the Team Rocket Hideout")
	heal_party()
	respawn_map = "CeladonPokecenter"
	if not await _pt_warp_out("RocketHideoutB1F"):
		return _pt_fail("descend into the hideout")
	if not await _pt_hideout_descend():
		return _pt_fail("hideout descent B1F->B4F (on %s)" % center_label)
	print("[playthrough] MILESTONE descended to Rocket Hideout B4F")
	if not await _pt_hideout_b4f():
		return _pt_fail("hideout B4F Giovanni / SILPH SCOPE (on %s)" % center_label)
	print("[playthrough] MILESTONE got the SILPH SCOPE — %s" % str(_pt_party_summary()))
	# Walk back out. Giovanni's wing touches nothing but the elevator, so if the climb out were broken
	# the scope would be a dead end — the stage only counts once we're standing in Celadon again.
	if not await _pt_hideout_exit():
		return _pt_fail("climb out of the Rocket Hideout (on %s)" % center_label)
	print("[playthrough] MILESTONE left the Rocket Hideout -> Celadon")
	return true


## Out of Giovanni's B4F wing and back to Celadon. The wing's only exit is the elevator, and the
## panel's B1F stop lands in a 12-cell closet sealed behind B1F's own guard door (--rtprobe), so the
## ride goes to B2F — which reaches the B1F up-stairs (27,8) — then B1F (23,2) -> Game Corner (21,2).
func _pt_hideout_exit() -> bool:
	if str(center_label) == "RocketHideoutB4F":
		if not await _pt_walk_dungeon(Vector2i(24, 15), 4000):       # the wing's elevator door
			return false
		if not await _pt_ride_elevator("RocketHideoutElevator", _PT_LIFT_B2F, "RocketHideoutB2F"):
			return false
	if str(center_label) == "RocketHideoutB2F":
		if not await _pt_walk_dungeon(Vector2i(27, 8), 4000, true):  # up-stairs, through the spin maze
			return false
		await _drive_until(func() -> bool: return str(center_label) != "RocketHideoutB2F", 400)
	if str(center_label) != "RocketHideoutB1F" or not await _pt_warp_out("GameCorner"):
		return false
	return await _pt_warp_out("CeladonCity")


## --- POKé FLUTE stage (gh #76): with the SILPH SCOPE in hand, cross back to Lavender, climb the
## Pokémon Tower (the rival ambushes on 2F, channelers engage on sight the whole way up), lay the
## restless MAROWAK to rest on 6F, clear the three Rockets holding Mr. Fuji on 7F — he sends you to his
## house — and take the POKé FLUTE. The flute is what wakes the SNORLAX blocking the roads south. ---
func _pt_stage_pokeflute() -> bool:
	if player_bag.has("POKé FLUTE"):
		return true                                        # already done (resumed)
	if not player_bag.has("SILPH SCOPE"):
		return _pt_fail("the POKé FLUTE stage needs the SILPH SCOPE (Rocket Hideout)")
	if not await _pt_celadon_to_lavender():
		return _pt_fail("Celadon -> Lavender (on %s)" % center_label)
	print("[playthrough] MILESTONE reached Lavender Town")
	heal_party()
	respawn_map = "LavenderPokecenter"
	# Persistent player (ADR-011: a lost battle is never a run failure). A channeler, the rival, or the
	# MAROWAK can white us out to the Center — heal and climb again. Beaten trainers and the ghost's
	# event persist, so a retry picks up where the last one died rather than refighting the tower.
	for attempt in 3:
		_pt_buy("SUPER POTION", 16)                        # the last attempt spent them (gh #94)
		if has_event("RESCUED_MR_FUJI") or await _pt_climb_tower():
			break
		print("[playthrough] Pokémon Tower attempt %d failed (on %s) — heal + retry" % [attempt + 1, center_label])
		heal_party()
		if str(center_label) != "LavenderTown" and not await _pt_warp_out("LavenderTown"):
			return _pt_fail("back to Lavender after a whiteout (on %s)" % center_label)
	if not has_event("RESCUED_MR_FUJI"):
		return _pt_fail("Pokémon Tower climb (on %s @%s)" % [center_label, str(player.cell)])
	print("[playthrough] MILESTONE rescued MR.FUJI — %s" % str(_pt_party_summary()))
	# The rescue warps us into his house, but a resumed run can start anywhere; he's only shown at home
	# once RESCUED_MR_FUJI is set (MrFujisHouse.gd).
	if str(center_label) != "MrFujisHouse":
		if str(center_label) != "LavenderTown" and not await _pt_warp_out("LavenderTown"):
			return _pt_fail("reach Lavender for MR.FUJI's house (on %s)" % center_label)
		if not await _pt_warp_out("MrFujisHouse"):
			return _pt_fail("enter MR.FUJI's house")
	if not await _pt_talk_npc(Vector2i(3, 1), func() -> bool: return player_bag.has("POKé FLUTE")):
		return _pt_fail("take the POKé FLUTE from MR.FUJI (on %s)" % center_label)
	print("[playthrough] MILESTONE got the POKé FLUTE")
	return true


## Celadon -> Lavender on foot: east onto Route 7, through the Route 7-8 Underground Path (which ducks
## under the drink-gated Saffron gates), out onto Route 8, then east into Lavender. The mirror of
## _pt_lavender_to_celadon.
func _pt_celadon_to_lavender() -> bool:
	if str(center_label) == "LavenderTown":
		return true
	if str(center_label) != "CeladonCity" and not await _pt_warp_out("CeladonCity"):
		return false
	heal_party()
	respawn_map = "CeladonPokecenter"
	if not await _pt_hop(3, "Route7"):                     # Celadon -> Route 7 (east)
		return false
	for leg in ["UndergroundPathRoute7Copy", "UndergroundPathWestEast", "UndergroundPathRoute8", "Route8"]:
		if not await _pt_warp_out(leg):
			return false
	print("[playthrough] MILESTONE reached Route8 (Underground Path)")
	return await _pt_hop(3, "LavenderTown")               # Route 8 -> Lavender (east)


## Step onto one *specific* warp cell and ride it. `_pt_warp_out` takes the first warp matching the
## destination, which is the wrong door whenever a map has two of them: a gate house straddling a route
## has one on each side (both `LAST_MAP`), and the route itself has a door into each side of the gate.
## `outside` names the map a `LAST_MAP` exit should resolve to. `avoid_warps` keeps the walk off every
## *other* door on the way — Saffron's streets and Silph Co 1F both have doors the path would otherwise
## step through. Returns true once `dest_map` is loaded.
func _pt_warp_via(cell: Vector2i, dest_map: String, outside := "", avoid_warps := false) -> bool:
	if outside != "":
		last_outside_map = outside
	await _pt_walk_to(cell, 1200, avoid_warps)
	# An overworld gate house entered horizontally warps only when you face its doorway (an fn2 warp tile
	# in front, gh #80); the walk may have arrived on the warp facing the wrong way. If so, turn to the
	# facing that fires it. Only kicks in when the warp hasn't already fired, so working warps are untouched.
	if str(center_label) != dest_map and warp_armed and _warp_at(player.cell) != null:
		for dir in 4:
			if _warp_should_fire(player.cell, dir):
				await _pt_step(dir)
				break
	await _drive_until(func() -> bool: return str(center_label) == dest_map and modal == null, 600)
	return str(center_label) == dest_map


## --- SNORLAX stage (gh #76): the POKé FLUTE's purpose. Play it at the SNORLAX asleep across Route 12
## (10,62) — the road south out of Lavender — beat it, and carry on down Routes 12/13/14/15 to Fuchsia,
## the next gym town. Route 12's north end is sealed by its gate house, which has a door on each side. ---
func _pt_stage_snorlax() -> bool:
	if str(center_label) == "FuchsiaCity":
		return true                                        # already done (resumed)
	if not player_bag.has("POKé FLUTE"):
		return _pt_fail("the SNORLAX stage needs the POKé FLUTE (MR.FUJI)")
	heal_party()
	respawn_map = "LavenderPokecenter"
	# The SNORLAX fight and the Route 13-15 trainer gauntlet (bird keepers + wild) can white the party out;
	# heal, re-stock, and retry the road south from Lavender if a leg is lost (persistent player) — beaten
	# trainers and the woken SNORLAX stay done, so a retry resumes rather than refights. (gh #131)
	for _attempt in 4:
		if str(center_label) == "FuchsiaCity":
			break
		if str(center_label) != "LavenderTown" and not await _pt_warp_out("LavenderTown"):
			return _pt_fail("reach Lavender for the road south (on %s)" % center_label)
		_pt_buy("SUPER POTION", 16)
		heal_party()
		# The gate house is the only way past Route 12's north wall: in its north door, out its south one;
		# then wake + beat the SNORLAX blocking the road.
		if not await _pt_hop(0, "Route12") \
				or not await _pt_warp_via(Vector2i(10, 15), "Route12Gate1F") \
				or not await _pt_warp_via(Vector2i(4, 7), "Route12", "Route12") \
				or not await _pt_wake_snorlax():
			continue                                       # whited out on the road south / SNORLAX — retry
		print("[playthrough] MILESTONE woke and beat the Route 12 SNORLAX")
		# Route 13's west edge lines up with Route 14's rows: leave it at y=8, because row 6 is a one-tile
		# corridor plugged by a BIRD KEEPER who faces away (his sight line points down the gap below him, so
		# he never steps aside) — walking straight across strands you in a pocket you can only back out of.
		var routes_ok := true
		for leg in [[0, "Route13", -1], [2, "Route14", 8], [2, "Route15", -1]]:
			if not await _pt_hop(int(leg[0]), str(leg[1]), int(leg[2])):
				routes_ok = false
				break
			print("[playthrough] MILESTONE reached %s" % leg[1])
		if not routes_ok:
			continue                                       # whited out on the Route 13-15 gauntlet — retry
		# Route 15's gate house walls its two halves apart, so the road west runs through the building.
		if not await _pt_warp_via(Vector2i(14, 8), "Route15Gate1F") \
				or not await _pt_warp_via(Vector2i(0, 4), "Route15", "Route15") \
				or not await _pt_hop(2, "FuchsiaCity"):
			continue                                       # whited out at the Route 15 gate / into Fuchsia — retry
	if str(center_label) != "FuchsiaCity":
		return _pt_fail("Lavender -> Fuchsia (all attempts), on %s" % center_label)
	print("[playthrough] MILESTONE reached FuchsiaCity")
	heal_party()
	respawn_map = "FuchsiaPokecenter"
	print("[playthrough] MILESTONE reached Fuchsia City — %s" % str(_pt_party_summary()))
	return true


## --- SAFFRON stage (gh #76): the walk back north and through the drink gate. Fuchsia -> Lavender ->
## Celadon (buy a drink off the Mart's rooftop vending machines) -> Route 7 -> the thirsty guard's gate
## -> Saffron. One drink opens all four gates (GAVE_SAFFRON_GUARDS_DRINK). ---
## The level the lead grinds to on Route 7, on the way through to Saffron. Silph Co's 7F rival fields
## **five** mons (pidgeot L37, gyarados L38, growlithe L35, alakazam L35, venusaur L40) and the bot fields
## one — it routes around trainers, so it arrives at L41 where a player arrives at L40 with a *team*. At
## L41 it lost the ambush 4 times out of 4. Route 7's grass is the last pool it walks through before
## Saffron (gh #94). The better long-term answer is to fight the trainers it passes, for the money too.
const _PT_SILPH_LEVEL := 48


func _pt_stage_saffron() -> bool:
	if str(center_label) == "SaffronCity":
		return true                                        # already done (resumed)
	# gh #29: the run's longest unguarded walk (Fuchsia -> Lavender -> Celadon -> the Mart's rooftop
	# drink -> Route 7's gate -> Saffron) had no retry, so one transient wander-RNG blockage or
	# whiteout anywhere ended the whole run — it had passed both seeds, and the gh #131 hardening
	# left it as a "theoretical" gap. Standard pattern now: each leg of the attempt is skipped once
	# its outcome holds, so a retry resumes from wherever the last attempt actually ended.
	var why := ""
	for attempt in 3:
		why = await _pt_saffron_attempt()
		if why == "":
			break
		print("[playthrough] saffron attempt %d ended on %s @%s (%s) — heal + retry" % [
			attempt + 1, center_label, str(player.cell), why])
		heal_party()
	if why != "":
		return _pt_fail("saffron: %s (all attempts, on %s)" % [why, center_label])
	heal_party()
	respawn_map = "SaffronPokecenter"
	print("[playthrough] MILESTONE reached Saffron City — %s" % str(_pt_party_summary()))
	return true


## One saffron attempt, resumable (gh #29): returns "" once we stand in Saffron, else the leg that
## failed. Legs are guarded by center_label / the drink / GAVE_SAFFRON_GUARDS_DRINK, so a retry
## picks up mid-walk — out of the respawn Center after a whiteout, or from the city a transient
## walk failure stranded us in — instead of demanding the Fuchsia start over.
func _pt_saffron_attempt() -> String:
	if str(center_label) == "SaffronCity":
		return ""                                          # a prior attempt died past the gate
	if str(center_label) == "LavenderPokecenter" and not await _pt_warp_out("LavenderTown"):
		return "step out of the Lavender Center"           # a Lavender->Celadon whiteout parks us here
	if str(center_label) == "Route7Gate" and not await _pt_warp_out("Route7"):
		return "step out of the Route 7 gate"              # stranded mid-gate (either side resumes)
	if not has_event("GAVE_SAFFRON_GUARDS_DRINK") and not _pt_have_drink() \
			and str(center_label) != "CeladonCity" and str(center_label) != "Route7" \
			and not str(center_label).begins_with("CeladonMart"):
		if not await _pt_fuchsia_to_lavender():            # no-ops on Lavender; warps out of Fuchsia's Center
			return "Fuchsia -> Lavender"
		print("[playthrough] MILESTONE walked back up to Lavender")
		if not await _pt_lavender_to_celadon(_PT_SILPH_LEVEL, false, true):   # catch a FLY carrier (PIDGEY) too
			return "Lavender -> Celadon"
		print("[playthrough] MILESTONE reached Celadon")
	if not has_event("GAVE_SAFFRON_GUARDS_DRINK") and not await _pt_buy_drink():
		return "buy a drink on the Celadon Mart roof"
	if str(center_label).begins_with("CeladonMart") and not await _pt_warp_out("CeladonCity"):
		return "walk back out of the Mart"                 # a resume with the drink already in the bag
	if str(center_label) != "Route7" and not await _pt_hop(3, "Route7"):   # Celadon -> Route 7 (east)
		return "Celadon -> Route 7"
	if not has_event("GAVE_SAFFRON_GUARDS_DRINK"):
		# Route 7's east edge is walled but for the gate house, and the guard inside wants a drink. Its
		# east door drops us back on Route 7 (both doors are LAST_MAP), past the wall.
		if not await _pt_warp_via(Vector2i(11, 10), "Route7Gate"):   # (11,9) is a wall; the door is the lower cell
			return "enter the Route 7 gate"
		if not await _pt_warp_via(Vector2i(5, 3), "Route7", "Route7"):   # stepping on (3,3) buys us past
			return "get past the thirsty guard"
		if not has_event("GAVE_SAFFRON_GUARDS_DRINK"):
			return "the Saffron guard never took the drink"
		print("[playthrough] MILESTONE gave the Saffron guards a drink")
	if not await _pt_hop(3, "SaffronCity"):
		return "Route 7 -> Saffron"
	return ""


## --- SILPH CO stage (gh #76): liberate Silph and open Saffron Gym. Beating GIOVANNI here is what
## clears the Rockets out of the city — one of them (ROCKET3) stands on (34,4), in front of the gym
## door — so this stage gates SABRINA. Silph Co is a **teleport-pad maze**, and the elevator, which
## serves every floor without a key, is a red herring for both places that matter. Derived on the
## real collision + object data, with every trainer treated as a permanent wall (a beaten one stays
## where it stopped), so this route needs no luck:
##
##   * The **CARD KEY** (5F, 21,16) sits in a row-16 corridor whose west door is held by a range-1
##     ROCKET who never steps aside and whose east end is a one-wide column with another ROCKET in
##     it. The only way in is to *arrive*: ride to **9F**, take its pad (17,15), and it drops you on
##     5F (9,15) — inside the corridor. A warp you land on is inert until you leave it, so you simply
##     step south off it and walk to the ball.
##   * **11F's elevator landing (13,0) cannot reach GIOVANNI** — it reaches the top corridor and the
##     10F stairs, nothing else. Giovanni sits behind the floor's one card-key door, block (3,6).
##     The only way into that half is the pad **7F (5,7) -> 11F (3,2)**, and 7F's pad room is sealed
##     off from the rest of 7F: you land in it from **3F's pad (11,11)**, which is itself behind 3F's
##     card-key door, block (8,4).
##
## So: 1F -> lift 9F -> pad to 5F -> CARD KEY -> back through the pad -> lift 3F -> open (8,4) ->
## pad to 7F -> pad to 11F -> open (3,6) -> GIOVANNI. `_pt_walk_dungeon` opens the doors itself
## (`_pt_open_blocking_door`) once the key is in the bag.
##
## The president's MASTER BALL is **not** taken: he is unreachable on foot until gh #80 lands (warps
## fire on any step, so the (5,5) floor tile you must cross to reach him throws you out of the
## building). It is optional content — Stage 2, per the PRD — and nothing later needs it. ---
func _pt_stage_silph() -> bool:
	if has_event("BEAT_SILPH_CO_GIOVANNI"):
		if str(center_label).begins_with("SilphCo"):        # resumed inside — still has to walk out
			return await _pt_silph_exit()
		return true
	if not has_event("RESCUED_MR_FUJI"):
		# ROCKET8 stands on (18,22), the only cell the Silph Co door at (18,21) can be entered from,
		# until the Pokémon Tower rescue moves him (gh #79). The `pokeflute` stage is what does that.
		return _pt_fail("Silph Co is sealed until MR.FUJI is rescued (POKé FLUTE stage)")
	if str(center_label) != "SaffronCity" and not await _pt_warp_out("SaffronCity"):
		return _pt_fail("reach Saffron for Silph Co (on %s)" % center_label)
	heal_party()
	respawn_map = "SaffronPokecenter"
	for attempt in 4:
		_pt_buy("SUPER POTION", 16)                        # each attempt spends them; restock like a player
		if await _pt_silph_climb():
			break
		# A lost battle whites us out to the Saffron Center; anywhere else is a genuine dead-end.
		if str(center_label) != "SaffronPokecenter" and str(center_label) != "SaffronCity":
			return _pt_fail("Silph Co climb (on %s @%s)" % [center_label, str(player.cell)])
		print("[playthrough] Silph attempt %d lost (whited out to %s) — heal + retry" % [
			attempt + 1, center_label])
		heal_party()
		if str(center_label) != "SaffronCity" and not await _pt_warp_out("SaffronCity"):
			return _pt_fail("back to Saffron after a whiteout (on %s)" % center_label)
	if not has_event("BEAT_SILPH_CO_GIOVANNI"):
		return _pt_fail("Silph Co / GIOVANNI (all attempts)")
	print("[playthrough] MILESTONE beat GIOVANNI — Team Rocket has left Saffron")
	if not await _pt_silph_exit():
		return _pt_fail("walk back out of Silph Co (on %s)" % center_label)
	heal_party()
	print("[playthrough] MILESTONE liberated Silph Co — %s" % str(_pt_party_summary()))
	return true


## One attempt at the whole building, from Saffron's street to GIOVANNI beaten. Every leg is guarded on
## what's already held, so a whited-out attempt resumes rather than starting over. Each leg walks with
## `avoid_warps`: the floors are strewn with pads, and a stray step onto one lands us on the wrong floor
## — and the walk to Silph's door crosses Saffron, which has seven other doors.
func _pt_silph_climb() -> bool:
	if not str(center_label).begins_with("SilphCo") \
			and not await _pt_warp_via(Vector2i(18, 21), "SilphCo1F", "", true):
		return false
	if not player_bag.has("CARD KEY"):
		if not await _pt_silph_card_key():
			return false
		print("[playthrough] MILESTONE got the CARD KEY (Silph Co 5F)")
	return await _pt_silph_giovanni()


## Ride to 9F, cross to its pad at (17,15), and land inside 5F's sealed row-16 corridor at (9,15).
## Walk east to (20,16), face the CARD KEY ball at (21,16), and take it. Then step back north onto
## (9,15) — armed again, now that we have left it — which returns us to 9F and the elevator.
func _pt_silph_card_key() -> bool:
	if not await _pt_silph_lift(9):
		return false
	if not await _pt_walk_dungeon(Vector2i(17, 15), 4000, false, true) or str(center_label) != "SilphCo5F":
		return false                                        # the 9F pad drops us on 5F (9,15)
	if not await _pt_walk_dungeon(Vector2i(20, 16), 4000, false, true) or player.cell != Vector2i(20, 16):
		return false
	if not _pt_bag_room():                                  # a full bag leaves the ball on the floor (gh #91)
		return false
	player.facing = 3                                       # RIGHT -> the CARD KEY ball at (21,16)
	interact(player)
	await _drive_until(func() -> bool: return player_bag.has("CARD KEY") and modal == null, 400)
	if not player_bag.has("CARD KEY"):
		return false
	if not await _pt_walk_dungeon(Vector2i(9, 16), 4000, false, true) or player.cell != Vector2i(9, 16):
		return false
	await _pt_step(1)                                       # UP onto the pad -> back to 9F (17,15)
	await _drive_until(func() -> bool: return str(center_label) == "SilphCo9F", 600)
	return str(center_label) == "SilphCo9F"


## With the key: lift to 3F, open its door (block 8,4) and take the pad at (11,11) into 7F's sealed pad
## room; cross it to the pad at (5,7) — the rival ambushes at (3,3) on the way, as he must — and land on
## 11F (3,2). Open the floor's one door (block 3,6) from (6,14) and face GIOVANNI at (6,9).
func _pt_silph_giovanni() -> bool:
	if str(center_label) != "SilphCo7F" and str(center_label) != "SilphCo11F":
		if not await _pt_silph_lift(3):
			return false
		if not await _pt_walk_dungeon(Vector2i(11, 11), 6000, false, true) or str(center_label) != "SilphCo7F":
			return false                                    # 3F's pad -> 7F (5,3), the pad room
		print("[playthrough] MILESTONE opened 3F's card-key door and took the pad into Silph 7F")
	if str(center_label) == "SilphCo7F":
		if not await _pt_walk_dungeon(Vector2i(5, 7), 4000, false, true) or str(center_label) != "SilphCo11F":
			return false                                    # 7F's pad -> 11F (3,2)
		if not has_event("BEAT_SILPH_CO_RIVAL"):
			return false                                    # crossed the pad room without the ambush firing
		print("[playthrough] MILESTONE beat the rival on Silph 7F and took the pad to 11F")
	heal_party()                                            # a real player heals before the boss
	if not await _pt_walk_dungeon(Vector2i(6, 10), 6000, false, true) or player.cell != Vector2i(6, 10):
		return false                                        # (6,10) is behind the card-key door at block (3,6)
	player.facing = 1                                       # UP -> GIOVANNI at (6,9)
	interact(player)
	for _i in 12000:
		if has_event("BEAT_SILPH_CO_GIOVANNI") and modal == null and not cutscene_active:
			return true
		if modal == battle:
			await _pt_win_battle()
			await _drive_until(func() -> bool: return modal == null, 400)
			continue
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == null and not cutscene_active:
			break
		await get_tree().process_frame
	return has_event("BEAT_SILPH_CO_GIOVANNI")


## Out of the building. Giovanni's half of 11F touches nothing but the pad it was entered by, so the
## way out is the way in, backwards: 11F (3,2) -> 7F (5,7) -> 7F (5,3) -> 3F (11,11) -> 3F's lift ->
## 1F -> the street. The doors stay open (their SILPH_DOOR_* events are saved).
func _pt_silph_exit() -> bool:
	if str(center_label) == "SilphCo11F":
		if not await _pt_walk_dungeon(Vector2i(3, 2), 4000, false, true) or str(center_label) != "SilphCo7F":
			return false
	if str(center_label) == "SilphCo7F":
		if not await _pt_walk_dungeon(Vector2i(5, 3), 4000, false, true) or str(center_label) != "SilphCo3F":
			return false
	if str(center_label) == "SilphCo3F":
		if not await _pt_silph_lift(1):
			return false
	if str(center_label) != "SilphCo1F":
		return false
	# 1F's lift landing (20,0) also sees the 2F door (26,0) and the 3F stairs (16,10) — walk past both.
	return await _pt_warp_via(Vector2i(10, 17), "SaffronCity", "SaffronCity", true)


## Walk to this floor's elevator door, board, and ride to `floor_no` (SilphCoElevatorFloors serves
## every floor, no key). Each floor's door sits on its top wall; the car always lands us on its (1,3) mat.
const _PT_SILPH_LIFT_DOOR := {"SilphCo1F": Vector2i(20, 0), "SilphCo2F": Vector2i(20, 0),
	"SilphCo3F": Vector2i(20, 0), "SilphCo4F": Vector2i(20, 0), "SilphCo5F": Vector2i(20, 0),
	"SilphCo6F": Vector2i(18, 0), "SilphCo7F": Vector2i(18, 0), "SilphCo8F": Vector2i(18, 0),
	"SilphCo9F": Vector2i(18, 0), "SilphCo10F": Vector2i(12, 0), "SilphCo11F": Vector2i(13, 0)}


func _pt_silph_lift(floor_no: int) -> bool:
	var dest := "SilphCo%dF" % floor_no
	if str(center_label) == dest:
		return true
	var door: Vector2i = _PT_SILPH_LIFT_DOOR.get(str(center_label), Vector2i(-1, -1))
	if door.x < 0:
		return false
	if not await _pt_walk_dungeon(door, 6000, false, true) or str(center_label) != "SilphCoElevator":
		return false
	return await _pt_ride_elevator("SilphCoElevator", floor_no - 1, dest)   # the panel lists 1F..11F in order


## --- SABRINA stage (gh #76): the sixth badge. Saffron Gym is nine sealed rooms in a 3x3 grid, joined
## only by teleport pads — its whole warp table is 30 self-warps (data/maps/objects/SaffronGym.asm) — and
## its door is only clear once GIOVANNI has fallen in Silph Co, since SAFFRONCITY_ROCKET3 stands on
## (34,4) in front of it. SABRINA has view range 0, so she is talked to, not walked into.
##
## The pad chain is derived on the real warp table with every trainer treated as a permanent wall, so it
## needs no luck: from the door at (8,17), stepping the pads (11,15) -> (15,15) -> (15,5) -> (1,5) lands
## us on (11,11), the one pad inside SABRINA's room. Landing on a pad leaves it inert until we step off,
## which is what stops the last hop from flinging us straight back out. ---
const _PT_SABRINA_PADS := [Vector2i(11, 15), Vector2i(15, 15), Vector2i(15, 5), Vector2i(1, 5)]


func _pt_stage_sabrina() -> bool:
	if has_event("BEAT_SABRINA"):
		return true                                        # already done (resumed)
	if not has_event("BEAT_SILPH_CO_GIOVANNI"):
		return _pt_fail("Saffron Gym's door is held by a Rocket until GIOVANNI falls (silph stage)")
	for attempt in 4:
		if str(center_label) != "SaffronCity" and not await _pt_warp_out("SaffronCity"):
			return _pt_fail("reach Saffron for the gym (on %s)" % center_label)
		heal_party()
		respawn_map = "SaffronPokecenter"
		_pt_buy("SUPER POTION", 16)
		# avoid_warps: Saffron's streets are lined with doors, and the gym's is one cell from a Rocket's
		# old post — a plain walk trips the Fighting Dojo's first.
		if not await _pt_warp_via(Vector2i(34, 3), "SaffronGym", "", true):
			return _pt_fail("enter Saffron Gym (on %s)" % center_label)
		if await _pt_sabrina_room() and await _pt_talk_and_battle(Vector2i(9, 9), 1, "BEAT_SABRINA", 8000, true):
			break
		# A lost battle whites us out to the Saffron Center; anywhere else is a genuine dead-end.
		if str(center_label) != "SaffronPokecenter" and str(center_label) != "SaffronCity":
			return _pt_fail("Saffron Gym / SABRINA (on %s @%s)" % [center_label, str(player.cell)])
		print("[playthrough] SABRINA attempt %d lost (whited out to %s) — heal + retry" % [
			attempt + 1, center_label])
	if not has_event("BEAT_SABRINA"):
		return _pt_fail("Saffron Gym / SABRINA (all attempts)")
	print("[playthrough] MILESTONE beat SABRINA — %s (lead L%d)" % [str(badges), int(player_party[0]["level"])])
	return true


## --- The bot's first water crossing (gh #76, `blaine` prep): Fuchsia -> Route 19 -> Route 20, on SURF.
## Route 19's beach runs out at row 9; everything below it, and all of Route 20, is open water with
## swimmer trainers in it. Route 19's west edge meets Route 20 at its bottom (an 18-block connection
## offset), so the leg is: cross south onto the beach, mount the water at (5,9), swim down to the
## junction, and cross west. `is_walkable` reports water as passable only while `surfing`, so the
## ordinary NPC-aware walk and `_pt_cross` both work afloat with no special casing — once a neighbour
## map's water is passable at all, which it was not before gh #82.
##
## This stops at Route 20 on purpose. **Route 20's sea is split in two**: a wall at column 43 (rows
## 2-13) and another at column 62 (rows 10-16) fence the Seafoam Islands landmass across the middle,
## and the two halves share no water (verified on the `.blk`, which is byte-identical to pokered's).
## The only way across is through the islands' two Route-20 doors — and on Seafoam 1F those doors sit in
## disconnected regions, so the crossing drops into B1F. The open-water approach to Cinnabar is instead
## **Pallet Town -> Route 21**, which is a single water component end to end. Either is a stage of its
## own; this helper just proves the bot can take to the sea and cross a map connection on it. ---
func _pt_surf_to_route20() -> bool:
	if str(center_label) == "Route20":
		return true                                        # already there (resumed)
	if _mon_with_move("SURF") == "":
		return _pt_fail("the sea needs SURF (the `safari` stage teaches it)")
	if not badges.has("SOULBADGE"):
		return _pt_fail("SURF is Soul-Badge gated (the `koga` stage)")
	if str(center_label) != "FuchsiaCity" and not await _pt_warp_out("FuchsiaCity"):
		return _pt_fail("reach Fuchsia to set out to sea (on %s)" % center_label)
	heal_party()
	respawn_map = "FuchsiaPokecenter"
	if not await _pt_cross(0, 3000) or str(center_label) != "Route19":
		return _pt_fail("Fuchsia -> Route 19 (on %s)" % center_label)
	# The beach's last dry row is 9; (5,10) below it is open water.
	if not await _pt_walk_dungeon(Vector2i(5, 9), 3000) or player.cell != Vector2i(5, 9):
		return _pt_fail("reach Route 19's shore at (5,9) (at %s)" % str(player.cell))
	if not await _pt_surf_on(0):
		return _pt_fail("SURF onto the water at Route 19 (5,10)")
	print("[playthrough] MILESTONE took to the water on Route 19")
	# Swim down the route to the Route 20 junction; the swimmers engage on sight and are fought en route.
	if not await _pt_walk_dungeon(Vector2i(1, 45), 8000):
		return _pt_fail("swim down Route 19 (at %s)" % str(player.cell))
	if not await _pt_cross(2, 4000, 45) or str(center_label) != "Route20":
		return _pt_fail("Route 19 -> Route 20 (on %s)" % center_label)
	if not surfing:
		return _pt_fail("dismounted crossing into Route 20 — the rebase dropped SURF")
	print("[playthrough] MILESTONE swam into Route 20 — %s" % str(_pt_party_summary()))
	return true


## --- Reach Cinnabar Island (gh #76, `blaine` prep). Cinnabar has **no dry connection**: the only ways in
## are Route 20 from Fuchsia — whose sea is fenced in two by the Seafoam landmass, so it runs *through*
## the islands (see `_pt_surf_to_route20`) — and **Route 21 from Pallet Town**, which is one open-water
## component end to end. So the cheap route is to FLY home and swim south.
##
## Pallet's beach is the water at (4..7, 14..17); we mount from (4,13). Route 21 is 90 cells of open sea
## with fishers and swimmers scattered down it, all of whom engage on sight and are fought en route. Its
## south edge meets Cinnabar's north shore at columns 1-3 (water) — dismounting happens on its own as
## soon as a step lands on dry land. ---
func _pt_reach_cinnabar() -> bool:
	if str(center_label) == "CinnabarIsland":
		return true                                        # already there (resumed)
	if _mon_with_move("SURF") == "" or not badges.has("SOULBADGE"):
		return _pt_fail("Cinnabar needs SURF + the SOULBADGE (`safari` / `koga` stages)")
	if not await _pt_ensure_fly():
		return _pt_fail("HM02 (FLY) from the Route 16 house (on %s)" % center_label)
	if not await _pt_fly_to("PalletTown"):
		return _pt_fail("FLY home to Pallet Town (on %s)" % center_label)
	print("[playthrough] MILESTONE flew home to Pallet Town")
	if not await _pt_walk_dungeon(Vector2i(4, 13), 2000, false, true) or player.cell != Vector2i(4, 13):
		return _pt_fail("reach Pallet's beach at (4,13) (at %s)" % str(player.cell))
	if not await _pt_surf_on(0):                           # face the water at (4,14)
		return _pt_fail("SURF out of Pallet Town")
	if not await _pt_cross(0, 3000) or str(center_label) != "Route21":
		return _pt_fail("Pallet -> Route 21 (on %s)" % center_label)
	print("[playthrough] MILESTONE put to sea down Route 21")
	if not await _pt_walk_dungeon(Vector2i(2, 88), 16000):
		return _pt_fail("swim down Route 21 (at %s)" % str(player.cell))
	if not await _pt_cross(0, 4000, 2) or str(center_label) != "CinnabarIsland":
		return _pt_fail("Route 21 -> Cinnabar Island (on %s)" % center_label)
	# Ashore: (6,12) is the first dry cell east of the west-shore water. avoid_warps keeps the walk off
	# the Pokémon Center (11,11) and the Mart (15,11), which share that row.
	if not await _pt_walk_dungeon(Vector2i(8, 12), 3000, false, true):
		return _pt_fail("step ashore on Cinnabar (at %s)" % str(player.cell))
	if surfing:
		return _pt_fail("still afloat on Cinnabar — the walk never made landfall")
	print("[playthrough] MILESTONE reached Cinnabar Island — %s" % str(_pt_party_summary()))
	return true


## Make sure somebody in the party knows FLY. Nothing in the stage chain ever went to get HM02, so
## `_pt_reach_cinnabar`'s "FLY home to Pallet" failed outright (gh #95). Only the Squirtle line carries
## SURF; only the SPEAROW line carries FLY, and the bot caught one long ago as exactly this slave.
func _pt_ensure_fly() -> bool:
	if _mon_with_move("FLY") != "":
		return true
	if not await _pt_get_hm02():
		return false
	if not _pt_party_can_learn("FLY"):
		# The `saffron` stage catches a PIDGEY on Route 7 for exactly this. If it somehow didn't, fail
		# loudly here rather than let _pt_teach_hm return a bare false with the HM sitting unused (gh #104).
		return _pt_fail("no party mon can learn FLY — the Route 7 PIDGEY catch was missed")
	return await _pt_teach_hm("HM02", "FLY")


## Saffron -> Celadon on foot: the mirror of the `saffron` stage's crossing. West onto Route 7, in the
## gate house's east door (18,10) — which lands inside at (5,4) — out its west one at (0,3), and west into
## Celadon. Both gate doors are LAST_MAP, so each is walked to by cell. The thirsty guard was paid off in
## the `saffron` stage (GAVE_SAFFRON_GUARDS_DRINK), so he waves us through.
func _pt_saffron_to_celadon() -> bool:
	if str(center_label) == "CeladonCity":
		return true
	if str(center_label) != "SaffronCity" and not await _pt_warp_out("SaffronCity"):
		return false
	if not await _pt_hop(2, "Route7"):
		return false
	if not await _pt_warp_via(Vector2i(18, 10), "Route7Gate"):   # (18,9) never fires; the door is the lower cell
		return false
	if not await _pt_warp_via(Vector2i(0, 3), "Route7", "Route7"):
		return false
	return await _pt_hop(2, "CeladonCity")


## HM02 (FLY) from the girl in the Route 16 house — the run's only source of it.
##
## Route 16 is cut in two by a fence along row 9, and Celadon's exit lands on the **south** half at
## (39,10). The halves meet at exactly one cell: a **CUT tree at (34,9)** (overworld block 0x60 -> 0x6E,
## feet tile 0x3D). The gate house straddles the fence with a *separate* east-west passage per half —
## `--rtprobe` shows its upper room (entered from (24,4)) and lower room (from (24,10)) are disconnected
## inside — so the north half is crossed by the upper passage alone, and the house door is (7,5). The
## SNORLAX at (26,10) sits west of the tree and never has to be woken. The tree regrows on each reload
## of Route 16, so re-cut per entry (gh #95).
func _pt_get_hm02() -> bool:
	if player_bag.has("HM02"):
		return true
	if str(center_label) != "CeladonCity" and not await _pt_saffron_to_celadon():
		return false
	if not await _pt_hop(2, "Route16"):
		return false
	var tree := Vector2i(34, 9)
	if not is_walkable(tree):
		if not await _pt_walk_to(Vector2i(34, 10), 1200, true):
			return false
		player.facing = 1                                  # UP -> the fence tree at (34,9)
		_try_cut(player.front_cell())
		modal = null
		textbox.visible = false
		if not is_walkable(tree):
			return false
		print("[playthrough] cut Route 16's fence tree at (34,9) — the north half is open")
	if not await _pt_warp_via(Vector2i(24, 4), "Route16Gate1F", "", true):
		return false                                       # the gate's UPPER passage, east door
	if not await _pt_warp_via(Vector2i(0, 2), "Route16", "Route16"):
		return false                                       # out its west door, onto Route 16 (17,4)
	if not _pt_bag_room():                                 # a full bag would refuse the gift (gh #91)
		return false
	if not await _pt_warp_via(Vector2i(7, 5), "Route16FlyHouse", "", true):
		return false
	if not await _pt_interact_from(Vector2i(1, 3), 3):     # the girl at (2,3), faced from her left
		return false
	await _drive_until(func() -> bool: return has_event("GOT_HM02") and modal == null and not cutscene_active, 800)
	if not player_bag.has("HM02"):
		return false
	print("[playthrough] MILESTONE got HM02 (FLY) from the Route 16 house")
	return await _pt_warp_out("Route16")


## --- The SECRET KEY (gh #76, `blaine` prep). The Pokémon Mansion is a switch puzzle threaded by two
## **balcony holes** (gh #85): 1F's southern half — the B1F stairs included — has no walkable entrance at
## all, in either switch state. You get in by *falling* into it from 3F. The route below is derived on the
## real collision + warp + hole graph, with the switch state carried through:
##
##   1F (5,10) -> 2F ; 2F (6,1) -> 3F ; flip 3F's switch (panel 10,5, pressed from 10,6)
##   fall through 3F's western balcony (16,14) -> 1F (16,14) ; 1F (21,23) -> B1F
##   flip B1F's south switch (panel 18,25) then its north one (20,3) -> the SECRET KEY at (5,13) opens up
##
## Every switch is a **wall panel**: stand on the cell below it and press A facing UP. The flag is global
## and toggles on each press, so the order matters — this is the sequence, not a set. ---
const _PT_MANSION_SWITCHES := {                       # panel cell -> the cell you press it from
	"PokemonMansion3F": Vector2i(10, 6), "PokemonMansionB1F_south": Vector2i(18, 26),
	"PokemonMansionB1F_north": Vector2i(20, 4)}


func _pt_mansion_secret_key() -> bool:
	if player_bag.has("SECRET KEY"):
		return true                                        # already done (resumed)
	if str(center_label) != "CinnabarIsland" and not await _pt_reach_cinnabar():
		return _pt_fail("reach Cinnabar for the mansion (on %s)" % center_label)
	heal_party()
	respawn_map = "CinnabarPokecenter"
	if not await _pt_warp_via(Vector2i(6, 3), "PokemonMansion1F", "", true):
		return _pt_fail("enter the Pokémon Mansion (on %s)" % center_label)
	# Up to 3F. avoid_warps: 1F's four front doors share the entrance room, and each floor has stairs we
	# must not trip on the way to the one we want.
	if not await _pt_walk_dungeon(Vector2i(5, 10), 4000, false, true) or str(center_label) != "PokemonMansion2F":
		return _pt_fail("Mansion 1F -> 2F (on %s @%s)" % [center_label, str(player.cell)])
	if not await _pt_walk_dungeon(Vector2i(6, 1), 4000, false, true) or str(center_label) != "PokemonMansion3F":
		return _pt_fail("Mansion 2F -> 3F (on %s @%s)" % [center_label, str(player.cell)])
	if not await _pt_mansion_switch("PokemonMansion3F"):
		return _pt_fail("flip the Mansion 3F switch")
	# The western balcony. Walk to the cell above it and step on deliberately: a hole is an ordinary
	# walkable tile, so a plan that merely *crosses* row 14 would drop us down the wrong one.
	if not await _pt_walk_dungeon(Vector2i(16, 13), 4000, false, true) or player.cell != Vector2i(16, 13):
		return _pt_fail("reach Mansion 3F's western balcony (at %s)" % str(player.cell))
	await _pt_step(0)
	await _drive_until(func() -> bool: return str(center_label) == "PokemonMansion1F" \
		and not cutscene_active, 900)
	if str(center_label) != "PokemonMansion1F" or player.cell != Vector2i(16, 14):
		return _pt_fail("fall through the balcony to 1F (on %s @%s)" % [center_label, str(player.cell)])
	print("[playthrough] MILESTONE fell through the Mansion's balcony into 1F's sealed south")
	if not await _pt_walk_dungeon(Vector2i(21, 23), 4000, false, true) or str(center_label) != "PokemonMansionB1F":
		return _pt_fail("Mansion 1F -> B1F (on %s @%s)" % [center_label, str(player.cell)])
	if not await _pt_mansion_switch("PokemonMansionB1F_south"):
		return _pt_fail("flip the Mansion B1F south switch")
	if not await _pt_mansion_switch("PokemonMansionB1F_north"):
		return _pt_fail("flip the Mansion B1F north switch")
	if not await _pt_take_ball(Vector2i(5, 13), "SECRET KEY"):
		return _pt_fail("take the SECRET KEY at B1F (5,13) (at %s)" % str(player.cell))
	print("[playthrough] MILESTONE took the SECRET KEY — %s" % str(_pt_party_summary()))
	if not await _pt_mansion_exit():
		return _pt_fail("leave the Pokémon Mansion (on %s @%s)" % [center_label, str(player.cell)])
	print("[playthrough] MILESTONE left the Pokémon Mansion -> Cinnabar Island")
	return true


## --- BLAINE stage (gh #76): the seventh badge. Cinnabar Gym's door is locked without the SECRET KEY, and
## inside are six rooms that snake back on themselves, each sealed by a **quiz gate**
## (scripts/CinnabarGym.asm; the machines are `hidden_events.asm` wall panels — stand below one and press
## A facing UP). A right answer opens that room's gate for good; a wrong one and the room's trainer jumps
## you. Because the rooms snake, the order is forced: the only machine you can reach is the next one. The
## bot answers correctly (the same `HIDDEN_EVENTS` table the engine reads), as a player with a guide
## would, rather than brute-forcing six fights before the leader. ---
const _PT_CINNABAR_QUIZ := [Vector2i(15, 8), Vector2i(10, 2), Vector2i(9, 8),
	Vector2i(9, 14), Vector2i(1, 14), Vector2i(1, 8)]     # the cell below each machine, gates 1..6


func _pt_stage_blaine() -> bool:
	if has_event("BEAT_BLAINE"):
		return true                                        # already done (resumed)
	# The `sabrina` stage ends in her pad-sealed room; ride the pads back out first (gh #76 seam).
	if str(center_label) == "SaffronGym" and not await _pt_saffron_gym_exit():
		return _pt_fail("pad back out of Saffron Gym")
	if not player_bag.has("SECRET KEY") and not await _pt_mansion_secret_key():
		return _pt_fail("the SECRET KEY (Pokémon Mansion) — the gym door is locked without it")
	for attempt in 4:
		if str(center_label) != "CinnabarIsland" and not await _pt_warp_out("CinnabarIsland"):
			return _pt_fail("reach Cinnabar for the gym (on %s)" % center_label)
		heal_party()
		respawn_map = "CinnabarPokecenter"
		_pt_buy("SUPER POTION", 16)
		if not await _pt_warp_via(Vector2i(18, 3), "CinnabarGym", "", true):
			return _pt_fail("enter Cinnabar Gym — is the door still locked? (on %s)" % center_label)
		var opened := true
		for i in _PT_CINNABAR_QUIZ.size():
			if not await _pt_answer_quiz(i):
				opened = false
				break
		if opened and await _pt_talk_and_battle(Vector2i(3, 4), 1, "BEAT_BLAINE", 8000, true):
			break                                          # BLAINE @ (3,3), face UP
		# A lost battle whites us out to the Cinnabar Center; anywhere else is a genuine dead-end.
		if str(center_label) != "CinnabarPokecenter" and str(center_label) != "CinnabarIsland":
			return _pt_fail("Cinnabar Gym (on %s @%s)" % [center_label, str(player.cell)])
		print("[playthrough] BLAINE attempt %d lost (whited out to %s) — heal + retry" % [
			attempt + 1, center_label])
	if not has_event("BEAT_BLAINE"):
		return _pt_fail("Cinnabar Gym / BLAINE (all attempts)")
	print("[playthrough] MILESTONE beat BLAINE — %s (lead L%d)" % [str(badges), int(player_party[0]["level"])])
	return true


## --- GIOVANNI stage (gh #76): the eighth badge, and the last gym. Viridian Gym's door is shut until you
## hold every *other* badge (`ViridianCityCheckGymOpenScript`, gh #86), and inside is a **spin-tile maze**:
## step on an arrow and you slide until a wall stops you. `spin_aware` planning models a step onto an
## arrow as landing on its stop tile, which is what makes the floor walkable at all — the same machinery
## that threads the Rocket Hideout. Eight sight-trainers are scattered through it; GIOVANNI stands at
## (2,1) with view range 0, so he is talked to. ---
const _PT_SEVEN_BADGES := ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
	"SOULBADGE", "MARSHBADGE", "VOLCANOBADGE"]


func _pt_stage_giovanni() -> bool:
	if has_event("BEAT_GIOVANNI"):
		return true                                        # already done (resumed)
	for b in _PT_SEVEN_BADGES:
		if not badges.has(b):
			return _pt_fail("Viridian Gym stays locked until every other badge is in hand (no %s)" % b)
	for attempt in 4:
		if str(center_label) != "ViridianCity" and not await _pt_fly_to("ViridianCity") \
				and not await _pt_warp_out("ViridianCity"):
			return _pt_fail("reach Viridian for the gym (on %s)" % center_label)
		heal_party()
		respawn_map = "ViridianPokecenter"
		_pt_buy("SUPER POTION", 16)
		# Walking onto (32,8) is what latches VIRIDIAN_GYM_OPEN, so the door admits us on the way in.
		if not await _pt_warp_via(Vector2i(32, 7), "ViridianGym", "", true):
			return _pt_fail("enter Viridian Gym — is the door still locked? (on %s)" % center_label)
		if await _pt_talk_and_battle(Vector2i(2, 2), 1, "BEAT_GIOVANNI", 8000, false, true):
			break                                          # GIOVANNI @ (2,1), face UP
		# A lost battle whites us out to the Viridian Center; anywhere else is a genuine dead-end.
		if str(center_label) != "ViridianPokecenter" and str(center_label) != "ViridianCity":
			return _pt_fail("Viridian Gym (on %s @%s)" % [center_label, str(player.cell)])
		print("[playthrough] GIOVANNI attempt %d lost (whited out to %s) — heal + retry" % [
			attempt + 1, center_label])
	if not has_event("BEAT_GIOVANNI"):
		return _pt_fail("Viridian Gym / GIOVANNI (all attempts)")
	print("[playthrough] MILESTONE beat GIOVANNI — all eight badges: %s" % str(badges))
	return true


## --- VICTORY ROAD stage (gh #76): the road to the League. Viridian -> Route 22 -> the gate house ->
## Route 23 -> Victory Road -> the Indigo Plateau.
##
## Route 23 is a **river with a footpath at each end**: the middle 32 rows (y 72..103) are open water, so
## the climb is walk / SURF / walk. Seven badge checkpoints are strung up its length (`Route23GuardsYCoords`);
## by now every one of them waves us through. The only door onto it is **Route22Gate** — Route 22's north
## edge has no crossable cell at all — and that gate is the one in Kanto that joins two different maps
## (gh #87).
##
## Victory Road is three floors of boulder puzzle, and the route was derived on the real collision +
## object + warp graph with every trainer and item ball treated as a permanent wall:
##  * **1F** (in at 8,17) reaches its 2F ladder (1,1) on foot — the floor's own switch (17,13) only opens
##    a shortcut, so no boulder is needed here.
##  * **2F** lands you at (0,8) in a sealed **71-cell west pocket**. Its one exit is the door that
##    switch1 (1,16) opens, and the only boulder in the pocket sits at (4,14). Shoving it onto the switch
##    is the whole puzzle: DOWN, LEFT, DOWN, then LEFT twice.
##  * The 315-cell main region then holds three ladders, and **none of them is the exit**: 2F's exit pair
##    (29,7)/(29,8) sits in a **13-cell pocket** whose only door is the ladder down from 3F's (26,8).
##  * **3F** is likewise split. Its (23,7) ladder lands in the big western half (the hole, the switch, the
##    items); the east pocket that holds (26,8) is reached only from **2F's (25,14) ladder**.
##
## So the way out is a figure-of-eight: 1F -> 2F west -> (switch) -> 2F main -> **3F east** -> **2F exit
## pocket** -> Route 23, twelve rows above where we went in. Neither 2F's second switch nor 3F's hole is
## on the critical path — they gate items. ---
# VR1F (gh #105): tile-pairs seal the entrance pocket off from the (1,1) up-ladder; the only bridge is the
# (17,13) switch (opens block (4,6)). tools/sokoban.py's route for boulder (5,15) -> (17,13) (dir DOWN=0
# UP=1 LEFT=2 RIGHT=3): [from, dir, times]. Push 3 stands the player on the entrance warp (8,17) facing
# north — legal since VR1F warps only fire facing the map edge (the gh #80 fix).
const _PT_VR1F_PUSHES := [
	[Vector2i(5, 15), 0, 1],                      # DOWN  -> (5,16)
	[Vector2i(5, 16), 3, 3],                      # RIGHT -> (8,16)
	[Vector2i(8, 16), 1, 1],                      # UP    -> (8,15)
	[Vector2i(8, 15), 3, 1],                      # RIGHT -> (9,15)
	[Vector2i(9, 15), 1, 1],                      # UP    -> (9,14)
	[Vector2i(9, 14), 3, 7],                      # RIGHT -> (16,14)
	[Vector2i(16, 14), 1, 2],                     # UP    -> (16,12)
	[Vector2i(16, 12), 3, 1],                     # RIGHT -> (17,12)
	[Vector2i(17, 12), 0, 1],                     # DOWN  -> (17,13), the switch
]

const _PT_VR2F_PUSHES := [                        # boulder (4,14) -> switch1 (1,16): [from, dir, times]
	[Vector2i(4, 14), 0, 1],                      # DOWN  -> (4,15)
	[Vector2i(4, 15), 2, 1],                      # LEFT  -> (3,15)
	[Vector2i(3, 15), 0, 1],                      # DOWN  -> (3,16)
	[Vector2i(3, 16), 2, 2],                      # LEFT  -> (2,16) -> (1,16), the switch
]

# 3F (gh #105): boulder (22,3) -> switch1 (3,5) opens block (3,5), connecting the landing to pocket1 (the
# hole + hole-boulder). tools/vrsolve.py route (dir DOWN=0 UP=1 LEFT=2 RIGHT=3).
const _PT_VR3F_PUSHES := [
	[Vector2i(22, 3), 1, 2],                      # UP    -> (22,1)
	[Vector2i(22, 1), 2, 16],                     # LEFT  -> (6,1)
	[Vector2i(6, 1), 0, 1],                       # DOWN  -> (6,2)
	[Vector2i(6, 2), 2, 4],                       # LEFT  -> (2,2)
	[Vector2i(2, 2), 0, 3],                       # DOWN  -> (2,5)
	[Vector2i(2, 5), 3, 1],                       # RIGHT -> (3,5), the switch
]

## The level the lead grinds to before the League. LORELEI opens at L53 and the CHAMPION ends at L65,
## thirty mons deep. `--elite4stage` clears it with a L62 Blastoise *plus* a L52 Pidgeot and a L55
## Arcanine to switch to; the run fields one real mon and carries the gauntlet on FULL RESTOREs, so match
## that lead at least. Victory Road's own trainers top it up further (gh #94).
const _PT_LEAGUE_LEVEL := 62


## Grind for the League *before* Route 22. Walking onto Route 22 with all eight badges arms the second
## rival ambush (`Route22.gd`), and he fields six mons topping out at a L53 VENUSAUR — which killed the
## run's L51 lead outright. Route 22's own grass is L2-5, and Route 23's good pool (fearow/ditto L38-43)
## sits *behind* the ambush.
##
## The best grass the bot can actually stand on first is **Route 18's** — spearow/doduo/fearow/raticate
## L20-29, mean 418 exp a fight, twice Route 7's — one FLY from Fuchsia and straight out its west edge.
## (Route 15's is richer on paper but sits east of that route's gate house, unreachable from Fuchsia;
## Route 12's and Route 8's are fenced off from their entrances the same way. Checked, all three.)
## Then FLY back (gh #94).
func _pt_grind_for_the_league() -> bool:
	if int(player_party[0]["level"]) >= _PT_LEAGUE_LEVEL:
		return true
	if await _pt_fly_to("FuchsiaCity") and await _pt_hop(2, "Route18"):
		await _pt_grind_to(_PT_LEAGUE_LEVEL, 1400)
		warp_armed = _warp_at(player.cell) == null         # the grind teleports onto grass (gh #76)
	else:
		print("[playthrough] no FLY to Route 18's grass — Route 23's pool will have to do")
	return await _pt_fly_to("ViridianCity") or str(center_label) == "ViridianCity"


func _pt_stage_victoryroad() -> bool:
	if str(center_label) == "IndigoPlateau" or visited_fly.has("IndigoPlateau"):
		return true                                        # already done (resumed)
	if badges.size() < 8:
		return _pt_fail("Route 23's checkpoints want all eight badges (have %d)" % badges.size())
	if _mon_with_move("SURF") == "" or _mon_with_move("STRENGTH") == "":
		return _pt_fail("Victory Road needs SURF (Route 23's river) + STRENGTH (its boulders)")
	if str(center_label) != "ViridianCity" and not await _pt_fly_to("ViridianCity") \
			and not await _pt_warp_out("ViridianCity"):
		return _pt_fail("reach Viridian for the road west (on %s)" % center_label)
	if not await _pt_grind_for_the_league():
		return _pt_fail("grind for the League (on %s)" % center_label)
	# Persistent player (ADR-011): Route 22's rival ambush and Victory Road's trainers can white us out to
	# the Viridian Center, and the stage used to die there. Beaten trainers and the rival's event persist,
	# so a retry resumes rather than refights (gh #94).
	var climbed := false
	for attempt in 3:
		# gh #30: a failed climb (unlike a whiteout) leaves us standing INSIDE the cave, where FLY is
		# refused and no warp names Viridian — the old loop died here blaming "a whiteout" that never
		# happened. Walk back out the way we came: each floor's down-ladder is an explicit warp, and
		# the 1F mouth resolves honestly to Route 23. Boulders reset on floor re-entry (switch events
		# persist), so leaving restarts the puzzle cleanly for the retry. Best effort — a boulder can
		# genuinely seal a pocket, and then the honest outcome is the stage failing where it stands.
		var way_out := {"VictoryRoad3F": "VictoryRoad2F", "VictoryRoad2F": "VictoryRoad1F",
			"VictoryRoad1F": "Route23"}
		for _floor in 3:
			if not way_out.has(str(center_label)):
				break
			if not await _pt_warp_out(str(way_out[str(center_label)])):
				break
		if str(center_label) != "ViridianCity" and not await _pt_fly_to("ViridianCity") \
				and not await _pt_warp_out("ViridianCity"):
			return _pt_fail("back to Viridian for retry %d (on %s @%s)" % [
				attempt + 1, center_label, str(player.cell)])
		heal_party()
		respawn_map = "ViridianPokecenter"
		# A SUPER POTION restores 50 HP; the lead has ~205 by now, and _pt_should_heal only fires under
		# 40%. HYPER POTION (200 HP) is effectively a full heal for twice the money, and
		# _pt_heal_item_key already reaches for the strongest thing in the bag (gh #94).
		_pt_bag_room(1)
		_pt_buy("HYPER POTION", 10)
		_pt_buy("SUPER POTION", 10)
		if not await _pt_reach_route23():
			print("[playthrough] Victory Road approach attempt %d ended on %s — heal + retry" % [
				attempt + 1, center_label])
			continue
		print("[playthrough] MILESTONE crossed Route 23's river — at Victory Road's door")
		if await _pt_climb_victory_road():
			climbed = true
			break
		print("[playthrough] Victory Road attempt %d ended on %s @%s — heal + retry" % [
			attempt + 1, center_label, str(player.cell)])
	if not climbed:
		return _pt_fail("Victory Road (all attempts), on %s @%s" % [center_label, str(player.cell)])
	print("[playthrough] MILESTONE out of Victory Road — %s" % str(_pt_party_summary()))
	# Back on Route 23 at (14,31), twelve rows above the entrance. Column 18 is the only way north.
	if not await _pt_walk_dungeon(Vector2i(18, 22), 4000, false, true):
		return _pt_fail("climb Route 23 past Victory Road (at %s)" % str(player.cell))
	if not await _pt_walk_dungeon(Vector2i(9, 1), 4000, false, true):
		return _pt_fail("thread Route 23's north maze (at %s)" % str(player.cell))
	if not await _pt_cross_north() or str(center_label) != "IndigoPlateau":
		return _pt_fail("Route 23 -> Indigo Plateau (on %s @%s)" % [center_label, str(player.cell)])
	print("[playthrough] MILESTONE reached the INDIGO PLATEAU (lead L%d)" % int(player_party[0]["level"]))
	return true


## Viridian -> Route 22 -> Route22Gate -> Route 23, then up it: walk to the south shore, SURF the river,
## and come ashore below Victory Road's door. The waypoints keep the swim in the channel — a step onto
## land dismounts, and the two dry cells at (8..9, 90..91) are an island in the middle of the water.
func _pt_reach_route23() -> bool:
	if str(center_label) != "Route22" and not await _pt_hop(2, "Route22"):
		return _pt_fail("Viridian -> Route 22 (on %s)" % center_label)
	if not await _pt_warp_out("Route22Gate"):
		return _pt_fail("into the Route 22 gate house (on %s)" % center_label)
	# The gate's four doors are all LAST_MAP; standing north of the counter is what makes them Route 23.
	if not await _pt_walk_to(Vector2i(4, 1), 400, true):
		return _pt_fail("past the gate's badge guard (at %s)" % str(player.cell))
	await _pt_step(1)                                      # UP onto the north door (4,0)
	await _drive_until(func() -> bool: return str(center_label) != "Route22Gate", 600)
	if str(center_label) != "Route23":
		return _pt_fail("out the gate's north door -> Route 23 (on %s)" % center_label)
	# South footpath -> the shore at (12,104); the water begins one row north.
	if not await _pt_walk_dungeon(Vector2i(12, 104), 6000, false, true):
		return _pt_fail("walk up Route 23's south footpath (at %s)" % str(player.cell))
	if not await _pt_surf_on(1):                           # face the river at (12,103)
		return _pt_fail("SURF up Route 23's river (at %s)" % str(player.cell))
	for wp in [Vector2i(11, 92), Vector2i(5, 80), Vector2i(10, 72)]:
		if not await _pt_walk_dungeon(wp, 4000) or player.cell != wp:
			return _pt_fail("swim to %s (at %s, surfing=%s)" % [str(wp), str(player.cell), surfing])
	# Ashore, one step short of the last wild pool before the point of no return. The bot arrives here
	# around L44 because it routes *around* trainers instead of fighting them, while LORELEI opens at
	# L53 and the CHAMPION ends at L65 — thirty mons, no bench worth switching to. Route 23's grass
	# (rows 44-69: ekans/spearow L26, ditto/fearow L38-43) is where a player grinds, so grind (gh #94).
	if not await _pt_walk_dungeon(Vector2i(10, 71), 2000, false, true) or surfing:
		return _pt_fail("Route 23: ashore north of the river (at %s, surfing=%s)" % [str(player.cell), surfing])
	if int(player_party[0]["level"]) < _PT_LEAGUE_LEVEL:
		await _pt_grind_to(_PT_LEAGUE_LEVEL, 900)
		warp_armed = _warp_at(player.cell) == null     # the grind teleports onto grass; re-arm (gh #76)
	if not await _pt_walk_dungeon(Vector2i(4, 31), 8000, false, true) or str(center_label) != "VictoryRoad1F":
		return _pt_fail("north shore -> Victory Road's door (on %s @%s)" % [center_label, str(player.cell)])
	return true


## Victory Road, in at 1F (8,17) and out of 2F's east pocket onto Route 23 (14,31).
## Push a named boulder sequence with STRENGTH on (each entry is [from, dir, times]).
func _pt_run_pushes(pushes: Array, where: String) -> bool:
	if not strength_active and not await _pt_use_field_move("STRENGTH"):
		return _pt_fail("use STRENGTH on %s" % where)
	for push in pushes:
		if not await _pt_push_boulder(push[0], int(push[1]), int(push[2])):
			return _pt_fail("shove the %s boulder %s from %s (at %s)" % [
				where, _PT_DIR_NAME[int(push[1])], str(push[0]), str(player.cell)])
	return true


## Victory Road 1F: shove boulder (5,15) onto the (17,13) switch (opens the (1,1) ladder).
func _pt_vr1f_open_switch() -> bool:
	if has_event("VR1_SWITCH"):
		return true
	if not await _pt_run_pushes(_PT_VR1F_PUSHES, "Victory Road 1F"):
		return false
	return has_event("VR1_SWITCH")


## Victory Road 3F: shove boulder (22,3) onto switch1 (3,5) — opens the way to the hole + its boulder.
func _pt_vr3f_open_switch() -> bool:
	if has_event("VR3_SWITCH1"):
		return true
	if not await _pt_run_pushes(_PT_VR3F_PUSHES, "Victory Road 3F"):
		return false
	return has_event("VR3_SWITCH1")


## Victory Road is a holistic multi-floor boulder puzzle under tile-pair collisions (gh #105); the exit is
## reachable only by weaving 1F→2F→3F→(hole)→2F→3F→2F. Route derived by tools/vrdyn.py; see
## docs/notes/gh105-victory-road.md.
func _pt_climb_victory_road() -> bool:
	if str(center_label) != "VictoryRoad1F":
		return _pt_fail("expected Victory Road 1F, on %s" % center_label)
	# 1F: switch (17,13) opens block (4,6) -> the (1,1) ladder to 2F.
	if not await _pt_vr1f_open_switch():
		return false
	print("[playthrough] MILESTONE Victory Road 1F's switch pressed — the (1,1) ladder is open")
	if not await _pt_take_ladder(Vector2i(1, 1), "VictoryRoad2F", Vector2i(0, 8), 4000):
		return _pt_fail("1F -> its 2F ladder (on %s @%s)" % [center_label, str(player.cell)])
	# 2F west pocket: switch1 (1,16) opens block (3,4) -> the (23,7) ladder to 3F.
	if not await _pt_vr2f_open_switch():
		return false
	print("[playthrough] MILESTONE Victory Road 2F's switch1 pressed — the west door is open")
	if not await _pt_take_ladder(Vector2i(23, 7), "VictoryRoad3F", Vector2i(23, 7), 6000):
		return _pt_fail("2F -> the (23,7) ladder up (on %s @%s)" % [center_label, str(player.cell)])
	# 3F: switch1 (3,5) reaches the hole; shove boulder (22,15) into it (a 2F boulder appears), then drop.
	if not await _pt_vr3f_open_switch():
		return false
	print("[playthrough] MILESTONE Victory Road 3F's switch1 pressed — the hole is reachable")
	if not await _pt_push_boulder(Vector2i(22, 15), 3, 1):   # RIGHT into the hole (23,15)
		return _pt_fail("shove the 3F boulder into the hole (at %s)" % str(player.cell))
	await _pt_step(3)                                        # step onto the hole (23,15)
	# fall_down_hole is an async cutscene fired from on_step, so wait for the warp to land us on 2F.
	await _drive_until(func() -> bool: return str(center_label) == "VictoryRoad2F", 600)
	if str(center_label) != "VictoryRoad2F":
		return _pt_fail("fall through the 3F hole (on %s @%s)" % [center_label, str(player.cell)])
	print("[playthrough] MILESTONE fell through the 3F hole to 2F — the switch2 boulder has appeared")
	# 2F: shove the fallen boulder (23,16) onto switch2 (9,16) -> opens block (7,11) -> the (25,14) ladder.
	if not await _pt_run_pushes([[Vector2i(23, 16), 2, 14]], "Victory Road 2F switch2"):
		return false
	print("[playthrough] MILESTONE Victory Road 2F's switch2 pressed — the (25,14) ladder is open")
	if not await _pt_take_ladder(Vector2i(25, 14), "VictoryRoad3F", Vector2i(27, 15), 6000):
		return _pt_fail("2F -> the (25,14) ladder up (on %s @%s)" % [center_label, str(player.cell)])
	# 3F pocket2 -> the (26,8) ladder down to 2F's exit pocket, then out to Route 23.
	if not await _pt_take_ladder(Vector2i(26, 8), "VictoryRoad2F", Vector2i(27, 7), 4000):
		return _pt_fail("3F's exit pocket -> its (26,8) ladder down (on %s @%s)" % [center_label, str(player.cell)])
	if not await _pt_walk_dungeon(Vector2i(29, 7), 2000, false, true) or str(center_label) != "Route23":
		return _pt_fail("2F's exit pocket -> Route 23 (on %s @%s)" % [center_label, str(player.cell)])
	return true


## Step onto the ladder at `ladder` and require it to land on `landing` of `dest`. Victory Road's floors
## carry four ladders each and `_pt_walk_dungeon` reports "the map changed" for any of them, so an
## unintended one reads as success and strands the climb a floor away from where the route expects it.
func _pt_take_ladder(ladder: Vector2i, dest: String, landing: Vector2i, budget := 4000) -> bool:
	var from := str(center_label)
	if not await _pt_walk_dungeon(ladder, budget, false, true):
		return false
	if str(center_label) != dest or player.cell != landing:
		print("[playthrough] %s's %s ladder led to %s @%s, not %s @%s" % [
			from, str(ladder), center_label, str(player.cell), dest, str(landing)])
		return false
	return true


## Victory Road 2F's west pocket: STRENGTH, then shove the lone boulder onto switch1 at (1,16).
func _pt_vr2f_open_switch() -> bool:
	if has_event("VR2_SWITCH1"):
		return true                                        # already pressed (resumed / re-entered)
	if not strength_active and not await _pt_use_field_move("STRENGTH"):
		return _pt_fail("use STRENGTH on Victory Road 2F")
	for push in _PT_VR2F_PUSHES:
		if not await _pt_push_boulder(push[0], int(push[1]), int(push[2])):
			return _pt_fail("shove the 2F boulder %s from %s (at %s)" % [
				_PT_DIR_NAME[int(push[1])], str(push[0]), str(player.cell)])
	return has_event("VR2_SWITCH1")


## Shove the boulder standing on `at` one cell in `dir`, `times` times (STRENGTH must already be active).
## The push is a real step: `try_push_boulder` slides the boulder and the player advances into the cell it
## vacated, so `times` consecutive steps keep shoving the same boulder. The fourth obstacle kind after
## guards, item balls and card-key doors (ADR-012) — but unlike those it is aimed, not merely cleared, so
## the caller names each leg rather than letting the walk discover it.
func _pt_push_boulder(at: Vector2i, dir: int, times := 1) -> bool:
	var behind: Vector2i = at - DIRV4[dir]
	if player.cell != behind and (not await _pt_walk_dungeon(behind, 2000, false, true) or player.cell != behind):
		return false                                       # can't line up behind it
	for i in times:
		var boulder = _npc_at(at + DIRV4[dir] * i)
		if boulder == null or not str(boulder.key).begins_with("SPRITE_BOULDER@"):
			print("[playthrough] boulder shove: nothing to push at %s (tile %d of %d)" % [
				str(at + DIRV4[dir] * i), i + 1, times])
			return false                                   # nothing there to push
		# gh #129: pokered requires two consecutive same-direction pushes per tile — the first only arms
		# BIT_TRIED_PUSH_BOULDER (a bump in place), the second slides the boulder and advances the player.
		# Push until the player actually advances, capped so a genuinely-blocked shove still fails.
		var moved_tile := false
		for _try in 3:
			if await _pt_step(dir):
				moved_tile = true
				break
		if not moved_tile:
			# The boulder is there but won't budge: the cell beyond is solid, occupied, or the
			# shove crosses an elevation edge (gh #105's CheckForCollisionWhenPushingBoulder).
			# Name the tile — a stale derived route fails here, and "which tile" is the whole
			# diagnosis (gh #28).
			print("[playthrough] boulder shove refused at %s -> %s (tile %d of %d, %s)" % [
				str(at + DIRV4[dir] * i), str(at + DIRV4[dir] * (i + 1)), i + 1, times,
				_PT_DIR_NAME[dir]])
			return false
		# pokered ignores pushes while BIT_BOULDER_DUST is set (shove start -> dust end). Wait the
		# beat out, or the next tile's arming presses vanish into it and the shove reads as refused:
		# the player's step (0.268s) ends mid-slide (0.536s), so the bot is always here early (gh #28).
		await _drive_until(func() -> bool: return not _boulder_dust_pending, 120)
		if modal != null or cutscene_active:               # a cave-floor wild encounter fired on landing —
			await _pt_settle()                             # win it before the next shove (gh #105/#106)
	return true


## --- ELITE FOUR stage (gh #76): the last of the run. Four rooms stacked north, each sealing its own exit
## until its member falls (`*ShowOrHideExitBlock`), then LANCE's hall, then the CHAMPION.
##
## It is a **gauntlet**, and that is a rule, not a mood: `IndigoPlateauLobby_Script` wipes the whole Indigo
## Plateau event range the moment you walk back down having started (`BIT_STARTED_ELITE_4`), so all four
## stand up again. The bot therefore heals and buys *once*, on the way in, then runs the five fights
## without leaving — and on a whiteout it restarts from LORELEI, exactly as a player would.
##
## Every member has view range 0, so each is talked to rather than walked into (`_pt_fight_trainer` keyed
## by home cell). The CHAMPION is not a trainer at all: walking into his room is the trigger
## (`SCRIPT_CHAMPIONSROOM_PLAYER_ENTERS`, armed by beating AGATHA), and the fight runs straight on into
## the HALL OF FAME. ---
const _PT_E4_ROOMS := [                           # [room, member's home cell, the door up from it]
	["LoreleisRoom", Vector2i(5, 2), Vector2i(4, 0)],
	["BrunosRoom", Vector2i(5, 2), Vector2i(4, 0)],
	["AgathasRoom", Vector2i(5, 2), Vector2i(4, 0)],
	["LancesRoom", Vector2i(6, 1), Vector2i(5, 0)],
]


func _pt_stage_elite4() -> bool:
	if has_event("HALL_OF_FAME"):
		return true                                        # already done (resumed)
	if str(center_label) != "IndigoPlateauLobby":
		if str(center_label) != "IndigoPlateau" and not await _pt_fly_to("IndigoPlateau") \
				and not await _pt_warp_out("IndigoPlateau"):
			return _pt_fail("reach the Indigo Plateau (on %s)" % center_label)
		if not await _pt_warp_out("IndigoPlateauLobby"):
			return _pt_fail("into the Indigo Plateau lobby (on %s)" % center_label)
	# Each attempt is worth more than the last: the four pay out on every defeat, so the lobby can afford
	# another batch of FULL RESTOREs, and the lead climbs a level or two on the way through. Four attempts
	# carried a L63 Blastoise to L72; a player who keeps losing to the CHAMPION does exactly this, because
	# the Elite Four is the best experience in the game (gh #94).
	for attempt in 8:
		# A loss whites us OUTSIDE onto IndigoPlateau (gh #101 escape-warp fly-warps to the town), not back
		# into the lobby, so walk back in — re-entering the lobby is what resets the gauntlet (its on_enter,
		# gh #96). (The pre-loop approach above only runs once; each retry lands out here.)
		if str(center_label) == "IndigoPlateau":
			await _pt_warp_out("IndigoPlateauLobby")
		if str(center_label) != "IndigoPlateauLobby":
			return _pt_fail("the Elite Four: stranded on %s @%s" % [center_label, str(player.cell)])
		heal_party()
		respawn_map = "IndigoPlateauLobby"
		_pt_bag_room(2)
		_pt_buy("FULL RESTORE", 10)                        # the strongest first — money runs out, not slots
		_pt_buy("HYPER POTION", 10)
		if await _pt_run_gauntlet() or has_event("BEAT_CHAMPION"):
			break
		print("[playthrough] ELITE FOUR attempt %d lost — the lobby reset it; start over at LORELEI" % [
			attempt + 1])
	if not has_event("BEAT_CHAMPION"):
		return _pt_fail("the Elite Four / the CHAMPION (all attempts)")
	print("[playthrough] MILESTONE beat the CHAMPION — %s" % str(_pt_party_summary()))
	# The Hall of Fame ceremony and the credits roll straight out of the last battle; wait them out.
	await _drive_until(func() -> bool: return has_event("HALL_OF_FAME") and not cutscene_active, 60000)
	if not has_event("HALL_OF_FAME"):
		return _pt_fail("the HALL OF FAME ceremony never finished (on %s)" % center_label)
	print("[playthrough] MILESTONE entered the HALL OF FAME — the run is complete")
	return true


## The lobby's north door -> LORELEI -> BRUNO -> AGATHA -> LANCE -> the CHAMPION, without coming back
## down. False if a fight was lost (we whited out to the lobby), which the caller retries from LORELEI.
func _pt_run_gauntlet() -> bool:
	if not await _pt_warp_via(Vector2i(8, 0), "LoreleisRoom", "", true):
		print("[playthrough] gauntlet: could not enter LORELEI's room (on %s @%s)" % [
			center_label, str(player.cell)])
		return false
	for room in _PT_E4_ROOMS:
		if str(center_label) != str(room[0]):
			print("[playthrough] gauntlet: expected %s, on %s" % [room[0], center_label])
			return false
		heal_party()                                       # full HP + PP going in, as a player would
		if not await _pt_fight_trainer(room[1], 12000):
			print("[playthrough] gauntlet: lost to %s (now on %s @%s)" % [
				str(room[0]).replace("sRoom", ""), center_label, str(player.cell)])
			return false                                   # lost — whited out to the lobby
		print("[playthrough] MILESTONE beat %s (lead L%d)" % [str(room[0]).replace("sRoom", ""),
			int(player_party[0]["level"])])
		# The exit unseals the instant its owner falls (on_battle_end re-runs the room's load callback).
		if not await _pt_walk_dungeon(room[2], 3000, false, true) or str(center_label) == str(room[0]):
			print("[playthrough] gauntlet: stuck leaving %s at %s" % [room[0], str(player.cell)])
			return false
	# LANCE's stairs land us in the CHAMPION's room, whose entry script marches us into the last battle.
	return str(center_label) == "ChampionsRoom" and await _pt_beat_champion()


## The Champion's room drives itself: the entry walk, his speech, OPP_RIVAL3, then Oak's congratulations
## and the Hall of Fame. All the bot does is win the battle and keep the text moving. False on a whiteout.
func _pt_beat_champion() -> bool:
	for _i in 30000:
		if has_event("BEAT_CHAMPION"):
			return true
		if modal == battle:
			await _pt_win_battle()
			await _drive_until(func() -> bool: return modal == null, 400)
			continue
		if str(center_label) != "ChampionsRoom" and modal == null and not cutscene_active:
			return false                                   # whited out to the lobby
		if textbox.active and textbox.visible:
			textbox.advance()
		await get_tree().process_frame
	return has_event("BEAT_CHAMPION")


## Answer quiz `idx` (gate `idx+1`). The machine is a wall panel: stand below it, face UP, press A. The
## right answer is the one the engine's own `HIDDEN_EVENTS` row carries, so this reads the table rather
## than duplicating six booleans. A wrong answer would start the room's trainer — the loop below wins that
## too, so a mis-answer costs a fight, not the run.
func _pt_answer_quiz(idx: int) -> bool:
	var gate: int = idx + 1
	var ev := "CINNABAR_GATE_%d" % gate
	if has_event(ev):
		return true                                        # already answered (resumed / retry)
	var stand: Vector2i = _PT_CINNABAR_QUIZ[idx]
	if not await _pt_walk_dungeon(stand, 4000, false, true) or player.cell != stand:
		return false
	player.facing = 1                                      # UP, at the quiz machine
	interact(player)
	var want := _pt_quiz_answer(gate)
	var answered := false
	for _i in 2000:
		if has_event(ev) and modal == null and not cutscene_active:
			return true
		if modal == battle:
			await _pt_win_battle()                         # a wrong call: the room's trainer jumps us
			await _drive_until(func() -> bool: return modal == null, 400)
		elif modal == menu and not answered:
			menu.chosen.emit(0 if want else 1)             # YES / NO
			answered = true
		elif textbox.active and textbox.visible:
			textbox.advance()
		elif answered and modal == null and not cutscene_active:
			break
		await get_tree().process_frame
	return has_event(ev)


## The correct YES/NO for a Cinnabar quiz gate, read off the same HIDDEN_EVENTS row the engine fires from.
func _pt_quiz_answer(gate: int) -> bool:
	for h in HIDDEN_EVENTS.get("CinnabarGym", []):
		if str(h.get("kind", "")) == "quiz" and int(h.get("gate", 0)) == gate:
			return bool(h.get("yes", true))
	return true


## Out of the Mansion, key in hand. The switch state that opens the SECRET KEY's room shuts the way back,
## and **1F's southern half cannot reach 1F's own switch panel** — the panel is across the floor, behind
## the wall you fell over. Its only exit is the south-east back door, which needs the switch ON. So the
## way out is: up to 1F; if the back door is shut, duck back down to B1F, flip a switch there, and come
## up again. Bounded at four rounds.
func _pt_mansion_exit() -> bool:
	for _round in 4:
		if str(center_label) == "PokemonMansionB1F":
			# 1F's back door needs the switch ON, so leave B1F with it on — and B1F's staircase is only
			# reachable in that state from its *south* panel, which `_pt_mansion_flip_for` finds.
			if not has_event("MANSION_SWITCH_ON") and not await _pt_mansion_flip_for(Vector2i(23, 22)):
				return false
			if not await _pt_mansion_walk_to(Vector2i(23, 22)) or str(center_label) != "PokemonMansion1F":
				return false
		if str(center_label) != "PokemonMansion1F":
			return false
		if await _pt_mansion_walk_to(Vector2i(26, 27)) and str(center_label) == "CinnabarIsland":
			return true
		if str(center_label) != "PokemonMansion1F":
			return false                                   # ended up somewhere unexpected
		if not await _pt_walk_dungeon(Vector2i(21, 23), 4000, false, true) \
				or str(center_label) != "PokemonMansionB1F":
			return false                                   # can't even get back downstairs
	return false


## The cell you press each Mansion floor's switch from — one below its wall panel (gh #83).
const _PT_MANSION_PANELS := {
	"PokemonMansion1F": [Vector2i(2, 6)], "PokemonMansion2F": [Vector2i(2, 12)],
	"PokemonMansion3F": [Vector2i(10, 6)],
	"PokemonMansionB1F": [Vector2i(18, 26), Vector2i(20, 4)]}


## Walk to `goal` on a Mansion floor, flipping a switch whenever the way is shut. The switch-doors are
## laid from one global flag, so a floor's layout has two shapes and the room you are standing in may only
## connect to the goal in the other one — which is exactly how the puzzle works, and why the way *out* of
## the SECRET KEY's room is not the way in. Bounded: at most one flip per attempt, four attempts. Returns
## true on arrival, or if a step crossed a warp (the goal is usually a staircase).
func _pt_mansion_walk_to(goal: Vector2i, budget := 4000) -> bool:
	var start_map := str(center_label)
	for _attempt in 4:
		if await _pt_walk_dungeon(goal, budget, false, true):
			return true
		if str(center_label) != start_map:
			return true                                    # a flip's walk crossed a staircase
		if not await _pt_mansion_flip_for(goal):
			return false                                   # nothing left to try
	return str(center_label) != start_map


## Flip a switch that actually opens the way to `goal`. The floor's panels are **not interchangeable** —
## B1F's north panel (20,3) seals B1F's own staircase, so the flip that gets you back out is the south one
## — and the flag is global, so a press that doesn't help must be pressed straight back before trying the
## next. That is what a player does: press, look, press it back. Returns false if none opens the way.
func _pt_mansion_flip_for(goal: Vector2i) -> bool:
	for stand in _PT_MANSION_PANELS.get(str(center_label), []):
		if not (_pt_on_center(stand) and player_can_enter(stand)):
			continue
		if player.cell != stand and _pt_plan(player.cell, stand, true).is_empty():
			continue
		if not await _pt_mansion_press(stand):
			continue
		if player.cell == goal or not _pt_plan(player.cell, goal, true).is_empty():
			return true
		await _pt_mansion_press(stand)                     # didn't help — put it back, try the next panel
	return false


## Press a Mansion switch. It is a wall panel (gh #83): walk to the cell below it and press A facing UP.
## The flag is global, so each press toggles it — the way in presses them in a fixed order, not a set.
func _pt_mansion_switch(which: String) -> bool:
	return await _pt_mansion_press(_PT_MANSION_SWITCHES[which])


func _pt_mansion_press(stand: Vector2i) -> bool:
	var was := has_event("MANSION_SWITCH_ON")
	if not await _pt_walk_dungeon(stand, 4000, false, true) or player.cell != stand:
		return false
	player.facing = 1                                      # UP, at the panel
	interact(player)
	await _drive_until(func() -> bool: return has_event("MANSION_SWITCH_ON") != was \
		and modal == null and not cutscene_active, 400)
	if has_event("MANSION_SWITCH_ON") == was:
		return false                                       # the panel never took the press
	print("[playthrough] flipped the Mansion switch at %s on %s (now %s)" % [
		str(stand), center_label, "ON" if has_event("MANSION_SWITCH_ON") else "OFF"])
	return true


## Ride the pad chain from SABRINA's room back to the gym door and out to Saffron. The `sabrina`
## checkpoint ends in her room, and the nine rooms are joined only by pads — `_pt_warp_out` alone can
## never walk to the door (gh #76 seam). Derived on the map's own warp table, which is **directed**:
## the way out is not the way in reversed. These are the pads to STEP ON, each walked to from where
## the previous one dropped us: (11,11)→lands(1,5), (1,3)→(15,5), (19,3)→(15,15), (19,17)→(11,15).
## (11,15)'s room is the only one holding the door mats (8,17)/(9,17), so _pt_warp_out finishes.
const _PT_SABRINA_EXIT_PADS := [Vector2i(11, 11), Vector2i(1, 3), Vector2i(19, 3), Vector2i(19, 17)]


func _pt_saffron_gym_exit() -> bool:
	if str(center_label) != "SaffronGym":
		return true
	for pad in _PT_SABRINA_EXIT_PADS:
		if not await _pt_take_pad(pad):
			print("[playthrough] Saffron Gym exit: could not take the pad at %s (on %s @%s)" % [
				str(pad), center_label, str(player.cell)])
			return false
	return await _pt_warp_out("SaffronCity")


## Ride the pad chain from the gym door into SABRINA's room. True once we are standing on (11,11).
func _pt_sabrina_room() -> bool:
	if player.cell == Vector2i(11, 11):
		return true                                        # already inside (retry after a dialogue bail)
	for pad in _PT_SABRINA_PADS:
		if not await _pt_take_pad(pad):
			print("[playthrough] Saffron Gym: could not take the pad at %s (on %s @%s)" % [
				str(pad), center_label, str(player.cell)])
			return false
	return player.cell == Vector2i(11, 11)


## Step onto `pad` and ride it. A Saffron Gym pad warps *within* the map, so no map change fires: walk to
## a cell beside it, step on, and confirm we arrived where the map's own warp table says. Reading the
## landing off `map["warps"]` rather than a second table keeps the two from drifting apart.
func _pt_take_pad(pad: Vector2i) -> bool:
	var w = _warp_at(pad)
	if w == null:
		return false
	var t: Dictionary = map["warps"][int(w["dest_warp"]) - 1]
	var landing := Vector2i(int(t["x"]), int(t["y"]))
	for d in 4:
		var stand: Vector2i = pad + DIRV4[d]
		if not (_pt_on_center(stand) and player_can_enter(stand)):
			continue
		if player.cell != stand:
			if _pt_plan(player.cell, stand, true).is_empty():
				continue                                   # avoid_warps: never trip a neighbouring pad
			if not await _pt_walk_dungeon(stand, 3000, false, true) or player.cell != stand:
				continue
		await _pt_step(d ^ 1)                              # step onto the pad — the warp fires on the step
		await _drive_until(func() -> bool: return player.cell == landing, 300)
		if player.cell == landing:
			return true
	return false


## Fuchsia -> Lavender on foot: the mirror of the `snorlax` walk down. Route 15's gate again (west door
## in, east out), then Routes 14/13 north — leaving Route 14 by row 8, since row 6 is the BIRD KEEPER
## pocket — and Route 12 up through its gate to Lavender. The SNORLAX is already gone by now.
func _pt_fuchsia_to_lavender() -> bool:
	if str(center_label) == "LavenderTown":
		return true
	if str(center_label) != "FuchsiaCity" and not await _pt_warp_out("FuchsiaCity"):
		return false
	heal_party()
	respawn_map = "FuchsiaPokecenter"
	if not await _pt_hop(3, "Route15"):
		return false
	if not await _pt_warp_via(Vector2i(7, 8), "Route15Gate1F"):
		return false
	if not await _pt_warp_via(Vector2i(7, 4), "Route15", "Route15"):
		return false
	if not await _pt_hop(3, "Route14"):
		return false
	if not await _pt_hop(3, "Route13", 8):                 # leave Route 14 by row 8, not the row-6 pocket
		return false
	if not await _pt_hop(1, "Route12", 50):                # north into Route 12 at x=50/51
		return false
	if not await _pt_warp_via(Vector2i(10, 21), "Route12Gate1F"):
		return false
	if not await _pt_warp_via(Vector2i(4, 0), "Route12", "Route12"):
		return false
	return await _pt_hop(1, "LavenderTown")


## The Saffron guards' drink comes from the Celadon Mart's rooftop vending machines (CeladonMartRoof
## bg_events at (10,1)/(11,1)/(12,2)) — five flights up and back. The stairs alternate sides per floor.
const _PT_MART_UP := [["CeladonMart1F", Vector2i(12, 1)], ["CeladonMart2F", Vector2i(16, 1)],
	["CeladonMart3F", Vector2i(12, 1)], ["CeladonMart4F", Vector2i(16, 1)],
	["CeladonMart5F", Vector2i(12, 1)]]
const _PT_MART_DOWN := [["CeladonMartRoof", Vector2i(15, 2)], ["CeladonMart5F", Vector2i(16, 1)],
	["CeladonMart4F", Vector2i(12, 1)], ["CeladonMart3F", Vector2i(16, 1)],
	["CeladonMart2F", Vector2i(12, 1)]]
const _PT_DRINKS := ["FRESH WATER", "SODA POP", "LEMONADE"]


func _pt_have_drink() -> bool:
	for d in _PT_DRINKS:
		if player_bag.has(d):
			return true
	return false


func _pt_buy_drink() -> bool:
	if _pt_have_drink():
		return true
	if str(center_label) != "CeladonCity" and not await _pt_warp_out("CeladonCity"):
		return false
	if not await _pt_warp_out("CeladonMart1F", true):
		return false
	if not await _pt_stair_chain(_PT_MART_UP) or str(center_label) != "CeladonMartRoof":
		return false
	if not await _pt_interact_from(Vector2i(10, 2), 1):    # face the vending machine at (10,1)
		return false
	# _vending_buy reopens the machine for another can, so the menu has to be cancelled out of or the
	# modal never clears and every later walk stalls waiting on it.
	var bought := false
	for _i in 900:
		await get_tree().process_frame
		if _pt_have_drink() and modal == null and not cutscene_active:
			break
		if modal == menu:
			menu.chosen.emit(3 if bought else 0)           # FRESH WATER (¥200), then CANCEL
			bought = true
		elif textbox.active and textbox.visible:
			textbox.advance()
	if not _pt_have_drink() or modal != null:
		return false
	print("[playthrough] MILESTONE bought a drink for the Saffron guards")
	if not await _pt_stair_chain(_PT_MART_DOWN):
		return false
	return await _pt_warp_out("CeladonCity")


## Walk a chain of [floor, stairs cell] hops, one flight each. avoid_warps keeps the walk off the
## floor's other doors (the Mart's elevator, its street exits).
func _pt_stair_chain(legs: Array) -> bool:
	for leg in legs:
		if str(center_label) != str(leg[0]):
			return false
		var before := str(center_label)
		if not await _pt_walk_to(leg[1], 1200, true):
			return false
		await _drive_until(func() -> bool: return str(center_label) != before, 400)
		if str(center_label) == before:
			return false
	return true


## --- SAFARI ZONE stage (gh #76): the park pays for both remaining field HMs. Pay the ¥500 fee, cross
## the Center into the West area for the SECRET HOUSE (HM03 SURF), take the GOLD TEETH (19,7) on the way
## back out, and trade them to the WARDEN in Fuchsia for HM04 (STRENGTH); then teach both. Encounters
## inside the park are BALL/BAIT/ROCK/RUN, so the bot just runs. Running out of the park's 500 steps only
## costs another ¥500 — the trip is resumable, so the stage pays again and finishes what it started. ---
func _pt_stage_safari() -> bool:
	if _mon_with_move("SURF") != "" and _mon_with_move("STRENGTH") != "":
		return true                                        # already done (resumed)
	if str(center_label) != "FuchsiaCity" and not await _pt_warp_out("FuchsiaCity"):
		return _pt_fail("reach Fuchsia for the Safari Zone (on %s)" % center_label)
	# This stage takes three new bag slots — HM03, the GOLD TEETH, HM04 — and by now the bag is full
	# of stones, fossils and gym TMs. A gift or a ball with no room is silently refused, so make room.
	if not _pt_bag_room(3):
		return _pt_fail("no bag room for HM03 + the GOLD TEETH + HM04 (bag %d/%d)" % [
			player_bag.size(), BAG_CAPACITY])
	for attempt in 3:
		if has_event("GOT_HM03") and (player_bag.has("GOLD TEETH") or has_event("GOT_HM04")):
			break
		if not await _pt_safari_trip():
			print("[playthrough] Safari trip %d cut short (on %s) — pay again and finish" % [
				attempt + 1, center_label])
		if not await _pt_safari_exit():                     # the park is a loop; retrace, don't warp
			return _pt_fail("back out of the Safari Zone (on %s @%s)" % [center_label, str(player.cell)])
	if not has_event("GOT_HM03"):
		return _pt_fail("HM03 (SURF) from the Safari secret house")
	if not (player_bag.has("GOLD TEETH") or has_event("GOT_HM04")):
		return _pt_fail("the GOLD TEETH in the Safari West area")
	print("[playthrough] MILESTONE left the Safari Zone with HM03 + the GOLD TEETH")
	# The WARDEN can't speak without his dentures; hand them over and he parts with HM04.
	if not has_event("GOT_HM04"):
		if not await _pt_warp_out("WardensHouse", true):
			return _pt_fail("enter the WARDEN's house")
		if not await _pt_talk_npc(Vector2i(2, 3), func() -> bool: return has_event("GOT_HM04")):
			return _pt_fail("trade the GOLD TEETH to the WARDEN")
		print("[playthrough] MILESTONE got HM04 (STRENGTH) from the WARDEN")
	if not await _pt_teach_hm("HM03", "SURF"):
		return _pt_fail("teach SURF to the party")
	if not await _pt_teach_hm("HM04", "STRENGTH"):
		return _pt_fail("teach STRENGTH to the party")
	print("[playthrough] MILESTONE taught SURF + STRENGTH — %s" % str(_pt_party_summary()))
	return true


## One paid trip into the park. The areas are a one-way-ish loop, not a hub (`--rtprobe`): from the
## Center's entrance only the **East** door is reachable, East reaches North, and North reaches West.
## The Center's own west door opens into a pocket that leads nowhere but back into West — so the way out
## is to retrace, not to take the nearest door. Every leg is guarded on what we already hold, so a trip
## cut short by the park's 500-step timer resumes where it left off. True only if we walk out with both.
const _PT_SAFARI_IN := [["SafariZoneCenter", Vector2i(29, 10), "SafariZoneEast"],
	["SafariZoneEast", Vector2i(0, 4), "SafariZoneNorth"],
	["SafariZoneNorth", Vector2i(2, 35), "SafariZoneWest"]]
const _PT_SAFARI_OUT := [["SafariZoneWest", Vector2i(20, 0), "SafariZoneNorth"],
	["SafariZoneNorth", Vector2i(39, 30), "SafariZoneEast"],
	["SafariZoneEast", Vector2i(0, 22), "SafariZoneCenter"],
	["SafariZoneCenter", Vector2i(14, 25), "SafariZoneGate"]]


func _pt_safari_trip() -> bool:
	if not await _pt_safari_enter():
		return false
	if not await _pt_safari_legs(_PT_SAFARI_IN):
		return false
	if not has_event("GOT_HM03"):
		if not await _pt_walk_to(Vector2i(3, 3), 1500, true) or str(center_label) != "SafariZoneSecretHouse":
			return false
		if not await _pt_interact_from(Vector2i(3, 4), 1):       # the guru at (3,3), face UP
			return false
		await _drive_until(func() -> bool: return has_event("GOT_HM03") and modal == null and not cutscene_active, 600)
		if not has_event("GOT_HM03"):
			return false
		print("[playthrough] MILESTONE reached the SECRET HOUSE — HM03 (SURF)")
		if not await _pt_warp_via(Vector2i(2, 7), "SafariZoneWest"):
			return false
	if not player_bag.has("GOLD TEETH") and not has_event("GOT_HM04"):
		if not await _pt_take_ball(Vector2i(19, 7), "GOLD TEETH"):
			return false
		print("[playthrough] MILESTONE found the WARDEN's GOLD TEETH")
	return await _pt_safari_exit()


## Retrace out of the park. It is a **loop, not a hub** — SafariZoneWest holds no door to Fuchsia — so a
## stage retry that just calls `_pt_warp_out("FuchsiaCity")` from inside hard-fails with a misleading
## message. Pick up the OUT chain at whichever area we are standing in, and re-look each time round: the
## 500-step timer can eject us to the gate mid-retrace, which is a shortcut, not a failure (gh #91).
func _pt_safari_exit() -> bool:
	for _i in 8:
		var here := str(center_label)
		if here == "FuchsiaCity":
			return true
		if here == "SafariZoneGate":
			return await _pt_warp_via(Vector2i(3, 5), "FuchsiaCity", "FuchsiaCity")
		var idx := -1
		for j in _PT_SAFARI_OUT.size():
			if str(_PT_SAFARI_OUT[j][0]) == here:
				idx = j
				break
		if idx >= 0:
			await _pt_safari_legs(_PT_SAFARI_OUT.slice(idx))   # a failed leg re-enters the loop above
			continue
		if here.begins_with("SafariZone"):                 # a rest house or the SECRET HOUSE: step outside
			var back := str((map["warps"][0] as Dictionary).get("dest_map", ""))   # each names its area
			if back == "" or not await _pt_warp_out(back):
				return false
			continue
		return await _pt_warp_out("FuchsiaCity")           # somehow already out of the park
	return str(center_label) == "FuchsiaCity"


## Walk a chain of [area, door cell, next area] hops. avoid_warps keeps the walk off the park's other
## doors (each area is a field of them, plus a rest house).
func _pt_safari_legs(legs: Array) -> bool:
	for leg in legs:
		if str(center_label) != str(leg[0]):
			return false
		if not await _pt_walk_to(leg[1], 2000, true):
			return false
		await _drive_until(func() -> bool: return str(center_label) == str(leg[2]), 400)
		if str(center_label) != str(leg[2]):
			return false
	return true


## Walk up to an overworld item ball and take it, keeping off every other warp on the way (a Safari area
## is a field of doors). Tries each side of the ball we can actually reach.
func _pt_take_ball(ball: Vector2i, want: String) -> bool:
	if player_bag.has(want):
		return true
	if not _pt_bag_room():                                      # else the ball stays on the floor
		print("[playthrough] no bag slot free for %s (bag %d/%d)" % [want, player_bag.size(), BAG_CAPACITY])
		return false
	for d in 4:
		var stand: Vector2i = ball + DIRV4[d]
		if not _pt_on_center(stand):
			continue
		if player.cell != stand:
			if _pt_plan(player.cell, stand, true).is_empty():
				continue
			if not await _pt_walk_to(stand, 1500, true) or player.cell != stand:
				continue
		player.facing = d ^ 1                                    # face back at the ball
		interact(player)
		await _drive_until(func() -> bool: return player_bag.has(want) and modal == null, 300)
		if player_bag.has(want):
			return true
	return player_bag.has(want)


## Into the park: the gate's north door charges ¥500 (SafariZoneGate.on_warp -> Cutscene.safari_gate),
## which is a yes/no the bot answers before the scripted warp drops it on the Center.
func _pt_safari_enter() -> bool:
	if in_safari:
		return true
	if str(center_label) != "SafariZoneGate" and not await _pt_warp_out("SafariZoneGate", true):
		return false
	if not await _pt_walk_to(Vector2i(3, 1)):
		return false
	await _pt_step(1)                                          # UP onto (3,0): the fee prompt fires
	for _i in 900:
		await get_tree().process_frame
		if str(center_label) == "SafariZoneCenter" and modal == null and not cutscene_active:
			return true
		if modal == menu:
			menu.chosen.emit(0)                                # YES, join the hunt
		elif textbox.active and textbox.visible:
			textbox.advance()
	return false


## --- KOGA stage (gh #76): the fifth badge. Fuchsia Gym is a maze of invisible walls — ordinary
## collision, so the guard-aware walk threads it — with six sight-trainers scattered through it and KOGA
## at (4,10). Winning takes the SOULBADGE, which is what lets SURF be used outside battle. ---
func _pt_stage_koga() -> bool:
	if has_event("BEAT_KOGA"):
		return true                                        # already done (resumed)
	if str(center_label) != "FuchsiaCity" and not await _pt_warp_out("FuchsiaCity"):
		return _pt_fail("reach Fuchsia for the gym (on %s)" % center_label)
	heal_party()
	respawn_map = "FuchsiaPokecenter"
	for attempt in 4:
		_pt_buy("SUPER POTION", 16)                        # the last attempt spent them (gh #94)
		# avoid_warps: Fuchsia's doors share a row, so a plain walk to the gym trips the Center's first.
		if str(center_label) != "FuchsiaGym" and not await _pt_warp_out("FuchsiaGym", true):
			return _pt_fail("enter Fuchsia Gym (on %s)" % center_label)
		if await _pt_talk_and_battle(Vector2i(4, 11), 1, "BEAT_KOGA"):   # KOGA @ (4,10), face UP
			break
		print("[playthrough] KOGA attempt %d lost (whited out to %s) — heal + retry" % [attempt + 1, center_label])
		heal_party()
		if str(center_label) != "FuchsiaCity" and not await _pt_warp_out("FuchsiaCity"):
			return _pt_fail("back to Fuchsia after a whiteout (on %s)" % center_label)
	if not has_event("BEAT_KOGA"):
		return _pt_fail("Fuchsia Gym / KOGA (all attempts)")
	print("[playthrough] MILESTONE beat KOGA — %s (lead L%d)" % [str(badges), int(player_party[0]["level"])])
	return true


## The SNORLAX asleep on Route 12 at (10,62). Stand north of it, play the flute (ItemUsePokeFlute ->
## Cutscene.wake_snorlax), and win the L30 battle; beating or catching it clears the road for good
## (BEAT_SNORLAX_Route12, then `_object_shown` hides it).
func _pt_wake_snorlax() -> bool:
	if has_event("BEAT_SNORLAX_Route12"):
		return true
	if not await _pt_walk_dungeon(Vector2i(10, 61), 4000) or player.cell != Vector2i(10, 61):
		return false
	player.facing = 0                                      # DOWN -> the SNORLAX at (10,62)
	selected_item = "POKé FLUTE"
	_use_poke_flute()
	for _i in 8000:
		if has_event("BEAT_SNORLAX_Route12") and modal == null and not cutscene_active:
			return true
		if modal == battle:
			await _pt_win_battle()
			await _drive_until(func() -> bool: return modal == null, 400)
			continue
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == null and not cutscene_active:
			break
		await get_tree().process_frame
	return has_event("BEAT_SNORLAX_Route12")


## Lavender -> Pokémon Tower 1F, up to 7F, and out through Mr. Fuji. Each floor's up-stairs alternate
## east/west (1F 18,9 · 2F 3,9 · 3F 18,9 · 4F 3,9 · 5F 18,9), and _pt_walk_dungeon clears the channelers
## that engage on sight. Two beats are unavoidable steps rather than doors: 2F's rival trigger (15,5) —
## the top corridor is the only link between the floor's halves — and 6F's MAROWAK coord trigger (10,16),
## the sole cell leading to the 7F stairs (PokemonTower6FMarowakCoords). 7F's three Rockets guard
## Mr. Fuji (10,3); talking to him warps us to his house. True once we're standing in it.
func _pt_climb_tower() -> bool:
	if str(center_label) != "LavenderTown" or not await _pt_warp_out("PokemonTower1F"):
		return false
	var stairs := [["PokemonTower1F", Vector2i(18, 9)], ["PokemonTower2F", Vector2i(3, 9)],
		["PokemonTower3F", Vector2i(18, 9)], ["PokemonTower4F", Vector2i(3, 9)],
		["PokemonTower5F", Vector2i(18, 9)]]
	for leg in stairs:
		if str(center_label) != leg[0]:
			return false
		var before := str(center_label)
		if not await _pt_walk_dungeon(leg[1], 4000):       # the 2F rival trips en route (on_step)
			return false
		await _drive_until(func() -> bool: return str(center_label) != before, 600)
	if str(center_label) != "PokemonTower6F":
		return false
	# Stepping onto (10,16) wakes the ghost; with the SILPH SCOPE it's a real MAROWAK battle, and the
	# stairs at (9,16) are behind it. _pt_walk_dungeon drives the fight, then we re-plan onto the stairs.
	if not await _pt_walk_dungeon(Vector2i(9, 16), 4000):
		return false
	if not has_event("BEAT_GHOST_MAROWAK"):
		return false                                       # walked past the ghost without laying it to rest
	print("[playthrough] MILESTONE laid the MAROWAK ghost to rest")
	await _drive_until(func() -> bool: return str(center_label) == "PokemonTower7F", 600)
	if str(center_label) != "PokemonTower7F":
		return false
	if not await _pt_walk_dungeon(Vector2i(10, 4), 4000):  # the three Rockets engage on sight en route
		return false
	player.facing = 1                                      # UP -> MR.FUJI at (10,3)
	interact(player)
	await _drive_until(func() -> bool: return str(center_label) == "MrFujisHouse" \
		and modal == null and not cutscene_active, 900)    # he warps us to his house
	return str(center_label) == "MrFujisHouse"


## Descend the Rocket Hideout B1F -> B2F -> B3F -> B4F to Giovanni's floor. Down-stairs: B1F (23,2),
## B2F (21,8), B3F (19,18); B2F/B3F are spin-tile mazes, so plan spin-aware there. Rocket grunts are
## fought en route by _pt_walk_dungeon. Returns true once on B4F.
func _pt_hideout_descend() -> bool:
	var route := [["RocketHideoutB1F", Vector2i(23, 2), false], ["RocketHideoutB2F", Vector2i(21, 8), true],
		["RocketHideoutB3F", Vector2i(19, 18), true]]
	for leg in route:
		if str(center_label) != leg[0]:
			return false
		var before := str(center_label)
		if not await _pt_walk_dungeon(leg[1], 4000, bool(leg[2])):
			return false
		await _drive_until(func() -> bool: return str(center_label) != before, 400)
	return str(center_label) == "RocketHideoutB4F"


## Rocket Hideout B4F, the Giovanni floor. It is two disconnected regions (--rtprobe): the B3F stairs
## (19,10) drop into the west one, which holds Rocket 3 (11,2) and the LIFT KEY he drops (10,2);
## Giovanni (25,3), the SILPH SCOPE (25,2), his two door grunts (23,12)/(26,12) and the elevator
## (24,15)/(25,15) all sit in the east one. Nothing walks between them — the only crossing is the
## LIFT-KEY elevator, so the leg is: take the key here, climb out, ride back down into Giovanni's half.
func _pt_hideout_b4f() -> bool:
	if player_bag.has("SILPH SCOPE"):
		return true                                        # already done (resumed)
	if not player_bag.has("LIFT KEY") and not await _pt_hideout_lift_key():
		return false
	print("[playthrough] MILESTONE got the LIFT KEY")
	if not await _pt_hideout_ride_to_b4f():
		return false
	print("[playthrough] MILESTONE rode the elevator into Giovanni's B4F wing")
	heal_party()                                           # a real player heals before the boss wing
	# The two door grunts have view range 0, so no amount of walking past engages them — pokered wants
	# them talked to (TalkToTrainer). Beating the second one swings the door open (EndTrainerBattle).
	for grunt in [Vector2i(23, 12), Vector2i(26, 12)]:
		if not await _pt_fight_trainer(grunt):
			return false
	if not is_walkable(Vector2i(24, 11)):
		return false                                       # the guard door never opened
	if not await _pt_talk_and_battle(Vector2i(24, 3), 3, "BEAT_ROCKET_HIDEOUT_GIOVANNI"):  # Giovanni @ (25,3)
		return false
	print("[playthrough] MILESTONE beat Giovanni (Rocket Hideout)")
	await _pt_interact_from(Vector2i(25, 3), 1)            # his vacated cell, face up -> SILPH SCOPE ball (25,2)
	await _drive_until(func() -> bool: return player_bag.has("SILPH SCOPE") and modal == null, 300)
	return player_bag.has("SILPH SCOPE")


## B4F's west region: Rocket 3 guards the LIFT KEY. Beat him (his view range trips as we approach),
## then talk to him again — his after-battle line is what drops the ball (ShowObject ITEM_5) — and
## take it from below.
func _pt_hideout_lift_key() -> bool:
	if not await _pt_fight_trainer(Vector2i(11, 2)):
		return false
	var dropped := func() -> bool: return has_event("ROCKET_DROPPED_LIFT_KEY")
	if not dropped.call() and not await _pt_talk_npc(Vector2i(11, 2), dropped):
		return false
	await _pt_interact_from(Vector2i(10, 3), 1)            # face UP -> the LIFT KEY ball at (10,2)
	await _drive_until(func() -> bool: return player_bag.has("LIFT KEY") and modal == null, 300)
	return player_bag.has("LIFT KEY")


## Climb B4F -> B3F -> B2F, ride the LIFT-KEY elevator, and step out into Giovanni's wing at (25,15).
## B2F is the boarding floor: B1F's elevator door sits behind its own guard door, and B3F has no
## elevator at all (RocketHideoutElevatorFloors is B1F/B2F/B4F). Up-stairs: B4F (19,10), B3F (25,6).
func _pt_hideout_ride_to_b4f() -> bool:
	for leg in [["RocketHideoutB4F", Vector2i(19, 10), false], ["RocketHideoutB3F", Vector2i(25, 6), true]]:
		if str(center_label) != leg[0]:
			return false
		var before := str(center_label)
		if not await _pt_walk_dungeon(leg[1], 4000, bool(leg[2])):   # B3F is a spin-tile maze
			return false
		await _drive_until(func() -> bool: return str(center_label) != before, 400)
	if str(center_label) != "RocketHideoutB2F":
		return false
	if not await _pt_walk_dungeon(Vector2i(24, 19), 4000, true):     # B2F's elevator door
		return false
	if not await _pt_ride_elevator("RocketHideoutElevator", _PT_LIFT_B4F, "RocketHideoutB4F"):
		return false
	# The door mat at (25,15) auto-steps the player off it on arrival (gh #142), so the landing
	# cell is the mat or the cell below it.
	return player.cell in [Vector2i(25, 15), Vector2i(25, 16)]


## The LIFT-KEY panel's floor list (RocketHideoutElevatorFloors) — B3F has no elevator.
const _PT_LIFT_B2F := 1
const _PT_LIFT_B4F := 2

## Each elevator car, as the bot has to work it: the map, the cell to stand on and the direction to
## face to reach its panel, and the door mat a warp drops us on. The hideout car's door mats fire
## on step and the gh #142 arrival auto-step leaves them ARMED, so the panel must be worked from
## the car floor — (1,2) facing UP, the only approach a real player has — never from atop a mat.
const _PT_ELEVATORS := {
	"RocketHideoutElevator": {"stand": Vector2i(1, 2), "face": 1, "mat": Vector2i(2, 1)},
	"SilphCoElevator": {"stand": Vector2i(3, 1), "face": 1, "mat": Vector2i(1, 3)},
}


## Ride an elevator, having just stepped onto a door mat that led into the car. Work its panel to pick
## a floor, then walk back onto a door mat. Arriving by warp leaves `warp_armed` false, so the mat we
## landed on is inert until we leave it — which is why a car whose panel *is* the mat has to step off
## first. True once on dest_map.
func _pt_ride_elevator(car: String, floor_idx: int, dest_map: String) -> bool:
	await _drive_until(func() -> bool: return str(center_label) == car, 400)
	if str(center_label) != car:
		return false
	var cfg: Dictionary = _PT_ELEVATORS[car]
	if not await _pt_interact_from(cfg["stand"], int(cfg["face"])):
		return false
	var picked := false
	for _i in 900:
		await get_tree().process_frame
		if modal == menu and not picked:
			menu.chosen.emit(floor_idx)                              # ...then the car shakes
			picked = true
		elif picked and modal == null and not cutscene_active:
			break
	if not picked or str(map["warps"][0].get("dest_map", "")) != dest_map:
		return false                                                 # the panel never retargeted the doors
	if player.cell == cfg["mat"] and not await _pt_step(0):          # step off so the mat re-arms
		return false
	await _pt_walk_dungeon(cfg["mat"])
	# The mat is an edge warp that fires only for the right facing (gh #80): Silph Co's exit is a bottom
	# edge (face DOWN), but the walk to it can arrive facing sideways. Turn to the facing that fires it.
	if str(center_label) == car and warp_armed and _warp_at(player.cell) != null:
		for dir in 4:
			if _warp_should_fire(player.cell, dir):
				await _pt_step(dir)
				break
	await _drive_until(func() -> bool: return str(center_label) == dest_map, 600)
	return str(center_label) == dest_map


## The map trainer whose spawn (home) cell is `home` — found by home, so it still resolves after the
## trainer has marched off its tile to intercept us.
func _pt_npc_home(home: Vector2i) -> Variant:
	for n in npcs:
		if n.home == home:
			return n
	return null


## Walk up to that trainer, talk, and drive whatever follows (a battle, or its after-battle line),
## until `done` holds. Trainers with view range 0 — the B4F door grunts — can only be started this
## way; a sight walk-in never engages them. Tries each side of the trainer we can actually reach.
func _pt_talk_npc(home: Vector2i, done: Callable, budget := 8000) -> bool:
	var here := str(center_label)
	for _attempt in 4:
		if done.call():
			return true
		var npc = _pt_npc_home(home)
		if npc == null or not npc.shown:
			return false
		var talked := false
		for d in 4:
			var stand: Vector2i = npc.cell + DIRV4[d]
			if not _pt_on_center(stand):
				continue
			if player.cell != stand:
				if _pt_plan(player.cell, stand).is_empty():
					continue
				if not await _pt_walk_dungeon(stand):
					if str(center_label) != here:
						return false                     # whited out on the way
					continue
				if str(center_label) != here:
					return false
				if player.cell != stand:
					continue
			player.facing = d ^ 1                        # face back at the trainer (0<->1, 2<->3)
			interact(player)
			talked = true
			break
		if not talked:
			return done.call()                           # its sight may have settled this mid-walk
		match await _pt_drive_talk(done, here, budget):
			_PtTalk.DONE:
				return true
			_PtTalk.WHITEOUT:
				return false                             # whited out — the battle was lost
			_:
				pass                                     # dialogue ended — re-approach and try again
	return done.call()


## Talk a map trainer into a battle and win it, keyed by its home cell (trainer_id).
func _pt_fight_trainer(home: Vector2i, budget := 8000) -> bool:
	var npc = _pt_npc_home(home)
	if npc == null:
		return false
	var tid := trainer_id(npc)
	return await _pt_talk_npc(home, func() -> bool: return defeated_trainers.has(tid), budget)


## Route 4 -> Cerulean City. Try the open route east first; if the Mt. Moon cliff blocks it, go
## through the mountain and cross east from its far side.
func _pt_reach_cerulean() -> bool:
	if str(center_label) == "CeruleanCity":
		return true
	await _pt_cross(3)                                  # try the open route east first
	if str(center_label) == "CeruleanCity":
		return true
	if str(center_label) != "Route4":
		return false                                    # crossed somewhere unexpected
	if not await _pt_traverse_mtmoon():                 # the cliff blocks east — go through Mt. Moon
		return false
	print("[playthrough] MILESTONE cleared Mt. Moon -> %s @%s" % [center_label, str(player.cell)])
	await _pt_cross(3)                                  # from Mt. Moon's east exit onto Cerulean
	return str(center_label) == "CeruleanCity"


## Mt. Moon is a maze of ladders between 1F/B1F/B2F: the Route 4 *west* entrance (MtMoon1F @14,35) and the
## far exit that drops back onto Route 4 *east* of a cliff (MtMoonB1F @27,3 → LAST_MAP) are on opposite
## sides, so you wind through. Its `cavern` elevation ledges (`TilePairCollisions`, gh #105) fracture B1F/B2F
## into ladder-linked pockets — you can SEE across a ledge but not step it — so the route is fixed by which
## ladder lands in which pocket, not by open connectivity (mapped with `--tpprobe`). Team Rocket grunts
## stand in the corridors — a sight-trainer marches off its tile to intercept — so `_pt_walk_dungeon` commits
## toward each ladder (planning through NPCs when needed) to trigger and clear them. The faithful legs, each
## `[map, ladder]` landing in the next pocket: 1F@5,5→B1F@5,5 ; B1F@21,17→B2F@21,17 (the fossil area) ;
## B2F@5,7→B1F@23,3 ; B1F@27,3→Route 4 east.
func _pt_traverse_mtmoon() -> bool:
	if not await _pt_warp_out("MtMoon1F"):
		print("[playthrough] mtmoon: could not enter MtMoon1F from %s @%s" % [center_label, str(player.cell)])
		return false
	var route := [["MtMoon1F", Vector2i(5, 5)], ["MtMoonB1F", Vector2i(21, 17)],
		["MtMoonB2F", Vector2i(5, 7)], ["MtMoonB1F", Vector2i(27, 3)]]
	for leg in route:
		var want: String = leg[0]
		var ladder: Vector2i = leg[1]
		if str(center_label) != want:
			print("[playthrough] mtmoon: expected %s, on %s @%s" % [want, center_label, str(player.cell)])
			return false
		# B2F's exit-side ladder (@5,7) sits behind the two fossils: the room is walled off except
		# through their tiles, so take a fossil first — that hides BOTH (MtMoonB2F.asm) and opens the way.
		if want == "MtMoonB2F" and not await _pt_mtmoon_take_fossil():
			print("[playthrough] mtmoon: could not take a fossil on B2F @%s" % str(player.cell))
			return false
		print("[playthrough] mtmoon: on %s @%s -> ladder %s" % [center_label, str(player.cell), str(ladder)])
		var before := str(center_label)
		# avoid_warps: several ladders share a floor, and the tile-pair pockets mean the *wrong* ladder is
		# often on the way to the right one (walking 1F@14,35 -> @5,5 would otherwise trip @17,11). Route to
		# the goal ladder without stepping on any other warp; the goal itself is exempt and fires on arrival.
		if not await _pt_walk_dungeon(ladder, 3000, false, true):
			print("[playthrough] mtmoon: stuck reaching %s on %s @%s" % [str(ladder), center_label, str(player.cell)])
			return false
		if str(center_label) == before:                    # reached the tile but the warp didn't fire — nudge
			await _pt_step(0)
			await _pt_walk_dungeon(ladder, 3000, false, true)
		await _drive_until(func() -> bool: return str(center_label) != before, 400)
	return str(center_label) == "Route4"


## Navigate a dungeon on foot using only NPC-aware paths (which route AROUND immovable objects — the
## fossils, the STAY Super Nerd — exactly as a real player does). When no NPC-free path to the ladder
## exists, something is blocking a corridor, and the walk clears it by kind (ADR-012): a Team Rocket
## grunt (walk into its sight line so it marches off its tile to fight us), an item ball parked in the
## way, or a locked Silph Co card-key door we hold the key to. Then re-plan. Repeats until the way
## opens or every clearable obstacle is spent (a genuine dead-end). Wild/guard battles en route are
## won. Returns true once a step fires a ladder (map change) or we reach `goal`.
## `avoid_warps` keeps the walk off every warp cell but the goal — needed on the Silph Co floors,
## where teleport pads are strewn across the open floor rather than tucked into doorways.
func _pt_walk_dungeon(goal: Vector2i, budget := 3000, spin_aware := false, avoid_warps := false) -> bool:
	var start_map := str(center_label)
	var stuck := 0
	var tried := {}                              # guards we've already walked out to trigger
	var taken := {}                              # item balls we've already cleared off the path
	var opened := {}                             # card-key doors we've already tried to open
	for _i in budget:
		if str(center_label) != start_map:
			return true                        # a step fired a ladder/warp
		if player.cell == goal:
			await _pt_settle()                 # every cave floor rolls encounters — don't return into one
			return true
		if modal == battle:
			await _pt_win_battle()
			await _drive_until(func() -> bool: return modal == null and not cutscene_active, 400)
			if not player_party.is_empty() and int(player_party[0]["hp"]) < int(player_party[0]["maxhp"]) / 3:
				heal_party()
			stuck = 0
			continue
		if modal != null or cutscene_active:
			await _drive_until(func() -> bool: return modal == null and not cutscene_active, 400)
			continue
		# spin_aware: on the Rocket Hideout spin-tile floors, model a step onto an arrow as landing on
		# its stop tile so the plan threads the spinner maze instead of getting flung around.
		var dirs := _pt_plan(player.cell, goal, avoid_warps, spin_aware)  # NPC-aware: never routes through an NPC
		if dirs.is_empty():
			if await _pt_trigger_guard(tried):               # clear a guard blocking the way, then re-plan
				stuck = 0
				continue
			if await _pt_take_blocking_item(taken, spin_aware):   # ...or an item ball parked in a corridor
				stuck = 0
				continue
			if await _pt_open_blocking_door(opened, spin_aware):  # ...or a card-key door we can open
				stuck = 0
				continue
			if str(center_label) != start_map:
				return true                                  # the detour crossed a warp after all
			_pt_report_blocked(goal, spin_aware)
			return false                                     # nothing left to clear
		if _pt_verbose:
			print("[dungeon] %s @%s -> %s dir=%s" % [center_label, str(player.cell), str(goal), _PT_DIR_NAME[int(dirs[0])]])
		if await _pt_step(int(dirs[0])):
			stuck = 0
		else:
			stuck += 1
			if stuck > 20:
				return false
	return str(center_label) != start_map


## Take a Mt. Moon B2F fossil to open the exit room (both fossils vanish when one is taken). Walk to a
## cell directly below a fossil (clearing any guards en route), face up, take it, answer YES.
func _pt_mtmoon_take_fossil() -> bool:
	if has_event("GOT_DOME_FOSSIL") or has_event("GOT_HELIX_FOSSIL"):
		return true
	# The SUPER NERD (12,8) guards the alcove: the only way up to the fossils crosses his engage tile
	# (13,8), which starts the fight (MtMoonB2F.gd / gh #107). Beat him before reaching for a fossil — the
	# bot can talk him into it from (12,9) below, which needs no step onto (13,8).
	if not defeated_trainers.has("MtMoonB2F:12,8"):
		if not await _pt_fight_trainer(Vector2i(12, 8)):
			return false
	for stand in [Vector2i(13, 7), Vector2i(12, 7)]:      # below HELIX (13,6) / DOME (12,6)
		if not await _pt_walk_dungeon(stand) or player.cell != stand:
			continue
		player.facing = 1                                 # UP, toward the fossil
		interact(player)
		for _i in 800:                                    # drive the "You want the FOSSIL?" YES flow
			if has_event("GOT_DOME_FOSSIL") or has_event("GOT_HELIX_FOSSIL"):
				return true
			if textbox.active and textbox.visible:
				textbox.advance()
			elif modal == menu:
				menu.chosen.emit(0)                       # YES
			elif modal == null and not cutscene_active:
				break
			await get_tree().process_frame
	return has_event("GOT_DOME_FOSSIL") or has_event("GOT_HELIX_FOSSIL")


## Of all the cells in `targets`, the one we can reach a neighbour of most cheaply, as
## `[stand_cell, facing, target_cell]` — or `[]` if none is reachable. Ranked by path length, since the
## bot only knows "no path", never which object is the articulation point (ADR-012).
## avoid_warps: never ride a ladder or a teleport pad on the way to an obstacle. spin_aware: an arrow
## tile slides us off, so on the spinner floors the plan has to model where a step actually lands.
func _pt_nearest_face(targets: Array, spin_aware: bool) -> Array:
	var best: Array = []
	var best_len := 1 << 30
	for target in targets:
		for d in 4:
			var stand: Vector2i = target + DIRV4[d]
			if not (_pt_on_center(stand) and player_can_enter(stand)):
				continue
			var path := _pt_plan(player.cell, stand, true, spin_aware)
			if player.cell != stand and path.is_empty():
				continue
			if path.size() < best_len:
				best_len = path.size()
				best = [stand, d ^ 1, target]        # d^1 faces back the way we came: at the target
	return best


## Walk to `pick`'s stand cell, face its target, and press A. False if we never arrived — a step may
## have tripped a warp, or a dynamic obstacle moved into the path. The caller checks what the
## interaction actually did.
func _pt_face_and_interact(pick: Array, spin_aware: bool) -> bool:
	var here := str(center_label)
	if not await _pt_walk_to(pick[0], 1500, true, spin_aware) or str(center_label) != here \
			or player.cell != pick[0]:
		return false
	player.facing = int(pick[1])
	interact(player)
	await _drive_until(func() -> bool: return modal == null and not cutscene_active, 400)
	return true


## An item ball is a solid sprite, so one dropped in a corridor is a door with an item for a key: Pokémon
## Tower 6F's RARE CANDY (6,8) sits on the single-tile passage to the whole southern half of the floor —
## the 7F stairs included — so a real player has to take it to get by. Walk to the nearest reachable ball,
## face it, and pick it up; `taken` stops us retrying one that didn't help. Ranked by path length rather
## than proven to be *the* blocker, so on a stuck floor we may collect a bystander ball first — bounded,
## and only ever on a leg that had no other move left. Returns true if a ball actually went away.
func _pt_take_blocking_item(taken: Dictionary, spin_aware := false) -> bool:
	var balls: Array = []
	for n in npcs:
		if n.shown and n.item != "" and not taken.has(n.key):
			balls.append(n.cell)
	var pick := _pt_nearest_face(balls, spin_aware)
	if pick.is_empty():
		return false
	var ball = _npc_at(pick[2])
	taken[str(ball.key)] = true
	_pt_bag_room()                                           # a full bag leaves the ball solid, and the
	if not await _pt_face_and_interact(pick, spin_aware):    # corridor it stands in stays shut (gh #91)
		return false
	if ball.shown:                                           # _pick_up_item refuses a full bag: ball stays solid
		print("[playthrough] could not take the %s at %s — no room in the bag" % [ball.item, str(ball.cell)])
		return false
	print("[playthrough] picked up the %s — it was standing in the way" % ball.item)
	return true


## The locked-door blocks each Silph Co floor lays on load (SilphCo*F.gd `place_silph_doors`, from the
## floors' GateCallbackScripts). None of these ids appears in any Silph floor's static `.blk`, and an
## opened door is overwritten with plain floor (0xE, or 0x3 on 11F) — so a block still carrying one of
## these ids is exactly a door nobody has unlocked. 1F-10F are the `facility` tileset (0x54 walls its
## top pair of cells, 0x5F its right pair); 11F is `interior` (0x20 walls its bottom pair).
const _PT_LOCKED_DOOR_BLOCKS := {"facility": [0x54, 0x5F], "interior": [0x20]}


## Block coords of every still-locked card-key door on the current floor — Silph Co only. Both tilesets
## dress maps with no card-key doors at all, and there the same ids mean something else: RocketHideoutB1F
## lays its grunt door as `facility` 0x54 (`RocketHideoutB1F.gd guard_door`), which the bot would
## otherwise mistake for a door its CARD KEY opens.
func _pt_locked_doors() -> Array:
	if not str(center_label).begins_with("SilphCo"):
		return []
	var ids: Array = _PT_LOCKED_DOOR_BLOCKS.get(str(map["tileset"]), [])
	var out: Array = []
	for by in map["blocks"].size():
		for bx in map["blocks"][by].size():
			if int(map["blocks"][by][bx]) in ids:
				out.append(Vector2i(bx, by))
	return out


## The third obstacle kind the dungeon walk can clear, alongside a sight-guard and an item ball
## (ADR-012): a card-key door we are holding the key to. Facing one opens it for good. Walks to the
## nearest cell from which a wall cell of a still-locked door can be faced, and opens it. Which of the
## block's four cells is the wall differs per floor, so we read it off the collision rather than assume.
## `opened` stops us retrying a door that didn't help. Returns true if a door actually opened.
func _pt_open_blocking_door(opened: Dictionary, spin_aware := false) -> bool:
	var here := str(center_label)
	if not player_bag.has("CARD KEY"):
		return false
	var walls := {}                                          # wall cell -> the door block it belongs to
	for b in _pt_locked_doors():
		if opened.has(b):
			continue
		for cy in range(b.y * 2, b.y * 2 + 2):
			for cx in range(b.x * 2, b.x * 2 + 2):
				if not is_walkable(Vector2i(cx, cy)):        # the block's other cells are its open half
					walls[Vector2i(cx, cy)] = b
	var pick := _pt_nearest_face(walls.keys(), spin_aware)
	if pick.is_empty():
		return false
	var door: Vector2i = walls[pick[2]]
	opened[door] = true
	if not await _pt_face_and_interact(pick, spin_aware):
		return false
	if door in _pt_locked_doors():
		return false                                         # still locked — the CARD KEY was refused
	print("[playthrough] the CARD KEY opened the door at block %s on %s" % [str(door), here])
	return true


## No NPC-free path to `goal` and nothing left to clear — say why, so a failing leg names the thing in
## the way instead of just a cell (gh #76). An NPC that the collision-only flood would walk through is a
## blocker: a stationary trainer, or an item ball nobody picked up. So is a still-locked card-key door.
func _pt_report_blocked(goal: Vector2i, spin_aware: bool) -> void:
	var no_path := _pt_plan(player.cell, goal, false, spin_aware).is_empty()
	var standing: Array = []
	for n in npcs:
		if n.shown and n.cell != player.cell:
			standing.append("%s@%s%s" % [n.key, str(n.cell), " (item)" if n.item != "" else ""])
	print("[dungeon] BLOCKED on %s @%s -> %s (no npc-free path=%s); standing objects: %s; locked doors: %s" % [
		center_label, str(player.cell), str(goal), no_path, str(standing), str(_pt_locked_doors())])


## Find an undefeated sight-trainer whose view line we can reach, walk into it (the step trips its
## sight → it marches up and battles → its home tile frees), and win. `tried` records attempts so we
## don't loop on a guard that couldn't be reached/triggered. Returns true if we engaged one. Tries the
## nearest reachable sight cell across all guards, so guards gate-blocking each other clear in order.
func _pt_trigger_guard(tried: Dictionary) -> bool:
	var best_cell := Vector2i(-1, -1)
	var best_tid := ""
	var best_len := 1 << 30
	for n in npcs:
		if not n.shown or n.trainer_class == "" or n.sight <= 0:
			continue
		var tid: String = trainer_id(n)
		if defeated_trainers.has(tid) or tried.has(tid):
			continue
		for k in range(1, n.sight + 1):
			var sc: Vector2i = n.cell + DIRV4[n.facing] * k          # a cell in the guard's view line
			if not (_pt_on_center(sc) and player_can_enter(sc)):
				continue
			var path := _pt_plan(player.cell, sc)
			if (player.cell == sc or not path.is_empty()) and path.size() < best_len:
				best_len = path.size()
				best_cell = sc
				best_tid = tid
	if best_cell.x < 0:
		return false
	tried[best_tid] = true                                           # only the guard we're going for
	await _pt_walk_to(best_cell)                                     # stepping into the line trips the sight
	await _drive_until(func() -> bool: return modal == null and not cutscene_active, 800)
	return true


## Drive dialogue/tweens until `done_check` returns true (or a frame budget runs out). Advances
## the textbox each frame; returns the iteration count taken (for diagnostics).
func _drive_until(done_check: Callable, budget := 4000) -> int:
	for i in budget:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		if done_check.call():
			return i
	return budget


func _parceltest() -> void:
	await get_tree().process_frame
	player_name = "RED"
	rival_name = "BLUE"
	player_starter = "squirtle"

	# Phase 0: Viridian City road-north gate is blocked before the Pokédex.
	story_events = {"GOT_STARTER": true}
	player_party = [make_mon("squirtle", 5, [])]
	load_world("ViridianCity")
	player.place(Vector2i(19, 9)); player.facing = 1
	_on_player_moved(Vector2i(19, 9))
	var gate_fired: bool = modal == textbox or cutscene_active
	await _drive_until(func() -> bool: return not cutscene_active and modal == null, 600)
	var pushed_back: bool = player.cell == Vector2i(19, 10)
	print("[parceltest] gate(no dex): fired=%s pushed_back=%s cell=%s" % [gate_fired, pushed_back, str(player.cell)])

	# Phase 1: Viridian Mart hands over OAK's PARCEL.
	load_world("ViridianMart")
	await _drive_until(func() -> bool: return has_event("GOT_OAKS_PARCEL") and not cutscene_active and modal == null)
	var got_parcel := player_bag.has("OAK's PARCEL") and has_event("GOT_OAKS_PARCEL")
	print("[parceltest] mart: got_parcel=%s bag=%s player_cell=%s" % [got_parcel, str(player_bag.keys()), str(player.cell)])

	# Phase 2: deliver to Oak in the lab -> Pokédex receipt.
	story_events["FOLLOWED_OAK_INTO_LAB"] = true
	story_events["FOLLOWED_OAK_INTO_LAB_2"] = true
	story_events["BEAT_RIVAL1"] = true
	story_events["RIVAL_LEFT_LAB"] = true
	load_world("OaksLab")
	player.place(Vector2i(5, 3)); player.facing = 1   # face UP -> Oak at (5,2)
	var dex1 = _npc_by_key("SPRITE_POKEDEX@2,1")
	var dex_on_shelf: bool = dex1 != null and dex1.shown
	interact(player)
	await _drive_until(func() -> bool: return has_event("GOT_POKEDEX") and not cutscene_active and modal == null)
	var rival = _npc_by_key("SPRITE_BLUE@4,3")
	print("[parceltest] deliver: oak_got_parcel=%s got_pokedex=%s rival_got_dex=%s parcel_gone=%s dex_shelf_before=%s dex_hidden_after=%s rival_hidden=%s" % [
		has_event("OAK_GOT_PARCEL"), has_event("GOT_POKEDEX"), has_event("RIVAL_GOT_POKEDEX"),
		not player_bag.has("OAK's PARCEL"), dex_on_shelf,
		dex1 != null and not dex1.shown, rival != null and not rival.shown])
	print("[parceltest] oak line now: '%s'" % map_script("OaksLab")._oak_text().replace("\n", " "))

	# Phase 3: with the Pokédex, the Viridian gate lets the player through.
	load_world("ViridianCity")
	player.place(Vector2i(19, 9)); player.facing = 1
	_on_player_moved(Vector2i(19, 9))
	print("[parceltest] gate(with dex): blocked=%s (expect false)" % (cutscene_active or modal == textbox))
	get_tree().quit()


func _sighttest() -> void:
	await get_tree().process_frame
	story_events = {"GOT_STARTER": true}
	player_name = "RED"
	player_party = [make_mon("squirtle", 30, ["TACKLE"])]
	load_world("Route3")
	var t = _npc_by_key("SPRITE_YOUNGSTER@10,6")   # facing RIGHT, sight 2, OPP_BUG_CATCHER
	print("[sighttest] trainer facing=%d sight=%d class=%s before=%s" % [
		t.facing, t.sight, t.trainer_class, t.battle_text.replace("\n", " ")])

	# Negatives: too far, off-axis, and behind the trainer should NOT engage.
	var neg: Array = []
	for c in [Vector2i(13, 6), Vector2i(10, 5), Vector2i(8, 6)]:
		player.place(c)
		_on_player_moved(c)
		neg.append(cutscene_active or modal != null)
		cutscene_active = false
		modal = null
	print("[sighttest] negatives (expect [false, false, false]): %s" % str(neg))

	# Positive: stepping into the line of sight at (12,6) engages.
	player.place(Vector2i(12, 6))
	_on_player_moved(Vector2i(12, 6))
	var engaged: bool = cutscene_active
	var saw_bubble := false
	var pages: Array = []
	var prev_active := false
	var win_forced := false
	for i in 4000:
		await get_tree().process_frame
		if t._emote != null and t._emote.visible:
			if not saw_bubble and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://sight_bubble.png")
			saw_bubble = true
		var act: bool = textbox.active and textbox.visible
		if act and not prev_active and textbox.pages.size() > 0:
			pages.append(str(textbox.pages[0]).replace("\n", " "))
		prev_active = act
		if act:
			textbox.advance()
		elif modal == battle and not battle.won:
			battle.won = true
			battle.blacked_out = false
			battle.finished.emit()
			win_forced = true
		if win_forced and not cutscene_active and modal == null:
			break
	print("[sighttest] engaged=%s saw_bubble=%s walked_adjacent=%s defeated=%s" % [
		engaged, saw_bubble, t.cell == Vector2i(11, 6), defeated_trainers.has(trainer_id(t))])
	print("[sighttest] pages shown: %s" % str(pages))
	# Re-talking a defeated trainer (now standing at 11,6) shows the after-battle line.
	player.place(Vector2i(12, 6)); player.facing = 2   # face LEFT toward the trainer
	var handled := interact(player)
	var after := str(textbox.pages[0]).replace("\n", " ") if (modal == textbox and textbox.pages.size() > 0) else ""
	print("[sighttest] re-talk handled=%s after_text=%s" % [handled, after])
	get_tree().quit()


func _scrolltest() -> void:
	await get_tree().process_frame
	var items: Array = []
	for i in 12:
		items.append("ITEM%02d" % i)
	menu.open(items, Vector2(8, 8))
	var s0: int = menu.scroll              # top
	menu.cursor = 8; menu._fix_scroll()
	var s8: int = menu.scroll              # window follows down (8-7+1=2)
	menu.cursor = 11; menu._fix_scroll()
	var s11: int = menu.scroll             # clamped to last window (12-7=5)
	menu.cursor = 0; menu._fix_scroll()
	var stop: int = menu.scroll            # back to top
	print("[scrolltest] n=%d vis=%d scroll @0=%d @8=%d @11=%d @top=%d (expect 0,2,5,0)" % [
		items.size(), mini(items.size(), menu.MAX_VISIBLE), s0, s8, s11, stop])
	get_tree().quit()


## Drive a Bill cutscene: advance dialogue and answer its YES/NO until `done`.
func _drive_bill(done: Callable, budget := 2000) -> void:
	for i in budget:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == menu and menu_mode == "cutscene":
			menu.chosen.emit(0)               # YES
		elif modal == naming:
			naming.done.emit("")              # skip the nickname keyboard (keep species name) —
		if done.call():                       # YES above opens it for every offer_nickname beat
			return


func _flashtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_party = [make_mon("pidgey", 20, [])]
	player_party[0]["moves"].append({"move": "FLASH", "pp": 20, "maxpp": 20})
	load_world("RockTunnel1F")
	var dark_on_enter: bool = darkness.visible
	# No badge -> FLASH is blocked.
	badges = []
	_open_party_view(); _on_menu_chosen(0)
	var has_flash: bool = "FLASH" in _mon_menu_opts
	_on_menu_chosen(_mon_menu_opts.find("FLASH"))
	var blocked_no_badge: bool = not flash_lit
	modal = null; textbox.visible = false
	# With the Boulder Badge -> FLASH lights the cave.
	badges = ["BOULDERBADGE"]
	_open_party_view(); _on_menu_chosen(0); _on_menu_chosen(_mon_menu_opts.find("FLASH"))
	var lit: bool = flash_lit
	var dark_after_flash: bool = darkness.visible
	modal = null; textbox.visible = false
	# Leaving the dark area resets FLASH.
	load_world("PalletTown")
	print("[flashtest] dark_on_enter=%s has_flash_opt=%s blocked_no_badge=%s lit=%s dark_after=%s reset_on_leave=%s outside_dark=%s" % [
		dark_on_enter, has_flash, blocked_no_badge, lit, dark_after_flash, not flash_lit, darkness.visible])
	# HM05 from the Route 2 aide (needs >= 10 species).
	story_events = {}; player_bag = {}
	pokedex_owned = {}
	for i in 12:
		pokedex_owned["mon%d" % i] = true
	load_world("Route2Gate")
	player.place(Vector2i(2, 4)); player.facing = 2   # face LEFT -> aide at (1,4)
	interact(player)
	await _drive_bill(func() -> bool: return has_event("GOT_HM05") and not cutscene_active and modal == null, 1200)
	print("[flashtest] aide: got_hm05=%s bag_hm05=%s" % [has_event("GOT_HM05"), player_bag.has("HM05")])
	get_tree().quit()


## DIG and TELEPORT as party-menu field moves (gh #102). DIG is ItemUseEscapeRope (cave/dungeon only,
## never AGATHAS_ROOM); TELEPORT is outdoors-only; both warp to the last town's fly tile via _escape_warp.
func _digteleporttest() -> void:
	await get_tree().process_frame
	story_events = {}
	respawn_map = "ViridianPokecenter"                 # -> ViridianCity, fly tile (23,26)
	var town := "ViridianCity"
	var fly: Vector2i = FLY_DESTS[town][0]

	# DIG offered + warps out of a cave.
	player_party = [make_mon("diglett", 20, [])]
	player_party[0]["moves"].append({"move": "DIG", "pp": 10, "maxpp": 10})
	load_world("MtMoonB1F")
	_open_party_view(); _on_menu_chosen(0)
	var dig_offered: bool = "DIG" in _mon_menu_opts
	_on_menu_chosen(_mon_menu_opts.find("DIG"))
	await get_tree().process_frame
	var dig_cave_ok: bool = str(center_label) == town and player.cell == fly
	modal = null; textbox.visible = false; _text_then = Callable()

	# DIG refused outdoors (not an EscapeRopeTileset).
	load_world("PewterCity")
	_open_party_view(); _on_menu_chosen(0); _on_menu_chosen(_mon_menu_opts.find("DIG"))
	await get_tree().process_frame
	var dig_outdoor_refused: bool = str(center_label) == "PewterCity"
	modal = null; textbox.visible = false; _text_then = Callable()

	# TELEPORT offered + warps when outdoors.
	player_party = [make_mon("abra", 12, [])]
	player_party[0]["moves"].append({"move": "TELEPORT", "pp": 20, "maxpp": 20})
	load_world("PewterCity")
	_open_party_view(); _on_menu_chosen(0)
	var tp_offered: bool = "TELEPORT" in _mon_menu_opts
	_on_menu_chosen(_mon_menu_opts.find("TELEPORT"))
	await get_tree().process_frame
	var tp_outdoor_ok: bool = str(center_label) == town and player.cell == fly
	modal = null; textbox.visible = false; _text_then = Callable()

	# TELEPORT refused in a cave (CheckIfInOutsideMap fails).
	load_world("MtMoonB1F")
	_open_party_view(); _on_menu_chosen(0); _on_menu_chosen(_mon_menu_opts.find("TELEPORT"))
	await get_tree().process_frame
	var tp_indoor_refused: bool = str(center_label) == "MtMoonB1F"

	var pass_all := dig_offered and dig_cave_ok and dig_outdoor_refused and tp_offered and tp_outdoor_ok and tp_indoor_refused
	print("[digteleporttest] %s: dig_offered=%s dig_cave=%s dig_outdoor_refused=%s | tp_offered=%s tp_outdoor=%s tp_indoor_refused=%s" % [
		"PASS" if pass_all else "FAIL", dig_offered, dig_cave_ok, dig_outdoor_refused, tp_offered, tp_outdoor_ok, tp_indoor_refused])
	get_tree().quit()


func _drain_battle_to_menu(budget := 60) -> void:
	for i in budget:
		if battle.state == "menu" or modal == null:
			return
		if battle.state == "msg":
			battle._next_msg()
		await get_tree().process_frame


func _action_has_key(action: String, key: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and int(ev.keycode) == key:
			return true
	return false


func _slottest() -> void:
	await get_tree().process_frame
	var s = slots
	# Payout table (SlotRewardPointers).
	var pay_ok: bool = s.PAYOUT["SEVEN"] == 300 and s.PAYOUT["BAR"] == 100 \
		and s.PAYOUT["CHERRY"] == 8 and s.PAYOUT["FISH"] == 15
	# A middle-row 7-7-7 (the only middle match these reel positions allow).
	var mid7 = s.find_match([4, 17, 17], 1)
	var r_sb = s.resolve_rig([4, 17, 17], 1, "sevenbar")    # jackpot allowed -> pays 300
	var r_skip = s.resolve_rig([4, 17, 17], 1, "normal")    # normal mode skips the 7 -> no win
	var r_none = s.resolve_rig([4, 17, 17], 1, "none")      # never wins, even on a triple
	var r_cherry = s.resolve_rig([8, 8, 0], 1, "normal")    # rolls reel 3 into a cherry line -> 8
	# Rig decision gating (SlotMachine_SetFlags).
	s.seven_bar_mode = true; s.allow_counter = 0
	var d_sb = s._decide()
	s.seven_bar_mode = false; s.allow_counter = 5
	var d_norm = s._decide()
	# Reward side effects (SlotReward*Func).
	s.allow_counter = 5; s.seven_bar_mode = true
	s.apply_reward("SEVEN"); var rw_seven: int = s.allow_counter
	s.seven_bar_mode = true; s.apply_reward("BAR"); var rw_bar: bool = s.seven_bar_mode
	s.allow_counter = 5; s.apply_reward("CHERRY"); var rw_cherry: int = s.allow_counter
	# Coin cap.
	player_coins = 9980; player_coins = mini(9999, player_coins + 50)
	var cap_ok: bool = player_coins == 9999
	var pass_all: bool = pay_ok and mid7 == "SEVEN" \
		and r_sb["symbol"] == "SEVEN" and int(r_sb["payout"]) == 300 \
		and r_skip["symbol"] == "" and r_none["symbol"] == "" \
		and r_cherry["symbol"] == "CHERRY" and int(r_cherry["payout"]) == 8 \
		and d_sb == "sevenbar" and d_norm == "normal" \
		and rw_seven == 0 and rw_bar == false and rw_cherry == 4 and cap_ok
	print("[slottest] mid7=%s sb=%s/%d skip='%s' none='%s' cherry=%s/%d decide=%s,%s rw=%d,%s,%d cap=%s" % [
		mid7, r_sb["symbol"], int(r_sb["payout"]), r_skip["symbol"], r_none["symbol"],
		r_cherry["symbol"], int(r_cherry["payout"]), d_sb, d_norm, rw_seven, str(rw_bar), rw_cherry, cap_ok])
	print("[slottest] PASS=%s" % pass_all)
	# Integration: a full play cycle (bet -> spin -> stop x3 -> result -> finish) shouldn't crash.
	player_bag["COIN CASE"] = 1
	player_coins = 50
	var done := [false]
	s.finished.connect(func() -> void: done[0] = true, CONNECT_ONE_SHOT)
	s.start(false)
	s._to_bet()
	s.bet = 1; player_coins -= 1                          # bet 1 coin
	var bet_taken: bool = player_coins == 49
	s._begin_spin()
	s._stop_reel(); s._stop_reel(); s._stop_reel()       # stop all three reels -> resolve (may win)
	s._after_result()
	s._finish()
	print("[slottest] flow phase=%s finished=%s bet_taken=%s coins=%d" % [s.phase, done[0], bet_taken, player_coins])
	print("[slottest] FLOW_PASS=%s" % (done[0] and s.phase == "done" and bet_taken))
	get_tree().quit()


func _first_boulder() -> Variant:
	for n in npcs:
		if str(n.key).begins_with("SPRITE_BOULDER@"):
			return n
	return null


func _creditstest() -> void:
	await get_tree().process_frame
	var all := str(credits_pages)
	var mon_slides := 0
	var copyright_pages := 0
	for pg in credits_pages:
		if pg.get("mon") != null:
			mon_slides += 1
		if bool(pg.get("copyright", false)):
			copyright_pages += 1
	var pages_ok: bool = credits_pages.size() >= 30 and "DIRECTOR" in all \
		and "SATOSHI TAJIRI" in all and "RED VERSION STAFF" in all \
		and mon_slides == 15 and copyright_pages == 1
	cutscene.run_credits()                          # fast path (audio disabled in tests)
	await _drive_until(func() -> bool: return not cutscene.visible, 600)
	var done_ok: bool = not cutscene.visible and not cutscene._in_credits
	var pass_all: bool = pages_ok and done_ok
	print("[creditstest] pages=%d mon_slides=%d (expect 15) copyright=%d done=%s" % [
		credits_pages.size(), mon_slides, copyright_pages, done_ok])
	print("[creditstest] PASS=%s" % pass_all)
	get_tree().quit()


func _creditshot() -> void:
	await get_tree().process_frame
	cutscene.visible = true
	cutscene._in_credits = true
	cutscene._the_end_tex = load("res://assets/credits_the_end.png")
	# a text page, a mon silhouette mid-scroll, the © page, and THE END
	var text_page = credits_pages[1] if credits_pages.size() > 1 else {"lines": [[-3, "DIRECTOR"]]}
	for shot in [["text", text_page], ["mon", null], ["copyright", null], ["end", null]]:
		cutscene._credit_end = shot[0] == "end"
		cutscene._credit_mon = null
		cutscene._credit_page = {}
		cutscene._fade = 0.0
		if shot[0] == "text":
			cutscene._credit_page = text_page
		elif shot[0] == "mon":
			# a SMALL pic (40×40), to show the 7×7 bottom-align + centring pads (gh #183)
			cutscene._credit_mon = load("res://assets/pokemon/front/diglett.png")
			cutscene._credit_mon_x = 52.0 + (56.0 - cutscene._credit_mon.get_width()) / 2.0
			cutscene._credit_mon_y = 48.0 + (56.0 - cutscene._credit_mon.get_height())
		elif shot[0] == "copyright":
			cutscene._credit_page = {"copyright": true, "lines": []}
		cutscene.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://credits_%s.png" % shot[0])
	print("[creditshot] posed text/mon/copyright/end")
	get_tree().quit()


func _martshot() -> void:
	await get_tree().process_frame
	load_world("ViridianMart", -1, Vector2i(3, 5), false)
	for _i in 4:
		await get_tree().process_frame
	var clerk = _npc_by_key("SPRITE_CLERK@0,5")
	if clerk:
		print("[martshot] clerk facing=%d frames=%d flip=%s frame_row=%d" % [
			clerk.facing, clerk.frames, clerk.spr.flip_h, int(clerk.spr.region_rect.position.y / 16)])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_mart.png")
	# The shop UI: the BUY/SELL/QUIT + MONEY boxes (the money label must sit IN the top
	# border with no line through it), then the BUY list over them.
	player.place(Vector2i(2, 5)); player.facing = 2
	interact(player)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_mart_top.png")
	martscreen._top_select(0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_mart_buy.png")
	get_tree().quit()


func _pcentershot() -> void:
	await get_tree().process_frame
	load_world("ViridianPokecenter", -1, Vector2i(7, 6), false)
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_pcenter.png")
	# Bench guy: stand at (1,4) facing LEFT (front = 0,4), examine the left-wall person (#9).
	player.place(Vector2i(1, 4)); player.facing = player.LEFT
	print("[pcentershot] bench guy handled=%s" % interact(player))
	menu.close(); textbox.visible = false; modal = null
	# Try interacting with each NPC from a walkable adjacent tile.
	for label in [["nurse", Vector2i(3, 1)], ["link", Vector2i(11, 2)], ["sitting", Vector2i(4, 3)]]:
		var c: Vector2i = label[1]
		var stand := Vector2i(-99, -99)
		var faced: int = player.DOWN
		for step in [[Vector2i(0, 1), player.UP], [Vector2i(-1, 0), player.RIGHT],
				[Vector2i(1, 0), player.LEFT], [Vector2i(0, -1), player.DOWN]]:
			if is_walkable(c + step[0]) or int(_tile_at(c + step[0])) in placed[0]["ts"].get("counter_tiles", []):
				stand = c + step[0]; faced = step[1]; break
		var handled := false
		if stand.x > -99:
			player.place(stand); player.facing = faced
			handled = interact(player)
			menu.close(); textbox.visible = false; modal = null
		print("[pcentershot] %s@%s stand=%s interact=%s" % [label[0], str(c), str(stand), handled])
	get_tree().quit()


func _visibilitytest() -> void:
	await get_tree().process_frame
	story_events = {}
	load_world("SaffronCity")                          # occupied: Rockets out, residents hidden
	var saf_before: bool = _npc_by_key("SPRITE_ROCKET@7,6").shown and not _npc_by_key("SPRITE_SCIENTIST@8,14").shown
	set_event("BEAT_SILPH_CO_GIOVANNI")
	load_world("SaffronCity")                          # freed: Rockets gone, residents back
	var saf_after: bool = not _npc_by_key("SPRITE_ROCKET@7,6").shown and _npc_by_key("SPRITE_SCIENTIST@8,14").shown
	story_events = {}
	load_world("SilphCo1F")
	var silph_before: bool = not _npc_by_key("SPRITE_LINK_RECEPTIONIST@4,2").shown
	set_event("BEAT_SILPH_CO_GIOVANNI")
	load_world("SilphCo1F")
	var silph_after: bool = _npc_by_key("SPRITE_LINK_RECEPTIONIST@4,2").shown
	story_events = {}
	load_world("ChampionsRoom")
	var champ_before: bool = not _npc_by_key("SPRITE_OAK@3,7").shown
	set_event("BEAT_CHAMPION")
	load_world("ChampionsRoom")
	# gh #179: TOGGLE_CHAMPIONS_ROOM_OAK ships hidden and is only ShowObject'd mid-ceremony — at
	# load OAK is never standing at the door, before or after the title is won.
	var champ_after: bool = not _npc_by_key("SPRITE_OAK@3,7").shown
	var ok: bool = saf_before and saf_after and silph_before and silph_after and champ_before and champ_after
	print("[visibilitytest] saffron=%s/%s silph1f=%s/%s champion_oak=%s/%s" % [
		saf_before, saf_after, silph_before, silph_after, champ_before, champ_after])
	print("[visibilitytest] PASS=%s" % ok)
	get_tree().quit()


func _giftnpctest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_bag = {}
	load_world("Route1")
	var npc = null
	for n in npcs:
		if n.text_id == "TEXT_ROUTE1_YOUNGSTER1":
			npc = n; break
	player.place(npc.cell + Vector2i(0, 1)); player.facing = 1   # face the youngster
	interact(player)
	var got: bool = player_bag.has("POTION") and has_event("GOT_POTION_SAMPLE")
	menu.close(); textbox.visible = false; modal = null
	var before: int = int(player_bag.get("POTION", 0))
	interact(player)                                             # talk again -> no second potion
	var no_double: bool = int(player_bag.get("POTION", 0)) == before
	# Cerulean Rocket returns TM_DIG once you've beaten him.
	story_events = {}; player_bag = {}
	load_world("CeruleanCity")
	var rk = _npc_by_key("SPRITE_ROCKET@30,8")
	defeated_trainers[trainer_id(rk)] = true
	player.place(rk.cell + Vector2i(0, 1)); player.facing = 1
	interact(player)
	var tm_ok: bool = player_bag.has("TM28") and has_event("GOT_TM28")
	print("[giftnpctest] got_potion=%s no_double=%s cerulean_tm=%s" % [got, no_double, tm_ok])
	# The Copycat: mimics without a POKé DOLL; trades it for TM31 (and keeps the doll).
	load_world("CopycatsHouse2F")
	await get_tree().process_frame
	player.place(Vector2i(4, 4), true); player.facing = 1   # face UP -> the Copycat at (4,3)
	interact(player)
	var mimic_only: bool = not has_event("GOT_TM31")
	modal = null; textbox.visible = false
	player_bag["POKé DOLL"] = 1
	interact(player)
	var tm31: String = str(item_names.get("TM_MIMIC", "TM31"))
	var traded: bool = player_bag.has(tm31) and not player_bag.has("POKé DOLL") and has_event("GOT_TM31")
	print("[giftnpctest] copycat: mimic_without_doll=%s traded_doll_for_tm31=%s" % [mimic_only, traded])
	print("[giftnpctest] PASS=%s" % (got and no_double and tm_ok and mimic_only and traded))
	get_tree().quit()


func _cyclinggatetest() -> void:
	await get_tree().process_frame
	player_bag = {}
	load_world("Route16Gate1F")
	player.place(Vector2i(4, 7)); player.facing = 1    # walking up toward Cycling Road, no bike
	_on_player_moved(Vector2i(4, 7))
	var blocked: bool = player.cell == Vector2i(4, 8)  # turned back
	menu.close(); textbox.visible = false; modal = null
	player_bag = {"BICYCLE": 1}
	player.place(Vector2i(4, 7)); player.facing = 1
	_on_player_moved(Vector2i(4, 7))
	var passed: bool = player.cell == Vector2i(4, 7)    # allowed through with the bike
	menu.close(); textbox.visible = false; modal = null
	# Route 22 Gate: blocked north without the BOULDERBADGE.
	badges = []
	load_world("Route22Gate")
	player.place(Vector2i(4, 2)); player.facing = 1
	_on_player_moved(Vector2i(4, 2))
	var gate_blocked: bool = player.cell == Vector2i(4, 3)
	menu.close(); textbox.visible = false; modal = null
	badges = ["BOULDERBADGE"]
	player.place(Vector2i(4, 2)); player.facing = 1
	_on_player_moved(Vector2i(4, 2))
	var gate_passed: bool = player.cell == Vector2i(4, 2)
	print("[cyclinggatetest] bike: blocked=%s passed=%s | r22gate: blocked=%s passed=%s" % [
		blocked, passed, gate_blocked, gate_passed])
	print("[cyclinggatetest] PASS=%s" % (blocked and passed and gate_blocked and gate_passed))
	get_tree().quit()


func _forcedbiketest() -> void:
	await get_tree().process_frame
	player_bag = {"BICYCLE": 1}
	force_bike = false
	riding = false
	player.step_scale = 1.0
	modal = null; textbox.visible = false
	load_world("Route16", -1, Vector2i(17, 11), false)
	player.facing = player.UP                         # real walk from below onto ForcedBikeOrSurfMaps (17,10)
	Input.action_press("ui_up")
	await player.moved                                # exercise Player's collision + completed-step signal
	Input.action_release("ui_up")
	var forced: bool = player.cell == Vector2i(17, 10) and riding and force_bike
	var mounted_silently: bool = forced and modal == null and not textbox.visible
	assert(mounted_silently, "Route16 forced-bike coordinate must silently mount and set force_bike")
	_toggle_bike()
	var dismount_refused: bool = riding and abs(float(player.step_scale) - 0.5) < 0.01
	assert(dismount_refused, "force_bike must refuse bicycle dismount")
	load_world("Route16Gate1F")
	var reset_at_gate: bool = not force_bike and not riding
	assert(reset_at_gate, "Route16Gate1F must reset force_bike and permit the indoor dismount")
	load_world("Route16", -1, Vector2i(10, 10), false)
	_toggle_bike()                                    # mount away from the force-on coordinates
	modal = null; textbox.visible = false
	_toggle_bike()                                    # once reset, the ordinary outdoor dismount works
	var toggled_off: bool = not riding and abs(float(player.step_scale) - 1.0) < 0.01
	assert(toggled_off, "the bicycle must toggle off normally after the gate reset")
	print("[forcedbiketest] forced=%s dismount_refused=%s reset_at_gate=%s toggled_off=%s mounted_silently=%s PASS=%s" % [
		forced, dismount_refused, reset_at_gate, toggled_off, mounted_silently,
		forced and mounted_silently and dismount_refused and reset_at_gate and toggled_off])
	get_tree().quit()


func _rivallosstest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"; rival_name = "BLUE"; player_starter = "charmander"
	player_party = [make_mon("charmander", 5, ["SCRATCH"])]
	load_world("OaksLab")
	set_event("GOT_STARTER")
	player.place(Vector2i(5, 6))
	cutscene.rival_challenge()
	await _drive_until(func() -> bool: return modal == battle, 400)
	player_party[0]["hp"] = 0                           # faint -> would normally black out
	battle.blacked_out = true
	battle.won = false
	battle.finished.emit()
	await _drive_bill(func() -> bool: return has_event("BEAT_RIVAL1") and not cutscene_active, 800)
	var no_whiteout: bool = center_label == "OaksLab"   # still in the lab (didn't warp to a respawn)
	var healed: bool = int(player_party[0]["hp"]) == int(player_party[0]["maxhp"])
	print("[rivallosstest] no_whiteout=%s healed=%s battled=%s" % [
		no_whiteout, healed, has_event("BEAT_RIVAL1")])
	print("[rivallosstest] PASS=%s" % (no_whiteout and healed and has_event("BEAT_RIVAL1")))
	get_tree().quit()


func _starterballtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_starter = "squirtle"; rival_starter = "bulbasaur"
	set_event("OAK_ASKED_TO_CHOOSE_MON"); set_event("GOT_STARTER")
	load_world("OaksLab")
	# Only the untaken (charmander) ball remains; the two chosen ones are gone (#13).
	var left = _npc_by_key("SPRITE_POKE_BALL@6,3")
	var taken_p = _npc_by_key("SPRITE_POKE_BALL@7,3")   # squirtle (player)
	var taken_r = _npc_by_key("SPRITE_POKE_BALL@8,3")   # bulbasaur (rival)
	var vis_ok: bool = left.shown and not taken_p.shown and not taken_r.shown
	player.place(left.cell + Vector2i(0, 1)); player.facing = 1
	var handled: bool = interact(player)
	var text_ok: bool = handled and modal == textbox
	print("[starterballtest] leftover_visible=%s taken_hidden=%s last_mon_text=%s" % [
		left.shown, not taken_p.shown and not taken_r.shown, text_ok])
	print("[starterballtest] PASS=%s" % (vis_ok and text_ok))
	get_tree().quit()


func _pcaccesstest() -> void:
	await get_tree().process_frame
	story_events = {}
	pc_items = {"POTION": 2}
	pc_box = []
	player_party = [make_mon("squirtle", 10, []), make_mon("pidgey", 8, [])]
	# #8: Red's bedroom PC opens the player's ITEM PC directly.
	load_world("RedsHouse2F")
	player.place(Vector2i(0, 2)); player.facing = 1    # face the PC at (0,1)
	interact(player)
	var reds_ok: bool = modal == menu and menu_mode == "pc_item"
	menu.close(); modal = null
	# #20: a Pokécenter PC opens the full menu; SOMEONE'S PC reaches Pokémon storage.
	load_world("ViridianPokecenter")
	player.place(Vector2i(13, 4)); player.facing = 1   # face the PC at (13,3)
	interact(player)
	var top_ok: bool = modal == menu and menu_mode == "pc_top"
	_on_menu_chosen(0)                                 # SOMEONE'S PC
	var mon_ok: bool = menu_mode == "pc_mon"
	var pass_all: bool = reds_ok and top_ok and mon_ok
	print("[pcaccesstest] reds_item_pc=%s center_top=%s someones_pc=%s" % [reds_ok, top_ok, mon_ok])
	print("[pcaccesstest] PASS=%s" % pass_all)
	get_tree().quit()


## gh #39 (ADR-019): the Event VM tracer. Proves the pipeline end-to-end on the real
## project: the loader's boot refusals (unknown command / trigger kind / unparseable
## condition each name the record), the generic EventMapScript serving BluesHouse (its
## hand-written adapter is GONE), the `visible` query behind object_shown, and the
## authored Daisy TOWN MAP beat — pre-dex line, the gift (+ flag + re-talk line), and
## the full-bag refusal aborting the event with no flag set.
## Run: `pwsh tools/run.ps1 -- --eventtest`. Headless.
func _eventtest() -> void:
	await get_tree().process_frame
	var ok := true

	# 1 — the loader refuses semantics this build lacks, naming the record
	var vm := EventVM.new()
	vm.main = self
	var e := vm.load_all({"bad": {"trigger": {"kind": "interact", "map": "map:X", "object": "o"},
		"commands": [{"cmd": "explode"}]}})
	ok = _ev_check("loader refuses an unknown command", e.contains("unknown command 'explode'"), e) and ok
	e = vm.load_all({"bad2": {"trigger": {"kind": "on_dance", "map": "map:X"}}})
	ok = _ev_check("loader refuses an unknown trigger kind", e.contains("unknown trigger kind 'on_dance'"), e) and ok
	e = vm.load_all({"bad3": {"trigger": {"kind": "visible", "map": "map:X", "object": "o",
		"visible_when": "GOT_ +"}}})
	ok = _ev_check("loader refuses an unparseable condition", e.contains("does not parse"), e) and ok

	# 2 — the tracer map is served by the generic event adapter (its .gd is deleted)
	ok = _ev_check("BluesHouse is served by EventMapScript",
		map_script("BluesHouse") is EventAdapter) and ok

	# 3 — the pre-dex line: no gift, no flag
	story_events = {}
	player_bag = {}
	player_name = "RED"
	rival_name = "BLUE"
	load_world("BluesHouse")
	player.place(Vector2i(2, 4))
	player.facing = 1                                  # UP -> sitting Daisy at (2,3)
	interact(player)
	await _drive_until(func() -> bool: return not cutscene_active and modal == null, 600)
	ok = _ev_check("pre-dex: no TOWN MAP, no flag",
		not player_bag.has("TOWN MAP") and not has_event("GOT_TOWN_MAP")) and ok

	# 4 — the gift: item + sfx + flag, then the re-talk line changes and gives nothing
	story_events = {"GOT_POKEDEX": true}
	interact(player)
	await _drive_until(func() -> bool: return not cutscene_active and modal == null, 600)
	ok = _ev_check("gift: TOWN MAP in the bag + GOT_TOWN_MAP set",
		player_bag.has("TOWN MAP") and has_event("GOT_TOWN_MAP")) and ok
	interact(player)
	await _drive_until(func() -> bool: return not cutscene_active and modal == null, 600)
	ok = _ev_check("re-talk: still exactly one TOWN MAP",
		int(player_bag.get("TOWN MAP", 0)) == 1) and ok

	# 5 — a full bag refuses the gift and ABORTS the event (no flag, faithful to _gift)
	story_events = {"GOT_POKEDEX": true}
	player_bag = {}
	for i in BAG_CAPACITY:
		player_bag["FILLER %d" % i] = 1
	interact(player)
	await _drive_until(func() -> bool: return not cutscene_active and modal == null, 600)
	ok = _ev_check("full bag: refused, event aborted, no flag",
		not player_bag.has("TOWN MAP") and not has_event("GOT_TOWN_MAP")) and ok

	# 6 — the `visible` query drives object_shown on a fresh load
	story_events = {"GOT_TOWN_MAP": true}
	load_world("BluesHouse")
	ok = _ev_check("visible_when: walking Daisy shown once GOT_TOWN_MAP",
		not _npc_by_key("SPRITE_DAISY@2,3").shown and _npc_by_key("SPRITE_DAISY@6,4").shown) and ok

	# 7 — wave-B refusals (gh #40): a beat that is not a Cutscene method, a step trigger
	# with no cells — each refuses at boot naming the record.
	e = vm.load_all({"badbeat": {"trigger": {"kind": "interact", "map": "map:X", "object": "o"},
		"commands": [{"cmd": "beat", "name": "no_such_beat"}]}})
	ok = _ev_check("loader refuses an unknown beat", e.contains("unknown beat 'no_such_beat'"), e) and ok
	e = vm.load_all({"badstep": {"trigger": {"kind": "step", "map": "map:X"}, "commands": []}})
	ok = _ev_check("loader refuses a step trigger without cells", e.contains("needs cells"), e) and ok

	# 8 — step dispatch: the non-consuming record runs first (id order), its flag is
	# visible to the consuming record's `when` in the SAME step, and the step consumes.
	var vm2 := EventVM.new()
	vm2.main = self
	e = vm2.load_all({
		"a_poke": {"trigger": {"kind": "step", "map": "map:X", "cells": [[1, 1]], "consume": false},
			"commands": [{"cmd": "set_flag", "flag": "EVT_POKE"}]},
		"b_gate": {"trigger": {"kind": "step", "map": "map:X", "cells": [[1, 1]], "when": "EVT_POKE"},
			"commands": [{"cmd": "set_flag", "flag": "EVT_GATE"}]}})
	ok = _ev_check("wave-B synthetic records load clean", e == "", e) and ok
	story_events = {}
	var consumed: bool = vm2.step_fire("X", Vector2i(1, 1))
	ok = _ev_check("step: poke ran, gated record consumed the step",
		consumed and has_event("EVT_POKE") and has_event("EVT_GATE")) and ok
	ok = _ev_check("step: run() restored cutscene_active", not cutscene_active) and ok

	# 9 — battle_end records run inside the trainer-battle beat, which still owns the
	# cutscene flag: run() must save/restore it, never clear it.
	e = vm2.load_all({"c_be": {"trigger": {"kind": "battle_end", "map": "map:Y"},
		"commands": [{"cmd": "set_flag", "flag": "EVT_BE"}]}})
	ok = _ev_check("battle_end record loads clean", e == "", e) and ok
	cutscene_active = true
	vm2.run_battle_end("Y")
	ok = _ev_check("battle_end: ran with cutscene_active preserved",
		has_event("EVT_BE") and cutscene_active) and ok
	cutscene_active = false

	print("[eventtest] %s" % ("ALL GREEN" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _ev_check(name: String, good: bool, detail := "") -> bool:
	print("[eventtest] %s: %s%s" % [name, "PASS" if good else "FAIL",
		"" if good or detail == "" else " — " + detail])
	return good


func _blueshousetest() -> void:
	await get_tree().process_frame
	story_events = {}
	load_world("BluesHouse")                           # early: sitting Daisy only
	var early_ok: bool = _npc_by_key("SPRITE_DAISY@2,3").shown and not _npc_by_key("SPRITE_DAISY@6,4").shown
	set_event("GOT_TOWN_MAP")
	load_world("BluesHouse")                           # after the map: walking Daisy only
	var late_ok: bool = not _npc_by_key("SPRITE_DAISY@2,3").shown and _npc_by_key("SPRITE_DAISY@6,4").shown
	print("[blueshousetest] early(sitting only)=%s late(walking only)=%s" % [early_ok, late_ok])
	print("[blueshousetest] PASS=%s" % (early_ok and late_ok))
	get_tree().quit()


func _hiddencuttest() -> void:
	await get_tree().process_frame
	story_events = {}
	found_hidden = {}
	player_bag = {}
	load_world("ViridianCity")
	player.place(Vector2i(13, 4))
	player.facing = 3                                  # RIGHT -> front is the (14,4) hidden POTION + cut tree
	# ((13,4) is where a player really stands: (14,5), the cell below the tree, is itself solid — gh #84)
	interact(player)
	var got_potion: bool = player_bag.has("POTION")    # hidden item now wins over the cut tree (#31)
	print("[hiddencuttest] front=%s got_potion=%s" % [str(player.front_cell()), got_potion])
	print("[hiddencuttest] PASS=%s" % got_potion)
	get_tree().quit()


func _route22test() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"; rival_name = "BLUE"
	player_starter = "charmander"; rival_starter = "squirtle"
	player_party = [make_mon("charmander", 18, ["SCRATCH", "EMBER"])]
	load_world("Route22")
	# The rival is hidden by default (was appearing prematurely before this fix).
	var hidden_ok: bool = _npc_by_key("SPRITE_BLUE@25,5") != null and not _npc_by_key("SPRITE_BLUE@25,5").shown
	# Reaching the trigger with nothing armed does nothing.
	player.place(Vector2i(29, 5)); _on_player_moved(Vector2i(29, 5))
	var no_trigger: bool = not cutscene_active
	# Arm battle 1 (Pokédex, no Brock) -> the rival walks in and battles.
	set_event("GOT_POKEDEX")
	player.place(Vector2i(29, 5)); _on_player_moved(Vector2i(29, 5))
	var triggered: bool = cutscene_active
	await _drive_until(func() -> bool: return modal == battle, 400)
	# The rival's battle name is the chosen name ("BLUE"), not the "RIVAL1" class placeholder (#24).
	var battle_ok: bool = modal == battle and battle.is_trainer and battle.trainer_name == "BLUE" \
			and _npc_by_key("SPRITE_BLUE@25,5").shown
	# gh #177: the rival stops ALONGSIDE the player (28,5), never on top of them (29,5).
	var rc: Vector2i = _npc_by_key("SPRITE_BLUE@25,5").cell
	var rival_beside: bool = rc != player.cell and abs(rc.x - player.cell.x) + abs(rc.y - player.cell.y) == 1
	# Win -> BEAT flag set and the rival leaves.
	battle.won = true
	battle.finished.emit()
	await _drive_bill(func() -> bool: return has_event("BEAT_ROUTE22_RIVAL_1") and not cutscene_active, 800)
	var beat_ok: bool = has_event("BEAT_ROUTE22_RIVAL_1") and not _npc_by_key("SPRITE_BLUE@25,5").shown
	var pass_all: bool = hidden_ok and no_trigger and triggered and battle_ok and beat_ok and rival_beside
	print("[route22test] hidden=%s no_trigger=%s triggered=%s battle=%s beat=%s rival_beside=%s(rival@%s player@%s)" % [
		hidden_ok, no_trigger, triggered, battle_ok, beat_ok, rival_beside, str(rc), str(player.cell)])
	print("[route22test] PASS=%s" % pass_all)
	get_tree().quit()


func _partytest() -> void:
	await get_tree().process_frame
	player_party = [make_mon("charmander", 12, ["SCRATCH"]), make_mon("pidgey", 9, [])]
	player_party[0]["hp"] = 10
	player_party[1]["status"] = "psn"
	# The POKéMON menu opens in party mode (HP-bar rows), cursor count = party size.
	_open_party_view()
	var mode_ok: bool = modal == menu and menu.party_mode and menu.party.size() == 2 and menu.items.size() == 2
	# gh #155: the HP-bar fill is GB shade 2 — a step lighter than the black outline. Sample row 0's
	# fill rows (y2 = 8 -> fill at y 11-12) for the shade; the outline-dark fill was the bug.
	await RenderingServer.frame_post_draw
	var pimg := get_viewport().get_texture().get_image()
	pimg.save_png("res://party_hp.png")
	var hp_fill := false
	for sx in range(48, 96):
		for sy in range(11, 13):
			var pc := pimg.get_pixel(sx, sy)
			if absf(pc.r - 0.396) < 0.02 and absf(pc.g - 0.541) < 0.02 and absf(pc.b - 0.447) < 0.02:
				hp_fill = true
	# Selecting a mon opens its submenu; the bag CANCEL entry is present + is a no-op.
	_on_menu_chosen(0)
	var sel_ok: bool = menu_mode == "mon_menu"
	player_bag = {"POTION": 2}
	_open_bag()
	var cancel_ok: bool = "CANCEL" in menu.items and menu.items.size() == 2   # 1 item + CANCEL
	_bag_select(1)                                     # the CANCEL row -> no crash / no selection
	var pass_all: bool = mode_ok and sel_ok and cancel_ok and hp_fill
	print("[partytest] party_mode=%s select=%s bag_cancel=%s hp_fill(gh#155)=%s" % [
		mode_ok, sel_ok, cancel_ok, hp_fill])
	print("[partytest] PASS=%s" % pass_all)
	get_tree().quit()


func _uishot() -> void:
	await get_tree().process_frame
	var args: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "moveforget" in args:
		# Pose the WhichMoveToForget screen while this four-move mon is being taught CUT.
		player_party = [make_mon("charmander", 20, ["SCRATCH", "GROWL", "EMBER", "LEER"])]
		load_world("PalletTown")
		await _ui_snap("moveforget", func() -> void:
			textbox.show_ask("Which move should\nbe forgotten?")
			textbox.revealed = 999.0
			_open_move_forget_menu(["SCRATCH", "GROWL", "EMBER", "LEER"]))
		get_tree().quit()
		return
	player_name = "RED"
	player_money = 3000
	player_party = [make_mon("charmander", 12, ["SCRATCH", "GROWL", "EMBER"]),
		make_mon("pidgey", 9, ["GUST", "SAND_ATTACK"]), make_mon("rattata", 5, ["TACKLE"])]
	player_party[0]["hp"] = int(player_party[0]["maxhp"]) / 2
	player_party[1]["status"] = "psn"
	player_bag = {"POKé BALL": 5, "POTION": 3, "ANTIDOTE": 1, "TOWN MAP": 1, "BICYCLE": 1}
	badges = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE"]
	set_event("GOT_POKEDEX")
	for sp in ["charmander", "pidgey", "rattata", "caterpie", "weedle"]:
		mark_seen(sp)
	load_world("PalletTown")
	await _ui_snap("start", func() -> void: open_start_menu())
	await _ui_snap("bag", func() -> void: _open_bag())
	# gh #66: the stacked boxes — USE/TOSS over the item list over the start menu, then the
	# toss ×NN picker and the YES/NO confirm with the question overdrawing the stack.
	await _ui_snap("usetoss", func() -> void:
		_open_bag()
		_on_menu_chosen(1))                          # POTION -> USE/TOSS
	await _ui_snap("tossqty", func() -> void:
		_open_bag()
		_on_menu_chosen(1)
		_on_menu_chosen(1))                          # TOSS -> the ×NN picker
	await _ui_snap("tossconfirm", func() -> void:
		_open_bag()
		_on_menu_chosen(1)
		_on_menu_chosen(1)
		_on_menu_chosen(2)                           # toss 2 -> "Is it OK to toss" + YES/NO
		textbox.revealed = 999.0
		textbox.queue_redraw())
	await _ui_snap("party", func() -> void: _open_party_view())
	await _ui_snap("monmenu", func() -> void: _open_mon_menu(0))
	await _ui_snap("dex", func() -> void: _open_dex())
	await _ui_snap("card", func() -> void:
		modal = trainercard
		trainercard.open_card())
	await _ui_snap("stats1", func() -> void:
		modal = statsscreen
		statsscreen.open(player_party[0]))
	await _ui_snap("stats2", func() -> void:
		modal = statsscreen
		statsscreen.open(player_party[0])
		statsscreen.page = 1
		statsscreen.queue_redraw())
	await _ui_snap("pc", func() -> void: _open_pc())
	load_world("ViridianMart")
	set_event("GOT_OAKS_PARCEL"); set_event("OAK_GOT_PARCEL")
	await _ui_snap("mart", func() -> void:
		_open_mart()
		martscreen._top_select(0))

	get_tree().quit()


func _ui_snap(name: String, opener: Callable) -> void:
	menu.close(); if naming: naming.visible = false
	textbox.visible = false; modal = null
	if trainercard: trainercard.visible = false
	if statsscreen: statsscreen.visible = false
	if optionsscreen: optionsscreen.visible = false
	if dexlist: dexlist.visible = false
	if martscreen: martscreen.visible = false
	if townmap: townmap.visible = false
	opener.call()
	await get_tree().process_frame
	await get_tree().process_frame
	var path: String = ProjectSettings.globalize_path("res://../build/preview/ui_moveforget.png") \
		if name == "moveforget" \
		else "res://ui_%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)


func _rockettest() -> void:
	await get_tree().process_frame
	defeated_trainers = {}
	# B1F guard door: shut until Rocket 5 (28,18) falls.
	load_world("RocketHideoutB1F")
	var b1_locked: bool = map["blocks"][8][12] == 0x54 and not is_walkable(Vector2i(24, 16))
	defeated_trainers["RocketHideoutB1F:28,18"] = true
	load_world("RocketHideoutB1F")
	var b1_open: bool = map["blocks"][8][12] == 0x0E and is_walkable(Vector2i(24, 16))
	# B4F Giovanni door: shut until BOTH guards fall.
	defeated_trainers = {}
	load_world("RocketHideoutB4F")
	var b4_locked: bool = map["blocks"][5][12] == 0x2D and not is_walkable(Vector2i(24, 11))
	defeated_trainers["RocketHideoutB4F:23,12"] = true    # only one guard
	load_world("RocketHideoutB4F")
	var b4_one: bool = map["blocks"][5][12] == 0x2D       # still shut
	defeated_trainers["RocketHideoutB4F:26,12"] = true    # both guards
	load_world("RocketHideoutB4F")
	var b4_open: bool = map["blocks"][5][12] == 0x0E and is_walkable(Vector2i(24, 11))
	# EndTrainerBattle (home/trainers.asm) re-runs the map's load callback, so the door opens the
	# moment the second guard falls — you never have to leave the floor and come back.
	defeated_trainers = {}
	story_events = {}
	load_world("RocketHideoutB4F")
	defeated_trainers["RocketHideoutB4F:23,12"] = true
	map_script(center_label).on_battle_end()
	var b4_live_one: bool = map["blocks"][5][12] == 0x2D             # one guard down: still shut
	defeated_trainers["RocketHideoutB4F:26,12"] = true
	map_script(center_label).on_battle_end()
	var b4_live_open: bool = map["blocks"][5][12] == 0x0E and is_walkable(Vector2i(24, 11))
	# toggleable_objects.asm ships both B4F balls OFF: the LIFT KEY appears only when Rocket 3
	# admits he dropped it, the SILPH SCOPE only when Giovanni steps aside.
	defeated_trainers = {}
	story_events = {}
	load_world("RocketHideoutB4F")
	var key_hidden: bool = not _npc_by_key("SPRITE_POKE_BALL@10,2").shown
	var scope_hidden: bool = not _npc_by_key("SPRITE_POKE_BALL@25,2").shown
	set_event("ROCKET_DROPPED_LIFT_KEY")
	set_event("BEAT_ROCKET_HIDEOUT_GIOVANNI")
	load_world("RocketHideoutB4F")
	var key_shown: bool = _npc_by_key("SPRITE_POKE_BALL@10,2").shown
	var scope_shown: bool = _npc_by_key("SPRITE_POKE_BALL@25,2").shown
	# Talking to the beaten Rocket 3 drops the key (CheckAndSetEvent EVENT_ROCKET_DROPPED_LIFT_KEY
	# -> ShowObject ITEM_5), so the ball turns up without reloading the floor.
	story_events = {}
	defeated_trainers = {"RocketHideoutB4F:11,2": true}
	load_world("RocketHideoutB4F")
	player.place(Vector2i(11, 3))
	player.facing = 1                                                # UP -> Rocket 3 at (11,2)
	interact(player)
	# PrintText comes first: while his line is still up, the ball hasn't turned up yet.
	var not_yet: bool = not has_event("ROCKET_DROPPED_LIFT_KEY") \
		and not _npc_by_key("SPRITE_POKE_BALL@10,2").shown
	await _drive_until(func() -> bool: return has_event("ROCKET_DROPPED_LIFT_KEY") \
		and modal == null and not cutscene_active, 600)
	var dropped: bool = has_event("ROCKET_DROPPED_LIFT_KEY") and _npc_by_key("SPRITE_POKE_BALL@10,2").shown
	modal = null
	textbox.visible = false
	var pass_all: bool = b1_locked and b1_open and b4_locked and b4_one and b4_open \
		and b4_live_one and b4_live_open and key_hidden and scope_hidden and key_shown \
		and scope_shown and not_yet and dropped
	print("[rockettest] b1_locked=%s b1_open=%s b4_locked=%s b4_oneGuard=%s b4_open=%s" % [
		b1_locked, b1_open, b4_locked, b4_one, b4_open])
	print("[rockettest] post-battle: b4_oneGuard=%s b4_open=%s" % [b4_live_one, b4_live_open])
	print("[rockettest] balls: key_hidden=%s scope_hidden=%s key_shown=%s scope_shown=%s" % [
		key_hidden, scope_hidden, key_shown, scope_shown])
	print("[rockettest] key drop: hidden_during_text=%s shown_after=%s" % [not_yet, dropped])
	print("[rockettest] PASS=%s" % pass_all)
	get_tree().quit()


func _e4test() -> void:
	await get_tree().process_frame
	defeated_trainers = {}
	# Lorelei not beaten -> exit sealed.
	load_world("LoreleisRoom")
	var l_locked: bool = map["blocks"][0][2] == 0x24 and not is_walkable(Vector2i(4, 0))
	# Beat Lorelei -> the exit opens (this fixes the .blk softlock).
	defeated_trainers["LoreleisRoom:5,2"] = true
	load_world("LoreleisRoom")
	var l_open: bool = map["blocks"][0][2] == 0x05 and is_walkable(Vector2i(4, 0))
	# Bruno not beaten -> exit sealed (this fixes the .blk skip; its default was open).
	load_world("BrunosRoom")
	var b_locked: bool = map["blocks"][0][2] == 0x24 and not is_walkable(Vector2i(4, 0))
	# Agatha not beaten -> the approach cell (5,1) is walled; beating opens it.
	load_world("AgathasRoom")
	var a_locked: bool = map["blocks"][0][2] == 0x3B and not is_walkable(Vector2i(4, 0))
	defeated_trainers["AgathasRoom:5,2"] = true
	load_world("AgathasRoom")
	var a_open: bool = map["blocks"][0][2] == 0x0E and is_walkable(Vector2i(4, 0))
	# Each seal lifts the moment its member falls (EndTrainerBattle re-runs ShowOrHideExitBlock) — the
	# rooms have no other exit, so waiting for a re-entry would read as a softlock.
	var live_open := {}
	for room in [["LoreleisRoom", 0x05], ["BrunosRoom", 0x05], ["AgathasRoom", 0x0E]]:
		defeated_trainers = {}
		load_world(str(room[0]))
		defeated_trainers["%s:5,2" % room[0]] = true
		map_script(center_label).on_battle_end()
		live_open[room[0]] = map["blocks"][0][2] == int(room[1]) and is_walkable(Vector2i(4, 0))
	var all_live: bool = live_open.values().all(func(v: bool) -> bool: return v)
	var pass_all: bool = l_locked and l_open and b_locked and a_locked and a_open and all_live
	print("[e4test] lorelei_locked=%s lorelei_open=%s bruno_locked=%s agatha_locked=%s agatha_open=%s" % [
		l_locked, l_open, b_locked, a_locked, a_open])
	print("[e4test] post-battle opens: %s" % str(live_open))
	print("[e4test] PASS=%s" % pass_all)
	get_tree().quit()


func _seafoamcurrenttest() -> void:
	await get_tree().process_frame
	story_events = {}
	load_world("SeafoamIslandsB4F")
	surfing = true
	# Without the boulders placed, the current tile does nothing.
	player.place(Vector2i(4, 14))  # audit: surf
	_on_player_moved(Vector2i(4, 14))
	var no_current: bool = not cutscene_active and player.cell == Vector2i(4, 14)
	# With the B3F boulders down (SEAFOAM4 events), the current sweeps you north.
	set_event("SEAFOAM4_BOULDER1_DOWN_HOLE")
	set_event("SEAFOAM4_BOULDER2_DOWN_HOLE")
	player.place(Vector2i(4, 14))  # audit: surf
	_on_player_moved(Vector2i(4, 14))
	var started: bool = cutscene_active
	await _drive_until(func() -> bool: return not cutscene_active and not player.moving, 300)
	var carried: bool = player.cell.y < 14 and not cutscene_active
	var pass_all: bool = no_current and started and carried
	print("[seafoamcurrenttest] no_current=%s started=%s carried_to=%s carried=%s" % [
		no_current, started, str(player.cell), carried])
	print("[seafoamcurrenttest] PASS=%s" % pass_all)
	get_tree().quit()


func _cardkeytest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_bag = {}
	load_world("SilphCo2F")
	# Both card-key doors are placed (block 0x54) and their wall cells are impassable.
	var placed_ok: bool = map["blocks"][2][2] == 0x54 and map["blocks"][5][2] == 0x54
	var blocked_ok: bool = not is_walkable(Vector2i(4, 4)) and not is_walkable(Vector2i(4, 10))
	# Face door 1 (stand on its floor cell (4,5) facing up at the wall (4,4)) without the key -> locked.
	player.place(Vector2i(4, 5)); player.facing = 1
	interact(player)
	var locked_ok: bool = not has_event("SILPH_DOOR_SilphCo2F_2_2") and modal == textbox
	modal = null; textbox.visible = false
	# With the CARD KEY -> it opens (block becomes floor, walkable, event set).
	player_bag = {"CARD KEY": 1}
	interact(player)
	var opened_ok: bool = has_event("SILPH_DOOR_SilphCo2F_2_2") and map["blocks"][2][2] == 0x0E \
		and is_walkable(Vector2i(4, 4))
	modal = null; textbox.visible = false
	# On reload, door 1 stays open and door 2 stays locked.
	load_world("SilphCo2F")
	var persist_ok: bool = map["blocks"][2][2] != 0x54 and map["blocks"][5][2] == 0x54
	var pass_all: bool = placed_ok and blocked_ok and locked_ok and opened_ok and persist_ok
	print("[cardkeytest] placed=%s blocked=%s locked=%s opened=%s persist=%s" % [
		placed_ok, blocked_ok, locked_ok, opened_ok, persist_ok])
	print("[cardkeytest] PASS=%s" % pass_all)
	get_tree().quit()


func _seafoamtest() -> void:
	await get_tree().process_frame
	story_events = {}
	# B3F: push the (3,15) boulder down into the (3,16) hole -> it falls and sets the event.
	load_world("SeafoamIslandsB3F")
	strength_active = true
	var b = _npc_by_key("SPRITE_BOULDER@3,15")
	var present_ok: bool = b != null and b.shown
	try_push_boulder(Vector2i(3, 15), Vector2i(0, 1))                     # 1st push arms the tried flag (gh #129)
	var pushed: bool = try_push_boulder(Vector2i(3, 15), Vector2i(0, 1))  # 2nd push slides it into the hole
	var fell_ok: bool = pushed and has_event("SEAFOAM4_BOULDER1_DOWN_HOLE") and not b.shown
	# The fallen boulder stays gone on reload.
	load_world("SeafoamIslandsB3F")
	var b2 = _npc_by_key("SPRITE_BOULDER@3,15")
	var stays_ok: bool = b2 == null or not b2.shown
	# Articuno is still reachable (we left the water surfable).
	load_world("SeafoamIslandsB4F")
	var articuno_ok := false
	for n in npcs:
		if n.wild_species == "articuno" and n.shown:
			articuno_ok = true
	var pass_all: bool = present_ok and pushed and fell_ok and stays_ok and articuno_ok
	print("[seafoamtest] present=%s pushed=%s fell=%s stays=%s articuno=%s" % [
		present_ok, pushed, fell_ok, stays_ok, articuno_ok])
	print("[seafoamtest] PASS=%s" % pass_all)
	get_tree().quit()


func _route23test() -> void:
	await get_tree().process_frame
	story_events = {}
	load_world("Route23")
	for nn in npcs:
		nn.set_shown(false)                       # ignore trainer sight for this test
	# No badges: blocked at the southernmost checkpoint (Y=136 needs CASCADE). The corridor through
	# that booth row is x 6..9 (the x=2 cells this test used to stand on are inside the booth wall —
	# the old place()-based turn-back teleported into it, the faithful simulated step refuses, gh #84).
	badges = []
	player.place(Vector2i(7, 136)); _on_player_moved(Vector2i(7, 136))
	var blocked_ok: bool = player.cell == Vector2i(7, 137) and modal == textbox
	modal = null; textbox.visible = false
	# CASCADE lets you past 136 but not 119 (THUNDER). 119's corridor is x 8..9.
	badges = ["CASCADEBADGE"]
	player.place(Vector2i(7, 136)); _on_player_moved(Vector2i(7, 136))
	var pass136_ok: bool = player.cell == Vector2i(7, 136) and modal == textbox and has_event("PASSED_CASCADEBADGE_CHECK")
	modal = null; textbox.visible = false        # advance the guard's "Oh! That is the CASCADEBADGE! Go right ahead!"
	player.place(Vector2i(8, 119)); _on_player_moved(Vector2i(8, 119))
	var block119_ok: bool = player.cell == Vector2i(8, 120)
	modal = null; textbox.visible = false
	# All badges -> the northern checkpoint (Y=35, needs EARTH) passes.
	badges = ["CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE"]
	player.place(Vector2i(2, 35)); _on_player_moved(Vector2i(2, 35))
	var pass35_ok: bool = player.cell == Vector2i(2, 35) and has_event("PASSED_EARTHBADGE_CHECK")
	modal = null; textbox.visible = false
	# The east side of Y=35 (X>=14) is never gated.
	badges = []
	player.place(Vector2i(15, 35)); _on_player_moved(Vector2i(15, 35))
	var east_free: bool = player.cell == Vector2i(15, 35)
	var pass_all: bool = blocked_ok and pass136_ok and block119_ok and pass35_ok and east_free
	print("[route23test] blocked=%s pass136=%s block119=%s pass35=%s eastFree=%s" % [
		blocked_ok, pass136_ok, block119_ok, pass35_ok, east_free])
	print("[route23test] PASS=%s" % pass_all)
	get_tree().quit()


func _townmaptest() -> void:
	await get_tree().process_frame
	var n: int = townmap.entries.size()
	var pallet_ok: bool = int(townmap_start.get("PalletTown", -1)) == 0 \
		and str(townmap.entries[0]["name"]) == "PALLET TOWN"
	var ci: int = int(townmap_start.get("CeladonCity", -1))
	# Opening from Celadon starts the cursor there.
	player_bag = {"TOWN MAP": 1}
	center_label = "CeladonCity"
	_open_town_map()
	var open_ok: bool = modal == townmap and townmap.visible and townmap.idx == ci \
		and str(townmap.entries[ci]["name"]) == "CELADON CITY"
	# Cursor pixel stays on-screen (160x144).
	var e: Dictionary = townmap.entries[ci]
	var cx: int = int(e["x"]) * 8 + 12
	var cy: int = int(e["y"]) * 8 + 4
	var on_screen: bool = cx >= 0 and cx <= 144 and cy >= 0 and cy <= 128
	var pass_all: bool = n >= 30 and pallet_ok and ci >= 0 and open_ok and on_screen
	print("[townmaptest] entries=%d pallet=%s celadon_idx=%d open=%s cursor=(%d,%d) on_screen=%s" % [
		n, pallet_ok, ci, open_ok, cx, cy, on_screen])
	print("[townmaptest] PASS=%s" % pass_all)
	get_tree().quit()


func _caveshot() -> void:
	await get_tree().process_frame
	flash_lit = false
	load_world("RockTunnel1F")
	_update_darkness()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://cave_dark.png")
	flash_lit = true
	_update_darkness()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://cave_flash.png")
	get_tree().quit()


func _townmapshot() -> void:
	await get_tree().process_frame
	player_bag = {"TOWN MAP": 1}
	center_label = "PalletTown"
	_open_town_map()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://townmap_pallet.png")
	center_label = "CeladonCity"
	_open_town_map()
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://townmap_celadon.png")
	get_tree().quit()


func _victorytest() -> void:
	await get_tree().process_frame
	story_events = {}
	# 1F: a boulder pushed onto the (17,13) switch opens the door block at (4,6).
	load_world("VictoryRoad1F")
	strength_active = true
	var closed_ok: bool = map["blocks"][6][4] != 0x1D
	var b = _first_boulder()
	b.cell = Vector2i(16, 13); b.position = Vector2(b.cell * 16)
	try_push_boulder(Vector2i(16, 13), Vector2i(1, 0))                     # 1st push arms the tried flag (gh #129)
	var pushed: bool = try_push_boulder(Vector2i(16, 13), Vector2i(1, 0))  # 2nd push moves it onto the switch
	var open_ok: bool = has_event("VR1_SWITCH") and map["blocks"][6][4] == 0x1D and b.cell == Vector2i(17, 13)
	# The opened door persists across a reload.
	load_world("VictoryRoad1F")
	var persist_ok: bool = map["blocks"][6][4] == 0x1D
	# 2F: switch 1 at (1,16) opens its own door block at (3,4).
	load_world("VictoryRoad2F")
	strength_active = true
	var b2 = _first_boulder()
	b2.cell = Vector2i(0, 16); b2.position = Vector2(b2.cell * 16)
	try_push_boulder(Vector2i(0, 16), Vector2i(1, 0))                       # 1st push arms the tried flag (gh #129)
	var pushed2: bool = try_push_boulder(Vector2i(0, 16), Vector2i(1, 0))   # 2nd push moves it onto switch 1
	var f2_ok: bool = has_event("VR2_SWITCH1") and map["blocks"][4][3] == 0x15
	var pass_all: bool = closed_ok and pushed and open_ok and persist_ok and pushed2 and f2_ok
	print("[victorytest] closed=%s pushed=%s open=%s persist=%s f2=%s" % [
		closed_ok, pushed, open_ok, persist_ok, f2_ok])
	print("[victorytest] PASS=%s" % pass_all)
	get_tree().quit()


func _mansiontest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_bag = {}
	# Mansion 1F loads in the switch-OFF layout.
	load_world("PokemonMansion1F")
	var off_ok: bool = map["blocks"][6][12] == 0x0E and map["blocks"][3][8] == 0x2D and map["blocks"][13][13] == 0x2D
	# Flip the 1F switch: it is a wall panel at (2,5), so stand BELOW it at (2,6) and face UP. Standing on
	# the switch cell is what the adapters used to demand, and it is solid — no player could reach it (#83).
	var standable_1f: bool = is_walkable(Vector2i(2, 6)) and not is_walkable(Vector2i(2, 5))
	player.place(Vector2i(2, 6)); player.facing = 1
	interact(player)
	modal = null; textbox.visible = false
	var on_ok: bool = has_event("MANSION_SWITCH_ON") and map["blocks"][6][12] == 0x2D \
		and map["blocks"][3][8] == 0x0E and map["blocks"][13][13] == 0x0E
	# The flag persists across a reload, and other floors honour it.
	load_world("PokemonMansion1F")
	var persist_ok: bool = map["blocks"][6][12] == 0x2D
	load_world("PokemonMansion2F")
	var f2_ok: bool = map["blocks"][2][4] == 0x5F and map["blocks"][4][9] == 0x0E
	# Flip it back from the 2F switch: panel at (2,11), stand below it at (2,12).
	player.place(Vector2i(2, 12)); player.facing = 1
	interact(player)
	modal = null; textbox.visible = false
	var off_again: bool = not has_event("MANSION_SWITCH_ON") and map["blocks"][2][4] == 0x0E
	# Cinnabar Gym door: locked without the SECRET KEY, open with it.
	story_events = {}; player_bag = {}
	load_world("CinnabarIsland")
	player.place(Vector2i(18, 3))
	_do_warp({"dest_const": "CINNABAR_GYM", "dest_map": "CinnabarGym", "dest_warp": 1})
	var locked_ok: bool = center_label == "CinnabarIsland" and player.cell == Vector2i(18, 4)
	modal = null; textbox.visible = false
	player_bag = {"SECRET KEY": 1}
	load_world("CinnabarIsland")
	player.place(Vector2i(18, 3))
	_do_warp({"dest_const": "CINNABAR_GYM", "dest_map": "CinnabarGym", "dest_warp": 1})
	var unlocked_ok: bool = center_label == "CinnabarGym"
	var pass_all: bool = off_ok and on_ok and persist_ok and f2_ok and off_again and locked_ok \
		and unlocked_ok and standable_1f
	print("[mansiontest] off=%s on=%s persist=%s f2=%s offAgain=%s locked=%s unlocked=%s" % [
		off_ok, on_ok, persist_ok, f2_ok, off_again, locked_ok, unlocked_ok])
	# The switch is a wall panel pressed from below — assert that, so nobody "fixes" the test by
	# teleporting onto the switch cell again (gh #83).
	print("[mansiontest] switch is a wall panel, pressed from the cell below: %s" % standable_1f)
	print("[mansiontest] PASS=%s" % pass_all)
	get_tree().quit()


## Museum ticket gate + counter chats (scripts/Museum1F.asm, gh #54): the aisle trigger asks
## ¥50 — decline is pushed back a step, buying opens the way, a ticket holder is waved through;
## the back-way chat branches on the yes/no.
func _museumtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_party = [make_mon("squirtle", 10, ["TACKLE"])]
	# 1) Broke + aisle trigger -> denied and pushed back south.
	player_money = 10
	load_world("Museum1F")
	player.place(Vector2i(9, 4)); player.facing = 3
	_on_player_moved(Vector2i(9, 4))
	await _drive_bill(func() -> bool: return not cutscene_active and modal == null, 600)
	var pushed: bool = player.cell == Vector2i(9, 5) and not has_event("BOUGHT_MUSEUM_TICKET")
	# 2) With money -> the ticket costs 50 and opens the way.
	player_money = 500
	player.place(Vector2i(9, 4))
	_on_player_moved(Vector2i(9, 4))
	await _drive_bill(func() -> bool: return has_event("BOUGHT_MUSEUM_TICKET") and not cutscene_active and modal == null, 600)
	var bought: bool = has_event("BOUGHT_MUSEUM_TICKET") and player_money == 450
	# 3) Ticket holder stepping on the aisle again: waved through, not pushed.
	player.place(Vector2i(10, 4))
	_on_player_moved(Vector2i(10, 4))
	await _drive_bill(func() -> bool: return not cutscene_active and modal == null, 600)
	var waved: bool = player.cell == Vector2i(10, 4) and player_money == 450
	# 4) The back-way amber chat (player behind the counter at (13,4), YES -> the lab hint).
	player.place(Vector2i(13, 4)); player.facing = 2       # face LEFT -> the receptionist at (12,4)
	interact(player)
	await _drive_bill(func() -> bool: return not cutscene_active and modal == null, 600)
	var chatted: bool = player.cell == Vector2i(13, 4)     # no push from the back-way chat
	print("[museumtest] pushed_back=%s bought=%s waved_through=%s back_chat=%s" % [
		pushed, bought, waved, chatted])
	# 5) gh #71: the fossil displays pop the skeleton pic + plaque line (UP only).
	modal = null; textbox.visible = false
	player.place(Vector2i(2, 4)); player.facing = 1        # face UP at the AERODACTYL case (2,3)
	interact(player)
	var t := "" if textbox.pages.is_empty() else str(textbox.pages[0])
	var aero: bool = "AERODACTYL Fossil" in t and cutscene._pic != null
	await _drive_bill(func() -> bool: return not cutscene_active and modal == null, 600)
	var cleared: bool = cutscene._pic == null
	player.place(Vector2i(2, 7)); player.facing = 1        # the KABUTOPS case (2,6)
	interact(player)
	t = "" if textbox.pages.is_empty() else str(textbox.pages[0])
	var kabu: bool = "KABUTOPS Fossil" in t
	await _drive_bill(func() -> bool: return not cutscene_active and modal == null, 600)
	print("[museumtest] fossils: aero_pic=%s cleared_after=%s kabutops=%s (expect true true true)" % [
		aero, cleared, kabu])
	print("[museumtest] PASS=%s" % (pushed and bought and waved and chatted and aero and cleared and kabu))
	get_tree().quit()


func _fossiltest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_bag = {}
	# Mt. Moon: take the DOME FOSSIL; the HELIX one becomes unreachable.
	load_world("MtMoonB2F")
	var helix = _npc_by_key("SPRITE_FOSSIL@13,6")
	var both_shown: bool = _npc_by_key("SPRITE_FOSSIL@12,6") != null and _npc_by_key("SPRITE_FOSSIL@12,6").shown \
		and helix != null and helix.shown
	player.place(Vector2i(12, 7)); player.facing = 1                 # face UP -> DOME fossil at (12,6)
	interact(player)
	await _drive_bill(func() -> bool: return has_event("GOT_DOME_FOSSIL") and not cutscene_active and modal == null, 800)
	var dome_ok: bool = player_bag.has("DOME FOSSIL") and not helix.shown
	load_world("MtMoonB2F")
	var fossils_gone: bool = _npc_by_key("SPRITE_FOSSIL@12,6") == null or not _npc_by_key("SPRITE_FOSSIL@12,6").shown
	# Pewter Museum: receive the OLD AMBER.
	load_world("Museum1F")
	player.place(Vector2i(15, 3)); player.facing = 1                 # face UP -> scientist at (15,2)
	interact(player)
	await _drive_bill(func() -> bool: return has_event("GOT_OLD_AMBER") and not cutscene_active and modal == null, 800)
	var amber_ok: bool = player_bag.has("OLD AMBER")
	# Cinnabar Lab: give the DOME FOSSIL, walk away, and come back for KABUTO.
	player_party = [make_mon("charmander", 10, ["SCRATCH"])]
	load_world("CinnabarLabFossilRoom")
	cutscene.revive_fossil()
	await _drive_bill(func() -> bool: return has_event("GAVE_FOSSIL_TO_LAB") and not cutscene_active and modal == null, 800)
	var gave_ok: bool = fossil_mon == "kabuto" and not player_bag.has("DOME FOSSIL") and has_event("LAB_STILL_REVIVING_FOSSIL")
	cutscene.revive_fossil()                                          # still reviving -> no mon
	await _drive_bill(func() -> bool: return not cutscene_active and modal == null, 400)
	var waiting_ok: bool = player_party.size() == 1
	load_world("CinnabarIsland")                                     # leaving finishes the revival
	var cleared_ok: bool = not has_event("LAB_STILL_REVIVING_FOSSIL")
	load_world("CinnabarLabFossilRoom")
	cutscene.revive_fossil()
	await _drive_bill(func() -> bool: return not has_event("GAVE_FOSSIL_TO_LAB") and not cutscene_active and modal == null, 800)
	var revived_ok: bool = player_party.size() == 2 and str(player_party[1]["species"]) == "kabuto" \
		and int(player_party[1]["level"]) == 30 and fossil_mon == ""
	var pass_all: bool = both_shown and dome_ok and fossils_gone and amber_ok and gave_ok \
		and waiting_ok and cleared_ok and revived_ok
	print("[fossiltest] dome=%s gone=%s amber=%s gave=%s waiting=%s cleared=%s revived=%s" % [
		dome_ok, fossils_gone, amber_ok, gave_ok, waiting_ok, cleared_ok, revived_ok])
	print("[fossiltest] PASS=%s" % pass_all)
	get_tree().quit()


func _gifttest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	# --- Eevee: a direct gift Poké Ball (no yes/no). ---
	player_party = [make_mon("charmander", 10, ["SCRATCH"])]
	pc_box = []
	load_world("CeladonMansionRoofHouse")
	var eevee_shown: bool = _npc_by_key("SPRITE_POKE_BALL@4,3") != null and _npc_by_key("SPRITE_POKE_BALL@4,3").shown
	player.place(Vector2i(5, 3)); player.facing = 2                # face LEFT -> ball at (4,3), on its table (gh #84)
	interact(player)
	await _drive_bill(func() -> bool: return has_event("GOT_EEVEE") and not cutscene_active and modal == null, 800)
	var eevee_ok: bool = eevee_shown and player_party.size() == 2 \
		and str(player_party[1]["species"]) == "eevee" and int(player_party[1]["level"]) == 25
	load_world("CeladonMansionRoofHouse")
	var eevee_gone: bool = _npc_by_key("SPRITE_POKE_BALL@4,3") == null or not _npc_by_key("SPRITE_POKE_BALL@4,3").shown
	# --- Hitmon: pick HITMONLEE; HITMONCHAN vanishes; can't get a second. ---
	player_party = [make_mon("charmander", 10, ["SCRATCH"])]
	load_world("FightingDojo")
	var both_shown: bool = _npc_by_key("SPRITE_POKE_BALL@4,1").shown and _npc_by_key("SPRITE_POKE_BALL@5,1").shown
	player.place(Vector2i(4, 2)); player.facing = 1               # face UP -> HITMONLEE ball at (4,1)
	interact(player)
	await _drive_bill(func() -> bool: return has_event("GOT_HITMONLEE") and not cutscene_active and modal == null, 800)
	var lee_ok: bool = player_party.size() == 2 and str(player_party[1]["species"]) == "hitmonlee" \
		and int(player_party[1]["level"]) == 30
	var chan_gone: bool = not _npc_by_key("SPRITE_POKE_BALL@5,1").shown    # both balls vanish
	# Greedy guard: a second Hitmon is refused.
	cutscene.hitmon_gift("hitmonchan", null)
	await _drive_bill(func() -> bool: return not cutscene_active and modal == null, 400)
	var no_second: bool = player_party.size() == 2 and not has_event("GOT_HITMONCHAN")
	# --- Magikarp salesman: L5 for ¥500. ---
	player_party = [make_mon("charmander", 10, ["SCRATCH"])]
	player_money = 600
	cutscene.magikarp_salesman()
	await _drive_bill(func() -> bool: return has_event("BOUGHT_MAGIKARP") and not cutscene_active and modal == null, 800)
	var karp_ok: bool = player_money == 100 and player_party.size() == 2 \
		and str(player_party[1]["species"]) == "magikarp" and int(player_party[1]["level"]) == 5
	var pass_all: bool = eevee_ok and eevee_gone and both_shown and lee_ok and chan_gone and no_second and karp_ok
	print("[gifttest] eevee=%s gone=%s hitmon(both=%s lee=%s chanGone=%s noSecond=%s) karp=%s" % [
		eevee_ok, eevee_gone, both_shown, lee_ok, chan_gone, no_second, karp_ok])
	print("[gifttest] PASS=%s" % pass_all)
	get_tree().quit()


func _legendtest() -> void:
	await get_tree().process_frame
	story_events = {}
	# All four static legendaries spawn with the right species + level.
	var want := {"PowerPlant": ["zapdos", 50], "SeafoamIslandsB4F": ["articuno", 50],
		"VictoryRoad2F": ["moltres", 50], "CeruleanCaveB1F": ["mewtwo", 70]}
	var spawn_ok := true
	for m in want:
		load_world(m)
		var found := false
		for n in npcs:
			if n.wild_species == want[m][0] and n.wild_level == int(want[m][1]) and n.shown:
				found = true
		if not found:
			spawn_ok = false
			print("[legendtest] MISSING %s on %s" % [want[m][0], m])
	# Power Plant also hides Voltorbs/Electrodes (disguised wild battles).
	load_world("PowerPlant")
	var z = null
	var voltorbs := 0
	for n in npcs:
		if n.wild_species == "zapdos":
			z = n
		if n.wild_species == "voltorb" and n.shown:
			voltorbs += 1
	var voltorb_ok: bool = voltorbs == 6
	# Interacting with Zapdos starts a catchable L50 battle.
	cutscene.static_encounter(z)
	await get_tree().process_frame
	var battle_ok: bool = modal == battle and str(battle.enemy_mon["species"]) == "zapdos" \
		and int(battle.enemy_mon["level"]) == 50
	# Winning sets the flag, removes the sprite, and it doesn't respawn on reload.
	battle.won = true
	battle.finished.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var flag_ok: bool = has_event("CAUGHT_STATIC_PowerPlant_4_9") and not z.shown
	load_world("PowerPlant")
	var respawn := false
	var voltorbs2 := 0
	for n in npcs:
		if n.wild_species == "zapdos" and n.shown:
			respawn = true
		if n.wild_species == "voltorb" and n.shown:
			voltorbs2 += 1
	var isolate_ok: bool = voltorbs2 == 6           # beating Zapdos didn't hide the Voltorbs
	var pass_all: bool = spawn_ok and battle_ok and flag_ok and not respawn and voltorb_ok and isolate_ok
	print("[legendtest] spawn=%s battle=%s flag=%s noRespawn=%s voltorbs=%d/%d" % [
		spawn_ok, battle_ok, flag_ok, not respawn, voltorbs, voltorbs2])
	print("[legendtest] PASS=%s" % pass_all)
	get_tree().quit()


func _rodtest() -> void:
	await get_tree().process_frame
	# Old Rod always hooks Magikarp L5.
	var old := _rod_encounter("OLD ROD")
	var old_ok: bool = old["bite"] and old["species"] == "magikarp" and int(old["level"]) == 5
	# Good Rod: bites only GOLDEEN / POLIWAG at L10 (global).
	var gsp := {}
	var gbites := 0
	var glvl_ok := true
	for i in 400:
		var e := _rod_encounter("GOOD ROD")
		if e["bite"]:
			gbites += 1
			gsp[str(e["species"])] = true
			if int(e["level"]) != 10:
				glvl_ok = false
	var good_ok: bool = gbites > 0 and glvl_ok and gsp.has("goldeen") and gsp.has("poliwag") and gsp.size() == 2
	# Super Rod on Cerulean City (Group3: PSYDUCK/GOLDEEN/KRABBY at L15).
	center_label = "CeruleanCity"
	var ssp := {}
	var sbites := 0
	var slvl_ok := true
	for i in 600:
		var e := _rod_encounter("SUPER ROD")
		if e["bite"]:
			sbites += 1
			ssp[str(e["species"])] = true
			if int(e["level"]) != 15:
				slvl_ok = false
	var super_ok: bool = sbites > 0 and slvl_ok and ssp.has("psyduck") and ssp.has("goldeen") \
		and ssp.has("krabby") and ssp.size() == 3
	# Super Rod where there's no fishing group: never a bite.
	center_label = "PewterCity"
	var nofish_ok := true
	for i in 60:
		if _rod_encounter("SUPER ROD")["bite"]:
			nofish_ok = false
	var pass_all: bool = old_ok and good_ok and super_ok and nofish_ok
	print("[rodtest] old=%s good=%s(%d bites %s) super=%s(%d bites %s) nogroup=%s" % [
		old_ok, good_ok, gbites, str(gsp.keys()), super_ok, sbites, str(ssp.keys()), nofish_ok])
	print("[rodtest] PASS=%s" % pass_all)
	get_tree().quit()


func _prizetest() -> void:
	await get_tree().process_frame
	load_world("GameCornerPrizeRoom")
	player_bag = {"COIN CASE": 1}
	player_party = [make_mon("charmander", 5, [])]
	pc_box = []
	var P = cutscene._PRIZES
	# Buy ABRA (180): joins the party, coins deducted.
	player_coins = 200
	var r_abra: int = cutscene.give_prize(P[0][0], false)
	var abra_ok: bool = r_abra == 0 and player_party.size() == 2 and player_coins == 20
	# Can't afford CLEFAIRY (500) with 20 coins: nothing changes.
	var r_poor: int = cutscene.give_prize(P[0][1], false)
	var poor_ok: bool = r_poor == 1 and player_party.size() == 2 and player_coins == 20
	# Buy a TM (DRAGON RAGE / TM23, 3300): lands in the bag.
	player_coins = 4000
	var r_tm: int = cutscene.give_prize(P[2][0], true)
	var tm_ok: bool = r_tm == 0 and player_bag.has("TM23") and player_coins == 700
	# Party full -> the prize mon goes to the box.
	player_party = []
	for i in 6:
		player_party.append(make_mon("rattata", 5, []))
	player_coins = 9999
	var r_box: int = cutscene.give_prize(P[1][2], false)   # PORYGON, 9999
	var box_ok: bool = r_box == 0 and pc_box.size() == 1 and player_coins == 0
	var pass_all: bool = abra_ok and poor_ok and tm_ok and box_ok
	print("[prizetest] abra=%s poor=%s tm=%s box=%s" % [abra_ok, poor_ok, tm_ok, box_ok])
	print("[prizetest] PASS=%s" % pass_all)
	get_tree().quit()


func _saffrontest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_bag = {}
	load_world("Route6Gate")
	# 1) no drink -> thirsty line, then WALK back a tile (gh #113: a real step, not a teleport). Drive the
	# push-back cutscene: advance the text, wait for the walk step to finish.
	player.place(Vector2i(3, 2))
	_on_player_moved(Vector2i(3, 2))
	var walked_back := false
	for _i in 300:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		if not cutscene_active:
			walked_back = player.cell == Vector2i(3, 3)   # stepped south (PUSH) off the checkpoint
			break
	var blocked: bool = not has_event("GAVE_SAFFRON_GUARDS_DRINK") and walked_back
	modal = null; textbox.visible = false
	# 2) with a drink -> consumed, all gates open.
	player_bag = {"FRESH WATER": 1}
	player.place(Vector2i(3, 2))
	_on_player_moved(Vector2i(3, 2))
	var paid: bool = has_event("GAVE_SAFFRON_GUARDS_DRINK") and not player_bag.has("FRESH WATER")
	modal = null; textbox.visible = false
	# 3) once paid, the gate no longer stops you.
	player.place(Vector2i(3, 2))
	_on_player_moved(Vector2i(3, 2))
	var open_after: bool = player.cell == Vector2i(3, 2)
	print("[saffrontest] blocked=%s(at %s) paid=%s open_after=%s" % [
		blocked, str(player.cell), paid, open_after])
	get_tree().quit()


func _keybindtest() -> void:
	await get_tree().process_frame
	var gp := ProjectSettings.globalize_path("user://keybinds.cfg")
	DirAccess.remove_absolute(gp)                 # clean slate
	Keybinds.apply()                              # writes the default config
	var created: bool = FileAccess.file_exists("user://keybinds.cfg")
	var default_z: bool = _action_has_key("ui_accept", KEY_Z)
	var default_arrows: bool = _action_has_key("ui_up", KEY_UP) and _action_has_key("ui_left", KEY_LEFT)
	# START and SELECT are their own buttons (the faithfulness gap this fixes).
	var has_start: bool = _action_has_key("p_start", KEY_ENTER) and _action_has_key("p_start", KEY_ESCAPE)
	var has_select: bool = _action_has_key("p_select", KEY_BACKSPACE)
	# remap A from Z to Q and re-apply.
	var cfg := ConfigFile.new(); cfg.load("user://keybinds.cfg")
	cfg.set_value("controls", "a", "Q"); cfg.save("user://keybinds.cfg")
	Keybinds.apply()
	var remap_q: bool = _action_has_key("ui_accept", KEY_Q)
	var old_gone: bool = not _action_has_key("ui_accept", KEY_Z)
	DirAccess.remove_absolute(gp)                 # cleanup -> next launch regenerates defaults
	# SELECT reorders bag items: hold item 0, then SELECT item 1 to swap them.
	player_bag = {"POTION": 1, "ANTIDOTE": 2, "POKé BALL": 3}
	_open_bag()
	_on_menu_select(0)
	var held: bool = _swap_first == 0
	_on_menu_select(1)
	var reordered: bool = menu_keys[0] == "ANTIDOTE" and menu_keys[1] == "POTION" \
		and player_bag.keys()[0] == "ANTIDOTE" and _swap_first == -1
	# gh #57: the redrawn list keeps its CANCEL row (a swap used to drop it) ...
	var cancel_kept: bool = menu.items.size() == 4 and str(menu.items[-1]) == "CANCEL" \
		and str(menu.items[0]) == "ANTIDOTE" and int(menu.qtys[0]) == 2
	# ... SELECT on CANCEL is ignored, and re-SELECTing the held item keeps it held.
	_on_menu_select(3)
	var cancel_ignored: bool = _swap_first == -1
	_on_menu_select(1)
	_on_menu_select(1)
	var self_kept: bool = _swap_first == 1
	menu.chosen.emit(-1)                          # close the bag (saves the cursor)
	# The player's PC item lists are ITEMLISTMENUs too (players_pc.asm): they reorder as well.
	pc_items = {"POTION": 2, "POKé BALL": 1}
	_pc_item_list("withdraw")
	_on_menu_select(0)
	_on_menu_select(1)
	var pc_swap: bool = pc_items.keys()[0] == "POKé BALL" and str(menu.items[-1]) == "CANCEL"
	print("[keybindtest] created=%s default_Z=%s arrows=%s start=%s select=%s remap_Q=%s old_Z_gone=%s held=%s reorder=%s cancel_kept=%s cancel_ignored=%s self_kept=%s pc_swap=%s" % [
		created, default_z, default_arrows, has_start, has_select, remap_q, old_gone, held,
		reordered, cancel_kept, cancel_ignored, self_kept, pc_swap])
	get_tree().quit()


func _safaritest() -> void:
	await get_tree().process_frame
	story_events = {}; player_money = 1000
	player_party = [make_mon("pidgey", 20, ["TACKLE"])]
	load_world("SafariZoneGate")
	# 1) gate: pay ¥500 -> 30 balls + 500 steps + enter the park.
	cutscene.safari_gate("SafariZoneCenter", 0)
	await _drive_bill(func() -> bool: return in_safari and not cutscene_active and modal == null, 800)
	var entered: bool = in_safari and safari_balls == 30 and safari_steps == 500 \
		and player_money == 500 and center_label == "SafariZoneCenter"
	# 2) the step counter ticks down (on a normal, non-warp cell).
	var safe := Vector2i(-1, -1)
	for y in gh:
		for x in gw:
			if is_walkable(Vector2i(x, y)) and _warp_at(Vector2i(x, y)) == null:
				safe = Vector2i(x, y); break
		if safe.x >= 0: break
	player.place(safe)
	safari_steps = 5
	_on_player_moved(safe)
	var step_dec: bool = safari_steps == 4 or modal == battle   # battle = a grass encounter
	modal = null; textbox.visible = false
	# 3) the timer running out (gh #171). SafariZoneGameOver rings the PA and reads the announcement
	#    out, and only THEN sets wSafariZoneGameOver — which is what makes OverworldLoop take the
	#    WarpFound2 branch. So the eject is the LAST beat, not the first: assert the order, not just
	#    the destination. At the gate, SafariZoneGateLeavingSafariScript signs you out and walks you
	#    south (PAD_DOWN, c=3) from the park-side door.
	load_world("SafariZoneCenter")
	in_safari = true; safari_steps = 0; safari_balls = 7
	cutscene.safari_game_over()
	for i in 30:                                       # the PA announcement plays inside the park
		await get_tree().process_frame
		if textbox.visible: break
	var pa_before_warp: bool = textbox.visible and center_label == "SafariZoneCenter"
	await _drive_bill(func() -> bool: return not cutscene_active, 600)
	var at_gate: bool = center_label == "SafariZoneGate"
	var walked_out: bool = player.cell == Vector2i(3, 3)   # (3,0) park-side door, then 3 steps down
	var game_over: bool = not in_safari and safari_balls == 0 and not has_event("IN_SAFARI_ZONE")
	print("[safaritest] entered=%s(money=%d) step_dec=%s pa_before_warp=%s at_gate=%s walked_out=%s game_over=%s" % [
		entered, player_money, step_dec, pa_before_warp, at_gate, walked_out, game_over])
	get_tree().quit()


func _safaribattletest() -> void:
	await get_tree().process_frame
	player_name = "RED"
	player_party = [make_mon("pidgey", 20, ["TACKLE"])]
	# 1) menu is the safari menu.
	safari_balls = 30
	start_safari_battle("rattata", 22)
	await _drain_battle_to_menu()
	var safari_menu: bool = battle.is_safari and battle.menu_items == battle.SAFARI_MENU
	# gh #169: shoot the menu screen — SAFARI_BATTLE_MENU_TEMPLATE is one full-width box with
	# BALL×nn/BAIT/THROW ROCK/RUN at the safari coords, no mid-screen ball counter.
	for i in 600:
		if battle.state == "menu":
			break
		if battle.state == "msg":
			battle._next_msg()
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://safari_menu.png")
	print("[safaribattletest] shot state=%s" % battle.state)
	var base_catch := int(battle.safari_catch)
	# 2) ROCK doubles the catch rate.
	battle.cursor = 2; battle._choose_action()
	var rock_ok: bool = battle.safari_catch == mini(255, base_catch * 2)
	# 3) fresh battle: BAIT halves the catch rate.
	start_safari_battle("rattata", 22)
	await _drain_battle_to_menu()
	var bc := int(battle.safari_catch)
	battle.cursor = 1; battle._choose_action()
	var bait_ok: bool = battle.safari_catch == bc >> 1
	# 4) fresh battle: BALL consumes a Safari Ball.
	start_safari_battle("rattata", 22)
	await _drain_battle_to_menu()
	safari_balls = 5
	battle.cursor = 0; battle._choose_action()
	var ball_ok: bool = safari_balls == 4
	await _drain_battle_to_menu()
	# 5) RUN ends the encounter.
	if modal == battle:
		battle.cursor = 3; battle._choose_action()
		await _drain_battle_to_menu()
		for i in 30:
			if modal == null: break
			if battle.state == "msg": battle._next_msg()
			await get_tree().process_frame
	var run_ended: bool = modal == null
	# 6) gh #180: the LAST ball ends the encounter on the spot (caught or broke free — core.asm
	#    .outOfSafariBallsText), and back on the overworld SafariZoneCheck ends the whole game:
	#    the PA ceremony ejects to the gate.
	in_safari = true
	safari_balls = 1
	start_safari_battle("rattata", 22)
	await _drain_battle_to_menu()
	battle.cursor = 0; battle._choose_action()
	for i in 2000:
		if center_label == "SafariZoneGate" and not cutscene_active:
			break
		if modal == battle and battle.state == "msg":
			battle._next_msg()             # the throw + PA lines (or the catch flow's messages)
		elif textbox.active and textbox.visible:
			textbox.advance()              # the game-over ceremony texts
		elif modal == naming:
			naming.done.emit("")           # a lucky last-ball catch offers a nickname
		await get_tree().process_frame
	var zero_ball_end: bool = safari_balls == 0 and not in_safari \
		and center_label == "SafariZoneGate" and modal == null
	print("[safaribattletest] safari_menu=%s rock_doubles=%s bait_halves=%s ball_used=%s ended=%s zero_ball_end(gh#180)=%s" % [
		safari_menu, rock_ok, bait_ok, ball_ok, run_ended, zero_ball_end])
	get_tree().quit()


func _silphtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"; rival_name = "BLUE"; player_starter = "charmander"; rival_starter = "squirtle"
	player_party = [make_mon("charmander", 55, ["EMBER"])]
	player_bag = {}
	# 1) Lapras gift (7F worker).
	load_world("SilphCo7F")
	player.place(Vector2i(1, 6)); player.facing = 1   # face UP -> worker at (1,5)
	interact(player)
	var g := 0
	while not (has_event("GOT_LAPRAS") and not cutscene_active and modal == null) and g < 600:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	var got_lapras := false
	for m in player_party:
		if str(m["species"]) == "lapras":
			got_lapras = true
	modal = null; textbox.visible = false
	# 2) Saffron rival (7F).
	player.place(Vector2i(3, 6)); player.facing = 0   # face DOWN -> rival at (3,7); (3,8) is wall (gh #84)
	interact(player)
	var r_enemy := ""
	var wf := false
	for i in 4000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			r_enemy = str(battle.trainer_name)
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); wf = true
		if wf and not cutscene_active and modal == null:
			break
	var rival_beat := has_event("BEAT_SILPH_CO_RIVAL")
	# 3) Giovanni #2 (11F).
	load_world("SilphCo11F")
	player.place(Vector2i(6, 10)); player.facing = 1   # face UP -> Giovanni at (6,9)
	interact(player)
	wf = false
	for i in 4000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); wf = true
		if wf and not cutscene_active and modal == null:
			break
	var gio_beat := has_event("BEAT_SILPH_CO_GIOVANNI")
	# 4) President -> MASTER BALL.
	player.place(Vector2i(6, 5)); player.facing = 3   # face RIGHT -> president at (7,5); (7,6) is wall (gh #84)
	interact(player)
	g = 0
	while not (has_event("GOT_MASTER_BALL") and modal == null) and g < 600:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	print("[silphtest] lapras=%s rival_beat=%s(%s) giovanni2=%s master_ball=%s" % [
		got_lapras, rival_beat, r_enemy, gio_beat, player_bag.has("MASTER BALL")])
	get_tree().quit()


func _flytest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"; badges = ["THUNDERBADGE"]; player_bag = {}
	player_party = [make_mon("pidgeot", 40, ["TACKLE"])]
	# 1) HM02 from the Route 16 house girl.
	load_world("Route16FlyHouse")
	player.place(Vector2i(1, 3)); player.facing = 3   # face RIGHT -> girl at (2,3); (3,3) is her table (gh #84)
	interact(player)
	var g := 0
	while not (has_event("GOT_HM02") and not cutscene_active and modal == null) and g < 800:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	var got_hm02: bool = player_bag.has("HM02")
	# 2) teach FLY.
	selected_item = "HM02"; _teach(0)
	var learned := false
	for mv in player_party[0]["moves"]:
		if str(mv["move"]) == "FLY":
			learned = true
	modal = null; textbox.visible = false
	# 3) visiting towns unlocks them as FLY destinations.
	load_world("PewterCity")
	load_world("CeruleanCity")
	var visited: Array = visited_fly.duplicate()
	# 4) FLY from Cerulean to Pewter.
	_open_party_view(); _on_menu_chosen(0); _on_menu_chosen(_mon_menu_opts.find("FLY"))
	var town_map_shown: bool = modal == townmap and townmap.is_fly_mode()
	assert(town_map_shown, "FLY should open the Town Map picker")
	# Same bounded, frame-separated cursor stepping as _pt_fly_to (gh #27): handle_input()
	# reads is_action_just_pressed, so the press needs its own frame — and the loop needs a
	# cap, or a cursor that won't move hangs the test instead of failing it.
	var fly_hops := 0
	while townmap.current_fly_label() != "PewterCity":
		assert(fly_hops <= townmap.fly_dests.size(),
			"FLY cursor never reached PewterCity (stuck on '%s')" % townmap.current_fly_label())
		if fly_hops > townmap.fly_dests.size():
			break
		Input.action_release("ui_up")
		await get_tree().process_frame
		Input.action_press("ui_up")
		townmap.handle_input()
		Input.action_release("ui_up")
		await get_tree().process_frame
		fly_hops += 1
	Input.action_press("ui_accept")
	townmap.handle_input()
	Input.action_release("ui_accept")
	# gh #144: the BIRD departure is drawing — the player hidden, the bird swooping off toward the
	# top-right (FlyAnimationScreenCoords1). Shoot it mid-swoop for the visual check.
	var bird_seen := false
	for i in 600:
		if cutscene._fly_bird_tex != null and cutscene._fly_bird.x >= 0x70 and cutscene._fly_bird_right:
			bird_seen = true
			break
		await get_tree().process_frame
	if bird_seen and not player.spr.visible:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://fly_bird.png")
	await _drive_until(func() -> bool: return center_label == "PewterCity" and not cutscene_active, 800)
	assert(center_label == "PewterCity" and not cutscene_active, "FLY should arrive in Pewter City")
	print("[flytest] got_hm02=%s learned=%s visited=%s town_map_shown=%s bird_anim(gh#144)=%s flew_to_pewter=%s" % [
		got_hm02, learned, str(visited), town_map_shown, bird_seen and player.spr.visible,
		center_label == "PewterCity"])
	get_tree().quit()


func _elitetest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"; rival_name = "BLUE"; player_starter = "charmander"
	player_party = [make_mon("charmander", 65, ["EMBER"])]
	# 1) An Elite Four member via the generic trainer system (Lorelei).
	load_world("LoreleisRoom")
	var lorelei = _npc_by_key("SPRITE_LORELEI@5,2")
	player.place(Vector2i(5, 3)); player.facing = 1
	interact(player)
	var l_class: String = str(lorelei.trainer_class) if lorelei else "?"
	var l_engaged: bool = cutscene_active or modal == battle
	var wf := false
	for i in 4000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); wf = true
		if wf and not cutscene_active and modal == null:
			break
	var l_beat: bool = lorelei != null and defeated_trainers.has(trainer_id(lorelei))
	# 2) The Champion (rival) -> Hall of Fame.
	load_world("ChampionsRoom")
	player.place(Vector2i(4, 3)); player.facing = 1
	interact(player)
	var c_engaged: bool = cutscene_active
	var enemy := ""
	wf = false
	for i in 5000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			enemy = str(battle.trainer_name)
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); wf = true
		if wf and not cutscene_active and modal == null:
			break
	print("[elitetest] lorelei: class=%s engaged=%s beat=%s | champion: engaged=%s trainer=%s beat=%s hall_of_fame=%s" % [
		l_class, l_engaged, l_beat, c_engaged, enemy, has_event("BEAT_CHAMPION"), has_event("HALL_OF_FAME")])
	get_tree().quit()


func _strengthtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"; badges = ["RAINBOWBADGE"]
	player_bag = {"GOLD TEETH": 1}
	player_party = [make_mon("machoke", 40, ["TACKLE"])]
	# 1) Warden trades the GOLD TEETH for HM04.
	load_world("WardensHouse")
	player.place(Vector2i(2, 4)); player.facing = 1   # face UP -> Warden at (2,3)
	interact(player)
	var g := 0
	while not (has_event("GOT_HM04") and not cutscene_active and modal == null) and g < 800:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	var got_hm04: bool = player_bag.has("HM04") and not player_bag.has("GOLD TEETH")
	# 2) teach STRENGTH.
	selected_item = "HM04"; _teach(0)
	var learned := false
	for mv in player_party[0]["moves"]:
		if str(mv["move"]) == "STRENGTH":
			learned = true
	modal = null; textbox.visible = false
	# 3) activate STRENGTH via the field-move menu.
	_open_party_view(); _on_menu_chosen(0); _on_menu_chosen(_mon_menu_opts.find("STRENGTH"))
	var activated: bool = strength_active
	modal = null; textbox.visible = false
	# 4) push a boulder one tile.
	load_world("VictoryRoad1F")
	strength_active = true
	if audio:
		audio.log_sfx = true
		audio.sfx_log = []
	var boulder = null
	for n in npcs:
		if str(n.key).begins_with("SPRITE_BOULDER@"):
			boulder = n; break
	var pushed := false
	var two_push_ok := false     # gh #129: the two-push rule + its resets (acceptance criteria)
	var old := Vector2i(-99, -99)
	if boulder:
		old = boulder.cell
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_boulder_reset_tried()
			var first_moved: bool = try_push_boulder(boulder.cell, d)     # 1st push: arms the flag, no move
			var second_moved: bool = try_push_boulder(boulder.cell, d)    # 2nd push: moves it if beyond is clear
			if second_moved:
				pushed = true
				# The 1st push must NOT have moved it; after the move the count resets, so another single
				# same-direction push only re-arms (no move); and a different direction re-arms too.
				var reset_after_move: bool = not try_push_boulder(boulder.cell, d)
				_boulder_reset_tried()
				try_push_boulder(boulder.cell, d)                          # arm direction d
				var diff_dir_rearms: bool = not try_push_boulder(boulder.cell, -d)
				two_push_ok = (not first_moved) and reset_after_move and diff_dir_rearms
				break
	# gh #185: the slide plays SFX_PUSH_BOULDER, then the dust puff runs (a transient
	# sprite beneath the NPCs) and SFX_CUT closes the beat (dust_smoke.asm).
	var saw_dust := false
	g = 0
	while g < 300:
		await get_tree().process_frame
		if not saw_dust and _smoke_texs.size() > 0:
			for ch in get_children():
				if ch is Sprite2D and (ch.texture == _smoke_texs[0] or ch.texture == _smoke_texs[1]):
					saw_dust = true
		if saw_dust and audio and "cut" in audio.sfx_log:
			break
		g += 1
	var dust_ok: bool = saw_dust and audio != null and "push_boulder" in audio.sfx_log \
		and "cut" in audio.sfx_log
	# strength off -> no push.
	strength_active = false
	var blocked_no_strength := boulder != null and not try_push_boulder(boulder.cell, Vector2i(1, 0))
	var pass_all: bool = got_hm04 and learned and activated and pushed and two_push_ok \
		and dust_ok and blocked_no_strength
	print("[strengthtest] got_hm04=%s learned=%s activated=%s pushed=%s two_push=%s moved=%s dust=%s no_strength_blocked=%s" % [
		got_hm04, learned, activated, pushed, two_push_ok, boulder != null and boulder.cell != old, dust_ok, blocked_no_strength])
	print("[strengthtest] PASS=%s" % pass_all)
	get_tree().quit()


func _surftest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"; player_bag = {}; badges = ["SOULBADGE"]
	player_party = [make_mon("squirtle", 30, ["TACKLE"])]
	# 1) HM03 from the Safari Zone secret-house guru.
	load_world("SafariZoneSecretHouse")
	player.place(Vector2i(3, 4)); player.facing = 1   # face UP -> guru at (3,3)
	interact(player)
	var g := 0
	while not (has_event("GOT_HM03") and not cutscene_active and modal == null) and g < 800:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	var got_hm03: bool = player_bag.has("HM03")
	# 2) teach SURF.
	selected_item = "HM03"; _teach(0)
	var learned := false
	for mv in player_party[0]["moves"]:
		if str(mv["move"]) == "SURF":
			learned = true
	modal = null; textbox.visible = false
	# 3) surf: can't walk into water, but SURF hops on and water becomes passable; land dismounts.
	load_world("PalletTown")
	var water := Vector2i(-1, -1)
	for y in gh:
		for x in gw:
			if _is_water(Vector2i(x, y)):
				water = Vector2i(x, y); break
		if water.x >= 0: break
	var land := water + Vector2i(0, -1)
	player.place(land); player.facing = 0             # face DOWN -> front is the water
	var blocked_walking: bool = not is_walkable(water)
	_open_party_view(); _on_menu_chosen(0); _on_menu_chosen(_mon_menu_opts.find("SURF"))
	var mounted: bool = surfing and player.cell == water
	# gh #170: mounting swaps the sheet to the SEEL — Gen 1's surfing player sprite
	# (LoadSurfingPlayerSpriteGraphics loads SeelSprite).
	var surf_sprite: bool = player._sheet == "seel" \
		and str(player.spr.texture.resource_path).ends_with("seel.png")
	modal = null; textbox.visible = false
	player.cell = land                                # step back onto land
	_on_player_moved(land)
	var dismounted: bool = not surfing
	# ...and dismounting swaps straight back (.stopSurfing calls LoadPlayerSpriteGraphics).
	var walk_sprite: bool = player._sheet == "red" \
		and str(player.spr.texture.resource_path).ends_with("red.png")
	print("[surftest] got_hm03=%s learned_surf=%s blocked_walking=%s mounted=%s surf_sprite(gh#170)=%s dismounted=%s walk_sprite=%s" % [
		got_hm03, learned, blocked_walking, mounted, surf_sprite, dismounted, walk_sprite])
	get_tree().quit()


func _snorlaxtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_bag = {"POKé FLUTE": 1}
	player_party = [make_mon("charmander", 50, ["EMBER"])]
	load_world("Route12")
	var snorlax = _npc_by_key("SPRITE_SNORLAX@10,62")
	var snorlax_shown: bool = snorlax != null and snorlax.shown
	player.place(Vector2i(10, 63)); player.facing = 1   # face UP -> SNORLAX at (10,62)
	selected_item = "POKé FLUTE"; _use_poke_flute()
	var engaged: bool = cutscene_active or modal == battle
	var enemy := ""
	var win_forced := false
	for i in 4000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			enemy = "%s L%d" % [battle.enemy_mon["species"], int(battle.enemy_mon["level"])]
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); win_forced = true
		if win_forced and not cutscene_active and modal == null:
			break
	var beat: bool = has_event("BEAT_SNORLAX_Route12")
	var gone: bool = not (snorlax != null and snorlax.shown)
	# Flute also cures party sleep when not facing a SNORLAX.
	modal = null; textbox.visible = false
	player.place(Vector2i(8, 5)); player.facing = 0    # a standable road cell, nothing faced (gh #84)
	player_party[0]["status"] = "slp"; player_party[0]["sleep"] = 3
	selected_item = "POKé FLUTE"; _use_poke_flute()
	var cured: bool = str(player_party[0]["status"]) == ""
	print("[snorlaxtest] shown=%s engaged=%s enemy=%s beat=%s gone=%s sleep_cured=%s" % [
		snorlax_shown, engaged, enemy, beat, gone, cured])
	get_tree().quit()


## gh #182 (reopened): play the REAL champion-room ceremony end to end and record every cell
## the player and OAK cross, relative to the rival at (4,2) — pixel truth for the
## walks-through-the-rival report. Ends when the Hall of Fame floor loads.
func _champwalktest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	rival_name = "BLUE"
	player_starter = "charmander"
	player_party = [make_mon("charmander", 62, ["EMBER"])]
	load_world("ChampionsRoom")
	player.place(Vector2i(3, 7))
	player.facing = 1
	set_event("CHAMPION_ROOM_ENTRY")               # armed by beating Lance (the walk-in trigger)
	map_script(center_label).on_enter()            # fires champion_entrance
	var rival = _npc_by_key("SPRITE_BLUE@4,2")
	var oak = _npc_by_key("SPRITE_OAK@3,7")
	var ptrace: Array = []
	var otrace: Array = []
	var rival_cells := {}
	var overlap := false
	var g := 0
	while g < 12000 and center_label == "ChampionsRoom":
		await get_tree().process_frame
		g += 1
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			battle.won = true; battle.blacked_out = false; battle.finished.emit()
		var pc: Vector2i = player.cell
		if ptrace.is_empty() or ptrace[-1] != pc:
			ptrace.append(pc)
		if is_instance_valid(oak) and oak.shown:
			var oc: Vector2i = oak.cell
			if otrace.is_empty() or otrace[-1] != oc:
				otrace.append(oc)
		if is_instance_valid(rival) and rival.shown:
			rival_cells[rival.cell] = true
			if pc == rival.cell or (is_instance_valid(oak) and oak.shown and oak.cell == rival.cell):
				overlap = true
	print("[champwalk] rival stood at %s  overlap_with_rival=%s (expect [(4, 2)] false)" % [
		str(rival_cells.keys()), overlap])
	print("[champwalk] player path: %s" % str(ptrace))
	print("[champwalk] oak path:    %s" % str(otrace))
	print("[champwalk] reached=%s (expect HallOfFame)" % center_label)
	get_tree().quit()


func _towerghosttest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_party = [make_mon("charmander", 50, ["EMBER"])]
	# 1a) MAROWAK ghost without the SILPH SCOPE -> blocked, no battle.
	player_bag = {}
	load_world("PokemonTower6F")
	player.place(Vector2i(10, 16))
	_on_player_moved(Vector2i(10, 16))
	var g := 0
	while cutscene_active and g < 200:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	var blocked_no_scope: bool = not has_event("BEAT_GHOST_MAROWAK") and modal != battle
	modal = null; textbox.visible = false
	# 1a2) A Tower wild encounter without the scope presents as the unfightable GHOST:
	# named GHOST, moves are "too scared", nobody takes damage; running is the way out.
	start_battle("gastly", 20)
	while battle.state != "menu" and modal == battle and g < 1200:
		await _press("ui_accept"); g += 1
	var ghost_name: String = str(battle.enemy_mon["name"])
	var php0: int = int(battle.player_mon["hp"])
	battle._resolve({"kind": "move", "idx": 0})
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	var scared: bool = int(battle.player_mon["hp"]) == php0 \
		and int(battle.enemy_mon["hp"]) == int(battle.enemy_mon["maxhp"])
	# A thrown BALL dodges (IsGhostBattle skips the capture calc): ball spent, not caught,
	# and the GHOST's turn is only its wail — the battle stays up.
	player_bag = {"POKé BALL": 1}
	battle._use_item("POKé BALL")
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	var ghost_dodge: bool = not battle.caught and modal == battle \
		and not player_bag.has("POKé BALL")
	battle.cursor = 3                                  # RUN always works vs the GHOST
	battle._choose_action()
	g = 0
	while modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	print("[towerghosttest] ghost: name=%s (expect GHOST) scared_no_damage=%s dodge=%s ran=%s" % [
		ghost_name, scared, ghost_dodge, modal == null])
	# 1b0) The unveil beat: GHOST through the intro, MAROWAK once the scope reveal lands;
	# and the ghost MAROWAK can't be caught.
	player_bag = {"SILPH SCOPE": 1, "POKé BALL": 2}
	battle.unveil = true
	start_battle("marowak", 30)
	g = 0
	while battle.state != "menu" and modal == battle and g < 1200:
		await _press("ui_accept"); g += 1
	var unveiled: bool = str(battle.enemy_mon["name"]) == "MAROWAK"
	battle._use_item("POKé BALL")
	g = 0
	while battle.state != "menu" and modal == battle and g < 600:
		await _press("ui_accept"); g += 1
	var ball_failed: bool = not battle.caught and modal == battle \
		and int(player_bag.get("POKé BALL", 0)) == 1        # the dodged ball IS spent
	print("[towerghosttest] unveil: marowak_after_intro=%s ball_failed=%s" % [unveiled, ball_failed])
	battle.won = true; battle.blacked_out = false; battle.finished.emit()
	battle.unveil = false
	modal = null; textbox.visible = false
	# 1b-doll) The POKé DOLL trick: a doll escape from the scripted MAROWAK counts as laying
	# it to rest (the Tower script keys on wBattleResult == 0, which the doll never writes).
	player_bag = {"SILPH SCOPE": 1, "POKé DOLL": 1}
	player.place(Vector2i(10, 16))
	_on_player_moved(Vector2i(10, 16))
	g = 0
	while modal != battle and g < 600:                 # the intro line, then the unveil battle
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	g = 0
	while battle.state != "menu" and modal == battle and g < 1200:
		await _press("ui_accept"); g += 1
	battle._use_item("POKé DOLL")
	g = 0
	while modal == battle and g < 600:
		await _press("ui_accept"); g += 1
	g = 0
	while cutscene_active and g < 400:                 # "The mother's soul was calmed..."
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	var doll_trick: bool = has_event("BEAT_GHOST_MAROWAK") \
		and int(player_bag.get("POKé DOLL", 0)) == 0
	print("[towerghosttest] doll trick: escaped_laid_to_rest=%s" % doll_trick)
	story_events.erase("BEAT_GHOST_MAROWAK")           # leg 1b re-earns it by winning
	modal = null; textbox.visible = false
	# 1b) with the SILPH SCOPE -> battle the MAROWAK, win.
	player_bag = {"SILPH SCOPE": 1}
	player.place(Vector2i(10, 16))
	_on_player_moved(Vector2i(10, 16))
	var enemy := ""
	var win_forced := false
	for i in 4000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			enemy = "%s L%d" % [battle.enemy_mon["species"], int(battle.enemy_mon["level"])]
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); win_forced = true
		if win_forced and not cutscene_active and modal == null:
			break
	var marowak_beat: bool = has_event("BEAT_GHOST_MAROWAK")
	# 2) Mr. Fuji on 7F -> rescue -> warp to his house.
	load_world("PokemonTower7F")
	player.place(Vector2i(10, 4)); player.facing = 1   # face UP -> Mr. Fuji at (10,3)
	interact(player)
	g = 0
	while center_label != "MrFujisHouse" and g < 600:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	var rescued: bool = has_event("RESCUED_MR_FUJI") and center_label == "MrFujisHouse"
	# 3) Mr. Fuji at home -> the POKé FLUTE.
	player.place(Vector2i(3, 2)); player.facing = 1   # face UP -> Mr. Fuji at (3,1)  # audit: map=MrFujisHouse
	interact(player)
	g = 0
	while not has_event("GOT_POKE_FLUTE") and g < 600:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	print("[towerghosttest] blocked_no_scope=%s enemy=%s marowak_beat=%s rescued=%s got_flute=%s" % [
		blocked_no_scope, enemy, marowak_beat, rescued, player_bag.has("POKé FLUTE")])
	get_tree().quit()


func _hideouttest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_party = [make_mon("charmander", 30, [])]
	load_world("GameCorner")
	var closed_before: bool = not is_walkable(Vector2i(17, 4))   # staircase hidden behind the wall
	player.place(Vector2i(9, 5)); player.facing = 1             # face UP -> poster at (9,4)
	interact(player)
	var found: bool = has_event("FOUND_ROCKET_HIDEOUT")
	var open_after: bool = is_walkable(Vector2i(17, 4))          # staircase now walkable -> warp
	load_world("RocketHideoutB1F")                              # the dungeon floors load
	var hideout_loads: bool = center_label == "RocketHideoutB1F"
	print("[hideouttest] closed_before=%s found=%s open_after=%s hideout_loads=%s" % [
		closed_before, found, open_after, hideout_loads])
	# B4F: Giovanni guards the SILPH SCOPE, then steps aside when beaten.
	story_events = {}
	player_party = [make_mon("charmander", 50, ["EMBER"])]
	load_world("RocketHideoutB4F")
	var giovanni = _npc_by_key("SPRITE_GIOVANNI@25,3")
	var giovanni_shown: bool = giovanni != null and giovanni.shown
	var scope_ball = _npc_by_key("SPRITE_POKE_BALL@25,2")
	var scope_is_silph: bool = scope_ball != null and str(scope_ball.item) == "SILPH SCOPE"
	player.place(Vector2i(24, 3)); player.facing = 3           # face RIGHT -> Giovanni at (25,3); (25,4) is wall (gh #84)
	interact(player)
	var engaged: bool = cutscene_active
	var win_forced := false
	for i in 4000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); win_forced = true
		if win_forced and not cutscene_active and modal == null:
			break
	print("[hideouttest] B4F: giovanni_shown=%s scope_is_silph=%s engaged=%s beat=%s giovanni_gone=%s" % [
		giovanni_shown, scope_is_silph, engaged, has_event("BEAT_ROCKET_HIDEOUT_GIOVANNI"),
		not (giovanni != null and giovanni.shown)])
	# Elevator (gh #22 delta): the door leads back to the boarding floor until the LIFT-KEY
	# panel picks a floor, which retargets the exits (RocketHideoutElevator.asm).
	modal = null; textbox.visible = false
	player_bag = {}
	load_world("RocketHideoutB1F")
	var ew: Dictionary = {}
	for w in map["warps"]:
		if str(w.get("dest_map", "")) == "RocketHideoutElevator":
			ew = w
			break
	player.place(Vector2i(int(ew["x"]), int(ew["y"])))
	_do_warp(ew)
	var in_lift: bool = center_label == "RocketHideoutElevator"
	var back_to: String = str(map["warps"][0]["dest_map"])
	map_script(center_label).on_interact(Vector2i(1, 1), null)   # the panel, no key
	var refused: bool = modal == textbox and not player_bag.has("LIFT KEY")
	modal = null; textbox.visible = false
	player_bag = {"LIFT KEY": 1}
	map_script(center_label).on_interact(Vector2i(1, 1), null)   # -> the floor menu
	await get_tree().process_frame
	var floors_up: bool = modal == menu and menu.items == ["B1F", "B2F", "B4F"]
	menu.chosen.emit(2)                                          # B4F
	await get_tree().process_frame
	var retargeted: bool = str(map["warps"][0]["dest_map"]) == "RocketHideoutB4F" \
		and int(map["warps"][0]["dest_warp"]) == 3 \
		and str(map["warps"][1]["dest_map"]) == "RocketHideoutB4F"
	# Taking the retargeted door lands on B4F's elevator-door square (25,15).
	player.place(Vector2i(2, 1))  # audit: map=RocketHideoutElevator
	_do_warp(map["warps"][0])
	var rode: bool = center_label == "RocketHideoutB4F" and player.cell == Vector2i(25, 15)
	print("[hideouttest] elevator: entered=%s returns_to=%s no_key_refused=%s floors=%s to_B4F=%s rode=%s" % [
		in_lift, back_to, refused, floors_up, retargeted, rode])
	# The Silph elevator ships broken static warps (UNUSED_MAP_ED): entry must retarget them.
	load_world("SilphCo7F")
	for w in map["warps"]:
		if str(w.get("dest_map", "")) == "SilphCoElevator":
			ew = w
			break
	player.place(Vector2i(int(ew["x"]), int(ew["y"])))
	_do_warp(ew)
	var silph_back: bool = center_label == "SilphCoElevator" \
		and str(map["warps"][0]["dest_map"]) == "SilphCo7F"
	map_script(center_label).on_interact(Vector2i(3, 0), null)   # no key needed
	await get_tree().process_frame
	var silph_floors: bool = modal == menu and menu.items.size() == 11
	menu.chosen.emit(10)                                         # 11F
	await get_tree().process_frame
	var silph_11: bool = str(map["warps"][0]["dest_map"]) == "SilphCo11F" \
		and int(map["warps"][0]["dest_warp"]) == 2
	print("[hideouttest] silph elevator: doors_fixed=%s floors=%s to_11F=%s" % [
		silph_back, silph_floors, silph_11])
	get_tree().quit()


func _daycaretest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_money = 5000
	player_party = [make_mon("pidgey", 5, ["TACKLE"]), make_mon("rattata", 5, ["TACKLE"])]
	load_world("Daycare")
	player.place(Vector2i(1, 3)); player.facing = 3   # face RIGHT -> Day-Care man at (2,3); (3,3) is his table (gh #84)
	interact(player)
	var g := 0
	while menu_mode != "daycare_deposit" and g < 600:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == menu and menu_mode == "cutscene":
			menu.chosen.emit(0)                       # YES, raise one
		g += 1
	_on_menu_chosen(0)                                # deposit the pidgey
	var deposited: bool = not daycare_mon.is_empty() and player_party.size() == 1
	var dep_name: String = str(daycare_mon.get("name", "?")) if deposited else "?"
	modal = null; textbox.visible = false
	# EXP accrues per step.
	var e0 := int(daycare_mon["exp"])
	for i in 30:
		_on_player_moved(player.cell)
	var per_step: bool = int(daycare_mon["exp"]) == e0 + 30
	# Force enough EXP for L8, then withdraw.
	daycare_mon["exp"] = exp_for_level(8, str(daycare_mon["growth"]))
	player.facing = 3                                 # still at (1,3): the man is to the RIGHT (gh #84)
	interact(player)
	g = 0
	while not (player_party.size() == 2 and daycare_mon.is_empty()) and g < 600:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == menu and menu_mode == "cutscene":
			menu.chosen.emit(0)                       # YES, pay the fee
		g += 1
	var withdrawn: bool = player_party.size() == 2 and daycare_mon.is_empty()
	var lvl: int = int(player_party[1]["level"]) if withdrawn else 0
	print("[daycaretest] deposited=%s name=%s exp_per_step=%s withdrawn=%s level=%d money=%d (expect 4600)" % [
		deposited, dep_name, per_step, withdrawn, lvl, player_money])
	get_tree().quit()


func _tmtest() -> void:
	await get_tree().process_frame
	player_bag = {"TM06": 1, "TM38": 1}              # TOXIC (learnable), FIRE_BLAST (not, for bulbasaur)
	player_party = [make_mon("bulbasaur", 15, ["TACKLE"])]
	var has_move := func(m: String) -> bool:
		for mv in player_party[0]["moves"]:
			if str(mv["move"]) == m:
				return true
		return false
	selected_item = "TM06"; _teach(0)
	var learned: bool = has_move.call("TOXIC")
	var consumed: bool = not player_bag.has("TM06")
	modal = null; textbox.visible = false
	selected_item = "TM38"; _teach(0)
	var incompat_rejected: bool = not has_move.call("FIRE_BLAST") and player_bag.has("TM38")
	var names: Array = []
	for mv in player_party[0]["moves"]:
		names.append(str(mv["move"]))
	print("[tmtest] learned_TOXIC=%s tm_consumed=%s incompat_rejected=%s moves=%s" % [
		learned, consumed, incompat_rejected, str(names)])
	modal = null; textbox.visible = false; _text_then = Callable()
	# gh #60: a full moveset runs the LearnMove forget flow; accept everything -> slot 0
	# is forgotten, TOXIC learned, the TM consumed.
	player_bag = {"TM06": 1}
	player_party = [make_mon("bulbasaur", 15, ["TACKLE", "GROWL", "LEECH_SEED", "VINE_WHIP"])]
	selected_item = "TM06"; _teach(0)
	for i in 60:
		if modal != null:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
	var forgot_ok: bool = has_move.call("TOXIC") and not has_move.call("TACKLE") \
		and not player_bag.has("TM06")
	print("[tmtest] forget flow: forgot_slot0_learned_TOXIC_consumed=%s (expect true)" % forgot_ok)
	# Declining the delete then confirming the abandon keeps the TM and the moves.
	player_bag = {"TM06": 1}
	player_party = [make_mon("bulbasaur", 15, ["TACKLE", "GROWL", "LEECH_SEED", "VINE_WHIP"])]
	selected_item = "TM06"; _teach(0)
	var menus := 0
	for i in 60:
		if modal == menu:
			menus += 1
			if menus == 1:
				await _press("ui_cancel")        # decline "Delete an older move?"
			else:
				await _press("ui_accept")        # confirm "Abandon learning?"
		elif modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
	var abandon_ok: bool = player_bag.has("TM06") and not has_move.call("TOXIC")
	print("[tmtest] abandon: tm_kept_not_learned=%s (expect true)" % abandon_ok)
	# ItemUseTMHM: USE from the bag boots the machine and asks first; NO -> back to the bag.
	modal = null; textbox.visible = false; _text_then = Callable()
	_open_bag()
	_bag_select(0)                       # TM06 -> USE/TOSS
	_on_menu_chosen(0)                   # USE -> "Booted up a TM!" ask
	var boot_seen := false
	for i in 40:
		if modal == menu and menu_mode == "cutscene":
			boot_seen = true
			await _press("ui_down")      # NO
			await _press("ui_accept")
			break
		await _press("ui_accept")
	await get_tree().process_frame
	print("[tmtest] booted up: ask_seen=%s declined_back_to_bag=%s (expect true true)" % [
		boot_seen, modal == menu and menu_mode == "bag"])
	get_tree().quit()


func _battleitemtest() -> void:
	await get_tree().process_frame
	player_bag = {"SUPER POTION": 2, "POTION": 1, "ANTIDOTE": 1, "FULL HEAL": 1, "X ATTACK": 1,
		"DIRE HIT": 1, "GUARD SPEC.": 1, "POKé DOLL": 1}
	player_party = [make_mon("charmander", 30, ["SCRATCH"])]
	start_battle("rattata", 5)
	await get_tree().process_frame
	# X ATTACK -> +1 ATTACK stage, consumed.
	battle._use_item("X ATTACK")
	var x_ok: bool = int(battle.p_stages["atk"]) == 1 and not player_bag.has("X ATTACK")
	# FULL HEAL cures a burn, consumed.
	battle.player_mon["status"] = "brn"
	battle._use_item("FULL HEAL")
	var heal_ok: bool = str(battle.player_mon["status"]) == "" and not player_bag.has("FULL HEAL")
	# ANTIDOTE on a non-poisoned mon -> no effect, NOT consumed.
	battle._use_item("ANTIDOTE")
	var anti_noeffect: bool = player_bag.has("ANTIDOTE")
	# SUPER POTION at full HP -> no effect, NOT consumed.
	battle.player_mon["hp"] = int(battle.player_mon["maxhp"])
	battle._use_item("SUPER POTION")
	var fullhp_noconsume: bool = int(player_bag.get("SUPER POTION", 0)) == 2
	# SUPER POTION when hurt -> heals (up to 50) + consumed.
	battle.player_mon["hp"] = 1
	battle._use_item("SUPER POTION")
	var potion_ok: bool = int(player_bag.get("SUPER POTION", 0)) == 1 and int(battle.player_mon["hp"]) > 1
	# ANTIDOTE cures poison in battle (the reported "antidote not working").
	battle.player_mon["status"] = "psn"
	battle._use_item("ANTIDOTE")
	var anti_cure: bool = str(battle.player_mon["status"]) == "" and not player_bag.has("ANTIDOTE")
	# POTION restores a flat 20 HP (not full, not 0): 50 -> ~70 minus a small enemy chip.
	battle.player_mon["maxhp"] = 100; battle.player_mon["hp"] = 50
	battle._use_item("POTION")
	var hp_after := int(battle.player_mon["hp"])
	var potion20: bool = not player_bag.has("POTION") and hp_after >= 62 and hp_after <= 70
	# gh #175: DIRE HIT / GUARD SPEC. / POKé DOLL used to do nothing.
	battle._use_item("DIRE HIT")                                       # Focus Energy crit bit
	var dire_ok: bool = bool(battle.p_vol["focus"]) and not player_bag.has("DIRE HIT")
	battle._use_item("GUARD SPEC.")                                    # MIST: blocks stat drops
	var guard_ok: bool = bool(battle.p_vol["mist"]) and not player_bag.has("GUARD SPEC.")
	battle._use_item("POKé DOLL")                                      # flee the wild battle
	var doll_ok: bool = str(battle.after) == "run" and not player_bag.has("POKé DOLL")
	print("[battleitemtest] x_atk=%s full_heal=%s antidote_noeffect=%s fullhp_noconsume=%s super_potion=%s antidote_cure=%s potion20=%s(hp=%d)" % [
		x_ok, heal_ok, anti_noeffect, fullhp_noconsume, potion_ok, anti_cure, potion20, hp_after])
	print("[battleitemtest] gh#175 dire_hit=%s guard_spec=%s poke_doll=%s (expect true/true/true)" % [dire_ok, guard_ok, doll_ok])
	get_tree().quit()


func _biketest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_bag = {}
	player_name = "RED"
	player_party = [make_mon("charmander", 10, [])]
	# 1) Fan Club chairman -> BIKE VOUCHER.
	load_world("PokemonFanClub")
	player.place(Vector2i(2, 1)); player.facing = 3   # face RIGHT -> chairman at (3,1); (3,2) is his table (gh #84)
	interact(player)
	await _drive_bill(func() -> bool: return has_event("GOT_BIKE_VOUCHER") and not cutscene_active and modal == null, 1200)
	var got_voucher := player_bag.has("BIKE VOUCHER")
	# 2) Bike Shop trades the voucher for a BICYCLE.
	load_world("BikeShop")
	player.place(Vector2i(7, 2)); player.facing = 2   # face LEFT -> clerk at (6,2); (6,3) is his counter (gh #84)
	interact(player)
	await _drive_until(func() -> bool: return has_event("GOT_BICYCLE") and not cutscene_active and modal == null, 600)
	var got_bike := player_bag.has("BICYCLE") and not player_bag.has("BIKE VOUCHER")
	# 3) Can't ride indoors.
	selected_item = "BICYCLE"; _toggle_bike()
	var indoor_blocked := not riding
	modal = null; textbox.visible = false
	# Ride outdoors (2x), then off.
	load_world("CeruleanCity")
	selected_item = "BICYCLE"; _toggle_bike()
	var ride_on: bool = riding and abs(float(player.step_scale) - 0.5) < 0.01
	player._update_sprite()                            # gh #161: the player shows the BICYCLE sprite
	var bike_sprite: bool = player._sheet == "red_bike" and str(player.spr.texture.resource_path).ends_with("red_bike.png")
	modal = null; textbox.visible = false
	_toggle_bike()
	var ride_off: bool = not riding and abs(float(player.step_scale) - 1.0) < 0.01
	player._update_sprite()
	var walk_sprite: bool = player._sheet == "red" and str(player.spr.texture.resource_path).ends_with("red.png")
	print("[biketest] voucher=%s bike=%s indoor_blocked=%s ride_on=%s ride_off=%s bike_sprite(gh#161)=%s walk_sprite=%s" % [
		got_voucher, got_bike, indoor_blocked, ride_on, ride_off, bike_sprite, walk_sprite])
	get_tree().quit()


func _vendingtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_money = 1000
	player_bag = {}
	load_world("CeladonMartRoof")
	player.place(Vector2i(10, 2)); player.facing = 1   # face UP -> vending machine at (10,1)
	var opened := interact(player)
	var intro_ok: bool = modal == textbox              # VendingMachineText1 shows first now (gh #136)
	# Drive the machine: intro text -> menu -> buy FRESH WATER -> delivery text -> menu reopens. Advance
	# any textbox (the human presses A; the bot does the same) and buy on the first menu.
	var saw_delivery := false
	var bought := false
	for _i in 120:
		await get_tree().process_frame
		if modal == textbox and textbox.visible:
			if str(textbox.pages).contains("popped out"):
				saw_delivery = true
			textbox.advance()
		elif modal == menu and menu_mode == "vending":
			if not bought:
				_on_menu_chosen(0)                     # FRESH WATER ($200)
				bought = true
			else:
				break                                  # reopened after the buy -> on to the broke test
	var buy_ok := player_money == 800 and int(player_bag.get("FRESH WATER", 0)) == 1
	# Can't afford: VendingMachineText4 ("not enough money"), no charge.
	player_money = 50
	var saw_broke := false
	_on_menu_chosen(0)
	for _i in 40:
		await get_tree().process_frame
		if modal == textbox and textbox.visible:
			if str(textbox.pages).contains("not enough"):
				saw_broke = true
			textbox.advance()
		elif modal == menu:
			break
	var broke_ok := player_money == 50 and int(player_bag.get("FRESH WATER", 0)) == 1
	print("[vendingtest] opened=%s intro=%s delivery_text=%s bought=%s broke_text=%s broke_rejected=%s" % [
		opened, intro_ok, saw_delivery, buy_ok, saw_broke, broke_ok])
	get_tree().quit()


func _fishtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_bag = {}
	player_party = [make_mon("charmander", 10, ["SCRATCH"])]
	# 1) The Fishing Guru gives the OLD ROD.
	load_world("VermilionOldRodHouse")
	player.place(Vector2i(1, 4)); player.facing = 3   # face RIGHT -> guru at (2,4); (3,4) is his table (gh #84)
	interact(player)
	await _drive_bill(func() -> bool: return has_event("GOT_OLD_ROD") and not cutscene_active and modal == null, 800)
	var got_rod := player_bag.has("OLD ROD")
	# 2) Use the rod facing land -> nothing to fish.
	load_world("PalletTown")
	player.place(Vector2i(5, 6)); player.facing = 1
	selected_item = "OLD ROD"; _use_rod()
	var land_blocked: bool = modal == textbox
	modal = null; textbox.visible = false
	# 3) Find a water tile, stand above it, fish -> wild battle.
	var water := Vector2i(-1, -1)
	for y in gh:
		for x in gw:
			if _tile_at(Vector2i(x, y)) in WATER_TILES:
				water = Vector2i(x, y); break
		if water.x >= 0: break
	player.place(water + Vector2i(0, -1)); player.facing = 0   # face DOWN onto the water
	selected_item = "OLD ROD"; _use_rod()
	await _drive_until(func() -> bool: return modal == battle, 400)
	var enemy: String = str(battle.enemy_mon["species"]) if modal == battle else "?"
	var lvl: int = int(battle.enemy_mon["level"]) if modal == battle else 0
	print("[fishtest] got_rod=%s land_no_fish=%s water_cell=%s fished=%s enemy=%s L%d" % [
		got_rod, land_blocked, str(water), modal == battle, enemy, lvl])
	get_tree().quit()


func _ssannetest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_bag = {}
	load_world("VermilionCity")
	var ms = map_script("VermilionCity")
	last_outside_map = "Route11"                       # stale: boarding must overwrite it (gh #116)
	# The ticket check is at (18,30) facing DOWN, a tile north of the dock warp (gh #115). No ticket -> turned back.
	player.place(Vector2i(18, 30)); player.facing = 0
	ms.on_step(Vector2i(18, 30))
	for _i in 400:
		await get_tree().process_frame
		if textbox.active and textbox.visible: textbox.advance()
		if not cutscene_active and modal == null: break
	var blocked: bool = center_label == "VermilionCity"
	modal = null; textbox.visible = false
	# With the ticket, the sailor waves you onto the dock and last_outside_map becomes VermilionCity.
	set_event("GOT_SS_TICKET")
	player.place(Vector2i(18, 30)); player.facing = 0
	ms.on_step(Vector2i(18, 30))
	for _i in 600:
		await get_tree().process_frame
		if textbox.active and textbox.visible: textbox.advance()
		if not cutscene_active and modal == null and center_label == "VermilionDock": break
	var boarded := center_label
	var lom_ok: bool = last_outside_map == "VermilionCity"   # gh #116: the dock's LAST_MAP exit resolves here
	# Captain in his cabin -> rub back -> HM01.
	load_world("SSAnneCaptainsRoom")
	var cap = _npc_by_key("SPRITE_CAPTAIN@4,2")
	player.place(Vector2i(4, 3)); player.facing = 1   # face UP -> captain at (4,2)
	interact(player)
	await _drive_until(func() -> bool: return has_event("GOT_HM01") and not cutscene_active and modal == null, 1500)
	print("[ssannetest] no_ticket_blocked=%s boarded=%s last_outside_map_ok=%s cap_shown=%s rubbed=%s got_hm01=%s bag_hm01=%s" % [
		blocked, boarded, lom_ok, cap != null and cap.shown, has_event("RUBBED_CAPTAINS_BACK"),
		has_event("GOT_HM01"), player_bag.has("HM01")])
	# Deck rival battle on 2F. Trigger from (37,8) — the gh #117 case where the after-battle walk used to
	# march the rival straight down through the player.
	player_party = [make_mon("charmander", 40, ["EMBER"])]; player_starter = "charmander"
	load_world("SSAnne2F")
	var rival_npc = _npc_by_key("SPRITE_BLUE@36,4")
	player.place(Vector2i(37, 8)); player.facing = 1
	_on_player_moved(Vector2i(37, 8))
	var rengaged: bool = cutscene_active
	var rname := ""
	var win_forced := false
	var rival_through := false                            # did the rival ever stand on the player's cell?
	for i in 4000:
		await get_tree().process_frame
		if rival_npc != null and rival_npc.shown and rival_npc.cell == player.cell:
			rival_through = true
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			rname = battle.trainer_name
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); win_forced = true
		if win_forced and not cutscene_active and modal == null:
			break
	print("[ssannetest] rival: engaged=%s trainer=%s beat=%s walked_through_player=%s" % [
		rengaged, rname, has_event("BEAT_SS_ANNE_RIVAL"), rival_through])
	# Departure: stepping off the ship onto the dock after HM01 sets sail — the scene erases the ship to
	# water and walks the player north off the dock into Vermilion. last_outside_map was set by boarding
	# (gh #116) and survives the intervening ship-tileset loads, so the dock's LAST_MAP exit resolves right.
	load_world("VermilionDock", 1)                   # arrive at the gangway (warp 1)
	await _drive_until(func() -> bool: return has_event("SS_ANNE_LEFT") \
		and center_label == "VermilionCity" and not cutscene_active and modal == null, 900)
	print("[ssannetest] departure: ss_anne_left=%s back_at=%s (expect VermilionCity)" % [
		has_event("SS_ANNE_LEFT"), center_label])
	get_tree().quit()


func _billtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_bag = {}
	load_world("BillsHouse")
	var billmon = _npc_by_key("SPRITE_MONSTER@6,5")
	var mon_shown: bool = billmon.shown
	# 1) Talk to Bill-as-a-POKéMON.
	player.place(Vector2i(6, 6)); player.facing = 1
	interact(player)
	await _drive_bill(func() -> bool: return has_event("BILL_SAID_USE_CELL_SEPARATOR") and not cutscene_active and modal == null)
	var mon_hidden: bool = not billmon.shown
	# 2) Run the cell separator from the PC.
	player.place(Vector2i(1, 5)); player.facing = 1
	interact(player)
	await _drive_bill(func() -> bool: return has_event("USED_CELL_SEPARATOR_ON_BILL") and not cutscene_active and modal == null)
	var bill = _npc_by_key("SPRITE_SUPER_NERD@4,4")
	var bill_shown: bool = bill != null and bill.shown
	# 3) gh #174: a FULL bag refuses the ticket and leaves GOT_SS_TICKET unset, so Bill re-offers.
	player_bag = {}
	for i in 20:
		player_bag["ITEM%02d" % i] = 1
	player.place(Vector2i(4, 5)); player.facing = 1
	interact(player)
	await _drive_bill(func() -> bool: return not cutscene_active and modal == null)
	var refused: bool = not player_bag.has("S.S.TICKET") and not has_event("GOT_SS_TICKET")
	# 4) Make room -> the ticket is given, and control returns cleanly.
	player_bag.erase("ITEM19")
	player.place(Vector2i(4, 5)); player.facing = 1
	interact(player)
	await _drive_bill(func() -> bool: return has_event("GOT_SS_TICKET") and not cutscene_active and modal == null)
	print("[billtest] mon_shown=%s said=%s mon_hidden=%s used=%s bill_shown=%s ticket=%s bag_has=%s" % [
		mon_shown, has_event("BILL_SAID_USE_CELL_SEPARATOR"), mon_hidden,
		has_event("USED_CELL_SEPARATOR_ON_BILL"), bill_shown, has_event("GOT_SS_TICKET"),
		player_bag.has("S.S.TICKET")])
	print("[billtest] gh#174 full-bag refused=%s then given-after-room=%s (expect true/true)" % [
		refused, player_bag.has("S.S.TICKET")])
	get_tree().quit()


func _dextest() -> void:
	await get_tree().process_frame
	story_events = {"GOT_POKEDEX": true}
	pokedex_seen = {}; pokedex_owned = {}
	player_party = [make_mon("charmander", 10, ["SCRATCH"])]
	pc_box = [make_mon("pidgey", 5, [])]
	start_battle("rattata", 3)                    # battle marks the enemy seen
	var seen_foe := pokedex_seen.has("rattata")
	battle.won = true; battle.blacked_out = false; battle.finished.emit()
	await get_tree().process_frame               # _on_battle_finished -> _sync_owned
	set_event("GOT_POKEDEX")
	battle.visible = false                        # the force-ended battle never tore down its layer
	open_start_menu(); _on_menu_chosen(0)         # POKéDEX -> the dex list screen
	var opened: bool = modal == dexlist
	print("[dextest] seen_foe=%s owned_party=%s owned_box=%s seen=%d owned=%d dex_open=%s" % [
		seen_foe, pokedex_owned.has("charmander"), pokedex_owned.has("pidgey"),
		pokedex_seen.size(), pokedex_owned.size(), opened])
	# gh #152: shoot the contents screen (the tile rail + the '─' row + dashes for unseen).
	for _i in 3:
		await get_tree().process_frame   # let the freshly opened list render first
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://dex_contents.png")
	await get_tree().process_frame       # re-sync to a process step, or the next press is eaten
	# gh #152 nav: RIGHT pages the window +7, LEFT pages it back, and a held DOWN auto-repeats
	# (the hJoy7 low-sensitivity joypad). rattata seen at 019 keeps the list long enough to page.
	dexlist.scroll = 0; dexlist.cursor = 0
	await _press("ui_right")
	var paged: bool = dexlist.scroll == 7
	await _press("ui_left")
	paged = paged and dexlist.scroll == 0
	Input.action_press("ui_down")
	for _i in 80:
		await get_tree().process_frame
	Input.action_release("ui_down")
	await get_tree().process_frame
	var held_scrolled: bool = dexlist.scroll + dexlist.cursor > 2
	print("[dextest] nav(gh#152): paged=%s held_scrolled=%s" % [paged, held_scrolled])
	# DATA opens the data screen for the selected (seen) mon — via real keypresses.
	dexlist.scroll = 3; dexlist.cursor = 0                    # row 004 = charmander (owned)
	await _press("ui_accept")                                 # open the side menu
	var side_open: bool = dexlist.focus == "menu"
	await _press("ui_accept")                                 # DATA
	await get_tree().process_frame
	var data_open: bool = modal == dexentry and dexentry.visible
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://dex_data.png")
	await get_tree().process_frame
	var list_hidden: bool = not dexlist.visible               # the entry must not be under it
	print("[dextest] DATA: side_menu=%s modal_is_entry=%s list_hidden=%s" % [
		side_open, data_open, list_hidden])
	await _press("ui_accept")                                 # close the entry (single page)
	while dexentry.visible:
		await _press("ui_accept")
	await get_tree().process_frame
	# QUIT returns to the START menu (RedisplayStartMenu).
	dexlist.focus = "menu"; dexlist.menu_cur = 3
	await dexlist._side_select()
	var back: bool = modal == menu and menu_mode == "start"
	# AREA resolves nest spots from the wild data onto the town map.
	show_nest("rattata")
	var nest_open: bool = modal == townmap and townmap.nest_title.begins_with("RATTATA")
	var has_spots: bool = not townmap.nest_spots.is_empty()
	townmap._close()
	print("[dextest] quit_to_start=%s nest_open=%s nest_has_spots=%s" % [back, nest_open, has_spots])
	get_tree().quit()


func _towertest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"; rival_name = "BLUE"; player_starter = "charmander"
	player_party = [make_mon("charmander", 45, ["EMBER"])]
	load_world("PokemonTower2F")
	var rival = _npc_by_key("SPRITE_BLUE@14,5")
	var shown_before: bool = rival.shown
	player.place(Vector2i(15, 5)); player.facing = 2   # face LEFT -> rival at (14,5)
	_on_player_moved(Vector2i(15, 5))
	var engaged: bool = cutscene_active
	var enemy := ""
	var win_forced := false
	for i in 4000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			enemy = "%s L%d" % [battle.enemy_mon["species"], int(battle.enemy_mon["level"])]
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); win_forced = true
		if win_forced and not cutscene_active and modal == null:
			break
	print("[towertest] shown_before=%s engaged=%s enemy=%s beat=%s rival_hidden_after=%s" % [
		shown_before, engaged, enemy, has_event("BEAT_POKEMON_TOWER_RIVAL"), not rival.shown])
	get_tree().quit()


func _crivaltest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"; rival_name = "BLUE"; player_starter = "charmander"
	player_party = [make_mon("charmander", 35, ["EMBER"])]
	load_world("CeruleanCity")
	var rival = _npc_by_key("SPRITE_BLUE@20,2")
	var hidden_before: bool = not rival.shown
	player.place(Vector2i(20, 6)); player.facing = 1
	_on_player_moved(Vector2i(20, 6))
	var engaged: bool = cutscene_active
	var enemy := ""
	var tname := ""
	var win_forced := false
	for i in 4000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			enemy = "%s L%d" % [battle.enemy_mon["species"], int(battle.enemy_mon["level"])]
			tname = battle.trainer_name
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); win_forced = true
		if win_forced and not cutscene_active and modal == null:
			break
	print("[crivaltest] hidden_before=%s engaged=%s trainer=%s enemy=%s beat=%s rival_hidden_after=%s" % [
		hidden_before, engaged, tname, enemy, has_event("BEAT_CERULEAN_RIVAL"), not rival.shown])
	get_tree().quit()


func _itemusetest() -> void:
	await get_tree().process_frame
	story_events = {}
	load_world("CeruleanCity")
	player_party = [make_mon("charmander", 25, ["SCRATCH"])]
	var mon: Dictionary = player_party[0]
	var mx: int = int(mon["maxhp"])
	var function := func(item: String, idx := 0) -> void:
		player_bag = {item: 1}; selected_item = item; _bag_use_on(idx); modal = null; textbox.visible = false
	# SUPER POTION (+50, capped at max)
	mon["hp"] = 1; function.call("SUPER POTION")
	var sp: int = int(mon["hp"])
	# FRESH WATER (+50): a vending drink must be usable and heal HP (gh #148)
	mon["hp"] = 1; function.call("FRESH WATER")
	var fw: bool = int(mon["hp"]) == mini(51, mx) and not player_bag.has("FRESH WATER")
	# FULL RESTORE: full HP + clears status
	mon["hp"] = 5; mon["status"] = "brn"; function.call("FULL RESTORE")
	var fr: bool = int(mon["hp"]) == mx and str(mon["status"]) == ""
	# ANTIDOTE cures poison; wrong-status item is inert
	mon["status"] = "psn"; function.call("ANTIDOTE")
	var anti: bool = str(mon["status"]) == ""
	# REVIVE on a fainted mon
	mon["hp"] = 0; mon["status"] = "psn"; function.call("REVIVE")
	var rev := int(mon["hp"])
	# RARE CANDY: +1 level
	var lv: int = int(mon["level"]); function.call("RARE CANDY")
	var candy := int(mon["level"])
	# REPEL: field item, sets the counter + decrements per step + suppresses encounters
	repel_steps = 0; player_bag = {"REPEL": 1}; _open_bag(); _bag_select(menu_keys.find("REPEL")); _on_menu_chosen(0)   # USE
	modal = null; textbox.visible = false
	var repel_set := repel_steps
	_on_player_moved(player.cell)
	var repel_after_step := repel_steps
	# ESCAPE ROPE: refused outdoors (EscapeRopeTilesets, gh #61); from a cave it warps
	# to the respawn map and is consumed.
	respawn_map = "ViridianPokecenter"
	player_bag = {"ESCAPE ROPE": 1}; _open_bag(); _bag_select(menu_keys.find("ESCAPE ROPE")); _on_menu_chosen(0)   # USE
	var rope_refused: bool = center_label == "CeruleanCity" and player_bag.has("ESCAPE ROPE")
	modal = null; textbox.visible = false; _text_then = Callable()
	load_world("MtMoonB2F")
	_open_bag(); _bag_select(menu_keys.find("ESCAPE ROPE")); _on_menu_chosen(0)   # USE
	print("[itemusetest] super_potion hp=%d/%d fresh_water(gh#148)=%s full_restore=%s antidote=%s revive=%d(/%d) candy=%d(was %d)" % [
		sp, mx, fw, fr, anti, rev, mx, candy, lv])
	# ESCAPE ROPE shares the blackout destination (gh #101): outside, at the town's fly tile —
	# ViridianCity (23,26), not the Pokémon Center interior.
	print("[itemusetest] repel set=%d after_step=%d | escape_rope: outdoor_refused=%s cave -> %s @%s (expect ViridianCity (23,26)) used=%s" % [
		repel_set, repel_after_step, rope_refused, center_label, str(player.cell), not player_bag.has("ESCAPE ROPE")])
	get_tree().quit()


func _hiddentest() -> void:
	await get_tree().process_frame
	found_hidden = {}
	player_bag = {}
	player_name = "RED"
	load_world("ViridianForest")           # hidden POTION at (1,18), ANTIDOTE at (16,42)
	player.place(Vector2i(1, 19)); player.facing = 1   # face UP -> (1,18)
	var h1 := interact(player)
	var got := int(player_bag.get("POTION", 0))
	var msg := str(textbox.pages[0]).replace("\n", " ") if (modal == textbox and textbox.pages.size() > 0) else ""
	modal = null; textbox.visible = false
	# Second try on the same spot: nothing left.
	var h2 := interact(player)
	# A tile with no hidden item: not handled by the hidden-item check ((7,19) is standable and
	# (7,18) is plain ground — the forest's hidden items are (1,18) and (16,42); gh #84).
	player.place(Vector2i(7, 19)); player.facing = 1
	var h3 := _try_hidden_item(player.front_cell())
	print("[hiddentest] found=%s msg=%s bag_potion=%d retake_handled=%s empty_tile=%s taken=%s" % [
		h1, msg, got, h2, h3, found_hidden.has("ViridianForest:1,18")])
	get_tree().quit()


func _cuttest() -> void:
	await get_tree().process_frame
	story_events = {}
	badges = []
	player_party = [make_mon("charmander", 20, ["SCRATCH"])]   # charmander can learn CUT
	player_bag = {"HM01": 1}
	load_world("CeruleanCity")
	var tree := Vector2i(19, 28)                    # the cut tree block (9,14), top-right quadrant
	var tree_solid := not is_walkable(tree)
	# Teach CUT from the bag (HM not consumed) — through the "Booted up an HM!" ask (gh #60).
	_open_bag(); _bag_select(0); _on_menu_chosen(0)   # USE
	for i in 20:
		if modal == menu and menu_mode == "cutscene":
			await _press("ui_accept")                 # YES: teach it
			break
		await _press("ui_accept")
	var routed := menu_mode == "teach_target"
	_teach(0); modal = null; textbox.visible = false
	var knows := _mon_with_move("CUT") != ""
	# Face the tree WITHOUT the badge -> only a hint, no cut.
	player.place(Vector2i(19, 29)); player.facing = 1
	interact(player)
	var hint := str(textbox.pages[0]).replace("\n", " ") if (modal == textbox and textbox.pages.size() > 0) else ""
	var still_tree := not is_walkable(tree)
	modal = null; textbox.visible = false
	# With the Cascade Badge -> cut it.
	badges = ["CASCADEBADGE"]
	player.place(Vector2i(19, 29)); player.facing = 1
	interact(player)
	var cut_msg := str(textbox.pages[0]).replace("\n", " ") if (modal == textbox and textbox.pages.size() > 0) else ""
	var open_now := is_walkable(tree)
	modal = null; textbox.visible = false
	# Teaching CUT to an incompatible species (Squirtle) fails.
	player_party = [make_mon("squirtle", 20, ["TACKLE"])]
	selected_item = "HM01"; _teach(0)
	var sq_fail := _mon_with_move("CUT") == ""
	print("[cuttest] teach routed=%s knows=%s hm_kept=%s" % [routed, knows, player_bag.has("HM01")])
	print("[cuttest] no-badge: tree_solid=%s hint=%s still_tree=%s" % [tree_solid, hint, still_tree])
	print("[cuttest] cut: msg=%s tree_now_walkable=%s" % [cut_msg, open_now])
	print("[cuttest] squirtle can't learn CUT: %s" % sq_fail)
	get_tree().quit()


func _pctest() -> void:
	await get_tree().process_frame
	story_events = {}
	pc_box = []
	player_party = [make_mon("squirtle", 10, []), make_mon("pidgey", 8, []), make_mon("rattata", 6, [])]
	pc_items = {}
	load_world("ViridianPokecenter")
	player.place(Vector2i(13, 4)); player.facing = 1   # face UP -> PC at (13,3)
	var opened := interact(player)
	var top_mode := menu_mode              # expect "pc_top"
	_on_menu_chosen(0)                     # SOMEONE'S PC -> Pokémon storage
	# Deposit the 3rd party mon (rattata).
	_on_menu_chosen(1)                     # DEPOSIT -> party list
	var dep_mode := menu_mode
	_on_menu_chosen(2)                     # deposit index 2
	var dep := "party=%d box=%d top=%s" % [player_party.size(), pc_box.size(),
		str(pc_box[0]["species"]) if pc_box.size() > 0 else "?"]
	# Back to the mon PC menu, then withdraw it again.
	_on_menu_chosen(player_party.size())   # CANCEL deposit list -> mon PC menu
	var back := menu_mode
	_on_menu_chosen(0)                     # WITHDRAW -> box list
	_on_menu_chosen(0)                     # withdraw box[0]
	var wd := "party=%d box=%d" % [player_party.size(), pc_box.size()]
	print("[pctest] opened=%s(top=%s) deposit_list=%s after_deposit %s | back=%s after_withdraw %s" % [
		opened, top_mode, dep_mode, dep, back, wd])
	# <PLAYER>'s PC item box: withdraw 3 of 5 POTION to the bag.
	pc_items = {"POTION": 5}; player_bag = {}
	_open_pc(); _on_menu_chosen(1)         # <PLAYER>'s PC -> item box
	var item_mode := menu_mode             # expect "pc_item"
	_on_menu_chosen(0)                     # WITHDRAW ITEM -> list
	_on_menu_chosen(0)                     # pick POTION
	_on_menu_chosen(3)                     # quantity 3
	var item_wd: bool = int(player_bag.get("POTION", 0)) == 3 and int(pc_items.get("POTION", 0)) == 2
	# Deposit 1 of those POTION back to the box.
	_on_menu_chosen(_pc_item_keys.size())  # CANCEL the withdraw list -> item menu
	_on_menu_chosen(1)                     # DEPOSIT ITEM -> bag list
	_on_menu_chosen(0)                     # pick POTION (from bag)
	_on_menu_chosen(1)                     # quantity 1
	var item_dep: bool = int(pc_items.get("POTION", 0)) == 3 and int(player_bag.get("POTION", 0)) == 2
	print("[pctest] item_pc: mode=%s withdraw=%s deposit=%s" % [item_mode, item_wd, item_dep])
	# Guard: can't deposit your last mon.
	player_party = [make_mon("squirtle", 10, [])]
	_open_pc(); _on_menu_chosen(0); _on_menu_chosen(1)
	var dep_last_blocked := menu_mode == "pc_mon"
	# Guard: can't withdraw into a full party.
	player_party = [make_mon("squirtle", 5, []), make_mon("pidgey", 5, []), make_mon("rattata", 5, []),
		make_mon("spearow", 5, []), make_mon("ekans", 5, []), make_mon("pikachu", 5, [])]
	pc_box = [make_mon("mewtwo", 70, [])]
	_open_pc(); _on_menu_chosen(0); _on_menu_chosen(0); _on_menu_chosen(0)
	var wd_full_blocked := player_party.size() == 6 and pc_box.size() == 1
	print("[pctest] guards: deposit_last_blocked=%s withdraw_full_blocked=%s" % [
		dep_last_blocked, wd_full_blocked])
	get_tree().quit()


## gh #185: PROF.OAK's dex rating (pokedex_rating.asm) at his PC and in his lab, the
## lab 5-ball gift branch, and PalletTown arming PALLET_AFTER_GETTING_POKEBALLS.
func _dexratingtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_party = [make_mon("squirtle", 10, [])]
	pc_box = []
	pokedex_seen = {}
	pokedex_owned = {}
	for i in 54:                              # + squirtle via _sync_owned = 55 owned/seen
		pokedex_seen["fake%d" % i] = true
		pokedex_owned["fake%d" % i] = true
	if audio:
		audio.log_sfx = true
	# --- Oak's PC: 55 owned -> the "at least 50" tier + the get_item1 band jingle ---
	load_world("ViridianPokecenter")
	player.place(Vector2i(13, 4)); player.facing = 1   # face UP -> the PC at (13,3)
	interact(player)
	_on_menu_chosen(2)                        # PROF.OAK's PC
	if audio: audio.sfx_log = []              # (after: the menu pick logs press_ab)
	var text := "\n".join(textbox.pages)
	var tier_ok: bool = "least 50 species!" in text and "55 POKéMON owned" in text \
		and "55 POKéMON seen" in text
	var guard := 0
	while textbox.active and guard < 60:      # drive to the end so on_typed fires
		textbox.advance()
		await get_tree().process_frame
		guard += 1
	var jingle: String = str(audio.sfx_log[0]) if audio and audio.sfx_log.size() > 0 else "none"
	print("[dexratingtest] pc: tier_ok=%s jingle=%s(want get_item1)" % [tier_ok, jingle])
	# --- band edges: 0 owned -> "lots to do"/denied; 150 -> "entirely complete"/get_item2 ---
	player_party = []
	pokedex_seen = {}; pokedex_owned = {}
	if audio: audio.sfx_log = []
	oaks_dex_rating()
	var low_ok: bool = "lots to do." in "\n".join(textbox.pages)
	guard = 0
	while textbox.active and guard < 60:
		textbox.advance()
		await get_tree().process_frame
		guard += 1
	var low_jingle: String = str(audio.sfx_log[0]) if audio and audio.sfx_log.size() > 0 else "none"
	for i in 150:
		pokedex_owned["fake%d" % i] = true
	if audio: audio.sfx_log = []
	oaks_dex_rating()
	var top_ok: bool = "entirely complete!" in "\n".join(textbox.pages)
	guard = 0
	while textbox.active and guard < 60:
		textbox.advance()
		await get_tree().process_frame
		guard += 1
	var top_jingle: String = str(audio.sfx_log[0]) if audio and audio.sfx_log.size() > 0 else "none"
	print("[dexratingtest] edges: low=%s/%s(want denied) top=%s/%s(want get_item2)" % [
		low_ok, low_jingle, top_ok, top_jingle])
	# --- Oak's lab: rating branch (>=2 owned + dex), then the 5-ball gift, then come-see-me ---
	story_events = {"GOT_STARTER": true, "BEAT_RIVAL1": true, "GOT_POKEDEX": true,
		"OAK_GOT_PARCEL": true, "GOT_OAKS_PARCEL": true, "FOLLOWED_OAK_INTO_LAB": true,
		"RIVAL_LEFT_LAB": true}
	player_party = [make_mon("squirtle", 10, [])]
	pokedex_seen = {"fake0": true}; pokedex_owned = {"fake0": true}   # + squirtle = 2 owned
	player_bag = {}
	load_world("OaksLab")
	player.place(Vector2i(5, 3)); player.facing = 1    # face UP -> Oak at (5,2)
	interact(player)
	var lab_rating_ok: bool = "How is your" in "\n".join(textbox.pages)
	guard = 0
	while textbox.active and guard < 60:
		textbox.advance()
		await get_tree().process_frame
		guard += 1
	# Gift branch: rating off (1 owned), no balls, Route 22 rival beaten, gift not yet given.
	pokedex_seen = {}; pokedex_owned = {}
	player_party = [make_mon("squirtle", 10, [])]
	story_events.erase("GOT_POKEDEX")
	story_events["BEAT_ROUTE22_RIVAL_1"] = true
	interact(player)
	guard = 0
	while (textbox.active or cutscene_active) and guard < 120:
		textbox.advance()
		await get_tree().process_frame
		guard += 1
	var gift_ok: bool = int(player_bag.get("POKé BALL", 0)) == 5 \
		and has_event("GOT_POKEBALLS_FROM_OAK")
	# With balls in the bag the same talk is "Come see me sometimes."
	interact(player)
	var see_ok: bool = "Come see me" in "\n".join(textbox.pages)
	guard = 0
	while textbox.active and guard < 60:
		textbox.advance()
		await get_tree().process_frame
		guard += 1
	print("[dexratingtest] lab: rating=%s gift=%s come_see_me=%s" % [
		lab_rating_ok, gift_ok, see_ok])
	# --- PalletTown arms the PALLET_AFTER_GETTING_POKEBALLS event on enter ---
	load_world("PalletTown")
	var pallet_ok := has_event("PALLET_AFTER_GETTING_POKEBALLS")
	var pass_all: bool = tier_ok and jingle == "get_item1" and low_ok and low_jingle == "denied" \
		and top_ok and top_jingle == "get_item2" and lab_rating_ok and gift_ok and see_ok and pallet_ok
	print("[dexratingtest] pallet_event=%s" % pallet_ok)
	print("[dexratingtest] PASS=%s" % pass_all)
	get_tree().quit()


## gh #185: the DIPLOMA (diploma.asm) — the designer's 150-owned gate and the card screen.
func _diplomatest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_party = [make_mon("squirtle", 10, [])]
	pokedex_seen = {}
	pokedex_owned = {}
	load_world("CeladonMansion3F")
	player.place(Vector2i(2, 4)); player.facing = 1     # face UP -> the designer at (2,3)
	# Below 150 owned: the regular designer line, no diploma.
	interact(player)
	await get_tree().process_frame
	var normal_ok: bool = "designer!" in "\n".join(textbox.pages) and not diploma.visible
	var guard := 0
	while textbox.active and guard < 60:
		textbox.advance()
		await get_tree().process_frame
		guard += 1
	# Exactly 150 owned (149 fakes + squirtle — Mew discounted): the card.
	for i in 149:
		pokedex_owned["fake%d" % i] = true
	interact(player)
	guard = 0
	while not diploma.visible and guard < 120:
		textbox.advance()
		await get_tree().process_frame
		guard += 1
	var opened: bool = diploma.visible and modal == diploma
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://diploma_shot.png")
	await get_tree().process_frame                      # post-draw eats the next press otherwise
	await _press("ui_accept")
	var closed_ok: bool = not diploma.visible and modal == null
	print("[diplomatest] normal=%s opened=%s closed=%s -> diploma_shot.png" % [
		normal_ok, opened, closed_ok])
	print("[diplomatest] PASS=%s" % (normal_ok and opened and closed_ok))
	get_tree().quit()


## Drive a cutscene money dialog: advance text, answer asks from `answers` (default YES).
## Returns whether the MONEY_BOX was up when an ask menu appeared (gh #185).
func _mb_drive(answers: Array, done: Callable) -> bool:
	var seen := false
	var g := 0
	while not done.call() and g < 900:
		await get_tree().process_frame
		if modal == menu and menu_mode == "cutscene":
			seen = seen or moneybox.visible
			menu.chosen.emit(int(answers.pop_front()) if answers.size() > 0 else 0)
		elif textbox.active and textbox.visible:
			textbox.advance()
		g += 1
	return seen


## gh #185: the MONEY_BOX shows through every paid dialog outside marts —
## vending machines, the Daycare fee, the Museum ticket, the Safari gate, the
## MtMoon Magikarp salesman — refreshing after payment and clearing at script end.
func _moneyboxtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_party = [make_mon("pidgey", 5, ["TACKLE"])]
	# --- vending machine: up with the intro, refreshed on buy, cleared on leave ---
	player_money = 1000
	player_bag = {}
	load_world("CeladonMartRoof")
	_vending_enter()
	var v_open: bool = moneybox.visible
	var g := 0
	while textbox.active and g < 60:
		textbox.advance()
		await get_tree().process_frame
		g += 1
	_vending_buy(0)                          # FRESH WATER ¥200
	var v_buy: bool = moneybox.visible and player_money == 800
	g = 0
	while textbox.active and g < 60:
		textbox.advance()
		await get_tree().process_frame
		g += 1
	_vending_buy(-1)                         # CANCEL -> "Not thirsty!" -> box clears
	g = 0
	while textbox.active and g < 60:
		textbox.advance()
		await get_tree().process_frame
		g += 1
	var v_hide: bool = not moneybox.visible
	print("[moneyboxtest] vending: open=%s buy=%s hidden=%s" % [v_open, v_buy, v_hide])
	# --- Daycare withdrawal: fee (8-5+1)*100 = 400 ---
	player_money = 5000
	daycare_mon = make_mon("rattata", 5, ["TACKLE"])
	daycare_mon["exp"] = exp_for_level(8, str(daycare_mon["growth"]))
	daycare_start_level = 5
	load_world("Daycare")
	player.place(Vector2i(1, 3)); player.facing = 3
	interact(player)
	var d_seen: bool = await _mb_drive([0], func() -> bool: return daycare_mon.is_empty() and not cutscene_active)
	var d_ok: bool = d_seen and not moneybox.visible and player_money == 4600
	# --- Museum ticket: ¥50 ---
	player_money = 1000
	story_events = {}
	load_world("Museum1F")
	cutscene.museum_ticket()
	var m_seen: bool = await _mb_drive([0], func() -> bool: return not cutscene_active)
	var m_ok: bool = m_seen and not moneybox.visible and has_event("BOUGHT_MUSEUM_TICKET") \
		and player_money == 950
	# --- Safari gate: ¥500, the entry warp clears the box with the map ---
	player_money = 1000
	load_world("SafariZoneGate")
	cutscene.safari_gate("SafariZoneCenter", 0)
	var s_seen: bool = await _mb_drive([0], func() -> bool: return not cutscene_active)
	var s_ok: bool = s_seen and not moneybox.visible and in_safari \
		and center_label == "SafariZoneCenter" and player_money == 500
	end_safari_game()
	# --- MtMoon Magikarp salesman: ¥500, no nickname ---
	player_money = 1000
	story_events = {}
	load_world("MtMoonPokecenter")
	cutscene.magikarp_salesman()
	var k_seen: bool = await _mb_drive([0, 1], func() -> bool: return not cutscene_active)
	var k_ok: bool = k_seen and not moneybox.visible and has_event("BOUGHT_MAGIKARP") \
		and player_money == 500 and player_party.size() == 3 \
		and str(player_party.back()["species"]) == "magikarp"    # pidgey + the daycare rattata first
	print("[moneyboxtest] daycare=%s museum=%s safari=%s magikarp=%s" % [d_ok, m_ok, s_ok, k_ok])
	print("[moneyboxtest] PASS=%s" % (v_open and v_buy and v_hide and d_ok and m_ok and s_ok and k_ok))
	get_tree().quit()


## gh #185: Up+Select+B at the title -> the clear-save dialogue (clear_save.asm), NO/YES
## with NO first; YES deletes the save, both reboot the title; no combo = normal start.
func _clearsavetest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_party = [make_mon("squirtle", 10, [])]
	load_world("PalletTown")
	save_game()                                       # a save to clear (the isolated test file)
	var existed := FileAccess.file_exists(SAVE_PATH)
	modal = title
	title.visible = true
	title.phase = "title"
	# The combo asks; declining (NO) reboots the title and keeps the save.
	Input.action_press("ui_up"); Input.action_press("p_select"); Input.action_press("ui_cancel")
	await _press("ui_accept")
	var asked: bool = menu_mode == "clear_save" and modal == menu
	_on_menu_chosen(0)                                # NO
	var kept: bool = FileAccess.file_exists(SAVE_PATH) and modal == title
	# YES clears it.
	title.phase = "title"
	await _press("ui_accept")
	var asked2: bool = menu_mode == "clear_save"
	_on_menu_chosen(1)                                # YES
	var cleared: bool = not FileAccess.file_exists(SAVE_PATH) and modal == title
	Input.action_release("ui_up"); Input.action_release("p_select"); Input.action_release("ui_cancel")
	await get_tree().process_frame
	# Without the combo held, A just opens the main menu.
	title.phase = "title"
	await _press("ui_accept")
	var normal: bool = menu_mode == "title"
	print("[clearsavetest] existed=%s asked=%s kept=%s asked_again=%s cleared=%s normal_start=%s" % [
		existed, asked, kept, asked2, cleared, normal])
	print("[clearsavetest] PASS=%s" % (existed and asked and kept and asked2 and cleared and normal))
	get_tree().quit()


func _marttest() -> void:
	await get_tree().process_frame
	story_events = {}                      # no GOT_STARTER -> no parcel cutscene on load
	player_name = "RED"
	player_money = 1000
	player_bag = {"POTION": 2}
	load_world("PewterMart")               # sells POKé BALL($200), POTION($300), ESCAPE ROPE, ...
	player.place(Vector2i(2, 5)); player.facing = 2   # in front of the counter -> clerk across at (0,5)
	var opened := interact(player)
	print("[marttest] clerk opens shop: opened=%s modal_is_mart=%s state=%s (expect top)" % [
		opened, modal == martscreen, martscreen.state])
	# BUY 3 POKé BALLs ($200 each) through qty + the YES/NO confirm.
	martscreen._top_select(0)              # BUY
	var pb: String = martscreen.stock[0]
	martscreen._list_select(0)             # POKé BALL -> qty strip
	var qmax: int = martscreen.maxq        # 1000/200 = 5 affordable
	martscreen.qty = 3
	martscreen._to_confirm()
	var confirm_state: String = martscreen.state
	martscreen._confirm(true)              # YES -> -$600
	print("[marttest] buy x3: qmax=%d (expect 5) confirm=%s money 1000->%d (expect 400) bag_pb=%d (expect 3)" % [
		qmax, confirm_state, player_money, int(player_bag.get(pb, 0))])
	# Affordability: at $400, POTION ($300) caps at 1.
	martscreen._list_select(1)             # POTION -> qty
	var pot_cap: int = martscreen.maxq
	martscreen.qty = pot_cap
	martscreen._to_confirm()
	martscreen._confirm(true)
	print("[marttest] potion cap=%d (expect 1) money=%d (expect 100) potion=%d (expect 3)" % [
		pot_cap, player_money, int(player_bag.get("POTION", 0))])
	# CANCEL back to BUY/SELL/QUIT, then SELL 2 POTIONs at half price (+$300).
	martscreen._list_select(martscreen.stock.size())    # CANCEL -> top
	var back_state: String = martscreen.state
	martscreen._top_select(1)              # SELL
	var pi: int = martscreen.bag_keys.find("POTION")
	var money_before_sell := player_money
	martscreen._list_select(pi)
	martscreen.qty = 2
	martscreen._to_confirm()
	martscreen._confirm(true)              # +$150 x2
	print("[marttest] cancel->state=%s (expect top) | sell POTION x2: money %d->%d (expect +300) potion=%d (expect 1)" % [
		back_state, money_before_sell, player_money, int(player_bag.get("POTION", 0))])
	# QUIT closes the shop with the farewell.
	martscreen._top_select(2)
	print("[marttest] quit: mart_hidden=%s farewell_text=%s" % [
		not martscreen.visible, modal == textbox])
	modal = null; textbox.visible = false
	# gh #132: every Celadon Mart TM must resolve a real price (TechnicalMachinePrices), not 0 — the exact
	# display lookup the mart does (marts stock const -> item_names display -> item_prices).
	var tm_all_ok := true
	var tm0 := 0
	for ic in marts["CeladonMart2F"]:
		var pr: int = int(item_prices.get(str(item_names.get(ic, ic)), 0))
		if pr <= 0:
			tm_all_ok = false
		if tm0 == 0:
			tm0 = pr
	print("[marttest] Celadon TMs priced (gh #132): all>0=%s first=%s=¥%d (expect ¥1000)" % [
		tm_all_ok, str(item_names.get(marts["CeladonMart2F"][0])), tm0])
	# gh #133: the TM18 clerk shows the OFFER before giving, then the EXPLANATION after — not the offer
	# again (which read as a loop). Talk once (get TM18), then again (should mention COUNTER, differ).
	story_events = {}
	player_bag = {}
	load_world("CeladonMart3F")
	player.place(Vector2i(15, 5), true); player.facing = 3     # face RIGHT -> the clerk at (16,5)
	interact(player)
	var got_tm18: bool = int(player_bag.get("TM18", 0)) == 1 and has_event("GOT_TM18")
	var offer := str(textbox.pages)
	modal = null; textbox.visible = false
	interact(player)                                           # re-talk: GOT_TM18 is now set
	var again := str(textbox.pages)
	print("[marttest] TM18 clerk (gh #133): got_tm18=%s explains_COUNTER=%s differs_from_offer=%s" % [
		got_tm18, again.contains("COUNTER"), again != offer])
	get_tree().quit()


## Gen-1 trainer AI probes (trainer_ai.asm): the move-choice modification layers and the
## per-class item handlers.
func _aitest() -> void:
	await get_tree().process_frame
	player_party = [make_mon("charmander", 10, ["SCRATCH"])]
	start_battle("rattata", 5)
	var b = battle
	b.is_trainer = true
	b.trainer_name = "TEST"
	# Mod1: a statused player means pure status moves get heavily discouraged.
	b.ai_mods = [1]
	b.enemy_mon["moves"] = [{"move": "SING", "pp": 15, "maxpp": 15},
		{"move": "TACKLE", "pp": 35, "maxpp": 35}]
	b.player_mon["status"] = "psn"
	var picks := {}
	for i in 60:
		picks[b._enemy_choose()] = true
	print("[aitest] mod1 statused player -> picks=%s (expect [TACKLE])" % [picks.keys()])
	# Mod3: the type matchup vs charmander (WATER 2x beats FIRE 0.5x).
	b.ai_mods = [1, 3]
	b.player_mon["status"] = ""
	b.enemy_mon["moves"] = [{"move": "WATER_GUN", "pp": 25, "maxpp": 25},
		{"move": "EMBER", "pp": 25, "maxpp": 25}]
	picks = {}
	for i in 60:
		picks[b._enemy_choose()] = true
	print("[aitest] mod3 vs charmander -> picks=%s (expect [WATER_GUN])" % [picks.keys()])
	# Brock cures his statused mon with FULL HEAL, no roll needed.
	b.ai_kind = "Brock"; b._ai_uses = 5
	b.enemy_mon["status"] = "par"
	var ms: Array = []
	var used: bool = b._ai_item_turn(ms)
	print("[aitest] Brock FULL HEAL: used=%s cured=%s uses=%d (expect true true 4)" % [
		used, str(b.enemy_mon["status"]) == "", b._ai_uses])
	# Lorelei heals below 1/5 HP (50%-gated roll; loop until it fires).
	b.ai_kind = "Lorelei"; b._ai_uses = 2
	b.enemy_mon["maxhp"] = 50; b.enemy_mon["hp"] = 5
	var healed := false
	for i in 60:
		ms = []
		if b._ai_item_turn(ms):
			healed = true
			break
	print("[aitest] Lorelei SUPER POTION: healed=%s hp=%d (expect 50)" % [healed, int(b.enemy_mon["hp"])])
	get_tree().quit()


## RARE CANDY runs the FULL level-up pipeline — stats, the learnset move (with the forget
## prompt), and evolution — exactly like a battle level-up. The old path skipped both
## (ItemUseMedicine .useRareCandy goes through the same LearnMoveFromLevelUp/evolution flow).
func _rare_candy(mon: Dictionary) -> void:
	modal = null
	var oldmax := int(mon["maxhp"])
	mon["level"] = int(mon["level"]) + 1
	mon["exp"] = exp_for_level(int(mon["level"]), str(mon["growth"]))
	recompute_stats(mon)
	mon["hp"] = int(mon["hp"]) + (int(mon["maxhp"]) - oldmax)
	if audio:
		audio.play_sfx("level_up")
	await cutscene.say("%s grew to\nlevel %d!" % [mon["name"], int(mon["level"])])
	for lm in mon_base[str(mon["species"])]["level_moves"]:
		if int(lm[0]) == int(mon["level"]):
			await _overworld_learn(mon, str(lm[1]))
	var into := ""
	for ev in mon_base[str(mon["species"])]["evolutions"]:
		if str(ev[0]) == "EVOLVE_LEVEL" and int(mon["level"]) >= int(ev[1]):
			into = str(ev[2])
	if into != "":
		await run_evolution(mon, into)               # the full sequence, B-cancellable (gh #67)


## The overworld "wants to learn" flow with the forget prompt (LearnMoveFromLevelUp texts).
func _overworld_learn(mon: Dictionary, move: String) -> void:
	for mv in mon["moves"]:
		if str(mv["move"]) == move:
			return                                # already knows it
	var mname := str(mon_moves[move]["name"]) if mon_moves.has(move) else move
	var maxpp := int(mon_moves.get(move, {}).get("pp", 5))
	if (mon["moves"] as Array).size() < 4:
		mon["moves"].append({"move": move, "pp": maxpp, "maxpp": maxpp})
		await cutscene.say("%s learned\n%s!" % [mon["name"], mname])
		return
	while true:
		# TryingToLearn: declining the delete (or B on the forget menu) asks "Abandon
		# learning?"; NO loops back to the whole prompt (AbandonLearning -> DontAbandonLearning).
		if not await cutscene.ask("%s is trying to\nlearn %s!\fBut, %s can't\nlearn more than\n4 moves!\fDelete an older\nmove to make room\nfor %s?" % [
				mon["name"], mname, mon["name"], mname]):
			if await cutscene.ask("Abandon learning\n%s?" % mname):
				await cutscene.say("%s did not\nlearn %s!" % [mon["name"], mname])
				return
			continue
		var names: Array = []
		for mv in mon["moves"]:
			var k := str(mv["move"])
			names.append(str(mon_moves[k]["name"]) if mon_moves.has(k) else k)
		var mi := -1
		while true:
			await cutscene.say("Which move should\nbe forgotten?")
			menu_mode = "cutscene"
			modal = menu
			_open_move_forget_menu(names)
			mi = await menu.chosen
			modal = null
			if mi >= 0 and str(mon["moves"][mi]["move"]) in HM_MOVES.values():
				await cutscene.say("HM techniques\ncan't be deleted!")   # IsMoveHM -> re-prompt
				continue
			break
		if mi < 0:
			if await cutscene.ask("Abandon learning\n%s?" % mname):      # B on the forget menu
				await cutscene.say("%s did not\nlearn %s!" % [mon["name"], mname])
				return
			continue
		var forgot: String = names[mi]
		mon["moves"][mi] = {"move": move, "pp": maxpp, "maxpp": maxpp}
		await cutscene.say("1, 2 and...\fPoof!\f%s forgot\n%s!\fAnd...\f%s learned\n%s!" % [
			mon["name"], forgot, mon["name"], mname])
		return


## WhichMoveToForget (engine/pokemon/learn_move.asm): TextBoxBorder at (4,7) with
## a 14x4-tile interior; PlaceString starts at (6,8), and the cursor starts at (5,8).
func _open_move_forget_menu(names: Array) -> void:
	menu.open(names, Vector2(4 * TILE, 7 * TILE))
	menu.box_w = 16                         # c=14 interior plus the two border columns
	menu.box_h = 6                          # b=4 interior plus the two border rows
	menu.row0 = 1                           # names/cursor begin at row 8
	menu.single_spaced = true               # BIT_SINGLE_SPACED_LINES: rows 8, 9, 10, 11
	menu.queue_redraw()


## Apply an ETHER / MAX ETHER / PP UP to the picked technique (ItemUseMedicine / PP UP).
func _bag_use_on_move(mi: int) -> void:
	textbox.visible = false
	if mi < 0 or _bag_target_idx >= player_party.size():
		_open_bag()                           # backed out of the technique pick: the bag again
		return
	var mon: Dictionary = player_party[_bag_target_idx]
	if mi >= (mon["moves"] as Array).size():
		_open_bag()
		return
	var mv: Dictionary = mon["moves"][mi]
	var key := str(mv["move"])
	var mname := str(mon_moves[key]["name"]) if mon_moves.has(key) else key
	if selected_item == "PP UP":
		var ups := int(mv.get("ppup", 0))
		if ups >= 3:                          # three applications max (the PP byte's upper bits)
			_say_bag("%s's PP\nis maxed out." % mname)
			return
		mv["ppup"] = ups + 1
		var base_pp := int(mon_moves.get(key, {}).get("pp", int(mv["maxpp"])))
		mv["maxpp"] = int(base_pp * (5 + ups + 1) / 5.0)
		_consume(selected_item)
		_say_bag("%s's PP\nincreased." % mname)
		return
	var amt := int(PP_ITEMS[selected_item][0])
	var to := int(mv["maxpp"]) if amt < 0 else mini(int(mv["maxpp"]), int(mv["pp"]) + amt)
	if to <= int(mv["pp"]):
		_say_bag("It won't have\nany effect.")
		return
	mv["pp"] = to
	_consume(selected_item)
	_say_bag("PP was restored.")


## Memory audit (gh #44): loads a heavy multi-connection map and reports where the bytes are.
func _memtest() -> void:
	await get_tree().process_frame
	load_world("ViridianCity")
	for i in 30:
		await get_tree().process_frame
	print("[memtest] static=%.1f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	print("[memtest] texture_mem=%.1f MB video_mem=%.1f MB" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
	print("[memtest] objects=%d nodes=%d" % [
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	print("[memtest] songs_cached=%d sfx_cached=%d" % [audio._cache.size(), audio._sfx_cache.size()])
	get_tree().quit()


## Recreate the exact states of the user's reference screenshots (build/preview/bugs) so the
## renders can be pixel-diffed against them: the issue25 party and the issue26 summary pages.
func _refshots() -> void:
	await get_tree().process_frame
	player_name = "GEO"
	player_id = 19052
	player_party = [
		make_mon("charmander", 12, []), make_mon("rattata", 4, []),
		make_mon("pidgey", 3, []), make_mon("nidoranm", 4, []),
		make_mon("spearow", 3, []), make_mon("nidoranf", 3, []),
	]
	var hp := [[23, 34], [17, 17], [15, 15], [1, 18], [5, 16], [5, 16]]
	for i in 6:
		player_party[i]["maxhp"] = hp[i][1]
		player_party[i]["hp"] = hp[i][0]
	load_world("PalletTown", -1, Vector2i(10, 8), false)
	await _ui_snap("refparty", func() -> void: _open_party_view())
	await _ui_snap("refstats1", func() -> void:
		modal = statsscreen
		statsscreen.open(player_party[1]))       # RATTATA L4 17/17, page 1
	await _ui_snap("refstats2", func() -> void:
		modal = statsscreen
		statsscreen.open(player_party[1])
		statsscreen.page = 1
		statsscreen.queue_redraw())
	get_tree().quit()


func _roofgirltest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_bag = {"SODA POP": 1}
	load_world("CeladonMartRoof", -1, Vector2i(5, 6), false)
	var girl = _npc_by_key("SPRITE_LITTLE_GIRL@5,5")
	player.place(girl.cell + Vector2i(0, 1)); player.facing = player.UP
	interact(player)
	var g := 0
	while cutscene_active and g < 900:                # YES -> SODA POP -> TM48
		if modal == menu or modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	print("[roofgirltest] soda->TM48: tm=%d (expect 1) soda_gone=%s event=%s" % [
		int(player_bag.get("TM48", 0)), not player_bag.has("SODA POP"), has_event("GOT_TM48")])
	player_bag["SODA POP"] = 1                        # a second soda: she's not thirsty for it
	player.place(girl.cell + Vector2i(0, 1)); player.facing = player.UP
	interact(player)
	g = 0
	while cutscene_active and g < 900:
		if modal == menu or modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	print("[roofgirltest] repeat refused: tm48_still=%d (expect 1) soda_kept=%s" % [
		int(player_bag.get("TM48", 0)), int(player_bag.get("SODA POP", 0)) == 1])
	get_tree().quit()


func _nameratertest() -> void:
	await get_tree().process_frame
	player_name = "RED"
	player_party = [make_mon("rattata", 5, []), make_mon("jynx", 10, [])]
	player_party[1]["ot"] = "TRAINER"                 # traded mon: the rater refuses it
	load_world("NameRatersHouse", -1, Vector2i(5, 4), false)
	player.facing = player.UP                         # the rater sits at (5,3)
	var handled := interact(player)
	var saw_naming := false
	var g := 0
	while cutscene_active and g < 900:                # flow 1: rename RATTATA -> SPEEDY
		if modal == naming:
			saw_naming = true
			naming.visible = false
			naming.done.emit("SPEEDY")
		elif modal == menu or modal == textbox:
			await _press("ui_accept")                 # YES / pick slot 0 / advance text
		else:
			await get_tree().process_frame
		g += 1
	print("[nameratertest] handled=%s renamed=%s (expect SPEEDY): got %s, naming_shown=%s" % [
		handled, str(player_party[0]["name"]) == "SPEEDY", player_party[0]["name"], saw_naming])
	interact(player)                                  # flow 2: the traded JYNX is refused
	saw_naming = false
	g = 0
	while cutscene_active and g < 900:
		if modal == naming:
			saw_naming = true
			naming.visible = false
			naming.done.emit("X")
		elif modal == menu and menu.party_mode and menu.cursor == 0:
			await _press("ui_down")                   # move the pick to JYNX
		elif modal == menu or modal == textbox:
			await _press("ui_accept")
		else:
			await get_tree().process_frame
		g += 1
	print("[nameratertest] traded: refused=%s (expect true, no keyboard) jynx=%s" % [
		not saw_naming, player_party[1]["name"]])
	get_tree().quit()


func _itemtest() -> void:
	await get_tree().process_frame
	picked_items = {}
	player_bag = {}
	player_name = "RED"
	load_world("ViridianForest")               # item balls: POTION@12,29, ANTIDOTE@25,11, POKé BALL@1,31
	var ball = _npc_by_key("SPRITE_POKE_BALL@12,29")
	print("[itemtest] spawn: item=%s shown=%s" % [ball.item, ball.shown])
	player.place(Vector2i(11, 29)); player.facing = 3   # face RIGHT -> the ball at (12,29); (12,30) is a tree (gh #84)
	var handled := interact(player)
	print("[itemtest] pickup: handled=%s bag_potion=%d ball_shown=%s picked=%s" % [
		handled, int(player_bag.get("POTION", 0)), ball.shown, picked_items.has("ViridianForest:12,29")])
	modal = null; textbox.visible = false
	load_world("ViridianForest")               # reload: the taken ball stays gone, others remain
	var ball2 = _npc_by_key("SPRITE_POKE_BALL@12,29")
	var anti = _npc_by_key("SPRITE_POKE_BALL@25,11")
	print("[itemtest] after reload: taken_ball_shown=%s (expect false) | antidote item=%s shown=%s" % [
		ball2.shown, anti.item, anti.shown])
	# gh #175: the overworld use texts. COIN CASE reports the balance; OAK's PARCEL refuses with
	# "isn't yours"; everything unusable funnels into OAK's ItemUseNotTime line — never an
	# invented "Can't use that here!".
	player_coins = 123
	var texts := {}
	for it in ["COIN CASE", "OAK's PARCEL", "POKé BALL", "X ATTACK", "NUGGET"]:
		selected_item = it
		_bag_use()
		texts[it] = "\f".join(textbox.pages)
		modal = null; textbox.visible = false
	var coin_ok: bool = "0123" in str(texts["COIN CASE"])
	var parcel_ok: bool = "isn't yours" in str(texts["OAK's PARCEL"])
	var oak_ok: bool = true
	for it in ["POKé BALL", "X ATTACK", "NUGGET"]:
		oak_ok = oak_ok and "This isn't the" in str(texts[it]) and "OAK: RED!" in str(texts[it])
	print("[itemtest] overworld_use(gh#175): coin_case=%s parcel=%s oak_refusal=%s" % [
		coin_ok, parcel_ok, oak_ok])
	get_tree().quit()


func _surgetest() -> void:
	await get_tree().process_frame
	story_events = {"GOT_POKEDEX": true}
	badges = []
	player_name = "RED"
	player_party = [make_mon("squirtle", 50, ["TACKLE"])]
	player_bag = {}
	load_world("VermilionGym")
	var door_closed: bool = not is_walkable(Vector2i(4, 4))   # top tile of the door block (2,2)
	print("[surgetest] can_index (1,7)=%d (9,11)=%d (2,2)=%d | door_closed=%s" % [
		map_script("VermilionGym")._trash_can_index(Vector2i(1, 7)), map_script("VermilionGym")._trash_can_index(Vector2i(9, 11)),
		map_script("VermilionGym")._trash_can_index(Vector2i(2, 2)), door_closed])
	# Wrong first can -> just trash, no lock.
	map_script("VermilionGym")._trash_check((_trash_first + 1) % 15); modal = null; textbox.visible = false
	var no_lock := not has_event("VERMILION_1ST_LOCK")
	# Correct first switch.
	map_script("VermilionGym")._trash_check(_trash_first); modal = null; textbox.visible = false
	var first_ok := has_event("VERMILION_1ST_LOCK")
	# Wrong second can -> reset.
	map_script("VermilionGym")._trash_check((_trash_second + 1) % 15); modal = null; textbox.visible = false
	var reset_ok := not has_event("VERMILION_1ST_LOCK")
	# Redo first (was re-randomized on reset), then solve with the fresh second.
	map_script("VermilionGym")._trash_check(_trash_first); modal = null; textbox.visible = false
	map_script("VermilionGym")._trash_check(_trash_second); modal = null; textbox.visible = false
	var solved: bool = has_event("VERMILION_2ND_LOCK")
	var door_open: bool = is_walkable(Vector2i(4, 4))
	print("[surgetest] puzzle: no_lock_on_wrong=%s first_ok=%s reset_on_wrong2=%s solved=%s door_open=%s" % [
		no_lock, first_ok, reset_ok, solved, door_open])
	# Battle Lt. Surge -> Thunder Badge + TM24.
	player.place(Vector2i(5, 2)); player.facing = 1          # face UP -> Surge at (5,1)
	interact(player)
	var win_forced := false
	for i in 5000:
		await get_tree().process_frame
		if textbox.active and textbox.visible:
			textbox.advance()
		elif modal == battle and not battle.won:
			print("[surgetest] battle: trainer=%s enemy=%s lv=%d" % [
				battle.trainer_name, battle.enemy_mon["species"], int(battle.enemy_mon["level"])])
			battle.won = true; battle.blacked_out = false; battle.finished.emit(); win_forced = true
		if win_forced and not cutscene_active and modal == null:
			break
	print("[surgetest] result: thunder=%s beat=%s tm24=%s" % [
		"THUNDERBADGE" in badges, has_event("BEAT_LT_SURGE"), player_bag.has("TM24")])
	get_tree().quit()


func _maptest() -> void:
	await get_tree().process_frame
	# The previously-skipped underground maps now load with consistent collision dimensions.
	for label in ["UndergroundPathNorthSouth", "UndergroundPathRoute7Copy", "UndergroundPathRoute5"]:
		load_world(label)
		print("[maptest] %s: gw=%d gh=%d collision=%d (expect %d) warps=%d player=%s" % [
			label, gw, gh, collision.size(), gw * gh, (map["warps"] as Array).size(), str(player.cell)])
	get_tree().quit()


func _badgetest() -> void:
	await get_tree().process_frame
	badges = []
	player_party = [make_mon("charmander", 30, ["SCRATCH"])]
	start_battle("rattata", 5)
	var g := 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	var base_atk: int = int(battle.player_mon["atk"])
	var base_def: int = int(battle.player_mon["def"])
	battle._rebuild_mod_stats(true)
	var without: int = int(battle.p_mod["atk"])
	badges = ["BOULDERBADGE"]
	battle._rebuild_mod_stats(true)
	var with_boulder: int = int(battle.p_mod["atk"])
	var enemy_atk: int = int(battle.e_mod["atk"])      # foe must not get the boost
	# The badge->stat map is by BIT position (BadgeStatBoosts): CASCADE boosts NOTHING,
	# and it's THUNDER that boosts DEFENSE (Soul->speed, Volcano->special).
	badges = ["CASCADEBADGE"]
	battle._rebuild_mod_stats(true)
	var cascade_nothing: bool = int(battle.p_mod["atk"]) == base_atk \
		and int(battle.p_mod["def"]) == base_def
	badges = ["THUNDERBADGE"]
	battle._rebuild_mod_stats(true)
	var thunder_def: bool = int(battle.p_mod["def"]) == base_def + (base_def >> 3) \
		and int(battle.p_mod["spd"]) == int(battle.player_mon["spd"])
	print("[badgetest] atk base=%d no_badge=%d boulder=%d (expect +%d)" % [
		base_atk, without, with_boulder, base_atk >> 3])
	print("[badgetest] atk_boost_ok=%s cascade_boosts_nothing=%s thunder_boosts_def=%s enemy_unboosted=%s" % [
		with_boulder == base_atk + (base_atk >> 3) and without == base_atk,
		cascade_nothing, thunder_def, enemy_atk == int(battle.enemy_mon["atk"])])
	get_tree().quit()


func _sfxtest() -> void:
	await get_tree().process_frame
	# 1) The battle SFX (engine-2 bank) are all extracted.
	var want := ["damage", "super_effective", "not_very_effective", "faint_fall",
		"level_up", "ball_toss", "caught_mon", "run"]
	var missing: Array = []
	for k in want:
		if not audio.sfx.has(k):
			missing.append(k)
	print("[sfxtest] sfx keys ok=%s missing=%s (total %d)" % [missing.is_empty(), str(missing), audio.sfx.size()])
	audio.log_sfx = true

	# 2) Attack that's super-effective and faints the foe (near a level-up): hit + faint + level_up.
	player_bag = {"POKé BALL": 5}
	player_party = [make_mon("charmander", 30, ["EMBER", "SCRATCH"])]
	player_party[0]["exp"] = exp_for_level(31, str(player_party[0]["growth"])) - 5
	audio.sfx_log = []
	start_battle("caterpie", 3)              # FIRE EMBER vs BUG -> super effective
	battle.fast_hp = false                   # real presentation: the faint slide plays its SFX
	var g := 0
	while battle.state != "menu" and modal == battle and g < 600:
		await _press("ui_accept"); g += 1
	g = 0
	while modal == battle and g < 600:
		await _press("ui_accept"); g += 1
	battle.fast_hp = true
	print("[sfxtest] attack: hit=%s faint=%s level_up=%s log=%s" % [
		"super_effective" in audio.sfx_log or "damage" in audio.sfx_log,
		"faint_fall" in audio.sfx_log, "level_up" in audio.sfx_log, str(audio.sfx_log)])
	# Per-move attack SFX (MoveSoundTable): EMBER plays its own sound when used.
	var ember_key: String = str(move_sfx["EMBER"][0]) if move_sfx.has("EMBER") else "?"
	print("[sfxtest] move_sfx: loaded=%d EMBER->%s played=%s" % [
		move_sfx.size(), ember_key, ember_key in audio.sfx_log])

	# 3) Catch: throw a Poké Ball at a weakened foe -> ball_toss + caught_mon.
	audio.sfx_log = []
	start_battle("rattata", 3)
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	battle.enemy_mon["hp"] = 1
	await _press("ui_down"); await _press("ui_accept")   # the 2x2 menu: down = ITEM; open it
	await _press("ui_accept")                # use POKé BALL
	g = 0
	while modal == battle and g < 40:
		await _press("ui_accept"); g += 1
	print("[sfxtest] catch: ball_toss=%s caught_mon=%s log=%s" % [
		"ball_toss" in audio.sfx_log, "caught_mon" in audio.sfx_log, str(audio.sfx_log)])

	# 4) Run from a wild battle -> run.
	audio.sfx_log = []
	start_battle("rattata", 3)
	g = 0
	while battle.state != "menu" and modal == battle and g < 400:
		await _press("ui_accept"); g += 1
	await _press("ui_down"); await _press("ui_right")    # the 2x2 menu: RUN is down+right
	await _press("ui_accept")
	g = 0
	while modal == battle and g < 40:
		await _press("ui_accept"); g += 1
	print("[sfxtest] run: run_sfx=%s log=%s" % ["run" in audio.sfx_log, str(audio.sfx_log)])
	get_tree().quit()


## gh #107: the Mt Moon fossil SUPER NERD. He has no sight cone, so the only thing that must stop a
## walk-past is the (13,8) coordinate guard. Proven by reachability (the strong test — no teleporting):
## with the nerd on (12,8) and the guard holding (13,8), no fossil-adjacent cell is reachable; open (13,8)
## and they are. Plus the guard's decision: it engages the nerd undefeated, and stays silent once beaten.
func _fossilguardtest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_name = "RED"
	player_party = [make_mon("squirtle", 30, ["TACKLE"])]
	load_world("MtMoonB2F", -1, Vector2i(13, 10))   # in the nerd's corridor, just south of the gateway
	await get_tree().process_frame
	var ms = map_script("MtMoonB2F")
	var nerd = _npc_by_key("SPRITE_SUPER_NERD@12,8")
	var fossils := [Vector2i(12, 7), Vector2i(13, 7), Vector2i(11, 6), Vector2i(14, 6), Vector2i(12, 5), Vector2i(13, 5)]
	var ok := true

	if nerd == null:
		print("[fossilguard] FAIL: no Super Nerd NPC"); get_tree().quit(1); return
	if nerd.sight != 0:
		print("[fossilguard] FAIL: nerd sight=%d — a sight cone would mask the real (walk-past) bug" % nerd.sight); ok = false
	if nerd.battle_text == "":
		print("[fossilguard] FAIL: nerd has no before-battle text (on_enter didn't wire it)"); ok = false

	# Flood-fill from the player's spawn, treating `extra` cells as walls.
	var reach := func(start: Vector2i, extra: Array) -> Dictionary:
		var seen := {start: true}
		var q: Array[Vector2i] = [start]
		while not q.is_empty():
			var c: Vector2i = q.pop_front()
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var n: Vector2i = c + d
				if seen.has(n) or extra.has(n) or not is_walkable(n):
					continue
				seen[n] = true
				q.append(n)
		return seen

	var start: Vector2i = player.cell
	# Nerd on (12,8) + guard holding (13,8): every fossil-adjacent cell must be unreachable.
	var blocked: Dictionary = reach.call(start, [Vector2i(12, 8), Vector2i(13, 8)])
	for f in fossils:
		if blocked.has(f):
			print("[fossilguard] FAIL: fossil cell %s reachable while the nerd guards (13,8)" % str(f)); ok = false
	# Open the gateway (nerd beaten): now at least one fossil cell is reachable — (13,8) really is the door.
	var opened: Dictionary = reach.call(start, [Vector2i(12, 8)])
	var any_open := false
	for f in fossils:
		if opened.has(f):
			any_open = true
	if not any_open:
		print("[fossilguard] FAIL: fossils unreachable even with (13,8) open — bad start/geometry"); ok = false

	# The guard's decision: engages the nerd while undefeated…
	cutscene_active = false
	modal = null
	if not ms.on_step(Vector2i(13, 8)):
		print("[fossilguard] FAIL: on_step did not engage the nerd on (13,8)"); ok = false
	elif not cutscene_active:
		print("[fossilguard] FAIL: guard fired but no cutscene started"); ok = false
	# …and stays silent once he is beaten (MtMoonB2FDefaultScript rets early).
	cutscene_active = false
	modal = null
	defeated_trainers["MtMoonB2F:12,8"] = true
	if ms.on_step(Vector2i(13, 8)):
		print("[fossilguard] FAIL: guard re-fired after the nerd was beaten"); ok = false

	print("[fossilguard] %s: sight=%d, (13,8) is the sole fossil approach, guard fires then quiets" % [
		"PASS" if ok else "FAIL", nerd.sight])
	get_tree().quit(0 if ok else 1)


func _gymtest() -> void:
	await get_tree().process_frame
	player_name = "RED"
	# Pewter / Brock and Cerulean / Misty: same gym-leader path, different data.
	await _run_gym("PewterGym", "SPRITE_SUPER_NERD@4,1", Vector2i(4, 2), "BOULDERBADGE", "TM34", "BEAT_BROCK")
	await _run_gym("CeruleanGym", "SPRITE_BRUNETTE_GIRL@4,2", Vector2i(4, 3), "CASCADEBADGE", "TM11", "BEAT_MISTY")
	# gh #109: beating the leader marks the gym's trainers defeated so they no longer engage.
	print("[gymtest] gh#109 CeruleanGym trainers defeated after MISTY: jr=%s swimmer=%s (expect both true)" % [
		defeated_trainers.has("CeruleanGym:2,3"), defeated_trainers.has("CeruleanGym:8,7")])
	await _run_gym("CeladonGym", "SPRITE_SILPH_WORKER_F@4,3", Vector2i(4, 4), "RAINBOWBADGE", "TM21", "BEAT_ERIKA")
	await _run_gym("FuchsiaGym", "SPRITE_KOGA@4,10", Vector2i(4, 11), "SOULBADGE", "TM06", "BEAT_KOGA")
	await _run_gym("SaffronGym", "SPRITE_GIRL@9,8", Vector2i(9, 9), "MARSHBADGE", "TM46", "BEAT_SABRINA")
	await _run_gym("CinnabarGym", "SPRITE_MIDDLE_AGED_MAN@3,3", Vector2i(3, 4), "VOLCANOBADGE", "TM38", "BEAT_BLAINE")
	await _run_gym("ViridianGym", "SPRITE_GIOVANNI@2,1", Vector2i(2, 2), "EARTHBADGE", "TM27", "BEAT_GIOVANNI")
	# gh #68: the gym statues — the plaque lists <RIVAL>, and the player once badged (UP only).
	badges = []
	rival_name = "BLUE"
	load_world("PewterGym")
	player.place(Vector2i(3, 11)); player.facing = 1     # face UP at the statue (3,10)
	interact(player)
	var t1 := "" if textbox.pages.is_empty() else "\n".join(textbox.pages)
	var statue_ok: bool = "BROCK" in t1 and "BLUE" in t1 and not "RED" in t1
	modal = null; textbox.visible = false
	player.facing = 0                                    # facing DOWN: the statue stays quiet
	interact(player)
	var silent: bool = modal == null
	badges = ["BOULDERBADGE"]
	player.facing = 1
	interact(player)
	var t2 := "" if textbox.pages.is_empty() else "\n".join(textbox.pages)
	var statue_won: bool = "BLUE" in t2 and "RED" in t2
	modal = null; textbox.visible = false
	print("[gymtest] statue: plaque=%s down_silent=%s player_added=%s (expect true true true)" % [
		statue_ok, silent, statue_won])
	get_tree().quit()


## Drive one gym: challenge the leader, force a win, then verify badge + TM + re-talk advice.
func _run_gym(gym: String, leader_key: String, stand: Vector2i, badge: String, tm: String, ev: String) -> void:
	story_events = {"GOT_POKEDEX": true}
	badges = []
	player_party = [make_mon("squirtle", 50, ["TACKLE"])]
	player_bag = {}
	load_world(gym)
	var leader = _npc_by_key(leader_key)
	print("[gymtest] %s: leader shown=%s class=%s is_leader=%s sight=%d (expect 0: talk-only, gh #55)" % [
		gym, leader.shown, leader.trainer_class, cutscene.is_gym_leader(leader.trainer_class),
		int(leader.sight)])
	player.place(stand); player.facing = 1            # face UP toward the leader one tile above
	interact(player)
	var pages: Array = []
	var prev := false
	var win_forced := false
	for i in 5000:
		await get_tree().process_frame
		var act: bool = textbox.active and textbox.visible
		if act and not prev and textbox.pages.size() > 0:
			pages.append(str(textbox.pages[0]).replace("\n", " "))
		prev = act
		if act:
			textbox.advance()
		elif modal == battle and not battle.won:
			print("[gymtest] %s battle: trainer=%s enemy=%s lv=%d" % [
				gym, battle.trainer_name, battle.enemy_mon["species"], int(battle.enemy_mon["level"])])
			battle.won = true
			battle.blacked_out = false
			battle.finished.emit()
			win_forced = true
		if win_forced and not cutscene_active and modal == null:
			break
	print("[gymtest] %s result: badge=%s beat=%s tm=%s | first/last page: %s ... %s" % [
		gym, badge in badges, has_event(ev), player_bag.has(tm),
		pages[0] if pages.size() > 0 else "?", pages[-1] if pages.size() > 0 else "?"])
	# Re-talking the beaten leader shows its post line.
	interact(player)
	var post := str(textbox.pages[0]).replace("\n", " ") if (modal == textbox and textbox.pages.size() > 0) else ""
	await _drive_until(func() -> bool: return not cutscene_active and modal == null, 400)
	print("[gymtest] %s re-talk: %s" % [gym, post])


func _housetest() -> void:
	await get_tree().process_frame
	story_events = {}
	player_party = [make_mon("charmander", 5, [])]   # has a starter, so no Pallet gate
	last_outside_map = "PalletTown"
	load_world("RedsHouse2F", -1, Vector2i(3, 6))
	# SNES: spawn cell (3,6) facing UP -> faced tile (3,5).
	player.facing = 1
	var snes := interact(player)
	var snes_text := str(textbox.pages[0]) if (modal == textbox and textbox.pages.size() > 0) else ""
	modal = null; textbox.visible = false
	# PC: stand at (0,2) facing UP -> faced tile (0,1).
	player.place(Vector2i(0, 2)); player.facing = 1
	var pc := interact(player)
	var pc_text := str(textbox.pages[0]) if (modal == textbox and textbox.pages.size() > 0) else ""
	modal = null; textbox.visible = false
	print("[housetest] SNES handled=%s text=%s" % [snes, snes_text])
	print("[housetest] PC handled=%s text=%s" % [pc, pc_text])
	# Exit: 2F stairs (7,1) -> 1F, then 1F door (2,7) -> PalletTown (LAST_MAP).
	player.place(Vector2i(7, 1)); warp_armed = true
	_on_player_moved(Vector2i(7, 1))
	var after_stairs := center_label
	player.place(Vector2i(2, 7)); warp_armed = true
	_on_player_moved(Vector2i(2, 7))
	print("[housetest] stairs->%s (expect RedsHouse1F), door->%s (expect PalletTown)" % [
		after_stairs, center_label])
	get_tree().quit()


func _nametest() -> void:
	await get_tree().process_frame
	naming.open("YOUR", ["RED", "ASH", "JACK"], "First, what is\nyour name?")
	naming.mode = "keyboard"
	naming.name_buf = "RE"
	naming.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://name_kb.png")
	# Preset list with the trainer pic slid right beside it (full intro presentation).
	cutscene.visible = true
	cutscene.pic(load("res://assets/title/redfront.png"))
	cutscene._pic_pos = Vector2(96, 24)               # post-slide position
	cutscene.queue_redraw()
	naming.mode = "presets"
	naming.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://name_presets.png")
	cutscene.visible = false
	cutscene.clear_pic()
	print("[nametest] rendered keyboard + presets")
	get_tree().quit()                            # every other driver quits; without this a headless run hangs


func _saveshot() -> void:
	await get_tree().process_frame
	load_world("PalletTown")
	player_name = "GEO"
	pokedex_owned["charmander"] = true
	play_seconds = 2 * 3600 + 28 * 60
	menu_mode = "yesno_save"
	modal = menu
	menu.open(["YES", "NO"], Vector2(0, 56))
	menu.save_info = {"player": player_name, "badges": badges.size(), "dex": pokedex_owned.size(),
		"time": "%3d:%02d" % [int(play_seconds / 3600.0), int(play_seconds / 60.0) % 60]}
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://save.png")
	# gh #156: YES -> "Now saving..." holds 120 frames, then "<PLAYER> saved the game!" + SFX_SAVE.
	_on_menu_chosen(0)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://save2.png")
	var now_saving: bool = textbox.visible and modal == textbox
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://save3.png")
	DirAccess.open("user://").remove(SAVE_PATH.get_file())   # clean the test save
	print("[saveshot] rendered now_saving=%s" % now_saving)
	get_tree().quit()


func _statsshot() -> void:
	await get_tree().process_frame
	var m: Dictionary = make_mon("charmander", 7, [])
	m["hp"] = 16; m["maxhp"] = 24; m["exp"] = 269
	player_id = 19052; player_name = "GEO"
	for pg in [0, 1]:
		modal = statsscreen
		statsscreen.open(m)
		statsscreen.page = pg
		statsscreen.queue_redraw()
		for _i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://stats%d.png" % pg)
	print("[statsshot] rendered 2 pages")
	get_tree().quit()


func _partyshot() -> void:
	await get_tree().process_frame
	player_party = [make_mon("charmander", 7, []), make_mon("pidgey", 5, []), make_mon("rattata", 4, [])]
	player_party[0]["hp"] = 16; player_party[0]["maxhp"] = 24
	_open_party_view()
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://party.png")
	print("[partyshot] party=%d" % player_party.size())
	get_tree().quit()


func _dexlistshot() -> void:
	await get_tree().process_frame
	for sp in ["bulbasaur", "ivysaur", "charmander", "squirtle", "pidgey"]:
		pokedex_seen[sp] = true
	pokedex_owned["charmander"] = true
	pokedex_owned["squirtle"] = true
	modal = dexlist
	dexlist.open()
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://dexlist.png")
	print("[dexlistshot] seen=%d own=%d" % [pokedex_seen.size(), pokedex_owned.size()])
	get_tree().quit()


func _dexshot() -> void:
	await get_tree().process_frame
	for sp in ["charmander", "squirtle"]:
		var num: int = dex_order.find(sp) + 1
		var tex: Texture2D = load("res://assets/pokemon/front/%s.png" % sp)
		modal = dexentry
		dexentry.open(mon_display_name(sp), dex_entries[sp], tex, num)
		for _i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://dexentry_%s.png" % sp)
		print("[dexshot] %s No%03d cat=%s" % [sp, num, dex_entries[sp]["cat"]])
	get_tree().quit()


func _catchnicktest() -> void:
	# After catching a wild mon, the "give it a nickname?" prompt should appear (#6).
	await get_tree().process_frame
	load_world("PalletTown")
	var mon := make_mon("rattata", 3, [])
	battle.caught = true
	battle.blacked_out = false
	battle.enemy_mon = mon
	_on_battle_finished()                 # async: runs offer_nickname
	await get_tree().process_frame
	await get_tree().process_frame
	var offered: bool = modal == textbox and textbox.visible
	print("[catchnicktest] offered=%s cutscene_active=%s" % [offered, cutscene_active])
	print("[catchnicktest] PASS=%s" % offered)
	get_tree().quit()


func _exitwarptest() -> void:
	# Exit the player's house, then confirm the door above is still an armed warp (issue #1).
	battle.fast_hp = true                    # skip the warp fade so _do_warp completes synchronously
	load_world("RedsHouse1F")
	last_outside_map = "PalletTown"                      # house doors exit via LAST_MAP
	var exit_w = null
	for w in map["warps"]:
		if str(w.get("dest_const", "")) == "LAST_MAP":
			exit_w = w
			break
	_do_warp(exit_w)
	var door: Vector2i = player.cell + Vector2i(0, -1)   # the door we stepped down from
	var re_ok: bool = warp_armed and _warp_at(door) != null
	print("[exitwarptest] outside=%s player=%s door_is_warp=%s armed=%s" % [
		center_label, str(player.cell), _warp_at(door) != null, warp_armed])
	# gh #114: an underground-path connector's LAST_MAP exit must go to ITS route, not wherever you came
	# from. Enter UndergroundPathRoute6 with a stale last_outside_map (as if walked in from Route 5) and
	# confirm on_enter reset it to Route6, so the exit lands on Route 6, not loops back to Route 5.
	last_outside_map = "Route5"
	load_world("UndergroundPathRoute6")                  # _on_map_loaded -> on_enter sets last_outside_map
	var lom_ok: bool = last_outside_map == "Route6"
	var upath_exit = null
	for w in map["warps"]:
		if str(w.get("dest_const", "")) == "LAST_MAP":
			upath_exit = w
			break
	_do_warp(upath_exit)
	var upath_ok: bool = center_label == "Route6"
	print("[exitwarptest] gh#114 underground: last_outside_map=%s (expect Route6) exit->%s (expect Route6) PASS=%s" % [
		lom_ok, center_label, lom_ok and upath_ok])
	print("[exitwarptest] PASS=%s" % (re_ok and lom_ok and upath_ok))
	get_tree().quit()


func _titlemenushot() -> void:
	await get_tree().process_frame
	_on_title_started()                              # show the CONTINUE / NEW GAME menu
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_titlemenu.png")
	get_tree().quit()


func _titletest() -> void:
	await get_tree().process_frame
	DirAccess.open("user://").remove(SAVE_PATH.get_file())     # start with no save
	_show_title()
	var shown: bool = (modal == title and title.visible)
	title._mon_idx = 0
	title._load_mon()
	print("[titletest] introbattle length = %.2fs" % title._battle_dur)
	for shot in [["copyright", "copyright", 1.0], ["gf_star", "gamefreak", 0.6], ["gf_logo", "gamefreak", 2.0],
			["fight_in", "battle", 0.05], ["fight_slash", "battle", 0.55], ["fight_lunge", "battle", 0.95],
			["title_slide", "title", 0.15], ["title", "title", 1.5], ["title_out", "title", 1.95]]:
		title.phase = str(shot[1])
		title.t = float(shot[2]) * (title._battle_dur if str(shot[1]) == "battle" else 1.0)
		title._mon_timer = title.t                                 # cycle position for the mon slide
		title.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://title_%s.png" % str(shot[0]))
	_on_title_started()
	var no_save_menu: Array = (menu.items as Array).duplicate()
	_on_menu_chosen(0)                                         # NEW GAME
	print("[titletest] no-save: title_shown=%s menu=%s -> map=%s" % [shown, str(no_save_menu), center_label])
	respawn_map = "CeruleanPokecenter"
	save_game()
	_show_title()
	_on_title_started()
	var save_menu: Array = (menu.items as Array).duplicate()
	respawn_map = "PalletTown"                                 # clobber; CONTINUE should restore it
	_on_menu_chosen(0)                                         # CONTINUE
	print("[titletest] with-save: menu=%s -> map=%s respawn=%s (expect CeruleanPokecenter)" % [
		str(save_menu), center_label, respawn_map])
	DirAccess.open("user://").remove(SAVE_PATH.get_file())
	get_tree().quit()


func party_hp_list() -> Array:
	var a := []
	for m in player_party:
		a.append("%s/%d" % [m["name"], m["hp"]])
	return a


func _signtest() -> void:
	await get_tree().process_frame
	player.place(Vector2i(7, 10))   # stand below the Pallet Town sign at (7,9)
	player.facing = 1               # face UP
	await _press_accept()           # open via a real keypress
	var n_pages: int = textbox.pages.size()
	await get_tree().create_timer(1.0).timeout   # let page 1 type out
	get_viewport().get_texture().get_image().save_png("res://signtest.png")
	var presses := 0
	while (modal != null) and presses < 12:
		await _press_accept()
		presses += 1
	print("[signtest] pages=%d presses_to_close=%d active=%s (expect false, NOT looping)" % [n_pages, presses, (modal != null)])
	# A press after close should be free to move again (not stuck).
	print("[signtest] player can act now: (modal != null)=%s" % (modal != null))
	get_tree().quit()
