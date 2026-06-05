extends Control
class_name WorldMapCanvas

signal destination_selected(world_position: Vector3)
signal zoom_changed(zoom_level: float)

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")

const MAP_PADDING := 12.0
const PLAYER_MARKER_RADIUS := 5.5
const VEHICLE_MARKER_RADIUS := 4.5
const BUILDING_MARKER_RADIUS := 2.8
const DESTINATION_MARKER_RADIUS := 6.0
const MIN_ZOOM := 1.0
const DEFAULT_ZOOM := 3.3
const MAX_ZOOM := 8.0
const ZOOM_STEP := 1.35

var world: World = null
var target_node: Node3D = null
var selection_enabled: bool = true
var zoom_level: float = DEFAULT_ZOOM
var selected_position: Vector3 = Vector3.INF
var route_points: PackedVector3Array = PackedVector3Array()
var extra_markers: Array = []
var _manual_center: Vector3 = Vector3.INF
var _is_panning: bool = false
var _pan_anchor_world: Vector3 = Vector3.INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(356, 250)


func set_world(world_ref: World) -> void:
	world = world_ref
	queue_redraw()


func set_target_node(target_ref: Node3D) -> void:
	target_node = target_ref
	queue_redraw()


func set_selection_enabled(enabled: bool) -> void:
	selection_enabled = enabled
	queue_redraw()


func set_selected_position(world_position: Vector3) -> void:
	selected_position = world_position
	queue_redraw()


func clear_selected_position() -> void:
	selected_position = Vector3.INF
	queue_redraw()


func set_route_points(points: PackedVector3Array) -> void:
	route_points = points
	queue_redraw()


func set_extra_markers(markers: Array) -> void:
	extra_markers = markers.duplicate(true)
	queue_redraw()


func get_zoom_level() -> float:
	return zoom_level


func get_default_zoom_level() -> float:
	return DEFAULT_ZOOM


func set_zoom_level(value: float, center_world: Vector3 = Vector3.INF) -> void:
	var next_zoom := clampf(value, MIN_ZOOM, MAX_ZOOM)
	if _is_finite_vector(center_world):
		_manual_center = _clamp_view_center(center_world, next_zoom)
	zoom_level = next_zoom
	if zoom_level <= MIN_ZOOM + 0.001:
		zoom_level = MIN_ZOOM
		_manual_center = Vector3.INF
	zoom_changed.emit(zoom_level)
	queue_redraw()


func zoom_in(center_world: Vector3 = Vector3.INF) -> void:
	set_zoom_level(zoom_level * ZOOM_STEP, center_world)


func zoom_out(center_world: Vector3 = Vector3.INF) -> void:
	set_zoom_level(zoom_level / ZOOM_STEP, center_world)


func reset_zoom() -> void:
	_is_panning = false
	_pan_anchor_world = Vector3.INF
	_manual_center = Vector3.INF
	set_zoom_level(DEFAULT_ZOOM)


func reset_view() -> void:
	reset_zoom()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		var local_pos: Vector2 = mouse_event.position
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and not mouse_event.pressed:
			_is_panning = false
			_pan_anchor_world = Vector3.INF
			accept_event()
			return
		if not _map_rect().has_point(local_pos):
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_is_panning = true
			_pan_anchor_world = _map_to_world(local_pos)
			accept_event()
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in(_map_to_world(local_pos))
			accept_event()
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out(_map_to_world(local_pos))
			accept_event()
			return
		if not selection_enabled:
			return
		if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
			return
		destination_selected.emit(_map_to_world(local_pos))
		accept_event()
		return
	if event is InputEventMouseMotion and _is_panning:
		var motion_event := event as InputEventMouseMotion
		if not _is_finite_vector(_pan_anchor_world):
			_pan_anchor_world = _map_to_world(motion_event.position)
			accept_event()
			return
		var current_world := _map_to_world(motion_event.position)
		var center := _current_view_center()
		center += _pan_anchor_world - current_world
		_manual_center = _clamp_view_center(center, zoom_level)
		queue_redraw()
		accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, UiThemeScript.BG_800)
	_draw_grid()
	_draw_route()
	_draw_buildings()
	_draw_vehicles()
	_draw_target_marker()
	_draw_extra_markers()
	_draw_selected_destination()
	_draw_border()


func _draw_grid() -> void:
	var rect := _map_rect()
	var grid_color := Color(UiThemeScript.BORDER.r, UiThemeScript.BORDER.g, UiThemeScript.BORDER.b, 0.55)
	for i in range(1, 4):
		var x := rect.position.x + rect.size.x * float(i) / 4.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.position.y + rect.size.y), grid_color, 1.0)
		var y := rect.position.y + rect.size.y * float(i) / 4.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x + rect.size.x, y), grid_color, 1.0)


func _draw_route() -> void:
	if route_points.size() < 2:
		return
	var color := Color(UiThemeScript.ACCENT.r, UiThemeScript.ACCENT.g, UiThemeScript.ACCENT.b, 0.85)
	for i in range(route_points.size() - 1):
		var from_pos := route_points[i]
		var to_pos := route_points[i + 1]
		if not _is_world_position_in_view(from_pos) and not _is_world_position_in_view(to_pos):
			continue
		draw_line(_world_to_map(from_pos), _world_to_map(to_pos), color, 2.5)


func _draw_buildings() -> void:
	if world == null:
		return
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		if not _is_world_position_in_view(building.global_position):
			continue
		draw_circle(_world_to_map(building.global_position), BUILDING_MARKER_RADIUS, _building_color(building))


func _draw_vehicles() -> void:
	if world == null:
		return
	for vehicle in world.vehicles:
		if vehicle == null or not is_instance_valid(vehicle):
			continue
		if not _is_world_position_in_view(vehicle.global_position):
			continue
		var vehicle_color := UiThemeScript.WARNING if vehicle.is_in_group("taxi_vehicle") else UiThemeScript.TEXT_SECONDARY
		draw_circle(_world_to_map(vehicle.global_position), VEHICLE_MARKER_RADIUS, vehicle_color)


func _draw_target_marker() -> void:
	if target_node == null or not is_instance_valid(target_node):
		return
	if not _is_world_position_in_view(target_node.global_position):
		return
	var pos := _world_to_map(target_node.global_position)
	draw_circle(pos, PLAYER_MARKER_RADIUS + 2.0, Color(0.0, 0.0, 0.0, 0.75))
	draw_circle(pos, PLAYER_MARKER_RADIUS, UiThemeScript.SUCCESS)


func _draw_extra_markers() -> void:
	for marker in extra_markers:
		var raw_position: Variant = marker.get("position", null)
		if raw_position is not Vector3:
			continue
		if not _is_world_position_in_view(raw_position as Vector3):
			continue
		var color: Color = marker.get("color", UiThemeScript.ACCENT) as Color
		var radius := float(marker.get("radius", 4.0))
		draw_circle(_world_to_map(raw_position as Vector3), radius, color)


func _draw_selected_destination() -> void:
	if not _is_finite_vector(selected_position):
		return
	if not _is_world_position_in_view(selected_position):
		return
	var pos := _world_to_map(selected_position)
	draw_circle(pos, DESTINATION_MARKER_RADIUS + 2.0, Color(0.0, 0.0, 0.0, 0.7))
	draw_line(pos + Vector2(-DESTINATION_MARKER_RADIUS, 0.0), pos + Vector2(DESTINATION_MARKER_RADIUS, 0.0), UiThemeScript.WARNING, 2.0)
	draw_line(pos + Vector2(0.0, -DESTINATION_MARKER_RADIUS), pos + Vector2(0.0, DESTINATION_MARKER_RADIUS), UiThemeScript.WARNING, 2.0)


func _draw_border() -> void:
	var rect := _map_rect()
	draw_rect(rect, UiThemeScript.BORDER, false, 1.0)
	if selection_enabled:
		draw_rect(rect.grow(-1.0), Color(UiThemeScript.ACCENT.r, UiThemeScript.ACCENT.g, UiThemeScript.ACCENT.b, 0.45), false, 1.0)


func _building_color(building: Building) -> Color:
	if building == null:
		return UiThemeScript.TEXT_MUTED
	var service := building.get_service_type() if building.has_method("get_service_type") else ""
	match service:
		"housing":
			return Color8(126, 187, 255)
		"food":
			return Color8(255, 194, 98)
		"shopping":
			return Color8(186, 135, 255)
		"healthcare":
			return Color8(239, 102, 102)
		"education":
			return Color8(107, 210, 160)
		"fun":
			return Color8(255, 135, 182)
		"production_goods":
			return Color8(178, 188, 205)
		"fuel":
			return Color8(250, 152, 76)
		"governance":
			return Color8(126, 221, 235)
		_:
			return UiThemeScript.TEXT_MUTED


func _map_rect() -> Rect2:
	var available := size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
	available.x = maxf(available.x, 8.0)
	available.y = maxf(available.y, 8.0)
	var bounds := _view_bounds()
	var world_width := maxf(bounds.size.x, 1.0)
	var world_depth := maxf(bounds.size.z, 1.0)
	var scale := minf(available.x / world_width, available.y / world_depth)
	var rect_size := Vector2(world_width * scale, world_depth * scale)
	return Rect2((size - rect_size) * 0.5, rect_size)


func _world_to_map(world_position: Vector3) -> Vector2:
	var bounds := _view_bounds()
	var rect := _map_rect()
	var world_width := maxf(bounds.size.x, 1.0)
	var world_depth := maxf(bounds.size.z, 1.0)
	var x_ratio := clampf((world_position.x - bounds.position.x) / world_width, 0.0, 1.0)
	var z_ratio := clampf((world_position.z - bounds.position.z) / world_depth, 0.0, 1.0)
	return Vector2(
		rect.position.x + (1.0 - x_ratio) * rect.size.x,
		rect.position.y + (1.0 - z_ratio) * rect.size.y
	)


func _map_to_world(map_position: Vector2) -> Vector3:
	var bounds := _view_bounds()
	var rect := _map_rect()
	var x_ratio := 1.0 - clampf((map_position.x - rect.position.x) / maxf(rect.size.x, 1.0), 0.0, 1.0)
	var z_ratio := 1.0 - clampf((map_position.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
	var ground_y := world.get_ground_fallback_y() if world != null and world.has_method("get_ground_fallback_y") else bounds.position.y
	return Vector3(
		bounds.position.x + bounds.size.x * x_ratio,
		ground_y,
		bounds.position.z + bounds.size.z * z_ratio
	)


func _world_bounds() -> AABB:
	if world != null and world.has_method("get_world_bounds"):
		var bounds: AABB = world.get_world_bounds()
		if bounds.size.x > 0.001 and bounds.size.z > 0.001:
			return bounds
	if target_node != null and is_instance_valid(target_node):
		return AABB(target_node.global_position - Vector3(40.0, 1.0, 40.0), Vector3(80.0, 2.0, 80.0))
	return AABB(Vector3(-40.0, -1.0, -40.0), Vector3(80.0, 2.0, 80.0))


func _view_bounds() -> AABB:
	var bounds := _world_bounds()
	if zoom_level <= MIN_ZOOM + 0.001:
		return bounds
	var view_width := maxf(bounds.size.x / zoom_level, 1.0)
	var view_depth := maxf(bounds.size.z / zoom_level, 1.0)
	var center := _current_view_center()
	return AABB(
		Vector3(center.x - view_width * 0.5, bounds.position.y, center.z - view_depth * 0.5),
		Vector3(view_width, bounds.size.y, view_depth)
	)


func _current_view_center() -> Vector3:
	var bounds := _world_bounds()
	var center := _manual_center if _is_finite_vector(_manual_center) else _default_view_center(bounds)
	center = _clamp_view_center(center, zoom_level)
	return center


func _default_view_center(bounds: AABB) -> Vector3:
	if target_node != null and is_instance_valid(target_node):
		return target_node.global_position
	if _is_finite_vector(selected_position):
		return selected_position
	return bounds.position + bounds.size * 0.5


func _clamp_view_center(center: Vector3, zoom: float) -> Vector3:
	var bounds := _world_bounds()
	var view_width := maxf(bounds.size.x / maxf(zoom, MIN_ZOOM), 1.0)
	var view_depth := maxf(bounds.size.z / maxf(zoom, MIN_ZOOM), 1.0)
	var min_x := bounds.position.x + view_width * 0.5
	var max_x := bounds.position.x + bounds.size.x - view_width * 0.5
	var min_z := bounds.position.z + view_depth * 0.5
	var max_z := bounds.position.z + bounds.size.z - view_depth * 0.5
	if min_x > max_x:
		center.x = bounds.position.x + bounds.size.x * 0.5
	else:
		center.x = clampf(center.x, min_x, max_x)
	if min_z > max_z:
		center.z = bounds.position.z + bounds.size.z * 0.5
	else:
		center.z = clampf(center.z, min_z, max_z)
	center.y = bounds.position.y + bounds.size.y * 0.5
	return center


func _is_world_position_in_view(world_position: Vector3) -> bool:
	var bounds := _view_bounds()
	return world_position.x >= bounds.position.x \
			and world_position.x <= bounds.position.x + bounds.size.x \
			and world_position.z >= bounds.position.z \
			and world_position.z <= bounds.position.z + bounds.size.z


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
