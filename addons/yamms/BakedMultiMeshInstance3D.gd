@tool
extends MultiMeshInstance3D
class_name BakedMultiMeshInstance3D

@export_storage var baked_mesh: Mesh
@export_storage var baked_instance_count: int = 0
@export_storage var baked_visible_instance_count: int = 0
@export_storage var baked_buffer: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_restore_baked_multimesh_if_needed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_cache_baked_multimesh()
		multimesh = null
		return
	if what == NOTIFICATION_EDITOR_POST_SAVE:
		_restore_baked_multimesh_if_needed()


func _reset_multimesh_instance_counts() -> void:
	if multimesh == null:
		return
	multimesh.instance_count = 0
	multimesh.visible_instance_count = 0


func _restore_baked_multimesh_if_needed() -> void:
	if baked_mesh == null or baked_instance_count <= 0 or baked_buffer.is_empty():
		return
	if multimesh != null and multimesh.instance_count > 0:
		return
	var restored_multimesh := MultiMesh.new()
	restored_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	restored_multimesh.mesh = baked_mesh
	restored_multimesh.instance_count = baked_instance_count
	restored_multimesh.buffer = baked_buffer
	var visible_count := baked_visible_instance_count
	if visible_count <= 0:
		visible_count = baked_instance_count
	restored_multimesh.visible_instance_count = clampi(visible_count, 0, baked_instance_count)
	multimesh = restored_multimesh


func _cache_baked_multimesh() -> void:
	if multimesh == null or multimesh.instance_count <= 0:
		if baked_instance_count <= 0:
			_clear_baked_multimesh()
		return
	baked_mesh = multimesh.mesh
	baked_instance_count = multimesh.instance_count
	baked_visible_instance_count = multimesh.visible_instance_count
	baked_buffer = _get_multimesh_buffer_for_storage()


func _clear_baked_multimesh() -> void:
	baked_mesh = null
	baked_instance_count = 0
	baked_visible_instance_count = 0
	baked_buffer = PackedFloat32Array()


func _get_multimesh_buffer_for_storage() -> PackedFloat32Array:
	var existing_buffer := multimesh.buffer
	if not existing_buffer.is_empty():
		return existing_buffer
	return _build_3d_transform_buffer_from_instances()


func _build_3d_transform_buffer_from_instances() -> PackedFloat32Array:
	var packed_buffer := PackedFloat32Array()
	if multimesh == null or multimesh.instance_count <= 0:
		return packed_buffer
	packed_buffer.resize(multimesh.instance_count * 12)
	for index in range(multimesh.instance_count):
		var transform := multimesh.get_instance_transform(index)
		var offset := index * 12
		packed_buffer[offset] = transform.basis.x.x
		packed_buffer[offset + 1] = transform.basis.y.x
		packed_buffer[offset + 2] = transform.basis.z.x
		packed_buffer[offset + 3] = transform.origin.x
		packed_buffer[offset + 4] = transform.basis.x.y
		packed_buffer[offset + 5] = transform.basis.y.y
		packed_buffer[offset + 6] = transform.basis.z.y
		packed_buffer[offset + 7] = transform.origin.y
		packed_buffer[offset + 8] = transform.basis.x.z
		packed_buffer[offset + 9] = transform.basis.y.z
		packed_buffer[offset + 10] = transform.basis.z.z
		packed_buffer[offset + 11] = transform.origin.z
	return packed_buffer
