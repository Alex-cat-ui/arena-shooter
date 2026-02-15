## enemy_awareness_system.gd
## Centralized awareness state machine for enemy perception-driven behavior.
class_name EnemyAwarenessSystem
extends RefCounted

enum State {
	CALM,
	ALERT,
	COMBAT,
}

const COMBAT_LOCK_SEC := 10.0
const POST_COMBAT_ALERT_SEC := 5.0
const VISIBILITY_DECAY_SEC := 2.0

var _state: State = State.CALM
var _visibility: float = 0.0
var _combat_lock_timer: float = 0.0
var _post_alert_timer: float = 0.0


func reset() -> void:
	_state = State.CALM
	_visibility = 0.0
	_combat_lock_timer = 0.0
	_post_alert_timer = 0.0


func get_state() -> State:
	return _state


func get_state_name() -> String:
	return state_to_name(_state)


func get_visibility() -> float:
	return _visibility


func process(delta: float, has_los: bool) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	var dt := maxf(delta, 0.0)

	if has_los:
		_visibility = 1.0
		if _state != State.COMBAT:
			_transition_to(State.COMBAT, "vision", transitions)
	else:
		_decay_visibility(dt)

	_advance_timers(dt, has_los, transitions)
	return transitions


func register_noise() -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	if _state == State.CALM:
		_transition_to(State.ALERT, "noise", transitions)
	elif _state == State.ALERT:
		_post_alert_timer = POST_COMBAT_ALERT_SEC
	elif _state == State.COMBAT:
		_combat_lock_timer = COMBAT_LOCK_SEC
	return transitions


func register_room_alert_propagation() -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	if _state == State.CALM:
		_transition_to(State.ALERT, "room_alert_propagation", transitions)
	elif _state == State.ALERT:
		_post_alert_timer = POST_COMBAT_ALERT_SEC
	return transitions


func register_reinforcement() -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []
	if _state == State.COMBAT:
		_combat_lock_timer = COMBAT_LOCK_SEC
		return transitions
	_transition_to(State.COMBAT, "reinforcement", transitions)
	return transitions


func _advance_timers(delta: float, has_los: bool, transitions: Array[Dictionary]) -> void:
	match _state:
		State.COMBAT:
			if has_los:
				_combat_lock_timer = COMBAT_LOCK_SEC
				return
			_combat_lock_timer = maxf(0.0, _combat_lock_timer - delta)
			if _combat_lock_timer <= 0.0:
				_transition_to(State.ALERT, "timer", transitions)
		State.ALERT:
			if has_los:
				return
			_post_alert_timer = maxf(0.0, _post_alert_timer - delta)
			if _post_alert_timer <= 0.0:
				_transition_to(State.CALM, "timer", transitions)
		_:
			pass


func _transition_to(new_state: State, reason: String, transitions: Array[Dictionary]) -> void:
	if _state == new_state:
		return
	var from_state := _state
	_state = new_state
	match _state:
		State.COMBAT:
			_visibility = 1.0
			_combat_lock_timer = COMBAT_LOCK_SEC
			_post_alert_timer = POST_COMBAT_ALERT_SEC
		State.ALERT:
			_combat_lock_timer = 0.0
			_post_alert_timer = POST_COMBAT_ALERT_SEC
		State.CALM:
			_combat_lock_timer = 0.0
			_post_alert_timer = 0.0
			_visibility = 0.0
		_:
			pass
	transitions.append({
		"from_state": state_to_name(from_state),
		"to_state": state_to_name(_state),
		"reason": reason,
	})


func _decay_visibility(delta: float) -> void:
	if VISIBILITY_DECAY_SEC <= 0.0:
		_visibility = 0.0
		return
	_visibility = maxf(0.0, _visibility - (delta / VISIBILITY_DECAY_SEC))


static func state_to_name(state: int) -> String:
	match state:
		State.CALM:
			return "CALM"
		State.ALERT:
			return "ALERT"
		State.COMBAT:
			return "COMBAT"
		_:
			return "UNKNOWN"
