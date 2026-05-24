extends SceneTree

const FARM_SCENE_PATH := "res://Scenes/Farm.tscn"
const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")


func _initialize() -> void:
	var errors: Array[String] = []
	var scene := load(FARM_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("Could not load %s." % FARM_SCENE_PATH)
		quit(FAILED)
		return

	var farm := scene.instantiate() as Farm
	if farm == null:
		push_error("Could not instantiate %s." % FARM_SCENE_PATH)
		quit(FAILED)
		return
	root.add_child(farm)
	await process_frame

	var multimesh_count := _count_nodes_of_type(farm, MultiMeshInstance3D)
	var collision_count := _count_nodes_of_type(farm, CollisionShape3D)
	_check_scene_contract(farm, errors)
	_check_crop_multimeshes(farm, errors)
	await _check_daily_production(farm, errors)

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		farm.free()
		quit(FAILED)
		return

	print("Farm probe passed: multimeshes=%d collisions=%d groups=%s" % [
		multimesh_count,
		collision_count,
		farm.get_groups(),
	])

	farm.free()
	quit(OK)


func _check_scene_contract(farm: Node, errors: Array[String]) -> void:
	if farm.name != "Farm":
		errors.append("Farm root should be named Farm.")
	if not farm.is_in_group("buildings"):
		errors.append("Farm root must stay in the buildings group.")
	if _count_nodes_of_type(farm, Camera3D) > 0:
		errors.append("Farm prefab must not contain a Camera3D; city cameras own rendering.")

	var required_nodes := [
		"Entrance",
		"HarvestPoint",
		"StoragePoint",
		"ClickArea/CollisionShape3D",
		"Obstacles/HouseShape",
		"Obstacles/BarnShape",
		"Obstacles/SiloShape",
		"Obstacles/TractorShape",
	]
	for node_path in required_nodes:
		if farm.get_node_or_null(NodePath(node_path)) == null:
			errors.append("Missing required Farm node: %s" % node_path)


func _check_crop_multimeshes(farm: Node, errors: Array[String]) -> void:
	var crop_paths := [
		"Fields/FieldWest/CropStemInstances",
		"Fields/FieldWest/CropLeafAInstances",
		"Fields/FieldWest/CropLeafBInstances",
		"Fields/FieldEast/CropStemInstances",
		"Fields/FieldEast/CropLeafAInstances",
		"Fields/FieldEast/CropLeafBInstances",
	]
	for node_path in crop_paths:
		var node := farm.get_node_or_null(NodePath(node_path))
		if node == null:
			errors.append("Missing crop MultiMesh node: %s" % node_path)
			continue
		if node is not MultiMeshInstance3D:
			errors.append("Crop node is not a MultiMeshInstance3D: %s" % node_path)
			continue

		var crop_node := node as MultiMeshInstance3D
		if crop_node.multimesh == null:
			errors.append("Crop MultiMesh node has no MultiMesh resource: %s" % node_path)
			continue
		if crop_node.multimesh.instance_count != 16:
			errors.append("Expected 16 crop instances in %s, found %d." % [
				node_path,
				crop_node.multimesh.instance_count,
			])
		if crop_node.multimesh.buffer.size() != 192:
			errors.append("Expected serialized 3D transform buffer size 192 in %s, found %d." % [
				node_path,
				crop_node.multimesh.buffer.size(),
			])


func _check_daily_production(farm: Farm, errors: Array[String]) -> void:
	var world := World.new()
	world.name = "FarmProbeWorld"
	root.add_child(world)
	await process_frame

	var starting_food_stock: int = int(world.economy.commodity_stock.get("food", 0))
	farm.workers.clear()
	farm.output_today = 0
	farm.stored_food = 0
	farm.crop_growth_minutes = 0
	farm.crop_state = Farm.CropState.GROWING
	farm.advance_crop_growth(farm.get_crop_growth_total_minutes() - 1)
	if farm.is_crop_ready():
		errors.append("Farm crops should not be ready before the full two-day growth window.")
	farm.advance_crop_growth(1)
	if not farm.is_crop_ready():
		errors.append("Farm crops should be ready after the configured two-day growth window.")
	if farm.get_crop_visual_stage() != 3:
		errors.append("Ready crops should use the final visual stage.")

	farm.run_daily_production(world)
	if farm.output_today != 0:
		errors.append("Farm should not harvest food without staff.")
	if int(world.economy.commodity_stock.get("food", 0)) != starting_food_stock:
		errors.append("Farm should not push food to the market before harvest storage has food.")

	var worker := CitizenScene.instantiate() as Citizen
	if worker == null:
		errors.append("Could not instantiate CitizenNew.tscn for farm worker test.")
		world.free()
		return
	root.add_child(worker)
	await process_frame

	var job := Job.new()
	job.title = "Gardener"
	job.workplace = farm
	job.preferred_workplace = farm
	job.wage_per_hour = 12
	job.start_hour = 5
	job.shift_hours = 8
	worker.job = job
	worker.needs.hunger = 0.0
	worker.needs.energy = 100.0
	worker.needs.health = 100.0
	farm.try_hire(worker)
	farm.account.balance = 1000
	farm.income_today = 0
	farm.expenses_today = 0
	farm.production_costs_today = 0
	worker.current_location = farm
	worker.global_position = farm.get_storage_point_global()

	var work_action := WorkAction.new(job)
	worker.current_action = work_action
	work_action.start(world, worker)
	work_action.tick(world, worker, 5)
	worker.global_position = farm.get_harvest_point_global()
	worker.stop_travel()
	work_action.tick(world, worker, 5)
	for _i in range(4):
		work_action.tick(world, worker, 15)
	worker.global_position = farm.get_storage_point_global()
	worker.stop_travel()
	work_action.tick(world, worker, 5)

	if farm.output_today <= 0:
		errors.append("Farm worker should harvest ready crops.")
	if farm.stored_food <= 0:
		errors.append("Farm harvest should move food into farm storage.")
	if farm.is_crop_ready():
		errors.append("Farm crops should reset to growing after harvest.")
	if farm.production_costs_today <= 0:
		errors.append("Farm harvest should record production costs.")
	if int(world.economy.commodity_stock.get("food", 0)) != starting_food_stock:
		errors.append("Harvested food should stay in farm storage before daily export.")

	var supermarket := Supermarket.new()
	supermarket.name = "FarmDeliveryProbeSupermarket"
	supermarket.position = Vector3(8.0, 0.0, 0.0)
	root.add_child(supermarket)
	await process_frame
	world.buildings.append(supermarket)
	supermarket.inventory["grocery_bundle"] = 0
	supermarket.account.balance = 1000
	var grocery_stock_before := supermarket.get_stock("grocery_bundle")
	var stored_before_delivery := farm.stored_food
	farm.market_export_enabled = false
	farm.run_daily_production(world)
	if supermarket.get_stock("grocery_bundle") != grocery_stock_before:
		errors.append("Farm should not deliver to supermarkets without a Fahrer worker doing delivery work.")

	var driver := CitizenScene.instantiate() as Citizen
	if driver == null:
		errors.append("Could not instantiate CitizenNew.tscn for farm driver test.")
		world.free()
		return
	root.add_child(driver)
	await process_frame

	var driver_job := Job.new()
	driver_job.title = "Fahrer"
	driver_job.workplace = farm
	driver_job.preferred_workplace = farm
	driver_job.wage_per_hour = 15
	driver_job.start_hour = 5
	driver_job.shift_hours = 8
	driver.job = driver_job
	driver.needs.hunger = 0.0
	driver.needs.energy = 100.0
	driver.needs.health = 100.0
	farm.try_hire(driver)
	if not farm.has_delivery_staff():
		errors.append("Farm should recognize a hired Fahrer as delivery staff.")

	driver.current_location = farm
	driver.global_position = farm.get_storage_point_global()
	var delivery_action := WorkAction.new(driver_job)
	driver.current_action = delivery_action
	delivery_action.start(world, driver)
	delivery_action.tick(world, driver, 5)
	var truck := _first_delivery_vehicle()
	if truck == null:
		errors.append("Farm Fahrer delivery should spawn a delivery truck.")
	else:
		driver.global_position = truck.call("get_entry_point_global") as Vector3
		driver.stop_travel()
		delivery_action.tick(world, driver, 5)
		if not driver.has_method("is_inside_vehicle") or not driver.is_inside_vehicle():
			errors.append("Farm Fahrer should enter the delivery truck before driving.")
		_advance_vehicle_until_stopped(truck)
		delivery_action.tick(world, driver, 5)
		for _i in range(3):
			delivery_action.tick(world, driver, 5)
		_advance_vehicle_until_stopped(truck)
		delivery_action.tick(world, driver, 5)

	driver.global_position = supermarket.get_entrance_pos()
	driver.stop_travel()

	if supermarket.get_stock("grocery_bundle") <= grocery_stock_before:
		errors.append("Farm Fahrer should increase supermarket grocery stock from storage.")
	if farm.delivered_food_today <= 0:
		errors.append("Farm Fahrer delivery should record delivered food.")
	if farm.stored_food >= stored_before_delivery:
		errors.append("Farm Fahrer delivery should consume farm storage.")
	if supermarket.production_costs_today <= 0:
		errors.append("Supermarket Fahrer delivery should record supply cost.")
	if int(world.economy.commodity_stock.get("food", 0)) != starting_food_stock:
		errors.append("Fahrer delivery should not pass through regional market stock.")
	if farm.income_today <= 0:
		errors.append("Farm Fahrer delivery should record direct supply revenue.")

	farm.stored_food = 12
	farm.direct_supermarket_delivery_enabled = false
	farm.market_export_enabled = true
	farm.run_daily_production(world)
	if int(world.economy.commodity_stock.get("food", 0)) <= starting_food_stock:
		errors.append("Farm market fallback should export leftover storage to regional market.")
	if farm.market_exported_food_today <= 0:
		errors.append("Farm market fallback should record exported food.")

	farm.workers.clear()
	supermarket.free()
	driver.free()
	worker.free()
	world.free()


func _first_delivery_vehicle() -> Node:
	for node in get_nodes_in_group("delivery_vehicles"):
		return node
	return null


func _advance_vehicle_until_stopped(vehicle: Node, max_steps: int = 160) -> void:
	if vehicle == null:
		return
	for _i in range(max_steps):
		if not vehicle.has_method("is_driving") or not bool(vehicle.call("is_driving")):
			return
		if vehicle.has_method("advance_vehicle_simulation"):
			vehicle.call("advance_vehicle_simulation", 0.2)


func _count_nodes_of_type(node: Node, type_ref: Variant) -> int:
	var count := 0
	if is_instance_of(node, type_ref):
		count += 1
	for child in node.get_children():
		count += _count_nodes_of_type(child, type_ref)
	return count
