extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

const CONFIRM_CONFIG := {
	"confirm_time_to_engage": 5.0,
	"confirm_decay_rate": 0.10,
	"confirm_grace_window": 0.50,
	"suspicious_enter": 0.25,
	"alert_enter": 0.55,
	"alert_fallback": 0.25,
}

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
	print("ALERT->COMBAT REQUIRES 5S CONTINUOUS CONFIRM TEST")
	print("============================================================")

	_test_alert_to_combat_requires_continuous_confirm()

	_t.summary("ALERT->COMBAT REQUIRES 5S CONTINUOUS CONFIRM RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_alert_to_combat_requires_continuous_confirm() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()

	for _i in range(30):
		awareness.process_confirm(0.1, true, false, false, CONFIRM_CONFIG)
	for _i in range(40):
		awareness.process_confirm(0.1, false, false, false, CONFIRM_CONFIG)
	for _i in range(30):
		awareness.process_confirm(0.1, true, false, false, CONFIRM_CONFIG)

	_t.run_test(
		"without continuous 5s, COMBAT is never entered",
		awareness.get_state_name() != "COMBAT"
	)

	awareness.reset()
	var entered_alert_at := -1.0
	var reached_at := -1.0
	var elapsed := 0.0
	for _i in range(120):
		elapsed += 0.1
		var transitions := awareness.process_confirm(0.1, true, false, false, CONFIRM_CONFIG)
		for tr_variant in transitions:
			var tr := tr_variant as Dictionary
			if String(tr.get("to_state", "")) == "ALERT" and String(tr.get("reason", "")) == "confirm_rising" and entered_alert_at < 0.0:
				entered_alert_at = elapsed
			if String(tr.get("to_state", "")) == "COMBAT" and String(tr.get("reason", "")) == "confirmed_contact":
				reached_at = elapsed
				break
		if reached_at >= 0.0:
			break

	_t.run_test(
		"continuous LOS enters COMBAT in 5.0±0.2s after ALERT",
		entered_alert_at >= 0.0
			and reached_at >= 0.0
			and (reached_at - entered_alert_at) >= 4.8
			and (reached_at - entered_alert_at) <= 5.2
			and awareness.get_state_name() == "COMBAT"
	)


func _has_confirmed_contact_transition(transitions: Array[Dictionary]) -> bool:
	for tr_variant in transitions:
		var tr := tr_variant as Dictionary
		if String(tr.get("to_state", "")) != "COMBAT":
			continue
		if String(tr.get("reason", "")) == "confirmed_contact":
			return true
	return false
