extends Node3D
class_name FarmWorkScene

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")
const FarmWorkInventoryScript = preload("res://Scenes/WorkScenes/Farm/FarmWorkInventory.gd")
const FarmWorkFieldDataScript = preload("res://Scenes/WorkScenes/Farm/FarmWorkFieldData.gd")
const FarmWorkProductionStateScript = preload("res://Scenes/WorkScenes/Farm/FarmWorkProductionState.gd")
const FarmWorkInteractableScript = preload("res://Scenes/WorkScenes/Farm/FarmWorkInteractable.gd")
const ItemIconCatalogScript = preload("res://Simulation/UI/ItemIconCatalog.gd")
const WindmillFarmScene = preload("res://Scenes/Farm_Windmill.tscn")
const PickupScene = preload("res://Scenes/Vehicles/CityPack/pickup_truck.tscn")
const PlayerVisualScene = preload("res://Scenes/Characters/CityPack/man.tscn")
const DaySkyMaterial = preload("res://environment/sky/Day2.tres")

signal session_finished(result: Dictionary)
signal score_changed(score: int)
signal mistake_made(reason: String)

const ACTION_PLANT := "plant"
const ACTION_WATER := "water"
const ACTION_WEED := "weed"
const ACTION_HARVEST := "harvest"
const ACTION_DELIVER := "deliver"

const LIVE_TAKE_WHEAT_SEEDS := "take_wheat_seeds"
const LIVE_TAKE_CORN_SEEDS := "take_corn_seeds"
const LIVE_TAKE_SUNFLOWER_SEEDS := "take_sunflower_seeds"
const LIVE_SOW_FIELD := "sow_field"
const LIVE_WATER_FIELD := "water_field"
const LIVE_HARVEST_FIELD := "harvest_field"
const LIVE_STORE_GRAIN_SILO := "store_grain_silo"
const LIVE_TAKE_GRAIN_SILO := "take_grain_silo"
const LIVE_TAKE_CORN_GRAIN_SILO := "take_corn_grain_silo"
const LIVE_TAKE_SUNFLOWER_GRAIN_SILO := "take_sunflower_grain_silo"
const LIVE_START_WINDMILL := "start_windmill"
const LIVE_START_CORN_PROCESSING := "start_corn_processing"
const LIVE_START_SUNFLOWER_PROCESSING := "start_sunflower_processing"
const LIVE_PAUSE_WINDMILL := "pause_windmill"
const LIVE_COLLECT_FLOUR := "collect_flour"
const LIVE_STORE_FLOUR_BARN := "store_flour_barn"
const LIVE_TAKE_FLOUR_BARN := "take_flour_barn"
const LIVE_TAKE_CORNMEAL_BARN := "take_cornmeal_barn"
const LIVE_TAKE_SUNFLOWER_OIL_BARN := "take_sunflower_oil_barn"
const LIVE_LOAD_PICKUP := "load_pickup"
const LIVE_USE_PICKUP := "use_pickup"
const LIVE_LEAVE_FARM := "leave_farm"

const CROP_WHEAT := "wheat"
const CROP_CORN := "corn"
const CROP_SUNFLOWER := "sunflower"
const FIELD_PREPARED := 0
const FIELD_SEEDED := 1
const FIELD_GROWING := 2
const FIELD_MATURE := 3
const FIELD_HARVESTED := 4

const PLOT_COUNT := 4
const DEFAULT_SESSION_DURATION_SEC := 1200.0
const DEFAULT_WORK_MINUTES := 75
const BASKET_CAPACITY_CRATES := 2
const FALLBACK_UNITS_PER_CRATE := 8
const GROWTH_MINUTES_PER_MAINTENANCE_TASK := 90
const QUALITY_BONUS_THRESHOLD := 0.62
const LIVE_GROWTH_DURATION_SEC := 8.0
const LIVE_PRODUCTION_DURATION_SEC := 8.0
const WHEAT_HARVEST_UNITS := 12
const FARM_FALLBACK_GROWTH_MINUTES := 2 * 24 * 60
const BARN_PRODUCT_CAPACITY := 80
const SILO_GRAIN_CAPACITY := 120
const PICKUP_PRODUCT_CAPACITY := 6
const SEED_WITHDRAWAL_AMOUNT := 4

const DEFAULT_SEED_STOCK := {
	"wheat_seed": 16,
	"corn_seed": 12,
	"sunflower_seed": 12,
}
const SEED_ITEM_IDS := ["wheat_seed", "corn_seed", "sunflower_seed"]
const GRAIN_ITEM_IDS := ["wheat_grain", "corn_grain", "sunflower_grain"]
const PRODUCT_ITEM_IDS := ["flour_sack", "cornmeal_sack", "sunflower_oil_crate"]
const BARN_ITEM_IDS := PRODUCT_ITEM_IDS
const PICKUP_ITEM_IDS := PRODUCT_ITEM_IDS

const PROCESSING_RECIPES := {
	CROP_WHEAT: {
		"input_item_id": "wheat_grain",
		"required_grain": 10,
		"output_item_id": "flour_sack",
		"output_amount": 3,
	},
	CROP_CORN: {
		"input_item_id": "corn_grain",
		"required_grain": 8,
		"output_item_id": "cornmeal_sack",
		"output_amount": 3,
	},
	CROP_SUNFLOWER: {
		"input_item_id": "sunflower_grain",
		"required_grain": 8,
		"output_item_id": "sunflower_oil_crate",
		"output_amount": 2,
	},
}

const TASK_FLOW := [
	"take_seed",
	"sow_wheat",
	"water_wheat",
	"wait_growth",
	"harvest_wheat",
	"store_silo",
	"start_mill",
	"collect_flour",
	"store_barn",
	"load_pickup",
]

const ITEM_LABEL_KEYS := {
	"wheat_seed": "farm_work.item.wheat_seed",
	"corn_seed": "farm_work.item.corn_seed",
	"sunflower_seed": "farm_work.item.sunflower_seed",
	"wheat_grain": "farm_work.item.wheat_grain",
	"corn_grain": "farm_work.item.corn_grain",
	"sunflower_grain": "farm_work.item.sunflower_grain",
	"flour_sack": "farm_work.item.flour_sack",
	"cornmeal_sack": "farm_work.item.cornmeal_sack",
	"sunflower_oil_crate": "farm_work.item.sunflower_oil_crate",
	"watering_can": "farm_work.item.watering_can",
	"sickle": "farm_work.item.sickle",
	"shovel": "farm_work.item.shovel",
	"empty_sack": "farm_work.item.empty_sack",
}

const CROP_LABEL_KEYS := {
	CROP_WHEAT: "farm_work.crop.wheat",
	CROP_CORN: "farm_work.crop.corn",
	CROP_SUNFLOWER: "farm_work.crop.sunflower",
}
const SUPPORTED_CROPS := [CROP_WHEAT, CROP_CORN, CROP_SUNFLOWER]

@export var auto_start: bool = true
@export var session_duration_sec: float = DEFAULT_SESSION_DURATION_SEC
@export var player_skill_level: int = 0
@export var player_speed: float = 2.2

var farm_label: String = "Windmill Farm"
var product_commodity: String = "bread"
var product_display_name: String = "flour"
var crop_ready: bool = false
var available_storage: int = 0
var suggested_harvest_units: int = 0
var running: bool = false
var elapsed_sec: float = 0.0
var score: int = 0
var mistakes: int = 0
var completed_tasks: int = 0
var delivered_crates: int = 0
var harvested_amount: int = 0
var quality_score: float = 1.0
var work_minutes: int = DEFAULT_WORK_MINUTES
var actor_role: String = "worker"
var demand_entries: Array[Dictionary] = []

var _barn_product_capacity: int = BARN_PRODUCT_CAPACITY
var _silo_grain_capacity: int = SILO_GRAIN_CAPACITY
var _initial_farm_inventory: Dictionary = {}
var _initial_field_snapshots: Dictionary = {}
var _initial_production_snapshot: Dictionary = {}

var _player_inventory = FarmWorkInventoryScript.new()
var _silo_inventory = FarmWorkInventoryScript.new()
var _barn_inventory = FarmWorkInventoryScript.new()
var _seed_inventory = FarmWorkInventoryScript.new()
var _pickup_inventory = FarmWorkInventoryScript.new()
var _production = FarmWorkProductionStateScript.new()

var _fields: Array = []
var _field_visuals: Dictionary = {}
var _interactables: Array = []
var _active_interactable = null
var _nearest_interactable = null
var _selected_crop_type: String = CROP_WHEAT
var _selected_tool: String = "Hands"
var _task_flags: Dictionary = {}
var _live_harvested_amount: int = 0
var _live_growth_minutes_added: int = 0
var _farm_growth_total_minutes: int = FARM_FALLBACK_GROWTH_MINUTES

var _legacy_plots: Array[Dictionary] = []
var _selected_plot_index: int = 0
var _basket_crates: int = 0
var _basket_units: int = 0
var _units_per_crate: int = FALLBACK_UNITS_PER_CRATE
var _maintenance_tasks_done: int = 0

var _world_root: Node3D = null
var _farm_environment: Node3D = null
var _pickup_visual: Node3D = null
var _player: CharacterBody3D = null
var _camera_pivot: Node3D = null
var _camera: Camera3D = null
var _previous_camera: Camera3D = null
var _camera_yaw: float = deg_to_rad(0.0)
var _ui_layer: CanvasLayer = null
var _hud_label: Label = null
var _task_label: Label = null
var _tool_label: Label = null
var _hint_label: Label = null
var _demand_label: Label = null
var _inventory_label: Label = null
var _leave_button: Button = null
var _context_panel: PanelContainer = null
var _context_content: VBoxContainer = null
var _context_signature: String = ""
var _ui_refresh_left: float = 0.0
var _last_locale: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous_camera = get_viewport().get_camera_3d()
	_reset_session_state()
	_build_world()
	_build_ui()
	_update_all_ui()
	if auto_start:
		start_session()


func _process(delta: float) -> void:
	if not running:
		return
	elapsed_sec += delta
	if elapsed_sec >= session_duration_sec:
		finish_session()
		return
	_tick_live_systems(delta)
	_update_nearest_interactable()
	_update_camera(delta)
	_ui_refresh_left -= delta
	if _ui_refresh_left <= 0.0:
		_ui_refresh_left = 0.25
		_update_all_ui()


func _physics_process(delta: float) -> void:
	if running:
		_update_player_motion(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	if _is_text_input_focused():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				if _nearest_interactable != null:
					_open_context_for(_nearest_interactable)
					get_viewport().set_input_as_handled()
			KEY_Q:
				_camera_yaw += deg_to_rad(10.0)
			KEY_E:
				_camera_yaw -= deg_to_rad(10.0)
			KEY_ESCAPE:
				if _context_panel != null and _context_panel.visible:
					_context_panel.visible = false
				else:
					finish_session()
				get_viewport().set_input_as_handled()


func configure_for_farm(
	farm,
	skill_level: int = 0,
	world: World = null,
	actor: Citizen = null
) -> bool:
	player_skill_level = maxi(skill_level, 0)
	if farm == null:
		_apply_context({
			"farm_label": "Windmill Farm",
			"product_commodity": "bread",
			"product_display_name": "flour",
			"crop_ready": true,
			"available_storage": 48,
			"suggested_harvest_units": 32,
			"crop_growth_total_minutes": FARM_FALLBACK_GROWTH_MINUTES,
		})
		return true
	if farm is not Farm:
		return false
	var context := {}
	if farm.has_method("get_player_work_context"):
		context = farm.call("get_player_work_context", world, actor)
	else:
		context = {
			"farm_label": farm.get_display_name() if farm.has_method("get_display_name") else str(farm.name),
			"product_commodity": "food",
			"product_display_name": "food",
			"crop_ready": false,
			"available_storage": 0,
			"suggested_harvest_units": 0,
		}
	if farm.has_method("get_crop_growth_total_minutes"):
		context["crop_growth_total_minutes"] = int(farm.call("get_crop_growth_total_minutes"))
	_apply_context(context)
	return true


func start_session() -> void:
	_reset_session_state()
	running = true
	_set_hint(_trf("farm_work.hint.session_ready", [farm_label], "%s: Arbeitsablauf bereit."))
	_update_all_ui()


func finish_session() -> void:
	if not running:
		return
	running = false
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.current = true
	_update_all_ui()
	session_finished.emit(get_result())


func get_result() -> Dictionary:
	var result_quality := get_quality_score()
	return {
		"job_type": "farm",
		"farm_label": farm_label,
		"product_commodity": product_commodity,
		"product_display_name": product_display_name,
		"score": score,
		"mistakes": mistakes,
		"completed_tasks": completed_tasks,
		"delivered_crates": delivered_crates,
		"harvested_amount": harvested_amount,
		"quality_score": result_quality,
		"work_minutes": _calculate_work_minutes(),
		"time_used_sec": elapsed_sec,
		"growth_minutes_added": get_growth_minutes_added(),
		"success": result_quality >= QUALITY_BONUS_THRESHOLD,
		"customer_satisfaction": result_quality * 100.0,
		"earned_money": 0,
		"reputation_gain": get_reputation_gain(),
		"goods_produced": _production.get_total_produced_units(),
		"goods_delivered": _product_inventory_total(_pickup_inventory),
		"live_harvested_amount": _live_harvested_amount,
		"legacy_harvested_amount": maxi(harvested_amount - _live_harvested_amount, 0),
		"farm_inventory": {
			"player": _player_inventory.get_snapshot(),
			"silo": _silo_inventory.get_snapshot(),
			"barn": _barn_inventory.get_snapshot(),
			"seeds": _seed_inventory.get_snapshot(),
			"pickup": _pickup_inventory.get_snapshot(),
		},
		"field_states": _get_field_snapshots(),
		"production": _production.get_snapshot(),
	}


func get_quality_score() -> float:
	var task_factor := clampf(float(_get_completed_task_count()) / float(TASK_FLOW.size()), 0.0, 1.0)
	var legacy_task_factor := clampf(float(completed_tasks) / 10.0, 0.0, 1.0)
	var harvest_factor := 0.0
	if suggested_harvest_units > 0:
		harvest_factor = clampf(float(harvested_amount) / float(suggested_harvest_units), 0.0, 1.0)
	elif harvested_amount > 0:
		harvest_factor = 1.0
	elif not crop_ready:
		harvest_factor = maxf(task_factor, legacy_task_factor)
	var mistake_penalty := clampf(float(mistakes) * 0.08, 0.0, 0.45)
	return clampf(maxf(task_factor, legacy_task_factor) * 0.45 + harvest_factor * 0.45 + quality_score * 0.10 - mistake_penalty, 0.0, 1.0)


func get_growth_minutes_added() -> int:
	if crop_ready:
		return 0
	if _live_harvested_amount > 0:
		return maxi(_farm_growth_total_minutes, _live_growth_minutes_added)
	return maxi(_maintenance_tasks_done * GROWTH_MINUTES_PER_MAINTENANCE_TASK, _live_growth_minutes_added)


func get_reputation_gain() -> int:
	var quality := get_quality_score()
	if quality >= 0.88 and mistakes == 0:
		return 3
	if quality >= QUALITY_BONUS_THRESHOLD:
		return 2
	if quality >= 0.42:
		return 1
	return 0


func get_action_ids() -> PackedStringArray:
	return PackedStringArray([
		ACTION_PLANT,
		ACTION_WATER,
		ACTION_WEED,
		ACTION_HARVEST,
		ACTION_DELIVER,
		LIVE_TAKE_WHEAT_SEEDS,
		LIVE_TAKE_CORN_SEEDS,
		LIVE_TAKE_SUNFLOWER_SEEDS,
		LIVE_SOW_FIELD,
		LIVE_WATER_FIELD,
		LIVE_HARVEST_FIELD,
		LIVE_STORE_GRAIN_SILO,
		LIVE_TAKE_GRAIN_SILO,
		LIVE_TAKE_CORN_GRAIN_SILO,
		LIVE_TAKE_SUNFLOWER_GRAIN_SILO,
		LIVE_START_WINDMILL,
		LIVE_START_CORN_PROCESSING,
		LIVE_START_SUNFLOWER_PROCESSING,
		LIVE_PAUSE_WINDMILL,
		LIVE_COLLECT_FLOUR,
		LIVE_STORE_FLOUR_BARN,
		LIVE_TAKE_FLOUR_BARN,
		LIVE_TAKE_CORNMEAL_BARN,
		LIVE_TAKE_SUNFLOWER_OIL_BARN,
		LIVE_LOAD_PICKUP,
	])


func get_plot_snapshot(plot_number: int) -> Dictionary:
	_ensure_legacy_plots()
	var index := plot_number - 1
	if index < 0 or index >= _legacy_plots.size():
		return {}
	var plot := _legacy_plots[index].duplicate(true)
	plot["plot_number"] = plot_number
	plot["label"] = "Feld %d" % plot_number
	plot["required_action"] = get_recommended_action_for_plot(plot_number)
	plot["state_label"] = _legacy_plot_state_label(plot)
	return plot


func get_recommended_action_for_plot(plot_number: int) -> String:
	_ensure_legacy_plots()
	var index := plot_number - 1
	if index < 0 or index >= _legacy_plots.size():
		return ""
	return _legacy_recommended_action_for_plot(_legacy_plots[index])


func select_plot(plot_number: int) -> bool:
	var index := plot_number - 1
	if index < 0 or index >= PLOT_COUNT:
		return false
	_selected_plot_index = index
	return true


func debug_perform_action(plot_number: int, action_id: String) -> Dictionary:
	if action_id == ACTION_DELIVER:
		return _perform_legacy_delivery_action()
	return _perform_legacy_plot_action(plot_number - 1, action_id)


func debug_perform_live_action(interactable_id: String, action_id: String) -> Dictionary:
	var interactable = _find_interactable(interactable_id)
	if interactable == null:
		return {"correct": false, "reason": "missing_interactable"}
	return _perform_live_action(action_id, interactable)


func debug_tick_live(seconds: float) -> void:
	_tick_live_systems(maxf(seconds, 0.0))
	_update_all_ui()


func debug_get_inventory_snapshot(scope: String = "player") -> Dictionary:
	match scope:
		"silo":
			return _silo_inventory.get_snapshot()
		"barn":
			return _barn_inventory.get_snapshot()
		"seeds":
			return _seed_inventory.get_snapshot()
		"pickup":
			return _pickup_inventory.get_snapshot()
		_:
			return _player_inventory.get_snapshot()


func debug_get_field_snapshot(field_id: String) -> Dictionary:
	var field = _get_field_data(field_id)
	return field.get_snapshot() if field != null else {}


func debug_force_elapsed(seconds: float) -> void:
	elapsed_sec = clampf(seconds, 0.0, session_duration_sec)
	_update_all_ui()


func _get_field_snapshots() -> Dictionary:
	var snapshots: Dictionary = {}
	for field in _fields:
		if field == null:
			continue
		snapshots[field.field_id] = field.get_snapshot()
	return snapshots


func _get_initial_inventory_scope(scope: String, fallback: Dictionary) -> Dictionary:
	if _initial_farm_inventory.has(scope) and _initial_farm_inventory.get(scope) is Dictionary:
		return (_initial_farm_inventory.get(scope) as Dictionary).duplicate(true)
	return fallback.duplicate(true)


func _apply_initial_field_snapshot(field) -> void:
	if field == null:
		return
	var field_snapshot := _duplicate_dictionary(_initial_field_snapshots.get(field.field_id, {}))
	if field_snapshot.is_empty():
		return
	field.apply_snapshot(field_snapshot)


func _duplicate_dictionary(value) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _apply_context(context: Dictionary) -> void:
	farm_label = str(context.get("farm_label", farm_label)).strip_edges()
	if farm_label.is_empty():
		farm_label = "Windmill Farm"
	product_commodity = str(context.get("product_commodity", product_commodity)).strip_edges()
	if product_commodity.is_empty():
		product_commodity = "bread"
	product_display_name = str(context.get("product_display_name", product_display_name)).strip_edges()
	if product_display_name.is_empty():
		product_display_name = "flour"
	crop_ready = bool(context.get("crop_ready", crop_ready))
	available_storage = maxi(int(context.get("available_storage", available_storage)), 0)
	suggested_harvest_units = maxi(int(context.get("suggested_harvest_units", suggested_harvest_units)), 0)
	work_minutes = maxi(int(context.get("work_minutes", work_minutes)), 15)
	_farm_growth_total_minutes = maxi(int(context.get("crop_growth_total_minutes", _farm_growth_total_minutes)), 1)
	actor_role = str(context.get("actor_role", actor_role)).strip_edges()
	_initial_farm_inventory = _duplicate_dictionary(context.get("farm_inventory", {}))
	_initial_field_snapshots = _duplicate_dictionary(context.get("field_states", {}))
	_initial_production_snapshot = _duplicate_dictionary(context.get("production", {}))
	var capacities := _duplicate_dictionary(context.get("work_inventory_capacities", {}))
	_barn_product_capacity = maxi(int(capacities.get("barn", BARN_PRODUCT_CAPACITY)), 1)
	_silo_grain_capacity = maxi(int(capacities.get("silo", SILO_GRAIN_CAPACITY)), 1)
	demand_entries.clear()
	var context_demand: Variant = context.get("demand_entries", [])
	if context_demand is Array:
		for entry_var in context_demand:
			if entry_var is Dictionary:
				demand_entries.append((entry_var as Dictionary).duplicate(true))
	_units_per_crate = _calculate_units_per_crate()
	if is_inside_tree():
		_reset_session_state()
		_update_all_ui()


func _reset_session_state() -> void:
	running = false
	elapsed_sec = 0.0
	score = 0
	mistakes = 0
	completed_tasks = 0
	delivered_crates = 0
	harvested_amount = 0
	quality_score = 1.0
	_basket_crates = 0
	_basket_units = 0
	_maintenance_tasks_done = 0
	_units_per_crate = _calculate_units_per_crate()
	_task_flags.clear()
	_live_harvested_amount = 0
	_live_growth_minutes_added = 0
	_selected_crop_type = CROP_WHEAT
	_selected_tool = "Hands"
	_player_inventory.clear()
	_seed_inventory.apply_snapshot(
		_get_initial_inventory_scope("seeds", DEFAULT_SEED_STOCK),
		SEED_ITEM_IDS
	)
	_silo_inventory.apply_snapshot(
		_get_initial_inventory_scope("silo", {}),
		GRAIN_ITEM_IDS,
		_silo_grain_capacity
	)
	_barn_inventory.apply_snapshot(
		_get_initial_inventory_scope("barn", {}),
		BARN_ITEM_IDS,
		_barn_product_capacity
	)
	_pickup_inventory.apply_snapshot(
		_get_initial_inventory_scope("pickup", {}),
		PICKUP_ITEM_IDS
	)
	_production.reset()
	_production.duration_sec = LIVE_PRODUCTION_DURATION_SEC
	if not _initial_production_snapshot.is_empty():
		_production.apply_snapshot(_initial_production_snapshot)
	_reset_legacy_plots()
	_reset_live_fields()


func _reset_live_fields() -> void:
	_fields.clear()
	var wheat = FarmWorkFieldDataScript.new()
	wheat.configure("field_wheat", _field_display_name("field_wheat"), CROP_WHEAT, FIELD_PREPARED)
	_apply_initial_field_snapshot(wheat)
	_fields.append(wheat)
	var corn = FarmWorkFieldDataScript.new()
	corn.configure("field_corn", _field_display_name("field_corn"), CROP_CORN, FIELD_SEEDED)
	_apply_initial_field_snapshot(corn)
	_fields.append(corn)
	_update_all_field_visuals()


func _build_world() -> void:
	_world_root = Node3D.new()
	_world_root.name = "WindmillFarm3D"
	add_child(_world_root)
	_build_environment()
	_build_existing_farm_environment()
	_build_environment_collisions()
	_build_player()
	_build_existing_farm_interactions()
	_build_pickup()
	_build_camera()


func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "FarmDayEnvironment"
	var sky := Sky.new()
	var sky_material := DaySkyMaterial.duplicate() as ShaderMaterial
	if sky_material != null:
		sky_material.set_shader_parameter("bottom_color", Color(0.32, 0.52, 0.28, 1.0))
		sky.sky_material = sky_material
	else:
		sky.sky_material = DaySkyMaterial
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment = env
	_world_root.add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.name = "FarmSun"
	sun.rotation_degrees = Vector3(-58.0, -28.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	_world_root.add_child(sun)


func _build_existing_farm_environment() -> void:
	var source := WindmillFarmScene.instantiate() as Node3D
	if source == null:
		push_error("FarmWorkScene could not instantiate Farm_Windmill.tscn")
		return
	_farm_environment = Node3D.new()
	_farm_environment.name = "ExistingFarm"
	_farm_environment.transform = source.transform
	_world_root.add_child(_farm_environment)
	for child in source.get_children():
		_clear_scene_owner_recursive(child)
		source.remove_child(child)
		_farm_environment.add_child(child)
	source.free()

	var city_click_area := _farm_environment.get_node_or_null("ClickArea") as Area3D
	if city_click_area != null:
		city_click_area.input_ray_pickable = false
		city_click_area.monitoring = false
		city_click_area.collision_layer = 0
		city_click_area.collision_mask = 0


func _build_environment_collisions() -> void:
	if _farm_environment == null:
		return
	if _farm_environment.get_node_or_null("Obstacles/GroundShape") == null:
		_add_static_collision_for_visual(_farm_environment.get_node_or_null("Ground") as Node3D, "GroundCollision", 0.0)
	for node_path in [
		"Buildings/BigBarnModel",
		"Buildings/SiloModel",
		"VariantDecor/SideBarnModel",
		"VariantDecor/WaterTowerModel",
		"TowerWindmill",
		"Props/WellModel",
	]:
		_add_static_collision_for_visual(_farm_environment.get_node_or_null(node_path) as Node3D, "%sCollision" % node_path.get_file(), 0.08)
	var fence_root := _farm_environment.get_node_or_null("Fence")
	if fence_root != null:
		for fence_part in fence_root.get_children():
			_add_static_collision_for_visual(fence_part as Node3D, "%sCollision" % fence_part.name, 0.02)


func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.name = "Player"
	var entrance := _farm_environment.get_node_or_null("Entrance") as Node3D if _farm_environment != null else null
	_player.position = entrance.position + Vector3(0.0, 0.25, -0.75) if entrance != null else Vector3(0.0, 0.25, 3.0)
	_player.collision_layer = 2
	_player.collision_mask = 1
	_world_root.add_child(_player)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.12
	capsule.height = 0.62
	collision.shape = capsule
	collision.position = Vector3(0.0, 0.31, 0.0)
	collision.visible = false
	collision.debug_fill = false
	collision.debug_color = Color(0.0, 0.0, 0.0, 0.0)
	_player.add_child(collision)

	var body := PlayerVisualScene.instantiate() as Node3D
	if body != null:
		body.name = "PlayerVisual"
		body.scale = Vector3.ONE * 0.15
		body.rotation_degrees.y = 180.0
		_player.add_child(body)


func _build_camera() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	_world_root.add_child(_camera_pivot)
	_camera = Camera3D.new()
	_camera.name = "FarmCamera"
	_camera.position = Vector3(0.0, 4.2, 5.0)
	_camera.rotation_degrees = Vector3(-42.0, 0.0, 0.0)
	_camera.fov = 60.0
	_camera.current = true
	_camera_pivot.add_child(_camera)
	_update_camera(1.0)


func _build_existing_farm_interactions() -> void:
	if _farm_environment == null:
		return
	_bind_field_interaction(_fields[0], "Fields/FieldWest2/FarmlandModel")
	_bind_field_interaction(_fields[1], "Fields/FieldWest/FarmlandModel")
	_bind_visual_interaction("barn", "barn", _interactable_label("barn"), "Buildings/BigBarnModel", 3.5)
	_bind_visual_interaction("shed", "shed", _interactable_label("shed"), "VariantDecor/SideBarnModel", 3.2)
	_bind_visual_interaction("silo", "silo", _interactable_label("silo"), "Buildings/SiloModel", 3.0)
	_bind_visual_interaction("windmill", "windmill", _interactable_label("windmill"), "TowerWindmill", 3.8)
	_bind_visual_interaction("gate", "gate", _interactable_label("gate"), "Fence/SideGateModel", 2.8)
	_update_all_field_visuals()


func _bind_field_interaction(field, node_path: String) -> void:
	var visual := _farm_environment.get_node_or_null(node_path) as Node3D
	var interactable = _create_interactable_for_visual(field.field_id, "field", field.display_name, visual, 3.2, 0.35)
	if interactable == null:
		return
	_field_visuals[field.field_id] = {
		"crop_nodes": _get_field_crop_nodes(visual.get_parent()),
	}


func _bind_visual_interaction(
	id: String,
	type_name: String,
	label: String,
	node_path: String,
	radius: float
) -> void:
	_create_interactable_for_visual(id, type_name, label, _farm_environment.get_node_or_null(node_path) as Node3D, radius, 0.25)


func _create_interactable_for_visual(
	id: String,
	type_name: String,
	label: String,
	visual: Node3D,
	radius: float,
	bounds_margin: float
):
	if visual == null:
		push_warning("FarmWorkScene missing visual anchor: %s" % id)
		return null
	var bounds := _get_visual_bounds(visual)
	if bounds.size.length_squared() <= 0.0001:
		bounds = AABB(_world_root.to_local(visual.global_position) - Vector3.ONE * 0.5, Vector3.ONE)
	var area = FarmWorkInteractableScript.new()
	area.setup(id, type_name, label, radius)
	area.position = bounds.get_center()
	area.add_box_shape(bounds.size + Vector3.ONE * bounds_margin)
	area.interaction_requested.connect(_on_interactable_requested)
	_world_root.add_child(area)
	_interactables.append(area)
	return area


func _build_pickup() -> void:
	var pickup := PickupScene.instantiate() as VehicleBody3D
	if pickup == null:
		push_warning("FarmWorkScene could not instantiate pickup truck")
		return
	pickup.name = "WorkPickup"
	pickup.position = Vector3(4.9, 0.18, 2.7)
	pickup.rotation_degrees.y = -90.0
	pickup.process_mode = Node.PROCESS_MODE_DISABLED
	pickup.freeze = true
	pickup.collision_layer = 0
	pickup.collision_mask = 0
	pickup.set_script(null)
	_world_root.add_child(pickup)
	_pickup_visual = pickup
	_create_interactable_for_visual("machine_yard", "machine_yard", "Pickup and loading area", pickup, 3.4, 0.35)
	_add_static_collision_for_visual(pickup, "PickupCollision", 0.02)


func _get_field_crop_nodes(field_root: Node) -> Array[MultiMeshInstance3D]:
	var crop_nodes: Array[MultiMeshInstance3D] = []
	if field_root == null:
		return crop_nodes
	var candidates: Array[Node] = []
	_collect_nodes_of_type(field_root, MultiMeshInstance3D, candidates)
	for node in candidates:
		var crop_node := node as MultiMeshInstance3D
		if crop_node != null:
			crop_nodes.append(crop_node)
	return crop_nodes


func _add_static_collision_for_visual(visual: Node3D, collision_name: String, margin: float) -> void:
	if visual == null:
		return
	var bounds := _get_visual_bounds(visual)
	if bounds.size.length_squared() <= 0.0001:
		return
	var body := StaticBody3D.new()
	body.name = collision_name
	body.position = bounds.get_center()
	body.collision_layer = 1
	body.collision_mask = 0
	body.input_ray_pickable = false
	_world_root.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = bounds.size + Vector3.ONE * margin
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.visible = false
	collision.debug_fill = false
	collision.debug_color = Color(0.0, 0.0, 0.0, 0.0)
	body.add_child(collision)


func _get_visual_bounds(visual: Node3D) -> AABB:
	var has_bounds := false
	var bounds := AABB()
	var mesh_nodes: Array[Node] = []
	_collect_nodes_of_type(visual, MeshInstance3D, mesh_nodes)
	for node in mesh_nodes:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var local_aabb := mesh_node.get_aabb()
		for corner_index in range(8):
			var corner := Vector3(
				local_aabb.position.x + (local_aabb.size.x if corner_index & 1 else 0.0),
				local_aabb.position.y + (local_aabb.size.y if corner_index & 2 else 0.0),
				local_aabb.position.z + (local_aabb.size.z if corner_index & 4 else 0.0)
			)
			var point := _world_root.to_local(mesh_node.to_global(corner))
			if not has_bounds:
				bounds = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(point)
	return bounds


func _collect_nodes_of_type(node: Node, target_type: Variant, out: Array[Node]) -> void:
	if is_instance_of(node, target_type):
		out.append(node)
	for child in node.get_children():
		_collect_nodes_of_type(child, target_type, out)


func _clear_scene_owner_recursive(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_scene_owner_recursive(child)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "FarmWorkHud"
	add_child(_ui_layer)

	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiThemeScript.get_or_build()
	_ui_layer.add_child(root)

	var hud := PanelContainer.new()
	hud.name = "MainHud"
	hud.anchor_left = 0.0
	hud.anchor_top = 0.0
	hud.anchor_right = 1.0
	hud.anchor_bottom = 0.0
	hud.offset_left = 12.0
	hud.offset_top = 12.0
	hud.offset_right = -12.0
	hud.offset_bottom = 94.0
	root.add_child(hud)

	var hud_box := HBoxContainer.new()
	hud_box.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	hud.add_child(hud_box)

	_hud_label = _make_label("", 15)
	_hud_label.custom_minimum_size = Vector2(170, 0)
	hud_box.add_child(_hud_label)
	_inventory_label = _make_label("", 13)
	_inventory_label.custom_minimum_size = Vector2(270, 0)
	hud_box.add_child(_inventory_label)
	_task_label = _make_label("", 13)
	_task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_box.add_child(_task_label)
	_demand_label = _make_label("", 12)
	_demand_label.custom_minimum_size = Vector2(270, 0)
	hud_box.add_child(_demand_label)
	_tool_label = _make_label("", 13)
	_tool_label.custom_minimum_size = Vector2(160, 0)
	hud_box.add_child(_tool_label)
	_hint_label = _make_label("", 13)
	_hint_label.custom_minimum_size = Vector2(250, 0)
	hud_box.add_child(_hint_label)

	_leave_button = Button.new()
	_leave_button.text = _tr("farm_work.hud.leave", "Verlassen")
	_leave_button.custom_minimum_size = Vector2(92, 42)
	_leave_button.pressed.connect(finish_session)
	hud_box.add_child(_leave_button)

	_context_panel = PanelContainer.new()
	_context_panel.name = "ContextMenu"
	_context_panel.anchor_left = 0.0
	_context_panel.anchor_top = 1.0
	_context_panel.anchor_right = 0.0
	_context_panel.anchor_bottom = 1.0
	_context_panel.offset_left = 12.0
	_context_panel.offset_top = -460.0
	_context_panel.offset_right = 430.0
	_context_panel.offset_bottom = -12.0
	_context_panel.visible = false
	root.add_child(_context_panel)

	var context_scroll := ScrollContainer.new()
	context_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_context_panel.add_child(context_scroll)

	_context_content = VBoxContainer.new()
	_context_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_context_content.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	context_scroll.add_child(_context_content)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _update_all_ui() -> void:
	_sync_locale_state()
	if _hud_label != null:
		var role_label := _tr("farm_work.role.owner", "Besitzer") if actor_role == "owner" else _tr("farm_work.role.worker", "Arbeiter")
		_hud_label.text = _trf("farm_work.hud.main", [
			farm_label,
			role_label,
			score,
			int(maxf(session_duration_sec - elapsed_sec, 0.0)),
		], "%s\n%s | Punkte %d | %02ds")
	if _inventory_label != null:
		_inventory_label.text = _trf("farm_work.hud.inventory", [_player_inventory.format_contents(_localized_item_labels())], "Inventar\n%s")
	if _task_label != null:
		_task_label.text = _trf("farm_work.hud.task", [_get_current_task_label()], "Aufgabe\n%s")
	if _demand_label != null:
		_demand_label.text = _format_demand_hud()
	if _tool_label != null:
		_tool_label.text = _trf("farm_work.hud.tool", [_tool_display_label(_selected_tool), _crop_label(_selected_crop_type)], "Werkzeug\n%s | Pflanze: %s")
	if _leave_button != null:
		_leave_button.text = _tr("farm_work.hud.leave", "Verlassen")
	if _hint_label != null and _nearest_interactable != null:
		_hint_label.text = _trf("farm_work.hud.nearby", [_nearest_interactable.display_name], "In der Nähe\n%s")
	elif _hint_label != null:
		_hint_label.text = _trf("farm_work.hud.nearby", ["-"], "In der Nähe\n-")
	if _context_panel != null and _context_panel.visible and _active_interactable != null:
		_refresh_context_panel()


func _open_context_for(interactable) -> void:
	if interactable == null:
		return
	_active_interactable = interactable
	_context_signature = ""
	if _context_panel != null:
		_context_panel.visible = true
	_refresh_context_panel()


func _refresh_context_panel() -> void:
	if _context_content == null or _active_interactable == null:
		return
	var signature := _get_context_signature(_active_interactable)
	if signature == _context_signature and _context_content.get_child_count() > 0:
		return
	_context_signature = signature
	_clear_children(_context_content)
	if _active_interactable.interactable_type == "barn":
		_build_farm_inventory_context()
		return
	var title := _make_label(_active_interactable.display_name, 17)
	_context_content.add_child(title)
	for line in _get_context_lines(_active_interactable):
		_context_content.add_child(_make_label(str(line), 13))
	var sep := HSeparator.new()
	_context_content.add_child(sep)
	for action in _get_context_actions(_active_interactable):
		var button := Button.new()
		button.text = str(action.get("label", action.get("id", "")))
		button.disabled = bool(action.get("disabled", false))
		button.pressed.connect(_perform_live_action.bind(str(action.get("id", "")), _active_interactable))
		_context_content.add_child(button)


func _get_context_signature(interactable) -> String:
	var state: Dictionary = {
		"id": interactable.interactable_id,
		"type": interactable.interactable_type,
		"locale": LocaleServiceScript.get_language(),
		"player": _player_inventory.get_snapshot(),
	}
	match interactable.interactable_type:
		"field":
			var field = _get_field_data(interactable.interactable_id)
			state["field"] = field.get_snapshot() if field != null else {}
			state["selected_crop"] = _selected_crop_type
		"barn", "shed":
			state["seeds"] = _seed_inventory.get_snapshot()
			state["barn"] = _barn_inventory.get_snapshot()
			state["silo"] = _silo_inventory.get_snapshot()
			state["pickup"] = _pickup_inventory.get_snapshot()
		"silo":
			state["silo"] = _silo_inventory.get_snapshot()
		"windmill":
			state["production"] = _production.get_snapshot()
		"machine_yard":
			state["barn"] = _barn_inventory.get_snapshot()
			state["pickup"] = _pickup_inventory.get_snapshot()
	return JSON.stringify(state)


func _build_farm_inventory_context() -> void:
	var title := _make_label(_tr("farm_work.inventory.title", "Farmlager"), 17)
	_context_content.add_child(title)

	var help := _make_label(_tr("farm_work.inventory.help", "Wähle einen Slot, um einen Stapel zu nehmen."), 12)
	help.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	_context_content.add_child(help)

	_add_inventory_section(_tr("farm_work.inventory.seeds", "Saatgut"), [
		_make_inventory_slot_data("wheat_seed", _seed_inventory, LIVE_TAKE_WHEAT_SEEDS),
		_make_inventory_slot_data("corn_seed", _seed_inventory, LIVE_TAKE_CORN_SEEDS),
		_make_inventory_slot_data("sunflower_seed", _seed_inventory, LIVE_TAKE_SUNFLOWER_SEEDS),
	], "SeedsGrid")
	_add_inventory_section(_tr("farm_work.inventory.stored_products", "Lagerbestand"), [
		_make_inventory_slot_data("wheat_grain", _silo_inventory, LIVE_TAKE_GRAIN_SILO),
		_make_inventory_slot_data("corn_grain", _silo_inventory, LIVE_TAKE_CORN_GRAIN_SILO),
		_make_inventory_slot_data("sunflower_grain", _silo_inventory, LIVE_TAKE_SUNFLOWER_GRAIN_SILO),
		_make_inventory_slot_data("flour_sack", _barn_inventory, LIVE_TAKE_FLOUR_BARN),
		_make_inventory_slot_data("cornmeal_sack", _barn_inventory, LIVE_TAKE_CORNMEAL_BARN),
		_make_inventory_slot_data("sunflower_oil_crate", _barn_inventory, LIVE_TAKE_SUNFLOWER_OIL_BARN),
	], "StoredproductsGrid")

	var capacity := _make_label(_trf("farm_work.inventory.capacity", [
		_barn_inventory.get_total_units(),
		_barn_product_capacity,
		_silo_inventory.get_total_units(),
		_silo_grain_capacity,
	], "Scheune %d / %d   Silo %d / %d"), 12)
	capacity.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_context_content.add_child(capacity)

	var carried := _make_label(_trf("farm_work.inventory.carried", [_player_inventory.format_contents(_localized_item_labels())], "Getragen: %s"), 12)
	carried.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	_context_content.add_child(carried)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	_context_content.add_child(action_row)
	_add_context_action_button(action_row, LIVE_STORE_FLOUR_BARN, _tr("farm_work.action.store_products", "Produkte einlagern"))
	_add_context_action_button(action_row, LIVE_LOAD_PICKUP, _tr("farm_work.action.load_pickup", "Pickup beladen"))


func _add_inventory_section(label: String, slots: Array[Dictionary], grid_name: String = "") -> void:
	var heading := _make_label(label, 14)
	heading.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	_context_content.add_child(heading)

	var grid := GridContainer.new()
	grid.name = grid_name if not grid_name.is_empty() else "%sGrid" % label.replace(" ", "")
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", UiThemeScript.SEPARATION_DENSE)
	grid.add_theme_constant_override("v_separation", UiThemeScript.SEPARATION_DENSE)
	_context_content.add_child(grid)
	for slot in slots:
		grid.add_child(_build_inventory_slot_button(slot))


func _make_inventory_slot_data(item_id: String, inventory, action_id: String) -> Dictionary:
	return {
		"item_id": item_id,
		"amount": inventory.get_amount(item_id) if inventory != null else 0,
		"action_id": action_id,
	}


func _processing_recipe(crop_type: String) -> Dictionary:
	var cleaned := crop_type.strip_edges()
	var recipe := PROCESSING_RECIPES.get(cleaned, {}) as Dictionary
	if recipe == null:
		return {}
	return recipe.duplicate(true)


func _processing_output_item(crop_type: String) -> String:
	var recipe := _processing_recipe(crop_type)
	return str(recipe.get("output_item_id", "flour_sack"))


func _product_inventory_total(inventory) -> int:
	if inventory == null:
		return 0
	var total := 0
	for item_id in PRODUCT_ITEM_IDS:
		total += int(inventory.get_amount(str(item_id)))
	return total


func _item_count_total(counts: Dictionary) -> int:
	var total := 0
	for key in counts.keys():
		total += maxi(int(counts.get(key, 0)), 0)
	return total


func _format_product_counts(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item_id in PRODUCT_ITEM_IDS:
		var amount := maxi(int(counts.get(str(item_id), 0)), 0)
		if amount > 0:
			parts.append("%s x%d" % [_item_label(str(item_id)), amount])
	if parts.is_empty():
		return "-"
	return ", ".join(parts)


func _build_inventory_slot_button(slot: Dictionary) -> Button:
	var item_id := str(slot.get("item_id", ""))
	var amount := maxi(int(slot.get("amount", 0)), 0)
	var action_id := str(slot.get("action_id", ""))
	var button := Button.new()
	button.name = "FarmInventorySlot_%s" % item_id
	button.text = ""
	button.tooltip_text = _trf("farm_work.inventory.take_tooltip", [_item_label(item_id)], "%s nehmen")
	button.custom_minimum_size = Vector2(112, 118)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = amount <= 0 or action_id.is_empty()
	button.add_theme_stylebox_override("normal", _make_inventory_slot_box(UiThemeScript.BG_700, UiThemeScript.BORDER_STRONG))
	button.add_theme_stylebox_override("hover", _make_inventory_slot_box(UiThemeScript.BG_600, UiThemeScript.WARNING))
	button.add_theme_stylebox_override("pressed", _make_inventory_slot_box(UiThemeScript.BG_500, UiThemeScript.ACCENT))
	button.add_theme_stylebox_override("disabled", _make_inventory_slot_box(UiThemeScript.BG_800, UiThemeScript.BORDER))

	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = ItemIconCatalogScript.get_texture(item_id)
	icon.custom_minimum_size = Vector2(58, 58)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = (
		CanvasItem.TEXTURE_FILTER_LINEAR
		if ItemIconCatalogScript.uses_linear_filter(item_id)
		else CanvasItem.TEXTURE_FILTER_NEAREST
	)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = Color(1.0, 1.0, 1.0, 0.45 if button.disabled else 1.0)
	content.add_child(icon)

	var item_label := _make_label(_item_label(item_id), 11)
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(item_label)

	var amount_label := _make_label("x%d" % amount, 12)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_label.add_theme_color_override(
		"font_color",
		UiThemeScript.TEXT_MUTED if button.disabled else UiThemeScript.TEXT_PRIMARY
	)
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(amount_label)

	if not button.disabled:
		button.pressed.connect(_perform_live_action.bind(action_id, _active_interactable))
	return button


func _make_inventory_slot_box(background: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(UiThemeScript.RADIUS_PANEL)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


func _add_context_action_button(parent: Control, action_id: String, label: String) -> void:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_perform_live_action.bind(action_id, _active_interactable))
	parent.add_child(button)


func _get_context_lines(interactable) -> PackedStringArray:
	var lines := PackedStringArray()
	match interactable.interactable_type:
		"field":
			var field = _get_field_data(interactable.interactable_id)
			if field != null:
				lines.append(_trf("farm_work.context.field_plant", [_field_crop_label(field)], "Pflanze: %s"))
				lines.append(_trf("farm_work.context.field_growth", [int(round(field.growth * 100.0))], "Wachstum: %d%%"))
				lines.append(_trf("farm_work.context.field_water", [int(round(field.water * 100.0))], "Wasser: %d%%"))
				lines.append(_trf("farm_work.context.field_state", [_field_state_label(field)], "Status: %s"))
				lines.append(_trf("farm_work.context.field_action", [_field_action_hint(field)], "Nächste Aktion: %s"))
		"silo":
			lines.append(_trf("farm_work.context.silo_wheat", [_silo_inventory.get_amount("wheat_grain")], "Weizen: %d"))
			lines.append(_trf("farm_work.context.silo_corn", [_silo_inventory.get_amount("corn_grain")], "Mais: %d"))
			lines.append(_trf("farm_work.context.silo_sunflowers", [_silo_inventory.get_amount("sunflower_grain")], "Sonnenblumen: %d"))
			lines.append(_trf("farm_work.context.capacity", [_silo_inventory.get_total_units(), _silo_grain_capacity], "Kapazität: %d / %d"))
		"windmill":
			var snapshot: Dictionary = _production.get_snapshot()
			var pending_products := snapshot.get("produced_items_pending", {}) as Dictionary
			if pending_products == null:
				pending_products = {}
			lines.append(_trf("farm_work.context.grain", [_crop_label(str(snapshot.get("selected_grain_type", CROP_WHEAT)))], "Getreide: %s"))
			lines.append(_trf("farm_work.context.required_input", [
				int(snapshot.get("required_grain", 0)),
				_item_label(str(snapshot.get("input_item_id", "wheat_grain"))),
			], "Benötigt: %d %s"))
			lines.append(_trf("farm_work.context.output_batch", [
				int(snapshot.get("output_amount", 0)),
				_item_label(str(snapshot.get("output_item_id", "flour_sack"))),
			], "Output: %d %s"))
			lines.append(_trf("farm_work.context.duration", [float(snapshot.get("duration_sec", 0.0))], "Dauer: %.1fs"))
			lines.append(_trf("farm_work.context.progress", [int(round(float(snapshot.get("progress_ratio", 0.0)) * 100.0))], "Fortschritt: %d%%"))
			lines.append(_trf("farm_work.context.products_ready", [_format_product_counts(pending_products)], "Produkte bereit: %s"))
		"barn":
			lines.append(_tr("farm_work.inventory.stored_products", "Lagerbestand"))
			lines.append(_trf("farm_work.context.products", [_format_product_counts(_barn_inventory.get_snapshot())], "Produkte: %s"))
			lines.append(_trf("farm_work.context.grain_stock", [
				_silo_inventory.get_amount("wheat_grain"),
				_silo_inventory.get_amount("corn_grain"),
				_silo_inventory.get_amount("sunflower_grain"),
			], "Getreide: Weizen %d | Mais %d | Sonnenblumen %d"))
			lines.append(_tr("farm_work.inventory.seeds", "Saatgut"))
			lines.append(_trf("farm_work.context.seed_stock", [
				_seed_inventory.get_amount("wheat_seed"),
				_seed_inventory.get_amount("corn_seed"),
				_seed_inventory.get_amount("sunflower_seed"),
			], "Weizen %d | Mais %d | Sonnenblume %d"))
			lines.append(_trf("farm_work.context.storage", [
				_barn_inventory.get_total_units(),
				_barn_product_capacity,
				_silo_inventory.get_total_units(),
				_silo_grain_capacity,
			], "Lager: Scheune %d / %d | Silo %d / %d"))
		"shed":
			lines.append(_trf("farm_work.context.tools", [_item_label("watering_can"), _item_label("sickle"), _item_label("shovel")], "Werkzeuge: %s, %s, %s"))
			lines.append(_trf("farm_work.context.seeds", [
				_seed_inventory.get_amount("wheat_seed"),
				_seed_inventory.get_amount("corn_seed"),
				_seed_inventory.get_amount("sunflower_seed"),
			], "Saatgut: Weizen %d | Mais %d | Sonnenblume %d"))
			lines.append(_tr("farm_work.context.sacks", "Säcke: leere Mehlsäcke"))
		"machine_yard":
			lines.append(_tr("farm_work.context.vehicle_pickup", "Fahrzeug: Pickup"))
			lines.append(_tr("farm_work.context.status_parked", "Status: geparkt"))
			lines.append(_trf("farm_work.context.cargo_products", [
				_product_inventory_total(_pickup_inventory),
				PICKUP_PRODUCT_CAPACITY,
				_format_product_counts(_pickup_inventory.get_snapshot()),
			], "Ladung: %d / %d Produkte (%s)"))
			if not demand_entries.is_empty():
				var priority := demand_entries[0]
				lines.append(_trf("farm_work.context.priority", [
					str(priority.get("target_name", _tr("farm_work.generic.business", "Business"))),
					int(priority.get("need", 0)),
					str(priority.get("target_item_label", _tr("farm_work.generic.goods", "goods"))),
				], "Priorität: %s benötigt %d %s"))
		"gate":
			lines.append(_tr("farm_work.context.exit_gate", "Ausgang: zurück zum Stadttor"))
	return lines


func _get_context_actions(interactable) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	match interactable.interactable_type:
		"field":
			var field = _get_field_data(interactable.interactable_id)
			if field != null:
				var crop_type := str(field.allowed_crop_type)
				actions.append({"id": "select_%s" % crop_type, "label": _trf("farm_work.action.select_crop", [_crop_label(crop_type)], "%s auswählen")})
			actions.append({"id": LIVE_SOW_FIELD, "label": _tr("farm_work.action.sow", "Säen")})
			actions.append({"id": LIVE_WATER_FIELD, "label": _tr("farm_work.action.water", "Gießen")})
			actions.append({"id": LIVE_HARVEST_FIELD, "label": _tr("farm_work.action.harvest", "Ernten")})
		"silo":
			actions.append({"id": LIVE_STORE_GRAIN_SILO, "label": _tr("farm_work.action.store_carried_grain", "Getragenes Getreide einlagern")})
			actions.append({"id": LIVE_TAKE_GRAIN_SILO, "label": _tr("farm_work.action.take_wheat_silo", "Weizen aus Silo nehmen")})
			actions.append({"id": LIVE_TAKE_CORN_GRAIN_SILO, "label": _tr("farm_work.action.take_corn_silo", "Mais aus Silo nehmen")})
			actions.append({"id": LIVE_TAKE_SUNFLOWER_GRAIN_SILO, "label": _tr("farm_work.action.take_sunflower_silo", "Sonnenblumen aus Silo nehmen")})
			actions.append({"id": LIVE_START_WINDMILL, "label": _tr("farm_work.action.send_wheat_windmill", "Weizen zur Windmühle schicken")})
			actions.append({"id": LIVE_START_CORN_PROCESSING, "label": _tr("farm_work.action.send_corn_windmill", "Mais zur Mühle schicken")})
			actions.append({"id": LIVE_START_SUNFLOWER_PROCESSING, "label": _tr("farm_work.action.send_sunflower_press", "Sonnenblumen zur Presse schicken")})
		"windmill":
			actions.append({"id": LIVE_START_WINDMILL, "label": _tr("farm_work.action.start_flour", "Mehl mahlen")})
			actions.append({"id": LIVE_START_CORN_PROCESSING, "label": _tr("farm_work.action.start_cornmeal", "Maismehl mahlen")})
			actions.append({"id": LIVE_START_SUNFLOWER_PROCESSING, "label": _tr("farm_work.action.start_oil", "Sonnenblumenöl pressen")})
			actions.append({"id": LIVE_PAUSE_WINDMILL, "label": _tr("farm_work.action.pause_production", "Produktion pausieren")})
			actions.append({"id": LIVE_COLLECT_FLOUR, "label": _tr("farm_work.action.collect_products", "Produkte abholen")})
		"barn":
			actions.append({"id": LIVE_STORE_FLOUR_BARN, "label": _tr("farm_work.action.store_products", "Produkte einlagern")})
			actions.append({"id": LIVE_TAKE_FLOUR_BARN, "label": _tr("farm_work.action.take_flour_sacks", "Mehlsäcke nehmen")})
			actions.append({"id": LIVE_TAKE_CORNMEAL_BARN, "label": _tr("farm_work.action.take_cornmeal_sacks", "Maismehl nehmen")})
			actions.append({"id": LIVE_TAKE_SUNFLOWER_OIL_BARN, "label": _tr("farm_work.action.take_oil_crates", "Ölkisten nehmen")})
			actions.append({"id": LIVE_LOAD_PICKUP, "label": _tr("farm_work.action.prepare_pickup", "Pickup-Ladung vorbereiten")})
		"shed":
			_append_seed_actions(actions)
		"machine_yard":
			actions.append({"id": LIVE_USE_PICKUP, "label": _tr("farm_work.action.use_pickup", "Pickup nutzen")})
			actions.append({"id": LIVE_LOAD_PICKUP, "label": _tr("farm_work.action.load_pickup", "Pickup beladen")})
		"gate":
			actions.append({"id": LIVE_LEAVE_FARM, "label": _tr("farm_work.action.leave_farm", "Farm verlassen")})
	return actions


func _append_seed_actions(actions: Array[Dictionary]) -> void:
	actions.append({"id": LIVE_TAKE_WHEAT_SEEDS, "label": _tr("farm_work.action.take_wheat_seeds", "Weizensaat nehmen")})
	actions.append({"id": LIVE_TAKE_CORN_SEEDS, "label": _tr("farm_work.action.take_corn_seeds", "Maissaat nehmen")})
	actions.append({"id": LIVE_TAKE_SUNFLOWER_SEEDS, "label": _tr("farm_work.action.take_sunflower_seeds", "Sonnenblumensaat nehmen")})


func _perform_live_action(action_id: String, interactable) -> Dictionary:
	var result := {"correct": false, "reason": "unsupported", "action": action_id}
	match action_id:
		"select_wheat":
			_selected_crop_type = CROP_WHEAT
			_selected_tool = "Seed bag"
			result = _ok("selected_wheat")
		"select_corn":
			_selected_crop_type = CROP_CORN
			_selected_tool = "Seed bag"
			result = _ok("selected_corn")
		"select_sunflower":
			_selected_crop_type = CROP_SUNFLOWER
			_selected_tool = "Seed bag"
			result = _ok("selected_sunflower")
		LIVE_TAKE_WHEAT_SEEDS:
			result = _take_seeds(CROP_WHEAT)
		LIVE_TAKE_CORN_SEEDS:
			result = _take_seeds(CROP_CORN)
		LIVE_TAKE_SUNFLOWER_SEEDS:
			result = _take_seeds(CROP_SUNFLOWER)
		LIVE_SOW_FIELD:
			result = _sow_live_field(interactable)
		LIVE_WATER_FIELD:
			result = _water_live_field(interactable)
		LIVE_HARVEST_FIELD:
			result = _harvest_live_field(interactable)
		LIVE_STORE_GRAIN_SILO:
			result = _store_grain_in_silo()
		LIVE_TAKE_GRAIN_SILO:
			result = _take_grain_from_silo(CROP_WHEAT)
		LIVE_TAKE_CORN_GRAIN_SILO:
			result = _take_grain_from_silo(CROP_CORN)
		LIVE_TAKE_SUNFLOWER_GRAIN_SILO:
			result = _take_grain_from_silo(CROP_SUNFLOWER)
		LIVE_START_WINDMILL:
			result = _start_windmill()
		LIVE_START_CORN_PROCESSING:
			result = _start_processing(CROP_CORN)
		LIVE_START_SUNFLOWER_PROCESSING:
			result = _start_processing(CROP_SUNFLOWER)
		LIVE_PAUSE_WINDMILL:
			result = _pause_windmill()
		LIVE_COLLECT_FLOUR:
			result = _collect_flour_sacks()
		LIVE_STORE_FLOUR_BARN:
			result = _store_flour_in_barn()
		LIVE_TAKE_FLOUR_BARN:
			result = _take_flour_from_barn()
		LIVE_TAKE_CORNMEAL_BARN:
			result = _take_product_from_barn("cornmeal_sack")
		LIVE_TAKE_SUNFLOWER_OIL_BARN:
			result = _take_product_from_barn("sunflower_oil_crate")
		LIVE_LOAD_PICKUP:
			result = _load_pickup()
		LIVE_USE_PICKUP:
			result = _ok("pickup_ready")
			_set_hint(_tr("farm_work.hint.pickup_selected", "Pickup als temporäres Farmfahrzeug ausgewählt."))
		LIVE_LEAVE_FARM:
			finish_session()
			result = _ok("left_farm")
		_:
			_wrong_live_action("unsupported")
	_update_all_field_visuals()
	_update_all_ui()
	return result


func _take_seeds(crop_type: String) -> Dictionary:
	var cleaned_crop := crop_type.strip_edges()
	if not SUPPORTED_CROPS.has(cleaned_crop):
		return _wrong_live_action("unknown_seed_type")
	var seed_id := "%s_seed" % cleaned_crop
	var moved: int = int(_seed_inventory.transfer_to(
		_player_inventory,
		seed_id,
		mini(_seed_inventory.get_amount(seed_id), SEED_WITHDRAWAL_AMOUNT)
	))
	if moved <= 0:
		return _wrong_live_action("seed_stock_empty")
	for tool_id in ["watering_can", "sickle", "shovel"]:
		if not _player_inventory.has_item(tool_id):
			_player_inventory.add_item(tool_id, 1)
	var missing_sacks := maxi(4 - _player_inventory.get_amount("empty_sack"), 0)
	if missing_sacks > 0:
		_player_inventory.add_item("empty_sack", missing_sacks)
	_selected_crop_type = cleaned_crop
	_selected_tool = "Seed bag"
	if cleaned_crop == CROP_WHEAT:
		_mark_task_done("take_seed")
	_set_hint(_trf("farm_work.hint.seeds_taken", [moved, _item_label(seed_id)], "%d %s aus dem Farmlager genommen."))
	return _ok("%s_seeds_taken" % cleaned_crop)


func _sow_live_field(interactable) -> Dictionary:
	var field = _field_from_interactable(interactable)
	if field == null:
		return _wrong_live_action("not_field")
	var seed_id := "%s_seed" % _selected_crop_type
	if not field.can_sow(_selected_crop_type):
		return _wrong_live_action("wrong_crop_or_state")
	if not _player_inventory.has_item(seed_id):
		return _wrong_live_action("missing_seed")
	_player_inventory.remove_item(seed_id, 1)
	field.sow(_selected_crop_type)
	_selected_tool = "Seed bag"
	if field.field_id == "field_wheat":
		_mark_task_done("sow_wheat")
	_set_hint(_trf("farm_work.hint.sowed", [_field_crop_label(field)], "%s gesät."))
	return _ok("sowed")


func _water_live_field(interactable) -> Dictionary:
	var field = _field_from_interactable(interactable)
	if field == null:
		return _wrong_live_action("not_field")
	if not _player_inventory.has_item("watering_can"):
		return _wrong_live_action("missing_watering_can")
	if not field.water_field():
		return _wrong_live_action("field_not_waterable")
	_selected_tool = "Watering can"
	if field.field_id == "field_wheat":
		_mark_task_done("water_wheat")
	_set_hint(_trf("farm_work.hint.watered", [field.display_name], "%s bewässert."))
	return _ok("watered")


func _harvest_live_field(interactable) -> Dictionary:
	var field = _field_from_interactable(interactable)
	if field == null:
		return _wrong_live_action("not_field")
	if not _player_inventory.has_item("sickle"):
		return _wrong_live_action("missing_sickle")
	var units: int = int(field.harvest(WHEAT_HARVEST_UNITS))
	if units <= 0:
		return _wrong_live_action("field_not_mature")
	var grain_id := "%s_grain" % field.crop_type
	_player_inventory.add_item(grain_id, units)
	_live_harvested_amount += units
	harvested_amount += units
	_selected_tool = "Sickle"
	if field.field_id == "field_wheat":
		_mark_task_done("harvest_wheat")
	_set_hint(_trf("farm_work.hint.harvested", [_field_crop_label(field)], "%s geerntet."))
	return _ok("harvested")


func _store_grain_in_silo() -> Dictionary:
	var moved := 0
	for crop in [CROP_WHEAT, CROP_CORN, CROP_SUNFLOWER]:
		var item_id := "%s_grain" % crop
		moved += _player_inventory.transfer_to(_silo_inventory, item_id, _player_inventory.get_amount(item_id))
	if moved <= 0:
		return _wrong_live_action("no_grain_to_store")
	delivered_crates += 1
	_mark_task_done("store_silo")
	_set_hint(_trf("farm_work.hint.stored_grain", [moved], "%d Getreide im Silo eingelagert."))
	return _ok("stored_silo")


func _take_grain_from_silo(crop_type: String) -> Dictionary:
	var cleaned_crop := crop_type.strip_edges()
	if not SUPPORTED_CROPS.has(cleaned_crop):
		return _wrong_live_action("unknown_grain_type")
	var grain_id := "%s_grain" % cleaned_crop
	var moved: int = int(_silo_inventory.transfer_to(
		_player_inventory,
		grain_id,
		mini(_silo_inventory.get_amount(grain_id), 10)
	))
	if moved <= 0:
		return _wrong_live_action("silo_has_no_%s" % cleaned_crop)
	_set_hint(_trf("farm_work.hint.took_grain", [moved, _crop_label(cleaned_crop)], "%d %s aus dem Silo genommen."))
	return _ok("%s_grain_taken" % cleaned_crop)


func _start_windmill() -> Dictionary:
	return _start_processing(CROP_WHEAT)


func _start_processing(crop_type: String) -> Dictionary:
	var cleaned_crop := crop_type.strip_edges()
	if not SUPPORTED_CROPS.has(cleaned_crop):
		return _wrong_live_action("unknown_grain_type")
	var recipe := _processing_recipe(cleaned_crop)
	if recipe.is_empty():
		return _wrong_live_action("unknown_grain_type")
	if _production.start(cleaned_crop, _silo_inventory, recipe):
		var output_item := str(recipe.get("output_item_id", "flour_sack"))
		_mark_task_done("start_mill")
		_set_hint(_trf("farm_work.hint.processing_started", [
			_crop_label(cleaned_crop),
			_item_label(output_item),
		], "Produktion gestartet: %s -> %s."))
		return _ok("windmill_started")
	return _wrong_live_action("not_enough_processing_input_or_running")


func _pause_windmill() -> Dictionary:
	if _production.pause():
		_set_hint(_tr("farm_work.hint.windmill_paused", "Windmühle pausiert.") if _production.paused else _tr("farm_work.hint.windmill_resumed", "Windmühle fortgesetzt."))
		return _ok("windmill_pause_toggle")
	return _wrong_live_action("windmill_not_running")


func _collect_flour_sacks() -> Dictionary:
	var products: Dictionary = _production.collect_items()
	var moved := _add_product_counts_to_inventory(_player_inventory, products)
	if moved <= 0:
		return _wrong_live_action("no_products_ready")
	_player_inventory.remove_item("empty_sack", mini(_player_inventory.get_amount("empty_sack"), moved))
	_mark_task_done("collect_flour")
	_set_hint(_trf("farm_work.hint.collected_products", [_format_product_counts(products)], "Produkte abgeholt: %s."))
	return _ok("flour_collected")


func _store_flour_in_barn() -> Dictionary:
	var moved := 0
	for item_id in PRODUCT_ITEM_IDS:
		moved += _player_inventory.transfer_to(_barn_inventory, str(item_id), _player_inventory.get_amount(str(item_id)))
	if moved <= 0:
		return _wrong_live_action("no_products_to_store")
	_mark_task_done("store_barn")
	_set_hint(_trf("farm_work.hint.stored_products", [moved], "%d Produkte in der Scheune eingelagert."))
	return _ok("flour_stored")


func _take_flour_from_barn() -> Dictionary:
	return _take_product_from_barn("flour_sack")


func _take_product_from_barn(item_id: String) -> Dictionary:
	var cleaned := item_id.strip_edges()
	if not PRODUCT_ITEM_IDS.has(cleaned):
		return _wrong_live_action("unsupported")
	var moved: int = int(_barn_inventory.transfer_to(
		_player_inventory,
		cleaned,
		mini(_barn_inventory.get_amount(cleaned), 4)
	))
	if moved <= 0:
		return _wrong_live_action("barn_has_no_product")
	_set_hint(_trf("farm_work.hint.took_product", [moved, _item_label(cleaned)], "%d %s aus der Scheune genommen."))
	return _ok("flour_taken")


func _load_pickup() -> Dictionary:
	var moved := _transfer_products_to_pickup(_barn_inventory, PICKUP_PRODUCT_CAPACITY - _product_inventory_total(_pickup_inventory))
	moved += _transfer_products_to_pickup(_player_inventory, PICKUP_PRODUCT_CAPACITY - _product_inventory_total(_pickup_inventory))
	if moved <= 0:
		return _wrong_live_action("no_products_to_load")
	delivered_crates += moved
	_mark_task_done("load_pickup")
	_set_hint(_trf("farm_work.hint.loaded_pickup", [moved], "%d Produkte auf den Pickup geladen."))
	return _ok("pickup_loaded")


func _add_product_counts_to_inventory(inventory, counts: Dictionary) -> int:
	if inventory == null:
		return 0
	var moved := 0
	for item_id in PRODUCT_ITEM_IDS:
		var amount := maxi(int(counts.get(str(item_id), 0)), 0)
		if amount > 0:
			moved += int(inventory.add_item(str(item_id), amount))
	return moved


func _transfer_products_to_pickup(source_inventory, max_units: int) -> int:
	if source_inventory == null or max_units <= 0:
		return 0
	var moved := 0
	var remaining := max_units
	for item_id in PRODUCT_ITEM_IDS:
		if remaining <= 0:
			break
		var transfer_amount := mini(source_inventory.get_amount(str(item_id)), remaining)
		if transfer_amount <= 0:
			continue
		var transferred: int = int(source_inventory.transfer_to(_pickup_inventory, str(item_id), transfer_amount))
		moved += transferred
		remaining -= transferred
	return moved


func _tick_live_systems(delta: float) -> void:
	for field in _fields:
		var became_mature: bool = bool(field.tick_growth(delta, LIVE_GROWTH_DURATION_SEC))
		if became_mature:
			if field.field_id == "field_wheat":
				_mark_task_done("wait_growth")
			_live_growth_minutes_added = maxi(_live_growth_minutes_added, int(round(_farm_growth_total_minutes * field.growth)))
			_set_hint(_trf("farm_work.hint.field_mature", [field.display_name], "%s ist reif."))
	var produced: Dictionary = _production.tick(delta)
	if not produced.is_empty():
		_set_hint(_trf("farm_work.hint.processing_produced", [_format_product_counts(produced)], "Produktion fertig: %s."))
	_update_all_field_visuals()


func _ok(reason: String) -> Dictionary:
	return {"correct": true, "reason": reason, "score": score}


func _wrong_live_action(reason: String) -> Dictionary:
	mistakes += 1
	score = maxi(score - 6, 0)
	quality_score = clampf(quality_score - 0.07, 0.0, 1.0)
	_set_hint(_trf("farm_work.hint.action_unavailable", [_action_error_label(reason)], "Aktion nicht möglich: %s."))
	mistake_made.emit(reason)
	return {"correct": false, "reason": reason, "score": score, "mistakes": mistakes}


func _action_error_label(reason: String) -> String:
	match reason:
		"unsupported":
			return _tr("farm_work.error.unsupported", "nicht unterstützt")
		"unknown_seed_type":
			return _tr("farm_work.error.unknown_seed_type", "unbekannte Saat")
		"seed_stock_empty":
			return _tr("farm_work.error.seed_stock_empty", "Saatgut ist leer")
		"not_field":
			return _tr("farm_work.error.not_field", "das ist kein Feld")
		"wrong_crop_or_state":
			return _tr("farm_work.error.wrong_crop_or_state", "falsche Saat oder Feldzustand")
		"missing_seed":
			return _tr("farm_work.error.missing_seed", "Saatgut fehlt")
		"missing_watering_can":
			return _tr("farm_work.error.missing_watering_can", "Gießkanne fehlt")
		"field_not_waterable":
			return _tr("farm_work.error.field_not_waterable", "Feld braucht gerade kein Wasser")
		"missing_sickle":
			return _tr("farm_work.error.missing_sickle", "Sichel fehlt")
		"field_not_mature":
			return _tr("farm_work.error.field_not_mature", "Feld ist noch nicht reif")
		"no_grain_to_store":
			return _tr("farm_work.error.no_grain_to_store", "kein Getreide zum Einlagern")
		"unknown_grain_type":
			return _tr("farm_work.error.unknown_grain_type", "unbekannte Getreidesorte")
		"not_enough_wheat_or_running":
			return _tr("farm_work.error.not_enough_wheat_or_running", "nicht genug Weizen oder Mühle läuft bereits")
		"not_enough_processing_input_or_running":
			return _tr("farm_work.error.not_enough_processing_input_or_running", "nicht genug Rohware oder Produktion läuft bereits")
		"windmill_not_running":
			return _tr("farm_work.error.windmill_not_running", "Mühle läuft nicht")
		"no_flour_ready":
			return _tr("farm_work.error.no_flour_ready", "kein Mehl bereit")
		"no_products_ready":
			return _tr("farm_work.error.no_products_ready", "keine Produkte bereit")
		"no_flour_to_store":
			return _tr("farm_work.error.no_flour_to_store", "keine Mehlsäcke zum Einlagern")
		"no_products_to_store":
			return _tr("farm_work.error.no_products_to_store", "keine Produkte zum Einlagern")
		"barn_has_no_flour":
			return _tr("farm_work.error.barn_has_no_flour", "keine Mehlsäcke in der Scheune")
		"barn_has_no_product":
			return _tr("farm_work.error.barn_has_no_product", "dieses Produkt ist nicht in der Scheune")
		"no_flour_to_load":
			return _tr("farm_work.error.no_flour_to_load", "keine Mehlsäcke zum Beladen")
		"no_products_to_load":
			return _tr("farm_work.error.no_products_to_load", "keine Produkte zum Beladen")
	if reason.begins_with("silo_has_no_"):
		return _trf("farm_work.error.silo_has_no", [_crop_label(reason.substr("silo_has_no_".length()))], "kein %s im Silo")
	return reason.replace("_", " ")


func _mark_task_done(task_id: String) -> void:
	if _task_flags.has(task_id):
		return
	_task_flags[task_id] = true
	completed_tasks += 1
	score += 12 + mini(player_skill_level, 5)
	quality_score = clampf(quality_score + 0.015, 0.0, 1.0)
	score_changed.emit(score)


func _get_completed_task_count() -> int:
	var count := 0
	for task_id in TASK_FLOW:
		if _task_flags.has(task_id):
			count += 1
	return count


func _get_current_task_label() -> String:
	for task_id in TASK_FLOW:
		if not _task_flags.has(task_id):
			return _task_label_for_id(task_id)
	return _tr("farm_work.task.load_complete", "Ladung fertig")


func _task_label_for_id(task_id: String) -> String:
	match task_id:
		"take_seed":
			return _tr("farm_work.task.take_seed", "Weizensaat aus dem Farmlager holen")
		"sow_wheat":
			return _tr("farm_work.task.sow_wheat", "Weizen auf dem Weizenfeld säen")
		"water_wheat":
			return _tr("farm_work.task.water_wheat", "Weizenfeld bewässern")
		"wait_growth":
			return _tr("farm_work.task.wait_growth", "Wachstum des Weizens abwarten")
		"harvest_wheat":
			return _tr("farm_work.task.harvest_wheat", "Weizen ernten")
		"store_silo":
			return _tr("farm_work.task.store_silo", "Getreide im Silo einlagern")
		"start_mill":
			return _tr("farm_work.task.start_mill", "Windmühle starten")
		"collect_flour":
			return _tr("farm_work.task.collect_flour", "Mehlsäcke abholen")
		"store_barn":
			return _tr("farm_work.task.store_barn", "Säcke in der Scheune lagern")
		"load_pickup":
			return _tr("farm_work.task.load_pickup", "Pickup beladen")
	return task_id


func _update_player_motion(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	if input_dir.length_squared() > 0.0001:
		input_dir = input_dir.normalized().rotated(Vector3.UP, _camera_yaw)
		_player.velocity.x = input_dir.x * player_speed
		_player.velocity.z = input_dir.z * player_speed
		_player.look_at(_player.global_position + input_dir, Vector3.UP)
	else:
		_player.velocity.x = move_toward(_player.velocity.x, 0.0, player_speed * delta * 6.0)
		_player.velocity.z = move_toward(_player.velocity.z, 0.0, player_speed * delta * 6.0)
	if not _player.is_on_floor():
		_player.velocity.y -= 18.0 * delta
	else:
		_player.velocity.y = 0.0
	_player.move_and_slide()


func _update_camera(delta: float) -> void:
	if _camera_pivot == null or _player == null:
		return
	var target := _player.global_position + Vector3.UP * 0.25
	var blend := 1.0 - exp(-8.0 * delta)
	_camera_pivot.global_position = _camera_pivot.global_position.lerp(target, blend)
	_camera_pivot.rotation.y = lerp_angle(_camera_pivot.rotation.y, _camera_yaw, blend)


func _update_nearest_interactable() -> void:
	if _player == null:
		return
	var best = null
	var best_dist := INF
	for interactable in _interactables:
		if interactable == null or not is_instance_valid(interactable):
			continue
		var dist := _planar_distance(_player.global_position, interactable.global_position)
		if dist <= interactable.interaction_radius and dist < best_dist:
			best = interactable
			best_dist = dist
	if best == _nearest_interactable:
		return
	if _nearest_interactable != null and is_instance_valid(_nearest_interactable):
		_nearest_interactable.set_highlighted(false)
	_nearest_interactable = best
	if _nearest_interactable != null:
		_nearest_interactable.set_highlighted(true)


func _on_interactable_requested(interactable) -> void:
	if interactable == null:
		return
	if _player != null and _planar_distance(_player.global_position, interactable.global_position) > interactable.interaction_radius + 0.75:
		_set_hint(_trf("farm_work.hint.move_closer", [interactable.display_name], "Geh näher zu %s."))
		return
	_open_context_for(interactable)


func _field_from_interactable(interactable):
	if interactable == null or interactable.interactable_type != "field":
		return null
	return _get_field_data(interactable.interactable_id)


func _get_field_data(field_id: String):
	for field in _fields:
		if field.field_id == field_id:
			return field
	return null


func _find_interactable(interactable_id: String):
	for interactable in _interactables:
		if interactable.interactable_id == interactable_id:
			return interactable
	return null


func _field_action_hint(field) -> String:
	if field.can_sow(_selected_crop_type):
		return _tr("farm_work.action.sow", "Säen")
	if field.can_water():
		return _tr("farm_work.action.water", "Gießen")
	if field.can_harvest():
		return _tr("farm_work.action.harvest", "Ernten")
	return "-"


func _update_all_field_visuals() -> void:
	for field in _fields:
		_update_field_visual(field)


func _update_field_visual(field) -> void:
	if field == null or not _field_visuals.has(field.field_id):
		return
	var visual: Dictionary = _field_visuals[field.field_id]
	var crop_nodes: Array = visual.get("crop_nodes", [])
	var active_index := 0
	match field.crop_type if not field.crop_type.is_empty() else field.allowed_crop_type:
		CROP_CORN:
			active_index = 1
		CROP_SUNFLOWER:
			active_index = 2
	if crop_nodes.size() == 1:
		active_index = 0
	var show_crop := int(field.state) != FIELD_PREPARED and int(field.state) != FIELD_HARVESTED
	for index in range(crop_nodes.size()):
		var crop_node := crop_nodes[index] as MultiMeshInstance3D
		if crop_node == null or crop_node.multimesh == null:
			continue
		crop_node.visible = show_crop and index == active_index
		if not crop_node.visible:
			continue
		var ratio := 1.0 if int(field.state) == FIELD_MATURE else clampf(maxf(field.growth, 0.2), 0.2, 1.0)
		crop_node.multimesh.visible_instance_count = clampi(
			int(ceil(float(crop_node.multimesh.instance_count) * ratio)),
			1,
			crop_node.multimesh.instance_count
		)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _sync_locale_state() -> void:
	var language := LocaleServiceScript.get_language()
	if language == _last_locale:
		return
	_last_locale = language
	_context_signature = ""
	_update_localized_field_labels()
	_update_localized_interactable_labels()


func _update_localized_field_labels() -> void:
	for field in _fields:
		if field == null:
			continue
		field.display_name = _field_display_name(str(field.field_id))


func _update_localized_interactable_labels() -> void:
	for interactable in _interactables:
		if interactable == null or not is_instance_valid(interactable):
			continue
		if interactable.interactable_type == "field":
			var field = _get_field_data(interactable.interactable_id)
			if field != null:
				interactable.display_name = field.display_name
		else:
			interactable.display_name = _interactable_label(str(interactable.interactable_id))


func _tr(key: String, fallback: String = "") -> String:
	return LocaleServiceScript.t(key, fallback)


func _trf(key: String, args: Array, fallback: String) -> String:
	return _tr(key, fallback) % args


func _localized_item_labels() -> Dictionary:
	var labels: Dictionary = {}
	for item_id in ITEM_LABEL_KEYS.keys():
		labels[item_id] = _item_label(str(item_id))
	return labels


func _field_display_name(field_id: String) -> String:
	match field_id:
		"field_wheat":
			return _tr("farm_work.field.wheat", "Weizenfeld")
		"field_corn":
			return _tr("farm_work.field.corn", "Maisfeld")
	return field_id


func _interactable_label(interactable_id: String) -> String:
	match interactable_id:
		"barn":
			return _tr("farm_work.interactable.barn", "Farmlager")
		"shed":
			return _tr("farm_work.interactable.shed", "Werkzeug- und Saatlager")
		"silo":
			return _tr("farm_work.interactable.silo", "Getreidesilo")
		"windmill":
			return _tr("farm_work.interactable.windmill", "Windmühlenproduktion")
		"gate":
			return _tr("farm_work.interactable.gate", "Hoftor")
	return interactable_id


func _crop_label(crop_type: String) -> String:
	var key := str(CROP_LABEL_KEYS.get(crop_type, ""))
	return _tr(key, crop_type) if not key.is_empty() else crop_type


func _field_crop_label(field) -> String:
	if field == null:
		return "-"
	var crop_type := str(field.crop_type)
	if crop_type.is_empty():
		crop_type = str(field.allowed_crop_type)
	return _crop_label(crop_type)


func _field_state_label(field) -> String:
	if field == null:
		return "-"
	match int(field.state):
		FIELD_PREPARED:
			return _tr("farm_work.field_state.prepared", "vorbereitet")
		FIELD_SEEDED:
			return _tr("farm_work.field_state.seeded", "gesät")
		FIELD_GROWING:
			return _tr("farm_work.field_state.growing", "wächst")
		FIELD_MATURE:
			return _tr("farm_work.field_state.mature", "reif")
		FIELD_HARVESTED:
			return _tr("farm_work.field_state.harvested", "geerntet")
	return str(field.get_state_label())


func _item_label(item_id: String) -> String:
	var key := str(ITEM_LABEL_KEYS.get(item_id, ""))
	return _tr(key, item_id) if not key.is_empty() else item_id

func _tool_display_label(tool: String) -> String:
	match tool:
		"Hands":
			return _tr("farm_work.tool.hands", "Hände")
		"Seed bag":
			return _tr("farm_work.tool.seed_bag", "Saatbeutel")
		"Watering can":
			return _tr("farm_work.item.watering_can", "Gießkanne")
		"Sickle":
			return _tr("farm_work.item.sickle", "Sichel")
	return tool


func _set_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = _trf("farm_work.hud.hint", [text], "Hinweis\n%s")


func _calculate_units_per_crate() -> int:
	if suggested_harvest_units <= 0:
		return FALLBACK_UNITS_PER_CRATE
	return maxi(int(ceil(float(suggested_harvest_units) / 3.0)), 1)


func _calculate_work_minutes() -> int:
	var progress := clampf(elapsed_sec / maxf(session_duration_sec, 1.0), 0.25, 1.0)
	return maxi(int(round(float(work_minutes) * progress)), 15)


func _format_demand_hud() -> String:
	if demand_entries.is_empty():
		return _tr("farm_work.demand.none", "Nachfrage\nKeine offenen Bestellungen")
	var lines := PackedStringArray([_tr("farm_work.hud.demand_title", "Nachfrage")])
	var count := mini(demand_entries.size(), 2)
	for index in range(count):
		var entry := demand_entries[index]
		lines.append("%s: %d %s" % [
			str(entry.get("target_name", _tr("farm_work.generic.business", "Business"))),
			int(entry.get("need", 0)),
			str(entry.get("target_item_label", _tr("farm_work.generic.goods", "goods"))),
		])
	if demand_entries.size() > count:
		lines.append(_trf("farm_work.demand.more", [demand_entries.size() - count], "+%d weitere"))
	return "\n".join(lines)


func _is_text_input_focused() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner: Control = viewport.gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _reset_legacy_plots() -> void:
	_legacy_plots.clear()
	if crop_ready and available_storage > 0:
		_legacy_plots.append(_legacy_make_plot(true, true, 0, true))
		_legacy_plots.append(_legacy_make_plot(true, false, 0, true))
		_legacy_plots.append(_legacy_make_plot(true, true, 1, true))
		_legacy_plots.append(_legacy_make_plot(true, true, 0, true))
	else:
		_legacy_plots.append(_legacy_make_plot(false, false, 0, false))
		_legacy_plots.append(_legacy_make_plot(true, false, 0, false))
		_legacy_plots.append(_legacy_make_plot(true, true, 1, false))
		_legacy_plots.append(_legacy_make_plot(true, true, 0, false))
	_selected_plot_index = 0


func _legacy_make_plot(planted: bool, watered: bool, weeds: int, ready: bool) -> Dictionary:
	return {
		"planted": planted,
		"watered": watered,
		"weeds": maxi(weeds, 0),
		"ready": ready,
		"harvested": false,
	}


func _ensure_legacy_plots() -> void:
	if _legacy_plots.size() != PLOT_COUNT:
		_reset_legacy_plots()


func _perform_legacy_plot_action(plot_index: int, action_id: String) -> Dictionary:
	_ensure_legacy_plots()
	if plot_index < 0 or plot_index >= _legacy_plots.size():
		return _legacy_wrong_action("invalid_plot", -1, action_id, "")
	var plot := _legacy_plots[plot_index]
	var required_action := _legacy_recommended_action_for_plot(plot)
	if action_id != required_action:
		return _legacy_wrong_action("wrong_action", plot_index, action_id, required_action)

	match action_id:
		ACTION_PLANT:
			plot["planted"] = true
			plot["watered"] = false
			plot["weeds"] = 0
			plot["ready"] = false
			_legacy_score_correct(plot_index, _tr("farm_work.legacy.seed_set", "Saat gesetzt"), 10)
			_maintenance_tasks_done += 1
		ACTION_WATER:
			plot["watered"] = true
			_legacy_score_correct(plot_index, _tr("farm_work.legacy.plant_watered", "Pflanze bewässert"), 9)
			_maintenance_tasks_done += 1
		ACTION_WEED:
			plot["weeds"] = maxi(int(plot.get("weeds", 0)) - 1, 0)
			_legacy_score_correct(plot_index, _tr("farm_work.legacy.weeds_removed", "Unkraut entfernt"), 11)
			_maintenance_tasks_done += 1
		ACTION_HARVEST:
			if _basket_crates >= BASKET_CAPACITY_CRATES:
				return _legacy_wrong_action("basket_full", plot_index, action_id, ACTION_DELIVER)
			plot["harvested"] = true
			_basket_crates += 1
			_basket_units += _units_per_crate
			_legacy_score_correct(plot_index, _trf("farm_work.legacy.harvested", [product_display_name], "%s geerntet"), 16)
		_:
			return _legacy_wrong_action("unsupported_action", plot_index, action_id, required_action)

	_legacy_plots[plot_index] = plot
	return {
		"correct": true,
		"reason": "ok",
		"plot_number": plot_index + 1,
		"action": action_id,
		"score": score,
		"basket_crates": _basket_crates,
	}


func _perform_legacy_delivery_action() -> Dictionary:
	if _basket_crates <= 0:
		return _legacy_wrong_action("empty_basket", _selected_plot_index, ACTION_DELIVER, "")
	delivered_crates += _basket_crates
	harvested_amount += _basket_units
	score += 12 * _basket_crates
	completed_tasks += 1
	_basket_crates = 0
	_basket_units = 0
	score_changed.emit(score)
	return {
		"correct": true,
		"reason": "delivered",
		"action": ACTION_DELIVER,
		"score": score,
		"delivered_crates": delivered_crates,
		"harvested_amount": harvested_amount,
	}


func _legacy_score_correct(plot_index: int, message: String, points: int) -> void:
	completed_tasks += 1
	score += points + mini(player_skill_level, 5)
	quality_score = clampf(quality_score + 0.015, 0.0, 1.0)
	_set_hint(_trf("farm_work.hint.plot", [plot_index + 1, message], "Plot %d: %s."))
	score_changed.emit(score)


func _legacy_wrong_action(reason: String, plot_index: int, action_id: String, required_action: String) -> Dictionary:
	mistakes += 1
	score = maxi(score - 8, 0)
	quality_score = clampf(quality_score - 0.10, 0.0, 1.0)
	mistake_made.emit(reason)
	return {
		"correct": false,
		"reason": reason,
		"plot_number": plot_index + 1,
		"action": action_id,
		"required_action": required_action,
		"score": score,
		"mistakes": mistakes,
	}


func _legacy_recommended_action_for_plot(plot: Dictionary) -> String:
	if bool(plot.get("harvested", false)):
		return ""
	if not bool(plot.get("planted", false)):
		return ACTION_PLANT
	if not bool(plot.get("watered", false)):
		return ACTION_WATER
	if int(plot.get("weeds", 0)) > 0:
		return ACTION_WEED
	if bool(plot.get("ready", false)):
		return ACTION_HARVEST
	return ""


func _legacy_plot_state_label(plot: Dictionary) -> String:
	if bool(plot.get("harvested", false)):
		return "harvested"
	if not bool(plot.get("planted", false)):
		return "empty"
	if not bool(plot.get("watered", false)):
		return "dry"
	if int(plot.get("weeds", 0)) > 0:
		return "weeds"
	if bool(plot.get("ready", false)):
		return "ready"
	return "maintained"
