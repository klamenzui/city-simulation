extends Action
class_name SocialVisitAction

const GoToBuildingActionScript = preload("res://Actions/GoToBuildingAction.gd")
const EatAtRestaurantActionScript = preload("res://Actions/EatAtRestaurantAction.gd")
const SocializeActionScript = preload("res://Actions/SocializeAction.gd")
const WatchCinemaActionScript = preload("res://Actions/WatchCinemaAction.gd")

const ACTIVITY_RESTAURANT := "restaurant"
const ACTIVITY_PARK := "park"
const ACTIVITY_CINEMA := "cinema"

const PHASE_TRAVEL := "travel"
const PHASE_ACTIVITY := "activity"
const PHASE_DONE := "done"

var target: Building = null
var activity: String = ""
var travel_minutes: int = 20
var restore_control_after: bool = false

var _step: Action = null
var _phase: String = PHASE_DONE
var _restore_keyboard_control: bool = false
var _restore_manual_control: bool = false
var _restore_click_move: bool = false

func _init(
	_target: Building = null,
	_activity: String = "",
	_restore_control_after: bool = false,
	_travel_minutes: int = 20
) -> void:
	super()
	target = _target
	activity = _activity
	restore_control_after = _restore_control_after
	travel_minutes = maxi(_travel_minutes, 1)
	label = "Visit"

func start(world, citizen) -> void:
	super.start(world, citizen)
	_step = null
	_phase = PHASE_DONE
	if target == null or citizen == null:
		finished = true
		return
	_capture_and_disable_player_control(citizen, world)
	_start_step(GoToBuildingActionScript.new(target, travel_minutes, false), world, citizen, PHASE_TRAVEL)

func tick(world, citizen, dt: int) -> void:
	super.tick(world, citizen, dt)
	if finished:
		return
	if _step == null:
		finished = true
		return
	_step.tick(world, citizen, dt)
	if not _step.is_done():
		return
	_step.finish(world, citizen)
	if _phase == PHASE_TRAVEL:
		if citizen == null or citizen.current_location != target:
			finished = true
			return
		var activity_step := _build_activity_step()
		if activity_step == null:
			finished = true
			return
		_start_step(activity_step, world, citizen, PHASE_ACTIVITY)
		if _step != null and _step.is_done():
			_step.finish(world, citizen)
			finished = true
		return
	finished = true

func finish(world, citizen) -> void:
	if _step != null and not _step.is_done():
		_step.finish(world, citizen)
	_step = null
	_phase = PHASE_DONE
	_restore_player_control(citizen, world)

func get_needs_modifier(world, citizen) -> Dictionary:
	if _step != null:
		return _step.get_needs_modifier(world, citizen)
	return Action.make_default_needs_modifier()

func get_target_building() -> Building:
	return target

func get_activity() -> String:
	return activity

func _start_step(step: Action, world, citizen, phase: String) -> void:
	_step = step
	_phase = phase
	if _step == null:
		finished = true
		return
	_step.start(world, citizen)

func _build_activity_step() -> Action:
	match activity:
		ACTIVITY_RESTAURANT:
			if target is Restaurant:
				return EatAtRestaurantActionScript.new(target as Restaurant)
		ACTIVITY_PARK:
			if target is Park or target.is_in_group("parks"):
				return SocializeActionScript.new()
		ACTIVITY_CINEMA:
			if target is Cinema:
				return WatchCinemaActionScript.new(target as Cinema)
	return null

func _capture_and_disable_player_control(citizen, world) -> void:
	if not restore_control_after or citizen == null:
		return
	if citizen.has_method("is_keyboard_control_enabled") and citizen.is_keyboard_control_enabled():
		_restore_keyboard_control = true
		if citizen.has_method("exit_keyboard_control_mode"):
			citizen.exit_keyboard_control_mode()
	if citizen.has_method("is_manual_control_enabled") and citizen.is_manual_control_enabled():
		_restore_manual_control = true
		citizen.set_manual_control_enabled(false, world)
	if citizen.has_method("is_click_move_mode_enabled") and citizen.is_click_move_mode_enabled():
		_restore_click_move = true
		citizen.set_click_move_mode_enabled(false, world)

func _restore_player_control(citizen, world) -> void:
	if not restore_control_after or citizen == null:
		return
	if _restore_keyboard_control and citizen.has_method("enter_keyboard_control_mode"):
		citizen.enter_keyboard_control_mode(true)
	elif _restore_manual_control and citizen.has_method("set_manual_control_enabled"):
		citizen.set_manual_control_enabled(true, world)
	elif _restore_click_move and citizen.has_method("set_click_move_mode_enabled"):
		citizen.set_click_move_mode_enabled(true, world)
	_restore_keyboard_control = false
	_restore_manual_control = false
	_restore_click_move = false
