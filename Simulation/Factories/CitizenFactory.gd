extends RefCounted
class_name CitizenFactory

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const CITIZEN_SCENE_PATH := "res://Entities/Citizens/Citizen.tscn"

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

		parent.add_child(citizen)
		world.register_citizen(citizen)
		spawned.append(citizen)

	return spawned

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
