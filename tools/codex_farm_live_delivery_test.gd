extends SceneTree

const MainScene := preload("res://Main.tscn")
const WorkActionScript := preload("res://Actions/WorkAction.gd")
const VehicleDepotAccessScript := preload("res://Simulation/Transport/VehicleDepotAccess.gd")
const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")

const PICKUP_TRUCK_SCENE_PATH := "res://scenes/vehicles/citypack/pickup_truck.tscn"
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
	var depot_parking_position := VehicleDepotAccessScript.resolve_marker_parking_position(main, "DeliveryVehicleDepot")
	if not VehicleDepotAccessScript.is_finite_vector(depot_parking_position):
		_errors.append("Main scene should contain a DeliveryVehicleDepot with a parking CollisionShape3D.")
		_finish(main)
		return
	var depot_access_position := _get_vehicle_road_access_point(world, depot_parking_position)

	var pair := _select_farm_supermarket_pair(world, depot_access_position)
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
	var loading_parking_position := VehicleDepotAccessScript.resolve_marker_parking_position(farm, "DeliveryLoadingDepot")
	if not VehicleDepotAccessScript.is_finite_vector(loading_parking_position):
		_errors.append("Selected Farm should resolve a nearby DeliveryLoadingDepot parking area.")
		_finish(main)
		return
	var loading_marker := VehicleDepotAccessScript.find_marker(farm, "DeliveryLoadingDepot")
	var loading_parking_radius := VehicleDepotAccessScript.get_marker_parking_radius(loading_marker)
	var loading_access_position := _get_vehicle_road_access_point(world, loading_parking_position)

	var driver := _find_delivery_driver_candidate(main, world)
	if driver == null:
		_errors.append("Main scene should have an available Citizen for the live Farm delivery test.")
		_finish(main)
		return

	var action := _prepare_live_delivery_fixture(world, farm, supermarket, driver)
	var product_key := farm.get_product_commodity()
	var delivery_item := farm.get_supermarket_delivery_item()
	var stock_before := supermarket.get_stock(delivery_item)
	var stored_before := farm.get_product_inventory_amount(product_key)
	var farm_income_before := farm.income_today
	var supermarket_supply_cost_before := supermarket.production_costs_today
	var regional_product_before := int(world.economy.commodity_stock.get(product_key, 0))
	var vehicle_count_before_delivery := world.vehicles.size()
	var depot_capacities := _collect_free_depot_delivery_capacities(main, world, depot_parking_position)
	if depot_capacities.size() < 2 or not depot_capacities.has(4) or not depot_capacities.has(8):
		_errors.append("Main DeliveryVehicleDepot should contain two free delivery vehicles with capacities 4 and 8.")

	action.start(world, driver)
	action.tick(world, driver, DELIVERY_TICK_MINUTES)
	var truck := _find_assigned_delivery_truck()
	if truck == null:
		_errors.append("Farm Fahrer live delivery should claim a delivery truck from the depot fleet in Main.tscn.")
		_finish(main, action, world, driver)
		return
	if not _is_pickup_delivery_vehicle(truck):
		_errors.append("Farm live delivery should claim the pre-placed PickupTruck from DeliveryVehicleDepot.")
	if VehicleDepotAccessScript.get_delivery_vehicle_load_capacity(truck, 1) != 4:
		_errors.append("Farm live delivery should use the 4-unit pickup load capacity.")
	if int(farm.get("_delivery_quantity")) != 0:
		_errors.append("Farm live delivery should not load cargo before reaching the Farm loading depot.")
	if world.vehicles.size() != vehicle_count_before_delivery:
		_errors.append("Farm live delivery should not register a new dynamic delivery vehicle.")
	if not world.vehicles.has(truck):
		_errors.append("Claimed Farm delivery truck should be registered in World.vehicles.")
	if _planar_distance((truck as Node3D).global_position, depot_parking_position) > 2.0:
		_errors.append("Claimed Farm delivery truck should be parked inside DeliveryVehicleDepot at hand-off.")

	driver.global_position = truck.call("get_entry_point_global") as Vector3
	if driver.has_method("stop_travel"):
		driver.stop_travel()
	action.tick(world, driver, DELIVERY_TICK_MINUTES)

	if not driver.has_method("is_inside_vehicle") or not driver.is_inside_vehicle():
		_errors.append("Live Farm Fahrer should board the existing pickup truck before delivery driving.")
	if not bool(truck.call("is_driving")):
		_errors.append("Live Farm delivery truck should start driving out of DeliveryVehicleDepot.")
	if str(farm.get("_delivery_phase")) == "exiting_depot":
		var exited_depot := await _advance_vehicle_until_stopped(truck)
		if not exited_depot:
			_errors.append("Live Farm delivery truck did not finish the local depot exit maneuver.")
		action.tick(world, driver, DELIVERY_TICK_MINUTES)
	if not bool(truck.call("is_driving")):
		_errors.append("Live Farm delivery truck should start driving toward the Farm loading depot after depot exit.")
	var depot_to_loading_route := truck.get("last_vehicle_route") as PackedVector3Array
	if depot_to_loading_route.size() < 2:
		_errors.append("Live Farm depot-to-loading route should use the Main road graph, not a direct fallback route.")
	elif _route_uses_building_endpoint(depot_to_loading_route, depot_parking_position, loading_parking_position):
		_errors.append("Live Farm depot-to-loading route should stay on road waypoints before the local Farm parking maneuver.")

	var reached_loading_access := await _advance_vehicle_until_stopped(truck)
	if not reached_loading_access:
		_errors.append("Live Farm delivery truck did not reach the Farm loading road access within the test step budget.")
	else:
		var loading_access_distance := _planar_distance((truck as Node3D).global_position, loading_access_position)
		if loading_access_distance > 1.75:
			_errors.append("Live Farm delivery truck stopped %.2f units from the Farm loading road access point." % loading_access_distance)
	action.tick(world, driver, DELIVERY_TICK_MINUTES)
	if bool(truck.call("is_driving")):
		var parked_at_loading := await _advance_vehicle_until_stopped(truck)
		if not parked_at_loading:
			_errors.append("Live Farm delivery truck did not finish the local Farm loading parking maneuver.")
		action.tick(world, driver, DELIVERY_TICK_MINUTES)
	var loading_parking_distance := _planar_distance((truck as Node3D).global_position, loading_parking_position)
	if loading_parking_distance > maxf(loading_parking_radius, 2.0):
		_errors.append("Live Farm delivery truck should park inside DeliveryLoadingDepot before loading, distance %.2f." % loading_parking_distance)
	if str(farm.get("_delivery_phase")) != "loading":
		_errors.append("Live Farm delivery should enter a loading phase at the Farm parking depot, phase=%s." % str(farm.get("_delivery_phase")))
	for _i in range(4):
		if str(farm.get("_delivery_phase")) != "loading":
			break
		action.tick(world, driver, DELIVERY_TICK_MINUTES)
	if int(farm.get("_delivery_quantity")) != 4:
		_errors.append("Farm live delivery quantity should be limited to 4 after loading at the Farm depot.")
	if not _is_delivery_cargo_visible(truck):
		_errors.append("Farm live delivery truck should show cargo immediately after loading at the Farm loading depot.")
	if str(farm.get("_delivery_phase")) == "exiting_loading":
		if bool(truck.call("is_driving")):
			var exited_loading := await _advance_vehicle_until_stopped(truck)
			if not exited_loading:
				_errors.append("Live Farm delivery truck did not finish the local Farm loading exit maneuver.")
		action.tick(world, driver, DELIVERY_TICK_MINUTES)
	if not bool(truck.call("is_driving")):
		_errors.append("Live Farm delivery truck should start driving toward the Supermarket after Farm loading.")
	var outbound_route := truck.get("last_vehicle_route") as PackedVector3Array
	if outbound_route.size() < 2:
		_errors.append("Live Farm loading-to-target route should use the Main road graph, not a direct fallback route.")
	elif _route_uses_building_endpoint(outbound_route, loading_parking_position, supermarket.get_entrance_pos()):
		_errors.append("Live Farm delivery route should stay on road waypoints after leaving the Farm loading depot.")

	var reached_supermarket := await _advance_vehicle_until_stopped(truck)
	if not reached_supermarket:
		_errors.append("Live Farm delivery truck did not reach the Supermarket within the test step budget.")
	else:
		var target_distance := _planar_distance((truck as Node3D).global_position, _get_vehicle_road_access_point(world, supermarket.get_entrance_pos()))
		if target_distance > 2.25:
			_errors.append("Live Farm delivery truck stopped %.2f units from the Supermarket road access or curbside point." % target_distance)

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
		if return_route.size() < 2:
			_errors.append("Live Farm return trip should use the Main road graph, not a direct fallback route.")
		elif _route_uses_building_endpoint(return_route, supermarket.get_entrance_pos(), depot_parking_position):
			_errors.append("Live Farm return route should stay on road waypoints before the local depot parking maneuver.")
		var returned_to_depot_access := await _advance_vehicle_until_stopped(truck)
		if not returned_to_depot_access:
			_errors.append("Live Farm delivery truck did not return to the DeliveryVehicleDepot road access within the test step budget.")
		else:
			var depot_access_distance := _planar_distance((truck as Node3D).global_position, depot_access_position)
			if depot_access_distance > 1.75:
				_errors.append("Live Farm delivery truck stopped %.2f units from the DeliveryVehicleDepot road access point after return." % depot_access_distance)
		action.tick(world, driver, DELIVERY_TICK_MINUTES)
		if bool(truck.call("is_driving")):
			var parked_at_depot := await _advance_vehicle_until_stopped(truck)
			if not parked_at_depot:
				_errors.append("Live Farm delivery truck did not finish the local DeliveryVehicleDepot parking maneuver.")
		action.tick(world, driver, DELIVERY_TICK_MINUTES)
		var depot_parking_distance := _planar_distance((truck as Node3D).global_position, depot_parking_position)
		if depot_parking_distance > 2.0:
			_errors.append("Live Farm delivery truck should park inside DeliveryVehicleDepot after return, distance %.2f." % depot_parking_distance)

	if driver.has_method("is_inside_vehicle") and driver.is_inside_vehicle():
		_errors.append("Live Farm Fahrer should exit the truck after the return trip.")
	if farm.has_delivery_in_progress():
		_errors.append("Live Farm delivery state should be released after the return trip.")
	if truck.is_in_group(VehicleDepotAccessScript.DELIVERY_VEHICLE_ASSIGNED_GROUP):
		_errors.append("Live Farm delivery truck should be released back to the depot fleet after the return trip.")

	await _check_owner_manual_delivery(world, farm, supermarket)

	_finish(main, action, world, driver)


func _select_farm_supermarket_pair(world: World, depot_access_position: Vector3) -> Dictionary:
	var farms: Array[Farm] = []
	var supermarkets: Array[Supermarket] = []
	for building in world.buildings:
		if building is Farm:
			farms.append(building as Farm)
		elif building is Supermarket:
			supermarkets.append(building as Supermarket)

	for farm in farms:
		var loading_position := VehicleDepotAccessScript.resolve_marker_parking_position(farm, "DeliveryLoadingDepot")
		if not VehicleDepotAccessScript.is_finite_vector(loading_position):
			continue
		var loading_access_position := _get_vehicle_road_access_point(world, loading_position)
		for supermarket in supermarkets:
			var depot_to_loading_route := world.get_vehicle_road_path(depot_access_position, loading_access_position)
			var outbound_route := world.get_vehicle_road_path(loading_access_position, supermarket.get_entrance_pos())
			var return_route := world.get_vehicle_road_path(supermarket.get_entrance_pos(), depot_access_position)
			if depot_to_loading_route.size() >= 2 and outbound_route.size() > 2 and return_route.size() > 2:
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
		var business := building as CommercialBuilding
		if business == null or business == farm:
			continue
		var consumes_product := false
		for item_var in business.source_commodities.keys():
			if str(business.source_commodities.get(item_var, "")) == product_key:
				consumes_product = true
				break
		if consumes_product:
			business.restock_enabled = business == target_market
		if business is Supermarket and business != target_market and business.inventory.has(delivery_item):
			business.inventory[delivery_item] = int(business.restock_targets.get(delivery_item, business.get_stock(delivery_item)))

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


func _check_owner_manual_delivery(world: World, farm: Farm, target: Supermarket) -> void:
	var owner := CitizenScene.instantiate() as Citizen
	if owner == null:
		_errors.append("Could not instantiate Farm owner for manual delivery test.")
		return
	root.add_child(owner)
	await process_frame
	owner.citizen_name = "Manual Farm Owner"
	owner.set_world_ref(world)
	owner.autonomous_simulation_enabled = false
	owner.needs.hunger = 0.0
	owner.needs.energy = 100.0
	owner.needs.health = 100.0
	farm.citizen_owner = owner
	farm.owner_display_name = owner.citizen_name
	farm.set_product_inventory_amount(
		farm.get_product_commodity(),
		maxi(farm.get_product_inventory_amount(), 20)
	)
	target.restock_enabled = true
	target.account.balance = maxi(target.account.balance, 2000)
	var delivery_item := farm.get_supermarket_delivery_item()
	target.inventory[delivery_item] = 0
	owner.enter_building(farm, world, false, true)

	if not farm.can_actor_perform_work(owner):
		_errors.append("Farm owner should be authorized to work without an employment contract.")
	var requests := farm.get_delivery_demand_snapshot(world, owner, true)
	var request: Dictionary = {}
	for entry_var in requests:
		var entry := entry_var as Dictionary
		if str(entry.get("target_name", "")) == target.get_display_name() \
				and str(entry.get("target_item", "")) == delivery_item:
			request = entry
			break
	if request.is_empty():
		_errors.append("Farm owner should see the reachable Supermarket demand.")
		owner.queue_free()
		return
	if not request.has("expected_revenue"):
		_errors.append("Farm owner demand data should include expected revenue.")

	var stock_before := farm.get_product_inventory_amount()
	var income_before := farm.income_today
	var result := farm.begin_manual_delivery(world, owner, str(request.get("request_id", "")))
	if not bool(result.get("accepted", false)):
		_errors.append("Farm owner should start a self-delivery: %s." % str(result.get("reason", "")))
		owner.queue_free()
		return
	if owner.job != null:
		_errors.append("Farm owner self-delivery should not require an employment job.")
	var manual_vehicle := owner.current_vehicle as VehicleAgent
	if manual_vehicle == null:
		_errors.append("Farm owner self-delivery should board a depot vehicle.")
		farm.cancel_manual_delivery(owner)
		owner.queue_free()
		return
	if not manual_vehicle.is_in_group(VehicleDepotAccessScript.DELIVERY_VEHICLE_ASSIGNED_GROUP):
		_errors.append("Farm owner self-delivery should reserve the selected vehicle.")
	manual_vehicle.global_position = target.get_entrance_pos()
	var completion := farm.complete_manual_delivery(world, owner)
	if not bool(completion.get("accepted", false)):
		_errors.append("Farm owner should unload a self-delivery at the target: %s." % str(completion.get("reason", "")))
	if farm.get_product_inventory_amount() >= stock_before:
		_errors.append("Farm owner self-delivery should consume reserved Farm stock.")
	if farm.income_today <= income_before:
		_errors.append("Farm owner self-delivery should add revenue to the Farm account.")
	if farm.owner_work_minutes_today <= 0:
		_errors.append("Farm owner self-delivery should record unpaid owner work time.")
	if manual_vehicle.is_in_group(VehicleDepotAccessScript.DELIVERY_VEHICLE_ASSIGNED_GROUP):
		_errors.append("Completed owner self-delivery should release the vehicle claim.")
	if owner.is_inside_vehicle():
		manual_vehicle.unboard_driver(world, manual_vehicle.get_entry_point_global())
	owner.queue_free()


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


func _find_assigned_delivery_truck() -> Node3D:
	for node in get_nodes_in_group(VehicleDepotAccessScript.DELIVERY_VEHICLE_ASSIGNED_GROUP):
		if node is Node3D:
			return node as Node3D
	return null


func _is_pickup_delivery_vehicle(vehicle: Node) -> bool:
	if vehicle == null:
		return false
	var scene_path := vehicle.scene_file_path.to_lower()
	return scene_path == PICKUP_TRUCK_SCENE_PATH or vehicle.name.to_lower().contains("pickup")


func _is_delivery_cargo_visible(vehicle: Node) -> bool:
	if vehicle == null:
		return false
	var load_node := vehicle.get_node_or_null("Load") as Node3D
	return load_node != null and load_node.visible


func _collect_free_depot_delivery_capacities(owner_node: Node, world: World, depot_position: Vector3) -> Array[int]:
	var capacities: Array[int] = []
	var depot_marker := VehicleDepotAccessScript.find_marker(owner_node, "DeliveryVehicleDepot")
	var depot_radius := VehicleDepotAccessScript.get_marker_parking_radius(depot_marker)
	var seen: Dictionary = {}
	if world != null:
		for vehicle in world.vehicles:
			_append_depot_delivery_capacity(vehicle, depot_position, depot_radius, capacities, seen)
	for node in get_nodes_in_group("delivery_vehicles"):
		_append_depot_delivery_capacity(node, depot_position, depot_radius, capacities, seen)
	capacities.sort()
	return capacities


func _append_depot_delivery_capacity(
	node: Node,
	depot_position: Vector3,
	depot_radius: float,
	capacities: Array[int],
	seen: Dictionary
) -> void:
	if node == null or not is_instance_valid(node):
		return
	if seen.has(node.get_instance_id()):
		return
	seen[node.get_instance_id()] = true
	if node is not VehicleAgent:
		return
	var vehicle := node as VehicleAgent
	if not vehicle.delivery_vehicle:
		return
	if vehicle.is_in_group(VehicleDepotAccessScript.DELIVERY_VEHICLE_ASSIGNED_GROUP):
		return
	if _planar_distance(vehicle.global_position, depot_position) > depot_radius:
		return
	capacities.append(VehicleDepotAccessScript.get_delivery_vehicle_load_capacity(vehicle, 1))


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


func _route_uses_building_endpoint(route: PackedVector3Array, start_endpoint: Vector3, end_endpoint: Vector3) -> bool:
	if route.is_empty():
		return false
	return _planar_distance(route[0], start_endpoint) <= 0.05 \
		or _planar_distance(route[route.size() - 1], end_endpoint) <= 0.05


func _get_vehicle_road_access_point(world: World, pos: Vector3) -> Vector3:
	if world != null and world.has_method("get_vehicle_road_access_point"):
		return world.get_vehicle_road_access_point(pos)
	return pos


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
