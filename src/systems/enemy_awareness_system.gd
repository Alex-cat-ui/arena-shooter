## enemy_awareness_system.gd
## Centralized awareness state machine for enemy perception-driven behavior.
class_name EnemyAwarenessSystem
extends RefCounted

const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

enum State {
	CALM = ENEMY_ALERT_LEVELS_SCRIPT.CALM,
	SUSPICIOUS = ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS,
	ALERT = ENEMY_ALERT_LEVELS_SCRIPT.ALERT,
	COMBAT = ENEMY_ALERT_LEVELS_SCRIPT.COMBAT,
}

enum CombatPhase {
	NONE,
	ENGAGED,
	HOSTILE_SEARCH,
}

var _state: State = State.CALM
var _visibility: float = 0.0
var _suspicion: float = 0.0
var hostile_contact: bool = false
var hostile_damaged: bool = false
var combat_phase: CombatPhase = CombatPhase.NONE
var _confirm_progress: float = 0.0 # 0..1, replaces _suspicion for canon mode
var _has_confirmed_visual: bool = false
var _los_lost_time: float = 0.0
var _suspicion_profile_enabled: bool = false
var _combat_timer: float = 0.0
var _alert_timer: float = 0.0
var _suspicious_timer: float = 0.0
var _combat_lock: bool = false
var _debug_last_flashlight_bonus_raw: float = 1.0
var _debug_last_effective_visibility_pre_clamp: float = 0.0
var _debug_last_effective_visibility_post_clamp: float = 0.0


func reset() -> void:
	_state = State.CALM
	_visibility = 0.0
	_suspicion = 0.0
	hostile_contact = false
	hostile_damaged = false
	combat_phase = CombatPhase.NONE
	_confirm_progress = 0.0
	_has_confirmed_visual = false
	_los_lost_time = 0.0
	_combat_timer = 0.0
	_alert_timer = 0.0
	_suspicious_timer = 0.0
	_combat_lock = false
	_debug_last_flashlight_bonus_raw = 1.0
	_debug_last_effective_visibility_pre_clamp = 0.0
	_debug_last_effective_visibility_post_clamp = 0.0


func get_state() -> State:
	return _state


func get_state_name() -> String:
	return state_to_name(_state)


func get_visibility() -> float:
	return _visibility


func get_suspicion() -> float:
	return _suspicion


func has_confirmed_visual() -> bool:
	return _has_confirmed_visual


func get_awareness_state() -> int:
	return int(_state)


func is_combat_locked() -> bool:
	return _combat_lock


func get_last_suspicion_debug() -> Dictionary:
	return {
		"flashlight_bonus_raw": _debug_last_flashlight_bonus_raw,
		"effective_visibility_pre_clamp": _debug_last_effective_visibility_pre_clamp,
		"effective_visibility_post_clamp": _debug_last_effective_visibility_post_clamp,
	}


func set_suspicion_profile_enabled(enabled: bool) -> void:
	_suspicion_profile_enabled = enabled
	if not enabled:
		_has_confirmed_visual = false
		_los_lost_time = 0.0


func process_suspicion(
	delta: float,
	has_los: bool,
	visibility_factor: float,
	flashlight_hit: bool,
	profile: Dictionary
) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	var dt := maxf(delta, 0.0)
	var gain_rate_calm := float(profile.get("suspicion_gain_rate_calm", 0.35))
	var gain_rate_alert := float(profile.get("suspicion_gain_rate_alert", 1.2))
	var decay_rate := float(profile.get("suspicion_decay_rate", 0.45))
	var combat_threshold := clampf(float(profile.get("combat_threshold", 1.0)), 0.0, 1.0)
	var suspicious_threshold := clampf(float(profile.get("suspicious_threshold", 0.25)), 0.0, 1.0)
	var alert_threshold := clampf(float(profile.get("alert_threshold", 0.55)), 0.0, 1.0)
	var grace_time := maxf(float(profile.get("los_grace_time", 0.3)), 0.0)
	var grace_decay_mult := clampf(float(profile.get("los_grace_decay_mult", 0.25)), 0.0, 1.0)
	var flashlight_bonus := maxf(float(profile.get("flashlight_bonus", 2.5)), 0.0)
	var flashlight_bonus_in_alert := bool(profile.get("flashlight_bonus_in_alert", true))
	var flashlight_bonus_in_combat := bool(profile.get("flashlight_bonus_in_combat", true))

	if _state == State.COMBAT:
		_suspicion = maxf(_suspicion, combat_threshold)
		if has_los:
			_los_lost_time = 0.0
			var combat_effective_visibility := maxf(visibility_factor, 0.0)
			var combat_flashlight_bonus_raw := 1.0
			if flashlight_hit and flashlight_bonus_in_combat:
				combat_flashlight_bonus_raw = flashlight_bonus
				combat_effective_visibility *= combat_flashlight_bonus_raw
			var combat_effective_visibility_post_clamp := clampf(combat_effective_visibility, 0.0, 1.0)
			_debug_last_flashlight_bonus_raw = combat_flashlight_bonus_raw
			_debug_last_effective_visibility_pre_clamp = combat_effective_visibility
			_debug_last_effective_visibility_post_clamp = combat_effective_visibility_post_clamp
			_visibility = combat_effective_visibility_post_clamp
			_suspicion = clampf(_suspicion + gain_rate_alert * combat_effective_visibility_post_clamp * dt, 0.0, 1.0)
		else:
			_debug_last_flashlight_bonus_raw = 1.0
			_debug_last_effective_visibility_pre_clamp = 0.0
			_debug_last_effective_visibility_post_clamp = 0.0
		_advance_timers(dt, has_los, transitions)
		if _state != State.COMBAT:
			_has_confirmed_visual = false
		return transitions

	if has_los:
		_los_lost_time = 0.0
		var effective_visibility := maxf(visibility_factor, 0.0)
		var flashlight_bonus_raw := 1.0
		if _state == State.ALERT and flashlight_hit and flashlight_bonus_in_alert:
			flashlight_bonus_raw = flashlight_bonus
			effective_visibility *= flashlight_bonus_raw
		var effective_visibility_post_clamp := clampf(effective_visibility, 0.0, 1.0)
		_debug_last_flashlight_bonus_raw = flashlight_bonus_raw
		_debug_last_effective_visibility_pre_clamp = effective_visibility
		_debug_last_effective_visibility_post_clamp = effective_visibility_post_clamp
		_visibility = effective_visibility_post_clamp
		var gain_rate := gain_rate_alert if _state == State.ALERT else gain_rate_calm
		_suspicion = clampf(_suspicion + gain_rate * effective_visibility_post_clamp * dt, 0.0, 1.0)
	else:
		var suspicion_before_decay := _suspicion
		_los_lost_time += dt
		_debug_last_flashlight_bonus_raw = 1.0
		_debug_last_effective_visibility_pre_clamp = 0.0
		_debug_last_effective_visibility_post_clamp = 0.0
		var decay_mult := 1.0
		if _los_lost_time < grace_time:
			decay_mult = grace_decay_mult
		_suspicion = clampf(_suspicion - decay_rate * decay_mult * dt, 0.0, 1.0)
		# Keep micro-LOS grace from hard-resetting suspicion because of tiny residual values.
		if _los_lost_time < grace_time and suspicion_before_decay > 0.0 and _suspicion <= 0.0:
			_suspicion = suspicion_before_decay
		_decay_visibility(dt)

	if _state != State.COMBAT and _suspicion >= combat_threshold:
		_has_confirmed_visual = true
		_transition_to(State.COMBAT, "suspicion_visual_confirmed", transitions)
		return transitions

	if (_state == State.CALM or _state == State.SUSPICIOUS) and _suspicion >= alert_threshold:
		_transition_to(State.ALERT, "suspicion", transitions)
	elif _state == State.CALM and _suspicion >= suspicious_threshold:
		_transition_to(State.SUSPICIOUS, "suspicion", transitions)

	_advance_timers(dt, has_los, transitions)
	return transitions


func process_confirm(
	delta: float,
	has_visual_los: bool,
	in_shadow: bool,
	flashlight_hit: bool,
	config: Dictionary
) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	var dt := maxf(delta, 0.0)
	var confirm_time := float(config.get("confirm_time_to_engage", 2.50))
	var decay_rate := float(config.get("confirm_decay_rate", 0.275))
	var grace_window := float(config.get("confirm_grace_window", 0.50))

	# Determine if confirm should accumulate.
	var visual_channel := has_visual_los and not in_shadow
	var can_accumulate := visual_channel or flashlight_hit

	if can_accumulate:
		_los_lost_time = 0.0
		var gain := dt / maxf(confirm_time, 0.001)
		_confirm_progress = clampf(_confirm_progress + gain, 0.0, 1.0)
		_visibility = 1.0
	else:
		_los_lost_time += dt
		if _los_lost_time > grace_window:
			_confirm_progress = clampf(_confirm_progress - decay_rate * dt, 0.0, 1.0)
		_decay_visibility(dt)
	_suspicion = _confirm_progress

	# Hostility persistence: never return to CALM.
	if hostile_contact or hostile_damaged:
		if _state == State.COMBAT and not can_accumulate:
			if combat_phase != CombatPhase.HOSTILE_SEARCH:
				combat_phase = CombatPhase.HOSTILE_SEARCH
		elif _state == State.COMBAT and can_accumulate:
			combat_phase = CombatPhase.ENGAGED
		# Never auto-downgrade from COMBAT when hostile.
		_combat_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.COMBAT)
		return transitions

	# State transitions based on confirm_progress.
	if _confirm_progress >= 1.0 and _state != State.COMBAT:
		hostile_contact = true
		combat_phase = CombatPhase.ENGAGED
		_transition_to(State.COMBAT, "confirmed_contact", transitions)
		return transitions

	if _confirm_progress >= 0.55 and (_state == State.CALM or _state == State.SUSPICIOUS):
		_transition_to(State.ALERT, "confirm_rising", transitions)
	elif _confirm_progress >= 0.25 and _state == State.CALM:
		_transition_to(State.SUSPICIOUS, "confirm_rising", transitions)

	_advance_timers(dt, can_accumulate, transitions)
	return transitions


func register_noise() -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	match _state:
		State.COMBAT:
			_combat_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.COMBAT)
		State.ALERT:
			_alert_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.ALERT)
		_:
			_transition_to(State.ALERT, "noise", transitions)
	return transitions


func register_room_alert_propagation() -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	if _state == State.COMBAT:
		return transitions
	if _state == State.ALERT:
		_alert_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.ALERT)
		return transitions
	_transition_to(State.ALERT, "room_alert_propagation", transitions)
	return transitions


func register_reinforcement() -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	if _suspicion_profile_enabled:
		match _state:
			State.COMBAT:
				_combat_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.COMBAT)
			State.ALERT:
				_alert_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.ALERT)
			_:
				_transition_to(State.ALERT, "reinforcement", transitions)
		return transitions
	if _state == State.COMBAT:
		_combat_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.COMBAT)
		return transitions
	_transition_to(State.COMBAT, "reinforcement", transitions)
	return transitions


func _transition_to_combat_from_damage() -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	hostile_damaged = true
	combat_phase = CombatPhase.ENGAGED
	_transition_to(State.COMBAT, "damage", transitions)
	return transitions


func get_ui_snapshot() -> Dictionary:
	return {
		"state": _state,
		"combat_phase": combat_phase,
		"confirm01": _confirm_progress,
		"hostile_contact": hostile_contact,
		"hostile_damaged": hostile_damaged,
	}


func _advance_timers(delta: float, has_los: bool, transitions: Array[Dictionary]) -> void:
	match _state:
		State.COMBAT:
			if _combat_lock:
				_combat_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.COMBAT)
				return
			if has_los:
				_combat_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.COMBAT)
				return
			_combat_timer = maxf(0.0, _combat_timer - delta)
			if _combat_timer <= 0.0:
				_transition_to(State.ALERT, "timer", transitions)
		State.ALERT:
			if has_los:
				return
			_alert_timer = maxf(0.0, _alert_timer - delta)
			if _alert_timer <= 0.0:
				_transition_to(State.SUSPICIOUS, "timer", transitions)
		State.SUSPICIOUS:
			if has_los:
				return
			_suspicious_timer = maxf(0.0, _suspicious_timer - delta)
			if _suspicious_timer <= 0.0:
				_transition_to(State.CALM, "timer", transitions)
		_:
			pass


func _transition_to(new_state: State, reason: String, transitions: Array[Dictionary]) -> void:
	if _state == new_state:
		return
	if _combat_lock and new_state != State.COMBAT:
		return
	var from_state := _state
	_state = new_state
	match _state:
		State.COMBAT:
			_combat_lock = true
			_visibility = 1.0
			_combat_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.COMBAT)
			_alert_timer = 0.0
			_suspicious_timer = 0.0
			_has_confirmed_visual = true
		State.ALERT:
			_combat_timer = 0.0
			_alert_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.ALERT)
			_suspicious_timer = 0.0
			_has_confirmed_visual = false
		State.SUSPICIOUS:
			_combat_timer = 0.0
			_alert_timer = 0.0
			_suspicious_timer = ENEMY_ALERT_LEVELS_SCRIPT.ttl_for_level(State.SUSPICIOUS)
			_has_confirmed_visual = false
		State.CALM:
			_combat_timer = 0.0
			_alert_timer = 0.0
			_suspicious_timer = 0.0
			_visibility = 0.0
			_has_confirmed_visual = false
		_:
			pass
	transitions.append({
		"from_state": state_to_name(from_state),
		"to_state": state_to_name(_state),
		"reason": reason,
	})


func _decay_visibility(delta: float) -> void:
	var decay_sec := ENEMY_ALERT_LEVELS_SCRIPT.visibility_decay_sec()
	if decay_sec <= 0.0:
		_visibility = 0.0
		return
	_visibility = maxf(0.0, _visibility - (delta / decay_sec))


static func state_to_name(state: int) -> String:
	return ENEMY_ALERT_LEVELS_SCRIPT.level_name(state)
