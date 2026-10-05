class_name FX
extends RefCounted

## One-shot particle bursts used for every hit / death / ability.

## Token for overlapping hit-stops: only the last one to expire may restore
## the engine clock, otherwise a chain of hits ends the freeze early.
static var _stop_id := 0

## The two puff shapes never change, and a hit lands several times a second -
## each one used to mint a fresh mesh (and its own GPU buffers) on the spot.
static var _unit_box: BoxMesh = null
static var _flat_box: BoxMesh = null


static func _unit_box_mesh() -> BoxMesh:
	if _unit_box == null:
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		_unit_box = b
	return _unit_box


static func _flat_box_mesh() -> BoxMesh:
	if _flat_box == null:
		var b := BoxMesh.new()
		b.size = Vector3(1.0, 0.25, 1.0)
		_flat_box = b
	return _flat_box


## Hit-stop: a fraction of a second where the world nearly stops, so a big
## connect reads as an impact instead of a number changing. Accessibility
## switch lives in GameManager.opt_hitstop.
static func hitstop(duration: float = 0.06, strength: float = 0.05) -> void:
	if not GameManager.opt_hitstop:
		return
	var secs := clampf(duration, 0.0, 0.3)
	if secs <= 0.0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_stop_id += 1
	var id := _stop_id
	Engine.time_scale = clampf(strength, 0.02, 1.0)
	# process_always + ignore_time_scale: the thaw happens in real seconds
	# even though the whole engine is crawling.
	var t := tree.create_timer(secs, true, false, true)
	t.timeout.connect(func() -> void:
		if FX._stop_id == id:
			Engine.time_scale = 1.0)


## The full "something just died" package: a ring plus a burst.
static func impact(parent: Node, pos: Vector3, color: Color,
		radius: float = 3.0) -> void:
	ring(parent, pos, color, radius, 0.4)
	burst(parent, pos, color, 34, 0.14, 0.5, radius * 1.6)


static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 24,
		size: float = 0.12, life: float = 0.55, speed: float = 6.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var tree := parent.get_tree()
	if tree == null:
		return

	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = maxi(amount, 4)
	p.lifetime = life
	p.explosiveness = 1.0
	p.randomness = 0.7
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -15, 0)
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size * 1.5
	p.color = color

	var mesh := _unit_box_mesh()
	p.mesh = mesh

	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.22

	parent.add_child(p)
	p.global_position = pos
	p.emitting = true

	var timer := tree.create_timer(life + 0.6)
	# A SceneTree timer outlives change_scene_to_file, so the puff it is
	# holding can already be gone by the time it fires. Godot drops the
	# connection when the target dies, but asking is cheaper than relying on it.
	timer.timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())


## A quick expanding ring, used for the big area abilities.
static func ring(parent: Node, pos: Vector3, color: Color, radius: float = 3.0,
		life: float = 0.45) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var tree := parent.get_tree()
	if tree == null:
		return

	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 40
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = radius * 1.4
	p.initial_velocity_max = radius * 1.9
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.14
	p.color = color

	var mesh := _flat_box_mesh()
	p.mesh = mesh
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6

	parent.add_child(p)
	p.global_position = pos
	p.emitting = true

	var timer := tree.create_timer(life + 0.6)
	# A SceneTree timer outlives change_scene_to_file, so the puff it is
	# holding can already be gone by the time it fires. Godot drops the
	# connection when the target dies, but asking is cheaper than relying on it.
	timer.timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())


# --------------------------------------------------------------- mesh fx ----
## The particle puffs above are right for an ordinary hit, but at super scale
## they read as a shrug. These are real meshes that grow out of the impact and
## fade: a ground shockwave, a pillar of light, an energy core, radial blades.

static func _energy_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	return m


## Grows a node from one size to another while its material fades to nothing,
## then removes it. Everything below is a wrapper around this.
static func _grow_fade(node: Node3D, mat: StandardMaterial3D, from: Vector3,
		to: Vector3, life: float, delay: float = 0.0) -> void:
	node.scale = from
	var span := maxf(life, 0.05)
	var tw := node.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(node, "scale", to, span) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, span) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(node.queue_free)


## Sits the mesh under an anchor placed at the effect's own origin, so scaling
## the anchor pushes the shape outward from the impact instead of inflating it
## around its middle.
static func _grow_from(parent: Node, anchor_pos: Vector3, mesh: Mesh,
		offset: Vector3, rot_y: float, color: Color, from: Vector3,
		to: Vector3, life: float, delay: float = 0.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	if parent.get_tree() == null:
		return
	var anchor := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = mesh
	var mat := _energy_mat(color)
	body.material_override = mat
	body.position = offset
	anchor.add_child(body)
	parent.add_child(anchor)
	anchor.global_position = anchor_pos
	anchor.rotation.y = rot_y
	_grow_fade(anchor, mat, from, to, life, delay)


## A ring that races outward along the floor from the point of impact.
static func shockwave(parent: Node, pos: Vector3, color: Color,
		radius: float = 6.0, life: float = 0.5, thickness: float = 0.14,
		delay: float = 0.0) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.0
	mesh.outer_radius = 1.0 + thickness
	mesh.rings = 44
	mesh.ring_segments = 6
	_grow_from(parent, pos + Vector3(0, 0.06, 0), mesh, Vector3.ZERO, 0.0, color,
		Vector3.ONE * 0.25, Vector3.ONE * radius, life, delay)


## A pillar standing where the blow landed, growing up out of the floor.
static func column(parent: Node, pos: Vector3, color: Color,
		radius: float = 1.8, height: float = 9.0, life: float = 0.6,
		delay: float = 0.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 22
	_grow_from(parent, pos, mesh, Vector3(0, 0.5, 0), 0.0, color,
		Vector3(radius * 0.3, 0.02, radius * 0.3),
		Vector3(radius, height, radius), life, delay)


## A flash of raw energy: the core of every super.
static func orb(parent: Node, pos: Vector3, color: Color, radius: float = 3.0,
		life: float = 0.3, delay: float = 0.0) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	_grow_from(parent, pos, mesh, Vector3.ZERO, 0.0, color,
		Vector3.ONE * 0.15, Vector3.ONE * radius, life, delay)


## Blades shooting out of the impact in every direction.
static func spokes(parent: Node, pos: Vector3, color: Color, count: int = 8,
		length: float = 7.0, life: float = 0.45, thickness: float = 0.3,
		delay: float = 0.0) -> void:
	var n := maxi(count, 1)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.16, 1.0)
	for i in n:
		var angle := TAU * float(i) / float(n)
		var dir := Vector3(cos(angle), 0.0, -sin(angle))
		_grow_from(parent, pos, mesh, Vector3(0.5, 0.0, 0.0),
			atan2(-dir.z, dir.x), color,
			Vector3(length * 0.06, 1.0, thickness),
			Vector3(length, 1.0, thickness), life, delay)
