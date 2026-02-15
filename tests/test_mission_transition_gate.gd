## test_mission_transition_gate.gd
## Verifies north mission transition is gated by combat clear conditions.
## Run via: godot --headless res://tests/test_mission_transition_gate.tscn
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

var _t := TestHelpers.new()


func _ready() -> void:
	print("=".repeat(60))
	print("MISSION TRANSITION GATE TEST")
	print("=".repeat(60))

	Engine.max_fps = 60
	GameConfig.reset_to_defaults()
	GameConfig.god_mode = true
	GameConfig.waves_enabled = false
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

	_t.summary("MISSION TRANSITION GATE RESULTS")
	get_tree().quit(_t.quit_code())


func _run_tests(level: Node) -> void:
	if not level:
		_t.check("Level is available", false)
		return

	level._mission_cycle_pos = 0

	# Case 1: any alive enemy in scene -> blocked
	var dummy_enemy := Node2D.new()
	dummy_enemy.name = "DummyEnemy"
	dummy_enemy.add_to_group("enemies")
	level.entities_container.add_child(dummy_enemy)
	var before: int = int(level._current_mission_index())
	_try_transition(level)
	_t.check("Blocked while alive enemies exist", level._current_mission_index() == before)
	level._north_transition_enabled = false
	level._north_transition_rect = Rect2()
	level._north_transition_cooldown = 0.0
	dummy_enemy.queue_free()
	await get_tree().process_frame

	# Case 2: no alive enemies -> allowed
	for node_variant in level.get_tree().get_nodes_in_group("enemies"):
		var node := node_variant as Node
		if node and is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	before = level._current_mission_index()
	_try_transition(level)
	await get_tree().process_frame
	var after: int = int(level._current_mission_index())
	_t.check("Allowed after clear", after != before)
	_t.check("RuntimeState mission index synced", RuntimeState.mission_index == after)


func _try_transition(level: Node) -> void:
	if not level.player:
		return
	var p: Vector2 = level.player.position
	level._north_transition_enabled = true
	level._north_transition_rect = Rect2(p.x - 12.0, p.y - 12.0, 24.0, 24.0)
	level._north_transition_cooldown = 0.0
	level._check_north_transition()


