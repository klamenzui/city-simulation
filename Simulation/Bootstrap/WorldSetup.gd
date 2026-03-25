extends RefCounted
class_name WorldSetup

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

static func configure_scene_buildings(tree: SceneTree, world: World) -> void:
	if tree == null or world == null:
		return

	for node in tree.get_nodes_in_group("buildings"):
		if node is not Building:
			continue

		var building := node as Building
		world.register_building(building)
		_ensure_work_capacity(building)
		_configure_residential(building, world)
		_configure_city_hall(building)
		_configure_university(building)

static func _ensure_work_capacity(building: Building) -> void:
	var default_work_capacity := BalanceConfig.get_int("world_setup.default_work_capacity", 1)
	if "work" in building.get_groups() and building.job_capacity == 0:
		building.job_capacity = default_work_capacity

static func _configure_residential(building: Building, world: World) -> void:
	if building is not ResidentialBuilding:
		return

	var residential := building as ResidentialBuilding
	residential.rent_per_day = BalanceConfig.get_int("buildings.residential.rent_per_day", 15)

	var rent_callback := residential.charge_rent.bind(world)
	if not world.time.rent_due.is_connected(rent_callback):
		world.time.rent_due.connect(rent_callback)

static func _configure_city_hall(building: Building) -> void:
	if building is not CityHall:
		return
	building.account.balance = BalanceConfig.get_int("economy.city_hall.start_balance", building.account.balance)

static func _configure_university(building: Building) -> void:
	if building is not University:
		return
	building.job_capacity = BalanceConfig.get_int("world_setup.university_job_capacity_override", building.job_capacity)
