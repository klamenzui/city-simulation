extends RefCounted
class_name CitizenFactory

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
	"Verkaeufer", "Designer", "Doctor", "Teacher", "Engineer"
]

const EDUCATION_JOBS := {
	"Doctor": 1,
	"Teacher": 1,
	"Engineer": 1,
}

const JOB_SERVICE_TYPES := {
	"Baecker": "food",
	"Kellner": "food",
	"Programmierer": "governance",
	"Fahrer": "production_goods",
	"Mechaniker": "production_goods",
	"Verkaeufer": "shopping",
	"Designer": "fun",
	"Doctor": "governance",
	"Teacher": "education",
	"Engineer": "production_goods",
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
	job.wage_per_hour = randi_range(10, 26)
	job.start_hour = randi_range(7, 9)
	job.shift_hours = 8
	job.required_education_level = int(EDUCATION_JOBS.get(job.title, 0))
	job.workplace_service_type = str(JOB_SERVICE_TYPES.get(job.title, ""))
	return job

static func _random_job_title() -> String:
	var idx: int = randi() % JOB_TITLES.size()
	return str(JOB_TITLES[idx])
