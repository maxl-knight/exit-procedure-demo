class_name IceBolt
extends Node3D

## The Ice Mage's basic attack: a straight-line frost shard that stops on the
## first wall or body it touches.

## One source of truth: the bolt flies at the player's own bolt speed.
const SPEED := Player.ICE_BOLT_SPEED
const LIFE := 3.0

var damage := 12.0
var direction := Vector3(0, 0, -1)
var max_range := 13.0

## Whoever fired it - used to hand the damage back as super charge.
var source

var _travelled := 0.0
var _life := LIFE


func setup(dir: Vector3, dmg: float, reach: float, shooter = null) -> void:
	direction = dir.normalized() if dir.length_squared() > 0.001 else Vector3(0, 0, -1)
	damage = dmg
	max_range = maxf(reach, 2.0)
	source = shooter


func _ready() -> void:
	var mat := Util.make_material(Color(0.74, 0.95, 1.0), 0.15, 0.0,
		Color(0.35, 0.78, 1.0), 4.0)
	var spike := Util.add_cone(self, 0.17, 0.6, Vector3.ZERO, mat)
	spike.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	Util.add_sphere(self, 0.15, Vector3.ZERO, mat)

	var light := OmniLight3D.new()
	light.omni_range = 3.4
	light.light_color = Color(0.5, 0.85, 1.0)
	light.light_energy = 1.5
	light.shadow_enabled = false
	add_child(light)

	var trail := CPUParticles3D.new()
	trail.amount = 22
	trail.lifetime = 0.3
	trail.local_coords = false
	trail.direction = Vector3.ZERO
	trail.spread = 30.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 1.0
	trail.scale_amount_min = 0.04
	trail.scale_amount_max = 0.1
	trail.color = Color(0.55, 0.88, 1.0)
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3.ONE
	trail.mesh = tmesh
	add_child(trail)
	trail.emitting = true

	rotation.y = atan2(-direction.x, -direction.z)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return

	var prev := global_position
	var next := prev + direction * SPEED * delta

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(prev, next,
		Combat.LAYER_ENEMY | Combat.LAYER_WORLD)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("apply_hit"):
			var applied: Variant = collider.call("apply_hit", damage, direction, 5.0)
			var dealt := damage
			if typeof(applied) == TYPE_FLOAT or typeof(applied) == TYPE_INT:
				dealt = float(applied)
			if dealt > 0.0 and source != null and source.has_method("charge_super"):
				source.call("charge_super", dealt)
			if dealt > 0.0:
				GameManager.hit_connected.emit(Color(0.55, 0.85, 1.0))
		# The bolt does not travel through Combat.damage_sphere, so it voices
		# its own contact - frost shattering, whether it found a body or a wall.
		Sfx.play_at("bolt_hit", next, -5.0)
		FX.burst(get_tree().current_scene, next, Color(0.6, 0.9, 1.0), 20, 0.1, 0.4, 5.0)
		queue_free()
		return

	_travelled += (next - prev).length()
	if _travelled >= max_range:
		FX.burst(get_tree().current_scene, next, Color(0.5, 0.85, 1.0), 8, 0.08, 0.3, 3.0)
		queue_free()
		return

	global_position = next
