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
	print("BLOOD EVIDENCE INVESTIGATE ANCHOR TEST")
	print("============================================================")

	_test_blood_evidence_sets_investigate_anchor()
	_test_blood_evidence_state_becomes_suspicious()

	_t.summary("BLOOD EVIDENCE INVESTIGATE ANCHOR RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_blood_evidence_sets_investigate_anchor() -> void:
	var enemy := _make_enemy()
	var evidence_pos := Vector2(100.0, 200.0)
	var accepted := enemy.apply_blood_evidence(evidence_pos)
	var anchor := enemy.get("_investigate_anchor") as Vector2
	var anchor_valid := bool(enemy.get("_investigate_anchor_valid"))

	_t.run_test("blood evidence is accepted from CALM enemy", accepted)
	_t.run_test(
		"blood evidence sets investigate anchor + valid flag",
		anchor.distance_to(evidence_pos) <= 0.001 and anchor_valid
	)
	enemy.free()


func _test_blood_evidence_state_becomes_suspicious() -> void:
	var enemy := _make_enemy()
	enemy.apply_blood_evidence(Vector2(100.0, 200.0))
	var awareness = enemy.get("_awareness")
	var state_ok := awareness != null and int(awareness.get_state()) == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.SUSPICIOUS)
	_t.run_test("blood evidence moves CALM enemy to SUSPICIOUS", state_ok)
	enemy.free()


func _make_enemy() -> Enemy:
	var enemy := ENEMY_SCRIPT.new()
	enemy.entity_id = 14001
	enemy._awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	enemy._awareness.reset()
	enemy._last_seen_pos = Vector2(999.0, 999.0)
	enemy._last_seen_age = 0.1
	enemy._investigate_anchor_valid = false
	return enemy
