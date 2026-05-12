extends SceneTree

const InteractionControllerScript = preload("res://Simulation/UI/SimulationInteractionController.gd")
const SelectionStateControllerScript = preload("res://Simulation/Debug/SelectionStateController.gd")

const SETTLE_FRAMES := 30

func _init() -> void:
	print("=== Selection hit test ===")

	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)
	for _i in range(SETTLE_FRAMES):
		await process_frame
	await physics_frame

	var world := main.get_node_or_null("World") as World
	var camera := main.get_node_or_null("Camera3D") as CityBuilderCamera
	if world == null or camera == null:
		printerr("FAIL: World or Camera3D not found")
		quit(1)
		return

	var citizen := _first_selectable_citizen(world)
	if citizen == null:
		printerr("FAIL: no visible citizen found")
		quit(1)
		return

	var aim_pos := citizen.global_position + Vector3(0.0, 0.45, 0.0)
	camera.global_position = aim_pos + Vector3(0.0, 6.0, 7.0)
	camera.look_at(aim_pos, Vector3.UP)
	camera.current = true
	await process_frame
	await physics_frame

	var selection = SelectionStateControllerScript.new()
	selection.setup(world, camera, null, null, null, null, null)
	var interaction = InteractionControllerScript.new()
	interaction.owner_node = main
	interaction.world = world
	interaction.selection_state_controller = selection

	var screen_pos := camera.unproject_position(aim_pos)
	if not interaction._try_select_entity_under_cursor(screen_pos):
		printerr("FAIL: selection ray did not pick a citizen")
		quit(1)
		return

	var selected := selection.get_selected_citizen()
	if selected != citizen:
		printerr("FAIL: selected wrong citizen expected=%s actual=%s" % [
			citizen.citizen_name,
			selected.citizen_name if selected != null else "-"
		])
		quit(1)
		return

	print("SELECTION_HIT OK citizen=%s screen=%s" % [
		citizen.citizen_name,
		str(screen_pos)
	])
	main.queue_free()
	await process_frame
	quit(0)


func _first_selectable_citizen(world: World) -> Citizen:
	for citizen in world.citizens:
		if citizen != null and citizen.visible and not citizen.is_inside_building():
			return citizen
	return null
