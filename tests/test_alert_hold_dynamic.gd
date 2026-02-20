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
