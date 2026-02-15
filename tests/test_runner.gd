## test_runner.gd
## Legacy shim for script-based launch.
## Use scene-based runner instead:
##   godot --headless --path . --scene res://tests/test_runner.tscn
extends SceneTree

func _init() -> void:
	print("Use scene runner: godot --headless --path . --scene res://tests/test_runner.tscn")
	quit(1)
