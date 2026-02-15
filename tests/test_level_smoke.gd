## test_level_smoke.gd
## Headless smoke test for level MVP.
## Tests: start-delay guard + wave-off behavior (no wave spawns).
## Run via: godot --headless res://tests/test_level_smoke.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

var _t := TestHelpers.new()
var _enemy_spawn_count := 0


func _ready() -> void:
	print("=" .repeat(60))
	print("SMOKE TEST: Level MVP")
	print("=" .repeat(60))

	Engine.max_fps = 60
	GameConfig.reset_to_defaults()
	GameConfig.god_mode = true
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	StateManager.change_state(GameState.State.LEVEL_SETUP)
	StateManager.change_state(GameState.State.PLAYING)

	var scene := load("res://scenes/levels/level_mvp.tscn") as PackedScene
	var level := scene.instantiate()
	add_child(level)

	await _run_tests()

	_t.summary("SMOKE RESULTS")
	get_tree().quit(_t.quit_code())


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

	_t.check("No enemies spawned during start delay", _enemy_spawn_count == 0)

	# ==================================================================
	# Phase 2: ~5 more seconds (300 frames at 60fps), total ~6s.
	# Waves are disabled in runtime, so wave spawns must stay off.
	# ==================================================================
	print("\n--- Phase 2: After start delay (waves disabled) ---")
	for i in range(300):
		await get_tree().process_frame

	_t.check("No wave enemies spawned after start delay", _enemy_spawn_count == 0)
	_t.check("State remains PLAYING in wave-off runtime",
		StateManager.current_state == GameState.State.PLAYING)


