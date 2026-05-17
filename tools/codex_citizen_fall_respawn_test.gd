extends SceneTree

const SETTLE_FRAMES := 45
const RESPAWN_FRAMES := 12
const COOLDOWN_FRAMES := 75

func _init() -> void:
	print("=== Citizen fall respawn test ===")
	var main_scene := load("res://Main.tscn") as PackedScene
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	for _i in range(SETTLE_FRAMES):
		await process_frame
	await physics_frame

	var world := main.get_node_or_null("World") as World
	if world == null:
		printerr("FAIL: World node not found")
		quit(1)
		return

	var citizen := _find_visible_citizen(world)
	if citizen == null:
		printerr("FAIL: need a visible citizen for fall respawn coverage")
		quit(1)
		return

	if citizen.has_method("set_network_server_control_enabled"):
		citizen.set_network_server_control_enabled(true, world)
	citizen.set_physics_process(true)

	var ground_y := world.get_ground_fallback_y()
	var player_before := _fall_respawn_count(citizen)
	_drop_below_world(citizen, ground_y)
	for _i in range(RESPAWN_FRAMES):
		await physics_frame

	if _fall_respawn_count(citizen) <= player_before:
		printerr("FAIL: server-controlled player citizen did not respawn after fall")
		quit(1)
		return
	if citizen.global_position.y < ground_y - 0.5:
		printerr("FAIL: player citizen respawned below ground threshold")
		quit(1)
		return
	if not citizen.visible:
		printerr("FAIL: respawned player citizen should be visible")
		quit(1)
		return

	if citizen.has_method("set_network_server_control_enabled"):
		citizen.set_network_server_control_enabled(false, world)
	for _i in range(COOLDOWN_FRAMES):
		await physics_frame

	var citizen_before := _fall_respawn_count(citizen)
	_drop_below_world(citizen, ground_y)
	for _i in range(RESPAWN_FRAMES):
		await physics_frame

	if _fall_respawn_count(citizen) <= citizen_before:
		printerr("FAIL: autonomous citizen did not respawn after fall")
		quit(1)
		return
	if citizen.global_position.y < ground_y - 0.5:
		printerr("FAIL: autonomous citizen respawned below ground threshold")
		quit(1)
		return
	if not citizen.visible:
		printerr("FAIL: respawned citizens should be visible")
		quit(1)
		return

	print("respawn=%s count=%d ground_y=%.2f" % [
		_fmt_v3(citizen.global_position),
		_fall_respawn_count(citizen),
		ground_y,
	])
	print("CITIZEN_FALL_RESPAWN OK")
	main.queue_free()
	await process_frame
	quit(0)

func _find_visible_citizen(world: World) -> Citizen:
	for citizen in world.citizens:
		if citizen == null or not is_instance_valid(citizen):
			continue
		if not citizen.visible:
			continue
		if citizen.has_method("is_inside_building") and citizen.is_inside_building():
			continue
		return citizen
	return null

func _drop_below_world(citizen: Citizen, ground_y: float) -> void:
	var pos := citizen.global_position
	pos.y = ground_y - 50.0
	citizen.global_position = pos
	citizen.velocity = Vector3.ZERO

func _fall_respawn_count(citizen: Citizen) -> int:
	if citizen != null and citizen.has_method("get_fall_respawn_count"):
		return int(citizen.get_fall_respawn_count())
	return 0

func _fmt_v3(value: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [value.x, value.y, value.z]
