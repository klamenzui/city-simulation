extends Node

class_name CelestialBodies

# References
var sky_material: ShaderMaterial
var time_manager: SkyTimeManager

# Visibility Toggles
@export_group("Visibility Toggles")
@export var sun_visible: bool = true
@export var moon_visible: bool = true
@export var stars_visible: bool = true
@export var planets_visible: bool = true
@export var clouds_visible: bool = true
@export var high_clouds_visible: bool = true

# Sun settings
@export_group("Sun Settings")
@export var sun_size: float = 4.0 # scale factor for sun size
@export var sun_intensity: float = 3.0 # brightness multiplier
@export var sun_bloom: float = 1.2 # Amount of glow around the sun
@export var sun_color: Color = Color(1.0, 0.9, 0.7) # Warm sun color

# Moon settings
@export_group("Moon Settings")
@export var moon_phase_cycle: float = 29.53 # days in lunar cycle
@export var moon_phase_offset: float = 0.0 # 0.0-1.0 to adjust initial phase
@export var moon_size: float = 5.0 # scale factor for moon size
@export var moon_brightness: float = 1.5 # brightness multiplier
@export var moon_tint: Color = Color(0.95, 0.95, 1.0) # Slight blue tint for the moon

# NEW: Moon rise/set timing adjustments 
@export var moon_rise_hour_offset: float = 18.0 # Hour when moon rises (default: sunset)
@export var moon_set_hour_offset: float = 6.0 # Hour when moon sets (default: sunrise)
@export var moon_rise_duration: float = 1.0 # Duration of moon rise transition in hours
@export var moon_set_duration: float = 1.0 # Duration of moon set transition in hours

# Stars settings
@export_group("Stars Settings") 
@export var stars_intensity: float = 5.0
@export var stars_tint: Color = Color(1.0, 1.0, 1.0)
@export var stars_scintillation: float = 0.5 # How much stars twinkle

# Planets settings
@export_group("Planets Settings")
@export var planet_brightness: float = 0.8
@export var planet1_visible: bool = true # Venus
@export var planet2_visible: bool = true # Mars
@export var planet3_visible: bool = true # Jupiter

# Clouds settings
@export_group("Clouds Settings")
@export var clouds_density: float = 0.4
@export var high_clouds_density: float = 0.2

# Resources
var moon_texture: Texture2D
var sun_texture: Texture2D
var planet_textures: Array[Texture2D] = []

# Current state
var current_day: float = 0.0
var moon_phase: float = 0.0 # 0.0-1.0 (0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter)

# Planet positions (simplified model)
var planets = [
	{"name": "Venus", "period": 224.7, "angle_offset": 0.0, "size": 2.0, "color": Color(1.0, 0.95, 0.8)},
	{"name": "Mars", "period": 687.0, "angle_offset": 120.0, "size": 1.5, "color": Color(1.0, 0.6, 0.4)},
	{"name": "Jupiter", "period": 4333.0, "angle_offset": 240.0, "size": 3.0, "color": Color(0.9, 0.85, 0.75)},
]

# Configuration save path
const CONFIG_FILE_PATH = "user://sky_settings.cfg"

func _ready():
	# Find time manager
	time_manager = get_node_or_null("../SkyTimeManager")
	
	# Find sky material
	var world_env = get_node_or_null("../WorldEnvironment")
	if world_env:
		var sky = world_env.environment.sky
		if sky:
			sky_material = sky.sky_material
	
	# Load textures
	moon_texture = load("res://environment/sky/Moon.png") if ResourceLoader.exists("res://environment/sky/Moon.png") else null
	sun_texture = load("res://environment/sky/Sun.png") if ResourceLoader.exists("res://environment/sky/Sun.png") else null
	
	if moon_texture:
		# Set moon texture in shader
		sky_material.set_shader_parameter("moon_sampler", moon_texture)
		
	if sun_texture:
		# Set sun texture in shader
		sky_material.set_shader_parameter("sun_sampler", sun_texture)
	
	# Initialize shader parameters
	update_shader_parameters()
	
	# Initialize planet textures
	for i in range(planets.size()):
		var texture_path = "res://environment/sky/planet_" + str(i+1) + ".png"
		var texture = load(texture_path) if ResourceLoader.exists(texture_path) else null
		planet_textures.append(texture)
	
	# Load settings if they exist
	load_settings()

func _process(delta):
	if time_manager == null or sky_material == null:
		return
	
	# Update current day based on time progression
	current_day += delta * time_manager.time_scale / (24.0 * 60.0 * 60.0)
	
	# Update shader parameters based on toggles
	update_shader_parameters()
	
	# Update celestial positions and phases
	if sun_visible:
		update_sun()
	
	if moon_visible:
		update_moon_phase()
	
	if stars_visible:
		update_stars_visibility()
	
	if planets_visible:
		update_planets()
		
	if clouds_visible:
		update_clouds()

func update_shader_parameters():
	if sky_material == null:
		return
		
	# Update sun parameters
	sky_material.set_shader_parameter("sun_visible", sun_visible)
	sky_material.set_shader_parameter("sun_color", sun_color)
	sky_material.set_shader_parameter("sun_size", sun_size)
	sky_material.set_shader_parameter("sun_intensity", sun_intensity)
	sky_material.set_shader_parameter("sun_bloom", sun_bloom)
	
	# Update moon parameters
	sky_material.set_shader_parameter("moon_visible", moon_visible)
	sky_material.set_shader_parameter("moon_tint", moon_tint)
	sky_material.set_shader_parameter("moon_size", moon_size)
	sky_material.set_shader_parameter("moon_brightness", moon_brightness)
	
	# Update stars parameters
	sky_material.set_shader_parameter("stars_intensity", stars_intensity if stars_visible else 0.0)
	sky_material.set_shader_parameter("stars_tint", stars_tint)
	sky_material.set_shader_parameter("stars_scintillation", stars_scintillation)
	
	# Update planets visibility
	sky_material.set_shader_parameter("planet1_visible", planets_visible and planet1_visible)
	sky_material.set_shader_parameter("planet2_visible", planets_visible and planet2_visible)
	sky_material.set_shader_parameter("planet3_visible", planets_visible and planet3_visible)
	
	# Update clouds parameters
	sky_material.set_shader_parameter("clouds_density", clouds_density if clouds_visible else 0.0)
	sky_material.set_shader_parameter("high_clouds_density", high_clouds_density if high_clouds_visible else 0.0)

func update_sun():
	if not sun_visible:
		sky_material.set_shader_parameter("sun_visible", false)
		return
		
	var sun_time_visible = true
	
	# Солнце видно только днем (от 6:00 до 18:00)
	if time_manager:
		sun_time_visible = time_manager.current_time >= 6.0 and time_manager.current_time <= 18.0
	
	# Обновляем параметры в шейдере
	sky_material.set_shader_parameter("sun_color", sun_color)
	sky_material.set_shader_parameter("sun_size", sun_size)
	sky_material.set_shader_parameter("sun_visible", sun_visible and sun_time_visible)

func update_moon_phase():
	if not moon_visible:
		sky_material.set_shader_parameter("moon_visible", false)
		return
		
	# Calculate moon phase (0-1 range)
	moon_phase = fmod(current_day / moon_phase_cycle + moon_phase_offset, 1.0)
	
	# Calculate moon position based on time of day with improved realism
	# Moon should rise around sunset and set around sunrise
	
	# Get current time in 24-hour format
	var current_time = time_manager.current_time
	
	# Calculate angle based on rise/set times (improved version)
	# Map time to angle: moon_rise_hour_offset → 0°, (moon_rise_hour_offset + 12) % 24 → 180°, moon_set_hour_offset → 360°
	var hours_since_rise
	
	# Calculate hours since moonrise, accounting for day boundary
	if current_time >= moon_rise_hour_offset:
		hours_since_rise = current_time - moon_rise_hour_offset
	else:
		hours_since_rise = current_time + (24.0 - moon_rise_hour_offset)
	
	# Full cycle of visible moon is from rise to set (typically ~12 hours)
	var visible_arc_duration
	if moon_set_hour_offset > moon_rise_hour_offset:
		visible_arc_duration = moon_set_hour_offset - moon_rise_hour_offset
	else:
		visible_arc_duration = (24.0 - moon_rise_hour_offset) + moon_set_hour_offset
	
	# Normalize to 0-1 range
	var progress = hours_since_rise / visible_arc_duration
	
	# Convert to radians (mapping progress to an arc from east to west through zenith)
	var moon_angle_rad = progress * PI
	
	# Calculate moon altitude and azimuth using the angle
	var moon_altitude = sin(moon_angle_rad) # Highest at zenith (progress = 0.5)
	var moon_azimuth = cos(moon_angle_rad)  # East at rise, West at set
	
	# Convert to 3D coordinates (xyz), where y is height above horizon
	var moon_x = -cos(moon_altitude) * sin(moon_azimuth)
	var moon_y = sin(moon_altitude)
	var moon_z = -cos(moon_altitude) * cos(moon_azimuth)
	
	# Is moon currently visible?
	var moon_time_visible = false
	
	# Moon visible if it's between rise and set times
	if moon_set_hour_offset > moon_rise_hour_offset:
		# Simple case: rise and set on the same day
		moon_time_visible = current_time >= moon_rise_hour_offset and current_time <= moon_set_hour_offset
	else:
		# Complex case: rise today, set tomorrow
		moon_time_visible = current_time >= moon_rise_hour_offset or current_time <= moon_set_hour_offset
	
	# Add transition for gradual rise/set
	var transition_factor = 1.0
	
	# Calculate rise transition
	if moon_rise_hour_offset <= current_time and current_time <= (moon_rise_hour_offset + moon_rise_duration):
		# Rising transition
		transition_factor = (current_time - moon_rise_hour_offset) / moon_rise_duration
	# Calculate set transition
	elif (moon_set_hour_offset - moon_set_duration) <= current_time and current_time <= moon_set_hour_offset:
		# Setting transition
		transition_factor = (moon_set_hour_offset - current_time) / moon_set_duration
	
	# Update moon parameters in shader
	sky_material.set_shader_parameter("moon_position", Vector3(moon_x, moon_y, moon_z))
	sky_material.set_shader_parameter("moon_size", moon_size)
	sky_material.set_shader_parameter("moon_phase", moon_phase)
	sky_material.set_shader_parameter("moon_visible", moon_visible and moon_time_visible)
	
	# Apply brightness with transition factor and phase calculation
	var phase_factor = 1.0
	if moon_phase <= 0.1 or moon_phase >= 0.9:
		# New moon
		phase_factor = 0.1
	elif moon_phase > 0.4 and moon_phase < 0.6:
		# Full moon
		phase_factor = 1.0
	else:
		# Partial phases
		phase_factor = 0.6
	
	sky_material.set_shader_parameter("moon_brightness", moon_brightness * transition_factor * phase_factor)

func update_stars_visibility():
	if not stars_visible:
		sky_material.set_shader_parameter("stars_intensity", 0.0)
		sky_material.set_shader_parameter("shooting_stars_intensity", 0.0)
		return
		
	# Calculate stars intensity based on time of day
	var stars_factor = 0.0
	
	if time_manager.current_time > 19.0 or time_manager.current_time < 5.0:
		# Full intensity at night
		stars_factor = 1.0
	elif time_manager.current_time > 18.0 and time_manager.current_time <= 19.0:
		# Fade in at dusk
		stars_factor = inverse_lerp(18.0, 19.0, time_manager.current_time)
	elif time_manager.current_time >= 5.0 and time_manager.current_time < 6.0:
		# Fade out at dawn
		stars_factor = 1.0 - inverse_lerp(5.0, 6.0, time_manager.current_time)
	
	sky_material.set_shader_parameter("stars_intensity", stars_intensity * stars_factor)
	
	# Control shooting stars intensity (most visible in deep night)
	var shooting_stars_factor = 0.0
	if time_manager.current_time > 22.0 or time_manager.current_time < 3.0:
		shooting_stars_factor = 1.0
	elif time_manager.current_time > 21.0 and time_manager.current_time <= 22.0:
		shooting_stars_factor = inverse_lerp(21.0, 22.0, time_manager.current_time)
	elif time_manager.current_time >= 3.0 and time_manager.current_time < 4.0:
		shooting_stars_factor = 1.0 - inverse_lerp(3.0, 4.0, time_manager.current_time)
	
	sky_material.set_shader_parameter("shooting_stars_intensity", 0.5 * shooting_stars_factor)

func update_planets():
	if not planets_visible:
		sky_material.set_shader_parameter("planet1_visible", false)
		sky_material.set_shader_parameter("planet2_visible", false)
		sky_material.set_shader_parameter("planet3_visible", false)
		return
		
	for i in range(planets.size()):
		var planet = planets[i]
		
		# Calculate planet position based on orbital period
		var planet_angle = fmod(current_day / planet["period"] * 360.0 + planet["angle_offset"], 360.0)
		var planet_angle_rad = deg_to_rad(planet_angle)
		
		# Add time of day influence (simplified)
		var time_angle = deg_to_rad(time_manager.current_time * 15.0)
		
		# Calculate 3D position (improved orbital model)
		var planet_x = -cos(time_angle) * sin(planet_angle_rad) * 0.8
		var planet_y = 0.3 * sin(time_angle) + 0.1 # Better vertical position
		var planet_z = -cos(time_angle) * cos(planet_angle_rad) * 0.8
		
		# Planet is visible at night with improved transition
		var planet_time_visible = false
		
		if time_manager.current_time > 19.5 or time_manager.current_time < 4.5:
			# Fully visible at night
			planet_time_visible = true
		elif (time_manager.current_time > 18.5 and time_manager.current_time <= 19.5) or (time_manager.current_time >= 4.5 and time_manager.current_time < 5.5):
			# Transition periods - only show if well above horizon
			planet_time_visible = planet_y > 0.0
		
		# Update planet parameters in shader
		var param_name = "planet" + str(i+1)
		var planet_toggle_visible = false
		if i == 0:
			planet_toggle_visible = planet1_visible
		elif i == 1:
			planet_toggle_visible = planet2_visible
		elif i == 2:
			planet_toggle_visible = planet3_visible
			
		sky_material.set_shader_parameter(param_name + "_position", Vector3(planet_x, planet_y, planet_z))
		sky_material.set_shader_parameter(param_name + "_size", planet["size"])
		sky_material.set_shader_parameter(param_name + "_color", planet["color"])
		sky_material.set_shader_parameter(param_name + "_visible", planet_time_visible and planets_visible and planet_toggle_visible)

func update_clouds():
	# Update cloud density based on visibility toggle
	sky_material.set_shader_parameter("clouds_density", clouds_density if clouds_visible else 0.0)
	sky_material.set_shader_parameter("high_clouds_density", high_clouds_density if high_clouds_visible else 0.0)

# Public functions to manually control celestial objects
func set_sun_visible(visible: bool):
	sun_visible = visible
	if sky_material:
		sky_material.set_shader_parameter("sun_visible", visible)

func set_moon_visible(visible: bool):
	moon_visible = visible
	update_moon_phase()

func set_stars_visible(visible: bool):
	stars_visible = visible
	update_stars_visibility()

func set_planets_visible(visible: bool):
	planets_visible = visible
	update_planets()

func set_clouds_visible(visible: bool):
	clouds_visible = visible
	update_clouds()

func set_high_clouds_visible(visible: bool):
	high_clouds_visible = visible
	update_clouds()

func set_moon_phase(phase: float):
	moon_phase_offset = clamp(phase, 0.0, 1.0)
	update_moon_phase()

func set_current_time(hour: float):
	if time_manager:
		time_manager.set_time(hour)

# New functions for settings management

# Save all celestial and sky settings
func save_settings():
	var config = ConfigFile.new()
	
	# Visibility toggles
	config.set_value("visibility", "sun_visible", sun_visible)
	config.set_value("visibility", "moon_visible", moon_visible)
	config.set_value("visibility", "stars_visible", stars_visible)
	config.set_value("visibility", "planets_visible", planets_visible)
	config.set_value("visibility", "clouds_visible", clouds_visible)
	config.set_value("visibility", "high_clouds_visible", high_clouds_visible)
	config.set_value("visibility", "planet1_visible", planet1_visible)
	config.set_value("visibility", "planet2_visible", planet2_visible)
	config.set_value("visibility", "planet3_visible", planet3_visible)
	
	# Sun settings
	config.set_value("sun", "sun_size", sun_size)
	config.set_value("sun", "sun_intensity", sun_intensity)
	config.set_value("sun", "sun_bloom", sun_bloom)
	config.set_value("sun", "sun_color", sun_color)
	
	# Moon settings
	config.set_value("moon", "moon_phase_cycle", moon_phase_cycle)
	config.set_value("moon", "moon_phase_offset", moon_phase_offset)
	config.set_value("moon", "moon_size", moon_size)
	config.set_value("moon", "moon_brightness", moon_brightness)
	config.set_value("moon", "moon_tint", moon_tint)
	config.set_value("moon", "moon_rise_hour_offset", moon_rise_hour_offset)
	config.set_value("moon", "moon_set_hour_offset", moon_set_hour_offset)
	config.set_value("moon", "moon_rise_duration", moon_rise_duration)
	config.set_value("moon", "moon_set_duration", moon_set_duration)
	
	# Stars settings
	config.set_value("stars", "stars_intensity", stars_intensity)
	config.set_value("stars", "stars_tint", stars_tint)
	config.set_value("stars", "stars_scintillation", stars_scintillation)
	
	# Clouds settings
	config.set_value("clouds", "clouds_density", clouds_density)
	config.set_value("clouds", "high_clouds_density", high_clouds_density)
	
	# Time settings (if time manager exists)
	if time_manager:
		config.set_value("time", "day_length", time_manager.day_length)
		config.set_value("time", "time_scale", time_manager.time_scale)
		config.set_value("time", "latitude", time_manager.latitude)
		config.set_value("time", "longitude", time_manager.longitude)
	
	# Save to file
	config.save(CONFIG_FILE_PATH)
	print("Sky settings saved to: " + CONFIG_FILE_PATH)
	
	return true

# Load all celestial and sky settings
func load_settings():
	var config = ConfigFile.new()
	var err = config.load(CONFIG_FILE_PATH)
	
	if err != OK:
		print("No saved sky settings found. Using defaults.")
		return false
	
	# Visibility toggles
	sun_visible = config.get_value("visibility", "sun_visible", sun_visible)
	moon_visible = config.get_value("visibility", "moon_visible", moon_visible)
	stars_visible = config.get_value("visibility", "stars_visible", stars_visible)
	planets_visible = config.get_value("visibility", "planets_visible", planets_visible)
	clouds_visible = config.get_value("visibility", "clouds_visible", clouds_visible)
	high_clouds_visible = config.get_value("visibility", "high_clouds_visible", high_clouds_visible)
	planet1_visible = config.get_value("visibility", "planet1_visible", planet1_visible)
	planet2_visible = config.get_value("visibility", "planet2_visible", planet2_visible)
	planet3_visible = config.get_value("visibility", "planet3_visible", planet3_visible)
	
	# Sun settings
	sun_size = config.get_value("sun", "sun_size", sun_size)
	sun_intensity = config.get_value("sun", "sun_intensity", sun_intensity)
	sun_bloom = config.get_value("sun", "sun_bloom", sun_bloom)
	sun_color = config.get_value("sun", "sun_color", sun_color)
	
	# Moon settings
	moon_phase_cycle = config.get_value("moon", "moon_phase_cycle", moon_phase_cycle)
	moon_phase_offset = config.get_value("moon", "moon_phase_offset", moon_phase_offset)
	moon_size = config.get_value("moon", "moon_size", moon_size)
	moon_brightness = config.get_value("moon", "moon_brightness", moon_brightness)
	moon_tint = config.get_value("moon", "moon_tint", moon_tint)
	moon_rise_hour_offset = config.get_value("moon", "moon_rise_hour_offset", moon_rise_hour_offset)
	moon_set_hour_offset = config.get_value("moon", "moon_set_hour_offset", moon_set_hour_offset)
	moon_rise_duration = config.get_value("moon", "moon_rise_duration", moon_rise_duration)
	moon_set_duration = config.get_value("moon", "moon_set_duration", moon_set_duration)
	
	# Stars settings
	stars_intensity = config.get_value("stars", "stars_intensity", stars_intensity)
	stars_tint = config.get_value("stars", "stars_tint", stars_tint)
	stars_scintillation = config.get_value("stars", "stars_scintillation", stars_scintillation)
	
	# Clouds settings
	clouds_density = config.get_value("clouds", "clouds_density", clouds_density)
	high_clouds_density = config.get_value("clouds", "high_clouds_density", high_clouds_density)
	
	# Time settings (if time manager exists)
	if time_manager:
		time_manager.day_length = config.get_value("time", "day_length", time_manager.day_length)
		time_manager.time_scale = config.get_value("time", "time_scale", time_manager.time_scale)
		time_manager.latitude = config.get_value("time", "latitude", time_manager.latitude)
		time_manager.longitude = config.get_value("time", "longitude", time_manager.longitude)
	
	# Update all parameters
	update_shader_parameters()
	
	print("Sky settings loaded from: " + CONFIG_FILE_PATH)
	return true
