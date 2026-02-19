extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
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
	print("COMBAT->ALERT REQUIRES NO-CONTACT + SEARCH PROGRESS TEST")
	print("============================================================")

	_test_non_lockdown_gates()
	_test_lockdown_window_12_sec()

	_t.summary("COMBAT->ALERT REQUIRES NO-CONTACT + SEARCH PROGRESS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_non_lockdown_gates() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()

	# Enter COMBAT first.
	for _i in range(52):
		awareness.process_confirm(0.1, true, false, false, _cfg(false, 0.0, 0.0, 0.0, false))
	_t.run_test("setup: entered COMBAT", awareness.get_state_name() == "COMBAT")

	var total_elapsed := 0.0
	var transitioned_early := false
	for _i in range(85): # 8.5s no-contact, progress below threshold
		total_elapsed += 0.1
		var transitions := awareness.process_confirm(0.1, false, false, false, _cfg(false, 0.5, total_elapsed, 8.0, false))
		if _has_combat_to_alert(transitions):
			transitioned_early = true
			break
	_t.run_test("no transition before search_progress >= 0.8", not transitioned_early and awareness.get_state_name() == "COMBAT")

	var transitioned_after_progress := false
	for _i in range(10):
		total_elapsed += 0.1
		var transitions := awareness.process_confirm(0.1, false, false, false, _cfg(false, 0.9, total_elapsed, 8.0, false))
		if _has_combat_to_alert(transitions):
			transitioned_after_progress = true
			break
	_t.run_test("transition happens when no-contact + search gates are satisfied", transitioned_after_progress and awareness.get_state_name() == "ALERT")


func _test_lockdown_window_12_sec() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	for _i in range(52):
		awareness.process_confirm(0.1, true, false, false, _cfg(true, 0.0, 0.0, 0.0, false))

	var total_elapsed := 0.0
	var before_12_transition := false
	for _i in range(100): # 10s
		total_elapsed += 0.1
		var transitions := awareness.process_confirm(0.1, false, false, false, _cfg(true, 0.9, total_elapsed, 8.0, false))
		if _has_combat_to_alert(transitions):
			before_12_transition = true
			break
	_t.run_test("lockdown: no transition before 12.0s no-contact window", not before_12_transition and awareness.get_state_name() == "COMBAT")

	var after_12_transition := false
	for _i in range(25): # +2.5s
		total_elapsed += 0.1
		var transitions := awareness.process_confirm(0.1, false, false, false, _cfg(true, 0.9, total_elapsed, 8.0, false))
		if _has_combat_to_alert(transitions):
			after_12_transition = true
			break
	_t.run_test("lockdown: transition allowed after 12.0s gate", after_12_transition and awareness.get_state_name() == "ALERT")


func _cfg(lockdown: bool, progress: float, total_elapsed: float, room_elapsed: float, force_cap: bool) -> Dictionary:
	return {
		"confirm_time_to_engage": 5.0,
		"suspicious_enter": 0.25,
		"alert_enter": 0.55,
		"combat_require_search_progress": true,
		"combat_no_contact_window_sec": 12.0 if lockdown else 8.0,
		"combat_search_progress": progress,
		"combat_search_total_elapsed_sec": total_elapsed,
		"combat_search_room_elapsed_sec": room_elapsed,
		"combat_search_total_cap_sec": 24.0,
		"combat_search_force_complete": force_cap,
	}


func _has_combat_to_alert(transitions: Array[Dictionary]) -> bool:
	for tr_variant in transitions:
		var tr := tr_variant as Dictionary
		if String(tr.get("from_state", "")) != "COMBAT":
			continue
		if String(tr.get("to_state", "")) != "ALERT":
			continue
		return true
	return false
