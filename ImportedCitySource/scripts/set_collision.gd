extends Node3D

@onready var data_node = load("res://ImportedCitySource/scripts/data/data_node.gd")
var map: Resource

func _set_nodes(parent) -> void:
	# if not Engine.is_editor_hint():
	# 	return  # Only run in editor
	for categorie: Node3D in parent.get_children():
		for node: Node3D in categorie.get_children():
			if node.get_child_count() > 0:
				# node.set_script(data_node)
				_set_collision(node)

func _ready() -> void:
	_set_nodes(self)

func find_mesh(node: Node, parent: Node = null) -> Array:
	if node is MeshInstance3D:
		return [node, parent]

	for child in node.get_children():
		var res = find_mesh(child, node)
		if res[0] != null:
			return res

	return [null, null]

func _set_collision(parent) -> void:
	if _has_existing_physics_body(parent):
		return

	var result = find_mesh(parent)
	var mesh_instance := result[0] as MeshInstance3D
	var parent_node := result[1] as Node3D
	if mesh_instance == null or parent_node == null:
		return

	var mesh_tmp: Mesh = mesh_instance.mesh
	if mesh_tmp == null:
		return

	var static_body := StaticBody3D.new()
	parent_node.add_child(static_body)
	static_body.transform = mesh_instance.transform

	var collision_shape := CollisionShape3D.new()
	static_body.add_child(collision_shape)
	collision_shape.shape = mesh_tmp.create_trimesh_shape()

func _has_existing_physics_body(node: Node) -> bool:
	if node == null:
		return false

	for child in node.get_children():
		if child is StaticBody3D or child is RigidBody3D or child is CharacterBody3D:
			return true
		if _has_existing_physics_body(child):
			return true
	return false
