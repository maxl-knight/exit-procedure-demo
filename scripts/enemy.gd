class_name Enemy
extends CharacterBody3D

signal died(enemy: Enemy)

enum Type { GRUNT, ARCHER, FAST, BIG }
enum Elite { NONE, BERSERKER, JUGGERNAUT, HEXMASTER }
enum State { CHASE, WINDUP, LUNGE, RECOVER, DEAD }

const BAR_WIDTH := 0.95

const TYPE_NAMES := {
	Type.GRUNT: "Grunt",
	Type.ARCHER: "Archer",
	Type.FAST: "Runner",
	Type.BIG: "Brute",
}

## Per-type silhouette + behaviour tuning.
const TYPE_DATA := {
	Type.GRUNT: {
		"scale": 1.0, "radius": 0.45, "height": 1.9, "windup": 0.55,
		"recover": 0.75, "range": 2.3, "hp_mult": 1.0, "dmg_mult": 1.0, "spd_mult": 1.0,
	},
	Type.ARCHER: {
		"scale": 0.85, "radius": 0.4, "height": 1.6, "windup": 0.7,
		"recover": 1.3, "range": 13.0, "hp_mult": 0.45, "dmg_mult": 1.1, "spd_mult": 0.95,
	},
	Type.FAST: {
		"scale": 0.75, "radius": 0.34, "height": 1.45, "windup": 0.34,
		"recover": 0.5, "range": 1.9, "hp_mult": 0.5, "dmg_mult": 0.7, "spd_mult": 1.85,
	},
	Type.BIG: {
		"scale": 1.5, "radius": 0.68, "height": 2.85, "windup": 0.85,
		"recover": 1.05, "range": 3.1, "hp_mult": 3.2, "dmg_mult": 2.0, "spd_mult": 0.6,
	},
}

## The three elite / mini-boss flavours. Elites hit harder, reach further,
## soak far more damage and (except the Hexmaster) lunge at you.
const ELITE_DATA := {
	Elite.BERSERKER: {
		# The dasher is meant to be a threat you answer, not a wall: low
		# health for an elite, and a long cool-down on the lunge so every
		# dash has to be committed to.
		"name": "Berserker", "hp_mult": 2.8, "dmg_mult": 1.6, "range_mult": 1.6,
		"windup_mult": 0.7, "recover_mult": 0.7, "spd_mult": 1.2, "scale": 1.3,
		"dash": true, "dash_cd": 6.5, "color": Color(0.98, 0.28, 0.14),
		"aura": Color(1.0, 0.35, 0.1),
	},
	Elite.JUGGERNAUT: {
		# The wall is meant to be readable, not punishing. He telegraphs for
		# roughly twice as long as anything else in the room, shuffles instead
		# of striding, and stays committed after every swing long enough for you
		# to walk out and answer. He still soaks a mountain of damage - that is
		# what he is for - but he is no longer also the fastest thing on the floor.
		"name": "Juggernaut", "hp_mult": 7.5, "dmg_mult": 2.2, "range_mult": 2.2,
		"windup_mult": 2.2, "recover_mult": 1.9, "spd_mult": 0.55, "scale": 1.75,
		"dash": true, "dash_cd": 11.0, "color": Color(0.58, 0.3, 0.95),
		"aura": Color(0.7, 0.3, 1.0),
	},
	Elite.HEXMASTER: {
		"name": "Hexmaster", "hp_mult": 3.0, "dmg_mult": 1.7, "range_mult": 1.0,
		"windup_mult": 0.85, "recover_mult": 0.8, "spd_mult": 1.0, "scale": 1.35,
		"dash": false, "dash_cd": 0.0, "color": Color(0.1, 0.88, 0.84),
		"aura": Color(0.2, 1.0, 0.9),
	},
}

const ELITE_KINDS := [Elite.BERSERKER, Elite.JUGGERNAUT, Elite.HEXMASTER]

## Frost-tinted colour an enemy wears while slowed (Ice Mage shards).
const CHILL_COLOR := Color(0.55, 0.84, 1.0)

## Anything that falls out of the world gets pulled back onto the floor.
const FLOOR_Y := -20.0

## Melee hits only land if both bodies are within this height of each other.
const HIT_Y_MAX := 4.0

## How long a freshly-materialised enemy stands down before it commits. The
## room only spawns once you are inside it, so this is the beat that turns
## "enemies appeared" into "you both started fighting" instead of a cheap hit.
const ENTRY_GRACE := 0.75

var type: int = Type.GRUNT
var elite: int = Elite.NONE
var target: Node3D

var max_hp := 40.0
var hp := 40.0
var damage := 8.0
## Grip instead of glide, same call as the player: one shared low rate in both
## directions made every body read as though the floor were ice - slow to pick
## up speed, slow to shed it, and slowest of all to change its mind. The chase
## used to round off into every turn, so bodies drifted where you expected
## them to stop. Rates scale with the individual's speed so a slow bruiser and
## a sprinter both feel responsive rather than one of them feeling mushy.
const ACCEL := 24.0
const DECEL := 34.0
## The lunge carries real momentum, but the old 10/s recovery brake let a
## 13 u/s body skid 8+ units past its target before it could recover - the
## enemy half of "the dash launches you across the room".
const LUNGE_BRAKE := 46.0
const WINDUP_BRAKE := 34.0
## A dash still has to feel faster than the walk, but the floor used to be a
## flat 13 u/s that ignored whose body it was on - which meant the deliberately
## slow tank covered ground exactly as fast as the berserker. It now scales with
## the individual and can never exceed the old value.
const LUNGE_FLOOR := 13.0
var speed := 3.4
var attack_range := 2.3
var shoot_range := 13.0
var windup_time := 0.55
var recover_time := 0.75
var body_color := Color(0.7, 0.25, 0.25)

var state: int = State.CHASE
var state_timer := 0.0
var attack_cd := 0.0
var dead := false
## Set by the room on spawn: the enemy holds still for this long first.
var grace := 0.0

var pending_lunge := false
var lunge_time := 0.0
var lunge_cd := 0.0
var lunge_dir := Vector3.ZERO

## Chill stacks: `slow_mult` multiplies movement speed until `slow_time` runs out.
var slow_mult := 1.0
var slow_time := 0.0

var _strafe_dir := 1.0
var _strafe_timer := 2.0

var visual: Node3D
var _body_mat: StandardMaterial3D
var _collision: CollisionShape3D
var _telegraph: MeshInstance3D
var _aura: MeshInstance3D
var _aura_mat: StandardMaterial3D
var _hp_root: Node3D
var _hp_front: MeshInstance3D
var _hp_front_mat: StandardMaterial3D
var _flash := 0.0
## Hit "pop": the visual is scaled by (1.0 + _pop) while this decays.
var _pop := 0.0
## Telegraph geometry, re-fitted every frame it is on screen.
var _telegraph_max := 1.0
var _telegraph_half_w := 1.2


func configure(body_target: Node3D, hp_value: float, dmg: float, spd: float,
		color: Color, enemy_type: int = Type.GRUNT,
		enemy_elite: int = Elite.NONE) -> void:
	type = enemy_type
	elite = enemy_elite
	target = body_target
	var data: Dictionary = TYPE_DATA[type]
	max_hp = hp_value
	hp = hp_value
	damage = dmg
	speed = spd
	body_color = color
	windup_time = float(data["windup"])
	recover_time = float(data["recover"])
	attack_range = float(data["range"])
	shoot_range = float(data["range"])

	if elite != Elite.NONE:
		var e: Dictionary = ELITE_DATA[elite]
		max_hp *= float(e["hp_mult"])
		hp = max_hp
		damage *= float(e["dmg_mult"])
		speed *= float(e["spd_mult"])
		windup_time *= float(e["windup_mult"])
		recover_time *= float(e["recover_mult"])
		if type != Type.ARCHER:
			attack_range *= float(e["range_mult"])
		else:
			shoot_range *= float(e["range_mult"])
		lunge_cd = float(e["dash_cd"])


func elite_name() -> String:
	return str(ELITE_DATA[elite]["name"]) if elite != Elite.NONE else ""


## Telegraph colour reads as threat at a glance: cyan for the ranged lane
## (archers and the Hexmaster), warm red for anything elite, blue for the
## rank and file.
func telegraph_color() -> Color:
	if elite == Elite.HEXMASTER or type == Type.ARCHER:
		return Color(0.3, 0.9, 1.0)
	if elite != Elite.NONE:
		return Color(1.0, 0.32, 0.16)
	return Color(0.3, 0.6, 1.0)


func type_scale() -> float:
	return float(TYPE_DATA[type]["scale"])


func elite_scale() -> float:
	return float(ELITE_DATA[elite]["scale"]) if elite != Elite.NONE else 1.0


func body_scale() -> float:
	return type_scale() * elite_scale()


## Movement speed with any active chill applied.
func eff_speed() -> float:
	return speed * slow_mult


## Ice Mage shards call this: `mult` 0.65 == 35% slower. The strongest chill
## wins and the timer is the longest one applied.
func apply_slow(mult: float, duration: float) -> void:
	if dead or duration <= 0.0:
		return
	slow_mult = minf(slow_mult, clampf(mult, 0.05, 1.0))
	slow_time = maxf(slow_time, duration)


func _ready() -> void:
	collision_layer = Combat.LAYER_ENEMY
	collision_mask = Combat.LAYER_WORLD | Combat.LAYER_PLAYER | Combat.LAYER_ENEMY

	var data: Dictionary = TYPE_DATA[type]
	var s := elite_scale()
	_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(data["radius"]) * s
	capsule.height = float(data["height"]) * s
	_collision.shape = capsule
	_collision.position = Vector3(0, float(data["height"]) * s / 2.0, 0)
	add_child(_collision)

	_build_visual()
	_build_telegraph()
	_build_aura()
	_build_hp_bar()
	_update_hp_bar()


func _physics_process(delta: float) -> void:
	if dead:
		return

	if slow_time > 0.0:
		slow_time -= delta
		if slow_time <= 0.0:
			slow_time = 0.0
			slow_mult = 1.0

	# Never let a body end up under the world: drag it back onto the floor.
	if global_position.y < FLOOR_Y:
		velocity = Vector3.ZERO
		var home := Vector3(0, 1.2, 0)
		if get_parent() is Node3D:
			home = (get_parent() as Node3D).to_global(home)
		global_position = home

	var dir_to_target := Vector3.ZERO
	var dist := 999.0
	if target != null and is_instance_valid(target):
		dir_to_target = target.global_position - global_position
		dir_to_target.y = 0.0
		dist = dir_to_target.length()

	attack_cd = maxf(0.0, attack_cd - delta)
	lunge_cd = maxf(0.0, lunge_cd - delta)

	if grace > 0.0:
		# Standing spawn-in: no AI and no telegraph until the room settles.
		grace -= delta
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
	else:
		_attack_ai(delta, dir_to_target, dist)

	if is_on_floor():
		velocity.y = -0.6
	else:
		velocity.y -= 26.0 * delta

	move_and_slide()


## The state machine, held off while an enemy is still materialising.
func _attack_ai(delta: float, dir_to_target: Vector3, dist: float) -> void:
	match state:
		State.CHASE:
			if type == Type.ARCHER:
				_archer_chase(delta, dir_to_target, dist)
			elif elite != Elite.NONE and _can_lunge(dist) and lunge_cd <= 0.0:
				pending_lunge = true
				_enter_windup(0.6)
			elif dist <= attack_range and attack_cd <= 0.0:
				_enter_windup()
			else:
				_move_towards(delta, dir_to_target, eff_speed())
		State.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, WINDUP_BRAKE * delta)
			velocity.z = move_toward(velocity.z, 0.0, WINDUP_BRAKE * delta)
			if dir_to_target.length_squared() > 0.001:
				var n := dir_to_target.normalized()
				rotation.y = lerp_angle(rotation.y, atan2(-n.x, -n.z), 6.0 * delta)
			state_timer -= delta
			if state_timer <= 0.0:
				if pending_lunge:
					pending_lunge = false
					_begin_lunge(dir_to_target)
				elif type == Type.ARCHER:
					_shoot(dist)
				else:
					_strike(dist, dir_to_target)
		State.LUNGE:
			velocity.x = lunge_dir.x * _lunge_speed()
			velocity.z = lunge_dir.z * _lunge_speed()
			if lunge_dir.length_squared() > 0.001:
				rotation.y = lerp_angle(rotation.y,
					atan2(-lunge_dir.x, -lunge_dir.z), 14.0 * delta)
			lunge_time -= delta
			if dist <= attack_range + 0.6:
				lunge_cd = _lunge_cooldown()
				_strike(dist, dir_to_target)
			elif lunge_time <= 0.0:
				lunge_cd = _lunge_cooldown()
				state = State.RECOVER
				state_timer = recover_time
		State.RECOVER:
			# A controlled skid, not a slide: at the old rate a lunge put the
			# body a whole room away from where it was aiming.
			velocity.x = move_toward(velocity.x, 0.0, LUNGE_BRAKE * delta)
			velocity.z = move_toward(velocity.z, 0.0, LUNGE_BRAKE * delta)
			state_timer -= delta
			if state_timer <= 0.0:
				state = State.CHASE


func _process(delta: float) -> void:
	if dead:
		return
	if state == State.WINDUP or state == State.LUNGE:
		_fit_telegraph()
	else:
		_telegraph.visible = false
	_telegraph_pulse(delta)
	_flash = maxf(0.0, _flash - delta)
	# Damage "pop": a quick punch of the silhouette that lands back on exactly
	# the base scale the frame the pop runs out.
	if _pop > 0.0:
		_pop = maxf(0.0, _pop - delta * 1.6)
		visual.scale = _base_scale() * (1.0 + _pop)
	var base := body_color
	if slow_time > 0.0:
		base = base.lerp(CHILL_COLOR, 0.7)
	if state == State.WINDUP:
		var t := 1.0 - state_timer / maxf(windup_time, 0.01)
		_body_mat.albedo_color = base.lerp(Color.WHITE, 0.15 + t * 0.35)
	elif _flash > 0.0:
		_body_mat.albedo_color = base.lerp(Color.WHITE, _flash / 0.12)
	else:
		_body_mat.albedo_color = base
	_update_hp_billboard()


func _can_lunge(dist: float) -> bool:
	if elite == Elite.NONE or not bool(ELITE_DATA[elite]["dash"]):
		return false
	return dist > attack_range * 0.6 and dist < 13.0


func _lunge_speed() -> float:
	return maxf(speed * 3.4, minf(LUNGE_FLOOR, speed * 5.0))


func _lunge_cooldown() -> float:
	return float(ELITE_DATA[elite]["dash_cd"]) if elite != Elite.NONE else 4.0


func _begin_lunge(dir: Vector3) -> void:
	lunge_dir = dir
	if lunge_dir.length_squared() < 0.001:
		lunge_dir = -global_transform.basis.z
	lunge_dir = Vector3(lunge_dir.x, 0, lunge_dir.z).normalized()
	lunge_time = 0.6
	state = State.LUNGE
	velocity.x = 0.0
	velocity.z = 0.0
	# Dropped an octave: the tell is visual, the voice is the weight behind it.
	Sfx.play_at("lunge", global_position, -5.0, 0.8, 0.05)
	FX.burst(get_tree().current_scene, global_position + Vector3(0, 0.4, 0),
		ELITE_DATA[elite]["aura"], 16, 0.12, 0.4, 4.0)
	# A committed elite lunge should rattle your teeth a little.
	if GameManager.opt_shake and target is Player:
		var p := target as Player
		if p.camera != null:
			p.camera.shake(0.28)


func _telegraph_pulse(delta: float) -> void:
	var mat := _telegraph.material_override as StandardMaterial3D
	if state == State.WINDUP or state == State.LUNGE:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		if mat != null:
			mat.albedo_color = Color(telegraph_color(), 0.22 + pulse * 0.2)
		if type == Type.BIG or type == Type.GRUNT:
			var squash := 1.0 + pulse * 0.06
			visual.scale = visual.scale.lerp(_base_scale() * squash, 12.0 * delta)
		elif _flash <= 0.0:
			visual.scale = visual.scale.lerp(_base_scale(), 10.0 * delta)
		return
	if mat != null and mat.albedo_color.a > 0.001:
		mat.albedo_color.a = lerpf(mat.albedo_color.a, 0.0, 12.0 * delta)
	if _flash <= 0.0 and (type == Type.BIG or type == Type.GRUNT):
		visual.scale = visual.scale.lerp(_base_scale(), 10.0 * delta)

	if elite != Elite.NONE and _aura != null and _aura_mat != null:
		var a := 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
		_aura_mat.albedo_color = Color(ELITE_DATA[elite]["aura"], maxf(0.15, a))


func _base_scale() -> Vector3:
	var s := body_scale()
	return Vector3(s, s, s)


func _move_towards(delta: float, dir_to_target: Vector3, spd: float) -> void:
	var d := dir_to_target
	if d.length_squared() > 0.001:
		d = d.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 9.0 * delta)
	else:
		d = Vector3.ZERO
	var wanted := d * spd
	var rate := _grip_rate(wanted, spd)
	velocity.x = move_toward(velocity.x, wanted.x, rate * delta)
	velocity.z = move_toward(velocity.z, wanted.z, rate * delta)


## Which rate this body should use to reach `wanted`: brake through a reversal
## or when coasting, accelerate when already heading the right way, and never
## slower than `spd` implies so fast types change their minds crisply too.
func _grip_rate(wanted: Vector3, spd: float) -> float:
	var vel := Vector3(velocity.x, 0.0, velocity.z)
	var rate := DECEL
	if wanted.length_squared() > 0.001 and \
			(vel.length_squared() < 0.01 or wanted.dot(vel) >= 0.0):
		rate = ACCEL
	return maxf(rate, spd * 6.0)


## Archers keep their distance, backing off when crowded and closing when too far.
func _archer_chase(delta: float, dir_to_target: Vector3, dist: float) -> void:
	if attack_cd <= 0.0 and dist <= shoot_range and dist >= 4.5:
		_enter_windup()
		return
	var d := dir_to_target
	if d.length_squared() < 0.001:
		return
	d = d.normalized()
	var spd := eff_speed()
	var wanted := Vector3.ZERO
	if dist < 7.0:
		wanted = -d * spd
	elif dist > 12.0:
		wanted = d * spd
	else:
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = 2.2
			_strafe_dir = -_strafe_dir
		var strafe := d.cross(Vector3.UP)
		wanted = strafe * spd * 0.55 * _strafe_dir
	velocity.x = move_toward(velocity.x, wanted.x, _grip_rate(wanted, spd) * delta)
	velocity.z = move_toward(velocity.z, wanted.z, _grip_rate(wanted, spd) * delta)
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 8.0 * delta)


func _enter_windup(time_scale: float = 1.0) -> void:
	state = State.WINDUP
	state_timer = windup_time * time_scale


func _shoot(dist: float) -> void:
	state = State.RECOVER
	state_timer = recover_time
	attack_cd = recover_time
	if dist > shoot_range + 3.0:
		return
	# Twang and release: the string, then the shaft. Layered rather than
	# sequential because an arrow only has one moment.
	Sfx.play_at("bow", global_position, -4.0)
	Sfx.play_at("shot", global_position, -10.0, 1.1, 0.06)
	var dir := -global_transform.basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = Vector3(0, 0, -1)
	else:
		dir = dir.normalized()

	var shots := 3 if elite == Elite.HEXMASTER else 1
	for i in shots:
		var spread := deg_to_rad(float(i - (shots - 1) * 0.5) * 15.0)
		_spawn_projectile(dir.rotated(Vector3.UP, spread))


func _spawn_projectile(dir: Vector3) -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	var shot := Projectile.new()
	shot.setup(dir, damage, target)
	parent_node.add_child(shot)
	shot.global_position = global_position + Vector3(0, 1.35, 0) + dir * 0.9


func _strike(dist: float, dir_to_target: Vector3) -> void:
	pending_lunge = false
	state = State.RECOVER
	state_timer = recover_time
	attack_cd = recover_time
	# Voiced at the top, not after the range check: the wind-up already
	# committed to the swing, and a swing that misses still makes a sound.
	Sfx.play_at("enemy_swing", global_position, -4.0)
	if target == null or not is_instance_valid(target):
		return
	if dist > attack_range + 0.8:
		return
	# Never land a hit on something that is not on the same floor as you.
	if absf(target.global_position.y - global_position.y) > HIT_Y_MAX:
		return
	if not target.has_method("apply_hit"):
		return
	var dir := dir_to_target
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = -global_transform.basis.z
	else:
		dir = dir.normalized()
	var knock := 5.0 + (6.0 if type == Type.BIG else 0.0)
	if elite != Elite.NONE:
		knock += 6.0
	target.call("apply_hit", damage, dir, knock, ArenaMemory.CAUSE_MELEE)
	if target is Player:
		var p := target as Player
		FX.burst(get_tree().current_scene, p.global_position + Vector3(0, 1.1, 0),
			Color(1.0, 0.35, 0.15), 22, 0.12, 0.45, 5.5)


## Returns the damage actually dealt so the player can charge the super ability.
## `source` tags the hit so the Arena can file it by cause; anything untagged
## (or tagged as a straight player attack) counts toward damage dealt.
func apply_hit(amount: float, dir: Vector3, knockback: float = 0.0,
		source: String = "") -> float:
	if dead:
		return 0.0
	var dealt := minf(amount, hp)
	hp -= dealt
	# Traps tag their hits (CAUSE_TRAP); the player's attacks arrive untagged.
	if dealt > 0.0 and source == "":
		GameManager.damage_dealt += dealt
	_flash = 0.12
	if dealt > 0.0:
		_pop = 0.14
	if dir.length_squared() > 0.01 and knockback > 0.0:
		var push := dir.normalized() * knockback
		velocity.x += push.x
		velocity.z += push.z
	FX.burst(get_tree().current_scene, global_position + Vector3(0, 1.0, 0),
		Color(1.0, 0.5, 0.15), 20, 0.11, 0.45, 5.5)
	# The player's attacks voice themselves from the attacker's side (see
	# Player.announce_hit), so this branch only covers things that strike from
	# outside a swing - traps, mostly.
	if dealt > 0.0 and source != "":
		Sfx.play_at("hit", global_position, -6.0)
	# A big body takes a hit differently from a small one, and it should sound
	# like it even while the character's own hit is doing the talking. Kept
	# quiet so it reads as weight underneath the punch, not as a second event.
	if dealt > 0.0 and (type == Type.BIG or elite != Elite.NONE):
		Sfx.play_at("hit_heavy", global_position, -10.0, 0.9, 0.08)
	_update_hp_bar()
	if dealt > 0.0:
		Combat.pop_number(get_tree().current_scene,
			global_position + Vector3(0, 1.75 * body_scale(), 0), dealt,
			Color(1.0, 0.85, 0.3) if hp <= 0.0 else Color.WHITE)
	if hp <= 0.0:
		_die()
	return dealt


func _die() -> void:
	if dead:
		return
	dead = true
	state = State.DEAD
	collision_layer = 0
	# An elite going down is a bigger event than a grunt going down, and it
	# should sound like one even when a crowd of them falls on the same frame.
	Sfx.play_at("kill_elite" if elite != Elite.NONE else "kill",
		global_position, 0.0, 1.0, 0.12)
	call_deferred("_disable_collision")
	GameManager.add_kill()
	if elite != Elite.NONE:
		GameManager.elites_killed += 1
		_drop_orb()
	died.emit(self)
	if GameManager.opt_shake and target is Player:
		var p := target as Player
		if p.camera != null:
			p.camera.shake(0.12)
	var scene := get_tree().current_scene
	if elite != Elite.NONE:
		# Elites get the full package: a wide shockwave in their own aura colour.
		FX.impact(scene, global_position + Vector3(0, 1.0, 0),
			Color(ELITE_DATA[elite]["aura"]), 8.0)
	else:
		FX.burst(scene, global_position + Vector3(0, 1.0, 0), Color(1.0, 0.42, 0.1),
			45, 0.15, 0.7, 8.5)
	FX.ring(scene, global_position + Vector3(0, 0.2, 0),
		Color(ELITE_DATA[elite]["aura"]) if elite != Elite.NONE else Color(1.0, 0.5, 0.15),
		4.0 if elite != Elite.NONE else 2.0, 0.4)
	if _hp_root != null:
		_hp_root.visible = false
	if _telegraph != null:
		_telegraph.visible = false
	if _aura != null:
		_aura.visible = false
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(0.05, 0.05, 0.05), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "visible", false, 0.05)
	tw.tween_callback(queue_free)


## Elites leave a recovery mote behind: it drifts, magnetises, and only
## resolves once you actually need health (never wasted on a full bar).
func _drop_orb() -> void:
	if elite == Elite.NONE:
		# Recovery motes are an elite's tribute - the rank and file drop nothing.
		return
	var parent_node := get_parent()
	if parent_node == null or not (parent_node is Node3D):
		return
	var orb := HealthOrb.new()
	if target is Player:
		orb.player = target as Player
	parent_node.add_child(orb)
	orb.global_position = global_position + Vector3(0, 0.9, 0)


func _disable_collision() -> void:
	if _collision != null and is_instance_valid(_collision):
		_collision.disabled = true


# --------------------------------------------------------------- visuals ----

func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)

	_body_mat = Util.make_material(body_color, 0.7, 0.05)
	var wide := 1.0
	if type == Type.BIG:
		wide = 1.45
	elif type == Type.FAST:
		wide = 0.78

	Util.add_box(visual, Vector3(0.85 * wide, 1.0, 0.6 * wide), Vector3(0, 0.95, 0),
		_body_mat, 0.05)
	Util.add_box(visual, Vector3(0.62 * wide, 0.5, 0.52 * wide), Vector3(0, 1.65, 0),
		_body_mat, 0.05)
	Util.add_box(visual, Vector3(0.2 * wide, 0.7, 0.2), Vector3(-0.55 * wide, 1.0, 0),
		_body_mat, 0.04)
	Util.add_box(visual, Vector3(0.2 * wide, 0.7, 0.2), Vector3(0.55 * wide, 1.0, 0),
		_body_mat, 0.04)
	Util.add_box(visual, Vector3(0.26 * wide, 0.45, 0.26), Vector3(-0.2, 0.22, 0),
		_body_mat, 0.04)
	Util.add_box(visual, Vector3(0.26 * wide, 0.45, 0.26), Vector3(0.2, 0.22, 0),
		_body_mat, 0.04)

	var eye := Util.make_material(Color(1.0, 0.2, 0.1), 0.3, 0.0, Color(1.0, 0.15, 0.05), 3.0)
	if type == Type.ARCHER:
		eye = Util.make_material(Color(0.4, 0.8, 1.0), 0.3, 0.0, Color(0.3, 0.7, 1.0), 3.0)
	Util.add_box(visual, Vector3(0.16, 0.1, 0.06), Vector3(-0.15, 1.7, -0.27), eye)
	Util.add_box(visual, Vector3(0.16, 0.1, 0.06), Vector3(0.15, 1.7, -0.27), eye)

	match type:
		Type.FAST:
			Util.add_cone(visual, 0.2, 0.55, Vector3(0, 2.05, 0), _body_mat, 0.03)
			Util.add_box(visual, Vector3(0.1, 0.5, 0.1), Vector3(0, 1.1, -0.32),
				Util.make_material(Color(0.75, 1.0, 0.85), 0.5, 0.2), 0.02)
		Type.BIG:
			Util.add_box(visual, Vector3(0.5, 0.4, 0.5), Vector3(-0.62, 1.5, 0), _body_mat, 0.05)
			Util.add_box(visual, Vector3(0.5, 0.4, 0.5), Vector3(0.62, 1.5, 0), _body_mat, 0.05)
			Util.add_cone(visual, 0.3, 1.1, Vector3(0.75, 1.2, -0.7),
				Util.make_material(Color(0.45, 0.3, 0.25), 0.8, 0.1), 0.03)
		Type.ARCHER:
			Util.add_box(visual, Vector3(0.08, 1.0, 0.08), Vector3(-0.5, 1.1, -0.5),
				Util.make_material(Color(0.7, 0.55, 0.3), 0.7, 0.1), 0.02)
			Util.add_box(visual, Vector3(0.06, 0.7, 0.06), Vector3(-0.5, 1.1, -0.5),
				Util.make_material(Color(0.85, 0.9, 1.0), 0.4, 0.2), 0.02)
			Util.add_box(visual, Vector3(0.7, 0.2, 0.6), Vector3(0, 1.9, 0.06),
				Util.make_material(Color(0.2, 0.2, 0.28), 0.9, 0.0), 0.03)

	if elite != Elite.NONE:
		_build_elite_decor()

	visual.scale = _base_scale()


func _build_elite_decor() -> void:
	var horn := Util.make_material(Color(0.95, 0.9, 0.7), 0.35, 0.6,
		Color(ELITE_DATA[elite]["aura"]), 1.4)
	Util.add_cone(visual, 0.12, 0.5, Vector3(-0.2, 2.0, 0.0), horn, 0.03)
	Util.add_cone(visual, 0.12, 0.5, Vector3(0.2, 2.0, 0.0), horn, 0.03)
	Util.add_cone(visual, 0.1, 0.34, Vector3(0.0, 2.05, -0.15), horn, 0.03)
	# shoulder spikes sell the silhouette
	for side in [-1.0, 1.0]:
		Util.add_cone(visual, 0.14, 0.6, Vector3(side * 0.5, 1.55, 0.0), horn, 0.03)


## Colour-coded, low-opacity box showing exactly where this enemy's attack
## will land: blue for the rank and file, cyan for shooters, warm red for
## elites. Depth-tested so it can never bleed through a solid wall, and
## clipped to the room interior (see _fit_telegraph) so it cannot show
## through the doorway or the closed barrier either.
func _build_telegraph() -> void:
	_telegraph = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var forward := 0.0
	var width := 2.4
	if type == Type.ARCHER:
		forward = shoot_range
		width = 1.4 if elite == Elite.NONE else 2.2
	else:
		forward = attack_range
		width = 3.0 if type == Type.BIG else 2.4
	var s := body_scale()
	_telegraph_max = maxf(forward, 0.1)
	_telegraph_half_w = width * s * 0.5
	mesh.size = Vector3(width * s, 1.7 * s, _telegraph_max)
	_telegraph.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(telegraph_color(), 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_telegraph.material_override = mat
	_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph.position = Vector3(0, 1.0 * s, -(_telegraph_max * 0.5 + Room.TELEGRAPH_LEAD))
	_telegraph.visible = false
	add_child(_telegraph)


## Re-fits the box every frame it is on screen. The mesh is built at its
## maximum reach and only scaled / slid, so this costs a handful of floats.
## Horizontal: clipped to the room interior (walls, doorway, barrier).
## Vertical: pinned to the floor and held under the ceiling.
func _fit_telegraph() -> void:
	if _telegraph == null:
		return
	var s := body_scale()
	var fitted := _telegraph_max
	var cy := 1.0 * s
	var ky := 1.0
	var room := get_parent()
	if room is Room:
		var r := room as Room
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.0001:
			fwd = fwd.normalized()
			fitted = r.clamp_attack_box(global_position, fwd,
				_telegraph_max, _telegraph_half_w)
		var p_y := r.to_local(global_position).y
		var box_h := 1.7 * s
		var lo := Room.WALL_PAD
		var hi := minf(lo + box_h, Room.HEIGHT - Room.WALL_PAD)
		ky = clampf((hi - lo) / maxf(box_h, 0.001), 0.05, 1.0)
		# Solved so the box always lands on exactly [lo, hi] in room space,
		# whatever height the enemy happens to be standing at.
		cy = (lo + hi) * 0.5 - p_y
	fitted = clampf(fitted, 0.0, _telegraph_max)
	if fitted <= 0.35:
		_telegraph.visible = false
		return
	_telegraph.visible = true
	_telegraph.scale = Vector3(1.0, ky, fitted / _telegraph_max)
	_telegraph.position = Vector3(0, cy, -(fitted * 0.5 + Room.TELEGRAPH_LEAD))


func _build_aura() -> void:
	_aura = null
	_aura_mat = null
	if elite == Elite.NONE:
		return
	_aura = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.35 * elite_scale()
	disc.bottom_radius = 1.35 * elite_scale()
	disc.height = 0.08
	_aura.mesh = disc
	_aura_mat = StandardMaterial3D.new()
	_aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_mat.albedo_color = Color(ELITE_DATA[elite]["aura"], 0.35)
	_aura_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aura_mat.no_depth_test = false
	_aura.material_override = _aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.position = Vector3(0, 0.06, 0)
	add_child(_aura)


func _build_hp_bar() -> void:
	_hp_root = Node3D.new()
	var bar_w := BAR_WIDTH * (1.9 if elite != Elite.NONE else 1.0)
	_hp_root.position = Vector3(0, 2.45 * body_scale(), 0)
	add_child(_hp_root)

	var back := QuadMesh.new()
	back.size = Vector2(bar_w, 0.16 if elite != Elite.NONE else 0.13)
	var back_mi := MeshInstance3D.new()
	back_mi.mesh = back
	back_mi.material_override = _bar_material(Color(0.05, 0.05, 0.07, 0.9))
	_hp_root.add_child(back_mi)

	var front := QuadMesh.new()
	front.size = Vector2(bar_w, 0.12 if elite != Elite.NONE else 0.1)
	_hp_front = MeshInstance3D.new()
	_hp_front.mesh = front
	_hp_front_mat = _bar_material(Color(0.3, 0.95, 0.4))
	_hp_front.material_override = _hp_front_mat
	_hp_root.add_child(_hp_front)
	_hp_root.set_meta("bar_w", bar_w)

	if elite != Elite.NONE:
		# Elites sign their work: the name rides above the bar in their colour.
		var tag := Label3D.new()
		tag.text = elite_name()
		tag.font_size = 44
		tag.pixel_size = 0.005  # 44px * 0.005 == 0.22 world units tall
		# Godot 4.7 renamed Label3D's colours: the glyph tint is `modulate`
		# and the outline tint is `outline_modulate`.
		tag.modulate = Color(ELITE_DATA[elite]["aura"])
		tag.outline_size = 10
		tag.outline_modulate = Color(0.02, 0.02, 0.04, 0.9)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tag.position = Vector3(0, 0.24, 0)
		_hp_root.add_child(tag)


func _bar_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _update_hp_bar() -> void:
	if _hp_front == null:
		return
	var bar_w := float(_hp_root.get_meta("bar_w", BAR_WIDTH))
	var pct := clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	_hp_front.scale.x = maxf(pct, 0.001)
	_hp_front.position.x = bar_w * (pct - 1.0) * 0.5
	var good := Color(1.0, 0.75, 0.2) if elite != Elite.NONE else Color(0.3, 0.95, 0.4)
	_hp_front_mat.albedo_color = good.lerp(Color(0.95, 0.2, 0.15), 1.0 - pct)


func _update_hp_billboard() -> void:
	if _hp_root == null or not _hp_root.visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - _hp_root.global_position
	if to_cam.length_squared() < 0.0001:
		return
	if absf(to_cam.normalized().dot(Vector3.UP)) > 0.97:
		return
	_hp_root.look_at(cam.global_position, Vector3.UP)
