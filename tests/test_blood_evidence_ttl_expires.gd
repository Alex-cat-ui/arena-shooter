extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const BLOOD_EVIDENCE_SYSTEM_SCRIPT := preload("res://src/systems/blood_evidence_system.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class MockBloodEnemy:
	extends Node2D

	var entity_id: int = 14101
	var apply_blood_evidence_calls: int = 0
	var awareness := ENEMY_AWARENESS_SYSTEM_SCRIPT.new()

	func _init() -> void:
		awareness.reset()

	func apply_blood_evidence(_evidence_pos: Vector2) -> bool:
		apply_blood_evidence_calls += 1
		var transitions := awareness.register_blood_evidence()
		return transitions.size() > 0


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("BLOOD EVIDENCE TTL EXPIRES TEST")
	print("============================================================")

	_test_blood_evidence_entry_expires_after_ttl()
	_test_blood_evidence_expired_entry_does_not_trigger()

	_t.summary("BLOOD EVIDENCE TTL EXPIRES RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_blood_evidence_entry_expires_after_ttl() -> void:
	var system = BLOOD_EVIDENCE_SYSTEM_SCRIPT.new()
	system._on_blood_spawned(Vector3.ZERO, 1.0)
	if not system._evidence_entries.is_empty():
		system._evidence_entries[0]["ttl_sec"] = 1.0
	system._process(1.01)

	_t.run_test("blood evidence entry expires after TTL", system._evidence_entries.is_empty())
	system.free()


func _test_blood_evidence_expired_entry_does_not_trigger() -> void:
	var system = BLOOD_EVIDENCE_SYSTEM_SCRIPT.new()
	var entities := Node2D.new()
	system.initialize(entities)
	system._on_blood_spawned(Vector3.ZERO, 1.0)
	if not system._evidence_entries.is_empty():
		system._evidence_entries[0]["ttl_sec"] = 1.0
	system._process(1.01)

	var enemy := MockBloodEnemy.new()
	enemy.global_position = Vector2.ZERO
	enemy.add_to_group("enemies")
	entities.add_child(enemy)
	system._process(0.001)

	_t.run_test("expired entry does not call apply_blood_evidence", enemy.apply_blood_evidence_calls == 0)
	_t.run_test(
		"enemy remains CALM when expired evidence is processed",
		int(enemy.awareness.get_state()) == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.CALM)
	)

	entities.free()
	system.free()
