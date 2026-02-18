extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_UTILITY_BRAIN_SCRIPT := preload("res://src/systems/enemy_utility_brain.gd")

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
	print("LAST_SEEN GRACE WINDOW TEST")
	print("============================================================")

	await _test_last_seen_grace_window()

	_t.summary("LAST_SEEN GRACE WINDOW RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_last_seen_grace_window() -> void:
	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(900.0, 0.0)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2(0.0, 0.0)
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(4701, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	enemy.runtime_budget_tick(0.1)

	var last_seen_anchor := player.global_position
	var blocker := _spawn_blocker(world, Vector2(230.0, 0.0), Vector2(32.0, 640.0))
	_t.run_test("grace setup: blocker exists", blocker != null)
	player.global_position = Vector2(900.0, 200.0)
	await get_tree().physics_frame

	enemy.runtime_budget_tick(0.75)
	var intent_during_grace := enemy.get_current_intent() as Dictionary
	var type_during_grace := int(intent_during_grace.get("type", -1))
	var target_during_grace := intent_during_grace.get("target", Vector2.ZERO) as Vector2
	_t.run_test(
		"during grace: combat intent remains push/hold to last_seen anchor",
		(
			type_during_grace == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PUSH
			or type_during_grace == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.HOLD_RANGE
		)
		and target_during_grace.distance_to(last_seen_anchor) <= 24.0
	)

	enemy.runtime_budget_tick(0.90)
	var intent_after_grace := enemy.get_current_intent() as Dictionary
	var type_after_grace := int(intent_after_grace.get("type", -1))
	var target_after_grace := intent_after_grace.get("target", Vector2.ZERO) as Vector2
	_t.run_test(
		"after grace: intent switches to investigate/search around last_seen",
		(
			type_after_grace == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
			or type_after_grace == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
		)
		and target_after_grace.distance_to(last_seen_anchor) <= 24.0
		and target_after_grace.distance_to(player.global_position) > 48.0
	)

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("after grace: snapshot keeps no-LOS state", not bool(snapshot.get("has_los", true)))

	world.queue_free()
	await get_tree().process_frame


func _spawn_blocker(parent: Node2D, pos: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)
	return body
