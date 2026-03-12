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
	account.owner_name = building_name
	_setup_clickable()
	_setup_highlight()

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
		if mesh == null or mesh.mesh == null:
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
	return entrance.global_position if entrance else global_position
