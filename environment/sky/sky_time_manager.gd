extends Node

class_name SkyTimeManager

# Time settings
@export var day_length: float = 1200.0 # seconds in a full day
@export var start_time: float = 8.0 # 24-hour format (8:00 AM)
@export var time_scale: float = 1.0 # 1.0 = realtime, 60.0 = 1 minute = 1 hour

# Geographic position (affects sun angle)
@export var latitude: float = 45.0 # degrees (-90 to 90)
@export var longitude: float = 0.0 # degrees (-180 to 180)

# Current time
var current_time: float = 0.0 # 0-24 hours
var day_of_year: int = 80 # 1-365 (80 = spring equinox)

# References
var directional_light: DirectionalLight3D
var sky_material: ShaderMaterial
var animation_player: AnimationPlayer

# Astronomical constants
const OBLIQUITY = 23.439 # Earth's axial tilt in degrees

# Color presets for different times of day
var dawn_colors = {
	"top_color": Color(0.294, 0.255, 0.451),
	"bottom_color": Color(0.945, 0.592, 0.408),
	"sun_scatter": Color(0.988, 0.655, 0.42),
	"clouds_light_color": Color(0.992, 0.816, 0.682)
}

var sunrise_colors = {
	"top_color": Color(0.447, 0.525, 0.812),
	"bottom_color": Color(0.984, 0.725, 0.474),
	"sun_scatter": Color(1.0, 0.737, 0.443),
	"clouds_light_color": Color(0.996, 0.882, 0.741)
}

var day_colors = {
	"top_color": Color(0.569, 0.686, 0.859),
	"bottom_color": Color(0.937, 0.886, 0.769),
	"sun_scatter": Color(0.467, 0.412, 0.361),
	"clouds_light_color": Color(1.0, 0.965, 0.925)
}

var sunset_colors = {
	"top_color": Color(0.424, 0.451, 0.761),
	"bottom_color": Color(0.988, 0.569, 0.329),
	"sun_scatter": Color(0.992, 0.553, 0.286),
	"clouds_light_color": Color(1.0, 0.737, 0.541)
}

var dusk_colors = {
	"top_color": Color(0.208, 0.227, 0.482),
	"bottom_color": Color(0.663, 0.341, 0.388),
	"sun_scatter": Color(0.816, 0.408, 0.357),
	"clouds_light_color": Color(0.847, 0.569, 0.486)
}

var night_colors = {
	"top_color": Color(0.043, 0.082, 0.188),
	"bottom_color": Color(0.063, 0.098, 0.184),
	"sun_scatter": Color(0.149, 0.118, 0.282),
	"clouds_light_color": Color(0.278, 0.341, 0.584)
}

func _ready():
	# Initialize time to start_time
	current_time = start_time
	
	# Find references to required nodes
	directional_light = get_node_or_null("../DirectionalLight3D")
	animation_player = get_node_or_null("../AnimationPlayer")
	
	var world_env = get_node_or_null("../WorldEnvironment")
	if world_env:
		var sky = world_env.environment.sky
		if sky:
			sky_material = sky.sky_material

func _process(delta):
	# Update time
	var time_delta = delta * time_scale
	current_time = fmod(current_time + time_delta / day_length * 24.0, 24.0)
	
	# Update sun position
	update_sun_position()
	
	# Update sky colors
	update_sky_colors()

func update_sun_position():
	if directional_light == null:
		return
	
	# Простой расчет положения солнца на основе времени суток
	# Преобразуем время (0-24 часа) в угол (0-360 градусов)
	var sun_angle_deg = (current_time / 24.0) * 360.0
	
	# Корректируем угол так, чтобы в полдень солнце было вверху
	sun_angle_deg = sun_angle_deg - 90.0
	
	# Преобразуем в радианы
	var sun_angle_rad = deg_to_rad(sun_angle_deg)
	
	# Рассчитываем положение солнца
	var sun_x = cos(sun_angle_rad)
	var sun_y = sin(sun_angle_rad)
	var sun_z = 0.0
	
	# Создаем направление на солнце
	var sun_direction = Vector3(sun_x, sun_y, sun_z).normalized()
	
	# Свет должен направляться от солнца к сцене
	var light_direction = -sun_direction
	
	# Устанавливаем направление света
	directional_light.transform.basis = Basis().looking_at(light_direction, Vector3.UP)
	
	# Передаем положение солнца в шейдер
	if sky_material:
		# Важно! Используем sun_direction (не light_direction) для шейдера
		sky_material.set_shader_parameter("sun_direction", sun_direction)
		
		# Солнце видно только когда оно над горизонтом
		var sun_visible = sun_y > 0.0
		sky_material.set_shader_parameter("sun_visible", sun_visible)
	
	# Настройка интенсивности света и теней
	var sun_height = max(0.0, sun_y)  # Берем только положительные значения
	directional_light.light_energy = sun_height * 1.2
	directional_light.shadow_enabled = sun_height > 0.05
	
	# Настройка визуальных параметров солнца
	if sky_material:
		var sun_intensity = 2.0 * max(0.2, sun_height)
		sky_material.set_shader_parameter("sun_intensity", sun_intensity)
		
		# Увеличиваем свечение на рассвете/закате
		var is_sunrise_sunset = (current_time > 5.0 and current_time < 7.0) or (current_time > 17.0 and current_time < 19.0)
		var bloom = 1.5 if is_sunrise_sunset else 0.8
		sky_material.set_shader_parameter("sun_bloom", bloom)
	
	#print("Time: ", current_time, ", Sun position: ", sun_direction, ", Light direction: ", light_direction)

func update_sky_colors():
	if sky_material == null:
		return
	
	# Color transitions based on time of day
	var colors = {}
	
	if current_time < 5.0: # Night
		colors = night_colors
	elif current_time < 6.0: # Dawn
		var t = inverse_lerp(5.0, 6.0, current_time)
		colors = lerp_colors(night_colors, dawn_colors, t)
	elif current_time < 7.0: # Sunrise
		var t = inverse_lerp(6.0, 7.0, current_time)
		colors = lerp_colors(dawn_colors, sunrise_colors, t)
	elif current_time < 8.0: # Morning transition
		var t = inverse_lerp(7.0, 8.0, current_time)
		colors = lerp_colors(sunrise_colors, day_colors, t)
	elif current_time < 17.0: # Day
		colors = day_colors
	elif current_time < 18.0: # Evening transition
		var t = inverse_lerp(17.0, 18.0, current_time)
		colors = lerp_colors(day_colors, sunset_colors, t)
	elif current_time < 19.0: # Sunset
		var t = inverse_lerp(18.0, 19.0, current_time)
		colors = lerp_colors(sunset_colors, dusk_colors, t)
	elif current_time < 20.0: # Dusk
		var t = inverse_lerp(19.0, 20.0, current_time)
		colors = lerp_colors(dusk_colors, night_colors, t)
	else: # Night
		colors = night_colors
	
	# Apply colors to shader
	sky_material.set_shader_parameter("top_color", colors["top_color"])
	sky_material.set_shader_parameter("bottom_color", colors["bottom_color"])
	sky_material.set_shader_parameter("sun_scatter", colors["sun_scatter"])
	sky_material.set_shader_parameter("clouds_light_color", colors["clouds_light_color"])

# Helper function to interpolate between color presets
func lerp_colors(colors1, colors2, t):
	var result = {}
	for key in colors1:
		result[key] = colors1[key].lerp(colors2[key], t)
	return result

# Public functions to control time
func set_time(hour):
	current_time = clamp(hour, 0.0, 24.0)

func set_day_of_year(day):
	day_of_year = clamp(day, 1, 365)

func set_time_scale(scale):
	time_scale = scale

func get_time_of_day_string():
	var hours = floor(current_time)
	var minutes = floor((current_time - hours) * 60.0)
	return "%02d:%02d" % [hours, minutes]
