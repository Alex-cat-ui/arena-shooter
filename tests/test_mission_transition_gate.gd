extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("=".repeat(60))
	print("MISSION TRANSITION GATE TEST")
	print("=".repeat(60))

	Engine.max_fps = 60
	GameConfig.reset_to_defaults()
	GameConfig.god_mode = true
	GameConfig.start_delay_sec = 999.0

	if StateManager.current_state != GameState.State.MAIN_MENU:
		StateManager.change_state(GameState.State.MAIN_MENU)
	StateManager.change_state(GameState.State.LEVEL_SETUP)
	StateManager.change_state(GameState.State.PLAYING)

	# Disable layout generation for entire test to skip slow navmesh bake
	var _layout_was_enabled: bool = GameConfig.procedural_layout_enabled if GameConfig else false
	if GameConfig:
		GameConfig.procedural_layout_enabled = false
	var scene := load("res://scenes/levels/level_mvp.tscn") as PackedScene
	var level := scene.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame

	await _run_tests(level)

	if GameConfig:
		GameConfig.procedural_layout_enabled = _layout_was_enabled
	_t.summary("MISSION TRANSITION GATE RESULTS")
	level.queue_free()
	await get_tree().process_frame
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _run_tests(level: Node) -> void:
	if not level:
		_t.check("Level is available", false)
		return

	level.set_mission_cycle_position(0)

	# Case 1: any alive enemy in scene -> blocked
	var dummy_enemy := Node2D.new()
	dummy_enemy.name = "DummyEnemy"
	dummy_enemy.add_to_group("enemies")
	level.entities_container.add_child(dummy_enemy)
	var before: int = int(level.get_current_mission_index())
	_try_transition(level)
	_t.check("Blocked while alive enemies exist", level.get_current_mission_index() == before)
	level.set_north_transition_probe(Rect2(), false, 0.0)
	dummy_enemy.queue_free()
	await get_tree().process_frame

	# Case 2: no alive enemies -> allowed
	for node_variant in level.get_tree().get_nodes_in_group("enemies"):
		var node := node_variant as Node
		if node and is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var unlocked_before = level.alive_scene_enemies_count() == 0 and level.is_north_transition_unlocked()
	before = level.get_current_mission_index()
	_try_transition(level)
	await get_tree().process_frame
	var after: int = int(level.get_current_mission_index())
	_t.check("Allowed after clear", after != before)
	_t.check("Gate unlock condition is alive_scene_enemies_count == 0", unlocked_before)
	_t.check("RuntimeState mission index synced", RuntimeState.mission_index == after)


func _try_transition(level: Node) -> void:
	if not level.player:
		return
	var p: Vector2 = level.player.position
	level.set_north_transition_probe(Rect2(p.x - 12.0, p.y - 12.0, 24.0, 24.0), true, 0.0)
	level.check_north_transition_gate()
