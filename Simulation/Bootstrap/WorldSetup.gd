extends RefCounted
class_name WorldSetup

const DEFAULT_RENT_PER_DAY := 15
const DEFAULT_WORK_CAPACITY := 1

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
	if "work" in building.get_groups() and building.job_capacity == 0:
		building.job_capacity = DEFAULT_WORK_CAPACITY

static func _configure_residential(building: Building, world: World) -> void:
	if building is not ResidentialBuilding:
		return

	var residential := building as ResidentialBuilding
	residential.rent_per_day = DEFAULT_RENT_PER_DAY

	var rent_callback := residential.charge_rent.bind(world)
	if not world.time.rent_due.is_connected(rent_callback):
		world.time.rent_due.connect(rent_callback)

static func _configure_city_hall(building: Building) -> void:
	if building is not CityHall:
		return
	if building.account.balance <= 0:
		building.account.balance = 4500

static func _configure_university(building: Building) -> void:
	if building is not University:
		return
	if building.job_capacity <= 0:
		building.job_capacity = 6
