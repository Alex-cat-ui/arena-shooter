## test_runner.gd
## Test runner that works with autoloads loaded.
## Run via: godot --headless -s res://tests/test_runner.gd
extends SceneTree

func _init() -> void:
	# Load and run the smoke test
	var test_script = load("res://tests/test_level_smoke.gd")
	if test_script:
		var test_instance = test_script.new()
	else:
		print("ERROR: Could not load test script")
		quit(1)
