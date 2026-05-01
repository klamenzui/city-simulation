class_name CitizenManualControl
extends RefCounted

## Manual-control + click-move state flags. Extracted from old `Citizen.gd`.
##
## Pure state — the Facade orchestrates the side effects (rest-pose clear,
## building exit, travel stop, etc.) when these flags toggle. The component
## itself does not know about Movement, Location, or RestPose.
##
## Three orthogonal flags (only one of `manual_enabled` / `click_move_enabled`
## is typically active at a time, but the component does not enforce that —
## the Facade does via `set_*_enabled` orchestration).

## True when the player has taken direct WASD control of this citizen.
var manual_enabled: bool = false

## True when the citizen is moving toward a player-clicked map point.
var click_move_enabled: bool = false

## Suppresses input reads while a UI dialog is open over the manual citizen.
var manual_input_locked: bool = false

## Edge state for jump key; the Facade movement helper reads/writes this
## across physics frames.
var manual_jump_was_pressed: bool = false


func is_manual_enabled() -> bool:
	return manual_enabled


func set_manual_enabled(enabled: bool) -> void:
	manual_enabled = enabled
	if not enabled:
		manual_jump_was_pressed = false


func is_click_move_enabled() -> bool:
	return click_move_enabled


func set_click_move_enabled(enabled: bool) -> void:
	click_move_enabled = enabled


func is_input_locked() -> bool:
	return manual_input_locked


func set_input_locked(locked: bool) -> void:
	manual_input_locked = locked
	if locked:
		manual_jump_was_pressed = false


## Resets all flags. Called on full disable / scene teardown.
func reset() -> void:
	manual_enabled = false
	click_move_enabled = false
	manual_input_locked = false
	manual_jump_was_pressed = false
