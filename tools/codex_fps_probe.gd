extends SceneTree

const SceneTestUtils = preload("res://tools/codex_scene_test_utils.gd")

const WARMUP_FRAMES: int = 120
const MEASURE_FRAMES: int = 360


func _init() -> void:
	print("=== FPS probe ===")
	_configure_runtime_for_measurement()

	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		printerr("FAIL: cannot load Main.tscn")
		quit(1)
		return

	var main: Node = main_scene.instantiate()
	root.add_child(main)

	for _i in range(8):
		await process_frame
	if main.get("_runtime_controller") == null and main.has_method("_on_main_menu_singleplayer"):
		main.call("_on_main_menu_singleplayer")

	for _i in range(WARMUP_FRAMES):
		await process_frame

	var world := SceneTestUtils.find_world(main)
	if world == null:
		printerr("FAIL: World node not found")
		quit(1)
		return

	var frame_ms: Array[float] = []
	var totals := _new_monitor_dictionary()
	var peaks := _new_monitor_dictionary()
	var last_usec := Time.get_ticks_usec()
	for _i in range(MEASURE_FRAMES):
		await process_frame
		var now_usec := Time.get_ticks_usec()
		var elapsed_ms := float(now_usec - last_usec) / 1000.0
		last_usec = now_usec
		frame_ms.append(elapsed_ms)
		_sample_monitors(totals, peaks)

	_print_result(frame_ms, totals, peaks, world)
	print("=== End FPS probe ===")
	quit(0)


func _configure_runtime_for_measurement() -> void:
	Engine.max_fps = 0
	var display_name := DisplayServer.get_name()
	if display_name != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("display      = %s" % display_name)
	print("renderer     = %s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")))
	if display_name != "headless":
		var size := DisplayServer.window_get_size()
		print("window       = %dx%d" % [size.x, size.y])
	else:
		print("window       = headless")
	print("warmup       = %d frames" % WARMUP_FRAMES)
	print("measure      = %d frames" % MEASURE_FRAMES)


func _new_monitor_dictionary() -> Dictionary:
	return {
		"perf_fps": 0.0,
		"process_ms": 0.0,
		"physics_ms": 0.0,
		"draw_calls": 0.0,
		"primitives": 0.0,
		"render_objects": 0.0,
		"physics_objects": 0.0,
		"nodes": 0.0,
		"resources": 0.0,
	}


func _sample_monitors(totals: Dictionary, peaks: Dictionary) -> void:
	_add_monitor(totals, peaks, "perf_fps", Performance.TIME_FPS)
	_add_monitor(totals, peaks, "process_ms", Performance.TIME_PROCESS)
	_add_monitor(totals, peaks, "physics_ms", Performance.TIME_PHYSICS_PROCESS)
	_add_monitor(totals, peaks, "draw_calls", Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_add_monitor(totals, peaks, "primitives", Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_add_monitor(totals, peaks, "render_objects", Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_add_monitor(totals, peaks, "physics_objects", Performance.PHYSICS_3D_ACTIVE_OBJECTS)
	_add_monitor(totals, peaks, "nodes", Performance.OBJECT_NODE_COUNT)
	_add_monitor(totals, peaks, "resources", Performance.OBJECT_RESOURCE_COUNT)


func _add_monitor(totals: Dictionary, peaks: Dictionary, key: String, monitor: int) -> void:
	var value := float(Performance.get_monitor(monitor))
	totals[key] = float(totals.get(key, 0.0)) + value
	peaks[key] = maxf(float(peaks.get(key, 0.0)), value)


func _print_result(frame_ms: Array[float], totals: Dictionary, peaks: Dictionary, world: World) -> void:
	var avg_ms := _average(frame_ms)
	var sorted_ms := frame_ms.duplicate()
	sorted_ms.sort()
	var measured_fps := 1000.0 / avg_ms if avg_ms > 0.0 else 0.0
	var sample_count := maxi(frame_ms.size(), 1)

	print("scene        = citizens:%d buildings:%d paused:%s" % [
		world.citizens.size(),
		world.buildings.size(),
		str(world.is_paused),
	])
	print("FPS_RESULT avg_fps=%.1f perf_fps_avg=%.1f avg_ms=%.2f min_ms=%.2f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f" % [
		measured_fps,
		float(totals.get("perf_fps", 0.0)) / float(sample_count),
		avg_ms,
		sorted_ms[0],
		_percentile(sorted_ms, 0.95),
		_percentile(sorted_ms, 0.99),
		sorted_ms[sorted_ms.size() - 1],
	])
	print("FPS_RENDER draw_calls_avg=%.0f draw_calls_max=%.0f primitives_avg=%.0f render_objects_avg=%.0f physics_objects_avg=%.0f nodes_avg=%.0f resources_avg=%.0f" % [
		float(totals.get("draw_calls", 0.0)) / float(sample_count),
		float(peaks.get("draw_calls", 0.0)),
		float(totals.get("primitives", 0.0)) / float(sample_count),
		float(totals.get("render_objects", 0.0)) / float(sample_count),
		float(totals.get("physics_objects", 0.0)) / float(sample_count),
		float(totals.get("nodes", 0.0)) / float(sample_count),
		float(totals.get("resources", 0.0)) / float(sample_count),
	])
	print("FPS_CPU process_ms_avg=%.2f process_ms_max=%.2f physics_ms_avg=%.2f physics_ms_max=%.2f" % [
		float(totals.get("process_ms", 0.0)) / float(sample_count),
		float(peaks.get("process_ms", 0.0)),
		float(totals.get("physics_ms", 0.0)) / float(sample_count),
		float(peaks.get("physics_ms", 0.0)),
	])
	if DisplayServer.get_name() == "headless":
		print("FPS_NOTE headless run: rendering metrics are not representative.")


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var idx := int(ceil(percentile * float(sorted_values.size()))) - 1
	idx = clampi(idx, 0, sorted_values.size() - 1)
	return sorted_values[idx]
