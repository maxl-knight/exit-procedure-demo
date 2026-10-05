extends Node

## Every sound in Exit Procedure comes through here.
##
## Three things this gives the game that a pile of AudioStreamPlayer nodes do
## not:
##
##   * a fixed pool. A whirlwind can catch ten bodies on one frame, and sixteen
##     players is a budget while sixteen hundred is a stutter.
##   * per-frame de-duplication. Ten simultaneous impacts play ONE punch, because
##     ten copies of the same clip stacked together do not sound like ten hits,
##     they sound like distortion.
##   * distance falloff. A trap at the far end of a 36-unit room should be
##     quieter than the one under your feet.
##
## Streams load the first time a key is used and are cached afterwards, so
## booting straight into the menu costs nothing, and a file that has gone
## missing warns once instead of every frame.

## Owns its own bus so "volume" is one slider and music can be added later
## without touching it.
const BUS := "SFX"

const POOL_SIZE := 16
## Hard ceiling on how many clips may start in a single frame.
const MAX_PER_FRAME := 8
## ...and on how many of the SAME clip may start in one frame.
const MAX_SAME_KEY := 2
## A positioned sound fades to nothing over this distance, in metres.
const AUDIBLE := 34.0
const FAR_DB := -26.0
## Every play is nudged off pitch, so a punch thrown twice is never identical.
const JITTER := 0.05

## Looping room tone for the arena. Quiet enough to be air, not music.
const AMBIENT_DB := -24.0
const AMBIENCE_PATH := "res://sound effects/Environment/ambient_wind.wav"

## key -> one or more res:// paths. A key holding several paths picks one at
## random per play, which is what stops a horde from sounding like a loop.
const BANK := {
	# ------------------------------------------------------------- menus ----
	"ui_hover": ["res://sound effects/UI/sci_fi_hover.wav"],
	"ui_click": ["res://sound effects/UI/sci_fi_confirm.wav"],
	"ui_back": ["res://sound effects/UI/sci_fi_cancel.wav"],
	"ui_error": ["res://sound effects/UI/sci_fi_error.wav"],
	"ui_select": ["res://sound effects/UI/sci_fi_select.wav"],
	"ui_toggle_on": ["res://sound effects/UI/toggle_on.wav"],
	"ui_toggle_off": ["res://sound effects/UI/toggle_off.wav"],
	"ui_warn": ["res://sound effects/UI/synth_warning.wav"],
	"ui_done": ["res://sound effects/UI/synth_process_complete.wav"],

	# ------------------------------------------------- your own body -------
	"swing": ["res://sound effects/Combat and Gore/swipe.wav",
		"res://sound effects/Other/whoosh_1.wav"],
	"sword_swing": ["res://sound effects/Weapons/sword_light.wav"],
	"cast": ["res://sound effects/Environment/air_burst.wav",
		"res://sound effects/Other/whoosh_2.wav"],
	"step": ["res://sound effects/Footsteps/foley_footstep_concrete_1.wav",
		"res://sound effects/Footsteps/foley_footstep_concrete_2.wav",
		"res://sound effects/Footsteps/foley_footstep_concrete_3.wav",
		"res://sound effects/Footsteps/foley_footstep_concrete_4.wav"],
	"dash": ["res://sound effects/Other/whoosh_2.wav"],
	"heal": ["res://sound effects/Items/heart_collect.wav"],
	"super": ["res://sound effects/Musical Effects/synth_bass_positive_long.wav"],
	"desperation": ["res://sound effects/Musical Effects/horror_sting.wav"],
	"hurt": ["res://sound effects/Human/man_0.wav",
		"res://sound effects/Human/man_1.wav",
		"res://sound effects/Human/man_2.wav",
		"res://sound effects/Human/man_3.wav",
		"res://sound effects/Human/man_4.wav",
		"res://sound effects/Human/man_5.wav"],
	"player_die": ["res://sound effects/Musical Effects/synth_bass_negative_long.wav"],

	# --------------------------------------------- landing / taking hits ----
	"hit": ["res://sound effects/Combat and Gore/punch.wav",
		"res://sound effects/Combat and Gore/punch_2.wav",
		"res://sound effects/Combat and Gore/punch_3.wav"],
	"hit_sword": ["res://sound effects/Weapons/sword_slice.wav",
		"res://sound effects/Weapons/sword_clash.wav"],
	"hit_heavy": ["res://sound effects/Combat and Gore/crunch.wav",
		"res://sound effects/Weapons/harsh_thud.wav"],
	# The thud on the way in: a short crack instead of the old long boom, so a
	# hit on you reads instantly and never mushes into the punches you land.
	"hit_taken": ["res://sound effects/Combat and Gore/crunch_quick.wav",
		"res://sound effects/Combat and Gore/kick.wav"],
	"kill": ["res://sound effects/Combat and Gore/crunch_splat.wav",
		"res://sound effects/Combat and Gore/crunch_splat_2.wav"],
	"kill_elite": ["res://sound effects/Combat and Gore/bone_snap.wav",
		"res://sound effects/Materials/metal_clang.wav"],

	# ----------------------------------------------------------- enemies ----
	"enemy_swing": ["res://sound effects/Other/whoosh_1.wav"],
	"lunge": ["res://sound effects/Other/whoosh_1.wav"],
	"bow": ["res://sound effects/Other/elastic_twang.wav"],
	"shot": ["res://sound effects/Weapons/shot_muffled.wav"],
	"projectile_hit": ["res://sound effects/Materials/concrete_scrape.wav",
		"res://sound effects/Materials/metal_blunt_tap.wav"],
	"bolt_hit": ["res://sound effects/Materials/glass_ping_small.wav"],
	# Hitting something that is not open to being hit. The Core's guard, mostly.
	"shield": ["res://sound effects/Materials/metal_blunt_tap.wav",
		"res://sound effects/Weapons/sword_clash.wav"],

	# ------------------------------------------------------------ traps -----
	"trap_warn": ["res://sound effects/UI/synth_warning.wav"],
	"trap_fire": ["res://sound effects/Machines/hydraulic_up.wav"],
	"trap_retract": ["res://sound effects/Machines/hydraulic_down.wav"],

	# ---------------------------------------------------- rooms / run flow ---
	"door_open": ["res://sound effects/Machines/industrial_door_open.wav"],
	"door_close": ["res://sound effects/Machines/industrial_door_close.wav"],
	"room_start": ["res://sound effects/Musical Effects/synth_bass_level_start.wav"],
	"room_clear": ["res://sound effects/Musical Effects/synth_bass_chime_positive.wav"],
	"elite_spawn": ["res://sound effects/Musical Effects/horror_sting.wav"],
	"boss_spawn": ["res://sound effects/Musical Effects/horror_sting.wav"],
	"upgrade": ["res://sound effects/Items/item_equip.wav"],
	"orb": ["res://sound effects/Items/gem_collect.wav"],
	"curse": ["res://sound effects/Musical Effects/synth_bass_negative_quick.wav"],
	"milestone": ["res://sound effects/Musical Effects/synth_bass_level_complete.wav"],
	"victory": ["res://sound effects/Musical Effects/synth_bass_level_complete.wav"],
}

## Mix levels per key, in dB. Anything unlisted sits at 0. Keeping the mix in
## one table is what stops "tweak one sound" from becoming "re-record the game".
const GAIN := {
	"ui_hover": -14.0,
	"ui_click": -5.0,
	"ui_back": -5.0,
	"ui_select": -5.0,
	"ui_toggle_on": -7.0,
	"ui_toggle_off": -7.0,
	"ui_warn": -9.0,
	"ui_error": -6.0,
	"ui_done": -7.0,
	"step": -17.0,
	"trap_warn": -9.0,
	"trap_retract": -7.0,
	"door_open": -7.0,
	"door_close": -7.0,
	"room_start": -7.0,
	"room_clear": -5.0,
	"elite_spawn": -5.0,
	"boss_spawn": -5.0,
	"upgrade": -7.0,
	"orb": -7.0,
	"curse": -7.0,
	"milestone": -6.0,
	"victory": -4.0,
	"player_die": -5.0,
	"hurt": -6.0,
	"cast": -7.0,
	"dash": -6.0,
	"heal": -6.0,
	"bow": -5.0,
	"enemy_swing": -9.0,
	"lunge": -5.0,
	"projectile_hit": -9.0,
	"bolt_hit": -7.0,
	"shield": -6.0,
	"hit_taken": -3.5,
}

var _pool: Array[AudioStreamPlayer] = []
var _slot := 0
var _cache: Dictionary = {}
var _warned: Dictionary = {}
var _amb: AudioStreamPlayer = null
var _amb_on := false
var _frame: int = -1
var _frame_key: Dictionary = {}
var _frame_total := 0


func _ready() -> void:
	# The upgrade and ending screens pause the tree while they wait for an
	# answer, and they are exactly where the confirmation sound has to land.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_pool.append(p)
	_amb = AudioStreamPlayer.new()
	_amb.bus = BUS
	_amb.volume_db = AMBIENT_DB
	# Belt and braces: when the imported honours loop points the stream never
	# ends and this never fires; when it does not, the bed comes straight back
	# rather than the arena falling silent halfway through a run.
	_amb.finished.connect(_restart_ambience)
	add_child(_amb)
	apply_volume()


func _restart_ambience() -> void:
	if not _amb_on or _amb == null or not is_instance_valid(_amb):
		return
	if not _amb.playing:
		_amb.play()


## Plays a bank key. Positionless: for things that happen "here", like UI.
func play(key: String, extra_db := 0.0, pitch := 1.0, jitter := JITTER) -> void:
	_emit(key, extra_db, pitch, jitter, null)


## Plays a bank key at a world position, quieter the further it is from the
## camera. For anything with a place in the room.
func play_at(key: String, pos: Vector3, extra_db := 0.0, pitch := 1.0,
		jitter := JITTER) -> void:
	_emit(key, extra_db, pitch, jitter, pos)


func _emit(key: String, extra_db: float, pitch: float, jitter: float, pos) -> void:
	if _pool.is_empty():
		return
	var stream := _stream(key)
	if stream == null:
		return
	if _frame != Engine.get_process_frames():
		_frame = Engine.get_process_frames()
		_frame_key.clear()
		_frame_total = 0
	if _frame_total >= MAX_PER_FRAME:
		return
	var seen := int(_frame_key.get(key, 0))
	if seen >= MAX_SAME_KEY:
		return
	_frame_key[key] = seen + 1
	_frame_total += 1

	var p := _pool[_slot]
	_slot = (_slot + 1) % _pool.size()
	p.stream = stream
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-jitter, jitter)))
	p.volume_db = float(GAIN.get(key, 0.0)) + extra_db + _falloff(pos)
	p.play()


## Distance falloff in dB. No camera (menu, headless run) means no falloff,
## because a listener that does not exist cannot be too far away.
func _falloff(pos) -> float:
	if pos == null:
		return 0.0
	var vp := get_viewport()
	if vp == null:
		return 0.0
	var cam := vp.get_camera_3d()
	if cam == null:
		return 0.0
	var here: Vector3 = pos
	return lerpf(0.0, FAR_DB,
		clampf(cam.global_position.distance_to(here) / AUDIBLE, 0.0, 1.0))


func _stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key] as AudioStream
	if not BANK.has(key):
		_warn_once(key, "is not in the sound bank")
		return null
	var paths: Array = BANK[key]
	if paths.is_empty():
		_warn_once(key, "has an empty sound bank entry")
		return null
	var path := str(paths.pick_random())
	var loaded: Resource = load(path)
	if not (loaded is AudioStream):
		_warn_once(key, "points at a file that is not a stream: " + path)
		return null
	_cache[key] = loaded
	return loaded as AudioStream


func _warn_once(key: String, why: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("Sfx: '%s' %s" % [key, why])


# ------------------------------------------------------------- ambience ----

## The arena has air in it. The menu does not, so the bed follows the scene
## rather than running forever and quietly flattening every silence.
func set_ambience(on: bool) -> void:
	if _amb == null:
		return
	if not on:
		_amb_on = false
		_amb.stop()
		return
	if _amb.stream == null:
		var loaded: Resource = load(AMBIENCE_PATH)
		if not (loaded is AudioStreamWAV):
			_warn_once("ambience", "points at a file that is not a wav")
			return
		_amb.stream = _loop(loaded as AudioStreamWAV)
	_amb_on = true
	if not _amb.playing:
		_amb.play()


## Loops a wav for its whole length. Godot imports sound as one-shot by
## default, and it arrives compressed, so the frame count is worked out from
## the stream's own length and rate instead of from its byte layout - which
## only holds for raw PCM.
func _loop(w: AudioStreamWAV) -> AudioStreamWAV:
	var rate := int(w.mix_rate)
	var seconds := w.get_length()
	if rate <= 0 or seconds <= 0.01:
		return w
	var frames := int(round(seconds * float(rate)))
	if frames <= 0:
		return w
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = frames
	return w


# --------------------------------------------------------------- volume ----

## Pushes the saved percentage onto the SFX bus. 0 mutes rather than dropping
## to -80 dB, so a silent slider actually reads as silent.
func apply_volume() -> void:
	var idx := AudioServer.get_bus_index(BUS)
	if idx < 0:
		return
	var pct := int(GameManager.opt_volume)
	AudioServer.set_bus_mute(idx, pct <= 0)
	if pct > 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(pct / 100.0, 0.01, 1.0)))


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_send(i, "Master")
