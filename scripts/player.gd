class_name Player
extends CharacterBody3D

signal died
signal health_changed(current: float, max_health: float)
signal damaged_received(amount: float)
signal buff_added(id: String, stacks: int)
signal curse_added(id: String, total: int)

const CHAR_BRAWLER := 0
const CHAR_SWORDSMAN := 1
const CHAR_ICE_MAGE := 2

const DATA := {
	CHAR_BRAWLER: {
		"name": "Brawler",
		"color": Color(0.2, 0.55, 1.0),
		"accent": Color(0.04, 0.1, 0.3),
		"speed": 7.0,
		"max_health": 120.0,
		"damage": 14.0,
		"range": 2.5,
		"attack_cd": 0.42,
		"unique_name": "Super Punch",
		"dash_charges": 3,
		"desc": "Fast punches and 3 dashes. Super Punch detonates everything nearby.",
	},
	CHAR_SWORDSMAN: {
		"name": "Swordsman",
		"color": Color(1.0, 0.55, 0.12),
		"accent": Color(0.35, 0.12, 0.02),
		"speed": 6.4,
		"max_health": 90.0,
		"damage": 24.0,
		"range": 3.7,
		"attack_cd": 0.72,
		"unique_name": "Whirlwind",
		"dash_charges": 1,
		"desc": "Longer, harder sword swings and Whirlwind, but only 1 dash.",
	},
	CHAR_ICE_MAGE: {
		"name": "Ice Mage",
		"color": Color(0.55, 0.85, 1.0),
		"accent": Color(0.06, 0.2, 0.5),
		"speed": 8.58,
		"max_health": 85.0,
		"damage": 15.0,
		"range": 13.0,
		"attack_cd": 0.5,
		"unique_name": "Ice Shards",
		"dash_charges": 2,
		"desc": "Frost bolts from range, 2 dashes. Super chills everything close.",
	},
}

const DASH_SPEED := 23.0
const DASH_TIME := 0.22
const DASH_RECHARGE := 4.0
## What the dash hands back to the controller when it runs out. Handing back
## the full 23 u/s is what used to fling you most of the way across the arena:
## the old controller only had a single 18/s rate, so that leftover speed took
## over a second and ~15 units to bleed off, with no steering the whole way.
const DASH_EXIT_MULT := 1.25
## Grip instead of glide. One shared rate in both directions is what made the
## floor read as ice - you picked up speed as slowly as you shed it, so
## releasing the stick coasted for a beat and reversing swung you round in a
## long arc. Now you leave the mark briskly and stop almost on it.
const MOVE_ACCEL := 62.0
const MOVE_DECEL := 88.0
## Metres travelled per footfall. Driven by distance rather than a timer so the
## cadence speeds up with you instead of jogging on the spot at a sprint.
const STEP_SPACING := 3.0
const HEAL_AMOUNT := 45.0
const HEAL_DURATION := 1.4
const HEAL_CD_MAX := 14.0

## A hit shoves you off the strike line for a beat - hard enough to read as
## a stumble, soft enough that the stick always wins the argument.
const FLINCH_TIME := 0.15
const FLINCH_SPEED := 5.0

## The super bar climbs to 200%. 100% fires normally, 200% is the boosted hit.
const SUPER_MAX := 200.0
const SUPER_READY := 100.0
const SUPER_RADIUS := 3.6
const SUPER_RADIUS_SWORD := 4.3
const SUPER_DAMAGE := 55.0
const SUPER_DAMAGE_SWORD := 51.0
const SUPER_PER_DEALT := 1.0
const SUPER_PER_TAKEN := 2.0
const DESPERATION_HEALTH_PCT := 0.25
const DESPERATION_TIME := 10.0

## Ice Mage super: orbiting shards at 100%, homing shards at 200%.
const ICE_SHARD_COUNT := 6
const ICE_MEGA_SHARD_COUNT := 10
const ICE_SHARD_DAMAGE := 12.0
const ICE_SEEK_DAMAGE := 18.0
const ICE_SHARD_SLOW := 0.65
const ICE_SHARD_SLOW_TIME := 3.0
const ICE_ORBIT_TIME := 6.0
const ICE_SEEK_TIME := 7.0
const ICE_BOLT_SPEED := 32.0

const HIT_COLOR := Color(1.0, 0.72, 0.25)

var character_type: int = 0
var stats: Dictionary = {}

var health: Health
var camera: CameraRig

## Stacking run upgrades (8 kinds) and the System Defects that never wear
## off (10 kinds).
var buffs: Dictionary = {}
var curses: Array[String] = []

var super_charge := SUPER_MAX
var dash_charges_max := 3
var dash_charges := 3
var dash_recharging := false
var dash_recharge_t := 0.0
var heal_cd := 0.0

var ability_names: Array[String] = ["Super Punch", "Dash", "Heal"]
var ability_keys: Array[String] = ["Q", "Shift", "E"]

var invulnerable := false
var dead := false

## What most recently hurt us ("melee" / "ranged" / "trap" / "clone") - the
## Arena files its memory by cause of death.
var last_hit_source := "unknown"

## Adaptive-room suppression: halves healing while the Arena tests the fact
## that you lean on reconstruction.
var arena_heal_mult := 1.0

## True once the bar has been rebuilt to 190%+ after a spend - used to catch
## "holds the super forever" as a tracked play style.
var _super_held_announced := false

## 1.5x damage window granted by a desperation super.
var damage_bonus_mult := 1.0
var damage_bonus_time := 0.0

var visual: Node3D
var _arm_pivot: Node3D
var _body_mat: StandardMaterial3D
var _collision: CollisionShape3D
var _swing_tween: Tween
var _spin_tween: Tween

## The authored character when one loads, otherwise null and the blocky
## capsule below stands in. `_model_parts` is what turns white when you are
## hit; the clip timers drive Idle/Walk/Attack off the model's own rig.
var _model: Node3D
var _anim: AnimationPlayer
var _model_parts: Array = []
var _model_flashed := false
var _flash_mat: StandardMaterial3D
var _model_attack_t := 0.0
var _model_attack_len := 0.45
var _model_anim := ""

## The swing connects a beat after the click, on the animation's contact
## frame rather than on the press. Zero when there is no rig to time against.
var _pending_t := 0.0
var _pending_fwd := Vector3.FORWARD
var _pending_origin := Vector3.ZERO
var _pending_reach := 1.0

var attack_timer := 0.0
var attack_face_time := 0.0
var dash_time := 0.0
var dash_dir := Vector3.ZERO
var heal_time := 0.0
var heal_fx_accum := 0.0
var hit_flash := 0.0
var _trail_accum := 0.0
var _step_accum := 0.0

## A swing turns the body onto its line over a few frames (_wind_up_face)
## instead of teleporting it there in one.
var _windup_left := 0.0
var _windup_target := 0.0

## Push taken on the chin: full strength, decaying to nothing over
## FLINCH_TIME, laid over the input velocity and peeled back off each frame.
var _flinch_vel := Vector3.ZERO
var _flinch_left := 0.0
var _flinch_applied := Vector3.ZERO

## Whether the super currently resolving fired off a full (200%) bar - the
## hit marker reads that as gold.
var _strike_gold := false


func _ready() -> void:
	stats = DATA[character_type]
	collision_layer = Combat.LAYER_PLAYER
	collision_mask = Combat.LAYER_WORLD

	_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	_collision.shape = capsule
	_collision.position = Vector3(0, 0.9, 0)
	add_child(_collision)

	health = Health.new()
	health.setup(max_health_now())
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.healed.connect(_on_healed)
	health.died.connect(_on_died)

	ability_names[0] = stats["unique_name"]
	dash_charges_max = dash_max_now()
	dash_charges = dash_charges_max
	# The score measures "clean" against this run's real bar, and the ledger
	# bias rides on top of whatever the run pays out.
	GameManager.run_max_hp = max_health_now()
	GameManager.score_bonus = 0.15 * buff_stacks("jackpot")
	# Runs start with a full bar, so "held to 190%" only means something
	# after the first spend.
	_super_held_announced = super_charge >= 190.0

	_build_visual()


# ----------------------------------------------------------- derived stats ---

func buff_stacks(id: String) -> int:
	return int(buffs.get(id, 0))


func curse_count(id: String) -> int:
	var n := 0
	for c in curses:
		if c == id:
			n += 1
	return n


func max_health_now() -> float:
	var v := float(stats["max_health"]) + GameManager.hp_bonus()
	v += 20.0 * buff_stacks("vigor")
	v *= pow(0.85, curse_count("frailty"))
	return maxf(10.0, v)


func recalc_max_health() -> void:
	var new_max := max_health_now()
	# The score's clean factor follows the bar around - tell it when it moves.
	GameManager.run_max_hp = new_max
	var delta := new_max - health.max_health
	health.max_health = new_max
	if delta > 0.0:
		health.health = minf(new_max, health.health + delta)
	else:
		health.health = minf(health.health, new_max)
	health_changed.emit(health.health, health.max_health)


## Difficulty cooldowns * Haste * Broken Focus.
func cooldown_mult_now() -> float:
	var v := GameManager.cooldown_mult()
	v *= pow(0.9, buff_stacks("haste"))
	v *= pow(1.25, curse_count("broken_focus"))
	return maxf(0.2, v)


func attack_cooldown_now() -> float:
	var v := float(stats["attack_cd"]) * cooldown_mult_now()
	v *= pow(1.25, curse_count("slow_blades"))
	# CADENCE: a stacked cooldown still has to leave the swing animation
	# something to do, hence the floor.
	v *= GameManager.upg_mult("atk_speed")
	return maxf(0.18, v)


func damage_now() -> float:
	var v := float(stats["damage"])
	v *= 1.0 + 0.15 * buff_stacks("might")
	v *= pow(0.8, curse_count("weakness"))
	# STRIKE FRAME.
	v *= GameManager.upg_mult("power")
	v *= damage_bonus_mult
	return maxf(1.0, v)


func move_speed_now() -> float:
	var v := float(stats["speed"])
	v *= 1.0 + 0.08 * buff_stacks("swiftness")
	v *= pow(0.85, curse_count("sluggish"))
	# SERVO MUSCLE.
	v *= GameManager.upg_mult("speed")
	return maxf(1.5, v)


func attack_range_now() -> float:
	var v := float(stats["range"])
	v *= 1.0 + 0.12 * buff_stacks("reach")
	v *= pow(0.8, curse_count("short_reach"))
	return maxf(1.0, v)


func heal_amount_now() -> float:
	var v := HEAL_AMOUNT * (1.0 + 0.25 * buff_stacks("second_wind"))
	# REGENERATION.
	v *= GameManager.upg_mult("heal")
	v *= pow(0.5, curse_count("deep_wounds"))
	v *= arena_heal_mult
	return v


## Heals a percentage of max health (recovery-bay suppression applies).
## Returns what actually landed, so a full bar costs the caller nothing.
func heal_percent(pct: float) -> float:
	var amount := max_health_now() * clampf(pct, 0.0, 1.0) * arena_heal_mult
	# REGENERATION covers the bays and motes too - healing is healing.
	amount *= GameManager.upg_mult("heal")
	var before := health.health
	health.heal(amount)
	return health.health - before


func damage_taken_mult_now() -> float:
	var v := 1.0 + 0.15 * curse_count("brittle")
	v *= pow(0.92, buff_stacks("thick_skin"))
	# PLATING.
	v *= GameManager.upg_mult("defense")
	return v


func charge_rate_now() -> float:
	# CHARGE CELL.
	return (1.0 + 0.25 * buff_stacks("fury")) * pow(0.6, curse_count("soul_drain")) \
		* GameManager.upg_mult("super_rate")


func dash_max_now() -> int:
	# Resolute opens a spare slot on top of the kit; burden takes one back.
	return maxi(1, int(stats["dash_charges"]) + buff_stacks("resolute")
		- curse_count("burden"))


## Focus is folded in once, here, so every super strike gets it without
## each call site having to remember it.
func super_focus_mult() -> float:
	return 1.0 + 0.15 * buff_stacks("focus")


func super_base_damage() -> float:
	var v := SUPER_DAMAGE
	match character_type:
		CHAR_SWORDSMAN:
			v = SUPER_DAMAGE_SWORD
		CHAR_ICE_MAGE:
			v = SUPER_DAMAGE * 0.9
	# OVERCHARGE, folded in here so every super - base, tempest, absolute
	# zero and the desperation move - picks it up without remembering to.
	v *= GameManager.upg_mult("super_dmg")
	return v * super_focus_mult()


func super_base_radius() -> float:
	return SUPER_RADIUS if character_type == CHAR_BRAWLER else SUPER_RADIUS_SWORD


# ---------------------------------------------------------------- upgrades ---

func apply_buff(id: String) -> bool:
	if not Content.BUFFS.has(id):
		return false
	buffs[id] = buff_stacks(id) + 1
	if id == "vigor":
		recalc_max_health()
	if id == "resolute":
		# The spare charge opens on the spot, unless the recharge queue is
		# already running - that one gets to finish on its own.
		dash_charges_max = dash_max_now()
		if not dash_recharging and dash_charges < dash_charges_max:
			dash_charges = mini(dash_charges + 1, dash_charges_max)
	# Ledger Bias is worth points: the score system needs to know it loaded.
	GameManager.score_bonus = 0.15 * buff_stacks("jackpot")
	buff_added.emit(id, buff_stacks(id))
	return true


func apply_curse(id: String) -> bool:
	if not Content.CURSES.has(id):
		return false
	curses.append(id)
	recalc_max_health()
	dash_charges_max = dash_max_now()
	dash_charges = mini(dash_charges, dash_charges_max)
	curse_added.emit(id, curse_count(id))
	return true


## Picks a curse the player does not have yet when there is one left,
## applies it, and returns its id so the caller can announce it.
func apply_random_curse(rng_seed: int = -1) -> String:
	var owned := {}
	for c in curses:
		owned[c] = true
	var fresh: Array = []
	for id in Content.CURSE_IDS:
		if not owned.has(id):
			fresh.append(id)
	var pool: Array = fresh if not fresh.is_empty() else Content.CURSE_IDS.duplicate()
	var id: String
	if rng_seed >= 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed
		id = str(pool[rng.randi_range(0, pool.size() - 1)])
	else:
		id = str(pool[randi() % pool.size()])
	apply_curse(id)
	return id


# ------------------------------------------------------------------ input ----

func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		try_attack()


func _physics_process(delta: float) -> void:
	if dead:
		return

	attack_timer = maxf(0.0, attack_timer - delta)
	attack_face_time = maxf(0.0, attack_face_time - delta)
	heal_cd = maxf(0.0, heal_cd - delta)
	_resolve_pending(delta)

	if damage_bonus_time > 0.0:
		damage_bonus_time -= delta
		if damage_bonus_time <= 0.0:
			damage_bonus_time = 0.0
			damage_bonus_mult = 1.0

	if dash_recharging:
		dash_recharge_t -= delta
		if dash_recharge_t <= 0.0:
			dash_recharging = false
			dash_recharge_t = 0.0
			dash_charges = dash_charges_max

	_handle_abilities()
	_handle_movement(delta)
	_handle_heal(delta)
	animate_hit_flash(delta)
	move_and_slide()


func _process(delta: float) -> void:
	if not dead:
		_animate_model(delta)
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - delta)
		if _model_parts.is_empty():
			var base: Color = stats["color"]
			var t := hit_flash / 0.18
			_body_mat.albedo_color = base.lerp(Color.WHITE, t)
		else:
			_set_model_flash(true)
	elif not _model_parts.is_empty():
		_set_model_flash(false)


## Swap the authored character to a flat white silhouette while the flinch
## lasts, and put its own materials back the moment it does.
func _set_model_flash(on: bool) -> void:
	if _model_flashed == on or _flash_mat == null:
		return
	_model_flashed = on
	for part in _model_parts:
		var mi := part as MeshInstance3D
		if mi != null:
			mi.material_override = _flash_mat if on else null


## Idle / Walk / Attack, straight off the model's own rig. The attack clip is
## held for its full length so the swing reads, then the loop takes back over.
func _animate_model(delta: float) -> void:
	if _anim == null:
		return
	if _model_attack_t > 0.0:
		_model_attack_t -= delta
		_play_model("Attack")
	elif absf(velocity.x) + absf(velocity.z) > 0.75 or dash_time > 0.0:
		_play_model("Walk")
	else:
		_play_model("Idle")


func _play_model(anim_name: String) -> void:
	if _anim == null or _model_anim == anim_name:
		return
	_model_anim = anim_name
	_anim.play(anim_name)


func _handle_movement(delta: float) -> void:
	var dir := _input_direction()

	# Peel last frame's flinch back off first, so the controller steers a
	# clean body; the remainder goes back on at the bottom of the frame.
	velocity.x -= _flinch_applied.x
	velocity.z -= _flinch_applied.z
	_flinch_applied = Vector3.ZERO

	if dash_time > 0.0:
		dash_time -= delta
		velocity.x = dash_dir.x * DASH_SPEED
		velocity.z = dash_dir.z * DASH_SPEED
		_trail_accum += delta
		if _trail_accum >= 0.05:
			_trail_accum = 0.0
			FX.burst(get_tree().current_scene, global_position + Vector3(0, 0.9, 0),
				Color(0.55, 0.8, 1.0), 8, 0.09, 0.35, 2.5)
		if dash_time <= 0.0:
			invulnerable = false
			# Hand the body back at a controllable speed rather than leaving
			# it at 23 u/s for the movement controller to chase down.
			var exit_speed := minf(DASH_SPEED, move_speed_now() * DASH_EXIT_MULT)
			velocity.x = dash_dir.x * exit_speed
			velocity.z = dash_dir.z * exit_speed
	else:
		var target := dir * move_speed_now()
		# Asymmetric rates: brisk to start, brisker to stop, and reversing
		# brakes first instead of swinging round a long arc.
		var moving := dir.length_squared() > 0.001
		var against := moving and dir.x * velocity.x + dir.z * velocity.z < 0.0
		var rate := MOVE_ACCEL if (moving and not against) else MOVE_DECEL
		velocity.x = move_toward(velocity.x, target.x, rate * delta)
		velocity.z = move_toward(velocity.z, target.z, rate * delta)

	if is_on_floor():
		velocity.y = -0.6
	else:
		velocity.y -= 26.0 * delta

	# Footfalls: distance-based, grounded, and silent through a dash (the dash
	# has its own whoosh and would otherwise step all the way across the room).
	var planar := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and dash_time <= 0.0 and planar > 1.2 and not dead:
		_step_accum += planar * delta
		if _step_accum >= STEP_SPACING:
			_step_accum = 0.0
			Sfx.play("step", -3.0, randf_range(0.94, 1.06), 0.03)
	else:
		_step_accum = 0.0

	var face := dir
	if attack_face_time > 0.0 and camera != null:
		face = camera.get_flat_forward()
	if _windup_left > 0.0:
		# Turn onto the swing line fast, but over real time - a wind-up the
		# eye can follow instead of a one-frame snap.
		_windup_left = maxf(0.0, _windup_left - delta)
		rotation.y = lerp_angle(rotation.y, _windup_target, minf(26.0 * delta, 1.0))
	elif face.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 12.0 * delta)

	if _flinch_left > 0.0:
		# The shove rides on top of input velocity and fades to nothing, so
		# it never argues with the stick for longer than a heartbeat.
		_flinch_left = maxf(0.0, _flinch_left - delta)
		_flinch_applied = _flinch_vel * (_flinch_left / FLINCH_TIME)
		velocity.x += _flinch_applied.x
		velocity.z += _flinch_applied.z


func _handle_abilities() -> void:
	if Input.is_action_just_pressed("ability_1"):
		_use_unique()
	elif Input.is_action_just_pressed("ability_2"):
		_use_dash()
	elif Input.is_action_just_pressed("ability_3"):
		_use_heal()


func _handle_heal(delta: float) -> void:
	if heal_time <= 0.0:
		return
	heal_time -= delta
	health.heal(heal_amount_now() * delta / HEAL_DURATION)
	heal_fx_accum += delta
	if heal_fx_accum >= 0.22:
		heal_fx_accum = 0.0
		FX.burst(get_tree().current_scene, global_position + Vector3(0, 1.4, 0),
			Color(0.35, 1.0, 0.5), 8, 0.09, 0.5, 2.2)
	if heal_time <= 0.0:
		heal_time = 0.0


# --------------------------------------------------------------- combat ----

func try_attack() -> void:
	if dead or attack_timer > 0.0:
		return
	attack_timer = attack_cooldown_now()
	attack_face_time = 0.3
	ArenaMemory.note_attack("bolt" if character_type == CHAR_ICE_MAGE else "melee")
	# The whoosh belongs to the wind-up, not to contact: you hear the swing you
	# committed to whether or not it finds a body. The mage's cast is voiced
	# when the bolt actually leaves.
	if character_type != CHAR_ICE_MAGE:
		Sfx.play("sword_swing" if character_type == CHAR_SWORDSMAN else "swing")
	var reach := attack_range_now()
	var fwd := _attack_forward()
	# Soft lock: lean the attack toward whatever is closest to the crosshair.
	var cone := 45.0 if character_type != CHAR_ICE_MAGE else 26.0
	fwd = Combat.aim_assist(self, global_position + Vector3(0, 1.0, 0), fwd, reach, cone)
	_wind_up_face(atan2(-fwd.x, -fwd.z))
	_swing(true)
	# The hit lands where the swing was thrown from, a beat later, so the
	# damage and the arm read as the same event instead of two.
	var delay := _contact_delay()
	if delay <= 0.0:
		_land_hit(fwd, reach, global_position)
	else:
		_pending_t = delay
		_pending_fwd = fwd
		_pending_origin = global_position
		_pending_reach = reach


## The moment of contact. The sphere is computed from where the swing started,
## so a dash mid-swing cannot stretch the reach.
func _land_hit(fwd: Vector3, reach: float, origin: Vector3) -> void:
	if dead:
		return
	if character_type == CHAR_ICE_MAGE:
		_fire_bolt(fwd)
		return
	var center := origin + Vector3(0, 1.0, 0) + fwd * (reach * 0.55)
	var dealt := Combat.damage_sphere(self, center, reach * 0.6, damage_now(),
		fwd, 7.0, HIT_COLOR)
	_mark_hit(dealt, super_charge >= SUPER_MAX - 0.5)
	_charge_super(dealt)


func _resolve_pending(delta: float) -> void:
	if _pending_t <= 0.0:
		return
	_pending_t -= delta
	if _pending_t > 0.0:
		return
	_pending_t = 0.0
	_land_hit(_pending_fwd, _pending_reach, _pending_origin)


## Long enough to land on the animation's contact frame, short enough that it
## never reads as lag - a fraction of the swing, capped just under a tenth.
const CONTACT_FRACTION := 0.35
const CONTACT_MAX := 0.16

## The rig's swing was authored for its own tempo, not for ours: every clip is
## 2.5 seconds of wind-up, strike and recovery, which reads as a shrug next to
## a 0.4-second cooldown. It is played fast enough to be a swing instead, and
## short enough that the loop takes over before the next swing is allowed.
const SWING_BUDGET := 0.42
const SWING_MAX_SPEED := 8.0


func _attack_clip_speed() -> float:
	if _anim == null or _model_attack_len <= 0.0:
		return 1.0
	var budget := minf(attack_cooldown_now() * 0.9, SWING_BUDGET)
	return clampf(_model_attack_len / maxf(budget, 0.05), 1.0, SWING_MAX_SPEED)


## Long enough to land on the animation's contact frame, short enough that it
## never reads as lag - a third of the swing, and never more than a heartbeat.
func _contact_delay() -> float:
	if _anim == null or _model_attack_t <= 0.0:
		return 0.0
	return minf(_model_attack_t * CONTACT_FRACTION, CONTACT_MAX)


## Centre-screen marker for a real connect: white for ordinary contact, gold
## when it lands off a full (200%) bar or a desperation swing.
func _mark_hit(dealt: float, gold: bool) -> void:
	if dealt <= 0.0:
		return
	GameManager.hit_connected.emit(
		Color(1.0, 0.85, 0.35) if gold else Color(1.0, 1.0, 1.0))


## Called back by Combat.damage_sphere once a sweep has actually connected.
## Every one of the player's area attacks funnels through that one function, so
## putting the voice here means supers, jabs and crowd sweeps are all heard
## exactly once and each character still sounds like itself.
func announce_hit(dealt: float, at: Vector3) -> void:
	var key := "hit"
	match character_type:
		CHAR_SWORDSMAN:
			key = "hit_sword"
		CHAR_ICE_MAGE:
			key = "bolt_hit"
	# One body is a jab. A sweep that went through a crowd drops a pitch, so
	# three bodies read as weight instead of as three copies of the same clip.
	var crowd := clampf(dealt / maxf(damage_now() * 2.5, 1.0), 0.0, 1.0)
	Sfx.play_at(key, at, lerpf(-2.0, 2.0, crowd), lerpf(1.0, 0.86, crowd), 0.06)


## Frost bolt: straight-line skillshot that stops on the first wall or body.
func _fire_bolt(dir: Vector3) -> void:
	var root := _scene_root()
	if root == null:
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length_squared() > 0.001 else Vector3(0, 0, -1)
	var bolt := IceBolt.new()
	bolt.setup(d, damage_now(), attack_range_now(), self)
	root.add_child(bolt)
	bolt.global_position = global_position + Vector3(0, 1.25, 0) + d * 0.75
	Sfx.play("cast")
	FX.burst(root, bolt.global_position, Color(0.6, 0.9, 1.0), 10, 0.1, 0.3, 3.0)


func charge_super(amount: float) -> void:
	_charge_super(amount)


func _scene_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return get_parent()
	return tree.current_scene if tree.current_scene != null else get_parent()


func can_use_unique() -> bool:
	return not dead and super_charge >= SUPER_READY - 0.01


func _use_unique() -> void:
	if not can_use_unique():
		# The bar is the timer, but a press that does nothing should still
		# answer - otherwise the ability reads as broken rather than as not
		# ready. Soft, because you will hear it often.
		if not dead:
			Sfx.play("ui_error")
		return
	ArenaMemory.note_super()
	_super_held_announced = false
	var at_max := super_charge >= SUPER_MAX - 0.5
	var desperate := at_max and health.health <= health.max_health * DESPERATION_HEALTH_PCT
	# Remember the tier before the bar empties: the marker wants it gold.
	_strike_gold = at_max
	super_charge = 0.0
	attack_face_time = 0.45
	GameManager.super_fired.emit(_super_name(at_max, desperate), 2 if at_max else 1)
	# The 200% bar is pitched up so the two tiers do not sound like the same
	# event; LAST STAND gets its own sting because it only happens once.
	if desperate:
		Sfx.play("desperation", 0.0, 0.9, 0.02)
	else:
		Sfx.play("super", 0.0, 1.2 if at_max else 1.0, 0.03)
	if camera != null:
		# A short punch-in so every super lands with weight, not just shake.
		camera.kick_fov(-7.0)

	if desperate:
		_desperation_strike()
	elif at_max:
		if character_type == CHAR_ICE_MAGE:
			_absolute_zero()
		elif character_type == CHAR_SWORDSMAN:
			_blade_tempest()
		else:
			_mega_strike()
	elif character_type == CHAR_ICE_MAGE:
		_spawn_shards(ICE_SHARD_COUNT, false)
	elif character_type == CHAR_SWORDSMAN:
		_whirlwind()
	else:
		_super_punch()


## What the move is called, so the banner can say it. The 100% and 200% bars
## fire on the same key, and the difference between them used to be invisible.
func _super_name(at_max: bool, desperate: bool) -> String:
	if desperate:
		return "LAST STAND"
	if at_max:
		match character_type:
			CHAR_SWORDSMAN:
				return "BLADE TEMPEST"
			CHAR_ICE_MAGE:
				return "ABSOLUTE ZERO"
		return "METEOR STRIKE"
	match character_type:
		CHAR_SWORDSMAN:
			return "WHIRLWIND"
		CHAR_ICE_MAGE:
			return "FROST ORBIT"
	return "SUPER PUNCH"


## What the super slot should call itself right now: the move the bar is
## actually holding, which changes once it crosses 200%.
func super_display_name() -> String:
	var at_max := super_charge >= SUPER_MAX - 0.5
	var desperate := at_max and health.health <= health.max_health * DESPERATION_HEALTH_PCT
	return _super_name(at_max, desperate)


## 100%: six shards circle you and chill anything they touch.
## 200%: ten shards launch themselves at the nearest enemies.
func _spawn_shards(count: int, homing: bool) -> void:
	var root := _scene_root()
	if root == null:
		return
	_spin_visual()
	var field := IceShards.new()
	field.setup(self, count, homing)
	root.add_child(field)
	var radius := 6.5 if homing else 4.5
	FX.ring(root, global_position + Vector3(0, 0.3, 0),
		Color(0.45, 0.85, 1.0), radius, 0.55)
	FX.shockwave(root, global_position, Color(0.5, 0.9, 1.0), radius + 1.5, 0.55, 0.15)
	FX.column(root, global_position, Color(0.4, 0.8, 1.0),
		1.5 if homing else 1.1, 8.0 if homing else 6.0, 0.55, 0.05)
	FX.burst(root, global_position + Vector3(0, 1.1, 0),
		Color(0.7, 0.95, 1.0), 60 if homing else 34, 0.14, 0.7, 9.0)
	if camera != null:
		camera.shake(0.6 if homing else 0.35)


## 100% - the original super, and it finally looks like one: a ring racing
## across the floor, a pillar where the punch lands, a core flash and blades
## thrown outward from the fist.
func _super_punch() -> void:
	var fwd := Combat.aim_assist(self, global_position + Vector3(0, 1.0, 0),
		_attack_forward(), super_base_radius() + 2.0, 40.0)
	_wind_up_face(atan2(-fwd.x, -fwd.z))
	_swing(false)
	var scene := _scene_root()
	var center := global_position + Vector3(0, 0.9, 0) + fwd * 2.0
	FX.shockwave(scene, global_position, Color(1.0, 0.6, 0.15), 7.5, 0.5, 0.16)
	FX.column(scene, global_position + fwd * 2.0, Color(1.0, 0.72, 0.2),
		1.8, 9.0, 0.55, 0.06)
	FX.orb(scene, center, Color(1.0, 0.85, 0.45), 3.6, 0.34)
	FX.spokes(scene, global_position + Vector3(0, 0.5, 0), Color(1.0, 0.88, 0.55),
		8, 7.0, 0.45, 0.32, 0.05)
	FX.ring(scene, global_position + Vector3(0, 0.3, 0), Color(1.0, 0.7, 0.2), 4.0, 0.5)
	FX.burst(scene, center, Color(1.0, 0.78, 0.3), 55, 0.17, 0.7, 11.0)
	FX.hitstop(0.1, 0.05)
	var dealt := Combat.damage_sphere(self, center, super_base_radius(),
		super_base_damage(), fwd, 17.0, Color(1.0, 0.82, 0.35))
	_mark_hit(dealt, _strike_gold)
	if camera != null:
		camera.shake(0.55)


## 100% - three passes of the blade, each one wider than the last.
func _whirlwind() -> void:
	_spin_visual()
	FX.orb(_scene_root(), global_position + Vector3(0, 1.1, 0),
		Color(1.0, 0.92, 0.5), 3.4, 0.3)
	for i in 3:
		# process_always = false: the passes wait out a pause instead of
		# landing hits while the menu is up.
		var timer := get_tree().create_timer(0.17 * i, false)
		timer.timeout.connect(_whirlwind_tick.bind(i))
	if camera != null:
		camera.shake(0.3)


func _whirlwind_tick(i: int = 0) -> void:
	if dead or not is_instance_valid(self):
		return
	var center := global_position + Vector3(0, 0.9, 0)
	var scene := _scene_root()
	var wide := 3.4 + 1.3 * float(i)
	FX.ring(scene, global_position + Vector3(0, 0.2, 0), Color(1.0, 0.9, 0.4), wide, 0.4)
	FX.shockwave(scene, global_position, Color(1.0, 0.85, 0.35), wide + 1.6, 0.45, 0.13)
	if i >= 2:
		FX.spokes(scene, global_position + Vector3(0, 0.55, 0),
			Color(1.0, 0.95, 0.7), 8, 6.5, 0.4, 0.28, 0.04)
		FX.column(scene, global_position, Color(1.0, 0.88, 0.45), 1.5, 7.0, 0.5)
		FX.hitstop(0.08, 0.06)
	var dealt := Combat.damage_sphere(self, center, super_base_radius(),
		17.0 * super_focus_mult(), Vector3.ZERO, 6.0, Color(1.0, 0.92, 0.45))
	_mark_hit(dealt, _strike_gold)
	if camera != null:
		camera.shake(0.18 + 0.12 * float(i))


## 200% - Blade Tempest: three widening rings of steel thrown around you, the
## last pass throwing blades in every direction under a column of gold.
func _blade_tempest() -> void:
	_spin_visual()
	_swing(false)
	var scene := _scene_root()
	FX.orb(scene, global_position + Vector3(0, 1.1, 0), Color(1.0, 0.9, 0.5), 4.2, 0.34)
	FX.burst(scene, global_position + Vector3(0, 1.0, 0), Color(1.0, 0.88, 0.4),
		70, 0.18, 0.7, 13.0)
	FX.hitstop(0.09, 0.05)
	if camera != null:
		camera.shake(0.45)
	for i in 3:
		var timer := get_tree().create_timer(0.12 * i, false)
		timer.timeout.connect(_tempest_tick.bind(i))


func _tempest_tick(i: int) -> void:
	if dead or not is_instance_valid(self):
		return
	var scene := _scene_root()
	var f := float(i)
	var ring_r := 5.0 + 3.4 * f
	var hit_r := super_base_radius() * (1.8 + 0.65 * f)
	var center := global_position + Vector3(0, 0.9, 0)
	FX.shockwave(scene, global_position, Color(1.0, 0.85, 0.35), ring_r, 0.5, 0.16)
	FX.ring(scene, global_position + Vector3(0, 0.2, 0),
		Color(1.0, 0.95, 0.65), ring_r * 0.7, 0.4)
	var dealt := Combat.damage_sphere(self, center, hit_r,
		super_base_damage() * 0.8, Vector3.ZERO, 16.0, Color(1.0, 0.88, 0.4))
	_mark_hit(dealt, _strike_gold)
	FX.burst(scene, center, Color(1.0, 0.9, 0.5), 40 + i * 25, 0.16, 0.6, 10.0)
	if i >= 2:
		FX.spokes(scene, global_position + Vector3(0, 0.55, 0),
			Color(1.0, 0.96, 0.72), 12, 10.0, 0.5, 0.32, 0.03)
		FX.column(scene, global_position, Color(1.0, 0.85, 0.4), 2.4, 10.0, 0.6)
		FX.hitstop(0.13, 0.05)
		if camera != null:
			camera.shake(0.8)
	elif camera != null:
		camera.shake(0.25)


## 200% - twice the damage across three times the reach, and it looks like it.
func _mega_strike() -> void:
	var fwd := Combat.aim_assist(self, global_position + Vector3(0, 1.0, 0),
		_attack_forward(), super_base_radius() * 2.0, 45.0)
	_wind_up_face(atan2(-fwd.x, -fwd.z))
	_swing(false)
	var scene := _scene_root()
	var center := global_position + Vector3(0, 0.9, 0) + fwd * 3.0
	var radius := super_base_radius() * 3.0
	FX.shockwave(scene, global_position, Color(1.0, 0.55, 0.1), 13.0, 0.65, 0.2)
	FX.shockwave(scene, global_position, Color(0.4, 0.8, 1.0), 8.5, 0.5, 0.14, 0.1)
	FX.column(scene, global_position + fwd * 3.0, Color(0.55, 0.88, 1.0),
		3.0, 12.0, 0.65, 0.04)
	FX.orb(scene, center, Color(0.7, 0.93, 1.0), 5.4, 0.4)
	FX.spokes(scene, global_position + Vector3(0, 0.5, 0), Color(0.75, 0.95, 1.0),
		12, 11.0, 0.5, 0.34, 0.05)
	FX.ring(scene, global_position + Vector3(0, 0.3, 0), Color(0.3, 0.75, 1.0), 7.0, 0.6)
	FX.ring(scene, global_position + Vector3(0, 0.3, 0), Color(1.0, 1.0, 1.0), 4.0, 0.35)
	FX.burst(scene, center, Color(0.5, 0.85, 1.0), 90, 0.2, 0.8, 16.0)
	FX.hitstop(0.14, 0.045)
	var dealt := Combat.damage_sphere(self, center, radius, super_base_damage() * 2.0,
		fwd, 24.0, Color(0.55, 0.9, 1.0))
	_mark_hit(dealt, _strike_gold)
	if camera != null:
		camera.shake(0.85)


## 200% - Absolute Zero: the room freezes in one flash, everything caught in
## the ring takes the hit, and the shards that were orbiting you hunt.
func _absolute_zero() -> void:
	_spin_visual()
	var scene := _scene_root()
	var center := global_position + Vector3(0, 0.9, 0)
	FX.shockwave(scene, global_position, Color(0.6, 0.95, 1.0), 13.0, 0.7, 0.2)
	FX.shockwave(scene, global_position, Color(1.0, 1.0, 1.0), 8.0, 0.5, 0.14, 0.12)
	FX.column(scene, global_position, Color(0.45, 0.85, 1.0), 3.0, 12.0, 0.7, 0.05)
	FX.orb(scene, center, Color(0.75, 0.96, 1.0), 5.6, 0.42)
	FX.spokes(scene, global_position + Vector3(0, 0.55, 0), Color(0.8, 0.97, 1.0),
		10, 11.0, 0.55, 0.34, 0.06)
	var dealt := Combat.damage_sphere(self, center, super_base_radius() * 2.6,
		super_base_damage() * 1.2, Vector3.ZERO, 26.0, Color(0.55, 0.9, 1.0))
	_mark_hit(dealt, _strike_gold)
	_spawn_shards(ICE_MEGA_SHARD_COUNT, true)
	FX.hitstop(0.14, 0.045)
	if camera != null:
		camera.shake(0.9)


## 200% at <=25% health - 5x damage in every direction, a knockback blast and
## 1.5x damage for the next 10 seconds.
func _desperation_strike() -> void:
	var center := global_position + Vector3(0, 0.9, 0)
	var radius := minf(super_base_radius() * 3.4, 12.5)
	var scene := _scene_root()
	_spin_visual()
	# Layered so it reads as the loudest thing in the game: two racing ground
	# rings, a burning pillar, the core flash and blades thrown to the walls.
	FX.shockwave(scene, global_position, Color(1.0, 0.2, 0.12), 15.0, 0.75, 0.24)
	FX.shockwave(scene, global_position, Color(1.0, 0.8, 0.3), 10.0, 0.6, 0.18, 0.1)
	FX.column(scene, global_position, Color(1.0, 0.45, 0.18), 3.4, 13.0, 0.75)
	FX.orb(scene, center, Color(1.0, 0.5, 0.3), 6.0, 0.45)
	FX.spokes(scene, global_position + Vector3(0, 0.55, 0), Color(1.0, 0.7, 0.4),
		14, 13.0, 0.55, 0.36)
	FX.ring(scene, global_position + Vector3(0, 0.3, 0), Color(1.0, 0.2, 0.15), 9.0, 0.7)
	FX.ring(scene, global_position + Vector3(0, 0.3, 0), Color(1.0, 0.85, 0.3), 6.0, 0.5)
	FX.burst(scene, center, Color(1.0, 0.35, 0.2), 140, 0.24, 0.9, 22.0)
	FX.hitstop(0.18, 0.04)
	var dealt := Combat.damage_sphere(self, center, radius, super_base_damage() * 5.0,
		Vector3.ZERO, 34.0, Color(1.0, 0.45, 0.25))
	# Desperation is always gold, whatever the bar said when it fired.
	_mark_hit(dealt, true)
	damage_bonus_mult = 1.5
	damage_bonus_time = DESPERATION_TIME
	if character_type == CHAR_ICE_MAGE:
		# The frost version of the desperation blast keeps the 200% payload.
		_spawn_shards(ICE_MEGA_SHARD_COUNT, true)
	if camera != null:
		camera.shake(1.0)


func _charge_super(amount: float) -> void:
	if amount <= 0.0:
		return
	super_charge = minf(SUPER_MAX, super_charge + amount * charge_rate_now())
	if not _super_held_announced and super_charge >= 190.0:
		_super_held_announced = true
		ArenaMemory.note_super_held()


func can_dash() -> bool:
	return not dead and dash_time <= 0.0 and not dash_recharging and dash_charges > 0


## Clearing a room hands back one dash charge. Returns true when one landed,
## so the HUD only pings you when it actually mattered.
func refund_dash() -> bool:
	if dead:
		return false
	if dash_charges >= dash_charges_max:
		return false
	if dash_recharging:
		dash_recharging = false
		dash_recharge_t = 0.0
		dash_charges = 0
	dash_charges = mini(dash_charges + 1, dash_charges_max)
	return true


func _use_dash() -> void:
	if not can_dash():
		# Mid-dash an early press is just early, and buzzing at it every time
		# becomes noise. Out of charges is real feedback and deserves an answer.
		if not dead and dash_time <= 0.0:
			Sfx.play("ui_error")
		return
	ArenaMemory.note_dash()
	dash_charges -= 1
	if dash_charges <= 0:
		dash_charges = 0
		dash_recharging = true
		dash_recharge_t = DASH_RECHARGE * cooldown_mult_now()
	dash_time = DASH_TIME
	invulnerable = true
	_trail_accum = 0.0
	if camera != null:
		camera.kick_fov(9.0)
	var dir := _input_direction()
	if dir.length_squared() < 0.01:
		dir = _attack_forward()
	dash_dir = dir.normalized()
	dash_dir.y = 0.0
	Sfx.play("dash")
	FX.burst(get_tree().current_scene, global_position + Vector3(0, 0.5, 0),
		Color(0.55, 0.8, 1.0), 18, 0.1, 0.4, 4.5)


func _use_heal() -> void:
	if dead:
		return
	if heal_cd > 0.0 or heal_time > 0.0:
		Sfx.play("ui_error")
		return
	if health.health >= health.max_health:
		Sfx.play("ui_error")
		return
	ArenaMemory.note_heal()
	heal_cd = HEAL_CD_MAX * cooldown_mult_now()
	heal_time = HEAL_DURATION
	heal_fx_accum = 0.0
	Sfx.play("heal")


## Damage from traps / enemies / projectiles. Returns the damage actually taken.
## `source` tags the hit so the Arena can file its memory by cause of death.
func apply_hit(damage: float, dir: Vector3, knockback: float = 0.0,
		source: String = "") -> float:
	# `invulnerable` is the dash window; Health keeps its own post-hit grace.
	# Neither may let damage through that Health will refuse to count.
	if dead or invulnerable or health == null or health.invulnerable:
		return 0.0
	var scaled := damage * damage_taken_mult_now()
	var dealt := minf(scaled, health.health)
	if source != "":
		last_hit_source = source
	if dir.length_squared() > 0.01 and knockback > 0.0:
		var push := dir.normalized() * knockback
		velocity.x += push.x
		velocity.z += push.z
	# Report the strike from where it came from, not from our own feet: the
	# flinch reads that position to work out which way to stumble.
	var hit_at := global_position
	if dir.length_squared() > 0.01:
		hit_at = global_position - dir.normalized() * 1.4
	if not health.take_damage(scaled, hit_at):
		return 0.0
	return dealt


## One entry per ability: how full the bar is (0..1), a short label, readiness.
func get_ability_state() -> Array:
	var super_fill := clampf(super_charge / SUPER_MAX, 0.0, 1.0)
	var dash_fill := 1.0
	var dash_label := "x%d" % dash_charges
	var dash_ready := not dash_recharging and dash_charges > 0
	if dash_recharging:
		dash_fill = clampf(1.0 - dash_recharge_t / maxf(DASH_RECHARGE
			* cooldown_mult_now(), 0.1), 0.0, 1.0)
		dash_label = "%.0f" % dash_recharge_t
	elif dash_charges_max > 0:
		dash_fill = float(dash_charges) / float(dash_charges_max)

	var heal_max := HEAL_CD_MAX * cooldown_mult_now()
	var heal_fill := clampf(1.0 - heal_cd / maxf(heal_max, 0.1), 0.0, 1.0)
	var super_label := "%d%%" % int(round(super_charge))
	if super_charge >= SUPER_MAX - 0.5:
		super_label = "200%!"
	elif super_charge >= SUPER_READY:
		super_label = "READY"

	return [
		{
			"name": ability_names[0],
			"key": ability_keys[0],
			"fill": super_fill,
			"label": super_label,
			"ready": super_charge >= SUPER_READY - 0.01,
		},
		{
			"name": ability_names[1],
			"key": ability_keys[1],
			"fill": dash_fill,
			"label": dash_label,
			"ready": dash_ready,
		},
		{
			"name": ability_names[2],
			"key": ability_keys[2],
			"fill": heal_fill,
			"label": "%.1f" % heal_cd if heal_cd > 0.05 else "READY",
			"ready": heal_cd <= 0.0,
		},
	]


# -------------------------------------------------------------- signals ----

func _on_damaged(amount: float, current: float, hit_position: Vector3) -> void:
	hit_flash = 0.18
	GameManager.room_damage += amount
	GameManager.damage_taken_run += amount
	GameManager.break_streak()
	ArenaMemory.note_damage(amount)
	health_changed.emit(current, health.max_health)
	damaged_received.emit(amount)
	_charge_super(amount * SUPER_PER_TAKEN)
	# Your own hurt gets a number too - red, so it never reads as a heal.
	Combat.pop_number(_scene_root(), global_position + Vector3(0, 1.8, 0),
		amount, Color(1.0, 0.35, 0.35), 1.1)
	_flinch_from(hit_position)
	FX.burst(get_tree().current_scene, global_position + Vector3(0, 1.1, 0),
		Color(1.0, 0.2, 0.18), 26, 0.13, 0.5, 6.5)
	# The thud is where it landed, the grunt is you. Layered on purpose - one
	# alone reads as either a wall hit or a cutscene.
	Sfx.play_at("hit_taken", global_position)
	Sfx.play("hurt")
	if camera != null:
		camera.shake(0.24)


func _on_healed(_amount: float, current: float) -> void:
	health_changed.emit(current, health.max_health)


func _on_died() -> void:
	if dead:
		return
	dead = true
	invulnerable = true
	collision_layer = 0
	Sfx.play("player_die")
	call_deferred("_disable_collision")
	died.emit()
	var scene := get_tree().current_scene
	FX.burst(scene, global_position + Vector3(0, 1.0, 0), Color(1.0, 0.15, 0.15),
		70, 0.17, 0.9, 9.5)
	FX.ring(scene, global_position + Vector3(0, 0.2, 0), Color(1.0, 0.3, 0.2), 3.0, 0.5)
	if camera != null:
		camera.shake(0.5)
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(1.0, 0.04, 1.0), 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "visible", false, 0.05)


func _disable_collision() -> void:
	if _collision != null and is_instance_valid(_collision):
		_collision.disabled = true


# --------------------------------------------------------------- helpers ----

func _input_direction() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := Basis.IDENTITY
	if camera != null:
		basis = camera.get_yaw_basis()
	var fwd := -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	var d := right * v.x + fwd * (-v.y)
	d.y = 0.0
	if d.length_squared() > 1.0:
		d = d.normalized()
	return d


func _attack_forward() -> Vector3:
	if camera != null:
		return camera.get_flat_forward()
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3(0, 0, -1)


## Wind the body onto the swing line over a tenth of a second. A one-frame
## snap read as a teleport; the hit itself still lands on the same tick.
func _wind_up_face(target: float) -> void:
	_windup_target = target
	_windup_left = 0.1


## Shove away from the strike, decaying over FLINCH_TIME. Small on purpose:
## enough to feel the hit, not enough to push you through anything.
func _flinch_from(hit_position: Vector3) -> void:
	var away := global_position - hit_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	_flinch_vel = away.normalized() * FLINCH_SPEED
	_flinch_left = FLINCH_TIME


func animate_hit_flash(_delta: float) -> void:
	if hit_flash <= 0.0:
		var base: Color = stats["color"]
		_body_mat.albedo_color = base


# --------------------------------------------------------------- visuals ----

func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)

	_body_mat = Util.make_material(stats["color"], 0.55, 0.15)

	_arm_pivot = Node3D.new()
	_arm_pivot.position = Vector3(0.42, 1.3, 0.0)
	visual.add_child(_arm_pivot)

	# The three warriors ship as rigged characters. If one will not load or
	# will not fit, _model stays null and the blocky body below stands in.
	_model = CharacterModels.build(visual, character_type)
	if _model != null:
		for row in CharacterModels.meshes(_model):
			_model_parts.append(row[0])
		_anim = CharacterModels.animation_player(_model)
		_model_attack_len = CharacterModels.prime(_anim)
		_flash_mat = Util.make_material(Color(1, 1, 1), 1.0, 0.0)
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if _anim != null:
			_model_anim = "Idle"
			_anim.play("Idle")
		# The rig carries the weapon and the swing itself. The pivot stays so
		# the old tween below has something harmless to push around.
		_arm_pivot.visible = false
		return

	Util.add_capsule(visual, 0.45, 1.8, Vector3(0, 0.9, 0), _body_mat, 0.05)

	var accent := Util.make_material(stats["accent"], 0.7, 0.1)
	Util.add_sphere(visual, 0.3, Vector3(0, 1.95, 0), accent, 0.04)

	var eye_mat := Util.make_material(Color(0.95, 0.97, 1.0), 0.2, 0.0,
		Color(1, 1, 1), 1.6)
	Util.add_sphere(visual, 0.07, Vector3(-0.13, 2.0, -0.26), eye_mat)
	Util.add_sphere(visual, 0.07, Vector3(0.13, 2.0, -0.26), eye_mat)

	Util.add_box(visual, Vector3(0.22, 0.3, 0.22), Vector3(-0.18, 0.16, 0), accent, 0.03)
	Util.add_box(visual, Vector3(0.22, 0.3, 0.22), Vector3(0.18, 0.16, 0), accent, 0.03)

	if character_type == CHAR_SWORDSMAN:
		Util.add_box(_arm_pivot, Vector3(0.14, 0.14, 0.7), Vector3(0, 0, -0.3), accent, 0.03)
		Util.add_box(_arm_pivot, Vector3(0.34, 0.08, 0.1), Vector3(0, 0, -0.66),
			Util.make_material(Color(0.75, 0.6, 0.2), 0.35, 0.8), 0.02)
		Util.add_box(_arm_pivot, Vector3(0.08, 0.06, 1.5), Vector3(0, 0, -1.45),
			Util.make_material(Color(0.85, 0.88, 0.95), 0.15, 0.95, Color(0.6, 0.75, 1.0), 0.35),
			0.02)
	elif character_type == CHAR_ICE_MAGE:
		var staff := Util.make_material(Color(0.22, 0.3, 0.52), 0.6, 0.15)
		Util.add_box(_arm_pivot, Vector3(0.13, 0.13, 0.5), Vector3(0, 0, -0.2), accent, 0.03)
		Util.add_box(_arm_pivot, Vector3(0.09, 0.09, 1.75), Vector3(0, 0.04, -0.8),
			staff, 0.03)
		Util.add_cone(_arm_pivot, 0.14, 0.34, Vector3(0, 0.04, -1.68), staff, 0.03)
		var crystal := Util.make_material(Color(0.72, 0.95, 1.0), 0.1, 0.0,
			Color(0.35, 0.75, 1.0), 4.0)
		Util.add_sphere(_arm_pivot, 0.2, Vector3(0, 0.04, -1.86), crystal, 0.04)
		# Frozen pauldrons so the silhouette reads at a glance.
		var ice := Util.make_material(Color(0.75, 0.93, 1.0), 0.2, 0.1,
			Color(0.4, 0.8, 1.0), 1.6)
		for side in [-1.0, 1.0]:
			Util.add_cone(visual, 0.14, 0.4, Vector3(side * 0.4, 1.75, 0.0), ice, 0.04)
	else:
		Util.add_box(_arm_pivot, Vector3(0.14, 0.14, 0.5), Vector3(0, 0, -0.2), accent, 0.03)
		Util.add_sphere(_arm_pivot, 0.19, Vector3(0, 0, -0.52),
			Util.make_material(stats["color"], 0.5, 0.2), 0.03)


func _swing(fast := true) -> void:
	if _anim != null:
		# Restart the clip even if the last swing never finished. On a basic
		# attack the rig is sped up to finish inside the cooldown, so the loop
		# takes back over before the next swing is allowed to start.
		var speed := _attack_clip_speed() if fast else 1.0
		_model_attack_t = _model_attack_len / maxf(speed, 0.01)
		if _model_anim == "Attack":
			_anim.stop()
		_model_anim = "Attack"
		_anim.play("Attack", -1, speed)
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_arm_pivot.position.z = 0.0
	_arm_pivot.rotation.x = 0.0
	_swing_tween = create_tween()
	if character_type == CHAR_SWORDSMAN:
		_arm_pivot.rotation.x = -1.7
		_swing_tween.tween_property(_arm_pivot, "rotation:x", 1.1, 0.13) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_swing_tween.tween_property(_arm_pivot, "rotation:x", 0.0, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_swing_tween.tween_property(_arm_pivot, "position:z", -0.5, 0.06) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_swing_tween.tween_property(_arm_pivot, "position:z", 0.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## One full turn of the model. Supers call this and then hand off to another
## helper that calls it again, so the previous turn is dropped rather than
## left fighting this one over the same rotation.
func _spin_visual() -> void:
	if _spin_tween != null and _spin_tween.is_valid():
		_spin_tween.kill()
	_spin_tween = create_tween()
	_spin_tween.tween_property(visual, "rotation:y", visual.rotation.y + TAU, 0.45) \
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
