extends Node
## Languages: godot --headless --path . res://tests/test_i18n.tscn
var fails := 0
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c: fails += 1

func _ready() -> void:
	var keys: Array = JSON.parse_string(FileAccess.get_file_as_string("res://translations/keys.json"))
	for l in Prefs.LANGUAGES:
		var code: String = l[0]
		if code == "en":
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://translations/%s.json" % code))
		var missing := 0
		for k in keys:
			if not d.has(k) or str(d[k]).strip_edges() == "":
				missing += 1
		check(missing == 0, "%s: all %d texts translated (%d missing)" % [code, keys.size(), missing])
		TranslationServer.set_locale(code)
		check(tr("Respawn  (counts as a death)") != "Respawn  (counts as a death)", "%s: tr() returns the translation" % code)
		check(tr("some text that is not translated") == "some text that is not translated", "%s: unknown text falls back to English" % code)
	TranslationServer.set_locale("en")
	check(tr("Settings") == "Settings", "english stays english")
	Prefs.language = ""
	check(Prefs.effective_language() in ["en", "fr", "de", "es", "ru", "zh_CN", "ja"], "automatic language resolves")
	Prefs.set_values({"language": "xx"})
	check(Prefs.language == "", "unknown language code is dropped")
	Prefs.set_values({"language": "ja"})
	Prefs.apply_all()
	check(TranslationServer.get_locale().begins_with("ja"), "apply_all sets the locale")
	# a Control's text is translated by itself
	var b := Button.new()
	b.text = "Quit"
	add_child(b)
	await get_tree().process_frame
	check(b.get_parent() != null and tr("Quit") == "終了", "Japanese Quit")
	Prefs.reset_defaults()
	print("RESULT: PASS" if fails == 0 else "RESULT: %d FAILED" % fails)
	get_tree().quit(0 if fails == 0 else 1)
