extends CharacterBody3D

const SPEED = 1
const JUMP_VELOCITY = 15
const ACCEL = 10

var stuck_timer := 0.0
var last_position := Vector3.ZERO
@export var target := Vector3.ZERO
@onready var nav := $NavigationAgent3D 
@onready var ray_forward = $MeshInstance3D2/ObstacleRayCastForward
@onready var ray_left = $MeshInstance3D2/ObstacleRayCastLeft
@onready var ray_right = $MeshInstance3D2/ObstacleRayCastRight
@onready var ground_check = $MeshInstance3D2/GroundCheckRay

func _physics_process(delta):
	# Schwerkraft
	if not is_on_floor():
		velocity += Vector3(0, -30.0, 0) * delta
		move_and_slide()
		return
		
	if not target:
		return
		
	# Handle jump.
	#if Input.is_action_just_pressed("ui_accept") and is_on_floor():
	#	velocity.y = JUMP_VELOCITY

	# Ziel setzen
	nav.target_position = target
	var move_direction = nav.get_next_path_position() - global_position
	move_direction = move_direction.normalized()
	
	# Zusäzliche prüfung
	if (global_position - last_position).length() < 0.01:
		stuck_timer += delta
	else:
		stuck_timer = 0.0
	last_position = global_position
	# Wenn die Einheit stecken bleibt
	if stuck_timer > 1.0:
		move_direction = Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
		
	if move_direction.length() > 0.1:
		move_direction = move_direction.normalized()
		if not ground_check.is_colliding():
			velocity = -transform.basis.z * SPEED * 0.5
			return

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
		
		# Rotation anpassen
		var target_rotation = transform.looking_at(global_position + move_direction, Vector3.UP)
		rotation.y = lerp_angle(rotation.y, target_rotation.basis.get_euler().y, delta * 5)

	# Hindernis erkannt?
	#if obstacle_check.is_colliding():
		# Hindernis umgehen: einfache Methode – seitlich ausweichen
	#	var side = transform.basis.x
	#	direction += side * 0.5
	#	direction = direction.normalized()

	# Geschwindigkeit anpassen
	velocity = velocity.lerp(move_direction * SPEED, ACCEL * delta)
	move_and_slide()
