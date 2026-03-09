extends CSGBox3D
class_name World

@export var minutes_per_tick: int = 10
@export var tick_interval_sec: float = 0.5

var time: TimeSystem = TimeSystem.new()
var economy: EconomySystem = EconomySystem.new()

# Reserve account used as fallback / infrastructure sink.
var city_account: Account = Account.new()

var citizens: Array[Citizen] = []
var buildings: Array[Building] = []
var jobs: Array[Job] = []

var is_paused: bool = false
var speed_multiplier: float = 1.0

signal paused_changed(paused: bool)
signal speed_changed(multiplier: float)

var _timer: Timer

func _ready() -> void:
	use_collision = true

	add_child(time)
	add_child(economy)

	city_account.owner_name = "CityReserve"
	city_account.balance = 18000

	_register_existing_scene_nodes(get_tree())

	_timer = Timer.new()
	_timer.wait_time = tick_interval_sec
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)

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
	# Hook for future global day-based systems.
	pass

func _on_payday() -> void:
	print("\n=== PAYDAY (Day %d) ===" % world_day())

	var city_hall = find_city_hall()
	if city_hall != null:
		city_hall.collect_daily_taxes(self)

	var welfare_total := 0
	var salaries_total := 0

	for citizen in citizens:
		if citizen == null:
			continue

		if citizen.job == null or citizen.job.workplace == null:
			var welfare: int = 40
			if _pay_welfare(citizen, welfare, city_hall):
				welfare_total += welfare
				print("  [WELFARE] %s +%d" % [citizen.citizen_name, welfare])
			else:
				print("  [WELFARE-FAIL] %s could not be paid" % citizen.citizen_name)
			continue

		var hours_worked: float = citizen.work_minutes_today / 60.0
		var daily_wage: int = int(citizen.job.wage_per_hour * hours_worked)
		if daily_wage <= 0:
			print("  [SKIP] %s worked %.1fh -> no pay" % [citizen.citizen_name, hours_worked])
			continue

		var source := _pay_salary(citizen, daily_wage, city_hall)
		if source != "":
			salaries_total += daily_wage
			print("  [PAY:%s] %s +%d" % [source, citizen.citizen_name, daily_wage])
		else:
			print("  [PAY-FAIL] %s +%d could not be paid" % [citizen.citizen_name, daily_wage])

	if city_hall != null:
		city_hall.pay_infrastructure(self)

	print("  [SUMMARY] salaries=%d welfare=%d city_reserve=%d" % [
		salaries_total,
		welfare_total,
		city_account.balance
	])
	print("===========================\n")

	_rollover_building_finances()

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
	_timer.wait_time = tick_interval_sec / speed_multiplier
	speed_changed.emit(speed_multiplier)

func world_day() -> int:
	return time.day

func get_ground_fallback_y() -> float:
	var world_height := size.y * absf(scale.y)
	return global_position.y + (world_height * 0.5) + 0.01

func register_citizen(citizen: Citizen) -> void:
	if citizen == null or citizens.has(citizen):
		return
	citizens.append(citizen)

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

func find_first_residential_building() -> ResidentialBuilding:
	for building in buildings:
		if building is ResidentialBuilding:
			return building as ResidentialBuilding
	return null

func find_nearest_restaurant(from_pos: Vector3, require_open: bool = true) -> Restaurant:
	var best: Restaurant = null
	var best_dist := INF
	for building in buildings:
		if building is not Restaurant:
			continue
		var restaurant := building as Restaurant
		if require_open and not restaurant.is_open(time.get_hour()):
			continue
		var dist := from_pos.distance_to(restaurant.global_position)
		if dist < best_dist:
			best_dist = dist
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
		var dist := from_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	return best

func find_nearest_open_workplace(from_pos: Vector3, workplace_name_filter: String = "") -> Building:
	var best: Building = null
	var best_dist := INF

	for building in buildings:
		if building == null:
			continue
		if not building.has_free_job_slots():
			continue
		if workplace_name_filter != "" and building.building_name != workplace_name_filter:
			continue

		var dist := from_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building

	return best
