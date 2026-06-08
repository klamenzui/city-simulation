extends SceneTree

const WorldScript := preload("res://Simulation/World.gd")
const FactoryScript := preload("res://Entities/Buildings/Factory.gd")
const ShopScript := preload("res://Entities/Buildings/Shop.gd")
const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")
const WorkActionScript := preload("res://Actions/WorkAction.gd")

const DELIVERY_TICK_MINUTES := 5
const ROUTE_DRIVE_DELTA := 0.2
const MAX_DRIVE_STEPS := 240

var _errors: Array[String] = []


func _initialize() -> void:
	var world := WorldScript.new() as World
	root.add_child(world)
	await process_frame
	world.is_paused = true
	world.time.minutes_total = 10 * 60

	var factory := FactoryScript.new() as Factory
	factory.name = "FactoryDeliveryProbe"
	factory.building_name = "Factory Delivery Probe"
	factory.position = Vector3(0.0, 0.0, 0.0)
	root.add_child(factory)

	var shop := ShopScript.new() as Shop
	shop.name = "FactoryDeliveryTargetShop"
	shop.building_name = "Factory Delivery Target Shop"
	shop.position = Vector3(8.0, 0.0, 0.0)
	root.add_child(shop)
	await process_frame

	var depot_marker := Area3D.new()
	depot_marker.name = "DeliveryVehicleDepot"
	root.add_child(depot_marker)
	depot_marker.global_position = Vector3(0.0, 0.0, 5.0)
	var depot_shape := CollisionShape3D.new()
	var depot_box := BoxShape3D.new()
	depot_box.size = Vector3(4.0, 1.0, 5.0)
	depot_shape.shape = depot_box
	depot_shape.position = Vector3(0.0, 0.0, 1.5)
	depot_marker.add_child(depot_shape)

	if not world.buildings.has(factory):
		world.buildings.append(factory)
	if not world.buildings.has(shop):
		world.buildings.append(shop)
	_configure_probe_vehicle_road_graph(world, factory, shop)

	factory.account.balance = 2000
	shop.account.balance = 2000
	factory.direct_shop_delivery_enabled = true
	factory.market_export_enabled = false
	factory.set_factory_inventory_amount("clothes", 36)
	shop.restock_enabled = true
	shop.inventory["clothing"] = 0

	var driver := CitizenScene.instantiate() as Citizen
	if driver == null:
		_errors.append("Could not instantiate CitizenNew.tscn for factory driver test.")
		_finish(world, factory, shop)
		return
	root.add_child(driver)
	await process_frame

	var job := Job.new()
	job.title = "Fahrer"
	job.workplace = factory
	job.preferred_workplace = factory
	job.wage_per_hour = 15
	job.start_hour = 6
	job.shift_hours = 8
	job.allowed_building_types = [factory.building_type]
	driver.job = job
	world.register_job(job)
	factory.job_capacity = maxi(factory.job_capacity, factory.workers.size() + 1)
	factory.try_hire(driver)
	driver.set_world_ref(world)
	driver.current_location = factory
	driver.global_position = factory.get_storage_point_global()
	driver.wallet.balance = 200
	driver.needs.hunger = 0.0
	driver.needs.energy = 100.0
	driver.needs.health = 100.0
	driver.needs.fun = 80.0
	driver.autonomous_simulation_enabled = false
	if driver.has_method("set_manual_control_enabled"):
		driver.set_manual_control_enabled(false, world)
	if driver.has_method("set_click_move_mode_enabled"):
		driver.set_click_move_mode_enabled(false, world)

	var existing_vehicle_ids := _capture_delivery_vehicle_ids()
	var regional_clothes_before := int(world.economy.commodity_stock.get("clothes", 0))
	var shop_stock_before := shop.get_stock("clothing")
	var factory_stock_before := factory.get_factory_inventory_amount("clothes")
	var factory_income_before := factory.income_today
	var shop_supply_cost_before := shop.production_costs_today

	var action := WorkActionScript.new(job) as WorkAction
	driver.current_action = action
	action.start(world, driver)
	action.tick(world, driver, DELIVERY_TICK_MINUTES)

	var truck := _find_new_delivery_truck(existing_vehicle_ids)
	if truck == null:
		_errors.append("Factory Fahrer delivery should spawn a delivery truck.")
		_finish(world, factory, shop, driver, action)
		return
	if not world.vehicles.has(truck):
		_errors.append("Factory delivery truck should be registered in World.vehicles.")
	if _planar_distance(truck.global_position, depot_shape.global_position) > 2.0:
		_errors.append("Factory delivery truck should spawn parked inside DeliveryVehicleDepot.")

	driver.global_position = truck.call("get_entry_point_global") as Vector3
	if driver.has_method("stop_travel"):
		driver.stop_travel()
	action.tick(world, driver, DELIVERY_TICK_MINUTES)

	if not driver.has_method("is_inside_vehicle") or not driver.is_inside_vehicle():
		_errors.append("Factory Fahrer should enter the delivery truck before driving.")
	if not bool(truck.call("is_driving")):
		_errors.append("Factory delivery truck should start driving out of DeliveryVehicleDepot.")
	if str(factory.get("_delivery_phase")) == "exiting_depot":
		_advance_vehicle_until_stopped(truck)
		action.tick(world, driver, DELIVERY_TICK_MINUTES)
	if not bool(truck.call("is_driving")):
		_errors.append("Factory delivery truck should start driving toward the retailer after depot exit.")

	_advance_vehicle_until_stopped(truck)
	action.tick(world, driver, DELIVERY_TICK_MINUTES)
	for _i in range(4):
		if factory.delivered_goods_today > 0:
			break
		action.tick(world, driver, DELIVERY_TICK_MINUTES)

	var debug := _delivery_debug_summary(factory, shop, driver, truck)
	if shop.get_stock("clothing") <= shop_stock_before:
		_errors.append("Factory delivery should increase Shop clothing stock. %s" % debug)
	if factory.delivered_goods_today <= 0:
		_errors.append("Factory delivery should record delivered goods. %s" % debug)
	if factory.get_factory_inventory_amount("clothes") >= factory_stock_before:
		_errors.append("Factory delivery should consume Factory clothes inventory. %s" % debug)
	if shop.production_costs_today <= shop_supply_cost_before:
		_errors.append("Shop should record direct factory supply cost. %s" % debug)
	if factory.income_today <= factory_income_before:
		_errors.append("Factory should record direct supply income. %s" % debug)
	if int(world.economy.commodity_stock.get("clothes", 0)) != regional_clothes_before:
		_errors.append("Factory direct delivery should not pass through regional clothes stock.")

	if bool(truck.call("is_driving")):
		_advance_vehicle_until_stopped(truck)
		action.tick(world, driver, DELIVERY_TICK_MINUTES)
		if bool(truck.call("is_driving")):
			_advance_vehicle_until_stopped(truck)
			action.tick(world, driver, DELIVERY_TICK_MINUTES)
	else:
		_errors.append("Factory delivery should start a return trip after unloading.")

	if driver.has_method("is_inside_vehicle") and driver.is_inside_vehicle():
		_errors.append("Factory Fahrer should exit the truck after the return trip.")
	if factory.has_delivery_in_progress():
		_errors.append("Factory delivery state should be released after the return trip.")
	if _planar_distance(truck.global_position, depot_shape.global_position) > 2.0:
		_errors.append("Factory delivery truck should park back inside DeliveryVehicleDepot after the route.")

	_finish(world, factory, shop, driver, action, depot_marker)


func _configure_probe_vehicle_road_graph(world: World, factory: Factory, shop: Shop) -> void:
	var start := factory.get_storage_point_global()
	var end := shop.get_entrance_pos()
	start.y = 0.0
	end.y = 0.0
	var corner := Vector3(end.x, 0.0, start.z)
	var road_nodes: Array[Vector3] = [start, corner, end]
	world.road_graph.nodes = road_nodes
	world.road_graph.neighbors = {
		0: [1],
		1: [0, 2],
		2: [1],
	}
	world.road_graph._is_ready = true


func _capture_delivery_vehicle_ids() -> Dictionary:
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


func _advance_vehicle_until_stopped(vehicle: Node) -> void:
	if vehicle == null:
		return
	for _i in range(MAX_DRIVE_STEPS):
		if not vehicle.has_method("is_driving") or not bool(vehicle.call("is_driving")):
			return
		if vehicle.has_method("advance_vehicle_simulation"):
			vehicle.call("advance_vehicle_simulation", ROUTE_DRIVE_DELTA)


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()


func _delivery_debug_summary(factory: Factory, shop: Shop, driver: Citizen, truck: Node3D) -> String:
	return "phase=%s qty=%d unload_left=%d factory_clothes=%d shop_stock=%d shop_need=%d shop_balance=%d truck_driving=%s driver_inside=%s" % [
		str(factory.get("_delivery_phase")),
		int(factory.get("_delivery_quantity")),
		int(factory.get("_delivery_minutes_left")),
		factory.get_factory_inventory_amount("clothes"),
		shop.get_stock("clothing"),
		shop.get_restock_need("clothing"),
		shop.account.balance,
		str(truck != null and truck.has_method("is_driving") and bool(truck.call("is_driving"))),
		str(driver != null and driver.has_method("is_inside_vehicle") and driver.is_inside_vehicle()),
	]


func _finish(
	world: World = null,
	factory: Factory = null,
	shop: Shop = null,
	driver: Citizen = null,
	action: WorkAction = null,
	depot_marker: Node = null
) -> void:
	if action != null and world != null and driver != null:
		action.finish(world, driver)
		if driver.current_action == action:
			driver.current_action = null
	if driver != null:
		driver.queue_free()
	if shop != null:
		shop.queue_free()
	if factory != null:
		factory.queue_free()
	if depot_marker != null:
		depot_marker.queue_free()
	for node in get_nodes_in_group("delivery_vehicles"):
		if node != null and is_instance_valid(node):
			node.queue_free()
	if world != null:
		world.queue_free()
	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
		quit(FAILED)
		return
	print("FACTORY_DELIVERY_TEST OK")
	quit(OK)
