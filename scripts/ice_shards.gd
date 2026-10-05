class_name IceShards
extends Node3D

## The Ice Mage's super ability.
## 100%: six shards orbit you and chill whatever they touch.
## 200%: ten shards launch themselves at the nearest enemies instead.
## Every shard slows its victim by 35% for a few seconds - chilled bodies
## turn light blue.

const ORBIT_RADIUS := 3.1
const ORBIT_HEIGHT := 1.15
const ORBIT_SPEED := 3.6
const HIT_RADIUS := 1.3
const HIT_COOLDOWN := 1.1
const SEEK_SPEED := 17.0
const SEEK_TURN := 7.0
const SEEK_RANGE := 45.0

## The tuning lives on the Player; these are the local names for it, so a
## balance change there lands here too.
const SHARD_DAMAGE := Player.ICE_SHARD_DAMAGE
const SEEK_DAMAGE := Player.ICE_SEEK_DAMAGE
const SLOW_MULT := Player.ICE_SHARD_SLOW
const SLOW_TIME := Player.ICE_SHARD_SLOW_TIME
const ORBIT_TIME := Player.ICE_ORBIT_TIME
const SEEK_TIME := Player.ICE_SEEK_TIME

## Untyped on purpose: the Player script owns this class, so we duck-type the
## few members we need instead of creating a cyclic class reference.
var player
var count := 6
var homing := false
var damage := SHARD_DAMAGE
var duration := ORBIT_TIME

var _shards: Array = []
var _angle := 0.0
var _time := ORBIT_TIME
var _hit_cd := {}


func setup(p, n: int, seek: bool) -> void:
	player = p
	count = maxi(1, n)
	homing = seek
	damage = SEEK_DAMAGE if seek else SHARD_DAMAGE
	duration = SEEK_TIME if seek else ORBIT_TIME
	_time = duration


func _ready() -> void:
	_angle = randf() * TAU
	var mat := Util.make_material(Color(0.76, 0.96, 1.0), 0.12, 0.0,
		Color(0.4, 0.8, 1.0), 4.5)
	for i in count:
		var node := Node3D.new()
		var spike := Util.add_cone(node, 0.16, 0.62, Vector3.ZERO, mat)
		spike.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		Util.add_sphere(node, 0.17, Vector3.ZERO, mat)
		add_child(node)
		_shards.append({"node": node, "vel": Vector3.ZERO, "target": null,
			"pos": global_position + Vector3(0, 1.2, 0)})

	if player != null:
		FX.burst(get_tree().current_scene, player.global_position + Vector3(0, 1.1, 0),
			Color(0.6, 0.92, 1.0), 30, 0.13, 0.6, 7.0)


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.dead:
		queue_free()
		return

	_time -= delta
	if _time <= 0.0:
		_expire()
		return

	for id in _hit_cd.keys():
		_hit_cd[id] = float(_hit_cd[id]) - delta
		if float(_hit_cd[id]) <= 0.0:
			_hit_cd.erase(id)

	_angle += ORBIT_SPEED * delta
	var origin: Vector3 = player.global_position

	for i in _shards.size():
		var shard: Dictionary = _shards[i]
		var node := shard["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue

		if homing:
			_seek(shard, delta, origin)
		else:
			var a := _angle + TAU * float(i) / float(_shards.size())
			shard["pos"] = origin + Vector3(cos(a) * ORBIT_RADIUS,
				ORBIT_HEIGHT + sin(a * 2.0) * 0.2, sin(a) * ORBIT_RADIUS)

		var pos: Vector3 = shard["pos"]
		node.global_position = pos
		node.rotation.y += delta * 6.0
		node.rotation.x += delta * 4.0
		_hit(shard, pos)


## Homing shards drift toward the nearest living enemy and pick a new one
## after every hit.
func _seek(shard: Dictionary, delta: float, origin: Vector3) -> void:
	var target = shard["target"]
	if target == null or not is_instance_valid(target) or target.dead:
		target = _nearest_enemy(origin)
		shard["target"] = target

	var pos: Vector3 = shard["pos"]
	if target == null or not is_instance_valid(target):
		# Nothing left to hunt - drift outward and let the timer end it.
		var vel: Vector3 = shard["vel"]
		shard["pos"] = pos + vel * delta
		return

	var to: Vector3 = target.global_position + Vector3(0, 1.1, 0) - pos
	var dist := to.length()
	var vel2: Vector3 = shard["vel"]
	if dist > 0.001:
		var wanted := to.normalized() * SEEK_SPEED
		vel2 = vel2.lerp(wanted, minf(1.0, SEEK_TURN * delta))
	else:
		vel2 = Vector3.ZERO
	shard["vel"] = vel2
	shard["pos"] = pos + vel2 * delta


func _nearest_enemy(from: Vector3):
	var space := get_world_3d().direct_space_state
	var best = null
	var best_d := SEEK_RANGE
	for h in Combat.query_sphere(space, from, SEEK_RANGE, Combat.LAYER_ENEMY):
		var collider: Object = h.get("collider")
		if collider == null or not (collider is Node3D):
			continue
		if collider.get("dead") == true:
			continue
		if not collider.has_method("apply_hit"):
			continue
		var d: float = (collider as Node3D).global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = collider
	return best


## One shard checking the bodies around it.
func _hit(shard: Dictionary, pos: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	for h in Combat.query_sphere(space, pos, HIT_RADIUS, Combat.LAYER_ENEMY):
		var collider: Object = h.get("collider")
		if collider == null or not (collider is Node3D):
			continue
		var id: int = collider.get_instance_id()
		if float(_hit_cd.get(id, 0.0)) > 0.0:
			continue
		_hit_cd[id] = HIT_COOLDOWN
		var dir: Vector3 = (collider as Node3D).global_position - pos
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.ZERO
		var applied: Variant = collider.call("apply_hit", damage, dir, 4.0)
		var dealt := damage
		if typeof(applied) == TYPE_FLOAT or typeof(applied) == TYPE_INT:
			dealt = float(applied)
		if collider.has_method("apply_slow"):
			collider.call("apply_slow", SLOW_MULT, SLOW_TIME)
		if dealt > 0.0 and player != null and player.has_method("charge_super"):
			player.call("charge_super", dealt)
		if dealt > 0.0:
			GameManager.hit_connected.emit(Color(0.55, 0.85, 1.0))
			# Frost cracking. Six shards landing together is capped upstream,
			# so this reads as a patter rather than as a wall of tinkle.
			Sfx.play_at("bolt_hit", pos, -9.0, 1.2, 0.1)

		var scene := get_tree().current_scene
		FX.burst(scene, pos, Color(0.6, 0.92, 1.0), 16, 0.11, 0.4, 5.0)
		FX.burst(scene, (collider as Node3D).global_position + Vector3(0, 1.0, 0),
			Color(0.55, 0.85, 1.0), 12, 0.1, 0.4, 4.0)
		if homing:
			# Spent: retarget rather than shredding the same body.
			shard["target"] = null
			var vel: Vector3 = shard["vel"]
			shard["vel"] = -vel * 0.35 + Vector3(randf_range(-3, 3), 0,
				randf_range(-3, 3))
		return


func _expire() -> void:
	FX.ring(get_tree().current_scene, player.global_position + Vector3(0, 0.3, 0),
		Color(0.5, 0.85, 1.0), 3.4, 0.4)
	queue_free()
