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
	print("FIRST SHOT DELAY STARTS ON FIRST VALID FIRING SOLUTION TEST")
	print("============================================================")

	await _test_first_shot_delay_runtime_contract()

	_t.summary("FIRST SHOT DELAY STARTS ON FIRST VALID FIRING SOLUTION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_first_shot_delay_runtime_contract() -> void:
	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(6501, "zombie")
	enemy.debug_force_awareness_state("COMBAT")

	enemy.call("_reset_first_shot_delay_state")
	enemy.call("_update_first_shot_delay_runtime", 0.4, false, "ctx_a")
	var before_valid := enemy.get_debug_detection_snapshot() as Dictionary

	enemy.call("_update_first_shot_delay_runtime", 0.1, true, "ctx_a")
	var after_arm := enemy.get_debug_detection_snapshot() as Dictionary
	var armed_delay := float(after_arm.get("shotgun_first_attack_delay_left", 0.0))

	enemy.call("_update_first_shot_delay_runtime", 0.6, false, "ctx_a")
	var after_pause := enemy.get_debug_detection_snapshot() as Dictionary
	var paused_delay := float(after_pause.get("shotgun_first_attack_delay_left", 0.0))

	enemy.call("_update_first_shot_delay_runtime", 0.4, true, "ctx_a")
	var after_resume := enemy.get_debug_detection_snapshot() as Dictionary
	var resumed_delay := float(after_resume.get("shotgun_first_attack_delay_left", 0.0))

	enemy.call("_update_first_shot_delay_runtime", 0.1, true, "ctx_b")
	var after_context_switch := enemy.get_debug_detection_snapshot() as Dictionary
	var switched_delay := float(after_context_switch.get("shotgun_first_attack_delay_left", 0.0))

	_t.run_test("before first valid solution: delay is not armed", not bool(before_valid.get("shotgun_first_attack_delay_armed", true)) and is_zero_approx(float(before_valid.get("shotgun_first_attack_delay_left", 1.0))))
	_t.run_test("first valid solution arms delay in 1.2..2.0s", bool(after_arm.get("shotgun_first_attack_delay_armed", false)) and armed_delay >= 1.2 and armed_delay <= 2.0)
	_t.run_test("losing solution pauses timer", is_equal_approx(paused_delay, armed_delay))
	_t.run_test("restoring same solution resumes without reset", resumed_delay < paused_delay and resumed_delay > 0.0)
	_t.run_test("target context change resets and rearms timer", switched_delay >= 1.2 and switched_delay <= 2.0 and switched_delay > resumed_delay)

	world.queue_free()
	await get_tree().process_frame
