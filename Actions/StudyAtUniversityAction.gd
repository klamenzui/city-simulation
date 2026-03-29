extends Action
class_name StudyAtUniversityAction

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

var university: University
var study_minutes_target: int = 90
var _study_started: bool = false
var _education_before: int = 0
var _stop_hunger_threshold: float = 70.0
var _stop_health_threshold: float = 35.0

func _init(_university: University, _study_minutes_target: int = -1) -> void:
	super()
	label = "Study"
	university = _university
	var config: Dictionary = BalanceConfig.get_section("actions.study")
	study_minutes_target = _study_minutes_target
	if study_minutes_target < 0:
		study_minutes_target = int(config.get("default_minutes", 90))
	_stop_hunger_threshold = float(config.get("stop_hunger_threshold", 70.0))
	_stop_health_threshold = float(config.get("stop_health_threshold", 35.0))

func start(world, citizen) -> void:
	super.start(world, citizen)
	_study_started = false
	_education_before = citizen.education_level

	if university == null:
		citizen.debug_log_once_per_day("study_missing_target", "Study action aborted: no university target was assigned.")
		finished = true
		return
	if not university.is_open(world.time.get_hour()):
		var status := university.get_open_status_label(world.time.get_hour())
		citizen.debug_log_once_per_day(
			"study_closed_%s" % university.get_display_name(),
			"Study blocked at %s: status %s at %02d:00." % [
				university.get_display_name(),
				status,
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

	_study_started = university.study_session(world, citizen)
	if not _study_started:
		citizen.debug_log_once_per_day(
			"study_start_%s" % university.get_display_name(),
			"Study could not start at %s because the university is not operational." % [
				university.get_display_name(),
			]
		)
		finished = true
		return
	citizen.debug_log("Study session started at %s: education %d -> %d." % [
		university.get_display_name(),
		_education_before,
		citizen.education_level
	])

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if not _study_started:
		finished = true
		return
	if citizen.needs.hunger >= _stop_hunger_threshold \
		or citizen.needs.energy <= citizen.low_energy_threshold \
		or citizen.needs.health <= _stop_health_threshold:
		finished = true
		return
	if elapsed_minutes >= study_minutes_target:
		finished = true

func finish(world, citizen) -> void:
	if university != null:
		university.finish_study(citizen)
	if _study_started:
		citizen.debug_log("Study session finished at %s after %d min. Education now %d." % [
			university.get_display_name() if university != null else "Unknown",
			elapsed_minutes,
			citizen.education_level
		])
