extends Action
class_name StudyAtUniversityAction

var university: University
var study_minutes_target: int = 90
var _tuition_paid: bool = false
var _education_before: int = 0
var _wallet_before: int = 0

func _init(_university: University, _study_minutes_target: int = 90) -> void:
	super()
	label = "Study"
	university = _university
	study_minutes_target = _study_minutes_target

func start(world, citizen) -> void:
	super.start(world, citizen)
	_tuition_paid = false
	_education_before = citizen.education_level
	_wallet_before = citizen.wallet.balance

	if university == null:
		citizen.debug_log_once_per_day("study_missing_target", "Study action aborted: no university target was assigned.")
		finished = true
		return
	if not university.is_open(world.time.get_hour()):
		citizen.debug_log_once_per_day(
			"study_closed_%s" % university.get_display_name(),
			"Study blocked at %s: building is closed at %02d:00." % [
				university.get_display_name(),
				world.time.get_hour()
			]
		)
		finished = true
		return
	if not university.begin_study(citizen):
		citizen.debug_log_once_per_day(
			"study_capacity_%s" % university.get_display_name(),
			"Study blocked at %s: visitor capacity reached." % university.get_display_name()
		)
		finished = true
		return

	_tuition_paid = university.study_session(world, citizen)
	if not _tuition_paid:
		citizen.debug_log_once_per_day(
			"study_payment_%s" % university.get_display_name(),
			"Study payment failed at %s: tuition %d EUR, balance %d EUR." % [
				university.get_display_name(),
				university.tuition_fee,
				_wallet_before
			]
		)
		finished = true
		return
	citizen.debug_log("Study session started at %s: tuition %d EUR, education %d -> %d, balance %d -> %d." % [
		university.get_display_name(),
		university.tuition_fee,
		_education_before,
		citizen.education_level,
		_wallet_before,
		citizen.wallet.balance
	])

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
	if _tuition_paid:
		citizen.debug_log("Study session finished at %s after %d min. Education now %d." % [
			university.get_display_name() if university != null else "Unknown",
			elapsed_minutes,
			citizen.education_level
		])

