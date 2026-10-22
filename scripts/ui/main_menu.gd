extends Control
## Main menu. Buttons/labels are nodes in scenes/main_menu.tscn; signals connected there.

func _ready() -> void:
	%NoticeLabel.text = Data.notice
	Data.notice = ""
	%QuitButton.visible = OS.get_name() != "Web"


func _on_creation_pressed() -> void:
	Data.builder_open_path = ""
	Game.go_to(Game.BUILDER_SCENE)


func _on_play_pressed() -> void:
	Game.go_to(Game.BROWSER_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
