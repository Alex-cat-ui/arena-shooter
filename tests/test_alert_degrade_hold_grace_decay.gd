extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()

const CONFIG := {
	"confirm_time_to_engage": 5.0,
	"suspicious_enter": 0.25,
	"alert_enter": 0.55,
}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ALERT DEGRADE HOLD/GRACE/DECAY TEST")
	print("============================================================")

	_test_alert_degrade_requires_hold_grace_and_confirm_zero()

	_t.summary("ALERT DEGRADE HOLD/GRACE/DECAY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_alert_degrade_requires_hold_grace_and_confirm_zero() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()

	for _i in range(10):
		awareness.process_confirm(0.1, true, false, false, CONFIG)
	var pre_alert_confirm := float((awareness.get_ui_snapshot() as Dictionary).get("confirm01", 0.0))
	awareness.register_noise()

	var degraded_at := -1.0
	var elapsed_no_contact := 0.0
	var early_degrade := false
	for _i in range(40):
		elapsed_no_contact += 0.1
		var transitions := awareness.process_confirm(0.1, false, false, false, CONFIG)
		if _has_transition(transitions, "ALERT", "SUSPICIOUS", "confirm_fallback"):
			degraded_at = elapsed_no_contact
			if elapsed_no_contact < 2.5:
				early_degrade = true
			break

	var post_confirm := float((awareness.get_ui_snapshot() as Dictionary).get("confirm01", 1.0))
	_t.run_test("setup: ALERT entered with positive confirm", pre_alert_confirm > 0.0)
	_t.run_test("no early ALERT->SUSPICIOUS before hold 2.5s", not early_degrade)
	_t.run_test("ALERT->SUSPICIOUS occurs after hold/grace/decay gate", degraded_at >= 2.5 and degraded_at <= 3.0)
	_t.run_test("degrade occurs only when confirm01 reached zero", post_confirm <= 0.0)


func _has_transition(transitions: Array[Dictionary], from_state: String, to_state: String, reason: String) -> bool:
	for tr_variant in transitions:
		var tr := tr_variant as Dictionary
		if String(tr.get("from_state", "")) != from_state:
			continue
		if String(tr.get("to_state", "")) != to_state:
			continue
		if String(tr.get("reason", "")) != reason:
			continue
		return true
	return false
