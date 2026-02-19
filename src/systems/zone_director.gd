## zone_director.gd
## Single-owner zone intensity machine (CALM/ELEVATED/LOCKDOWN) with hysteresis
## and centralized reinforcement-call validation.
class_name ZoneDirector
extends Node


enum ZoneState {
	CALM = 0,
	ELEVATED = 1,
	LOCKDOWN = 2,
}

const AWARENESS_ALERT := "ALERT"
const AWARENESS_COMBAT := "COMBAT"

const ZONE_EVENT_ROOM_ALERT := "room_alert"
const ZONE_EVENT_ROOM_COMBAT := "room_combat"
const ZONE_EVENT_ACCEPTED_TEAMMATE_CALL := "accepted_teammate_call"
const ZONE_EVENT_CONFIRMED_CONTACT_INCREMENT := "confirmed_contact_increment"
const ZONE_EVENT_ACCEPTED_REINFORCEMENT_CALL := "accepted_reinforcement_call"
const ZONE_EVENT_WAVE_SPAWN_SUCCESS := "wave_spawn_success"

const DEFAULT_ELEVATED_MIN_HOLD_SEC := 16.0
const DEFAULT_LOCKDOWN_MIN_HOLD_SEC := 24.0
const DEFAULT_ELEVATED_TO_CALM_NO_EVENTS_SEC := 12.0
const DEFAULT_LOCKDOWN_TO_ELEVATED_NO_EVENTS_SEC := 18.0
const DEFAULT_CONFIRMED_CONTACT_THRESHOLD := 3
const DEFAULT_CONFIRMED_CONTACT_WINDOW_SEC := 8.0
const DEFAULT_CALLS_PER_ENEMY_PER_WINDOW := 2
const DEFAULT_CALL_WINDOW_SEC := 20.0
const DEFAULT_GLOBAL_CALL_COOLDOWN_SEC := 3.0
const DEFAULT_CALL_DEDUP_TTL_SEC := 1.5
const MIN_TRANSITION_INTERVAL_SEC := 2.0

const DEFAULT_CALM_PROFILE := {
	"alert_sweep_budget_scale": 0.85,
	"role_weights_profiled": {"PRESSURE": 0.30, "HOLD": 0.60, "FLANK": 0.10},
	"reinforcement_cooldown_scale": 1.25,
	"flashlight_active_cap": 1,
	"zone_refill_scale": 0.0,
}

const DEFAULT_ELEVATED_PROFILE := {
	"alert_sweep_budget_scale": 1.10,
	"role_weights_profiled": {"PRESSURE": 0.45, "HOLD": 0.40, "FLANK": 0.15},
	"reinforcement_cooldown_scale": 0.90,
	"flashlight_active_cap": 2,
	"zone_refill_scale": 0.35,
}

const DEFAULT_LOCKDOWN_PROFILE := {
	"alert_sweep_budget_scale": 1.45,
	"role_weights_profiled": {"PRESSURE": 0.60, "HOLD": 0.25, "FLANK": 0.15},
	"reinforcement_cooldown_scale": 0.65,
	"flashlight_active_cap": 4,
	"zone_refill_scale": 1.00,
}

var _zone_states: Dictionary = {} # zone_id -> ZoneState
var _zone_rooms: Dictionary = {} # zone_id -> Array[int] room_ids
var _room_to_zone: Dictionary = {} # room_id -> zone_id
var _zone_graph: Dictionary = {} # zone_id -> Array[int] neighbor zone_ids

var _zone_state_entered_sec: Dictionary = {} # zone_id -> float
var _zone_last_event_sec: Dictionary = {} # zone_id -> float
var _zone_last_transition_sec: Dictionary = {} # zone_id -> float
var _zone_transition_history: Dictionary = {} # zone_id -> Array[float]

var _zone_confirmed_contact_times: Dictionary = {} # zone_id -> Array[float]
var _enemy_room_by_id: Dictionary = {} # enemy_id -> room_id

var _reinforcement_waves: Dictionary = {} # zone_id -> int
var _reinforcement_enemies: Dictionary = {} # zone_id -> int
var _zone_wave_budget_credit: Dictionary = {} # zone_id -> float
var _zone_enemy_budget_credit: Dictionary = {} # zone_id -> float

var _zone_last_call_sec: Dictionary = {} # zone_id -> float
var _zone_source_call_times: Dictionary = {} # zone_id -> Dictionary[source_enemy_id -> Array[float]]
var _zone_call_dedup_until_sec: Dictionary = {} # zone_id -> Dictionary[call_id -> expiry_sec]

var _alert_system: EnemyAlertSystem = null
var _sim_time_sec: float = 0.0
var _debug_time_override_sec: float = -1.0
var _event_bus_connected: bool = false


func _ready() -> void:
	_connect_event_bus_signals()


func initialize(zone_config: Array[Dictionary], zone_edges: Array[Array], alert_system: EnemyAlertSystem = null) -> void:
	_zone_states.clear()
	_zone_rooms.clear()
	_room_to_zone.clear()
	_zone_graph.clear()
	_zone_state_entered_sec.clear()
	_zone_last_event_sec.clear()
	_zone_last_transition_sec.clear()
	_zone_transition_history.clear()
	_zone_confirmed_contact_times.clear()
	_enemy_room_by_id.clear()
	_reinforcement_waves.clear()
	_reinforcement_enemies.clear()
	_zone_wave_budget_credit.clear()
	_zone_enemy_budget_credit.clear()
	_zone_last_call_sec.clear()
	_zone_source_call_times.clear()
	_zone_call_dedup_until_sec.clear()
	_alert_system = alert_system
	_sim_time_sec = 0.0
	_debug_time_override_sec = -1.0

	for zone_variant in zone_config:
		var zone_id := int(zone_variant.get("id", zone_variant.get("zone_id", -1)))
		if zone_id < 0:
			continue
		_ensure_zone_entry(zone_id)
		var rooms: Array[int] = []
		var room_source: Array = zone_variant.get("rooms", zone_variant.get("room_ids", [])) as Array
		for room_variant in room_source:
			var room_id := int(room_variant)
			if room_id < 0:
				continue
			rooms.append(room_id)
			_room_to_zone[room_id] = zone_id
		_zone_rooms[zone_id] = rooms

	for edge_variant in zone_edges:
		var edge := edge_variant as Array
		if edge.size() < 2:
			continue
		var a := int(edge[0])
		var b := int(edge[1])
		if a < 0 or b < 0 or a == b:
			continue
		_ensure_zone_entry(a)
		_ensure_zone_entry(b)
		var neighbors_a := (_zone_graph.get(a, []) as Array).duplicate()
		if not neighbors_a.has(b):
			neighbors_a.append(b)
		_zone_graph[a] = neighbors_a
		var neighbors_b := (_zone_graph.get(b, []) as Array).duplicate()
		if not neighbors_b.has(a):
			neighbors_b.append(a)
		_zone_graph[b] = neighbors_b

	_connect_event_bus_signals()


func update(delta: float) -> void:
	_connect_event_bus_signals()
	var dt := maxf(delta, 0.0)
	if dt <= 0.0:
		return
	_sim_time_sec += dt
	_refill_reinforcement_budgets(dt)
	_prune_confirmed_contact_windows()
	_prune_reinforcement_call_windows_and_dedup()
	_process_zone_decay()


func get_zone_state(zone_id: int) -> int:
	if zone_id < 0:
		return -1
	return int(_zone_states.get(zone_id, -1))


func get_zone_for_room(room_id: int) -> int:
	if room_id < 0:
		return -1
	return int(_room_to_zone.get(room_id, -1))


func get_zone_profile(zone_id: int) -> Dictionary:
	return _profile_for_state(get_zone_state(zone_id))


func get_zone_profile_for_state(state: int) -> Dictionary:
	return _profile_for_state(state)


func trigger_elevated(zone_id: int) -> void:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return
	_transition_zone(zone_id, ZoneState.ELEVATED, "manual_trigger_elevated")


func trigger_lockdown(zone_id: int) -> void:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return
	_transition_zone(zone_id, ZoneState.LOCKDOWN, "manual_trigger_lockdown")


func record_accepted_teammate_call(source_room_id: int, target_room_id: int) -> bool:
	var zone_id := get_zone_for_room(target_room_id)
	if zone_id < 0:
		zone_id = get_zone_for_room(source_room_id)
	if zone_id < 0:
		return false
	_record_zone_event(zone_id, ZONE_EVENT_ACCEPTED_TEAMMATE_CALL)
	if get_zone_state(zone_id) == ZoneState.CALM:
		_transition_zone(zone_id, ZoneState.ELEVATED, ZONE_EVENT_ACCEPTED_TEAMMATE_CALL)
	return true


func record_confirmed_contact_increment(room_id: int) -> void:
	var zone_id := get_zone_for_room(room_id)
	if zone_id < 0:
		return
	_record_confirmed_contact_for_zone(zone_id)


func can_spawn_reinforcement(zone_id: int) -> bool:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return false
	_ensure_reinforcement_budget_entry(zone_id)
	var caps := _get_reinforcement_caps(zone_id)
	var wave_credit := float(_zone_wave_budget_credit.get(zone_id, 0.0))
	var enemy_credit := float(_zone_enemy_budget_credit.get(zone_id, 0.0))
	return caps.max_waves > 0 and caps.max_enemies > 0 and wave_credit >= 1.0 and enemy_credit >= 1.0


func register_reinforcement_wave(zone_id: int, count: int) -> void:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return
	_ensure_reinforcement_budget_entry(zone_id)
	var used_enemy_credit := maxf(float(maxi(count, 0)), 0.0)
	_zone_wave_budget_credit[zone_id] = maxf(float(_zone_wave_budget_credit.get(zone_id, 0.0)) - 1.0, 0.0)
	_zone_enemy_budget_credit[zone_id] = maxf(float(_zone_enemy_budget_credit.get(zone_id, 0.0)) - used_enemy_credit, 0.0)
	_reinforcement_waves[zone_id] = int(_reinforcement_waves.get(zone_id, 0)) + 1
	_reinforcement_enemies[zone_id] = int(_reinforcement_enemies.get(zone_id, 0)) + maxi(count, 0)
	_record_zone_event(zone_id, ZONE_EVENT_WAVE_SPAWN_SUCCESS)


func validate_reinforcement_call(
	source_enemy_id: int,
	source_room_id: int,
	source_awareness_state: String,
	call_id: int,
	now_sec: float = -1.0
) -> Dictionary:
	var zone_id := get_zone_for_room(source_room_id)
	if zone_id < 0:
		return _rejected_call(zone_id, "invalid_zone")
	if call_id <= 0:
		return _rejected_call(zone_id, "invalid_call_id")
	if source_enemy_id <= 0:
		return _rejected_call(zone_id, "invalid_source_enemy_id")

	var now := _now_sec(now_sec)
	_prune_reinforcement_call_data_for_zone(zone_id, now)

	var dedup := (_zone_call_dedup_until_sec.get(zone_id, {}) as Dictionary).duplicate(true)
	var call_key := str(call_id)
	if dedup.has(call_key) and float(dedup.get(call_key, 0.0)) > now:
		return _rejected_call(zone_id, "dedup_ttl")

	var zone_state := get_zone_state(zone_id)
	if zone_state == ZoneState.CALM:
		return _rejected_call(zone_id, "permission_calm")
	if zone_state == ZoneState.ELEVATED and source_awareness_state != AWARENESS_ALERT:
		return _rejected_call(zone_id, "permission_elevated_requires_alert")
	if zone_state == ZoneState.LOCKDOWN and source_awareness_state != AWARENESS_ALERT and source_awareness_state != AWARENESS_COMBAT:
		return _rejected_call(zone_id, "permission_lockdown_requires_alert_or_combat")

	var profile := _profile_for_state(zone_state)
	var cooldown_scale := maxf(float(profile.get("reinforcement_cooldown_scale", 1.0)), 0.0)
	var global_cooldown := _global_call_cooldown_sec() * cooldown_scale
	var last_zone_call := float(_zone_last_call_sec.get(zone_id, -999999.0))
	if now - last_zone_call < global_cooldown:
		return _rejected_call(zone_id, "global_cooldown")

	var per_zone_calls := (_zone_source_call_times.get(zone_id, {}) as Dictionary).duplicate(true)
	var source_times := (per_zone_calls.get(source_enemy_id, []) as Array).duplicate()
	var call_window_sec := _call_window_sec()
	var pruned_source_times: Array = []
	for time_variant in source_times:
		var ts := float(time_variant)
		if now - ts <= call_window_sec:
			pruned_source_times.append(ts)
	if pruned_source_times.size() >= _calls_per_enemy_per_window():
		return _rejected_call(zone_id, "source_window_limit")

	if not can_spawn_reinforcement(zone_id):
		return _rejected_call(zone_id, "budget_exhausted")

	pruned_source_times.append(now)
	per_zone_calls[source_enemy_id] = pruned_source_times
	_zone_source_call_times[zone_id] = per_zone_calls
	_zone_last_call_sec[zone_id] = now
	dedup[call_key] = now + _call_dedup_ttl_sec()
	_zone_call_dedup_until_sec[zone_id] = dedup
	_record_zone_event(zone_id, ZONE_EVENT_ACCEPTED_REINFORCEMENT_CALL)

	return {
		"accepted": true,
		"reason": "ok",
		"zone_id": zone_id,
	}


func debug_set_time_override_sec(time_sec: float) -> void:
	_debug_time_override_sec = maxf(time_sec, 0.0)


func debug_clear_time_override_sec() -> void:
	_debug_time_override_sec = -1.0


func debug_get_zone_timing_snapshot(zone_id: int) -> Dictionary:
	var now := _now_sec()
	return {
		"state_entered_sec": float(_zone_state_entered_sec.get(zone_id, now)),
		"last_event_sec": float(_zone_last_event_sec.get(zone_id, now)),
		"last_transition_sec": float(_zone_last_transition_sec.get(zone_id, -999999.0)),
		"time_in_state_sec": now - float(_zone_state_entered_sec.get(zone_id, now)),
		"idle_sec": now - float(_zone_last_event_sec.get(zone_id, now)),
		"transition_history": (_zone_transition_history.get(zone_id, []) as Array).duplicate(),
	}


func debug_get_zone_budget_snapshot(zone_id: int) -> Dictionary:
	return {
		"wave_credit": float(_zone_wave_budget_credit.get(zone_id, 0.0)),
		"enemy_credit": float(_zone_enemy_budget_credit.get(zone_id, 0.0)),
		"reinforcement_waves": int(_reinforcement_waves.get(zone_id, 0)),
		"reinforcement_enemies": int(_reinforcement_enemies.get(zone_id, 0)),
	}


func _connect_event_bus_signals() -> void:
	if not EventBus:
		return
	if EventBus.has_signal("enemy_state_changed") and not EventBus.enemy_state_changed.is_connected(_on_enemy_state_changed):
		EventBus.enemy_state_changed.connect(_on_enemy_state_changed)
	if EventBus.has_signal("enemy_player_spotted") and not EventBus.enemy_player_spotted.is_connected(_on_enemy_player_spotted):
		EventBus.enemy_player_spotted.connect(_on_enemy_player_spotted)
	_event_bus_connected = true


func _on_enemy_state_changed(enemy_id: int, _from_state: String, to_state: String, room_id: int, _reason: String) -> void:
	if enemy_id > 0 and room_id >= 0:
		_enemy_room_by_id[enemy_id] = room_id
	var zone_id := get_zone_for_room(room_id)
	if zone_id < 0:
		return

	if to_state == AWARENESS_ALERT:
		_record_zone_event(zone_id, ZONE_EVENT_ROOM_ALERT)
		if get_zone_state(zone_id) == ZoneState.CALM:
			_transition_zone(zone_id, ZoneState.ELEVATED, ZONE_EVENT_ROOM_ALERT)
		return

	if to_state == AWARENESS_COMBAT:
		_record_zone_event(zone_id, ZONE_EVENT_ROOM_COMBAT)
		_transition_zone(zone_id, ZoneState.LOCKDOWN, ZONE_EVENT_ROOM_COMBAT)


func _on_enemy_player_spotted(enemy_id: int, _position: Vector3) -> void:
	if enemy_id <= 0:
		return
	var room_id := int(_enemy_room_by_id.get(enemy_id, -1))
	if room_id < 0:
		room_id = _resolve_enemy_room_id(enemy_id)
		if room_id >= 0:
			_enemy_room_by_id[enemy_id] = room_id
	var zone_id := get_zone_for_room(room_id)
	if zone_id < 0:
		return
	_record_confirmed_contact_for_zone(zone_id)


func _record_confirmed_contact_for_zone(zone_id: int) -> void:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return
	_record_zone_event(zone_id, ZONE_EVENT_CONFIRMED_CONTACT_INCREMENT)
	var now := _now_sec()
	var contact_times := (_zone_confirmed_contact_times.get(zone_id, []) as Array).duplicate()
	contact_times.append(now)
	_zone_confirmed_contact_times[zone_id] = contact_times
	_prune_confirmed_contact_window_for_zone(zone_id, now)
	if get_zone_state(zone_id) == ZoneState.ELEVATED and (_zone_confirmed_contact_times.get(zone_id, []) as Array).size() >= _confirmed_contact_threshold():
		_transition_zone(zone_id, ZoneState.LOCKDOWN, "confirmed_contacts_threshold")


func _process_zone_decay() -> void:
	var now := _now_sec()
	for zone_variant in _zone_states.keys():
		var zone_id := int(zone_variant)
		var state := get_zone_state(zone_id)
		var state_entered := float(_zone_state_entered_sec.get(zone_id, now))
		var last_event := float(_zone_last_event_sec.get(zone_id, now))
		var time_in_state := now - state_entered
		var no_events_elapsed := now - last_event

		if state == ZoneState.LOCKDOWN:
			if time_in_state >= _lockdown_min_hold_sec() and no_events_elapsed >= _lockdown_to_elevated_no_events_sec():
				_transition_zone(zone_id, ZoneState.ELEVATED, "lockdown_no_event_decay")
		elif state == ZoneState.ELEVATED:
			if time_in_state >= _elevated_min_hold_sec() and no_events_elapsed >= _elevated_to_calm_no_events_sec():
				_transition_zone(zone_id, ZoneState.CALM, "elevated_no_event_decay")


func _transition_zone(zone_id: int, new_state: int, _reason: String) -> bool:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return false
	var old_state := get_zone_state(zone_id)
	if old_state == new_state:
		return false

	var now := _now_sec()
	var last_transition := float(_zone_last_transition_sec.get(zone_id, -999999.0))
	if now - last_transition < MIN_TRANSITION_INTERVAL_SEC:
		return false

	_zone_states[zone_id] = new_state
	_zone_state_entered_sec[zone_id] = now
	_zone_last_transition_sec[zone_id] = now
	var history := (_zone_transition_history.get(zone_id, []) as Array).duplicate()
	history.append(now)
	_zone_transition_history[zone_id] = history
	_sync_reinforcement_budget_caps_for_state_change(zone_id, old_state, new_state)
	_emit_zone_state_changed(zone_id, old_state, new_state)
	return true


func _emit_zone_state_changed(zone_id: int, old_state: int, new_state: int) -> void:
	if not EventBus:
		return
	if EventBus.has_method("emit_zone_state_changed"):
		EventBus.emit_zone_state_changed(zone_id, old_state, new_state)
	elif EventBus.has_signal("zone_state_changed"):
		EventBus.zone_state_changed.emit(zone_id, old_state, new_state)


func _record_zone_event(zone_id: int, event_name: String) -> void:
	if zone_id < 0 or not _zone_states.has(zone_id):
		return
	match event_name:
		ZONE_EVENT_ROOM_ALERT, ZONE_EVENT_ROOM_COMBAT, ZONE_EVENT_ACCEPTED_TEAMMATE_CALL, ZONE_EVENT_CONFIRMED_CONTACT_INCREMENT, ZONE_EVENT_ACCEPTED_REINFORCEMENT_CALL, ZONE_EVENT_WAVE_SPAWN_SUCCESS:
			_zone_last_event_sec[zone_id] = _now_sec()
		_:
			return


func _ensure_zone_entry(zone_id: int) -> void:
	if not _zone_states.has(zone_id):
		_zone_states[zone_id] = ZoneState.CALM
	if not _zone_rooms.has(zone_id):
		_zone_rooms[zone_id] = []
	if not _zone_graph.has(zone_id):
		_zone_graph[zone_id] = []
	if not _zone_state_entered_sec.has(zone_id):
		_zone_state_entered_sec[zone_id] = _now_sec()
	if not _zone_last_event_sec.has(zone_id):
		_zone_last_event_sec[zone_id] = _now_sec()
	if not _zone_last_transition_sec.has(zone_id):
		_zone_last_transition_sec[zone_id] = -999999.0
	if not _zone_transition_history.has(zone_id):
		_zone_transition_history[zone_id] = []
	if not _zone_confirmed_contact_times.has(zone_id):
		_zone_confirmed_contact_times[zone_id] = []
	if not _reinforcement_waves.has(zone_id):
		_reinforcement_waves[zone_id] = 0
	if not _reinforcement_enemies.has(zone_id):
		_reinforcement_enemies[zone_id] = 0
	if not _zone_last_call_sec.has(zone_id):
		_zone_last_call_sec[zone_id] = -999999.0
	if not _zone_source_call_times.has(zone_id):
		_zone_source_call_times[zone_id] = {}
	if not _zone_call_dedup_until_sec.has(zone_id):
		_zone_call_dedup_until_sec[zone_id] = {}
	_ensure_reinforcement_budget_entry(zone_id)


func _ensure_reinforcement_budget_entry(zone_id: int) -> void:
	var caps := _get_reinforcement_caps(zone_id)
	if not _zone_wave_budget_credit.has(zone_id):
		_zone_wave_budget_credit[zone_id] = float(caps.max_waves)
	if not _zone_enemy_budget_credit.has(zone_id):
		_zone_enemy_budget_credit[zone_id] = float(caps.max_enemies)
	_zone_wave_budget_credit[zone_id] = clampf(float(_zone_wave_budget_credit.get(zone_id, 0.0)), 0.0, float(caps.max_waves))
	_zone_enemy_budget_credit[zone_id] = clampf(float(_zone_enemy_budget_credit.get(zone_id, 0.0)), 0.0, float(caps.max_enemies))


func _sync_reinforcement_budget_caps_for_state_change(zone_id: int, old_state: int, new_state: int) -> void:
	var caps := _get_reinforcement_caps(zone_id)
	var wave_credit := float(_zone_wave_budget_credit.get(zone_id, 0.0))
	var enemy_credit := float(_zone_enemy_budget_credit.get(zone_id, 0.0))
	if new_state > old_state:
		wave_credit = maxf(wave_credit, float(caps.max_waves))
		enemy_credit = maxf(enemy_credit, float(caps.max_enemies))
	_zone_wave_budget_credit[zone_id] = clampf(wave_credit, 0.0, float(caps.max_waves))
	_zone_enemy_budget_credit[zone_id] = clampf(enemy_credit, 0.0, float(caps.max_enemies))


func _refill_reinforcement_budgets(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	if dt <= 0.0:
		return
	for zone_variant in _zone_states.keys():
		var zone_id := int(zone_variant)
		_ensure_reinforcement_budget_entry(zone_id)
		var caps := _get_reinforcement_caps(zone_id)
		var profile := _profile_for_state(get_zone_state(zone_id))
		var refill_scale := maxf(float(profile.get("zone_refill_scale", 0.0)), 0.0)
		if refill_scale <= 0.0:
			continue
		var wave_credit := float(_zone_wave_budget_credit.get(zone_id, 0.0)) + refill_scale * dt
		var enemy_credit := float(_zone_enemy_budget_credit.get(zone_id, 0.0)) + refill_scale * dt
		_zone_wave_budget_credit[zone_id] = minf(float(caps.max_waves), wave_credit)
		_zone_enemy_budget_credit[zone_id] = minf(float(caps.max_enemies), enemy_credit)


func _resolve_enemy_room_id(enemy_id: int) -> int:
	if get_tree() == null:
		return -1
	for enemy_variant in get_tree().get_nodes_in_group("enemies"):
		var enemy := enemy_variant as Node
		if enemy == null:
			continue
		var candidate_id := int(enemy.get("entity_id")) if "entity_id" in enemy else int(enemy.get_meta("entity_id", -1))
		if candidate_id != enemy_id:
			continue
		if enemy.has_method("_resolve_room_id_for_events"):
			var resolved := int(enemy.call("_resolve_room_id_for_events"))
			if resolved >= 0:
				return resolved
		return int(enemy.get_meta("room_id", -1))
	return -1


func _prune_confirmed_contact_windows() -> void:
	var now := _now_sec()
	for zone_variant in _zone_confirmed_contact_times.keys():
		_prune_confirmed_contact_window_for_zone(int(zone_variant), now)


func _prune_confirmed_contact_window_for_zone(zone_id: int, now_sec: float) -> void:
	var window_sec := _confirmed_contact_window_sec()
	var times := (_zone_confirmed_contact_times.get(zone_id, []) as Array).duplicate()
	var pruned: Array = []
	for time_variant in times:
		var ts := float(time_variant)
		if now_sec - ts <= window_sec:
			pruned.append(ts)
	_zone_confirmed_contact_times[zone_id] = pruned


func _prune_reinforcement_call_windows_and_dedup() -> void:
	var now := _now_sec()
	for zone_variant in _zone_states.keys():
		_prune_reinforcement_call_data_for_zone(int(zone_variant), now)


func _prune_reinforcement_call_data_for_zone(zone_id: int, now_sec: float) -> void:
	var call_window_sec := _call_window_sec()
	var per_zone_calls := (_zone_source_call_times.get(zone_id, {}) as Dictionary).duplicate(true)
	var cleaned_per_zone: Dictionary = {}
	for source_variant in per_zone_calls.keys():
		var source_enemy_id := int(source_variant)
		var timestamps := (per_zone_calls.get(source_variant, []) as Array).duplicate()
		var pruned_timestamps: Array = []
		for ts_variant in timestamps:
			var ts := float(ts_variant)
			if now_sec - ts <= call_window_sec:
				pruned_timestamps.append(ts)
		if not pruned_timestamps.is_empty():
			cleaned_per_zone[source_enemy_id] = pruned_timestamps
	_zone_source_call_times[zone_id] = cleaned_per_zone

	var dedup := (_zone_call_dedup_until_sec.get(zone_id, {}) as Dictionary).duplicate(true)
	var remove_keys: Array = []
	for call_key_variant in dedup.keys():
		var key := str(call_key_variant)
		if float(dedup.get(call_key_variant, 0.0)) <= now_sec:
			remove_keys.append(key)
	for key_variant in remove_keys:
		dedup.erase(key_variant)
	_zone_call_dedup_until_sec[zone_id] = dedup


func _rejected_call(zone_id: int, reason: String) -> Dictionary:
	return {
		"accepted": false,
		"reason": reason,
		"zone_id": zone_id,
	}


func _now_sec(override_sec: float = -1.0) -> float:
	if override_sec >= 0.0:
		return override_sec
	if _debug_time_override_sec >= 0.0:
		return _debug_time_override_sec
	return _sim_time_sec


func _zone_system_config() -> Dictionary:
	if GameConfig and GameConfig.zone_system is Dictionary:
		return GameConfig.zone_system as Dictionary
	return {}


func _profile_for_state(state: int) -> Dictionary:
	var defaults := _default_profile_for_state(state)
	var zone_system := _zone_system_config()
	var configured_profiles: Dictionary = {}
	var profiles_variant: Variant = zone_system.get("zone_profiles", {})
	if profiles_variant is Dictionary:
		configured_profiles = profiles_variant as Dictionary
	var state_key := _state_name(state)
	if configured_profiles.has(state_key) and configured_profiles.get(state_key) is Dictionary:
		var configured_profile := (configured_profiles.get(state_key) as Dictionary).duplicate(true)
		return _merge_profile(defaults, configured_profile)
	return defaults


func _default_profile_for_state(state: int) -> Dictionary:
	match state:
		ZoneState.CALM:
			return DEFAULT_CALM_PROFILE.duplicate(true)
		ZoneState.ELEVATED:
			return DEFAULT_ELEVATED_PROFILE.duplicate(true)
		ZoneState.LOCKDOWN:
			return DEFAULT_LOCKDOWN_PROFILE.duplicate(true)
		_:
			return DEFAULT_CALM_PROFILE.duplicate(true)


func _merge_profile(base: Dictionary, override: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	out["alert_sweep_budget_scale"] = float(override.get("alert_sweep_budget_scale", out.get("alert_sweep_budget_scale", 1.0)))
	out["reinforcement_cooldown_scale"] = float(override.get("reinforcement_cooldown_scale", out.get("reinforcement_cooldown_scale", 1.0)))
	out["flashlight_active_cap"] = int(override.get("flashlight_active_cap", out.get("flashlight_active_cap", 1)))
	out["zone_refill_scale"] = float(override.get("zone_refill_scale", out.get("zone_refill_scale", 0.0)))
	var role_weights := (out.get("role_weights_profiled", {}) as Dictionary).duplicate(true)
	var override_weights: Dictionary = {}
	var override_weights_variant: Variant = override.get("role_weights_profiled", {})
	if override_weights_variant is Dictionary:
		override_weights = override_weights_variant as Dictionary
	role_weights["PRESSURE"] = float(override_weights.get("PRESSURE", role_weights.get("PRESSURE", 0.0)))
	role_weights["HOLD"] = float(override_weights.get("HOLD", role_weights.get("HOLD", 0.0)))
	role_weights["FLANK"] = float(override_weights.get("FLANK", role_weights.get("FLANK", 0.0)))
	out["role_weights_profiled"] = role_weights
	return out


func _state_name(state: int) -> String:
	match state:
		ZoneState.CALM:
			return "CALM"
		ZoneState.ELEVATED:
			return "ELEVATED"
		ZoneState.LOCKDOWN:
			return "LOCKDOWN"
		_:
			return "CALM"


func _elevated_min_hold_sec() -> float:
	return maxf(float(_zone_system_config().get("elevated_min_hold_sec", DEFAULT_ELEVATED_MIN_HOLD_SEC)), 0.0)


func _lockdown_min_hold_sec() -> float:
	return maxf(float(_zone_system_config().get("lockdown_min_hold_sec", DEFAULT_LOCKDOWN_MIN_HOLD_SEC)), 0.0)


func _elevated_to_calm_no_events_sec() -> float:
	return maxf(float(_zone_system_config().get("elevated_to_calm_no_events_sec", DEFAULT_ELEVATED_TO_CALM_NO_EVENTS_SEC)), 0.0)


func _lockdown_to_elevated_no_events_sec() -> float:
	return maxf(float(_zone_system_config().get("lockdown_to_elevated_no_events_sec", DEFAULT_LOCKDOWN_TO_ELEVATED_NO_EVENTS_SEC)), 0.0)


func _confirmed_contact_threshold() -> int:
	return maxi(int(_zone_system_config().get("confirmed_contacts_lockdown_threshold", DEFAULT_CONFIRMED_CONTACT_THRESHOLD)), 1)


func _confirmed_contact_window_sec() -> float:
	return maxf(float(_zone_system_config().get("confirmed_contacts_window_sec", DEFAULT_CONFIRMED_CONTACT_WINDOW_SEC)), 0.0)


func _calls_per_enemy_per_window() -> int:
	return maxi(int(_zone_system_config().get("calls_per_enemy_per_window", DEFAULT_CALLS_PER_ENEMY_PER_WINDOW)), 1)


func _call_window_sec() -> float:
	return maxf(float(_zone_system_config().get("call_window_sec", DEFAULT_CALL_WINDOW_SEC)), 0.001)


func _global_call_cooldown_sec() -> float:
	return maxf(float(_zone_system_config().get("global_call_cooldown_sec", DEFAULT_GLOBAL_CALL_COOLDOWN_SEC)), 0.0)


func _call_dedup_ttl_sec() -> float:
	return maxf(float(_zone_system_config().get("call_dedup_ttl_sec", DEFAULT_CALL_DEDUP_TTL_SEC)), 0.0)


func _get_reinforcement_caps(zone_id: int = -1) -> Dictionary:
	var max_waves := 1
	var max_enemies := 2
	var zone_system := _zone_system_config()
	if not zone_system.is_empty():
		max_waves = maxi(int(zone_system.get("max_reinforcement_waves_per_zone", max_waves)), 0)
		max_enemies = maxi(int(zone_system.get("max_reinforcement_enemies_per_zone", max_enemies)), 0)
		if get_zone_state(zone_id) == ZoneState.LOCKDOWN:
			max_waves = maxi(int(zone_system.get("lockdown_max_reinforcement_waves_per_zone", max_waves)), max_waves)
			max_enemies = maxi(int(zone_system.get("lockdown_max_reinforcement_enemies_per_zone", max_enemies)), max_enemies)
	return {
		"max_waves": max_waves,
		"max_enemies": max_enemies,
	}
