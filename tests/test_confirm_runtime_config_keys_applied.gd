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
	print("CONFIRM RUNTIME CONFIG KEYS APPLIED TEST")
	print("============================================================")

	_test_confirm_decay_rate_applied()
	_test_confirm_grace_window_applied()
	_test_minimum_hold_alert_sec_applied()

	_t.summary("CONFIRM RUNTIME CONFIG KEYS APPLIED RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_confirm_decay_rate_applied() -> void:
	var slow = _new_awareness()
	var fast = _new_awareness()
	var base_cfg := _cfg(5.0, 0.0, 0.0, 0.0)
	var slow_cfg := _cfg(5.0, 0.20, 0.0, 0.0)
	var fast_cfg := _cfg(5.0, 2.00, 0.0, 0.0)

	for _i in range(12):
		slow.process_confirm(0.1, true, false, false, base_cfg)
		fast.process_confirm(0.1, true, false, false, base_cfg)

	for _i in range(10):
		slow.process_confirm(0.1, false, false, false, slow_cfg)
		fast.process_confirm(0.1, false, false, false, fast_cfg)

	var slow_confirm := _confirm01(slow)
	var fast_confirm := _confirm01(fast)
	_t.run_test(
		"confirm_decay_rate applied: higher decay lowers confirm faster",
		fast_confirm + 0.01 < slow_confirm
	)


func _test_confirm_grace_window_applied() -> void:
	var no_grace = _new_awareness()
	var long_grace = _new_awareness()
	var prime_cfg := _cfg(5.0, 0.0, 0.0, 0.0)

	for _i in range(10):
		no_grace.process_confirm(0.1, true, false, false, prime_cfg)
		long_grace.process_confirm(0.1, true, false, false, prime_cfg)

	var before_no_grace := _confirm01(no_grace)
	var before_long_grace := _confirm01(long_grace)

	no_grace.process_confirm(0.3, false, false, false, _cfg(5.0, 1.25, 0.0, 0.0))
	long_grace.process_confirm(0.3, false, false, false, _cfg(5.0, 1.25, 1.0, 0.0))

	var after_no_grace := _confirm01(no_grace)
	var after_long_grace := _confirm01(long_grace)

	_t.run_test(
		"confirm_grace_window applied: long grace postpones decay",
		after_long_grace >= before_long_grace - 0.0001 and after_no_grace < before_no_grace - 0.01
	)


func _test_minimum_hold_alert_sec_applied() -> void:
	var short_hold = _new_awareness()
	var long_hold = _new_awareness()
	var short_hold_cfg := _cfg(5.0, 10.0, 0.0, 0.2)
	var long_hold_cfg := _cfg(5.0, 10.0, 0.0, 1.2)

	var short_alert_entered := _enter_alert_state(short_hold, short_hold_cfg)
	var long_alert_entered := _enter_alert_state(long_hold, long_hold_cfg)
	_t.run_test("minimum_hold: short-hold setup enters ALERT", short_alert_entered)
	_t.run_test("minimum_hold: long-hold setup enters ALERT", long_alert_entered)
	if not short_alert_entered or not long_alert_entered:
		return

	var short_time := _time_until_state(short_hold, ENEMY_AWARENESS_SYSTEM_SCRIPT.State.SUSPICIOUS, short_hold_cfg, 4.0)
	var long_time := _time_until_state(long_hold, ENEMY_AWARENESS_SYSTEM_SCRIPT.State.SUSPICIOUS, long_hold_cfg, 4.0)

	_t.run_test(
		"minimum_hold_alert_sec applied: longer hold delays ALERT->SUSPICIOUS",
		long_time > short_time + 0.5
	)


func _new_awareness():
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	return awareness


func _cfg(confirm_time: float, decay_rate: float, grace_window: float, minimum_hold_alert_sec: float) -> Dictionary:
	return {
		"confirm_time_to_engage": confirm_time,
		"confirm_decay_rate": decay_rate,
		"confirm_grace_window": grace_window,
		"suspicious_enter": 0.25,
		"alert_enter": 0.55,
		"minimum_hold_alert_sec": minimum_hold_alert_sec,
	}


func _confirm01(awareness) -> float:
	var snap := awareness.get_ui_snapshot() as Dictionary
	return float(snap.get("confirm01", 0.0))


func _state(awareness) -> int:
	var snap := awareness.get_ui_snapshot() as Dictionary
	return int(snap.get("state", -1))


func _enter_alert_state(awareness, cfg: Dictionary) -> bool:
	for _i in range(64):
		awareness.process_confirm(0.1, true, false, false, cfg)
		if _state(awareness) == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.ALERT):
			return true
	return false


func _time_until_state(awareness, target_state: int, cfg: Dictionary, max_sec: float) -> float:
	var elapsed := 0.0
	while elapsed <= max_sec:
		if _state(awareness) == target_state:
			return elapsed
		awareness.process_confirm(0.1, false, false, false, cfg)
		elapsed += 0.1
	return max_sec + 1.0
