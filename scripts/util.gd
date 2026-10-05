class_name Util
extends RefCounted

## Small helpers for building meshes / materials / collision boxes in code.

## Shapes and the outline material are built once and shared. The same handful
## of dimensions comes up over and over - an eyeball, a horn, a bolt, a fist -
## and every separate copy is another set of GPU buffers the moment it is
## drawn. Caches are capped so a randomized dimension can never grow them.
static var _outline_mat: StandardMaterial3D = null
static var _sphere_meshes := {}
static var _capsule_meshes := {}
static var _cone_meshes := {}
const _MESH_CACHE_MAX := 64


static func make_material(color: Color, roughness: float = 0.8, metallic: float = 0.0,
		emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


static func make_outline_material() -> StandardMaterial3D:
	# Never mutated after creation, so one copy serves every outline in the
	# game instead of one material per enemy per part.
	if _outline_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.02, 0.02, 0.03)
		m.cull_mode = BaseMaterial3D.CULL_FRONT
		m.roughness = 1.0
		_outline_mat = m
	return _outline_mat


## Inverted-hull outline: a slightly inflated copy with front faces culled.
static func add_outline(mesh_instance: MeshInstance3D, thickness: float = 0.04) -> MeshInstance3D:
	var m := mesh_instance.mesh
	if m == null:
		return null
	var size := Vector3.ONE
	if m is BoxMesh:
		size = (m as BoxMesh).size
	elif m is CapsuleMesh:
		var c := m as CapsuleMesh
		size = Vector3(c.radius * 2.0, c.height, c.radius * 2.0)
	elif m is SphereMesh:
		var s := m as SphereMesh
		size = Vector3(s.radius * 2.0, s.height, s.radius * 2.0)
	elif m is CylinderMesh:
		var cy := m as CylinderMesh
		var r := maxf(cy.top_radius, cy.bottom_radius)
		size = Vector3(r * 2.0, cy.height, r * 2.0)
	else:
		return null
	size.x = maxf(size.x, 0.001)
	size.y = maxf(size.y, 0.001)
	size.z = maxf(size.z, 0.001)
	var outline := MeshInstance3D.new()
	outline.mesh = m
	outline.scale = Vector3(
		(size.x + 2.0 * thickness) / size.x,
		(size.y + 2.0 * thickness) / size.y,
		(size.z + 2.0 * thickness) / size.z
	)
	outline.material_override = make_outline_material()
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.add_child(outline)
	return outline


static func add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		outline: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if outline > 0.0:
		add_outline(mi, outline)
	return mi


## Shared primitives, keyed on the dimensions the caller asked for.
static func _sphere_mesh(radius: float) -> SphereMesh:
	var key := str(snappedf(radius, 0.001))
	var hit = _sphere_meshes.get(key)
	if hit != null:
		return hit
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	if _sphere_meshes.size() < _MESH_CACHE_MAX:
		_sphere_meshes[key] = m
	return m


static func _capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var key := "%s|%s" % [snappedf(radius, 0.001), snappedf(height, 0.001)]
	var hit = _capsule_meshes.get(key)
	if hit != null:
		return hit
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	if _capsule_meshes.size() < _MESH_CACHE_MAX:
		_capsule_meshes[key] = m
	return m


static func _cone_mesh(radius: float, height: float) -> CylinderMesh:
	var key := "%s|%s" % [snappedf(radius, 0.001), snappedf(height, 0.001)]
	var hit = _cone_meshes.get(key)
	if hit != null:
		return hit
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = height
	if _cone_meshes.size() < _MESH_CACHE_MAX:
		_cone_meshes[key] = m
	return m


static func add_capsule(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material, outline: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _capsule_mesh(radius, height)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if outline > 0.0:
		add_outline(mi, outline)
	return mi


static func add_sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material,
		outline: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(radius)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if outline > 0.0:
		add_outline(mi, outline)
	return mi


static func add_cone(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: Material, outline: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _cone_mesh(radius, height)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if outline > 0.0:
		add_outline(mi, outline)
	return mi


## A mesh box plus a static collider, both centred on `pos`.
static func add_static_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		layer: int = 1, outline: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	body.add_child(mi)
	if outline > 0.0:
		add_outline(mi, outline)
	parent.add_child(body)
	return body


static func white_texture() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)
