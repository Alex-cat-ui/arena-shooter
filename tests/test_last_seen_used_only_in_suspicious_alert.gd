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
	print("LAST_SEEN USED ONLY IN SUSPICIOUS/ALERT TEST")
	print("============================================================")

	await _test_last_seen_forbidden_in_combat_and_allowed_in_alert()

	_t.summary("LAST_SEEN USED ONLY IN SUSPICIOUS/ALERT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_last_seen_forbidden_in_combat_and_allowed_in_alert() -> void:
	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(520.0, 0.0)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2(0.0, 0.0)
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(5201, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	enemy.runtime_budget_tick(0.1)

	var remembered_pos := player.global_position
	var blocker := _spawn_blocker(world, Vector2(260.0, 0.0), Vector2(32.0, 640.0))
	_t.run_test("last_seen rule: blocker exists", blocker != null)
	player.global_position = Vector2(520.0, 220.0)
	await get_tree().physics_frame

	enemy.runtime_budget_tick(0.8)
	var combat_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var combat_intent := enemy.get_current_intent() as Dictionary
	var combat_target := combat_intent.get("target", Vector2.ZERO) as Vector2
	var combat_type := int(combat_intent.get("type", -1))

	_t.run_test("last_seen rule: COMBAT no-LOS does not mark target_is_last_seen", not bool(combat_snapshot.get("target_is_last_seen", true)))
	_t.run_test(
		"last_seen rule: COMBAT no-LOS does not target remembered last_seen point",
		combat_target.distance_to(remembered_pos) > 48.0
	)
	_t.run_test(
		"last_seen rule: COMBAT no-LOS intent is not INVESTIGATE/SEARCH-by-last_seen",
		combat_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.INVESTIGATE
		and combat_type != ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH
	)

	enemy.debug_force_awareness_state("ALERT")
	enemy.set("_last_seen_pos", remembered_pos)
	enemy.set("_last_seen_age", 0.1)
	var utility_variant: Variant = enemy.get("_utility_brain")
	if utility_variant != null:
		var utility_obj := utility_variant as Object
		if utility_obj and utility_obj.has_method("reset"):
			utility_obj.call("reset")
	enemy.runtime_budget_tick(1.0)
	var alert_snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var alert_intent := enemy.get_current_intent() as Dictionary
	var alert_target := alert_intent.get("target", Vector2.ZERO) as Vector2

	_t.run_test("last_seen rule: ALERT can mark target as last_seen", bool(alert_snapshot.get("target_is_last_seen", false)))
	_t.run_test(
		"last_seen rule: ALERT can use remembered last_seen target",
		alert_target.distance_to(remembered_pos) <= 24.0
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
