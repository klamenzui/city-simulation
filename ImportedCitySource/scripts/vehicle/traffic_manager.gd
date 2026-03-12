extends Node3D

# Fahrzeug & Verkehrseinstellungen
@export var vehicle_count = 5
@export var min_speed = 2.0
@export var max_speed = 4.0
@export var vehicle_models: Array[PackedScene] = []
@export var vehicle_scale = Vector3(1, 1, 1)
@export var vehicle_height = 0.3
@export var right_lane_offset = 0.3
@export var left_lane_offset = -0.3

@export var city_generator_path: NodePath
var city_generator

# Navigation & Straßen
var vehicles = []
var road_points = []
var astar = AStar3D.new()

# Debug
@export var debug_mode = false
var debug_markers = []

func _ready():
	if city_generator_path:
		city_generator = get_node(city_generator_path)
	
	await get_tree().create_timer(0.5).timeout
	generate_route_points()
	
	if debug_mode:
		visualize_route_points()
	
	spawn_vehicles()

func generate_route_points():
	road_points.clear()
	astar.clear()

	var road_nodes = get_tree().get_nodes_in_group("road")
	var point_id = 0

	for road in road_nodes:
		var road_pos = road.global_position
		var road_forward = -road.global_transform.basis.z

		# Rechte Spur
		var right_lane = road_pos + road_forward.cross(Vector3.UP).normalized() * right_lane_offset
		var left_lane = road_pos - road_forward.cross(Vector3.UP).normalized() * left_lane_offset
		
		road_points.append({"position": right_lane, "lane": "right", "road": road})
		road_points.append({"position": left_lane, "lane": "left", "road": road})

		astar.add_point(point_id, right_lane)
		astar.add_point(point_id + 1, left_lane)

		if point_id > 0:
			astar.connect_points(point_id - 2, point_id)
			astar.connect_points(point_id - 1, point_id + 1)
		
		point_id += 2

func spawn_vehicles():
	if vehicle_models.is_empty():
		push_error("Keine Fahrzeugmodelle!")
		return

	if road_points.is_empty():
		push_error("Keine Straßenpunkte!")
		return

	for i in range(vehicle_count):
		var vehicle_scene = vehicle_models[randi() % vehicle_models.size()]
		var vehicle = vehicle_scene.instantiate()

		vehicle.name = "Vehicle_" + str(i)
		vehicle.add_to_group("traffic")
		vehicle.scale = vehicle_scale

		var start_index = randi() % road_points.size()
		vehicle.global_position = road_points[start_index]["position"]

		vehicle.set_meta("current_point", start_index)
		vehicle.set_meta("speed", randf_range(min_speed, max_speed))
		vehicle.set_meta("target_path", calculate_path(start_index))
		vehicle.set_meta("path_index", 0)

		add_child(vehicle)
		vehicles.append(vehicle)

func calculate_path(start_index):
	var target_index = randi() % road_points.size()
	return astar.get_point_path(start_index, target_index)

func _physics_process(delta):
	for vehicle in vehicles:
		if not is_instance_valid(vehicle):
			continue
		move_vehicle(vehicle, delta)

func move_vehicle(vehicle, delta):
	var path = vehicle.get_meta("target_path")
	var path_index = vehicle.get_meta("path_index")
	var speed = vehicle.get_meta("speed")

	if path_index >= len(path) - 1:
		vehicle.set_meta("target_path", calculate_path(vehicle.get_meta("current_point")))
		vehicle.set_meta("path_index", 0)
		return

	var target_pos = path[path_index]
	var direction = (target_pos - vehicle.global_position).normalized()
	
	# Kollisionserkennung für realistischeres Fahrverhalten
	var safe_speed = check_for_obstacles(vehicle, direction, speed)

	vehicle.global_position += direction * safe_speed * delta

	if vehicle.global_position.distance_to(target_pos) < 0.5:
		vehicle.set_meta("path_index", path_index + 1)

func check_for_obstacles(vehicle, direction, base_speed):
	var detection_distance = 3.0
	var adjusted_speed = base_speed

	for other in vehicles:
		if other == vehicle:
			continue
		
		var to_other = other.global_position - vehicle.global_position
		var distance = to_other.length()
		var is_ahead = direction.dot(to_other.normalized()) > 0.7

		if is_ahead and distance < detection_distance:
			var slow_factor = clamp(distance / detection_distance, 0.2, 1.0)
			adjusted_speed *= slow_factor

	return adjusted_speed

func visualize_route_points():
	for point in road_points:
		var marker = create_debug_marker(point["position"])
		debug_markers.append(marker)
		add_child(marker)

func create_debug_marker(position):
	var marker = Node3D.new()
	var mesh_instance = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.2
	mesh_instance.mesh = mesh
	marker.add_child(mesh_instance)
	marker.global_position = position
	return marker
