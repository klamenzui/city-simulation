extends SceneTree

const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const ParkScript = preload("res://Entities/Buildings/Park.gd")
const UniversityScript = preload("res://Entities/Buildings/University.gd")
const CitizenScript = preload("res://Entities/Citizens/Citizen.gd")
const WorldScript = preload("res://Simulation/World.gd")
const StudyAtUniversityActionScript = preload("res://Actions/StudyAtUniversityAction.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const RelaxAtParkActionScript = preload("res://Actions/RelaxAtParkAction.gd")
const RelaxAtBenchActionScript = preload("res://Actions/RelaxAtBenchAction.gd")

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
		"university_requires_worker_for_study",
		"university_unstaffed_label_is_teaching_specific",
		"park_entry_keeps_citizen_visible",
		"park_reserved_bench_sets_visit_point",
		"park_arrival_auto_rest_uses_reserved_bench",
		"relax_park_uses_bench_bonus",
		"relax_park_without_bench_stays_fun_only",
		"world_city_bench_excludes_park_benches",
		"relax_bench_uses_energy_bonus",
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
		"university_requires_worker_for_study":
			return _test_university_requires_worker_for_study()
		"university_unstaffed_label_is_teaching_specific":
			return _test_university_unstaffed_label_is_teaching_specific()
		"park_entry_keeps_citizen_visible":
			return _test_park_entry_keeps_citizen_visible()
		"park_reserved_bench_sets_visit_point":
			return _test_park_reserved_bench_sets_visit_point()
		"park_arrival_auto_rest_uses_reserved_bench":
			return _test_park_arrival_auto_rest_uses_reserved_bench()
		"relax_park_uses_bench_bonus":
			return _test_relax_park_uses_bench_bonus()
		"relax_park_without_bench_stays_fun_only":
			return _test_relax_park_without_bench_stays_fun_only()
		"world_city_bench_excludes_park_benches":
			return _test_world_city_bench_excludes_park_benches()
		"relax_bench_uses_energy_bonus":
			return _test_relax_bench_uses_energy_bonus()
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

func _test_university_requires_worker_for_study() -> String:
	var university: University = _new_university("Study Uni")
	var citizen: Citizen = _new_citizen("Student One")
	var teacher: Citizen = _new_citizen("Teacher One")
	var world: World = _new_world()
	var wallet_before: int = citizen.wallet.balance
	teacher.job = Job.new()
	teacher.job.title = "Teacher"
	teacher.job.workplace = university

	_expect(not university.is_open(world.time.get_hour()), "university should be unavailable without at least one worker")
	_expect(not university.can_study(citizen), "student should not be able to study when no worker is present")

	citizen.enter_building(university, null, false)
	_expect_eq(university.visitors.size(), 1, "entering the university should count as one visitor before study starts")

	var action: StudyAtUniversityAction = StudyAtUniversityActionScript.new(university, 90)
	action.start(world, citizen)
	_expect(action.finished, "study action should stop immediately when the university has no worker")
	_expect_eq(university.account.balance, 0, "university should not receive income while it has no worker")
	_expect_eq(citizen.education_level, 0, "study should not progress while university is unstaffed")

	_expect(university.try_hire(teacher), "university should accept its first worker")
	_expect(university.is_open(world.time.get_hour()), "university should open once at least one worker is hired")
	_expect(university.can_study(citizen), "student should be allowed to study once the university is staffed")

	action = StudyAtUniversityActionScript.new(university, 90)
	action.start(world, citizen)
	_expect_eq(university.visitors.size(), 1, "study start should not double-count an already entered visitor")
	_expect_eq(citizen.education_level, 1, "study start should grant education progress")
	_expect_eq(university.account.balance, 0, "university should not charge tuition in the public funding model")
	_expect_eq(citizen.wallet.balance, wallet_before, "public university study should not change the student wallet")

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

func _test_university_unstaffed_label_is_teaching_specific() -> String:
	var university: University = _new_university("Teaching Uni")
	var janitor: Citizen = _new_citizen("Janitor Worker")
	janitor.job = Job.new()
	janitor.job.title = "Janitor"
	janitor.job.workplace = university

	_expect(university.try_hire(janitor), "university should be able to hire non-teaching staff")
	_expect_eq(university.workers.size(), 1, "worker count should include non-teaching staff")
	_expect_eq(university.get_open_status_label(10), "UNSTAFFED", "university should remain unstaffed for teaching without teachers")
	_expect_eq(university.get_open_status_display_label(10), "Geschlossen: keine Lehrkraft", "status label should explain the missing teaching role")
	return _current_error

func _test_park_entry_keeps_citizen_visible() -> String:
	var park: Park = _new_park("Central Park")
	var citizen: Citizen = _new_citizen("Park Visitor")

	citizen.enter_building(park, null, false)
	_expect(citizen.current_location == park, "citizen current_location should point to the park")
	_expect(not citizen.is_inside_building(), "park should not mark the citizen as hidden indoors")
	_expect(citizen.visible, "citizen should stay visible inside the park")
	_expect_eq(park.visitors.size(), 1, "park should register one visitor")

	citizen.leave_current_location(null, false)
	_expect(citizen.current_location == null, "leaving the park should clear current location")
	_expect_eq(park.visitors.size(), 0, "park visitor should be removed after leaving")
	return _current_error

func _test_park_reserved_bench_sets_visit_point() -> String:
	var park: Park = _new_park("Bench Park")
	var citizen: Citizen = _new_citizen("Bench Walker")
	var bench := _add_bench(park, "Bench_A", Vector3(2.5, 0.0, -0.5), 0.9)

	var reservation := park.reserve_bench_for(citizen, citizen.global_position)
	var nav_points := citizen.get_navigation_points_for_building(park, null)

	_expect(not reservation.is_empty(), "park should reserve a bench for the citizen")
	_expect(nav_points.has("visit"), "park navigation should expose a visit target")
	_expect_eq(nav_points.get("visit"), bench.global_position, "reserved bench position should become the visit target")
	_expect(is_equal_approx(float(nav_points.get("bench_yaw", 0.0)), bench.global_rotation.y), "bench yaw should be forwarded for the rest pose")
	return _current_error

func _test_park_arrival_auto_rest_uses_reserved_bench() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Arrival Park")
	var visitor: Citizen = _new_citizen("Park Visitor")
	var worker: Citizen = _new_citizen("Park Worker")
	var bench := _add_bench(park, "Bench_A", Vector3(1.8, 0.0, 0.4), 0.7)

	visitor.set_world_ref(world)
	park.reserve_bench_for(visitor, visitor.global_position)
	visitor.current_action = GoToBuildingActionScript.new(park, 10)
	visitor.enter_building(park, world, false)
	_expect(visitor.has_active_rest_pose(), "park arrival should immediately use the reserved bench for visitors")
	_expect_vec3_near(visitor.global_position, bench.global_position + Vector3(0.0, 0.02, 0.0), 0.001, "park arrival should snap the visitor to the reserved bench")

	worker.job = Job.new()
	worker.job.workplace = park
	worker.set_world_ref(world)
	worker.current_action = GoToBuildingActionScript.new(park, 10)
	worker.enter_building(park, world, false)
	_expect(not worker.has_active_rest_pose(), "park workers should not auto-occupy visitor benches on arrival")

	_free_world(world)
	return _current_error

func _test_relax_park_uses_bench_bonus() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Rest Park")
	var citizen: Citizen = _new_citizen("Park Sitter")
	var bench := _add_bench(park, "Bench_Main", Vector3(1.2, 0.0, 0.8), 1.1)
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)
	park.reserve_bench_for(citizen, citizen.global_position)

	var action: RelaxAtParkAction = RelaxAtParkActionScript.new()
	action.start(world, citizen)
	var modifier := action.get_needs_modifier(world, citizen)

	_expect(action.is_using_bench(), "relaxing in a park with a reserved bench should use the bench flow")
	_expect(citizen.has_active_rest_pose(), "bench relax should activate a rest pose on the citizen")
	_expect_vec3_near(citizen.global_position, bench.global_position + Vector3(0.0, 0.02, 0.0), 0.001, "citizen should snap to the reserved bench marker")
	_expect(float(modifier.get("energy_add", 0.0)) > 0.08, "bench relax should produce a net positive energy gain")
	_expect(float(modifier.get("fun_add", 0.0)) > 0.22, "bench relax should provide a small extra fun bonus")

	action.finish(world, citizen)
	_expect(not citizen.has_active_rest_pose(), "bench relax finish should clear the rest pose again")
	_expect(park.get_reserved_bench_for(citizen).is_empty(), "bench relax finish should release the reserved bench")

	_free_world(world)
	return _current_error

func _test_relax_park_without_bench_stays_fun_only() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Open Park")
	var citizen: Citizen = _new_citizen("Standing Visitor")
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)

	var action: RelaxAtParkAction = RelaxAtParkActionScript.new()
	action.start(world, citizen)
	var modifier := action.get_needs_modifier(world, citizen)

	_expect(not action.is_using_bench(), "park relax without benches should stay in non-bench mode")
	_expect(not citizen.has_active_rest_pose(), "without a bench the citizen should not be locked into a rest pose")
	_expect(is_equal_approx(float(modifier.get("energy_add", -1.0)), 0.0), "park relax without a bench should not add energy")
	_expect(float(modifier.get("fun_add", 0.0)) > 0.0, "park relax without a bench should still add fun")

	action.finish(world, citizen)
	_free_world(world)
	return _current_error

func _test_world_city_bench_excludes_park_benches() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench House")
	var park: Park = _new_park("Garden Park")
	var citizen: Citizen = _new_citizen("Bench Finder")
	var city_bench := _add_bench(building, "Bench", Vector3(2.0, 0.0, 0.6), 0.4)
	_add_bench(park, "Bench", Vector3(0.4, 0.0, 0.2), 0.2)
	world.register_building(building)
	world.register_building(park)
	world.register_citizen(citizen)

	var reservation := world.reserve_city_bench_for(citizen, citizen.global_position)

	_expect(not reservation.is_empty(), "world should find a free city bench")
	_expect_eq(reservation.get("node"), city_bench, "city bench search should ignore park benches")

	world.release_city_bench_for(citizen)
	_free_world(world)
	return _current_error

func _test_relax_bench_uses_energy_bonus() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench House")
	var citizen: Citizen = _new_citizen("Bench Sitter")
	var bench := _add_bench(building, "Bench", Vector3(1.4, 0.0, -0.3), 1.05)
	world.register_building(building)
	world.register_citizen(citizen)

	var reservation := world.reserve_city_bench_for(citizen, citizen.global_position)
	var action = RelaxAtBenchActionScript.new()
	action.start(world, citizen)
	var modifier: Dictionary = action.get_needs_modifier(world, citizen)

	_expect(not reservation.is_empty(), "world should reserve a city bench before bench relax starts")
	_expect(action.is_using_bench(world, citizen), "bench relax should keep the city bench reservation active")
	_expect(citizen.has_active_rest_pose(), "bench relax should activate a rest pose on the citizen")
	_expect_vec3_near(citizen.global_position, bench.global_position + Vector3(0.0, 0.02, 0.0), 0.001, "bench relax should snap the citizen onto the city bench marker")
	_expect(float(modifier.get("energy_add", 0.0)) > 0.08, "city bench relax should provide a net positive energy gain")

	action.finish(world, citizen)
	_expect(not citizen.has_active_rest_pose(), "bench relax finish should clear the rest pose")
	_expect(world.get_reserved_city_bench_for(citizen).is_empty(), "bench relax finish should release the city bench reservation")

	_free_world(world)
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

func _new_park(building_name: String) -> Park:
	var cluster := Node3D.new()
	cluster.name = "%sCluster" % building_name
	_harness_root.add_child(cluster)
	var park: Park = ParkScript.new()
	park.name = building_name
	park.building_name = building_name
	var entrance_south := Node3D.new()
	entrance_south.name = "EntranceSouth"
	entrance_south.position = Vector3(0.0, 0.0, 1.4)
	park.add_child(entrance_south)
	var entrance_north := Node3D.new()
	entrance_north.name = "EntranceNorth"
	entrance_north.position = Vector3(0.0, 0.0, -1.4)
	park.add_child(entrance_north)
	cluster.add_child(park)
	return park

func _add_bench(parent: Node3D, bench_name: String, position: Vector3, yaw: float = 0.0) -> Node3D:
	var bench := Node3D.new()
	bench.name = bench_name
	bench.position = position
	bench.rotation.y = yaw
	parent.add_child(bench)
	return bench

func _new_citizen(citizen_name: String) -> Citizen:
	var citizen: Citizen = CitizenScript.new()
	citizen.name = citizen_name
	citizen.citizen_name = citizen_name
	_harness_root.add_child(citizen)
	return citizen

func _new_world() -> World:
	var world: World = WorldScript.new()
	world.time.minutes_total = 10 * 60
	_harness_root.add_child(world)
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

func _expect_vec3_near(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	_checks_run += 1
	if actual.distance_to(expected) <= tolerance or _current_error != "":
		return
	_current_error = "%s | expected=%s actual=%s tol=%.4f" % [message, str(expected), str(actual), tolerance]
