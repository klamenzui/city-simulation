extends SceneTree

const MainScene := preload("res://Main.tscn")
const BuyGroceriesActionScript := preload("res://Actions/BuyGroceriesAction.gd")
const EatAtRestaurantActionScript := preload("res://Actions/EatAtRestaurantAction.gd")
const WorkActionScript := preload("res://Actions/WorkAction.gd")

var _checks_run: int = 0
var _current_error: String = ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Live economy food integration test ===")

	var main_instance := MainScene.instantiate()
	if main_instance == null:
		printerr("FAIL: cannot instantiate Main.tscn")
		quit(1)
		return
	root.add_child(main_instance)

	for _i in range(8):
		await process_frame
	for _i in range(4):
		await physics_frame

	var world := main_instance.get_node_or_null("World") as World
	if world == null:
		_fail("Main.tscn should expose $World")
		_finish(main_instance)
		return
	world.is_paused = true
	_set_time(world, 12, 0)

	var restaurants := _collect_buildings(world, Building.BuildingType.RESTAURANT)
	var supermarkets := _collect_buildings(world, Building.BuildingType.SUPERMARKET)
	_expect(restaurants.size() > 0, "Main scene should have restaurants")
	_expect(supermarkets.size() > 0, "Main scene should have supermarkets")
	_expect_all_food_buildings_open(restaurants, world, "restaurant")
	_expect_all_food_buildings_open(supermarkets, world, "supermarket")

	var restaurant := _first_open_restaurant_with_stock(restaurants, world)
	var supermarket := _first_open_supermarket_with_stock(supermarkets, world)
	_expect(restaurant != null, "At least one open restaurant should have meal stock")
	_expect(supermarket != null, "At least one open supermarket should have grocery stock")

	var citizen := _find_test_citizen(world)
	_expect(citizen != null, "Main scene should have a registered citizen")
	if citizen != null and restaurant != null and supermarket != null:
		_prepare_citizen_for_instant_economy(citizen, world, restaurant, supermarket)
		_test_restaurant_meal_flow(citizen, world, restaurant)
		_test_supermarket_grocery_flow(citizen, world, supermarket)
		_test_work_flow_without_travel_delay(citizen, world, supermarket)

	_finish(main_instance)


func _collect_buildings(world: World, type_id: int) -> Array[Building]:
	var found: Array[Building] = []
	for building in world.buildings:
		if building != null and building.building_type == type_id:
			found.append(building)
	return found


func _expect_all_food_buildings_open(buildings: Array[Building], world: World, label: String) -> void:
	var blocked: PackedStringArray = []
	for building in buildings:
		if building == null:
			continue
		var status := building.get_open_status_label(world.time.get_hour())
		if not building.is_open(world.time.get_hour()):
			blocked.append("%s status=%s workers=%d/%d stock=%s" % [
				building.get_display_name(),
				status,
				building.workers.size(),
				building.job_capacity,
				_food_stock_summary(building),
			])
	_expect(blocked.is_empty(), "All %s food buildings should be open at noon; blocked: %s" % [
		label,
		"; ".join(blocked),
	])


func _first_open_restaurant_with_stock(buildings: Array[Building], world: World) -> Restaurant:
	for building in buildings:
		var restaurant := building as Restaurant
		if restaurant != null and restaurant.is_open(world.time.get_hour()) and restaurant.can_sell_item("meal", 1):
			return restaurant
	return null


func _first_open_supermarket_with_stock(buildings: Array[Building], world: World) -> Supermarket:
	for building in buildings:
		var supermarket := building as Supermarket
		if supermarket != null and supermarket.is_open(world.time.get_hour()) and supermarket.can_sell_item("grocery_bundle", 1):
			return supermarket
	return null


func _find_test_citizen(world: World) -> Citizen:
	for citizen in world.citizens:
		if citizen != null \
				and citizen.is_inside_tree() \
				and citizen.has_method("is_autonomous_simulation_enabled") \
				and citizen.is_autonomous_simulation_enabled():
			return citizen
	for citizen in world.citizens:
		if citizen != null and citizen.is_inside_tree():
			return citizen
	return null


func _prepare_citizen_for_instant_economy(
	citizen: Citizen,
	world: World,
	restaurant: Restaurant,
	supermarket: Supermarket
) -> void:
	if citizen.current_action != null:
		citizen.current_action.finish(world, citizen)
		citizen.current_action = null
	citizen.stop_travel()
	citizen.set_world_ref(world)
	if citizen.has_method("exit_keyboard_control_mode"):
		citizen.exit_keyboard_control_mode()
	citizen.autonomous_simulation_enabled = true
	citizen.set_manual_control_enabled(false, world)
	citizen.set_click_move_mode_enabled(false, world)
	citizen.set_simulation_lod_state("focus", true, true, 1)
	if citizen.is_inside_building():
		citizen.exit_current_building(world)
	citizen.favorite_restaurant = restaurant
	citizen.favorite_supermarket = supermarket
	if citizen.home == null:
		citizen.home = world.find_available_residential_building(citizen.global_position)
	citizen.wallet.balance = 200
	citizen.home_food_stock = 0
	citizen.needs.hunger = 92.0
	citizen.needs.energy = 90.0
	citizen.needs.fun = 70.0
	citizen.needs.health = 100.0
	citizen.decision_cooldown_left = 0


func _test_restaurant_meal_flow(citizen: Citizen, world: World, restaurant: Restaurant) -> void:
	_set_time(world, 12, 0)
	_clear_action(citizen, world)
	_prepare_direct_visitor_slot(restaurant, citizen)
	citizen.current_location = restaurant
	citizen.home_food_stock = 0
	citizen.needs.hunger = 92.0
	var hunger_before := citizen.needs.hunger
	var wallet_before := citizen.wallet.balance
	var stock_before := restaurant.get_stock("meal")

	citizen.plan_next_action(world)
	_expect(citizen.current_action is EatAtRestaurantActionScript, "Hungry citizen already at restaurant should start EatAtRestaurant")
	for _i in range(80):
		if citizen.current_action == null:
			break
		citizen.sim_tick(world)

	_expect(citizen.needs.hunger < hunger_before, "Restaurant meal should reduce hunger")
	_expect(citizen.wallet.balance < wallet_before, "Restaurant meal should charge the citizen")
	_expect(restaurant.get_stock("meal") == stock_before - 1, "Restaurant meal should consume one meal stock")
	_clear_action(citizen, world)


func _prepare_direct_visitor_slot(building: Building, citizen: Citizen) -> void:
	if building == null:
		return
	if building.has_method("remove_visitor"):
		for visitor in building.visitors.duplicate():
			building.remove_visitor(visitor)
	var effective_capacity := building.get_effective_visitor_capacity()
	if effective_capacity > 0 and building.visitors.size() >= effective_capacity:
		building.capacity = building.visitors.size() + 1
	if citizen != null and building.visitors.has(citizen):
		building.remove_visitor(citizen)


func _test_supermarket_grocery_flow(citizen: Citizen, world: World, supermarket: Supermarket) -> void:
	_set_time(world, 12, 0)
	_clear_action(citizen, world)
	citizen.current_location = supermarket
	citizen.home_food_stock = 0
	citizen.wallet.balance = 200
	var wallet_before := citizen.wallet.balance
	var stock_before := supermarket.get_stock("grocery_bundle")

	citizen.start_action(BuyGroceriesActionScript.new(supermarket), world)
	_finish_done_action(citizen, world)

	_expect(citizen.home_food_stock > 0, "Buying groceries should add home food stock")
	_expect(citizen.wallet.balance < wallet_before, "Buying groceries should charge the citizen")
	_expect(supermarket.get_stock("grocery_bundle") == stock_before - 1, "Buying groceries should consume one grocery bundle")


func _test_work_flow_without_travel_delay(citizen: Citizen, world: World, workplace: Building) -> void:
	_set_time(world, 10, 0)
	_clear_action(citizen, world)
	var job := Job.new()
	job.title = "Verkaeufer"
	job.wage_per_hour = 12
	job.start_hour = 9
	job.shift_hours = 8
	job.workplace = workplace
	job.preferred_workplace = workplace
	job.allowed_building_types = [workplace.building_type]
	citizen.job = job
	workplace.try_hire(citizen)
	citizen.current_location = workplace
	citizen.work_minutes_today = 0
	citizen.needs.hunger = 20.0
	citizen.needs.energy = 90.0
	citizen.needs.health = 100.0

	citizen.plan_next_action(world)
	_expect(citizen.current_action is WorkActionScript, "Citizen already at workplace during shift should start Work")
	citizen.sim_tick(world)
	_expect(citizen.work_minutes_today > 0, "Work tick should increase work_minutes_today without travel delay")
	_clear_action(citizen, world)


func _clear_action(citizen: Citizen, world: World) -> void:
	if citizen.current_action != null:
		citizen.current_action.finish(world, citizen)
	citizen.current_action = null
	citizen.decision_cooldown_left = 0


func _finish_done_action(citizen: Citizen, world: World) -> void:
	if citizen.current_action == null:
		return
	if not citizen.current_action.is_done():
		return
	citizen.current_action.finish(world, citizen)
	citizen.current_action = null


func _set_time(world: World, hour: int, minute: int) -> void:
	world.time.minutes_total = hour * 60 + minute


func _food_stock_summary(building: Building) -> String:
	if building is Restaurant:
		return "meal=%d" % (building as Restaurant).get_stock("meal")
	if building is Supermarket:
		return "grocery=%d" % (building as Supermarket).get_stock("grocery_bundle")
	return "-"


func _finish(main_instance: Node) -> void:
	if main_instance != null:
		main_instance.queue_free()
	if _current_error.is_empty():
		print("LIVE_ECONOMY_FOOD_TEST OK checks=%d" % _checks_run)
		print("=== End live economy food integration test ===")
		quit(0)
		return
	push_error(_current_error)
	print("LIVE_ECONOMY_FOOD_TEST FAIL checks=%d" % _checks_run)
	print("=== End live economy food integration test ===")
	quit(1)


func _expect(condition: bool, message: String) -> void:
	_checks_run += 1
	if not condition and _current_error.is_empty():
		_current_error = message


func _fail(message: String) -> void:
	_expect(false, message)
