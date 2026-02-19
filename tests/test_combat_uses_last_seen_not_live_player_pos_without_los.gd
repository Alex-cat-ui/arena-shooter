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
	print("COMBAT LAST_SEEN FORBIDDEN TEST")
	print("============================================================")

	await _test_combat_does_not_use_last_seen_without_los()

	_t.summary("COMBAT LAST_SEEN FORBIDDEN RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_combat_does_not_use_last_seen_without_los() -> void:
	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(460.0, 0.0)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2(0.0, 0.0)
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(4601, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	enemy.runtime_budget_tick(0.1)

	var remembered := player.global_position
	var blocker := _spawn_blocker(world, Vector2(230.0, 0.0), Vector2(32.0, 640.0))
	_t.run_test("no-los setup: blocker exists", blocker != null)
	player.global_position = Vector2(540.0, 140.0)
	await get_tree().physics_frame

	enemy.runtime_budget_tick(0.70)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var intent := enemy.get_current_intent() as Dictionary
	var intent_target := intent.get("target", Vector2.ZERO) as Vector2

	_t.run_test("without LOS: snapshot marks has_los=false", not bool(snapshot.get("has_los", true)))
	_t.run_test("without LOS: target_is_last_seen=false in COMBAT", not bool(snapshot.get("target_is_last_seen", true)))
	_t.run_test(
		"without LOS: intent target is not remembered last_seen anchor",
		intent_target.distance_to(remembered) > 48.0
	)

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
