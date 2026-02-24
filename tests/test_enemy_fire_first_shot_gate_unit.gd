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
	print("ENEMY FIRE FIRST-SHOT GATE UNIT TEST")
	print("============================================================")

	await _test_first_shot_gate_arm_pause_resume_and_context_switch()
	await _test_first_shot_gate_pause_reset_after_max_window()
	await _test_first_shot_gate_ready_requires_armed_delay_and_telegraph_complete()

	_t.summary("ENEMY FIRE FIRST-SHOT GATE UNIT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, id: int) -> Dictionary:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(id, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	return {
		"enemy": enemy,
		"runtime": runtime,
	}


func _test_first_shot_gate_arm_pause_resume_and_context_switch() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs: Dictionary = await _spawn_enemy(world, 84601)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("first-shot gate: runtime is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("reset_first_shot_delay_state")
	runtime.call("update_first_shot_delay_runtime", 0.4, false, "ctx_a")
	var before_valid := enemy.get_debug_detection_snapshot() as Dictionary

	runtime.call("update_first_shot_delay_runtime", 0.1, true, "ctx_a")
	var after_arm := enemy.get_debug_detection_snapshot() as Dictionary
	var armed_left := float(after_arm.get("shotgun_first_attack_delay_left", 0.0))

	runtime.call("update_first_shot_delay_runtime", 0.6, false, "ctx_a")
	var after_pause := enemy.get_debug_detection_snapshot() as Dictionary
	var paused_left := float(after_pause.get("shotgun_first_attack_delay_left", 0.0))

	runtime.call("update_first_shot_delay_runtime", 0.3, true, "ctx_a")
	var after_resume := enemy.get_debug_detection_snapshot() as Dictionary
	var resumed_left := float(after_resume.get("shotgun_first_attack_delay_left", 0.0))

	runtime.call("update_first_shot_delay_runtime", 0.1, true, "ctx_b")
	var after_context_switch := enemy.get_debug_detection_snapshot() as Dictionary
	var switched_left := float(after_context_switch.get("shotgun_first_attack_delay_left", 0.0))

	_t.run_test(
		"first-shot gate: timer is not armed before first valid contact",
		not bool(before_valid.get("shotgun_first_attack_delay_armed", true))
			and is_zero_approx(float(before_valid.get("shotgun_first_attack_delay_left", 1.0)))
	)
	_t.run_test(
		"first-shot gate: first valid contact arms 1.2..2.0 delay",
		bool(after_arm.get("shotgun_first_attack_delay_armed", false))
			and armed_left >= 1.2
			and armed_left <= 2.0
	)
	_t.run_test("first-shot gate: losing valid contact pauses timer", is_equal_approx(paused_left, armed_left))
	_t.run_test("first-shot gate: restoring same context resumes timer", resumed_left < paused_left and resumed_left > 0.0)
	_t.run_test(
		"first-shot gate: context switch re-arms timer with fresh window",
		bool(after_context_switch.get("shotgun_first_attack_delay_armed", false))
			and switched_left >= 1.2
			and switched_left <= 2.0
			and switched_left > resumed_left
	)

	world.queue_free()
	await get_tree().process_frame


func _test_first_shot_gate_pause_reset_after_max_window() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs: Dictionary = await _spawn_enemy(world, 84602)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("first-shot pause reset: runtime is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("reset_first_shot_delay_state")
	runtime.call("update_first_shot_delay_runtime", 0.1, true, "ctx_pause")
	var armed := enemy.get_debug_detection_snapshot() as Dictionary

	runtime.call("update_first_shot_delay_runtime", 2.6, false, "ctx_pause")
	var after_pause_reset := enemy.get_debug_detection_snapshot() as Dictionary

	_t.run_test(
		"first-shot pause reset: timer is armed before long pause",
		bool(armed.get("shotgun_first_attack_delay_armed", false))
	)
	_t.run_test(
		"first-shot pause reset: >2.5s pause clears armed state",
		not bool(after_pause_reset.get("shotgun_first_attack_delay_armed", true))
			and is_zero_approx(float(after_pause_reset.get("shotgun_first_attack_delay_left", 1.0)))
	)

	world.queue_free()
	await get_tree().process_frame


func _test_first_shot_gate_ready_requires_armed_delay_and_telegraph_complete() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs: Dictionary = await _spawn_enemy(world, 84603)
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("first-shot ready gate: runtime is available", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("set_state_patch", {
		"_combat_first_shot_fired": false,
		"_combat_first_shot_delay_armed": true,
		"_combat_first_attack_delay_timer": 0.0,
		"_combat_telegraph_active": true,
		"_combat_telegraph_timer": 0.0,
	})
	var gate_ready := bool(runtime.call("is_first_shot_gate_ready"))

	runtime.call("set_state_patch", {
		"_combat_telegraph_active": true,
		"_combat_telegraph_timer": 0.25,
	})
	var gate_blocked_by_telegraph := not bool(runtime.call("is_first_shot_gate_ready"))

	runtime.call("set_state_patch", {
		"_combat_first_shot_fired": true,
	})
	var gate_open_after_first_shot := bool(runtime.call("is_first_shot_gate_ready"))

	_t.run_test("first-shot ready gate: armed+telegraph_complete opens gate", gate_ready)
	_t.run_test("first-shot ready gate: active telegraph timer blocks gate", gate_blocked_by_telegraph)
	_t.run_test("first-shot ready gate: once first shot fired gate stays open", gate_open_after_first_shot)

	world.queue_free()
	await get_tree().process_frame
