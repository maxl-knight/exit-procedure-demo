class_name TheCreator
extends CharacterBody3D

signal died
signal phase_changed(label: String, detail: String)

## The Arena's central intelligence, waiting at the top of the Core Perimeter.
## It is untouchable while its summons live - kill them all and it drops its
## guard long enough to be hurt. It has watched every reconstruction, so it
## opens with a line built from how many times you have already died.

enum S { INTRO, SUMMON, STUN, PHASE2_INTRO, CLONE, FINAL, DEAD }

const MAX_HP := 1600.0
const STUN_TIME := 5.0
const STUNS_BEFORE_PHASE2 := 2

var target: Player
var max_hp := MAX_HP
var hp := MAX_HP
var state: int = S.INTRO
var state_timer := 2.4
var invulnerable := true
var stuns_done := 0
var dead := false

var adds: Array = []
var clone: PlayerClone

var _shoot_cd := 3.0
var _visual: Node3D
var _body_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _collision: CollisionShape3D
var _time := 0.0
var _hurt_flash := 0.0
var _add_count := 3


func _ready() -> void:
	collision_layer = Combat.LAYER_ENEMY
	collision_mask = Combat.LAYER_WORLD

	_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.9
	capsule.height = 4.6
	_collision.shape = capsule
	_collision.position = Vector3(0, 2.3, 0)
	add_child(_collision)

	_build_visual()
	_emit_phase("THE CORE", "Kill its summons to break its guard")


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	_body_mat = Util.make_material(Color(0.94, 0.93, 0.97), 0.35, 0.1)
	Util.add_cone(_visual, 1.5, 3.4, Vector3(0, 1.7, 0), _body_mat, 0.06)
	Util.add_box(_visual, Vector3(1.5, 0.9, 0.85), Vector3(0, 3.5, 0),
		Util.make_material(Color(0.97, 0.96, 1.0), 0.4, 0.05), 0.06)
	Util.add_sphere(_visual, 0.62, Vector3(0, 4.4, 0),
		Util.make_material(Color(0.98, 0.97, 1.0), 0.3, 0.0), 0.05)

	var gold := Util.make_material(Color(0.95, 0.78, 0.25), 0.25, 0.85,
		Color(1.0, 0.85, 0.3), 0.8)
	# Crown
	for i in 7:
		var a := TAU * float(i) / 7.0
		Util.add_cone(_visual, 0.11, 0.55,
			Vector3(cos(a) * 0.45, 5.05, sin(a) * 0.45), gold, 0.03)
	Util.add_box(_visual, Vector3(1.05, 0.16, 1.05), Vector3(0, 4.78, 0), gold, 0.04)

	# Shoulder plates
	for side in [-1.0, 1.0]:
		Util.add_box(_visual, Vector3(0.7, 0.35, 0.7), Vector3(side * 0.95, 3.9, 0),
			gold, 0.05)

	# Face - two burning eyes
	var eye := Util.make_material(Color(1.0, 0.9, 0.4), 0.2, 0.0, Color(1.0, 0.85, 0.3), 5.0)
	Util.add_sphere(_visual, 0.13, Vector3(-0.22, 4.45, -0.55), eye)
	Util.add_sphere(_visual, 0.13, Vector3(0.22, 4.45, -0.55), eye)

	# Halo
	_halo = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.92
	_halo.mesh = torus
	var hm := Util.make_material(Color(1.0, 0.9, 0.45), 0.2, 0.0,
		Color(1.0, 0.88, 0.4), 3.0)
	_halo.material_override = hm
	_halo.position = Vector3(0, 5.4, 0)
	_halo.rotation.x = PI / 2.0
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_halo)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_time += delta
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if _body_mat != null:
		var base := Color(0.94, 0.93, 0.97)
		_body_mat.albedo_color = base.lerp(Color(1.0, 0.3, 0.25), _hurt_flash / 0.12) \
			if _hurt_flash > 0.0 else base

	if _halo != null:
		_halo.position.y = 5.4 + sin(_time * 1.4) * 0.18
		_halo.rotation.y += delta * 1.2
	_visual.position.y = sin(_time * 1.1) * 0.12

	_prune_adds()

	match state:
		S.INTRO:
			state_timer -= delta
			if state_timer <= 0.0:
				_start_summon()
		S.SUMMON:
			_shoot_cd -= delta
			if _shoot_cd <= 0.0:
				_shoot_cd = 3.4
				_shoot()
			if adds.is_empty():
				_enter_stun()
		S.STUN:
			# Slump while vulnerable.
			_visual.rotation.z = lerp_angle(_visual.rotation.z, 0.45, 3.0 * delta)
			state_timer -= delta
			if state_timer <= 0.0:
				stuns_done += 1
				if stuns_done >= STUNS_BEFORE_PHASE2 or hp <= max_hp * 0.55:
					_enter_phase2()
				else:
					_start_summon()
		S.PHASE2_INTRO:
			state_timer -= delta
			if state_timer <= 0.0:
				_spawn_clone()
		S.CLONE:
			if clone == null or not is_instance_valid(clone) or clone.dead:
				clone = null
				invulnerable = false
				state = S.FINAL
				_emit_phase("THE CORE IS EXPOSED", "Finish it")
		S.FINAL:
			pass

	if is_on_floor():
		velocity.y = -0.6
	else:
		velocity.y -= 26.0 * delta
	# Drift slowly toward the back of the arena while untouchable.
	if state == S.SUMMON or state == S.INTRO:
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
	move_and_slide()


# ------------------------------------------------------------- damage --------

## Combat.damage_sphere routes player hits here.
func apply_hit(amount: float, _dir: Vector3 = Vector3.ZERO,
		_knockback: float = 0.0) -> float:
	return take_damage(amount)


func take_damage(amount: float) -> float:
	if not is_vulnerable():
		# A hit the Core refuses: it should sound like striking a closed door,
		# not like a hit that quietly failed to happen.
		Sfx.play_at("shield", global_position + Vector3(0, 3.0, 0), -3.0, 1.1, 0.06)
		FX.burst(get_tree().current_scene, global_position + Vector3(0, 3.0, 0),
			Color(0.5, 0.7, 1.0), 12, 0.1, 0.3, 3.0)
		return 0.0
	var dealt := minf(amount, hp)
	hp -= dealt
	if dealt > 0.0:
		GameManager.damage_dealt += dealt
	_hurt_flash = 0.12
	FX.burst(get_tree().current_scene, global_position + Vector3(0, 3.0, 0),
		Color(1.0, 0.85, 0.4), 26, 0.13, 0.5, 7.0)
	if dealt > 0.0:
		Combat.pop_number(get_tree().current_scene,
			global_position + Vector3(0, 5.6, 0), dealt,
			Color(1.0, 0.85, 0.3) if hp <= 0.0 else Color.WHITE, 1.4)
	if hp <= 0.0:
		hp = 0.0
		_die()
	return dealt


func is_vulnerable() -> bool:
	return not invulnerable and not dead


func state_label() -> String:
	match state:
		S.INTRO:
			return "THE CORE"
		S.SUMMON:
			return "SUMMONING"
		S.STUN:
			return "STUNNED"
		S.PHASE2_INTRO:
			return "PHASE II"
		S.CLONE:
			return "THE CLONE"
		S.FINAL:
			return "EXPOSED"
	return ""


func adds_alive() -> int:
	var n := 0
	for a in adds:
		if a != null and is_instance_valid(a) and not a.dead:
			n += 1
	return n


# -------------------------------------------------------------- summons ------

func _prune_adds() -> void:
	for i in range(adds.size() - 1, -1, -1):
		var a = adds[i]
		if a == null or not is_instance_valid(a):
			adds.remove_at(i)


func _start_summon() -> void:
	state = S.SUMMON
	invulnerable = true
	_visual.rotation.z = 0.0
	_shoot_cd = 1.6
	_emit_phase("THE CORE", "Invincible - kill its summons")
	var n := 3 + stuns_done
	_add_count = n
	for i in n:
		_spawn_add(i, n)


func _spawn_add(index: int, total: int) -> void:
	var parent_node := get_parent()
	if parent_node == null or target == null:
		return
	var settings: Dictionary = GameManager.settings()
	var elite_kind: int = Enemy.Elite.NONE
	# Roughly a quarter of the summons are an elite, and the last one before
	# phase 2 is always allowed to be one.
	var elite_chance := 0.25 + 0.15 * stuns_done
	if index == total - 1 and randf() < elite_chance + 0.25:
		elite_kind = Enemy.ELITE_KINDS[randi() % Enemy.ELITE_KINDS.size()]
	elif randf() < elite_chance:
		elite_kind = Enemy.ELITE_KINDS[randi() % Enemy.ELITE_KINDS.size()]

	var base_type: int = Enemy.Type.GRUNT
	match randi() % 4:
		0:
			base_type = Enemy.Type.GRUNT
		1:
			base_type = Enemy.Type.FAST
		2:
			base_type = Enemy.Type.ARCHER
		3:
			base_type = Enemy.Type.BIG
	if elite_kind == Enemy.Elite.HEXMASTER:
		base_type = Enemy.Type.ARCHER
	elif elite_kind == Enemy.Elite.JUGGERNAUT:
		base_type = Enemy.Type.BIG

	var td: Dictionary = Enemy.TYPE_DATA[base_type]
	# Same 40 HP baseline as EnemyFactory.room_cfg: one number, two fights.
	var hp_v: float = 40.0 * float(td["hp_mult"]) * float(settings["hp_mult"])
	var dmg: float = 8.0 * float(td["dmg_mult"]) * float(settings["dmg_mult"])
	var spd: float = 3.4 * float(td["spd_mult"]) * float(settings["speed_mult"])
	var color := Room.enemy_color(base_type, elite_kind)

	var pos := _summon_position(index, total)
	var add := EnemyFactory.spawn(parent_node, target, pos,
		{"hp": hp_v, "dmg": dmg, "spd": spd, "color": color,
			"type": base_type, "elite": elite_kind})
	adds.append(add)
	# Every add lands as a little jolt; a bigger wave shakes harder.
	_shake_player(0.06)


func _summon_position(index: int, total: int) -> Vector3:
	# Positions are relative to the arena the boss is standing in.
	var center := Vector3(global_position.x, 0.0, global_position.z)
	var angle := TAU * float(index) / float(maxi(total, 1))
	var radius := 6.5 + randf() * 2.5
	var p := center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	p.y = 0.05
	p.x = clampf(p.x, center.x - 8.5, center.x + 8.5)
	p.z = clampf(p.z, center.z - 8.5, center.z + 8.5)
	return p


func _enter_stun() -> void:
	state = S.STUN
	invulnerable = false
	state_timer = STUN_TIME
	_emit_phase("THE CORE IS STUNNED", "Hit it now - %.0fs" % STUN_TIME)
	FX.ring(get_tree().current_scene, global_position + Vector3(0, 0.2, 0),
		Color(1.0, 0.85, 0.35), 7.0, 0.6)
	FX.burst(get_tree().current_scene, global_position + Vector3(0, 3.0, 0),
		Color(1.0, 0.9, 0.5), 70, 0.18, 0.8, 12.0)
	FX.hitstop(0.08)
	_shake_player(0.24)


func _enter_phase2() -> void:
	state = S.PHASE2_INTRO
	invulnerable = true
	state_timer = 2.2
	_visual.rotation.z = 0.0
	_emit_phase("PHASE II", "It built a copy of your combat record")
	FX.burst(get_tree().current_scene, global_position + Vector3(0, 3.5, 0),
		Color(1.0, 0.3, 0.6), 120, 0.2, 1.0, 16.0)
	FX.hitstop(0.08)
	_shake_player(0.34)


func _spawn_clone() -> void:
	state = S.CLONE
	invulnerable = true
	if target == null or get_parent() == null:
		return
	clone = PlayerClone.new()
	clone.setup_clone(target)
	get_parent().add_child(clone)
	var offset := Vector3(4.0, 0.05, -3.0)
	clone.global_position = target.global_position + offset
	if clone.global_position.y < 0.05:
		clone.global_position.y = 0.05
	_emit_phase("THE CLONE", "Your record, walking. Same health, same moves.")
	FX.burst(get_tree().current_scene, clone.global_position + Vector3(0, 1.0, 0),
		Color(1.0, 0.3, 0.6), 60, 0.16, 0.7, 9.0)


# ---------------------------------------------------------------- attacks ----

func _shoot() -> void:
	if target == null or not is_instance_valid(target):
		return
	var dir := target.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	var shot := Projectile.new()
	shot.setup(dir, 12.0 * float(GameManager.settings()["dmg_mult"]), target)
	shot.scale_factor = 1.6
	get_parent().add_child(shot)
	shot.global_position = global_position + Vector3(0, 4.2, 0) + dir * 1.4
	FX.burst(get_tree().current_scene, shot.global_position, Color(1.0, 0.85, 0.4),
		16, 0.1, 0.35, 4.0)


func _emit_phase(label: String, detail: String) -> void:
	phase_changed.emit(label, detail)


## The player feels every turn of this fight - if they have shake enabled.
func _shake_player(amount: float) -> void:
	if not GameManager.opt_shake or target == null or not is_instance_valid(target):
		return
	if target.camera != null:
		target.camera.shake(amount)


func _die() -> void:
	if dead:
		return
	dead = true
	state = S.DEAD
	collision_layer = 0
	# Underneath the victory sting: something very large coming apart.
	Sfx.play_at("kill_elite", global_position + Vector3(0, 2.5, 0), 2.0, 0.7, 0.05)
	call_deferred("_disable_collision")
	if clone != null and is_instance_valid(clone):
		clone.queue_free()
		clone = null
	for a in adds:
		if a != null and is_instance_valid(a) and not a.dead:
			a.queue_free()
	adds.clear()
	died.emit()
	var scene := get_tree().current_scene
	FX.burst(scene, global_position + Vector3(0, 2.5, 0), Color(1.0, 0.9, 0.5), 200, 0.22, 1.4, 18.0)
	# One last shockwave through the floor, and the clock stutters.
	FX.impact(scene, global_position + Vector3(0, 2.5, 0), Color(1.0, 0.9, 0.5), 9.0)
	FX.ring(scene, global_position + Vector3(0, 0.2, 0), Color(1.0, 0.9, 0.4), 14.0, 1.2)
	FX.hitstop(0.12, 0.03)
	if _visual != null:
		var tw := create_tween()
		tw.tween_property(_visual, "scale", Vector3(1.4, 0.02, 1.4), 1.1) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(_visual, "visible", false, 0.1)
		tw.tween_callback(queue_free)


func _disable_collision() -> void:
	if _collision != null and is_instance_valid(_collision):
		_collision.disabled = true
