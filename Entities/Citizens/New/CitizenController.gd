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
@export var local_astar_road_buffer_cells: int = 1
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
@export var local_astar_height_clearance_probe_radius: float = 0.08
@export_flags_3d_physics var local_astar_surface_collision_mask: int = 3
@export var local_astar_surface_probe_up: float = 0.5
@export var local_astar_surface_probe_down: float = 2.2
@export var local_astar_surface_probe_max_hits: int = 8

# ---------------------------------------------------------- Exports: Jump
@export_group("Low Obstacle Jump")
@export var jump_low_obstacles: bool = true
@export_node_path("RayCast3D") var obstacle_down_ray_path: NodePath
@export var max_jump_obstacle_height: float = 0.14
@export var min_jump_obstacle_height: float = 0.005
@export var jump_probe_distance: float = 0.45
@export var jump_velocity: float = 1.8
@export var jump_cooldown: float = 0.35

# ---------------------------------------------------------- Exports: Stuck
@export_group("Stuck Recovery")
@export var stuck_detection_interval: float = 1.5
@export var stuck_detection_min_distance: float = 0.25
@export var stuck_max_recovery_attempts: int = 3

# ---------------------------------------------------------- Exports: Logging
@export_group("Logging")
@export var enable_file_log: bool = true
## Minimum log level: 0=TRACE 1=DEBUG 2=INFO 3=WARN 4=ERROR.
## For single-citizen bug hunting keep at 0. Multi-citizen: raise to 2.
@export_range(0, 4, 1) var log_min_level: int = 0
@export var log_flush_interval: float = 0.25
@export var debug_log_probe_hits: bool = true
## Override log file path. Empty → user://logs/citizen_<name>.log
@export var log_file_path: String = ""

# ---------------------------------------------------------- Exports: Debug
@export_group("Debug Draw")
@export var debug_draw_avoidance: bool = false
@export var debug_draw_surface_cells: bool = true
@export var debug_draw_physics_hits: bool = true
@export var debug_draw_cell_heights: bool = true
@export var show_global_path: bool = true
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
var _manual_last_direction: Vector3 = Vector3.FORWARD

# Surface-escape suppression (set after stuck replan + after no-candidates)
var _surface_escape_cooldown: float = 0.0


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


# ========================================================================
# Public API (unchanged from old citizen_new.gd)
# ========================================================================

func set_global_target(target: Vector3) -> bool:
	_target_position = target
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
	_stuck.reset_for_new_target(global_position)

	if _is_travelling:
		_is_travelling = _advance_path_progress()

	_debug.update_global_path(_global_path, _path_index)

	_logger.info("CTRL", "TARGET_SET", {
		"from": global_position,
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
	velocity = Vector3.ZERO
	_debug.clear_global_path()
	_debug.clear_avoidance()


func is_travelling() -> bool:
	return _is_travelling


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

	var move_target := SteeringController.blend_corner(_global_path, _path_index,
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
		if _jump.try_jump(desired_direction, is_on_floor()):
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

	if not keyboard_control_disable_jump and _can_try_auto_jump(desired_direction, steered_direction):
		_jump.try_jump(steered_direction, is_on_floor())

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
		_debug_avoidance_status = "green corridor"
		return corridor_dir

	_green_corridor_direction = Vector3.ZERO
	_green_corridor_timer = 0.0
	_cached_avoidance_blocked = false
	_debug_avoidance_status = "manual"
	return desired_direction


func _can_try_auto_jump(desired_direction: Vector3, steered_direction: Vector3) -> bool:
	if not _config.jump_low_obstacles:
		return false
	if _debug_avoidance_status == "green corridor" or _green_corridor_timer > 0.0:
		return false
	var desired := desired_direction
	desired.y = 0.0
	var steered := steered_direction
	steered.y = 0.0
	if desired.length_squared() <= 0.0001 or steered.length_squared() <= 0.0001:
		return false
	return true


# ========================================================================
# Steering choice (perception → local grid → fallback)
# ========================================================================

## Returns the direction the citizen should actually move this frame.
## Runs the forward probe on a timer, triggers local-grid replans when
## blocked, and falls back to the global path direction when the grid gives
## up.  All transitions are logged so the reason for any heading change is
## recoverable from the log.
func _choose_steered_direction(desired_direction: Vector3, delta: float) -> Vector3:
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
		var too_close := _perception.is_too_close_to_road(desired_direction)
		var was_blocked := _cached_avoidance_blocked
		_cached_avoidance_blocked = _perception.is_path_ahead_blocked(desired_direction, _config.jump_low_obstacles) \
				or _should_escape_surface(surface_kind) \
				or too_close
		var corridor_dir := _pick_green_corridor_direction(desired_direction, surface_kind, too_close)
		if corridor_dir != Vector3.ZERO:
			_green_corridor_direction = corridor_dir
			_green_corridor_timer = maxf(_config.obstacle_check_interval, 0.08)
			_cached_avoidance_blocked = true
			_debug_avoidance_status = "green corridor"
			if not was_blocked:
				_logger.debug("CTRL", "GREEN_CORRIDOR_PICK", {
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
		_debug_avoidance_status = "green corridor"
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
	if not _config.debug_draw_avoidance:
		_clear_live_debug_scan()
		return
	if not _config.use_local_astar_avoidance:
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
	if probe_radius <= 0.0:
		probe_radius = _LIVE_SCAN_PROBE_RADIUS
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

	var best_score := -1000000.0
	var best_direction := Vector3.ZERO
	for cell_data in _debug_live_scan_cells:
		if bool(cell_data.get("blocked", false)):
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
			score -= 2.4
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
		if not _is_at_path_index(_path_index) and not _has_passed_path_index(_path_index):
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


func _get_path_reach_distance(index: int) -> float:
	if index >= _global_path.size() - 1:
		return maxf(_config.final_waypoint_reach_distance, 0.02)
	return maxf(_config.waypoint_reach_distance, 0.02)


func _stop_at_target() -> void:
	var was_travelling := _is_travelling
	_is_travelling = false
	_cached_avoidance_blocked = false
	_steering.reset()
	_stuck.reset_for_idle(global_position)
	velocity.x = 0.0
	velocity.z = 0.0
	if _config.clear_global_path_on_arrival:
		_debug.clear_global_path()
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
			_try_replan_from_stuck()
		StuckRecovery.ACTION_ABORT:
			_logger.error("CTRL", "STUCK_FINAL", {
				"pos": global_position,
				"target": _target_position,
			})
			stop_travel()
			stuck.emit()


func _try_replan_from_stuck() -> void:
	# Very close to the destination? Just arrive.
	var dist_to_target := _planar_distance(global_position, _target_position)
	if dist_to_target <= maxf(_config.stuck_detection_min_distance * 2.0,
			_config.final_waypoint_reach_distance * 2.0):
		_stop_at_target()
		return
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
		return
	_global_path = rebuilt
	_path_index = 0
	_clear_local_avoidance_path()
	_cached_avoidance_blocked = false
	_steering.reset()
	_obstacle_check_timer = 0.0
	_local_astar_replan_timer = 0.0
	_advance_path_progress()
	_debug.update_global_path(_global_path, _path_index)
	_logger.info("CTRL", "STUCK_REPLAN_OK", {
		"waypoints": _global_path.size(),
		"pos": global_position,
	})


# ========================================================================
# Misc helpers
# ========================================================================

func _tick_surface_escape(delta: float) -> void:
	if _surface_escape_cooldown > 0.0:
		_surface_escape_cooldown = maxf(_surface_escape_cooldown - delta, 0.0)


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
	if (accept_click_input or keyboard_control_enabled) and not c.debug_draw_avoidance:
		c.debug_draw_avoidance = true
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
