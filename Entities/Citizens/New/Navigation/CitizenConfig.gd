class_name CitizenConfig
extends RefCounted

## Plain-data config bag — populated once by the Controller via `populate_from`
## and passed to every navigation module via NavigationContext.
##
## Keeping this as a single struct-like object means modules don't need a
## reference back to the Controller (fewer circular deps) and config snapshots
## are cheap to duplicate for future LOD overrides ("coarse citizens get a
## smaller local grid").
##
## To add a tunable: declare it here, add the field name to `FIELD_NAMES`,
## then add the matching `@export var` in `CitizenController.gd`.
## `tools/codex_citizen_config_drift_test.gd` enforces the matching set.

# Movement
var move_speed: float = 0.5
var waypoint_reach_distance: float = 0.35
var final_waypoint_reach_distance: float = 0.18
var waypoint_pass_distance: float = 0.55
var corner_blend_distance: float = 0.8
var corner_blend_strength: float = 0.45

# Steering
var steering_smoothing: float = 5.0
var avoidance_slowdown_factor: float = 0.65

# Perception (forward probe)
var obstacle_check_interval: float = 0.08

# Local A* grid
var use_local_astar_avoidance: bool = true
var local_astar_radius: float = 1.2
var local_astar_cell_size: float = 0.24
var local_astar_grid_subdivisions: int = 2
var local_astar_probe_radius: float = 0.16
var local_astar_replan_interval: float = 0.18
## Cooldown applied to the replan timer ONLY when the previous replan failed
## (no candidates → fallback to global, or build aborted). Stops the spam
## where a citizen on a narrow walkway near a road triggers ~5 replans/sec
## that all reach the same "all blocked" verdict. Successful replans keep
## the normal `local_astar_replan_interval`.
var local_astar_fallback_replan_cooldown: float = 1.0
var local_astar_goal_reach_distance: float = 0.12
var local_astar_front_row_tolerance: float = 0.24
var local_astar_prefer_right_when_left_open: bool = true
var local_astar_avoid_road_cells: bool = true
var local_astar_near_road_penalty: float = 16.0
var local_astar_road_proximity_margin: float = 0.3
var local_astar_road_buffer_cells: int = 1
var local_astar_forward_road_check_distance: float = 0.28
var local_astar_physics_near_road_margin: float = 0.22
var local_astar_probe_min_height: float = 0.08
var local_astar_probe_max_height: float = 0.9
var local_astar_probe_height_steps: int = 4
## Live-steering hybrid threshold. Matches CoordPicker `_LIVE_SCAN_STEP_HEIGHT`
## so the debug visualization and the planner agree on what counts as a wall
## vs. a step. >0 enables the top-hit + clearance-sphere + wall-buffer pipeline
## inside `build_detour`; 0 falls back to the legacy multi-height sphere stack.
var local_astar_height_block_threshold: float = 0.25
var local_astar_height_clearance_probe_radius: float = 0.08
var local_astar_surface_collision_mask: int = 3
var local_astar_surface_probe_up: float = 0.5
var local_astar_surface_probe_down: float = 2.2
var local_astar_surface_probe_max_hits: int = 8

# Jump
var jump_low_obstacles: bool = true
var max_jump_obstacle_height: float = 0.14
var min_jump_obstacle_height: float = 0.005
var jump_probe_distance: float = 0.45
var jump_velocity: float = 1.8
var jump_cooldown: float = 0.35

# Stuck recovery
var stuck_detection_interval: float = 1.5
var stuck_detection_min_distance: float = 0.25
var stuck_max_recovery_attempts: int = 3

# Click-to-move
var click_ray_distance: float = 1000.0
var ignore_ui_clicks: bool = true
var click_collision_mask: int = 0xFFFFFFFF

# Debug
var debug_draw_avoidance: bool = false
var debug_draw_surface_cells: bool = true
var debug_draw_physics_hits: bool = true
var debug_draw_cell_heights: bool = true
var debug_log_probe_hits: bool = true

# Global path visual
var show_global_path: bool = true
var clear_global_path_on_arrival: bool = false
var global_path_line_color: Color = Color(0.1, 0.85, 1.0, 1.0)
var global_path_line_y_offset: float = 0.2
var global_path_line_width: float = 0.08


## Whitelist of every config field that is mirrored from a CitizenController
## `@export var`. The drift test (`codex_citizen_config_drift_test.gd`)
## fails if this list and the Controller's @export set disagree.
const FIELD_NAMES: Array[String] = [
	# Movement
	"move_speed",
	"waypoint_reach_distance",
	"final_waypoint_reach_distance",
	"waypoint_pass_distance",
	"corner_blend_distance",
	"corner_blend_strength",
	# Steering
	"steering_smoothing",
	"avoidance_slowdown_factor",
	# Perception
	"obstacle_check_interval",
	# Local A* grid
	"use_local_astar_avoidance",
	"local_astar_radius",
	"local_astar_cell_size",
	"local_astar_grid_subdivisions",
	"local_astar_probe_radius",
	"local_astar_replan_interval",
	"local_astar_fallback_replan_cooldown",
	"local_astar_goal_reach_distance",
	"local_astar_front_row_tolerance",
	"local_astar_prefer_right_when_left_open",
	"local_astar_avoid_road_cells",
	"local_astar_near_road_penalty",
	"local_astar_road_proximity_margin",
	"local_astar_road_buffer_cells",
	"local_astar_forward_road_check_distance",
	"local_astar_physics_near_road_margin",
	"local_astar_probe_min_height",
	"local_astar_probe_max_height",
	"local_astar_probe_height_steps",
	"local_astar_height_block_threshold",
	"local_astar_height_clearance_probe_radius",
	"local_astar_surface_collision_mask",
	"local_astar_surface_probe_up",
	"local_astar_surface_probe_down",
	"local_astar_surface_probe_max_hits",
	# Jump
	"jump_low_obstacles",
	"max_jump_obstacle_height",
	"min_jump_obstacle_height",
	"jump_probe_distance",
	"jump_velocity",
	"jump_cooldown",
	# Stuck recovery
	"stuck_detection_interval",
	"stuck_detection_min_distance",
	"stuck_max_recovery_attempts",
	# Click-to-move
	"click_ray_distance",
	"ignore_ui_clicks",
	"click_collision_mask",
	# Debug
	"debug_draw_avoidance",
	"debug_draw_surface_cells",
	"debug_draw_physics_hits",
	"debug_draw_cell_heights",
	"debug_log_probe_hits",
	# Global path visual
	"show_global_path",
	"clear_global_path_on_arrival",
	"global_path_line_color",
	"global_path_line_y_offset",
	"global_path_line_width",
]


## Copies every property listed in `FIELD_NAMES` from `source` into self.
## Properties that the source doesn't expose are silently skipped — the
## drift test catches missing fields, so the runtime path stays light.
func populate_from(source: Object) -> void:
	if source == null:
		return
	for field in FIELD_NAMES:
		if field in source:
			set(field, source.get(field))


## Returns the Y-heights used for both the forward-ahead probe and the grid
## probe.  Keeping them in sync avoids "A* cleared cell X but forward probe
## still says blocked" flapping at half grid radius.
func get_probe_heights() -> Array[float]:
	var min_h := maxf(local_astar_probe_min_height, 0.0)
	var max_h := maxf(local_astar_probe_max_height, min_h)
	var steps := maxi(local_astar_probe_height_steps, 1)
	var heights: Array[float] = []
	if steps == 1:
		heights.append(min_h)
		return heights
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		heights.append(lerpf(min_h, max_h, t))
	return heights
