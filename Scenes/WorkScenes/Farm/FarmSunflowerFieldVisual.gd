extends Node3D
class_name FarmSunflowerFieldVisual

const COLUMN_COUNT := 5
const ROW_COUNT := 7
const PETALS_PER_FLOWER := 10
const PLANT_COUNT := COLUMN_COUNT * ROW_COUNT
const FIELD_HALF_WIDTH := 2.35
const FIELD_HALF_DEPTH := 3.25
const STEM_HEIGHT := 1.1
const HEAD_HEIGHT := 1.16

var _stems: MultiMeshInstance3D = null
var _leaves: MultiMeshInstance3D = null
var _petals: MultiMeshInstance3D = null
var _centers: MultiMeshInstance3D = null


func _ready() -> void:
	_build_crop()
	set_crop_progress(false, 0.0)


func set_crop_progress(show_crop: bool, growth_ratio: float) -> void:
	visible = show_crop
	if not show_crop:
		return
	var ratio := clampf(growth_ratio, 0.0, 1.0)
	var horizontal_scale := lerpf(0.72, 1.0, ratio)
	scale = Vector3(horizontal_scale, lerpf(0.16, 1.0, ratio), horizontal_scale)
	if _leaves != null:
		_leaves.visible = ratio >= 0.16
	var show_heads := ratio >= 0.55
	if _petals != null:
		_petals.visible = show_heads
	if _centers != null:
		_centers.visible = show_heads


func get_crop_nodes() -> Array[MultiMeshInstance3D]:
	return [_stems, _leaves, _petals, _centers]


func _build_crop() -> void:
	if _stems != null:
		return
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.035
	stem_mesh.bottom_radius = 0.045
	stem_mesh.height = STEM_HEIGHT
	stem_mesh.radial_segments = 6
	stem_mesh.rings = 1
	stem_mesh.material = _make_material(Color(0.18, 0.43, 0.11), false)

	var leaf_mesh := QuadMesh.new()
	leaf_mesh.size = Vector2(0.24, 0.38)
	leaf_mesh.material = _make_material(Color(0.24, 0.52, 0.13), true)

	var petal_mesh := QuadMesh.new()
	petal_mesh.size = Vector2(0.105, 0.24)
	petal_mesh.material = _make_material(Color(1.0, 0.62, 0.035), true)

	var center_mesh := CylinderMesh.new()
	center_mesh.top_radius = 0.14
	center_mesh.bottom_radius = 0.14
	center_mesh.height = 0.075
	center_mesh.radial_segments = 10
	center_mesh.rings = 1
	center_mesh.material = _make_material(Color(0.27, 0.105, 0.025), false)

	_stems = _make_multimesh_instance("Stems", stem_mesh, PLANT_COUNT)
	_leaves = _make_multimesh_instance("Leaves", leaf_mesh, PLANT_COUNT * 2)
	_petals = _make_multimesh_instance("Petals", petal_mesh, PLANT_COUNT * PETALS_PER_FLOWER)
	_centers = _make_multimesh_instance("Centers", center_mesh, PLANT_COUNT)
	_populate_instances()


func _populate_instances() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 20260710
	var plant_index := 0
	for row in range(ROW_COUNT):
		for column in range(COLUMN_COUNT):
			var x_ratio := float(column) / float(maxi(COLUMN_COUNT - 1, 1))
			var z_ratio := float(row) / float(maxi(ROW_COUNT - 1, 1))
			var plant_position := Vector3(
				lerpf(-FIELD_HALF_WIDTH, FIELD_HALF_WIDTH, x_ratio) + random.randf_range(-0.11, 0.11),
				0.0,
				lerpf(-FIELD_HALF_DEPTH, FIELD_HALF_DEPTH, z_ratio) + random.randf_range(-0.12, 0.12)
			)
			var plant_scale := random.randf_range(0.88, 1.08)
			var yaw_basis := Basis(Vector3.UP, random.randf_range(-0.32, 0.32))
			_set_plant_instances(plant_index, plant_position, plant_scale, yaw_basis, random)
			plant_index += 1


func _set_plant_instances(
	plant_index: int,
	plant_position: Vector3,
	plant_scale: float,
	yaw_basis: Basis,
	random: RandomNumberGenerator
) -> void:
	var stem_basis := Basis().scaled(Vector3(plant_scale, plant_scale, plant_scale))
	_stems.multimesh.set_instance_transform(
		plant_index,
		Transform3D(stem_basis, plant_position + Vector3.UP * STEM_HEIGHT * plant_scale * 0.5)
	)
	_stems.multimesh.set_instance_color(plant_index, Color(random.randf_range(0.88, 1.0), 1.0, 0.88, 1.0))

	for leaf_offset in range(2):
		var side := -1.0 if leaf_offset == 0 else 1.0
		var leaf_index := plant_index * 2 + leaf_offset
		var leaf_angle := side * deg_to_rad(34.0)
		var leaf_basis := yaw_basis * Basis(Vector3.FORWARD, leaf_angle)
		leaf_basis = leaf_basis.scaled(Vector3(plant_scale, plant_scale, plant_scale))
		var local_offset := Vector3(side * 0.115, 0.43 + float(leaf_offset) * 0.24, 0.0) * plant_scale
		_leaves.multimesh.set_instance_transform(
			leaf_index,
			Transform3D(leaf_basis, plant_position + yaw_basis * local_offset)
		)
		_leaves.multimesh.set_instance_color(leaf_index, Color(0.9, random.randf_range(0.9, 1.0), 0.86, 1.0))

	var head_position := plant_position + Vector3.UP * HEAD_HEIGHT * plant_scale
	var head_plane_basis := yaw_basis * Basis(Vector3.RIGHT, deg_to_rad(-20.0))
	var center_basis := yaw_basis * Basis(Vector3.RIGHT, deg_to_rad(70.0))
	center_basis = center_basis.scaled(Vector3(plant_scale, plant_scale, plant_scale))
	_centers.multimesh.set_instance_transform(plant_index, Transform3D(center_basis, head_position))
	_centers.multimesh.set_instance_color(plant_index, Color(random.randf_range(0.84, 1.0), 0.9, 0.82, 1.0))

	for petal_offset in range(PETALS_PER_FLOWER):
		var petal_index := plant_index * PETALS_PER_FLOWER + petal_offset
		var angle := TAU * float(petal_offset) / float(PETALS_PER_FLOWER)
		var petal_basis := head_plane_basis * Basis(Vector3.FORWARD, angle)
		petal_basis = petal_basis.scaled(Vector3(plant_scale, plant_scale, plant_scale))
		var radial_offset := head_plane_basis * Vector3(cos(angle) * 0.19, sin(angle) * 0.19, -0.012)
		_petals.multimesh.set_instance_transform(
			petal_index,
			Transform3D(petal_basis, head_position + radial_offset * plant_scale)
		)
		_petals.multimesh.set_instance_color(petal_index, Color(1.0, random.randf_range(0.88, 1.0), 0.78, 1.0))


func _make_multimesh_instance(
	node_name: String,
	mesh: Mesh,
	instance_count: int
) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	# Format and color flags must be configured while the instance count is zero.
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = instance_count
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	return instance


func _make_material(color: Color, double_sided: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
