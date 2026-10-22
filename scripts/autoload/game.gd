extends Node
## Autoload "Game": scene paths and scene switching only.
## Player choices and tunable constants live in the "Data" autoload.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const BUILDER_SCENE := "res://scenes/ship_builder.tscn"
const BROWSER_SCENE := "res://scenes/lobby_browser.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const WORLD_SCENE := "res://scenes/game_world.tscn"


func go_to(path: String) -> void:
	get_tree().change_scene_to_file(path)
