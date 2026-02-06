## test_level_smoke.gd
## Headless smoke test for level MVP.
## Tests: start-delay guard, enemy spawning, boss_killed → LEVEL_COMPLETE.
## Run via: godot --headless res://tests/test_level_smoke.tscn
extends Node

var _tests_run := 0
var _tests_passed := 0
var _enemy_spawn_count := 0


func _ready() -> void:
	print("=" .repeat(60))
	print("SMOKE TEST: Level MVP")
	print("=" .repeat(60))

	# Lock frame rate for predictable timing in headless mode
	Engine.max_fps = 60

	# Ensure clean config; enable god mode so player cannot die
	GameConfig.reset_to_defaults()
	GameConfig.god_mode = true

	# Subscribe to enemy_spawned to count spawns
	EventBus.enemy_spawned.connect(_on_enemy_spawned)

	# Transition to PLAYING via valid state path
	StateManager.change_state(GameState.State.LEVEL_SETUP)
	StateManager.change_state(GameState.State.PLAYING)

	# Instantiate level scene
	var scene := load("res://scenes/levels/level_mvp.tscn") as PackedScene
	var level := scene.instantiate()
	add_child(level)

	# Run async tests
	await _run_tests()

	print("")
	print("=" .repeat(60))
	print("SMOKE RESULTS: %d/%d tests passed" % [_tests_passed, _tests_run])
	print("=" .repeat(60))

	get_tree().quit(0 if _tests_passed == _tests_run else 1)


func _on_enemy_spawned(_id: int, _type: String, _wave: int, _pos: Vector3) -> void:
	_enemy_spawn_count += 1


func _run_tests() -> void:
	# ==================================================================
	# Phase 1: ~1 second (60 frames at 60fps)
	# Default start_delay_sec = 1.5s, so at ~1s no enemies yet.
	# ==================================================================
	print("\n--- Phase 1: During start delay (60 frames ~ 1s) ---")
	for i in range(60):
		await get_tree().process_frame

	_test("No enemies spawned during start delay", _enemy_spawn_count == 0)

	# ==================================================================
	# Phase 2: ~5 more seconds (300 frames at 60fps), total ~6s
	# Start delay finishes at ~1.5s, first spawn batch fires immediately
	# after that. By 6s multiple batches should have occurred.
	# ==================================================================
	print("\n--- Phase 2: After start delay + spawning (300 frames ~ 5s) ---")
	for i in range(300):
		await get_tree().process_frame

	_test("Enemies spawned after start delay", _enemy_spawn_count > 0)

	# ==================================================================
	# Phase 3: boss_killed → LEVEL_COMPLETE
	# Verify PLAYING state, emit boss_killed, check transition.
	# ==================================================================
	print("\n--- Phase 3: boss_killed -> LEVEL_COMPLETE ---")

	_test("StateManager in PLAYING before boss test",
		StateManager.current_state == GameState.State.PLAYING)

	# Emit boss_killed event (queued, dispatched next frame)
	EventBus.emit_boss_killed(999)

	# Wait 2 frames for event dispatch + state transition
	await get_tree().process_frame
	await get_tree().process_frame

	_test("StateManager transitioned to LEVEL_COMPLETE",
		StateManager.current_state == GameState.State.LEVEL_COMPLETE)


func _test(name: String, result: bool) -> void:
	_tests_run += 1
	if result:
		_tests_passed += 1
		print("[PASS] %s" % name)
	else:
		print("[FAIL] %s" % name)
