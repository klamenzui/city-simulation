extends SceneTree

const MiniGameScene = preload("res://Scenes/Minigames/TeacherLesson/TeacherLessonMinigame.tscn")
const UniversityScript = preload("res://Entities/Buildings/University.gd")
const CitizenScript = preload("res://Entities/Citizens/New/Citizen.gd")
const JobScript = preload("res://Entities/Job.gd")

const TARGET_FORMULA := "formula"
const TARGET_EVENT := "event"
const TARGET_TOOL := "tool"

var _harness: Node3D = null

func _initialize() -> void:
	_harness = Node3D.new()
	root.add_child(_harness)
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures: Array[String] = []

	var game = MiniGameScene.instantiate()
	game.auto_start = false
	game.rng_seed = 12345
	root.add_child(game)

	_expect(game.supports_workplace_type("University"), "University should be supported", failures)
	_expect(game.supports_workplace_type("universitaet"), "ASCII Universitaet alias should be supported", failures)
	_expect(not game.supports_workplace_type("Shop"), "Shop should not use teacher lesson gameplay", failures)

	_expect_eq(game.get_target_for_question("area_rectangle"), TARGET_FORMULA, "rectangle area target", failures)
	_expect_eq(game.get_target_for_question("wall_fall"), TARGET_EVENT, "wall fall target", failures)
	_expect_eq(game.get_target_for_question("multimeter"), TARGET_TOOL, "multimeter target", failures)

	var basic_ids: PackedStringArray = game.get_question_ids_for_skill(0)
	var skilled_ids: PackedStringArray = game.get_question_ids_for_skill(2)
	_expect(basic_ids.has("area_rectangle"), "base run should include simple math", failures)
	_expect(basic_ids.has("screwdriver"), "base run should include simple technology", failures)
	_expect(not basic_ids.has("circle_area"), "circle area should be skill-gated", failures)
	_expect(skilled_ids.has("circle_area"), "skilled run should include circle area", failures)
	_expect(skilled_ids.has("french_revolution"), "skilled run should include harder history", failures)

	var correct_result: Dictionary = game.debug_answer_question("area_rectangle", TARGET_FORMULA)
	_expect(bool(correct_result.get("correct", false)), "correct lesson answer should pass", failures)
	_expect(int(correct_result.get("score", 0)) > 0, "correct lesson answer should score", failures)
	var wrong_result: Dictionary = game.debug_answer_question("multimeter", TARGET_FORMULA)
	_expect(not bool(wrong_result.get("correct", true)), "wrong lesson target should fail", failures)
	_expect_eq(int(wrong_result.get("combo", -1)), 0, "wrong target should reset combo", failures)

	game.start_session()
	var start_window: float = game.debug_get_current_question_window()
	game.debug_set_elapsed(game.session_duration_sec)
	var end_window: float = game.debug_get_current_question_window()
	_expect(end_window < start_window, "question window should shrink over the session", failures)

	game.start_session()
	for question_id in [
		"area_rectangle",
		"percentage",
		"wall_fall",
		"moon_landing",
		"screwdriver",
		"multimeter",
		"pythagoras",
	]:
		var target_id: String = game.get_target_for_question(question_id)
		game.debug_answer_question(question_id, target_id)

	var result: Dictionary = game.get_result()
	_expect(float(result.get("teaching_quality", 0.0)) >= 0.65, "solid lesson should create teaching quality", failures)
	_expect_eq(int(result.get("education_progress_bonus", 0)), 1, "solid lesson should grant education progress bonus", failures)
	_expect(int(result.get("city_effect_sessions", 0)) > 0, "solid lesson should affect at least one study session", failures)

	var university: University = _new_university(_harness, "Lesson Uni")
	var teacher: Citizen = _new_citizen(_harness, "Teacher One")
	teacher.job = JobScript.new()
	teacher.job.title = "Teacher"
	teacher.job.workplace = university
	teacher.job.workplace_service_type = "education"
	_expect(university.try_hire(teacher), "university should hire teaching staff", failures)

	var student: Citizen = _new_citizen(_harness, "Student One")
	student.education_level = 0
	var sessions_before := int(result.get("city_effect_sessions", 0))
	_expect_eq(university.apply_teacher_lesson_result(result), 1, "lesson result should arm university quality bonus", failures)
	_expect_eq(university.get_teacher_quality_extra_gain(), 1, "university should expose active quality extra gain", failures)
	_expect(university.study_session(null, student), "student should study at quality-boosted university", failures)
	_expect_eq(student.education_level, 2, "quality lesson should add one extra education level", failures)
	_expect_eq(
		university.teacher_quality_study_sessions_remaining,
		sessions_before - 1,
		"quality bonus should consume one effective study session",
		failures
	)

	game.queue_free()
	_harness.queue_free()
	if failures.is_empty():
		print("TEACHER_LESSON_MINIGAME_TEST OK")
		quit(0)
		return
	print("TEACHER_LESSON_MINIGAME_TEST FAILED:")
	for failure in failures:
		print("  - %s" % failure)
	quit(1)


func _new_university(harness: Node, building_name: String) -> University:
	var university: University = UniversityScript.new()
	university.name = building_name
	university.building_name = building_name
	var entrance := Node3D.new()
	entrance.name = "Entrance"
	entrance.position = Vector3(0.0, 0.0, 1.4)
	university.add_child(entrance)
	harness.add_child(university)
	return university


func _new_citizen(harness: Node, citizen_name: String) -> Citizen:
	var citizen: Citizen = CitizenScript.new()
	citizen.name = citizen_name
	citizen.citizen_name = citizen_name
	citizen.jump_low_obstacles = false
	harness.add_child(citizen)
	return citizen


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _expect_eq(actual, expected, message: String, failures: Array[String]) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])
