extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeAwareness:
	extends RefCounted

	var _state: int = ENEMY_ALERT_LEVELS_SCRIPT.CALM

	func _init(state: int) -> void:
		_state = state

	func get_awareness_state() -> int:
		return _state


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY DETECTION RUNTIME REACTION WARMUP UNIT TEST")
	print("============================================================")

	await _test_warmup_arms_on_first_calm_los()
	await _test_warmup_expires_and_confirm_resumes()
	await _test_no_warmup_when_awareness_not_calm()

	_t.summary("ENEMY DETECTION RUNTIME REACTION WARMUP UNIT RESULTS")
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
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("detection_runtime", null)
	return {
		"enemy": enemy,
		"runtime": runtime,
	}


func _test_warmup_arms_on_first_calm_los() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 84971)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("reaction warmup runtime: helper is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("set_state_value", "_awareness", FakeAwareness.new(ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	runtime.call("set_state_value", "_reaction_warmup_timer", 0.0)
	runtime.call("set_state_value", "_had_visual_los_last_frame", false)
	var gated := bool(runtime.call("tick_reaction_warmup", 0.016, true))
	var timer := float(runtime.call("get_state_value", "_reaction_warmup_timer", 0.0))

	_t.run_test("reaction warmup runtime: first CALM LOS frame is gated", not gated)
	_t.run_test("reaction warmup runtime: timer is armed on first CALM LOS frame", timer > 0.0)

	world.queue_free()
	await get_tree().process_frame


func _test_warmup_expires_and_confirm_resumes() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 84972)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("reaction warmup runtime expire: helper is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("set_state_value", "_awareness", FakeAwareness.new(ENEMY_ALERT_LEVELS_SCRIPT.CALM))
	runtime.call("set_state_value", "_reaction_warmup_timer", 0.001)
	runtime.call("set_state_value", "_had_visual_los_last_frame", true)
	var gated := bool(runtime.call("tick_reaction_warmup", 0.1, true))
	var timer := float(runtime.call("get_state_value", "_reaction_warmup_timer", 0.0))

	_t.run_test("reaction warmup runtime expire: LOS resumes when timer reaches zero", gated)
	_t.run_test("reaction warmup runtime expire: timer reaches zero after overshoot delta", is_zero_approx(timer))

	world.queue_free()
	await get_tree().process_frame


func _test_no_warmup_when_awareness_not_calm() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 84973)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("reaction warmup runtime non-calm: helper is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("set_state_value", "_awareness", FakeAwareness.new(ENEMY_ALERT_LEVELS_SCRIPT.ALERT))
	runtime.call("set_state_value", "_reaction_warmup_timer", 0.0)
	runtime.call("set_state_value", "_had_visual_los_last_frame", false)
	var gated := bool(runtime.call("tick_reaction_warmup", 0.016, true))
	var timer := float(runtime.call("get_state_value", "_reaction_warmup_timer", 0.0))

	_t.run_test("reaction warmup runtime non-calm: LOS is not gated", gated)
	_t.run_test("reaction warmup runtime non-calm: timer is not armed", is_zero_approx(timer))

	world.queue_free()
	await get_tree().process_frame
