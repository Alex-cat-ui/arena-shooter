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
	print("FIRST SHOT TIMER PAUSE/RESET AFTER 2.5S TEST")
	print("============================================================")

	await _test_first_shot_timer_pause_and_reset_after_2_5s()

	_t.summary("FIRST SHOT TIMER PAUSE/RESET AFTER 2.5S RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_first_shot_timer_pause_and_reset_after_2_5s() -> void:
	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame

	enemy.initialize(7602, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	_t.run_test("first-shot timer pause/reset: runtime helper exists", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return
	runtime.call("reset_first_shot_delay_state")

	runtime.call("update_first_shot_delay_runtime", 0.1, true, "ctx_a")
	var armed := enemy.get_debug_detection_snapshot() as Dictionary
	var armed_left := float(armed.get("shotgun_first_attack_delay_left", 0.0))

	runtime.call("update_first_shot_delay_runtime", 2.6, false, "ctx_a")
	var after_long_pause := enemy.get_debug_detection_snapshot() as Dictionary

	runtime.call("update_first_shot_delay_runtime", 0.1, true, "ctx_a")
	var rearmed := enemy.get_debug_detection_snapshot() as Dictionary
	var rearmed_left := float(rearmed.get("shotgun_first_attack_delay_left", 0.0))

	_t.run_test(
		"timer was armed before pause",
		bool(armed.get("shotgun_first_attack_delay_armed", false)) and armed_left > 0.0
	)
	_t.run_test(
		"pause longer than 2.5s resets timer state",
		not bool(after_long_pause.get("shotgun_first_attack_delay_armed", true))
			and is_zero_approx(float(after_long_pause.get("shotgun_first_attack_delay_left", 1.0)))
			and is_zero_approx(float(after_long_pause.get("shotgun_first_attack_pause_elapsed", 1.0)))
	)
	_t.run_test(
		"next valid contact rearms timer after reset",
		bool(rearmed.get("shotgun_first_attack_delay_armed", false))
			and rearmed_left >= 1.2
			and rearmed_left <= 2.0
	)

	world.queue_free()
	await get_tree().process_frame
