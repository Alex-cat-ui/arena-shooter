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
	print("ENEMY FIRE TRACE CACHE RUNTIME TEST")
	print("============================================================")

	await _test_friendly_excludes_cache_rebuild_once_per_physics_frame()

	_t.summary("ENEMY FIRE TRACE CACHE RUNTIME RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_friendly_excludes_cache_rebuild_once_per_physics_frame() -> void:
	Enemy.debug_reset_fire_trace_cache_metrics()
	var world := Node2D.new()
	add_child(world)

	var enemies: Array[Enemy] = []
	for i in range(4):
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		enemy.global_position = Vector2(80.0 * float(i), 0.0)
		world.add_child(enemy)
		enemies.append(enemy)

	await get_tree().process_frame
	await get_tree().physics_frame
	for i in range(enemies.size()):
		enemies[i].initialize(7500 + i, "zombie")

	Enemy.debug_reset_fire_trace_cache_metrics()
	for enemy in enemies:
		enemy.call("_build_fire_line_excludes", true)
	var frame_a := Enemy.debug_get_fire_trace_cache_metrics() as Dictionary

	for enemy in enemies:
		enemy.call("_build_fire_line_excludes", false)
	var frame_a_after_non_friendly := Enemy.debug_get_fire_trace_cache_metrics() as Dictionary

	await get_tree().physics_frame
	for enemy in enemies:
		enemy.call("_build_fire_line_excludes", true)
	var frame_b := Enemy.debug_get_fire_trace_cache_metrics() as Dictionary

	_t.run_test(
		"cache rebuilds once per physics frame across all enemies",
		int(frame_a.get("rebuild_count", -1)) == 1
	)
	_t.run_test(
		"cache contains all active enemies in group",
		int(frame_a.get("cache_size", 0)) >= enemies.size()
	)
	_t.run_test(
		"non-friendly trace path does not rebuild cache",
		int(frame_a_after_non_friendly.get("rebuild_count", -1)) == int(frame_a.get("rebuild_count", -2))
	)
	_t.run_test(
		"next physics frame rebuilds cache exactly once more",
		int(frame_b.get("rebuild_count", -1)) == 2
	)

	world.queue_free()
	await get_tree().process_frame
	Enemy.debug_reset_fire_trace_cache_metrics()
