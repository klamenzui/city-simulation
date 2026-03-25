extends Building
class_name Park

func _ready() -> void:
	building_type = BuildingType.PARK
	apply_balance_settings("park")
	super._ready()
	add_to_group("parks")

func get_service_type() -> String:
	return "fun"

func get_navigation_points(world = null, lateral_lane_offset: float = 0.0) -> Dictionary:
	var nav_points := super.get_navigation_points(world, lateral_lane_offset)
	var entrance_pos := nav_points.get("entrance", get_entrance_pos()) as Vector3
	var access_pos := nav_points.get("access", entrance_pos) as Vector3
	nav_points["spawn"] = _compute_park_spawn_point(entrance_pos, access_pos, lateral_lane_offset)
	return nav_points

func _compute_park_spawn_point(
	entrance_pos: Vector3,
	access_pos: Vector3,
	lateral_lane_offset: float = 0.0
) -> Vector3:
	var outward := access_pos - entrance_pos
	outward.y = 0.0
	if outward.length_squared() <= 0.0001:
		outward = Vector3.FORWARD
	else:
		outward = outward.normalized()

	var lateral := Vector3(-outward.z, 0.0, outward.x)
	var spawn_base := entrance_pos.lerp(access_pos, 0.82)
	var spawn_pos := spawn_base + lateral * lateral_lane_offset + outward * 0.10
	spawn_pos.y = spawn_base.y
	return spawn_pos
