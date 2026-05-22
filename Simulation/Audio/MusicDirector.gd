extends Node
class_name MusicDirector

const BalanceConfig = preload("res://Simulation/Config/BalanceConfig.gd")

const MUSIC_ROOT := "res://environment/audio/music"
const MUSIC_BUS_NAME := "Music"
const SILENT_VOLUME_DB := -80.0
const MOOD_AMBIENT := &"ambient"
const MOOD_LIGHT := &"light"
const MOOD_NIGHT := &"night"
const MOOD_ACTION := &"action"

@export var base_volume_db: float = -12.0 # -18.0
@export var fade_seconds: float = 3.0

var _world: World = null
var _players: Array[AudioStreamPlayer] = []
var _playlists: Dictionary = {}
var _last_track_by_mood: Dictionary = {}
var _active_player_index: int = 0
var _active_mood: StringName = &""
var _active_track_path: String = ""
var _is_started: bool = false
var _is_enabled: bool = true
var _transition_tween: Tween = null
var _rng := RandomNumberGenerator.new()
var _night_start_hour: int = 22
var _day_start_hour: int = 6

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _is_headless_runtime():
		set_process(false)
		return

	_rng.randomize()
	_night_start_hour = clampi(BalanceConfig.get_int("schedule.night_start_hour", 22), 0, 23)
	_day_start_hour = clampi(BalanceConfig.get_int("schedule.day_start_hour", 6), 0, 23)
	_setup_players()
	_build_playlists()

func _exit_tree() -> void:
	_disconnect_world()
	stop()

func bind_world(world_ref: World) -> void:
	if _world == world_ref:
		return

	_disconnect_world()
	_world = world_ref
	_connect_world()

	if _is_started:
		_refresh_mood(true)

func start() -> void:
	if _is_headless_runtime() or not _is_enabled:
		return

	if _players.is_empty():
		_setup_players()
	if _playlists.is_empty():
		_build_playlists()

	_is_started = true
	_refresh_mood(false)

func stop() -> void:
	_is_started = false
	_active_mood = &""
	_active_track_path = ""
	_kill_transition()
	for player in _players:
		player.stop()
		player.stream = null
		player.volume_db = SILENT_VOLUME_DB

func set_enabled(enabled: bool) -> void:
	_is_enabled = enabled
	if not _is_enabled:
		stop()
	elif _world != null:
		start()

func set_volume_db(volume_db: float) -> void:
	base_volume_db = volume_db
	if _players.is_empty():
		return
	var active_player := _players[_active_player_index]
	if active_player.playing:
		active_player.volume_db = base_volume_db

func get_current_mood() -> StringName:
	return _active_mood

func get_current_track_path() -> String:
	return _active_track_path

func _connect_world() -> void:
	if _world == null or _world.time == null:
		return

	var hour_cb := Callable(self, "_on_world_hour_changed")
	if not _world.time.hour_changed.is_connected(hour_cb):
		_world.time.hour_changed.connect(hour_cb)

func _disconnect_world() -> void:
	if _world == null or _world.time == null:
		return

	var hour_cb := Callable(self, "_on_world_hour_changed")
	if _world.time.hour_changed.is_connected(hour_cb):
		_world.time.hour_changed.disconnect(hour_cb)

func _on_world_hour_changed(_hour: int) -> void:
	_refresh_mood(true)

func _refresh_mood(use_fade: bool) -> void:
	if not _is_started or not _is_enabled:
		return

	var desired_mood := _resolve_mood()
	if desired_mood == _active_mood and not _active_track_path.is_empty():
		return

	if _play_next_track_for_mood(desired_mood, use_fade):
		_active_mood = desired_mood

func _setup_players() -> void:
	if not _players.is_empty():
		return

	var bus_name := _ensure_music_bus()
	for index in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "MusicPlayer%d" % (index + 1)
		player.bus = bus_name
		player.volume_db = SILENT_VOLUME_DB
		player.finished.connect(Callable(self, "_on_player_finished").bind(player))
		add_child(player)
		_players.append(player)

func _ensure_music_bus() -> String:
	var bus_index := AudioServer.get_bus_index(MUSIC_BUS_NAME)
	if bus_index >= 0:
		return MUSIC_BUS_NAME

	AudioServer.add_bus(AudioServer.get_bus_count())
	bus_index = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(bus_index, MUSIC_BUS_NAME)
	AudioServer.set_bus_send(bus_index, "Master")
	return MUSIC_BUS_NAME

func _build_playlists() -> void:
	_playlists.clear()
	_playlists[MOOD_AMBIENT] = _scan_ogg_files("%s/ambient" % MUSIC_ROOT)
	_playlists[MOOD_LIGHT] = _scan_ogg_files("%s/light" % MUSIC_ROOT)
	_playlists[MOOD_NIGHT] = _scan_ogg_files("%s/night" % MUSIC_ROOT)
	_playlists[MOOD_ACTION] = _scan_ogg_files("%s/action" % MUSIC_ROOT)

func _scan_ogg_files(directory_path: String) -> Array[String]:
	var tracks: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_warning("MusicDirector: Could not open music directory %s." % directory_path)
		return tracks

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.to_lower().ends_with(".ogg"):
			tracks.append("%s/%s" % [directory_path, file_name])
		file_name = directory.get_next()
	directory.list_dir_end()

	tracks.sort()
	return tracks

func _resolve_mood() -> StringName:
	var hour := 12
	if _world != null and _world.time != null:
		hour = _world.time.get_hour()

	if _is_night_hour(hour):
		return MOOD_NIGHT
	if _is_light_hour(hour):
		return MOOD_LIGHT
	return MOOD_AMBIENT

func _is_night_hour(hour: int) -> bool:
	return hour >= _night_start_hour or hour < _day_start_hour

func _is_light_hour(hour: int) -> bool:
	var morning_end := (_day_start_hour + 3) % 24
	if _is_hour_in_window(hour, _day_start_hour, morning_end):
		return true

	var evening_start := posmod(_night_start_hour - 4, 24)
	return _is_hour_in_window(hour, evening_start, _night_start_hour)

func _is_hour_in_window(hour: int, start_hour: int, end_hour: int) -> bool:
	if start_hour == end_hour:
		return true
	if start_hour < end_hour:
		return hour >= start_hour and hour < end_hour
	return hour >= start_hour or hour < end_hour

func _play_next_track_for_mood(mood: StringName, use_fade: bool) -> bool:
	var tracks := _get_tracks_for_mood(mood)
	if tracks.is_empty():
		push_warning("MusicDirector: No tracks available for mood '%s'." % str(mood))
		return false

	var track_path := _select_next_track(tracks, mood)
	var stream := load(track_path) as AudioStream
	if stream == null:
		push_warning("MusicDirector: Could not load music track %s." % track_path)
		return false

	_last_track_by_mood[mood] = track_path
	_active_track_path = track_path

	if use_fade and _has_active_player():
		_crossfade_to_stream(stream)
	else:
		_play_immediately(stream)
	return true

func _get_tracks_for_mood(mood: StringName) -> Array:
	var tracks: Array = _playlists.get(mood, [])
	if not tracks.is_empty():
		return tracks

	if mood != MOOD_AMBIENT:
		tracks = _playlists.get(MOOD_AMBIENT, [])
		if not tracks.is_empty():
			return tracks

	tracks = []
	for playlist in _playlists.values():
		for track in playlist:
			tracks.append(track)
	return tracks

func _select_next_track(tracks: Array, mood: StringName) -> String:
	var candidates := tracks.duplicate()
	var last_track := str(_last_track_by_mood.get(mood, ""))
	if candidates.size() > 1 and not last_track.is_empty():
		candidates.erase(last_track)

	var index := _rng.randi_range(0, candidates.size() - 1)
	return str(candidates[index])

func _play_immediately(stream: AudioStream) -> void:
	_kill_transition()
	_stop_inactive_players()

	var player := _players[_active_player_index]
	player.stop()
	player.stream = stream
	player.volume_db = base_volume_db
	player.play()

func _crossfade_to_stream(stream: AudioStream) -> void:
	_kill_transition()
	_stop_inactive_players()

	var old_player := _players[_active_player_index]
	var new_index := 1 - _active_player_index
	var new_player := _players[new_index]

	new_player.stop()
	new_player.stream = stream
	new_player.volume_db = SILENT_VOLUME_DB
	new_player.play()
	_active_player_index = new_index

	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_transition_tween.tween_property(new_player, "volume_db", base_volume_db, fade_seconds)
	if old_player.playing:
		_transition_tween.tween_property(old_player, "volume_db", SILENT_VOLUME_DB, fade_seconds)
		_transition_tween.finished.connect(Callable(self, "_stop_player").bind(old_player))
	else:
		_stop_player(old_player)

func _on_player_finished(player: AudioStreamPlayer) -> void:
	if not _is_started or not _is_enabled:
		return
	if _players.is_empty() or player != _players[_active_player_index]:
		return

	_play_next_track_for_mood(_active_mood, false)

func _has_active_player() -> bool:
	if _players.is_empty():
		return false
	var active_player := _players[_active_player_index]
	return active_player.playing and active_player.stream != null

func _stop_inactive_players() -> void:
	for index in range(_players.size()):
		if index == _active_player_index:
			continue
		_stop_player(_players[index])

func _stop_player(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	player.stop()
	player.stream = null
	player.volume_db = SILENT_VOLUME_DB

func _kill_transition() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null

func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server")
