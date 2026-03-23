extends Node3D
class_name Building

signal clicked(building: Building)

enum BuildingType {
	GENERIC,
	RESIDENTIAL,
	RESTAURANT,
	SHOP,
	SUPERMARKET,
	CAFE,
	CITY_HALL,
	UNIVERSITY,
	CINEMA,
	PARK,
	FARM,
	FACTORY,
}

@export var building_name: String = "Building"
@export var building_type: BuildingType = BuildingType.GENERIC
@export var entrance: Node3D
@export var debug_panel: DebugPanel
@export var capacity: int = 10
@export var open_hour: int = 8
@export var close_hour: int = 22
@export var job_capacity: int = 0
@export var navigation_blocker_enabled: bool = true
@export var navigation_blocker_margin: float = 0.75
@export var entrance_clearance_width: float = 1.9
@export var entrance_clearance_depth: float = 1.4
@export var entrance_trigger_enabled: bool = true
@export var entrance_trigger_radius: float = 0.7
@export var entrance_trigger_height: float = 1.6
@export var entrance_trigger_outset: float = 0.55

var account: Account = Account.new()
var workers: Array[Citizen] = []
var visitors: Array[Citizen] = []

var income_today: int = 0
var expenses_today: int = 0

var _highlight_targets: Array[MeshInstance3D] = []
var _original_overlay_by_mesh: Dictionary = {}
var _highlight_material: StandardMaterial3D = null

func _ready() -> void:
	add_to_group("buildings")
	if building_name.strip_edges().is_empty():
		building_name = name
	account.owner_name = get_display_name()
	_setup_clickable()
	_setup_highlight()
	_setup_navigation_blocker()
	_setup_entrance_trigger()

func _setup_clickable() -> void:
	var area := get_node_or_null("ClickArea") as Area3D
	if area == null:
		area = Area3D.new()
		area.name = "ClickArea"
		area.input_ray_pickable = true
		add_child(area)

	var shape_node := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "CollisionShape3D"
		area.add_child(shape_node)

	var shape := shape_node.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		shape_node.shape = shape

	var bounds := _infer_click_bounds()
	shape.size = bounds.size
	shape_node.position = bounds.position + bounds.size * 0.5

	if not area.input_event.is_connected(_on_area_input_event):
		area.input_event.connect(_on_area_input_event)

func _infer_click_bounds() -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(self, meshes)
	if meshes.is_empty():
		return AABB(Vector3(-0.75, 0.0, -0.75), Vector3(1.5, 2.0, 1.5))

	var has_points := false
	var min_v := Vector3.ZERO
	var max_v := Vector3.ZERO
	var to_local := global_transform.affine_inverse()

	for mesh in meshes:
		if mesh == null or mesh.mesh == null or not mesh.is_inside_tree():
			continue
		var local_xf := to_local * mesh.global_transform
		for corner in _aabb_corners(mesh.mesh.get_aabb()):
			var p := local_xf * corner
			if not has_points:
				has_points = true
				min_v = p
				max_v = p
			else:
				min_v = Vector3(minf(min_v.x, p.x), minf(min_v.y, p.y), minf(min_v.z, p.z))
				max_v = Vector3(maxf(max_v.x, p.x), maxf(max_v.y, p.y), maxf(max_v.z, p.z))

	if not has_points:
		return AABB(Vector3(-0.75, 0.0, -0.75), Vector3(1.5, 2.0, 1.5))

	var size := max_v - min_v
	size = Vector3(maxf(size.x, 1.5), maxf(size.y, 1.5), maxf(size.z, 1.5))
	var base_y := minf(min_v.y, 0.0)
	return AABB(Vector3(min_v.x, base_y, min_v.z), size)

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := child as MeshInstance3D
			if mesh.mesh != null:
				out.append(mesh)
		if child is Node:
			_collect_mesh_instances(child as Node, out)

func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	return [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, s.y, s.z),
		p + s,
	]

func _on_area_input_event(_camera: Camera3D, event: InputEvent,
		_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		clicked.emit(self)
		get_viewport().set_input_as_handled()

func _setup_highlight() -> void:
	_highlight_targets.clear()
	_original_overlay_by_mesh.clear()
	_collect_mesh_instances(self, _highlight_targets)
	if _highlight_targets.is_empty():
		return

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(0.95, 0.75, 0.12)
	_highlight_material.emission_enabled = true
	_highlight_material.emission = Color(0.5, 0.35, 0.05)

	for mesh in _highlight_targets:
		if mesh == null:
			continue
		_original_overlay_by_mesh[mesh] = mesh.material_overlay

func _setup_navigation_blocker() -> void:
	if not navigation_blocker_enabled:
		return
	if building_type == BuildingType.PARK:
		return
	if get_node_or_null("NavigationBlocker") != null:
		return
	if _has_physics_body(self):
		return

	var bounds := get_footprint_bounds()
	var blocker_size := bounds.size
	blocker_size.x = maxf(blocker_size.x - navigation_blocker_margin, 0.5)
	blocker_size.z = maxf(blocker_size.z - navigation_blocker_margin, 0.5)
	blocker_size.y = maxf(blocker_size.y, 1.2)

	var blocker := StaticBody3D.new()
	blocker.name = "NavigationBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 1

	_add_navigation_blocker_shapes(blocker, bounds, blocker_size)
	add_child(blocker)

func _add_navigation_blocker_shapes(blocker: StaticBody3D, bounds: AABB, blocker_size: Vector3) -> void:
	var blocker_bounds := _build_blocker_bounds(bounds, blocker_size)
	var shape_index := 0
	var cutout := _compute_entrance_cutout(blocker_bounds)
	if cutout.is_empty():
		_add_blocker_shape(blocker, blocker_bounds, shape_index)
		return

	var axis := str(cutout["axis"])
	var sign := int(cutout["sign"])
	var depth := float(cutout["depth"])
	var gap_min := float(cutout["gap_min"])
	var gap_max := float(cutout["gap_max"])

	if axis == "x":
		var min_x := blocker_bounds.position.x
		var max_x := blocker_bounds.position.x + blocker_bounds.size.x
		var min_z := blocker_bounds.position.z
		var max_z := blocker_bounds.position.z + blocker_bounds.size.z
		var band_min_x := max_x - depth if sign > 0 else min_x
		var band_max_x := max_x if sign > 0 else min_x + depth
		if sign > 0:
			var core_size_x := band_min_x - min_x
			if core_size_x > 0.15:
				shape_index = _add_blocker_shape(blocker, AABB(
					Vector3(min_x, blocker_bounds.position.y, min_z),
					Vector3(core_size_x, blocker_bounds.size.y, blocker_bounds.size.z)
				), shape_index)
		else:
			var core_min_x := band_max_x
			var core_size_x := max_x - core_min_x
			if core_size_x > 0.15:
				shape_index = _add_blocker_shape(blocker, AABB(
					Vector3(core_min_x, blocker_bounds.position.y, min_z),
					Vector3(core_size_x, blocker_bounds.size.y, blocker_bounds.size.z)
				), shape_index)

		var band_size_x := band_max_x - band_min_x
		if band_size_x > 0.15:
			var left_size_z := gap_min - min_z
			if left_size_z > 0.15:
				shape_index = _add_blocker_shape(blocker, AABB(
					Vector3(band_min_x, blocker_bounds.position.y, min_z),
					Vector3(band_size_x, blocker_bounds.size.y, left_size_z)
				), shape_index)
			var right_size_z := max_z - gap_max
			if right_size_z > 0.15:
				shape_index = _add_blocker_shape(blocker, AABB(
					Vector3(band_min_x, blocker_bounds.position.y, gap_max),
					Vector3(band_size_x, blocker_bounds.size.y, right_size_z)
				), shape_index)
	else:
		var min_x := blocker_bounds.position.x
		var max_x := blocker_bounds.position.x + blocker_bounds.size.x
		var min_z := blocker_bounds.position.z
		var max_z := blocker_bounds.position.z + blocker_bounds.size.z
		var band_min_z := max_z - depth if sign > 0 else min_z
		var band_max_z := max_z if sign > 0 else min_z + depth
		if sign > 0:
			var core_size_z := band_min_z - min_z
			if core_size_z > 0.15:
				shape_index = _add_blocker_shape(blocker, AABB(
					Vector3(min_x, blocker_bounds.position.y, min_z),
					Vector3(blocker_bounds.size.x, blocker_bounds.size.y, core_size_z)
				), shape_index)
		else:
			var core_min_z := band_max_z
			var core_size_z := max_z - core_min_z
			if core_size_z > 0.15:
				shape_index = _add_blocker_shape(blocker, AABB(
					Vector3(min_x, blocker_bounds.position.y, core_min_z),
					Vector3(blocker_bounds.size.x, blocker_bounds.size.y, core_size_z)
				), shape_index)

		var band_size_z := band_max_z - band_min_z
		if band_size_z > 0.15:
			var left_size_x := gap_min - min_x
			if left_size_x > 0.15:
				shape_index = _add_blocker_shape(blocker, AABB(
					Vector3(min_x, blocker_bounds.position.y, band_min_z),
					Vector3(left_size_x, blocker_bounds.size.y, band_size_z)
				), shape_index)
			var right_size_x := max_x - gap_max
			if right_size_x > 0.15:
				shape_index = _add_blocker_shape(blocker, AABB(
					Vector3(gap_max, blocker_bounds.position.y, band_min_z),
					Vector3(right_size_x, blocker_bounds.size.y, band_size_z)
				), shape_index)

	if shape_index == 0:
		_add_blocker_shape(blocker, blocker_bounds, 0)

func _build_blocker_bounds(bounds: AABB, blocker_size: Vector3) -> AABB:
	var blocker_center := Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y + blocker_size.y * 0.5,
		bounds.position.z + bounds.size.z * 0.5
	)
	return AABB(blocker_center - blocker_size * 0.5, blocker_size)

func _compute_entrance_cutout(blocker_bounds: AABB) -> Dictionary:
	var entrance_node := get_entrance_node()
	if entrance_node == null:
		return {}

	var local_entrance := to_local(entrance_node.global_position)
	var center := blocker_bounds.position + blocker_bounds.size * 0.5
	var outward_dir := local_entrance - center
	outward_dir.y = 0.0
	if outward_dir.length_squared() <= 0.0001:
		return {}
	outward_dir = outward_dir.normalized()

	var axis := "x" if absf(outward_dir.x) >= absf(outward_dir.z) else "z"
	var sign := 1 if (outward_dir.x if axis == "x" else outward_dir.z) >= 0.0 else -1
	var axis_size := blocker_bounds.size.x if axis == "x" else blocker_bounds.size.z
	var cross_size := blocker_bounds.size.z if axis == "x" else blocker_bounds.size.x
	if axis_size <= 0.4 or cross_size <= 0.6:
		return {}

	var desired_depth := maxf(entrance_clearance_depth, entrance_trigger_outset + entrance_trigger_radius + 0.2)
	var desired_width := maxf(entrance_clearance_width, entrance_trigger_radius * 2.0 + 0.5)
	var cutout_depth := clampf(desired_depth, 0.45, axis_size - 0.15)
	var cutout_width := clampf(desired_width, 0.7, cross_size - 0.2)
	if cutout_depth <= 0.15 or cutout_width <= 0.25:
		return {}

	var cross_min := blocker_bounds.position.z if axis == "x" else blocker_bounds.position.x
	var cross_max := cross_min + cross_size
	var cross_center := local_entrance.z if axis == "x" else local_entrance.x
	var half_gap := cutout_width * 0.5
	var clamped_center := clampf(cross_center, cross_min + half_gap, cross_max - half_gap)
	var gap_min := maxf(cross_min, clamped_center - half_gap)
	var gap_max := minf(cross_max, clamped_center + half_gap)
	if gap_max - gap_min <= 0.25:
		return {}

	return {
		"axis": axis,
		"sign": sign,
		"depth": cutout_depth,
		"gap_min": gap_min,
		"gap_max": gap_max,
	}

func _add_blocker_shape(blocker: StaticBody3D, local_bounds: AABB, shape_index: int) -> int:
	if local_bounds.size.x <= 0.05 or local_bounds.size.y <= 0.05 or local_bounds.size.z <= 0.05:
		return shape_index

	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D" if shape_index == 0 else "CollisionShape3D_%d" % shape_index
	var shape := BoxShape3D.new()
	shape.size = local_bounds.size
	shape_node.shape = shape
	shape_node.position = local_bounds.position + local_bounds.size * 0.5
	blocker.add_child(shape_node)
	return shape_index + 1

func _setup_entrance_trigger() -> void:
	if not entrance_trigger_enabled:
		return
	if get_node_or_null("EntranceTrigger") != null:
		return

	var entrance_node := get_entrance_node()
	if entrance_node == null:
		return

	var local_entrance := to_local(entrance_node.global_position)
	var bounds := get_footprint_bounds()
	var bounds_center := bounds.position + bounds.size * 0.5
	var outward_dir := Vector3(
		local_entrance.x - bounds_center.x,
		0.0,
		local_entrance.z - bounds_center.z
	)
	if outward_dir.length_squared() <= 0.0001:
		outward_dir = Vector3.FORWARD
	else:
		outward_dir = outward_dir.normalized()

	var trigger := StaticBody3D.new()
	trigger.name = "EntranceTrigger"
	trigger.collision_layer = 8
	trigger.collision_mask = 0

	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var shape := SphereShape3D.new()
	shape.radius = entrance_trigger_radius
	shape_node.shape = shape

	var trigger_pos := local_entrance + outward_dir * entrance_trigger_outset
	trigger_pos.y = maxf(local_entrance.y, entrance_trigger_height * 0.5)
	shape_node.position = trigger_pos

	trigger.add_child(shape_node)
	add_child(trigger)

func _has_physics_body(node: Node) -> bool:
	for child in node.get_children():
		if child.name == "ClickArea" or child.name == "NavigationBlocker":
			continue
		if child is StaticBody3D or child is CharacterBody3D or child is RigidBody3D:
			return true
		if _has_physics_body(child):
			return true
	return false

func set_selected(selected: bool) -> void:
	if _highlight_targets.is_empty():
		return
	for mesh in _highlight_targets:
		if mesh == null:
			continue
		if selected:
			mesh.material_overlay = _highlight_material
		else:
			mesh.material_overlay = _original_overlay_by_mesh.get(mesh, null)

func select(panel: DebugPanel, world = null) -> void:
	debug_panel = panel
	set_selected(panel != null)
	refresh_info_panel(world)

func refresh_info_panel(world = null) -> void:
	if debug_panel == null:
		return
	debug_panel.update_debug(get_info(world))

func get_info(world = null) -> Dictionary:
	var hour := -1
	if world != null and world.time != null:
		hour = world.time.get_hour()

	var info: Dictionary = {
		"Building": building_name,
		"Type": get_building_type_name(),
		"Service": get_service_type(),
		"Workers": "%d / %d" % [workers.size(), max(job_capacity, 0)],
		"Visitors": "%d / %d" % [visitors.size(), max(capacity, 0)],
		"Open": "%02d:00 - %02d:00 (%s)" % [
			open_hour,
			close_hour,
			"OPEN" if is_open(hour) else "CLOSED"
		],
		"Income today": "%d EUR" % income_today,
		"Expenses today": "%d EUR" % expenses_today,
		"Profit today": "%d EUR" % get_profit_today(),
		"Balance": "%d EUR" % account.balance,
		"Position": "%d, %d, %d " % [global_position.x, global_position.y, global_position.z],
	}

	var extra := _get_extra_info(world)
	for key in extra.keys():
		info[key] = extra[key]
	return info

func _get_extra_info(_world = null) -> Dictionary:
	return {}

func get_building_type_name() -> String:
	match building_type:
		BuildingType.RESIDENTIAL:
			return "Residential"
		BuildingType.RESTAURANT:
			return "Restaurant"
		BuildingType.SHOP:
			return "Shop"
		BuildingType.SUPERMARKET:
			return "Supermarket"
		BuildingType.CAFE:
			return "Cafe"
		BuildingType.CITY_HALL:
			return "City Hall"
		BuildingType.UNIVERSITY:
			return "University"
		BuildingType.CINEMA:
			return "Cinema"
		BuildingType.PARK:
			return "Park"
		BuildingType.FARM:
			return "Farm"
		BuildingType.FACTORY:
			return "Factory"
		_:
			return "Generic"

func is_open(hour: int = -1) -> bool:
	if hour < 0:
		return true

	if open_hour == close_hour:
		return true

	if close_hour > open_hour:
		return hour >= open_hour and hour < close_hour

	# Overnight schedule, e.g. 20:00 - 04:00
	return hour >= open_hour or hour < close_hour

func get_service_type() -> String:
	return "generic"

func has_free_job_slots() -> bool:
	if job_capacity <= 0:
		return false
	return workers.size() < job_capacity

func try_hire(c: Citizen) -> bool:
	if c == null:
		return false
	if workers.has(c):
		return true
	if not has_free_job_slots():
		return false
	workers.append(c)
	return true

func fire(c: Citizen) -> void:
	workers.erase(c)

func try_add_visitor(c: Citizen) -> bool:
	if c == null:
		return false
	if visitors.has(c):
		return true
	if capacity > 0 and visitors.size() >= capacity:
		return false
	visitors.append(c)
	return true

func remove_visitor(c: Citizen) -> void:
	visitors.erase(c)

func record_income(amount: int) -> void:
	if amount <= 0:
		return
	income_today += amount

func record_expense(amount: int) -> void:
	if amount <= 0:
		return
	expenses_today += amount

func get_profit_today() -> int:
	return income_today - expenses_today

func begin_new_day() -> void:
	income_today = 0
	expenses_today = 0

func get_entrance_pos() -> Vector3:
	var entrance_node := get_entrance_node()
	if entrance_node != null:
		return entrance_node.global_position
	return global_position

func get_entrance_node() -> Node3D:
	if entrance != null:
		return entrance
	return get_node_or_null("Entrance") as Node3D

func get_navigation_points(world = null, lateral_lane_offset: float = 0.0) -> Dictionary:
	var entrance_pos := get_entrance_pos()
	var access_pos := entrance_pos
	if world != null and world.has_method("get_pedestrian_access_point"):
		access_pos = world.get_pedestrian_access_point(entrance_pos, self)
	return {
		"entrance": entrance_pos,
		"access": access_pos,
		"spawn": _compute_navigation_spawn_point(entrance_pos, access_pos, lateral_lane_offset),
	}

func _compute_navigation_spawn_point(
	entrance_pos: Vector3,
	access_pos: Vector3,
	lateral_lane_offset: float = 0.0
) -> Vector3:
	var outward := access_pos - entrance_pos
	outward.y = 0.0
	if outward.length_squared() <= 0.0001:
		outward = access_pos - global_position
		outward.y = 0.0
	if outward.length_squared() <= 0.0001:
		outward = Vector3.FORWARD
	else:
		outward = outward.normalized()

	var lateral := Vector3(-outward.z, 0.0, outward.x)
	var spawn_base := entrance_pos.lerp(access_pos, 0.55)
	var spawn_pos := spawn_base + lateral * lateral_lane_offset + outward * 0.02
	spawn_pos.y = spawn_base.y
	return spawn_pos

func get_navigation_debug_summary(world = null) -> String:
	var nav_points := get_navigation_points(world, 0.0)
	return "entrance=%s access=%s spawn=%s blocker_margin=%.2f clearance=(w=%.2f d=%.2f) trigger=(r=%.2f out=%.2f)" % [
		_format_vec3(nav_points.get("entrance", get_entrance_pos())),
		_format_vec3(nav_points.get("access", get_entrance_pos())),
		_format_vec3(nav_points.get("spawn", get_entrance_pos())),
		navigation_blocker_margin,
		entrance_clearance_width,
		entrance_clearance_depth,
		entrance_trigger_radius,
		entrance_trigger_outset
	]

func owns_navigation_node(node: Node) -> bool:
	var current := node
	while current != null:
		if current == self:
			return true
		current = current.get_parent()
	return false

func is_entrance_trigger_node(node: Node) -> bool:
	if node == null or not owns_navigation_node(node):
		return false
	var current := node
	while current != null and current != self:
		if current.name == "EntranceTrigger":
			return true
		current = current.get_parent()
	return false

func get_footprint_bounds() -> AABB:
	return _infer_click_bounds()

func get_display_name() -> String:
	if not building_name.strip_edges().is_empty():
		return building_name
	return name

func _format_vec3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]
