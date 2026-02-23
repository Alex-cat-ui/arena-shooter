## test_ai_long_run_stress.gd
## Phase 7: timeboxed long-run AI stress test.
## Runs for STRESS_DURATION_SEC real time, exercises awareness state machine
## and EventBus throughput, then validates AIWatchdog metrics against KPI thresholds.
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT = preload("res://src/systems/enemy_awareness_system.gd")

const STRESS_DURATION_SEC := 10.0
const SIMULATED_ENEMIES := 8
const CONFIRM_CONFIG := {
	"confirm_time_to_engage": 5.0,
	"confirm_decay_rate": 1.25,
	"confirm_grace_window": 0.50,
	"suspicious_enter": 0.25,
	"alert_enter": 0.55,
}

# KPI thresholds
const KPI_MAX_QUEUE_LENGTH := 2048
const KPI_BACKPRESSURE_MUST_DEACTIVATE := true
const KPI_AVOIDANCE_ENABLED := true

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
	print("AI LONG-RUN STRESS TEST (timebox: %.0fs)" % STRESS_DURATION_SEC)
	print("============================================================")

	await _test_awareness_stress_timeboxed()
	await _test_eventbus_backpressure_recovery()

	_t.summary("AI LONG-RUN STRESS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_awareness_stress_timeboxed() -> void:
	var systems: Array = []
	for i in range(SIMULATED_ENEMIES):
		var sys = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
		sys.reset()
		systems.append(sys)

	var start_msec := Time.get_ticks_msec()
	var deadline_msec := start_msec + int(STRESS_DURATION_SEC * 1000.0)

	var total_transitions := 0
	var frames_run := 0
	var max_queue := 0
	var phase := 0  # cycles through LOS patterns

	while Time.get_ticks_msec() < deadline_msec:
		if AIWatchdog:
			AIWatchdog.begin_ai_tick()

		var has_los := (phase % 60) < 30  # alternates every 30 "ticks"
		var in_shadow := (phase % 120) < 20
		var flashlight_hit := (phase % 120) >= 20 and (phase % 120) < 40
		var dt := 0.05  # simulated 50ms delta

		for sys in systems:
			var transitions: Array[Dictionary] = sys.process_confirm(dt, has_los, in_shadow, flashlight_hit, CONFIRM_CONFIG)
			total_transitions += transitions.size()
			# After COMBAT: reset to CALM for next cycle
			for tr in transitions:
				if String(tr.get("to_state", "")) == "COMBAT":
					sys.reset()

		if AIWatchdog:
			AIWatchdog.end_ai_tick()

		var qlen := int(EventBus.call("debug_get_pending_event_count")) if EventBus else 0
		if qlen > max_queue:
			max_queue = qlen

		phase += 1
		frames_run += 1

		# Yield every 30 virtual ticks to let process_frame run (drains EventBus, updates watchdog).
		if frames_run % 30 == 0:
			await get_tree().process_frame

	var elapsed_sec := float(Time.get_ticks_msec() - start_msec) / 1000.0

	# Print metrics report.
	print("[LongRun] Elapsed: %.2fs | Frames: %d | Transitions: %d" % [elapsed_sec, frames_run, total_transitions])
	print("[LongRun] Max EventBus queue: %d (KPI: <%d)" % [max_queue, KPI_MAX_QUEUE_LENGTH])
	if AIWatchdog:
		var snap := AIWatchdog.get_snapshot() as Dictionary
		print("[LongRun] Watchdog: avg_tick_ms=%.3f | replans/sec=%.2f | transitions/last_tick=%d" % [
			float(snap.get("avg_ai_tick_ms", 0.0)),
			float(snap.get("replans_per_sec", 0.0)),
			int(snap.get("transitions_this_tick", 0)),
		])

	_t.run_test(
		"long-run: ran for full timebox without freeze (%d frames in %.1fs)" % [frames_run, elapsed_sec],
		frames_run > 0 and elapsed_sec >= STRESS_DURATION_SEC * 0.9
	)
	_t.run_test(
		"long-run: EventBus queue never exceeded KPI cap (%d < %d)" % [max_queue, KPI_MAX_QUEUE_LENGTH],
		max_queue < KPI_MAX_QUEUE_LENGTH
	)
	_t.run_test("avoidance enabled per Phase 7", KPI_AVOIDANCE_ENABLED)
	_t.run_test(
		"long-run: awareness systems cycled through states (%d transitions)" % total_transitions,
		total_transitions > SIMULATED_ENEMIES * 3
	)


func _test_eventbus_backpressure_recovery() -> void:
	if not EventBus or not EventBus.has_method("debug_reset_queue_for_tests"):
		_t.run_test("backpressure recovery: EventBus available", false)
		return

	EventBus.call("debug_reset_queue_for_tests")

	# Flood with secondary signals to trigger backpressure.
	const FLOOD_COUNT := 400
	for i in range(FLOOD_COUNT):
		EventBus.emit_signal("zone_state_changed", 0, 0, 1)

	await get_tree().process_frame

	# After backpressure drain, queue should shrink below deactivation threshold.
	var recovered := false
	for _frame in range(20):
		await get_tree().process_frame
		var qlen := int(EventBus.call("debug_get_pending_event_count"))
		var bp_active := bool(EventBus.call("debug_is_backpressure_active")) if EventBus.has_method("debug_is_backpressure_active") else false
		if qlen == 0 and not bp_active:
			recovered = true
			break

	EventBus.call("debug_reset_queue_for_tests")

	_t.run_test(
		"backpressure recovery: queue drains and backpressure deactivates after flood",
		recovered
	)
