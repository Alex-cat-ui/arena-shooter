## zone_reinforcement_runtime.gd
## Reinforcement budget/call window runtime helpers for ZoneDirector.
class_name ZoneReinforcementRuntime
extends RefCounted

var _director: Node = null


func _init(director: Node) -> void:
	_director = director


func can_spawn_reinforcement(zone_id: int) -> bool:
	if zone_id < 0 or not _director._zone_states.has(zone_id):
		return false
	ensure_reinforcement_budget_entry(zone_id)
	var caps: Dictionary = _director._get_reinforcement_caps(zone_id)
	var max_waves := int(caps.get("max_waves", 0))
	var max_enemies := int(caps.get("max_enemies", 0))
	var wave_credit: float = float(_director._zone_wave_budget_credit.get(zone_id, 0.0))
	var enemy_credit: float = float(_director._zone_enemy_budget_credit.get(zone_id, 0.0))
	return max_waves > 0 and max_enemies > 0 and wave_credit >= 1.0 and enemy_credit >= 1.0


func register_reinforcement_wave(zone_id: int, count: int) -> void:
	if zone_id < 0 or not _director._zone_states.has(zone_id):
		return
	ensure_reinforcement_budget_entry(zone_id)
	var used_enemy_credit: float = maxf(float(maxi(count, 0)), 0.0)
	_director._zone_wave_budget_credit[zone_id] = maxf(float(_director._zone_wave_budget_credit.get(zone_id, 0.0)) - 1.0, 0.0)
	_director._zone_enemy_budget_credit[zone_id] = maxf(float(_director._zone_enemy_budget_credit.get(zone_id, 0.0)) - used_enemy_credit, 0.0)
	_director._reinforcement_waves[zone_id] = int(_director._reinforcement_waves.get(zone_id, 0)) + 1
	_director._reinforcement_enemies[zone_id] = int(_director._reinforcement_enemies.get(zone_id, 0)) + maxi(count, 0)
	_director._record_zone_event(zone_id, _director.ZONE_EVENT_WAVE_SPAWN_SUCCESS)


func validate_reinforcement_call(
	source_enemy_id: int,
	source_room_id: int,
	source_awareness_state: String,
	call_id: int,
	now_sec: float = -1.0
) -> Dictionary:
	var zone_id: int = int(_director.get_zone_for_room(source_room_id))
	if zone_id < 0:
		return rejected_call(zone_id, "invalid_zone")
	if call_id <= 0:
		return rejected_call(zone_id, "invalid_call_id")
	if source_enemy_id <= 0:
		return rejected_call(zone_id, "invalid_source_enemy_id")

	var now: float = float(_director._now_sec(now_sec))
	prune_reinforcement_call_data_for_zone(zone_id, now)

	var dedup := (_director._zone_call_dedup_until_sec.get(zone_id, {}) as Dictionary).duplicate(true)
	var call_key := str(call_id)
	if dedup.has(call_key) and float(dedup.get(call_key, 0.0)) > now:
		return rejected_call(zone_id, "dedup_ttl")

	var zone_state: int = int(_director.get_zone_state(zone_id))
	if zone_state == int(_director.ZoneState.CALM):
		return rejected_call(zone_id, "permission_calm")
	if zone_state == int(_director.ZoneState.ELEVATED) and source_awareness_state != _director.AWARENESS_ALERT:
		return rejected_call(zone_id, "permission_elevated_requires_alert")
	if zone_state == int(_director.ZoneState.LOCKDOWN) and source_awareness_state != _director.AWARENESS_ALERT and source_awareness_state != _director.AWARENESS_COMBAT:
		return rejected_call(zone_id, "permission_lockdown_requires_alert_or_combat")

	var profile: Dictionary = _director._profile_for_state(zone_state)
	var cooldown_scale: float = maxf(float(profile.get("reinforcement_cooldown_scale", 1.0)), 0.0)
	var global_cooldown: float = float(_director._global_call_cooldown_sec()) * cooldown_scale
	var last_zone_call: float = float(_director._zone_last_call_sec.get(zone_id, -999999.0))
	if now - last_zone_call < global_cooldown:
		return rejected_call(zone_id, "global_cooldown")

	var per_zone_calls := (_director._zone_source_call_times.get(zone_id, {}) as Dictionary).duplicate(true)
	var source_times := (per_zone_calls.get(source_enemy_id, []) as Array).duplicate()
	var call_window_sec: float = float(_director._call_window_sec())
	var pruned_source_times: Array = []
	for time_variant in source_times:
		var ts := float(time_variant)
		if now - ts <= call_window_sec:
			pruned_source_times.append(ts)
	if pruned_source_times.size() >= int(_director._calls_per_enemy_per_window()):
		return rejected_call(zone_id, "source_window_limit")

	if not can_spawn_reinforcement(zone_id):
		return rejected_call(zone_id, "budget_exhausted")

	pruned_source_times.append(now)
	per_zone_calls[source_enemy_id] = pruned_source_times
	_director._zone_source_call_times[zone_id] = per_zone_calls
	_director._zone_last_call_sec[zone_id] = now
	dedup[call_key] = now + float(_director._call_dedup_ttl_sec())
	_director._zone_call_dedup_until_sec[zone_id] = dedup
	_director._record_zone_event(zone_id, _director.ZONE_EVENT_ACCEPTED_REINFORCEMENT_CALL)

	return {
		"accepted": true,
		"reason": "ok",
		"zone_id": zone_id,
	}


func ensure_reinforcement_budget_entry(zone_id: int) -> void:
	var caps: Dictionary = _director._get_reinforcement_caps(zone_id)
	var max_waves := int(caps.get("max_waves", 0))
	var max_enemies := int(caps.get("max_enemies", 0))
	if not _director._zone_wave_budget_credit.has(zone_id):
		_director._zone_wave_budget_credit[zone_id] = float(max_waves)
	if not _director._zone_enemy_budget_credit.has(zone_id):
		_director._zone_enemy_budget_credit[zone_id] = float(max_enemies)
	_director._zone_wave_budget_credit[zone_id] = clampf(float(_director._zone_wave_budget_credit.get(zone_id, 0.0)), 0.0, float(max_waves))
	_director._zone_enemy_budget_credit[zone_id] = clampf(float(_director._zone_enemy_budget_credit.get(zone_id, 0.0)), 0.0, float(max_enemies))


func sync_reinforcement_budget_caps_for_state_change(zone_id: int, old_state: int, new_state: int) -> void:
	var caps: Dictionary = _director._get_reinforcement_caps(zone_id)
	var max_waves := int(caps.get("max_waves", 0))
	var max_enemies := int(caps.get("max_enemies", 0))
	var wave_credit: float = float(_director._zone_wave_budget_credit.get(zone_id, 0.0))
	var enemy_credit: float = float(_director._zone_enemy_budget_credit.get(zone_id, 0.0))
	if new_state > old_state:
		wave_credit = maxf(wave_credit, float(max_waves))
		enemy_credit = maxf(enemy_credit, float(max_enemies))
	_director._zone_wave_budget_credit[zone_id] = clampf(wave_credit, 0.0, float(max_waves))
	_director._zone_enemy_budget_credit[zone_id] = clampf(enemy_credit, 0.0, float(max_enemies))


func refill_reinforcement_budgets(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	if dt <= 0.0:
		return
	for zone_variant in _director._zone_states.keys():
		var zone_id := int(zone_variant)
		ensure_reinforcement_budget_entry(zone_id)
		var caps: Dictionary = _director._get_reinforcement_caps(zone_id)
		var max_waves := int(caps.get("max_waves", 0))
		var max_enemies := int(caps.get("max_enemies", 0))
		var profile: Dictionary = _director._profile_for_state(_director.get_zone_state(zone_id))
		var refill_scale := maxf(float(profile.get("zone_refill_scale", 0.0)), 0.0)
		if refill_scale <= 0.0:
			continue
		var wave_credit: float = float(_director._zone_wave_budget_credit.get(zone_id, 0.0)) + refill_scale * dt
		var enemy_credit: float = float(_director._zone_enemy_budget_credit.get(zone_id, 0.0)) + refill_scale * dt
		_director._zone_wave_budget_credit[zone_id] = minf(float(max_waves), wave_credit)
		_director._zone_enemy_budget_credit[zone_id] = minf(float(max_enemies), enemy_credit)


func prune_confirmed_contact_windows() -> void:
	var now: float = float(_director._now_sec())
	for zone_variant in _director._zone_confirmed_contact_times.keys():
		prune_confirmed_contact_window_for_zone(int(zone_variant), now)


func prune_confirmed_contact_window_for_zone(zone_id: int, now_sec: float) -> void:
	var window_sec: float = float(_director._confirmed_contact_window_sec())
	var times := (_director._zone_confirmed_contact_times.get(zone_id, []) as Array).duplicate()
	var pruned: Array = []
	for time_variant in times:
		var ts := float(time_variant)
		if now_sec - ts <= window_sec:
			pruned.append(ts)
	_director._zone_confirmed_contact_times[zone_id] = pruned


func prune_reinforcement_call_windows_and_dedup() -> void:
	var now: float = float(_director._now_sec())
	for zone_variant in _director._zone_states.keys():
		prune_reinforcement_call_data_for_zone(int(zone_variant), now)


func prune_reinforcement_call_data_for_zone(zone_id: int, now_sec: float) -> void:
	var call_window_sec: float = float(_director._call_window_sec())
	var per_zone_calls := (_director._zone_source_call_times.get(zone_id, {}) as Dictionary).duplicate(true)
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
	_director._zone_source_call_times[zone_id] = cleaned_per_zone

	var dedup := (_director._zone_call_dedup_until_sec.get(zone_id, {}) as Dictionary).duplicate(true)
	var remove_keys: Array = []
	for call_key_variant in dedup.keys():
		var key := str(call_key_variant)
		if float(dedup.get(call_key_variant, 0.0)) <= now_sec:
			remove_keys.append(key)
	for key_variant in remove_keys:
		dedup.erase(key_variant)
	_director._zone_call_dedup_until_sec[zone_id] = dedup


func rejected_call(zone_id: int, reason: String) -> Dictionary:
	return {
		"accepted": false,
		"reason": reason,
		"zone_id": zone_id,
	}
