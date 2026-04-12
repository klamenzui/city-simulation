extends SceneTree

const BuildingScript = preload("res://Entities/Buildings/Building.gd")
const ParkScript = preload("res://Entities/Buildings/Park.gd")
const UniversityScript = preload("res://Entities/Buildings/University.gd")
const CitizenScript = preload("res://Entities/Citizens/Citizen.gd")
const WorldScript = preload("res://Simulation/World.gd")
const ActionScript = preload("res://Actions/Action.gd")
const StudyAtUniversityActionScript = preload("res://Actions/StudyAtUniversityAction.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const GoToBenchActionScript = preload("res://Actions/GoToBenchAction.gd")
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
		"park_arrival_keeps_bench_reserved_without_auto_rest",
		"go_to_park_finish_chains_relax_for_visitors",
		"go_to_park_finish_uses_015_entrance_tolerance",
		"go_to_bench_arrival_keeps_reservation_without_auto_rest",
		"relax_park_uses_bench_bonus",
		"relax_park_finish_releases_bench_after_location_change",
		"relax_park_without_bench_stays_fun_only",
		"agent_clears_stale_outdoor_rest_pose",
		"agent_finishes_relax_park_without_stale_rest_trace",
		"manual_control_releases_city_bench_reservation",
		"world_city_bench_excludes_park_benches",
		"world_city_bench_cache_refreshes_on_scene_change",
		"world_auto_registers_runtime_park_queries",
		"world_unregisters_removed_park_from_queries",
		"citizen_auto_resolves_world_for_queries",
		"action_default_needs_modifier_is_isolated",
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
	_reset_harness_root()
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
		"park_arrival_keeps_bench_reserved_without_auto_rest":
			return _test_park_arrival_keeps_bench_reserved_without_auto_rest()
		"go_to_park_finish_chains_relax_for_visitors":
			return _test_go_to_park_finish_chains_relax_for_visitors()
		"go_to_park_finish_uses_015_entrance_tolerance":
			return _test_go_to_park_finish_uses_015_entrance_tolerance()
		"go_to_bench_arrival_keeps_reservation_without_auto_rest":
			return _test_go_to_bench_arrival_keeps_reservation_without_auto_rest()
		"relax_park_uses_bench_bonus":
			return _test_relax_park_uses_bench_bonus()
		"relax_park_finish_releases_bench_after_location_change":
			return _test_relax_park_finish_releases_bench_after_location_change()
		"relax_park_without_bench_stays_fun_only":
			return _test_relax_park_without_bench_stays_fun_only()
		"agent_clears_stale_outdoor_rest_pose":
			return _test_agent_clears_stale_outdoor_rest_pose()
		"agent_finishes_relax_park_without_stale_rest_trace":
			return _test_agent_finishes_relax_park_without_stale_rest_trace()
		"manual_control_releases_city_bench_reservation":
			return _test_manual_control_releases_city_bench_reservation()
		"world_city_bench_excludes_park_benches":
			return _test_world_city_bench_excludes_park_benches()
		"world_city_bench_cache_refreshes_on_scene_change":
			return _test_world_city_bench_cache_refreshes_on_scene_change()
		"world_auto_registers_runtime_park_queries":
			return _test_world_auto_registers_runtime_park_queries()
		"world_unregisters_removed_park_from_queries":
			return _test_world_unregisters_removed_park_from_queries()
		"citizen_auto_resolves_world_for_queries":
			return _test_citizen_auto_resolves_world_for_queries()
		"action_default_needs_modifier_is_isolated":
			return _test_action_default_needs_modifier_is_isolated()
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

func _test_park_arrival_keeps_bench_reserved_without_auto_rest() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Arrival Park")
	var visitor: Citizen = _new_citizen("Park Visitor")
	var worker: Citizen = _new_citizen("Park Worker")
	var bench := _add_bench(park, "Bench_A", Vector3(1.8, 0.0, 0.4), 0.7)

	visitor.set_world_ref(world)
	var visitor_reservation := park.reserve_bench_for(visitor, visitor.global_position)
	visitor.current_action = GoToBuildingActionScript.new(park, 10)
	visitor.enter_building(park, world, false)
	_expect(not visitor.has_active_rest_pose(), "park arrival should wait for RelaxPark before locking a visitor into the bench rest pose")
	_expect_eq(visitor_reservation.get("node"), bench, "park should reserve the expected bench for the visitor")
	_expect_eq(park.get_reserved_bench_for(visitor).get("node"), bench, "park arrival should keep the reserved bench locked until RelaxPark starts")

	worker.job = Job.new()
	worker.job.workplace = park
	worker.set_world_ref(world)
	worker.current_action = GoToBuildingActionScript.new(park, 10)
	worker.enter_building(park, world, false)
	_expect(not worker.has_active_rest_pose(), "park workers should not auto-occupy visitor benches on arrival")
	_expect(park.get_reserved_bench_for(worker).is_empty(), "park workers should not keep a visitor bench reservation on arrival")

	_free_world(world)
	return _current_error

func _test_go_to_park_finish_chains_relax_for_visitors() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Chain Park")
	var visitor: Citizen = _new_citizen("Chain Visitor")
	var worker: Citizen = _new_citizen("Chain Worker")
	_add_bench(park, "Bench_A", Vector3(1.5, 0.0, 0.5), 0.4)

	visitor.set_world_ref(world)
	var visitor_action: GoToBuildingAction = GoToBuildingActionScript.new(park, 10)
	visitor.current_action = visitor_action
	visitor_action._arrival_target = visitor.get_navigation_points_for_building(park, world).get("access", park.global_position)
	visitor.set_position_grounded(visitor_action._arrival_target)
	visitor._travel_target = visitor_action._arrival_target
	visitor.stop_travel()
	visitor_action.finish(world, visitor)
	_expect(visitor.current_action is RelaxAtParkAction, "park arrival should immediately chain into RelaxPark for normal visitors")

	worker.job = Job.new()
	worker.job.workplace = park
	worker.set_world_ref(world)
	var worker_action: GoToBuildingAction = GoToBuildingActionScript.new(park, 10)
	worker.current_action = worker_action
	worker_action._arrival_target = worker.get_navigation_points_for_building(park, world).get("access", park.global_position)
	worker.set_position_grounded(worker_action._arrival_target)
	worker._travel_target = worker_action._arrival_target
	worker.stop_travel()
	worker_action.finish(world, worker)
	_expect(not (worker.current_action is RelaxAtParkAction), "park workers should enter the park without auto-starting RelaxPark")

	_free_world(world)
	return _current_error

func _test_go_to_park_finish_uses_015_entrance_tolerance() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Tolerance Park")
	var within: Citizen = _new_citizen("Tolerance Within")
	var outside: Citizen = _new_citizen("Tolerance Outside")
	_add_bench(park, "Bench_A", Vector3(1.5, 0.0, 0.5), 0.4)

	within.set_world_ref(world)
	var within_action: GoToBuildingAction = GoToBuildingActionScript.new(park, 10)
	within.current_action = within_action
	within_action._arrival_target = within.get_navigation_points_for_building(park, world).get("access", park.global_position)
	within.set_position_grounded(within_action._arrival_target + Vector3(0.14, 0.0, 0.0))
	within._travel_target = within_action._arrival_target
	within.stop_travel()
	within_action.finish(world, within)
	_expect(within.current_action is RelaxAtParkAction, "park arrival should accept up to 0.15m entrance deviation")

	outside.set_world_ref(world)
	var outside_action: GoToBuildingAction = GoToBuildingActionScript.new(park, 10)
	outside.current_action = outside_action
	outside_action._arrival_target = outside.get_navigation_points_for_building(park, world).get("access", park.global_position)
	outside.set_position_grounded(outside_action._arrival_target + Vector3(0.16, 0.0, 0.0))
	outside._travel_target = outside_action._arrival_target
	outside.stop_travel()
	outside_action.finish(world, outside)
	_expect(not (outside.current_action is RelaxAtParkAction), "park arrival should not accept more than 0.15m entrance deviation")
	_expect(outside.current_location == null, "park arrival outside the 0.15m tolerance should not enter the park yet")

	_free_world(world)
	return _current_error

func _test_go_to_bench_arrival_keeps_reservation_without_auto_rest() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench House")
	var citizen: Citizen = _new_citizen("Bench Walker")
	var bench := _add_bench(building, "Bench", Vector3(1.4, 0.0, -0.3), 1.05)
	world.register_building(building)
	world.register_citizen(citizen)

	var reservation := world.get_reserved_city_bench_for(citizen)
	if reservation.is_empty():
		reservation = world.reserve_city_bench_for(citizen, citizen.global_position)
	_expect(not reservation.is_empty(), "go-to-bench should reserve a city bench before travel starts")
	_expect_eq(reservation.get("node"), bench, "go-to-bench should reserve the expected city bench")
	var action = GoToBenchActionScript.new()
	citizen.global_position = reservation.get("position", citizen.global_position)
	citizen._is_travelling = false
	citizen._travel_target = reservation.get("position", citizen.global_position)
	citizen.decision_cooldown_left = citizen.decision_cooldown_range_max

	action.finish(world, citizen)
	_expect(not citizen.has_active_rest_pose(), "arriving at a city bench should wait for RelaxBench before activating the rest pose")
	_expect_eq(world.get_reserved_city_bench_for(citizen).get("node"), bench, "city bench arrival should keep the reservation for the follow-up relax action")
	_expect_eq(citizen.decision_cooldown_left, 0, "city bench arrival should allow immediate follow-up planning")

	_free_world(world)
	return _current_error

func _test_relax_park_uses_bench_bonus() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Rest Park")
	var citizen: Citizen = _new_citizen("Park Sitter")
	var bench := _add_bench(park, "Bench_Main", Vector3(1.2, 0.0, 0.8), 1.1)
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)
	var nav_points := citizen.get_navigation_points_for_building(park, world)
	citizen.set_position_grounded(nav_points.get("access", park.global_position))
	park.reserve_bench_for(citizen, citizen.global_position)

	var action: RelaxAtParkAction = RelaxAtParkActionScript.new()
	action.start(world, citizen)

	_expect(action.is_using_bench(), "relaxing in a park with a reserved bench should use the bench flow")
	_expect(citizen.is_travelling(), "park relax should first walk from the entrance to the reserved bench")
	_expect(not citizen.has_active_rest_pose(), "bench relax should wait with the rest pose until the citizen reaches the bench")

	citizen.set_position_grounded(bench.global_position)
	citizen.stop_travel()
	action.tick(world, citizen, world.minutes_per_tick)
	var modifier := action.get_needs_modifier(world, citizen)

	_expect(citizen.has_active_rest_pose(), "bench relax should activate a rest pose after arriving at the reserved bench")
	_expect_planar_vec3_near(citizen.global_position, bench.global_position, 0.001, "citizen should rest at the reserved bench marker")
	_expect(float(modifier.get("energy_add", 0.0)) > 0.08, "bench relax should produce a net positive energy gain")
	_expect(float(modifier.get("fun_add", 0.0)) > 0.22, "bench relax should provide a small extra fun bonus")

	action.finish(world, citizen)
	_expect(not citizen.has_active_rest_pose(), "bench relax finish should clear the rest pose again")
	_expect(park.get_reserved_bench_for(citizen).is_empty(), "bench relax finish should release the reserved bench")
	_expect_eq(citizen.decision_cooldown_left, 0, "bench relax finish should allow immediate replanning")

	_free_world(world)
	return _current_error

func _test_relax_park_finish_releases_bench_after_location_change() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Moved Park")
	var citizen: Citizen = _new_citizen("Moved Visitor")
	_add_bench(park, "Bench_Main", Vector3(1.2, 0.0, 0.8), 1.1)
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)
	var nav_points := citizen.get_navigation_points_for_building(park, world)
	citizen.set_position_grounded(nav_points.get("access", park.global_position))
	park.reserve_bench_for(citizen, citizen.global_position)

	var action: RelaxAtParkAction = RelaxAtParkActionScript.new()
	action.start(world, citizen)
	citizen.current_location = null

	action.finish(world, citizen)
	_expect(park.get_reserved_bench_for(citizen).is_empty(), "park bench reservation should still be released even if the citizen location changed before finish")

	_free_world(world)
	return _current_error

func _test_relax_park_without_bench_stays_fun_only() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Open Park")
	var citizen: Citizen = _new_citizen("Standing Visitor")
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)
	var nav_points := citizen.get_navigation_points_for_building(park, world)
	citizen.set_position_grounded(nav_points.get("access", park.global_position))

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

func _test_agent_clears_stale_outdoor_rest_pose() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Cleanup Park")
	var citizen: Citizen = _new_citizen("Cleanup Visitor")
	var bench := _add_bench(park, "Bench", Vector3(0.8, 0.0, 0.6), 0.5)
	citizen.set_world_ref(world)
	park.on_citizen_entered(citizen)
	citizen.current_location = park
	park.reserve_bench_for(citizen, citizen.global_position)
	citizen.set_rest_pose(bench.global_position, bench.global_rotation.y)
	citizen.current_action = null
	citizen.decision_cooldown_left = citizen.decision_cooldown_range_max

	citizen._agent.sim_tick(citizen, world)

	_expect(not citizen.has_active_rest_pose(), "agent should clear stale outdoor rest poses that are no longer owned by a relax action")
	_expect(park.get_reserved_bench_for(citizen).is_empty(), "clearing a stale outdoor rest pose should also release the reserved park bench")

	_free_world(world)
	return _current_error

func _test_agent_finishes_relax_park_without_stale_rest_trace() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Finish Park")
	var citizen: Citizen = _new_citizen("Trace Visitor")
	_add_bench(park, "Bench", Vector3(0.8, 0.0, 0.6), 0.5)
	citizen.set_world_ref(world)
	citizen.enter_building(park, world, false)
	var nav_points := citizen.get_navigation_points_for_building(park, world)
	citizen.set_position_grounded(nav_points.get("access", park.global_position))

	var action: RelaxAtParkAction = RelaxAtParkActionScript.new()
	citizen.current_action = action
	action.start(world, citizen)
	action.finished = true

	citizen._agent.sim_tick(citizen, world)

	_expect(citizen.current_action == null, "finished relax action should be cleared from the citizen")
	_expect(not citizen.has_active_rest_pose(), "finishing relax park through the agent should clear the active rest pose immediately")
	_expect(not citizen._trace_last_decision_reason.begins_with("rest_pose"), "finishing relax park should not leave a stale rest_pose trace reason behind")
	_expect(park.get_reserved_bench_for(citizen).is_empty(), "finishing relax park through the agent should release the reserved park bench immediately")

	_free_world(world)
	return _current_error

func _test_manual_control_releases_city_bench_reservation() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench House")
	var citizen: Citizen = _new_citizen("Manual Bench User")
	var bench := _add_bench(building, "Bench", Vector3(1.4, 0.0, -0.3), 1.05)
	world.register_building(building)
	world.register_citizen(citizen)
	var reservation := world.reserve_city_bench_for(citizen, citizen.global_position)
	citizen.set_rest_pose(bench.global_position, bench.global_rotation.y)

	citizen.set_manual_control_enabled(true, world)

	_expect(not reservation.is_empty(), "manual control test should start with a city bench reservation")
	_expect(not citizen.has_active_rest_pose(), "switching to manual control should clear the bench rest pose")
	_expect(world.get_reserved_city_bench_for(citizen).is_empty(), "switching to manual control should also release the reserved city bench")

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

func _test_world_city_bench_cache_refreshes_on_scene_change() -> String:
	var world: World = _new_world()
	var building: Building = _new_building("Bench Cache House")
	var citizen: Citizen = _new_citizen("Bench Cache Finder")
	world.register_building(building)
	world.register_citizen(citizen)

	_expect(not world.has_available_city_bench_for(citizen, citizen.global_position), "without markers the city bench cache should start empty")

	var bench := _add_bench(building, "Bench_Late", Vector3(1.8, 0.0, 0.2), 0.35)
	var reservation := world.reserve_city_bench_for(citizen, citizen.global_position)
	_expect(not reservation.is_empty(), "adding a bench after the initial lookup should invalidate the cache")
	_expect_eq(reservation.get("node"), bench, "cache rebuild should discover the newly added city bench")

	world.release_city_bench_for(citizen)
	bench.free()
	_expect(not world.has_available_city_bench_for(citizen, citizen.global_position), "removing the bench should invalidate the cache again")

	_free_world(world)
	return _current_error

func _test_world_auto_registers_runtime_park_queries() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Auto Park")

	_expect_eq(world.find_nearest_park(Vector3.ZERO), park, "runtime-added parks should auto-register for nearest park queries")
	_expect_eq(world.find_nearest_building_with_service(Vector3.ZERO, "fun", false, null), park, "runtime-added parks should also populate the generic service registry")

	_free_world(world)
	return _current_error

func _test_world_unregisters_removed_park_from_queries() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Removed Park")

	_expect_eq(world.find_nearest_park(Vector3.ZERO), park, "precondition failed: park should be queryable before removal")
	park.free()
	_expect(world.find_nearest_park(Vector3.ZERO) == null, "removed parks should be pruned from nearest park queries")
	_expect(world.find_nearest_building_with_service(Vector3.ZERO, "fun", false, null) == null, "removed parks should also leave the generic service registry")

	_free_world(world)
	return _current_error

func _test_citizen_auto_resolves_world_for_queries() -> String:
	var world: World = _new_world()
	var park: Park = _new_park("Query Park")
	var citizen: Citizen = _new_citizen("Query Citizen")

	var found_park := citizen._find_nearest_park(Vector3.ZERO)

	_expect_eq(found_park, park, "citizen should still find the nearest park through the world service")
	_expect_eq(citizen._world_ref, world, "citizen query helpers should auto-resolve and retain the world reference")

	_free_world(world)
	return _current_error

func _test_action_default_needs_modifier_is_isolated() -> String:
	var action := ActionScript.new()
	var first_modifier := action.get_needs_modifier(null, null)
	first_modifier["energy_add"] = 123.0
	var second_modifier := action.get_needs_modifier(null, null)

	_expect(is_equal_approx(float(second_modifier.get("energy_add", -1.0)), 0.0), "default action needs modifiers should not leak mutations across calls")
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
	_expect_planar_vec3_near(citizen.global_position, bench.global_position, 0.001, "bench relax should snap the citizen onto the city bench marker")
	_expect(float(modifier.get("energy_add", 0.0)) > 0.08, "city bench relax should provide a net positive energy gain")

	action.finish(world, citizen)
	_expect(not citizen.has_active_rest_pose(), "bench relax finish should clear the rest pose")
	_expect(world.get_reserved_city_bench_for(citizen).is_empty(), "bench relax finish should release the city bench reservation")
	_expect_eq(citizen.decision_cooldown_left, 0, "bench relax finish should allow immediate replanning")

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

func _reset_harness_root() -> void:
	if not is_instance_valid(_harness_root):
		return
	for child in _harness_root.get_children():
		child.free()

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

func _expect_planar_vec3_near(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	_checks_run += 1
	if _current_error != "":
		return
	var delta := actual - expected
	delta.y = 0.0
	if delta.length() <= tolerance:
		return
	_current_error = "%s | expected=%s actual=%s tol=%.4f" % [message, str(expected), str(actual), tolerance]
