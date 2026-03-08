extends Node3D
class_name Building

@export var building_name: String = "Building"
@export var entrance: Node3D
@export var debug_panel: DebugPanel
@export var job_capacity: int = 0  # how many workers this building can employ

var account: Account = Account.new()
var employees: Array[Citizen] = []

func _ready() -> void:
	add_to_group("buildings")
	account.owner_name = building_name

# English: Buildings with capacity 0 offer no jobs.
func has_free_job_slots() -> bool:
	if job_capacity <= 0:
		return false
	return employees.size() < job_capacity

func try_hire(c: Citizen) -> bool:
	if c == null:
		return false
	if employees.has(c):
		return true
	if not has_free_job_slots():
		return false
	employees.append(c)
	return true

func fire(c: Citizen) -> void:
	employees.erase(c)

func get_entrance_pos() -> Vector3:
	if debug_panel:
		debug_panel.update_debug({ building_name: employees })
	return entrance.global_position if entrance else global_position
