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
	PARK
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

var _mesh_instance: MeshInstance3D = null
var _original_material: Material = null
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

		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = _infer_click_shape_size()
		shape_node.shape = shape
		shape_node.position = Vector3(0, shape.size.y * 0.5, 0)

		area.add_child(shape_node)
		add_child(area)

	if not area.input_event.is_connected(_on_area_input_event):
		area.input_event.connect(_on_area_input_event)

func _infer_click_shape_size() -> Vector3:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return Vector3(2.0, 2.0, 2.0)

	var aabb := mesh.mesh.get_aabb()
	var size := aabb.size
	var scale := mesh.transform.basis.get_scale()
	size.x *= absf(scale.x)
	size.y *= absf(scale.y)
	size.z *= absf(scale.z)
	size.x = maxf(size.x, 1.5)
	size.y = maxf(size.y, 1.5)
	size.z = maxf(size.z, 1.5)
	return size

func _on_area_input_event(_camera: Camera3D, event: InputEvent,
		_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		clicked.emit(self)
		get_viewport().set_input_as_handled()

func _setup_highlight() -> void:
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance == null:
		return

	_original_material = _mesh_instance.get_surface_override_material(0)
	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(0.95, 0.75, 0.12)
	_highlight_material.emission_enabled = true
	_highlight_material.emission = Color(0.5, 0.35, 0.05)

func set_selected(selected: bool) -> void:
	if _mesh_instance == null:
		return
	if selected:
		_mesh_instance.set_surface_override_material(0, _highlight_material)
	else:
		_mesh_instance.set_surface_override_material(0, _original_material)

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
		"Income today": "%d €" % income_today,
		"Expenses today": "%d €" % expenses_today,
		"Profit today": "%d €" % get_profit_today(),
		"Balance": "%d €" % account.balance,
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
