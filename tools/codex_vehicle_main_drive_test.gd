extends SceneTree

const MAIN_SCENE := "res://Main.tscn"

var _errors: Array[String] = []


func _initialize() -> void:
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		_errors.append("Could not load Main.tscn.")
		_finish()
		return
	var main := scene.instantiate()
	if main == null:
		_errors.append("Could not instantiate Main.tscn.")
		_finish()
		return
	root.add_child(main)
	await process_frame
	await physics_frame
	await physics_frame

	var truck := _find_main_truck(main)
	var citizen := _find_controlled_citizen(main)
	var world := main.get_node_or_null("World") as World
	if truck == null:
		_errors.append("Main scene should contain a truck in the vehicles group.")
		_finish(main)
		return
	if citizen == null:
		_errors.append("Main scene should contain a controllable Citizen.")
		_finish(main)
		return
	if world == null:
		_errors.append("Main scene should expose $World.")
		_finish(main)
		return
	if not world.vehicles.has(truck):
		_errors.append("Main-scene truck should register itself in World.vehicles.")

	if citizen.has_method("enter_keyboard_control_mode"):
		citizen.enter_keyboard_control_mode(false)
	else:
		citizen.set("keyboard_control_enabled", true)
	citizen.global_position = truck.call("get_entry_point_global")
	await physics_frame

	var entered := bool(truck.call("board_driver", citizen))
	if not entered:
		_errors.append("Controlled citizen should be able to board the main-scene truck.")
		_finish(main)
		return
	var start_pos: Vector3 = truck.global_position
	Input.action_press("accelerate")
	for _i in range(120):
		await physics_frame
	Input.action_release("accelerate")

	var moved := truck.global_position.distance_to(start_pos)
	if moved <= 0.05:
		var physics_state := ""
		if truck is VehicleBody3D:
			var body := truck as VehicleBody3D
			var contact_count := 0
			for child in body.get_children():
				if child is VehicleWheel3D and (child as VehicleWheel3D).is_in_contact():
					contact_count += 1
			physics_state = " freeze=%s sleeping=%s speed=%.3f engine=%.3f brake=%.3f y=%.3f" % [
				str(body.freeze),
				str(body.sleeping),
				body.linear_velocity.length(),
				body.engine_force,
				body.brake,
				body.global_position.y,
			]
			physics_state += " wheel_contacts=%d" % contact_count
		_errors.append("Main-scene truck should move after boarding and holding accelerate; moved %.3f units.%s" % [moved, physics_state])
	if truck is VehicleBody3D and (truck as VehicleBody3D).freeze:
		_errors.append("Main-scene truck should unfreeze while player driving.")
	if truck.has_method("is_manual_driving") and not bool(truck.call("is_manual_driving")):
		_errors.append("Main-scene truck should report manual driving after accelerate input.")

	_release_vehicle_inputs()
	_finish(main)


func _find_main_truck(scope: Node) -> Node3D:
	for node in scope.get_tree().get_nodes_in_group("vehicles"):
		if node is Node3D and node.has_method("board_driver"):
			return node as Node3D
	return null


func _find_controlled_citizen(scope: Node) -> Citizen:
	var named := scope.find_child("ControlledCitizen", true, false)
	if named is Citizen:
		return named as Citizen
	for child in _walk(scope):
		if child is Citizen:
			return child as Citizen
	return null


func _walk(node: Node) -> Array[Node]:
	var nodes: Array[Node] = []
	for child in node.get_children():
		nodes.append(child)
		nodes.append_array(_walk(child))
	return nodes


func _release_vehicle_inputs() -> void:
	for action_name in ["accelerate", "reverse", "turn_left", "turn_right"]:
		if InputMap.has_action(action_name):
			Input.action_release(action_name)


func _finish(main: Node = null) -> void:
	if main != null:
		main.queue_free()
	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
		quit(FAILED)
		return
	print("VEHICLE_MAIN_DRIVE_TEST OK")
	quit(OK)
