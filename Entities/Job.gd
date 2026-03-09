extends Resource
class_name Job

@export var title: String = "Worker"
@export var wage_per_hour: int = 12

@export var start_hour: int = 9
@export var shift_hours: int = 8  # always 8h shift

@export var workplace_name: String = ""  # optional filter by building_name
@export var required_education_level: int = 0

var workplace: Building = null

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
	return workplace.try_hire(person)

func meets_requirements(person: Citizen) -> bool:
	if person == null:
		return false
	return person.education_level >= required_education_level

func _auto_find_workplace(root: Node, from_pos: Vector3) -> Building:
	var best: Building = null
	var best_dist := INF

	for node in root.get_tree().get_nodes_in_group("buildings"):
		if not (node is Building):
			continue
		var b := node as Building

		if workplace_name != "" and b.building_name != workplace_name:
			continue
		if not b.has_free_job_slots():
			continue

		var d := from_pos.distance_to(b.global_position)
		if d < best_dist:
			best_dist = d
			best = b

	return best
