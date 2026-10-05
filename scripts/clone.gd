class_name PlayerClone
extends Enemy

## The Core's phase-2 trick: a mirror of you. Same health, same speed, same
## punch reach, and it will dash, whirl and heal exactly the way you do.

var player_target: Player
var _ranged := false
var _clone_character := 0
var _clone_has_model := false

## The clone wears your character model, so it runs the same rig.
var _clone_anim: AnimationPlayer
var _clone_model_anim := ""
var _clone_attack_t := 0.0
var _clone_attack_len := 0.45

var _clone_max_hp := 100.0
var _attack_cd := 0.0
var _dash_cd := 0.0
var _super := 100.0
var _heal_cd := 8.0
var _dash_time := 0.0
var _dash_dir := Vector3.ZERO
var _unique_cd := 3.0
var _spin_tween: Tween
var _arm_pivot: Node3D
var _trail_accum := 0.0


func setup_clone(p: Player) -> void:
	player_target = p
	_clone_max_hp = p.max_health_now()
	configure(p, _clone_max_hp, p.damage_now(), p.move_speed_now() * 0.97,
		Color(0.9, 0.2, 0.45), Type.GRUNT, Elite.NONE)
	attack_range = p.attack_range_now()
	_clone_character = p.character_type
	# A frost mirror shoots instead of swinging.
	_ranged = p.character_type == Player.CHAR_ICE_MAGE


func _ready() -> void:
	super()
	# The clone mirrors your silhouette instead of the blocky grunt body.
	var old: Array = []
	for child in visual.get_children():
		old.append(child)
	for child in old:
		child.free()
	_build_clone_visual()
	# Over the authored model the bar sits just over the head, not over a
	# body the clone no longer has.
	_hp_root.position.y = 1.95 if _clone_has_model else 2.45 * body_scale()
	_update_hp_bar()


func _build_clone_visual() -> void:
	# The flinch tint below writes straight into this even when the model
	# ends up carrying the look.
	_body_mat = Util.make_material(Color(0.9, 0.18, 0.42), 0.5, 0.2)

	# The Core's copy wears your body, drenched in its colour, so the fight
	# reads as you against you.
	var wrap := CharacterModels.build(visual, _clone_character)
	if wrap != null:
		_clone_has_model = true
		CharacterModels.tint(wrap, Color(1.0, 0.3, 0.48))
		_clone_anim = CharacterModels.animation_player(wrap)
		_clone_attack_len = CharacterModels.prime(_clone_anim)
		if _clone_anim != null:
			_clone_model_anim = "Idle"
			_clone_anim.play("Idle")
		visual.scale = _base_scale()
		return

	var base := Color(0.9, 0.18, 0.42)
	var accent := Color(0.18, 0.02, 0.08)
	Util.add_capsule(visual, 0.45, 1.8, Vector3(0, 0.9, 0), _body_mat, 0.05)
	Util.add_sphere(visual, 0.3, Vector3(0, 1.95, 0),
		Util.make_material(accent, 0.7, 0.1), 0.04)

	var eye := Util.make_material(Color(1.0, 0.85, 0.9), 0.2, 0.0, Color(1.0, 0.2, 0.5), 2.6)
	Util.add_sphere(visual, 0.07, Vector3(-0.13, 2.0, -0.26), eye)
	Util.add_sphere(visual, 0.07, Vector3(0.13, 2.0, -0.26), eye)

	Util.add_box(visual, Vector3(0.22, 0.3, 0.22), Vector3(-0.18, 0.16, 0),
		Util.make_material(accent, 0.7, 0.1), 0.03)
	Util.add_box(visual, Vector3(0.22, 0.3, 0.22), Vector3(0.18, 0.16, 0),
		Util.make_material(accent, 0.7, 0.1), 0.03)

	_arm_pivot = Node3D.new()
	_arm_pivot.position = Vector3(0.42, 1.3, 0.0)
	visual.add_child(_arm_pivot)
	Util.add_box(_arm_pivot, Vector3(0.14, 0.14, 0.5), Vector3(0, 0, -0.2),
		Util.make_material(accent, 0.7, 0.1), 0.03)
	Util.add_sphere(_arm_pivot, 0.19, Vector3(0, 0, -0.52),
		Util.make_material(base, 0.5, 0.2), 0.03)

	# A dark crown marks it as the Core's puppet.
	var crown := Util.make_material(Color(0.15, 0.1, 0.2), 0.4, 0.7,
		Color(1.0, 0.3, 0.6), 1.2)
	for x in [-0.18, 0.0, 0.18]:
		Util.add_cone(visual, 0.07, 0.3, Vector3(x, 2.22, 0.0), crown, 0.02)

	visual.scale = _base_scale()


func _physics_process(delta: float) -> void:
	if dead:
		return

	var dir := Vector3.ZERO
	var dist := 999.0
	if player_target != null and is_instance_valid(player_target):
		dir = player_target.global_position - global_position
		dir.y = 0.0
		dist = dir.length()

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_heal_cd = maxf(0.0, _heal_cd - delta)
	_unique_cd = maxf(0.0, _unique_cd - delta)
	_super = minf(200.0, _super + 6.0 * delta)

	# Same defensive instincts as the human player.
	if hp < _clone_max_hp * 0.35 and _heal_cd <= 0.0 and dist > 5.0:
		_heal_cd = 16.0
		_do_heal()
	elif _super >= 200.0 and dist < 7.0 and _unique_cd <= 0.0:
		_unique_cd = 6.0
		_super = 0.0
		_do_super(dist, dir)
	elif _dash_cd <= 0.0 and dist > 6.0 and dist < 16.0:
		_dash_cd = 4.5
		_start_dash(dir)
	elif _attack_cd <= 0.0 and dist <= attack_range:
		if _ranged:
			_shoot_bolt(dir)
		else:
			_do_punch(dist, dir)
	else:
		_move_towards(delta, dir, eff_speed() if _dash_time <= 0.0 else 0.0)

	if _dash_time > 0.0:
		_dash_time -= delta
		velocity.x = _dash_dir.x * 20.0
		velocity.z = _dash_dir.z * 20.0
		_trail_accum += delta
		if _trail_accum >= 0.06:
			_trail_accum = 0.0
			FX.burst(get_tree().current_scene, global_position + Vector3(0, 0.9, 0),
				Color(1.0, 0.3, 0.55), 7, 0.08, 0.3, 2.5)
		if _dash_time <= 0.0 and dist <= attack_range and not _ranged:
			_do_punch(dist, dir)

	if is_on_floor():
		velocity.y = -0.6
	else:
		velocity.y -= 26.0 * delta

	_clone_animate(delta)
	move_and_slide()
	_flash = maxf(0.0, _flash - delta)
	var base := body_color
	if slow_time > 0.0:
		base = base.lerp(CHILL_COLOR, 0.7)
	_body_mat.albedo_color = base.lerp(Color.WHITE, _flash / 0.12) if _flash > 0.0 \
		else base
	if _hp_root != null and _hp_root.visible:
		_update_hp_billboard()


## Frost mirror: a ranged shot instead of a punch.
func _shoot_bolt(dir: Vector3) -> void:
	_clone_model_attack()
	_attack_cd = 0.55
	state = State.RECOVER
	state_timer = 0.25
	if dir.length_squared() < 0.001:
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.001:
		return
	d = d.normalized()
	var shot := Projectile.new()
	shot.setup(d, damage, self, Color(0.6, 0.9, 1.0))
	get_parent().add_child(shot)
	shot.global_position = global_position + Vector3(0, 1.25, 0) + d * 0.8
	FX.burst(get_tree().current_scene, shot.global_position, Color(0.7, 0.95, 1.0),
		10, 0.1, 0.3, 3.0)


func _start_dash(dir: Vector3) -> void:
	_dash_dir = dir
	if _dash_dir.length_squared() < 0.001:
		_dash_dir = -global_transform.basis.z
	_dash_dir = Vector3(_dash_dir.x, 0, _dash_dir.z).normalized()
	_dash_time = 0.32
	FX.burst(get_tree().current_scene, global_position + Vector3(0, 0.5, 0),
		Color(1.0, 0.3, 0.55), 16, 0.1, 0.4, 4.5)


func _do_punch(dist: float, dir: Vector3) -> void:
	_attack_cd = 0.45 if player_target == null else player_target.attack_cooldown_now()
	state = State.RECOVER
	state_timer = 0.1
	if dir.length_squared() > 0.001:
		rotation.y = atan2(-dir.x, -dir.z)
	_swing()
	if dist <= attack_range + 0.8 and player_target != null:
		var d := dir
		d.y = 0.0
		d = d.normalized() if d.length_squared() > 0.01 else Vector3(0, 0, -1)
		player_target.apply_hit(damage, d, 7.0, ArenaMemory.CAUSE_CLONE)
		FX.burst(get_tree().current_scene, player_target.global_position + Vector3(0, 1.1, 0),
			Color(1.0, 0.3, 0.5), 22, 0.12, 0.45, 5.5)


func _do_super(dist: float, dir: Vector3) -> void:
	_clone_model_attack()
	_spin_visual()
	if dir.length_squared() > 0.001:
		rotation.y = atan2(-dir.x, -dir.z)
	var center := global_position + Vector3(0, 0.9, 0)
	var scene := get_tree().current_scene
	FX.ring(scene, global_position + Vector3(0, 0.3, 0), Color(1.0, 0.2, 0.5), 5.5, 0.55)
	FX.burst(scene, center, Color(1.0, 0.35, 0.6), 80, 0.18, 0.7, 13.0)
	if player_target != null and dist < 6.5:
		var d := dir
		d.y = 0.0
		d = d.normalized() if d.length_squared() > 0.01 else Vector3.ZERO
		player_target.apply_hit(damage * 2.4, d, 16.0, ArenaMemory.CAUSE_CLONE)
	if camera_rig() != null:
		camera_rig().shake(0.55)


func _do_heal() -> void:
	FX.burst(get_tree().current_scene, global_position + Vector3(0, 1.4, 0),
		Color(0.4, 1.0, 0.6), 30, 0.12, 0.6, 3.0)
	hp = minf(_clone_max_hp, hp + _clone_max_hp * 0.3)
	_update_hp_bar()


## Idle / Walk / Attack off the model's own rig, mirroring the player's ladder.
func _clone_animate(delta: float) -> void:
	if _clone_anim == null:
		return
	if _clone_attack_t > 0.0:
		_clone_attack_t -= delta
		_clone_play("Attack")
	elif _dash_time > 0.0 or velocity.length() > 0.75:
		_clone_play("Walk")
	else:
		_clone_play("Idle")


func _clone_play(anim_name: String) -> void:
	if _clone_anim == null or _clone_model_anim == anim_name:
		return
	_clone_model_anim = anim_name
	_clone_anim.play(anim_name)


func _clone_model_attack() -> void:
	if _clone_anim == null:
		return
	_clone_attack_t = _clone_attack_len
	if _clone_model_anim == "Attack":
		_clone_anim.stop()
	_clone_model_anim = "Attack"
	_clone_anim.play("Attack")


func _swing() -> void:
	_clone_model_attack()
	if _arm_pivot == null:
		return
	if _spin_tween != null and _spin_tween.is_valid():
		_spin_tween.kill()
	_spin_tween = create_tween()
	_spin_tween.tween_property(_arm_pivot, "position:z", -0.5, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_spin_tween.tween_property(_arm_pivot, "position:z", 0.0, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _spin_visual() -> void:
	var tw := create_tween()
	tw.tween_property(visual, "rotation:y", visual.rotation.y + TAU, 0.4) \
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)


func camera_rig() -> CameraRig:
	if player_target != null and is_instance_valid(player_target):
		return player_target.camera
	return null


## The clone never awards score - it is a gate, not loot.
func _die() -> void:
	if dead:
		return
	dead = true
	state = State.DEAD
	collision_layer = 0
	call_deferred("_disable_collision")
	# A gate, not loot: the kill still counts, the score does not.
	GameManager.add_kill(false)
	died.emit(self)
	var scene := get_tree().current_scene
	# The mirror shatters instead of falling: pale glass over the Core's wave.
	FX.impact(scene, global_position + Vector3(0, 1.0, 0), Color(1.0, 0.3, 0.6), 6.5)
	FX.burst(scene, global_position + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.93),
		70, 0.1, 0.7, 9.0)
	FX.hitstop(0.08)
	if _hp_root != null:
		_hp_root.visible = false
	if _telegraph != null:
		_telegraph.visible = false
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(0.05, 0.05, 0.05), 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "visible", false, 0.05)
	tw.tween_callback(queue_free)
