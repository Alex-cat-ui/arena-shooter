extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
const CANON_CONFIG := {
	"confirm_time_to_engage": 5.0,
	"confirm_decay_rate": 0.10,
	"confirm_grace_window": 0.50,
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
	print("ENEMY AWARENESS SYSTEM TEST")
	print("============================================================")

	_test_alert_to_combat_requires_5s_continuous_confirm()
	_test_continuous_5s_confirm_hits_combat_in_tolerance()
	_test_combat_degrades_to_alert_after_timer_without_contact()
	_test_room_alert_propagation_does_not_refresh_combat_timer()
	_test_reinforcement_refreshes_combat_timer()
	_test_deterministic_repeated_runs()

	_t.summary("ENEMY AWARENESS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_alert_to_combat_requires_5s_continuous_confirm() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()

	for _i in range(35):
		awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
	for _i in range(40):
		awareness.process_confirm(0.1, false, false, false, CANON_CONFIG)
	for _i in range(20):
		awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)

	_t.run_test(
		"without continuous 5s confirm COMBAT does not trigger",
		awareness.get_state_name() != "COMBAT"
	)


func _test_continuous_5s_confirm_hits_combat_in_tolerance() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()

	var elapsed := 0.0
	var entered_alert_at := -1.0
	var reached_combat_at := -1.0
	for _i in range(120):
		elapsed += 0.1
		var transitions := awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
		for tr_variant in transitions:
			var tr := tr_variant as Dictionary
			if String(tr.get("to_state", "")) == "ALERT" and String(tr.get("reason", "")) == "confirm_rising" and entered_alert_at < 0.0:
				entered_alert_at = elapsed
			if String(tr.get("to_state", "")) == "COMBAT" and String(tr.get("reason", "")) == "confirmed_contact":
				reached_combat_at = elapsed
				break
		if reached_combat_at >= 0.0:
			break

	_t.run_test(
		"continuous confirm reaches COMBAT in 5.0±0.2s after ALERT entry",
		entered_alert_at >= 0.0
			and reached_combat_at >= 0.0
			and (reached_combat_at - entered_alert_at) >= 4.8
			and (reached_combat_at - entered_alert_at) <= 5.2
			and awareness.get_state_name() == "COMBAT"
	)


func _test_combat_degrades_to_alert_after_timer_without_contact() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness._transition_to_combat_from_damage()
	_t.run_test("damage transition enters COMBAT", awareness.get_state_name() == "COMBAT")

	var combat_ttl := ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	var steps := maxi(int(ceil((combat_ttl + 0.5) / 0.1)), 1)
	var dropped := false
	for _i in range(steps):
		var transitions := awareness.process_confirm(0.1, false, false, false, CANON_CONFIG)
		if _has_transition(transitions, "COMBAT", "ALERT", "timer"):
			dropped = true
			break

	_t.run_test(
		"COMBAT degrades to ALERT after no-contact timer",
		dropped and awareness.get_state_name() == "ALERT"
	)


func _test_room_alert_propagation_does_not_refresh_combat_timer() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness._transition_to_combat_from_damage()
	var combat_timer_before := float(awareness._combat_timer)
	awareness.register_room_alert_propagation()
	var combat_timer_after := float(awareness._combat_timer)
	_t.run_test(
		"room_alert_propagation in COMBAT does not refresh combat timer",
		is_equal_approx(combat_timer_after, combat_timer_before)
	)


func _test_reinforcement_refreshes_combat_timer() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness._transition_to_combat_from_damage()
	awareness._combat_timer = 0.01
	awareness.register_reinforcement()
	_t.run_test(
		"reinforcement in COMBAT refreshes combat timer",
		float(awareness._combat_timer) > 0.01
	)


func _test_deterministic_repeated_runs() -> void:
	var trace_a := _scenario_trace()
	var trace_b := _scenario_trace()
	_t.run_test("deterministic confirm trace across repeated runs", trace_a == trace_b)


func _scenario_trace() -> PackedStringArray:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	var trace := PackedStringArray()
	for i in range(140):
		var has_los := i < 30 or (i >= 45 and i < 95)
		var transitions := awareness.process_confirm(0.1, has_los, false, false, CANON_CONFIG)
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
