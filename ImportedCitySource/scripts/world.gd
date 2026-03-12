extends Node3D
var rng = RandomNumberGenerator.new()

@export var house_scene: PackedScene
@export var plant_scene: PackedScene
@export var car_scene: PackedScene
var world: Node3D = self
func _ready() -> void:
	rng.randomize()
	
@export var block_size := 4
@export var city_size := 3
@export var grid_size := 2

@export var traffic_enabled := true
@export var car_count := 5
# Ð¡ÑÑ‹Ð»ÐºÐ° Ð½Ð° Ð¼ÐµÐ½ÐµÐ´Ð¶ÐµÑ€ Ñ‚Ñ€Ð°Ñ„Ð¸ÐºÐ°
var traffic_manager
var buildings = {}
var plants = {}
func generate_city():
	generate_roads()
	#generate_houses()
	# Ð•ÑÐ»Ð¸ Ð²ÐºÐ»ÑŽÑ‡ÐµÐ½ Ñ‚Ñ€Ð°Ñ„Ð¸Ðº, ÑÐ¾Ð·Ð´Ð°ÐµÐ¼ Ð¼ÐµÐ½ÐµÐ´Ð¶ÐµÑ€ Ñ‚Ñ€Ð°Ñ„Ð¸ÐºÐ°
	if traffic_enabled:
		generate_traffic()

func generate_roads():
	var road_builder: RoadBuilder = RoadBuilder.new(world)
	road_builder.road_map.clear()
	
	var total_size: int = city_size * (block_size + 1)
	
	# Horizontale und vertikale StraÃŸenpositionen sammeln
	for i in range(city_size + 1):
		var offset: int = i * (block_size + 1)
		for j in range(total_size + 1):
			road_builder.road_map[Vector2(j, offset) * grid_size] = null  # Horizontale StraÃŸen
			road_builder.road_map[Vector2(offset, j) * grid_size] = null  # Vertikale StraÃŸen
	for i in range(total_size + 1):
		for j in range(total_size + 1):
			plants[Vector2(i, j) * grid_size] = null  # Vertikale StraÃŸen
	#var c = 158
	# StraÃŸen platzieren - erst verbundene StraÃŸen, damit Verbindungen korrekt erkannt werden
	for pos in road_builder.road_map:
		road_builder.build(pos)
		#c-=1
		#if c < 0:
		#	break
	road_builder.decorate_all()
	for pos in road_builder.road_map:
		var road = road_builder.get_road(pos)
		if not road:
			continue
		for s in road.connections:
			var neighbor_pos = road.connections[s]
			if neighbor_pos == null:
				neighbor_pos = pos + road_builder.sides_positions[s]
				if buildings.get(neighbor_pos):
					continue
				var house = house_scene.instantiate().duplicate()
				var building_type = Building.BuildingType.MIX
				if road.crossing != null:
					building_type = Building.BuildingType.COMMERCIAL
				#elif randi() % 2 + 1 == 2:
				#	building_type = Building.BuildingType.RESIDENTIAL
				
				house.build(building_type)
				var building_direction = road_builder.get_opposite_direction(s)
				house.rotate_y(road_builder.get_rotation_for_direction(building_direction))
				house.position = Vector3(neighbor_pos.x, 0, neighbor_pos.y)
				buildings[neighbor_pos] = true
				add_child(house)
	for pos in plants:
		if road_builder.get_road(pos) or buildings.get(pos):
			continue
		var plant: Node3D = plant_scene.instantiate().duplicate()
		plant.plant(Plant.PlantType.TREE if randi() % 2 == 0 else Plant.PlantType.BUSH)
		plant.rotate_y(deg_to_rad(randi() % 360 + 1))
		plant.position = Vector3(pos.x, 0, pos.y)
		plants[pos] = true
		add_child(plant)

func clear_current_city():
	# Ð£Ð´Ð°Ð»ÐµÐ½Ð¸Ðµ Ð´Ð¾Ñ€Ð¾Ð³
	var roads = get_tree().get_nodes_in_group("road")
	for road in roads:
		road.queue_free()
	
	# Ð£Ð´Ð°Ð»ÐµÐ½Ð¸Ðµ Ð´ÐµÐºÐ¾Ñ€Ð°Ñ†Ð¸Ð¹
	var decos = get_tree().get_nodes_in_group("deco")
	for deco in decos:
		deco.queue_free()
	
	# Ð£Ð´Ð°Ð»ÐµÐ½Ð¸Ðµ Ð·Ð´Ð°Ð½Ð¸Ð¹
	var house_nodes = get_tree().get_nodes_in_group("building")
	for house in house_nodes:
		house.queue_free()
		
	var plant = get_tree().get_nodes_in_group("plant")
	for p in plant:
		p.queue_free()
	
	# Ð£Ð´Ð°Ð»ÐµÐ½Ð¸Ðµ Ñ‚Ñ€Ð°Ð½ÑÐ¿Ð¾Ñ€Ñ‚Ð°
	var traffic = get_tree().get_nodes_in_group("traffic")
	for car in traffic:
		car.queue_free()
		
	# Ð¡Ð±Ñ€Ð¾Ñ ÑÐ»Ð¾Ð²Ð°Ñ€Ñ Ð·Ð´Ð°Ð½Ð¸Ð¹
	buildings.clear()
	# Ð•ÑÐ»Ð¸ ÐµÑÑ‚ÑŒ Ð¼ÐµÐ½ÐµÐ´Ð¶ÐµÑ€ Ñ‚Ñ€Ð°Ñ„Ð¸ÐºÐ°, ÑƒÐ´Ð°Ð»ÑÐµÐ¼ ÐµÐ³Ð¾
	if traffic_manager:
		traffic_manager.queue_free()
		traffic_manager = null
	


# Ð“ÐµÐ½ÐµÑ€Ð°Ñ†Ð¸Ñ Ð°Ð²Ñ‚Ð¾Ð¼Ð¾Ð±Ð¸Ð»ÐµÐ¹ Ð´Ð»Ñ ÑÐ¸Ð¼ÑƒÐ»ÑÑ†Ð¸Ð¸ Ñ‚Ñ€Ð°Ñ„Ð¸ÐºÐ°
func generate_traffic():
	if not traffic_enabled or car_count <= 0:
		print("Ð¢Ñ€Ð°Ñ„Ð¸Ðº Ð¾Ñ‚ÐºÐ»ÑŽÑ‡ÐµÐ½ Ð¸Ð»Ð¸ ÐºÐ¾Ð»Ð¸Ñ‡ÐµÑÑ‚Ð²Ð¾ Ð°Ð²Ñ‚Ð¾Ð¼Ð¾Ð±Ð¸Ð»ÐµÐ¹ Ñ€Ð°Ð²Ð½Ð¾ Ð½ÑƒÐ»ÑŽ")
		return
	
	print("Ð˜Ð½Ð¸Ñ†Ð¸Ð°Ð»Ð¸Ð·Ð°Ñ†Ð¸Ñ ÑÐ¸ÑÑ‚ÐµÐ¼Ñ‹ Ñ‚Ñ€Ð°Ñ„Ð¸ÐºÐ° Ñ ", car_count, " Ð°Ð²Ñ‚Ð¾Ð¼Ð¾Ð±Ð¸Ð»ÑÐ¼Ð¸")
	
	# Ð¡Ð¾Ð·Ð´Ð°ÐµÐ¼ Ð¼ÐµÐ½ÐµÐ´Ð¶ÐµÑ€ Ñ‚Ñ€Ð°Ñ„Ð¸ÐºÐ°
	traffic_manager = load("res://ImportedCitySource/scripts/traffic_manager.gd").new()
	traffic_manager.name = "TrafficManager"
	
	# ÐÐ°ÑÑ‚Ñ€Ð°Ð¸Ð²Ð°ÐµÐ¼ Ð¿Ð°Ñ€Ð°Ð¼ÐµÑ‚Ñ€Ñ‹ Ñ‚Ñ€Ð°Ñ„Ð¸ÐºÐ°
	traffic_manager.vehicle_count = car_count
	traffic_manager.city_generator_path = self.get_path()
	
	# Ð”Ð¾Ð±Ð°Ð²Ð»ÑÐµÐ¼ Ð¼Ð¾Ð´ÐµÐ»ÑŒ Ð°Ð²Ñ‚Ð¾Ð¼Ð¾Ð±Ð¸Ð»Ñ Ð² Ð¼ÐµÐ½ÐµÐ´Ð¶ÐµÑ€
	if car_scene:
		traffic_manager.vehicle_models.append(car_scene)
	else:
		# ÐŸÐ¾Ð¿Ñ€Ð¾Ð±ÑƒÐµÐ¼ Ð½Ð°Ð¹Ñ‚Ð¸ Ð°Ð²Ñ‚Ð¾Ð¼Ð¾Ð±Ð¸Ð»ÑŒ Ð² Ñ€ÐµÑÑƒÑ€ÑÐ°Ñ… Ð¿Ñ€Ð¾ÐµÐºÑ‚Ð°
		var default_car = load("res://ImportedCitySource/scenes/car_police.tscn")
		if default_car:
			traffic_manager.vehicle_models.append(default_car)
		else:
			push_error("ÐžÑˆÐ¸Ð±ÐºÐ°: Ð½Ðµ Ð½Ð°Ð¹Ð´ÐµÐ½Ð° Ð¼Ð¾Ð´ÐµÐ»ÑŒ Ð°Ð²Ñ‚Ð¾Ð¼Ð¾Ð±Ð¸Ð»Ñ!")
			return
	
	# Ð”Ð¾Ð±Ð°Ð²Ð»ÑÐµÐ¼ Ð¼ÐµÐ½ÐµÐ´Ð¶ÐµÑ€ Ñ‚Ñ€Ð°Ñ„Ð¸ÐºÐ° Ð² ÑÑ†ÐµÐ½Ñƒ
	add_child(traffic_manager)
	
	print("ÐœÐµÐ½ÐµÐ´Ð¶ÐµÑ€ Ñ‚Ñ€Ð°Ñ„Ð¸ÐºÐ° Ð¸Ð½Ð¸Ñ†Ð¸Ð°Ð»Ð¸Ð·Ð¸Ñ€Ð¾Ð²Ð°Ð½")
