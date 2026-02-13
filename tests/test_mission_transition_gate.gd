## test_mission_transition_gate.gd
## Verifies north mission transition is gated by combat clear conditions.
## Run via: godot --headless res://tests/test_mission_transition_gate.tscn
extends Node

var _tests_run := 0
var _tests_passed := 0


func _ready() -> void:
	print("=".repeat(60))
	print("MISSION TRANSITION GATE TEST")
	print("=".repeat(60))

	Engine.max_fps = 60
	GameConfig.reset_to_defaults()
	GameConfig.god_mode = true
	GameConfig.waves_enabled = true
	GameConfig.start_delay_sec = 999.0

	if StateManager.current_state != GameState.State.MAIN_MENU:
		StateManager.change_state(GameState.State.MAIN_MENU)
	StateManager.change_state(GameState.State.LEVEL_SETUP)
	StateManager.change_state(GameState.State.PLAYING)

	var scene := load("res://scenes/levels/level_mvp.tscn") as PackedScene
	var level := scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	await _run_tests(level)

	print("")
	print("=".repeat(60))
	print("MISSION TRANSITION GATE RESULTS: %d/%d passed" % [_tests_passed, _tests_run])
	print("=".repeat(60))
	get_tree().quit(0 if _tests_passed == _tests_run else 1)


func _run_tests(level: Node) -> void:
	if not level or not level.wave_manager:
		_test("Level and WaveManager are available", false)
		return

	var total_waves := GameConfig.waves_per_level
	level._mission_cycle_pos = 0

	# Case 1: alive enemies -> blocked
	_set_wave_state(level, total_waves, true, 2, false)
	var before: int = int(level._current_mission_index())
	_try_transition(level)
	_test("Blocked while alive_total > 0", level._current_mission_index() == before)

	# Case 2: wave not finished spawning -> blocked
	_set_wave_state(level, total_waves, false, 0, false)
	before = level._current_mission_index()
	_try_transition(level)
	_test("Blocked while wave not finished", level._current_mission_index() == before)

	# Case 3: not final wave -> blocked
	_set_wave_state(level, maxi(1, total_waves - 1), true, 0, false)
	before = level._current_mission_index()
	_try_transition(level)
	_test("Blocked before final wave", level._current_mission_index() == before)

	# Case 4: boss active -> blocked
	_set_wave_state(level, total_waves, true, 0, true)
	before = level._current_mission_index()
	_try_transition(level)
	_test("Blocked while boss is active", level._current_mission_index() == before)

	# Case 5: final wave done + no enemies + no boss -> allowed
	_set_wave_state(level, total_waves, true, 0, false)
	before = level._current_mission_index()
	_try_transition(level)
	await get_tree().process_frame
	var after: int = int(level._current_mission_index())
	_test("Allowed after full clear", after != before)
	_test("RuntimeState mission index synced", RuntimeState.mission_index == after)


func _set_wave_state(level: Node, wave_idx: int, finished: bool, alive: int, boss_active: bool) -> void:
	level.wave_manager.wave_index = wave_idx
	level.wave_manager.wave_finished_spawning = finished
	level.wave_manager.alive_total = alive
	level.wave_manager.boss_spawned = boss_active
	level._north_transition_cooldown = 0.0


func _try_transition(level: Node) -> void:
	if not level.player:
		return
	var p: Vector2 = level.player.position
	level._north_transition_enabled = true
	level._north_transition_rect = Rect2(p.x - 12.0, p.y - 12.0, 24.0, 24.0)
	level._north_transition_cooldown = 0.0
	level._check_north_transition()


func _test(name: String, result: bool) -> void:
	_tests_run += 1
	if result:
		_tests_passed += 1
		print("[PASS] %s" % name)
	else:
		print("[FAIL] %s" % name)
