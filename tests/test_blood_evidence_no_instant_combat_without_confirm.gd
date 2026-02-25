extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

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
	print("BLOOD EVIDENCE NO INSTANT COMBAT TEST")
	print("============================================================")

	_test_blood_evidence_does_not_set_alert()
	_test_blood_evidence_does_not_set_combat()
	_test_blood_evidence_no_op_when_already_alert()

	_t.summary("BLOOD EVIDENCE NO INSTANT COMBAT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_blood_evidence_does_not_set_alert() -> void:
	var enemy := _make_enemy()
	enemy.apply_blood_evidence(Vector2(50.0, 50.0))
	var state := _awareness_state(enemy)
	_t.run_test(
		"blood evidence does not set ALERT directly",
		state != ENEMY_ALERT_LEVELS_SCRIPT.ALERT
	)
	enemy.free()


func _test_blood_evidence_does_not_set_combat() -> void:
	var enemy := _make_enemy()
	enemy.apply_blood_evidence(Vector2(50.0, 50.0))
	var state := _awareness_state(enemy)
	_t.run_test(
		"blood evidence does not set COMBAT directly",
		state != ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)
	enemy.free()


func _test_blood_evidence_no_op_when_already_alert() -> void:
	var enemy := _make_enemy()
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("blood evidence no-op setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		enemy.free()
		return
	var awareness := detection_runtime.call("get_state_value", "_awareness", null) as Object
	if awareness != null and awareness.has_method("register_noise"):
		awareness.call("register_noise")
	var anchor_before := detection_runtime.call("get_state_value", "_investigate_anchor", Vector2.ZERO) as Vector2
	var anchor_valid_before := bool(detection_runtime.call("get_state_value", "_investigate_anchor_valid", false))
	var accepted := enemy.apply_blood_evidence(Vector2(50.0, 50.0))

	_t.run_test("blood evidence is ignored when enemy is already ALERT", accepted == false)
	_t.run_test(
		"enemy state remains ALERT after blood evidence no-op",
		_awareness_state(enemy) == ENEMY_ALERT_LEVELS_SCRIPT.ALERT
	)
	var anchor_after := detection_runtime.call("get_state_value", "_investigate_anchor", Vector2.ZERO) as Vector2
	var anchor_valid_after := bool(detection_runtime.call("get_state_value", "_investigate_anchor_valid", false))
	_t.run_test(
		"blood evidence no-op preserves investigate anchor fields",
		anchor_after == anchor_before and anchor_valid_after == anchor_valid_before
	)
	enemy.free()


func _make_enemy() -> Enemy:
	var enemy := ENEMY_SCRIPT.new()
	enemy.initialize(14002, "zombie")
	var detection_runtime := _detection_runtime(enemy)
	if detection_runtime != null:
		var awareness := ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
		awareness.reset()
		detection_runtime.call("set_state_value", "_awareness", awareness)
		detection_runtime.call("set_state_value", "_investigate_anchor", Vector2.ZERO)
		detection_runtime.call("set_state_value", "_investigate_anchor_valid", false)
	return enemy


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object


func _awareness_state(enemy: Enemy) -> int:
	var detection_runtime := _detection_runtime(enemy)
	if detection_runtime == null:
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	var awareness := detection_runtime.call("get_state_value", "_awareness", null) as Object
	if awareness == null or not awareness.has_method("get_state"):
		return ENEMY_ALERT_LEVELS_SCRIPT.CALM
	return int(awareness.call("get_state"))
