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
	print("FIRST SHOT TIMER STARTS ON FIRST VALID FIRING SOLUTION TEST")
	print("============================================================")

	await _test_first_shot_timer_starts_on_first_valid_firing_solution()

	_t.summary("FIRST SHOT TIMER STARTS ON FIRST VALID FIRING SOLUTION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_first_shot_timer_starts_on_first_valid_firing_solution() -> void:
	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame

	enemy.initialize(7601, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	_t.run_test("first-shot timer start: runtime helper exists", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return
	runtime.call("reset_first_shot_delay_state")

	runtime.call("update_first_shot_delay_runtime", 0.4, false, "ctx_a")
	var before_valid := enemy.get_debug_detection_snapshot() as Dictionary

	runtime.call("update_first_shot_delay_runtime", 0.1, true, "ctx_a")
	var after_first_valid := enemy.get_debug_detection_snapshot() as Dictionary
	var armed_delay := float(after_first_valid.get("shotgun_first_attack_delay_left", 0.0))

	_t.run_test(
		"before first valid contact: timer is not armed",
		not bool(before_valid.get("shotgun_first_attack_delay_armed", true))
			and is_zero_approx(float(before_valid.get("shotgun_first_attack_delay_left", 1.0)))
	)
	_t.run_test(
		"first valid contact arms timer in 1.2..2.0s window",
		bool(after_first_valid.get("shotgun_first_attack_delay_armed", false))
			and armed_delay >= 1.2
			and armed_delay <= 2.0
	)

	world.queue_free()
	await get_tree().process_frame
