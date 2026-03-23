extends CharacterBody3D
class_name Citizen

const CitizenAgentScript = preload("res://Simulation/Citizens/CitizenAgent.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

# Emittiert wenn der Spieler auf diesen Citizen klickt
signal clicked

@export var citizen_name: String = "Alex"
@export var home_path: NodePath
@export var restaurant_path: NodePath
@export var supermarket_path: NodePath
@export var shop_path: NodePath
@export var cinema_path: NodePath
@export var park_path: NodePath
@export var job: Job
@export var debug_panel: DebugPanel

var home: ResidentialBuilding
var favorite_restaurant: Restaurant
var favorite_supermarket: Supermarket
var favorite_shop: Shop
var favorite_cinema: Cinema
var favorite_park: Building

var needs := Needs.new()
var wallet := Account.new()
var home_food_stock: int = 2
var education_level: int = 0

var current_location: Building = null
var current_action: Action = null

var _world_ref: World = null
var _agent = CitizenAgentScript.new()
var _last_job_requirement_notice_level: int = -1
var _last_job_requirement_notice_title: String = ""
var _last_workplace_full_notice_day: int = -1
var _debug_once_day: int = -1
var _debug_once_keys: Dictionary = {}

# --- Movement / Navigation ---
@export var move_speed_min: float = 1.6
@export var move_speed_max: float = 2.4
@export var move_acceleration: float = 5.5
@export var move_deceleration: float = 7.0
@export var turn_speed: float = 8.0
@export var waypoint_reach_distance: float = 0.35
@export var arrival_distance: float = 0.65
@export var final_arrival_distance: float = 0.18
@export var ground_probe_up: float = 4.0
@export var ground_probe_down: float = 12.0
@export var max_ground_step_up: float = 0.85
@export var max_ground_probe_skips: int = 8
@export var repath_interval_sec: float = 0.6
@export var gravity_strength: float = 28.0
@export var max_fall_speed: float = 35.0
@export var ground_snap_rate: float = 18.0
@export var obstacle_sensor_height: float = 0.9
@export var obstacle_probe_length: float = 0.95
@export var obstacle_side_probe_length: float = 0.9
@export var obstacle_side_angle_deg: float = 35.0
@export var obstacle_turn_weight: float = 1.1
@export var obstacle_side_bias: float = 0.35
@export var obstacle_stuck_timeout: float = 0.7
@export var obstacle_stuck_distance: float = 0.02
@export var obstacle_repath_timeout: float = 1.6
@export var obstacle_slide_hold_sec: float = 0.4
@export var entrance_contact_distance: float = 1.05
@export var entrance_contact_alignment: float = 0.45

var _nav_agent: NavigationAgent3D = null
var _is_travelling: bool = false
var _travel_target: Vector3 = Vector3.ZERO
var _travel_target_building: Building = null
var _travel_route: PackedVector3Array = PackedVector3Array()
var _travel_route_index: int = -1
var _arrived_via_entrance_contact: bool = false
var _repath_time_left: float = 0.0
var _walk_speed: float = 2.0
var _current_speed: float = 0.0
var _vertical_speed: float = 0.0
var _ground_fallback_y: float = 0.0
var _debug_last_travel_route: PackedVector3Array = PackedVector3Array()
var _debug_last_travel_failed: bool = false
var _obstacle_sensor_pivot: Node3D = null
var _obstacle_ray_forward: RayCast3D = null
var _obstacle_ray_left: RayCast3D = null
var _obstacle_ray_right: RayCast3D = null
var _body_collision_shape: CollisionShape3D = null
var _click_area: Area3D = null
var _click_area_shape: CollisionShape3D = null
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0
var _inside_building: Building = null
var _stuck_timer: float = 0.0
var _last_move_position: Vector3 = Vector3.ZERO
var _trace_last_decision_reason: String = "idle"
var _trace_last_desired_dir: Vector3 = Vector3.ZERO
var _trace_last_move_dir: Vector3 = Vector3.ZERO
var _trace_last_forward_hit: String = "clear"
var _trace_last_left_hit: String = "clear"
var _trace_last_right_hit: String = "clear"
var _stuck_slide_hold_dir: Vector3 = Vector3.ZERO
var _stuck_slide_hold_left: float = 0.0
# --- Variation / Personality ---
@export var schedule_offset_min: int = -25
@export var schedule_offset_max: int = 25
var schedule_offset: int = 0

@export var decision_cooldown_range_min: int = 5
@export var decision_cooldown_range_max: int = 20
var decision_cooldown_left: int = 0

@export var hunger_threshold_base: float = 60.0
@export var hunger_threshold_jitter: float = 12.0
var hunger_threshold: float = 60.0

@export var low_energy_threshold_base: float = 35.0
@export var low_energy_threshold_jitter: float = 10.0
var low_energy_threshold: float = 35.0

@export var work_motivation_base: float = 1.0
@export var work_motivation_jitter: float = 0.4
var work_motivation: float = 1.0

@export var park_interest_base: float = 0.35
@export var park_interest_jitter: float = 0.20
var park_interest: float = 0.35

@export var fun_target_base: float = 65.0
@export var fun_target_jitter: float = 15.0
var fun_target: float = 65.0

# --- Work tracking ---
var work_minutes_today: int = 0
var _work_day_key: int = -1

# --- Selection highlight ---
var _mesh_instance: MeshInstance3D = null
var _original_material: Material = null
var _highlight_material: StandardMaterial3D = null

func _ready() -> void:
	wallet.owner_name = citizen_name
	wallet.balance = 200

	schedule_offset = randi_range(schedule_offset_min, schedule_offset_max)
	hunger_threshold = hunger_threshold_base + randf_range(-hunger_threshold_jitter, hunger_threshold_jitter)
	low_energy_threshold = low_energy_threshold_base + randf_range(-low_energy_threshold_jitter, low_energy_threshold_jitter)
	work_motivation = work_motivation_base + randf_range(-work_motivation_jitter, work_motivation_jitter)
	park_interest = clamp(park_interest_base + randf_range(-park_interest_jitter, park_interest_jitter), 0.0, 0.9)
	_walk_speed = randf_range(move_speed_min, move_speed_max)

	decision_cooldown_left = randi_range(0, 10)

	_setup_clickable()
	_setup_highlight()
	_setup_obstacle_sensors()
	_body_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	_agent.setup(self)
	_last_move_position = global_position
	call_deferred("_auto_resolve_refs")

func _physics_process(delta: float) -> void:
	_agent.physics_step(self, delta, _world_ref)

# Click detection via Area3D
func _setup_clickable() -> void:
	var area := get_node_or_null("ClickArea") as Area3D
	if area == null:
		area = Area3D.new()
		area.name = "ClickArea"
		add_child(area)
	area.input_ray_pickable = true

	var col := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		area.add_child(col)
	var shape := col.shape as CapsuleShape3D
	if shape == null:
		shape = CapsuleShape3D.new()
		col.shape = shape
	shape.radius = 0.45
	shape.height = 2.1
	col.position = Vector3(0, 1.05, 0)  # Mitte der Kapsel-Figur

	_click_area = area
	_click_area_shape = col

	area.input_event.connect(_on_area_input_event)


func _on_area_input_event(_camera: Camera3D, event: InputEvent,
		_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT \
		and event.pressed:
		clicked.emit()
		get_viewport().set_input_as_handled()


# Highlight selection material
func _setup_highlight() -> void:
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance == null:
		return
	_original_material = _mesh_instance.get_surface_override_material(0)

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(1.0, 0.85, 0.1)  # Gelb
	_highlight_material.emission_enabled = true
	_highlight_material.emission = Color(0.6, 0.4, 0.0)

func _setup_obstacle_sensors() -> void:
	_obstacle_sensor_pivot = get_node_or_null("ObstacleSensorPivot") as Node3D
	_obstacle_ray_forward = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastForward") as RayCast3D
	_obstacle_ray_left = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastLeft") as RayCast3D
	_obstacle_ray_right = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastRight") as RayCast3D

	if _obstacle_sensor_pivot != null:
		_obstacle_sensor_pivot.position = Vector3(0.0, obstacle_sensor_height, 0.0)

	var side_angle := deg_to_rad(obstacle_side_angle_deg)
	var side_x := sin(side_angle) * obstacle_side_probe_length
	var side_z := -cos(side_angle) * obstacle_side_probe_length

	if _obstacle_ray_forward != null:
		_obstacle_ray_forward.target_position = Vector3(0.0, 0.0, -obstacle_probe_length)
		_obstacle_ray_forward.collision_mask = 9
		_obstacle_ray_forward.enabled = true
	if _obstacle_ray_left != null:
		_obstacle_ray_left.target_position = Vector3(-side_x, 0.0, side_z)
		_obstacle_ray_left.collision_mask = 9
		_obstacle_ray_left.enabled = true
	if _obstacle_ray_right != null:
		_obstacle_ray_right.target_position = Vector3(side_x, 0.0, side_z)
		_obstacle_ray_right.collision_mask = 9
		_obstacle_ray_right.enabled = true

func _setup_navigation() -> void:
	_nav_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _nav_agent == null:
		_nav_agent = NavigationAgent3D.new()
		_nav_agent.name = "NavigationAgent3D"
		add_child(_nav_agent)

	_nav_agent.path_desired_distance = waypoint_reach_distance
	_nav_agent.target_desired_distance = arrival_distance
	_nav_agent.path_max_distance = 2.0
	_nav_agent.radius = 0.35
	_nav_agent.height = 1.8
	_nav_agent.avoidance_enabled = false

func _probe_ground_hit(pos: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}

	var from := pos + Vector3.UP * ground_probe_up
	var to := pos + Vector3.DOWN * ground_probe_down
	var exclude: Array[RID] = [get_rid()]
	var attempts := maxi(max_ground_probe_skips, 1)

	for _attempt in range(attempts):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collide_with_areas = false
		query.exclude = exclude

		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		var hit_pos: Vector3 = hit.get("position", pos)
		if hit_pos.y <= pos.y + max_ground_step_up:
			return hit

		if not hit.has("rid"):
			return {}
		exclude.append(hit["rid"])

	return {}

func _project_to_ground(pos: Vector3) -> Vector3:
	var hit := _probe_ground_hit(pos)
	if hit.is_empty():
		var fallback := pos
		fallback.y = _ground_fallback_y
		return fallback

	var grounded := pos
	grounded.y = (hit["position"] as Vector3).y
	return grounded

func _apply_grounding(pos: Vector3, delta: float) -> Vector3:
	var grounded := pos
	var hit := _probe_ground_hit(pos)
	if hit.is_empty():
		_vertical_speed = max(_vertical_speed - gravity_strength * delta, -max_fall_speed)
		grounded.y += _vertical_speed * delta
		if grounded.y < _ground_fallback_y:
			grounded.y = _ground_fallback_y
			_vertical_speed = 0.0
		return grounded

	_vertical_speed = 0.0
	var floor_y := (hit["position"] as Vector3).y
	grounded.y = lerp(grounded.y, floor_y, clamp(ground_snap_rate * delta, 0.0, 1.0))
	return grounded

func set_position_grounded(pos: Vector3) -> void:
	_agent.locomotion.set_position_grounded(self, pos, _world_ref)

func begin_travel_to(target_pos: Vector3, target_building: Building = null) -> bool:
	return _agent.locomotion.begin_travel_to(self, target_pos, target_building, _world_ref)

func has_reached_travel_target() -> bool:
	return _agent.locomotion.has_reached_travel_target(self)

func stop_travel() -> void:
	_agent.locomotion.stop_travel(self)

func is_inside_building() -> bool:
	return _inside_building != null

func enter_building(building: Building, world: World = null, emit_log: bool = true) -> void:
	if building == null:
		return
	stop_travel()
	current_location = building
	_inside_building = building
	_set_interior_presence(true)
	if world != null:
		_ground_fallback_y = world.get_ground_fallback_y()
	_update_trace_navigation_state("entered_%s" % building.get_display_name(), Vector3.ZERO, Vector3.ZERO)
	if emit_log:
		SimLogger.log("[Citizen %s] Entered %s at %s | entry=%s access=%s" % [
			citizen_name,
			building.get_display_name(),
			_trace_fmt_vec3(global_position),
			_trace_fmt_vec3(building.get_entrance_pos()),
			_trace_fmt_vec3(_get_building_access_pos(building, world))
		])

func exit_current_building(world: World = null) -> void:
	if _inside_building == null:
		return

	var exit_building := _inside_building
	var access_pos := _get_building_access_pos(exit_building, world)
	var exit_pos := _get_building_exit_spawn_pos(exit_building, world)

	_inside_building = null
	_set_interior_presence(false)
	set_position_grounded(exit_pos)
	if absf(global_position.y - exit_pos.y) > 0.45:
		global_position = exit_pos
		_vertical_speed = 0.0
		velocity = Vector3.ZERO
		_last_move_position = global_position
	_update_trace_navigation_state("exited_%s" % exit_building.get_display_name(), Vector3.ZERO, Vector3.ZERO)
	SimLogger.log("[Citizen %s] Exited %s at %s | entrance=%s access=%s spawn=%s" % [
		citizen_name,
		exit_building.get_display_name(),
		_trace_fmt_vec3(global_position),
		_trace_fmt_vec3(exit_building.get_entrance_pos()),
		_trace_fmt_vec3(access_pos),
		_trace_fmt_vec3(exit_pos)
	])

func _set_interior_presence(hidden: bool) -> void:
	if hidden:
		hide()
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
	else:
		show()
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask

	if _body_collision_shape != null:
		_body_collision_shape.disabled = hidden
	if _click_area != null:
		_click_area.input_ray_pickable = not hidden
	if _click_area_shape != null:
		_click_area_shape.disabled = hidden

func _get_building_access_pos(building: Building, world: World = null) -> Vector3:
	if building == null:
		return global_position
	var access_pos := building.get_entrance_pos()
	if world != null and world.has_method("get_pedestrian_access_point"):
		access_pos = world.get_pedestrian_access_point(access_pos, building)
	return access_pos

func _get_building_exit_spawn_pos(building: Building, world: World = null) -> Vector3:
	var access_pos := _get_building_access_pos(building, world)
	if building == null:
		return access_pos

	var entrance_pos := building.get_entrance_pos()
	var outward := access_pos - entrance_pos
	outward.y = 0.0
	if outward.length_squared() <= 0.0001:
		outward = access_pos - building.global_position
		outward.y = 0.0
	if outward.length_squared() <= 0.0001:
		outward = Vector3.FORWARD
	else:
		outward = outward.normalized()

	var lateral := Vector3(-outward.z, 0.0, outward.x)
	var lane_slot := int(abs(citizen_name.hash())) % 5 - 2
	var lane_offset := float(lane_slot) * 0.18
	var spawn_base := entrance_pos.lerp(access_pos, 0.28)
	var spawn_pos := spawn_base + lateral * lane_offset + outward * 0.04
	spawn_pos.y = spawn_base.y
	return spawn_pos

func get_debug_travel_path() -> PackedVector3Array:
	var path := PackedVector3Array()
	path.append(global_position)

	if not _is_travelling:
		return path

	if _travel_target != Vector3.ZERO:
		path.append(_travel_target)

	var start_idx := clampi(_travel_route_index + 1, 0, _travel_route.size())
	for i in range(start_idx, _travel_route.size()):
		var point: Vector3 = _travel_route[i]
		if path[path.size() - 1].distance_to(point) >= 0.05:
			path.append(point)

	return path

func get_debug_source_building() -> Building:
	if _inside_building != null:
		return _inside_building
	if current_location != null:
		return current_location
	return home

func get_debug_travel_target_building() -> Building:
	return _travel_target_building

func get_debug_access_pos(building: Building, world: World = null) -> Vector3:
	return _get_building_access_pos(building, world)

func get_debug_exit_spawn_pos(building: Building, world: World = null) -> Vector3:
	return _get_building_exit_spawn_pos(building, world)

func get_debug_travel_route_points() -> PackedVector3Array:
	if _is_travelling:
		return _travel_route
	return _debug_last_travel_route

func get_debug_travel_current_target() -> Vector3:
	if _is_travelling:
		return _travel_target
	return Vector3.ZERO

func get_debug_travel_route_index() -> int:
	if _is_travelling:
		return _travel_route_index
	return -1

func is_debug_travelling() -> bool:
	return _is_travelling

func has_debug_travel_route() -> bool:
	return _is_travelling or _debug_last_travel_route.size() >= 2

func did_debug_last_travel_fail() -> bool:
	return _debug_last_travel_failed

func _advance_travel_route() -> bool:
	if _travel_route.is_empty():
		return false

	var next_index := _travel_route_index + 1
	if next_index >= _travel_route.size():
		return false

	_travel_route_index = next_index
	_travel_target = _project_to_ground(_travel_route[_travel_route_index])
	if _nav_agent != null:
		_nav_agent.target_position = _travel_target
	_repath_time_left = repath_interval_sec
	return true

func _move_along_path(delta: float) -> void:
	if _repath_time_left > 0.0:
		_repath_time_left = maxf(_repath_time_left - delta, 0.0)

	if _arrived_via_entrance_contact:
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			if velocity.y < 0.0:
				velocity.y = 0.0
		else:
			velocity.y = maxf(velocity.y - gravity_strength * delta, -max_fall_speed)
		move_and_slide()
		return

	var to_target := _travel_target - global_position
	to_target.y = 0.0
	var distance_to_target := to_target.length()
	var is_last_waypoint: bool = _travel_route_index >= _travel_route.size() - 1
	var reach_distance: float = final_arrival_distance if is_last_waypoint else waypoint_reach_distance
	if is_last_waypoint and _travel_target_building != null:
		reach_distance = maxf(reach_distance, arrival_distance)

	if distance_to_target <= reach_distance:
		if _advance_travel_route():
			return
		if _travel_target_building != null:
			_arrived_via_entrance_contact = true
			_current_speed = 0.0
			velocity.x = 0.0
			velocity.z = 0.0
			_update_trace_navigation_state("arrive_target_access", Vector3.ZERO, Vector3.ZERO)
			return
		stop_travel()
		return

	if distance_to_target <= 0.001:
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)
		_update_trace_navigation_state("arriving", Vector3.ZERO, Vector3.ZERO)
		return

	var desired_speed: float = _walk_speed
	if distance_to_target < 1.2:
		desired_speed *= clamp(distance_to_target / 1.2, 0.25, 1.0)

	if _current_speed < desired_speed:
		_current_speed = move_toward(_current_speed, desired_speed, move_acceleration * delta)
	else:
		_current_speed = move_toward(_current_speed, desired_speed, move_deceleration * delta)

	var desired_dir: Vector3 = to_target / distance_to_target
	var move_dir := _compute_move_direction(desired_dir)
	_update_facing(move_dir, delta)

	velocity.x = move_dir.x * _current_speed
	velocity.z = move_dir.z * _current_speed
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity_strength * delta, -max_fall_speed)

	move_and_slide()
	_update_stuck_state(delta)

func _update_facing(move_dir: Vector3, delta: float) -> void:
	if move_dir.length_squared() <= 0.0001:
		return

	var target_yaw := _yaw_from_move_direction(move_dir)
	rotation.y = lerp_angle(rotation.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))

func _yaw_from_move_direction(move_dir: Vector3) -> float:
	return atan2(-move_dir.x, -move_dir.z)

func _compute_move_direction(desired_dir: Vector3) -> Vector3:
	var planar_dir := desired_dir
	planar_dir.y = 0.0
	if planar_dir.length_squared() <= 0.0001:
		_update_trace_navigation_state("idle", Vector3.ZERO, Vector3.ZERO)
		return Vector3.ZERO
	planar_dir = planar_dir.normalized()

	_refresh_obstacle_sensors(planar_dir)
	_update_trace_obstacle_hits()
	if _try_mark_arrived_via_target_entrance(planar_dir):
		_update_trace_navigation_state("arrive_target_entrance", planar_dir, Vector3.ZERO)
		return Vector3.ZERO
	if _stuck_timer >= obstacle_stuck_timeout:
		if _stuck_timer >= obstacle_repath_timeout:
			if _agent != null and _agent.locomotion != null and _agent.locomotion.repath_current_travel(self, _world_ref):
				_update_trace_navigation_state("repath_stuck", planar_dir, Vector3.ZERO)
				return Vector3.ZERO
		var slide_escape := _get_stuck_slide_direction(planar_dir)
		if slide_escape != Vector3.ZERO:
			_update_trace_navigation_state("stuck_slide_%s" % _trace_relative_label(slide_escape), planar_dir, slide_escape)
			return slide_escape
		var escape_dir := _compute_escape_direction(planar_dir)
		_update_trace_navigation_state("stuck_escape_%s" % _trace_relative_label(escape_dir), planar_dir, escape_dir)
		return escape_dir

	var forward_blocked := _ray_is_blocked(_obstacle_ray_forward)
	var left_blocked := _ray_is_blocked(_obstacle_ray_left)
	var right_blocked := _ray_is_blocked(_obstacle_ray_right)

	if forward_blocked:
		var avoid_dir := _choose_turn_direction(planar_dir, left_blocked, right_blocked)
		if avoid_dir != Vector3.ZERO:
			var blended_avoid := _blend_move_direction(planar_dir, avoid_dir)
			_update_trace_navigation_state("avoid_forward_%s" % _trace_relative_label(avoid_dir), planar_dir, blended_avoid)
			return blended_avoid
		var reverse_dir := -planar_dir
		_update_trace_navigation_state("avoid_forward_back", planar_dir, reverse_dir)
		return reverse_dir

	if left_blocked != right_blocked:
		var side_push := global_transform.basis.x if left_blocked else -global_transform.basis.x
		side_push.y = 0.0
		var nudged_dir := _blend_move_direction(planar_dir, side_push.normalized(), obstacle_side_bias)
		_update_trace_navigation_state(
			"nudge_%s_blocked" % ("left" if left_blocked else "right"),
			planar_dir,
			nudged_dir
		)
		return nudged_dir

	_update_trace_navigation_state("path_follow", planar_dir, planar_dir)
	return planar_dir

func _refresh_obstacle_sensors(move_dir: Vector3) -> void:
	if _obstacle_sensor_pivot == null:
		return
	var target_yaw := _yaw_from_move_direction(move_dir)
	_obstacle_sensor_pivot.rotation.y = wrapf(target_yaw - rotation.y, -PI, PI)
	if _obstacle_ray_forward != null:
		_obstacle_ray_forward.force_raycast_update()
	if _obstacle_ray_left != null:
		_obstacle_ray_left.force_raycast_update()
	if _obstacle_ray_right != null:
		_obstacle_ray_right.force_raycast_update()

func _ray_is_blocked(ray: RayCast3D) -> bool:
	if ray == null or not ray.enabled:
		return false
	if not ray.is_colliding():
		return false
	var collider := ray.get_collider()
	if collider is Node and _is_entrance_trigger_node(collider as Node):
		return false
	return collider != null and collider != self

func _try_mark_arrived_via_target_entrance(preferred_dir: Vector3) -> bool:
	if _travel_target_building == null:
		return false
	var access_delta := _travel_target - global_position
	access_delta.y = 0.0
	var access_distance := access_delta.length()
	if _any_ray_hits_target_entrance_trigger() and access_distance <= maxf(arrival_distance, 0.8):
		_arrived_via_entrance_contact = true
		return true
	if not _any_ray_hits_target_building():
		return false
	if access_distance <= arrival_distance:
		_arrived_via_entrance_contact = true
		return true

	var to_entrance := _travel_target_building.get_entrance_pos() - global_position
	to_entrance.y = 0.0
	var entrance_distance := to_entrance.length()
	if entrance_distance > entrance_contact_distance:
		return false
	if entrance_distance > 0.001:
		var entrance_dir := to_entrance / entrance_distance
		if preferred_dir.dot(entrance_dir) < entrance_contact_alignment:
			return false

	_arrived_via_entrance_contact = true
	return true

func _ray_hits_target_building(ray: RayCast3D) -> bool:
	if ray == null or not ray.enabled or not ray.is_colliding():
		return false
	var collider := ray.get_collider()
	if not (collider is Node):
		return false
	var node := collider as Node
	if _is_target_entrance_trigger(node):
		return true
	if _travel_target_building != null and _travel_target_building.has_method("owns_navigation_node"):
		return _travel_target_building.owns_navigation_node(node)
	return false

func _ray_hits_target_entrance_trigger(ray: RayCast3D) -> bool:
	if ray == null or not ray.enabled or not ray.is_colliding():
		return false
	var collider := ray.get_collider()
	if not (collider is Node):
		return false
	return _is_target_entrance_trigger(collider as Node)

func _any_ray_hits_target_building() -> bool:
	return _ray_hits_target_building(_obstacle_ray_forward) \
		or _ray_hits_target_building(_obstacle_ray_left) \
		or _ray_hits_target_building(_obstacle_ray_right)

func _any_ray_hits_target_entrance_trigger() -> bool:
	return _ray_hits_target_entrance_trigger(_obstacle_ray_forward) \
		or _ray_hits_target_entrance_trigger(_obstacle_ray_left) \
		or _ray_hits_target_entrance_trigger(_obstacle_ray_right)

func _is_entrance_trigger_node(node: Node) -> bool:
	var current := node
	while current != null:
		if current.name == "EntranceTrigger":
			return true
		current = current.get_parent()
	return false

func _is_target_entrance_trigger(node: Node) -> bool:
	if _travel_target_building == null or node == null:
		return false
	if _travel_target_building.has_method("is_entrance_trigger_node"):
		return _travel_target_building.is_entrance_trigger_node(node)
	return false

func _choose_turn_direction(preferred_dir: Vector3, left_blocked: bool, right_blocked: bool) -> Vector3:
	var left_dir := _ray_move_direction(_obstacle_ray_left)
	var right_dir := _ray_move_direction(_obstacle_ray_right)
	var left_open := not left_blocked and left_dir != Vector3.ZERO
	var right_open := not right_blocked and right_dir != Vector3.ZERO

	if left_open and right_open:
		return left_dir if _score_direction(left_dir) <= _score_direction(right_dir) else right_dir
	if left_open:
		return left_dir
	if right_open:
		return right_dir
	return -preferred_dir

func _compute_escape_direction(preferred_dir: Vector3) -> Vector3:
	var left_dir := _ray_move_direction(_obstacle_ray_left)
	var right_dir := _ray_move_direction(_obstacle_ray_right)
	var left_open := not _ray_is_blocked(_obstacle_ray_left) and left_dir != Vector3.ZERO
	var right_open := not _ray_is_blocked(_obstacle_ray_right) and right_dir != Vector3.ZERO

	if left_open or right_open:
		return _choose_turn_direction(preferred_dir, not left_open, not right_open)
	return -preferred_dir

func _get_stuck_slide_direction(preferred_dir: Vector3) -> Vector3:
	if _stuck_slide_hold_left > 0.0 and _stuck_slide_hold_dir != Vector3.ZERO:
		return _stuck_slide_hold_dir

	var slide_dir := _compute_slide_escape_direction(preferred_dir)
	if slide_dir != Vector3.ZERO:
		_stuck_slide_hold_dir = slide_dir
		_stuck_slide_hold_left = obstacle_slide_hold_sec
	return slide_dir

func _compute_slide_escape_direction(preferred_dir: Vector3) -> Vector3:
	var collision_count := get_slide_collision_count()
	if collision_count <= 0:
		return Vector3.ZERO

	var best_dir := Vector3.ZERO
	var best_score := INF
	for i in range(collision_count):
		var collision := get_slide_collision(i)
		if collision == null:
			continue
		var normal := collision.get_normal()
		normal.y = 0.0
		if normal.length_squared() <= 0.0001:
			continue
		normal = normal.normalized()

		var tangent_a := Vector3(-normal.z, 0.0, normal.x)
		var tangent_b := -tangent_a
		for candidate in [tangent_a, tangent_b]:
			if candidate.length_squared() <= 0.0001:
				continue
			var score := _score_direction(candidate)
			if candidate.dot(preferred_dir) < -0.35:
				score += 2.5
			if score < best_score:
				best_score = score
				best_dir = candidate

	return best_dir.normalized() if best_dir != Vector3.ZERO else Vector3.ZERO

func _ray_move_direction(ray: RayCast3D) -> Vector3:
	if ray == null:
		return Vector3.ZERO
	var local_target := ray.target_position
	var world_target := ray.to_global(local_target)
	var dir := world_target - ray.global_position
	dir.y = 0.0
	if dir.length_squared() <= 0.0001:
		return Vector3.ZERO
	return dir.normalized()

func _score_direction(dir: Vector3) -> float:
	var projected := global_position + dir * obstacle_side_probe_length
	projected.y = _travel_target.y
	return projected.distance_to(_travel_target)

func _blend_move_direction(preferred_dir: Vector3, avoid_dir: Vector3, weight: float = -1.0) -> Vector3:
	var effective_weight := obstacle_turn_weight if weight < 0.0 else weight
	var blended := preferred_dir + avoid_dir * effective_weight
	blended.y = 0.0
	if blended.length_squared() <= 0.0001:
		return avoid_dir
	return blended.normalized()

func _update_stuck_state(delta: float) -> void:
	if _stuck_slide_hold_left > 0.0:
		_stuck_slide_hold_left = maxf(_stuck_slide_hold_left - delta, 0.0)
		if _stuck_slide_hold_left <= 0.0:
			_stuck_slide_hold_dir = Vector3.ZERO
	var moved := global_position.distance_to(_last_move_position)
	if _current_speed > 0.2 and moved <= obstacle_stuck_distance:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
		_stuck_slide_hold_dir = Vector3.ZERO
		_stuck_slide_hold_left = 0.0
	_last_move_position = global_position

func _update_trace_navigation_state(reason: String, desired_dir: Vector3, move_dir: Vector3) -> void:
	_trace_last_decision_reason = reason
	_trace_last_desired_dir = desired_dir
	_trace_last_move_dir = move_dir

func _update_trace_obstacle_hits() -> void:
	_trace_last_forward_hit = _trace_describe_ray_hit(_obstacle_ray_forward)
	_trace_last_left_hit = _trace_describe_ray_hit(_obstacle_ray_left)
	_trace_last_right_hit = _trace_describe_ray_hit(_obstacle_ray_right)

func _trace_describe_ray_hit(ray: RayCast3D) -> String:
	if ray == null or not ray.enabled:
		return "off"
	if not ray.is_colliding():
		return "clear"

	var collider := ray.get_collider()
	var collider_name := _trace_collider_label(collider)
	var hit_pos := ray.get_collision_point()
	var distance := ray.global_position.distance_to(hit_pos)
	return "%s @ %s d=%.2f" % [collider_name, _trace_fmt_vec3(hit_pos), distance]

func _trace_collider_label(collider: Variant) -> String:
	if collider is Node:
		var node := collider as Node
		if node.is_inside_tree():
			return str(node.get_path())
		return node.name
	return str(collider)

func _trace_relative_label(direction: Vector3) -> String:
	if direction.length_squared() <= 0.0001:
		return "none"
	var local_dir := global_transform.basis.inverse() * direction
	if absf(local_dir.x) > absf(local_dir.z):
		return "right" if local_dir.x > 0.0 else "left"
	return "back" if local_dir.z > 0.0 else "forward"

func _trace_fmt_vec3(value: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [value.x, value.y, value.z]

func get_trace_debug_summary() -> String:
	var action_label := current_action.label if current_action != null else "idle"
	var location_label := current_location.get_display_name() if current_location != null else "travelling"
	var inside_label := _inside_building.get_display_name() if _inside_building != null else "-"
	var travel_building_label := _travel_target_building.get_display_name() if _travel_target_building != null else "-"
	var target_label := _trace_fmt_vec3(_travel_target) if _is_travelling else "-"
	var waypoint_label := "-"
	if _is_travelling and not _travel_route.is_empty():
		waypoint_label = "%d/%d" % [_travel_route_index, _travel_route.size() - 1]

	return "citizen=%s pos=%s vel=%s speed=%.2f action=%s location=%s inside=%s travel_to=%s on_floor=%s travelling=%s target=%s waypoint=%s decision=%s desired=%s move=%s seen[fwd=%s | left=%s | right=%s]" % [
		citizen_name,
		_trace_fmt_vec3(global_position),
		_trace_fmt_vec3(velocity),
		_current_speed,
		action_label,
		location_label,
		inside_label,
		travel_building_label,
		str(is_on_floor()),
		str(_is_travelling),
		target_label,
		waypoint_label,
		_trace_last_decision_reason,
		_trace_fmt_vec3(_trace_last_desired_dir),
		_trace_fmt_vec3(_trace_last_move_dir),
		_trace_last_forward_hit,
		_trace_last_left_hit,
		_trace_last_right_hit
	]
# Called from main.gd when selection/debug panel changes.
func set_selected(selected: bool) -> void:
	if _mesh_instance == null:
		return
	if selected:
		_mesh_instance.set_surface_override_material(0, _highlight_material)
	else:
		_mesh_instance.set_surface_override_material(0, _original_material)


# Selection entrypoint called from main.gd
# NOTE: _set() is not called for exported vars in this case.
# Variable ist schon definiert, daher greift der _set-Fallback nie.
# Solution: main.gd calls select(panel) directly.
func select(panel) -> void:
	debug_panel = panel
	set_selected(panel != null)


# Auto-resolve optional node references
func _auto_resolve_refs() -> void:
	if home_path != NodePath():
		home = get_node_or_null(home_path) as ResidentialBuilding
	if restaurant_path != NodePath():
		favorite_restaurant = get_node_or_null(restaurant_path) as Restaurant
	if supermarket_path != NodePath():
		favorite_supermarket = get_node_or_null(supermarket_path) as Supermarket
	if shop_path != NodePath():
		favorite_shop = get_node_or_null(shop_path) as Shop
	if cinema_path != NodePath():
		favorite_cinema = get_node_or_null(cinema_path) as Cinema
	if park_path != NodePath():
		favorite_park = get_node_or_null(park_path) as Building

	if home == null:
		home = _find_first_residential_building(global_position)
		if home:
			SimLogger.log("[Citizen %s] Auto-found home: %s" % [citizen_name, _building_label(home)])

	if home != null:
		var added := home.add_tenant(self)
		if added:
			SimLogger.log("[Citizen %s] Registered as tenant at: %s" % [citizen_name, _building_label(home)])
		else:
			var full_home := home
			home = _find_first_residential_building(global_position)
			if home != null and home != full_home and home.add_tenant(self):
				SimLogger.log("[Citizen %s] Home %s was full, reassigned to: %s" % [
					citizen_name,
					_building_label(full_home),
					_building_label(home)
				])
				SimLogger.log("[Citizen %s] Registered as tenant at: %s" % [citizen_name, _building_label(home)])
			else:
				home = null
				SimLogger.log("[Citizen %s] WARNING: No residential building with free tenant slot found." % citizen_name)

	var origin := home.get_entrance_pos() if home else global_position
	if home != null and _world_ref != null and _world_ref.has_method("get_pedestrian_access_point"):
		origin = _world_ref.get_pedestrian_access_point(origin, home)

	if favorite_restaurant == null:
		favorite_restaurant = _find_nearest_restaurant(origin, false)
		if favorite_restaurant:
			SimLogger.log("[Citizen %s] Auto-found restaurant: %s" % [citizen_name, _building_label(favorite_restaurant)])

	if favorite_supermarket == null:
		favorite_supermarket = _find_nearest_supermarket(origin, false)
		if favorite_supermarket:
			SimLogger.log("[Citizen %s] Auto-found supermarket: %s" % [citizen_name, _building_label(favorite_supermarket)])

	if favorite_shop == null:
		favorite_shop = _find_nearest_shop(origin, false)
		if favorite_shop:
			SimLogger.log("[Citizen %s] Auto-found shop: %s" % [citizen_name, _building_label(favorite_shop)])

	if favorite_cinema == null:
		favorite_cinema = _find_nearest_cinema(origin, false)
		if favorite_cinema:
			SimLogger.log("[Citizen %s] Auto-found cinema: %s" % [citizen_name, _building_label(favorite_cinema)])

	if favorite_park == null:
		favorite_park = _find_nearest_park(origin)
		if favorite_park:
			SimLogger.log("[Citizen %s] Auto-found park: %s" % [citizen_name, _building_label(favorite_park)])

	_try_find_job_once()

	if home:
		current_location = home
		set_position_grounded(origin)
		enter_building(home, _world_ref, false)

func _try_find_job_once() -> void:
	if job == null:
		return
	if job.workplace != null:
		return

	var from_pos := home.get_entrance_pos() if home else global_position
	if home != null and _world_ref != null and _world_ref.has_method("get_pedestrian_access_point"):
		from_pos = _world_ref.get_pedestrian_access_point(from_pos, home)
	var found_reachable_workplace := false
	if _world_ref != null:
		job.workplace = _world_ref.find_nearest_open_workplace(from_pos, job.workplace_name, job.workplace_service_type)
		found_reachable_workplace = job.workplace != null

	if job.workplace == null and _world_ref == null:
		var root := get_tree().current_scene
		job.resolve_nearest(root, from_pos)
		if job.workplace != null and not found_reachable_workplace:
			debug_log_once_per_day(
				"job_fallback_%s" % job.title,
				"Fallback workplace selected without world reachability check: %s for %s (%s)." % [
					_building_label(job.workplace),
					job.title,
					get_job_debug_summary()
				]
			)

	if job.workplace == null:
		debug_log_once_per_day(
			"job_search_none_%s" % job.title,
			"No reachable open workplace found for %s (service=%s, reqEdu=%d, from=%s)." % [
				job.title,
				job.workplace_service_type if job.workplace_service_type != "" else "any",
				job.required_education_level,
				_building_label(home)
			]
		)
		return

	if not job.meets_requirements(self):
		var blocked_workplace := job.workplace
		_maybe_log_job_requirement_notice(blocked_workplace)
		job.workplace = null
		return

	var hired := job.try_get_employed(self)
	if hired:
		_reset_job_notice_state()
		SimLogger.log("[Citizen %s] Employed at: %s | %s" % [
			citizen_name,
			_building_label(job.workplace),
			get_job_debug_summary()
		])
	else:
		var full_workplace := job.workplace
		job.workplace = null
		_maybe_log_workplace_full_notice(full_workplace)

func set_world_ref(world: World) -> void:
	if world == null:
		return
	_world_ref = world
	_ground_fallback_y = world.get_ground_fallback_y()
	_connect_time_signals(world)

func _connect_time_signals(world: World) -> void:
	if world == null or world.time == null:
		return
	if not world.time.hour_changed.is_connected(_on_hour_changed):
		world.time.hour_changed.connect(_on_hour_changed)


func _on_hour_changed(new_hour: int) -> void:
	if new_hour < 6 or new_hour > 20:
		return
	_try_find_job_once()

func _update_debug(world: World, h_delta: float) -> void:
	if not debug_panel:
		return

	if abs(h_delta) >= 0.5:
		var reason := ""
		if needs.hunger >= 80.0:   reason += " [starving]"
		if needs.energy <= 10.0:   reason += " [exhausted]"
		if needs.fun <= 0.0:       reason += " [depressed]"
		if h_delta > 0:            reason = " [recovering]"
		SimLogger.log("[%s] Health %s%.1f -> %.1f%s" % [
			citizen_name,
			"+" if h_delta > 0 else "",
			h_delta, needs.health, reason
		])

	var debug_route := get_debug_travel_route_points()
	var travel_state := "idle"
	var path_start := "-"
	var path_end := "-"
	if _is_travelling:
		travel_state = "moving"
	elif _debug_last_travel_failed and debug_route.size() >= 2:
		travel_state = "route_failed"
	elif debug_route.size() >= 2:
		travel_state = "last_route"

	if debug_route.size() >= 2:
		var route_start: Vector3 = debug_route[0]
		var route_end: Vector3 = debug_route[debug_route.size() - 1]
		path_start = "%d, %d, %d" % [route_start.x, route_start.y, route_start.z]
		path_end = "%d, %d, %d" % [route_end.x, route_end.y, route_end.z]

	debug_panel.update_debug({
		"Citizen"  : citizen_name,
		"Location" : current_location.building_name if current_location else "travelling...",
		"Action"   : current_action.label if current_action else "idle",
		"----------": "",
		"Hunger"   : "%.1f / 100  (eat@50)" % needs.hunger,
		"Energy"   : "%.1f / 100  (sleep@80)" % needs.energy,
		"Fun"      : "%.1f / 100  (relax@30)" % needs.fun,
		"Health"   : "%.1f / 100" % needs.health,
		"----------2": "",
		"Money"    : "%d EUR" % wallet.balance,
		"Groceries": str(home_food_stock),
		"Education": "%d" % education_level,
		"Workplace": job.workplace.building_name if (job and job.workplace) else "unemployed",
		"WorkToday": "%d / %d min" % [
			work_minutes_today,
			int(job.shift_hours * 60) if job else 0
		],
		"JobReqEdu": "%d" % (job.required_education_level if job else 0),
		"Motivation": "%.2f" % work_motivation,
		"ParkInterest": "%.2f" % park_interest,
		"Position": "%d, %d, %d " % [global_position.x, global_position.y, global_position.z],
		"TravelState": travel_state,
		"PathStart": path_start,
		"PathEnd": path_end,
	})

func _update_work_day(world: World) -> void:
	var today: int = world.time.day
	if _work_day_key != today:
		_work_day_key = today
		work_minutes_today = 0


func sim_tick(world: World) -> void:
	_agent.sim_tick(self, world)

func plan_next_action(world: World) -> void:
	_agent.planner.plan_next_action(world, self)

func can_afford_restaurant(world: World) -> bool:
	if favorite_restaurant == null:
		return false
	var price: int = favorite_restaurant.meal_price
	if favorite_restaurant.has_method("get_meal_price"):
		price = int(favorite_restaurant.get_meal_price(world))
	return wallet.balance >= price

func can_afford_groceries(world: World) -> bool:
	if favorite_supermarket == null:
		return false
	var price: int = favorite_supermarket.grocery_price
	if favorite_supermarket.has_method("get_grocery_price"):
		price = int(favorite_supermarket.get_grocery_price(world))
	return wallet.balance >= price

func can_afford_shop_item(_world: World) -> bool:
	if favorite_shop == null:
		return false
	var price: int = favorite_shop.item_price
	if favorite_shop.has_method("get_item_price_quote"):
		price = int(favorite_shop.get_item_price_quote(1.0))
	return wallet.balance >= price + _get_fun_cash_reserve(_world)

func can_afford_cinema(_world: World) -> bool:
	if favorite_cinema == null:
		return false
	return wallet.balance >= favorite_cinema.ticket_price + _get_fun_cash_reserve(_world)

func _get_fun_cash_reserve(world: World) -> int:
	var reserve: int = 20
	if home != null:
		reserve = maxi(reserve, home.rent_per_day)
	if favorite_supermarket != null:
		var grocery_price: int = favorite_supermarket.grocery_price
		if favorite_supermarket.has_method("get_grocery_price"):
			grocery_price = int(favorite_supermarket.get_grocery_price(world))
		reserve += grocery_price
	elif favorite_restaurant != null:
		var meal_price: int = favorite_restaurant.meal_price
		if favorite_restaurant.has_method("get_meal_price"):
			meal_price = int(favorite_restaurant.get_meal_price(world))
		reserve += meal_price
	return reserve

func _find_first_residential_building(from_pos: Vector3 = Vector3.ZERO) -> ResidentialBuilding:
	if _world_ref != null:
		if _world_ref.has_method("find_available_residential_building"):
			return _world_ref.find_available_residential_building(from_pos)
		return _world_ref.find_first_residential_building()

	var best: ResidentialBuilding = null
	var best_load := INF
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is not ResidentialBuilding:
			continue
		var residential := node as ResidentialBuilding
		if not residential.has_free_slot():
			continue
		var load := float(residential.tenants.size()) / float(maxi(residential.capacity, 1))
		var dist := from_pos.distance_to(residential.global_position)
		if load < best_load or (is_equal_approx(load, best_load) and dist < best_dist):
			best_load = load
			best_dist = dist
			best = residential
	return best


func _find_nearest_restaurant(from_pos: Vector3, require_open: bool = true) -> Restaurant:
	if _world_ref != null:
		if _world_ref.has_method("find_preferred_restaurant"):
			return _world_ref.find_preferred_restaurant(from_pos, self, require_open)
		return _world_ref.find_nearest_restaurant(from_pos, require_open)

	var best: Restaurant = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Restaurant:
			var r := node as Restaurant
			var d := from_pos.distance_to(r.global_position)
			if d < best_dist:
				best_dist = d
				best = r
	return best


func _find_nearest_supermarket(from_pos: Vector3, require_open: bool = true) -> Supermarket:
	if _world_ref != null:
		return _world_ref.find_nearest_supermarket(from_pos, require_open)

	var best: Supermarket = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Supermarket:
			var market := node as Supermarket
			var d := from_pos.distance_to(market.global_position)
			if d < best_dist:
				best_dist = d
				best = market
	return best


func _find_nearest_shop(from_pos: Vector3, require_open: bool = true) -> Shop:
	if _world_ref != null:
		return _world_ref.find_nearest_shop(from_pos, require_open)

	var best: Shop = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Shop and node is not Supermarket:
			var shop := node as Shop
			var d := from_pos.distance_to(shop.global_position)
			if d < best_dist:
				best_dist = d
				best = shop
	return best


func _find_nearest_cinema(from_pos: Vector3, require_open: bool = true) -> Cinema:
	if _world_ref != null:
		return _world_ref.find_nearest_cinema(from_pos, require_open)

	var best: Cinema = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is Cinema:
			var cinema := node as Cinema
			var d := from_pos.distance_to(cinema.global_position)
			if d < best_dist:
				best_dist = d
				best = cinema
	return best

func _find_nearest_university(from_pos: Vector3, require_open: bool = true) -> University:
	if _world_ref != null:
		return _world_ref.find_nearest_university(from_pos, require_open)

	var best: University = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("buildings"):
		if node is University:
			var uni := node as University
			var d := from_pos.distance_to(uni.global_position)
			if d < best_dist:
				best_dist = d
				best = uni
	return best

func _find_nearest_park(from_pos: Vector3) -> Building:
	if _world_ref != null:
		return _world_ref.find_nearest_park(from_pos)

	var best: Building = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("parks"):
		if node is Building:
			var b := node as Building
			var d := from_pos.distance_to(b.global_position)
			if d < best_dist:
				best_dist = d
				best = b
	return best

func debug_log(message: String) -> void:
	SimLogger.log("[Citizen %s] %s" % [citizen_name, message])

func debug_log_once_per_day(key: String, message: String) -> void:
	var today := _world_ref.world_day() if _world_ref != null else -1
	if _debug_once_day != today:
		_debug_once_day = today
		_debug_once_keys.clear()
	if _debug_once_keys.has(key):
		return
	_debug_once_keys[key] = true
	debug_log(message)

func get_job_debug_summary() -> String:
	if job == null:
		return "job=none"
	var workplace_label := _building_label(job.workplace) if job.workplace != null else "none"
	var service_type := job.workplace_service_type if job.workplace_service_type != "" else "any"
	return "job=%s reqEdu=%d/%d service=%s workplace=%s wage=%d shift=%02d+%dh worked=%dmin" % [
		job.title,
		education_level,
		job.required_education_level,
		service_type,
		workplace_label,
		job.wage_per_hour,
		job.start_hour,
		job.shift_hours,
		work_minutes_today
	]

func get_unemployment_debug_reason() -> String:
	if job == null:
		return "no assigned job"
	if job.workplace == null and not job.meets_requirements(self):
		return "education mismatch for %s (%d/%d)" % [
			job.title,
			education_level,
			job.required_education_level
		]
	if job.workplace == null:
		return "no workplace assigned for %s (service=%s)" % [
			job.title,
			job.workplace_service_type if job.workplace_service_type != "" else "any"
		]
	return "employment status unclear"

func get_zero_pay_debug_reason() -> String:
	var action_label := current_action.label if current_action != null else "idle"
	var location_label := _building_label(current_location) if current_location != null else "travelling"
	return "%s action=%s location=%s" % [get_job_debug_summary(), action_label, location_label]


func start_action(a: Action, world: World) -> void:
	_start_action(a, world)

func _start_action(a: Action, world: World) -> void:
	if a is GoToBuildingAction and is_inside_building():
		exit_current_building(world)

	current_action = a
	current_action.start(world, self)

	var h := world.time.get_hour()
	var m := world.time.get_minute()
	var w := world.time.get_weekday_name()
	var loc = _building_label(current_location) if current_location else "travelling"

	if a is GoToBuildingAction:
		var target := (a as GoToBuildingAction).target
		if target != null:
			loc = "-> " + _building_label(target)

	var health_icon := ""
	if needs.health < 50.0:    health_icon = " [LOW]"
	elif needs.health < 75.0:  health_icon = " [WARN]"

	SimLogger.log("[%s] %02d:%02d (%s) | %-10s | H:%.0f E:%.0f F:%.0f HP:%.0f%s | $%d | at=%s" % [
		citizen_name, h, m, w,
		a.label,
		needs.hunger, needs.energy, needs.fun, needs.health, health_icon,
		wallet.balance,
		loc
	])


func pay_rent(world: World, landlord: ResidentialBuilding, amount: int) -> void:
	if landlord == null:
		return
	var before := wallet.balance
	var success := world.economy.transfer(wallet, landlord.account, amount)
	if success:
		SimLogger.log("[%s] Rent paid: %d EUR (balance: %d -> %d)" % [
			citizen_name, amount, before, wallet.balance
		])
	else:
		SimLogger.log("[%s] Could not pay rent! Need %d EUR, have %d EUR" % [
			citizen_name, amount, wallet.balance
		])

func _building_label(building: Building) -> String:
	if building == null:
		return "Unknown"
	return building.get_display_name()

func _maybe_log_job_requirement_notice(blocked_workplace: Building = null) -> void:
	if job == null:
		return
	if _last_job_requirement_notice_level == education_level and _last_job_requirement_notice_title == job.title:
		return
	_last_job_requirement_notice_level = education_level
	_last_job_requirement_notice_title = job.title
	var study_origin := home.get_entrance_pos() if home else global_position
	if home != null and _world_ref != null and _world_ref.has_method("get_pedestrian_access_point"):
		study_origin = _world_ref.get_pedestrian_access_point(study_origin, home)
	var nearest_uni := _find_nearest_university(study_origin, false)
	var study_hint := " No reachable university available right now."
	if nearest_uni != null:
		study_hint = " Study option: %s (tuition %d EUR)." % [
			nearest_uni.get_display_name(),
			nearest_uni.tuition_fee
		]
	debug_log("Needs education level %d for job %s (current %d). Candidate workplace: %s.%s" % [
		job.required_education_level,
		job.title,
		education_level,
		_building_label(blocked_workplace),
		study_hint
	])

func _maybe_log_workplace_full_notice(workplace: Building = null) -> void:
	var today := _world_ref.world_day() if _world_ref != null else -1
	if _last_workplace_full_notice_day == today:
		return
	_last_workplace_full_notice_day = today
	var worker_count := workplace.workers.size() if workplace != null else 0
	var capacity := workplace.job_capacity if workplace != null else 0
	debug_log("Workplace full at %s (%d/%d workers), will retry later." % [
		_building_label(workplace),
		worker_count,
		capacity
	])

func _reset_job_notice_state() -> void:
	_last_job_requirement_notice_level = -1
	_last_job_requirement_notice_title = ""
	_last_workplace_full_notice_day = -1
