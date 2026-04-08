extends Node
class_name LocalDialogueRuntimeService

const CONFIG_PATH := "res://config/dialogue_runtime.json"
const SimLogger = preload("res://Simulation/Logging/SimLogger.gd")

signal status_changed(status: String, detail: String)
signal npc_dialogue_ready(conversation_id: String)
signal player_dialogue_ready(session_id: String)

var _config: Dictionary = {}
var _headless_runtime: bool = false
var _probe_request: HTTPRequest = null
var _job_request: HTTPRequest = null
var _probe_phase: String = ""
var _probe_in_flight: bool = false
var _job_in_flight: bool = false
var _probe_retry_left: float = 0.0
var _status: String = "disabled"
var _status_detail: String = ""
var _backend_process_started: bool = false
var _available_models: Dictionary = {}
var _models_by_profile: Dictionary = {}
var _job_queue: Array = []
var _current_job: Dictionary = {}
var _pending_keys: Dictionary = {}
var _npc_cache: Dictionary = {}
var _player_cache: Dictionary = {}
var _warmup_queue: Array[String] = []
var _resolved_paths: Dictionary = {}
var _setup_process_pid: int = -1

func setup(config_override: Dictionary = {}, headless_runtime: bool = false) -> void:
	_headless_runtime = headless_runtime
	_config = _load_config(config_override)
	_prepare_local_runtime_layout()
	_ensure_http_nodes()
	if _get_bool("runtime.force_template_mode", false):
		_set_status("template_only", "forced_template_mode")
		return
	if _headless_runtime and _get_bool("startup.disabled_in_headless", true):
		_set_status("disabled", "headless_runtime")
		return
	if not _get_bool("startup.auto_start_on_game_boot", true):
		_set_status("idle", "startup_disabled")
		return
	_begin_backend_boot()

func update(delta: float) -> void:
	_refresh_setup_process_state()
	if _status in ["ready", "template_only", "disabled"]:
		_pump_job_queue()
		return
	if _status == "installing":
		_pump_job_queue()
	if _probe_in_flight:
		return
	_probe_retry_left = maxf(_probe_retry_left - delta, 0.0)
	if _probe_retry_left > 0.0:
		return
	_request_version_probe()

func get_status_label() -> String:
	return "%s:%s" % [_status, _status_detail]

func get_ui_runtime_state() -> Dictionary:
	var runtime_exists := _has_local_runtime_binary()
	var setup_script_exists := _has_setup_script()
	var recommended_model := _get_recommended_setup_model()
	var selected_models := _get_selected_model_names()
	var active_model_label := ", ".join(selected_models) if not selected_models.is_empty() else recommended_model
	var button_visible := false
	var button_enabled := false
	var button_text := ""
	var action := "none"
	var summary_text := "AI: Offline"

	match _status:
		"ready":
			summary_text = "AI: Ready (%s)" % [active_model_label]
		"warming":
			summary_text = "AI: Loading model (%s)" % [active_model_label]
		"installing":
			summary_text = "AI: Installing %s..." % [recommended_model if not recommended_model.is_empty() else "runtime"]
		"template_only":
			if _status_detail == "preferred_model_missing":
				summary_text = "AI: Model missing"
				action = "setup"
				button_text = "Download AI"
				button_visible = true
				button_enabled = setup_script_exists
			elif _status_detail == "forced_template_mode":
				summary_text = "AI: Template mode"
			else:
				summary_text = "AI: Fallback active"
				action = "retry" if runtime_exists else "setup"
				button_text = "Retry AI" if runtime_exists else "Setup AI"
				button_visible = true
				button_enabled = runtime_exists or setup_script_exists
		"idle":
			summary_text = "AI: Idle"
			action = "retry" if runtime_exists else "setup"
			button_text = "Start AI" if runtime_exists else "Setup AI"
			button_visible = true
			button_enabled = runtime_exists or setup_script_exists
		"disabled":
			summary_text = "AI: Disabled"
		_:
			if _status_detail.contains("probe_") or _status_detail.contains("request_failed") or _status_detail.contains("starting_local_backend"):
				summary_text = "AI: Starting..."
				if not _probe_in_flight and _setup_process_pid <= 0:
					action = "retry" if runtime_exists else "setup"
					button_text = "Retry AI" if runtime_exists else "Setup AI"
					button_visible = true
					button_enabled = runtime_exists or setup_script_exists
			else:
				summary_text = "AI: %s" % _status.capitalize()

	return {
		"status": _status,
		"detail": _status_detail,
		"summary_text": summary_text,
		"button_visible": button_visible,
		"button_enabled": button_enabled,
		"button_text": button_text,
		"action": action,
		"recommended_model": recommended_model,
		"runtime_exists": runtime_exists,
		"setup_script_exists": setup_script_exists,
		"llama_dir": str(_resolved_paths.get("llama_dir", "")),
		"models_dir": str(_resolved_paths.get("models_dir", "")),
		"runtime_dir": str(_resolved_paths.get("runtime_dir", "")),
		"selected_models": selected_models.duplicate(),
		"available_model_count": _available_models.size()
	}

func trigger_ui_runtime_action() -> Dictionary:
	var ui_state := get_ui_runtime_state()
	var action := str(ui_state.get("action", "none"))
	match action:
		"setup":
			return request_portable_setup(str(ui_state.get("recommended_model", "")))
		"retry":
			_begin_backend_boot()
			return {
				"started": true,
				"action": "retry"
			}
		_:
			return {
				"started": false,
				"action": "none"
			}

func request_portable_setup(model_name: String = "") -> Dictionary:
	if _setup_process_pid > 0:
		return {
			"started": false,
			"reason": "setup_already_running"
		}
	var powershell_path := _get_powershell_path()
	var script_path := _get_setup_script_path()
	if powershell_path.is_empty():
		return {
			"started": false,
			"reason": "powershell_missing"
		}
	if script_path.is_empty():
		return {
			"started": false,
			"reason": "setup_script_missing"
		}
	var requested_model := model_name.strip_edges()
	if requested_model.is_empty():
		requested_model = _get_recommended_setup_model()
	var args: Array[String] = [
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		script_path,
		"-ProjectRoot",
		str(_resolved_paths.get("project_dir", ProjectSettings.globalize_path("res://")))
	]
	if not requested_model.is_empty():
		args.append_array(["-Model", requested_model])
	var pid := OS.create_process(powershell_path, args, false)
	if pid <= 0:
		return {
			"started": false,
			"reason": "create_process_failed"
		}
	_setup_process_pid = pid
	_backend_process_started = false
	_set_status("installing", requested_model if not requested_model.is_empty() else "portable_setup")
	_probe_retry_left = _get_float("startup.retry_probe_interval_sec", 1.5)
	return {
		"started": true,
		"action": "setup",
		"pid": pid,
		"model": requested_model
	}

func get_cached_npc_conversation_block(conversation_id: String) -> Dictionary:
	if not _npc_cache.has(conversation_id):
		return {}
	return (_npc_cache.get(conversation_id, {}) as Dictionary).duplicate(true)

func request_npc_conversation_block(conversation_id: String, payload: Dictionary) -> Dictionary:
	if _npc_cache.has(conversation_id):
		return (_npc_cache.get(conversation_id, {}) as Dictionary).duplicate(true)
	if _pending_keys.has(conversation_id):
		return {
			"state": "pending",
			"source": "queued",
			"lines": []
		}

	var model := _get_profile_model("npc_npc")
	var npc_request := _build_generate_request_parts("npc_npc", model, payload)
	_log_generation_request("NPCDialog", conversation_id, "npc_npc", model, npc_request)
	if _should_use_template_fallback(model):
		var fallback_block := _build_npc_template_block(conversation_id, payload, _status)
		_npc_cache[conversation_id] = fallback_block
		return fallback_block.duplicate(true)

	if _job_queue.size() >= _get_int("runtime.max_queue_size", 2):
		var queue_policy := _get_string("fallback.on_queue_full", "skip_generation")
		SimLogger.log_ai("[AI][NPCDialog] Queue full for %s, policy=%s, status=%s" % [conversation_id, queue_policy, _status])
		if queue_policy == "use_template":
			var queued_fallback := _build_npc_template_block(conversation_id, payload, "queue_full")
			_npc_cache[conversation_id] = queued_fallback
			return queued_fallback.duplicate(true)
		return {
			"state": "skipped",
			"source": "queue_full",
			"lines": []
		}

	_pending_keys[conversation_id] = true
	_enqueue_job({
		"kind": "npc_npc",
		"key": conversation_id,
		"profile": "npc_npc",
		"model": model,
		"payload": payload.duplicate(true),
		"body": str(npc_request.get("body_json", "")),
		"prompt_text": str(npc_request.get("prompt_text", "")),
		"system_text": str(npc_request.get("system_text", ""))
	}, false)
	SimLogger.log_ai("[AI][NPCDialog] Queued job key=%s model=%s status=%s queue=%d" % [conversation_id, model, _status, _job_queue.size()])
	_pump_job_queue()
	return {
		"state": "pending",
		"source": "ollama",
		"model": model,
		"lines": []
	}

func request_player_reply(session_id: String, payload: Dictionary) -> Dictionary:
	if _player_cache.has(session_id):
		return (_player_cache.get(session_id, {}) as Dictionary).duplicate(true)
	if _pending_keys.has(session_id):
		return {
			"state": "pending",
			"source": "queued",
			"text": ""
		}

	var model := _get_profile_model("player_npc")
	var player_request := _build_generate_request_parts("player_npc", model, payload)
	_log_generation_request("PlayerDialog", session_id, "player_npc", model, player_request)
	if _should_use_template_fallback(model):
		var fallback_reply := _build_player_template_reply(session_id, payload, _status)
		_player_cache[session_id] = fallback_reply
		return fallback_reply.duplicate(true)

	_make_room_for_player_dialog_job(_get_int("runtime.max_queue_size", 2))
	if _job_queue.size() >= _get_int("runtime.max_queue_size", 2):
		var queue_policy := _get_string("fallback.on_queue_full", "use_template")
		SimLogger.log_ai("[AI][PlayerDialog] Queue full for %s, policy=%s, status=%s" % [session_id, queue_policy, _status])
		if queue_policy == "use_template":
			var queued_reply := _build_player_template_reply(session_id, payload, "queue_full")
			_player_cache[session_id] = queued_reply
			return queued_reply.duplicate(true)
		return {
			"state": "skipped",
			"source": "queue_full",
			"text": ""
		}

	_pending_keys[session_id] = true
	_enqueue_job({
		"kind": "player_npc",
		"key": session_id,
		"profile": "player_npc",
		"model": model,
		"payload": payload.duplicate(true),
		"body": str(player_request.get("body_json", "")),
		"prompt_text": str(player_request.get("prompt_text", "")),
		"system_text": str(player_request.get("system_text", ""))
	}, true)
	SimLogger.log_ai("[AI][PlayerDialog] Queued job key=%s model=%s status=%s queue=%d" % [session_id, model, _status, _job_queue.size()])
	_pump_job_queue()
	return {
		"state": "pending",
		"source": "ollama",
		"model": model,
		"text": ""
	}

func _begin_backend_boot() -> void:
	_set_status("starting", "probing_backend")
	_probe_retry_left = 0.0
	_request_version_probe()

func _ensure_http_nodes() -> void:
	var timeout_sec := _get_float("runtime.request_timeout_sec", 20.0)
	if _probe_request == null:
		_probe_request = HTTPRequest.new()
		_probe_request.name = "DialogueRuntimeProbe"
		add_child(_probe_request)
		_probe_request.request_completed.connect(_on_probe_request_completed)
	_probe_request.timeout = timeout_sec
	if _job_request == null:
		_job_request = HTTPRequest.new()
		_job_request.name = "DialogueRuntimeJobs"
		add_child(_job_request)
		_job_request.request_completed.connect(_on_job_request_completed)
	_job_request.timeout = timeout_sec

func _try_start_backend_process() -> void:
	if _backend_process_started:
		return
	var backend_kind := _get_string("startup.backend_kind", "ollama")
	if backend_kind != "ollama":
		return
	var serve_args := _get_string_array("startup.serve_args")
	for candidate in _resolve_command_candidates():
		var pid := OS.create_process(candidate, serve_args, false)
		if pid > 0:
			_backend_process_started = true
			SimLogger.log_ai("[AI] Started %s backend using %s (pid=%d)" % [backend_kind, candidate, pid])
			return

func _resolve_command_candidates() -> Array[String]:
	var resolved: Array[String] = []
	for raw_candidate in _get_value("startup.command_candidates", []):
		var candidate := str(raw_candidate)
		candidate = _expand_runtime_tokens(candidate)
		if candidate.is_empty():
			continue
		var looks_like_path := candidate.contains("\\") or candidate.contains("/") or candidate.contains(":")
		if looks_like_path and not FileAccess.file_exists(candidate):
			continue
		resolved.append(candidate)
	return resolved

func _request_version_probe() -> void:
	if _probe_request == null or _probe_in_flight:
		return
	_probe_phase = "version"
	_probe_in_flight = true
	var err := _probe_request.request(_get_api_url("/version"))
	if err != OK:
		_probe_in_flight = false
		_schedule_probe_retry("version_request_failed_%d" % err)

func _request_model_list_probe() -> void:
	if _probe_request == null or _probe_in_flight:
		return
	_probe_phase = "tags"
	_probe_in_flight = true
	var err := _probe_request.request(_get_api_url("/tags"))
	if err != OK:
		_probe_in_flight = false
		_schedule_probe_retry("tags_request_failed_%d" % err)

func _on_probe_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_probe_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_schedule_probe_retry("probe_%s_http_%d_result_%d" % [_probe_phase, response_code, result])
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if _probe_phase == "version":
		_request_model_list_probe()
		return
	if _probe_phase == "tags":
		if _setup_process_pid > 0:
			_capture_available_models(parsed)
			_prepare_profile_models()
			if _models_by_profile.is_empty():
				_set_status("installing", "waiting_for_model")
				_probe_retry_left = _get_float("startup.retry_probe_interval_sec", 1.5)
				return
			_setup_process_pid = -1
		else:
			_capture_available_models(parsed)
			_prepare_profile_models()
			if _models_by_profile.is_empty():
				_set_status("template_only", "preferred_model_missing")
				return
		_begin_warmup_if_needed()
		return

func _capture_available_models(parsed: Variant) -> void:
	_available_models.clear()
	if parsed is not Dictionary:
		return
	var models: Variant = (parsed as Dictionary).get("models", [])
	if models is not Array:
		return
	for model_entry in models:
		if model_entry is not Dictionary:
			continue
		var entry := model_entry as Dictionary
		var name := str(entry.get("name", entry.get("model", "")))
		if name.is_empty():
			continue
		_available_models[name] = true

func _prepare_profile_models() -> void:
	_models_by_profile.clear()
	var preferences: Variant = _get_value("model_preferences", {})
	if preferences is not Dictionary:
		return
	for profile in (preferences as Dictionary).keys():
		var profile_name := str(profile)
		var preferred_profile_model := _get_string("runtime_profiles.%s.profile_model_name" % profile_name, "")
		var resolved_profile_model := _resolve_available_model_name(preferred_profile_model)
		if not resolved_profile_model.is_empty():
			_models_by_profile[profile_name] = resolved_profile_model
			continue
		var candidates: Variant = (preferences as Dictionary).get(profile_name, [])
		if candidates is not Array:
			continue
		for candidate in candidates:
			var model_name := str(candidate)
			var resolved_candidate := _resolve_available_model_name(model_name)
			if not resolved_candidate.is_empty():
				_models_by_profile[profile_name] = resolved_candidate
				break

func _resolve_available_model_name(requested_name: String) -> String:
	var normalized := requested_name.strip_edges()
	if normalized.is_empty():
		return ""
	if _available_models.has(normalized):
		return normalized
	var latest_name := "%s:latest" % normalized
	if not normalized.contains(":") and _available_models.has(latest_name):
		return latest_name
	return ""

func _begin_warmup_if_needed() -> void:
	_warmup_queue.clear()
	if not _get_bool("startup.prewarm_on_boot", true):
		_set_status("ready", "connected")
		return
	var unique_models: Dictionary = {}
	for model_name in _models_by_profile.values():
		unique_models[str(model_name)] = true
	for model_name in unique_models.keys():
		_warmup_queue.append(str(model_name))
	if _warmup_queue.is_empty():
		_set_status("ready", "connected")
		return
	_set_status("warming", "loading_model")
	for model_name in _warmup_queue:
		_enqueue_job({
			"kind": "warmup",
			"key": str(model_name),
			"profile": "npc_npc",
			"model": str(model_name),
			"payload": {},
			"body": JSON.stringify({
				"model": str(model_name),
				"prompt": _get_string("startup.warmup_prompt", "Hello."),
				"stream": false,
				"keep_alive": _get_string("startup.prewarm_keep_alive", "10m"),
				"options": {
					"num_predict": 8,
					"temperature": 0.2
				}
			})
		}, false)
	_pump_job_queue()

func _enqueue_job(job: Dictionary, prioritize_player_dialog: bool) -> void:
	if not prioritize_player_dialog or _job_queue.is_empty():
		_job_queue.append(job.duplicate(true))
		return
	var insert_index := _job_queue.size()
	for idx in range(_job_queue.size()):
		var queued_variant: Variant = _job_queue[idx]
		if queued_variant is not Dictionary:
			continue
		var queued_job := queued_variant as Dictionary
		if str(queued_job.get("kind", "")) == "warmup":
			insert_index = idx
			break
	_job_queue.insert(insert_index, job.duplicate(true))

func _make_room_for_player_dialog_job(max_queue_size: int) -> void:
	if max_queue_size <= 0:
		return
	while _job_queue.size() >= max_queue_size:
		var removed_index := -1
		for idx in range(_job_queue.size() - 1, -1, -1):
			var queued_variant: Variant = _job_queue[idx]
			if queued_variant is not Dictionary:
				continue
			var queued_job := queued_variant as Dictionary
			if str(queued_job.get("kind", "")) == "warmup":
				removed_index = idx
				break
		if removed_index < 0:
			return
		var removed_job_variant: Variant = _job_queue[removed_index]
		_job_queue.remove_at(removed_index)
		if removed_job_variant is Dictionary:
			var removed_job := removed_job_variant as Dictionary
			SimLogger.log_ai("[AI][PlayerDialog] Dropped queued warmup %s to prioritize direct dialog" % str(removed_job.get("model", removed_job.get("key", ""))))

func _pump_job_queue() -> void:
	if _job_in_flight:
		return
	if _job_queue.is_empty():
		if _status == "warming":
			_set_status("ready", "models_warm")
		return
	if _status not in ["ready", "warming"]:
		return
	_current_job = (_job_queue.pop_front() as Dictionary).duplicate(true)
	_job_in_flight = true
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _job_request.request(
		_get_api_url("/generate"),
		headers,
		HTTPClient.METHOD_POST,
		str(_current_job.get("body", ""))
	)
	if err != OK:
		_job_in_flight = false
		_handle_job_failure(_current_job, "request_error_%d" % err)
		_current_job = {}
		_pump_job_queue()

func _on_job_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var finished_job := _current_job.duplicate(true)
	_current_job = {}
	_job_in_flight = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_handle_job_failure(finished_job, "http_%d_result_%d" % [response_code, result])
		_pump_job_queue()
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if finished_job.is_empty():
		_pump_job_queue()
		return

	match str(finished_job.get("kind", "")):
		"warmup":
			pass
		"npc_npc":
			_handle_npc_job_success(finished_job, parsed)
		"player_npc":
			_handle_player_job_success(finished_job, parsed)
		_:
			pass

	_pump_job_queue()

func _handle_npc_job_success(job: Dictionary, parsed: Variant) -> void:
	var conversation_id := str(job.get("key", ""))
	var payload := (job.get("payload", {}) as Dictionary).duplicate(true)
	var raw_text := _extract_response_text(parsed)
	SimLogger.log_ai("[AI][NPCDialog] Raw response key=%s:\n%s" % [conversation_id, raw_text])
	var lines := _normalize_npc_lines(raw_text, payload)
	_npc_cache[conversation_id] = {
		"state": "ready",
		"source": "ollama",
		"model": str(job.get("model", "")),
		"lines": lines
	}
	_pending_keys.erase(conversation_id)
	SimLogger.log_ai("[AI][NPCDialog] Job ready key=%s model=%s lines=%d" % [conversation_id, str(job.get("model", "")), lines.size()])
	npc_dialogue_ready.emit(conversation_id)

func _handle_player_job_success(job: Dictionary, parsed: Variant) -> void:
	var session_id := str(job.get("key", ""))
	var payload := (job.get("payload", {}) as Dictionary).duplicate(true)
	var raw_text := _extract_response_text(parsed)
	SimLogger.log_ai("[AI][PlayerDialog] Raw response key=%s:\n%s" % [session_id, raw_text])
	var reply_data := _normalize_player_reply_result(raw_text, payload)
	_player_cache[session_id] = {
		"state": "ready",
		"source": "ollama",
		"model": str(job.get("model", "")),
		"text": str(reply_data.get("text", "")),
		"mood": str(reply_data.get("mood", "")),
		"intent": str(reply_data.get("intent", ""))
	}
	_pending_keys.erase(session_id)
	SimLogger.log_ai("[AI][PlayerDialog] Job ready key=%s model=%s" % [session_id, str(job.get("model", ""))])
	player_dialogue_ready.emit(session_id)

func _handle_job_failure(job: Dictionary, reason: String) -> void:
	var kind := str(job.get("kind", ""))
	if kind == "warmup":
		SimLogger.log_ai("[AI] Warmup failed for %s: %s" % [str(job.get("model", "")), reason])
		return
	if kind == "npc_npc":
		var key := str(job.get("key", ""))
		var payload := (job.get("payload", {}) as Dictionary).duplicate(true)
		_npc_cache[key] = _build_npc_template_block(key, payload, reason)
		_pending_keys.erase(key)
		SimLogger.log_ai("[AI][NPCDialog] Job failed key=%s reason=%s" % [key, reason])
		npc_dialogue_ready.emit(key)
		return
	if kind == "player_npc":
		var session_id := str(job.get("key", ""))
		var player_payload := (job.get("payload", {}) as Dictionary).duplicate(true)
		_player_cache[session_id] = _build_player_template_reply(session_id, player_payload, reason)
		_pending_keys.erase(session_id)
		SimLogger.log_ai("[AI][PlayerDialog] Job failed key=%s reason=%s" % [session_id, reason])
		player_dialogue_ready.emit(session_id)

func _schedule_probe_retry(detail: String) -> void:
	if not _backend_process_started and _get_bool("startup.auto_start_backend_if_missing", true):
		_try_start_backend_process()
		if _backend_process_started:
			detail = "starting_local_backend"
	_set_status("starting", detail)
	_probe_retry_left = _get_float("startup.retry_probe_interval_sec", 1.5)

func _extract_response_text(parsed: Variant) -> String:
	if parsed is not Dictionary:
		return ""
	return str((parsed as Dictionary).get("response", "")).strip_edges()

func _should_use_template_fallback(model: String) -> bool:
	if _get_bool("runtime.force_template_mode", false):
		return true
	if _status not in ["ready", "warming"]:
		return true
	return model.is_empty()

func _build_generate_request_parts(profile: String, model: String, payload: Dictionary) -> Dictionary:
	var system_lines := _get_string_array("prompt_templates.%s.system" % profile)
	var prompt_text := _build_prompt(profile, payload)
	var system_text := "\n".join(system_lines)
	var request_body := {
		"model": model,
		"prompt": prompt_text,
		"system": system_text,
		"stream": false,
		"keep_alive": _get_string("startup.prewarm_keep_alive", "10m"),
		"options": _build_profile_request_options(profile)
	}
	var response_format := _get_string("runtime_profiles.%s.format" % profile, _get_string("runtime.format", ""))
	if not response_format.is_empty():
		request_body["format"] = response_format
	return {
		"prompt_text": prompt_text,
		"system_text": system_text,
		"body_json": JSON.stringify(request_body)
	}

func _build_profile_request_options(profile: String) -> Dictionary:
	var options := {
		"temperature": _get_float("runtime.temperature", 0.35),
		"num_predict": _get_int("runtime.num_predict", 70)
	}
	var profile_options: Variant = _get_value("runtime_profiles.%s.options" % profile, {})
	if profile_options is Dictionary:
		for key in (profile_options as Dictionary).keys():
			options[key] = (profile_options as Dictionary)[key]
	return options

func _log_generation_request(kind_label: String, key: String, profile: String, model: String, request_data: Dictionary) -> void:
	var system_text := str(request_data.get("system_text", ""))
	var prompt_text := str(request_data.get("prompt_text", ""))
	var body_json := str(request_data.get("body_json", ""))
	SimLogger.log_ai("[AI][%s] Request key=%s profile=%s model=%s" % [kind_label, key, profile, model])
	SimLogger.log_ai("[AI][%s] System Prompt:\n%s" % [kind_label, system_text])
	SimLogger.log_ai("[AI][%s] User Prompt:\n%s" % [kind_label, prompt_text])
	SimLogger.log_ai("[AI][%s] Request Body:\n%s" % [kind_label, body_json])

func _build_prompt(profile: String, payload: Dictionary) -> String:
	var lines: Array[String] = []
	for raw_field in _get_string_array("prompt_templates.%s.input_fields" % profile):
		var field_name := str(raw_field)
		if not payload.has(field_name):
			continue
		lines.append("%s: %s" % [field_name, _stringify_prompt_field(profile, field_name, payload[field_name])])
	if profile == "npc_npc":
		lines.append("Output JSON with key lines, where lines is an array of 2 to 4 short dialogue lines.")
		lines.append("Each line must use the format 'Name: text'.")
	elif profile == "player_npc":
		var reply_language := str(payload.get("reply_language", _get_string("runtime_profiles.%s.force_reply_language" % profile, ""))).strip_edges()
		if not reply_language.is_empty():
			lines.append("Reply language: %s." % reply_language)
		lines.append("Reply with one short natural answer in character.")
		lines.append("Answer only with the spoken reply text.")
		lines.append("No JSON. No speaker name. No narration.")
		if _player_dialog_has_farewell(payload):
			lines.append("The player is ending the conversation. Reply with one brief goodbye only.")
		if bool(payload.get("player_flagged_repetition", false)):
			lines.append("The player said you are repeating yourself. Acknowledge that briefly once, then answer in a different way.")
		lines.append("Do not just repeat mood or current_goal unless the player asked about them.")
	return "\n".join(lines)

func _stringify_prompt_field(profile: String, field_name: String, value: Variant) -> String:
	if profile == "player_npc":
		match field_name:
			"needs":
				return _stringify_player_needs(value)
			"state_hints":
				return _stringify_prompt_list(value, 3)
			"nearby_places":
				return _stringify_prompt_places(value, 2)
			"known_places":
				return _stringify_prompt_places(value, 4)
			"last_turns":
				return _stringify_prompt_turns(value, 3)
			"recent_summary":
				return _truncate_prompt_text(str(value), 140)
			"player_flagged_repetition":
				return "yes" if bool(value) else "no"
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	return str(value)

func _stringify_player_needs(value: Variant) -> String:
	if value is not Dictionary:
		return str(value)
	var typed_value := value as Dictionary
	return "hunger=%s energy=%s fun=%s health=%s" % [
		str(typed_value.get("hunger", "")),
		str(typed_value.get("energy", "")),
		str(typed_value.get("fun", "")),
		str(typed_value.get("health", ""))
	]

func _stringify_prompt_list(value: Variant, max_items: int) -> String:
	if value is not Array:
		return str(value)
	var parts: Array[String] = []
	for item in value as Array:
		var text := str(item).strip_edges()
		if text.is_empty():
			continue
		parts.append(text)
		if parts.size() >= max_items:
			break
	return ", ".join(parts)

func _stringify_prompt_places(value: Variant, max_places: int) -> String:
	var places := _extract_dialogue_places(value)
	if places.is_empty():
		return "-"
	var parts: Array[String] = []
	for place in places:
		var name := str(place.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		parts.append(name)
		if parts.size() >= max_places:
			break
	return ", ".join(parts) if not parts.is_empty() else "-"

func _stringify_prompt_turns(value: Variant, max_turns: int) -> String:
	if value is not Array:
		return str(value)
	var raw_turns := value as Array
	var start_index := maxi(raw_turns.size() - max_turns, 0)
	var parts: Array[String] = []
	for idx in range(start_index, raw_turns.size()):
		var turn_variant: Variant = raw_turns[idx]
		if turn_variant is not Dictionary:
			continue
		var turn := turn_variant as Dictionary
		var speaker := str(turn.get("speaker", "")).strip_edges()
		var text := str(turn.get("text", "")).replace("\r", " ").replace("\n", " ").strip_edges()
		if speaker.is_empty() or text.is_empty():
			continue
		parts.append("%s: %s" % [speaker, text])
	return " | ".join(parts) if not parts.is_empty() else "-"

func _truncate_prompt_text(text: String, max_length: int) -> String:
	var normalized := text.replace("\r", " ").replace("\n", " ").strip_edges()
	if normalized.length() <= max_length:
		return normalized
	return normalized.substr(0, max_length).strip_edges()

func _stringify_prompt_value(value: Variant) -> String:
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	return str(value)

func _normalize_npc_lines(raw_text: String, payload: Dictionary) -> Array[String]:
	var parsed: Variant = JSON.parse_string(raw_text)
	var lines: Array[String] = []
	if parsed is Dictionary:
		var raw_lines: Variant = (parsed as Dictionary).get("lines", [])
		if raw_lines is Array:
			for raw_line in raw_lines:
				var line := _normalize_npc_line(str(raw_line), payload)
				if not line.is_empty():
					lines.append(line)
	if lines.is_empty():
		for raw_line in raw_text.split("\n", false):
			var line := _normalize_npc_line(raw_line, payload)
			if not line.is_empty():
				lines.append(line)
	if lines.is_empty():
		lines = _build_template_lines_from_payload(payload)
	var max_lines := _get_int("output_rules.npc_npc.max_lines", 4)
	if lines.size() > max_lines:
		lines.resize(max_lines)
	return lines

func _normalize_npc_line(raw_line: String, payload: Dictionary) -> String:
	var line := raw_line.strip_edges()
	if line.is_empty():
		return ""
	if not line.contains(":"):
		var fallback_names := _get_npc_participant_names(payload)
		var speaker := fallback_names[0] if not fallback_names.is_empty() else "Citizen"
		line = "%s: %s" % [speaker, line]
	var max_words := _get_int("output_rules.npc_npc.max_words_per_line", 18)
	var parts := line.split(" ", false)
	if parts.size() <= max_words:
		return line
	return " ".join(parts.slice(0, max_words))

func _normalize_player_reply_result(raw_text: String, payload: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw_text)
	var reply_text := ""
	var reply_mood := ""
	var reply_intent := ""
	if parsed is Dictionary:
		var parsed_reply := parsed as Dictionary
		reply_text = str(parsed_reply.get("reply", parsed_reply.get("text", ""))).strip_edges()
		reply_mood = str(parsed_reply.get("mood", "")).strip_edges()
		reply_intent = str(parsed_reply.get("intent", "")).strip_edges()
	if reply_text.is_empty():
		reply_text = raw_text
	reply_text = _normalize_player_reply_text(reply_text, payload)
	if _is_effectively_same_reply(reply_text, str(payload.get("last_npc_reply", ""))):
		reply_text = _build_player_repeat_recovery_reply(payload)
		if reply_intent.is_empty():
			reply_intent = "clarify_without_repeating"
	return {
		"text": reply_text,
		"mood": reply_mood,
		"intent": reply_intent
	}

func _normalize_player_reply_text(raw_text: String, payload: Dictionary) -> String:
	var reply := raw_text.strip_edges()
	reply = _strip_player_reply_prefix(reply, payload)
	if reply.is_empty():
		return str(_build_player_template_reply("fallback", payload, "empty_response").get("text", ""))
	reply = reply.replace("\r", " ").replace("\n", " ").strip_edges()
	reply = _truncate_player_reply_sentences(reply)
	var max_words := _get_int("output_rules.player_npc.max_words", 60)
	var words := reply.split(" ", false)
	if words.size() > max_words:
		reply = " ".join(words.slice(0, max_words))
	return reply

func _is_effectively_same_reply(candidate: String, previous_reply: String) -> bool:
	var normalized_candidate := _normalize_dialogue_compare_text(candidate)
	var normalized_previous := _normalize_dialogue_compare_text(previous_reply)
	return not normalized_candidate.is_empty() and normalized_candidate == normalized_previous

func _normalize_dialogue_compare_text(text: String) -> String:
	var normalized := text.to_lower().strip_edges()
	for marker in [".", ",", "!", "?", ":", ";", "\"", "'", "(", ")", "[", "]", "{", "}"]:
		normalized = normalized.replace(marker, " ")
	return " ".join(normalized.split(" ", false))

func _strip_player_reply_prefix(reply: String, payload: Dictionary) -> String:
	var normalized := reply.strip_edges()
	if normalized.is_empty():
		return normalized
	var citizen_name := str(payload.get("name", "")).strip_edges()
	if not citizen_name.is_empty():
		var prefix := "%s:" % citizen_name
		if normalized.begins_with(prefix):
			return normalized.trim_prefix(prefix).strip_edges()
	if normalized.to_lower().begins_with("npc:"):
		return normalized.substr(4).strip_edges()
	return normalized

func _truncate_player_reply_sentences(reply: String) -> String:
	var max_sentences := maxi(_get_int("output_rules.player_npc.max_sentences", 2), 1)
	var trimmed := reply.strip_edges()
	if trimmed.is_empty():
		return trimmed
	var sentence_count := 0
	for idx in range(trimmed.length()):
		var ch := trimmed[idx]
		if ch == "." or ch == "!" or ch == "?":
			sentence_count += 1
			if sentence_count >= max_sentences:
				return trimmed.substr(0, idx + 1).strip_edges()
	return trimmed

func _build_npc_template_block(_conversation_id: String, payload: Dictionary, reason: String) -> Dictionary:
	return {
		"state": "ready",
		"source": "template",
		"reason": reason,
		"lines": _build_template_lines_from_payload(payload)
	}

func _build_player_template_reply(session_id: String, payload: Dictionary, reason: String) -> Dictionary:
	var reply_text := _build_player_template_reply_text_grounded(session_id, payload)
	var reply_intent := "farewell" if _player_dialog_has_farewell(payload) else "reply"
	if bool(payload.get("player_flagged_repetition", false)):
		reply_intent = "clarify_without_repeating"
	return {
		"state": "ready",
		"source": "template",
		"reason": reason,
		"text": reply_text,
		"mood": str(payload.get("mood", "")),
		"intent": reply_intent
	}

func _build_player_template_reply_text(session_id: String, payload: Dictionary) -> String:
	var mood := str(payload.get("mood", "calm"))
	var current_goal := str(payload.get("current_goal", "getting through the day"))
	var location := str(payload.get("location", "around town"))
	var recent_summary := str(payload.get("recent_summary", "")).strip_edges()
	var last_player_line := _get_last_player_line(payload)
	var lower_line := last_player_line.to_lower()
	var prefer_german := _should_reply_in_german(payload, lower_line, recent_summary)
	var mood_text := _humanize_dialogue_mood(mood, prefer_german)
	var goal_text := _humanize_dialogue_goal(current_goal, prefer_german)

	if _matches_any(lower_line, ["hallo", "hi", "hey", "hello", "moin", "servus"]):
		return "Hallo." if prefer_german else "Hey."
	if _matches_any(lower_line, ["wie geht", "alles gut", "how are you", "you doing"]):
		return "Ganz okay. Ich bin eher %s." % mood_text if prefer_german else "Doing alright. I'm feeling %s." % mood_text
	if _matches_any(lower_line, ["warum", "wieso", "why"]):
		return "Weil ich gerade an %s denke." % goal_text if prefer_german else "Because %s is on my mind right now." % goal_text
	if _matches_any(lower_line, ["wo bist", "wo seid", "where are you"]):
		return "Ich bin gerade bei %s." % location if prefer_german else "I'm around %s right now." % location
	if _matches_any(lower_line, ["wohin", "wo gehst", "where are you going", "where to"]):
		return "Ich bin gerade auf dem Weg zu %s." % goal_text if prefer_german else "I'm heading to %s right now." % goal_text
	if _matches_any(lower_line, ["wer bist", "wie heißt", "who are you", "your name"]):
		return "Ich bin nur unterwegs und versuche, meinen Tag hinzubekommen." if prefer_german else "Just someone trying to get through the day around here."
	if not recent_summary.is_empty():
		return "Wir haben ja schon kurz geredet. Ich bin eher %s." % mood_text if prefer_german else "We already talked a bit. I'm feeling %s." % mood_text

	var variant_index: int = abs((session_id + "|" + lower_line + "|" + goal_text).hash()) % 3
	match variant_index:
		0:
			return "Ich bin gerade %s und konzentriere mich auf %s." % [mood_text, goal_text] if prefer_german else "I'm %s right now and focused on %s." % [mood_text, goal_text]
		1:
			return "Heute ist etwas viel los. Ich will erstmal zu %s." % goal_text if prefer_german else "It's a bit busy today. I'm trying to get to %s first." % goal_text
		_:
			return "Im Moment bin ich bei %s und eher %s." % [location, mood_text] if prefer_german else "Right now I'm around %s and feeling %s." % [location, mood_text]

func _build_player_template_reply_text_grounded(session_id: String, payload: Dictionary) -> String:
	var citizen_name := str(payload.get("name", "Citizen")).strip_edges()
	var mood := str(payload.get("mood", "calm"))
	var current_goal := str(payload.get("current_goal", "getting through the day"))
	var location := str(payload.get("location", "around town"))
	var district := str(payload.get("district", "")).strip_edges()
	var recent_summary := str(payload.get("recent_summary", "")).strip_edges()
	var last_player_line := _get_last_player_line(payload)
	var lower_line := last_player_line.to_lower()
	var prefer_german := _should_reply_in_german(payload, lower_line, recent_summary)
	var mood_text := _humanize_dialogue_mood(mood, prefer_german)
	var goal_text := _humanize_dialogue_goal(current_goal, prefer_german)
	var nearby_places := _extract_dialogue_places(payload.get("nearby_places", []))
	var known_places := _extract_dialogue_places(payload.get("known_places", []))
	var food_place := _find_dialogue_place_by_services(nearby_places, ["food", "food_market"])
	if food_place.is_empty():
		food_place = _find_dialogue_place_by_services(known_places, ["food", "food_market"])
	if _player_dialog_has_farewell(payload):
		return "Bis spaeter." if prefer_german else "See you around."
	if bool(payload.get("player_flagged_repetition", false)):
		return _build_player_repeat_recovery_reply(payload)

	if _matches_any(lower_line, ["hallo", "hi", "hey", "hello", "moin", "servus"]):
		return "Hallo." if prefer_german else "Hey."
	if _matches_any(lower_line, ["wie geht", "alles gut", "how are you", "you doing"]):
		return "Ganz okay. Ich bin eher %s." % mood_text if prefer_german else "Doing alright. I'm feeling %s." % mood_text
	if _matches_any(lower_line, ["warum", "wieso", "why"]):
		return "Weil ich gerade an %s denke." % goal_text if prefer_german else "Because %s is on my mind right now." % goal_text
	if _matches_any(lower_line, ["wo bist", "wo seid", "where are you"]):
		if not district.is_empty():
			return "Ich bin gerade bei %s im Bereich %s." % [location, district] if prefer_german else "I'm around %s in %s right now." % [location, district]
		return "Ich bin gerade bei %s." % location if prefer_german else "I'm around %s right now." % location
	if _matches_any(lower_line, ["wohin", "wo gehst", "where are you going", "where to"]):
		return "Ich bin gerade auf dem Weg zu %s." % goal_text if prefer_german else "I'm heading to %s right now." % goal_text
	if _matches_any(lower_line, ["essen", "eat", "food", "restaurant", "hungry"]):
		if not food_place.is_empty():
			var food_name := str(food_place.get("name", ""))
			return "Wenn es passt, dann eher zu %s." % food_name if prefer_german else "If it works out, I'd rather go to %s." % food_name
		return "Ich wuerde lieber etwas in der Naehe suchen." if prefer_german else "I'd rather find something nearby."
	if _matches_any(lower_line, ["deutsch", "german", "englisch", "english", "sprichst", "sprich", "language"]):
		return "Ja, klar. Wir koennen Deutsch reden." if prefer_german else "Yeah, sure. We can talk in English."
	if _matches_any(lower_line, ["wer bist", "wie heißt", "wie heisst", "who are you", "your name"]):
		return "Ich bin nur unterwegs und versuche, meinen Tag hinzubekommen." if prefer_german else "Just someone trying to get through the day around here."
	if not recent_summary.is_empty():
		return "Wir haben ja schon kurz geredet. Ich bin eher %s." % mood_text if prefer_german else "We already talked a bit. I'm feeling %s." % mood_text

	var variant_index: int = abs((session_id + "|" + lower_line + "|" + goal_text).hash()) % 3
	match variant_index:
		0:
			return "Ich bin gerade %s und konzentriere mich auf %s." % [mood_text, goal_text] if prefer_german else "I'm %s right now and focused on %s." % [mood_text, goal_text]
		1:
			return "Heute ist etwas viel los. Ich will erstmal zu %s." % goal_text if prefer_german else "It's a bit busy today. I'm trying to get to %s first." % goal_text
		_:
			if not district.is_empty():
				return "Im Moment bin ich bei %s in %s und eher %s." % [location, district, mood_text] if prefer_german else "Right now I'm around %s in %s and feeling %s." % [location, district, mood_text]
			return "Im Moment bin ich bei %s und eher %s." % [location, mood_text] if prefer_german else "Right now I'm around %s and feeling %s." % [location, mood_text]

func _build_player_repeat_recovery_reply(payload: Dictionary) -> String:
	var last_player_line := _get_last_player_line(payload)
	var lower_line := last_player_line.to_lower()
	var prefer_german := _should_reply_in_german(payload, lower_line, str(payload.get("recent_summary", "")))
	var mood_text := _humanize_dialogue_mood(str(payload.get("mood", "calm")), prefer_german)
	var goal_text := _humanize_dialogue_goal(str(payload.get("current_goal", "getting through the day")), prefer_german)
	var location := str(payload.get("location", "hier")).strip_edges()
	if _matches_any(lower_line, ["wohin", "wo gehst", "where are you going", "where to"]):
		return "Stimmt, ich hab mich wiederholt. Kurz gesagt: Ich will gerade zu %s." % goal_text if prefer_german else "Right, I repeated myself. Short version: I'm heading to %s." % goal_text
	if _matches_any(lower_line, ["wo bist", "where are you"]):
		return "Stimmt, doppelt gesagt. Ich bin gerade bei %s." % location if prefer_german else "Right, that was repetitive. I'm around %s right now." % location
	if _matches_any(lower_line, ["wie geht", "how are you"]):
		return "Stimmt, das klang doppelt. Ehrlich gesagt bin ich eher %s." % mood_text if prefer_german else "Right, that sounded repetitive. Honestly I'm feeling %s." % mood_text
	return "Stimmt, ich hab mich wiederholt. Kurz gesagt: Ich bin eher %s und denke gerade an %s." % [mood_text, goal_text] if prefer_german else "Right, I repeated myself. Short version: I'm feeling %s and thinking about %s." % [mood_text, goal_text]

func _get_last_player_line(payload: Dictionary) -> String:
	var raw_turns: Variant = payload.get("last_turns", [])
	if raw_turns is not Array:
		return ""
	var turns := raw_turns as Array
	for idx in range(turns.size() - 1, -1, -1):
		var turn: Variant = turns[idx]
		if turn is not Dictionary:
			continue
		var typed_turn := turn as Dictionary
		if str(typed_turn.get("speaker", "")).to_lower() != "player":
			continue
		return str(typed_turn.get("text", "")).strip_edges()
	return ""

func _prefers_german_reply(last_player_line_lower: String, recent_summary: String) -> bool:
	if _matches_any(last_player_line_lower, ["hallo", "wie ", "warum", "wieso", "wo ", "wohin", "wer ", "heißt", "geht", "bist", "seid"]):
		return true
	var lower_summary := recent_summary.to_lower()
	return _matches_any(lower_summary, [" und ", " mit ", " bei ", " heute ", " gerade "])

func _should_reply_in_german(payload: Dictionary, last_player_line_lower: String, recent_summary: String) -> bool:
	var reply_language := str(payload.get("reply_language", "")).to_lower().strip_edges()
	if reply_language == "german":
		return true
	if reply_language == "english":
		return false
	return _prefers_german_reply(last_player_line_lower, recent_summary)

func _player_dialog_has_farewell(payload: Dictionary) -> bool:
	var last_player_line := _get_last_player_line(payload).to_lower().strip_edges()
	if last_player_line.is_empty():
		return false
	return _matches_any(last_player_line, ["bye", "goodbye", "see you", "ciao", "tschuess", "tschuss", "bis spaeter", "bis bald", "machs gut", "cu"])

func _humanize_dialogue_mood(mood: String, prefer_german: bool) -> String:
	var lower_mood := mood.to_lower().strip_edges()
	match lower_mood:
		"calm":
			return "ruhig" if prefer_german else "calm"
		"exhausted":
			return "ziemlich muede" if prefer_german else "pretty tired"
		"tired":
			return "muede" if prefer_german else "tired"
		"hungry":
			return "hungrig" if prefer_german else "hungry"
		"stressed":
			return "gestresst" if prefer_german else "stressed"
		"frustrated":
			return "genervt" if prefer_german else "frustrated"
		"happy":
			return "gut drauf" if prefer_german else "in a good mood"
		_:
			return lower_mood if not lower_mood.is_empty() else ("ruhig" if prefer_german else "calm")

func _humanize_dialogue_goal(current_goal: String, prefer_german: bool) -> String:
	var goal := current_goal.strip_edges()
	if goal.is_empty():
		return "meinen Tag" if prefer_german else "my day"
	if goal.begins_with("GoTo -> "):
		var target := goal.trim_prefix("GoTo -> ").strip_edges()
		return target if not target.is_empty() else ("irgendwohin" if prefer_german else "somewhere")
	if goal == "travelling":
		return "irgendwohin" if prefer_german else "somewhere"
	return goal

func _matches_any(text: String, needles: Array[String]) -> bool:
	if text.is_empty():
		return false
	for needle in needles:
		if text.contains(needle):
			return true
	return false

func _extract_dialogue_places(raw_places: Variant) -> Array[Dictionary]:
	var places: Array[Dictionary] = []
	if raw_places is not Array:
		return places
	for raw_place in raw_places:
		if raw_place is not Dictionary:
			continue
		places.append((raw_place as Dictionary).duplicate(true))
	return places

func _find_dialogue_place_by_services(places: Array[Dictionary], services: Array[String]) -> Dictionary:
	for place in places:
		var service := str(place.get("service", "")).strip_edges()
		if services.has(service):
			return place
	return {}

func _build_template_lines_from_payload(payload: Dictionary) -> Array[String]:
	var names := _get_npc_participant_names(payload)
	var speaker_a := names[0] if names.size() > 0 else "Citizen A"
	var speaker_b := names[1] if names.size() > 1 else "Citizen B"
	var topic := str(payload.get("topic", "the day"))
	var location := str(payload.get("location", "the street"))
	return [
		"%s: Busy day around %s." % [speaker_a, location],
		"%s: Yeah, especially with %s on my mind." % [speaker_b, topic]
	]

func _get_npc_participant_names(payload: Dictionary) -> Array[String]:
	var names: Array[String] = []
	var participant_a: Variant = payload.get("participant_a", {})
	var participant_b: Variant = payload.get("participant_b", {})
	if participant_a is Dictionary:
		var name_a := str((participant_a as Dictionary).get("name", ""))
		if not name_a.is_empty():
			names.append(name_a)
	if participant_b is Dictionary:
		var name_b := str((participant_b as Dictionary).get("name", ""))
		if not name_b.is_empty():
			names.append(name_b)
	return names

func _load_config(config_override: Dictionary) -> Dictionary:
	var defaults := {
		"runtime": {
			"provider": "local",
			"backend": "ollama_or_llama_cpp",
			"max_parallel_jobs": 1,
			"max_queue_size": 2,
			"request_timeout_sec": 8.0,
			"cancel_if_player_leaves_range": true,
			"temperature": 0.35,
			"num_predict": 70,
			"force_template_mode": false
		},
		"runtime_profiles": {
			"player_npc": {
				"profile_model_name": "npc-player:latest",
				"format": "",
				"force_reply_language": "german",
				"options": {
					"temperature": 0.25,
					"top_p": 0.8,
					"top_k": 24,
					"min_p": 0.05,
					"repeat_penalty": 1.15,
					"repeat_last_n": 48,
					"num_ctx": 1024,
					"num_predict": 40,
					"seed": 42
				}
			},
			"npc_npc": {
				"profile_model_name": "npc-overheard:latest",
				"format": "json",
				"options": {
					"temperature": 0.25,
					"top_p": 0.8,
					"top_k": 20,
					"min_p": 0.08,
					"repeat_penalty": 1.1,
					"repeat_last_n": 48,
					"num_ctx": 1024,
					"num_predict": 50,
					"seed": 42
				}
			}
		},
		"startup": {
			"backend_kind": "ollama",
			"api_base_url": "http://127.0.0.1:11434/api",
			"auto_start_on_game_boot": true,
			"auto_start_backend_if_missing": true,
			"disabled_in_headless": true,
			"retry_probe_interval_sec": 1.5,
			"prewarm_on_boot": true,
			"prewarm_keep_alive": "10m",
			"warmup_prompt": "Hello.",
			"serve_args": ["serve"],
			"command_candidates": [
				"{AI_LLAMA_DIR}\\ollama.exe",
				"ollama",
				"{LOCALAPPDATA}\\Programs\\Ollama\\ollama.exe"
			]
		},
		"packaging": {
			"ai_root_dir": "{PROJECT_DIR}\\AI",
			"llama_dir": "{AI_ROOT_DIR}\\llama",
			"models_dir": "{AI_ROOT_DIR}\\models",
			"runtime_dir": "{AI_ROOT_DIR}\\runtime",
			"ensure_directories_on_boot": true,
			"prefer_project_local_runtime": true
		},
		"model_preferences": {
			"player_npc": ["qwen2.5:3b"],
			"npc_npc": ["llama3.2:3b"]
		},
		"prompt_templates": {
			"player_npc": {
				"system": [
					"You are a local NPC in a city simulation.",
					"Stay in character.",
					"Only know what the citizen could reasonably know.",
					"Reply with one short natural spoken answer in everyday German.",
					"Do not sound like a helpful assistant or customer support.",
					"No JSON. No speaker prefix. No narration.",
					"Use only provided world facts and ordinary local knowledge.",
					"Do not invent additional landmarks, districts, shops, or routes.",
					"Respect needs literally: high hunger means hungry, low energy means tired.",
					"All spoken dialogue must be in natural German.",
					"If unsure, briefly say you are not sure."
				],
				"input_fields": [
					"name",
					"mood",
					"needs",
					"state_hints",
					"location",
					"district",
					"current_goal",
					"nearby_places",
					"reply_language",
					"player_flagged_repetition",
					"recent_summary",
					"last_turns"
				]
			},
			"npc_npc": {
				"system": [],
				"input_fields": []
			}
		},
		"output_rules": {
			"player_npc": {
				"max_sentences": 2,
				"max_words": 24
			},
			"npc_npc": {
				"max_lines": 4,
				"max_words_per_line": 18
			}
		},
		"memory": {
			"player_npc": {
				"keep_last_turns": 4,
				"summarize_after_turns": 3,
				"keep_world_facts_short": true
			},
			"npc_npc": {
				"cache_generated_block": true,
				"reuse_until_topic_changes": true
			}
		},
		"fallback": {
			"on_queue_full": "use_template"
		}
	}
	if FileAccess.file_exists(CONFIG_PATH):
		var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_deep_merge(defaults, parsed as Dictionary)
	_deep_merge(defaults, config_override)
	return defaults

func _deep_merge(base: Dictionary, override: Dictionary) -> void:
	for key in override.keys():
		var override_value: Variant = override[key]
		if base.has(key) and base[key] is Dictionary and override_value is Dictionary:
			_deep_merge(base[key], override_value)
		else:
			base[key] = override_value

func _set_status(status: String, detail: String) -> void:
	if _status == status and _status_detail == detail:
		return
	_status = status
	_status_detail = detail
	status_changed.emit(_status, _status_detail)
	SimLogger.log_ai("[AI] Runtime status: %s (%s)" % [_status, _status_detail])

func _get_api_url(path: String) -> String:
	var base_url := _get_string("startup.api_base_url", "http://127.0.0.1:11434/api").trim_suffix("/")
	return "%s%s" % [base_url, path]

func _get_profile_model(profile: String) -> String:
	return str(_models_by_profile.get(profile, ""))

func _get_selected_model_names() -> Array[String]:
	var models: Array[String] = []
	for model_name in _models_by_profile.values():
		var normalized := str(model_name)
		if normalized.is_empty() or models.has(normalized):
			continue
		models.append(normalized)
	return models

func _get_recommended_setup_model() -> String:
	for profile_name in ["player_npc", "npc_npc"]:
		var candidates := _get_string_array("model_preferences.%s" % profile_name)
		for candidate in candidates:
			if not candidate.is_empty():
				return candidate
	return ""

func _prepare_local_runtime_layout() -> void:
	_resolved_paths = _resolve_runtime_paths()
	if _get_bool("packaging.ensure_directories_on_boot", true):
		for key in ["ai_root_dir", "llama_dir", "models_dir", "runtime_dir"]:
			_ensure_absolute_dir(str(_resolved_paths.get(key, "")))
	var models_dir := str(_resolved_paths.get("models_dir", ""))
	if not models_dir.is_empty():
		OS.set_environment("OLLAMA_MODELS", models_dir)
	var host := _get_ollama_host()
	if not host.is_empty():
		OS.set_environment("OLLAMA_HOST", host)

func _resolve_runtime_paths() -> Dictionary:
	var paths := {
		"project_dir": ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	}
	paths["ai_root_dir"] = _normalize_absolute_path(_expand_runtime_tokens(_get_string("packaging.ai_root_dir", "{PROJECT_DIR}\\AI"), paths))
	paths["llama_dir"] = _normalize_absolute_path(_expand_runtime_tokens(_get_string("packaging.llama_dir", "{AI_ROOT_DIR}\\llama"), paths))
	paths["models_dir"] = _normalize_absolute_path(_expand_runtime_tokens(_get_string("packaging.models_dir", "{AI_ROOT_DIR}\\models"), paths))
	paths["runtime_dir"] = _normalize_absolute_path(_expand_runtime_tokens(_get_string("packaging.runtime_dir", "{AI_ROOT_DIR}\\runtime"), paths))
	return paths

func _expand_runtime_tokens(raw_value: String, extra_tokens: Dictionary = {}) -> String:
	var expanded := str(raw_value)
	var tokens := {
		"PROJECT_DIR": ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\"),
		"LOCALAPPDATA": OS.get_environment("LOCALAPPDATA"),
		"PROGRAMFILES": OS.get_environment("PROGRAMFILES"),
		"PROGRAMFILES_X86": OS.get_environment("PROGRAMFILES(X86)"),
		"AI_ROOT_DIR": str(_resolved_paths.get("ai_root_dir", "")),
		"AI_LLAMA_DIR": str(_resolved_paths.get("llama_dir", "")),
		"AI_MODELS_DIR": str(_resolved_paths.get("models_dir", "")),
		"AI_RUNTIME_DIR": str(_resolved_paths.get("runtime_dir", ""))
	}
	for token_key in extra_tokens.keys():
		tokens[str(token_key).to_upper()] = str(extra_tokens[token_key])
	for token_key in tokens.keys():
		expanded = expanded.replace("{%s}" % str(token_key), str(tokens[token_key]))
	return _normalize_absolute_path(expanded)

func _normalize_absolute_path(path: String) -> String:
	var normalized := str(path).replace("/", "\\").strip_edges()
	if normalized.is_empty():
		return ""
	return normalized.simplify_path()

func _ensure_absolute_dir(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path)

func _refresh_setup_process_state() -> void:
	if _setup_process_pid <= 0:
		return
	if OS.is_process_running(_setup_process_pid):
		return
	_setup_process_pid = -1
	if _status == "installing":
		_set_status("starting", "post_install_probe")
		_probe_retry_left = 0.0

func _has_local_runtime_binary() -> bool:
	return FileAccess.file_exists(_get_local_runtime_binary_path())

func _get_local_runtime_binary_path() -> String:
	var llama_dir := str(_resolved_paths.get("llama_dir", ""))
	if llama_dir.is_empty():
		return ""
	return _normalize_absolute_path("%s\\ollama.exe" % llama_dir)

func _get_setup_script_path() -> String:
	var path := ProjectSettings.globalize_path("res://tools/install_portable_ollama.ps1")
	if FileAccess.file_exists(path):
		return path
	return ""

func _has_setup_script() -> bool:
	return not _get_setup_script_path().is_empty()

func _get_powershell_path() -> String:
	var windir := OS.get_environment("WINDIR")
	if not windir.is_empty():
		var candidate := _normalize_absolute_path("%s\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" % windir)
		if FileAccess.file_exists(candidate):
			return candidate
	if OS.get_name() == "Windows":
		return "powershell.exe"
	return ""

func _get_ollama_host() -> String:
	var base_url := _get_string("startup.api_base_url", "http://127.0.0.1:11434/api").strip_edges()
	if base_url.is_empty():
		return ""
	var trimmed := base_url
	if trimmed.begins_with("http://"):
		trimmed = trimmed.trim_prefix("http://")
	elif trimmed.begins_with("https://"):
		trimmed = trimmed.trim_prefix("https://")
	var slash_index := trimmed.find("/")
	if slash_index >= 0:
		trimmed = trimmed.substr(0, slash_index)
	return trimmed

func _get_value(path: String, default_value = null):
	var current: Variant = _config
	for part in path.split("."):
		if part.is_empty():
			continue
		if current is Dictionary and current.has(part):
			current = current[part]
			continue
		return default_value
	return current

func _get_bool(path: String, default_value: bool) -> bool:
	return bool(_get_value(path, default_value))

func _get_int(path: String, default_value: int) -> int:
	return int(_get_value(path, default_value))

func _get_float(path: String, default_value: float) -> float:
	return float(_get_value(path, default_value))

func _get_string(path: String, default_value: String) -> String:
	return str(_get_value(path, default_value))

func _get_string_array(path: String) -> Array[String]:
	var values: Array[String] = []
	var raw: Variant = _get_value(path, [])
	if raw is not Array:
		return values
	for entry in raw:
		values.append(str(entry))
	return values
