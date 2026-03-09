extends RefCounted
class_name GoapAction

var action_id: String
var cost: float = 1.0
var preconditions: Dictionary = {}
var effects: Dictionary = {}

func _init(_action_id: String = "", _cost: float = 1.0, _preconditions: Dictionary = {}, _effects: Dictionary = {}) -> void:
	action_id = _action_id
	cost = _cost
	preconditions = _preconditions.duplicate(true)
	effects = _effects.duplicate(true)

func check_preconditions(state: Dictionary) -> bool:
	for key in preconditions.keys():
		if not state.has(key):
			return false
		if state[key] != preconditions[key]:
			return false
	return true

func apply_effects(state: Dictionary) -> Dictionary:
	var next_state: Dictionary = state.duplicate(true)
	for key in effects.keys():
		next_state[key] = effects[key]
	return next_state
