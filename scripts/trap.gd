class_name SpikeTrap
extends Node3D

## Floor spikes on a safe / warn / active cycle. Damages the player and enemies.

enum Phase { SAFE, WARN, ACTIVE }

const SAFE_TIME := 2.1
const WARN_TIME := 0.75
const ACTIVE_TIME := 1.4
const HIT_INTERVAL := 0.9

## Warn glows amber, firing burns red-orange: traps speak a different colour
## language from the blue enemy telegraphs.
const WARN_COLOR := Color(1.0, 0.72, 0.1)
const ACTIVE_COLOR := Color(1.0, 0.35, 0.1)

## How close the player has to be to feel a trap go off.
const SHAKE_RANGE := 14.0

var damage := 12.0
var trap_size := 3.2

## Adaptive-room tuning: >1.0 shortens every phase. The Arena speeds the
## hazards up when it has learned that you dash on reflex.
var haste := 1.0

var phase: int = Phase.SAFE
var timer := SAFE_TIME

var _spikes: Node3D
var _area: Area3D
var _plate_mat: StandardMaterial3D
var _spike_mat: StandardMaterial3D
var _last_hit: Dictionary = {}
## Looked up lazily - the room never hands us the player.
var _player: Player


func _ready() -> void:
	timer = SAFE_TIME / maxf(haste, 0.1)
	var dark := Util.make_material(Color(0.13, 0.13, 0.16), 0.6, 0.5)
	Util.add_box(self, Vector3(trap_size, 0.14, trap_size),
		Vector3(0, 0.07, 0), dark)

	_plate_mat = Util.make_material(Color(0.2, 0.16, 0.14), 0.5, 0.6,
		Color(1.0, 0.25, 0.05), 0.0)
	Util.add_box(self, Vector3(trap_size * 0.9, 0.06, trap_size * 0.9),
		Vector3(0, 0.15, 0), _plate_mat)

	_spike_mat = Util.make_material(Color(0.7, 0.72, 0.78), 0.25, 0.9,
		Color(1.0, 0.2, 0.05), 0.0)

	_spikes = Node3D.new()
	_spikes.position.y = -0.7
	add_child(_spikes)
	var half := trap_size * 0.5 - 0.5
	for ix in 3:
		for iz in 3:
			var x := (ix - 1) * half
			var z := (iz - 1) * half
			Util.add_cone(_spikes, 0.18, 0.7, Vector3(x, 0.3, z), _spike_mat, 0.02)

	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = Combat.LAYER_PLAYER | Combat.LAYER_ENEMY
	_area.monitoring = true
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(trap_size, 1.3, trap_size)
	cs.shape = box
	cs.position = Vector3(0, 0.65, 0)
	_area.add_child(cs)
	add_child(_area)


func _physics_process(delta: float) -> void:
	timer -= delta
	match phase:
		Phase.SAFE:
			_spikes.position.y = lerpf(_spikes.position.y, -0.7, 9.0 * delta)
			_set_glow(0.0)
			if timer <= 0.0:
				_enter(Phase.WARN, WARN_TIME)
		Phase.WARN:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
			_set_glow(0.6 + pulse * 2.4)
			_spikes.position.y = lerpf(_spikes.position.y, -0.35, 9.0 * delta)
			if timer <= 0.0:
				_enter(Phase.ACTIVE, ACTIVE_TIME)
		Phase.ACTIVE:
			_set_glow(1.6)
			_spikes.position.y = lerpf(_spikes.position.y, 0.3, 22.0 * delta)
			_do_damage()
			if timer <= 0.0:
				_enter(Phase.SAFE, SAFE_TIME)


func _enter(next_phase: int, duration: float) -> void:
	phase = next_phase
	timer = duration / maxf(haste, 0.1)
	# Amber while it warns, red-orange the moment it fires.
	_set_glow_color(ACTIVE_COLOR if phase == Phase.ACTIVE else WARN_COLOR)
	match phase:
		Phase.WARN:
			# Only cries out when someone is close enough to care. A bank of
			# four traps all warning is noise, not information.
			if _player_near(SHAKE_RANGE):
				Sfx.play_at("trap_warn", global_position, -3.0)
		Phase.ACTIVE:
			_fire_shake()
			if _player_near(SHAKE_RANGE):
				Sfx.play_at("trap_fire", global_position, -3.0)
		_:
			if _player_near(SHAKE_RANGE + 4.0):
				Sfx.play_at("trap_retract", global_position, -7.0)


## Whether the player is near enough for this trap to be heard over the fight.
func _player_near(range_m: float) -> bool:
	var p := _find_player()
	if p == null or not is_instance_valid(p):
		return false
	return p.global_position.distance_to(global_position) <= range_m


## Emission colour per phase. The plate and spikes are solid, depth-tested
## geometry, so the glow never bleeds through a wall the way a cheap
## no_depth_test overlay would.
func _set_glow_color(c: Color) -> void:
	_plate_mat.emission = c
	_spike_mat.emission = c


## Firing is felt as well as seen: a short jolt that falls off with distance.
func _fire_shake() -> void:
	if not GameManager.opt_shake:
		return
	var p := _find_player()
	if p == null or not is_instance_valid(p) or p.camera == null:
		return
	var d := p.global_position.distance_to(global_position)
	if d > SHAKE_RANGE:
		return
	p.camera.shake(lerpf(0.18, 0.04, d / SHAKE_RANGE))


## The room places traps without telling them who to hurt, so find the player
## in the scene once and keep the reference.
func _find_player() -> Player:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = _scan_for_player(get_tree().current_scene, 0)
	return _player


func _scan_for_player(node: Node, depth: int) -> Player:
	if node == null or depth > 3:
		return null
	for child in node.get_children():
		if child is Player:
			return child as Player
		var found := _scan_for_player(child, depth + 1)
		if found != null:
			return found
	return null


func _set_glow(energy: float) -> void:
	if energy <= 0.001:
		_plate_mat.emission_energy_multiplier = 0.0
		_spike_mat.emission_energy_multiplier = 0.0
		return
	_plate_mat.emission_enabled = true
	_spike_mat.emission_enabled = true
	_plate_mat.emission_energy_multiplier = energy * 0.5
	_spike_mat.emission_energy_multiplier = energy


func _do_damage() -> void:
	if _area == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var scene := get_tree().current_scene
	for body in _area.get_overlapping_bodies():
		if not body.has_method("apply_hit"):
			continue
		var id: int = body.get_instance_id()
		var last: float = _last_hit.get(id, -100.0)
		if now - last < HIT_INTERVAL:
			continue
		_last_hit[id] = now
		var dir := body.global_position - global_position
		dir.y = 0.0
		if dir.length_squared() < 0.01:
			dir = Vector3(0, 0, 1)
		else:
			dir = dir.normalized()
		body.call("apply_hit", damage, dir, 6.0, ArenaMemory.CAUSE_TRAP)
		FX.burst(scene, body.global_position + Vector3(0, 0.5, 0),
			Color(1.0, 0.55, 0.12), 18, 0.1, 0.4, 5.5)
