extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ZONE_DIRECTOR_SCRIPT := preload("res://src/systems/zone_director.gd")

const CALM := 0
const ELEVATED := 1
const LOCKDOWN := 2

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
	print("WAVE CALL PERMISSION MATRIX AND COOLDOWNS TEST")
	print("============================================================")

	await _test_wave_call_permission_matrix_and_cooldowns()

	_t.summary("WAVE CALL PERMISSION MATRIX AND COOLDOWNS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_wave_call_permission_matrix_and_cooldowns() -> void:
	var director := ZONE_DIRECTOR_SCRIPT.new()
	add_child(director)
	director.initialize([{"id": 0, "rooms": [0]}], [], null)

	var calm_block: Dictionary = director.validate_reinforcement_call(9001, 0, "ALERT", 1, 0.0) as Dictionary
	_t.run_test("CALM blocks reinforcement call", not bool(calm_block.get("accepted", true)))

	director.trigger_elevated(0)
	var elevated_requires_alert: Dictionary = director.validate_reinforcement_call(9001, 0, "COMBAT", 2, 0.0) as Dictionary
	var elevated_accept_first: Dictionary = director.validate_reinforcement_call(9001, 0, "ALERT", 2, 0.0) as Dictionary
	var dedup_block: Dictionary = director.validate_reinforcement_call(9001, 0, "ALERT", 2, 0.5) as Dictionary
	var global_cooldown_block: Dictionary = director.validate_reinforcement_call(9001, 0, "ALERT", 3, 1.0) as Dictionary
	var elevated_accept_second: Dictionary = director.validate_reinforcement_call(9001, 0, "ALERT", 4, 2.8) as Dictionary
	var source_window_block: Dictionary = director.validate_reinforcement_call(9001, 0, "ALERT", 5, 5.7) as Dictionary

	_t.run_test("ELEVATED requires source ALERT", not bool(elevated_requires_alert.get("accepted", true)))
	_t.run_test("ELEVATED accepts source ALERT", bool(elevated_accept_first.get("accepted", false)))
	_t.run_test("call_id dedup TTL blocks duplicate call", not bool(dedup_block.get("accepted", true)))
	_t.run_test("zone global cooldown blocks too-frequent call", not bool(global_cooldown_block.get("accepted", true)))
	_t.run_test("second call accepted after cooldown window", bool(elevated_accept_second.get("accepted", false)))
	_t.run_test("per-enemy call window limit blocks third call", not bool(source_window_block.get("accepted", true)))

	director.update(2.2)
	director.trigger_lockdown(0)
	var lockdown_accept_combat: Dictionary = director.validate_reinforcement_call(9002, 0, "COMBAT", 6, 6.0) as Dictionary
	var lockdown_reject_calm: Dictionary = director.validate_reinforcement_call(9002, 0, "CALM", 7, 8.0) as Dictionary
	_t.run_test("LOCKDOWN accepts source COMBAT", bool(lockdown_accept_combat.get("accepted", false)))
	_t.run_test("LOCKDOWN still rejects source outside ALERT/COMBAT", not bool(lockdown_reject_calm.get("accepted", true)))

	director.queue_free()
	await get_tree().process_frame
