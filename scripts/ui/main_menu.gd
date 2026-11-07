extends Control
## Main menu. Buttons/labels are nodes in scenes/main_menu.tscn; signals connected there.

func _ready() -> void:
	%NoticeLabel.text = tr(Data.notice)
	Data.notice = ""
	%QuitButton.visible = OS.get_name() != "Web"
	var tut := Button.new()                          # the tutorial: a solo game against a target drone
	tut.name = "TutorialButton"
	tut.text = tr("Tutorial (solo)")
	tut.custom_minimum_size = %QuitButton.custom_minimum_size
	tut.pressed.connect(_on_tutorial_pressed)
	%QuitButton.get_parent().add_child(tut)
	%QuitButton.get_parent().move_child(tut, %QuitButton.get_index())


func _on_creation_pressed() -> void:
	Data.builder_open_path = ""
	Game.go_to(Game.BUILDER_SCENE)


func _on_presets_pressed() -> void:
	Game.go_to(Game.PRESETS_SCENE)


func _on_settings_pressed() -> void:
	Game.go_to(Game.SETTINGS_SCENE)


func _on_play_pressed() -> void:
	Game.go_to(Game.BROWSER_SCENE)


func _on_tutorial_pressed() -> void:
	Data.tutorial = true
	Data.tutorial_text = ""
	if not Net.start_solo("res://ships/Dart.json"):
		Data.tutorial = false
		%NoticeLabel.text = tr("Could not start the tutorial.")


func _on_quit_pressed() -> void:
	get_tree().quit()
