extends Node3D

# Настройки автомобиля
@export var max_speed = 4.0  # Максимальная скорость
@export var acceleration = 2.0  # Ускорение
@export var steering_speed = 3.0  # Скорость поворота
@export var brake_power = 3.0  # Сила торможения
@export var gravity = 9.8  # Гравитация

# Флаги для типа автомобиля
@export var is_police = false  # Полицейский автомобиль?
@export var is_emergency = false  # Экстренная служба?
@export var signal_lights = false  # Включены ли сигнальные огни

# Физические свойства
var velocity = Vector3.ZERO
var current_speed = 0.0
var steering_angle = 0.0

# Ссылки на узлы автомобиля
var front_left_wheel: Node3D
var front_right_wheel: Node3D
var rear_left_wheel: Node3D
var rear_right_wheel: Node3D
var body_mesh: Node3D
var collision_shape: CollisionShape3D

func _ready():
	# Ищем узлы колес и кузова
	find_car_nodes()
	
	# Настройка колес
	setup_wheels()
	
	# Добавляем себя в группу транспорта
	add_to_group("traffic")
	
	# Автоматическое определение типа автомобиля по имени
	if is_police or "police" in name.to_lower():
		is_police = true
		is_emergency = true
	
	# Инициализация начальной скорости
	current_speed = randf_range(max_speed * 0.5, max_speed)

# Поиск узлов автомобиля
func find_car_nodes():
	# Найдем колеса
	for child in get_children():
		var lower_name = child.name.to_lower()
		
		if "wheel" in lower_name or "колесо" in lower_name:
			if "front" in lower_name or "перед" in lower_name:
				if "left" in lower_name or "лев" in lower_name:
					front_left_wheel = child
				elif "right" in lower_name or "прав" in lower_name:
					front_right_wheel = child
			elif "rear" in lower_name or "зад" in lower_name:
				if "left" in lower_name or "лев" in lower_name:
					rear_left_wheel = child
				elif "right" in lower_name or "прав" in lower_name:
					rear_right_wheel = child
		
		# Ищем кузов автомобиля
		if "body" in lower_name or "кузов" in lower_name or "car" in lower_name:
			body_mesh = child
		
		# Ищем коллизию
		if child is CollisionShape3D:
			collision_shape = child

# Настройка колес
func setup_wheels():
	# Задаем начальный поворот колес
	if front_left_wheel:
		front_left_wheel.rotation.y = 0
	if front_right_wheel:
		front_right_wheel.rotation.y = 0

# Физическое обновление (если используется собственная физика)
func _physics_process(delta):
	# Обновление физики
	update_physics(delta)
	
	# Обновление визуальных эффектов
	update_visuals(delta)

# Обновление физики автомобиля
func update_physics(delta):
	# Движение вперед с текущей скоростью
	var forward = -global_transform.basis.z
	velocity = forward * current_speed
	
	# Применяем движение
	position += velocity * delta
	
	# Применяем гравитацию (если нужно)
	if position.y > 0.1:
		position.y -= gravity * delta

# Обновление визуальных эффектов
func update_visuals(delta):
	# Поворот колес в зависимости от скорости поворота
	if front_left_wheel and front_right_wheel:
		front_left_wheel.rotation.y = steering_angle
		front_right_wheel.rotation.y = steering_angle
	
	# Вращение колес в зависимости от скорости
	var wheel_rotation_speed = current_speed * 2.0
	
	if front_left_wheel:
		front_left_wheel.rotate_x(wheel_rotation_speed * delta)
	if front_right_wheel:
		front_right_wheel.rotate_x(wheel_rotation_speed * delta)
	if rear_left_wheel:
		rear_left_wheel.rotate_x(wheel_rotation_speed * delta)
	if rear_right_wheel:
		rear_right_wheel.rotate_x(wheel_rotation_speed * delta)
	
	# Обновление сигнальных огней для экстренных служб
	if is_emergency and signal_lights:
		update_emergency_lights(delta)

# Обновление сигнальных огней
func update_emergency_lights(delta):
	# Здесь логика мигания огней
	pass

# Установка рулевого угла
func set_steering(angle):
	steering_angle = clamp(angle, -0.5, 0.5)  # Ограничение угла поворота колес

# Установка скорости
func set_speed(speed):
	current_speed = clamp(speed, 0, max_speed)

# Включение/выключение сигнальных огней
func toggle_signals():
	signal_lights = !signal_lights
	# Здесь код для включения/выключения визуализации огней
