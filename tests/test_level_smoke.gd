## test_level_smoke.gd
## Headless smoke test for level MVP.
## Tests: start-delay guard + spawn-off behavior (no enemy spawns).
## Run via: godot --headless res://tests/test_level_smoke.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

var _t := TestHelpers.new()
var _enemy_spawn_count := 0
var _mission_signal_count := 0
var _last_mission_signal: int = -1
var _level: Node = null


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
	_level = scene.instantiate()
	add_child(_level)

	EventBus.mission_transitioned.connect(_on_mission_transitioned)

	await _run_tests()

	_t.summary("SMOKE RESULTS")
	get_tree().quit(_t.quit_code())


func _on_enemy_spawned(_id: int, _type: String, _pos: Vector3) -> void:
	_enemy_spawn_count += 1


func _on_mission_transitioned(mission_index: int) -> void:
	_mission_signal_count += 1
	_last_mission_signal = mission_index


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
	# Runtime spawn is disabled, so enemies must not appear.
	# ==================================================================
	print("\n--- Phase 2: After start delay (spawn disabled) ---")
	for i in range(300):
		await get_tree().process_frame

	_t.check("No enemies spawned after start delay", _enemy_spawn_count == 0)
	_t.check("State remains PLAYING with spawn disabled",
		StateManager.current_state == GameState.State.PLAYING)

	# ==================================================================
	# Public facade checks (pause/resume + mission transition signal).
	# ==================================================================
	print("\n--- Phase 3: Public facade checks ---")
	_level.pause()
	_t.check("pause() facade freezes runtime", RuntimeState.is_frozen == true)
	_level.resume()
	_t.check("resume() facade unfreezes runtime", RuntimeState.is_frozen == false)

	for node_variant in get_tree().get_nodes_in_group("enemies"):
		var node := node_variant as Node
		if node and is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_t.check("transition gate query unlocked after scene clear", _level.alive_scene_enemies_count() == 0 and _level.is_north_transition_unlocked())

	var before_mission := int(_level.get_current_mission_index())
	var p = _level.player.position
	_level.set_north_transition_probe(Rect2(p.x - 12.0, p.y - 12.0, 24.0, 24.0), true, 0.0)
	_level.check_north_transition_gate()
	await get_tree().process_frame
	await get_tree().process_frame

	var after_mission := int(_level.get_current_mission_index())
	_t.check("mission transition uses facade and changes mission index", after_mission != before_mission)
	_t.check("mission_transitioned signal emitted once", _mission_signal_count == 1 and _last_mission_signal == after_mission)
