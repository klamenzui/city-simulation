extends SceneTree

const VehicleAgentScript = preload("res://Simulation/Transport/VehicleAgent.gd")

const VISUAL_SCENES := [
	"res://Scenes/Environment/Ground/MedievalVillage/floor_brick.tscn",
	"res://Scenes/Environment/Ground/MedievalVillage/floor_red_brick.tscn",
	"res://Scenes/Environment/Ground/MedievalVillage/floor_uneven_brick.tscn",
	"res://Scenes/Plants/MedievalVillage/vine_1.tscn",
	"res://Scenes/Plants/MedievalVillage/vine_2.tscn",
	"res://Scenes/Plants/MedievalVillage/vine_4.tscn",
	"res://Scenes/Plants/MedievalVillage/vine_5.tscn",
	"res://Scenes/Plants/MedievalVillage/vine_6.tscn",
	"res://Scenes/Plants/MedievalVillage/vine_9.tscn",
	"res://Scenes/FarmAssets/Quaternius/Corn_1.tscn",
	"res://Scenes/FarmAssets/Quaternius/Corn_2.tscn",
]

const VEHICLE_SCENES := {
	"res://Scenes/Vehicles/Ambulances/ambulance_low_poly.tscn": 0,
	"res://Scenes/Vehicles/Ambulances/dodge_ambulance_1957.tscn": 0,
	"res://Scenes/Vehicles/Synty/city_van.tscn": 0,
	"res://Scenes/Vehicles/Synty/city_police_car.tscn": 0,
	"res://Scenes/Vehicles/Synty/city_taxi_car.tscn": 0,
	"res://Scenes/Vehicles/Farm/tractor_yellow.tscn": 0,
	"res://Scenes/Vehicles/Farm/tractor_green.tscn": 0,
	"res://Scenes/Vehicles/Farm/crop_harvester.tscn": 0,
	"res://Scenes/Vehicles/Farm/combine_harvester_a.tscn": 0,
	"res://Scenes/Vehicles/Farm/combine_harvester_b.tscn": 0,
	"res://Scenes/Vehicles/Farm/combine_harvester_c.tscn": 0,
	"res://Scenes/Vehicles/Trucks/truck_box.tscn": 10,
	"res://Scenes/Vehicles/Trucks/truck_cargo.tscn": 8,
	"res://Scenes/Vehicles/Trucks/truck_flatbed.tscn": 12,
	"res://Scenes/Vehicles/Trucks/truck_cab.tscn": 0,
	"res://Scenes/Vehicles/Trucks/truck_tanker.tscn": 10,
}


func _initialize() -> void:
	var failures: Array[String] = []
	for scene_path in VISUAL_SCENES:
		_probe_visual_scene(scene_path, failures)
	for scene_path in VEHICLE_SCENES:
		_probe_vehicle_scene(scene_path, int(VEHICLE_SCENES[scene_path]), failures)

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(FAILED)
		return

	print(
		"EXTERNAL_ASSET_PROBE OK visuals=%d vehicles=%d"
		% [VISUAL_SCENES.size(), VEHICLE_SCENES.size()]
	)
	quit(OK)


func _probe_visual_scene(scene_path: String, failures: Array[String]) -> void:
	var root := _instantiate_scene(scene_path, failures)
	if root == null:
		return
	var mesh_count := _count_meshes(root)
	if mesh_count == 0:
		failures.append("%s contains no MeshInstance3D." % scene_path)
	root.free()


func _probe_vehicle_scene(
	scene_path: String,
	expected_capacity: int,
	failures: Array[String]
) -> void:
	var root := _instantiate_scene(scene_path, failures)
	if root == null:
		return
	if not root is VehicleBody3D:
		failures.append("%s root is not VehicleBody3D." % scene_path)
		root.free()
		return
	if root.get_script() != VehicleAgentScript:
		failures.append("%s does not use VehicleAgent.gd." % scene_path)
	if root.get_node_or_null("VisualRoot") == null:
		failures.append("%s has no VisualRoot." % scene_path)
	if root.get_node_or_null("EntryPoint") == null:
		failures.append("%s has no EntryPoint." % scene_path)
	if root.get_node_or_null("SeatPoint") == null:
		failures.append("%s has no SeatPoint." % scene_path)
	if root.get_node_or_null("EngineSound") == null:
		failures.append("%s has no EngineSound." % scene_path)
	if _count_direct_wheels(root) != 4:
		failures.append("%s does not have four direct VehicleWheel3D nodes." % scene_path)
	if not _has_enabled_collision(root):
		failures.append("%s has no enabled CollisionShape3D." % scene_path)
	if _count_meshes(root) == 0:
		failures.append("%s contains no vehicle geometry." % scene_path)

	var capacity := int(root.get("delivery_load_capacity"))
	var is_delivery := bool(root.get("delivery_vehicle"))
	if capacity != expected_capacity:
		failures.append(
			"%s delivery capacity is %d, expected %d."
			% [scene_path, capacity, expected_capacity]
		)
	if is_delivery != (expected_capacity > 0):
		failures.append("%s delivery flag does not match its capacity." % scene_path)
	root.free()


func _instantiate_scene(scene_path: String, failures: Array[String]) -> Node:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("Could not load %s." % scene_path)
		return null
	var root := packed.instantiate()
	if root == null:
		failures.append("Could not instantiate %s." % scene_path)
	return root


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count


func _count_direct_wheels(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is VehicleWheel3D:
			count += 1
	return count


func _has_enabled_collision(node: Node) -> bool:
	if node is CollisionShape3D:
		var collision := node as CollisionShape3D
		if not collision.disabled and collision.shape != null:
			return true
	for child in node.get_children():
		if _has_enabled_collision(child):
			return true
	return false
