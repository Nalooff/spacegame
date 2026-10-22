extends Node
func _ready() -> void:
	var runner := Node.new()
	runner.name = "LobbyRunner"
	runner.set_script(load("res://tests/lobby_runner.gd"))
	runner.role = OS.get_cmdline_user_args()[0]
	get_tree().root.add_child.call_deferred(runner)
