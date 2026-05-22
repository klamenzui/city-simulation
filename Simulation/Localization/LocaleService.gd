extends RefCounted
class_name LocaleService

## Central UI text localization.
##
## Mirrors the BalanceConfig pattern: a static, instance-free service that lazy-
## loads flat key/value JSON dictionaries from res://language/<code>.json. The
## active language is persisted in user://settings.cfg so the choice survives
## restarts. t(key) resolves against the active language first, then the default
## language as a fallback, then the literal key — a missing translation stays
## visible instead of breaking the UI.

const LANG_DIR := "res://language/"
const DEFAULT_LANG := "de"
const SUPPORTED: Array[String] = ["de", "en", "ru", "uk", "az"]

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "locale"
const SETTINGS_KEY := "language"

static var _loaded: bool = false
static var _current: String = DEFAULT_LANG
static var _data: Dictionary = {}
static var _fallback: Dictionary = {}

static func t(key: String, default_value: String = "") -> String:
	_ensure_loaded()
	var value: Variant = _lookup(_data, key)
	if value == null:
		value = _lookup(_fallback, key)
	if value == null:
		return default_value if not default_value.is_empty() else key
	return str(value)

# Resolves a dotted path ("hud.pause") through nested dictionaries. A flat key
# without dots resolves in one step, so old flat files keep working. Returns
# null if the path is missing or points at a subtree instead of a leaf value.
static func _lookup(dict: Dictionary, key: String) -> Variant:
	var current: Variant = dict
	for part in key.split("."):
		if not (current is Dictionary):
			return null
		var node := current as Dictionary
		if not node.has(part):
			return null
		current = node[part]
	if current is Dictionary:
		return null
	return current

static func get_language() -> String:
	_ensure_loaded()
	return _current

static func set_language(code: String) -> void:
	if not SUPPORTED.has(code):
		push_warning("LocaleService: unsupported language '%s'." % code)
		return
	_ensure_loaded()
	if code == _current:
		return
	_current = code
	_data = _fallback if code == DEFAULT_LANG else _load_language(code)
	_save_language(code)

# [{ "code": "de", "name": "Deutsch" }, ...] — display names are read from each
# file's language_name key so the dropdown shows every language in its own form.
static func available() -> Array:
	var result: Array = []
	for code in SUPPORTED:
		var strings := _load_language(code)
		result.append({
			"code": code,
			"name": str(strings.get("language_name", code.to_upper())),
		})
	return result

static func reload() -> void:
	_loaded = false
	_data = {}
	_fallback = {}
	_ensure_loaded()

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_current = _read_saved_language()
	_fallback = _load_language(DEFAULT_LANG)
	_data = _fallback if _current == DEFAULT_LANG else _load_language(_current)

static func _load_language(code: String) -> Dictionary:
	var path := LANG_DIR + code + ".json"
	if not FileAccess.file_exists(path):
		push_warning("LocaleService: missing language file %s." % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("LocaleService: could not open %s." % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	push_warning("LocaleService: invalid JSON in %s." % path)
	return {}

static func _read_saved_language() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return DEFAULT_LANG
	var code := str(config.get_value(SETTINGS_SECTION, SETTINGS_KEY, DEFAULT_LANG))
	return code if SUPPORTED.has(code) else DEFAULT_LANG

static func _save_language(code: String) -> void:
	var config := ConfigFile.new()
	# Load first so we preserve any other settings already in the file.
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY, code)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("LocaleService: could not save settings (%d)." % err)
