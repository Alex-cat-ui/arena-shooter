extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
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
	var state := int(enemy._awareness.get_state())
	_t.run_test(
		"blood evidence does not set ALERT directly",
		state != int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.ALERT)
	)
	enemy.free()


func _test_blood_evidence_does_not_set_combat() -> void:
	var enemy := _make_enemy()
	enemy.apply_blood_evidence(Vector2(50.0, 50.0))
	var state := int(enemy._awareness.get_state())
	_t.run_test(
		"blood evidence does not set COMBAT directly",
		state != int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT)
	)
	enemy.free()


func _test_blood_evidence_no_op_when_already_alert() -> void:
	var enemy := _make_enemy()
	enemy._awareness.register_noise()
	var anchor_before := enemy._investigate_anchor
	var anchor_valid_before := bool(enemy._investigate_anchor_valid)
	var accepted := enemy.apply_blood_evidence(Vector2(50.0, 50.0))

	_t.run_test("blood evidence is ignored when enemy is already ALERT", accepted == false)
	_t.run_test(
		"enemy state remains ALERT after blood evidence no-op",
		int(enemy._awareness.get_state()) == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.ALERT)
	)
	_t.run_test(
		"blood evidence no-op preserves investigate anchor fields",
		enemy._investigate_anchor == anchor_before and bool(enemy._investigate_anchor_valid) == anchor_valid_before
	)
	enemy.free()


func _make_enemy() -> Enemy:
	var enemy := ENEMY_SCRIPT.new()
	enemy.entity_id = 14002
	enemy._awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	enemy._awareness.reset()
	enemy._investigate_anchor = Vector2.ZERO
	enemy._investigate_anchor_valid = false
	return enemy
