extends Node3D

@onready var data_node = load("res://ImportedCitySource/scripts/data/data_node.gd")
var map: Resource

func _set_nodes(parent, node_name) -> void:
	#if not Engine.is_editor_hint():
	#	return  # Nur im Editor ausfÃ¼hren
	var count = 0
	node_name = node_name.to_lower()
	for node: Node3D in parent.get_children():
		if node.get_child_count() > 0:
			var child0 = node.get_child(0)
			var model_name = child0.name
			if model_name.to_lower() == node_name:
				var pos = node.position
				var rot = node.rotation
				node.hide()
				var pc: PackedScene = load("res://ImportedCitySource/scenes/"+node_name+"_active.tscn")
				var new_node = pc.instantiate()
				new_node.position = pos
				new_node.rotation = rot
				#node.set_script(data_node)
				#node.model_name = model_name
				new_node.name = model_name + str(count)
				new_node.add_to_group("model_name:" + model_name + str(count))
				parent.add_child(new_node)
				count += 1

func _ready() -> void:
	self._set_nodes($Streetlight, "streetlight")
	self._set_nodes($Trafficlight, "trafficlight_c")

	

func find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
		
	for child in node.get_children():
		var mesh := find_mesh(child)
		if mesh:
			return mesh
			
	return null

func map_save():
	
	print("Saving map...")
	#map.structures.clear()
	#var guards = get_tree().get_nodes_in_group("guards")
	#for guard in guards:
	#	map.guards.append(guard.transform)
	ResourceSaver.save(map, "res://ImportedCitySource/map.res")

func map_load():
	print("Loading map...")
	#map.structures.clear()
	map = ResourceLoader.load("res://ImportedCitySource/map.res")
	if not map:
		map = DataMap.new()
	#for cell in map_data.structures:
		#cell.biome = randi_range(Biomes.RAINFOREST, Biomes.DESERT)
		#var index = get_structure_index_by_id(cell.structure_id)
	#	set_grid_item(cell)
	
	#is_map_edited = true
func set_collision(node):
	var model_name = node.model_name
	print(model_name)
	node.node_type = get_node_type(model_name)
	var is_road = get_node_type(model_name) == "road"
	# 1) Referenz auf einen MeshInstance3D in der Szene
	var mesh_instance: MeshInstance3D = find_mesh(node)
	var mesh: Mesh = mesh_instance.mesh

	# 2) Einen StaticBody3D (oder RigidBody3D) erzeugen und in die Szene hÃ¤ngen
	var static_body = StaticBody3D.new()
	if is_road:
		node.transform.origin.y = 0
		static_body.collision_layer = 2  # Andere Bit-Maske
	else:
		static_body.collision_layer = 1  # Standard
	node.add_child(static_body)
	
	# 3) CollisionShape3D erzeugen und an den Body hÃ¤ngen
	var collision_shape = CollisionShape3D.new()
	static_body.add_child(collision_shape)

	# 4) Aus dem Mesh ein Trimesh-Shape generieren
	# (verwendet man meist fÃ¼r statische und eher komplexe 3D-Modelle)
	if mesh:
		var shape = mesh.create_trimesh_shape()
		collision_shape.shape = shape


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
