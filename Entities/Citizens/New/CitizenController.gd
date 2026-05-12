class_name CitizenController
extends CharacterBody3D

## Root of the 4-layer citizen navigation stack (Navigation.md).
##
## Orchestrates:
##   Layer 1  Global       → GlobalPathPlanner
##   Layer 2  Perception   → LocalPerception
##   Layer 3  Local Plan   → LocalGridPlanner
##   Layer 4  Motion       → SteeringController
##   + JumpController, StuckRecovery, NavigationDebugDraw, CitizenLogger
##
## Keeps the old public API:
##   set_global_target(target: Vector3) -> bool
##   stop_travel()
##   is_travelling() -> bool
##   signals: target_reached, stuck
##
## Every tuning knob stays as an @export so the Inspector workflow is
## preserved; values are copied once into the CitizenConfig struct in _ready.

# ---------------------------------------------------------- Exports: Movement
@export_group("Movement")
@export var move_speed: float = 0.5
@export var waypoint_reach_distance: float = 0.35
@export var final_waypoint_reach_distance: float = 0.18
@export var waypoint_pass_distance: float = 0.55
@export var corner_blend_distance: float = 0.8
@export var corner_blend_strength: float = 0.45

# ---------------------------------------------------------- Exports: Input
@export_group("Click Input")
## When true, a right-click sets a new global target via screen-ray pick.
## Default false — every CharacterBody3D receives `_input` globally, so leaving
## this on for all citizens makes a single right-click teleport ALL of them
## to the same point. Enable per-citizen in the Inspector for the one you
## want to control with the mouse.
@export var accept_click_input: bool = false
@export var click_ray_distance: float = 1000.0
@export var ignore_ui_clicks: bool = true
@export_flags_3d_physics var click_collision_mask: int = 0xFFFFFFFF

# ---------------------------------------------------------- Exports: Keyboard Control
@export_group("Keyboard Control")
@export var keyboard_control_enabled: bool = false
@export var keyboard_control_camera_relative: bool = true
@export var keyboard_control_speed_multiplier: float = 1.0
@export var keyboard_control_disable_jump: bool = true
@export var keyboard_control_use_green_corridor: bool = true

# ---------------------------------------------------------- Exports: Avoidance
@export_group("Local Avoidance")
@export var obstacle_check_interval: float = 0.08
@export var avoidance_slowdown_factor: float = 0.65
@export var steering_smoothing: float = 5.0

# ---------------------------------------------------------- Exports: Local A*
@export_group("Local AStar Avoidance")
@export var use_local_astar_avoidance: bool = true
@export var local_astar_radius: float = 1.2
@export var local_astar_cell_size: float = 0.24
@export var local_astar_grid_subdivisions: int = 2
@export var local_astar_probe_radius: float = 0.16
@export var local_astar_replan_interval: float = 0.18
@export var local_astar_fallback_replan_cooldown: float = 1.0
@export var local_astar_goal_reach_distance: float = 0.12
@export var local_astar_front_row_tolerance: float = 0.24
@export var local_astar_prefer_right_when_left_open: bool = true
@export var local_astar_avoid_road_cells: bool = true
@export var local_astar_near_road_penalty: float = 16.0
@export var local_astar_road_proximity_margin: float = 0.3
@export var local_astar_road_buffer_cells: int = 1.3
@export var local_astar_forward_road_check_distance: float = 0.28
@export var local_astar_physics_near_road_margin: float = 0.22
@export var local_astar_probe_min_height: float = 0.08
@export var local_astar_probe_max_height: float = 0.9
@export var local_astar_probe_height_steps: int = 4
# Live-steering height/clearance defaults match the Coord-Picker debug scan
# (`_LIVE_SCAN_STEP_HEIGHT` / `_LIVE_SCAN_PROBE_RADIUS`) so what the player sees
# in the debug overlay is what `build_detour` actually plans against. 0.25 is
# the citizen capsule's allowed step-up; anything taller is a wall/post/hydrant
# and triggers the height block + 1-cell wall_buffer dilation.
@export var local_astar_height_block_threshold: float = 0.25
@export var local_astar_height_clearance_probe_radius: float = 0.0
@export_range(0, 4, 1) var local_astar_wall_buffer_cells: int = 0
@export_flags_3d_physics var local_astar_surface_collision_mask: int = 3
@export var local_astar_surface_probe_up: float = 0.5
@export var local_astar_surface_probe_down: float = 2.2
@export var local_astar_surface_probe_max_hits: int = 8

# ---------------------------------------------------------- Exports: Jump
@export_group("Low Obstacle Jump")
@export var jump_low_obstacles: bool = true
@export_node_path("RayCast3D") var obstacle_down_ray_path: NodePath
@export var max_jump_obstacle_height: float = 0.24
@export var min_jump_obstacle_height: float = 0.005
@export var jump_probe_distance: float = 0.45
@export var jump_velocity: float = 1.8
@export var jump_cooldown: float = 0.35

# ---------------------------------------------------------- Exports: Stuck
@export_group("Stuck Recovery")
@export var stuck_detection_interval: float = 1.5
@export var stuck_detection_min_distance: float = 0.25
@export var stuck_max_recovery_attempts: int = 3
@export var stuck_escape_duration: float = 1.1
@export var stuck_escape_probe_distance: float = 0.75
@export var stuck_escape_success_distance: float = 0.45
@export var stuck_escape_retarget_interval: float = 0.35
@export var stuck_escape_rejoin_probe_interval: float = 0.22
@export var stuck_escape_waypoint_skip_distance: float = 1.4
@export var stuck_detection_jitter: float = 0.45

# ---------------------------------------------------------- Exports: Logging
@export_group("Logging")
@export var enable_file_log: bool = false
## Minimum log level: 0=TRACE 1=DEBUG 2=INFO 3=WARN 4=ERROR.
## For single-citizen bug hunting keep at 0. Multi-citizen: raise to 2.
@export_range(0, 4, 1) var log_min_level: int = 0
@export var log_flush_interval: float = 0.25
@export var debug_log_probe_hits: bool = false
## Override log file path. Empty → user://logs/citizen_<name>.log
@export var log_file_path: String = ""

# ---------------------------------------------------------- Exports: Debug
@export_group("Debug Draw")
@export var debug_draw_avoidance: bool = false
@export var debug_draw_surface_cells: bool = false
@export var debug_draw_physics_hits: bool = false
@export var debug_draw_cell_heights: bool = false
@export var show_global_path: bool = false
@export var clear_global_path_on_arrival: bool = false
@export var global_path_line_color: Color = Color(0.1, 0.85, 1.0, 1.0)
@export var global_path_line_y_offset: float = 0.2
@export var global_path_line_width: float = 0.08

# ---------------------------------------------------------- Signals
signal target_reached()
signal stuck()

# Live citizen scan should match CoordinatePicker Drop+Scan semantics even
# when the heavier local-A* height mode is disabled for path planning.
const _LIVE_SCAN_STEP_HEIGHT: float = 0.25
const _LIVE_SCAN_PROBE_RADIUS: float = 0.08
const _TARGET_GROUND_PROBE_UP: float = 6.0
const _TARGET_GROUND_PROBE_DOWN: float = 12.0
const _TARGET_GROUND_MAX_HITS: int = 16
const _TARGET_GROUND_Y_TOLERANCE: float = 0.35
const _TARGET_WALKABLE_SEARCH_RADII: Array[float] = [0.25, 0.5, 0.8, 1.15]
const _TARGET_WALKABLE_SEARCH_DIRECTIONS: Array[Vector3] = [
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.FORWARD,
	Vector3.BACK,
	Vector3(0.70710678, 0.0, 0.70710678),
	Vector3(-0.70710678, 0.0, 0.70710678),
	Vector3(0.70710678, 0.0, -0.70710678),
	Vector3(-0.70710678, 0.0, -0.70710678),
]

# ---------------------------------------------------------- Modules
var _config: CitizenConfig = null
var _ctx: NavigationContext = null
var _logger: CitizenLogger = null
var _perception: LocalPerception = null
var _local_grid: LocalGridPlanner = null
var _steering: SteeringController = null
var _jump: JumpController = null
var _stuck: StuckRecovery = null
var _debug: NavigationDebugDraw = null

# ---------------------------------------------------------- Runtime state
var _global_path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _target_position: Vector3 = Vector3.ZERO
var _is_travelling: bool = false
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

# Forward probe pacing (Perception)
var _obstacle_check_timer: float = 0.0
var _cached_avoidance_blocked: bool = false
var _debug_avoidance_status: String = "idle"

# Local-grid path follow
var _local_avoidance_path: PackedVector3Array = PackedVector3Array()
var _local_avoidance_path_index: int = 0
var _local_astar_replan_timer: float = 0.0
var _local_astar_follow_global_on_fail: bool = false
var _debug_local_grid_status: String = "-"
var _debug_local_grid_goal: Vector3 = Vector3.ZERO
var _debug_local_grid_has_goal: bool = false
var _debug_local_grid_cells: Array = []
var _debug_local_grid_physics_hits: Array = []
var _debug_live_scan_cells: Array = []
var _debug_live_scan_physics_hits: Array = []
var _debug_live_scan_timer: float = 0.0
var _green_corridor_direction: Vector3 = Vector3.ZERO
var _green_corridor_timer: float = 0.0
var _last_corridor_kind: String = ""
var _manual_last_direction: Vector3 = Vector3.FORWARD
var _keyboard_jump_was_pressed: bool = false

# Surface-escape suppression (set after stuck replan + after no-candidates)
var _surface_escape_cooldown: float = 0.0
var _stuck_escape_direction: Vector3 = Vector3.ZERO
var _stuck_escape_target: Vector3 = Vector3.ZERO
var _stuck_escape_timer: float = 0.0
var _stuck_escape_retarget_timer: float = 0.0
var _stuck_escape_rejoin_probe_timer: float = 0.0
var _stuck_escape_start_pos: Vector3 = Vector3.ZERO


# ========================================================================
# Lifecycle
# ========================================================================

func _ready() -> void:
	_config = _build_config()
	_logger = _build_logger()
	_ctx = NavigationContext.new(self, _config, _logger)

	_perception = LocalPerception.new(_ctx)
	_local_grid = LocalGridPlanner.new(_ctx, _perception)
	_steering = SteeringController.new()
	_jump = JumpController.new(_ctx)
	_stuck = StuckRecovery.new(_ctx)
	_debug = NavigationDebugDraw.new(_ctx)
	# Wire cross-module dep: Perception's jumpable check uses Jump's near ray.
	_perception.set_jump_controller(_jump)

	# Resolve jump raycast.
	var ray: RayCast3D = null
	if obstacle_down_ray_path != NodePath():
		ray = get_node_or_null(obstacle_down_ray_path) as RayCast3D
	if ray == null:
		ray = get_node_or_null("ObstacleSensorPivot/ObstacleRayCastDown") as RayCast3D
	_jump.bind_ray(ray)

	_logger.info("CTRL", "READY", {
		"name": name,
		"log_path": _resolve_log_path(),
		"groups": str(get_groups()),
		"has_jump_ray": ray != null,
	})


func _input(event: InputEvent) -> void:
	if keyboard_control_enabled:
		if event.is_action_pressed("ui_cancel"):
			exit_keyboard_control_mode()
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
		return
	if not accept_click_input:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed:
		return
	if _config.ignore_ui_clicks and get_viewport().gui_get_hovered_control() != null:
		return
	var click_pos: Variant = _get_click_world_position(event.position)
	if click_pos != null:
		set_global_target(click_pos as Vector3)
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


# ========================================================================
# Public API (unchanged from old citizen_new.gd)
# ========================================================================

func set_global_target(target: Vector3) -> bool:
	var requested_target := target
	_target_position = _resolve_navigation_target(target)
	_global_path = GlobalPathPlanner.build_path(global_position, _target_position, _ctx)
	_path_index = 0
	_is_travelling = _global_path.size() >= 2
	_cached_avoidance_blocked = false
	_obstacle_check_timer = 0.0
	_local_astar_replan_timer = 0.0
	_local_astar_follow_global_on_fail = false
	_surface_escape_cooldown = 0.0
	_green_corridor_direction = Vector3.ZERO
	_green_corridor_timer = 0.0
	_steering.reset()
	_clear_local_avoidance_path()
	_clear_stuck_escape()
	_stuck.reset_for_new_target(global_position)

	if _is_travelling:
		_is_travelling = _advance_path_progress()

	_debug.update_global_path(_global_path, _path_index)
	_debug.update_target_marker(_target_position, true)

	_logger.info("CTRL", "TARGET_SET", {
		"from": global_position,
		"requested": requested_target,
		"to": _target_position,
		"waypoints": _global_path.size(),
		"travelling": _is_travelling,
	})
	return _is_travelling


func stop_travel() -> void:
	_logger.info("CTRL", "STOP_TRAVEL", {
		"pos": global_position,
		"had_path": _global_path.size(),
	})
	_global_path = PackedVector3Array()
	_path_index = 0
	_is_travelling = false
	_cached_avoidance_blocked = false
	_local_astar_follow_global_on_fail = false
	_surface_escape_cooldown = 0.0
	_green_corridor_direction = Vector3.ZERO
	_green_corridor_timer = 0.0
	_steering.reset()
	_stuck.reset_for_idle(global_position)
	_clear_local_avoidance_path()
	_clear_stuck_escape()
	velocity = Vector3.ZERO
	_debug.clear_global_path()
	_debug.clear_target_marker()
	_debug.clear_avoidance()


func is_travelling() -> bool:
	return _is_travelling


func set_debug_visualization_enabled(enabled: bool) -> void:
	debug_draw_avoidance = enabled
	debug_draw_surface_cells = enabled
	debug_draw_physics_hits = enabled
	debug_draw_cell_heights = enabled
	show_global_path = enabled

	if _config != null:
		_config.debug_draw_avoidance = enabled
		_config.debug_draw_surface_cells = enabled
		_config.debug_draw_physics_hits = enabled
		_config.debug_draw_cell_heights = enabled
		_config.show_global_path = enabled

	if _debug == null:
		return
	if enabled:
		_debug.update_global_path(_global_path, _path_index)
		_debug.update_target_marker(_target_position, _is_travelling)
		return

	_debug_live_scan_cells = []
	_debug_live_scan_physics_hits = []
	_debug.clear_avoidance()
	_debug.clear_global_path()
	_debug.clear_target_marker()


func enter_keyboard_control_mode(follow_camera: bool = true) -> void:
	keyboard_control_enabled = true
	_is_travelling = false
	_global_path = PackedVector3Array()
	_path_index = 0
	_keyboard_jump_was_pressed = false
	_cached_avoidance_blocked = false
	_local_astar_follow_global_on_fail = false
	_clear_local_avoidance_path()
	_clear_live_debug_scan()
	_debug.clear_target_marker()
	if follow_camera:
		var camera := get_viewport().get_camera_3d()
		if camera != null and camera.has_method("set_follow_target"):
			camera.call("set_follow_target", self)


func exit_keyboard_control_mode() -> void:
	keyboard_control_enabled = false
	_keyboard_jump_was_pressed = false
	_cached_avoidance_blocked = false
	_local_astar_follow_global_on_fail = false
	velocity.x = 0.0
	velocity.z = 0.0
	_steering.reset()
	_clear_local_avoidance_path()
	_clear_live_debug_scan()
	_clear_stuck_escape()
	_debug.clear_avoidance()
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.has_method("clear_follow_target"):
		camera.call("clear_follow_target")


# ========================================================================
# Physics tick
# ========================================================================

func _physics_process(delta: float) -> void:
	_logger.tick(delta)
	_jump.update_timers(delta, is_on_floor())
	_tick_surface_escape(delta)

	if keyboard_control_enabled:
		_physics_process_keyboard_control(delta)
		return

	_tick_stuck_detection(delta)

	if not _is_travelling:
		_clear_live_debug_scan()
		_debug.clear_avoidance()
		_apply_idle_gravity(delta)
		move_and_slide()
		return

	if _path_index >= _global_path.size():
		_clear_live_debug_scan()
		_debug.clear_avoidance()
		_stop_at_target()
		_apply_idle_gravity(delta)
		move_and_slide()
		return

	if not _advance_path_progress():
		_clear_live_debug_scan()
		_debug.clear_avoidance()
		_stop_at_target()
		_apply_idle_gravity(delta)
		move_and_slide()
		return

	var move_target := _global_path[_path_index] if _should_follow_waypoint_directly(_path_index) \
			else SteeringController.blend_corner(_global_path, _path_index,
					global_position, _config.corner_blend_distance, _config.corner_blend_strength)
	var direction := move_target - global_position
	direction.y = 0.0

	if direction.length_squared() > 0.0001:
		var desired_direction := direction.normalized()
		var steered_direction := _choose_steered_direction(desired_direction, delta)
		var final_direction := _steering.smooth(steered_direction, desired_direction,
				delta, _config.steering_smoothing)

		var final_speed := _config.move_speed
		if _cached_avoidance_blocked:
			final_speed *= _config.avoidance_slowdown_factor

		velocity.x = final_direction.x * final_speed
		velocity.z = final_direction.z * final_speed

		# Jump uses DIRECT-TO-WAYPOINT direction so the ray faces the obstacle
		# regardless of how avoidance is steering.
		var allow_low_step := _should_allow_low_step_to_walkable(desired_direction)
		if _can_try_auto_jump(desired_direction, steered_direction, allow_low_step) \
				and _jump.try_jump(desired_direction, is_on_floor(), allow_low_step):
			# Cancel avoidance so the citizen flies straight over what was
			# just cleared, instead of being rerouted mid-air.
			_clear_local_avoidance_path()
			_green_corridor_direction = Vector3.ZERO
			_green_corridor_timer = 0.0
			_cached_avoidance_blocked = false
			_obstacle_check_timer = _config.jump_cooldown

		look_at(global_position + final_direction, Vector3.UP)
		_draw_debug(desired_direction, final_direction)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_steering.reset()
		_clear_live_debug_scan()
		_debug.clear_avoidance()

	_apply_idle_gravity(delta)
	move_and_slide()


func _physics_process_keyboard_control(delta: float) -> void:
	if _is_travelling:
		_global_path = PackedVector3Array()
		_path_index = 0
		_is_travelling = false
		_debug.clear_global_path()
		_clear_local_avoidance_path()
		_local_astar_follow_global_on_fail = false
		_surface_escape_cooldown = 0.0
		_clear_stuck_escape()

	var desired_direction := _get_keyboard_control_direction()
	if desired_direction.length_squared() <= 0.0001:
		velocity.x = 0.0
		velocity.z = 0.0
		_cached_avoidance_blocked = false
		_debug_avoidance_status = "manual idle"
		_update_live_debug_scan(_manual_last_direction, delta)
		_draw_debug(_manual_last_direction, _manual_last_direction)
		_apply_idle_gravity(delta)
		move_and_slide()
		return

	_manual_last_direction = desired_direction
	var steered_direction := desired_direction
	if keyboard_control_use_green_corridor:
		steered_direction = _choose_keyboard_steered_direction(desired_direction, delta)
	else:
		_cached_avoidance_blocked = false
		_debug_avoidance_status = "manual"
		_update_live_debug_scan(desired_direction, delta)

	var final_direction := _steering.smooth(steered_direction, desired_direction,
			delta, _config.steering_smoothing)
	var final_speed := _config.move_speed * maxf(keyboard_control_speed_multiplier, 0.0)
	if _cached_avoidance_blocked:
		final_speed *= _config.avoidance_slowdown_factor
	velocity.x = final_direction.x * final_speed
	velocity.z = final_direction.z * final_speed

	_try_keyboard_jump(desired_direction, steered_direction)

	if final_direction.length_squared() > 0.0001:
		look_at(global_position + final_direction, Vector3.UP)
	_draw_debug(desired_direction, final_direction)
	_apply_idle_gravity(delta)
	move_and_slide()


func _get_keyboard_control_direction() -> Vector3:
	var side := 0.0
	var forward_amount := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		side -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		side += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		forward_amount += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		forward_amount -= 1.0
	if absf(side) <= 0.001 and absf(forward_amount) <= 0.001:
		return Vector3.ZERO

	var basis_forward := Vector3.FORWARD
	var basis_right := Vector3.RIGHT
	if keyboard_control_camera_relative:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			basis_forward = -camera.global_transform.basis.z
			basis_forward.y = 0.0
			if basis_forward.length_squared() > 0.0001:
				basis_forward = basis_forward.normalized()
			basis_right = camera.global_transform.basis.x
			basis_right.y = 0.0
			if basis_right.length_squared() > 0.0001:
				basis_right = basis_right.normalized()

	var direction := basis_right * side + basis_forward * forward_amount
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return Vector3.ZERO
	return direction.normalized()


func _choose_keyboard_steered_direction(desired_direction: Vector3, delta: float) -> Vector3:
	_green_corridor_timer = maxf(_green_corridor_timer - delta, 0.0)
	_update_live_debug_scan(desired_direction, delta)
	if _debug_live_scan_cells.is_empty():
		_cached_avoidance_blocked = false
		_debug_avoidance_status = "manual"
		return desired_direction

	var surface_kind := _perception.get_surface_kind(global_position)
	var too_close := _perception.is_too_close_to_road(desired_direction)
	var corridor_dir := _pick_green_corridor_direction(desired_direction, surface_kind, too_close)
	if corridor_dir != Vector3.ZERO:
		_green_corridor_direction = corridor_dir
		_green_corridor_timer = maxf(_config.obstacle_check_interval, 0.08)
		_cached_avoidance_blocked = true
		_debug_avoidance_status = "%s corridor" % _last_corridor_kind
		return corridor_dir

	_green_corridor_direction = Vector3.ZERO
	_green_corridor_timer = 0.0
	_cached_avoidance_blocked = false
	_debug_avoidance_status = "manual"
	return desired_direction


func _try_keyboard_jump(desired_direction: Vector3, steered_direction: Vector3) -> void:
	if keyboard_control_disable_jump:
		_keyboard_jump_was_pressed = false
		return
	var pressed := Input.is_key_pressed(KEY_SPACE)
	if not pressed:
		_keyboard_jump_was_pressed = false
		return
	if _keyboard_jump_was_pressed:
		return
	_keyboard_jump_was_pressed = true
	if not is_on_floor():
		return

	var jump_direction := steered_direction
	jump_direction.y = 0.0
	if jump_direction.length_squared() <= 0.0001:
		jump_direction = desired_direction
		jump_direction.y = 0.0
	if jump_direction.length_squared() <= 0.0001:
		jump_direction = _manual_last_direction
		jump_direction.y = 0.0
	var allow_low_step := _should_allow_low_step_to_walkable(jump_direction)
	if jump_direction.length_squared() > 0.0001 \
			and _can_try_auto_jump(desired_direction, jump_direction, allow_low_step) \
			and _jump.try_jump(jump_direction.normalized(), is_on_floor(), allow_low_step):
		return

	velocity.y = maxf(_config.jump_velocity, 0.0)
	_logger.info("JUMP", "MANUAL", {
		"velocity": velocity.y,
		"pos": global_position,
	})


func _can_try_auto_jump(desired_direction: Vector3, steered_direction: Vector3,
		allow_low_step: bool = false) -> bool:
	if not _config.jump_low_obstacles:
		return false
	var desired := desired_direction
	desired.y = 0.0
	var steered := steered_direction
	steered.y = 0.0
	if desired.length_squared() <= 0.0001 or steered.length_squared() <= 0.0001:
		return false
	var on_road := _perception != null \
			and _perception.get_surface_kind(global_position) == SurfaceClassifier.KIND_ROAD
	if _debug_avoidance_status.ends_with("corridor") \
			or _debug_avoidance_status == "local path" \
			or _debug_avoidance_status == "road edge" \
			or _green_corridor_timer > 0.0:
		return allow_low_step
	if on_road and not allow_low_step:
		return false
	return true


func _is_direction_leaving_road(direction: Vector3) -> bool:
	if _perception == null:
		return false
	if _perception.get_surface_kind(global_position) != SurfaceClassifier.KIND_ROAD:
		return false
	var planar := direction
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		return false
	planar = planar.normalized()

	var base_dist := maxf(_config.jump_probe_distance,
			maxf(_config.local_astar_forward_road_check_distance, 0.35))
	for dist in [base_dist, base_dist * 1.6, base_dist + _config.local_astar_road_proximity_margin]:
		var sample_kind := _perception.get_surface_kind(global_position + planar * float(dist))
		if _is_walkable_exit_surface_kind(sample_kind):
			return true
	return false


func _should_allow_low_step_to_walkable(direction: Vector3) -> bool:
	if _perception == null:
		return false
	var planar := direction
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		return false
	planar = planar.normalized()

	if _is_direction_leaving_road(planar):
		return true

	var current_kind := _perception.get_surface_kind(global_position)
	var graph_kind := _get_pedestrian_graph_kind(global_position)
	if not _is_walkable_exit_surface_kind(current_kind) \
			and not _is_walkable_exit_surface_kind(graph_kind):
		return false
	if not _is_pedestrian_edge_route_context():
		return false
	if _is_pedestrian_edge_kind(graph_kind):
		return true

	var near_road_margin := maxf(_config.local_astar_road_proximity_margin + 0.15, 0.35)
	if not _perception.is_point_near_road(global_position, near_road_margin):
		return false
	return true


func _is_pedestrian_edge_route_context() -> bool:
	if _global_path.is_empty():
		return false
	if _is_pedestrian_edge_kind(_get_pedestrian_graph_kind(global_position)):
		return true

	var first_index := maxi(_path_index - 1, 0)
	var last_index := mini(_path_index + 2, _global_path.size() - 1)
	for index in range(first_index, last_index + 1):
		if _is_pedestrian_edge_kind(_get_pedestrian_graph_kind(_global_path[index])):
			return true
	return false


func _should_follow_waypoint_directly(index: int) -> bool:
	if _is_crosswalk_path_context(index):
		return true
	for candidate_index in [index - 1, index, index + 1]:
		var candidate := int(candidate_index)
		if candidate < 0 or candidate >= _global_path.size():
			continue
		if _is_pedestrian_edge_kind(_get_pedestrian_graph_kind(_global_path[candidate])):
			return true
	return false


func _is_pedestrian_edge_kind(kind: String) -> bool:
	return kind == "boundary" \
			or kind == "corner" \
			or kind == "access" \
			or kind.begins_with("crosswalk")


func _is_walkable_exit_surface_kind(kind: String) -> bool:
	if kind == SurfaceClassifier.KIND_PEDESTRIAN or kind == SurfaceClassifier.KIND_CROSSWALK:
		return true
	return kind == "boundary" \
			or kind == "corner" \
			or kind == "access" \
			or kind.begins_with("crosswalk")


# ========================================================================
# Steering choice (perception → local grid → fallback)
# ========================================================================

## Returns the direction the citizen should actually move this frame.
## Runs the forward probe on a timer, triggers local-grid replans when
## blocked, and falls back to the global path direction when the grid gives
## up.  All transitions are logged so the reason for any heading change is
## recoverable from the log.
func _choose_steered_direction(desired_direction: Vector3, delta: float) -> Vector3:
	var escape_direction := _get_stuck_escape_direction(desired_direction)
	if escape_direction != Vector3.ZERO:
		_cached_avoidance_blocked = true
		_debug_avoidance_status = "stuck escape"
		return escape_direction

	if not _config.use_local_astar_avoidance:
		_cached_avoidance_blocked = false
		_clear_local_avoidance_path()
		return desired_direction

	_local_astar_replan_timer -= delta
	_green_corridor_timer = maxf(_green_corridor_timer - delta, 0.0)
	_update_live_debug_scan(desired_direction, delta)

	# Follow active local detour if one exists.
	if not _local_avoidance_path.is_empty():
		var local_dir := _consume_local_avoidance_path()
		if local_dir != Vector3.ZERO:
			_cached_avoidance_blocked = true
			_debug_avoidance_status = "local path"
			return local_dir

	# Forward perception probe (timed).
	_obstacle_check_timer -= delta
	if _obstacle_check_timer <= 0.0:
		_obstacle_check_timer = _config.obstacle_check_interval
		var surface_kind := _perception.get_surface_kind(global_position)
		var trust_pedestrian_graph := _should_suppress_road_buffer_for_graph(surface_kind)
		var too_close := _perception.is_too_close_to_road(desired_direction) \
				and not trust_pedestrian_graph
		var was_blocked := _cached_avoidance_blocked
		_cached_avoidance_blocked = _perception.is_path_ahead_blocked(desired_direction, _config.jump_low_obstacles) \
				or _should_escape_surface(surface_kind) \
				or too_close
		var corridor_dir := Vector3.ZERO
		if not trust_pedestrian_graph:
			corridor_dir = _pick_green_corridor_direction(desired_direction, surface_kind, too_close)
		if corridor_dir != Vector3.ZERO:
			_green_corridor_direction = corridor_dir
			_green_corridor_timer = maxf(_config.obstacle_check_interval, 0.08)
			_cached_avoidance_blocked = true
			_debug_avoidance_status = "%s corridor" % _last_corridor_kind
			if not was_blocked:
				_logger.debug("CTRL", "%s_CORRIDOR_PICK" % _last_corridor_kind.to_upper(), {
					"surface": surface_kind,
					"road_edge": too_close,
					"pos": global_position,
					"dir": corridor_dir,
				})
		else:
			_green_corridor_direction = Vector3.ZERO
			_green_corridor_timer = 0.0
		if too_close:
			_debug_avoidance_status = "road edge"
		elif _green_corridor_timer <= 0.0:
			_debug_avoidance_status = "blocked" if _cached_avoidance_blocked else "clear"
		if _cached_avoidance_blocked and not was_blocked:
			_logger.debug("CTRL", "AVOIDANCE_BLOCKED", {
				"surface": surface_kind,
				"road_edge": too_close,
				"y": global_position.y,
				"pos": global_position,
				"dir": desired_direction,
			})
		elif not _cached_avoidance_blocked and was_blocked:
			_logger.debug("CTRL", "AVOIDANCE_CLEAR", {
				"pos": global_position,
				"dir": desired_direction,
			})

	if _green_corridor_timer > 0.0 and _green_corridor_direction != Vector3.ZERO:
		_cached_avoidance_blocked = true
		_debug_avoidance_status = "%s corridor" % _last_corridor_kind
		return _green_corridor_direction

	if _cached_avoidance_blocked and _local_astar_replan_timer <= 0.0:
		_local_astar_replan_timer = maxf(_config.local_astar_replan_interval, 0.02)
		var result := _local_grid.build_detour(desired_direction,
				_global_path, _path_index, _target_position)
		_apply_local_grid_result(result)
		var picked := _consume_local_avoidance_path()
		if picked != Vector3.ZERO:
			_cached_avoidance_blocked = true
			_debug_avoidance_status = "local path"
			return picked
		if _local_astar_follow_global_on_fail:
			_cached_avoidance_blocked = false
			_debug_avoidance_status = "global fallback"
			_logger.warn("CTRL", "AVOIDANCE_FALLBACK_GLOBAL", {
				"pos": global_position,
				"dir": desired_direction,
				"cooldown": _surface_escape_cooldown,
			})
	elif not _cached_avoidance_blocked:
		_clear_local_avoidance_path()

	return desired_direction


func _apply_local_grid_result(result: Dictionary) -> void:
	_local_avoidance_path = result.get(LocalGridPlanner.RESULT_KEY_PATH, PackedVector3Array())
	_local_avoidance_path_index = 0
	_debug_local_grid_status = str(result.get(LocalGridPlanner.RESULT_KEY_STATUS, "-"))
	_debug_local_grid_goal = result.get(LocalGridPlanner.RESULT_KEY_GOAL, Vector3.ZERO) as Vector3
	_debug_local_grid_has_goal = bool(result.get(LocalGridPlanner.RESULT_KEY_SUCCESS, false))
	_debug_local_grid_cells = result.get(LocalGridPlanner.RESULT_KEY_DEBUG_CELLS, [])
	_debug_local_grid_physics_hits = result.get(LocalGridPlanner.RESULT_KEY_DEBUG_HITS, [])
	_local_astar_follow_global_on_fail = bool(result.get(LocalGridPlanner.RESULT_KEY_FOLLOW_GLOBAL, false))
	var extra_cooldown: float = result.get(LocalGridPlanner.RESULT_KEY_SURFACE_ESCAPE, 0.0)
	if extra_cooldown > 0.0:
		_surface_escape_cooldown = maxf(_surface_escape_cooldown, extra_cooldown)
	# Failed replans get a longer cooldown so the citizen does not re-enter
	# `build_detour` 5 times per second on the same blocked corridor.
	var success := bool(result.get(LocalGridPlanner.RESULT_KEY_SUCCESS, false))
	if not success or _local_astar_follow_global_on_fail:
		var fallback_cooldown: float = maxf(_config.local_astar_fallback_replan_cooldown,
				_config.local_astar_replan_interval)
		_local_astar_replan_timer = maxf(_local_astar_replan_timer, fallback_cooldown)


func _consume_local_avoidance_path() -> Vector3:
	while _local_avoidance_path_index < _local_avoidance_path.size():
		var target := _local_avoidance_path[_local_avoidance_path_index]
		var to_target := target - global_position
		to_target.y = 0.0
		if to_target.length() > maxf(_config.local_astar_goal_reach_distance, 0.04):
			return to_target.normalized()
		_local_avoidance_path_index += 1
	_clear_local_avoidance_path()
	# Force immediate re-probe instead of re-triggering the old plan.
	_cached_avoidance_blocked = false
	_obstacle_check_timer = 0.0
	return Vector3.ZERO


func _clear_local_avoidance_path() -> void:
	_local_avoidance_path = PackedVector3Array()
	_local_avoidance_path_index = 0
	_debug_local_grid_goal = Vector3.ZERO
	_debug_local_grid_has_goal = false
	_debug_local_grid_cells = []
	_debug_local_grid_physics_hits = []
	if _debug_local_grid_status != "planning":
		_debug_local_grid_status = "-"


func _clear_live_debug_scan() -> void:
	_debug_live_scan_cells = []
	_debug_live_scan_physics_hits = []
	_debug_live_scan_timer = 0.0
	_green_corridor_direction = Vector3.ZERO
	_green_corridor_timer = 0.0


func _update_live_debug_scan(forward: Vector3, delta: float) -> void:
	if not _config.use_local_astar_avoidance:
		_clear_live_debug_scan()
		return
	if not _config.debug_draw_avoidance \
			and not (keyboard_control_enabled and keyboard_control_use_green_corridor):
		_clear_live_debug_scan()
		return
	if forward.length_squared() <= 0.0001:
		_clear_live_debug_scan()
		return

	_debug_live_scan_timer -= delta
	if _debug_live_scan_timer > 0.0 and not _debug_live_scan_cells.is_empty():
		return

	_debug_live_scan_timer = maxf(minf(_config.obstacle_check_interval, 0.15), 0.05)
	var height_threshold := _config.local_astar_height_block_threshold
	if height_threshold <= 0.0:
		height_threshold = _LIVE_SCAN_STEP_HEIGHT
	var probe_radius := _config.local_astar_height_clearance_probe_radius
	var result := _local_grid.scan_at(
			global_position,
			forward,
			_config.local_astar_radius,
			_config.local_astar_cell_size,
			true,
			height_threshold,
			probe_radius)
	_debug_live_scan_cells = result.get(LocalGridPlanner.RESULT_KEY_DEBUG_CELLS, [])
	_debug_live_scan_physics_hits = result.get(LocalGridPlanner.RESULT_KEY_DEBUG_HITS, [])


func _pick_green_corridor_direction(desired_direction: Vector3, _surface_kind: String,
		_too_close_to_road: bool) -> Vector3:
	_last_corridor_kind = ""
	if _debug_live_scan_cells.is_empty():
		return Vector3.ZERO

	var forward := desired_direction
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.ZERO
	forward = forward.normalized()
	var right := LocalPerception._planar_right(forward)
	var origin := global_position
	var cell_size := maxf(_config.local_astar_cell_size, 0.08)
	var lane_width := maxf(cell_size * 0.9, 0.18)
	var lookahead := maxf(_config.local_astar_radius * 0.75, cell_size * 2.0)
	var direct_lane_blocked := false
	var direct_lane_road := false
	var first_direct_block_forward := 1000000.0

	for cell_data in _debug_live_scan_cells:
		var world_pos: Vector3 = cell_data.get("world_pos", Vector3.ZERO) as Vector3
		var offset := world_pos - origin
		offset.y = 0.0
		var forward_dist := offset.dot(forward)
		if forward_dist < 0.0 or forward_dist > lookahead:
			continue
		var lateral_dist := absf(offset.dot(right))
		if lateral_dist > lane_width:
			continue
		var blocked := bool(cell_data.get("blocked", false))
		var reason := str(cell_data.get("blocked_reason", ""))
		var surface := str(cell_data.get("surface", ""))
		if blocked:
			direct_lane_blocked = true
			first_direct_block_forward = minf(first_direct_block_forward, forward_dist)
		if surface == SurfaceClassifier.KIND_ROAD or reason.contains("road"):
			direct_lane_road = true

	var needs_corridor := direct_lane_blocked \
			or direct_lane_road
	if not needs_corridor:
		return Vector3.ZERO

	var green_direction := _pick_corridor_candidate(
			desired_direction, forward, right, origin, cell_size, lane_width,
			first_direct_block_forward, direct_lane_blocked, direct_lane_road, false)
	if green_direction != Vector3.ZERO:
		_last_corridor_kind = "green"
		return green_direction

	var orange_direction := _pick_corridor_candidate(
			desired_direction, forward, right, origin, cell_size, lane_width,
			first_direct_block_forward, direct_lane_blocked, direct_lane_road, true)
	if orange_direction != Vector3.ZERO:
		_last_corridor_kind = "orange"
		return orange_direction
	return Vector3.ZERO


func _pick_corridor_candidate(
		_desired_direction: Vector3,
		forward: Vector3,
		right: Vector3,
		origin: Vector3,
		cell_size: float,
		lane_width: float,
		first_direct_block_forward: float,
		direct_lane_blocked: bool,
		direct_lane_road: bool,
		allow_orange_fallback: bool) -> Vector3:
	var best_score := -1000000.0
	var best_direction := Vector3.ZERO
	for cell_data in _debug_live_scan_cells:
		var blocked := bool(cell_data.get("blocked", false))
		if allow_orange_fallback:
			if not _is_orange_corridor_cell(cell_data):
				continue
		elif blocked:
			continue
		var surface := str(cell_data.get("surface", ""))
		if surface == SurfaceClassifier.KIND_ROAD:
			continue
		var world_pos: Vector3 = cell_data.get("world_pos", Vector3.ZERO) as Vector3
		var offset := world_pos - origin
		offset.y = 0.0
		var distance := offset.length()
		if distance < cell_size * 0.45:
			continue
		var forward_dist := offset.dot(forward)
		if forward_dist < -cell_size * 0.25:
			continue
		var lateral_dist := absf(offset.dot(right))
		var near_road := bool(cell_data.get("near_road_buffer", false)) \
				or bool(cell_data.get("physics_near_road", false))
		var score := forward_dist * 1.15 - lateral_dist * 0.18 + distance * 0.08
		if surface == SurfaceClassifier.KIND_PEDESTRIAN:
			score += 3.0
		elif surface == SurfaceClassifier.KIND_CROSSWALK:
			score += 2.4
		elif surface == SurfaceClassifier.KIND_UNKNOWN:
			score += 0.5
		if near_road:
			score -= 0.6 if allow_orange_fallback else 2.4
		if allow_orange_fallback:
			score -= 0.8
		if direct_lane_blocked and forward_dist >= first_direct_block_forward - cell_size \
				and lateral_dist < lane_width * 0.65:
			score -= 4.0
		if direct_lane_road and lateral_dist < lane_width * 0.65:
			score -= 2.0
		if score > best_score:
			best_score = score
			best_direction = offset.normalized()

	if best_direction == Vector3.ZERO:
		return Vector3.ZERO
	# A corridor correction may bend around a blocker, but it must still move
	# materially toward the current global waypoint. Pure sideways road escape
	# stays with LocalGridPlanner, which has path context and stuck recovery.
	if best_direction.dot(forward) < 0.25:
		return Vector3.ZERO
	return best_direction


func _should_suppress_road_buffer_for_graph(surface_kind: String) -> bool:
	if surface_kind == SurfaceClassifier.KIND_ROAD:
		return false
	if not _is_walkable_exit_surface_kind(surface_kind):
		return false
	return _is_pedestrian_edge_route_context()


func _is_orange_corridor_cell(cell_data: Dictionary) -> bool:
	var reason := str(cell_data.get("blocked_reason", ""))
	if reason != "road_buffer":
		return false
	if bool(cell_data.get("physics_blocked", false)):
		return false
	if bool(cell_data.get("height_blocked", false)):
		return false
	if bool(cell_data.get("surface_blocked", false)):
		return false
	return str(cell_data.get("surface", "")) != SurfaceClassifier.KIND_ROAD


func _should_escape_surface(surface_kind: String) -> bool:
	var on_road := surface_kind == SurfaceClassifier.KIND_ROAD
	# The cooldown is meant to prevent escape-spam when the citizen is just
	# NEAR a road edge. When the citizen is ACTUALLY on the road, the cooldown
	# would freeze him there for 2 s — fix priority: on-road escape always
	# fires.
	if not on_road and _surface_escape_cooldown > 0.0:
		return false
	if _jump.is_cooling_down():
		return false
	if not _config.local_astar_avoid_road_cells:
		return false
	return on_road


# ========================================================================
# Path progress (waypoint advance / pass / arrival)
# ========================================================================

func _advance_path_progress() -> bool:
	var old_index := _path_index
	while _path_index < _global_path.size():
		if not _is_at_path_index(_path_index) \
				and not _has_passed_path_index(_path_index) \
				and not _is_already_on_next_segment(_path_index):
			break
		_path_index += 1
		_reset_path_following_state_for_next_waypoint()
	if _path_index != old_index:
		_logger.debug("CTRL", "WAYPOINT_ADVANCE", {
			"old": old_index,
			"new": _path_index,
			"total": _global_path.size(),
			"pos": global_position,
		})
		_debug.update_global_path(_global_path, _path_index)
	return _path_index < _global_path.size()


func _reset_path_following_state_for_next_waypoint() -> void:
	_cached_avoidance_blocked = false
	_local_astar_replan_timer = 0.0
	_obstacle_check_timer = 0.0
	_local_astar_follow_global_on_fail = false
	_clear_local_avoidance_path()
	_clear_stuck_escape()


func _is_at_path_index(index: int) -> bool:
	if index < 0 or index >= _global_path.size():
		return false
	return _planar_distance(global_position, _global_path[index]) <= _get_path_reach_distance(index)


func _has_passed_path_index(index: int) -> bool:
	if index <= 0 or index >= _global_path.size() - 1:
		return false
	var previous := _global_path[index - 1]
	var waypoint := _global_path[index]
	var segment := waypoint - previous
	segment.y = 0.0
	var seg_len_sq := segment.length_squared()
	if seg_len_sq <= 0.0001:
		return false
	var to_pos := global_position - previous
	to_pos.y = 0.0
	var progress := to_pos.dot(segment) / seg_len_sq
	if progress < 1.0:
		return false
	var pass_distance := maxf(_config.waypoint_pass_distance, _get_path_reach_distance(index))
	return _planar_distance(global_position, waypoint) <= pass_distance


func _is_already_on_next_segment(index: int) -> bool:
	if index <= 0 or index >= _global_path.size() - 1:
		return false
	if _get_pedestrian_graph_kind(_global_path[index]).begins_with("crosswalk"):
		return false
	var waypoint := _global_path[index]
	var next := _global_path[index + 1]
	var segment := next - waypoint
	segment.y = 0.0
	var seg_len_sq := segment.length_squared()
	if seg_len_sq <= 0.0001:
		return false
	var to_pos := global_position - waypoint
	to_pos.y = 0.0
	var progress := to_pos.dot(segment) / seg_len_sq
	if progress <= 0.03:
		return false
	var lateral_distance := _planar_distance_to_segment(global_position, waypoint, next)
	var corridor_width := maxf(_config.waypoint_reach_distance, _config.waypoint_pass_distance * 0.5)
	return lateral_distance <= corridor_width


func _get_path_reach_distance(index: int) -> float:
	if index >= _global_path.size() - 1:
		return maxf(_config.final_waypoint_reach_distance,
				minf(_config.waypoint_reach_distance, 0.35))
	return maxf(_config.waypoint_reach_distance, 0.02)


func _is_crosswalk_path_context(index: int) -> bool:
	if index < 0 or index >= _global_path.size():
		return false
	for candidate_index in [index - 1, index, index + 1]:
		var candidate := int(candidate_index)
		if candidate < 0 or candidate >= _global_path.size():
			continue
		var kind := _get_pedestrian_graph_kind(_global_path[candidate])
		if kind.begins_with("crosswalk"):
			return true
	return false


func _stop_at_target() -> void:
	var was_travelling := _is_travelling
	_is_travelling = false
	_cached_avoidance_blocked = false
	_steering.reset()
	_stuck.reset_for_idle(global_position)
	_clear_stuck_escape()
	velocity.x = 0.0
	velocity.z = 0.0
	if _config.clear_global_path_on_arrival:
		_debug.clear_global_path()
	_debug.clear_target_marker()
	_debug.clear_avoidance()
	if was_travelling:
		_logger.info("CTRL", "ARRIVED", {
			"pos": global_position,
			"target": _target_position,
		})
		target_reached.emit()


# ========================================================================
# Stuck recovery
# ========================================================================

func _tick_stuck_detection(delta: float) -> void:
	if not _is_travelling:
		_stuck.reset_for_idle(global_position)
		return
	var dist_to_target := _planar_distance(global_position, _target_position)
	# Pass status strings directly — no per-frame dict allocation. StuckRecovery
	# builds a log dict only when a stuck event actually fires.
	var action := _stuck.tick(delta, global_position, dist_to_target,
			_debug_avoidance_status,
			_debug_local_grid_status,
			_jump.status())
	match action:
		StuckRecovery.ACTION_REPLAN:
			var recovered_locally := _try_stuck_escape_recovery(false)
			if recovered_locally:
				_stuck.reset_for_new_target(global_position)
			else:
				var replan_ok := _try_replan_from_stuck()
				if replan_ok and _is_travelling:
					_stuck.reset_for_new_target(global_position)
		StuckRecovery.ACTION_ABORT:
			var started_escape := _try_stuck_escape_recovery(true)
			if started_escape and _is_travelling:
				_logger.warn("CTRL", "STUCK_EXHAUSTED_ESCAPE", {
					"pos": global_position,
					"target": _target_position,
					"escape_target": _stuck_escape_target,
					"path_index": _path_index,
				})
				_stuck.reset_for_new_target(global_position)
			elif not _is_travelling:
				return
			else:
				var abort_replan_ok := _try_replan_from_stuck()
				if abort_replan_ok and _is_travelling:
					_stuck.reset_for_new_target(global_position)
				else:
					_logger.error("CTRL", "STUCK_FINAL", {
						"pos": global_position,
						"target": _target_position,
					})
					stop_travel()
					stuck.emit()


func _try_stuck_escape_recovery(strong: bool) -> bool:
	if _try_finish_stuck_near_target():
		return true
	var skipped := _try_skip_stuck_waypoint()
	var started := _begin_stuck_escape(strong)
	if skipped or started:
		_logger.warn("CTRL", "STUCK_ESCAPE_RECOVERY", {
			"pos": global_position,
			"target": _target_position,
			"path_index": _path_index,
			"skipped_waypoint": skipped,
			"escape_started": started,
			"strong": strong,
		})
	return skipped or started


func _try_finish_stuck_near_target() -> bool:
	var dist_to_target := _planar_distance(global_position, _target_position)
	var arrival_distance := maxf(_config.stuck_detection_min_distance * 2.0,
			maxf(_config.final_waypoint_reach_distance * 2.0,
					_config.waypoint_pass_distance + 0.1))
	if dist_to_target > arrival_distance:
		return false
	_stop_at_target()
	return true


func _try_skip_stuck_waypoint() -> bool:
	if _global_path.size() < 3:
		return false
	if _path_index <= 0 or _path_index >= _global_path.size() - 1:
		return false
	if _is_crosswalk_path_context(_path_index):
		return false

	var waypoint := _global_path[_path_index]
	var distance := _planar_distance(global_position, waypoint)
	var max_skip_distance := maxf(_config.stuck_escape_waypoint_skip_distance,
			_config.waypoint_pass_distance)
	if distance > max_skip_distance:
		return false

	var old_index := _path_index
	_path_index += 1
	_reset_path_following_state_for_next_waypoint()
	_obstacle_check_timer = 0.0
	_debug.update_global_path(_global_path, _path_index)
	_logger.info("CTRL", "STUCK_SKIP_WAYPOINT", {
		"old": old_index,
		"new": _path_index,
		"distance": distance,
		"pos": global_position,
	})
	return true


func _begin_stuck_escape(strong: bool) -> bool:
	var forward := _get_current_global_planar_direction()
	if forward == Vector3.ZERO:
		return false

	var picked := _pick_stuck_escape_direction(forward, strong)
	if picked == Vector3.ZERO:
		return false

	var distance := maxf(_config.stuck_escape_probe_distance, 0.25)
	if strong:
		distance *= 1.45
	_stuck_escape_direction = picked
	_stuck_escape_target = global_position + picked * distance
	_stuck_escape_timer = maxf(_config.stuck_escape_duration * (1.35 if strong else 1.0), 0.2)
	_stuck_escape_retarget_timer = maxf(_config.stuck_escape_retarget_interval, 0.08)
	_stuck_escape_rejoin_probe_timer = maxf(_config.stuck_escape_rejoin_probe_interval, 0.05)
	_stuck_escape_start_pos = global_position
	_cached_avoidance_blocked = true
	_debug_avoidance_status = "stuck escape"
	_local_astar_replan_timer = maxf(_config.local_astar_fallback_replan_cooldown,
			_config.local_astar_replan_interval)
	_obstacle_check_timer = 0.0
	_steering.reset()
	_clear_local_avoidance_path()
	_logger.info("CTRL", "STUCK_ESCAPE_BEGIN", {
		"pos": global_position,
		"target": _target_position,
		"escape_target": _stuck_escape_target,
		"dir": picked,
		"strong": strong,
	})
	return true


func _get_stuck_escape_direction(desired_direction: Vector3) -> Vector3:
	if _stuck_escape_timer <= 0.0:
		return Vector3.ZERO

	if _is_stuck_escape_ready_to_rejoin(desired_direction):
		_finish_stuck_escape("rejoin")
		return Vector3.ZERO

	var to_escape_target := _stuck_escape_target - global_position
	to_escape_target.y = 0.0
	if to_escape_target.length() <= 0.12 \
			or _stuck_escape_retarget_timer <= 0.0 \
			or _stuck_escape_direction == Vector3.ZERO:
		var picked := _pick_stuck_escape_direction(desired_direction, false)
		if picked != Vector3.ZERO:
			_stuck_escape_direction = picked
			_stuck_escape_target = global_position + picked * maxf(_config.stuck_escape_probe_distance, 0.25)
			_stuck_escape_retarget_timer = maxf(_config.stuck_escape_retarget_interval, 0.08)
			to_escape_target = _stuck_escape_target - global_position
			to_escape_target.y = 0.0
			_logger.debug("CTRL", "STUCK_ESCAPE_RETARGET", {
				"pos": global_position,
				"escape_target": _stuck_escape_target,
				"dir": picked,
			})

	if to_escape_target.length_squared() <= 0.0001:
		return _stuck_escape_direction
	return to_escape_target.normalized()


func _is_stuck_escape_ready_to_rejoin(desired_direction: Vector3) -> bool:
	var moved := _planar_distance(global_position, _stuck_escape_start_pos)
	if moved < maxf(_config.stuck_escape_success_distance, 0.1):
		return false
	if _stuck_escape_rejoin_probe_timer > 0.0:
		return false
	_stuck_escape_rejoin_probe_timer = maxf(_config.stuck_escape_rejoin_probe_interval, 0.05)
	var desired := desired_direction
	desired.y = 0.0
	if desired.length_squared() <= 0.0001:
		return true
	desired = desired.normalized()
	if _perception == null:
		return true
	if _perception.is_path_ahead_blocked(desired, _config.jump_low_obstacles):
		return false
	if _perception.is_too_close_to_road(desired) and not _is_pedestrian_edge_route_context():
		return false
	return true


func _finish_stuck_escape(reason: String) -> void:
	if _stuck_escape_direction == Vector3.ZERO and _stuck_escape_target == Vector3.ZERO:
		return
	_logger.info("CTRL", "STUCK_ESCAPE_END", {
		"reason": reason,
		"pos": global_position,
		"target": _target_position,
		"moved": _planar_distance(global_position, _stuck_escape_start_pos),
	})
	_clear_stuck_escape()
	_obstacle_check_timer = 0.0


func _clear_stuck_escape() -> void:
	_stuck_escape_direction = Vector3.ZERO
	_stuck_escape_target = Vector3.ZERO
	_stuck_escape_timer = 0.0
	_stuck_escape_retarget_timer = 0.0
	_stuck_escape_rejoin_probe_timer = 0.0
	_stuck_escape_start_pos = Vector3.ZERO


func _get_current_global_planar_direction() -> Vector3:
	var direction := Vector3.ZERO
	if _path_index >= 0 and _path_index < _global_path.size():
		direction = _global_path[_path_index] - global_position
	elif _target_position != Vector3.ZERO:
		direction = _target_position - global_position
	else:
		direction = -global_transform.basis.z
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return Vector3.ZERO
	return direction.normalized()


func _pick_stuck_escape_direction(forward: Vector3, strong: bool) -> Vector3:
	var base := forward
	base.y = 0.0
	if base.length_squared() <= 0.0001:
		base = _get_current_global_planar_direction()
	if base.length_squared() <= 0.0001:
		return Vector3.ZERO
	base = base.normalized()

	var right := LocalPerception._planar_right(base)
	var side_sign := 1.0 if randf() >= 0.5 else -1.0
	var candidates: Array[Vector3] = [
		(right * side_sign + base * 0.15).normalized(),
		(-right * side_sign + base * 0.15).normalized(),
		(right * side_sign - base * 0.35).normalized(),
		(-right * side_sign - base * 0.35).normalized(),
		-base,
		base.rotated(Vector3.UP, deg_to_rad(45.0 * side_sign)).normalized(),
		base.rotated(Vector3.UP, deg_to_rad(-45.0 * side_sign)).normalized(),
	]
	if strong:
		candidates.append((right * side_sign - base).normalized())
		candidates.append((-right * side_sign - base).normalized())
		candidates.append(base.rotated(Vector3.UP, randf_range(-PI, PI)).normalized())

	var best := Vector3.ZERO
	var best_score := -INF
	for candidate in candidates:
		var score := _score_stuck_escape_direction(candidate, base, strong)
		if score > best_score:
			best_score = score
			best = candidate
	if best_score <= -900.0:
		return Vector3.ZERO
	return best.normalized()


func _score_stuck_escape_direction(direction: Vector3, forward: Vector3, strong: bool) -> float:
	var candidate := direction
	candidate.y = 0.0
	if candidate.length_squared() <= 0.0001:
		return -INF
	candidate = candidate.normalized()

	var score := randf_range(0.0, 0.12)
	var dot_forward := candidate.dot(forward)
	# Sideways/backward moves are useful here: the citizen is explicitly stuck
	# on the forward plan, so the escape should sample another lane first.
	score += (1.0 - absf(dot_forward)) * 0.8
	if dot_forward < -0.2:
		score += 0.35 if strong else 0.15
	if _perception == null:
		return score

	var sample_distance := maxf(_config.stuck_escape_probe_distance, 0.25)
	var sample_kind := _perception.get_surface_kind(global_position + candidate * sample_distance)
	if _is_walkable_exit_surface_kind(sample_kind):
		score += 2.5
	elif sample_kind == SurfaceClassifier.KIND_ROAD:
		score -= 3.5
	elif sample_kind == SurfaceClassifier.KIND_UNKNOWN:
		score -= 0.4

	if _perception.is_path_ahead_blocked(candidate, _config.jump_low_obstacles):
		score -= 6.0
	if _perception.is_too_close_to_road(candidate) and not _is_pedestrian_edge_route_context():
		score -= 2.0
	return score


func _try_replan_from_stuck() -> bool:
	# Very close to the destination? Just arrive.
	var dist_to_target := _planar_distance(global_position, _target_position)
	if dist_to_target <= maxf(_config.stuck_detection_min_distance * 2.0,
			maxf(_config.final_waypoint_reach_distance * 2.0,
					_config.waypoint_pass_distance + 0.1)):
		_stop_at_target()
		return true
	# Suppress surface-escape for a few seconds so the rebuilt global path can
	# cross a road segment without immediately re-entering escape mode.
	_surface_escape_cooldown = 4.0
	var rebuilt := GlobalPathPlanner.build_path(global_position, _target_position, _ctx)
	if rebuilt.size() < 2:
		_logger.error("CTRL", "STUCK_REPLAN_FAIL", {
			"pos": global_position,
			"target": _target_position,
		})
		stop_travel()
		stuck.emit()
		return false
	_global_path = rebuilt
	_path_index = 0
	_clear_local_avoidance_path()
	_cached_avoidance_blocked = false
	_steering.reset()
	_obstacle_check_timer = 0.0
	_local_astar_replan_timer = 0.0
	_advance_path_progress()
	_debug.update_global_path(_global_path, _path_index)
	_try_local_replan_from_stuck()
	_logger.info("CTRL", "STUCK_REPLAN_OK", {
		"waypoints": _global_path.size(),
		"pos": global_position,
	})
	return true


func _try_local_replan_from_stuck() -> void:
	if not _config.use_local_astar_avoidance:
		return
	if _path_index >= _global_path.size():
		return

	var desired_direction := _global_path[_path_index] - global_position
	desired_direction.y = 0.0
	if desired_direction.length_squared() <= 0.0001:
		return
	desired_direction = desired_direction.normalized()

	_green_corridor_direction = Vector3.ZERO
	_green_corridor_timer = 0.0
	_local_astar_replan_timer = 0.0
	var result := _local_grid.build_detour(desired_direction,
			_global_path, _path_index, _target_position)
	_apply_local_grid_result(result)
	var success := bool(result.get(LocalGridPlanner.RESULT_KEY_SUCCESS, false))
	var path: PackedVector3Array = result.get(LocalGridPlanner.RESULT_KEY_PATH, PackedVector3Array())
	if success and not path.is_empty():
		_cached_avoidance_blocked = true
		_debug_avoidance_status = "local path"
		_local_astar_replan_timer = maxf(_config.local_astar_replan_interval, 0.02)
		_logger.info("CTRL", "STUCK_LOCAL_REPLAN_OK", {
			"status": _debug_local_grid_status,
			"points": path.size(),
			"pos": global_position,
			"dir": desired_direction,
		})
	else:
		_logger.warn("CTRL", "STUCK_LOCAL_REPLAN_FAIL", {
			"status": _debug_local_grid_status,
			"pos": global_position,
			"dir": desired_direction,
		})


# ========================================================================
# Misc helpers
# ========================================================================

func _tick_surface_escape(delta: float) -> void:
	if _surface_escape_cooldown > 0.0:
		_surface_escape_cooldown = maxf(_surface_escape_cooldown - delta, 0.0)
	if _stuck_escape_timer > 0.0:
		_stuck_escape_timer = maxf(_stuck_escape_timer - delta, 0.0)
		_stuck_escape_retarget_timer = maxf(_stuck_escape_retarget_timer - delta, 0.0)
		_stuck_escape_rejoin_probe_timer = maxf(_stuck_escape_rejoin_probe_timer - delta, 0.0)
		if _stuck_escape_timer <= 0.0:
			_finish_stuck_escape("timeout")


func _apply_idle_gravity(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


func _planar_distance(a: Vector3, b: Vector3) -> float:
	var off := a - b
	off.y = 0.0
	return off.length()


func _planar_distance_to_segment(point: Vector3, from: Vector3, to: Vector3) -> float:
	var planar_point := point
	var planar_from := from
	var planar_to := to
	planar_point.y = 0.0
	planar_from.y = 0.0
	planar_to.y = 0.0
	var segment := planar_to - planar_from
	var len_sq := segment.length_squared()
	if len_sq <= 0.0001:
		return planar_point.distance_to(planar_from)
	var t := clampf((planar_point - planar_from).dot(segment) / len_sq, 0.0, 1.0)
	return planar_point.distance_to(planar_from + segment * t)


func _resolve_navigation_target(target: Vector3) -> Vector3:
	var projected := _project_navigation_target_to_ground(target)
	var surface_kind := _get_navigation_surface_kind(projected)
	var graph_kind := _get_pedestrian_graph_kind(projected)
	var access: Variant = _get_pedestrian_access_point(projected)
	var resolved := projected
	var reason := "ground_projection" if target.distance_to(projected) > 0.03 else ""
	var high_hit := absf(target.y - projected.y) > _get_target_ground_y_tolerance()
	var needs_walkable_snap := surface_kind == SurfaceClassifier.KIND_ROAD \
			or (high_hit and not _is_walkable_exit_surface_kind(surface_kind))

	if needs_walkable_snap:
		var nearby_walkable: Variant = _find_nearby_walkable_navigation_target(projected)
		if nearby_walkable is Vector3:
			resolved = nearby_walkable as Vector3
			reason = "nearby_walkable_ground"

	if resolved == projected and access is Vector3:
		var access_point := access as Vector3
		if surface_kind == SurfaceClassifier.KIND_ROAD:
			resolved = access_point
			reason = "road_to_pedestrian_access"
		elif high_hit and not _is_walkable_exit_surface_kind(surface_kind):
			resolved = access_point
			reason = "high_hit_to_pedestrian_access"

	if not reason.is_empty() and _logger != null:
		_logger.info("CTRL", "TARGET_NORMALIZED", {
			"requested": target,
			"projected": projected,
			"resolved": resolved,
			"surface": surface_kind,
			"graph_kind": graph_kind if not graph_kind.is_empty() else "-",
			"reason": reason,
		})
	return resolved


func _find_nearby_walkable_navigation_target(origin: Vector3) -> Variant:
	var best := Vector3.ZERO
	var best_score := INF
	var has_best := false

	for radius in _TARGET_WALKABLE_SEARCH_RADII:
		for direction in _TARGET_WALKABLE_SEARCH_DIRECTIONS:
			var sample_seed := origin + direction * radius
			var sample := _project_navigation_target_to_ground(sample_seed)
			var surface_kind := _get_navigation_surface_kind(sample)
			if not _is_walkable_exit_surface_kind(surface_kind):
				continue

			var score := sample.distance_squared_to(origin)
			var graph_kind := _get_pedestrian_graph_kind(sample)
			if graph_kind == "crosswalk" or graph_kind.begins_with("crosswalk"):
				score -= 0.2
			elif graph_kind == "boundary" or graph_kind == "corner" or graph_kind == "access":
				score -= 0.05

			if not has_best or score < best_score:
				best = sample
				best_score = score
				has_best = true

	if has_best:
		return best
	return null


func _project_navigation_target_to_ground(target: Vector3) -> Vector3:
	if not is_inside_tree() or get_world_3d() == null:
		return target

	var from := target + Vector3.UP * _TARGET_GROUND_PROBE_UP
	var to := target + Vector3.DOWN * _TARGET_GROUND_PROBE_DOWN
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _config.click_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var excludes: Array[RID] = [get_rid()]
	var space := get_world_3d().direct_space_state
	for _attempt in range(_TARGET_GROUND_MAX_HITS):
		query.exclude = excludes
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break

		var collider: Variant = hit.get("collider", null)
		if collider is CharacterBody3D and hit.has("rid"):
			excludes.append(hit["rid"])
			continue

		var hit_pos := hit.get("position", target) as Vector3
		var kind := _classify_navigation_target_hit(hit, hit_pos)
		if _is_walkable_exit_surface_kind(kind) or kind == SurfaceClassifier.KIND_ROAD:
			return hit_pos

		var normal := hit.get("normal", Vector3.UP) as Vector3
		var near_citizen_ground := absf(hit_pos.y - global_position.y) <= _get_target_ground_y_tolerance()
		if normal.dot(Vector3.UP) >= 0.65 and near_citizen_ground:
			return hit_pos

		if not hit.has("rid"):
			break
		excludes.append(hit["rid"])

	var ground_y := _get_world_ground_fallback_y()
	var fallback := target
	fallback.y = ground_y
	return fallback


func _classify_navigation_target_hit(hit: Dictionary, point: Vector3) -> String:
	if _perception != null:
		return _perception.surface_kind_from_hit(hit, point)
	return SurfaceClassifier.classify_hit(hit)


func _get_navigation_surface_kind(point: Vector3) -> String:
	if _perception != null:
		return _perception.get_surface_kind(point)
	return SurfaceClassifier.KIND_UNKNOWN


func _get_pedestrian_graph_kind(point: Vector3) -> String:
	var world := _ctx.get_world_node()
	if world != null and world.has_method("get_pedestrian_path_point_kind"):
		return str(world.get_pedestrian_path_point_kind(point))
	return ""


func _get_pedestrian_access_point(point: Vector3) -> Variant:
	var world := _ctx.get_world_node()
	if world != null and world.has_method("get_pedestrian_access_point"):
		return world.get_pedestrian_access_point(point)
	return null


func _get_world_ground_fallback_y() -> float:
	var world := _ctx.get_world_node()
	if world != null and world.has_method("get_ground_fallback_y"):
		return float(world.get_ground_fallback_y())
	return global_position.y


func _get_target_ground_y_tolerance() -> float:
	return maxf(_config.local_astar_height_block_threshold, _TARGET_GROUND_Y_TOLERANCE)


func _get_click_world_position(screen_pos: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * _config.click_ray_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _config.click_collision_mask
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.get("position", Vector3.ZERO) as Vector3
	var ground_plane := Plane(Vector3.UP, global_position.y)
	return ground_plane.intersects_ray(from, camera.project_ray_normal(screen_pos))


func _draw_debug(desired_direction: Vector3, final_direction: Vector3) -> void:
	if _config == null or not _config.debug_draw_avoidance:
		return
	var debug_cells := _debug_live_scan_cells
	if debug_cells.is_empty():
		debug_cells = _debug_local_grid_cells
	var debug_hits := _debug_live_scan_physics_hits
	if debug_hits.is_empty():
		debug_hits = _debug_local_grid_physics_hits
	_debug.update_avoidance(desired_direction, final_direction,
			_local_avoidance_path, _debug_local_grid_goal, _debug_local_grid_has_goal,
			debug_cells, debug_hits,
			{
				"path": "%d/%d" % [_path_index, _global_path.size() - 1] if not _global_path.is_empty() else "-",
				"avoidance": _debug_avoidance_status,
				"local": _debug_local_grid_status,
				"jump": _jump.status(),
			})


# ========================================================================
# Config / logger bootstrap
# ========================================================================

func _build_config() -> CitizenConfig:
	# Reflexion via CitizenConfig.FIELD_NAMES — replaces a 50-line manual mirror
	# of every @export. Drift between Controller @exports and Config fields is
	# caught at startup by `tools/codex_citizen_config_drift_test.gd`.
	var c := CitizenConfig.new()
	c.populate_from(self)
	return c


func _build_logger() -> CitizenLogger:
	var lg := CitizenLogger.new()
	lg.enabled = enable_file_log
	lg.set_level(log_min_level)
	lg.flush_interval = log_flush_interval
	if enable_file_log:
		lg.open(_resolve_log_path(), name)
	return lg


func _resolve_log_path() -> String:
	if not log_file_path.is_empty():
		return log_file_path
	# Ensure the logs/ directory exists in user://.
	DirAccess.make_dir_recursive_absolute("user://logs")
	return "user://logs/citizen_%s.log" % name
