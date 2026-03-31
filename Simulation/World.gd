extends MeshInstance3D
class_name World

const RoadGraphScript = preload("res://Simulation/Navigation/RoadGraph.gd")
const PedestrianGraphScript = preload("res://Simulation/Navigation/PedestrianGraph.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const CitizenFactoryScript = preload("res://Simulation/Factories/CitizenFactory.gd")
const CITY_BENCH_NAME_HINTS := ["bench", "bank", "seat", "sit"]
const CITY_BENCH_RESERVATIONS_META := "_world_city_bench_reservations"

@export var minutes_per_tick: int = 1
@export var tick_interval_sec: float = 0.5
@export_range(0.1, 20.0, 0.1) var speed_multiplier: float = 1.0

var time: TimeSystem = TimeSystem.new()
var economy: EconomySystem = EconomySystem.new()
var road_graph = RoadGraphScript.new()
var pedestrian_graph = PedestrianGraphScript.new()

# Reserve/infrastructure account used as a visible sink for public-system costs.
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

	var city_hall := find_city_hall()
	if city_hall != null:
		city_hall.collect_daily_taxes(self)
		city_hall.ensure_operating_liquidity(self, "payday_start")
		city_hall.fund_public_buildings(self)

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
	var operating_total := 0
	var maintenance_total := 0

	for building in buildings:
		if building == null or not building.requires_public_funding():
			continue
		var operating_before := building.operating_costs_today
		if building.pay_base_operating_cost(self):
			operating_total += building.operating_costs_today - operating_before
			continue
		operating_total += building.operating_costs_today - operating_before

	for citizen in citizens:
		if citizen == null:
			continue

		if citizen.job == null or citizen.job.workplace == null:
			var welfare: int = city_hall.unemployment_support if city_hall != null else 0
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
			if citizen.job != null and citizen.job.workplace != null:
				citizen.job.workplace.record_unpaid_wages(daily_wage)
			SimLogger.log("  [PAY-FAIL] %s +%d could not be paid" % [citizen.citizen_name, daily_wage])

	for building in buildings:
		if building == null:
			continue
		building.apply_daily_condition_decay()
		var maintenance_before := building.maintenance_today
		var maintenance_ok := building.pay_daily_maintenance(self)
		var maintenance_paid_today := building.maintenance_today - maintenance_before
		maintenance_total += maintenance_paid_today
		if not maintenance_ok and building.has_maintenance_staff():
			var maintenance_shortfall := maxi(building.maintenance_cost_per_day - maintenance_paid_today, 0)
			building.record_unpaid_maintenance(maintenance_shortfall)

	if city_hall != null:
		city_hall.pay_infrastructure(self)

	var struggling_buildings := 0
	var closed_buildings := 0
	for building in buildings:
		if building == null:
			continue
		building.finalize_daily_financial_state(self)
		if building.is_financially_closed():
			closed_buildings += 1
		elif building.is_struggling() or building.is_underfunded():
			struggling_buildings += 1
		SimLogger.log("  [BUILDING] %s" % building.get_daily_finance_log_summary())

	SimLogger.log("  [SUMMARY] salaries=%d welfare=%d operating=%d maintenance=%d city_hall_balance=%d city_reserve_balance=%d reserve_transfers_today=%d public_funding_requested=%d public_funding_paid=%d struggling_buildings=%d closed_buildings=%d" % [
		salaries_total,
		welfare_total,
		operating_total,
		maintenance_total,
		city_hall.account.balance if city_hall != null else 0,
		city_account.balance,
		city_hall.reserve_transfer_amount_today if city_hall != null else 0,
		city_hall.public_funding_requested_total_today if city_hall != null else 0,
		city_hall.public_funding_total_today if city_hall != null else 0,
		struggling_buildings,
		closed_buildings
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
	if amount <= 0:
		return false
	if city_hall != null and city_hall.pay_welfare(self, citizen, amount):
		return true
	return false

func _pay_salary(citizen: Citizen, amount: int, _city_hall) -> String:
	if amount <= 0:
		return ""

	var workplace: Building = citizen.job.workplace if citizen.job != null else null
	if workplace is CityHall:
		(workplace as CityHall).ensure_operating_liquidity(self, "city_hall_payroll")
	if workplace != null and economy.pay_to_wallet(workplace.account, citizen, amount):
		workplace.record_wage_expense(amount)
		return "work"

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

func _is_building_temporarily_blocked_for(building: Building, seeker: Citizen = null) -> bool:
	if building == null or seeker == null:
		return false
	if seeker.has_method("is_building_temporarily_unreachable"):
		return seeker.is_building_temporarily_unreachable(building, self)
	return false

func find_nearest_restaurant(from_pos: Vector3, require_open: bool = true, seeker: Citizen = null) -> Restaurant:
	return find_preferred_restaurant(from_pos, null, require_open, seeker)

func find_preferred_restaurant(from_pos: Vector3, excluded_citizen: Citizen = null, require_open: bool = true, seeker: Citizen = null) -> Restaurant:
	var best: Restaurant = null
	var best_score := INF
	for building in buildings:
		if building is not Restaurant:
			continue
		var restaurant := building as Restaurant
		if _is_building_temporarily_blocked_for(restaurant, seeker):
			continue
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

func find_nearest_shop(from_pos: Vector3, require_open: bool = true, seeker: Citizen = null) -> Shop:
	var best: Shop = null
	var best_dist := INF
	for building in buildings:
		if building is not Shop:
			continue
		if building is Supermarket:
			continue
		var shop := building as Shop
		if _is_building_temporarily_blocked_for(shop, seeker):
			continue
		if require_open and not shop.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, shop):
			continue
		var dist := from_pos.distance_to(shop.global_position)
		if dist < best_dist:
			best_dist = dist
			best = shop
	return best

func find_nearest_cinema(from_pos: Vector3, require_open: bool = true, seeker: Citizen = null) -> Cinema:
	var best: Cinema = null
	var best_dist := INF
	for building in buildings:
		if building is not Cinema:
			continue
		var cinema := building as Cinema
		if _is_building_temporarily_blocked_for(cinema, seeker):
			continue
		if require_open and not cinema.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, cinema):
			continue
		var dist := from_pos.distance_to(cinema.global_position)
		if dist < best_dist:
			best_dist = dist
			best = cinema
	return best
func find_nearest_park(from_pos: Vector3, seeker: Citizen = null) -> Building:
	var best: Building = null
	var best_dist := INF
	for building in buildings:
		if building == null:
			continue
		if not building.is_in_group("parks"):
			continue
		if _is_building_temporarily_blocked_for(building, seeker):
			continue
		if not _is_building_pedestrian_reachable(from_pos, building):
			continue
		var dist := from_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	return best

func has_available_city_bench_for(citizen = null, reference_pos: Vector3 = Vector3.ZERO) -> bool:
	if not get_reserved_city_bench_for(citizen).is_empty():
		return true
	_prune_invalid_city_bench_reservations()
	return _find_best_city_bench(reference_pos) != null

func reserve_city_bench_for(citizen, reference_pos: Vector3 = Vector3.ZERO) -> Dictionary:
	if citizen == null:
		return {}

	var existing: Dictionary = get_reserved_city_bench_for(citizen)
	if not existing.is_empty():
		return existing

	_prune_invalid_city_bench_reservations()
	var best_bench := _find_best_city_bench(reference_pos)
	if best_bench == null:
		return {}

	var reservations := _get_city_bench_reservations()
	reservations[best_bench.get_instance_id()] = weakref(citizen)
	_set_city_bench_reservations(reservations)
	return _build_city_bench_reservation(best_bench)

func get_reserved_city_bench_for(citizen) -> Dictionary:
	if citizen == null:
		return {}

	_prune_invalid_city_bench_reservations()
	var reservations := _get_city_bench_reservations()
	for bench_id in reservations.keys():
		if _resolve_reserved_city_bench_citizen(reservations[bench_id]) != citizen:
			continue
		var bench := instance_from_id(int(bench_id)) as Node3D
		if bench == null or not is_instance_valid(bench):
			continue
		return _build_city_bench_reservation(bench)
	return {}

func release_city_bench_for(citizen) -> void:
	if citizen == null:
		return
	var reservations := _get_city_bench_reservations()
	var release_keys: Array[int] = []
	for bench_id in reservations.keys():
		if _resolve_reserved_city_bench_citizen(reservations[bench_id]) == citizen:
			release_keys.append(int(bench_id))
	for bench_id in release_keys:
		reservations.erase(bench_id)
	if not release_keys.is_empty():
		_set_city_bench_reservations(reservations)

func is_citizen_at_reserved_city_bench(citizen) -> bool:
	if citizen == null:
		return false
	var bench: Dictionary = get_reserved_city_bench_for(citizen)
	if bench.is_empty():
		return false
	var bench_pos: Vector3 = bench.get("position", citizen.global_position)
	var delta: Vector3 = citizen.global_position - bench_pos
	delta.y = 0.0
	if delta.length() <= 0.45:
		return true
	if citizen.has_method("has_active_rest_pose") and citizen.has_active_rest_pose():
		return true
	return false

func find_nearest_supermarket(from_pos: Vector3, require_open: bool = true, seeker: Citizen = null) -> Supermarket:
	var best: Supermarket = null
	var best_dist := INF
	for building in buildings:
		if building is not Supermarket:
			continue
		var market := building as Supermarket
		if _is_building_temporarily_blocked_for(market, seeker):
			continue
		if require_open and not market.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, market):
			continue
		var dist := from_pos.distance_to(market.global_position)
		if dist < best_dist:
			best_dist = dist
			best = market
	return best

func _find_best_city_bench(reference_pos: Vector3) -> Node3D:
	var best_bench: Node3D = null
	var best_score := INF
	for bench in _get_city_bench_nodes():
		if not _is_city_bench_available(bench):
			continue
		var score := bench.global_position.distance_squared_to(reference_pos)
		if score < best_score:
			best_score = score
			best_bench = bench
	return best_bench

func _get_city_bench_nodes() -> Array[Node3D]:
	var benches: Array[Node3D] = []
	if not is_inside_tree():
		return benches
	_collect_city_bench_nodes(get_tree().get_root(), benches)
	return benches

func _collect_city_bench_nodes(node: Node, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D:
			var marker := child as Node3D
			if _is_city_bench_marker_node(marker):
				out.append(marker)
		if child is Node:
			_collect_city_bench_nodes(child, out)

func _is_city_bench_marker_node(node: Node3D) -> bool:
	if node == null:
		return false
	if node.get_script() != null:
		return false
	if node.get_child_count() > 0:
		return false
	if _is_node_inside_park(node):
		return false
	var name_lower := node.name.to_lower()
	for hint in CITY_BENCH_NAME_HINTS:
		if name_lower.contains(hint):
			return true
	return false

func _is_city_bench_available(bench: Node3D) -> bool:
	if bench == null or not is_instance_valid(bench):
		return false
	var reservations := _get_city_bench_reservations()
	var bench_id := bench.get_instance_id()
	if not reservations.has(bench_id):
		return true
	return _resolve_reserved_city_bench_citizen(reservations[bench_id]) == null

func _build_city_bench_reservation(bench: Node3D) -> Dictionary:
	if bench == null:
		return {}
	return {
		"node": bench,
		"name": bench.name,
		"position": bench.global_position,
		"yaw": bench.global_rotation.y,
		"building": _find_bench_owner_building(bench),
	}

func _get_city_bench_reservations() -> Dictionary:
	if not has_meta(CITY_BENCH_RESERVATIONS_META):
		set_meta(CITY_BENCH_RESERVATIONS_META, {})
	var reservations: Variant = get_meta(CITY_BENCH_RESERVATIONS_META)
	if reservations is Dictionary:
		return reservations as Dictionary
	var fresh: Dictionary = {}
	set_meta(CITY_BENCH_RESERVATIONS_META, fresh)
	return fresh

func _set_city_bench_reservations(reservations: Dictionary) -> void:
	set_meta(CITY_BENCH_RESERVATIONS_META, reservations)

func _resolve_reserved_city_bench_citizen(value) -> Node:
	if value is WeakRef:
		var citizen: Node = (value as WeakRef).get_ref() as Node
		if citizen != null and is_instance_valid(citizen):
			return citizen
	return null

func _prune_invalid_city_bench_reservations() -> void:
	var reservations := _get_city_bench_reservations()
	var stale_keys: Array[int] = []
	for bench_id in reservations.keys():
		var bench := instance_from_id(int(bench_id)) as Node3D
		if bench == null or not is_instance_valid(bench):
			stale_keys.append(int(bench_id))
			continue
		if _resolve_reserved_city_bench_citizen(reservations[bench_id]) == null:
			stale_keys.append(int(bench_id))
	for bench_id in stale_keys:
		reservations.erase(bench_id)
	if not stale_keys.is_empty():
		_set_city_bench_reservations(reservations)

func _is_node_inside_park(node: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current is Node and current.is_in_group("parks"):
			return true
		current = current.get_parent()
	return false

func _find_bench_owner_building(node: Node) -> Building:
	var current := node.get_parent()
	while current != null:
		if current is Building:
			return current as Building
		current = current.get_parent()
	return null

func find_nearest_university(from_pos: Vector3, require_open: bool = true, seeker: Citizen = null) -> University:
	var best: University = null
	var best_dist := INF
	for building in buildings:
		if building is not University:
			continue
		var uni := building as University
		if _is_building_temporarily_blocked_for(uni, seeker):
			continue
		if require_open and not uni.is_open(time.get_hour()):
			continue
		if not _is_building_pedestrian_reachable(from_pos, uni):
			continue
		var dist := from_pos.distance_to(uni.global_position)
		if dist < best_dist:
			best_dist = dist
			best = uni
	return best

func find_nearest_building_with_service(from_pos: Vector3, service_type: String, require_open: bool = true, seeker: Citizen = null) -> Building:
	var best: Building = null
	var best_dist := INF
	for building in buildings:
		if building == null:
			continue
		if _is_building_temporarily_blocked_for(building, seeker):
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

func find_nearest_open_workplace(from_pos: Vector3, workplace_name_filter: String = "", workplace_service_type_filter: String = "", seeker: Citizen = null) -> Building:
	var best: Building = null
	var best_dist := INF

	for building in buildings:
		if building == null:
			continue
		if _is_building_temporarily_blocked_for(building, seeker):
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

func find_best_workplace_for_job(from_pos: Vector3, job: Job, seeker: Citizen = null) -> Building:
	if job == null:
		return null

	var best: Building = null
	var best_dist := INF

	for building in buildings:
		if building == null:
			continue
		if _is_building_temporarily_blocked_for(building, seeker):
			continue
		if not building.has_free_job_slots():
			continue
		if not job.allows_building(building):
			continue
		if not _is_building_pedestrian_reachable(from_pos, building):
			continue

		var building_pos := building.global_position if building.is_inside_tree() else building.position
		var dist := from_pos.distance_to(building_pos)
		if dist < best_dist:
			best_dist = dist
			best = building

	return best

func find_best_job_offer_for_citizen(from_pos: Vector3, citizen: Citizen, allow_training: bool = true) -> Dictionary:
	if citizen == null:
		return {}

	var best_fit: Dictionary = {}
	var best_fit_score := -INF
	var best_training: Dictionary = {}
	var best_training_score := -INF

	for building in buildings:
		if building == null:
			continue
		if _is_building_temporarily_blocked_for(building, citizen):
			continue
		if not building.has_free_job_slots():
			continue
		if not _is_building_pedestrian_reachable(from_pos, building):
			continue

		for job_title in _get_candidate_job_titles_for_building(building):
			var offer := _build_job_offer_for_citizen(citizen, building, job_title, from_pos)
			if offer.is_empty():
				continue
			var education_gap := int(offer.get("education_gap", 0))
			var offer_score := float(offer.get("score", -INF))
			if education_gap <= 0:
				if offer_score > best_fit_score:
					best_fit_score = offer_score
					best_fit = offer
			elif allow_training and offer_score > best_training_score:
				best_training_score = offer_score
				best_training = offer

	if not best_fit.is_empty():
		return best_fit
	if allow_training:
		return best_training
	return {}

func _build_job_offer_for_citizen(citizen: Citizen, building: Building, job_title: String, from_pos: Vector3) -> Dictionary:
	if citizen == null or building == null or job_title.is_empty():
		return {}

	var allowed_types := CitizenFactoryScript.get_allowed_building_types_for_job_title(job_title)
	if not allowed_types.is_empty() and not allowed_types.has(building.building_type):
		return {}

	var required_education := CitizenFactoryScript.get_required_education_for_job_title(job_title)
	var education_gap := maxi(required_education - citizen.education_level, 0)
	var offer_score := _score_job_offer_for_citizen(citizen, building, job_title, from_pos, education_gap)

	return {
		"title": job_title,
		"building": building,
		"required_education_level": required_education,
		"education_gap": education_gap,
		"wage_per_hour": CitizenFactoryScript.get_wage_for_job_title(job_title),
		"allowed_building_types": allowed_types.duplicate(),
		"score": offer_score,
	}

func _score_job_offer_for_citizen(
	citizen: Citizen,
	building: Building,
	job_title: String,
	from_pos: Vector3,
	education_gap: int
) -> float:
	var distance := from_pos.distance_to(building.get_entrance_pos())
	var free_slots := maxi(building.job_capacity - building.workers.size(), 0)
	var score := 0.0
	var university_missing_teaching := false
	var park_missing_gardener := false
	if building.building_type == Building.BuildingType.UNIVERSITY:
		university_missing_teaching = building.get_workers_by_titles(["Professor", "Teacher"]).is_empty()
	if building.building_type == Building.BuildingType.PARK:
		park_missing_gardener = building.get_workers_by_titles(["Gardener"]).is_empty()

	score -= distance * 1.6
	score += float(maxi(free_slots, 1)) * 40.0
	score += 240.0 if education_gap <= 0 else -170.0 * float(education_gap)

	if building.is_public_building():
		score += 260.0
	if building.requires_staff_to_operate() and not building.has_required_staff():
		score += 520.0
	if building.workers.is_empty():
		score += 120.0
	if building.is_underfunded():
		score -= 90.0
	elif building.is_struggling():
		score -= 45.0

	match building.building_type:
		Building.BuildingType.UNIVERSITY:
			if job_title == "Teacher":
				score += 900.0 if university_missing_teaching else 120.0
			elif job_title == "Professor":
				score += 620.0 if university_missing_teaching else 80.0
			elif job_title == "Janitor" or job_title == "MaintenanceWorker":
				score += 200.0
		Building.BuildingType.PARK:
			if job_title == "Gardener":
				score += 520.0 if park_missing_gardener else 90.0
		Building.BuildingType.CITY_HALL:
			if job_title == "Programmierer" or job_title == "Technician":
				score += 250.0
		Building.BuildingType.FACTORY:
			if job_title == "Technician" or job_title == "Engineer":
				score += 180.0

	if citizen.job != null and citizen.job.title == job_title:
		score += 30.0

	return score

func _get_candidate_job_titles_for_building(building: Building) -> Array[String]:
	if building == null:
		return []

	match building.building_type:
		Building.BuildingType.UNIVERSITY:
			return ["Teacher", "Professor", "Janitor", "MaintenanceWorker"]
		Building.BuildingType.PARK:
			return ["Gardener", "MaintenanceWorker", "Janitor"]
		Building.BuildingType.CITY_HALL:
			return ["Programmierer", "Technician", "Janitor", "Doctor", "MaintenanceWorker"]
		Building.BuildingType.RESTAURANT, Building.BuildingType.CAFE:
			return ["Kellner", "Baecker", "Janitor", "MaintenanceWorker"]
		Building.BuildingType.SHOP, Building.BuildingType.SUPERMARKET:
			return ["Verkaeufer", "Janitor", "MaintenanceWorker"]
		Building.BuildingType.CINEMA:
			return ["Designer", "Janitor", "MaintenanceWorker"]
		Building.BuildingType.FACTORY:
			return ["Engineer", "Technician", "Mechaniker", "Fahrer", "MaintenanceWorker"]
		Building.BuildingType.FARM:
			return ["Fahrer", "Mechaniker", "Gardener", "MaintenanceWorker"]
		Building.BuildingType.RESIDENTIAL:
			return ["Janitor", "MaintenanceWorker"]
		_:
			return ["MaintenanceWorker", "Janitor"]

func is_building_pedestrian_reachable(from_pos: Vector3, building: Building) -> bool:
	return _is_building_pedestrian_reachable(from_pos, building)

func _is_building_pedestrian_reachable(from_pos: Vector3, building: Building) -> bool:
	if building == null:
		return false
	if building.has_method("has_navigation_entry") and not building.has_navigation_entry():
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

	var tree := get_tree()
	if tree == null:
		return best_y

	for road in tree.get_nodes_in_group("road_group"):
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
