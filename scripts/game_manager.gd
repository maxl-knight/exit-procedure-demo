extends Node

## Autoload that owns the whole run: difficulty, realm progression, the score
## multiplier and the Hell unlock.

signal stats_changed

## Combat feedback the whole codebase can raise without needing a HUD
## reference: a small crosshair flash on connect, and the points pop when the
## tally actually moves.
signal hit_connected(color: Color)
signal score_gained(amount: float)

## Fired when a run's score is written to the lifetime record.
signal score_recorded(is_new_best: bool)

## Fired the moment a super is spent, with the move's name and which tier of
## the bar paid for it (1 = 100%, 2 = 200%). The HUD turns it into a banner:
## both tiers fire on the same key and the difference used to be invisible.
signal super_fired(move_name: String, tier: int)

const SAVE_PATH := "user://save.cfg"

## Rooms per realm, and the room index of The Core's arena.
const REALM_LENGTH := 20
const GAME_END_ROOM := REALM_LENGTH * 3

enum Difficulty { EASY, NORMAL, HARD, HELL }
enum CharacterType { BRAWLER, SWORDSMAN, ICE_MAGE }
enum Realm { HELL, EARTH, HEAVEN }

const DIFFICULTY_NAMES := ["Easy", "Normal", "Hard", "Hell"]
const CHARACTER_NAMES := ["Brawler", "Swordsman", "Ice Mage"]
const REALM_NAMES := ["RECONSTRUCTION WING", "ADAPTATION FIELD", "CORE PERIMETER"]

const DIFFICULTY_SETTINGS := {
	Difficulty.EASY: {
		"enemy_bonus": -1, "hp_mult": 0.7, "dmg_mult": 0.6, "speed_mult": 0.9,
		"hp_bonus": 50.0, "cooldown_mult": 0.8, "score_mult": 1.0,
		"desc": "+50 health and 20% shorter cooldowns. A relaxed warm-up.",
	},
	Difficulty.NORMAL: {
		"enemy_bonus": 0, "hp_mult": 1.0, "dmg_mult": 1.0, "speed_mult": 1.0,
		"hp_bonus": 0.0, "cooldown_mult": 1.0, "score_mult": 1.0,
		"desc": "The intended experience. Balanced fights.",
	},
	Difficulty.HARD: {
		"enemy_bonus": 2, "hp_mult": 1.9, "dmg_mult": 1.4, "speed_mult": 1.15,
		"hp_bonus": -20.0, "cooldown_mult": 1.3, "score_mult": 1.7,
		"desc": "Tougher enemies, 30% longer cooldowns, -20 health.",
	},
	Difficulty.HELL: {
		"enemy_bonus": 5, "hp_mult": 2.6, "dmg_mult": 1.9, "speed_mult": 1.3,
		"hp_bonus": -50.0, "cooldown_mult": 1.4, "score_mult": 3.5,
		"desc": "40% longer cooldowns, -50 health, 3.5x score.",
	},
}

## Par time for a "quick clear". Rooms grew from 22 to 36 units, so this
## grew with them: 26s was tuned for the old, much smaller arena.
const PAR_TIME := 40.0

## Kill streak: consecutive kills without taking a hit, worth +5% each up
## to +50%. Losing health drops you straight back to zero.
const STREAK_CAP := 10
const STREAK_BONUS := 0.05

var difficulty: int = Difficulty.NORMAL
var character: int = CharacterType.BRAWLER
var kills := 0
var rooms_cleared := 0
var score_points := 0.0
var hell_unlocked := false
var announce_unlock := false
var game_beaten := false
var endless := false
## Opened once you choose TAKE CONTROL behind The Core. Permanent.
var endless_admin := false

## Live inputs for the score multiplier - reset whenever a room starts.
var room_damage := 0.0
var room_time := 0.0

## The score multiplier's "clean" factor is measured against whatever body you
## are actually wearing. The player pushes its real maximum in on spawn, so an
## Ice Mage (85 HP) and a Brawler (120 HP + Reinforced Frame) are judged by
## different standards instead of both being measured against a hard-coded 100.
var run_max_hp := 100.0

## Ledger Bias (+15% score per stack) feeds in here; the player owns the stacks.
var score_bonus := 0.0

## Run statistics, wiped by start_run() and shown on both end screens.
var streak := 0
var best_streak := 0
var damage_dealt := 0.0
var damage_taken_run := 0.0
var elites_killed := 0

## Lifetime high score, kept in the save so a good run is remembered.
var best_score := 0

## What the last room clear paid out. Quoted by the clear toast.
var last_room_gain := 0.0

## Accessibility / feel options. Written to [settings] so they survive runs.
var opt_sensitivity := 1.0
var opt_shake := true
var opt_hitstop := true
var opt_reticle := true

## Sound volume, as a percentage. Nobody thinks in decibels.
var opt_volume := 100

## Windowed or fullscreen, remembered between launches so a player who picks
## one does not have to pick it again every session.
var opt_fullscreen := false

## True when the OS turned the last window-mode change down. A game embedded in
## the Godot editor cannot leave windowed mode at all, so the press has to be
## answered with something instead of leaving the player mashing the key.
var window_mode_refused := false

# ------------------------------------------------------------ meta bank -----
## Memory chips: the currency the hub's Upgrade screen sells. Every run's
## score is converted into chips once, when the run ends, and chips buy
## permanent upgrades - so the more runs you play, the easier the next one
## gets. Stored in the same save file as everything else.

## Score per chip. Low enough that the first upgrade lands inside the very
## first run, high enough that a chip is still worth having.
const CHIP_DIVISOR := 250.0

## Level N -> N+1 costs CHIP_BASE_COST * (N + 1): 25, 50, 75 ... A full
## seven-stat build is a long tail, but the first handful of levels are
## yours inside an afternoon.
const CHIP_BASE_COST := 25
const CHIP_MAX_LEVEL := 10

## The permanent upgrades, in the order the shop lists them. `pct` is the
## per-level change to the stat, in percent - negative for the two stats
## where less is better (attack cooldown, damage taken). The gameplay side
## reads these through upg_mult(); everything else here is shop furniture.
const UPGRADES := {
	"heal": {
		"name": "REGENERATION", "stat": "HEALING", "pct": 15.0,
		"desc": "Every heal - the E ability, the bays, the mites - restores more.",
	},
	"speed": {
		"name": "SERVO MUSCLE", "stat": "MOVE SPEED", "pct": 4.0,
		"desc": "You cross the floor faster, and dash out further.",
	},
	"atk_speed": {
		"name": "CADENCE", "stat": "ATTACK COOLDOWN", "pct": -4.0,
		"desc": "Swings and frost bolts come back sooner.",
	},
	"power": {
		"name": "STRIKE FRAME", "stat": "ATTACK POWER", "pct": 5.0,
		"desc": "Every hit you land does more.",
	},
	"defense": {
		"name": "PLATING", "stat": "DAMAGE TAKEN", "pct": -3.0,
		"desc": "What does reach you does less of it.",
	},
	"super_rate": {
		"name": "CHARGE CELL", "stat": "SUPER BUILD-UP", "pct": 8.0,
		"desc": "The super bar fills faster off damage dealt and taken.",
	},
	"super_dmg": {
		"name": "OVERCHARGE", "stat": "SUPER DAMAGE", "pct": 6.0,
		"desc": "Supers, desperation moves and the 200% tier hit harder.",
	},
}

var chips := 0
var upgrade_levels := {}
## Score already converted to chips this run. A victory followed by a
## descent keeps playing, so the bank pays the difference rather than
## paying the whole run twice.
var chips_claimed_score := 0
## What the last payout was, so both end screens can say it out loud.
var last_chip_gain := 0


func _ready() -> void:
	_setup_input()
	_load_unlock()
	_load_settings()
	_apply_window_mode()


## F11 and Alt+Enter toggle the window from anywhere, menu or fight. Bound here
## rather than in project.godot because the whole input map is built at runtime
## and there is no reason for this one action to live in a different place.
## Both the logical and the physical key are read, so the shortcut survives a
## layout where the two disagree.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		var is_f11 := k.keycode == KEY_F11 or k.physical_keycode == KEY_F11
		var is_enter := k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER
		if is_f11 or (is_enter and k.alt_pressed):
			toggle_fullscreen()
			get_viewport().set_input_as_handled()


func toggle_fullscreen() -> void:
	set_fullscreen(not opt_fullscreen)
	if window_mode_refused:
		# The press landed; the window itself is what could not move.
		Sfx.play("ui_error")


## Flips the actual window and writes the choice back to the save.
func set_fullscreen(on: bool) -> void:
	opt_fullscreen = on
	_apply_window_mode()
	# Only a mode the window really took is worth writing down - a preference
	# the OS refused would otherwise come back and be asked for at every launch.
	if opt_fullscreen == on:
		save_settings()


func _apply_window_mode() -> void:
	window_mode_refused = false
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if opt_fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() == want:
		return
	DisplayServer.window_set_mode(want)
	# Believe the window, not the request: an embedded editor window turns the
	# change down and hands the old mode straight back, which would otherwise
	# leave the settings box claiming a fullscreen the player does not have.
	if DisplayServer.window_get_mode() != want:
		window_mode_refused = true
		opt_fullscreen = DisplayServer.window_get_mode() \
			== DisplayServer.WINDOW_MODE_FULLSCREEN


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("settings", "sensitivity", opt_sensitivity)
	cfg.set_value("settings", "shake", opt_shake)
	cfg.set_value("settings", "hitstop", opt_hitstop)
	cfg.set_value("settings", "reticle", opt_reticle)
	cfg.set_value("settings", "volume", opt_volume)
	cfg.set_value("settings", "fullscreen", opt_fullscreen)
	cfg.save(SAVE_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	opt_sensitivity = clampf(float(cfg.get_value("settings", "sensitivity", 1.0)), 0.25, 3.0)
	opt_shake = bool(cfg.get_value("settings", "shake", true))
	opt_hitstop = bool(cfg.get_value("settings", "hitstop", true))
	opt_reticle = bool(cfg.get_value("settings", "reticle", true))
	opt_volume = clampi(int(cfg.get_value("settings", "volume", 100)), 0, 100)
	opt_fullscreen = bool(cfg.get_value("settings", "fullscreen", false))


## Commits this run's score to the lifetime record. Returns true on a new best.
## Both end screens come through here exactly once per run, and it already
## owns the save file, so the chip bank lives here too.
func commit_score() -> bool:
	bank_run_score()
	if score() <= best_score:
		score_recorded.emit(false)
		return false
	best_score = score()
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("record", "best_score", best_score)
	cfg.save(SAVE_PATH)
	score_recorded.emit(true)
	return true


# ------------------------------------------------------------ meta bank -----

## What a score is worth in chips. Integer by design: the last 249 points
## of a score are not worth a line of UI about them.
func chips_for(score_value: int) -> int:
	return maxi(0, int(floor(float(score_value) / CHIP_DIVISOR)))


## Pays out whatever this run's score has not paid out yet. Only ever the
## difference, so playing on past a victory cannot bank the same points
## twice. Returns what it just paid.
func bank_run_score() -> int:
	var worth := chips_for(score())
	last_chip_gain = maxi(0, worth - chips_claimed_score)
	# Never walk the baseline backwards: a score sitting below what has
	# already been paid must not hand the difference out a second time.
	chips_claimed_score = maxi(chips_claimed_score, worth)
	if last_chip_gain > 0:
		chips += last_chip_gain
		save_meta()
	return last_chip_gain


func upg_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


func upg_cost(id: String) -> int:
	return CHIP_BASE_COST * (upg_level(id) + 1)


## The multiplier a gameplay stat should be carrying right now. Kept in one
## place so player.gd can read it the same way it reads a buff.
func upg_mult(id: String) -> float:
	if not UPGRADES.has(id):
		return 1.0
	return 1.0 + float(UPGRADES[id]["pct"]) / 100.0 * float(upg_level(id))


func buy_upgrade(id: String) -> bool:
	if not UPGRADES.has(id):
		return false
	var level := upg_level(id)
	if level >= CHIP_MAX_LEVEL:
		return false
	var cost := CHIP_BASE_COST * (level + 1)
	if chips < cost:
		return false
	chips -= cost
	upgrade_levels[id] = level + 1
	save_meta()
	return true


## Writes only the meta section. Loading first keeps the record, the story
## and the settings this same file carries intact.
func save_meta() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("meta", "chips", chips)
	cfg.set_value("meta", "upgrades", upgrade_levels)
	cfg.save(SAVE_PATH)


func _setup_input() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("ability_1", KEY_Q)
	_add_key_action("ability_2", KEY_SHIFT)
	_add_key_action("ability_3", KEY_E)
	_add_key_action("pause", KEY_ESCAPE)


func _add_key_action(action: String, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func start_run(d: int, c: int) -> void:
	difficulty = d
	character = c
	kills = 0
	rooms_cleared = 0
	score_points = 0.0
	announce_unlock = false
	game_beaten = false
	endless = false
	streak = 0
	best_streak = 0
	damage_dealt = 0.0
	damage_taken_run = 0.0
	elites_killed = 0
	run_max_hp = 100.0
	score_bonus = 0.0
	last_room_gain = 0.0
	# Fresh run, fresh bank: the next payout starts from zero score.
	chips_claimed_score = 0
	last_chip_gain = 0
	reset_room_stats()
	ArenaMemory.start_run(c)
	stats_changed.emit()


func reset_room_stats() -> void:
	room_damage = 0.0
	room_time = 0.0


# ----------------------------------------------------------- difficulty -----

func settings() -> Dictionary:
	return DIFFICULTY_SETTINGS[difficulty]


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


func character_name() -> String:
	return CHARACTER_NAMES[character]


func hp_bonus() -> float:
	return float(settings()["hp_bonus"])


func cooldown_mult() -> float:
	return float(settings()["cooldown_mult"])


func base_score_mult() -> float:
	return float(settings()["score_mult"])


# ------------------------------------------------------------- realms -------

func is_boss_room(index: int) -> bool:
	return index > 0 and index % GAME_END_ROOM == 0


func realm_of_room(index: int) -> int:
	if is_boss_room(index):
		return Realm.HEAVEN
	return int(floor(float(index) / float(REALM_LENGTH))) % 3


func realm_name(index: int) -> String:
	return REALM_NAMES[realm_of_room(index)]


# ---------------------------------------------------------------- score -----

## Damage taken and speed inside the current room both push this around.
func multiplier() -> float:
	var max_hp := maxf(run_max_hp, 10.0)
	var dmg_factor := 1.0 + 2.0 * clampf(1.0 - room_damage / max_hp, 0.0, 1.0)
	var speed_factor := 1.0 + 1.5 * clampf((PAR_TIME - room_time) / PAR_TIME, 0.0, 1.0)
	var base := base_score_mult() * (1.0 + score_bonus)
	return clampf(base * dmg_factor * speed_factor, 0.5, 15.0)


## Awards a kill. `worth_score` is false for the Core's clone: that fight is a
## gate, not loot, and paying out for it inflated every score on file.
## Returns the points granted so the HUD can show them.
func add_kill(worth_score: bool = true) -> float:
	kills += 1
	streak += 1
	best_streak = maxi(best_streak, streak)
	var gained := 0.0
	if worth_score:
		gained = 100.0 * multiplier() * streak_mult()
		score_points += gained
		score_gained.emit(gained)
	stats_changed.emit()
	return gained


## The streak's cut of a kill: 1.0 on the first, +5% per clean kill after.
func streak_mult() -> float:
	if streak <= 1:
		return 1.0
	return 1.0 + STREAK_BONUS * float(mini(streak - 1, STREAK_CAP))


## Taking any damage - trap, arrow or punch - resets it to zero.
func break_streak() -> void:
	streak = 0


## One line of run statistics shared by the death and victory screens.
func combat_summary() -> String:
	return "damage dealt %d      damage taken %d      streak x%d      elites %d" % [
		int(round(damage_dealt)), int(round(damage_taken_run)),
		best_streak, elites_killed]


## Awards a room clear. Returns the points so the HUD can flash them.
func add_room() -> float:
	rooms_cleared += 1
	var gained := 250.0 * multiplier()
	score_points += gained
	score_gained.emit(gained)
	# Kept so the clear toast can quote what the room was actually worth.
	last_room_gain = gained
	stats_changed.emit()
	return gained


func score() -> int:
	return maxi(0, int(round(score_points)))


## Called the moment The Core falls. Only a Hard clear opens Hell.
func beat_game() -> bool:
	game_beaten = true
	var unlocked := false
	if difficulty == Difficulty.HARD and not hell_unlocked:
		hell_unlocked = true
		announce_unlock = true
		_save_unlock()
		unlocked = true
	stats_changed.emit()
	return unlocked


## Writing an ending into the record. Only TAKE CONTROL opens Endless
## Administration, and it stays open across every future reconstruction.
func apply_ending(id: String) -> void:
	ArenaMemory.note_ending(id)
	if id == "control" and not endless_admin:
		endless_admin = true
		_save_unlock()
	stats_changed.emit()


# ----------------------------------------------------------------- save -----

func _load_unlock() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		hell_unlocked = bool(cfg.get_value("unlock", "hell",
			bool(cfg.get_value("unlock", "secret", false))))
		endless_admin = bool(cfg.get_value("unlock", "endless_admin", false))
		best_score = maxi(0, int(cfg.get_value("record", "best_score", 0)))
		chips = maxi(0, int(cfg.get_value("meta", "chips", 0)))
		var levels: Variant = cfg.get_value("meta", "upgrades", {})
		if levels is Dictionary:
			upgrade_levels = levels


func _save_unlock() -> void:
	var cfg := ConfigFile.new()
	# Load first: ArenaMemory stores the story in this same file.
	cfg.load(SAVE_PATH)
	cfg.set_value("unlock", "hell", hell_unlocked)
	cfg.set_value("unlock", "endless_admin", endless_admin)
	cfg.save(SAVE_PATH)
