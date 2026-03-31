extends CharacterBody3D
class_name Citizen

const CitizenAgentScript = preload("res://Simulation/Citizens/CitizenAgent.gd")
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

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
@export var floor_snap_distance: float = 0.35
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
@export var obstacle_jump_stuck_timeout: float = 2.2
@export var obstacle_jump_velocity: float = 5.2
@export var obstacle_jump_cooldown_sec: float = 1.35
@export var obstacle_jump_floor_snap_suppress_sec: float = 0.28
@export var obstacle_jump_forward_hold_sec: float = 0.22
@export var obstacle_jump_forward_speed_multiplier: float = 1.2
@export var unreachable_target_retry_limit: int = 3
@export var unreachable_target_no_progress_minutes: int = 18
@export var unreachable_target_cooldown_minutes: int = 180
@export var crowded_waypoint_skip_distance: float = 1.0
@export var crowded_waypoint_neighbor_radius: float = 0.55
@export var crowded_waypoint_shared_target_radius: float = 0.45
@export var crowded_waypoint_neighbor_count: int = 2
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
var _obstacle_ray_down: RayCast3D = null
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
var _trace_last_down_hit: String = "clear"
var _trace_last_left_hit: String = "clear"
var _trace_last_right_hit: String = "clear"
var _stuck_slide_hold_dir: Vector3 = Vector3.ZERO
var _stuck_slide_hold_left: float = 0.0
var _stuck_jump_cooldown_left: float = 0.0
var _floor_snap_suppress_left: float = 0.0
var _stuck_jump_hold_dir: Vector3 = Vector3.ZERO
var _stuck_jump_hold_left: float = 0.0
var _temporarily_unreachable_targets: Dictionary = {}
# TODO: Keep local crowd-deadlock diagnosis separate from economy stabilization fixes.
var _debug_repath_count: int = 0
var _debug_stuck_slide_count: int = 0
var _debug_stuck_jump_count: int = 0
var _debug_last_blocking_area: String = "-"
var _rest_pose_active: bool = false
var _rest_pose_position: Vector3 = Vector3.ZERO
var _rest_pose_yaw: float = 0.0
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
@export var manual_control_move_speed: float = 3.6
@export var manual_control_turn_speed: float = 10.0
@export var manual_control_jump_velocity: float = 5.6

# --- Work tracking ---
var work_minutes_today: int = 0
var _work_day_key: int = -1

# --- Selection highlight ---
var _mesh_instance: MeshInstance3D = null
var _original_material: Material = null
var _highlight_material: StandardMaterial3D = null
var _manual_control_enabled: bool = false
var _manual_jump_was_pressed: bool = false

func _ready() -> void:
	_apply_balance_config()
	wallet.owner_name = citizen_name
	wallet.balance = BalanceConfig.get_int("citizen.wallet_start_balance", wallet.balance)
	home_food_stock = BalanceConfig.get_int("citizen.home_food_stock_start", home_food_stock)
	education_level = BalanceConfig.get_int("citizen.education_level_start", education_level)

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
	# Entrance triggers are debug/contact helpers, not physical blockers for walking.
	collision_mask &= ~8
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	floor_snap_length = floor_snap_distance
	_agent.setup(self)
	_last_move_position = global_position
	call_deferred("_auto_resolve_refs")

func _apply_balance_config() -> void:
	var threshold_settings := BalanceConfig.get_section("citizen.thresholds")
	hunger_threshold_base = float(threshold_settings.get("hunger_threshold_base", hunger_threshold_base))
	hunger_threshold_jitter = float(threshold_settings.get("hunger_threshold_jitter", hunger_threshold_jitter))
	low_energy_threshold_base = float(threshold_settings.get("low_energy_threshold_base", low_energy_threshold_base))
	low_energy_threshold_jitter = float(threshold_settings.get("low_energy_threshold_jitter", low_energy_threshold_jitter))
	work_motivation_base = float(threshold_settings.get("work_motivation_base", work_motivation_base))
	work_motivation_jitter = float(threshold_settings.get("work_motivation_jitter", work_motivation_jitter))
	park_interest_base = float(threshold_settings.get("park_interest_base", park_interest_base))
	park_interest_jitter = float(threshold_settings.get("park_interest_jitter", park_interest_jitter))
	fun_target_base = float(threshold_settings.get("fun_target_base", fun_target_base))
	fun_target_jitter = float(threshold_settings.get("fun_target_jitter", fun_target_jitter))

func _physics_process(delta: float) -> void:
	if _manual_control_enabled:
		_manual_control_physics(delta)
		return
	_agent.physics_step(self, delta, _world_ref)

func set_manual_control_enabled(enabled: bool, world: World = null) -> void:
	if _manual_control_enabled == enabled:
		return
	_manual_control_enabled = enabled
	if enabled:
		clear_rest_pose(true)
		if is_inside_building():
			exit_current_building(world)
		elif current_location != null:
			leave_current_location(world)
		stop_travel()
		current_action = null
		decision_cooldown_left = 0
		_current_speed = 0.0
		_vertical_speed = 0.0
		velocity = Vector3.ZERO
		_manual_jump_was_pressed = false
		_update_trace_navigation_state("manual_control", Vector3.ZERO, Vector3.ZERO)
	else:
		stop_travel()
		decision_cooldown_left = 0
		_current_speed = 0.0
		_vertical_speed = 0.0
		velocity = Vector3.ZERO
		_manual_jump_was_pressed = false
		_update_trace_navigation_state("manual_control_exit", Vector3.ZERO, Vector3.ZERO)

func is_manual_control_enabled() -> bool:
	return _manual_control_enabled

func _manual_control_physics(delta: float) -> void:
	var input_vec := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vec.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vec.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vec.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vec.y -= 1.0

	var move_dir := Vector3.ZERO
	if input_vec.length_squared() > 0.0001:
		input_vec = input_vec.normalized()
		var camera := get_viewport().get_camera_3d()
		var forward := Vector3.FORWARD
		var right := Vector3.RIGHT
		if camera != null:
			forward = -camera.global_transform.basis.z
			right = camera.global_transform.basis.x
			forward.y = 0.0
			right.y = 0.0
			if forward.length_squared() > 0.0001:
				forward = forward.normalized()
			else:
				forward = Vector3.FORWARD
			if right.length_squared() > 0.0001:
				right = right.normalized()
			else:
				right = Vector3.RIGHT
		move_dir = (right * input_vec.x + forward * input_vec.y).normalized()
		_update_facing(move_dir, delta * (manual_control_turn_speed / maxf(turn_speed, 0.001)))
		_current_speed = move_toward(_current_speed, manual_control_move_speed, move_acceleration * delta)
	else:
		_current_speed = move_toward(_current_speed, 0.0, move_deceleration * delta)

	var jump_pressed := Input.is_key_pressed(KEY_SPACE)
	if jump_pressed and not _manual_jump_was_pressed and is_on_floor():
		velocity.y = maxf(velocity.y, manual_control_jump_velocity)
		_floor_snap_suppress_left = maxf(_floor_snap_suppress_left, obstacle_jump_floor_snap_suppress_sec)
		floor_snap_length = 0.0
	_update_stuck_state(delta)
	_manual_jump_was_pressed = jump_pressed

	velocity.x = move_dir.x * _current_speed
	velocity.z = move_dir.z * _current_speed
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity_strength * delta, -max_fall_speed)
	move_and_slide()
	_recover_floor_contact()
	_last_move_position = global_position
	_update_trace_navigation_state("manual_control", move_dir, move_dir)

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
	var body_col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var body_shape := body_col.shape as CapsuleShape3D if body_col != null else null
	var shape := col.shape as CapsuleShape3D
	if shape == null:
		shape = CapsuleShape3D.new()
		col.shape = shape
	if body_shape != null:
		shape.radius = body_shape.radius
		shape.height = body_shape.height
		col.transform = body_col.transform
	else:
		shape.radius = 0.45
		shape.height = 2.1
		col.position = Vector3(0, 1.05, 0)  # Mitte der Kapsel-Figur

	_click_area = area
	_click_area_shape = col

	if not area.input_event.is_connected(_on_area_input_event):
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
	_obstacle_ray_down = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastDown") as RayCast3D
	_obstacle_ray_left = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastLeft") as RayCast3D
	_obstacle_ray_right = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastRight") as RayCast3D

	if _obstacle_sensor_pivot != null:
		# Preserve the scene-authored pivot height. Only fall back to the exported
		# value when the pivot has not been positioned in the scene yet.
		if _obstacle_sensor_pivot.position.is_zero_approx():
			_obstacle_sensor_pivot.position = Vector3(0.0, obstacle_sensor_height, 0.0)

	var side_angle := deg_to_rad(obstacle_side_angle_deg)
	var side_x := sin(side_angle) * obstacle_side_probe_length
	var side_z := -cos(side_angle) * obstacle_side_probe_length

	if _obstacle_ray_forward != null:
		_obstacle_ray_forward.target_position = Vector3(0.0, 0.0, -obstacle_probe_length)
		_obstacle_ray_forward.collision_mask = 9
		_obstacle_ray_forward.enabled = true
	if _obstacle_ray_down != null:
		# Preserve the scene-authored downwards tilt so we can probe curb-height
		# obstacles that the horizontal rays miss.
		_obstacle_ray_down.collision_mask = 9
		_obstacle_ray_down.enabled = true
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
		query.collision_mask = 1
		query.collide_with_areas = false
		query.exclude = exclude

		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		var collider: Variant = hit.get("collider", null)
		if _is_citizen_collider(collider):
			if not hit.has("rid"):
				return {}
			exclude.append(hit["rid"])
			continue

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

func has_active_rest_pose() -> bool:
	return _rest_pose_active

func set_rest_pose(target_pos: Vector3, yaw: float = 0.0) -> void:
	if _inside_building == null and is_inside_tree():
		target_pos = _project_to_ground(target_pos)
	_rest_pose_active = true
	_rest_pose_position = target_pos
	_rest_pose_yaw = yaw
	apply_rest_pose()

func apply_rest_pose() -> void:
	if not _rest_pose_active:
		return
	global_position = _rest_pose_position
	rotation.y = _rest_pose_yaw
	_current_speed = 0.0
	_vertical_speed = 0.0
	velocity = Vector3.ZERO
	_last_move_position = global_position
	_update_trace_navigation_state("rest_pose", Vector3.ZERO, Vector3.ZERO)

func clear_rest_pose(snap_to_ground: bool = false) -> void:
	if not _rest_pose_active:
		return
	_rest_pose_active = false
	_current_speed = 0.0
	_vertical_speed = 0.0
	velocity = Vector3.ZERO
	if snap_to_ground and is_inside_tree():
		set_position_grounded(global_position)
	_last_move_position = global_position

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
	clear_rest_pose(true)
	if current_location != null and current_location != building and current_location.has_method("release_bench_for"):
		current_location.release_bench_for(self)
	var nav_points := _get_building_nav_points(building, world)
	var entry_pos := global_position
	stop_travel()
	current_location = building
	var is_outdoor := building.has_method("is_outdoor_destination") and building.is_outdoor_destination()
	if is_outdoor:
		set_position_grounded(global_position)
		_inside_building = null
		if nav_points.has("bench") and _should_auto_rest_on_outdoor_entry(building):
			set_rest_pose(
				nav_points.get("bench", global_position),
				float(nav_points.get("bench_yaw", rotation.y))
			)
	else:
		if nav_points.has("spawn"):
			set_position_grounded(nav_points["spawn"])
		_inside_building = building
	if building.has_method("on_citizen_entered"):
		building.on_citizen_entered(self)
	_set_interior_presence(not is_outdoor)
	if world != null:
		_ground_fallback_y = world.get_ground_fallback_y()
	_update_trace_navigation_state("entered_%s" % building.get_display_name(), Vector3.ZERO, Vector3.ZERO)
	if emit_log:
		SimLogger.log("[Citizen %s] Entered %s at %s | entrance=%s access=%s visit=%s spawn=%s" % [
			citizen_name,
			building.get_display_name(),
			_trace_fmt_vec3(entry_pos),
			_trace_fmt_vec3(nav_points.get("entrance", building.get_entrance_pos())),
			_trace_fmt_vec3(nav_points.get("access", _get_building_access_pos(building, world))),
			_trace_fmt_vec3(nav_points.get("visit", global_position)),
			_trace_fmt_vec3(nav_points.get("spawn", global_position))
		])

func leave_current_location(world: World = null, emit_log: bool = true) -> void:
	if is_inside_building():
		exit_current_building(world)
		return
	if current_location == null:
		return

	var exit_building := current_location
	clear_rest_pose(true)
	if exit_building.has_method("release_bench_for"):
		exit_building.release_bench_for(self)
	var nav_points := _get_building_nav_points(exit_building, world)
	var is_outdoor := exit_building.has_method("is_outdoor_destination") and exit_building.is_outdoor_destination()
	var exit_pos: Vector3 = nav_points.get("spawn", nav_points.get("access", global_position))
	if is_outdoor:
		set_position_grounded(exit_pos)
	current_location = null
	if exit_building.has_method("on_citizen_exited"):
		exit_building.on_citizen_exited(self)
	_update_trace_navigation_state("left_%s" % exit_building.get_display_name(), Vector3.ZERO, Vector3.ZERO)
	if emit_log:
		SimLogger.log("[Citizen %s] Left %s at %s | entrance=%s access=%s visit=%s" % [
			citizen_name,
			exit_building.get_display_name(),
			_trace_fmt_vec3(global_position),
			_trace_fmt_vec3(nav_points.get("entrance", exit_building.get_entrance_pos())),
			_trace_fmt_vec3(nav_points.get("access", _get_building_access_pos(exit_building, world))),
			_trace_fmt_vec3(nav_points.get("visit", global_position))
		])

func exit_current_building(world: World = null) -> void:
	if _inside_building == null:
		return

	clear_rest_pose(true)
	var exit_building := _inside_building
	var nav_points := _get_building_nav_points(exit_building, world)
	var access_pos: Vector3 = nav_points.get("access", _get_building_access_pos(exit_building, world))
	var exit_pos: Vector3 = nav_points.get("spawn", _get_building_exit_spawn_pos(exit_building, world))

	_inside_building = null
	if exit_building.has_method("on_citizen_exited"):
		exit_building.on_citizen_exited(self)
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
		_trace_fmt_vec3(nav_points.get("entrance", exit_building.get_entrance_pos())),
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
	var nav_points := _get_building_nav_points(building, world)
	return nav_points.get("access", global_position)

func get_navigation_points_for_building(building: Building, world: World = null) -> Dictionary:
	return _get_building_nav_points(building, world)

func _get_building_exit_spawn_pos(building: Building, world: World = null) -> Vector3:
	var nav_points := _get_building_nav_points(building, world)
	return nav_points.get("spawn", global_position)

func _get_building_nav_points(building: Building, world: World = null) -> Dictionary:
	if building == null:
		return {}

	var lane_offset := _get_building_lane_offset()
	var nav_points: Dictionary = {}
	if building.has_method("get_navigation_points"):
		nav_points = building.get_navigation_points(world, lane_offset, global_position)
	else:
		var entrance_pos := building.get_entrance_pos()
		var access_pos := entrance_pos
		if world != null and world.has_method("get_pedestrian_access_point"):
			access_pos = world.get_pedestrian_access_point(entrance_pos, building)

		nav_points = {
			"entrance": entrance_pos,
			"access": access_pos,
			"spawn": _compute_building_exit_spawn_from_points(building, entrance_pos, access_pos, lane_offset),
		}

	var reserved_bench: Dictionary = {}
	if building is Park:
		reserved_bench = (building as Park).get_reserved_bench_for(self)
	elif building.has_method("get_reserved_bench_for"):
		reserved_bench = building.get_reserved_bench_for(self)
	if not reserved_bench.is_empty():
		var bench_pos: Vector3 = reserved_bench.get("position", nav_points.get("visit", nav_points.get("center", global_position)))
		nav_points["visit"] = bench_pos
		nav_points["center"] = bench_pos
		nav_points["bench"] = bench_pos
		nav_points["bench_yaw"] = float(reserved_bench.get("yaw", 0.0))

	return nav_points

func _get_building_lane_offset() -> float:
	var lane_offsets := [-0.18, -0.06, 0.06, 0.18]
	var lane_slot := int(abs(citizen_name.hash())) % lane_offsets.size()
	return float(lane_offsets[lane_slot])

func _compute_building_exit_spawn_from_points(
	building: Building,
	entrance_pos: Vector3,
	access_pos: Vector3,
	lane_offset: float = 0.0
) -> Vector3:
	if building == null:
		return access_pos

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
	var spawn_base := entrance_pos.lerp(access_pos, 0.55)
	var spawn_pos := spawn_base + lateral * lane_offset + outward * 0.02
	spawn_pos.y = spawn_base.y
	return spawn_pos

func _get_waypoint_move_target() -> Vector3:
	if _travel_route_index <= 0 or _travel_route_index >= _travel_route.size() - 1:
		return _travel_target
	if _is_crosswalk_waypoint(_travel_target):
		return _travel_target

	var prev_point := _travel_route[_travel_route_index - 1]
	var next_point := _travel_route[_travel_route_index + 1]
	var axis := next_point - prev_point
	axis.y = 0.0
	if axis.length_squared() <= 0.0001:
		axis = _travel_target - prev_point
		axis.y = 0.0
	if axis.length_squared() <= 0.0001:
		return _travel_target

	var lateral := Vector3(-axis.z, 0.0, axis.x).normalized()
	var adjusted_target := _travel_target + lateral * _get_building_lane_offset()
	adjusted_target.y = _travel_target.y
	return adjusted_target

func _should_skip_crowded_waypoint(distance_to_target: float, is_last_waypoint: bool) -> bool:
	if is_last_waypoint:
		return false
	if _travel_route_index <= 0 or _travel_route_index >= _travel_route.size() - 1:
		return false
	if _is_crosswalk_waypoint(_travel_target):
		return false
	if distance_to_target > crowded_waypoint_skip_distance:
		return false
	if _stuck_timer < obstacle_stuck_timeout:
		return false
	return _count_waypoint_conflicts() >= crowded_waypoint_neighbor_count

func _count_waypoint_conflicts() -> int:
	if _world_ref == null:
		return 0

	var conflicts := 0
	for other in _world_ref.citizens:
		if other == null or other == self:
			continue
		if not is_instance_valid(other):
			continue
		if other.has_method("is_inside_building") and other.is_inside_building():
			continue
		if global_position.distance_to(other.global_position) > crowded_waypoint_neighbor_radius:
			continue

		var shares_target := false
		if other is Citizen:
			var other_citizen := other as Citizen
			if other_citizen._is_travelling and other_citizen._travel_target.distance_to(_travel_target) <= crowded_waypoint_shared_target_radius:
				shares_target = true
		if not shares_target and other.global_position.distance_to(_travel_target) > crowded_waypoint_skip_distance:
			continue
		conflicts += 1

	return conflicts

func _is_crosswalk_waypoint(point: Vector3) -> bool:
	if _world_ref == null or not _world_ref.has_method("get_pedestrian_path_point_kind"):
		return false
	var kind := str(_world_ref.get_pedestrian_path_point_kind(point))
	return kind.begins_with("crosswalk")

func _recover_floor_contact() -> void:
	if _floor_snap_suppress_left > 0.0:
		return
	if is_on_floor():
		return
	var hit := _probe_ground_hit(global_position)
	if hit.is_empty():
		return
	var floor_pos := hit["position"] as Vector3
	var floor_gap := global_position.y - floor_pos.y
	if floor_gap < -0.05 or floor_gap > maxf(floor_snap_distance + 0.1, 0.55):
		return
	global_position.y = floor_pos.y
	velocity.y = 0.0
	_vertical_speed = 0.0

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
		_recover_floor_contact()
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
		if _travel_target_building != null and _should_use_entrance_contact_arrival():
			_arrived_via_entrance_contact = true
			_current_speed = 0.0
			velocity.x = 0.0
			velocity.z = 0.0
			_update_trace_navigation_state("arrive_target_access", Vector3.ZERO, Vector3.ZERO)
			return
		if _travel_target_building != null and _travel_target_building.has_method("is_outdoor_destination") and _travel_target_building.is_outdoor_destination():
			set_position_grounded(_travel_target)
		stop_travel()
		_update_trace_navigation_state("arrive_target_path_end", Vector3.ZERO, Vector3.ZERO)
		return

	if _should_skip_crowded_waypoint(distance_to_target, is_last_waypoint):
		if _advance_travel_route():
			_update_trace_navigation_state("skip_crowded_waypoint", Vector3.ZERO, Vector3.ZERO)
			return

	var move_target := _get_waypoint_move_target()
	var move_delta := move_target - global_position
	move_delta.y = 0.0
	var move_distance := move_delta.length()

	if move_distance <= 0.001:
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

	var desired_dir: Vector3 = move_delta / move_distance
	var move_dir := _compute_move_direction(desired_dir)
	if _stuck_jump_hold_left > 0.0 and _stuck_jump_hold_dir != Vector3.ZERO:
		_current_speed = maxf(_current_speed, _walk_speed * obstacle_jump_forward_speed_multiplier)
	_update_facing(move_dir, delta)

	velocity.x = move_dir.x * _current_speed
	velocity.z = move_dir.z * _current_speed
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity_strength * delta, -max_fall_speed)

	move_and_slide()
	_recover_floor_contact()
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

	if _stuck_jump_hold_left > 0.0 and _stuck_jump_hold_dir != Vector3.ZERO:
		var jump_dir := _stuck_jump_hold_dir.normalized()
		_update_trace_navigation_state("jump_carry", planar_dir, jump_dir)
		return jump_dir

	_refresh_obstacle_sensors(planar_dir)
	_update_trace_obstacle_hits()
	if _try_step_up_from_down_ray():
		_refresh_obstacle_sensors(planar_dir)
		_update_trace_obstacle_hits()
	if _try_mark_arrived_via_target_entrance(planar_dir):
		_update_trace_navigation_state("arrive_target_entrance", planar_dir, Vector3.ZERO)
		return Vector3.ZERO
	if _stuck_timer >= obstacle_stuck_timeout:
		var repath_timeout := maxf(obstacle_repath_timeout, obstacle_jump_stuck_timeout + 0.35)
		# Give the locomotion system a chance to rebuild the route before we keep
		# committing to the same slide direction forever against the same obstacle.
		if _stuck_timer >= repath_timeout:
			if _agent != null and _agent.locomotion != null and _agent.locomotion.repath_current_travel(self, _world_ref):
				_debug_repath_count += 1
				_update_congestion_debug_label()
				_update_trace_navigation_state("repath_stuck", planar_dir, Vector3.ZERO)
				return Vector3.ZERO
		if _stuck_timer >= obstacle_jump_stuck_timeout and _try_stuck_jump(planar_dir):
			_debug_stuck_jump_count += 1
			_update_congestion_debug_label()
			_update_trace_navigation_state("stuck_jump", planar_dir, planar_dir)
			return planar_dir
		var slide_escape := _get_stuck_slide_direction(planar_dir)
		if slide_escape != Vector3.ZERO:
			_debug_stuck_slide_count += 1
			_update_congestion_debug_label()
			_update_trace_navigation_state("stuck_slide_%s" % _trace_relative_label(slide_escape), planar_dir, slide_escape)
			return slide_escape
		var escape_dir := _compute_escape_direction(planar_dir)
		_update_trace_navigation_state("stuck_escape_%s" % _trace_relative_label(escape_dir), planar_dir, escape_dir)
		return escape_dir

	var forward_blocked := _ray_is_blocked(_obstacle_ray_forward)
	if not forward_blocked and _ray_detects_low_obstacle(_obstacle_ray_down):
		forward_blocked = true
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
	if _obstacle_ray_down != null:
		_obstacle_ray_down.force_raycast_update()
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
	if _is_citizen_collider(collider):
		return false
	return collider != null and collider != self

func _ray_detects_low_obstacle(ray: RayCast3D) -> bool:
	if ray == null or not ray.enabled or not ray.is_colliding():
		return false

	var collider := ray.get_collider()
	if collider == null or collider == self:
		return false
	if _is_citizen_collider(collider):
		return false
	if collider is Node:
		var node := collider as Node
		if _is_entrance_trigger_node(node):
			return false
	if _ray_hits_target_building(ray):
		return false

	var hit_normal := ray.get_collision_normal()
	return hit_normal.dot(Vector3.UP) < 0.55

func _is_citizen_collider(collider: Variant) -> bool:
	if collider == null or collider == self:
		return false
	if collider is Citizen:
		return true
	if collider is CharacterBody3D:
		var node := collider as Node
		return node.is_in_group("citizens")
	return false

func _should_auto_rest_on_outdoor_entry(building: Building) -> bool:
	if building == null:
		return false
	if not (current_action is GoToBuildingAction):
		return false
	if not building.is_in_group("parks"):
		return false
	if job != null and job.workplace == building:
		return false
	return true

func _is_walkable_step_surface(collider: Variant) -> bool:
	if not (collider is Node):
		return false
	var node := collider as Node
	var label := node.name.to_lower()
	if node.is_inside_tree():
		label = str(node.get_path()).to_lower()
	return label.contains("road_")

func _try_step_up_from_down_ray() -> bool:
	if _floor_snap_suppress_left > 0.0:
		return false
	if _obstacle_ray_down == null or not _obstacle_ray_down.enabled or not _obstacle_ray_down.is_colliding():
		return false

	var collider := _obstacle_ray_down.get_collider()
	if collider == null or collider == self:
		return false
	if collider is Node:
		var node := collider as Node
		if _is_entrance_trigger_node(node):
			return false
	if not _is_walkable_step_surface(collider):
		return false

	var hit_normal := _obstacle_ray_down.get_collision_normal()
	if hit_normal.dot(Vector3.UP) < 0.55:
		return false

	var hit_pos := _obstacle_ray_down.get_collision_point()
	var step_height := hit_pos.y - global_position.y
	if step_height <= 0.02 or step_height > max_ground_step_up:
		return false

	global_position.y = hit_pos.y
	velocity.y = 0.0
	_vertical_speed = 0.0
	_last_move_position = global_position
	return true

func _try_mark_arrived_via_target_entrance(preferred_dir: Vector3) -> bool:
	if _travel_target_building == null:
		return false
	if not _should_use_entrance_contact_arrival():
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

func _should_use_entrance_contact_arrival() -> bool:
	if _travel_target_building == null:
		return false
	return not (
		_travel_target_building.has_method("is_outdoor_destination")
		and _travel_target_building.is_outdoor_destination()
	)

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
		if current.name.begins_with("EntranceTrigger"):
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

func _try_stuck_jump(forward_dir: Vector3) -> bool:
	if _stuck_jump_cooldown_left > 0.0:
		return false
	if not _ensure_ground_contact_for_stuck_jump():
		return false
	if forward_dir.length_squared() <= 0.0001:
		return false

	velocity.y = maxf(velocity.y, obstacle_jump_velocity)
	_vertical_speed = velocity.y
	_stuck_jump_hold_dir = forward_dir.normalized()
	_stuck_jump_hold_left = obstacle_jump_forward_hold_sec
	_current_speed = maxf(_current_speed, _walk_speed * obstacle_jump_forward_speed_multiplier)
	_stuck_jump_cooldown_left = obstacle_jump_cooldown_sec
	_floor_snap_suppress_left = obstacle_jump_floor_snap_suppress_sec
	floor_snap_length = 0.0
	_stuck_timer = 0.0
	_stuck_slide_hold_dir = Vector3.ZERO
	_stuck_slide_hold_left = 0.0
	return true

func _ensure_ground_contact_for_stuck_jump() -> bool:
	if is_on_floor():
		return true

	var hit := _probe_ground_hit(global_position)
	if hit.is_empty():
		return false

	var floor_pos := hit["position"] as Vector3
	var floor_gap := global_position.y - floor_pos.y
	var max_jump_ground_gap := maxf(floor_snap_distance * 0.6, 0.18)
	if floor_gap < -0.05 or floor_gap > max_jump_ground_gap:
		return false

	global_position.y = floor_pos.y
	velocity.y = 0.0
	_vertical_speed = 0.0
	return true

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
	if _stuck_jump_cooldown_left > 0.0:
		_stuck_jump_cooldown_left = maxf(_stuck_jump_cooldown_left - delta, 0.0)
	if _stuck_jump_hold_left > 0.0:
		_stuck_jump_hold_left = maxf(_stuck_jump_hold_left - delta, 0.0)
		if _stuck_jump_hold_left <= 0.0:
			_stuck_jump_hold_dir = Vector3.ZERO
	if _floor_snap_suppress_left > 0.0:
		_floor_snap_suppress_left = maxf(_floor_snap_suppress_left - delta, 0.0)
		floor_snap_length = 0.0
	else:
		floor_snap_length = floor_snap_distance
	var moved := global_position.distance_to(_last_move_position)
	if _current_speed > 0.2 and moved <= obstacle_stuck_distance:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
		_stuck_slide_hold_dir = Vector3.ZERO
		_stuck_slide_hold_left = 0.0
		if is_on_floor():
			_stuck_jump_hold_dir = Vector3.ZERO
			_stuck_jump_hold_left = 0.0
	_last_move_position = global_position

func _update_trace_navigation_state(reason: String, desired_dir: Vector3, move_dir: Vector3) -> void:
	_trace_last_decision_reason = reason
	_trace_last_desired_dir = desired_dir
	_trace_last_move_dir = move_dir

func _update_trace_obstacle_hits() -> void:
	_trace_last_forward_hit = _trace_describe_ray_hit(_obstacle_ray_forward)
	_trace_last_down_hit = _trace_describe_ray_hit(_obstacle_ray_down)
	_trace_last_left_hit = _trace_describe_ray_hit(_obstacle_ray_left)
	_trace_last_right_hit = _trace_describe_ray_hit(_obstacle_ray_right)
	_update_congestion_debug_label()

func _update_congestion_debug_label() -> void:
	for candidate in [_trace_last_forward_hit, _trace_last_down_hit, _trace_last_left_hit, _trace_last_right_hit]:
		if candidate != "clear" and candidate != "off":
			_debug_last_blocking_area = candidate
			return

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

	return "citizen=%s pos=%s vel=%s speed=%.2f action=%s location=%s inside=%s travel_to=%s on_floor=%s travelling=%s target=%s waypoint=%s decision=%s desired=%s move=%s seen[fwd=%s | down=%s | left=%s | right=%s] crowd[repath=%d stuck_slide=%d jump=%d hotspot=%s]" % [
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
		_trace_last_down_hit,
		_trace_last_left_hit,
		_trace_last_right_hit,
		_debug_repath_count,
		_debug_stuck_slide_count,
		_debug_stuck_jump_count,
		_debug_last_blocking_area
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
	var from_pos := _get_job_search_origin()
	if job == null:
		_try_retarget_job_to_city_need(from_pos)
		if job == null:
			return
	elif job.workplace == null:
		_try_retarget_job_to_city_need(from_pos)

	if job == null or job.workplace != null:
		return
	var found_reachable_workplace := false
	if _world_ref != null:
		job.workplace = _world_ref.find_best_workplace_for_job(from_pos, job, self)
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

func notify_job_lost(closed_building: Building = null, reason: String = "") -> void:
	if job == null or job.workplace != null:
		return
	_reset_job_notice_state()
	if reason != "":
		debug_log("Searching for a new job after losing %s (%s)." % [
			_building_label(closed_building),
			reason
		])
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
			return _world_ref.find_preferred_restaurant(from_pos, self, require_open, self)
		return _world_ref.find_nearest_restaurant(from_pos, require_open, self)

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
		return _world_ref.find_nearest_supermarket(from_pos, require_open, self)

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
		return _world_ref.find_nearest_shop(from_pos, require_open, self)

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
		return _world_ref.find_nearest_cinema(from_pos, require_open, self)

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
		return _world_ref.find_nearest_university(from_pos, require_open, self)

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
		return _world_ref.find_nearest_park(from_pos, self)

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
	var workplace_label := "none"
	if job.workplace != null:
		workplace_label = _building_label(job.workplace)
	elif job.preferred_workplace != null:
		workplace_label = "target:%s" % _building_label(job.preferred_workplace)
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
		var target_label := _building_label(job.preferred_workplace) if job.preferred_workplace != null else "no target workplace"
		return "education mismatch for %s (%d/%d) target=%s" % [
			job.title,
			education_level,
			job.required_education_level,
			target_label
		]
	if job.workplace == null:
		var preferred_label := _building_label(job.preferred_workplace) if job.preferred_workplace != null else "none"
		return "no workplace assigned for %s (service=%s target=%s)" % [
			job.title,
			job.workplace_service_type if job.workplace_service_type != "" else "any",
			preferred_label
		]
	return "employment status unclear"

func _get_job_search_origin() -> Vector3:
	var from_pos := home.get_entrance_pos() if home else (global_position if is_inside_tree() else position)
	if home != null and _world_ref != null and _world_ref.has_method("get_pedestrian_access_point"):
		from_pos = _world_ref.get_pedestrian_access_point(from_pos, home)
	return from_pos

func _try_retarget_job_to_city_need(from_pos: Vector3) -> bool:
	if _world_ref == null or not _world_ref.has_method("find_best_job_offer_for_citizen"):
		return false
	var allow_training := _find_nearest_university(from_pos, true) != null
	var offer: Dictionary = _world_ref.find_best_job_offer_for_citizen(from_pos, self, allow_training)
	if offer.is_empty():
		return false
	return _apply_job_offer(offer)

func _apply_job_offer(offer: Dictionary) -> bool:
	var building := offer.get("building", null) as Building
	var job_title := str(offer.get("title", ""))
	if building == null or job_title.is_empty():
		return false
	if job != null \
		and job.title == job_title \
		and job.preferred_workplace == building \
		and job.required_education_level == int(offer.get("required_education_level", job.required_education_level)):
		return false

	if job == null:
		job = Job.new()
		if _world_ref != null and _world_ref.has_method("register_job"):
			_world_ref.register_job(job)

	job.title = job_title
	job.wage_per_hour = int(offer.get("wage_per_hour", job.wage_per_hour))
	job.required_education_level = int(offer.get("required_education_level", job.required_education_level))
	job.workplace_service_type = ""
	job.workplace_name = ""
	var allowed_types_variant: Variant = offer.get("allowed_building_types", [])
	job.allowed_building_types = (allowed_types_variant as Array).duplicate() if allowed_types_variant is Array else []
	job.preferred_workplace = building
	job.workplace = null
	_reset_job_notice_state()

	var mode := "training" if education_level < job.required_education_level else "direct placement"
	debug_log_once_per_day(
		"job_retarget_%s_%s" % [job.title, building.get_display_name()],
		"Retargeted to %s at %s (%s, edu %d/%d)." % [
			job.title,
			building.get_display_name(),
			mode,
			education_level,
			job.required_education_level
		]
	)
	return true

func get_zero_pay_debug_reason() -> String:
	var action_label := current_action.label if current_action != null else "idle"
	var location_label := _building_label(current_location) if current_location != null else "travelling"
	return "%s action=%s location=%s" % [get_job_debug_summary(), action_label, location_label]

func is_building_temporarily_unreachable(building: Building, world: World = null) -> bool:
	if building == null:
		return false
	var active_world := world if world != null else _world_ref
	if active_world == null or active_world.time == null:
		return false
	var key := building.get_instance_id()
	if not _temporarily_unreachable_targets.has(key):
		return false
	var blocked_until := int(_temporarily_unreachable_targets.get(key, 0))
	if blocked_until <= _get_sim_total_minutes(active_world):
		_temporarily_unreachable_targets.erase(key)
		return false
	return true

func prepare_go_to_target(target: Building, world: World) -> Building:
	if target == null:
		return null
	if not is_building_temporarily_unreachable(target, world):
		return target
	return handle_unreachable_target(target, world, "target already on cooldown")

func handle_unreachable_target(target: Building, world: World, reason: String = "") -> Building:
	if target == null:
		return null
	_mark_building_temporarily_unreachable(target, world, reason)
	var replacement := _find_alternative_for_building(target, world)
	if replacement != null and replacement != target:
		_apply_building_target_replacement(target, replacement)
		debug_log("Retargeting from unreachable %s to %s (%s)." % [
			_building_label(target),
			_building_label(replacement),
			reason if reason != "" else "stuck"
		])
		return replacement
	debug_log("Aborting unreachable target %s (%s)." % [
		_building_label(target),
		reason if reason != "" else "stuck"
	])
	return null

func _mark_building_temporarily_unreachable(target: Building, world: World, reason: String = "") -> void:
	if target == null:
		return
	var active_world := world if world != null else _world_ref
	if active_world == null or active_world.time == null:
		return
	var until_minute := _get_sim_total_minutes(active_world) + maxi(unreachable_target_cooldown_minutes, 1)
	_temporarily_unreachable_targets[target.get_instance_id()] = until_minute
	debug_log("Marked %s as temporarily unreachable for %d sim-min (%s)." % [
		_building_label(target),
		unreachable_target_cooldown_minutes,
		reason if reason != "" else "navigation failure"
	])

func _get_sim_total_minutes(world: World = null) -> int:
	var active_world := world if world != null else _world_ref
	if active_world == null or active_world.time == null:
		return 0
	return maxi(active_world.time.day - 1, 0) * 24 * 60 + active_world.time.minutes_total

func _get_retarget_origin(world: World) -> Vector3:
	if current_location != null:
		var origin := current_location.get_entrance_pos()
		if world != null and world.has_method("get_pedestrian_access_point"):
			return world.get_pedestrian_access_point(origin, current_location)
		return origin
	if _inside_building != null:
		return _get_building_access_pos(_inside_building, world)
	return global_position if is_inside_tree() else position

func _find_alternative_for_building(target: Building, world: World) -> Building:
	var from_pos := _get_retarget_origin(world)
	if target == null:
		return null
	if target == home:
		var alt_home := _find_first_residential_building(from_pos)
		return alt_home if alt_home != target else null
	if target == favorite_restaurant or target is Restaurant:
		var alt_restaurant := _find_nearest_restaurant(from_pos, true)
		return alt_restaurant if alt_restaurant != target else null
	if target == favorite_supermarket or target is Supermarket:
		var alt_market := _find_nearest_supermarket(from_pos, true)
		return alt_market if alt_market != target else null
	if target == favorite_shop or (target is Shop and target is not Supermarket):
		var alt_shop := _find_nearest_shop(from_pos, true)
		return alt_shop if alt_shop != target else null
	if target == favorite_cinema or target is Cinema:
		var alt_cinema := _find_nearest_cinema(from_pos, true)
		return alt_cinema if alt_cinema != target else null
	if target == favorite_park or target.is_in_group("parks"):
		var alt_park := _find_nearest_park(from_pos)
		return alt_park if alt_park != target else null
	if target is University:
		var alt_uni := _find_nearest_university(from_pos, true)
		return alt_uni if alt_uni != target else null
	if job != null and job.workplace == target:
		job.workplace = null
		_try_find_job_once()
		return job.workplace if job != null and job.workplace != target else null
	if world != null and world.has_method("find_nearest_building_with_service"):
		var alt_service := world.find_nearest_building_with_service(from_pos, target.get_service_type(), true, self)
		return alt_service if alt_service != target else null
	return null

func _apply_building_target_replacement(original: Building, replacement: Building) -> void:
	if original == null or replacement == null:
		return
	if home == original and replacement is ResidentialBuilding:
		home = replacement as ResidentialBuilding
	if favorite_restaurant == original and replacement is Restaurant:
		favorite_restaurant = replacement as Restaurant
	if favorite_supermarket == original and replacement is Supermarket:
		favorite_supermarket = replacement as Supermarket
	if favorite_shop == original and replacement is Shop:
		favorite_shop = replacement as Shop
	if favorite_cinema == original and replacement is Cinema:
		favorite_cinema = replacement as Cinema
	if favorite_park == original:
		favorite_park = replacement
	if job != null:
		if job.workplace == original:
			job.workplace = replacement
		if job.preferred_workplace == original:
			job.preferred_workplace = replacement


func start_action(a: Action, world: World) -> void:
	_start_action(a, world)

func _start_action(a: Action, world: World) -> void:
	clear_rest_pose(true)
	if a is GoToBuildingAction and is_inside_building():
		exit_current_building(world)
	elif a is GoToBuildingAction and current_location != null:
		leave_current_location(world)

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
		study_hint = " Study option: %s (publicly funded)." % [
			nearest_uni.get_display_name(),
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
