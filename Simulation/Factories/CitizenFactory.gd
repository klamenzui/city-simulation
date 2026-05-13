extends RefCounted
class_name CitizenFactory

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const CITIZEN_SCENE_PATH := "res://Entities/Citizens/CitizenNew.tscn"

const FIRST_NAMES := [
	"Alex", "Maria", "Jonas", "Sophie", "Luca", "Emma", "Finn", "Mia",
	"Noah", "Lea", "Ben", "Hannah", "Leon", "Anna", "Felix", "Laura",
	"Paul", "Clara", "Max", "Lisa", "Tom", "Julia", "Jan", "Sara",
	"Erik", "Nora", "David", "Lena", "Simon", "Eva"
]

const LAST_NAMES := [
	"Mueller", "Schmidt", "Weber", "Fischer", "Meyer", "Wagner", "Becker",
	"Schulz", "Hoffmann", "Koch", "Richter", "Klein", "Wolf", "Schroeder",
	"Neumann", "Schwarz", "Zimmermann", "Braun", "Krueger", "Hartmann"
]

const HOME_EXIT_COLUMNS := 3
const HOME_EXIT_LATERAL_SPACING := 0.26
const HOME_EXIT_ROW_SPACING := 0.30

const JOB_TITLES := [
	"Baecker", "Kellner", "Programmierer", "Fahrer", "Mechaniker",
	"Tankwart", "Verkaeufer", "Designer", "Doctor", "Teacher", "Engineer",
	"Professor", "Janitor", "Gardener", "MaintenanceWorker", "Technician"
]

const JOB_SERVICE_TYPES := {
	"Baecker": "food",
	"Kellner": "food",
	"Programmierer": "governance",
	"Fahrer": "production_goods",
	"Mechaniker": "production_goods",
	"Tankwart": "fuel",
	"Verkaeufer": "shopping",
	"Designer": "fun",
	"Doctor": "governance",
	"Teacher": "education",
	"Engineer": "production_goods",
	"Professor": "education",
}

const BUILDING_TYPE_NAMES := {
	"GENERIC": BuildingScript.BuildingType.GENERIC,
	"RESIDENTIAL": BuildingScript.BuildingType.RESIDENTIAL,
	"RESTAURANT": BuildingScript.BuildingType.RESTAURANT,
	"SHOP": BuildingScript.BuildingType.SHOP,
	"SUPERMARKET": BuildingScript.BuildingType.SUPERMARKET,
	"CAFE": BuildingScript.BuildingType.CAFE,
	"CITY_HALL": BuildingScript.BuildingType.CITY_HALL,
	"UNIVERSITY": BuildingScript.BuildingType.UNIVERSITY,
	"CINEMA": BuildingScript.BuildingType.CINEMA,
	"PARK": BuildingScript.BuildingType.PARK,
	"FARM": BuildingScript.BuildingType.FARM,
	"FACTORY": BuildingScript.BuildingType.FACTORY,
	"GAS_STATION": BuildingScript.BuildingType.GAS_STATION,
}

static func spawn_citizens(parent: Node, world: World, count: int) -> Array[Citizen]:
	var spawned: Array[Citizen] = []
	if parent == null or world == null or count <= 0:
		return spawned

	var first_pool: Array = FIRST_NAMES.duplicate()
	first_pool.shuffle()
	var last_pool: Array = LAST_NAMES.duplicate()
	last_pool.shuffle()

	var citizen_scene: PackedScene = load(CITIZEN_SCENE_PATH)
	if citizen_scene == null:
		push_error("CitizenFactory: Could not load %s" % CITIZEN_SCENE_PATH)
		return spawned

	var spawn_count_by_home: Dictionary = {}
	for i in count:
		var candidate := citizen_scene.instantiate()
		if candidate is not Citizen:
			continue

		var citizen := candidate as Citizen
		var first_name: String = str(first_pool[i % first_pool.size()])
		var last_name: String = str(last_pool[i % last_pool.size()])
		citizen.citizen_name = "%s %s" % [first_name, last_name]

		citizen.job = _create_random_job()
		citizen.set_world_ref(world)
		if citizen.job != null:
			world.register_job(citizen.job)

		var home := _assign_home(citizen, world)
		parent.add_child(citizen)
		place_citizen_at_home_exit(citizen, home, world, _claim_home_spawn_index(home, spawn_count_by_home))
		if home != null:
			citizen.enter_building(home, world, false)
		world.register_citizen(citizen)
		spawned.append(citizen)

	return spawned

static func place_citizen_at_home_exit(
	citizen: Citizen,
	home: ResidentialBuilding,
	world: World,
	spawn_index: int = 0
) -> void:
	if citizen == null:
		return

	var spawn_pos := _get_fallback_spawn_pos(world, spawn_index)
	var facing_dir := Vector3.FORWARD
	if home != null:
		var nav_points := home.get_navigation_points(world, _get_home_exit_lateral_offset(spawn_index))
		var entrance_pos: Vector3 = nav_points.get("entrance", home.get_entrance_pos())
		spawn_pos = nav_points.get("spawn", nav_points.get("access", entrance_pos)) as Vector3
		facing_dir = _get_exit_facing_dir(home, entrance_pos, spawn_pos)
		spawn_pos += facing_dir * _get_home_exit_row_offset(spawn_index)

	citizen.set_position_grounded(spawn_pos)
	_face_citizen(citizen, facing_dir)

static func _assign_home(citizen: Citizen, world: World) -> ResidentialBuilding:
	if citizen == null or world == null:
		return null
	var home := world.find_available_residential_building(Vector3.ZERO)
	if home == null:
		return null
	if not home.add_tenant(citizen):
		return null
	citizen.home = home
	return home

static func _claim_home_spawn_index(home: ResidentialBuilding, spawn_count_by_home: Dictionary) -> int:
	if home == null:
		return 0
	var home_id := home.get_instance_id()
	var spawn_index := int(spawn_count_by_home.get(home_id, 0))
	spawn_count_by_home[home_id] = spawn_index + 1
	return spawn_index

static func _get_home_exit_lateral_offset(spawn_index: int) -> float:
	var column := posmod(spawn_index, HOME_EXIT_COLUMNS)
	if column == 0:
		return 0.0
	var side := -1.0 if column % 2 == 1 else 1.0
	var lane := int((column + 1) / 2)
	return side * float(lane) * HOME_EXIT_LATERAL_SPACING

static func _get_home_exit_row_offset(spawn_index: int) -> float:
	var row := spawn_index / HOME_EXIT_COLUMNS
	return float(row) * HOME_EXIT_ROW_SPACING

static func _get_exit_facing_dir(home: ResidentialBuilding, entrance_pos: Vector3, spawn_pos: Vector3) -> Vector3:
	var facing_dir := spawn_pos - entrance_pos
	facing_dir.y = 0.0
	if facing_dir.length_squared() <= 0.0001 and home != null:
		facing_dir = entrance_pos - home.global_position
		facing_dir.y = 0.0
	if facing_dir.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return facing_dir.normalized()

static func _get_fallback_spawn_pos(world: World, spawn_index: int) -> Vector3:
	var spawn_pos := Vector3.ZERO
	if world != null:
		spawn_pos = world.get_world_center()
		spawn_pos.y = world.get_ground_fallback_y()
	var ring := float(spawn_index / 8) * 0.35 + 0.6
	var angle := float(posmod(spawn_index, 8)) * TAU / 8.0
	spawn_pos += Vector3(cos(angle) * ring, 0.0, sin(angle) * ring)
	return spawn_pos

static func _face_citizen(citizen: Citizen, facing_dir: Vector3) -> void:
	facing_dir.y = 0.0
	if facing_dir.length_squared() <= 0.0001:
		return
	citizen.look_at(citizen.global_position + facing_dir.normalized(), Vector3.UP)

static func _create_random_job() -> Job:
	var job := Job.new()
	job.title = _random_job_title()
	job.wage_per_hour = get_wage_for_job_title(job.title)
	job.start_hour = randi_range(7, 9)
	job.shift_hours = 8
	job.required_education_level = get_required_education_for_job_title(job.title)
	job.workplace_service_type = get_service_type_for_job_title(job.title)
	job.allowed_building_types = get_allowed_building_types_for_job_title(job.title)
	return job

static func get_wage_for_job_title(job_title: String) -> int:
	var configured_wage := BalanceConfig.get_int("economy.jobs.wage_per_hour_by_title.%s" % job_title, -1)
	if configured_wage > 0:
		return configured_wage
	var wage_min := BalanceConfig.get_int("economy.jobs.wage_per_hour_min", 10)
	var wage_max := BalanceConfig.get_int("economy.jobs.wage_per_hour_max", 26)
	return randi_range(mini(wage_min, wage_max), maxi(wage_min, wage_max))

static func get_required_education_for_job_title(job_title: String) -> int:
	return BalanceConfig.get_int("economy.jobs.required_education.%s" % job_title, 0)

static func get_service_type_for_job_title(job_title: String) -> String:
	return str(JOB_SERVICE_TYPES.get(job_title, ""))

static func get_allowed_building_types_for_job_title(job_title: String) -> Array[int]:
	var result: Array[int] = []
	var raw_types: Variant = BalanceConfig.get_value("economy.jobs.allowed_building_types.%s" % job_title, [])
	if raw_types is not Array:
		return result
	for raw_value in raw_types:
		var type_name := str(raw_value).to_upper()
		if BUILDING_TYPE_NAMES.has(type_name):
			result.append(int(BUILDING_TYPE_NAMES[type_name]))
	return result

static func _random_job_title() -> String:
	var idx: int = randi() % JOB_TITLES.size()
	return str(JOB_TITLES[idx])
