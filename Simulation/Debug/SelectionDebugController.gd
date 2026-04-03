extends RefCounted
class_name SelectionDebugController

var owner_node: Node = null

var _citizen_path_debug: MeshInstance3D = null
var _citizen_path_debug_mesh: ImmediateMesh = null
var _citizen_path_line_material: StandardMaterial3D = null
var _citizen_path_active_material: StandardMaterial3D = null
var _citizen_path_start_material: StandardMaterial3D = null
var _citizen_path_waypoint_material: StandardMaterial3D = null
var _citizen_path_end_material: StandardMaterial3D = null
var _citizen_path_failed_material: StandardMaterial3D = null

var _building_nav_debug: MeshInstance3D = null
var _building_nav_debug_mesh: ImmediateMesh = null
var _building_nav_link_material: StandardMaterial3D = null
var _building_nav_source_entrance_material: StandardMaterial3D = null
var _building_nav_source_access_material: StandardMaterial3D = null
var _building_nav_source_spawn_material: StandardMaterial3D = null
var _building_nav_extra_entrance_material: StandardMaterial3D = null
var _building_nav_extra_access_material: StandardMaterial3D = null
var _building_nav_visit_material: StandardMaterial3D = null
var _building_nav_target_entrance_material: StandardMaterial3D = null
var _building_nav_target_access_material: StandardMaterial3D = null

func setup(owner_ref: Node) -> void:
	owner_node = owner_ref
	_setup_citizen_path_debug()
	_setup_building_nav_debug()

func update(selected_citizen: Citizen, selected_building: Building, world: World) -> void:
	_update_selected_citizen_path_debug(selected_citizen)
	_update_selected_building_nav_debug(selected_citizen, selected_building, world)

func clear_citizen_path() -> void:
	_clear_selected_citizen_path_debug()

func clear_all() -> void:
	_clear_selected_citizen_path_debug()
	_clear_selected_building_nav_debug()

func _setup_citizen_path_debug() -> void:
	if owner_node == null:
		return
	_citizen_path_debug = MeshInstance3D.new()
	_citizen_path_debug.name = "SelectedCitizenPathDebug"
	_citizen_path_debug.top_level = true
	_citizen_path_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_citizen_path_debug.visible = false

	_citizen_path_debug_mesh = ImmediateMesh.new()
	_citizen_path_debug.mesh = _citizen_path_debug_mesh

	_citizen_path_line_material = _create_path_debug_material(Color(0.10, 0.95, 0.35, 1.0))
	_citizen_path_active_material = _create_path_debug_material(Color(0.10, 0.85, 1.0, 1.0))
	_citizen_path_start_material = _create_path_debug_material(Color(0.20, 1.0, 0.20, 1.0))
	_citizen_path_waypoint_material = _create_path_debug_material(Color(1.0, 0.82, 0.18, 1.0))
	_citizen_path_end_material = _create_path_debug_material(Color(1.0, 0.22, 0.22, 1.0))
	_citizen_path_failed_material = _create_path_debug_material(Color(1.0, 0.35, 0.10, 1.0))

	owner_node.add_child(_citizen_path_debug)

func _setup_building_nav_debug() -> void:
	if owner_node == null:
		return
	_building_nav_debug = MeshInstance3D.new()
	_building_nav_debug.name = "SelectedBuildingNavDebug"
	_building_nav_debug.top_level = true
	_building_nav_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_building_nav_debug.visible = false

	_building_nav_debug_mesh = ImmediateMesh.new()
	_building_nav_debug.mesh = _building_nav_debug_mesh

	_building_nav_link_material = _create_path_debug_material(Color(1.0, 1.0, 1.0, 0.95))
	_building_nav_source_entrance_material = _create_path_debug_material(Color(1.0, 0.30, 0.20, 1.0))
	_building_nav_source_access_material = _create_path_debug_material(Color(0.10, 0.85, 1.0, 1.0))
	_building_nav_source_spawn_material = _create_path_debug_material(Color(1.0, 0.88, 0.15, 1.0))
	_building_nav_extra_entrance_material = _create_path_debug_material(Color(1.0, 0.55, 0.15, 1.0))
	_building_nav_extra_access_material = _create_path_debug_material(Color(0.18, 1.0, 0.92, 1.0))
	_building_nav_visit_material = _create_path_debug_material(Color(0.96, 0.96, 0.96, 1.0))
	_building_nav_target_entrance_material = _create_path_debug_material(Color(1.0, 0.25, 0.75, 1.0))
	_building_nav_target_access_material = _create_path_debug_material(Color(0.20, 1.0, 0.35, 1.0))

	owner_node.add_child(_building_nav_debug)

func _create_path_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.no_depth_test = true
	return material

func _update_selected_citizen_path_debug(selected_citizen: Citizen) -> void:
	if _citizen_path_debug == null or _citizen_path_debug_mesh == null:
		return

	if selected_citizen == null or not is_instance_valid(selected_citizen):
		_clear_selected_citizen_path_debug()
		return

	if not selected_citizen.has_debug_travel_route():
		_clear_selected_citizen_path_debug()
		return

	var route := selected_citizen.get_debug_travel_route_points()
	if route.size() < 2:
		_clear_selected_citizen_path_debug()
		return

	var is_active_route := selected_citizen.is_debug_travelling()
	var route_failed := selected_citizen.did_debug_last_travel_fail()
	var current_target := selected_citizen.get_debug_travel_current_target()
	var current_target_idx := selected_citizen.get_debug_travel_route_index()
	var route_material := _citizen_path_failed_material if route_failed else _citizen_path_line_material

	_citizen_path_debug.visible = true
	_citizen_path_debug.global_transform = Transform3D.IDENTITY
	_citizen_path_debug_mesh.clear_surfaces()

	var path_offset := Vector3.UP * 0.18
	_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, route_material)
	for point in route:
		_citizen_path_debug_mesh.surface_add_vertex((point as Vector3) + path_offset)
	_citizen_path_debug_mesh.surface_end()

	if is_active_route and current_target != Vector3.ZERO:
		_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _citizen_path_active_material)
		_citizen_path_debug_mesh.surface_add_vertex(selected_citizen.global_position + path_offset)
		_citizen_path_debug_mesh.surface_add_vertex(current_target + path_offset)
		_add_path_debug_marker(current_target + path_offset, 0.18, 0.42)
		_citizen_path_debug_mesh.surface_end()

	_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _citizen_path_start_material)
	_add_path_debug_marker(route[0] + path_offset, 0.18, 0.42)
	_citizen_path_debug_mesh.surface_end()

	if route.size() > 2:
		_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _citizen_path_waypoint_material)
		for i in range(1, route.size() - 1):
			var point: Vector3 = route[i]
			if current_target_idx == i and current_target.distance_to(point) < 0.05:
				continue
			_add_path_debug_marker(point + path_offset, 0.12, 0.28)
		_citizen_path_debug_mesh.surface_end()

	_citizen_path_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _citizen_path_end_material)
	_add_path_debug_marker(route[route.size() - 1] + path_offset, 0.20, 0.48)
	_citizen_path_debug_mesh.surface_end()

func _add_path_debug_marker(center: Vector3, radius: float, height: float) -> void:
	_add_debug_marker(_citizen_path_debug_mesh, center, radius, height)

func _add_debug_marker(mesh: ImmediateMesh, center: Vector3, radius: float, height: float) -> void:
	if mesh == null:
		return
	mesh.surface_add_vertex(center)
	mesh.surface_add_vertex(center + Vector3.UP * height)
	mesh.surface_add_vertex(center + Vector3(-radius, 0.0, 0.0))
	mesh.surface_add_vertex(center + Vector3(radius, 0.0, 0.0))
	mesh.surface_add_vertex(center + Vector3(0.0, 0.0, -radius))
	mesh.surface_add_vertex(center + Vector3(0.0, 0.0, radius))
	mesh.surface_add_vertex(center + Vector3(-radius * 0.75, 0.0, -radius * 0.75))
	mesh.surface_add_vertex(center + Vector3(radius * 0.75, 0.0, radius * 0.75))
	mesh.surface_add_vertex(center + Vector3(-radius * 0.75, 0.0, radius * 0.75))
	mesh.surface_add_vertex(center + Vector3(radius * 0.75, 0.0, -radius * 0.75))

func _clear_selected_citizen_path_debug() -> void:
	if _citizen_path_debug_mesh != null:
		_citizen_path_debug_mesh.clear_surfaces()
	if _citizen_path_debug != null:
		_citizen_path_debug.visible = false

func _update_selected_building_nav_debug(selected_citizen: Citizen, selected_building: Building, world: World) -> void:
	if _building_nav_debug == null or _building_nav_debug_mesh == null:
		return

	_clear_selected_building_nav_debug()

	var has_debug := false
	if selected_citizen != null and is_instance_valid(selected_citizen):
		has_debug = _draw_selected_citizen_nav_debug(selected_citizen, world)
	elif selected_building != null and is_instance_valid(selected_building):
		has_debug = _draw_selected_building_nav_debug(selected_building, world)

	if has_debug:
		_building_nav_debug.visible = true
		_building_nav_debug.global_transform = Transform3D.IDENTITY

func _clear_selected_building_nav_debug() -> void:
	if _building_nav_debug_mesh != null:
		_building_nav_debug_mesh.clear_surfaces()
	if _building_nav_debug != null:
		_building_nav_debug.visible = false

func _draw_selected_citizen_nav_debug(citizen: Citizen, world: World) -> bool:
	var has_debug := false
	var source_building: Building = citizen.get_debug_source_building() if citizen.has_method("get_debug_source_building") else citizen.current_location
	if source_building != null:
		var source_entrance := source_building.get_entrance_pos()
		var source_access := citizen.get_debug_access_pos(source_building, world) if citizen.has_method("get_debug_access_pos") else source_entrance
		var source_spawn := citizen.get_debug_exit_spawn_pos(source_building, world) if citizen.has_method("get_debug_exit_spawn_pos") else source_access
		_draw_building_nav_triplet(
			source_entrance,
			source_access,
			source_spawn,
			_building_nav_source_entrance_material,
			_building_nav_source_access_material,
			_building_nav_source_spawn_material,
			Vector3.UP * 0.10
		)
		has_debug = true

	var target_building: Building = citizen.get_debug_travel_target_building() if citizen.has_method("get_debug_travel_target_building") else null
	if target_building != null:
		var target_nav_points: Dictionary = citizen.get_navigation_points_for_building(target_building, world) if citizen.has_method("get_navigation_points_for_building") else {}
		var target_entrance: Vector3 = target_nav_points.get("entrance", target_building.get_entrance_pos())
		var fallback_target_access: Vector3 = citizen.get_debug_access_pos(target_building, world) if citizen.has_method("get_debug_access_pos") else target_entrance
		var target_access: Vector3 = target_nav_points.get("access", fallback_target_access)
		_draw_building_nav_pair(
			target_entrance,
			target_access,
			_building_nav_target_entrance_material,
			_building_nav_target_access_material,
			Vector3.UP * 0.28
		)
		if target_nav_points.has("visit"):
			_draw_building_nav_pair(
				target_access,
				target_nav_points.get("visit", target_access),
				_building_nav_target_access_material,
				_building_nav_visit_material,
				Vector3.UP * 0.44,
				0.18,
				0.46
			)
		has_debug = true

	return has_debug

func _draw_selected_building_nav_debug(building: Building, world: World) -> bool:
	if building == null:
		return false

	var nav_points: Dictionary = building.get_navigation_points(world, 0.0) if building.has_method("get_navigation_points") else {}
	var entrance: Vector3 = nav_points.get("entrance", building.get_entrance_pos())
	var access: Vector3 = nav_points.get("access", entrance)
	var preview_spawn: Vector3 = nav_points.get("spawn", _compute_building_spawn_preview(entrance, access))
	var visit: Variant = nav_points.get("visit", null)
	_draw_building_nav_triplet(
		entrance,
		access,
		preview_spawn,
		_building_nav_source_entrance_material,
		_building_nav_source_access_material,
		_building_nav_source_spawn_material,
		Vector3.UP * 0.10
	)
	if visit is Vector3:
		_draw_building_nav_pair(
			access,
			visit,
			_building_nav_source_access_material,
			_building_nav_visit_material,
			Vector3.UP * 0.34,
			0.18,
			0.48
		)

	if building.has_method("get_debug_navigation_entries"):
		var extra_entries: Array = building.get_debug_navigation_entries(world)
		for idx in range(extra_entries.size()):
			var entry := extra_entries[idx] as Dictionary
			var extra_entrance: Vector3 = entry.get("entrance", entrance)
			var extra_access: Vector3 = entry.get("access", extra_entrance)
			if idx == 0:
				continue
			_draw_building_nav_pair(
				extra_entrance,
				extra_access,
				_building_nav_extra_entrance_material,
				_building_nav_extra_access_material,
				Vector3.UP * 0.22,
				0.30,
				0.95
			)
	return true

func _compute_building_spawn_preview(entrance_pos: Vector3, access_pos: Vector3) -> Vector3:
	var outward := access_pos - entrance_pos
	outward.y = 0.0
	if outward.length_squared() <= 0.0001:
		outward = Vector3.FORWARD
	else:
		outward = outward.normalized()

	var spawn_base := entrance_pos.lerp(access_pos, 0.55)
	var spawn_pos := spawn_base + outward * 0.02
	spawn_pos.y = spawn_base.y
	return spawn_pos

func _draw_building_nav_triplet(
	entrance: Vector3,
	access: Vector3,
	spawn: Vector3,
	entrance_material: StandardMaterial3D,
	access_material: StandardMaterial3D,
	spawn_material: StandardMaterial3D,
	offset: Vector3
) -> void:
	_building_nav_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _building_nav_link_material)
	_building_nav_debug_mesh.surface_add_vertex(entrance + offset)
	_building_nav_debug_mesh.surface_add_vertex(access + offset)
	_building_nav_debug_mesh.surface_add_vertex(entrance + offset)
	_building_nav_debug_mesh.surface_add_vertex(spawn + offset)
	_building_nav_debug_mesh.surface_add_vertex(access + offset)
	_building_nav_debug_mesh.surface_add_vertex(spawn + offset)
	_building_nav_debug_mesh.surface_end()

	_draw_building_nav_marker(entrance + offset, entrance_material, 0.18, 0.42)
	_draw_building_nav_marker(access + offset, access_material, 0.18, 0.42)
	_draw_building_nav_marker(spawn + offset, spawn_material, 0.22, 0.52)

func _draw_building_nav_pair(
	entrance: Vector3,
	access: Vector3,
	entrance_material: StandardMaterial3D,
	access_material: StandardMaterial3D,
	offset: Vector3,
	radius: float = 0.16,
	height: float = 0.38
) -> void:
	_building_nav_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _building_nav_link_material)
	_building_nav_debug_mesh.surface_add_vertex(entrance + offset)
	_building_nav_debug_mesh.surface_add_vertex(access + offset)
	_building_nav_debug_mesh.surface_end()

	_draw_building_nav_marker(entrance + offset, entrance_material, radius, height)
	_draw_building_nav_marker(access + offset, access_material, radius, height)

func _draw_building_nav_marker(center: Vector3, material: StandardMaterial3D, radius: float, height: float) -> void:
	_building_nav_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	_add_debug_marker(_building_nav_debug_mesh, center, radius, height)
	_building_nav_debug_mesh.surface_end()
