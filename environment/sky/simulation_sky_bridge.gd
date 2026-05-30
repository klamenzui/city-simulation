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
	if _is_headless_runtime():
		_disable_headless_visual_stack()
		return

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
	_apply_cozy_environment_style()
	call_deferred("_sync_from_world_time", true)

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")

func _disable_headless_visual_stack() -> void:
	enhanced_sky = get_node_or_null("../EnhancedSky")
	if enhanced_sky != null:
		enhanced_sky.queue_free()
	queue_free()

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

	_apply_cozy_environment_style()

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

func _apply_cozy_environment_style() -> void:
	if world_environment == null or world_environment.environment == null:
		return

	var env := world_environment.environment
	var hour := _get_world_time_hours()
	var night_t := _night_factor(hour)
	var golden_t := _golden_hour_factor(hour)

	# Filmic tonemap + subtle color grading: greens pop, sky stays clean.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 1.0
	env.adjustment_enabled = true
	env.adjustment_brightness = lerpf(1.02, 0.96, night_t)
	env.adjustment_contrast = lerpf(1.06, 1.02, night_t)
	env.adjustment_saturation = lerpf(1.12, 0.85, night_t)

	# Soft bloom on highlights (water sparkle, bright clouds, sun-lit foliage edges).
	env.glow_enabled = true
	env.glow_intensity = lerpf(0.55 + golden_t * 0.15, 0.35, night_t)
	env.glow_strength = 0.9
	env.glow_bloom = lerpf(0.08 + golden_t * 0.06, 0.04, night_t)
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Warm ambient fill during the day, cool desaturated fill at night.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.94, 0.93, 0.88).lerp(Color(0.18, 0.22, 0.32), night_t)
	env.ambient_light_energy = lerpf(1.05 + golden_t * 0.10, 0.30, night_t)
	env.ambient_light_sky_contribution = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Atmospheric perspective: distant geometry fades into the sky color, so mountains/forest
	# read as soft depth instead of a hard silhouette. This is the key "idyllic" cue.
	env.fog_enabled = false
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = lerpf(0.0028 + golden_t * 0.0006, 0.0042, night_t)
	env.fog_light_color = Color(0.74, 0.84, 0.94).lerp(Color(1.0, 0.78, 0.58), golden_t).lerp(Color(0.18, 0.24, 0.36), night_t)
	env.fog_light_energy = lerpf(0.85 + golden_t * 0.15, 0.30, night_t)
	env.fog_sun_scatter = lerpf(0.05, 0.18, golden_t)
	env.fog_sky_affect = 0.01
	env.fog_aerial_perspective = 0.01
	env.fog_height = 5.0
	env.fog_height_density = 0.06

	# Ground-contact shadows / crevice darkening — adds depth in foliage and against buildings.
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.4
	env.ssao_power = 1.5
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.1
	env.ssao_ao_channel_affect = 0.5

	if directional_light != null:
		# Warmer day sun, deeper sunset, cool moonlight at night.
		var day_color := Color(1.0, 0.96, 0.88)
		var sunset_color := Color(1.0, 0.70, 0.48)
		var night_color := Color(0.52, 0.60, 0.78)
		directional_light.light_color = day_color.lerp(sunset_color, golden_t).lerp(night_color, night_t)
		# Wider angular size -> softer penumbras (cozy soft shadows, not razor-sharp edges).
		directional_light.light_angular_distance = 2.4
		directional_light.shadow_blur = 1.4
		# Subtle specular so water and wet surfaces catch the sun without blowing out matte materials.
		directional_light.light_specular = lerpf(0.45, 0.15, night_t)

func _golden_hour_factor(hour: float) -> float:
	var sunrise := _window_factor(hour, 5.5, 8.0)
	var sunset := _window_factor(hour, 16.5, 19.5)
	return maxf(sunrise, sunset)

func _night_factor(hour: float) -> float:
	if hour >= 20.0 or hour < 5.0:
		return 1.0
	if hour < 7.0:
		return inverse_lerp(7.0, 5.0, hour)
	if hour > 18.5:
		return inverse_lerp(18.5, 20.0, hour)
	return 0.0

func _window_factor(hour: float, start_hour: float, end_hour: float) -> float:
	if hour <= start_hour or hour >= end_hour:
		return 0.0
	var mid := (start_hour + end_hour) * 0.5
	if hour <= mid:
		return inverse_lerp(start_hour, mid, hour)
	return inverse_lerp(end_hour, mid, hour)
