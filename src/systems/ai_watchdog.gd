## ai_watchdog.gd
## Phase 7: runtime performance monitor for AI subsystems.
## Tracks: EventBus queue length, AI transitions/tick, avg AI tick ms, replans/sec.
## Wired as autoload: AIWatchdog
extends Node

# --- Thresholds (read from GameConfig if available, else constants) ---
const QUEUE_WARN_THRESHOLD := 512
const TICK_MS_WARN_THRESHOLD := 2.0
const TRANSITIONS_PER_TICK_WARN := 4
const REPLANS_PER_SEC_WARN := 8.0

# --- Metrics (exponential moving average, alpha=0.05 for smoothing) ---
const EMA_ALPHA := 0.05

var event_queue_length: int = 0
var transitions_this_tick: int = 0
var avg_ai_tick_ms: float = 0.0
var replans_per_sec: float = 0.0

# Internal
var _tick_start_usec: int = 0
var _tick_active: bool = false
var _replan_accumulator: float = 0.0
var _replan_window_elapsed: float = 0.0
var _warn_cooldown: float = 0.0
const _WARN_COOLDOWN_SEC := 5.0


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

	_check_thresholds()


func begin_ai_tick() -> void:
	_tick_start_usec = Time.get_ticks_usec()
	_tick_active = true
	transitions_this_tick = 0


func end_ai_tick() -> void:
	if not _tick_active:
		return
	_tick_active = false
	var dt_ms := float(Time.get_ticks_usec() - _tick_start_usec) / 1000.0
	avg_ai_tick_ms = lerp(avg_ai_tick_ms, dt_ms, EMA_ALPHA)


func record_transition() -> void:
	transitions_this_tick += 1


func record_replan() -> void:
	_replan_accumulator += 1.0


func get_snapshot() -> Dictionary:
	return {
		"event_queue_length": event_queue_length,
		"transitions_this_tick": transitions_this_tick,
		"avg_ai_tick_ms": avg_ai_tick_ms,
		"replans_per_sec": replans_per_sec,
	}


func _check_thresholds() -> void:
	if _warn_cooldown > 0.0:
		return
	if event_queue_length > QUEUE_WARN_THRESHOLD:
		push_warning("[AIWatchdog] EventBus queue high: %d (threshold %d)" % [event_queue_length, QUEUE_WARN_THRESHOLD])
		_warn_cooldown = _WARN_COOLDOWN_SEC
	elif avg_ai_tick_ms > TICK_MS_WARN_THRESHOLD:
		push_warning("[AIWatchdog] AI tick slow: %.2fms (threshold %.1fms)" % [avg_ai_tick_ms, TICK_MS_WARN_THRESHOLD])
		_warn_cooldown = _WARN_COOLDOWN_SEC
	elif replans_per_sec > REPLANS_PER_SEC_WARN:
		push_warning("[AIWatchdog] High repath rate: %.1f/sec (threshold %.1f)" % [replans_per_sec, REPLANS_PER_SEC_WARN])
		_warn_cooldown = _WARN_COOLDOWN_SEC
