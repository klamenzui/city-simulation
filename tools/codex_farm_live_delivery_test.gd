extends SceneTree

const MainScene := preload("res://Main.tscn")
const WorkActionScript := preload("res://Actions/WorkAction.gd")

const SETTLE_PROCESS_FRAMES := 12
const SETTLE_PHYSICS_FRAMES := 4
const DELIVERY_TICK_MINUTES := 5
const ROUTE_DRIVE_DELTA := 0.25
const MAX_DRIVE_STEPS := 1200

var _errors: Array[String] = []


func _initialize() -> void:
	var main := MainScene.instantiate()
	if main == null:
		_errors.append("Could not instantiate Main.tscn.")
		_finish()
		return
	root.add_child(main)

	for _i in range(SETTLE_PROCESS_FRAMES):
		await process_frame
	for _i in range(SETTLE_PHYSICS_FRAMES):
		await physics_frame

	var world := main.get_node_or_null("World") as World
	if world == null:
		_errors.append("Main.tscn should expose $World.")
		_finish(main)
		return
	world.is_paused = true
	world.time.minutes_total = 10 * 60

	var pair := _select_farm_supermarket_pair(world)
	var farm := pair.get("farm", null) as Farm
	var supermarket := pair.get("supermarket", null) as Supermarket
	if farm == null:
		_errors.append("Main scene should contain a registered Farm with a vehicle road route to a Supermarket.")
		_finish(main)
		return
	if supermarket == null:
		_errors.append("Main scene should contain a registered Supermarket reachable from the selected Farm.")
		_finish(main)
		return

	var driver := _find_delivery_driver_candidate(main, world)
	if driver == null:
		_errors.append("Main scene should have an available Citizen for the live Farm delivery test.")
		_finish(main)
		return

	var action := _prepare_live_delivery_fixture(world, farm, supermarket, driver)
	var existing_vehicle_ids := _capture_vehicle_instance_ids()
	var product_key := farm.get_product_commodity()
	var delivery_item := farm.get_supermarket_delivery_item()
	var stock_before := supermarket.get_stock(delivery_item)
	var stored_before := farm.get_product_inventory_amount(product_key)
	var farm_income_before := farm.income_today
	var supermarket_supply_cost_before := supermarket.production_costs_today
	var regional_product_before := int(world.economy.commodity_stock.get(product_key, 0))

	action.start(world, driver)
	action.tick(world, driver, DELIVERY_TICK_MINUTES)
	var truck := _find_new_delivery_truck(existing_vehicle_ids)
	if truck == null:
		_errors.append("Farm Fahrer live delivery should spawn a new delivery truck in Main.tscn.")
		_finish(main, action, world, driver)
		return
	if not world.vehicles.has(truck):
		_errors.append("Spawned Farm delivery truck should be registered in World.vehicles.")

	driver.global_position = truck.call("get_entry_point_global") as Vector3
	if driver.has_method("stop_travel"):
		driver.stop_travel()
	action.tick(world, driver, DELIVERY_TICK_MINUTES)

	if not driver.has_method("is_inside_vehicle") or not driver.is_inside_vehicle():
		_errors.append("Live Farm Fahrer should board the spawned truck before delivery driving.")
	if not bool(truck.call("is_driving")):
		_errors.append("Live Farm delivery truck should start driving toward the Supermarket.")
	var outbound_route := truck.get("last_vehicle_route") as PackedVector3Array
	if outbound_route.size() <= 2:
		_errors.append("Live Farm delivery should use the Main road graph, not a direct two-point fallback route.")

	var reached_supermarket := await _advance_vehicle_until_stopped(truck)
	if not reached_supermarket:
		_errors.append("Live Farm delivery truck did not reach the Supermarket within the test step budget.")
	else:
		var target_distance := _planar_distance((truck as Node3D).global_position, supermarket.get_entrance_pos())
		if target_distance > 1.75:
			_errors.append("Live Farm delivery truck stopped %.2f units from the Supermarket entrance." % target_distance)

	action.tick(world, driver, DELIVERY_TICK_MINUTES)
	for _i in range(6):
		if bool(truck.call("is_driving")) or farm.delivered_food_today > 0:
			break
		action.tick(world, driver, DELIVERY_TICK_MINUTES)

	var delivery_debug := _delivery_debug_summary(farm, supermarket, driver, truck)
	if supermarket.get_stock(delivery_item) <= stock_before:
		_errors.append("Live Farm delivery should increase Supermarket %s stock. %s" % [delivery_item, delivery_debug])
	if farm.delivered_food_today <= 0:
		_errors.append("Live Farm delivery should record delivered product on the Farm. %s" % delivery_debug)
	if farm.get_product_inventory_amount(product_key) >= stored_before:
		_errors.append("Live Farm delivery should consume stored %s from the Farm. %s" % [product_key, delivery_debug])
	if supermarket.production_costs_today <= supermarket_supply_cost_before:
		_errors.append("Live Farm delivery should record direct supply cost on the Supermarket. %s" % delivery_debug)
	if farm.income_today <= farm_income_before:
		_errors.append("Live Farm delivery should record direct supply income on the Farm. %s" % delivery_debug)
	if int(world.economy.commodity_stock.get(product_key, 0)) != regional_product_before:
		_errors.append("Live Farm delivery should not pass through regional market %s stock." % product_key)

	if not bool(truck.call("is_driving")):
		_errors.append("Live Farm delivery should start the return trip after unloading.")
	else:
		var return_route := truck.get("last_vehicle_route") as PackedVector3Array
		if return_route.size() <= 2:
			_errors.append("Live Farm return trip should use the Main road graph, not a direct fallback route.")
		var returned_to_farm := await _advance_vehicle_until_stopped(truck)
		if not returned_to_farm:
			_errors.append("Live Farm delivery truck did not return to the Farm within the test step budget.")
		else:
			var farm_distance := _planar_distance((truck as Node3D).global_position, farm.get_storage_point_global())
			if farm_distance > 1.75:
				_errors.append("Live Farm delivery truck stopped %.2f units from the Farm storage point after return." % farm_distance)
		action.tick(world, driver, DELIVERY_TICK_MINUTES)

	if driver.has_method("is_inside_vehicle") and driver.is_inside_vehicle():
		_errors.append("Live Farm Fahrer should exit the truck after the return trip.")
	if farm.has_delivery_in_progress():
		_errors.append("Live Farm delivery state should be released after the return trip.")

	_finish(main, action, world, driver)


func _select_farm_supermarket_pair(world: World) -> Dictionary:
	var farms: Array[Farm] = []
	var supermarkets: Array[Supermarket] = []
	for building in world.buildings:
		if building is Farm:
			farms.append(building as Farm)
		elif building is Supermarket:
			supermarkets.append(building as Supermarket)

	for farm in farms:
		for supermarket in supermarkets:
			var route := world.get_vehicle_road_path(farm.get_storage_point_global(), supermarket.get_entrance_pos())
			if route.size() > 2:
				return {
					"farm": farm,
					"supermarket": supermarket,
				}
	return {}


func _find_delivery_driver_candidate(main: Node, world: World) -> Citizen:
	var controlled := main.get_node_or_null("ControlledCitizen") as Citizen
	for citizen in world.citizens:
		if citizen != null and is_instance_valid(citizen) and citizen != controlled:
			return citizen
	if controlled != null:
		return controlled
	return null


func _prepare_live_delivery_fixture(
	world: World,
	farm: Farm,
	supermarket: Supermarket,
	driver: Citizen
) -> WorkAction:
	_clear_driver_state(world, driver)
	driver.set_world_ref(world)
	_prepare_buildings_for_delivery(world, farm, supermarket)

	var old_workplace := driver.job.workplace if driver.job != null else null
	if old_workplace != null and old_workplace != farm and old_workplace.has_method("fire"):
		old_workplace.fire(driver)

	var job := Job.new()
	job.title = "Fahrer"
	job.workplace = farm
	job.preferred_workplace = farm
	job.wage_per_hour = 15
	job.start_hour = 5
	job.shift_hours = 8
	job.allowed_building_types = [farm.building_type]
	driver.job = job
	world.register_job(job)

	farm.job_capacity = maxi(farm.job_capacity, farm.workers.size() + 2)
	farm.try_hire(driver)
	driver.current_location = farm
	driver.global_position = farm.get_storage_point_global()
	driver.wallet.balance = 200
	driver.needs.hunger = 0.0
	driver.needs.energy = 100.0
	driver.needs.health = 100.0
	driver.needs.fun = 80.0
	driver.work_minutes_today = 0
	driver.autonomous_simulation_enabled = false
	if driver.has_method("set_manual_control_enabled"):
		driver.set_manual_control_enabled(false, world)
	if driver.has_method("set_click_move_mode_enabled"):
		driver.set_click_move_mode_enabled(false, world)
	if driver.has_method("set_simulation_lod_state"):
		driver.set_simulation_lod_state("focus", true, true, 1)

	var action := WorkActionScript.new(job) as WorkAction
	driver.current_action = action
	return action


func _prepare_buildings_for_delivery(world: World, farm: Farm, target_market: Supermarket) -> void:
	var product_key := farm.get_product_commodity()
	var delivery_item := farm.get_supermarket_delivery_item()
	for building in world.buildings:
		var market := building as Supermarket
		if market == null:
			continue
		market.restock_enabled = market == target_market
		if market != target_market and market.inventory.has(delivery_item):
			market.inventory[delivery_item] = int(market.restock_targets.get(delivery_item, market.get_stock(delivery_item)))

	farm.account.balance = maxi(farm.account.balance, 2000)
	target_market.account.balance = maxi(target_market.account.balance, 2000)
	if farm.is_financially_closed():
		farm.reopen_after_funding()
	if target_market.is_financially_closed():
		target_market.reopen_after_funding()

	farm.direct_supermarket_delivery_enabled = true
	farm.market_export_enabled = false
	farm.set_product_inventory_amount(product_key, mini(farm.storage_capacity, maxi(farm.direct_delivery_batch_per_supermarket, 40)))
	farm.delivered_food_today = 0
	farm.shipped_food_today = 0
	farm.market_exported_food_today = 0
	target_market.restock_enabled = true
	target_market.inventory[delivery_item] = 0


func _clear_driver_state(world: World, driver: Citizen) -> void:
	if driver.current_action != null:
		driver.current_action.finish(world, driver)
	driver.current_action = null
	if driver.has_method("stop_travel"):
		driver.stop_travel()
	if driver.has_method("is_inside_vehicle") and driver.is_inside_vehicle():
		for node in get_nodes_in_group("vehicles"):
			if node != null and node.has_method("unboard_driver") and node.get("current_driver") == driver:
				node.call("unboard_driver", world, driver.global_position)
	if driver.has_method("exit_keyboard_control_mode"):
		driver.exit_keyboard_control_mode()
	if driver.has_method("is_inside_building") and driver.is_inside_building():
		driver.exit_current_building(world)


func _capture_vehicle_instance_ids() -> Dictionary:
	var ids := {}
	for node in get_nodes_in_group("delivery_vehicles"):
		if node != null:
			ids[node.get_instance_id()] = true
	return ids


func _find_new_delivery_truck(existing_vehicle_ids: Dictionary) -> Node3D:
	for node in get_nodes_in_group("delivery_vehicles"):
		if node is Node3D and not existing_vehicle_ids.has(node.get_instance_id()):
			return node as Node3D
	return null


func _advance_vehicle_until_stopped(vehicle: Node) -> bool:
	for _i in range(MAX_DRIVE_STEPS):
		if vehicle == null or not is_instance_valid(vehicle):
			return false
		if not bool(vehicle.call("is_driving")):
			return true
		vehicle.call("advance_vehicle_simulation", ROUTE_DRIVE_DELTA)
		await physics_frame
	return vehicle != null and is_instance_valid(vehicle) and not bool(vehicle.call("is_driving"))


func _delivery_debug_summary(farm: Farm, supermarket: Supermarket, driver: Citizen, truck: Node3D) -> String:
	var driver_job_title := driver.job.title if driver != null and driver.job != null else "null"
	var driver_workplace := driver.job.workplace if driver != null and driver.job != null else null
	var delivery_item := farm.get_supermarket_delivery_item()
	return "phase=%s qty=%d unload_left=%d stored=%d item=%s market_stock=%d market_need=%d market_balance=%d truck_driving=%s driver_inside=%s driver_job=%s workplace_is_farm=%s" % [
		str(farm.get("_delivery_phase")),
		int(farm.get("_delivery_quantity")),
		int(farm.get("_delivery_minutes_left")),
		farm.get_product_inventory_amount(),
		delivery_item,
		supermarket.get_stock(delivery_item),
		supermarket.get_restock_need(delivery_item),
		supermarket.account.balance,
		str(truck != null and truck.has_method("is_driving") and bool(truck.call("is_driving"))),
		str(driver != null and driver.has_method("is_inside_vehicle") and driver.is_inside_vehicle()),
		driver_job_title,
		str(driver_workplace == farm),
	]


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()


func _finish(main: Node = null, action: WorkAction = null, world: World = null, driver: Citizen = null) -> void:
	if action != null and world != null and driver != null:
		action.finish(world, driver)
		if driver.current_action == action:
			driver.current_action = null
	if main != null:
		main.queue_free()
	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
		quit(FAILED)
		return
	print("FARM_LIVE_DELIVERY_TEST OK")
	quit(OK)
