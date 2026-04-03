extends SceneTree

func _init() -> void:
	var scene_path := _get_scene_path()
	if scene_path.is_empty():
		push_error("SCENE_WARNING_PROBE missing --scene argument")
		quit(2)
		return

	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("SCENE_WARNING_PROBE failed to load %s" % scene_path)
		quit(3)
		return

	var instance := packed_scene.instantiate()
	root.add_child(instance)
	print("SCENE_WARNING_PROBE loaded=", scene_path)

	await process_frame
	await process_frame

	instance.queue_free()
	await process_frame
	quit()

func _get_scene_path() -> String:
	var args := OS.get_cmdline_user_args()
	for idx in range(args.size()):
		if args[idx] != "--scene":
			continue
		if idx + 1 >= args.size():
			return ""
		return str(args[idx + 1])
	return ""
