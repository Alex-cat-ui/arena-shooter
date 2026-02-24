## ai_watchdog.gd
## Phase 7: runtime performance monitor for AI subsystems.
## Tracks: EventBus queue length, AI transitions/tick, avg AI tick ms, replans/sec.
## Wired as autoload: AIWatchdog
extends Node

# --- Thresholds ---
const QUEUE_WARN_THRESHOLD := 512
const TICK_MS_WARN_THRESHOLD := 2.0
const REPLANS_PER_SEC_WARN := 8.0
const WARN_MIN_SUSTAIN_SEC := 1.0
const WARN_COOLDOWN_SEC := 20.0

# --- Metrics (exponential moving average, alpha=0.05 for smoothing) ---
const EMA_ALPHA := 0.05
const AI_WATCHDOG_P95_SAMPLE_CAP := 32768

var event_queue_length: int = 0
var transitions_this_tick: int = 0
var avg_ai_tick_ms: float = 0.0
var replans_per_sec: float = 0.0
var replans_total: int = 0
var detour_candidates_evaluated_total: int = 0
var hard_stall_events_total: int = 0
var collision_repath_events_total: int = 0
var _ai_tick_samples_ms: Array[float] = []

# Internal
var _tick_start_usec: int = 0
var _tick_active: bool = false
var _replan_accumulator: float = 0.0
var _replan_window_elapsed: float = 0.0
var _warn_cooldown: float = 0.0
var _queue_warn_elapsed: float = 0.0
var _tick_warn_elapsed: float = 0.0
var _replan_warn_elapsed: float = 0.0


func _process(delta: float) -> void:
	event_queue_length = EventBus.debug_get_pending_event_count() if EventBus else 0

	# Decay replan accumulator over time.
	_replan_window_elapsed += delta
	if _replan_window_elapsed >= 1.0:
		replans_per_sec = lerp(replans_per_sec, _replan_accumulator / _replan_window_elapsed, EMA_ALPHA)
		_replan_accumulator = 0.0
		_replan_window_elapsed = 0.0

	if _warn_cooldown > 0.0:
		_warn_cooldown -= delta

	_update_violation_windows(delta)
	_check_thresholds()


func begin_ai_tick() -> void:
	_tick_start_usec = Time.get_ticks_usec()
	_tick_active = true
	transitions_this_tick = 0


func end_ai_tick() -> void:
	if not _tick_active:
		return
	_tick_active = false
	var dt_ms := maxf(float(Time.get_ticks_usec() - _tick_start_usec) / 1000.0, 0.0)
	avg_ai_tick_ms = lerp(avg_ai_tick_ms, dt_ms, EMA_ALPHA)
	if is_finite(dt_ms):
		_ai_tick_samples_ms.append(dt_ms)
		while _ai_tick_samples_ms.size() > AI_WATCHDOG_P95_SAMPLE_CAP:
			_ai_tick_samples_ms.remove_at(0)


func record_transition() -> void:
	transitions_this_tick += 1


func record_replan() -> void:
	_replan_accumulator += 1.0
	replans_total += 1


func record_detour_candidates_evaluated(count: int) -> void:
	detour_candidates_evaluated_total += maxi(count, 0)


func record_hard_stall_event() -> void:
	hard_stall_events_total += 1


func record_collision_repath_event() -> void:
	collision_repath_events_total += 1


func debug_reset_metrics_for_tests() -> void:
	event_queue_length = 0
	transitions_this_tick = 0
	avg_ai_tick_ms = 0.0
	replans_per_sec = 0.0
	replans_total = 0
	detour_candidates_evaluated_total = 0
	hard_stall_events_total = 0
	collision_repath_events_total = 0
	_ai_tick_samples_ms.clear()
	_tick_start_usec = 0
	_tick_active = false
	_replan_accumulator = 0.0
	_replan_window_elapsed = 0.0
	_warn_cooldown = 0.0
	_queue_warn_elapsed = 0.0
	_tick_warn_elapsed = 0.0
	_replan_warn_elapsed = 0.0


func get_snapshot() -> Dictionary:
	return {
		"event_queue_length": event_queue_length,
		"transitions_this_tick": transitions_this_tick,
		"avg_ai_tick_ms": avg_ai_tick_ms,
		"replans_per_sec": replans_per_sec,
		"ai_ms_p95": _percentile95_ms(),
		"replans_total": replans_total,
		"detour_candidates_evaluated_total": detour_candidates_evaluated_total,
		"hard_stall_events_total": hard_stall_events_total,
		"collision_repath_events_total": collision_repath_events_total,
		"ai_tick_samples_count": _ai_tick_samples_ms.size(),
	}


func _check_thresholds() -> void:
	if _warn_cooldown > 0.0:
		return
	if _queue_warn_elapsed >= WARN_MIN_SUSTAIN_SEC:
		push_warning("[AIWatchdog] EventBus queue high: %d (threshold %d)" % [event_queue_length, QUEUE_WARN_THRESHOLD])
		_warn_cooldown = WARN_COOLDOWN_SEC
	elif _tick_warn_elapsed >= WARN_MIN_SUSTAIN_SEC:
		push_warning("[AIWatchdog] AI tick slow: %.2fms (threshold %.1fms)" % [avg_ai_tick_ms, TICK_MS_WARN_THRESHOLD])
		_warn_cooldown = WARN_COOLDOWN_SEC
	elif _replan_warn_elapsed >= WARN_MIN_SUSTAIN_SEC:
		push_warning("[AIWatchdog] High repath rate: %.1f/sec (threshold %.1f)" % [replans_per_sec, REPLANS_PER_SEC_WARN])
		_warn_cooldown = WARN_COOLDOWN_SEC


func _update_violation_windows(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	_queue_warn_elapsed = _next_violation_elapsed(_queue_warn_elapsed, event_queue_length > QUEUE_WARN_THRESHOLD, safe_delta)
	_tick_warn_elapsed = _next_violation_elapsed(_tick_warn_elapsed, avg_ai_tick_ms > TICK_MS_WARN_THRESHOLD, safe_delta)
	_replan_warn_elapsed = _next_violation_elapsed(_replan_warn_elapsed, replans_per_sec > REPLANS_PER_SEC_WARN, safe_delta)


func _next_violation_elapsed(current: float, violated: bool, delta: float) -> float:
	if not violated:
		return 0.0
	return current + delta


func _percentile95_ms() -> float:
	var n := _ai_tick_samples_ms.size()
	if n <= 0:
		return 0.0
	var sorted_samples: Array = _ai_tick_samples_ms.duplicate()
	sorted_samples.sort()
	var idx := maxi(int(ceil(0.95 * float(n))) - 1, 0)
	idx = mini(idx, sorted_samples.size() - 1)
	return maxf(float(sorted_samples[idx]), 0.0)
