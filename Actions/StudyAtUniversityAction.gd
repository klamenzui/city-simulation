extends Action
class_name StudyAtUniversityAction

var university: University
var study_minutes_target: int = 90
var _tuition_paid: bool = false

func _init(_university: University, _study_minutes_target: int = 90) -> void:
	super()
	label = "Study"
	university = _university
	study_minutes_target = _study_minutes_target

func start(world, citizen) -> void:
	super.start(world, citizen)
	_tuition_paid = false

	if university == null:
		finished = true
		return
	if not university.is_open(world.time.get_hour()):
		finished = true
		return
	if not university.begin_study(citizen):
		finished = true
		return

	_tuition_paid = university.study_session(world, citizen)
	if not _tuition_paid:
		finished = true
		return

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if not _tuition_paid:
		finished = true
		return
	if citizen.needs.hunger >= 70.0 or citizen.needs.energy <= citizen.low_energy_threshold or citizen.needs.health <= 35.0:
		finished = true
		return
	if elapsed_minutes >= study_minutes_target:
		finished = true

func finish(world, citizen) -> void:
	if university != null:
		university.finish_study(citizen)

