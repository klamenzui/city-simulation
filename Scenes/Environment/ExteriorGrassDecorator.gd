class_name ExteriorGrassDecorator
extends Node3D

const GRASS_SCENE_PATH := "res://Scenes/Environment/Grass/grass.glb"
const GRASS_MATERIAL_PATH := "res://Scenes/Environment/Grass/Stylized3DGrass.tres"

@export var grass_enabled: bool = true
@export var seed: int = 43017
@export var field_min: Vector2 = Vector2(-78.0, -84.0)
@export var field_max: Vector2 = Vector2(96.0, 86.0)
@export var city_exclusion_min: Vector2 = Vector2(-8.0, -44.0)
@export var city_exclusion_max: Vector2 = Vector2(41.0, 44.0)
@export var island_radius: Vector2 = Vector2(122.0, 118.0)
@export_range(0.5, 5.0, 0.1) var spacing: float = 1.8
@export_range(0.0, 1.0, 0.01) var density: float = 0.62
@export_range(0.0, 2.0, 0.05) var jitter: float = 0.65
@export var max_instances: int = 4500
@export var ground_ray_height: float = 35.0
@export var ground_ray_depth: float = 55.0
@export var ground_y_offset: float = 0.03
@export var min_ground_y: float = -4.8
@export var max_ground_y: float = 1.4
@export var scale_min: float = 0.42
@export var scale_max: float = 0.72
@export var height_scale_min: float = 0.72
@export var height_scale_max: float = 1.15
@export var visibility_range_end: float = 135.0

var _grass_instance: MultiMeshInstance3D
var _generated_instance_count: int = 0
var _has_built: bool = false


func _ready() -> void:
	if not grass_enabled:
		return
	await get_tree().physics_frame
	_build_grass()


func get_generated_instance_count() -> int:
	return _generated_instance_count


func _build_grass() -> void:
	if _has_built:
		return
	_has_built = true

	var grass_mesh := _load_grass_mesh()
	if grass_mesh == null:
		push_warning("ExteriorGrassDecorator could not load grass mesh from %s." % GRASS_SCENE_PATH)
		return

	var transforms := _collect_instance_transforms()
	if transforms.is_empty():
		push_warning("ExteriorGrassDecorator found no valid ground positions for grass.")
		return

	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = grass_mesh
	multi_mesh.instance_count = transforms.size()
	multi_mesh.visible_instance_count = transforms.size()
	for index in range(transforms.size()):
		multi_mesh.set_instance_transform(index, transforms[index])

	var material := load(GRASS_MATERIAL_PATH) as Material
	var grass_instance := MultiMeshInstance3D.new()
	grass_instance.name = "GrassMultiMesh"
	grass_instance.multimesh = multi_mesh
	grass_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	grass_instance.visibility_range_end = visibility_range_end
	grass_instance.custom_aabb = _make_grass_aabb()
	if material != null:
		grass_instance.material_override = material

	add_child(grass_instance)
	_grass_instance = grass_instance
	_generated_instance_count = transforms.size()


func _load_grass_mesh() -> Mesh:
	var grass_scene := load(GRASS_SCENE_PATH) as PackedScene
	if grass_scene == null:
		return null

	var scene_root := grass_scene.instantiate()
	var mesh := _find_first_mesh(scene_root)
	scene_root.free()
	return mesh


func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			return mesh_instance.mesh
	for child in node.get_children():
		var mesh := _find_first_mesh(child)
		if mesh != null:
			return mesh
	return null


func _collect_instance_transforms() -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var x_steps := int(floor((field_max.x - field_min.x) / spacing)) + 1
	var z_steps := int(floor((field_max.y - field_min.y) / spacing)) + 1
	for z_index in range(z_steps):
		for x_index in range(x_steps):
			if transforms.size() >= max_instances:
				return transforms
			if rng.randf() > density:
				continue

			var point := Vector2(
				field_min.x + float(x_index) * spacing + rng.randf_range(-jitter, jitter),
				field_min.y + float(z_index) * spacing + rng.randf_range(-jitter, jitter)
			)
			if _is_inside_city_exclusion(point) or not _is_inside_playable_island(point):
				continue

			var hit := _sample_ground(point)
			if hit.is_empty():
				continue

			var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
			var local_position := to_local(hit_position)
			if local_position.y < min_ground_y or local_position.y > max_ground_y:
				continue
			local_position.y += ground_y_offset

			transforms.append(_make_grass_transform(local_position, rng))

	return transforms


func _sample_ground(point: Vector2) -> Dictionary:
	var from := to_global(Vector3(point.x, ground_ray_height, point.y))
	var to := to_global(Vector3(point.x, -ground_ray_depth, point.y))
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _make_grass_transform(local_position: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var rotation := rng.randf_range(0.0, TAU)
	var width_scale := rng.randf_range(scale_min, scale_max)
	var height_scale := rng.randf_range(height_scale_min, height_scale_max)
	var basis := Basis(Vector3.UP, rotation)
	basis = basis.scaled(Vector3(width_scale, height_scale, width_scale))
	return Transform3D(basis, local_position)


func _is_inside_city_exclusion(point: Vector2) -> bool:
	return (
		point.x >= city_exclusion_min.x
		and point.x <= city_exclusion_max.x
		and point.y >= city_exclusion_min.y
		and point.y <= city_exclusion_max.y
	)


func _is_inside_playable_island(point: Vector2) -> bool:
	var normalized := Vector2(point.x / island_radius.x, point.y / island_radius.y)
	return normalized.length_squared() <= 1.0


func _make_grass_aabb() -> AABB:
	var size := Vector3(
		field_max.x - field_min.x,
		max_ground_y - min_ground_y + 4.0,
		field_max.y - field_min.y
	)
	return AABB(Vector3(field_min.x, min_ground_y - 1.0, field_min.y), size)
