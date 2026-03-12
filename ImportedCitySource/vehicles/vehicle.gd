extends VehicleBody3D

const STEER_SPEED = 1.5
const STEER_LIMIT = 0.4
const BRAKE_STRENGTH = 2.0
@export var engine_force_value := 40.0
@export var main_target_position: Vector3 = Vector3(70, 1, 0)
@export var target_position: Vector3 = Vector3(70, 1, 0)
@export var arrival_distance: float = .05  # Entfernung, bei der das Auto als "angekommen" gilt
@export var slowdown_distance: float = 10.0  # Entfernung, bei der das Auto anfängt zu bremsen
@onready var ray_forward = $ObstacleRayCastForward
@onready var ray_left = $ObstacleRayCastLeft
@onready var ray_right = $ObstacleRayCastRight
@onready var nav := $NavigationAgent3D
var previous_speed := 0.0
var steer_target := 0.0
var has_reached_target := false

@onready var desired_engine_pitch: float = $EngineSound.pitch_scale if has_node("EngineSound") else 1.0

func _ready():
	print("Auto startet an Position: ", global_position)
	print("Zielposition: ", target_position)
	# WICHTIG: Hier explizit das Ziel setzen (falls es von außen nicht richtig gesetzt wird)
	#target_position = Vector3(0, 0, -20)  # Setzen Sie einen Punkt VOR dem Auto
	print("Ziel manuell gesetzt auf: ", target_position)
	#nav.target_position = main_target_position
	#nav.get_next_path_position()
	call_deferred("_init_navigation")

func _init_navigation():
	# nav.set_target_position(main_target_position)
	# optional: nav.target_desired_distance = arrival_distance
	# optional: nav.path_desired_distance   = slowdown_distance
	var roads: Array[Node3D] = [] 
	var road_list: Array[Node] = get_tree().get_nodes_in_group("road_group")
	for item: Node3D in road_list:
		roads.append_array(item.get_children())
	#global_position
	#get_tree().get_no
	print(roads)
	

func next_path_position():
	return target_position
	
func _physics_process(delta: float):
	
	var next_path_position = next_path_position() #nav.get_next_path_position()
	DebugDraw3D.draw_sphere(next_path_position, 0.5, Color(0, 1, 0))
	var move_direction = next_path_position - global_position
	move_direction = move_direction.normalized()
	
	# Zusäzliche prüfung
	#if (global_position - next_path_position).length() < 0.2:
		#next_path_position = nav.get_next_path_position()
		#return
	#if ray_forward.is_colliding():
	"""var collision_object:Node3D = ray_forward.get_collider()
	var parent = collision_object.get_parent_node_3d()
	print(parent.name)
	parent.position"""
	#	engine_force = -engine_force_value * 0.7
	#	return
	# RayCasts checken
	var avoid_direction = Vector3.ZERO
	if ray_forward.is_colliding():
		if not ray_left.is_colliding():
			avoid_direction += -transform.basis.x  # links ausweichen
		elif not ray_right.is_colliding():
			avoid_direction += transform.basis.x   # rechts ausweichen
		else:
			# beide Seiten blockiert – nach hinten? oder stehen bleiben
			avoid_direction += -move_direction

	if avoid_direction != Vector3.ZERO:
		move_direction += avoid_direction.normalized()
		move_direction = move_direction.normalized()
	var speed := linear_velocity.length()
	
	if has_reached_target:
		engine_force = 0.0
		brake = BRAKE_STRENGTH
		return
	
	# Debug-Ausgabe der aktuellen Vorwärtsrichtung
	var forward_dir = -global_transform.basis.z
	print("Vorwärtsrichtung des Autos: ", forward_dir)
	
	# Berechnung der Richtung zum Ziel
	var direction_to_target = move_direction#target_position - global_position
	direction_to_target.y = 0  # Ignoriere Höhenunterschiede
	var distance_to_target = direction_to_target.length()
	
	print("Richtung zum Ziel: ", direction_to_target.normalized())
	print("Entfernung zum Ziel: ", distance_to_target)
	
	# Prüfen, ob das Ziel erreicht wurde
	if distance_to_target < arrival_distance:
		has_reached_target = true
		engine_force = 0.0
		brake = BRAKE_STRENGTH
		return
	
	# Lokale Richtung berechnen
	var local_direction = global_transform.basis.inverse() * direction_to_target
	print("Lokale Richtung zum Ziel: ", local_direction)
	
	# In Godot zeigt -Z nach vorne für das Fahrzeug
	var target_angle = atan2(local_direction.x, local_direction.z)
	print("Berechneter Winkel (Radiant): ", target_angle, " (Grad): ", rad_to_deg(target_angle))
	
	# VEREINFACHTER ANSATZ: Steuern Sie das Auto mit einer weniger komplexen Logik
	if abs(target_angle) < PI/2:  # Ziel ist mehr oder weniger vorne
		# Vorwärts fahren
		engine_force = engine_force_value
		steer_target = clamp(target_angle, -STEER_LIMIT, STEER_LIMIT)
		print("Vorwärts fahren, Lenkung: ", steer_target)
	else:  # Ziel ist hinten
		# Stark zurücksetzen und wenden
		engine_force = -engine_force_value * 0.5
		# Lenken in die andere Richtung für bessere Wendung
		steer_target = clamp(-sign(target_angle) * 0.4, -STEER_LIMIT, STEER_LIMIT)
		print("Rückwärts fahren zum Wenden, Lenkung: ", steer_target)
	
	# Lenkung aktualisieren
	steering = move_toward(steering, steer_target, STEER_SPEED * delta)
	previous_speed = speed

# Visuelle Hilfe zum Debuggen
func _process(_delta):
	#if Engine.is_editor_hint():
	#	return
		
	# Wenn Sie das DebugDraw3D Plugin haben
	#DebugDraw3D.draw_line(global_position, target_position, Color(1, 0, 0))
	#DebugDraw3D.draw_sphere(target_position, 0.5, Color(0, 1, 0))
	if Engine.has_singleton("DebugDraw3D"):
		"""
		var dd = Engine.get_singleton("DebugDraw3D")
		# Zeige Ziel
		dd.draw_sphere(target_position, 0.5, Color(0, 1, 0))
		# Zeige Weg vom Auto zum Ziel
		dd.draw_line(global_position, target_position, Color(1, 0, 0))
		# Zeige Vorwärtsrichtung des Autos
		var forward = global_position - global_transform.basis.z * 5.0
		dd.draw_line(global_position, forward, Color(0, 0, 1))
		"""
		pass
