extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

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

	_test_sticky_combat_no_downgrade()
	_test_visibility_decay_2s()
	_test_alert_to_combat_locks_sticky()
	_test_deterministic_repeated_runs()

	_t.summary("ENEMY AWARENESS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_sticky_combat_no_downgrade() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()

	var transitions := awareness.process(0.1, true)
	_t.run_test("LOS enters COMBAT", _has_transition(transitions, "CALM", "COMBAT", "vision"))

	var had_downgrade_transition := false
	for _i in range(260):
		var step := awareness.process(0.1, false)
		if _has_non_combat_transition(step):
			had_downgrade_transition = true
	_t.run_test(
		"COMBAT stays sticky under prolonged no LOS",
		awareness.get_state_name() == "COMBAT" and not had_downgrade_transition
	)
	_t.run_test("COMBAT lock flag remains enabled", awareness.is_combat_locked())
	_t.run_test("COMBAT keeps confirmed visual sticky", bool(awareness.has_confirmed_visual()))


func _test_visibility_decay_2s() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.process(0.1, true)

	var decay_sec := ENEMY_ALERT_LEVELS_SCRIPT.visibility_decay_sec()
	var frames := maxi(int(ceil(maxf(decay_sec, 0.0) / 0.1)), 1)
	for _i in range(frames):
		awareness.process(0.1, false)

	_t.run_test("Visibility decays to zero on configured timer", is_zero_approx(awareness.get_visibility()))
	_t.run_test("Visibility decay does not bypass combat lock", awareness.get_state_name() == "COMBAT")


func _test_alert_to_combat_locks_sticky() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	var alert_transitions := awareness.register_noise()
	_t.run_test("Noise enters ALERT first", _has_transition(alert_transitions, "CALM", "ALERT", "noise"))
	var combat_transitions := awareness.process(0.1, true)
	_t.run_test("LOS from ALERT enters COMBAT", _has_transition(combat_transitions, "ALERT", "COMBAT", "vision"))
	for _i in range(160):
		awareness.process(0.1, false)
	_t.run_test("Post-alert COMBAT remains sticky", awareness.get_state_name() == "COMBAT" and awareness.is_combat_locked())


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


func _has_non_combat_transition(transitions: Array[Dictionary]) -> bool:
	for tr_variant in transitions:
		var tr := tr_variant as Dictionary
		if String(tr.get("to_state", "")) != "COMBAT":
			return true
	return false


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
