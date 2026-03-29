extends Resource
class_name Job

@export var title: String = "Worker"
@export var wage_per_hour: int = 12

@export var start_hour: int = 9
@export var shift_hours: int = 8

@export var workplace_name: String = ""
@export var workplace_service_type: String = ""
@export var required_education_level: int = 0
@export var allowed_building_types: Array[int] = []

var workplace: Building = null
var preferred_workplace: Building = null

func resolve_nearest(root: Node, from_pos: Vector3) -> void:
	if root == null:
		return
	if workplace != null and workplace.has_free_job_slots():
		return
	workplace = _auto_find_workplace(root, from_pos)

func try_get_employed(person: Citizen) -> bool:
	if workplace == null:
		return false
	if not meets_requirements(person):
		return false
	if not allows_building(workplace):
		return false
	return workplace.try_hire(person)

func meets_requirements(person: Citizen) -> bool:
	if person == null:
		return false
	return person.education_level >= required_education_level

func allows_building(building: Building) -> bool:
	if building == null:
		return false
	if preferred_workplace != null and building != preferred_workplace:
		return false
	if workplace_name != "" and building.building_name != workplace_name:
		return false
	if workplace_service_type != "" and building.get_service_type() != workplace_service_type:
		return false
	if not allowed_building_types.is_empty() and not allowed_building_types.has(building.building_type):
		return false
	return true

func _auto_find_workplace(root: Node, from_pos: Vector3) -> Building:
	var best: Building = null
	var best_dist := INF

	for node in root.get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var building := node as Building
		if not allows_building(building):
			continue
		if not building.has_free_job_slots():
			continue

		var dist := from_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building

	return best
