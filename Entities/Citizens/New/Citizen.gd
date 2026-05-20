class_name Citizen
extends CitizenController

## Production Citizen stack: `CitizenController` owns navigation/movement,
## `CitizenSimulation` owns composed sim state, and this class keeps the
## legacy API surface expected by World, Buildings, GOAP Actions and UI.
##
## See `Sim/MIGRATION.md` for the full roadmap.

signal clicked

@export_group("Identity")
## Display name. Mirrored into `_sim.identity.citizen_name` on `_ready`.
@export var citizen_name: String = "Alex"
@export var debug_panel: DebugPanel

## True when this citizen takes part in autonomous GOAP simulation.
## Player-controlled NPCs and the lone test-citizen `$Citizen` set this
## to false in the Inspector. Keyboard-controlled local players still tick
## needs/health, but skip autonomous GOAP planning and action execution.
@export var autonomous_simulation_enabled: bool = true

const SimLoggerScript = preload("res://Simulation/Logging/SimLogger.gd")
const CitizenAgentScript = preload("res://Simulation/Citizens/CitizenAgent.gd")
const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")
const WorldSnapshotSerializerScript = preload("res://Simulation/Multiplayer/shared/WorldSnapshotSerializer.gd")
const WorkActionScript = preload("res://Actions/WorkAction.gd")
const EatAtHomeActionScript = preload("res://Actions/EatAtHomeAction.gd")
const EatAtRestaurantActionScript = preload("res://Actions/EatAtRestaurantAction.gd")
const SleepActionScript = preload("res://Actions/SleepAction.gd")
const StudyAtUniversityActionScript = preload("res://Actions/StudyAtUniversityAction.gd")
const RelaxAtHomeActionScript = preload("res://Actions/RelaxAtHomeAction.gd")
const RelaxAtParkActionScript = preload("res://Actions/RelaxAtParkAction.gd")
const SocializeActionScript = preload("res://Actions/SocializeAction.gd")
const WatchCinemaActionScript = preload("res://Actions/WatchCinemaAction.gd")
const PlayerInventoryCatalogScript = preload("res://Simulation/UI/PlayerInventoryCatalog.gd")
const FALL_RESPAWN_DEPTH_METERS := 8.0
const FALL_RESPAWN_COOLDOWN_SEC := 1.0
const FALL_RESPAWN_GROUND_OFFSET := 0.12

var _sim: CitizenSimulation = null
var _world_ref: World = null
var _agent = CitizenAgentScript.new()

var _click_area: Area3D = null
var _click_area_shape: CollisionShape3D = null
var _mesh_instance: MeshInstance3D = null
var _original_material: Material = null
var _highlight_material: StandardMaterial3D = null
var _selection_active: bool = false
var _auto_resolved_refs: bool = false

# Saved at _ready so Presence-Toggle can restore them on building exit.
var _saved_collision_layer: int = 0
var _saved_collision_mask: int = 0
var _interior_presence_hidden: bool = false
var _debug_repath_count: int = 0
var _debug_last_travel_route: PackedVector3Array = PackedVector3Array()
var _debug_last_travel_failed: bool = false
# Accumulator for health-delta logging — emits one line per ~5 HP of drift
# instead of one per tick. Persisted across ticks so micro-changes add up.
var _log_health_accum: float = 0.0
# Idempotency-Flag fuer die() — verhindert doppelten Cleanup im selben Tick.
var _is_dying: bool = false
var _debug_travel_target_building: Building = null
var _travel_target: Vector3 = Vector3.ZERO
var _travel_target_building: Building = null
var _stuck_slide_hold_dir: Vector3 = Vector3.ZERO
var _stuck_slide_hold_left: float = 0.0
var _walk_speed: float = 0.5
var _home_rotation_candidate_day: int = -1
var _runtime_conversation_mode: String = ""
var _runtime_conversation_partner: String = ""
var _runtime_conversation_topic: String = ""
var network_replica_mode: bool = false
var _network_action_label: String = ""
var _network_player_action_id: String = ""
var _server_interaction_label: String = ""
var _network_lod_tier: String = ""
var _network_inside_building: bool = false
var _network_manual_control: bool = false
var _network_fall_respawn_count: int = 0
var _network_server_control_enabled: bool = false
var _network_server_control_direction: Vector3 = Vector3.ZERO
var _network_server_control_input_age_sec: float = INF
var _network_server_interaction_travel_enabled: bool = false
var _last_safe_respawn_position: Vector3 = Vector3.ZERO
var _has_last_safe_respawn_position: bool = false
var _fall_respawn_cooldown_sec: float = 0.0
var _fall_respawn_count: int = 0
var cheap_path_follow_lod_enabled: bool = true
var cheap_path_follow_camera_distance: float = 80.0
var obstacle_sensor_height: float = 0.9
var obstacle_probe_length: float = 0.95
var obstacle_clearance_probe_distance: float = 0.34
var obstacle_clearance_radius: float = 0.10
var obstacle_clearance_height: float = 0.78
var forward_avoidance_enabled: bool = true
var forward_avoidance_min_alignment: float = 0.08
var _obstacle_ray_forward: RayCast3D = null
var _obstacle_ray_left: RayCast3D = null
var _obstacle_ray_right: RayCast3D = null
var _forward_avoidance_area: Area3D = null
var _forward_avoidance_shape: CollisionShape3D = null
var unreachable_target_retry_limit: int = 2
var unreachable_target_no_progress_minutes: int = 30


func _init() -> void:
	_ensure_sim_initialized()


func _ready() -> void:
	super._ready()
	_ensure_sim_initialized()
	# Mirror Inspector-set @export values into Identity.
	if _sim != null and _sim.identity != null:
		_sim.identity.citizen_name = citizen_name
		_apply_identity_balance_config()
	# Initialise personality thresholds from balance.json + jitter.
	if _sim != null and _sim.scheduler != null:
		_sim.scheduler.apply_balance_config()
		_sim.scheduler.init_personality()
	# Snapshot collision layers so building entry/exit can toggle them.
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	_walk_speed = maxf(move_speed, 0.01)
	_setup_clickable()
	_setup_selection_visual()
	if network_replica_mode:
		set_network_replica_mode(true)
	else:
		call_deferred("_auto_resolve_refs")


func _physics_process(delta: float) -> void:
	if network_replica_mode:
		velocity = Vector3.ZERO
		return
	var resolved_world := _resolve_world_ref()
	_fall_respawn_cooldown_sec = maxf(_fall_respawn_cooldown_sec - delta, 0.0)
	if _should_respawn_after_fall(resolved_world):
		_respawn_after_fall(resolved_world)
		return
	if _network_server_control_enabled:
		if _network_server_interaction_travel_enabled:
			super._physics_process(delta)
			if not _is_travelling and has_reached_travel_target():
				_network_server_interaction_travel_enabled = false
			_post_physics_fall_safety(resolved_world)
			return
		_physics_process_network_server_control(delta)
		_post_physics_fall_safety(resolved_world)
		return
	if _is_body_presence_hidden():
		velocity = Vector3.ZERO
		return
	super._physics_process(delta)
	_post_physics_fall_safety(resolved_world)


func set_network_replica_mode(enabled: bool) -> void:
	network_replica_mode = enabled
	if not enabled:
		return
	autonomous_simulation_enabled = false
	velocity = Vector3.ZERO
	set_physics_process(false)


func set_network_server_control_enabled(enabled: bool, world: Node = null) -> void:
	_network_server_control_enabled = enabled
	_network_server_control_direction = Vector3.ZERO
	_network_server_control_input_age_sec = INF
	_network_server_interaction_travel_enabled = false
	if not enabled:
		clear_server_interaction_label()
	if enabled:
		set_manual_control_enabled(true, world)
		set_simulation_lod_state("focus", true, true, 1)
		_refresh_network_player_lod_commitment(world)
	else:
		set_manual_control_enabled(false, world)


func apply_network_server_control_input(direction: Vector3, world: Node = null) -> void:
	if not _network_server_control_enabled:
		return
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		cancel_network_server_interaction_travel()
		clear_server_interaction_label()
		if is_inside_building():
			exit_current_building(world)
		elif current_location != null:
			leave_current_location(world, false)
	_network_server_control_direction = direction.normalized() if direction.length_squared() > 1.0 else direction
	_network_server_control_input_age_sec = 0.0
	_refresh_network_player_lod_commitment(world)


func begin_network_server_interaction_travel(
	target_pos: Vector3,
	target_building: Building = null,
	world: Node = null
) -> bool:
	if not _network_server_control_enabled:
		set_network_server_control_enabled(true, world)
	clear_rest_pose(true)
	if is_inside_building():
		exit_current_building(world)
	elif current_location != null:
		leave_current_location(world, false)
	release_reserved_benches(world)
	current_action = null
	decision_cooldown_left = 0
	stop_travel()
	current_location = null
	_network_server_control_direction = Vector3.ZERO
	_network_server_control_input_age_sec = INF
	var travel_started := begin_travel_to(target_pos, target_building)
	_network_server_interaction_travel_enabled = travel_started
	return travel_started


func cancel_network_server_interaction_travel() -> void:
	if not _network_server_interaction_travel_enabled:
		return
	_network_server_interaction_travel_enabled = false
	stop_travel()


func finish_network_server_interaction_travel() -> void:
	_network_server_interaction_travel_enabled = false
	velocity.x = 0.0
	velocity.z = 0.0


func is_network_server_interaction_travelling() -> bool:
	return _network_server_interaction_travel_enabled and _is_travelling

func get_fall_respawn_count() -> int:
	if network_replica_mode:
		return _network_fall_respawn_count
	return _fall_respawn_count

func _post_physics_fall_safety(world: World) -> void:
	if _should_respawn_after_fall(world):
		_respawn_after_fall(world)
		return
	_remember_safe_respawn_position(world)

func _should_respawn_after_fall(world: World) -> bool:
	if _fall_respawn_cooldown_sec > 0.0:
		return false
	if _is_body_presence_hidden():
		return false
	return global_position.y < _fall_respawn_threshold_y(world)

func _fall_respawn_threshold_y(world: World) -> float:
	return _fall_respawn_ground_y(world) - FALL_RESPAWN_DEPTH_METERS

func _fall_respawn_ground_y(world: World) -> float:
	if world != null and world.has_method("get_ground_fallback_y"):
		return float(world.get_ground_fallback_y())
	return 0.0

func _remember_safe_respawn_position(world: World) -> void:
	if _is_body_presence_hidden() or not is_on_floor():
		return
	if global_position.y <= _fall_respawn_threshold_y(world) + 1.0:
		return
	_last_safe_respawn_position = global_position
	_has_last_safe_respawn_position = true

func _respawn_after_fall(world: World) -> void:
	var fallen_position := global_position
	var respawn_position := _get_fall_respawn_position(world)
	_prepare_for_fall_respawn(world)
	_set_position_grounded(respawn_position)
	_last_safe_respawn_position = global_position
	_has_last_safe_respawn_position = true
	_fall_respawn_cooldown_sec = FALL_RESPAWN_COOLDOWN_SEC
	_fall_respawn_count += 1
	if SimLoggerScript != null:
		SimLoggerScript.log("[Citizen %s] Respawned after fall from %s to %s" % [
			_get_log_name(),
			_fmt_v3(fallen_position),
			_fmt_v3(global_position),
		])

func _prepare_for_fall_respawn(world: World) -> void:
	cancel_network_server_interaction_travel()
	clear_server_interaction_label()
	clear_rest_pose(false)
	release_reserved_benches(world)
	if is_inside_building():
		exit_current_building(world)
	elif current_location != null:
		leave_current_location(world, false)
	stop_travel()
	current_location = null
	current_action = null
	decision_cooldown_left = 0
	_set_interior_presence(false)
	velocity = Vector3.ZERO

func _get_fall_respawn_position(world: World) -> Vector3:
	if _has_last_safe_respawn_position:
		return _snap_respawn_position(_last_safe_respawn_position, world)
	var location_position: Variant = _building_respawn_position(current_location, world)
	if location_position is Vector3:
		return location_position as Vector3
	var home_position: Variant = _building_respawn_position(home, world)
	if home_position is Vector3:
		return home_position as Vector3
	var nearest_building := _nearest_respawn_building(world, global_position)
	var nearest_position: Variant = _building_respawn_position(nearest_building, world)
	if nearest_position is Vector3:
		return nearest_position as Vector3
	var fallback := world.get_world_center() if world != null and world.has_method("get_world_center") else Vector3.ZERO
	fallback.y = _fall_respawn_ground_y(world) + FALL_RESPAWN_GROUND_OFFSET
	return _snap_respawn_position(fallback, world)

func _building_respawn_position(building: Building, world: World) -> Variant:
	if building == null or not is_instance_valid(building):
		return null
	var nav_points := get_navigation_points_for_building(building, world)
	var fallback := building.get_entrance_pos() if building.has_method("get_entrance_pos") else building.global_position
	var raw_position: Variant = nav_points.get("spawn", nav_points.get("access", fallback))
	if raw_position is not Vector3:
		raw_position = fallback
	return _snap_respawn_position(raw_position as Vector3, world, building)

func _snap_respawn_position(pos: Vector3, world: World, building: Building = null) -> Vector3:
	var snapped := pos
	if world != null and world.has_method("get_pedestrian_access_point"):
		snapped = world.get_pedestrian_access_point(snapped, building)
	if is_inside_tree():
		snapped = _project_navigation_target_to_ground(snapped)
	var ground_y := _fall_respawn_ground_y(world)
	snapped.y = maxf(snapped.y, ground_y + FALL_RESPAWN_GROUND_OFFSET)
	return snapped

func _nearest_respawn_building(world: World, origin: Vector3) -> Building:
	if world == null:
		return null
	var best: Building = null
	var best_distance := INF
	for building in world.buildings:
		if building == null or not is_instance_valid(building):
			continue
		var distance := _planar_distance(origin, building.global_position)
		if distance >= best_distance:
			continue
		best = building
		best_distance = distance
	return best


func set_server_interaction_label(label: String) -> void:
	_server_interaction_label = label.strip_edges()


func clear_server_interaction_label(expected_label: String = "") -> void:
	if expected_label.is_empty() or _server_interaction_label == expected_label:
		_server_interaction_label = ""


func get_server_interaction_label() -> String:
	return _server_interaction_label


func _physics_process_network_server_control(delta: float) -> void:
	if _network_server_control_input_age_sec > 0.35:
		_network_server_control_direction = Vector3.ZERO
	if has_method("apply_external_manual_direction"):
		apply_external_manual_direction(delta, _network_server_control_direction)
	_network_server_control_input_age_sec += delta


func apply_network_snapshot(data: Dictionary, building_lookup: Dictionary) -> void:
	set_network_replica_mode(true)
	citizen_name = str(data.get("name", citizen_name))
	if _sim != null and _sim.identity != null:
		_sim.identity.citizen_name = citizen_name
	global_position = WorldSnapshotSerializerScript.vector_from_snapshot(data.get("position", []), global_position)
	rotation.y = float(data.get("rotation_y", rotation.y))
	if bool(data.get("visible", visible)):
		show()
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask
	else:
		hide()
		collision_layer = 0
		collision_mask = 0
	if wallet != null:
		wallet.balance = int(data.get("wallet", wallet.balance))
	home_food_stock = int(data.get("home_food_stock", home_food_stock))
	clothing_items = int(data.get("clothing_items", clothing_items))
	education_level = int(data.get("education_level", education_level))
	if needs != null:
		needs.hunger = float(data.get("hunger", needs.hunger))
		needs.energy = float(data.get("energy", needs.energy))
		needs.fun = float(data.get("fun", needs.fun))
		needs.social = float(data.get("social", needs.social))
		needs.health = float(data.get("health", needs.health))
	if data.has("current_location_id"):
		var location_id := str(data.get("current_location_id", ""))
		current_location = building_lookup.get(location_id, null) as Building
	if data.has("home_id"):
		var home_id := str(data.get("home_id", ""))
		home = building_lookup.get(home_id, null) as ResidentialBuilding
	if data.has("workplace_id"):
		var workplace_id := str(data.get("workplace_id", ""))
		var workplace := building_lookup.get(workplace_id, null) as Building
		if workplace_id.is_empty() or workplace == null:
			job = null
		else:
			if job == null:
				job = Job.new()
			job.workplace = workplace
			job.preferred_workplace = workplace
			job.title = str(data.get("job_title", job.title))
			job.wage_per_hour = int(data.get("job_wage_per_hour", job.wage_per_hour))
			job.shift_hours = int(data.get("job_shift_hours", job.shift_hours))
			job.required_education_level = int(data.get("job_required_education_level", job.required_education_level))
			job.workplace_service_type = str(data.get("job_workplace_service_type", job.workplace_service_type))
			var allowed_types: Variant = data.get("job_allowed_building_types", job.allowed_building_types)
			if allowed_types is Array:
				var converted_types: Array[int] = []
				for allowed_type in allowed_types as Array:
					converted_types.append(int(allowed_type))
				job.allowed_building_types = converted_types
	work_minutes_today = int(data.get("work_minutes_today", work_minutes_today))
	_network_action_label = str(data.get("action", _network_action_label))
	_network_player_action_id = str(data.get("player_action_id", _network_player_action_id))
	_player_action_notice = str(data.get("player_action_notice", _player_action_notice))
	_network_lod_tier = str(data.get("lod", _network_lod_tier))
	_network_inside_building = bool(data.get("inside", _network_inside_building))
	_network_manual_control = bool(data.get("manual_control", _network_manual_control))
	_network_fall_respawn_count = int(data.get("fall_respawn_count", _network_fall_respawn_count))
	_is_travelling = bool(data.get("travelling", _is_travelling))
	velocity = Vector3.ZERO
	set_physics_process(false)


func is_network_manual_controlled() -> bool:
	return _network_manual_control


func _ensure_sim_initialized() -> void:
	if _sim != null:
		return
	_sim = CitizenSimulation.new(self)
	if _sim.identity != null:
		_sim.identity.citizen_name = citizen_name


func _apply_identity_balance_config() -> void:
	if _sim == null or _sim.identity == null:
		return
	if wallet != null:
		wallet.owner_name = citizen_name
		wallet.balance = BalanceConfig.get_int("citizen.wallet_start_balance", wallet.balance)
	home_food_stock = BalanceConfig.get_int("citizen.home_food_stock_start", home_food_stock)
	education_level = BalanceConfig.get_int("citizen.education_level_start", education_level)


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
		col.position = Vector3(0, 1.05, 0)

	_click_area = area
	_click_area_shape = col
	if not area.input_event.is_connected(_on_click_area_input_event):
		area.input_event.connect(_on_click_area_input_event)


func _on_click_area_input_event(_camera: Camera3D, event: InputEvent,
		_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		clicked.emit()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _setup_selection_visual() -> void:
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance != null:
		_original_material = _mesh_instance.material_overlay
	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(1.0, 0.84, 0.25, 0.55)
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func select(panel) -> void:
	debug_panel = panel
	set_debug_visualization_enabled(panel != null)
	set_selected(panel != null)


func set_selected(selected: bool) -> void:
	_selection_active = selected
	if _mesh_instance == null:
		return
	_mesh_instance.material_overlay = _highlight_material if selected else _original_material


# ========================================================================
# Identity property forwarding (CitizenAgent / Actions / World read these
# directly via dot-access on the citizen). Each pair forwards into
# `_sim.identity.*`. Null-safe: if the simulation hasn't been built yet,
# getters return null/defaults and setters are no-ops.
# ========================================================================

var home: ResidentialBuilding:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.home
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.home = value

var job: Job:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.job
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.job = value

var wallet: Account:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.wallet
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.wallet = value

var needs: Needs:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.needs
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.needs = value

var current_location: Building:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.current_location
		return null
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.current_location = value

var home_food_stock: int:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.home_food_stock
		return 0
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.home_food_stock = value

var clothing_items: int:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.clothing_items
		return 0
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.clothing_items = maxi(value, 0)

var education_level: int:
	get:
		if _sim != null and _sim.identity != null:
			return _sim.identity.education_level
		return 0
	set(value):
		if _sim != null and _sim.identity != null:
			_sim.identity.education_level = value


# Favorites — accessed via getters/setters rather than property forwarding to
# keep the @export-property cluster small. Plain helpers, identical effect.

var favorite_restaurant: Restaurant:
	get: return get_favorite_restaurant()
	set(value): set_favorite_restaurant(value)

var favorite_supermarket: Supermarket:
	get: return get_favorite_supermarket()
	set(value): set_favorite_supermarket(value)

var favorite_shop: Shop:
	get: return get_favorite_shop()
	set(value): set_favorite_shop(value)

var favorite_cinema: Cinema:
	get: return get_favorite_cinema()
	set(value): set_favorite_cinema(value)

var favorite_park: Building:
	get: return get_favorite_park()
	set(value): set_favorite_park(value)

var final_arrival_distance: float:
	get: return final_waypoint_reach_distance
	set(value): final_waypoint_reach_distance = value

var local_navigation_raycast_checks_enabled: bool:
	get: return use_local_astar_avoidance
	set(value): use_local_astar_avoidance = value

var repath_interval_sec: float:
	get: return local_astar_replan_interval
	set(value): local_astar_replan_interval = maxf(value, 0.05)

var _simulation_lod_tick_phase_seed: int:
	get:
		return _sim.lod.tick_phase_seed if _sim != null and _sim.lod != null else 0
	set(value):
		if _sim != null and _sim.lod != null:
			_sim.lod.tick_phase_seed = value

var _simulation_lod_path_mode: String:
	get:
		return _sim.lod.path_mode if _sim != null and _sim.lod != null else "default"
	set(value):
		if _sim != null and _sim.lod != null:
			_sim.lod.path_mode = value

var _travel_route: PackedVector3Array:
	get:
		return PackedVector3Array(_global_path)
	set(value):
		_global_path = PackedVector3Array(value)
		_debug_last_travel_route = PackedVector3Array(value)
		if not _global_path.is_empty():
			_target_position = _global_path[_global_path.size() - 1]
		_is_travelling = _global_path.size() >= 2 if _is_travelling else _is_travelling

var _travel_route_index: int:
	get:
		return _path_index
	set(value):
		_path_index = value
		if _global_path.is_empty():
			return
		var clamped_index := clampi(value, 0, _global_path.size() - 1)
		_path_index = clamped_index
		_travel_target = _global_path[clamped_index]
		_target_position = _global_path[_global_path.size() - 1]


func get_favorite_restaurant() -> Restaurant:
	return _sim.identity.favorite_restaurant if _sim != null and _sim.identity != null else null


func set_favorite_restaurant(value: Restaurant) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_restaurant = value


func get_favorite_supermarket() -> Supermarket:
	return _sim.identity.favorite_supermarket if _sim != null and _sim.identity != null else null


func set_favorite_supermarket(value: Supermarket) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_supermarket = value


func get_favorite_shop() -> Shop:
	return _sim.identity.favorite_shop if _sim != null and _sim.identity != null else null


func set_favorite_shop(value: Shop) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_shop = value


func get_favorite_cinema() -> Cinema:
	return _sim.identity.favorite_cinema if _sim != null and _sim.identity != null else null


func set_favorite_cinema(value: Cinema) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_cinema = value


func get_favorite_park() -> Building:
	return _sim.identity.favorite_park if _sim != null and _sim.identity != null else null


func set_favorite_park(value: Building) -> void:
	if _sim != null and _sim.identity != null:
		_sim.identity.favorite_park = value


# ========================================================================
# Scheduler property-forwarding — many fields are written and read directly
# by CitizenAgent / CitizenPlanner. Forwarding keeps the legacy access shape.
# ========================================================================

var schedule_offset: int:
	get: return _sim.scheduler.schedule_offset if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.schedule_offset = v

var schedule_offset_min: int:
	get: return _sim.scheduler.schedule_offset_min if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.schedule_offset_min = v

var schedule_offset_max: int:
	get: return _sim.scheduler.schedule_offset_max if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.schedule_offset_max = v

func _auto_resolve_refs() -> void:
	if _auto_resolved_refs or _agent == null or _agent.query_resolver == null:
		return
	if not is_inside_tree():
		return
	_auto_resolved_refs = true

	var origin := global_position
	var query: CitizenQueryResolver = _agent.query_resolver
	if home == null:
		home = query.find_first_residential_building(self, origin)
		if home != null:
			var added := home.add_tenant(self)
			if not added:
				var full_home := home
				home = query.find_first_residential_building(self, origin)
				if home != null and home != full_home:
					home.add_tenant(self)
	if favorite_restaurant == null:
		favorite_restaurant = query.find_nearest_restaurant(self, origin, false)
	if favorite_supermarket == null:
		favorite_supermarket = query.find_nearest_supermarket(self, origin, false)
	if favorite_shop == null:
		favorite_shop = query.find_nearest_shop(self, origin, false)
	if favorite_cinema == null:
		favorite_cinema = query.find_nearest_cinema(self, origin, false)
	if favorite_park == null:
		favorite_park = query.find_nearest_park(self, origin)

	if job != null:
		job.resolve_nearest(self, origin)
		if job.workplace != null:
			job.try_get_employed(self)
			if _world_ref != null and _world_ref.has_method("register_job"):
				_world_ref.register_job(job)


var decision_cooldown_left: int:
	get: return _sim.scheduler.decision_cooldown_left if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.decision_cooldown_left = v

var decision_cooldown_range_min: int:
	get: return _sim.scheduler.decision_cooldown_range_min if _sim != null and _sim.scheduler != null else 5
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.decision_cooldown_range_min = v

var decision_cooldown_range_max: int:
	get: return _sim.scheduler.decision_cooldown_range_max if _sim != null and _sim.scheduler != null else 20
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.decision_cooldown_range_max = v

var hunger_threshold: float:
	get: return _sim.scheduler.hunger_threshold if _sim != null and _sim.scheduler != null else 60.0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.hunger_threshold = v

var low_energy_threshold: float:
	get: return _sim.scheduler.low_energy_threshold if _sim != null and _sim.scheduler != null else 35.0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.low_energy_threshold = v

var work_motivation: float:
	get: return _sim.scheduler.work_motivation if _sim != null and _sim.scheduler != null else 1.0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.work_motivation = v

var fun_interest: float:
	get: return _sim.scheduler.fun_interest if _sim != null and _sim.scheduler != null else 0.35
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.fun_interest = v

var fun_target: float:
	get: return _sim.scheduler.fun_target if _sim != null and _sim.scheduler != null else 65.0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.fun_target = v

var sociability: float:
	get: return _sim.scheduler.sociability if _sim != null and _sim.scheduler != null else 0.5
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.sociability = v

var work_minutes_today: int:
	get: return _sim.scheduler.work_minutes_today if _sim != null and _sim.scheduler != null else 0
	set(v):
		if _sim != null and _sim.scheduler != null:
			_sim.scheduler.work_minutes_today = v

## Action ownership — kept directly on the Facade because GOAP-Action object
## has no natural Sim-component home. CitizenAgent reads + writes this.
var current_action: Action = null
var _player_action_active: bool = false
# Last player-action rejection (e.g. work refused for missing education).
# Shown in the player-action panel; cleared on the next start/enter/exit.
var _player_action_notice: String = ""


func is_player_action_active() -> bool:
	return _player_action_active and current_action != null


func clear_player_action_state() -> void:
	if current_action == null:
		_player_action_active = false


func cancel_player_action(world: Node = null) -> void:
	var resolved_world := _resolve_world_arg(world)
	if current_action != null and current_action.has_method("finish"):
		current_action.finish(resolved_world, self)
	current_action = null
	_player_action_active = false
	_player_action_notice = ""


func get_player_action_notice() -> String:
	return _player_action_notice


func get_network_player_action_id() -> String:
	return _active_player_action_id()


func player_rent_home(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	if location == null or location is not ResidentialBuilding:
		return false
	var residential := location as ResidentialBuilding
	if home == residential and residential.tenants.has(self):
		_player_action_notice = "Du wohnst bereits hier."
		return true
	if not residential.has_free_slot():
		_player_action_notice = "%s hat keine freie Wohnung." % _building_label(residential)
		return false
	cancel_player_action(resolved_world)
	var old_home := home
	if not residential.add_tenant(self):
		_player_action_notice = "%s hat keine freie Wohnung." % _building_label(residential)
		return false
	if old_home != null and old_home != residential:
		old_home.remove_tenant(self)
	home = residential
	_player_slot_building = residential
	_player_slot_kind = "tenant"
	_player_action_notice = "Wohnung gemietet: %s." % _building_label(residential)
	return true


func player_quit_home(world: Node = null, exit_after: bool = true) -> bool:
	if home == null:
		return false
	var resolved_world := _resolve_world_arg(world)
	var old_home := home
	cancel_player_action(resolved_world)
	if old_home.has_method("remove_tenant"):
		old_home.remove_tenant(self)
	home = null
	if is_inside_building() and _get_player_current_building() == old_home and exit_after:
		exit_current_building(resolved_world)
		_player_slot_building = null
		_player_slot_kind = ""
	_player_action_notice = "Wohnung gekuendigt."
	return true


## Applies for a job at the current workplace. Entering a workplace is only a
## visit; this method is the explicit acceptance step and takes the worker slot
## without starting a work action yet.
func player_apply_for_work(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var workplace := _get_player_current_building()
	if resolved_world == null or workplace == null:
		return false
	if current_action != null:
		_player_action_notice = "Aktion laeuft noch."
		return false
	if int(workplace.job_capacity) <= 0:
		_player_action_notice = "%s bietet keine Stelle." % _building_label(workplace)
		return false
	if _player_has_accepted_job_at(workplace):
		_player_action_notice = "Angenommen bei %s." % _building_label(workplace)
		return true
	if job != null and job.workplace != null and job.workplace != workplace:
		_player_action_notice = "Du hast schon einen Job bei %s." % _building_label(job.workplace)
		return false
	if not _workplace_has_open_application_slot(workplace, resolved_world):
		_player_action_notice = "Bewerbung bei %s nicht moeglich (voll)." % _building_label(workplace)
		return false

	var candidate_job := _build_player_job_for_workplace(workplace)
	if candidate_job == null:
		return false
	if not candidate_job.meets_requirements(self):
		_player_action_notice = "Abgelehnt: %s braucht Bildung %d/%d - erst an der Uni weiterbilden." % [
			candidate_job.title,
			education_level,
			candidate_job.required_education_level,
		]
		debug_log("Player work rejected: education %d/%d for %s." % [
			education_level,
			candidate_job.required_education_level,
			candidate_job.title,
		])
		return false
	job = candidate_job
	if not _ensure_player_hired_for_current_job(resolved_world):
		job = null
		_player_action_notice = "Einstellung bei %s nicht moeglich (voll)." % _building_label(workplace)
		return false
	_player_action_notice = "Angenommen: %s bei %s." % [job.title, _building_label(workplace)]
	return true


## Starts the accepted player job at the current workplace. Wage payout remains
## centralized in World._on_payday(), based on work_minutes_today.
func player_work(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var workplace := _get_player_current_building()
	if resolved_world == null or workplace == null:
		return false
	if not _player_has_accepted_job_at(workplace):
		_player_action_notice = "Erst bei %s bewerben." % _building_label(workplace)
		return false
	if current_action is WorkActionScript:
		return true
	if current_action != null:
		_player_action_notice = "Aktion laeuft noch."
		return false
	_player_action_notice = ""
	return _start_player_action(WorkActionScript.new(job), resolved_world)


func player_eat(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	if resolved_world == null or location == null:
		return false
	if location is Restaurant:
		return _start_player_action(EatAtRestaurantActionScript.new(location as Restaurant), resolved_world)
	if _is_player_home_location(location):
		if home_food_stock <= 0:
			debug_log("Player eat failed: no food stock at home.")
			return false
		return _start_player_action(EatAtHomeActionScript.new(), resolved_world)
	debug_log("Player eat failed: not at home or in a restaurant.")
	return false


func player_sleep(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	if resolved_world == null or location == null:
		return false
	if not _is_player_home_location(location):
		debug_log("Player sleep failed: not at home.")
		return false
	return _start_player_action(SleepActionScript.new(), resolved_world)


func player_study(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	if resolved_world == null or location == null or location is not University:
		return false
	return _start_player_action(StudyAtUniversityActionScript.new(location as University), resolved_world)


func player_relax(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	if resolved_world == null or location == null:
		return false
	if location is Park:
		_player_action_notice = ""
		return _start_player_action(RelaxAtParkActionScript.new(), resolved_world)
	if _is_player_home_location(location):
		_player_action_notice = ""
		return _start_player_action(RelaxAtHomeActionScript.new(), resolved_world)
	_player_action_notice = "Entspannen geht zuhause oder im Park."
	return false


func player_socialize(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	if resolved_world == null or location == null or location is not Park:
		_player_action_notice = "Sozialisieren geht im Park."
		return false
	if needs != null and needs.hunger >= 70.0:
		_player_action_notice = "Erst essen, dann sozialisieren."
		return false
	if needs != null and needs.health <= 35.0:
		_player_action_notice = "Gesundheit zu niedrig."
		return false
	_player_action_notice = ""
	return _start_player_action(SocializeActionScript.new(), resolved_world)


func player_watch_cinema(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	if resolved_world == null or location == null or location is not Cinema:
		_player_action_notice = "Du bist in keinem Kino."
		return false
	var cinema := location as Cinema
	if not cinema.is_open(resolved_world.time.get_hour()):
		_player_action_notice = "%s ist geschlossen." % _building_label(cinema)
		return false
	if wallet == null or wallet.balance < cinema.ticket_price:
		_player_action_notice = "Zu wenig Geld: %d EUR noetig." % cinema.ticket_price
		return false
	_player_action_notice = ""
	return _start_player_action(WatchCinemaActionScript.new(cinema), resolved_world)


func player_buy_shop_item(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	if resolved_world == null or location == null or location is not Shop:
		return false
	if current_action != null:
		_player_action_notice = "Aktion laeuft noch."
		return false
	var shop := location as Shop
	if not shop.is_open(resolved_world.time.get_hour()):
		_player_action_notice = "%s ist geschlossen." % _building_label(shop)
		return false
	if not shop.can_sell_item("clothing", 1):
		_player_action_notice = "Kleidung ist ausverkauft."
		return false
	var price := _get_shop_item_price(shop)
	if wallet == null or wallet.balance < price:
		_player_action_notice = "Zu wenig Geld: %d EUR noetig." % price
		return false
	if not shop.buy_item(resolved_world, self, 1.0):
		_player_action_notice = "Kauf bei %s nicht moeglich." % _building_label(shop)
		return false
	clothing_items += 1
	_player_action_notice = "Gekauft: Kleidung (%d EUR)." % price
	return true


func player_buy_groceries(world: Node = null) -> bool:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	if resolved_world == null or location == null or location is not Supermarket:
		return false
	if current_action != null:
		_player_action_notice = "Aktion laeuft noch."
		return false
	var market := location as Supermarket
	if not market.is_open(resolved_world.time.get_hour()):
		_player_action_notice = "%s ist geschlossen." % _building_label(market)
		return false
	if not market.can_sell_item("grocery_bundle", 1):
		_player_action_notice = "Lebensmittel sind ausverkauft."
		return false
	var price := market.get_grocery_price(resolved_world)
	if wallet == null or wallet.balance < price:
		_player_action_notice = "Zu wenig Geld: %d EUR noetig." % price
		return false
	var purchased_units := market.buy_groceries(resolved_world, self)
	if purchased_units <= 0:
		_player_action_notice = "Lebensmittelkauf bei %s nicht moeglich." % _building_label(market)
		return false
	home_food_stock += purchased_units
	_player_action_notice = "Gekauft: %d Vorraete (%d EUR)." % [purchased_units, price]
	return true


func player_quit_job(world: Node = null, exit_after: bool = true) -> bool:
	var resolved_world := _resolve_world_arg(world)
	if job == null:
		return false
	cancel_player_action(resolved_world)
	var workplace := job.workplace
	if workplace != null and workplace.has_method("fire"):
		workplace.fire(self)
	if resolved_world != null and resolved_world.has_method("unregister_job"):
		resolved_world.unregister_job(job)
	job = null
	if is_inside_building() and exit_after:
		exit_current_building(resolved_world)
		_player_slot_building = null
		_player_slot_kind = ""
	return true


## "Zur Uni": leave the current workplace so the player can walk to a
## university and study. No job is required (entering never assigns one).
func player_leave_for_training(world: Node = null) -> bool:
	if not is_inside_building():
		return false
	var resolved_world := _resolve_world_arg(world)
	cancel_player_action(resolved_world)
	exit_current_building(resolved_world)
	_player_slot_building = null
	_player_slot_kind = ""
	_player_action_notice = ""
	return true


func get_player_action_ui_state(world: Node = null) -> Dictionary:
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	var buttons: Array = []
	var status_lines: PackedStringArray = []
	var location_label := _building_label(location) if location != null else "unterwegs"
	var active_id := _active_player_action_id()
	var action_running := not active_id.is_empty()
	status_lines.append("Ort: %s" % location_label)
	status_lines.append("Wohnung: %s" % (_building_label(home) if home != null else "keine"))
	buttons.append(_make_player_action_button("inventory", "Inventar", true))
	if action_running:
		status_lines.append("Aktiv: %s" % _active_player_action_label())
		buttons.append(_make_player_action_button("stop", "Aktion stoppen", true))

	if location != null:
		if _is_player_home_location(location):
			buttons.append(_make_player_action_button("eat", "Essen", home_food_stock > 0, "Keine Vorraete zuhause."))
			buttons.append(_make_player_action_button("sleep", "Schlafen", true))
			buttons.append(_make_player_action_button("relax", "Entspannen", true))
			buttons.append(_make_player_action_button("quit_home", "Wohnung kuendigen", not action_running, "Aktion laeuft noch."))
		elif location is ResidentialBuilding:
			var residential := location as ResidentialBuilding
			var can_rent := not action_running and (residential.tenants.has(self) or residential.has_free_slot())
			var rent_label := "Umziehen" if home != null else "Mieten"
			buttons.append(_make_player_action_button("rent_home", rent_label, can_rent, "Keine freie Wohnung."))
		elif location is Restaurant:
			var restaurant := location as Restaurant
			var can_eat := resolved_world != null \
				and restaurant.is_open(resolved_world.time.get_hour()) \
				and can_afford_restaurant_at(restaurant, resolved_world)
			buttons.append(_make_player_action_button("eat", "Essen", can_eat, "Restaurant geschlossen oder zu wenig Geld."))
		elif location is University:
			var university := location as University
			var can_study := resolved_world != null and university.can_study(self)
			buttons.append(_make_player_action_button("study", "Studieren", can_study, "Uni ist geschlossen oder hat keine Lehrkraft."))
		elif location is Park:
			var can_socialize := needs == null or (needs.hunger < 70.0 and needs.health > 35.0)
			buttons.append(_make_player_action_button("relax", "Entspannen", true))
			buttons.append(_make_player_action_button("socialize", "Sozialisieren", can_socialize, "Erst essen oder erholen."))
		elif location is Cinema:
			var cinema := location as Cinema
			var can_watch := resolved_world != null \
				and cinema.is_open(resolved_world.time.get_hour()) \
				and wallet != null \
				and wallet.balance >= cinema.ticket_price
			buttons.append(_make_player_action_button("watch_cinema", "Film schauen", can_watch, "Kino geschlossen oder zu wenig Geld."))

		if location is Shop:
			buttons.append(_make_player_action_button("shop", "Einkaufen", true))

		if int(location.job_capacity) > 0:
			var prospective_title := location.get_default_job_title()
			var required_edu := location.get_required_education_level()
			var qualifies := education_level >= required_edu
			var employed_here := _player_has_accepted_job_at(location)
			if required_edu > 0:
				status_lines.append("Stelle: %s - Bildung %d/%d" % [prospective_title, education_level, required_edu])
			else:
				status_lines.append("Stelle: %s - keine Bildung noetig" % prospective_title)
			if employed_here:
				var can_work := not action_running or active_id == "work"
				buttons.append(_make_player_action_button("work", "Arbeiten", can_work, "Aktion laeuft noch."))
			else:
				buttons.append(_make_player_action_button("apply_work", "Bewerben", not action_running, "Aktion laeuft noch."))
			if not qualifies:
				buttons.append(_make_player_action_button("training", "Zur Uni", true))
			if employed_here:
				buttons.append(_make_player_action_button("quit_job", "Kuendigen", true))

	if not _player_action_notice.is_empty():
		status_lines.append(_player_action_notice)

	if buttons.is_empty():
		return {}
	for spec_var in buttons:
		var spec := spec_var as Dictionary
		spec["active"] = not active_id.is_empty() and str(spec.get("id", "")) == active_id
	return {
		"visible": true,
		"title": "Spieler-Aktionen",
		"status_text": "\n".join(status_lines),
		"buttons": buttons,
	}


func get_player_inventory_ui_state(world: Node = null, mode: String = "player") -> Dictionary:
	var clean_mode := mode.strip_edges()
	if clean_mode.is_empty():
		return {}
	var resolved_world := _resolve_world_arg(world)
	var location := _get_player_current_building()
	var show_shop := clean_mode == "shop" and location is Shop
	var resolved_mode := "shop" if show_shop else "player"
	var status_lines: PackedStringArray = []
	status_lines.append("Geld: %d EUR" % (wallet.balance if wallet != null else 0))
	if show_shop:
		var shop_for_status := location as Shop
		status_lines.append("Shop: %s" % _building_label(shop_for_status))
		if resolved_world != null:
			status_lines.append("Status: %s" % shop_for_status.get_open_status_display_label(resolved_world.time.get_hour()))
	else:
		status_lines.append("Ort: %s" % (_building_label(location) if location != null else "unterwegs"))
	if not _player_action_notice.is_empty():
		status_lines.append(_player_action_notice)

	var title := "Einkaufen" if show_shop else "Inventar"
	if show_shop:
		title = "Einkaufen: %s" % _building_label(location)

	return {
		"visible": true,
		"mode": resolved_mode,
		"title": title,
		"status_text": "\n".join(status_lines),
		"player_slots": _build_player_inventory_slots(),
		"categories": _build_shop_inventory_categories(location, resolved_world) if show_shop else [],
	}


func get_inventory_count(item_id: String) -> int:
	# Single point that translates inventory item ids to concrete citizen slots.
	# Extend here when a new item id is added to PlayerInventoryCatalog.
	match item_id:
		"food":
			return home_food_stock
		"clothing":
			return clothing_items
	return 0


func _build_player_inventory_slots() -> Array:
	var slots: Array = []
	for id_var in PlayerInventoryCatalogScript.item_ids():
		var id := str(id_var)
		slots.append({
			"id": id,
			"label": PlayerInventoryCatalogScript.get_label(id),
			"icon": PlayerInventoryCatalogScript.get_icon(id),
			"count": get_inventory_count(id),
		})
	return slots


func _build_shop_inventory_categories(location: Building, resolved_world: Node) -> Array:
	if location == null or location is not Shop:
		return []
	var shop := location as Shop
	var categories: Array = []
	var active := not _active_player_action_id().is_empty()
	if shop is Supermarket:
		categories.append(_build_shop_food_category(shop as Supermarket, resolved_world, active))
	categories.append(_build_shop_clothing_category(shop, resolved_world, active))
	return categories


func _build_shop_food_category(market: Supermarket, resolved_world: Node, action_running: bool) -> Dictionary:
	var price := market.get_grocery_price(resolved_world) if resolved_world != null else 0
	var enabled := not action_running and resolved_world != null and can_buy_groceries_at(market, resolved_world as World)
	var tooltip := _shop_buy_disabled_reason(market, resolved_world as World, "grocery_bundle", price) if not enabled else ""
	return {
		"id": "food",
		"label": PlayerInventoryCatalogScript.get_tab_label("food"),
		"icon": PlayerInventoryCatalogScript.get_icon("food"),
		"items": [
			{
				"id": "food",
				"label": PlayerInventoryCatalogScript.get_label("food"),
				"icon": PlayerInventoryCatalogScript.get_icon("food"),
				"price": price,
				"stock": market.get_stock("grocery_bundle"),
				"owned": get_inventory_count("food"),
				"enabled": enabled,
				"tooltip": tooltip,
				"button_text": "Kaufen",
				"action_id": "buy_groceries",
			},
		],
	}


func _build_shop_clothing_category(shop: Shop, resolved_world: Node, action_running: bool) -> Dictionary:
	var price := _get_shop_item_price(shop)
	var enabled := not action_running and resolved_world != null and can_buy_shop_item_at(shop, resolved_world as World)
	var tooltip := _shop_buy_disabled_reason(shop, resolved_world as World, "clothing", price) if not enabled else ""
	return {
		"id": "clothing",
		"label": PlayerInventoryCatalogScript.get_tab_label("clothing"),
		"icon": PlayerInventoryCatalogScript.get_icon("clothing"),
		"items": [
			{
				"id": "clothing",
				"label": PlayerInventoryCatalogScript.get_label("clothing"),
				"icon": PlayerInventoryCatalogScript.get_icon("clothing"),
				"price": price,
				"stock": shop.get_stock("clothing"),
				"owned": get_inventory_count("clothing"),
				"enabled": enabled,
				"tooltip": tooltip,
				"button_text": "Kaufen",
				"action_id": "buy_shop_item",
			},
		],
	}


## Maps the running action back to its UI button id so the panel can show
## which action is currently active (accent-highlighted button).
func _active_player_action_id() -> String:
	if network_replica_mode and not _network_player_action_id.is_empty():
		return _network_player_action_id
	if current_action == null:
		return ""
	if current_action is WorkActionScript:
		return "work"
	if current_action is EatAtHomeActionScript or current_action is EatAtRestaurantActionScript:
		return "eat"
	if current_action is SleepActionScript:
		return "sleep"
	if current_action is StudyAtUniversityActionScript:
		return "study"
	if current_action is RelaxAtHomeActionScript or current_action is RelaxAtParkActionScript:
		return "relax"
	if current_action is SocializeActionScript:
		return "socialize"
	if current_action is WatchCinemaActionScript:
		return "watch_cinema"
	return ""


func _active_player_action_label() -> String:
	if network_replica_mode and not _network_player_action_id.is_empty():
		if not _network_action_label.is_empty():
			return _network_action_label
		return _network_player_action_id
	return current_action.label if current_action != null else ""


func _make_player_action_button(action_id: String, text: String, enabled: bool, disabled_reason: String = "") -> Dictionary:
	return {
		"id": action_id,
		"text": text,
		"enabled": enabled,
		"tooltip": "" if enabled else disabled_reason,
	}


func _start_player_action(action: Action, world: World) -> bool:
	if action == null or world == null:
		return false
	if current_action != null:
		cancel_player_action(world)
	start_action(action, world)
	_player_action_active = current_action == action
	if current_action != null and current_action.is_done():
		current_action.finish(world, self)
		if current_action == action:
			current_action = null
		_player_action_active = false
		return false
	return _player_action_active


func _get_player_current_building() -> Building:
	if current_location != null and is_instance_valid(current_location):
		return current_location
	if _sim != null and _sim.location != null and _sim.location.is_inside():
		return _sim.location.get_inside_building()
	return null


func _is_player_home_location(building: Building) -> bool:
	if building == null:
		return false
	if home != null and building == home:
		return true
	return building is ResidentialBuilding and _player_slot_building == building and _player_slot_kind == "tenant"


func _ensure_player_hired_for_current_job(world: World) -> bool:
	if job == null or job.workplace == null:
		return false
	if not job.try_get_employed(self):
		return false
	if _player_slot_building == job.workplace and _player_slot_kind == "visitor":
		if job.workplace.has_method("remove_visitor"):
			job.workplace.remove_visitor(self)
		_player_slot_kind = "worker"
	if world != null and world.has_method("register_job"):
		world.register_job(job)
	return true


func _player_has_accepted_job_at(workplace: Building) -> bool:
	if network_replica_mode:
		return workplace != null \
			and job != null \
			and job.workplace == workplace
	return workplace != null \
		and job != null \
		and job.workplace == workplace \
		and workplace.workers.has(self)


func _workplace_has_open_application_slot(workplace: Building, world: World) -> bool:
	if workplace == null:
		return false
	if not workplace.can_accept_workers():
		return false
	if workplace.workers.has(self):
		return true
	var committed: Dictionary = {}
	if world != null and "jobs" in world:
		for existing_job in world.jobs:
			if existing_job == null or existing_job.workplace != workplace:
				continue
			committed[existing_job.get_instance_id()] = true
	for worker in workplace.workers:
		if worker == null:
			continue
		if worker.job != null and worker.job.workplace == workplace:
			committed[worker.job.get_instance_id()] = true
		else:
			committed["worker_%d" % worker.get_instance_id()] = true
	return committed.size() < int(workplace.job_capacity)


func _build_player_job_for_workplace(workplace: Building) -> Job:
	if workplace == null:
		return null
	var player_job := Job.new()
	player_job.title = _get_player_job_title_for_workplace(workplace)
	player_job.wage_per_hour = CitizenFactory.get_wage_for_job_title(player_job.title)
	player_job.shift_hours = 8
	player_job.required_education_level = CitizenFactory.get_required_education_for_job_title(player_job.title)
	player_job.workplace = workplace
	player_job.preferred_workplace = workplace
	player_job.workplace_service_type = workplace.get_service_type()
	player_job.allowed_building_types = [int(workplace.building_type)]
	return player_job


func _get_player_job_title_for_workplace(workplace: Building) -> String:
	if workplace == null:
		return "Worker"
	return workplace.get_default_job_title()


func _update_work_day(world: Node) -> void:
	if _sim == null or _sim.scheduler == null:
		return
	_sim.scheduler.update_work_day(world)


## Simplified `prepare_go_to_target` — checks the unreachable cache. Returning
## `null` when blocked. Building-discovery substitution (legacy
## `_find_alternative_for_building`) is NOT yet ported; callers that depend
## on automatic retargeting must check the alternative themselves until a
## Building-Discovery service is extracted.
func prepare_go_to_target(target: Building, world: Node) -> Building:
	if target == null or _sim == null or _sim.scheduler == null:
		return target
	if _sim.scheduler.is_target_temporarily_unreachable(target, world):
		var remaining := _sim.scheduler.get_target_remaining_minutes(target, world)
		debug_log_once_per_day(
				"target_cooldown_%d" % target.get_instance_id(),
				"Skipping temporarily unreachable target (%d sim-min remaining)." % remaining)
		return null
	return target


## Simplified `handle_unreachable_target` — marks the target. Returns null
## (legacy version returned an alternative; building-discovery service to come).
func handle_unreachable_target(target: Building, world: Node, reason: String = "") -> Building:
	if target == null or _sim == null or _sim.scheduler == null:
		return null
	if _sim.scheduler.mark_target_unreachable(target, world):
		debug_log("Marked target unreachable for %d sim-min (%s)." % [
				_sim.scheduler.unreachable_target_cooldown_minutes,
				reason if reason != "" else "navigation failure"])
	return null


# ========================================================================
# LOD API — delegates to CitizenLodComponent.
# Facade owns the side effects: physics_process toggle, presence layer,
# World.notify_citizen_lod_changed. Component owns the state.
# ========================================================================

## Default decision-cooldown range when no LOD profile is active.
## Pulled from the legacy Citizen.gd `@export` defaults — Scheduler
## migration will move these onto the Scheduler component.
const _DEFAULT_DECISION_COOLDOWN_MIN: int = 5
const _DEFAULT_DECISION_COOLDOWN_MAX: int = 20

func get_simulation_lod_tier() -> String:
	if network_replica_mode and not _network_lod_tier.is_empty():
		return _network_lod_tier
	if _sim == null or _sim.lod == null:
		return CitizenLodComponent.TIER_FOCUS
	return _sim.lod.tier


func set_simulation_lod_state(p_tier: String, rendered: bool, physics_enabled: bool,
		tick_interval_minutes: int = 1) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.set_state(p_tier, rendered, tick_interval_minutes)
	# Side-effects on the CharacterBody3D side:
	_apply_lod_presence_state()
	var should_process_physics := physics_enabled or accept_click_input
	set_physics_process(should_process_physics)
	if not should_process_physics:
		velocity = Vector3.ZERO
	if _sim.world != null and is_instance_valid(_sim.world) \
			and _sim.world.has_method("notify_citizen_lod_changed"):
		_sim.world.notify_citizen_lod_changed(self)


func apply_simulation_lod_runtime_profile(profile: Dictionary, world: Node = null) -> void:
	if _sim == null or _sim.lod == null:
		return
	# Capture defaults once — repath/local-avoidance values are pulled from
	# the new-stack equivalents.
	_sim.lod.capture_runtime_defaults(local_astar_replan_interval, use_local_astar_avoidance)
	var resolved := _sim.lod.apply_runtime_profile(profile)
	# Apply the resolved settings to the new-stack navigation knobs.
	# `repath_interval_sec` (legacy) → `local_astar_replan_interval` (new).
	# `local_avoidance` → `use_local_astar_avoidance` (toggle the whole detour).
	local_astar_replan_interval = float(resolved.get("repath_interval_sec",
			local_astar_replan_interval))
	use_local_astar_avoidance = bool(resolved.get("local_avoidance",
			use_local_astar_avoidance))
	if world != null and _sim != null:
		_sim.set_world(world)


func get_simulation_lod_decision_cooldown_range_minutes(world: Node) -> Vector2i:
	if _sim == null or _sim.lod == null:
		return Vector2i(_DEFAULT_DECISION_COOLDOWN_MIN, _DEFAULT_DECISION_COOLDOWN_MAX)
	return _sim.lod.get_decision_cooldown_range_minutes(world,
			_DEFAULT_DECISION_COOLDOWN_MIN, _DEFAULT_DECISION_COOLDOWN_MAX)


func should_run_simulation_lod_tick(world: Node) -> bool:
	if _sim == null or _sim.lod == null:
		return true
	if world == null:
		return true
	if _sim.lod.tier != CitizenLodComponent.TIER_COARSE:
		return true
	# Coarse tier asks the World scheduler — Facade has the citizen ref World needs.
	if not world.has_method("is_citizen_due_for_simulation"):
		return true
	return world.is_citizen_due_for_simulation(self)


func get_simulation_lod_tick_interval_minutes() -> int:
	if _sim == null or _sim.lod == null:
		return 1
	return _sim.lod.get_tick_interval_minutes()


func get_simulation_lod_tick_interval_ticks(world: Node) -> int:
	if _sim == null or _sim.lod == null:
		return 1
	return _sim.lod.get_tick_interval_ticks(world)


func get_simulation_lod_tick_slot(world: Node) -> int:
	if _sim == null or _sim.lod == null:
		return 0
	return _sim.lod.get_tick_slot(world)


func add_lod_commitment(commitment_type: String, until_day: int, until_minute: int,
		priority: float = 1.0) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.add_commitment(commitment_type, until_day, until_minute, priority)


func upsert_lod_commitment(commitment_type: String, until_day: int, until_minute: int,
		priority: float = 1.0, metadata: Dictionary = {}) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.upsert_commitment(commitment_type, until_day, until_minute, priority, metadata)


func remove_lod_commitment(commitment_type: String) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.remove_commitment(commitment_type)


func remove_lod_commitments(commitment_types: Array) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.remove_commitments(commitment_types)


func _refresh_network_player_lod_commitment(world: Node = null) -> void:
	if _sim == null or _sim.lod == null:
		return
	var until_day := 1
	var until_minute := 60
	if world != null and "time" in world and world.time != null:
		var current_day := int(world.time.day)
		var total_minutes := int(world.time.minutes_total) + 60
		until_day = current_day + int(total_minutes / (24 * 60))
		until_minute = posmod(total_minutes, 24 * 60)
	_sim.lod.upsert_commitment("player_interest", until_day, until_minute, 100.0, {
		"source": "network_player",
	})


func clear_expired_lod_commitments(world: Node) -> void:
	if _sim == null or _sim.lod == null:
		return
	_sim.lod.clear_expired_commitments(world)


func has_active_lod_commitment(world: Node, required_types: Array = []) -> bool:
	if _sim == null or _sim.lod == null:
		return false
	return _sim.lod.has_active_commitment(world, required_types)


func get_active_lod_commitments(world: Node) -> Array:
	if _sim == null or _sim.lod == null:
		return []
	return _sim.lod.get_active_commitments(world)


func set_runtime_conversation_state(mode: String, partner_name: String = "", topic: String = "") -> void:
	_runtime_conversation_mode = mode
	_runtime_conversation_partner = partner_name
	_runtime_conversation_topic = topic


func clear_runtime_conversation_state() -> void:
	_runtime_conversation_mode = ""
	_runtime_conversation_partner = ""
	_runtime_conversation_topic = ""


func get_runtime_conversation_label() -> String:
	if _runtime_conversation_mode == "":
		return "-"
	var parts: Array[String] = [_runtime_conversation_mode]
	if _runtime_conversation_partner != "":
		parts.append("with %s" % _runtime_conversation_partner)
	if _runtime_conversation_topic != "":
		parts.append("topic=%s" % _runtime_conversation_topic)
	return " ".join(parts)


func is_active_player_dialog_session() -> bool:
	return _runtime_conversation_mode == "interactive" \
		and _runtime_conversation_partner == "Player" \
		and _runtime_conversation_topic == "player_dialog"


func face_position_horizontal(target_position: Vector3) -> void:
	var facing_dir := target_position - global_position
	facing_dir.y = 0.0
	if facing_dir.length_squared() <= 0.0001:
		return
	rotation.y = atan2(-facing_dir.x, -facing_dir.z)


func get_home_rotation_candidate_day() -> int:
	return _home_rotation_candidate_day


func is_safe_home_rotation_candidate(world: World) -> bool:
	var at_home_idle := home != null \
		and current_location == home \
		and current_action == null \
		and not is_travelling() \
		and not is_manual_control_enabled() \
		and not is_click_move_mode_enabled()
	if at_home_idle:
		if _home_rotation_candidate_day < 0 and world != null:
			_home_rotation_candidate_day = world.world_day()
	else:
		_home_rotation_candidate_day = -1
	return at_home_idle and not has_active_lod_commitment(world)


func _is_eligible_for_cheap_lod() -> bool:
	if is_manual_control_enabled() or is_click_move_mode_enabled():
		return false
	if _selection_active:
		return false
	var path_mode := _simulation_lod_path_mode
	if path_mode == "full":
		return false
	if path_mode == "cheap":
		return true
	if not cheap_path_follow_lod_enabled:
		return false
	var tier := get_simulation_lod_tier()
	if tier == CitizenLodComponent.TIER_ACTIVE or tier == CitizenLodComponent.TIER_COARSE:
		return true
	var viewport := get_viewport()
	if viewport == null:
		return false
	var camera := viewport.get_camera_3d()
	if camera == null:
		return false
	var threshold := maxf(cheap_path_follow_camera_distance, 0.0)
	if threshold <= 0.0:
		return true
	var planar_camera_delta := global_position - camera.global_position
	planar_camera_delta.y = 0.0
	return planar_camera_delta.length_squared() >= threshold * threshold


## Combines LOD-presence-flag and indoor-presence-flag — both can hide the
## body. The order matters: indoor presence is set via `_set_interior_presence`
## above; LOD presence reuses the same toggle but ORs the flag.
func _apply_lod_presence_state() -> void:
	_apply_combined_presence_state()


func _apply_combined_presence_state() -> void:
	if _sim == null or _sim.lod == null:
		return
	# When LOD wants to hide and we're not already hidden by indoor presence,
	# trigger the hide path. When LOD wants to show but we ARE indoor, the
	# indoor flag wins.
	var should_hide := _sim.lod.presence_hidden or _interior_presence_hidden
	if should_hide and visible:
		hide()
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
	elif not should_hide and not visible:
		show()
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask


# ========================================================================
# Manual control + click-move + autonomous flag — orchestrates state
# changes (rest-pose, building exit, travel stop) when the mode toggles.
# Component holds the bare flags; Facade owns the side-effect pipeline.
# ========================================================================

func _is_body_presence_hidden() -> bool:
	var lod_hidden := _sim != null and _sim.lod != null and _sim.lod.presence_hidden
	return _interior_presence_hidden or lod_hidden


func is_autonomous_simulation_enabled() -> bool:
	return autonomous_simulation_enabled


func is_manual_control_enabled() -> bool:
	return _sim != null and _sim.manual_control != null and _sim.manual_control.is_manual_enabled()


func set_manual_control_enabled(enabled: bool, world: Node = null) -> void:
	if _sim == null or _sim.manual_control == null:
		return
	if _sim.manual_control.is_manual_enabled() == enabled:
		return
	_sim.manual_control.set_manual_enabled(enabled)
	if enabled:
		clear_rest_pose(true)
		if is_inside_building():
			exit_current_building(world)
		elif current_location != null:
			leave_current_location(world)
		stop_travel()
		release_reserved_benches(world)
		current_action = null
		decision_cooldown_left = 0
		velocity = Vector3.ZERO
		_sim.manual_control.set_input_locked(false)
		_update_trace_navigation_state("manual_control", Vector3.ZERO, Vector3.ZERO)
	else:
		stop_travel()
		decision_cooldown_left = 0
		velocity = Vector3.ZERO
		_sim.manual_control.set_input_locked(false)
		_update_trace_navigation_state("manual_control_exit", Vector3.ZERO, Vector3.ZERO)


func is_manual_control_input_locked() -> bool:
	return _sim != null and _sim.manual_control != null and _sim.manual_control.is_input_locked()


func set_manual_control_input_locked(locked: bool) -> void:
	if _sim == null or _sim.manual_control == null:
		return
	_sim.manual_control.set_input_locked(locked)
	if locked:
		velocity.x = 0.0
		velocity.z = 0.0


func is_click_move_mode_enabled() -> bool:
	return _sim != null and _sim.manual_control != null and _sim.manual_control.is_click_move_enabled()


func set_click_move_mode_enabled(enabled: bool, world: Node = null) -> void:
	if _sim == null or _sim.manual_control == null:
		return
	if _sim.manual_control.is_click_move_enabled() == enabled:
		return
	_sim.manual_control.set_click_move_enabled(enabled)
	if enabled:
		clear_rest_pose(true)
		stop_travel()
		_update_trace_navigation_state("click_move_mode", Vector3.ZERO, Vector3.ZERO)
	else:
		stop_travel()
		_update_trace_navigation_state("click_move_mode_exit", Vector3.ZERO, Vector3.ZERO)


## Begins a click-move trip to `target_pos`. Snaps to the world's
## pedestrian-access-point if available. Returns true iff a path was found.
func begin_click_move_to(target_pos: Vector3, world: Node = null) -> bool:
	if _sim == null:
		return false
	if is_manual_control_enabled():
		set_manual_control_enabled(false, world)
	clear_rest_pose(true)
	if is_inside_building():
		exit_current_building(world)
	elif current_location != null:
		leave_current_location(world, false)
	release_reserved_benches(world)
	current_action = null
	decision_cooldown_left = 0
	stop_travel()
	current_location = null

	var snapped_target := target_pos
	if world != null and world.has_method("get_pedestrian_access_point"):
		snapped_target = world.get_pedestrian_access_point(target_pos)
	return set_global_target(snapped_target)


# ========================================================================
# Bench reservation — delegates to CitizenBenchReservation.
# ========================================================================

func release_reserved_benches(world: Node = null, building: Building = null) -> void:
	if _sim == null or _sim.bench_reservation == null:
		return
	_sim.bench_reservation.release(world, building, current_location)


# ========================================================================
# Location API — delegates to CitizenLocation, orchestrates state on the
# CharacterBody3D side (position, presence toggle, building callbacks).
# ========================================================================

func is_inside_building() -> bool:
	if network_replica_mode:
		return _network_inside_building
	return _sim != null and _sim.location != null and _sim.location.is_inside()


func get_navigation_points_for_building(building: Building, world: Node = null) -> Dictionary:
	if _sim == null or _sim.location == null:
		return {}
	var name_for_offset := _sim.identity.citizen_name if _sim.identity != null else citizen_name
	var reserved_bench: Dictionary = {}
	if building != null and building.has_method("get_reserved_bench_for"):
		reserved_bench = building.get_reserved_bench_for(self)
	return CitizenLocation.resolve_navigation_points(
			building, world, name_for_offset, global_position, reserved_bench)


var _player_slot_building: Building = null
var _player_slot_kind: String = ""

func enter_building(building: Building, world: Node = null, emit_log: bool = true, skip_occupancy_callback: bool = false) -> void:
	if building == null or _sim == null or _sim.location == null:
		return
	clear_rest_pose(true)
	if current_location != building:
		release_reserved_benches(world, current_location)
	var name_for_offset := _sim.identity.citizen_name if _sim.identity != null else citizen_name
	var nav_points := CitizenLocation.resolve_navigation_points(
			building, world, name_for_offset, global_position)
	var entry_pos := global_position
	stop_travel()
	current_location = building
	var is_outdoor: bool = building.has_method("is_outdoor_destination") and building.is_outdoor_destination()
	if is_outdoor:
		_sim.location.clear_inside_building()
	else:
		if nav_points.has("spawn"):
			_set_position_grounded(nav_points["spawn"] as Vector3)
		_sim.location.set_inside_building(building)
	if not skip_occupancy_callback and building.has_method("on_citizen_entered"):
		# Use dynamic call() to bypass the legacy `Citizen` typed parameter on
		# Building.on_citizen_entered. The Facade isn't `Citizen` (yet) but
		# building callbacks only need a Node — type-tightening on Building's
		# side will happen during the Building-Discovery refactor.
		building.call("on_citizen_entered", self)
	_set_interior_presence(not is_outdoor)
	if emit_log and SimLoggerScript != null:
		SimLoggerScript.log("[Citizen %s] Entered %s at %s" % [
				_get_log_name(),
				building.get_display_name() if building.has_method("get_display_name") else "?",
				_fmt_v3(entry_pos)])


## Player-driven building entry (R key). Residential entry is an inspection
## unless it is already the player's home. Every other building is entered as
## a plain visitor unless the player is already accepted as a worker there.
## Employment is opt-in via the "Bewerben" action (player_apply_for_work).
func player_enter_building(building: Building, world: Node = null) -> bool:
	if building == null or _sim == null or _sim.location == null:
		return false
	if is_inside_building():
		return false
	_player_action_notice = ""
	var kind := ""
	var ok := false
	if building is ResidentialBuilding:
		var residential := building as ResidentialBuilding
		if home == residential:
			ok = residential.tenants.has(self) or residential.add_tenant(self)
			kind = "tenant"
		else:
			ok = true
			kind = "residential_visit"
	elif job != null and job.workplace == building and building.workers.has(self):
		ok = true
		kind = "worker"
	else:
		ok = building.try_add_visitor(self)
		kind = "visitor"
	if not ok:
		return false
	enter_building(building, world, true, true)
	_player_slot_building = building
	_player_slot_kind = kind
	return true


## Player-driven building exit (T key). Exiting only leaves the building.
## Jobs and home leases persist until their explicit quit buttons are used.
func player_exit_building(world: Node = null) -> bool:
	if not is_inside_building():
		return false
	var resolved_world := _resolve_world_arg(world)
	cancel_player_action(resolved_world)
	exit_current_building(world)
	_player_slot_building = null
	_player_slot_kind = ""
	_player_action_notice = ""
	return true


func leave_current_location(world: Node = null, emit_log: bool = true) -> void:
	if _sim == null:
		return
	if is_inside_building():
		exit_current_building(world)
		return
	if current_location == null:
		return

	var exit_building := current_location
	clear_rest_pose(true)
	release_reserved_benches(world, exit_building)
	var name_for_offset := _sim.identity.citizen_name if _sim.identity != null else citizen_name
	var nav_points := CitizenLocation.resolve_navigation_points(
			exit_building, world, name_for_offset, global_position)
	var is_outdoor: bool = exit_building.has_method("is_outdoor_destination") \
			and exit_building.is_outdoor_destination()
	var exit_pos: Vector3 = nav_points.get("spawn",
			nav_points.get("access", global_position)) as Vector3
	if is_outdoor:
		_set_position_grounded(exit_pos)
	current_location = null
	if exit_building.has_method("on_citizen_exited"):
		exit_building.call("on_citizen_exited", self)
	if emit_log and SimLoggerScript != null:
		SimLoggerScript.log("[Citizen %s] Left %s at %s" % [
				_get_log_name(),
				exit_building.get_display_name() if exit_building.has_method("get_display_name") else "?",
				_fmt_v3(global_position)])


func exit_current_building(world: Node = null) -> void:
	if _sim == null or _sim.location == null:
		return
	var exit_building := _sim.location.get_inside_building()
	if exit_building == null:
		return

	clear_rest_pose(true)
	var name_for_offset := _sim.identity.citizen_name if _sim.identity != null else citizen_name
	var nav_points := CitizenLocation.resolve_navigation_points(
			exit_building, world, name_for_offset, global_position)
	var exit_pos: Vector3 = nav_points.get("spawn", global_position) as Vector3

	_sim.location.clear_inside_building()
	if exit_building.has_method("on_citizen_exited"):
		exit_building.call("on_citizen_exited", self)
	_set_interior_presence(false)
	_set_position_grounded(exit_pos)
	if SimLoggerScript != null:
		SimLoggerScript.log("[Citizen %s] Exited %s at %s" % [
				_get_log_name(),
				exit_building.get_display_name() if exit_building.has_method("get_display_name") else "?",
				_fmt_v3(global_position)])


# ----------------------------- presence toggle -----------------------------
# Hide/show + collision toggle. Simpler than legacy Citizen.gd because the
# new stack has no Sensor-Area/Click-Area sub-nodes that need disabling.

func _set_interior_presence(hidden: bool) -> void:
	_interior_presence_hidden = hidden
	if _sim == null or _sim.lod == null:
		if hidden:
			hide()
			velocity = Vector3.ZERO
			collision_layer = 0
			collision_mask = 0
		else:
			show()
			collision_layer = _saved_collision_layer
			collision_mask = _saved_collision_mask
		return
	_apply_combined_presence_state()


func _set_position_grounded(pos: Vector3) -> void:
	# Keep teleports/exits on the walkable floor; otherwise failed short
	# routes can leave the body falling in place at building entrances.
	if is_inside_tree():
		global_position = _project_navigation_target_to_ground(pos)
	else:
		global_position = pos
	velocity = Vector3.ZERO


func _get_log_name() -> String:
	if _sim != null and _sim.identity != null:
		return _sim.identity.citizen_name
	return citizen_name


static func _fmt_v3(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


# ========================================================================
# Trace state — delegates to CitizenTraceState. Method name intentionally
# starts with underscore so the existing `has_method`-guarded caller in
# `CitizenAgent.gd:36` keeps working without modification.
# ========================================================================

func _update_trace_navigation_state(reason: String, desired_dir: Vector3, move_dir: Vector3) -> void:
	if _sim == null or _sim.trace == null:
		return
	_sim.trace.update_navigation(reason, desired_dir, move_dir)


# Override of CitizenController.set_trace_state — der Controller ruft das per
# dynamic dispatch aus dem Movement-Loop, damit der CitizenTrace-Logger jeden
# Tick aktuelle reason/desired/move-Werte sieht statt Default-"idle".
func set_trace_state(reason: String, desired_dir: Vector3, move_dir: Vector3) -> void:
	_update_trace_navigation_state(reason, desired_dir, move_dir)


var _trace_last_decision_reason: String:
	get:
		return _sim.trace.last_decision_reason if _sim != null and _sim.trace != null else "idle"
	set(value):
		if _sim != null and _sim.trace != null:
			_sim.trace.last_decision_reason = value

var _trace_last_desired_dir: Vector3:
	get:
		return _sim.trace.last_desired_dir if _sim != null and _sim.trace != null else Vector3.ZERO
	set(value):
		if _sim != null and _sim.trace != null:
			_sim.trace.last_desired_dir = value

var _trace_last_move_dir: Vector3:
	get:
		return _sim.trace.last_move_dir if _sim != null and _sim.trace != null else Vector3.ZERO
	set(value):
		if _sim != null and _sim.trace != null:
			_sim.trace.last_move_dir = value


# ========================================================================
# Debug logging — delegates to CitizenDebugFacade. Kept on the Facade as
# `debug_log` / `debug_log_once_per_day` because callers (Actions, GOAP,
# CitizenPlanner) call those names directly.
# ========================================================================

func debug_log(message: String) -> void:
	if _sim == null or _sim.debug_facade == null:
		return
	_sim.debug_facade.emit_log(_get_log_name(), message)


func debug_log_once_per_day(key: String, message: String) -> void:
	if _sim == null or _sim.debug_facade == null:
		return
	# `_sim.world` is set via `set_world_ref` from CitizenAgent before any
	# action runs — null-safe path covers headless tests.
	_sim.debug_facade.log_once_per_day(_sim.world, _get_log_name(), key, message)


## Compact one-line per-citizen summary for `RuntimeDebugLogger`. Reduced
## compared to legacy `get_trace_debug_summary()`: omits the four sensor-ray
## fields (no equivalent in the new stack) and the crowd/repath counters
## (live in not-yet-extracted Scheduler/LocalPerception).
func get_trace_debug_summary() -> String:
	var n := _get_log_name()
	var inside := "-"
	if _sim != null and _sim.location != null and _sim.location.is_inside():
		var b := _sim.location.get_inside_building()
		if b != null and b.has_method("get_display_name"):
			inside = b.get_display_name()
	var loc := "-"
	if current_location != null and current_location.has_method("get_display_name"):
		loc = current_location.get_display_name()
	var reason := _sim.trace.last_decision_reason if _sim != null and _sim.trace != null else "idle"
	var desired := _sim.trace.last_desired_dir if _sim != null and _sim.trace != null else Vector3.ZERO
	var move := _sim.trace.last_move_dir if _sim != null and _sim.trace != null else Vector3.ZERO
	return "citizen=%s pos=%s vel=%s on_floor=%s travelling=%s location=%s inside=%s decision=%s desired=%s move=%s" % [
		n,
		CitizenTraceState.fmt_v3(global_position),
		CitizenTraceState.fmt_v3(velocity),
		str(is_on_floor()),
		str(is_travelling()),
		loc,
		inside,
		reason,
		CitizenTraceState.fmt_v3(desired),
		CitizenTraceState.fmt_v3(move),
	]


# ========================================================================
# Sim API surface — forwarded into CitizenSimulation/components.
# Method names match legacy `Citizen.gd` so existing callers can use this
# Facade as a drop-in once they are pointed at it.
# ========================================================================

func set_world_ref(p_world: Node) -> void:
	_world_ref = p_world as World
	if _sim != null:
		_sim.set_world(p_world)
	if network_replica_mode:
		return
	_auto_resolved_refs = false
	call_deferred("_auto_resolve_refs")


func sim_tick(p_world: Node) -> void:
	if network_replica_mode:
		return
	if not should_run_simulation_lod_tick(p_world):
		return
	if _sim != null:
		_sim.tick(p_world)
	if _agent != null:
		_agent.sim_tick(self, p_world)


func notify_job_lost(_old_workplace: Building = null, reason: String = "") -> void:
	var world := _resolve_world_ref()
	var origin := global_position if is_inside_tree() else position

	if _try_reassign_existing_job(world, origin):
		return
	if _try_assign_best_job_offer(world, origin):
		return

	if job != null:
		SimLoggerScript.log("[Citizen %s] job lost (%s), no replacement found: %s" % [
			citizen_name,
			reason,
			get_unemployment_debug_reason()
		])


func _try_reassign_existing_job(world: World, origin: Vector3) -> bool:
	if job == null:
		return false
	if job.workplace != null and job.workplace.has_free_job_slots():
		return _try_hire_current_job(world)
	var replacement: Building = null
	if world != null and world.has_method("find_best_workplace_for_job"):
		replacement = world.find_best_workplace_for_job(origin, job, self)
	if replacement == null:
		if not is_inside_tree():
			return false
		job.resolve_nearest(self, origin)
	else:
		job.workplace = replacement
	return _try_hire_current_job(world)


func _try_assign_best_job_offer(world: World, origin: Vector3) -> bool:
	if world == null or not world.has_method("find_best_job_offer_for_citizen"):
		return false
	var offer: Dictionary = world.find_best_job_offer_for_citizen(origin, self, false)
	if offer.is_empty():
		return false
	var new_job := _build_job_from_offer(offer)
	if new_job == null:
		return false
	job = new_job
	return _try_hire_current_job(world)


func _build_job_from_offer(offer: Dictionary) -> Job:
	return CitizenFactory.build_job_from_offer(offer)


func _try_hire_current_job(world: World) -> bool:
	if job == null:
		return false
	if not job.try_get_employed(self):
		return false
	if world != null and world.has_method("register_job"):
		world.register_job(job)
	return true


func _resolve_world_ref() -> World:
	if _world_ref != null:
		return _world_ref
	var current: Node = get_parent()
	while current != null:
		if current is World:
			_world_ref = current as World
			return _world_ref
		current = current.get_parent()
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("world"):
		if node is World:
			_world_ref = node as World
			return _world_ref
	return null


func _resolve_world_arg(world: Node = null) -> World:
	if world is World:
		return world as World
	return _resolve_world_ref()


func plan_next_action(world: World) -> void:
	if _agent != null and _agent.planner != null:
		_agent.planner.plan_next_action(world, self)


func start_action(a: Action, world: World) -> void:
	if a == null:
		return
	clear_rest_pose(true)
	if a is GoToBuildingAction and is_inside_building():
		exit_current_building(world)
	elif a is GoToBuildingAction and current_location != null:
		leave_current_location(world)

	current_action = a
	current_action.start(world, self)

	if world != null and world.time != null:
		var loc := _building_label(current_location) if current_location != null else "travelling"
		if a is GoToBuildingAction:
			var target := (a as GoToBuildingAction).target
			if target != null:
				loc = "-> " + _building_label(target)
		SimLoggerScript.log("[%s] %02d:%02d (%s) | %-10s | H:%.0f E:%.0f F:%.0f HP:%.0f | $%d | at=%s" % [
			citizen_name,
			world.time.get_hour(),
			world.time.get_minute(),
			world.time.get_weekday_name(),
			a.label,
			needs.hunger if needs != null else 0.0,
			needs.energy if needs != null else 0.0,
			needs.fun if needs != null else 0.0,
			needs.health if needs != null else 0.0,
			wallet.balance if wallet != null else 0,
			loc
		])


func begin_travel_to(target_pos: Vector3, target_building: Building = null) -> bool:
	_debug_travel_target_building = target_building
	_travel_target = target_pos
	_travel_target_building = target_building
	_debug_last_travel_failed = false
	var ok := set_global_target(target_pos)
	if ok:
		_travel_target = _target_position
	_debug_last_travel_route = PackedVector3Array(_global_path)
	if not ok:
		_debug_last_travel_failed = true
	return ok


func begin_custom_travel_route(route_points: PackedVector3Array,
		target_building: Building = null) -> bool:
	var route := PackedVector3Array()
	route.append(global_position)
	for point in route_points:
		if route[route.size() - 1].distance_to(point) > 0.15:
			route.append(point)

	if route.size() < 2:
		_debug_last_travel_failed = true
		return false
	_debug_travel_target_building = target_building
	_travel_target = route[route.size() - 1]
	_travel_target_building = target_building
	_debug_last_travel_failed = false
	_global_path = route
	_path_index = 1
	_target_position = route[route.size() - 1]
	_is_travelling = true
	_debug_last_travel_route = PackedVector3Array(route)
	_stuck.reset_for_new_target(global_position)
	_debug.update_global_path(_global_path, _path_index)
	return true


func has_reached_travel_target() -> bool:
	if _debug_last_travel_failed:
		return false
	if _is_travelling:
		return false
	if not _global_path.is_empty() and _path_index >= _global_path.size():
		return true
	var final_target := _target_position
	if _travel_target != Vector3.ZERO or _travel_target_building != null:
		final_target = _travel_target
	var tolerance := maxf(final_arrival_distance + 0.05, waypoint_reach_distance + 0.05)
	return _planar_distance(global_position, final_target) <= tolerance


func did_debug_last_travel_fail() -> bool:
	return _debug_last_travel_failed


func get_debug_travel_route_points() -> PackedVector3Array:
	if not _global_path.is_empty():
		return PackedVector3Array(_global_path)
	return PackedVector3Array(_debug_last_travel_route)


func get_debug_travel_target_building() -> Building:
	return _debug_travel_target_building


func has_debug_travel_route() -> bool:
	return get_debug_travel_route_points().size() >= 2


func is_debug_travelling() -> bool:
	return _is_travelling


func get_debug_travel_current_target() -> Vector3:
	if not _global_path.is_empty() and _path_index >= 0 and _path_index < _global_path.size():
		return _global_path[_path_index]
	return _target_position


func get_debug_travel_route_index() -> int:
	return _path_index


func get_remaining_travel_distance() -> float:
	if _global_path.is_empty():
		return 0.0
	var total := 0.0
	var cursor := global_position
	for index in range(maxi(_path_index, 0), _global_path.size()):
		var point := _global_path[index]
		total += _planar_distance(cursor, point)
		cursor = point
	return total


func pay_rent(world: World, landlord: ResidentialBuilding, amount: int) -> bool:
	if landlord == null:
		return false
	if amount <= 0:
		return true
	if wallet == null:
		SimLoggerScript.log("[%s] Could not pay rent! Wallet missing." % citizen_name)
		return false
	var resolved_world := world if world != null else _resolve_world_ref()
	if resolved_world == null or resolved_world.economy == null:
		SimLoggerScript.log("[%s] Could not pay rent! Economy unavailable." % citizen_name)
		return false

	var before := wallet.balance
	var success := resolved_world.economy.transfer(wallet, landlord.account, amount)
	if success:
		SimLoggerScript.log("[%s] Rent paid: %d EUR (balance: %d -> %d)" % [
			citizen_name,
			amount,
			before,
			wallet.balance
		])
		return true

	SimLoggerScript.log("[%s] Could not pay rent! Need %d EUR, have %d EUR" % [
		citizen_name,
		amount,
		wallet.balance
	])
	return false


func can_afford_restaurant_at(restaurant: Restaurant, world: World) -> bool:
	if restaurant == null or wallet == null:
		return false
	var price: int = restaurant.meal_price
	if restaurant.has_method("get_meal_price"):
		price = int(restaurant.get_meal_price(world))
	return wallet.balance >= price


func can_afford_restaurant(world: World) -> bool:
	return can_afford_restaurant_at(favorite_restaurant, world)


func can_afford_groceries_at(supermarket: Supermarket, world: World) -> bool:
	if supermarket == null or wallet == null:
		return false
	var price: int = supermarket.grocery_price
	if supermarket.has_method("get_grocery_price"):
		price = int(supermarket.get_grocery_price(world))
	return wallet.balance >= price


func can_afford_groceries(world: World) -> bool:
	return can_afford_groceries_at(favorite_supermarket, world)


func can_afford_shop_item_at(shop: Shop, _world: World) -> bool:
	if shop == null or wallet == null:
		return false
	return wallet.balance >= _get_shop_item_price(shop)


func can_afford_shop_item(world: World) -> bool:
	return can_afford_shop_item_at(favorite_shop, world)


func can_buy_shop_item_at(shop: Shop, world: World) -> bool:
	if shop == null or world == null:
		return false
	return shop.is_open(world.time.get_hour()) \
		and shop.can_sell_item("clothing", 1) \
		and can_afford_shop_item_at(shop, world)


func can_buy_groceries_at(supermarket: Supermarket, world: World) -> bool:
	if supermarket == null or world == null:
		return false
	return supermarket.is_open(world.time.get_hour()) \
		and supermarket.can_sell_item("grocery_bundle", 1) \
		and can_afford_groceries_at(supermarket, world)


func _get_shop_item_price(shop: Shop) -> int:
	if shop == null:
		return 0
	if shop.has_method("get_item_price_quote"):
		return int(shop.get_item_price_quote(1.0))
	return maxi(int(shop.item_price), 1)


func _shop_buy_disabled_reason(shop: Shop, world: World, item: String, price: int) -> String:
	if current_action != null:
		return "Aktion laeuft noch."
	if shop == null or world == null:
		return "Kein Shop aktiv."
	if not shop.is_open(world.time.get_hour()):
		return "Shop geschlossen."
	if not shop.can_sell_item(item, 1):
		return "Ausverkauft."
	if wallet == null or wallet.balance < price:
		return "Zu wenig Geld."
	return ""


func can_afford_cinema(_world: World) -> bool:
	if favorite_cinema == null or wallet == null:
		return false
	return wallet.balance >= favorite_cinema.ticket_price


func set_position_grounded(pos: Vector3) -> void:
	_set_position_grounded(pos)


func _find_nearest_restaurant(from_pos: Vector3, require_open: bool = true) -> Restaurant:
	if _agent == null or _agent.query_resolver == null:
		return null
	return _agent.query_resolver.find_nearest_restaurant(self, from_pos, require_open)


func _find_nearest_restaurant_with_meal(from_pos: Vector3, require_open: bool = true) -> Restaurant:
	if _agent == null or _agent.query_resolver == null:
		return null
	if _agent.query_resolver.has_method("find_nearest_restaurant_with_meal"):
		return _agent.query_resolver.find_nearest_restaurant_with_meal(self, from_pos, require_open)
	return _agent.query_resolver.find_nearest_restaurant(self, from_pos, require_open)


func _find_nearest_supermarket(from_pos: Vector3, require_open: bool = true) -> Supermarket:
	if _agent == null or _agent.query_resolver == null:
		return null
	return _agent.query_resolver.find_nearest_supermarket(self, from_pos, require_open)


func _find_nearest_supermarket_with_groceries(from_pos: Vector3, require_open: bool = true) -> Supermarket:
	if _agent == null or _agent.query_resolver == null:
		return null
	if _agent.query_resolver.has_method("find_nearest_supermarket_with_groceries"):
		return _agent.query_resolver.find_nearest_supermarket_with_groceries(self, from_pos, require_open)
	return _agent.query_resolver.find_nearest_supermarket(self, from_pos, require_open)


func _find_nearest_shop(from_pos: Vector3, require_open: bool = true) -> Shop:
	if _agent == null or _agent.query_resolver == null:
		return null
	return _agent.query_resolver.find_nearest_shop(self, from_pos, require_open)


func _find_nearest_cinema(from_pos: Vector3, require_open: bool = true) -> Cinema:
	if _agent == null or _agent.query_resolver == null:
		return null
	return _agent.query_resolver.find_nearest_cinema(self, from_pos, require_open)


func _find_nearest_university(from_pos: Vector3, require_open: bool = true) -> University:
	if _agent == null or _agent.query_resolver == null:
		return null
	return _agent.query_resolver.find_nearest_university(self, from_pos, require_open)


func _find_nearest_park(from_pos: Vector3) -> Building:
	if _agent == null or _agent.query_resolver == null:
		return null
	return _agent.query_resolver.find_nearest_park(self, from_pos)


func _get_stuck_slide_direction(direction: Vector3) -> Vector3:
	_stuck_slide_hold_dir = Vector3.ZERO
	_stuck_slide_hold_left = 0.0
	if direction.length_squared() <= 0.0001:
		return Vector3.ZERO
	return direction.normalized()


func _is_slide_escape_direction_viable(candidate: Vector3) -> bool:
	var planar_candidate := candidate
	planar_candidate.y = 0.0
	if planar_candidate.length_squared() <= 0.0001:
		return false
	if not _is_crosswalk_route_context() and not _is_move_surface_allowed(planar_candidate, false):
		return false
	if _agent == null or _agent.obstacle_avoidance == null:
		return true
	return _agent.obstacle_avoidance.score_move_direction(
		self,
		planar_candidate.normalized(),
		_is_crosswalk_route_context()
	) < 1000.0


func _is_crosswalk_route_context() -> bool:
	if _global_path.is_empty():
		return false
	var start_idx := maxi(_path_index - 1, 0)
	var end_idx := mini(_path_index + 1, _global_path.size() - 1)
	for idx in range(start_idx, end_idx + 1):
		if _is_crosswalk_path_context(idx):
			return true
	return false


func _is_move_surface_allowed(_planar_direction: Vector3, _allow_road: bool = false) -> bool:
	return true


func _is_citizen_collider(collider: Variant) -> bool:
	return collider is Citizen or (collider is Node and (collider as Node).is_in_group("citizens"))


func _is_entrance_trigger_node(node: Node) -> bool:
	return node != null and (node.is_in_group("building_entrance_trigger") or node.name.to_lower().contains("entrance"))


func _is_target_entrance_trigger(node: Node) -> bool:
	return _is_entrance_trigger_node(node)


func _is_walkable_step_surface(collider: Variant) -> bool:
	if collider is not Node:
		return false
	var kind := SurfaceClassifier.classify_node(collider as Node)
	return kind == SurfaceClassifier.KIND_PEDESTRIAN or kind == SurfaceClassifier.KIND_CROSSWALK


func _ray_move_direction(ray: RayCast3D) -> Vector3:
	if ray == null:
		return Vector3.ZERO
	var world_target := ray.to_global(ray.target_position)
	var direction := world_target - ray.global_position
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO


func _rotate_planar_direction(direction: Vector3, angle_rad: float) -> Vector3:
	var planar := direction
	planar.y = 0.0
	if planar.length_squared() <= 0.0001:
		return Vector3.ZERO
	return planar.normalized().rotated(Vector3.UP, angle_rad)


func _blend_move_direction(a: Vector3, b: Vector3, weight: float) -> Vector3:
	var blended := a.lerp(b, clampf(weight, 0.0, 1.0))
	blended.y = 0.0
	return blended.normalized() if blended.length_squared() > 0.0001 else Vector3.ZERO


func _trace_collider_label(collider: Variant) -> String:
	if collider == null:
		return "-"
	if collider is Node:
		return (collider as Node).name
	return str(collider)


func _trace_fmt_vec3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func log_needs_changes(h_delta: float) -> void:
	# Health-Logging muss IMMER laufen — nicht nur fuer den selektierten Citizen.
	# Wird vom CitizenAgent jeden Sim-Tick aufgerufen.
	if needs == null or h_delta == 0.0:
		return
	_log_health_accum += h_delta
	if absf(_log_health_accum) < 5.0:
		return
	var reason := "recovering" if _log_health_accum > 0.0 else "declining"
	SimLoggerScript.log("[%s] Health %+0.1f -> %.1f [%s]" % [
		citizen_name,
		_log_health_accum,
		needs.health,
		reason
	])
	_log_health_accum = 0.0


## Returns true if HP reached 0 — caller should invoke die() and skip the rest
## of the tick. Kept as a separate query so CitizenAgent can decide ordering.
func is_dead() -> bool:
	return needs != null and needs.health <= 0.0

func is_dying() -> bool:
	return _is_dying


## Despawn-on-death. Idempotent: a second call is a no-op.
## Releases tenant/worker/visitor slots so a future spawn can fill them,
## cancels the current action, frees bench reservations, then queue_free()s
## the node. World cleanup is also invoked immediately so no simulation/debug
## list keeps a dead citizen until the deferred queue_free() removal.
func die(world: Node = null) -> void:
	if _is_dying:
		return
	_is_dying = true
	var cleanup_world: Node = world
	if cleanup_world == null:
		cleanup_world = _resolve_world_ref()

	var hp := needs.health if needs != null else 0.0
	var location_label := "outside"
	if current_location != null and current_location.has_method("get_display_name"):
		location_label = current_location.get_display_name()
	elif _sim != null and _sim.location != null and _sim.location.is_inside():
		var inside := _sim.location.get_inside_building()
		if inside != null and inside.has_method("get_display_name"):
			location_label = inside.get_display_name()
	SimLoggerScript.log("[%s] Died at HP=%.1f location=%s" % [
		citizen_name, hp, location_label
	])

	if current_action != null and current_action.has_method("finish"):
		current_action.finish(cleanup_world, self)
	current_action = null

	cancel_network_server_interaction_travel()
	clear_server_interaction_label()
	clear_rest_pose(false)
	release_reserved_benches(cleanup_world)
	stop_travel()
	velocity = Vector3.ZERO

	# Tenant slot frei.
	if home != null and home.has_method("remove_tenant"):
		home.remove_tenant(self)
		home = null

	# Worker slot frei (Building.fire setzt auch job.workplace = null).
	if job != null and job.workplace != null and job.workplace.has_method("fire"):
		job.workplace.fire(self)

	# Aus aktuellem Building/Visit austreten.
	if is_inside_building():
		exit_current_building(cleanup_world)
	elif current_location != null and current_location.has_method("on_citizen_exited"):
		current_location.call("on_citizen_exited", self)
	current_location = null

	if cleanup_world != null and cleanup_world.has_method("unregister_citizen"):
		cleanup_world.call("unregister_citizen", self)
	set_physics_process(false)
	queue_free()


func _update_debug(world: World, _h_delta: float) -> void:
	if debug_panel == null:
		return
	if debug_panel.has_method("update_sections"):
		debug_panel.update_sections(get_info_sections(world))
	else:
		debug_panel.update_debug(_get_flat_info_fallback())


# Strukturierter Info-Output fuers DebugPanel — Sektionen statt flachem Dict.
# Reihenfolge: Identitaet (wer) -> Beduerfnisse (Zustand) -> Aktivitaet (was
# gerade) -> Finanzen (kompakt). Leere Felder werden vom DebugPanel uebersprungen,
# damit z.B. "Bildung" nur erscheint, wenn der Citizen wirklich studiert.
func get_info_sections(_world = null) -> Array:
	return [
		_build_identity_section(),
		_build_needs_section(),
		_build_activity_section(),
		_build_finance_section(),
	]


func _build_identity_section() -> Dictionary:
	var rows: Array = [{"label": "Name", "value": citizen_name}]
	rows.append({"label": "Wohnung", "value": _building_label(home) if home != null else "keine"})
	var job_str := _format_job_status_text()
	if not job_str.is_empty():
		rows.append({"label": "Beruf", "value": job_str})
	var edu_str := _format_education_status_text()
	if not edu_str.is_empty():
		rows.append({"label": "Bildung", "value": edu_str})
	return {"title": "Identitaet", "rows": rows}


func _format_job_status_text() -> String:
	if job == null:
		return "arbeitslos"
	if job.workplace == null:
		return "arbeitslos (%s)" % job.title
	return "%s @ %s (%d EUR/h)" % [
		job.title,
		_building_label(job.workplace),
		job.wage_per_hour
	]


func _format_education_status_text() -> String:
	if job != null and job.required_education_level > education_level:
		return "%d / %d (fuer %s)" % [education_level, job.required_education_level, job.title]
	if education_level > 0:
		return "Level %d" % education_level
	return ""


func _build_needs_section() -> Dictionary:
	if needs == null:
		return {"title": "Beduerfnisse", "rows": []}
	return {
		"title": "Beduerfnisse",
		"rows": [
			_build_need_row("Hunger", needs.hunger, true),
			_build_need_row("Energie", needs.energy, false),
			_build_need_row("Spass", needs.fun, false),
			_build_need_row("Sozial", needs.social, false),
			_build_need_row("Gesundheit", needs.health, false),
		]
	}


# `high_is_bad` true fuer hunger (steigt -> Problem); false fuer energy/fun/health
# (fallen -> Problem). Severity steuert die Farbe im DebugPanel.
func _build_need_row(label_text: String, value: float, high_is_bad: bool) -> Dictionary:
	return {
		"label": label_text,
		"value": "%s  %3d / 100" % [_format_need_bar(value), int(round(value))],
		"severity": _classify_need_severity(value, high_is_bad),
	}


func _classify_need_severity(value: float, high_is_bad: bool) -> String:
	if high_is_bad:
		if value >= 85:
			return "critical"
		if value >= 70:
			return "warning"
		return "normal"
	if value <= 10:
		return "critical"
	if value <= 30:
		return "warning"
	return "normal"


func _format_need_bar(value: float, width: int = 10) -> String:
	var clamped := clampf(value, 0.0, 100.0)
	var fill := clampi(int(round(clamped / 100.0 * width)), 0, width)
	return "█".repeat(fill) + "░".repeat(width - fill)


func _build_activity_section() -> Dictionary:
	var rows: Array = []
	var action_label := current_action.label if current_action != null else "Idle"
	if current_action == null and not _server_interaction_label.is_empty():
		action_label = _server_interaction_label
	if network_replica_mode and not _network_action_label.is_empty():
		action_label = _network_action_label
	rows.append({"label": "Aktion", "value": action_label})
	var location_text := _format_location_text()
	if not location_text.is_empty():
		rows.append({"label": "Ort", "value": location_text})
	if is_travelling():
		var target_label := _format_travel_target_label()
		if not target_label.is_empty():
			rows.append({"label": "Ziel", "value": "-> %s" % target_label})
	rows.append({"label": "LOD", "value": get_simulation_lod_tier()})
	return {"title": "Aktivitaet", "rows": rows}


func _format_location_text() -> String:
	if current_location == null:
		return "unterwegs"
	if current_location.has_method("get_display_name"):
		return current_location.get_display_name()
	return current_location.building_name


func _format_travel_target_label() -> String:
	var target_building: Building = null
	if _debug_travel_target_building != null:
		target_building = _debug_travel_target_building
	elif _travel_target_building != null:
		target_building = _travel_target_building
	if target_building == null:
		return ""
	if target_building.has_method("get_display_name"):
		return target_building.get_display_name()
	return target_building.building_name


func _build_finance_section() -> Dictionary:
	var rows: Array = [{"label": "Geld", "value": "%d EUR" % (wallet.balance if wallet != null else 0)}]
	if home != null:
		rows.append({"label": "Miete/Tag", "value": "%d EUR" % home.rent_per_day})
	if home_food_stock > 0:
		rows.append({"label": "Vorraete", "value": str(home_food_stock)})
	if clothing_items > 0:
		rows.append({"label": "Kleidung", "value": str(clothing_items)})
	return {"title": "Finanzen", "rows": rows}


# Fallback wenn das DebugPanel die neue update_sections-API noch nicht hat
# (z.B. waehrend Tests, in denen ein gemocktes Panel verwendet wird).
func _get_flat_info_fallback() -> Dictionary:
	return {
		"Citizen": citizen_name,
		"Location": _format_location_text(),
		"Action": current_action.label if current_action != null else "idle",
		"Hunger": "%.1f / 100" % (needs.hunger if needs != null else 0.0),
		"Energy": "%.1f / 100" % (needs.energy if needs != null else 0.0),
		"Fun": "%.1f / 100" % (needs.fun if needs != null else 0.0),
		"Health": "%.1f / 100" % (needs.health if needs != null else 0.0),
		"Money": "%d EUR" % (wallet.balance if wallet != null else 0),
		"Home": _building_label(home) if home != null else "none",
		"Groceries": str(home_food_stock),
		"Clothing": str(clothing_items),
		"Education": "%d" % education_level,
		"Workplace": _building_label(job.workplace) if (job != null and job.workplace != null) else "unemployed",
		"LOD": get_simulation_lod_tier(),
		"TravelState": "moving" if is_travelling() else "idle",
	}


func get_job_debug_summary() -> String:
	if job == null:
		return "job=none"
	return "job=%s workplace=%s edu=%d/%d wage=%d" % [
		job.title,
		_building_label(job.workplace),
		education_level,
		job.required_education_level,
		job.wage_per_hour
	]


func get_unemployment_debug_reason() -> String:
	if job == null:
		return "no job"
	if job.workplace == null:
		return "no workplace"
	if education_level < job.required_education_level:
		return "education %d/%d" % [education_level, job.required_education_level]
	return "unknown"


func get_zero_pay_debug_reason() -> String:
	if job == null:
		return "no job"
	if job.wage_per_hour <= 0:
		return "zero wage"
	return ""


func _building_label(building: Building) -> String:
	if building == null:
		return "Unknown"
	if building.has_method("get_display_name"):
		return building.get_display_name()
	return building.building_name


# --- Rest pose (delegated to CitizenRestPose) ---

func has_active_rest_pose() -> bool:
	return _sim != null and _sim.rest_pose != null and _sim.rest_pose.is_active()


func set_rest_pose(target_pos: Vector3, yaw: float = 0.0) -> void:
	if _sim == null or _sim.rest_pose == null:
		return
	_sim.rest_pose.set_pose(target_pos, yaw)
	_sim.rest_pose.apply()


func clear_rest_pose(snap_to_ground: bool = false) -> void:
	if _sim == null or _sim.rest_pose == null:
		return
	_sim.rest_pose.clear(snap_to_ground)


func apply_rest_pose() -> void:
	if _sim == null or _sim.rest_pose == null:
		return
	_sim.rest_pose.apply()
