extends Node

# Ссылки на узлы
var time_manager: SkyTimeManager
var celestial_bodies: CelestialBodies
var world_environment: WorldEnvironment
var sky_material: ShaderMaterial

# Ссылки на существующие элементы
var slow_button: Button
var normal_button: Button
var fast_button: Button
var time_display: Label

# Константы скорости времени
const TIME_SCALE_SLOW = 0.1
const TIME_SCALE_NORMAL = 1.0
const TIME_SCALE_FAST = 20.0

# Интерфейс для управления элементами неба
var sky_settings_window: Window
var shader_settings_window: Window

# Элементы управления временем (внутри окна настроек)
var time_input_hours: SpinBox
var time_input_minutes: SpinBox

# Чекбоксы для видимости
var sun_checkbox: CheckBox
var moon_checkbox: CheckBox
var stars_checkbox: CheckBox
var clouds_checkbox: CheckBox
var high_clouds_checkbox: CheckBox
var planet1_checkbox: CheckBox
var planet2_checkbox: CheckBox
var planet3_checkbox: CheckBox

# NEW: Moon settings controls
var moon_rise_hour_spinbox: SpinBox
var moon_set_hour_spinbox: SpinBox
var moon_rise_duration_spinbox: SpinBox
var moon_set_duration_spinbox: SpinBox

# NEW: Save settings button
var save_settings_button: Button

# Текущая вкладка в окне настроек
var current_tab: int = 0
var tab_buttons: Array = []
var tab_containers: Array = []

# Расширенные диапазоны параметров
const EXTENDED_RANGES = {
	"sun_size": {"min": 1.0, "max": 20.0, "step": 0.1},
	"sun_intensity": {"min": 1.0, "max": 10.0, "step": 0.1},
	"sun_bloom": {"min": 0.0, "max": 5.0, "step": 0.1},
	"moon_size": {"min": 1.0, "max": 20.0, "step": 0.1},
	"moon_brightness": {"min": 0.1, "max": 5.0, "step": 0.1},
	"moon_phase": {"min": 0.0, "max": 1.0, "step": 0.01},
	"clouds_density": {"min": 0.0, "max": 1.0, "step": 0.01},
	"clouds_scale": {"min": 0.1, "max": 3.0, "step": 0.01},
	"high_clouds_density": {"min": 0.0, "max": 1.0, "step": 0.01},
	"stars_intensity": {"min": 0.0, "max": 10.0, "step": 0.1}
}

func _ready():
	# Получаем ссылки на узлы
	time_manager = get_node_or_null("../SkyTimeManager")
	celestial_bodies = get_node_or_null("../CelestialBodies")
	world_environment = get_node_or_null("../WorldEnvironment")
	
	if world_environment and world_environment.environment and world_environment.environment.sky:
		sky_material = world_environment.environment.sky.sky_material
	
	# Получаем ссылки на существующие кнопки
	slow_button = get_node_or_null("../TimeControls/SlowButton")
	normal_button = get_node_or_null("../TimeControls/NormalButton")
	fast_button = get_node_or_null("../TimeControls/FastButton")
	time_display = get_node_or_null("../TimeDisplay")
	
	# Подключаем сигналы существующих кнопок
	if slow_button:
		slow_button.pressed.connect(_on_slow_button_pressed)
	if normal_button:
		normal_button.pressed.connect(_on_normal_button_pressed)
	if fast_button:
		fast_button.pressed.connect(_on_fast_button_pressed)
	
	# Создаем кнопку для открытия настроек неба
	var settings_button = Button.new()
	settings_button.text = "⚙"
	settings_button.position = Vector2(10, 10)
	settings_button.size = Vector2(40, 40)
	settings_button.pressed.connect(_on_settings_button_pressed)
	add_child(settings_button)
	
	# Создаем окно настроек неба
	create_sky_settings_window()

func _process(_delta):
	# Обновляем отображение времени
	if time_manager and time_display:
		var hours = int(time_manager.current_time)
		var minutes = int((time_manager.current_time - hours) * 60)
		time_display.text = "%02d:%02d" % [hours, minutes]

# Создание окна настроек неба
func create_sky_settings_window():
	# Создаем окно
	sky_settings_window = Window.new()
	sky_settings_window.title = "Настройки неба"
	sky_settings_window.size = Vector2(400, 600)
	sky_settings_window.position = Vector2(50, 50)
	sky_settings_window.visible = false
	add_child(sky_settings_window)
	
	# Создаем основной контейнер
	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.position = Vector2(10, 10)
	main_vbox.custom_minimum_size = Vector2(380, 580)
	sky_settings_window.add_child(main_vbox)
	
	# Создаем кнопки вкладок
	var tabs_hbox = HBoxContainer.new()
	tabs_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tabs_hbox)
	
	var time_tab_button = Button.new()
	time_tab_button.text = "Время"
	time_tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_tab_button.pressed.connect(func(): switch_tab(0))
	tabs_hbox.add_child(time_tab_button)
	tab_buttons.append(time_tab_button)
	
	var visibility_tab_button = Button.new()
	visibility_tab_button.text = "Видимость"
	visibility_tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visibility_tab_button.pressed.connect(func(): switch_tab(1))
	tabs_hbox.add_child(visibility_tab_button)
	tab_buttons.append(visibility_tab_button)
	
	var shader_tab_button = Button.new()
	shader_tab_button.text = "Параметры шейдера"
	shader_tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shader_tab_button.pressed.connect(func(): switch_tab(2))
	tabs_hbox.add_child(shader_tab_button)
	tab_buttons.append(shader_tab_button)
	
	# NEW: Add Moon tab button
	var moon_tab_button = Button.new()
	moon_tab_button.text = "Луна"
	moon_tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moon_tab_button.pressed.connect(func(): switch_tab(3))
	tabs_hbox.add_child(moon_tab_button)
	tab_buttons.append(moon_tab_button)
	
	# Контейнер для вкладки времени
	var time_container = VBoxContainer.new()
	time_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(time_container)
	tab_containers.append(time_container)
	
	# Контейнер для вкладки видимости
	var visibility_container = VBoxContainer.new()
	visibility_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visibility_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	visibility_container.visible = false
	main_vbox.add_child(visibility_container)
	tab_containers.append(visibility_container)
	
	# Контейнер для вкладки шейдера
	var shader_container = VBoxContainer.new()
	shader_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shader_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shader_container.visible = false
	main_vbox.add_child(shader_container)
	tab_containers.append(shader_container)
	
	# NEW: Container for Moon tab
	var moon_container = VBoxContainer.new()
	moon_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moon_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	moon_container.visible = false
	main_vbox.add_child(moon_container)
	tab_containers.append(moon_container)
	
	# ======== ВКЛАДКА ВРЕМЕНИ ========
	
	# Раздел установки времени
	var time_label = Label.new()
	time_label.text = "Установить точное время:"
	time_container.add_child(time_label)
	
	var time_hbox = HBoxContainer.new()
	time_container.add_child(time_hbox)
	
	# Поле для ввода часов
	time_input_hours = SpinBox.new()
	time_input_hours.min_value = 0
	time_input_hours.max_value = 23
	time_input_hours.step = 1
	time_input_hours.value = 12
	time_input_hours.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_hbox.add_child(time_input_hours)
	
	# Метка ":"
	var colon_label = Label.new()
	colon_label.text = ":"
	time_hbox.add_child(colon_label)
	
	# Поле для ввода минут
	time_input_minutes = SpinBox.new()
	time_input_minutes.min_value = 0
	time_input_minutes.max_value = 59
	time_input_minutes.step = 1
	time_input_minutes.value = 0
	time_input_minutes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_hbox.add_child(time_input_minutes)
	
	# Кнопка установки времени
	var time_set_button = Button.new()
	time_set_button.text = "Установить"
	time_set_button.pressed.connect(_on_time_set_button_pressed)
	time_hbox.add_child(time_set_button)
	
	# Разделитель
	time_container.add_child(HSeparator.new())
	
	# Заголовок для скорости времени
	var speed_label = Label.new()
	speed_label.text = "Скорость времени:"
	time_container.add_child(speed_label)
	
	# Кнопки скорости времени
	var speed_hbox = HBoxContainer.new()
	time_container.add_child(speed_hbox)
	
	var slow_btn = Button.new()
	slow_btn.text = "Медленно"
	slow_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slow_btn.pressed.connect(_on_slow_button_pressed)
	speed_hbox.add_child(slow_btn)
	
	var normal_btn = Button.new()
	normal_btn.text = "Нормально"
	normal_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	normal_btn.pressed.connect(_on_normal_button_pressed)
	speed_hbox.add_child(normal_btn)
	
	var fast_btn = Button.new()
	fast_btn.text = "Быстро"
	fast_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fast_btn.pressed.connect(_on_fast_button_pressed)
	speed_hbox.add_child(fast_btn)
	
	# Разделитель
	time_container.add_child(HSeparator.new())
	
	# Кнопка для управления предустановленными временами
	var presets_label = Label.new()
	presets_label.text = "Предустановки времени:"
	time_container.add_child(presets_label)
	
	var presets_grid = GridContainer.new()
	presets_grid.columns = 2
	time_container.add_child(presets_grid)
	
	var dawn_button = Button.new()
	dawn_button.text = "Рассвет (6:00)"
	dawn_button.pressed.connect(func(): _set_preset_time(6.0))
	presets_grid.add_child(dawn_button)
	
	var noon_button = Button.new()
	noon_button.text = "Полдень (12:00)"
	noon_button.pressed.connect(func(): _set_preset_time(12.0))
	presets_grid.add_child(noon_button)
	
	var sunset_button = Button.new()
	sunset_button.text = "Закат (18:00)"
	sunset_button.pressed.connect(func(): _set_preset_time(18.0))
	presets_grid.add_child(sunset_button)
	
	var midnight_button = Button.new()
	midnight_button.text = "Полночь (0:00)"
	midnight_button.pressed.connect(func(): _set_preset_time(0.0))
	presets_grid.add_child(midnight_button)
	
	# ======== ВКЛАДКА ВИДИМОСТИ ========
	
	# Заголовок для видимости объектов
	var celestial_label = Label.new()
	celestial_label.text = "Небесные тела:"
	visibility_container.add_child(celestial_label)
	
	# Чекбоксы для видимости объектов
	sun_checkbox = CheckBox.new()
	sun_checkbox.text = "Солнце"
	sun_checkbox.button_pressed = true
	sun_checkbox.toggled.connect(_on_sun_toggled)
	visibility_container.add_child(sun_checkbox)
	
	moon_checkbox = CheckBox.new()
	moon_checkbox.text = "Луна"
	moon_checkbox.button_pressed = true
	moon_checkbox.toggled.connect(_on_moon_toggled)
	visibility_container.add_child(moon_checkbox)
	
	stars_checkbox = CheckBox.new()
	stars_checkbox.text = "Звезды"
	stars_checkbox.button_pressed = true
	stars_checkbox.toggled.connect(_on_stars_toggled)
	visibility_container.add_child(stars_checkbox)
	
	# Разделитель
	visibility_container.add_child(HSeparator.new())
	
	# Планеты
	var planets_label = Label.new()
	planets_label.text = "Планеты:"
	visibility_container.add_child(planets_label)
	
	planet1_checkbox = CheckBox.new()
	planet1_checkbox.text = "Венера"
	planet1_checkbox.button_pressed = true
	planet1_checkbox.toggled.connect(_on_planet1_toggled)
	visibility_container.add_child(planet1_checkbox)
	
	planet2_checkbox = CheckBox.new()
	planet2_checkbox.text = "Марс"
	planet2_checkbox.button_pressed = true
	planet2_checkbox.toggled.connect(_on_planet2_toggled)
	visibility_container.add_child(planet2_checkbox)
	
	planet3_checkbox = CheckBox.new()
	planet3_checkbox.text = "Юпитер"
	planet3_checkbox.button_pressed = true
	planet3_checkbox.toggled.connect(_on_planet3_toggled)
	visibility_container.add_child(planet3_checkbox)
	
	# Разделитель
	visibility_container.add_child(HSeparator.new())
	
	# Облака
	var clouds_label = Label.new()
	clouds_label.text = "Облака:"
	visibility_container.add_child(clouds_label)
	
	clouds_checkbox = CheckBox.new()
	clouds_checkbox.text = "Обычные облака"
	clouds_checkbox.button_pressed = true
	clouds_checkbox.toggled.connect(_on_clouds_toggled)
	visibility_container.add_child(clouds_checkbox)
	
	high_clouds_checkbox = CheckBox.new()
	high_clouds_checkbox.text = "Высокие облака"
	high_clouds_checkbox.button_pressed = true
	high_clouds_checkbox.toggled.connect(_on_high_clouds_toggled)
	visibility_container.add_child(high_clouds_checkbox)
	
	# ======== ВКЛАДКА ШЕЙДЕРА ========
	
	# Заголовок для параметров солнца
	var sun_params_label = Label.new()
	sun_params_label.text = "Параметры солнца:"
	shader_container.add_child(sun_params_label)
	
	# Размер солнца
	add_slider_parameter(shader_container, "Размер солнца:", 
		EXTENDED_RANGES["sun_size"]["min"],
		EXTENDED_RANGES["sun_size"]["max"],
		EXTENDED_RANGES["sun_size"]["step"],
		"sun_size")
	
	# Яркость солнца
	add_slider_parameter(shader_container, "Яркость солнца:", 
		EXTENDED_RANGES["sun_intensity"]["min"],
		EXTENDED_RANGES["sun_intensity"]["max"],
		EXTENDED_RANGES["sun_intensity"]["step"],
		"sun_intensity")
	
	# Свечение солнца
	add_slider_parameter(shader_container, "Свечение солнца:", 
		EXTENDED_RANGES["sun_bloom"]["min"],
		EXTENDED_RANGES["sun_bloom"]["max"],
		EXTENDED_RANGES["sun_bloom"]["step"],
		"sun_bloom")
	
	# Разделитель
	shader_container.add_child(HSeparator.new())
	
	# Заголовок для параметров луны
	var moon_params_label = Label.new()
	moon_params_label.text = "Параметры луны:"
	shader_container.add_child(moon_params_label)
	
	# Размер луны
	add_slider_parameter(shader_container, "Размер луны:", 
		EXTENDED_RANGES["moon_size"]["min"],
		EXTENDED_RANGES["moon_size"]["max"],
		EXTENDED_RANGES["moon_size"]["step"],
		"moon_size")
	
	# Яркость луны
	add_slider_parameter(shader_container, "Яркость луны:", 
		EXTENDED_RANGES["moon_brightness"]["min"],
		EXTENDED_RANGES["moon_brightness"]["max"],
		EXTENDED_RANGES["moon_brightness"]["step"],
		"moon_brightness")
	
	# Фаза луны
	add_slider_parameter(shader_container, "Фаза луны:", 
		EXTENDED_RANGES["moon_phase"]["min"],
		EXTENDED_RANGES["moon_phase"]["max"],
		EXTENDED_RANGES["moon_phase"]["step"],
		"moon_phase")
	
	# Разделитель
	shader_container.add_child(HSeparator.new())
	
	# Заголовок для параметров звезд
	var stars_params_label = Label.new()
	stars_params_label.text = "Параметры звезд:"
	shader_container.add_child(stars_params_label)
	
	# Интенсивность звезд
	add_slider_parameter(shader_container, "Интенсивность звезд:", 
		EXTENDED_RANGES["stars_intensity"]["min"],
		EXTENDED_RANGES["stars_intensity"]["max"],
		EXTENDED_RANGES["stars_intensity"]["step"],
		"stars_intensity")
	
	# Разделитель
	shader_container.add_child(HSeparator.new())
	
	# Заголовок для параметров облаков
	var clouds_params_label = Label.new()
	clouds_params_label.text = "Параметры облаков:"
	shader_container.add_child(clouds_params_label)
	
	# Плотность облаков
	add_slider_parameter(shader_container, "Плотность облаков:", 
		EXTENDED_RANGES["clouds_density"]["min"],
		EXTENDED_RANGES["clouds_density"]["max"],
		EXTENDED_RANGES["clouds_density"]["step"],
		"clouds_density")
	
	# Масштаб облаков
	add_slider_parameter(shader_container, "Масштаб облаков:", 
		EXTENDED_RANGES["clouds_scale"]["min"],
		EXTENDED_RANGES["clouds_scale"]["max"],
		EXTENDED_RANGES["clouds_scale"]["step"],
		"clouds_scale")
	
	# Плотность высоких облаков
	add_slider_parameter(shader_container, "Плотность высоких облаков:", 
		EXTENDED_RANGES["high_clouds_density"]["min"],
		EXTENDED_RANGES["high_clouds_density"]["max"],
		EXTENDED_RANGES["high_clouds_density"]["step"],
		"high_clouds_density")
		
	# ======== NEW: ВКЛАДКА ЛУНЫ ========
	
	var moon_settings_label = Label.new()
	moon_settings_label.text = "Настройки времени восхода и захода луны:"
	moon_container.add_child(moon_settings_label)
	
	# Moon rise time
	var moon_rise_hbox = HBoxContainer.new()
	moon_container.add_child(moon_rise_hbox)
	
	var moon_rise_label = Label.new()
	moon_rise_label.text = "Время восхода луны (час):"
	moon_rise_label.custom_minimum_size.x = 200
	moon_rise_hbox.add_child(moon_rise_label)
	
	moon_rise_hour_spinbox = SpinBox.new()
	moon_rise_hour_spinbox.min_value = 0
	moon_rise_hour_spinbox.max_value = 23
	moon_rise_hour_spinbox.value = 18  # Default to sunset (18:00)
	moon_rise_hour_spinbox.step = 1
	moon_rise_hour_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moon_rise_hour_spinbox.value_changed.connect(func(value): _on_moon_rise_hour_changed(value))
	moon_rise_hbox.add_child(moon_rise_hour_spinbox)
	
	# Moon set time
	var moon_set_hbox = HBoxContainer.new()
	moon_container.add_child(moon_set_hbox)
	
	var moon_set_label = Label.new()
	moon_set_label.text = "Время захода луны (час):"
	moon_set_label.custom_minimum_size.x = 200
	moon_set_hbox.add_child(moon_set_label)
	
	moon_set_hour_spinbox = SpinBox.new()
	moon_set_hour_spinbox.min_value = 0
	moon_set_hour_spinbox.max_value = 23
	moon_set_hour_spinbox.value = 6  # Default to sunrise (6:00)
	moon_set_hour_spinbox.step = 1
	moon_set_hour_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moon_set_hour_spinbox.value_changed.connect(func(value): _on_moon_set_hour_changed(value))
	moon_set_hbox.add_child(moon_set_hour_spinbox)
	
	# Moon rise duration
	var moon_rise_duration_hbox = HBoxContainer.new()
	moon_container.add_child(moon_rise_duration_hbox)
	
	var moon_rise_duration_label = Label.new()
	moon_rise_duration_label.text = "Продолжительность восхода (часы):"
	moon_rise_duration_label.custom_minimum_size.x = 200
	moon_rise_duration_hbox.add_child(moon_rise_duration_label)
	
	moon_rise_duration_spinbox = SpinBox.new()
	moon_rise_duration_spinbox.min_value = 0.1
	moon_rise_duration_spinbox.max_value = 2.0
	moon_rise_duration_spinbox.value = 1.0
	moon_rise_duration_spinbox.step = 0.1
	moon_rise_duration_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moon_rise_duration_spinbox.value_changed.connect(func(value): _on_moon_rise_duration_changed(value))
	moon_rise_duration_hbox.add_child(moon_rise_duration_spinbox)
	
	# Moon set duration
	var moon_set_duration_hbox = HBoxContainer.new()
	moon_container.add_child(moon_set_duration_hbox)
	
	var moon_set_duration_label = Label.new()
	moon_set_duration_label.text = "Продолжительность захода (часы):"
	moon_set_duration_label.custom_minimum_size.x = 200
	moon_set_duration_hbox.add_child(moon_set_duration_label)
	
	moon_set_duration_spinbox = SpinBox.new()
	moon_set_duration_spinbox.min_value = 0.1
	moon_set_duration_spinbox.max_value = 2.0
	moon_set_duration_spinbox.value = 1.0
	moon_set_duration_spinbox.step = 0.1
	moon_set_duration_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moon_set_duration_spinbox.value_changed.connect(func(value): _on_moon_set_duration_changed(value))
	moon_set_duration_hbox.add_child(moon_set_duration_spinbox)
	
	# Information text about full moon
	var full_moon_info = Label.new()
	full_moon_info.text = """
	Полнолуние:
	- Восходит на закате (18:00–19:00)
	- Заходит на рассвете (6:00–7:00)
	- Видна всю ночь
	"""
	moon_container.add_child(full_moon_info)
	
	# Apply button for moon settings
	var apply_moon_button = Button.new()
	apply_moon_button.text = "Применить настройки луны"
	apply_moon_button.pressed.connect(_on_apply_moon_settings)
	moon_container.add_child(apply_moon_button)
	
	# ======== SAVE SETTINGS BUTTON ========
	
	# Add a separator at the bottom of each container
	for container in tab_containers:
		container.add_child(HSeparator.new())
	
	# Add save settings button to each tab container
	for container in tab_containers:
		var save_button = Button.new()
		save_button.text = "Сохранить все настройки"
		save_button.pressed.connect(_on_save_settings_pressed)
		container.add_child(save_button)
	
	# Активируем первую вкладку по умолчанию
	switch_tab(0)

# Функция для добавления слайдера с параметром шейдера
func add_slider_parameter(container, label_text, min_val, max_val, step_val, param_name):
	var hbox = HBoxContainer.new()
	container.add_child(hbox)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 200
	hbox.add_child(label)
	
	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = get_shader_param_value(param_name)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value): set_shader_param(param_name, value))
	hbox.add_child(slider)
	
	# Добавляем метку со значением слайдера
	var value_label = Label.new()
	value_label.text = str(slider.value)
	value_label.custom_minimum_size.x = 60
	hbox.add_child(value_label)
	
	# Обновляем метку при изменении значения
	slider.value_changed.connect(func(value): value_label.text = str(snappedf(value, 0.01)))

# Функция для получения значения параметра шейдера
func get_shader_param_value(param_name):
	if sky_material and sky_material.get_shader_parameter(param_name) != null:
		return sky_material.get_shader_parameter(param_name)
	elif celestial_bodies and celestial_bodies.get(param_name) != null:
		return celestial_bodies.get(param_name)
	else:
		# Возвращаем значения по умолчанию
		match param_name:
			"sun_size": return 3.0
			"sun_intensity": return 2.0
			"sun_bloom": return 0.8
			"moon_size": return 4.0
			"moon_brightness": return 1.0
			"moon_phase": return 0.0
			"stars_intensity": return 5.0
			"clouds_density": return 0.4
			"clouds_scale": return 1.0
			"high_clouds_density": return 0.2
			_: return 0.0

# Функция для установки параметра шейдера
func set_shader_param(param_name, value):
	if sky_material:
		sky_material.set_shader_parameter(param_name, value)
	
	# Также обновляем параметр в celestial_bodies, если это доступно
	if celestial_bodies and celestial_bodies.get(param_name) != null:
		match param_name:
			"sun_size": celestial_bodies.sun_size = value
			"sun_intensity": celestial_bodies.sun_intensity = value
			"sun_bloom": celestial_bodies.sun_bloom = value
			"moon_size": celestial_bodies.moon_size = value
			"moon_brightness": celestial_bodies.moon_brightness = value
			"moon_phase": celestial_bodies.set_moon_phase(value)
			"clouds_density": celestial_bodies.clouds_density = value
			"high_clouds_density": celestial_bodies.high_clouds_density = value
			"stars_intensity": celestial_bodies.stars_intensity = value

# Функция для переключения вкладок
func switch_tab(tab_index):
	current_tab = tab_index
	
	# Обновляем видимость контейнеров
	for i in range(tab_containers.size()):
		tab_containers[i].visible = (i == tab_index)
	
	# Обновляем состояние кнопок вкладок
	for i in range(tab_buttons.size()):
		if i == tab_index:
			tab_buttons[i].add_theme_color_override("font_color", Color(1, 1, 0))
		else:
			tab_buttons[i].add_theme_color_override("font_color", Color(1, 1, 1))

# Обновление состояния чекбоксов
func update_checkboxes():
	if celestial_bodies:
		sun_checkbox.button_pressed = celestial_bodies.sun_visible
		moon_checkbox.button_pressed = celestial_bodies.moon_visible
		stars_checkbox.button_pressed = celestial_bodies.stars_visible
		clouds_checkbox.button_pressed = celestial_bodies.clouds_visible
		high_clouds_checkbox.button_pressed = celestial_bodies.high_clouds_visible
		planet1_checkbox.button_pressed = celestial_bodies.planet1_visible
		planet2_checkbox.button_pressed = celestial_bodies.planet2_visible
		planet3_checkbox.button_pressed = celestial_bodies.planet3_visible

# NEW: Update moon settings UI
func update_moon_settings():
	if celestial_bodies:
		moon_rise_hour_spinbox.value = celestial_bodies.moon_rise_hour_offset
		moon_set_hour_spinbox.value = celestial_bodies.moon_set_hour_offset
		moon_rise_duration_spinbox.value = celestial_bodies.moon_rise_duration
		moon_set_duration_spinbox.value = celestial_bodies.moon_set_duration

# Обработчики событий кнопок
func _on_slow_button_pressed():
	if time_manager:
		time_manager.set_time_scale(TIME_SCALE_SLOW)

func _on_normal_button_pressed():
	if time_manager:
		time_manager.set_time_scale(TIME_SCALE_NORMAL)

func _on_fast_button_pressed():
	if time_manager:
		time_manager.set_time_scale(TIME_SCALE_FAST)

# Обработчики событий для чекбоксов
func _on_sun_toggled(toggled_on):
	if celestial_bodies:
		celestial_bodies.set_sun_visible(toggled_on)
	# Добавьте прямое обновление шейдера
	if sky_material:
		sky_material.set_shader_parameter("sun_visible", toggled_on)

func _on_moon_toggled(toggled_on):
	if celestial_bodies:
		celestial_bodies.set_moon_visible(toggled_on)

func _on_stars_toggled(toggled_on):
	if celestial_bodies:
		celestial_bodies.set_stars_visible(toggled_on)

func _on_clouds_toggled(toggled_on):
	if celestial_bodies:
		celestial_bodies.set_clouds_visible(toggled_on)

func _on_high_clouds_toggled(toggled_on):
	if celestial_bodies:
		celestial_bodies.set_high_clouds_visible(toggled_on)

func _on_planet1_toggled(toggled_on):
	if celestial_bodies:
		celestial_bodies.planet1_visible = toggled_on
		if sky_material:
			sky_material.set_shader_parameter("planet1_visible", toggled_on)

func _on_planet2_toggled(toggled_on):
	if celestial_bodies:
		celestial_bodies.planet2_visible = toggled_on
		if sky_material:
			sky_material.set_shader_parameter("planet2_visible", toggled_on)

func _on_planet3_toggled(toggled_on):
	if celestial_bodies:
		celestial_bodies.planet3_visible = toggled_on
		if sky_material:
			sky_material.set_shader_parameter("planet3_visible", toggled_on)

# NEW: Moon settings handlers
func _on_moon_rise_hour_changed(value):
	if celestial_bodies:
		celestial_bodies.moon_rise_hour_offset = value

func _on_moon_set_hour_changed(value):
	if celestial_bodies:
		celestial_bodies.moon_set_hour_offset = value

func _on_moon_rise_duration_changed(value):
	if celestial_bodies:
		celestial_bodies.moon_rise_duration = value

func _on_moon_set_duration_changed(value):
	if celestial_bodies:
		celestial_bodies.moon_set_duration = value

func _on_apply_moon_settings():
	if celestial_bodies:
		# Apply all moon settings at once
		celestial_bodies.moon_rise_hour_offset = moon_rise_hour_spinbox.value
		celestial_bodies.moon_set_hour_offset = moon_set_hour_spinbox.value
		celestial_bodies.moon_rise_duration = moon_rise_duration_spinbox.value
		celestial_bodies.moon_set_duration = moon_set_duration_spinbox.value
		
		# Display confirmation message
		OS.alert("Настройки луны применены", "Информация")

# NEW: Save settings handler
func _on_save_settings_pressed():
	if celestial_bodies:
		var success = celestial_bodies.save_settings()
		if success:
			OS.alert("Все настройки сохранены", "Информация")
		else:
			OS.alert("Не удалось сохранить настройки", "Ошибка")

# Обработчик события кнопки установки времени
func _on_time_set_button_pressed():
	if time_manager:
		var hours = time_input_hours.value
		var minutes = time_input_minutes.value
		var decimal_time = hours + (minutes / 60.0)
		time_manager.set_time(decimal_time)

# Обработчик события кнопки настроек
func _on_settings_button_pressed():
	sky_settings_window.visible = !sky_settings_window.visible
	if sky_settings_window.visible:
		update_checkboxes()
		update_moon_settings()
		
		# Инициализируем поля времени только при открытии окна
		if time_manager:
			var hours = int(time_manager.current_time)
			var minutes = int((time_manager.current_time - hours) * 60)
			time_input_hours.value = hours
			time_input_minutes.value = minutes

# Установка предустановленного времени
func _set_preset_time(hour: float):
	if time_manager:
		time_manager.set_time(hour)
	
	# Обновляем поля ввода времени для соответствия предустановке
	var hours = int(hour)
	var minutes = int((hour - hours) * 60)
	time_input_hours.value = hours
	time_input_minutes.value = minutes
