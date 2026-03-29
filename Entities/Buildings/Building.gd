extends Node3D
class_name Building

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

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
@export var base_operating_cost: int = 0
@export_range(0.0, 100.0, 0.1) var condition_start: float = 100.0
@export var daily_decay: float = 1.0
@export var maintenance_cost_per_day: int = 14
@export_range(0.0, 100.0, 0.1) var repair_threshold: float = 60.0
@export var start_balance: int = 0
@export var max_missed_payment_days_before_closure: int = 3
@export_range(0.1, 1.0, 0.01) var struggling_efficiency_multiplier: float = 0.72
@export_range(0.1, 1.0, 0.01) var struggling_customer_multiplier: float = 0.78
@export var max_underfunded_days_before_closure: int = 3
@export_range(0.1, 1.0, 0.01) var underfunded_efficiency_multiplier: float = 0.82
@export_range(0.1, 1.0, 0.01) var underfunded_service_multiplier: float = 0.76

var account: Account = Account.new()
var workers: Array[Citizen] = []
var visitors: Array[Citizen] = []

var income_today: int = 0
var expenses_today: int = 0
var wages_today: int = 0
var taxes_today: int = 0
var maintenance_today: int = 0
var production_costs_today: int = 0
var operating_costs_today: int = 0
var wages_unpaid_today: int = 0
var taxes_unpaid_today: int = 0
var maintenance_unpaid_today: int = 0
var operating_unpaid_today: int = 0
var public_funding_requested_today: int = 0
var public_funding_today: int = 0
var public_funding_shortfall_today: int = 0
var condition: float = 100.0
var forced_closed_reason: String = ""
var missed_wage_days: int = 0
var missed_tax_days: int = 0
var missed_maintenance_days: int = 0
var negative_balance_days: int = 0
var underfunded_days: int = 0

var _highlight_targets: Array[MeshInstance3D] = []
var _original_overlay_by_mesh: Dictionary = {}
var _highlight_material: StandardMaterial3D = null

func _ready() -> void:
	add_to_group("buildings")
	if building_name.strip_edges().is_empty():
		building_name = name
	_apply_common_balance_settings()
	account.owner_name = get_display_name()
	_setup_clickable()
	_setup_highlight()
	_setup_navigation_blocker()
	_setup_entrance_trigger()

func _apply_common_balance_settings() -> void:
	_apply_financial_balance_settings(BalanceConfig.get_section("building"))
	_apply_financial_balance_settings(BalanceConfig.get_section("economy.buildings"))
	_apply_financial_balance_settings(BalanceConfig.get_section("economy.city_hall"))
	_maybe_apply_start_balance()

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
	var open_status_display := get_open_status_display_label(hour)
	var effective_capacity := get_effective_visitor_capacity()

	var info: Dictionary = {
		"Building": building_name,
		"Type": get_building_type_name(),
		"Category": get_economy_category_label(),
		"Service": get_service_type(),
		"Workers": "%d / %d" % [workers.size(), max(job_capacity, 0)],
		"Visitors": "%d / %d" % [visitors.size(), max(effective_capacity, 0)],
		"Status": open_status_display,
		"Financial state": get_financial_state_display_label(),
		"Open": "%02d:00 - %02d:00 (%s)" % [
			open_hour,
			close_hour,
			open_status_display
		],
		"Income today": "%d EUR" % income_today,
		"Expenses today": "%d EUR" % expenses_today,
		"Profit today": "%d EUR" % get_profit_today(),
		"Balance": "%d EUR" % account.balance,
		"Condition": "%.0f / 100 (%s)" % [condition, get_condition_state_label()],
		"Base operating cost": "%d EUR" % get_base_operating_cost_per_day(),
		"Payroll due": "%d EUR" % get_payroll_due_today(),
		"Estimated daily obligations": "%d EUR" % get_total_daily_obligation_estimate(),
		"Wages paid / unpaid": "%d / %d EUR" % [wages_today, wages_unpaid_today],
		"Taxes paid / unpaid": "%d / %d EUR" % [taxes_today, taxes_unpaid_today],
		"Maintenance paid / unpaid": "%d / %d EUR" % [maintenance_today, maintenance_unpaid_today],
		"Production today": "%d EUR" % production_costs_today,
		"Base operating paid / unpaid": "%d / %d EUR" % [operating_costs_today, operating_unpaid_today],
		"Public funding requested": "%d EUR" % public_funding_requested_today,
		"Public funding today": "%d EUR" % public_funding_today,
		"Funding shortfall": "%d EUR" % public_funding_shortfall_today,
		"Missed days": "w=%d t=%d m=%d neg=%d public=%d" % [
			missed_wage_days,
			missed_tax_days,
			missed_maintenance_days,
			negative_balance_days,
			underfunded_days
		],
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

func apply_balance_settings(type_key: String) -> Dictionary:
	var settings := BalanceConfig.get_section("buildings.%s" % type_key)
	if settings.is_empty():
		return settings

	_apply_financial_balance_settings(settings)

	if settings.has("capacity"):
		capacity = int(settings.get("capacity", capacity))
	if settings.has("job_capacity"):
		job_capacity = int(settings.get("job_capacity", job_capacity))
	if settings.has("open_hour"):
		open_hour = int(settings.get("open_hour", open_hour))
	if settings.has("close_hour"):
		close_hour = int(settings.get("close_hour", close_hour))
	if settings.has("navigation_blocker_margin"):
		navigation_blocker_margin = float(settings.get("navigation_blocker_margin", navigation_blocker_margin))
	if settings.has("entrance_clearance_width"):
		entrance_clearance_width = float(settings.get("entrance_clearance_width", entrance_clearance_width))
	if settings.has("entrance_clearance_depth"):
		entrance_clearance_depth = float(settings.get("entrance_clearance_depth", entrance_clearance_depth))
	if settings.has("entrance_trigger_radius"):
		entrance_trigger_radius = float(settings.get("entrance_trigger_radius", entrance_trigger_radius))
	if settings.has("entrance_trigger_outset"):
		entrance_trigger_outset = float(settings.get("entrance_trigger_outset", entrance_trigger_outset))
	_maybe_apply_start_balance()

	return settings

func _apply_financial_balance_settings(settings: Dictionary) -> void:
	if settings.is_empty():
		return
	if settings.has("base_operating_cost"):
		base_operating_cost = int(settings.get("base_operating_cost", base_operating_cost))
	elif settings.has("daily_operating_cost"):
		base_operating_cost = int(settings.get("daily_operating_cost", base_operating_cost))
	if settings.has("condition_start"):
		condition_start = float(settings.get("condition_start", condition_start))
	if settings.has("daily_decay"):
		daily_decay = float(settings.get("daily_decay", daily_decay))
	if settings.has("maintenance_cost_per_day"):
		maintenance_cost_per_day = int(settings.get("maintenance_cost_per_day", maintenance_cost_per_day))
	if settings.has("repair_threshold"):
		repair_threshold = float(settings.get("repair_threshold", repair_threshold))
	if settings.has("start_balance"):
		start_balance = int(settings.get("start_balance", start_balance))
	if settings.has("max_missed_payment_days_before_closure"):
		max_missed_payment_days_before_closure = int(settings.get("max_missed_payment_days_before_closure", max_missed_payment_days_before_closure))
	if settings.has("struggling_efficiency_multiplier"):
		struggling_efficiency_multiplier = float(settings.get("struggling_efficiency_multiplier", struggling_efficiency_multiplier))
	if settings.has("struggling_customer_multiplier"):
		struggling_customer_multiplier = float(settings.get("struggling_customer_multiplier", struggling_customer_multiplier))
	if settings.has("max_underfunded_days_before_closure"):
		max_underfunded_days_before_closure = int(settings.get("max_underfunded_days_before_closure", max_underfunded_days_before_closure))
	if settings.has("underfunded_efficiency_multiplier"):
		underfunded_efficiency_multiplier = float(settings.get("underfunded_efficiency_multiplier", underfunded_efficiency_multiplier))
	if settings.has("underfunded_service_multiplier"):
		underfunded_service_multiplier = float(settings.get("underfunded_service_multiplier", underfunded_service_multiplier))
	condition = clampf(condition_start, 0.0, 100.0)

func _maybe_apply_start_balance() -> void:
	if start_balance <= 0:
		return
	if account.balance != 0:
		return
	if not is_economic_building():
		return
	account.balance = start_balance

func get_economy_category_label() -> String:
	if is_public_building():
		return "Public"
	if is_economic_building():
		return "Economic"
	return "Neutral"

func is_public_building() -> bool:
	match building_type:
		BuildingType.CITY_HALL, BuildingType.UNIVERSITY, BuildingType.PARK:
			return true
		_:
			return false

func is_economic_building() -> bool:
	match building_type:
		BuildingType.CAFE, BuildingType.CINEMA, BuildingType.FACTORY, BuildingType.FARM, \
		BuildingType.RESIDENTIAL, BuildingType.RESTAURANT, BuildingType.SHOP, BuildingType.SUPERMARKET:
			return true
		_:
			return false

func pays_business_tax() -> bool:
	return is_economic_building()

func requires_public_funding() -> bool:
	return building_type == BuildingType.UNIVERSITY or building_type == BuildingType.PARK

func can_be_force_closed() -> bool:
	return building_type != BuildingType.CITY_HALL

func is_financially_closed() -> bool:
	return not forced_closed_reason.is_empty()

func is_underfunded() -> bool:
	return requires_public_funding() and not is_financially_closed() and underfunded_days > 0

func is_struggling() -> bool:
	if not is_economic_building() or is_financially_closed():
		return false
	return missed_wage_days > 0 or missed_tax_days > 0 or missed_maintenance_days > 0 or negative_balance_days > 0

func get_financial_state_key() -> String:
	if is_financially_closed():
		return "CLOSED"
	if is_underfunded():
		return "UNDERFUNDED"
	if is_struggling():
		return "STRUGGLING"
	return "NORMAL"

func get_financial_state_display_label() -> String:
	match get_financial_state_key():
		"CLOSED":
			return "Geschlossen"
		"UNDERFUNDED":
			return "Unterfinanziert"
		"STRUGGLING":
			return "Angeschlagen"
		_:
			return "Stabil"

func can_accept_workers() -> bool:
	return not is_financially_closed()

func get_public_funding_priority() -> int:
	match building_type:
		BuildingType.CITY_HALL:
			return 3
		BuildingType.UNIVERSITY:
			return 2
		BuildingType.PARK:
			return 1
		_:
			return 0

func requires_staff_to_operate() -> bool:
	if job_capacity <= 0:
		return false
	match building_type:
		BuildingType.RESIDENTIAL, BuildingType.PARK:
			return false
		_:
			return true

func has_required_staff() -> bool:
	if not requires_staff_to_operate():
		return true
	return workers.size() > 0

func get_open_status_label(hour: int = -1) -> String:
	if is_financially_closed():
		return "NO_FUNDS"

	if not has_required_staff():
		return "UNSTAFFED"

	if not _is_within_open_hours(hour):
		return "CLOSED"

	if is_underfunded():
		return "UNDERFUNDED"
	if is_struggling():
		return "STRUGGLING"
	return "OPEN"

func _is_within_open_hours(hour: int) -> bool:
	if hour < 0:
		return true
	if open_hour == close_hour:
		return true
	if close_hour > open_hour:
		return hour >= open_hour and hour < close_hour
	return hour >= open_hour or hour < close_hour

func get_open_status_display_label(hour: int = -1) -> String:
	match get_open_status_label(hour):
		"NO_FUNDS":
			return "Geschlossen: kein Budget"
		"UNDERFUNDED":
			return "Offen: unterfinanziert"
		"STRUGGLING":
			return "Offen: angeschlagen"
		"UNSTAFFED":
			return "Geschlossen: %s" % get_staff_requirement_label()
		"CLOSED":
			return "Geschlossen"
		"OPEN":
			return "Offen"
		_:
			return get_open_status_label(hour)

func is_open(hour: int = -1) -> bool:
	var status := get_open_status_label(hour)
	return status == "OPEN" or status == "UNDERFUNDED" or status == "STRUGGLING"

func get_service_type() -> String:
	return "generic"

func get_staff_requirement_label() -> String:
	return "kein Personal"

func is_outdoor_destination() -> bool:
	return false

func has_free_job_slots() -> bool:
	if job_capacity <= 0:
		return false
	if not can_accept_workers():
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
	if is_financially_closed() and account.balance >= 0:
		reopen_after_funding()
	return true

func fire(c: Citizen) -> void:
	if c == null:
		return
	workers.erase(c)
	if c.job != null and c.job.workplace == self:
		c.job.workplace = null

func try_add_visitor(c: Citizen) -> bool:
	if c == null:
		return false
	if is_financially_closed():
		return false
	if visitors.has(c):
		return true
	var effective_capacity := get_effective_visitor_capacity()
	if effective_capacity > 0 and visitors.size() >= effective_capacity:
		return false
	visitors.append(c)
	return true

func remove_visitor(c: Citizen) -> void:
	visitors.erase(c)

func on_citizen_entered(c: Citizen) -> void:
	if c == null:
		return
	if self is ResidentialBuilding or building_type == BuildingType.RESIDENTIAL:
		return
	if c.job != null and c.job.workplace == self:
		return
	try_add_visitor(c)

func on_citizen_exited(c: Citizen) -> void:
	if c == null:
		return
	remove_visitor(c)

func record_income(amount: int) -> void:
	if amount <= 0:
		return
	income_today += amount

func record_expense(amount: int) -> void:
	if amount <= 0:
		return
	expenses_today += amount

func record_wage_expense(amount: int) -> void:
	if amount <= 0:
		return
	wages_today += amount
	record_expense(amount)

func record_tax_expense(amount: int) -> void:
	if amount <= 0:
		return
	taxes_today += amount
	record_expense(amount)

func record_maintenance_expense(amount: int) -> void:
	if amount <= 0:
		return
	maintenance_today += amount
	record_expense(amount)

func record_production_expense(amount: int) -> void:
	if amount <= 0:
		return
	production_costs_today += amount
	record_expense(amount)

func record_base_operating_expense(amount: int) -> void:
	if amount <= 0:
		return
	operating_costs_today += amount
	record_expense(amount)

func record_public_funding_request(amount: int) -> void:
	if amount <= 0:
		return
	public_funding_requested_today += amount

func record_public_funding(amount: int) -> void:
	if amount <= 0:
		return
	public_funding_today += amount
	record_income(amount)

func record_public_funding_shortfall(amount: int) -> void:
	if amount <= 0:
		return
	public_funding_shortfall_today += amount

func record_unpaid_wages(amount: int) -> void:
	if amount <= 0:
		return
	wages_unpaid_today += amount

func record_unpaid_taxes(amount: int) -> void:
	if amount <= 0:
		return
	taxes_unpaid_today += amount

func record_unpaid_maintenance(amount: int) -> void:
	if amount <= 0:
		return
	maintenance_unpaid_today += amount

func record_unpaid_operating(amount: int) -> void:
	if amount <= 0:
		return
	operating_unpaid_today += amount

func get_profit_today() -> int:
	return income_today - expenses_today

func begin_new_day() -> void:
	income_today = 0
	expenses_today = 0
	wages_today = 0
	taxes_today = 0
	maintenance_today = 0
	production_costs_today = 0
	operating_costs_today = 0
	wages_unpaid_today = 0
	taxes_unpaid_today = 0
	maintenance_unpaid_today = 0
	operating_unpaid_today = 0
	public_funding_requested_today = 0
	public_funding_today = 0
	public_funding_shortfall_today = 0
	if is_financially_closed() and account.balance >= 0 and not can_be_force_closed():
		reopen_after_funding()

func get_condition_state_label() -> String:
	if condition >= repair_threshold:
		return "Good"
	if condition >= repair_threshold * 0.7:
		return "Needs repair"
	if condition >= repair_threshold * 0.4:
		return "Poor"
	return "Critical"

func get_condition_efficiency_multiplier() -> float:
	if condition >= repair_threshold:
		return 1.0
	var threshold := maxf(repair_threshold, 1.0)
	return clampf(0.45 + (condition / threshold) * 0.55, 0.35, 1.0)

func get_condition_attractiveness_multiplier() -> float:
	if condition >= repair_threshold:
		return 1.0
	var threshold := maxf(repair_threshold, 1.0)
	return clampf(0.55 + (condition / threshold) * 0.45, 0.4, 1.0)

func get_operating_efficiency_multiplier() -> float:
	var multiplier := get_condition_efficiency_multiplier()
	if is_underfunded():
		multiplier *= underfunded_efficiency_multiplier
	elif is_struggling():
		multiplier *= struggling_efficiency_multiplier
	return multiplier

func get_service_multiplier() -> float:
	var multiplier := 1.0
	if is_underfunded():
		multiplier *= underfunded_service_multiplier
	elif is_struggling():
		multiplier *= struggling_customer_multiplier
	return multiplier

func get_attractiveness_multiplier() -> float:
	return get_condition_attractiveness_multiplier() * get_service_multiplier()

func get_effective_visitor_capacity() -> int:
	if capacity <= 0:
		return capacity
	return maxi(int(round(float(capacity) * get_service_multiplier())), 1)

func get_maintenance_role_titles() -> Array[String]:
	match building_type:
		BuildingType.PARK:
			return ["Gardener", "MaintenanceWorker", "Janitor"]
		BuildingType.UNIVERSITY:
			return ["Janitor", "MaintenanceWorker", "Technician"]
		BuildingType.CITY_HALL:
			return ["Janitor", "Technician", "MaintenanceWorker"]
		BuildingType.FACTORY:
			return ["Technician", "MaintenanceWorker"]
		_:
			return ["MaintenanceWorker", "Janitor", "Technician", "Gardener"]

func get_workers_by_titles(job_titles: Array[String]) -> Array[Citizen]:
	var matches: Array[Citizen] = []
	for worker in workers:
		if worker == null or worker.job == null:
			continue
		if job_titles.has(worker.job.title):
			matches.append(worker)
	return matches

func has_maintenance_staff() -> bool:
	return not get_workers_by_titles(get_maintenance_role_titles()).is_empty()

func get_base_operating_cost_per_day() -> int:
	return maxi(base_operating_cost, 0)

func get_planned_maintenance_cost_per_day() -> int:
	if maintenance_cost_per_day <= 0:
		return 0
	if not has_maintenance_staff():
		return 0
	return maintenance_cost_per_day

func get_total_daily_obligation_estimate() -> int:
	return get_base_operating_cost_per_day() + get_payroll_due_today() + get_planned_maintenance_cost_per_day()

func get_payroll_due_today() -> int:
	var total := 0
	for worker in workers:
		if worker == null or worker.job == null:
			continue
		if worker.job.workplace != self:
			continue
		var hours_worked := maxf(worker.work_minutes_today / 60.0, 0.0)
		total += maxi(int(round(worker.job.wage_per_hour * hours_worked)), 0)
	return total

func get_public_funding_request() -> int:
	if not requires_public_funding():
		return 0
	var request: int = get_total_daily_obligation_estimate()
	if account.balance < 0:
		request += -account.balance
	return request

func apply_daily_condition_decay() -> void:
	var decay_multiplier := 1.0
	if not has_maintenance_staff():
		decay_multiplier *= 1.8
	if is_financially_closed():
		decay_multiplier *= 1.35
	if condition < repair_threshold:
		decay_multiplier *= 1.2
	condition = clampf(condition - maxf(daily_decay, 0.0) * decay_multiplier, 0.0, 100.0)

func pay_daily_maintenance(world: World) -> bool:
	if world == null or maintenance_cost_per_day <= 0:
		return true
	var maintenance_staff := get_workers_by_titles(get_maintenance_role_titles())
	if maintenance_staff.is_empty():
		return true

	var paid_total := 0
	var staff_count := maintenance_staff.size()
	for index in range(staff_count):
		var worker: Citizen = maintenance_staff[index]
		if worker == null:
			continue
		var remaining := maintenance_cost_per_day - paid_total
		var share := int(remaining / max(1, staff_count - index))
		share = maxi(share, 1 if remaining > 0 else 0)
		share = mini(share, account.balance)
		if share <= 0:
			return false
		if world.economy.pay_to_wallet(account, worker, share):
			paid_total += share
			record_maintenance_expense(share)
		else:
			return false

	if condition < repair_threshold:
		var repair_gain := maxf(2.5, daily_decay * 3.0)
		condition = clampf(condition + repair_gain, 0.0, 100.0)
	else:
		condition = clampf(condition + maxf(0.4, daily_decay * 0.75), 0.0, 100.0)
	return paid_total >= maintenance_cost_per_day

func pay_base_operating_cost(world: World) -> bool:
	var base_operating_due := get_base_operating_cost_per_day()
	if world == null or base_operating_due <= 0:
		return true
	if not requires_public_funding():
		return true
	var payable := mini(account.balance, base_operating_due)
	if payable > 0 and world.economy.pay_public_operating_cost(account, world.city_account, payable):
		record_base_operating_expense(payable)
	if payable < base_operating_due:
		record_unpaid_operating(base_operating_due - payable)
		return false
	return true

func finalize_daily_financial_state(world: World) -> void:
	if requires_public_funding():
		var had_shortfall := public_funding_shortfall_today > 0 \
			or wages_unpaid_today > 0 \
			or maintenance_unpaid_today > 0 \
			or operating_unpaid_today > 0
		underfunded_days = underfunded_days + 1 if had_shortfall else 0
		if had_shortfall and underfunded_days >= max_underfunded_days_before_closure:
			close_due_to_finance(world, "public funding collapse")
		return

	if is_economic_building():
		missed_wage_days = missed_wage_days + 1 if wages_unpaid_today > 0 else 0
		missed_tax_days = missed_tax_days + 1 if taxes_unpaid_today > 0 else 0
		missed_maintenance_days = missed_maintenance_days + 1 if maintenance_unpaid_today > 0 else 0
		negative_balance_days = negative_balance_days + 1 if account.balance < 0 else 0
		var miss_peak: int = max(
			max(missed_wage_days, missed_tax_days),
			max(missed_maintenance_days, negative_balance_days)
		)
		if miss_peak >= max_missed_payment_days_before_closure:
			close_due_to_finance(world, _get_closure_reason_for_current_shortfall())

func _get_closure_reason_for_current_shortfall() -> String:
	if wages_unpaid_today > 0 or missed_wage_days > 0:
		return "repeated unpaid wages"
	if taxes_unpaid_today > 0 or missed_tax_days > 0:
		return "repeated unpaid business tax"
	if maintenance_unpaid_today > 0 or missed_maintenance_days > 0:
		return "repeated unpaid maintenance"
	if account.balance < 0 or negative_balance_days > 0:
		return "persistent negative balance"
	return "financial collapse"

func get_daily_finance_log_summary() -> String:
	return "name=%s type=%s balance=%d income=%d wages=%d/%d taxes=%d/%d maintenance=%d/%d operating=%d/%d funding=%d/%d state=%s condition=%.1f" % [
		get_display_name(),
		get_building_type_name(),
		account.balance,
		income_today,
		wages_today,
		wages_unpaid_today,
		taxes_today,
		taxes_unpaid_today,
		maintenance_today,
		maintenance_unpaid_today,
		operating_costs_today,
		operating_unpaid_today,
		public_funding_requested_today,
		public_funding_today,
		get_financial_state_key(),
		condition
	]

func close_due_to_finance(world: World, reason: String) -> void:
	if not can_be_force_closed():
		forced_closed_reason = reason
		return
	if forced_closed_reason == reason:
		return
	forced_closed_reason = reason
	SimLogger.log("[Building %s] Closed due to finance issue: %s" % [get_display_name(), reason])
	for worker in workers.duplicate():
		if worker == null:
			continue
		fire(worker)
		if worker.has_method("notify_job_lost"):
			worker.notify_job_lost(self, reason)
		if worker.has_method("debug_log"):
			worker.debug_log("Lost job at %s because the building closed (%s)." % [get_display_name(), reason])
	if world != null:
		for visitor in visitors.duplicate():
			if visitor != null and visitor.current_location == self:
				visitor.current_location = null
	visitors.clear()

func reopen_after_funding() -> void:
	if forced_closed_reason.is_empty():
		return
	forced_closed_reason = ""
	missed_wage_days = 0
	missed_tax_days = 0
	missed_maintenance_days = 0
	negative_balance_days = 0
	underfunded_days = 0
	SimLogger.log("[Building %s] Reopened for operations after funding recovery." % get_display_name())

func get_entrance_pos() -> Vector3:
	var entrance_node := get_entrance_node()
	if entrance_node != null:
		return entrance_node.global_position
	return global_position if is_inside_tree() else position

func get_entrance_node() -> Node3D:
	if entrance != null:
		return entrance
	return get_node_or_null("Entrance") as Node3D

func get_navigation_points(world = null, lateral_lane_offset: float = 0.0, _reference_pos = null) -> Dictionary:
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
	var visit_text := ""
	if nav_points.has("visit"):
		visit_text = " visit=%s" % _format_vec3(nav_points.get("visit", get_entrance_pos()))
	var center_text := ""
	if nav_points.has("center"):
		center_text = " center=%s" % _format_vec3(nav_points.get("center", get_entrance_pos()))
	var center_name_text := ""
	if nav_points.has("center_node"):
		var center_name := str(nav_points.get("center_node", "")).strip_edges()
		if not center_name.is_empty():
			center_name_text = " center_node=%s" % center_name
	return "entrance=%s access=%s spawn=%s%s%s%s blocker_margin=%.2f clearance=(w=%.2f d=%.2f) trigger=(r=%.2f out=%.2f)" % [
		_format_vec3(nav_points.get("entrance", get_entrance_pos())),
		_format_vec3(nav_points.get("access", get_entrance_pos())),
		_format_vec3(nav_points.get("spawn", get_entrance_pos())),
		visit_text,
		center_text,
		center_name_text,
		navigation_blocker_margin,
		entrance_clearance_width,
		entrance_clearance_depth,
		entrance_trigger_radius,
		entrance_trigger_outset
	]

func get_debug_navigation_entries(world = null) -> Array[Dictionary]:
	var nav_points := get_navigation_points(world, 0.0)
	var entry := {
		"entrance": nav_points.get("entrance", get_entrance_pos()),
		"access": nav_points.get("access", get_entrance_pos()),
	}
	if nav_points.has("visit"):
		entry["visit"] = nav_points.get("visit")
	if nav_points.has("center"):
		entry["center"] = nav_points.get("center")
	return [entry]

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
		if current.name.begins_with("EntranceTrigger"):
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
