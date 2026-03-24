extends Node

const SECONDS_PER_SIM_DAY := 24.0 * 60.0 * 60.0

var world: World = null
var enhanced_sky: Node = null
var world_environment: WorldEnvironment = null
var directional_light: DirectionalLight3D = null
var sky_time_manager: SkyTimeManager = null
var celestial_bodies: CelestialBodies = null
var time_display: Label = null
var time_ui_controller: Node = null

func _ready() -> void:
	world = get_node_or_null("../World") as World
	enhanced_sky = get_node_or_null("../EnhancedSky")
	world_environment = get_node_or_null("../EnhancedSky/WorldEnvironment") as WorldEnvironment
	directional_light = get_node_or_null("../EnhancedSky/DirectionalLight3D") as DirectionalLight3D
	sky_time_manager = get_node_or_null("../EnhancedSky/SkyTimeManager") as SkyTimeManager
	celestial_bodies = get_node_or_null("../EnhancedSky/CelestialBodies") as CelestialBodies
	time_display = get_node_or_null("../EnhancedSky/TimeDisplay") as Label
	time_ui_controller = get_node_or_null("../EnhancedSky/TimeUIController")

	_disable_legacy_sky_ui()
	_connect_world_signals()
	_sync_sky_rate()
	call_deferred("_sync_from_world_time", true)

func _disable_legacy_sky_ui() -> void:
	if time_display != null:
		time_display.visible = false
	if time_ui_controller != null:
		time_ui_controller.queue_free()

func _connect_world_signals() -> void:
	if world == null:
		return
	if not world.paused_changed.is_connected(_on_world_paused_changed):
		world.paused_changed.connect(_on_world_paused_changed)
	if not world.speed_changed.is_connected(_on_world_speed_changed):
		world.speed_changed.connect(_on_world_speed_changed)
	if world.time != null and not world.time.time_advanced.is_connected(_on_world_time_advanced):
		world.time.time_advanced.connect(_on_world_time_advanced)

func _on_world_paused_changed(_paused: bool) -> void:
	_sync_sky_rate()
	_sync_from_world_time(true)

func _on_world_speed_changed(_multiplier: float) -> void:
	_sync_sky_rate()

func _on_world_time_advanced(_day: int, _hour: int, _minute: int) -> void:
	_sync_from_world_time(true)

func _sync_sky_rate() -> void:
	if sky_time_manager == null:
		return
	sky_time_manager.day_length = SECONDS_PER_SIM_DAY
	sky_time_manager.time_scale = _get_sim_seconds_per_real_second()

func _sync_from_world_time(refresh_now: bool = false) -> void:
	if world == null or world.time == null or sky_time_manager == null:
		return

	var world_time_hours := _get_world_time_hours()
	sky_time_manager.start_time = world_time_hours
	sky_time_manager.current_time = world_time_hours
	sky_time_manager.day_of_year = ((world.time.day - 1) % 365) + 1

	if celestial_bodies != null:
		celestial_bodies.current_day = float(world.time.day - 1) + world_time_hours / 24.0
	if directional_light != null:
		directional_light.shadow_enabled = true
	if time_display != null:
		time_display.text = world.time.get_time_string()

	if refresh_now:
		_refresh_sky_visuals()

func _refresh_sky_visuals() -> void:
	if sky_time_manager != null:
		sky_time_manager.update_sun_position()
		sky_time_manager.update_sky_colors()

	if celestial_bodies != null:
		celestial_bodies.update_shader_parameters()
		if celestial_bodies.sun_visible:
			celestial_bodies.update_sun()
		if celestial_bodies.moon_visible:
			celestial_bodies.update_moon_phase()
		if celestial_bodies.stars_visible:
			celestial_bodies.update_stars_visibility()
		if celestial_bodies.planets_visible:
			celestial_bodies.update_planets()
		if celestial_bodies.clouds_visible:
			celestial_bodies.update_clouds()

func _get_world_time_hours() -> float:
	if world == null or world.time == null:
		return 8.0
	return float(world.time.get_hour()) + float(world.time.get_minute()) / 60.0

func _get_sim_seconds_per_real_second() -> float:
	if world == null or world.is_paused:
		return 0.0

	var real_seconds_per_tick := world.tick_interval_sec / maxf(world.speed_multiplier, 0.1)
	if real_seconds_per_tick <= 0.0001:
		return 0.0

	return float(world.minutes_per_tick) * 60.0 / real_seconds_per_tick
