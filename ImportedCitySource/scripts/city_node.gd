extends Node3D

@export var model_name: String

func _ready() -> void:
	var is_road := model_name.begins_with("road")
	if _has_existing_physics_body(self):
		return

	var result := find_mesh(self)
	var mesh_instance := result[0] as MeshInstance3D
	var parent_node := result[1] as Node3D
	if mesh_instance == null or parent_node == null or mesh_instance.mesh == null:
		return

	var static_body := StaticBody3D.new()
	static_body.collision_layer = 2 if is_road else 1
	parent_node.add_child(static_body)
	static_body.transform = mesh_instance.transform

	var collision_shape := CollisionShape3D.new()
	static_body.add_child(collision_shape)
	collision_shape.shape = mesh_instance.mesh.create_trimesh_shape()

func find_mesh(node: Node, parent: Node = null) -> Array:
	if node is MeshInstance3D:
		return [node, parent]

	for child in node.get_children():
		var result := find_mesh(child, node)
		if result[0] != null:
			return result

	return [null, null]

func _has_existing_physics_body(node: Node) -> bool:
	if node == null:
		return false

	for child in node.get_children():
		if child is StaticBody3D or child is RigidBody3D or child is CharacterBody3D:
			return true
		if _has_existing_physics_body(child):
			return true
	return false
