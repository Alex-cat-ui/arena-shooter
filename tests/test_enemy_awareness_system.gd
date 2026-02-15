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
	print("ENEMY AWARENESS SYSTEM TEST")
	print("============================================================")

	_test_thresholds_and_timers()
	_test_visibility_decay_2s()
	_test_post_alert_los_reenters_combat()
	_test_deterministic_repeated_runs()

	_t.summary("ENEMY AWARENESS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_thresholds_and_timers() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()

	var transitions := awareness.process(0.1, true)
	_t.run_test("LOS enters COMBAT", _has_transition(transitions, "CALM", "COMBAT", "vision"))

	var had_early_transition := false
	for _i in range(99):
		var step := awareness.process(0.1, false)
		if not step.is_empty():
			had_early_transition = true
	_t.run_test("COMBAT lock keeps state for first 9.9s", awareness.get_state_name() == "COMBAT" and not had_early_transition)

	var combat_to_alert := false
	for _i in range(2):
		transitions = awareness.process(0.1, false)
		if _has_transition(transitions, "COMBAT", "ALERT", "timer"):
			combat_to_alert = true
			break
	_t.run_test("After ~10.0s no LOS: COMBAT -> ALERT", combat_to_alert)

	var calm_too_early := false
	for _i in range(49):
		var step := awareness.process(0.1, false)
		if not step.is_empty():
			calm_too_early = true
	_t.run_test("ALERT hold for first 4.9s", awareness.get_state_name() == "ALERT" and not calm_too_early)

	var alert_to_calm := false
	for _i in range(2):
		transitions = awareness.process(0.1, false)
		if _has_transition(transitions, "ALERT", "CALM", "timer"):
			alert_to_calm = true
			break
	_t.run_test("After ~5.0s post-alert: ALERT -> CALM", alert_to_calm)


func _test_visibility_decay_2s() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.process(0.1, true)

	for _i in range(20):
		awareness.process(0.1, false)

	_t.run_test("Visibility decays to zero in 2 seconds", is_zero_approx(awareness.get_visibility()))
	_t.run_test("Visibility decay does not bypass combat lock", awareness.get_state_name() == "COMBAT")


func _test_post_alert_los_reenters_combat() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.process(0.1, true)
	for _i in range(102):
		awareness.process(0.1, false)
	_t.run_test("Reached ALERT after combat lock expiration", awareness.get_state_name() == "ALERT")

	for _i in range(15):
		awareness.process(0.1, false)
	var transitions := awareness.process(0.1, true)
	_t.run_test("LOS during post-alert returns to COMBAT", _has_transition(transitions, "ALERT", "COMBAT", "vision"))

	for _i in range(99):
		awareness.process(0.1, false)
	_t.run_test("Re-entered COMBAT restarts 10s lock", awareness.get_state_name() == "COMBAT")


func _test_deterministic_repeated_runs() -> void:
	var trace_a := _scenario_trace()
	var trace_b := _scenario_trace()
	_t.run_test("Deterministic trace across repeated runs", trace_a == trace_b)


func _scenario_trace() -> PackedStringArray:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	var trace := PackedStringArray()
	for i in range(160):
		var has_los := i < 10 or (i >= 80 and i < 88)
		var transitions := awareness.process(0.1, has_los)
		for tr_variant in transitions:
			var tr := tr_variant as Dictionary
			trace.append("%03d:%s>%s:%s" % [
				i,
				String(tr.get("from_state", "")),
				String(tr.get("to_state", "")),
				String(tr.get("reason", "")),
			])
		trace.append("%03d:%s:%.3f" % [i, awareness.get_state_name(), awareness.get_visibility()])
	return trace


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
