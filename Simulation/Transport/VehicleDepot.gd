@tool
extends Node3D
class_name VehicleDepot

enum VehicleRole {
	GENERIC,
	TAXI,
	DELIVERY,
}

const TAXI_VEHICLE_GROUP := "taxi_vehicle"
const DELIVERY_VEHICLE_GROUP := "delivery_vehicles"
const PARKING_SPOT_META := "vehicle_parking_spot"
const GENERATED_VEHICLE_META := "generated_depot_vehicle"
const VEHICLE_ROLE_META := "depot_vehicle_role"

@export_group("Fleet")
@export var vehicle_scene: PackedScene = null
@export_enum("Generic", "Taxi", "Delivery") var vehicle_role: int = VehicleRole.GENERIC
@export var spawn_vehicles_on_ready: bool = true
@export var parking_spots_root_path: NodePath = ^"ParkingSpots"
@export var generated_vehicles_root_path: NodePath = ^"GeneratedVehicles"

@onready var parking_area_mesh: MeshInstance3D = $ParkingArea

@export_group("Parking Spot Layout")
@export var spot_width: float = 0.55
@export var spot_length: float = 1.25
@export var side_margin: float = 0.15
@export var front_margin: float = 0.15
@export var back_margin: float = 0.15
@export var side_gap: float = 0.08
@export var row_gap: float = 0.2
@export var spot_y_offset: float = 0.0
@export var spot_yaw_degrees: float = 0.0

@export_group("Generation")
@export var start_from_right: bool = true
@export var start_from_front: bool = true
@export var regenerate_on_ready: bool = false

@export var generate_parking_spots_now: bool:
	get:
		return false
	set(value):
		if value:
			generate_parking_spots()

@export_group("Debug")
@export var show_debug_parking_spots: bool = false
@export var debug_spot_height: float = 0.03
@export var debug_spot_color: Color = Color(0.1, 1.0, 0.2, 0.35)
@export var debug_front_color: Color = Color(1.0, 0.2, 0.1, 0.8)


func _ready() -> void:
	if Engine.is_editor_hint():
		_clear_generated_vehicles()
		_remove_empty_generated_vehicles_root()
		return

	if not show_debug_parking_spots:
		_clear_debug_spot_visuals()
	if regenerate_on_ready:
		generate_parking_spots()
	elif spawn_vehicles_on_ready:
		rebuild_generated_fleet()

func generate_parking_spots() -> void:
	if parking_area_mesh == null:
		parking_area_mesh = $ParkingArea
		push_warning("VehicleDepot: parking_area_mesh is not assigned.")
		#return

	if parking_area_mesh.mesh == null:
		push_warning("VehicleDepot: parking_area_mesh has no mesh.")
		return

	var spots_root := _get_or_create_parking_spots_root()
	if spots_root == null:
		push_warning("VehicleDepot: ParkingSpots root could not be created.")
		return

	_clear_generated_vehicles()
	_clear_generated_spots(spots_root)

	var aabb: AABB = parking_area_mesh.get_aabb()
	if aabb.size.x <= 0.01 or aabb.size.z <= 0.01:
		push_warning("VehicleDepot: ParkingArea mesh has invalid size.")
		return

	var mesh_scale: Vector3 = parking_area_mesh.global_transform.basis.get_scale()
	var scale_x: float = max(absf(mesh_scale.x), 0.001)
	var scale_z: float = max(absf(mesh_scale.z), 0.001)

	# Convert world-unit settings into mesh-local units.
	var local_spot_width: float = spot_width / scale_x
	var local_spot_length: float = spot_length / scale_z
	var local_side_margin: float = side_margin / scale_x
	var local_front_margin: float = front_margin / scale_z
	var local_back_margin: float = back_margin / scale_z
	var local_side_gap: float = side_gap / scale_x
	var local_row_gap: float = row_gap / scale_z

	var min_x: float = aabb.position.x + local_side_margin + local_spot_width * 0.5
	var max_x: float = aabb.position.x + aabb.size.x - local_side_margin - local_spot_width * 0.5

	var min_z: float = aabb.position.z + local_front_margin + local_spot_length * 0.5
	var max_z: float = aabb.position.z + aabb.size.z - local_back_margin - local_spot_length * 0.5

	if min_x > max_x or min_z > max_z:
		push_warning("VehicleDepot: ParkingArea is too small for one vehicle spot.")
		return

	var x_start: float = max_x if start_from_right else min_x
	var x_end: float = min_x if start_from_right else max_x
	var x_step: float = -(local_spot_width + local_side_gap) if start_from_right else local_spot_width + local_side_gap

	var z_start: float = min_z if start_from_front else max_z
	var z_end: float = max_z if start_from_front else min_z
	var z_step: float = local_spot_length + local_row_gap if start_from_front else -(local_spot_length + local_row_gap)

	var created_count := 0
	var row_index := 0
	var z := z_start

	while _is_inside_sequence(z, z_end, z_step):
		var col_index := 0
		var x := x_start

		while _is_inside_sequence(x, x_end, x_step):
			var local_pos := Vector3(x, aabb.position.y, z)
			_create_generated_spot(spots_root, local_pos, row_index, col_index)

			created_count += 1
			col_index += 1
			x += x_step

		row_index += 1
		z += z_step

	print("VehicleDepot: Generated %d vehicle parking spots." % created_count)
	if not Engine.is_editor_hint() and vehicle_scene != null:
		rebuild_generated_fleet()


func rebuild_generated_fleet() -> void:
	_clear_generated_vehicles()
	if Engine.is_editor_hint():
		_remove_empty_generated_vehicles_root()
		return
	if vehicle_scene == null:
		return

	var spots_root := get_node_or_null(parking_spots_root_path) as Node3D
	if spots_root == null:
		push_warning("VehicleDepot: Cannot spawn vehicles without a ParkingSpots root.")
		return

	var vehicles_root := _get_or_create_generated_vehicles_root()
	if vehicles_root == null:
		push_warning("VehicleDepot: GeneratedVehicles root could not be created.")
		return

	var spawned_count := 0
	for child in spots_root.get_children():
		var spot := child as VehicleParkingSpot
		if spot == null:
			continue

		var instance := vehicle_scene.instantiate()
		var vehicle := instance as VehicleAgent
		if vehicle == null:
			if instance != null:
				instance.free()
			push_warning("VehicleDepot: vehicle_scene must instantiate a VehicleAgent.")
			break

		_configure_vehicle_role(vehicle)
		vehicle.name = "GeneratedVehicle_%02d" % (spawned_count + 1)
		vehicle.set_meta(GENERATED_VEHICLE_META, true)
		vehicles_root.add_child(vehicle)

		vehicle.global_transform = spot.get_parking_transform()
		spot.occupy(vehicle)
		vehicle.set_meta(PARKING_SPOT_META, spot)
		spawned_count += 1

	print("VehicleDepot: Spawned %d depot vehicles." % spawned_count)


func _configure_vehicle_role(vehicle: VehicleAgent) -> void:
	vehicle.remove_from_group(TAXI_VEHICLE_GROUP)
	vehicle.remove_from_group(DELIVERY_VEHICLE_GROUP)
	vehicle.set_meta(VEHICLE_ROLE_META, _vehicle_role_name())

	match vehicle_role:
		VehicleRole.TAXI:
			vehicle.delivery_vehicle = false
			vehicle.add_to_group(TAXI_VEHICLE_GROUP)
		VehicleRole.DELIVERY:
			vehicle.delivery_vehicle = true
			vehicle.add_to_group(DELIVERY_VEHICLE_GROUP)
		_:
			vehicle.delivery_vehicle = false


func _vehicle_role_name() -> StringName:
	match vehicle_role:
		VehicleRole.TAXI:
			return &"taxi"
		VehicleRole.DELIVERY:
			return &"delivery"
		_:
			return &"generic"


func _create_generated_spot(
	spots_root: Node3D,
	local_pos: Vector3,
	row_index: int,
	col_index: int
) -> VehicleParkingSpot:
	var spot := VehicleParkingSpot.new()
	spot.name = "GeneratedSpot_%02d_%02d" % [row_index + 1, col_index + 1]
	spot.set_meta("generated_vehicle_spot", true)

	spots_root.add_child(spot)
	_set_editor_owner(spot)

	# Use the parking area transform for position, but avoid inheriting its scale.
	var global_pos: Vector3 = parking_area_mesh.global_transform * local_pos
	global_pos.y += spot_y_offset

	var plane_rotation: Basis = parking_area_mesh.global_transform.basis.orthonormalized()
	var spot_rotation := Basis(Vector3.UP, deg_to_rad(spot_yaw_degrees))

	spot.global_transform = Transform3D(plane_rotation * spot_rotation, global_pos)

	if show_debug_parking_spots:
		_add_debug_spot_visual(spot)
	return spot

func _get_or_create_parking_spots_root() -> Node3D:
	var root := get_node_or_null(parking_spots_root_path) as Node3D
	if root != null:
		return root

	root = Node3D.new()
	root.name = "ParkingSpots"
	add_child(root)
	_set_editor_owner(root)

	return root


func _get_or_create_generated_vehicles_root() -> Node3D:
	var root := get_node_or_null(generated_vehicles_root_path) as Node3D
	if root != null:
		return root

	root = Node3D.new()
	root.name = "GeneratedVehicles"
	add_child(root)
	return root


func _clear_generated_vehicles() -> void:
	var vehicles_root := get_node_or_null(generated_vehicles_root_path) as Node3D
	if vehicles_root == null:
		return

	for child in vehicles_root.get_children():
		if not child.has_meta(GENERATED_VEHICLE_META):
			continue
		if child.has_meta(PARKING_SPOT_META):
			var spot_value: Variant = child.get_meta(PARKING_SPOT_META)
			if spot_value is VehicleParkingSpot and is_instance_valid(spot_value):
				(spot_value as VehicleParkingSpot).release(child)
			child.remove_meta(PARKING_SPOT_META)
		child.free()


func _remove_empty_generated_vehicles_root() -> void:
	var vehicles_root := get_node_or_null(generated_vehicles_root_path) as Node3D
	if vehicles_root != null and vehicles_root.get_child_count() == 0:
		vehicles_root.free()


func _clear_generated_spots(spots_root: Node3D) -> void:
	for child in spots_root.get_children():
		if child.has_meta("generated_vehicle_spot") or child.name.begins_with("GeneratedSpot_"):
			child.free()

func _is_inside_sequence(value: float, end: float, step: float) -> bool:
	if step < 0.0:
		return value >= end

	return value <= end

func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return

	var edited_root := get_tree().edited_scene_root
	if edited_root != null:
		node.owner = edited_root

func _clear_debug_spot_visuals() -> void:
	var spots_root := get_node_or_null(parking_spots_root_path) as Node3D
	if spots_root == null:
		return
	for spot in spots_root.get_children():
		for child in spot.get_children():
			if child.has_meta("generated_vehicle_spot_debug"):
				child.queue_free()
		
func _add_debug_spot_visual(spot: Node3D) -> void:
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(spot_width, debug_spot_height, spot_length)

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = debug_spot_color
	body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var body := MeshInstance3D.new()
	body.name = "DebugSpotBody"
	body.mesh = body_mesh
	body.material_override = body_material
	body.position = Vector3.ZERO
	body.set_meta("generated_vehicle_spot_debug", true)

	spot.add_child(body)
	_set_editor_owner(body)

	# Small front marker to see parking direction.
	var front_mesh := BoxMesh.new()
	front_mesh.size = Vector3(spot_width * 0.8, debug_spot_height * 2.0, 0.18)

	var front_material := StandardMaterial3D.new()
	front_material.albedo_color = debug_front_color
	front_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	front_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var front_marker := MeshInstance3D.new()
	front_marker.name = "DebugFrontMarker"
	front_marker.mesh = front_mesh
	front_marker.material_override = front_material

	# Negative Z is usually forward in Godot.
	front_marker.position = Vector3(0.0, debug_spot_height, -spot_length * 0.5 + 0.15)
	front_marker.set_meta("generated_vehicle_spot_debug", true)

	spot.add_child(front_marker)
	_set_editor_owner(front_marker)
	
func get_next_parking_spot() -> VehicleParkingSpot:
	var spots_root := get_node_or_null(parking_spots_root_path) as Node3D
	if spots_root == null:
		return null

	for child in spots_root.get_children():
		var spot := child as VehicleParkingSpot
		if spot == null:
			continue

		if spot.is_free():
			return spot

	return null
	
func reserve_next_parking_spot(vehicle: Node) -> VehicleParkingSpot:
	var spot := get_next_parking_spot()
	if spot == null:
		return null

	if not spot.reserve(vehicle):
		return null

	return spot
	
