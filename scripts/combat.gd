class_name Combat
extends RefCounted

## Physics layers + hit queries shared by the player and the traps.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4


static func query_sphere(space: PhysicsDirectSpaceState3D, origin: Vector3, radius: float,
		mask: int) -> Array:
	if space == null or radius <= 0.0:
		return []
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return space.intersect_shape(params, 48)


## Applies damage to everything hit inside a sphere.
## Returns the total damage actually dealt (used to charge the super ability).
static func damage_sphere(host: Node3D, origin: Vector3, radius: float, damage: float,
		direction: Vector3, knockback: float, hit_color: Color) -> float:
	if host == null or not is_instance_valid(host):
		return 0.0
	var space := host.get_world_3d().direct_space_state
	var hits := query_sphere(space, origin, radius, LAYER_ENEMY)
	var total := 0.0
	var fx_parent := host.get_tree().current_scene
	for h in hits:
		var collider: Object = h.get("collider")
		if collider == null or not collider.has_method("apply_hit"):
			continue
		var applied: Variant = collider.call("apply_hit", damage, direction, knockback)
		var dealt := damage
		if typeof(applied) == TYPE_FLOAT or typeof(applied) == TYPE_INT:
			dealt = float(applied)
		total += dealt
		var hit_pos := origin
		if h.has("position"):
			hit_pos = h["position"]
		elif h.has("point"):
			hit_pos = h["point"]
		FX.burst(fx_parent, origin.lerp(hit_pos, 0.5) + Vector3(0, 0.4, 0),
			hit_color, 20, 0.11, 0.5, 5.5)
	# The sweep has landed, so ask whoever threw it how that should sound.
	# This is the single path all seven of the player's area attacks take,
	# which is why the voice lives here and not at each call site.
	if total > 0.0 and host.has_method("announce_hit"):
		host.call("announce_hit", total, origin)
	return total


## Soft aim assist: nudges `fwd` toward the enemy that sits closest to it inside
## a cone. Returns `fwd` untouched when nothing qualifies.
static func aim_assist(host: Node3D, origin: Vector3, fwd: Vector3,
		reach: float, cone_degrees: float = 34.0) -> Vector3:
	if host == null or not is_instance_valid(host):
		return fwd
	var f := Vector3(fwd.x, 0.0, fwd.z)
	if f.length_squared() < 0.0001:
		return fwd
	f = f.normalized()
	var best := f
	var best_dot := cos(deg_to_rad(cone_degrees))
	var space := host.get_world_3d().direct_space_state
	for h in query_sphere(space, origin, reach, LAYER_ENEMY):
		var collider: Object = h.get("collider")
		if collider == null or not (collider is Node3D):
			continue
		var to := (collider as Node3D).global_position - origin
		to.y = 0.0
		if to.length_squared() < 0.0001:
			continue
		to = to.normalized()
		var d := to.dot(f)
		if d > best_dot:
			best_dot = d
			best = to
	return best


## Floating combat text: a billboarded number that drifts up and fades out.
static func pop_number(parent: Node, pos: Vector3, amount: float,
		color: Color = Color.WHITE, scale_mult: float = 1.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var tree := parent.get_tree()
	if tree == null:
		return

	var l := Label3D.new()
	l.text = str(int(round(amount)))
	l.font_size = 64
	l.pixel_size = 0.006 * clampf(scale_mult, 0.5, 3.0)
	l.modulate = color
	l.outline_size = 16
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.shaded = false
	parent.add_child(l)
	l.global_position = pos

	var tw := l.create_tween()
	tw.tween_property(l, "position:y", pos.y + 1.1, 0.65) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.28).set_delay(0.37)
	tw.tween_callback(l.queue_free)
