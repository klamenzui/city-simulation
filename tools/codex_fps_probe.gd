extends SceneTree

const SceneTestUtils = preload("res://tools/codex_scene_test_utils.gd")

const DEFAULT_WARMUP_FRAMES: int = 120
const DEFAULT_MEASURE_FRAMES: int = 360

var _warmup_frames: int = DEFAULT_WARMUP_FRAMES
var _measure_frames: int = DEFAULT_MEASURE_FRAMES
var _profile_output_path: String = ""


func _init() -> void:
	_read_options()
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

	for _i in range(_warmup_frames):
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
	for _i in range(_measure_frames):
		await process_frame
		var now_usec := Time.get_ticks_usec()
		var elapsed_ms := float(now_usec - last_usec) / 1000.0
		last_usec = now_usec
		frame_ms.append(elapsed_ms)
		_sample_monitors(totals, peaks)

	var report := _build_report(frame_ms, totals, peaks, main, world)
	_print_result(report)
	_write_report(report)
	print("=== End FPS probe ===")
	quit(0)


func _read_options() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-output="):
			_profile_output_path = arg.get_slice("=", 1).strip_edges()
		elif arg.begins_with("--warmup="):
			_warmup_frames = maxi(0, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--frames="):
			_measure_frames = maxi(1, int(arg.get_slice("=", 1)))


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
	print("warmup       = %d frames" % _warmup_frames)
	print("measure      = %d frames" % _measure_frames)
	if not _profile_output_path.is_empty():
		print("profile_json = %s" % _profile_output_path)


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


func _build_report(
	frame_ms: Array[float],
	totals: Dictionary,
	peaks: Dictionary,
	main: Node,
	world: World
) -> Dictionary:
	var avg_ms := _average(frame_ms)
	var sorted_ms := frame_ms.duplicate()
	sorted_ms.sort()
	var measured_fps := 1000.0 / avg_ms if avg_ms > 0.0 else 0.0
	var sample_count := maxi(frame_ms.size(), 1)
	var display_name := DisplayServer.get_name()

	var window: Dictionary = {"headless": true}
	if display_name != "headless":
		var window_size := DisplayServer.window_get_size()
		window = {
			"headless": false,
			"width": window_size.x,
			"height": window_size.y,
		}

	return {
		"completed": true,
		"timestamp_unix": Time.get_unix_time_from_system(),
		"display": display_name,
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")),
		"window": window,
		"warmup_frames": _warmup_frames,
		"measure_frames": _measure_frames,
		"scene": {
			"citizens": world.citizens.size(),
			"buildings": world.buildings.size(),
			"paused": world.is_paused,
		},
		"fps": {
			"avg_fps": measured_fps,
			"perf_fps_avg": float(totals.get("perf_fps", 0.0)) / float(sample_count),
			"avg_ms": avg_ms,
			"min_ms": _first_or_zero(sorted_ms),
			"p95_ms": _percentile(sorted_ms, 0.95),
			"p99_ms": _percentile(sorted_ms, 0.99),
			"max_ms": _last_or_zero(sorted_ms),
		},
		"render": {
			"draw_calls_avg": float(totals.get("draw_calls", 0.0)) / float(sample_count),
			"draw_calls_max": float(peaks.get("draw_calls", 0.0)),
			"primitives_avg": float(totals.get("primitives", 0.0)) / float(sample_count),
			"render_objects_avg": float(totals.get("render_objects", 0.0)) / float(sample_count),
			"physics_objects_avg": float(totals.get("physics_objects", 0.0)) / float(sample_count),
			"nodes_avg": float(totals.get("nodes", 0.0)) / float(sample_count),
			"resources_avg": float(totals.get("resources", 0.0)) / float(sample_count),
		},
		"cpu": {
			"process_ms_avg": float(totals.get("process_ms", 0.0)) / float(sample_count),
			"process_ms_max": float(peaks.get("process_ms", 0.0)),
			"physics_ms_avg": float(totals.get("physics_ms", 0.0)) / float(sample_count),
			"physics_ms_max": float(peaks.get("physics_ms", 0.0)),
		},
		"visual_lod": _get_visual_lod_summary(main),
	}


func _print_result(report: Dictionary) -> void:
	var scene: Dictionary = report.get("scene", {})
	var fps: Dictionary = report.get("fps", {})
	var render: Dictionary = report.get("render", {})
	var cpu: Dictionary = report.get("cpu", {})
	var visual_lod: Dictionary = report.get("visual_lod", {})

	print("scene        = citizens:%d buildings:%d paused:%s" % [
		int(scene.get("citizens", 0)),
		int(scene.get("buildings", 0)),
		str(scene.get("paused", false)),
	])
	print("FPS_RESULT avg_fps=%.1f perf_fps_avg=%.1f avg_ms=%.2f min_ms=%.2f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f" % [
		float(fps.get("avg_fps", 0.0)),
		float(fps.get("perf_fps_avg", 0.0)),
		float(fps.get("avg_ms", 0.0)),
		float(fps.get("min_ms", 0.0)),
		float(fps.get("p95_ms", 0.0)),
		float(fps.get("p99_ms", 0.0)),
		float(fps.get("max_ms", 0.0)),
	])
	print("FPS_RENDER draw_calls_avg=%.0f draw_calls_max=%.0f primitives_avg=%.0f render_objects_avg=%.0f physics_objects_avg=%.0f nodes_avg=%.0f resources_avg=%.0f" % [
		float(render.get("draw_calls_avg", 0.0)),
		float(render.get("draw_calls_max", 0.0)),
		float(render.get("primitives_avg", 0.0)),
		float(render.get("render_objects_avg", 0.0)),
		float(render.get("physics_objects_avg", 0.0)),
		float(render.get("nodes_avg", 0.0)),
		float(render.get("resources_avg", 0.0)),
	])
	print("FPS_CPU process_ms_avg=%.2f process_ms_max=%.2f physics_ms_avg=%.2f physics_ms_max=%.2f" % [
		float(cpu.get("process_ms_avg", 0.0)),
		float(cpu.get("process_ms_max", 0.0)),
		float(cpu.get("physics_ms_avg", 0.0)),
		float(cpu.get("physics_ms_max", 0.0)),
	])
	if not visual_lod.is_empty():
		print("FPS_VISUAL_LOD meshes=%d lights=%d hidden_debug=%d missing_roots=%s" % [
			int(visual_lod.get("configured_meshes", 0)),
			int(visual_lod.get("configured_lights", 0)),
			int(visual_lod.get("hidden_debug_meshes", 0)),
			str(visual_lod.get("missing_roots", [])),
		])
	if DisplayServer.get_name() == "headless":
		print("FPS_NOTE headless run: rendering metrics are not representative.")


func _write_report(report: Dictionary) -> void:
	if _profile_output_path.is_empty():
		return
	var normalized_path := _profile_output_path.replace("\\", "/")
	var file := FileAccess.open(normalized_path, FileAccess.WRITE)
	if file == null:
		printerr("FPS_REPORT_WRITE_FAIL path=%s error=%s" % [
			normalized_path,
			error_string(FileAccess.get_open_error()),
		])
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("FPS_REPORT path=%s" % normalized_path)


func _get_visual_lod_summary(main: Node) -> Dictionary:
	var runtime = main.get("_runtime_controller")
	if runtime != null and runtime.has_method("get_visual_lod_summary"):
		return runtime.get_visual_lod_summary()
	return {}


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _first_or_zero(values: Array[float]) -> float:
	return values[0] if not values.is_empty() else 0.0


func _last_or_zero(values: Array[float]) -> float:
	return values[values.size() - 1] if not values.is_empty() else 0.0


func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var idx := int(ceil(percentile * float(sorted_values.size()))) - 1
	idx = clampi(idx, 0, sorted_values.size() - 1)
	return sorted_values[idx]
