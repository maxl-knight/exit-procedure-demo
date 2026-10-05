extends Node

## The Arena's memory - the story system's brain. Two layers:
##
##  * RUN counters: what you are doing right now. The Arena watches these,
##    comments on them, and (later) adapts rooms to them.
##  * STORY state: the lifetime record across every reconstruction, persisted
##    in user://save.cfg under [story] so death never resets the narrative.
##
## When the Arena decides to speak it emits `voice`; the game scene relays it
## to the HUD subtitle bar. Lines fire at thresholds, never at random.

signal voice(text: String)

const SAVE_PATH := "user://save.cfg"

## Death-cause buckets. Every damage source tags its hits with one of these.
const CAUSE_MELEE := "melee"
const CAUSE_RANGED := "ranged"
const CAUSE_TRAP := "trap"
const CAUSE_CLONE := "clone"
const CAUSE_UNKNOWN := "unknown"

const KNOWN_CAUSES: Array[String] = [
	CAUSE_MELEE, CAUSE_RANGED, CAUSE_TRAP, CAUSE_CLONE, CAUSE_UNKNOWN,
]

## The reactions the Arena ships with. Clinical, lowercase after the
## period - the Arena is a system, not a person (yet).
const LINES := {
	"heal_first": "ARENA: Reconstruction inputs observed.",
	"dash_rhythm": "ARENA: Movement pattern recorded.",
	"super_hoard": "ARENA: Power retained. Unusual.",
	"super_spent": "ARENA: Power spent. The account is now in deficit.",
	"record": "ARENA: New performance ceiling logged.",
	"score_record": "ARENA: That is the highest tally on file. It will not hold.",
	"adapt": "ARENA: Simulation adapting.",
	"boss": "ARENA: subject indexed. no prior record. begin.",
	"final_wing": "ARENA: last boundary. the Core is one door forward.",
	"orb": "ARENA: the elites are leaving you things now. that is new.",
}

## Said when you clear a realm wall (rooms 20 and 40) - the boundary between
## one wing and the next. Keyed by the realm you have just walked into.
const WING_LINES := {
	1: "ARENA: boundary crossed. the Adaptation Field is already recalculating.",
	2: "ARENA: boundary crossed. the Core Perimeter does not lose subjects.",
}

## Said the first time you see an adaptive test *of a given kind*, across
## every reconstruction ever. Keyed by habit: dash / heal / melee / ranged.
const FIRST_SIGHT := {
	"dash": "ARENA: you run before you think. we will build around that.",
	"heal": "ARENA: reconstruction is a crutch. it is being measured too.",
	"melee": "ARENA: you close distance out of habit. the field notices.",
	"ranged": "ARENA: you would rather not be touched. noted, and answered.",
}

## The Core's greeting is the one line that reads your whole history: it is
## chosen from how many times you have died across every reconstruction.
## [minimum deaths, line]
const BOSS_LINES := [
	[0, "ARENA: subject indexed. no prior record. begin."],
	[1, "THE CORE: reconstruction finished in 3.1 seconds. you came back faster than expected."],
	[3, "THE CORE: three shapes of you on file. the third one still screams."],
	[6, "THE CORE: pattern locked. you will fall exactly where you fell before."],
	[10, "THE CORE: we no longer need you to try. your moves are already ours."],
	[15, "THE CORE: you keep arriving with the same shoulders. we have stopped correcting it."],
	[25, "THE CORE: every version of you that opened this door is indexed under one name."],
	[40, "THE CORE: we have run this fight without you and it is identical."],
]

## Memory rooms dig up one fragment each, in order, forever. The cursor
## persists so the log keeps growing across reconstructions.
const FRAGMENTS: Array[String] = [
	"ARENA: fragment 001 - a subject once cleared this room without a weapon. logged as anomaly.",
	"ARENA: fragment 014 - reconstruction bill for your last death: 3.2 minutes of compute.",
	"ARENA: fragment 027 - the archers were copied from a subject who would not stop retreating.",
	"ARENA: fragment 039 - someone before you counted the ceiling tiles. 614. correct.",
	"ARENA: fragment 052 - this floor has been rebuilt 8,411 times. it does not remember you yet.",
	"ARENA: fragment 066 - a previous subject stacked every crate against the door. delay: 11 seconds.",
	"ARENA: fragment 078 - the first subject called this place home. we kept the phrase.",
	"ARENA: fragment 090 - your pattern is converging with a subject we dismantled long ago.",
	"ARENA: fragment 103 - the traps were tuned against someone who never stopped walking forward.",
	"ARENA: fragment 117 - two subjects held hands through the Adaptation Field. both were logged as one.",
	"ARENA: fragment 122 - we removed the ceiling once to see if anyone looked up. one did.",
	"ARENA: fragment 138 - the Core keeps a chair for a subject who never sat in it.",
	"ARENA: fragment 144 - a subject apologised to an elite before the kill. the elite did not record it.",
	"ARENA: fragment 159 - the doors are not locked. no subject has ever walked to the far wall.",
	"ARENA: fragment 166 - this fragment was written by the floor. it has opinions.",
	"ARENA: fragment 180 - you are the longest continuous record here. take that however you like.",
]

# ------------------------------------------------------------- run layer ----

var dashes := 0
var heals := 0
var melee_attacks := 0
var bolt_attacks := 0
var supers_used := 0
var damage_taken := 0.0
var death_cause := CAUSE_UNKNOWN

## True once this run has pushed the lifetime record.
var record_broken := false

var _said := {}
var _run_character := 0

# ----------------------------------------------------------- story layer ----

var runs := 0
var deaths := 0
var deaths_by_cause := {}
var char_runs := {}
## Deaths, bucketed by which body you were wearing. Persisted so the hub can
## show the record per warrior.
var deaths_by_char := {}
var highest_room := 0
var bosses_beaten := 0
var adaptive_seen := {}
var fragments_seen := 0
## Recovery motes you have ever taken. The first one is a story beat.
var orbs_seen := 0
## Which of the three doors you last walked through: "", "escape", "destroy"
## or "control". The record keeps it across reconstructions.
var ending := ""


func _ready() -> void:
	_load()


## Called by GameManager the moment a run starts: wipe the run counters,
## count the run and the character choice, persist immediately.
func start_run(character: int) -> void:
	runs += 1
	_run_character = character
	char_runs[character] = int(char_runs.get(character, 0)) + 1
	dashes = 0
	heals = 0
	melee_attacks = 0
	bolt_attacks = 0
	supers_used = 0
	damage_taken = 0.0
	death_cause = CAUSE_UNKNOWN
	record_broken = false
	_said.clear()
	_save()


# ------------------------------------------------------------- run notes ----

func note_dash() -> void:
	dashes += 1
	if dashes == 10:
		speak("dash_rhythm")


func note_heal() -> void:
	heals += 1
	if heals == 1:
		speak("heal_first")


func note_attack(kind: String) -> void:
	if kind == "bolt":
		bolt_attacks += 1
	else:
		melee_attacks += 1


func note_super() -> void:
	supers_used += 1
	# Spending the bar at all is a decision the Arena wants on record.
	if supers_used == 1:
		speak("super_spent")


func note_super_held() -> void:
	# Hoarding the bar past 190% is a play style the Arena finds notable.
	speak("super_hoard")


func note_damage(amount: float) -> void:
	damage_taken += amount


## The dominant behavior this run - used by the room schedule to pick which
## adaptive room tests you next. "" means not enough data yet.
func flagged_behavior() -> String:
	if heals >= 2:
		return "heal"
	if dashes >= 10:
		return "dash"
	if bolt_attacks >= 5 and bolt_attacks > melee_attacks:
		return "ranged"
	if melee_attacks >= 10:
		return "melee"
	return ""


# ----------------------------------------------------------- story notes ----

## `cleared` is how many rooms this run has cleared (1-based record).
func note_room(cleared: int) -> void:
	if cleared > highest_room:
		highest_room = cleared
		record_broken = true
		speak("record")
		_save()


func note_boss() -> void:
	bosses_beaten += 1
	_save()


func note_ending(id: String) -> void:
	ending = id
	_save()


func note_adaptive(kind: String) -> void:
	adaptive_seen[kind] = int(adaptive_seen.get(kind, 0)) + 1
	# Lifetime memory: the first time an adaptive test of this kind ever
	# appears across every reconstruction, the Arena says so. This is the
	# one place adaptive_seen is read back out.
	if int(adaptive_seen.get(kind, 0)) == 1 and FIRST_SIGHT.has(kind):
		voice.emit(str(FIRST_SIGHT[kind]))
	_save()


## Total adaptive tests of any kind ever survived.
func adaptive_total() -> int:
	var n := 0
	for key in adaptive_seen:
		n += int(adaptive_seen[key])
	return n


## The Core's door: the last boundary, said once per run when room 60 opens.
func speak_final_wing() -> void:
	speak("final_wing")


## A new lifetime high score - said once, after the run that set it.
func speak_score_record() -> void:
	speak("score_record")


## The first recovery mote you have ever taken. Elites leaving things behind
## is new behaviour, and the record notices new behaviour.
func note_orb() -> void:
	orbs_seen += 1
	if orbs_seen == 1:
		speak("orb")
	_save()


func note_death(cause: String) -> void:
	death_cause = cause if KNOWN_CAUSES.has(cause) else CAUSE_UNKNOWN
	deaths += 1
	deaths_by_cause[death_cause] = int(deaths_by_cause.get(death_cause, 0)) + 1
	deaths_by_char[_run_character] = int(deaths_by_char.get(_run_character, 0)) + 1
	_save()


## Emit a one-shot reaction. Each line fires at most once per run.
func speak(id: String) -> void:
	if _said.has(id) or not LINES.has(id):
		return
	_said[id] = true
	voice.emit(str(LINES[id]))


## Crossing into a new wing: the Arena notes the boundary, once per wing.
func speak_wing(realm: int) -> void:
	if not WING_LINES.has(realm):
		return
	var key := "wing_%d" % realm
	if _said.has(key):
		return
	_said[key] = true
	voice.emit(str(WING_LINES[realm]))


# --------------------------------------------------------- memory rooms -----

## The next lore fragment for a memory room. Never deduped: each memory
## room speaks even if fragments wrap around the pool. The cursor persists
## so the log grows across runs.
func next_fragment() -> String:
	var line := str(FRAGMENTS[fragments_seen % FRAGMENTS.size()])
	fragments_seen += 1
	_save()
	return line


## Memory room entry: show the fragment in the voice bar.
func speak_fragment() -> void:
	voice.emit(next_fragment())


# ------------------------------------------------------------ boss talk -----

## The line The Core opens with, picked from the highest threshold you have
## cleared. Returns the plain "boss" reaction when you have never died.
func boss_line() -> String:
	var line := str(LINES["boss"])
	for row in BOSS_LINES:
		if deaths >= int(row[0]):
			line = str(row[1])
	return line


## Called the moment the Core's chamber opens. Once per run - it greets you,
## then gets back to work.
func speak_boss() -> void:
	if _said.has("boss_greeted"):
		return
	_said["boss_greeted"] = true
	voice.emit(boss_line())


# -------------------------------------------------------------- hub talk -----

## The line the main menu opens with. Chosen from the record, never random -
## this is the Arena noticing you before you press play.
##
## The pool rotates once per reconstruction instead of short-circuiting on the
## first ending written: finishing a run used to permanently silence every
## progression line underneath it.
func menu_line() -> String:
	if runs <= 0:
		return "ARENA: no reconstruction on file. the chamber is cold."
	var pool: Array[String] = []
	match ending:
		"escape":
			pool.append("ARENA: subject walked out. the doors stay open.")
		"destroy":
			pool.append("ARENA: record destroyed. re-indexing from nothing.")
		"control":
			pool.append("ARENA: chair occupied. the Arena administers itself.")
	if bosses_beaten > 0:
		pool.append("ARENA: the Core has been broken %d time%s. it is expecting you."
			% [bosses_beaten, "" if bosses_beaten == 1 else "s"])
	if highest_room >= 20:
		pool.append("ARENA: you reached the Adaptation Field. i have notes on you.")
	elif highest_room >= 5:
		pool.append("ARENA: you reached room %d. i have notes on you." % highest_room)
	var body := menu_body_line()
	if body != "":
		pool.append(body)
	if adaptive_total() > 0:
		pool.append("ARENA: %d adaptive test%s survived. you are still predictable."
			% [adaptive_total(), "" if adaptive_total() == 1 else "s"])
	pool.append("ARENA: %d reconstruction%s logged. your pattern is forming."
		% [runs, "" if runs == 1 else "s"])
	pool.append("ARENA: %d failures on file. begin when ready." % deaths)
	return str(pool[(runs - 1) % pool.size()])


## A line about whichever body you spend the most time in. "" when the record
## has nothing to say yet.
func menu_body_line() -> String:
	var best_id := 0
	var best_n := 0
	for key in char_runs:
		if int(char_runs[key]) > best_n:
			best_n = int(char_runs[key])
			best_id = int(key)
	if best_n <= 0:
		return ""
	var name = GameManager.CHARACTER_NAMES[best_id] \
		if best_id >= 0 and best_id < GameManager.CHARACTER_NAMES.size() else "the body"
	return "ARENA: the %s has been worn %d time%s. it remembers the weight." \
		% [name, best_n, "" if best_n == 1 else "s"]


## The Core's projection panel text - a small piece of the boss in the menu.
func menu_projection() -> String:
	if bosses_beaten <= 0:
		return "THE CORE: projection unavailable.\nsubject has not arrived."
	if ending == "control":
		return "THE CORE: projection archived.\nthe chair is occupied. by you."
	if ending == "destroy":
		return "THE CORE: projection corrupt.\nfile rebuilt from nothing."
	if ending == "escape":
		return "THE CORE: projection tracking.\nthe doors did not close."
	return "THE CORE: projection stable.\nyou broke it %d time%s." \
		% [bosses_beaten, "" if bosses_beaten == 1 else "s"]


# ----------------------------------------------------------- death text -----

## The short reconstruction line shown under YOU DIED. Chosen from the bucket
## that actually killed you - never unique for its own sake.
func death_line() -> String:
	match death_cause:
		CAUSE_MELEE:
			return "Failure caused by repeated frontal engagement."
		CAUSE_RANGED:
			return "Failure caused by static positioning."
		CAUSE_TRAP:
			return "Failure caused by ignored hazard cycles."
		CAUSE_CLONE:
			return "The mirror read your pattern first."
	return "Reconstruction approved."


## Only at thresholds: the same cause logged three or more times.
func pattern_repeats() -> bool:
	return int(deaths_by_cause.get(death_cause, 0)) >= 3


func pattern_line() -> String:
	return "Pattern repeating - %d logged failures of this kind." \
		% int(deaths_by_cause.get(death_cause, 0))


## The one thing to change next - keyed by how you actually died, so the run
## that just ended has somewhere to point instead of only judging you.
func death_tip() -> String:
	return str(Content.DEATH_TIPS.get(death_cause, Content.DEATH_TIPS["unknown"]))


## Lifetime failures, one line per cause, only the ones you have actually
## collected. Shown on the death screen as the record it is.
func cause_summary() -> Array:
	var out: Array = []
	for cause in KNOWN_CAUSES:
		var n := int(deaths_by_cause.get(cause, 0))
		if n > 0:
			out.append("%-10s %d" % [cause.to_upper(), n])
	return out


## Everything the log has actually dug up, in order. Powers the hub archive.
func fragment_log() -> Array:
	var out: Array = []
	var count := mini(fragments_seen, FRAGMENTS.size())
	for i in count:
		out.append(str(FRAGMENTS[i]))
	return out


## What the Arena observed, for the death screen.
func learned_lines() -> Array:
	var atk := "%d melee" % melee_attacks
	if bolt_attacks > 0:
		atk += "  /  %d frost" % bolt_attacks
	var out := [
		"MOVEMENT          %d dashes" % dashes,
		"RECONSTRUCTION    %d heal%s" % [heals, "" if heals == 1 else "s"],
		"ATTACK            %s" % atk,
		"SUPER             %d spent" % supers_used,
		"DAMAGE TAKEN      %d" % int(damage_taken),
	]
	if record_broken:
		out.append("RECORD            new ceiling - room %d" % highest_room)
	return out


# ----------------------------------------------------------------- save -----

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	runs = int(cfg.get_value("story", "runs", 0))
	deaths = int(cfg.get_value("story", "deaths", 0))
	deaths_by_cause = cfg.get_value("story", "deaths_by_cause", {})
	char_runs = cfg.get_value("story", "char_runs", {})
	deaths_by_char = cfg.get_value("story", "deaths_by_char", {})
	highest_room = int(cfg.get_value("story", "highest_room", 0))
	bosses_beaten = int(cfg.get_value("story", "bosses_beaten", 0))
	adaptive_seen = cfg.get_value("story", "adaptive_seen", {})
	fragments_seen = int(cfg.get_value("story", "fragments_seen", 0))
	orbs_seen = int(cfg.get_value("story", "orbs_seen", 0))
	ending = str(cfg.get_value("story", "ending", ""))


## Load-then-merge: the [unlock] section written by GameManager must survive.
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("story", "runs", runs)
	cfg.set_value("story", "deaths", deaths)
	cfg.set_value("story", "deaths_by_cause", deaths_by_cause)
	cfg.set_value("story", "char_runs", char_runs)
	cfg.set_value("story", "deaths_by_char", deaths_by_char)
	cfg.set_value("story", "highest_room", highest_room)
	cfg.set_value("story", "bosses_beaten", bosses_beaten)
	cfg.set_value("story", "adaptive_seen", adaptive_seen)
	cfg.set_value("story", "fragments_seen", fragments_seen)
	cfg.set_value("story", "orbs_seen", orbs_seen)
	cfg.set_value("story", "ending", ending)
	cfg.save(SAVE_PATH)
