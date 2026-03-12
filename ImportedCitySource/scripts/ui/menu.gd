extends Control

# Сигналы
signal resume_game
signal settings_changed(settings_data)

# Переменная для отслеживания состояния паузы
var is_paused: bool = false
var is_settings_open: bool = false

# Настройки по умолчанию
var settings = {
	"city_size": 3,
	"block_size": 4,
	"traffic_enabled": true,
	"car_count": 5
}

# Ссылки на узлы
@onready var panel = $MenuPanel
@onready var background = $ColorRect
@onready var main_menu_container = $MenuPanel/MainMenuContainer
@onready var settings_container = $MenuPanel/SettingsContainer

# Tween для анимаций
var tween: Tween

func _ready():
	# По умолчанию меню паузы и настройки скрыты
	panel.visible = false
	background.visible = false
	settings_container.visible = false
	
	# Начальная прозрачность и масштаб
	panel.modulate.a = 0
	background.modulate.a = 0
	panel.scale = Vector2(0.9, 0.9)
	
	# Устанавливаем начальные значения для настроек в UI
	update_settings_ui()
	
func _input(event):
	# При нажатии Escape вызываем переключение меню паузы
	if event.is_action_pressed("ui_cancel"):
		if is_settings_open:
			# Если открыты настройки, то возвращаемся в основное меню
			show_main_menu()
		else:
			toggle_pause()

# Функция переключения состояния паузы
func toggle_pause():
	is_paused = !is_paused
	
	if is_paused:
		show_menu()
	else:
		hide_menu()

# Показать меню с анимацией
func show_menu():
	# Остановим предыдущий tween, если он существует
	if tween:
		tween.kill()
	
	# Установить паузу в игре
	get_tree().paused = true
	
	# Делаем панели видимыми перед анимацией
	panel.visible = true
	background.visible = true
	main_menu_container.visible = true
	settings_container.visible = false
	is_settings_open = false
	
	# Создаем новый tween
	tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK) # Используем TRANS_BACK для эффекта пружины
	
	# Анимация прозрачности
	tween.tween_property(background, "modulate:a", 1.0, 0.3)
	
	# Анимация масштаба и прозрачности панели
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.4)
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)

# Скрыть меню с анимацией
func hide_menu():
	# Остановим предыдущий tween, если он существует
	if tween:
		tween.kill()
	
	# Создаем новый tween
	tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	
	# Анимация прозрачности
	tween.tween_property(background, "modulate:a", 0.0, 0.2)
	
	# Анимация масштаба и прозрачности панели
	tween.tween_property(panel, "scale", Vector2(0.9, 0.9), 0.3)
	tween.tween_property(panel, "modulate:a", 0.0, 0.2)
	
	# После завершения всех анимаций
	tween.chain().tween_callback(func():
		# Скрываем панели
		panel.visible = false
		background.visible = false
		
		# Возобновить игру
		get_tree().paused = false
		
		# Вызвать сигнал о возобновлении игры
		resume_game.emit()
	)

# Показать настройки
func show_settings():
	is_settings_open = true
	
	# Анимация для плавного перехода
	var transition_tween = create_tween()
	transition_tween.set_ease(Tween.EASE_OUT)
	transition_tween.set_trans(Tween.TRANS_CUBIC)
	
	# Скрываем основное меню
	transition_tween.tween_property(main_menu_container, "modulate:a", 0.0, 0.2)
	
	# Обновляем UI настроек перед показом
	update_settings_ui()
	
	# Показываем настройки после скрытия основного меню
	transition_tween.tween_callback(func():
		main_menu_container.visible = false
		settings_container.visible = true
		settings_container.modulate.a = 0.0
	)
	
	# Анимируем появление панели настроек
	transition_tween.tween_property(settings_container, "modulate:a", 1.0, 0.2)

# Показать основное меню
func show_main_menu():
	is_settings_open = false
	
	# Анимация для плавного перехода
	var transition_tween = create_tween()
	transition_tween.set_ease(Tween.EASE_OUT)
	transition_tween.set_trans(Tween.TRANS_CUBIC)
	
	# Скрываем настройки
	transition_tween.tween_property(settings_container, "modulate:a", 0.0, 0.2)
	
	# Показываем основное меню после скрытия настроек
	transition_tween.tween_callback(func():
		settings_container.visible = false
		main_menu_container.visible = true
		main_menu_container.modulate.a = 0.0
	)
	
	# Анимируем появление основного меню
	transition_tween.tween_property(main_menu_container, "modulate:a", 1.0, 0.2)

# Обновить UI настроек в соответствии с текущими значениями
func update_settings_ui():
	$MenuPanel/SettingsContainer/VBoxContainer/CitySizeHBox/CitySizeSlider.value = settings["city_size"]
	$MenuPanel/SettingsContainer/VBoxContainer/BlockSizeHBox/BlockSizeSlider.value = settings["block_size"]
	$MenuPanel/SettingsContainer/VBoxContainer/CarCountHBox/CarCountSlider.value = settings["car_count"]
	$MenuPanel/SettingsContainer/VBoxContainer/TrafficHBox/TrafficCheckBox.button_pressed = settings["traffic_enabled"]
	
	# Обновляем текстовые метки значений
	$MenuPanel/SettingsContainer/VBoxContainer/CitySizeHBox/CitySizeValue.text = str(settings["city_size"])
	$MenuPanel/SettingsContainer/VBoxContainer/BlockSizeHBox/BlockSizeValue.text = str(settings["block_size"])
	$MenuPanel/SettingsContainer/VBoxContainer/CarCountHBox/CarCountValue.text = str(settings["car_count"])

# Применить настройки
# Обновите эту функцию в вашем файле menu.gd
func apply_settings():
	# Добавляем флаг для перегенерации города
	settings["regenerate_city"] = true
	
	# Отправляем сигнал с данными настроек для обработки в control.gd
	settings_changed.emit(settings)
	
	# Возвращаемся в основное меню
	show_main_menu()

# Обработчики изменения настроек
func _on_city_size_slider_value_changed(value):
	settings["city_size"] = int(value)
	$MenuPanel/SettingsContainer/VBoxContainer/CitySizeHBox/CitySizeValue.text = str(settings["city_size"])

func _on_block_size_slider_value_changed(value):
	settings["block_size"] = int(value)
	$MenuPanel/SettingsContainer/VBoxContainer/BlockSizeHBox/BlockSizeValue.text = str(settings["block_size"])

func _on_car_count_slider_value_changed(value):
	settings["car_count"] = int(value)
	$MenuPanel/SettingsContainer/VBoxContainer/CarCountHBox/CarCountValue.text = str(settings["car_count"])

func _on_traffic_check_box_toggled(button_pressed):
	settings["traffic_enabled"] = button_pressed

# Обработчик кнопки Resume
func _on_resume_button_pressed():
	toggle_pause()

# Обработчик кнопки Settings
func _on_settings_button_pressed():
	show_settings()

# Обработчик кнопки Apply в настройках
func _on_apply_button_pressed():
	apply_settings()

# Обработчик кнопки Back в настройках
func _on_back_button_pressed():
	show_main_menu()

# Обработчик кнопки Quit
func _on_quit_button_pressed():
	# Выход из игры
	get_tree().quit()
