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
	print("ALERT HOLD DYNAMIC TEST")
	print("============================================================")

	await _test_dynamic_alert_hold_after_far_shot()
	await _test_teammate_call_without_shot_pos_extends_alert_hold()
	await _test_teammate_call_with_shot_pos_sets_anchor_and_dynamic_hold()

	_t.summary("ALERT HOLD DYNAMIC RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_dynamic_alert_hold_after_far_shot() -> void:
	var world := Node2D.new()
	add_child(world)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame

	enemy.initialize(9101, "zombie")
	var shot_pos := Vector2(960.0, 0.0)
	enemy.on_heard_shot(0, shot_pos)

	var awareness = enemy.get("_awareness")
	var hold_timer := 0.0
	if awareness != null:
		hold_timer = float(awareness.get("_alert_hold_timer"))

	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var walk_speed := enemy.speed_tiles * float(tile_size)
	var walk_time := enemy.global_position.distance_to(shot_pos) / maxf(walk_speed, 0.001)

	_t.run_test("setup: awareness exists", awareness != null)
	_t.run_test("dynamic hold > walk_time + 3.0", hold_timer > walk_time + 2.999)

	world.queue_free()
	await get_tree().process_frame


func _test_teammate_call_without_shot_pos_extends_alert_hold() -> void:
	var world := Node2D.new()
	add_child(world)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame

	enemy.initialize(9102, "zombie")
	var accepted := enemy.apply_teammate_call(100, 10, 7001, Vector2.ZERO)

	var awareness = enemy.get("_awareness")
	var hold_timer := 0.0
	if awareness != null:
		hold_timer = float(awareness.get("_alert_hold_timer"))

	_t.run_test("teammate call without shot_pos is accepted from CALM", accepted)
	_t.run_test("teammate fallback hold lower bound is 8.0s", hold_timer >= 8.0)
	_t.run_test("teammate fallback hold upper bound is 15.0s", hold_timer <= 15.0)

	world.queue_free()
	await get_tree().process_frame


func _test_teammate_call_with_shot_pos_sets_anchor_and_dynamic_hold() -> void:
	var world := Node2D.new()
	add_child(world)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame

	enemy.initialize(9103, "zombie")
	var shot_pos := Vector2(900.0, 0.0)
	var accepted := enemy.apply_teammate_call(100, 10, 7002, shot_pos)

	var awareness = enemy.get("_awareness")
	var hold_timer := 0.0
	if awareness != null:
		hold_timer = float(awareness.get("_alert_hold_timer"))
	var tile_size: int = GameConfig.tile_size if GameConfig else 32
	var walk_speed := enemy.speed_tiles * float(tile_size)
	var walk_time := enemy.global_position.distance_to(shot_pos) / maxf(walk_speed, 0.001)

	var anchor := enemy.get("_investigate_anchor") as Vector2
	var anchor_valid := bool(enemy.get("_investigate_anchor_valid"))
	var flashlight_delay := float(enemy.get("_flashlight_activation_delay_timer"))

	_t.run_test("teammate call with shot_pos is accepted from CALM", accepted)
	_t.run_test("teammate shot_pos sets investigate anchor", anchor.distance_to(shot_pos) <= 0.001 and anchor_valid)
	_t.run_test("teammate shot_pos dynamic hold > walk_time + 3.0", hold_timer > walk_time + 2.999)
	_t.run_test("teammate far shot_pos sets flashlight delay in [1.0, 1.8]", flashlight_delay >= 1.0 and flashlight_delay <= 1.8)

	world.queue_free()
	await get_tree().process_frame
