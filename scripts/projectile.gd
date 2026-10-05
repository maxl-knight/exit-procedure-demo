class_name Projectile
extends Node3D

## Enemy archer shot. Straight-line skillshot, resolved with a ray each frame
## so it can never tunnel through the player or a wall.

const SPEED := 15.0
const LIFE := 4.5

var damage := 10.0
var direction := Vector3(0, 0, -1)
var scale_factor := 1.0
var tint := Color(0.35, 0.7, 1.0)
var _life := LIFE
var _exclude: Array[RID] = []


func setup(dir: Vector3, dmg: float, exclude_body: Node = null,
		new_tint: Color = Color(0.35, 0.7, 1.0)) -> void:
	direction = dir.normalized()
	damage = dmg
	tint = new_tint
	if exclude_body is CollisionObject3D:
		_exclude.append((exclude_body as CollisionObject3D).get_rid())


func _ready() -> void:
	var mat := Util.make_material(tint, 0.2, 0.0, tint, 3.5)
	Util.add_sphere(self, 0.24 * scale_factor, Vector3.ZERO, mat)

	var light := OmniLight3D.new()
	light.omni_range = 4.0 * scale_factor
	light.light_color = tint
	light.light_energy = 1.4
	light.shadow_enabled = false
	add_child(light)

	var trail := CPUParticles3D.new()
	trail.amount = 26
	trail.lifetime = 0.32
	trail.local_coords = false
	trail.direction = Vector3.ZERO
	trail.spread = 40.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.4
	trail.initial_velocity_max = 1.2
	trail.scale_amount_min = 0.05
	trail.scale_amount_max = 0.12
	trail.color = tint
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
		Combat.LAYER_PLAYER | Combat.LAYER_WORLD, _exclude)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("apply_hit"):
			var applied: Variant = collider.call("apply_hit", damage, direction,
				4.5, ArenaMemory.CAUSE_RANGED)
			# The reticle answers only a shot that actually drew blood.
			if collider is Player and float(applied) > 0.0:
				GameManager.hit_connected.emit(Color(0.6, 0.8, 1.0))
		Sfx.play_at("projectile_hit", next, -6.0)
		FX.burst(get_tree().current_scene, next, Color(0.4, 0.75, 1.0), 22, 0.1, 0.4, 5.0)
		set_physics_process(false)
		queue_free()
		return

	global_position = next
