extends Node3D

@onready var data_node = load("res://ImportedCitySource/scripts/data/data_node.gd")
var map: Resource

func _set_nodes(parent) -> void:
	#if not Engine.is_editor_hint():
	#	return  # Nur im Editor ausfÃ¼hren
	for categorie: Node3D in parent.get_children():
		for node: Node3D in categorie.get_children():
			if node.get_child_count() > 0:
				#node.set_script(data_node)
				_set_collision(node)

func _ready() -> void:
	self._set_nodes(self)

func find_mesh(node: Node, parent: Node = null) -> Array:
	if node is MeshInstance3D:
		return [node, parent]

	for child in node.get_children():
		var res = find_mesh(child, node)
		if res[0] != null:
			return res

	return [null, null]  # Immer ein Array zurÃ¼ckgeben

func _set_collision(parent) -> void:
	#var is_road = model_name.begins_with("road")
	# 1) Referenz auf einen MeshInstance3D in der Szene
	var result = find_mesh(parent)
	var mesh_instance = result[0]
	var parent_node = result[1]
	if !mesh_instance:
		return
	#var new_node: Node3D = Node3D.new()
	#new_node.add_child(mesh_instance)
	#new_node.position = parent_node.position
	#new_node.rotation = parent_node.rotation
	#parent_node.hide()

	var mesh_tmp: Mesh = mesh_instance.mesh

	# 2) Einen StaticBody3D (oder RigidBody3D) erzeugen und in die Szene hÃ¤ngen
	var static_body = StaticBody3D.new()
	#if is_road:
	#	static_body.collision_layer = 2  # Andere Bit-Maske
	#else:
	#static_body.collision_layer = 1  # Standard
	#new_node.add_child(static_body)
	parent_node.add_child(static_body)
	
	# 3) CollisionShape3D erzeugen und an den Body hÃ¤ngen
	var collision_shape = CollisionShape3D.new()
	collision_shape.scale = mesh_instance.scale
	static_body.add_child(collision_shape)

	# 4) Aus dem Mesh ein Trimesh-Shape generieren
	# (verwendet man meist fÃ¼r statische und eher komplexe 3D-Modelle)
	if mesh_tmp:
		var shape = mesh_tmp.create_trimesh_shape()
		collision_shape.shape = shape
