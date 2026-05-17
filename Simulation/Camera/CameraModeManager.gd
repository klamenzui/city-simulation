extends RefCounted
class_name CameraModeManager

## Central, minimal switch between the player 3rd-person camera and the
## city-builder camera. Guarantees exactly one Camera3D is `current` at a time.
##
## Rules:
## - Default mode is PLAYER_THIRD_PERSON.
## - Clients may ONLY use PLAYER_THIRD_PERSON (CITY_BUILDER is server/host/offline
##   only); toggle() and set_mode(CITY_BUILDER) are no-ops for clients.
## - The 5 legacy "follow the controlled player" call sites are served through
##   the set_follow_target / clear_follow_target / is_following_controller_view
##   shim so they keep working without knowing about two cameras.

enum CameraMode { PLAYER_THIRD_PERSON, CITY_BUILDER }

var city_builder_camera: CityBuilderCamera = null
var player_camera: PlayerThirdPersonCamera = null
var multiplayer_session = null

var _mode: int = CameraMode.PLAYER_THIRD_PERSON
var _player_target: Node3D = null


func setup(
	city_builder_camera_ref: CityBuilderCamera,
	player_camera_ref: PlayerThirdPersonCamera,
	multiplayer_session_ref = null
) -> void:
	city_builder_camera = city_builder_camera_ref
	player_camera = player_camera_ref
	multiplayer_session = multiplayer_session_ref
	if player_camera != null:
		player_camera.setup()
	_apply()


func get_mode() -> int:
	return _mode


func is_player_mode() -> bool:
	return _mode == CameraMode.PLAYER_THIRD_PERSON


func can_use_city_builder() -> bool:
	return not _is_network_client()


func set_mode(mode: int) -> void:
	if mode == CameraMode.CITY_BUILDER and not can_use_city_builder():
		mode = CameraMode.PLAYER_THIRD_PERSON
	_mode = mode
	_apply()


func toggle() -> void:
	# Clients cannot reach the builder camera via input.
	if not can_use_city_builder():
		set_mode(CameraMode.PLAYER_THIRD_PERSON)
		return
	set_mode(CameraMode.CITY_BUILDER if _mode == CameraMode.PLAYER_THIRD_PERSON else CameraMode.PLAYER_THIRD_PERSON)


func set_player_target(target: Node3D) -> void:
	_player_target = target
	if player_camera != null:
		player_camera.set_target(target)
	# Acquiring a player puts the local view into 3rd person by default; the
	# host can still toggle to the builder camera afterwards.
	if target != null:
		set_mode(CameraMode.PLAYER_THIRD_PERSON)
	else:
		_apply()


func clear_player_target() -> void:
	_player_target = null
	if player_camera != null:
		player_camera.set_target(null)
	_apply()


func get_player_target() -> Node3D:
	if _player_target == null or not is_instance_valid(_player_target):
		return null
	return _player_target


func get_active_camera() -> Camera3D:
	if _mode == CameraMode.PLAYER_THIRD_PERSON and player_camera != null:
		return player_camera.get_camera()
	return city_builder_camera


# --- Legacy follow-API shim -------------------------------------------------
# Existing callers (SelectionStateController player control, host authority,
# client replica) talk to "the camera" via these names. Route them to the
# 3rd-person rig + central mode switch.

func set_follow_target(target: Node3D, _controller_view: bool = true) -> void:
	set_player_target(target)


func clear_follow_target() -> void:
	clear_player_target()


func is_following_controller_view() -> bool:
	return _mode == CameraMode.PLAYER_THIRD_PERSON and get_player_target() != null


func is_follow_mode() -> bool:
	return is_following_controller_view()


func get_follow_target() -> Node3D:
	return get_player_target()


func set_input_locked(locked: bool) -> void:
	if player_camera != null:
		player_camera.set_input_locked(locked)
	if city_builder_camera != null and city_builder_camera.has_method("set_input_locked"):
		city_builder_camera.set_input_locked(locked)


func is_input_locked() -> bool:
	if city_builder_camera != null and city_builder_camera.has_method("is_input_locked"):
		return bool(city_builder_camera.is_input_locked())
	return false


func _apply() -> void:
	# Exactly one current camera. Setting Camera3D.current = true auto-clears
	# the previous one, but we deactivate explicitly to avoid any 1-frame
	# overlap / flicker.
	#
	# The player rig only takes over once it actually has a target. With no
	# player yet (pre-game menu, bootstrap) the builder camera stays current
	# so the backdrop is framed instead of an empty rig at the origin.
	var show_player := _mode == CameraMode.PLAYER_THIRD_PERSON and get_player_target() != null
	if show_player:
		if city_builder_camera != null:
			city_builder_camera.clear_follow_target()
			city_builder_camera.current = false
		if player_camera != null:
			player_camera.activate()
	else:
		if player_camera != null:
			player_camera.deactivate()
		if city_builder_camera != null:
			city_builder_camera.current = true


func _is_network_client() -> bool:
	return multiplayer_session != null \
		and multiplayer_session.has_method("is_client") \
		and multiplayer_session.is_client()
