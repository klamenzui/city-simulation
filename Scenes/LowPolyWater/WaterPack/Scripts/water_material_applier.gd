@tool
extends Node
class_name WaterMaterialApplier

@export var search_root_path: NodePath = ^".."
@export var water_material: Material
@export var name_keywords: PackedStringArray = PackedStringArray(["water", "ocean", "sea"])
@export var material_keywords: PackedStringArray = PackedStringArray(["water", "ocean", "sea"])
@export var apply_on_ready: bool = true

func _ready() -> void:
	if apply_on_ready:
		apply_water_material()

func apply_water_material() -> void:
	if water_material == null:
		return
	var root := get_node_or_null(search_root_path)
	if root == null:
		root = get_parent()
	if root == null:
		return
	_apply_recursive(root)

func _apply_recursive(node: Node) -> void:
	if node is MeshInstance3D and _looks_like_water(node as MeshInstance3D):
		(node as MeshInstance3D).material_override = water_material
	for child in node.get_children():
		_apply_recursive(child)

func _looks_like_water(mesh_instance: MeshInstance3D) -> bool:
	var node_name := mesh_instance.name.to_lower()
	for keyword in name_keywords:
		if node_name.contains(str(keyword).to_lower()):
			return true
	var mesh := mesh_instance.mesh
	if mesh == null:
		return false
	for i in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(i)
		if mat != null:
			var mat_name := mat.resource_name.to_lower()
			for keyword in material_keywords:
				if mat_name.contains(str(keyword).to_lower()):
					return true
	return false
