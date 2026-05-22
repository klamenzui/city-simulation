extends SceneTree

## Headless regression test for the UI localization layer.
##
## Verifies that every language file defines exactly the same key set (so a
## later language never silently misses a string), that t() resolves and that
## switching languages actually changes the resolved text, and that a missing
## key falls back to the key itself instead of crashing. The user's persisted
## language is captured up front and restored at the end so the test has no
## lasting effect on user://settings.cfg.

const LocaleServiceScript = preload("res://Simulation/Localization/LocaleService.gd")
const LANGS := ["de", "en", "ru", "uk", "az"]

func _initialize() -> void:
	var failures: Array[String] = []

	var key_sets := {}
	for code in LANGS:
		var path := "res://language/%s.json" % code
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			failures.append("missing/empty %s" % path)
			continue
		var parsed: Variant = JSON.parse_string(text)
		if parsed is not Dictionary:
			failures.append("invalid JSON in %s" % path)
			continue
		var leaves := {}
		_collect_leaf_keys(parsed as Dictionary, "", leaves)
		key_sets[code] = leaves.keys()

	# Key parity: every language must define the same keys as the default (de).
	if key_sets.has("de"):
		var base: Array = key_sets["de"]
		for code in LANGS:
			if code == "de" or not key_sets.has(code):
				continue
			var other: Array = key_sets[code]
			for k in base:
				if not other.has(k):
					failures.append("%s is missing key '%s'" % [code, k])
			for k in other:
				if not base.has(k):
					failures.append("%s has extra key '%s'" % [code, k])

	# Resolution + switching: the same key must resolve to different, non-raw
	# text in two different languages.
	var original := LocaleServiceScript.get_language()
	LocaleServiceScript.set_language("en")
	if LocaleServiceScript.get_language() != "en":
		failures.append("set_language('en') did not take effect")
	var en_play := LocaleServiceScript.t("menu.play")
	LocaleServiceScript.set_language("de")
	var de_play := LocaleServiceScript.t("menu.play")
	if en_play == "menu.play" or de_play == "menu.play":
		failures.append("t() returned the raw key instead of a translation")
	elif en_play == de_play:
		failures.append("switching language did not change the resolved text")

	# Missing key must stay visible (returns the key), never error.
	if LocaleServiceScript.t("__does_not_exist__") != "__does_not_exist__":
		failures.append("missing-key fallback did not return the key")

	# Restore the user's original language — no lasting side effect.
	LocaleServiceScript.set_language(original)

	if failures.is_empty():
		var key_count: int = (key_sets["de"] as Array).size() if key_sets.has("de") else 0
		print("Locale test OK (%d languages, %d keys each)." % [LANGS.size(), key_count])
		quit(0)
		return
	print("Locale test FAILED:")
	for f in failures:
		print("  - %s" % f)
	quit(1)

# Flattens a nested translation dict into dotted leaf paths ("mp.button_host")
# so parity can be compared key-for-key across languages.
func _collect_leaf_keys(dict: Dictionary, prefix: String, out: Dictionary) -> void:
	for k in dict.keys():
		var value: Variant = dict[k]
		var path: String = str(k) if prefix.is_empty() else "%s.%s" % [prefix, k]
		if value is Dictionary:
			_collect_leaf_keys(value as Dictionary, path, out)
		else:
			out[path] = true
