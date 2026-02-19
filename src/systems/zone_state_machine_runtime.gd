## zone_state_machine_runtime.gd
## State machine runtime helpers for ZoneDirector.
class_name ZoneStateMachineRuntime
extends RefCounted

var _director: Node = null


func _init(director: Node) -> void:
	_director = director


func process_zone_decay() -> void:
	var now: float = float(_director._now_sec())
	for zone_variant in _director._zone_states.keys():
		var zone_id := int(zone_variant)
		var state: int = int(_director.get_zone_state(zone_id))
		var state_entered: float = float(_director._zone_state_entered_sec.get(zone_id, now))
		var last_event: float = float(_director._zone_last_event_sec.get(zone_id, now))
		var time_in_state: float = now - state_entered
		var no_events_elapsed: float = now - last_event

		if state == int(_director.ZoneState.LOCKDOWN):
			if time_in_state >= float(_director._lockdown_min_hold_sec()) and no_events_elapsed >= float(_director._lockdown_to_elevated_no_events_sec()):
				transition_zone(zone_id, int(_director.ZoneState.ELEVATED), "lockdown_no_event_decay")
		elif state == int(_director.ZoneState.ELEVATED):
			if time_in_state >= float(_director._elevated_min_hold_sec()) and no_events_elapsed >= float(_director._elevated_to_calm_no_events_sec()):
				transition_zone(zone_id, int(_director.ZoneState.CALM), "elevated_no_event_decay")


func transition_zone(zone_id: int, new_state: int, _reason: String) -> bool:
	if zone_id < 0 or not _director._zone_states.has(zone_id):
		return false
	var old_state: int = int(_director.get_zone_state(zone_id))
	if old_state == new_state:
		return false

	var now: float = float(_director._now_sec())
	var last_transition: float = float(_director._zone_last_transition_sec.get(zone_id, -999999.0))
	if now - last_transition < float(_director.MIN_TRANSITION_INTERVAL_SEC):
		return false

	_director._zone_states[zone_id] = new_state
	_director._zone_state_entered_sec[zone_id] = now
	_director._zone_last_transition_sec[zone_id] = now
	var history := (_director._zone_transition_history.get(zone_id, []) as Array).duplicate()
	history.append(now)
	_director._zone_transition_history[zone_id] = history
	_director._sync_reinforcement_budget_caps_for_state_change(zone_id, old_state, new_state)
	emit_zone_state_changed(zone_id, old_state, new_state)
	return true


func emit_zone_state_changed(zone_id: int, old_state: int, new_state: int) -> void:
	if not EventBus:
		return
	if EventBus.has_method("emit_zone_state_changed"):
		EventBus.emit_zone_state_changed(zone_id, old_state, new_state)
	elif EventBus.has_signal("zone_state_changed"):
		EventBus.zone_state_changed.emit(zone_id, old_state, new_state)


func record_zone_event(zone_id: int, event_name: String) -> void:
	if zone_id < 0 or not _director._zone_states.has(zone_id):
		return
	match event_name:
		_director.ZONE_EVENT_ROOM_ALERT, _director.ZONE_EVENT_ROOM_COMBAT, _director.ZONE_EVENT_ACCEPTED_TEAMMATE_CALL, _director.ZONE_EVENT_CONFIRMED_CONTACT_INCREMENT, _director.ZONE_EVENT_ACCEPTED_REINFORCEMENT_CALL, _director.ZONE_EVENT_WAVE_SPAWN_SUCCESS:
			_director._zone_last_event_sec[zone_id] = _director._now_sec()
		_:
			return


func ensure_zone_entry(zone_id: int) -> void:
	if not _director._zone_states.has(zone_id):
		_director._zone_states[zone_id] = int(_director.ZoneState.CALM)
	if not _director._zone_rooms.has(zone_id):
		_director._zone_rooms[zone_id] = []
	if not _director._zone_graph.has(zone_id):
		_director._zone_graph[zone_id] = []
	if not _director._zone_state_entered_sec.has(zone_id):
		_director._zone_state_entered_sec[zone_id] = _director._now_sec()
	if not _director._zone_last_event_sec.has(zone_id):
		_director._zone_last_event_sec[zone_id] = _director._now_sec()
	if not _director._zone_last_transition_sec.has(zone_id):
		_director._zone_last_transition_sec[zone_id] = -999999.0
	if not _director._zone_transition_history.has(zone_id):
		_director._zone_transition_history[zone_id] = []
	if not _director._zone_confirmed_contact_times.has(zone_id):
		_director._zone_confirmed_contact_times[zone_id] = []
	if not _director._reinforcement_waves.has(zone_id):
		_director._reinforcement_waves[zone_id] = 0
	if not _director._reinforcement_enemies.has(zone_id):
		_director._reinforcement_enemies[zone_id] = 0
	if not _director._zone_last_call_sec.has(zone_id):
		_director._zone_last_call_sec[zone_id] = -999999.0
	if not _director._zone_source_call_times.has(zone_id):
		_director._zone_source_call_times[zone_id] = {}
	if not _director._zone_call_dedup_until_sec.has(zone_id):
		_director._zone_call_dedup_until_sec[zone_id] = {}
	_director._ensure_reinforcement_budget_entry(zone_id)
