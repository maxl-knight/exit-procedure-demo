class_name HealthOrb
extends Node3D

## What an elite leaves behind. It hangs there, drifting, until you are hurt
## enough to want it - then it comes to you. Deliberately never consumed at
## full health, so a full bar never wastes the drop.
##
## No Area3D: pickup is a plain distance check, which keeps the drop out of
## the physics servers entirely (elites tend to die mid-query).

const LIFETIME := 22.0
const MAGNET_RANGE := 6.0
const MAGNET_SPEED := 12.0
const PICKUP_RANGE := 1.5
const HEAL_PERCENT := 0.18
const BOB_HEIGHT := 0.95

## `magnet` widens both radii - but stops at double, so the drop stays a
## pickup rather than vacuuming the whole floor.
const MAGNET_RADIUS_CAP := 2.0

const GLOW := Color(0.35, 1.0, 0.55)

var player: Player

var _life := LIFETIME
var _t := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	var mat := Util.make_material(GLOW, 0.3, 0.0, GLOW, 3.2)
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	# A slightly bigger shell with its front faces culled reads as a glow
	# outline without needing depth tricks.
	var halo := MeshInstance3D.new()
	var shell := SphereMesh.new()
	shell.radius = 0.52
	shell.height = 1.04
	halo.mesh = shell
	var halo_mat := Util.make_material(GLOW, 0.3, 0.0, GLOW, 2.0)
	halo_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.add_child(halo)

	var light := OmniLight3D.new()
	light.light_color = GLOW
	light.omni_range = 5.0
	light.light_energy = 1.7
	light.shadow_enabled = false
	add_child(light)


func _physics_process(delta: float) -> void:
	_t += delta
	_life -= delta
	if _mesh != null:
		_mesh.position.y = BOB_HEIGHT + sin(_t * 3.0) * 0.16
		_mesh.rotation.y += delta * 1.7
	if _life <= 0.0:
		queue_free()
		return

	# Only interesting once you have something to heal.
	if player == null or not is_instance_valid(player) or player.dead:
		return
	if player.health.health >= player.health.max_health:
		return

	# Buffs move during a run, so the pull is measured fresh every frame.
	var grow := minf(1.0 + 0.35 * player.buff_stacks("magnet"), MAGNET_RADIUS_CAP)
	var to := player.global_position + Vector3(0, 1.0, 0) - global_position
	var dist := to.length()
	if dist <= PICKUP_RANGE * grow:
		_collect()
	elif dist <= MAGNET_RANGE * grow:
		global_position += to.normalized() * MAGNET_SPEED * delta


func _collect() -> void:
	var amount := 0.0
	if player != null and is_instance_valid(player):
		# Worth is counted here, not when the pull started - stacks change.
		var pct := HEAL_PERCENT * (1.0 + 0.5 * player.buff_stacks("magnet"))
		amount = player.heal_percent(pct)
	var scene := get_tree().current_scene
	FX.burst(scene, global_position, GLOW, 30, 0.13, 0.5, 6.5)
	FX.ring(scene, global_position, GLOW, 2.6, 0.4)
	if amount > 0.0:
		# Green centre flash: the floor gave something back.
		Sfx.play_at("orb", global_position, -4.0)
		GameManager.hit_connected.emit(Color(0.4, 1.0, 0.6))
		Combat.pop_number(scene, global_position + Vector3(0, 0.7, 0),
			amount, Color(0.4, 1.0, 0.6), 1.25)
		# The first mote ever taken is a story beat, not just a heal.
		ArenaMemory.note_orb()
	queue_free()
