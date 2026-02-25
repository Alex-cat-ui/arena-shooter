extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeAwareness:
	extends RefCounted

	var _state: int = 0

	func _init(p_state: int) -> void:
		_state = p_state

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
	print("REACTION LATENCY WINDOW RESPECTED TEST")
	print("============================================================")

	_test_reaction_warmup_blocks_confirm_during_window()
	_test_reaction_warmup_expires_and_confirm_resumes()
	_test_no_warmup_when_already_alert()

	_t.summary("REACTION LATENCY WINDOW RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_reaction_warmup_blocks_confirm_during_window() -> void:
	var enemy: Variant = _make_enemy_for_warmup(0)
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("reaction warmup setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		enemy.free()
		return
	var gated: bool = bool(detection_runtime.call("tick_reaction_warmup", 0.016, true))
	var warmup_timer := float(detection_runtime.call("get_state_value", "_reaction_warmup_timer", 0.0))

	_t.run_test("reaction warmup arms on first CALM LOS frame", warmup_timer > 0.0)
	_t.run_test("reaction warmup blocks confirm during active window", gated == false)
	enemy.free()


func _test_reaction_warmup_expires_and_confirm_resumes() -> void:
	var enemy: Variant = _make_enemy_for_warmup(0)
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("reaction expiry setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		enemy.free()
		return
	detection_runtime.call("set_state_value", "_reaction_warmup_timer", 0.001)
	detection_runtime.call("set_state_value", "_had_visual_los_last_frame", true) # avoid re-arming on this tick

	var gated: bool = bool(detection_runtime.call("tick_reaction_warmup", 0.1, true))
	var warmup_timer := float(detection_runtime.call("get_state_value", "_reaction_warmup_timer", 0.0))

	_t.run_test("reaction warmup timer reaches zero after overshoot delta", is_zero_approx(warmup_timer))
	_t.run_test("confirm resumes same tick when warmup reaches zero", gated == true)
	enemy.free()


func _test_no_warmup_when_already_alert() -> void:
	var enemy: Variant = _make_enemy_for_warmup(2)
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("alert warmup setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		enemy.free()
		return
	var gated: bool = bool(detection_runtime.call("tick_reaction_warmup", 0.016, true))
	var warmup_timer := float(detection_runtime.call("get_state_value", "_reaction_warmup_timer", 0.0))

	_t.run_test("no warmup timer is armed when awareness is ALERT", is_zero_approx(warmup_timer))
	_t.run_test("LOS is not gated when awareness is ALERT", gated == true)
	enemy.free()


func _make_enemy_for_warmup(awareness_state: int):
	var enemy: Variant = ENEMY_SCRIPT.new()
	enemy.initialize(7, "zombie")
	var detection_runtime := _detection_runtime(enemy)
	if detection_runtime != null:
		detection_runtime.call("set_state_value", "_awareness", FakeAwareness.new(awareness_state))
		var rng := RandomNumberGenerator.new()
		rng.seed = 1337
		detection_runtime.call("set_state_value", "_perception_rng", rng)
		detection_runtime.call("set_state_value", "_reaction_warmup_timer", 0.0)
		detection_runtime.call("set_state_value", "_had_visual_los_last_frame", false)
	return enemy


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object
