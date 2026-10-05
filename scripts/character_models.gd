class_name CharacterModels
extends RefCounted

## The three selectable warriors as authored characters.
##
## Each GLB ships its own rig and three clips (Idle / Walk / Attack), so this
## wrapper only has to load the scene, stand it on the arena floor, turn it to
## face the way the game runs (-Z) and hand back the parts the caller needs.
##
## Nothing here is required for the game to run: if a file is missing or a
## model will not fit, `build()` returns null and the caller keeps using its
## own procedural body.

## Keyed by the plain character indices the game passes around (0 brawler,
## 1 swordsman, 2 ice mage) - kept as ints so this file never has to include
## player.gd, which includes this file.
const PATHS := {
	0: "res://character assets/helix.glb",
	1: "res://character assets/maxl.glb",
	2: "res://character assets/icey.glb",
}

## Every model is scaled so the top of the body lands here. The player's
## collision capsule runs from y=0 to y=1.8, so the head sits just inside it.
const TARGET_HEIGHT := 1.76

## All three GLBs face +Z; the controller, the camera and the aim assist all
## treat -Z as forward.
const FACING_Y := PI

## A mesh wholly below this at rest is a parked effect (ice shards, casting
## seals, heart pulses) that the Attack clip lifts into view. It must not drag
## the bounding box, or the character would be scaled down to nothing.
const PARKED_BELOW := -1.0


## Instantiate into `parent` (which must already be in the tree, so global
## transforms can be measured) and return the fitted wrapper, or null on any
## kind of failure.
static func build(parent: Node3D, type: int) -> Node3D:
	var path: String = PATHS.get(type, "")
	if path == "" or parent == null:
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		return null

	# The fit transform lives on a wrapper we own, never on the GLB's own
	# root: if a clip animates that node it would overwrite our scale.
	var wrap := Node3D.new()
	wrap.name = "Character"
	parent.add_child(wrap)
	wrap.add_child(model)

	if not _fit(wrap, model):
		wrap.queue_free()
		return null
	return wrap


## Every MeshInstance3D under `root`, as [node, lo_y, hi_y] in world space.
static func meshes(root: Node3D) -> Array:
	return _measure(root, Transform3D.IDENTITY)


static func _measure(n: Node, inv: Transform3D) -> Array:
	var out: Array = []
	_collect(n, inv, out)
	return out


static func animation_player(root: Node3D) -> AnimationPlayer:
	return _find_anim(root)


## Loop the locomotion clips and report how long the attack clip runs, so the
## caller can hold the pose and hand back to Walk/Idle when it is done.
static func prime(anim: AnimationPlayer) -> float:
	if anim == null:
		return 0.45
	var attack := 0.45
	for a in anim.get_animation_list():
		var clip := anim.get_animation(a)
		if clip == null:
			continue
		if String(a) == "Attack":
			clip.loop_mode = Animation.LOOP_NONE
			attack = maxf(0.1, clip.length)
		else:
			clip.loop_mode = Animation.LOOP_LINEAR
	return attack


## The Core's copy of you: same body, drenched in its colour.
static func tint(root: Node3D, color: Color) -> void:
	var memo := {}
	for row in meshes(root):
		var mi := row[0] as MeshInstance3D
		if mi == null:
			continue
		for i in range(mi.get_surface_override_material_count()):
			var src := mi.get_surface_override_material(i)
			if src == null and mi.mesh != null and i < mi.mesh.get_surface_count():
				src = mi.mesh.surface_get_material(i)
			if src == null:
				continue
			var key := src.resource_path if src.resource_path != "" \
				else str(src.get_instance_id())
			if not memo.has(key):
				memo[key] = _tinted(src, color)
			mi.set_surface_override_material(i, memo[key])


static func _tinted(src: Material, color: Color) -> Material:
	var d := src.duplicate() as StandardMaterial3D
	if d == null:
		return src
	d.albedo_color = d.albedo_color * color
	d.emission_enabled = true
	d.emission = color * 0.5
	d.emission_energy_multiplier = 0.9
	return d


## Stand the model on y=0, scaled to TARGET_HEIGHT, facing -Z. Returns false
## if the measurement came out nonsense, so the caller can fall back.
##
## Everything is measured in the wrapper's own frame: measuring in world
## space would bake the player's spawn height straight into the floor offset
## and leave the character standing 20cm through the arena floor.
static func _fit(wrap: Node3D, model: Node3D) -> bool:
	var inv := wrap.global_transform.affine_inverse()
	var feet := INF
	var top := -INF
	for row in _measure(model, inv):
		var lo: float = row[1]
		var hi: float = row[2]
		if hi < PARKED_BELOW:
			continue
		feet = minf(feet, lo)
		# The greatsword rides well above the head and must not set the scale,
		# or Maxl would come out a foot shorter than the other two.
		var mi := row[0] as MeshInstance3D
		if mi != null and String(mi.name).contains("Greatsword"):
			continue
		top = maxf(top, hi)

	if not is_finite(feet) or not is_finite(top) or top - feet < 0.2:
		return false

	var s := TARGET_HEIGHT / (top - feet)
	wrap.scale = Vector3(s, s, s)
	wrap.rotation.y = FACING_Y
	# scale and rotation are applied before the translation, so this lands the
	# feet exactly on the floor regardless of either.
	wrap.position.y = -feet * s
	return true


static func _collect(n: Node, inv: Transform3D, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var bb := mi.mesh.get_aabb()
			# Only the y extent is ever read, and the frames involved are
			# rotated about Y, so the two opposite corners are enough.
			var p0: Vector3 = inv * (mi.global_transform * bb.position)
			var p1: Vector3 = inv * (mi.global_transform * (bb.position + bb.size))
			var lo := Vector3(minf(p0.x, p1.x), minf(p0.y, p1.y), minf(p0.z, p1.z))
			var hi := Vector3(maxf(p0.x, p1.x), maxf(p0.y, p1.y), maxf(p0.z, p1.z))
			out.append([mi, lo.y, hi.y])
	for c in n.get_children():
		_collect(c, inv, out)


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null
