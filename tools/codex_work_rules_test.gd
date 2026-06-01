extends SceneTree

## Focused test for shared work-planning rules.
##
## Covers the production bug class where CitizenPlanner could skip work for
## sickness, then the soft Work GOAP goal could immediately re-select work.

const CitizenWorkRulesScript = preload("res://Simulation/Citizens/CitizenWorkRules.gd")
const CitizenWorkGoapScript = preload("res://Simulation/GOAP/CitizenWorkGoap.gd")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const WorkActionScript = preload("res://Actions/WorkAction.gd")

var failures: int = 0
var _owned_nodes: Array[Node] = []


class StubTime extends RefCounted:
	var day: int = 1
	var hour: int = 10
	var minute: int = 0
	var weekend: bool = false
	func get_hour() -> int: return hour
	func get_minute() -> int: return minute
	func is_weekend() -> bool: return weekend


class StubWorld extends RefCounted:
	var time := StubTime.new()
	func world_day() -> int: return time.day


class StubNeeds extends RefCounted:
	var hunger: float = 10.0
	var energy: float = 90.0
	var health: float = 100.0


class StubWorkplace extends Building:
	pass


class StubJob extends RefCounted:
	var workplace: Building = null
	var title: String = "Tester"
	var shift_hours: int = 8
	var start_hour: int = 9
	var requirements_met: bool = true
	func meets_requirements(_citizen) -> bool:
		return requirements_met


class StubCitizen extends RefCounted:
	var needs := StubNeeds.new()
	var job = null
	var low_energy_threshold: float = 35.0
	var schedule_offset: int = 0
	var work_minutes_today: int = 0
	var current_location = null
	var started_action = null
	func start_action(action, _world) -> void:
		started_action = action


func _init() -> void:
	print("=== Work rules test ===")
	_test_healthy_work_context()
	_test_commute_window_is_schedule_only()
	_test_sickness_skip_blocks_goal_and_goap()
	_test_goap_uses_shared_context_for_actions()
	_cleanup_owned_nodes()
	print()
	if failures == 0:
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL (%d assertion(s))" % failures)
	quit(1)


func _make_citizen() -> StubCitizen:
	var citizen := StubCitizen.new()
	var job := StubJob.new()
	job.workplace = StubWorkplace.new()
	_owned_nodes.append(job.workplace)
	citizen.job = job
	return citizen


func _test_healthy_work_context() -> void:
	print("-- Healthy work context --")
	var world := StubWorld.new()
	var citizen := _make_citizen()
	var context := CitizenWorkRulesScript.build_context(world, citizen)

	_assert_eq("valid job", context.get("valid_job"), true)
	_assert_eq("inside work window", context.get("in_work_window"), true)
	_assert_eq("remaining work", context.get("remaining_work"), 8 * 60)
	_assert_eq("work fit", context.get("work_fit"), true)
	_assert_eq("goal available", CitizenWorkRulesScript.is_goal_available(context), true)


func _test_commute_window_is_schedule_only() -> void:
	print("-- Commute window --")
	var world := StubWorld.new()
	world.time.hour = 8
	world.time.minute = 45
	var citizen := _make_citizen()
	var context := CitizenWorkRulesScript.build_context(world, citizen)

	_assert_eq("commute window", context.get("in_commute_window"), true)
	_assert_eq("not work window yet", context.get("in_work_window"), false)
	_assert_eq("schedule window", CitizenWorkRulesScript.is_schedule_window(context), true)
	_assert_eq("goal not available before shift", CitizenWorkRulesScript.is_goal_available(context), false)


func _test_sickness_skip_blocks_goal_and_goap() -> void:
	print("-- Sickness skip blocks GOAP --")
	var world := StubWorld.new()
	var citizen := _make_citizen()
	citizen.needs.health = 40.0
	var skip_day := _find_sickness_skip_day(world, citizen)
	_assert_true("found deterministic sick-skip day", skip_day > 0)
	if skip_day <= 0:
		return
	world.time.day = skip_day

	var context := CitizenWorkRulesScript.build_context(world, citizen)
	_assert_eq("needs alone are fit", context.get("needs_fit"), true)
	_assert_eq("sick skip true", context.get("sick_skip"), true)
	_assert_eq("work fit false", context.get("work_fit"), false)
	_assert_eq("goal unavailable", CitizenWorkRulesScript.is_goal_available(context), false)

	var goap := CitizenWorkGoapScript.new()
	_assert_eq("GOAP refuses sick-skip work", goap.try_plan(world, citizen), false)
	_assert_eq("no action started", citizen.started_action == null, true)


func _test_goap_uses_shared_context_for_actions() -> void:
	print("-- GOAP action selection --")
	var world := StubWorld.new()
	var citizen := _make_citizen()
	citizen.current_location = citizen.job.workplace
	var goap := CitizenWorkGoapScript.new()

	_assert_eq("GOAP starts healthy workplace work", goap.try_plan(world, citizen), true)
	_assert_eq("started WorkAction", citizen.started_action is WorkActionScript, true)

	citizen.started_action = null
	citizen.current_location = null
	_assert_eq("GOAP starts commute when offsite", goap.try_plan(world, citizen), true)
	_assert_eq("started GoToBuildingAction", citizen.started_action is GoToBuildingActionScript, true)


func _find_sickness_skip_day(world: StubWorld, citizen: StubCitizen) -> int:
	for day in range(1, 366):
		world.time.day = day
		if CitizenWorkRulesScript.should_skip_work_for_sickness(world, citizen):
			return day
	return -1


func _cleanup_owned_nodes() -> void:
	for node in _owned_nodes:
		if node != null and is_instance_valid(node):
			node.free()
	_owned_nodes.clear()


func _assert_true(name: String, condition: bool) -> void:
	if condition:
		print("  OK   %s" % name)
		return
	failures += 1
	print("  FAIL %s" % name)


func _assert_eq(name: String, got, expected) -> void:
	if got == expected:
		print("  OK   %s: %s" % [name, str(got)])
		return
	failures += 1
	print("  FAIL %s: got %s expected %s" % [name, str(got), str(expected)])
