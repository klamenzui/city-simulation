extends SceneTree

const CitizenAgentScript = preload("res://Simulation/Citizens/CitizenAgent.gd")
const CitizenPlannerScript = preload("res://Simulation/Citizens/CitizenPlanner.gd")
const CitizenScene = preload("res://Entities/Citizens/CitizenNew.tscn")
const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")

var failures: int = 0
var _owned_nodes: Array[Node] = []


class StubNeeds extends RefCounted:
	var hunger: float = 10.0
	var energy: float = 90.0
	var health: float = 100.0


class StubCitizen extends RefCounted:
	var needs := StubNeeds.new()
	var home: Building = null
	var home_food: int = 0

	func get_home_inventory_count(item_id: String) -> int:
		return home_food if item_id == "food" else 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Travel safety test ===")
	_test_survival_interrupt_rules()
	_test_no_progress_watchdog()
	await _test_agent_interrupts_obsolete_travel()
	_cleanup()
	await process_frame
	print()
	if failures == 0:
		print("TRAVEL_SAFETY_TEST OK")
		quit(0)
		return
	print("TRAVEL_SAFETY_TEST FAIL (%d assertion(s))" % failures)
	quit(1)


func _test_survival_interrupt_rules() -> void:
	print("-- Survival interrupt rules --")
	var planner := CitizenPlannerScript.new()
	var citizen := StubCitizen.new()
	var home := ResidentialBuilding.new()
	var hospital := Hospital.new()
	var restaurant := Restaurant.new()
	var supermarket := Supermarket.new()
	var unrelated := Shop.new()
	_owned_nodes.append_array([home, hospital, restaurant, supermarket, unrelated])
	citizen.home = home

	_expect_eq(planner.get_travel_interrupt_reason(citizen, unrelated), "", "healthy travel continues")

	citizen.needs.health = 20.0
	_expect_eq(planner.get_travel_interrupt_reason(citizen, unrelated), "critical_health",
			"critical health interrupts unrelated travel")
	_expect_eq(planner.get_travel_interrupt_reason(citizen, hospital), "",
			"critical health keeps hospital travel")

	citizen.needs.health = 100.0
	citizen.needs.hunger = 80.0
	_expect_eq(planner.get_travel_interrupt_reason(citizen, restaurant), "",
			"critical hunger keeps restaurant travel")
	_expect_eq(planner.get_travel_interrupt_reason(citizen, supermarket), "",
			"critical hunger keeps supermarket travel")
	_expect_eq(planner.get_travel_interrupt_reason(citizen, unrelated), "critical_hunger",
			"critical hunger interrupts unrelated travel")
	citizen.home_food = 1
	_expect_eq(planner.get_travel_interrupt_reason(citizen, home), "",
			"critical hunger keeps stocked-home travel")

	citizen.needs.hunger = 10.0
	citizen.needs.energy = 10.0
	_expect_eq(planner.get_travel_interrupt_reason(citizen, unrelated), "critical_energy",
			"critical energy interrupts unrelated travel")
	_expect_eq(planner.get_travel_interrupt_reason(citizen, home), "",
			"critical energy keeps home travel")


func _test_no_progress_watchdog() -> void:
	print("-- No-progress watchdog --")
	var citizen := CitizenScene.instantiate() as Citizen
	var target := Shop.new()
	var action := GoToBuildingActionScript.new(target, 20)
	_owned_nodes.append_array([citizen, target])
	citizen._is_travelling = true
	citizen.unreachable_target_no_progress_minutes = 30
	citizen.unreachable_target_retry_limit = 2
	action._start_repath_count = citizen._debug_repath_count
	action._no_progress_minutes = 29
	_expect_eq(action._should_abort_for_unreachable(citizen), false,
			"watchdog allows progress window")
	action._no_progress_minutes = 30
	_expect_eq(action._should_abort_for_unreachable(citizen), true,
			"watchdog aborts without requiring navigation repath events")


func _test_agent_interrupts_obsolete_travel() -> void:
	print("-- Agent integration --")
	var citizen := CitizenScene.instantiate() as Citizen
	var target := Shop.new()
	var action := GoToBuildingActionScript.new(target, 20)
	var agent := CitizenAgentScript.new()
	var world := World.new()
	_owned_nodes.append_array([citizen, target, world])
	root.add_child(citizen)
	await process_frame
	citizen.needs.hunger = 90.0
	citizen._is_travelling = true
	citizen.current_action = action
	action._arrival_target = Vector3(10.0, 0.0, 0.0)
	agent._tick_current_action(citizen, world, 1)
	_expect_eq(citizen.current_action, null, "agent clears interrupted travel action")
	_expect_eq(citizen.is_travelling(), false, "agent stops interrupted movement")


func _cleanup() -> void:
	for node in _owned_nodes:
		if node != null and is_instance_valid(node):
			if node is World:
				_free_world(node as World)
			else:
				node.free()
	_owned_nodes.clear()


func _free_world(world: World) -> void:
	if world.time != null and is_instance_valid(world.time):
		world.time.free()
		world.time = null
	if world.economy != null and is_instance_valid(world.economy):
		world.economy.free()
		world.economy = null
	world.free()


func _expect_eq(got, expected, label: String) -> void:
	if got == expected:
		print("  OK   %s: %s" % [label, str(got)])
		return
	failures += 1
	print("  FAIL %s: got %s expected %s" % [label, str(got), str(expected)])
