extends MeshInstance3D
class_name World

const RoadGraphScript = preload("res://Simulation/Navigation/RoadGraph.gd")
const PedestrianGraphScript = preload("res://Simulation/Navigation/PedestrianGraph.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

@export var minutes_per_tick: int = 1
@export var tick_interval_sec: float = 0.5
@export_range(0.1, 20.0, 0.1) var speed_multiplier: float = 1.0

var time: TimeSystem = TimeSystem.new()
var economy: EconomySystem = EconomySystem.new()
var road_graph = RoadGraphScript.new()
var pedestrian_graph = PedestrianGraphScript.new()

# Reserve account used as fallback / infrastructure sink.
var city_account: Account = Account.new()

var citizens: Array[Citizen] = []
var buildings: Array[Building] = []
var jobs: Array[Job] = []

var is_paused: bool = false

signal paused_changed(paused: bool)
signal speed_changed(multiplier: float)

var _timer: Timer

func _ready() -> void:
	#use_collision = true
	minutes_per_tick = BalanceConfig.get_int("world.minutes_per_tick", minutes_per_tick)
	tick_interval_sec = BalanceConfig.get_float("world.tick_interval_sec", tick_interval_sec)
	speed_multiplier = BalanceConfig.get_float("world.speed_multiplier", speed_multiplier)

	add_child(time)
	add_child(economy)

	city_account.owner_name = "CityReserve"
	city_account.balance = BalanceConfig.get_int("world.city_reserve_start_balance", 18000)

	_register_existing_scene_nodes(get_tree())

	_timer = Timer.new()
	speed_multiplier = maxf(speed_multiplier, 0.1)
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_refresh_timer_wait_time()

	time.payday.connect(_on_payday)
	time.day_changed.connect(_on_day_changed)

func _register_existing_scene_nodes(tree: SceneTree) -> void:
	if tree == null:
		return

	for node in tree.get_nodes_in_group("buildings"):
		if node is Building:
			register_building(node as Building)

	for node in tree.get_nodes_in_group("citizens"):
		if node is Citizen:
			var citizen := node as Citizen
			register_citizen(citizen)
			if citizen.job != null:
				register_job(citizen.job)

func _on_tick() -> void:
	if is_paused:
		return

	time.advance(minutes_per_tick)
	for citizen in citizens:
		if citizen != null:
			citizen.sim_tick(self)

func _on_day_changed(_day: int) -> void:
	# Daily economy cycle is executed after payday in _on_payday().
	# This keeps tax collection based on the previous day's finances
	# and prevents midnight production from being taxed immediately.
	pass

func _on_payday() -> void:
	SimLogger.log("\n=== PAYDAY (Day %d) ===" % world_day())

	var city_hall = find_city_hall()
	if city_hall != null:
		city_hall.collect_daily_taxes(self)

	var employed_count := 0
	for citizen in citizens:
		if citizen != null and citizen.job != null and citizen.job.workplace != null:
			employed_count += 1
	SimLogger.log("  [WORKFORCE] citizens=%d employed=%d unemployed=%d open_jobs=%d" % [
		citizens.size(),
		employed_count,
		citizens.size() - employed_count,
		get_open_jobs().size()
	])

	var welfare_total := 0
	var salaries_total := 0

	for citizen in citizens:
		if citizen == null:
			continue

		if citizen.job == null or citizen.job.workplace == null:
			var welfare: int = 40
			if _pay_welfare(citizen, welfare, city_hall):
				welfare_total += welfare
				var welfare_reason := citizen.get_unemployment_debug_reason() if citizen.has_method("get_unemployment_debug_reason") else "no job/workplace"
				SimLogger.log("  [WELFARE] %s +%d (%s)" % [citizen.citizen_name, welfare, welfare_reason])
			else:
				SimLogger.log("  [WELFARE-FAIL] %s could not be paid" % citizen.citizen_name)
			continue

		var hours_worked: float = citizen.work_minutes_today / 60.0
		var daily_wage: int = int(citizen.job.wage_per_hour * hours_worked)
		if daily_wage <= 0:
			var skip_reason := citizen.get_zero_pay_debug_reason() if citizen.has_method("get_zero_pay_debug_reason") else "no debug reason"
			SimLogger.log("  [SKIP] %s worked %.1fh -> no pay (%s)" % [citizen.citizen_name, hours_worked, skip_reason])
			continue

		var source := _pay_salary(citizen, daily_wage, city_hall)
		if source != "":
			salaries_total += daily_wage
			SimLogger.log("  [PAY:%s] %s +%d" % [source, citizen.citizen_name, daily_wage])
		else:
			SimLogger.log("  [PAY-FAIL] %s +%d could not be paid" % [citizen.citizen_name, daily_wage])

	if city_hall != null:
		city_hall.pay_infrastructure(self)

	SimLogger.log("  [SUMMARY] salaries=%d welfare=%d city_reserve=%d" % [
		salaries_total,
		welfare_total,
		city_account.balance
	])
	SimLogger.log("===========================\n")

	_rollover_building_finances()
	_run_daily_market_cycle()


func _run_daily_market_cycle() -> void:
	economy.begin_new_day()

	# 1) Producers generate raw supply for the market.
	for building in buildings:
		if building is CommercialBuilding:
			(building as CommercialBuilding).run_daily_production(self)

	# 2) Consumers/commercials restock from the market.
	for building2 in buildings:
		if building2 is CommercialBuilding:
			(building2 as CommercialBuilding).run_daily_supply(self)

func _pay_welfare(citizen: Citizen, amount: int, city_hall) -> bool:
	if city_hall != null and city_hall.pay_welfare(self, citizen, amount):
		return true
	return economy.transfer(city_account, citizen.wallet, amount)

func _pay_salary(citizen: Citizen, amount: int, city_hall) -> String:
	if amount <= 0:
		return ""

	var workplace: Building = citizen.job.workplace if citizen.job != null else null
	if workplace != null and economy.transfer(workplace.account, citizen.wallet, amount):
		workplace.record_expense(amount)
		return "work"

	if city_hall != null and city_hall.pay_salary(self, citizen, amount):
		return "city_hall"

	if economy.transfer(city_account, citizen.wallet, amount):
		return "reserve"

	return ""

func _rollover_building_finances() -> void:
	for building in buildings:
		if building != null:
			building.begin_new_day()

func toggle_pause() -> void:
	is_paused = not is_paused
	paused_changed.emit(is_paused)

func set_speed(multiplier: float) -> void:
	speed_multiplier = maxf(multiplier, 0.1)
	_refresh_timer_wait_time()
	speed_changed.emit(speed_multiplier)

func _refresh_timer_wait_time() -> void:
	if _timer == null:
		return
	_timer.wait_time = tick_interval_sec / maxf(speed_multiplier, 0.1)

func world_day() -> int:
	return time.day

func rebuild_road_graph(root: Node3D) -> void:
	if road_graph == null:
		road_graph = RoadGraphScript.new()
	road_graph.rebuild_from_scene(root)

func rebuild_pedestrian_graph(root: Node3D) -> void:
	if pedestrian_graph == null:
		pedestrian_graph = PedestrianGraphScript.new()
	pedestrian_graph.rebuild_from_scene(root, buildings)

func get_road_path(start_pos: Vector3, end_pos: Vector3) -> PackedVector3Array:
	if road_graph == null:
		return PackedVector3Array()
	return road_graph.find_path_points(start_pos, end_pos)

func get_pedestrian_path(start_pos: Vector3, end_pos: Vector3, start_building: Building = null, end_building: Building = null) -> PackedVector3Array:
	if pedestrian_graph != null and pedestrian_graph.has_graph():
		if pedestrian_graph.has_path_between(start_pos, end_pos, start_building, end_building):
			return pedestrian_graph.find_path_points(start_pos, end_pos, start_building, end_building)
	if not _is_navigation_map_ready():
		return PackedVector3Array()
	return get_navigation_path(start_pos, end_pos)

func get_pedestrian_access_point(pos: Vector3, building: Building = null) -> Vector3:
	if pedestrian_graph != null and pedestrian_graph.has_graph():
		return pedestrian_graph.get_access_point(pos, building)
	return _get_navigation_closest_point(pos)

func describe_pedestrian_path(points: PackedVector3Array) -> String:
	if pedestrian_graph != null and pedestrian_graph.has_method("describe_path"):
		return pedestrian_graph.describe_path(points)
	return "points=%d" % points.size()

func count_pedestrian_path_crosswalk_centers(points: PackedVector3Array) -> int:
	if pedestrian_graph != null and pedestrian_graph.has_method("count_crosswalk_centers"):
		return pedestrian_graph.count_crosswalk_centers(points)
	return 0

func get_pedestrian_path_point_kind(point: Vector3) -> String:
	if pedestrian_graph != null and pedestrian_graph.has_method("get_path_point_kind"):
		return pedestrian_graph.get_path_point_kind(point)
	return ""

func has_pedestrian_route(start_pos: Vector3, end_pos: Vector3, start_building: Building = null, end_building: Building = null) -> bool:
	if pedestrian_graph != null and pedestrian_graph.has_graph():
		if pedestrian_graph.has_path_between(start_pos, end_pos, start_building, end_building):
			return true
	if not _is_navigation_map_ready():
		return pedestrian_graph == null or not pedestrian_graph.has_graph()
	return get_navigation_path(start_pos, end_pos).size() >= 2

func get_pedestrian_component_id(pos: Vector3, building: Building = null) -> int:
	if pedestrian_graph == null:
		return 0
	return pedestrian_graph.get_component_id_for_pos(pos, building)

func get_world_bounds() -> AABB:
	if mesh != null:
		return _transform_aabb_to_world(mesh.get_aabb())
	return AABB(global_position - Vector3(40.0, 1.0, 40.0), Vector3(80.0, 2.0, 80.0))

func get_world_center() -> Vector3:
	var bounds := get_world_bounds()
	return bounds.position + bounds.size * 0.5

func get_ground_fallback_y() -> float:
	var ground_y := _get_registered_ground_y()
	if ground_y != INF:
		return ground_y + 0.02

	var bounds := get_world_bounds()
	return bounds.position.y + bounds.size.y * 0.5

func register_citizen(citizen: Citizen) -> void:
	if citizen == null or citizens.has(citizen):
		return
	citizens.append(citizen)
	citizen.set_world_ref(self)

func register_building(building: Building) -> void:
	if building == null or buildings.has(building):
		return
	buildings.append(building)

func register_job(job: Job) -> void:
	if job == null or jobs.has(job):
		return
	jobs.append(job)
	economy.register_job(job)

func get_open_jobs() -> Array[Job]:
	return economy.get_open_jobs()

func find_city_hall() -> CityHall:
	for building in buildings:
		if building is CityHall:
			return building as CityHall
	return null

func find_available_residential_building(from_pos: Vector3 = Vector3.ZERO) -> ResidentialBuilding:
	var best: ResidentialBuilding = null
	var best_load := INF
	var best_dist := INF

	for building in buildings:
		if building is not ResidentialBuilding:
			continue
		var residential := building as ResidentialBuilding
		if not residential.has_free_slot():
			continue

		var load := float(residential.tenants.size()) / float(maxi(residential.capacity, 1))
		var dist := from_pos.distance_to(residential.global_position)
		if load < best_load or (is_equal_approx(load, best_load) and dist < best_dist):
			best_load = load
			best_dist = dist
			best = residential

	return best

func find_first_residential_building() -> ResidentialBuilding:
	return find_available_residential_building(Vector3.ZERO)

func find_nearest_restaurant(from_pos: Vector3, require_open: bool = true) -> Restaurant:
	return find_preferred_restaurant(from_pos, null, require_open)

func find_preferred_restaurant(from_pos: Vector3, excluded_citizen: Citizen = null, require_open: bool = true) -> Restaurant:
	var best: Restaurant = null
	var best_score := INF
	for building in buildings:
		if building is not Restaurant:
			continue
		var restaurant := building as Restaurant
		if require_open and not restaurant.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, restaurant):
			continue

		var capacity := float(maxi(restaurant.capacity, 1))
		var assigned_count := _count_citizen_building_preference("favorite_restaurant", restaurant, excluded_citizen)
		var current_load := float(assigned_count + restaurant.visitors.size()) / capacity
		var score := current_load * 1000.0 + from_pos.distance_to(restaurant.global_position)
		if score < best_score:
			best_score = score
			best = restaurant
	return best

func find_nearest_shop(from_pos: Vector3, require_open: bool = true) -> Shop:
	var best: Shop = null
	var best_dist := INF
	for building in buildings:
		if building is not Shop:
			continue
		if building is Supermarket:
			continue
		var shop := building as Shop
		if require_open and not shop.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, shop):
			continue
		var dist := from_pos.distance_to(shop.global_position)
		if dist < best_dist:
			best_dist = dist
			best = shop
	return best

func find_nearest_cinema(from_pos: Vector3, require_open: bool = true) -> Cinema:
	var best: Cinema = null
	var best_dist := INF
	for building in buildings:
		if building is not Cinema:
			continue
		var cinema := building as Cinema
		if require_open and not cinema.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, cinema):
			continue
		var dist := from_pos.distance_to(cinema.global_position)
		if dist < best_dist:
			best_dist = dist
			best = cinema
	return best
func find_nearest_park(from_pos: Vector3) -> Building:
	var best: Building = null
	var best_dist := INF
	for building in buildings:
		if building == null:
			continue
		if not building.is_in_group("parks"):
			continue
		if not _is_building_pedestrian_reachable(from_pos, building):
			continue
		var dist := from_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	return best

func find_nearest_supermarket(from_pos: Vector3, require_open: bool = true) -> Supermarket:
	var best: Supermarket = null
	var best_dist := INF
	for building in buildings:
		if building is not Supermarket:
			continue
		var market := building as Supermarket
		if require_open and not market.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, market):
			continue
		var dist := from_pos.distance_to(market.global_position)
		if dist < best_dist:
			best_dist = dist
			best = market
	return best

func find_nearest_university(from_pos: Vector3, require_open: bool = true) -> University:
	var best: University = null
	var best_dist := INF
	for building in buildings:
		if building is not University:
			continue
		var uni := building as University
		if require_open and not uni.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, uni):
			continue
		var dist := from_pos.distance_to(uni.global_position)
		if dist < best_dist:
			best_dist = dist
			best = uni
	return best

func find_nearest_building_with_service(from_pos: Vector3, service_type: String, require_open: bool = true) -> Building:
	var best: Building = null
	var best_dist := INF
	for building in buildings:
		if building == null:
			continue
		if building.get_service_type() != service_type:
			continue
		if require_open and not building.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, building):
			continue
		var dist := from_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	return best

func find_nearest_open_workplace(from_pos: Vector3, workplace_name_filter: String = "", workplace_service_type_filter: String = "") -> Building:
	var best: Building = null
	var best_dist := INF

	for building in buildings:
		if building == null:
			continue
		if not building.has_free_job_slots():
			continue
		if workplace_name_filter != "" and building.building_name != workplace_name_filter:
			continue
		if workplace_service_type_filter != "" and building.get_service_type() != workplace_service_type_filter:
			continue
		if not _is_building_pedestrian_reachable(from_pos, building):
			continue

		var dist := from_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building

	return best

func is_building_pedestrian_reachable(from_pos: Vector3, building: Building) -> bool:
	return _is_building_pedestrian_reachable(from_pos, building)

func _is_building_pedestrian_reachable(from_pos: Vector3, building: Building) -> bool:
	if building == null:
		return false
	return has_pedestrian_route(from_pos, building.get_entrance_pos(), null, building)

func get_navigation_path(start_pos: Vector3, end_pos: Vector3) -> PackedVector3Array:
	if not _is_navigation_map_ready():
		return PackedVector3Array()
	var navigation_map := _get_navigation_map()
	if not navigation_map.is_valid():
		return PackedVector3Array()

	var nav_start := NavigationServer3D.map_get_closest_point(navigation_map, start_pos)
	var nav_end := NavigationServer3D.map_get_closest_point(navigation_map, end_pos)
	var nav_path := NavigationServer3D.map_get_path(navigation_map, nav_start, nav_end, true)
	var route := PackedVector3Array()

	_append_route_point(route, start_pos)

	if nav_path.is_empty():
		if nav_start.distance_to(nav_end) > 0.5:
			return PackedVector3Array()
	else:
		for point in nav_path:
			_append_route_point(route, point)

	_append_route_point(route, end_pos)
	if route.size() < 2:
		return PackedVector3Array()
	return route

func _get_navigation_map() -> RID:
	if not is_inside_tree():
		return RID()
	var world_3d := get_world_3d()
	if world_3d == null:
		return RID()
	if world_3d.has_method("get_navigation_map"):
		return world_3d.get_navigation_map()
	return world_3d.navigation_map

func _get_navigation_closest_point(pos: Vector3) -> Vector3:
	if not _is_navigation_map_ready():
		return pos
	var navigation_map := _get_navigation_map()
	if not navigation_map.is_valid():
		return pos
	return NavigationServer3D.map_get_closest_point(navigation_map, pos)

func _append_route_point(route: PackedVector3Array, point: Vector3) -> void:
	if route.is_empty() or route[route.size() - 1].distance_to(point) >= 0.05:
		route.append(point)

func _is_navigation_map_ready() -> bool:
	var navigation_map := _get_navigation_map()
	if not navigation_map.is_valid():
		return false
	return NavigationServer3D.map_get_iteration_id(navigation_map) > 0

func _count_citizen_building_preference(property_name: String, building: Building, excluded_citizen: Citizen = null) -> int:
	if building == null or property_name.is_empty():
		return 0

	var count := 0
	for citizen in citizens:
		if citizen == null or citizen == excluded_citizen:
			continue
		if citizen.get(property_name) == building:
			count += 1
	return count

func _get_registered_ground_y() -> float:
	var best_y := INF
	for building in buildings:
		if building == null:
			continue
		best_y = minf(best_y, building.global_position.y)
	if best_y != INF:
		return best_y

	for road in get_tree().get_nodes_in_group("road_group"):
		if road is Node3D:
			best_y = minf(best_y, (road as Node3D).global_position.y)
	return best_y

func _transform_aabb_to_world(local_bounds: AABB) -> AABB:
	var corners := [
		local_bounds.position,
		local_bounds.position + Vector3(local_bounds.size.x, 0.0, 0.0),
		local_bounds.position + Vector3(0.0, local_bounds.size.y, 0.0),
		local_bounds.position + Vector3(0.0, 0.0, local_bounds.size.z),
		local_bounds.position + Vector3(local_bounds.size.x, local_bounds.size.y, 0.0),
		local_bounds.position + Vector3(local_bounds.size.x, 0.0, local_bounds.size.z),
		local_bounds.position + Vector3(0.0, local_bounds.size.y, local_bounds.size.z),
		local_bounds.position + local_bounds.size,
	]

	var min_corner := Vector3(INF, INF, INF)
	var max_corner := Vector3(-INF, -INF, -INF)
	for corner in corners:
		var world_corner := to_global(corner)
		min_corner.x = minf(min_corner.x, world_corner.x)
		min_corner.y = minf(min_corner.y, world_corner.y)
		min_corner.z = minf(min_corner.z, world_corner.z)
		max_corner.x = maxf(max_corner.x, world_corner.x)
		max_corner.y = maxf(max_corner.y, world_corner.y)
		max_corner.z = maxf(max_corner.z, world_corner.z)

	return AABB(min_corner, max_corner - min_corner)
