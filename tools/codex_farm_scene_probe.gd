extends SceneTree

const FARM_SCENE_PATHS := [
	"res://Scenes/Farm.tscn",
	"res://Scenes/Farm_Windmill.tscn",
	"res://Scenes/Farm_AnimalRanch.tscn",
]
const FARM_VARIANT_REQUIRED_NODES := {
	"res://Scenes/Farm_Windmill.tscn": [
		"VariantDecor/WindmillModel",
		"VariantDecor/WaterTowerModel",
		"VariantDecor/SideBarnModel",
		"Fence/SideGateModel",
	],
	"res://Scenes/Farm_AnimalRanch.tscn": [
		"AnimalArea/OpenBarnModel",
		"AnimalArea/ChickenCoopModel",
		"AnimalArea/FeedBarnModel",
		"AnimalArea/CowMarkerA",
		"AnimalArea/ChickenMarkerA",
		"Obstacles/OpenBarnShape",
		"Obstacles/ChickenCoopShape",
	],
}
const CitizenScene := preload("res://Entities/Citizens/CitizenNew.tscn")


func _initialize() -> void:
	var errors: Array[String] = []
	var scene_count := 0
	var multimesh_total := 0
	var collision_total := 0
	for scene_path in FARM_SCENE_PATHS:
		var scene := load(scene_path) as PackedScene
		if scene == null:
			errors.append("Could not load %s." % scene_path)
			continue

		var farm := scene.instantiate() as Farm
		if farm == null:
			errors.append("Could not instantiate %s as Farm." % scene_path)
			continue
		root.add_child(farm)
		await process_frame

		scene_count += 1
		multimesh_total += _count_nodes_of_type(farm, MultiMeshInstance3D)
		collision_total += _count_nodes_of_type(farm, CollisionShape3D)
		_check_scene_contract(farm, scene_path, errors)
		_check_crop_multimeshes(farm, scene_path, errors)
		_check_variant_nodes(farm, scene_path, errors)
		await _check_first_day_delivery_seed(farm, scene_path, errors)
		if scene_path != "res://Scenes/Farm_AnimalRanch.tscn":
			await _check_daily_production(farm, errors)
		farm.free()

	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(FAILED)
		return

	print("Farm probe passed: scenes=%d multimeshes=%d collisions=%d" % [
		scene_count,
		multimesh_total,
		collision_total,
	])
	quit(OK)


func _check_scene_contract(farm: Node, scene_path: String, errors: Array[String]) -> void:
	if farm.name != "Farm":
		errors.append("%s root should be named Farm." % scene_path)
	if not farm.is_in_group("buildings"):
		errors.append("%s root must stay in the buildings group." % scene_path)
	if _count_nodes_of_type(farm, Camera3D) > 0:
		errors.append("%s must not contain a Camera3D; city cameras own rendering." % scene_path)

	var required_nodes := [
		"Entrance",
		"HarvestPoint",
		"StoragePoint",
		"ClickArea/CollisionShape3D",
		"Buildings/SmallBarnModel",
		"Buildings/BigBarnModel",
		"Buildings/SiloModel",
		"Fields/FieldWest/FarmlandModel",
		"Fields/FieldEast/FarmlandModel",
		"Props/WellModel",
		"Props/Pumpkins/PumpkinA",
		"Obstacles/HouseShape",
		"Obstacles/BarnShape",
		"Obstacles/SiloShape",
		"Obstacles/WellShape",
		"Obstacles/StorageShape",
	]
	for node_path in required_nodes:
		if farm.get_node_or_null(NodePath(node_path)) == null:
			errors.append("%s missing required Farm node: %s" % [scene_path, node_path])


func _check_crop_multimeshes(farm: Node, scene_path: String, errors: Array[String]) -> void:
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
			errors.append("%s missing crop MultiMesh node: %s" % [scene_path, node_path])
			continue
		if node is not MultiMeshInstance3D:
			errors.append("%s crop node is not a MultiMeshInstance3D: %s" % [scene_path, node_path])
			continue

		var crop_node := node as MultiMeshInstance3D
		if crop_node.multimesh == null:
			errors.append("%s crop MultiMesh node has no MultiMesh resource: %s" % [scene_path, node_path])
			continue
		if crop_node.multimesh.instance_count != 16:
			errors.append("%s expected 16 crop instances in %s, found %d." % [
				scene_path,
				node_path,
				crop_node.multimesh.instance_count,
			])
		if crop_node.multimesh.buffer.size() != 192:
			errors.append("%s expected serialized 3D transform buffer size 192 in %s, found %d." % [
				scene_path,
				node_path,
				crop_node.multimesh.buffer.size(),
			])


func _check_variant_nodes(farm: Node, scene_path: String, errors: Array[String]) -> void:
	if not FARM_VARIANT_REQUIRED_NODES.has(scene_path):
		return
	for node_path in FARM_VARIANT_REQUIRED_NODES[scene_path]:
		if farm.get_node_or_null(NodePath(node_path)) == null:
			errors.append("%s missing variant node: %s" % [scene_path, node_path])
	if scene_path == "res://Scenes/Farm_Windmill.tscn" and farm is Farm:
		var windmill_farm := farm as Farm
		if windmill_farm.get_product_commodity() != "bread":
			errors.append("Farm_Windmill should produce bread, found %s." % windmill_farm.get_product_commodity())
		if windmill_farm.get_supermarket_delivery_item() != "bread":
			errors.append("Farm_Windmill should deliver bread, found %s." % windmill_farm.get_supermarket_delivery_item())


func _check_first_day_delivery_seed(farm: Farm, scene_path: String, errors: Array[String]) -> void:
	var market := Supermarket.new()
	root.add_child(market)
	await process_frame

	var product_key := farm.get_product_commodity()
	var delivery_item := farm.get_supermarket_delivery_item()
	var farm_stock := farm.get_product_inventory_amount(product_key)
	var market_need := market.get_restock_need(delivery_item)
	var minimum_delivery := mini(farm.direct_delivery_batch_per_supermarket, market_need)
	if farm.initial_stored_food <= 0:
		errors.append("%s should configure initial_stored_food for first-day deliveries." % scene_path)
	if farm_stock < minimum_delivery:
		errors.append("%s should start with enough %s inventory for one first-day delivery; stock=%d need=%d." % [
			scene_path,
			product_key,
			farm_stock,
			minimum_delivery,
		])
	if market_need <= 0:
		errors.append("Supermarket should start below %s restock target so first-day delivery has demand." % delivery_item)

	market.free()


func _check_daily_production(farm: Farm, errors: Array[String]) -> void:
	_clear_delivery_vehicles()
	var world := World.new()
	world.name = "FarmProbeWorld"
	root.add_child(world)
	await process_frame

	var product_key := farm.get_product_commodity()
	var delivery_item := farm.get_supermarket_delivery_item()
	var starting_product_stock: int = int(world.economy.commodity_stock.get(product_key, 0))
	farm.workers.clear()
	farm.output_today = 0
	farm.set_product_inventory_amount(product_key, 0)
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
		errors.append("%s should not harvest product without staff." % farm.get_display_name())
	if int(world.economy.commodity_stock.get(product_key, 0)) != starting_product_stock:
		errors.append("%s should not push %s to the market before harvest storage has product." % [
			farm.get_display_name(),
			product_key,
		])

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
	if farm.get_product_inventory_amount(product_key) <= 0:
		errors.append("Farm harvest should move %s into farm inventory." % product_key)
	if not farm.inventory.has(product_key):
		errors.append("Farm inventory should contain produced product key: %s." % product_key)
	if farm.is_crop_ready():
		errors.append("Farm crops should reset to growing after harvest.")
	if farm.production_costs_today <= 0:
		errors.append("Farm harvest should record production costs.")
	if int(world.economy.commodity_stock.get(product_key, 0)) != starting_product_stock:
		errors.append("Harvested %s should stay in farm inventory before daily export." % product_key)

	var supermarket := Supermarket.new()
	supermarket.name = "FarmDeliveryProbeSupermarket"
	supermarket.position = Vector3(8.0, 0.0, 0.0)
	root.add_child(supermarket)
	await process_frame
	world.buildings.append(supermarket)
	_configure_probe_vehicle_road_graph(world, farm, supermarket)
	supermarket.inventory[delivery_item] = 0
	supermarket.account.balance = 1000
	var partial_target := int(supermarket.restock_targets.get(delivery_item, 0))
	if partial_target > 2:
		supermarket.inventory[delivery_item] = partial_target - 2
		var partial_expense_before := supermarket.production_costs_today
		var partial_accepted := supermarket.receive_direct_supply(delivery_item, 5, 50)
		if partial_accepted != 2:
			errors.append("Direct supply should only accept remaining restock need; accepted %d." % partial_accepted)
		if supermarket.production_costs_today - partial_expense_before != 20:
			errors.append("Direct supply should record only accepted partial cost, not the full requested cost.")
		supermarket.production_costs_today = 0
		supermarket.inventory[delivery_item] = 0
	var delivery_stock_before := supermarket.get_stock(delivery_item)
	var stored_before_delivery := farm.get_product_inventory_amount(product_key)
	farm.market_export_enabled = false
	farm.run_daily_production(world)
	if supermarket.get_stock(delivery_item) != delivery_stock_before:
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

	if supermarket.get_stock(delivery_item) <= delivery_stock_before:
		errors.append("Farm Fahrer should increase supermarket %s stock from farm inventory." % delivery_item)
	if farm.delivered_food_today <= 0:
		errors.append("Farm Fahrer delivery should record delivered product.")
	if farm.get_product_inventory_amount(product_key) >= stored_before_delivery:
		errors.append("Farm Fahrer delivery should consume farm %s inventory." % product_key)
	if supermarket.production_costs_today <= 0:
		errors.append("Supermarket Fahrer delivery should record supply cost.")
	if int(world.economy.commodity_stock.get(product_key, 0)) != starting_product_stock:
		errors.append("Fahrer delivery should not pass through regional market stock.")
	if farm.income_today <= 0:
		errors.append("Farm Fahrer delivery should record direct supply revenue.")

	farm.set_product_inventory_amount(product_key, 12)
	farm.direct_supermarket_delivery_enabled = false
	farm.market_export_enabled = true
	farm.run_daily_production(world)
	if int(world.economy.commodity_stock.get(product_key, 0)) <= starting_product_stock:
		errors.append("Farm market fallback should export leftover %s inventory to regional market." % product_key)
	if farm.market_exported_food_today <= 0:
		errors.append("Farm market fallback should record exported product.")

	farm.apply_farm_state_snapshot({
		"stored_food": farm.storage_capacity + 12,
		"product_inventory": {
			product_key: farm.storage_capacity + 12,
		},
		"product_commodity": product_key,
		"product_display_name": farm.get_product_display_name(),
		"supermarket_delivery_item": delivery_item,
	})
	if farm.get_product_inventory_amount(product_key) > farm.storage_capacity:
		errors.append("Farm snapshot restore should clamp product inventory to storage capacity.")

	farm.workers.clear()
	supermarket.free()
	driver.free()
	worker.free()
	world.free()
	_clear_delivery_vehicles()


func _first_delivery_vehicle() -> Node:
	for node in get_nodes_in_group("delivery_vehicles"):
		return node
	return null


func _clear_delivery_vehicles() -> void:
	for node in get_nodes_in_group("delivery_vehicles"):
		if node != null and is_instance_valid(node):
			node.free()


func _configure_probe_vehicle_road_graph(world: World, farm: Farm, supermarket: Supermarket) -> void:
	if world == null or farm == null or supermarket == null:
		return
	var start := farm.get_storage_point_global()
	var end := supermarket.get_entrance_pos()
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
