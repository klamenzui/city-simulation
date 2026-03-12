extends Node3D

@export var model_name: String

func _ready() -> void:
	var is_road = model_name.begins_with("road")
	# 1) Referenz auf einen MeshInstance3D in der Szene
	var mesh_instance: MeshInstance3D = find_mesh(self)
	var mesh: Mesh = mesh_instance.mesh

	# 2) Einen StaticBody3D (oder RigidBody3D) erzeugen und in die Szene hängen
	var static_body = StaticBody3D.new()
	if is_road:
		static_body.collision_layer = 2  # Andere Bit-Maske
	else:
		static_body.collision_layer = 1  # Standard
	add_child(static_body)
	
	# 3) CollisionShape3D erzeugen und an den Body hängen
	var collision_shape = CollisionShape3D.new()
	static_body.add_child(collision_shape)

	# 4) Aus dem Mesh ein Trimesh-Shape generieren
	# (verwendet man meist für statische und eher komplexe 3D-Modelle)
	if mesh:
		var shape = mesh.create_trimesh_shape()
		collision_shape.shape = shape

func find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
		
	for child in node.get_children():
		var mesh := find_mesh(child)
		if mesh:
			return mesh
			
	return null
