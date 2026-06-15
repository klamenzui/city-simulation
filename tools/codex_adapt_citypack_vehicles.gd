extends SceneTree

const VehicleAgentScript = preload("res://Simulation/Transport/VehicleAgent.gd")
const EngineAudio = preload("res://environment/audio/vehicles/engine.wav")

const VEHICLE_LAYER := 4
const WORLD_AND_VEHICLE_MASK := 5


func _initialize() -> void:
	var failed := false
	for scene_path in _vehicle_specs().keys():
		if not _adapt_scene(scene_path, _vehicle_specs()[scene_path]):
			failed = true
	if failed:
		quit(FAILED)
		return

	print("CITYPACK_VEHICLE_ADAPT OK")
	quit(OK)


func _vehicle_specs() -> Dictionary:
	return {
		"res://Scenes/Vehicles/CityPack/bus.tscn": {
			"target_length": 2.35,
			"mass": 36.0,
			"height_bias": 0.05,
			"wheelbase_front_factor": 0.31,
			"wheelbase_rear_factor": 0.34,
		},
		"res://Scenes/Vehicles/CityPack/car_unqqk_u_lt_ru.tscn": {
			"target_length": 1.34,
			"mass": 12.0,
		},
		"res://Scenes/Vehicles/CityPack/police_car.tscn": {
			"target_length": 1.34,
			"mass": 13.0,
		},
		"res://Scenes/Vehicles/CityPack/sports_car.tscn": {
			"target_length": 1.28,
			"mass": 11.0,
			"height_bias": -0.02,
		},
		"res://Scenes/Vehicles/CityPack/sports_car_gzj704_d_xdr.tscn": {
			"target_length": 1.28,
			"mass": 11.0,
			"height_bias": -0.02,
		},
		"res://Scenes/Vehicles/CityPack/suv.tscn": {
			"target_length": 1.48,
			"mass": 16.0,
			"height_bias": 0.03,
		},
		"res://Scenes/Vehicles/CityPack/van.tscn": {
			"target_length": 1.58,
			"mass": 18.0,
			"height_bias": 0.04,
		},
	}


func _adapt_scene(scene_path: String, spec: Dictionary) -> bool:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_error("Could not load %s." % scene_path)
		return false

	var source_root := scene.instantiate() as Node3D
	if source_root == null:
		push_error("Could not instantiate %s." % scene_path)
		return false
	if source_root is VehicleBody3D:
		source_root.free()
		print("Skipped already adapted %s." % scene_path)
		return true

	var source_bounds := _calculate_mesh_bounds(source_root)
	if source_bounds.size == Vector3.ZERO:
		source_root.free()
		push_error("Could not calculate mesh bounds for %s." % scene_path)
		return false

	var target_length := float(spec.get("target_length", 1.34))
	var visual_scale := target_length / maxf(source_bounds.size.z, 0.001)
	var visual_size := source_bounds.size * visual_scale
	var collision_size := Vector3(
		maxf(visual_size.x * 0.82, 0.42),
		maxf(visual_size.y * 0.72 + float(spec.get("height_bias", 0.0)), 0.30),
		maxf(visual_size.z * 1.02, 0.95)
	)
	var wheel_radius := clampf(collision_size.y * 0.22, 0.07, 0.105)
	var wheel_mount_y := wheel_radius
	var track_half_width := clampf(collision_size.x * 0.34, 0.15, 0.32)
	var front_factor := float(spec.get("wheelbase_front_factor", 0.25))
	var rear_factor := float(spec.get("wheelbase_rear_factor", 0.28))
	var front_z := collision_size.z * front_factor
	var rear_z := -collision_size.z * rear_factor
	var mass := float(spec.get("mass", 12.0))
	var center_of_mass := Vector3(0.0, maxf(wheel_radius, 0.08), 0.0)

	var vehicle := VehicleBody3D.new()
	vehicle.name = source_root.name
	vehicle.collision_layer = VEHICLE_LAYER
	vehicle.collision_mask = WORLD_AND_VEHICLE_MASK
	vehicle.mass = mass
	vehicle.center_of_mass_mode = 1
	vehicle.center_of_mass = center_of_mass
	vehicle.set_script(VehicleAgentScript)
	vehicle.set("delivery_vehicle", false)
	vehicle.set("delivery_load_capacity", 0)
	vehicle.set("use_balance_vehicle_geometry", false)
	vehicle.set("vehicle_mass", mass)
	vehicle.set("center_of_mass_offset", center_of_mass)
	vehicle.set("wheel_track_half_width", track_half_width)
	vehicle.set("wheel_front_z", front_z)
	vehicle.set("wheel_rear_z", rear_z)
	vehicle.set("wheel_mount_y", wheel_mount_y)
	vehicle.set("wheel_radius", wheel_radius)
	vehicle.set("wheel_roll_influence", 0.35)
	vehicle.set("wheel_friction_slip", 1.1)
	vehicle.set("suspension_stiffness", 34.0)
	vehicle.set("suspension_travel", 0.12)
	vehicle.set("damping_compression", 0.9)
	vehicle.set("damping_relaxation", 1.6)
	vehicle.set("collision_shape_size", collision_size)
	vehicle.set("collision_shape_offset", Vector3(0.0, collision_size.y * 0.5 + 0.02, 0.0))

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "VehicleCollisionShape"
	var box_shape := BoxShape3D.new()
	box_shape.size = collision_size
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, collision_size.y * 0.5 + 0.02, 0.0)
	vehicle.add_child(collision_shape)

	_add_wheel(vehicle, "FrontLeftWheel", Vector3(track_half_width, wheel_mount_y, front_z), true, wheel_radius)
	_add_wheel(vehicle, "FrontRightWheel", Vector3(-track_half_width, wheel_mount_y, front_z), true, wheel_radius)
	_add_wheel(vehicle, "RearLeftWheel", Vector3(track_half_width, wheel_mount_y, rear_z), false, wheel_radius)
	_add_wheel(vehicle, "RearRightWheel", Vector3(-track_half_width, wheel_mount_y, rear_z), false, wheel_radius)

	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	visual_root.scale = Vector3.ONE * visual_scale
	var source_center := source_bounds.get_center()
	visual_root.position = Vector3(
		-source_center.x * visual_scale,
		-source_bounds.position.y * visual_scale + 0.02,
		-source_center.z * visual_scale
	)
	vehicle.add_child(visual_root)

	var source_name := source_root.name
	var source_visual := Node3D.new()
	source_visual.name = "%sVisual" % source_name
	source_visual.transform = source_root.transform
	visual_root.add_child(source_visual)
	for child in source_root.get_children():
		source_root.remove_child(child)
		source_visual.add_child(child)
	source_root.free()

	var entry := Node3D.new()
	entry.name = "EntryPoint"
	entry.position = Vector3(collision_size.x * 0.72, 0.03, 0.02)
	vehicle.add_child(entry)

	var seat := Node3D.new()
	seat.name = "SeatPoint"
	seat.position = Vector3(collision_size.x * 0.18, collision_size.y * 0.68, 0.08)
	vehicle.add_child(seat)

	var engine_sound := AudioStreamPlayer3D.new()
	engine_sound.name = "EngineSound"
	engine_sound.stream = EngineAudio
	engine_sound.volume_db = -28.0
	engine_sound.pitch_scale = 0.05
	engine_sound.attenuation_filter_cutoff_hz = 20500.0
	vehicle.add_child(engine_sound)

	_assign_owner_recursive(vehicle, vehicle)

	var packed := PackedScene.new()
	var pack_result := packed.pack(vehicle)
	if pack_result != OK:
		vehicle.free()
		push_error("Could not pack adapted scene %s: %s." % [scene_path, pack_result])
		return false

	var save_result := ResourceSaver.save(packed, scene_path)
	vehicle.free()
	if save_result != OK:
		push_error("Could not save adapted scene %s: %s." % [scene_path, save_result])
		return false

	print(
		"Adapted %s scale=%.5f collision=%s wheels=(%.3f, %.3f, %.3f)"
		% [scene_path, visual_scale, str(collision_size), track_half_width, front_z, rear_z]
	)
	return true


func _add_wheel(vehicle: Node3D, wheel_name: String, position: Vector3, is_steering: bool, radius: float) -> void:
	var wheel := VehicleWheel3D.new()
	wheel.name = wheel_name
	wheel.position = position
	wheel.use_as_traction = true
	wheel.use_as_steering = is_steering
	wheel.wheel_roll_influence = 0.35
	wheel.wheel_radius = radius
	wheel.wheel_friction_slip = 1.1
	wheel.suspension_travel = 0.12
	wheel.suspension_stiffness = 34.0
	wheel.damping_compression = 0.9
	wheel.damping_relaxation = 1.6
	vehicle.add_child(wheel)


func _calculate_mesh_bounds(root_node: Node3D) -> AABB:
	var state := {
		"has_bounds": false,
		"bounds": AABB(),
	}
	_collect_mesh_bounds(root_node, Transform3D.IDENTITY, state)
	if not bool(state["has_bounds"]):
		return AABB()
	return state["bounds"] as AABB


func _collect_mesh_bounds(node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			_include_aabb(state, mesh_instance.mesh.get_aabb(), current_transform)
	for child in node.get_children():
		_collect_mesh_bounds(child, current_transform, state)


func _include_aabb(state: Dictionary, local_aabb: AABB, transform: Transform3D) -> void:
	var min_point := local_aabb.position
	var max_point := local_aabb.position + local_aabb.size
	for x in [min_point.x, max_point.x]:
		for y in [min_point.y, max_point.y]:
			for z in [min_point.z, max_point.z]:
				_include_point(state, transform * Vector3(x, y, z))


func _include_point(state: Dictionary, point: Vector3) -> void:
	if not bool(state["has_bounds"]):
		state["bounds"] = AABB(point, Vector3.ZERO)
		state["has_bounds"] = true
		return
	var bounds := state["bounds"] as AABB
	state["bounds"] = bounds.expand(point)


func _assign_owner_recursive(node: Node, owner: Node) -> void:
	if node != owner:
		node.owner = owner
	for child in node.get_children():
		_assign_owner_recursive(child, owner)
