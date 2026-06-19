extends Area3D
class_name FarmWorkInteractable

signal interaction_requested(interactable: FarmWorkInteractable)

@export var interactable_id: String = ""
@export var interactable_type: String = ""
@export var display_name: String = "Interactable"
@export var interaction_radius: float = 3.0

var payload: Dictionary = {}

var _highlighted: bool = false
var _base_scale: Vector3 = Vector3.ONE


func setup(id: String, type_name: String, label: String, radius: float = 3.0) -> void:
	interactable_id = id.strip_edges()
	interactable_type = type_name.strip_edges()
	display_name = label.strip_edges() if not label.strip_edges().is_empty() else interactable_id
	interaction_radius = maxf(radius, 0.5)
	name = display_name.replace(" ", "")
	input_ray_pickable = true
	collision_layer = 1
	collision_mask = 0


func _ready() -> void:
	_base_scale = scale
	input_ray_pickable = true
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)


func add_box_shape(size: Vector3, offset: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 0.1), maxf(size.y, 0.1), maxf(size.z, 0.1))
	var collision := CollisionShape3D.new()
	collision.name = "InteractionShape"
	collision.shape = shape
	collision.position = offset
	add_child(collision)
	return collision


func set_payload_value(key: String, value: Variant) -> void:
	payload[key] = value


func get_payload_value(key: String, default_value: Variant = null) -> Variant:
	return payload.get(key, default_value)


func get_context_summary() -> Dictionary:
	return {
		"id": interactable_id,
		"type": interactable_type,
		"display_name": display_name,
		"interaction_radius": interaction_radius,
		"payload": payload.duplicate(true),
	}


func set_highlighted(highlighted: bool) -> void:
	if _highlighted == highlighted:
		return
	_highlighted = highlighted
	scale = _base_scale * (1.04 if highlighted else 1.0)


func _on_input_event(
	_camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	interaction_requested.emit(self)
