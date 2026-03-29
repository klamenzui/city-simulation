extends Node3D

@onready var data_node = load("res://ImportedCitySource/scripts/data/data_node.gd")
var map: Resource

func _set_nodes(parent, node_name) -> void:
	var count := 0
	node_name = node_name.to_lower()
	for node: Node3D in parent.get_children():
		if node.get_child_count() == 0:
			continue
		var child0 := node.get_child(0)
		var model_name := child0.name
		if model_name.to_lower() != node_name:
			continue

		var pos := node.position
		var rot := node.rotation
		var scl := node.scale
		node.hide()

		var pc: PackedScene = load("res://ImportedCitySource/scenes/" + node_name + "_active.tscn")
		var new_node := pc.instantiate() as Node3D
		if new_node == null:
			continue
		new_node.position = pos
		new_node.rotation = rot
		new_node.scale = scl
		new_node.name = model_name + str(count)
		new_node.add_to_group("model_name:" + model_name + str(count))
		parent.add_child(new_node)
		count += 1

func _ready() -> void:
	_set_nodes($Streetlight, "streetlight")
	_set_nodes($Trafficlight, "trafficlight_c")

func find_mesh(node: Node, parent: Node = null) -> Array:
	if node is MeshInstance3D:
		return [node, parent]

	for child in node.get_children():
		var result := find_mesh(child, node)
		if result[0] != null:
			return result

	return [null, null]

func map_save():
	print("Saving map...")
	ResourceSaver.save(map, "res://ImportedCitySource/map.res")

func map_load():
	print("Loading map...")
	map = ResourceLoader.load("res://ImportedCitySource/map.res")
	if not map:
		map = DataMap.new()

func set_collision(node):
	var model_name = node.model_name
	print(model_name)
	node.node_type = get_node_type(model_name)
	var is_road = get_node_type(model_name) == "road"
	if _has_existing_physics_body(node):
		return

	var result := find_mesh(node)
	var mesh_instance := result[0] as MeshInstance3D
	var parent_node := result[1] as Node3D
	if mesh_instance == null or parent_node == null or mesh_instance.mesh == null:
		return

	var static_body := StaticBody3D.new()
	if is_road:
		node.transform.origin.y = 0
		static_body.collision_layer = 2
	else:
		static_body.collision_layer = 1
	parent_node.add_child(static_body)
	static_body.transform = mesh_instance.transform

	var collision_shape := CollisionShape3D.new()
	static_body.add_child(collision_shape)
	collision_shape.shape = mesh_instance.mesh.create_trimesh_shape()

func _has_existing_physics_body(node: Node) -> bool:
	if node == null:
		return false

	for child in node.get_children():
		if child is StaticBody3D or child is RigidBody3D or child is CharacterBody3D:
			return true
		if _has_existing_physics_body(child):
			return true
	return false

func get_node_type(model_name: String) -> String:
	if model_name.begins_with("tree") or model_name.begins_with("bush"):
		return "plant"
	if model_name.begins_with("base"):
		return "base"
	if model_name.begins_with("building"):
		return "building"
	if model_name.begins_with("trafficlight"):
		return "trafficlight"
	if model_name.begins_with("streetlight"):
		return "streetlight"
	if model_name.begins_with("road"):
		return "road"
	return "none"
