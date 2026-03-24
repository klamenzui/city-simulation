extends SceneTree

const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const UniversityScript = preload("res://Entities/Buildings/University.gd")
const CitizenScript = preload("res://Entities/Citizens/Citizen.gd")
const WorldScript = preload("res://Simulation/World.gd")
const StudyAtUniversityActionScript = preload("res://Actions/StudyAtUniversityAction.gd")

var _checks_run: int = 0
var _current_error: String = ""
var _harness_root: Node3D

func _initialize() -> void:
	_harness_root = Node3D.new()
	get_root().add_child(_harness_root)
	call_deferred("_run_all_tests")

func _run_all_tests() -> void:
	var failed: Array[String] = []
	for test_name in [
		"building_entry_updates_visitors",
		"study_action_keeps_university_occupancy_consistent",
		"worker_count_lifecycle",
	]:
		var error := _run_test(test_name)
		if error != "":
			failed.append("%s: %s" % [test_name, error])

	if is_instance_valid(_harness_root):
		_harness_root.free()

	if failed.is_empty():
		print("OCCUPANCY_TEST OK checks=%d" % _checks_run)
		quit(0)
		return

	for failure in failed:
		push_error(failure)
	print("OCCUPANCY_TEST FAIL count=%d" % failed.size())
	quit(1)

func _run_test(test_name: String) -> String:
	_current_error = ""
	match test_name:
		"building_entry_updates_visitors":
			return _test_building_entry_updates_visitors()
		"study_action_keeps_university_occupancy_consistent":
			return _test_study_action_keeps_university_occupancy_consistent()
		"worker_count_lifecycle":
			return _test_worker_count_lifecycle()
		_:
			return "unknown test"

func _test_building_entry_updates_visitors() -> String:
	var university: University = _new_university("Entry Uni")
	var citizen: Citizen = _new_citizen("Visitor One")

	_expect_eq(university.visitors.size(), 0, "university should start with no visitors")
	citizen.enter_building(university, null, false)
	_expect(citizen.current_location == university, "citizen current_location should point to entered building")
	_expect_eq(university.visitors.size(), 1, "building entry should register a visitor immediately")
	_expect(university.visitors.has(citizen), "entered citizen should be listed as visitor")
	var info := university.get_info(null)
	_expect_eq(info.get("Visitors", ""), "1 / %d" % max(university.capacity, 0), "building info should reflect live visitor count")

	citizen.exit_current_building(null)
	_expect_eq(university.visitors.size(), 0, "leaving the building should remove the visitor")
	return _current_error

func _test_study_action_keeps_university_occupancy_consistent() -> String:
	var university: University = _new_university("Study Uni")
	var citizen: Citizen = _new_citizen("Student One")
	var world: World = _new_world()

	citizen.enter_building(university, null, false)
	_expect_eq(university.visitors.size(), 1, "entering the university should count as one visitor before study starts")

	var action: StudyAtUniversityAction = StudyAtUniversityActionScript.new(university, 90)
	action.start(world, citizen)
	_expect_eq(university.visitors.size(), 1, "study start should not double-count an already entered visitor")
	_expect_eq(citizen.education_level, 1, "study start should grant education progress")
	_expect_eq(university.account.balance, university.tuition_fee, "university should receive tuition during study start")

	action.finish(world, citizen)
	_expect_eq(university.visitors.size(), 0, "study finish should clear the university visitor again")

	_free_world(world)
	return _current_error

func _test_worker_count_lifecycle() -> String:
	var building: Building = _new_building("Workshop", 2)
	var worker_a: Citizen = _new_citizen("Worker A")
	var worker_b: Citizen = _new_citizen("Worker B")

	_expect(building.try_hire(worker_a), "first worker should be hired")
	_expect(building.try_hire(worker_a), "rehiring same worker should stay idempotent")
	_expect_eq(building.workers.size(), 1, "same worker should not be counted twice")
	_expect(building.try_hire(worker_b), "second worker should be hired while capacity remains")
	_expect_eq(building.workers.size(), 2, "worker array should reflect filled slots")
	building.fire(worker_a)
	_expect_eq(building.workers.size(), 1, "fire should reduce worker count")
	var info := building.get_info(null)
	_expect_eq(info.get("Workers", ""), "1 / 2", "building info should reflect live worker count")
	return _current_error

func _new_building(building_name: String, worker_capacity: int = 0) -> Building:
	var building: Building = BuildingScript.new()
	building.name = building_name
	building.building_name = building_name
	building.job_capacity = worker_capacity
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.1)
	building.add_child(entrance)
	_harness_root.add_child(building)
	return building

func _new_university(building_name: String) -> University:
	var university: University = UniversityScript.new()
	university.name = building_name
	university.building_name = building_name
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.4)
	university.add_child(entrance)
	_harness_root.add_child(university)
	return university

func _new_citizen(citizen_name: String) -> Citizen:
	var citizen: Citizen = CitizenScript.new()
	citizen.name = citizen_name
	citizen.citizen_name = citizen_name
	_harness_root.add_child(citizen)
	return citizen

func _new_world() -> World:
	var world: World = WorldScript.new()
	world.time.minutes_total = 10 * 60
	return world

func _free_world(world) -> void:
	if world == null:
		return
	if world.time != null:
		world.time.free()
		world.time = null
	if world.economy != null:
		world.economy.free()
		world.economy = null
	world.free()

func _expect(condition: bool, message: String) -> void:
	_checks_run += 1
	if condition or _current_error != "":
		return
	_current_error = message

func _expect_eq(actual, expected, message: String) -> void:
	_checks_run += 1
	if actual == expected or _current_error != "":
		return
	_current_error = "%s | expected=%s actual=%s" % [message, str(expected), str(actual)]
