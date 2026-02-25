extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("FLASHLIGHT SINGLE SOURCE PARITY TEST")
	print("============================================================")

	await _test_alert_parity()
	await _test_calm_parity()

	_t.summary("FLASHLIGHT SINGLE SOURCE PARITY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_alert_parity() -> void:
	var setup := await _spawn_world(Vector2(280.0, 0.0))
	var world := setup.get("world") as Node2D
	var enemy := setup.get("enemy") as Enemy
	var player := setup.get("player") as CharacterBody2D
	if world == null or enemy == null or player == null:
		_t.run_test("ALERT parity setup", false)
		return

	enemy.on_heard_shot(0, player.global_position)
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("ALERT parity setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return
	detection_runtime.call("set_state_value", "_flashlight_activation_delay_timer", 0.0)
	enemy.runtime_budget_tick(0.25)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var runtime_active := bool(snapshot.get("flashlight_active", false))
	var nav_active := enemy.is_flashlight_active_for_navigation()
	_t.run_test("ALERT parity: runtime snapshot equals navigation", runtime_active == nav_active)

	world.queue_free()
	await get_tree().process_frame


func _test_calm_parity() -> void:
	var setup := await _spawn_world(Vector2(2500.0, 0.0))
	var world := setup.get("world") as Node2D
	var enemy := setup.get("enemy") as Enemy
	if world == null or enemy == null:
		_t.run_test("CALM parity setup", false)
		return

	enemy.runtime_budget_tick(0.25)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var runtime_active := bool(snapshot.get("flashlight_active", false))
	var nav_active := enemy.is_flashlight_active_for_navigation()
	_t.run_test("CALM parity: runtime snapshot equals navigation", runtime_active == nav_active)

	world.queue_free()
	await get_tree().process_frame


func _spawn_world(player_position: Vector2) -> Dictionary:
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 100
		RuntimeState.player_visibility_mul = 1.0

	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.collision_layer = 1
	player.collision_mask = 1
	player.global_position = player_position
	var player_shape := CollisionShape2D.new()
	var player_circle := CircleShape2D.new()
	player_circle.radius = 16.0
	player_shape.shape = player_circle
	player.add_child(player_shape)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame

	enemy.initialize(9901, "zombie")
	enemy.debug_set_pursuit_facing_for_test(Vector2.RIGHT)

	return {
		"world": world,
		"enemy": enemy,
		"player": player,
	}


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object
